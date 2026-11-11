import '../../widgets/motion_entrance.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_media_widget.dart';
import 'chat_media_validation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/pick_ligo_photo.dart';

import 'package:flutter/material.dart';
import 'dart:async';

import '../discovery/discovery_models.dart';
import '../matches/student_match.dart';
import '../matches/unmatch_service.dart';
import 'chat_message.dart';
import 'chat_service.dart';
import '../safety/safety_dialog.dart';
import '../safety/safety_service.dart';
import '../matches/match_profile_screen.dart';
import 'voice_note_recorder.dart';
import 'voice_note_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.matchId,
    required this.uid,
    this.profile,
    this.service,
    this.unmatchService,
    this.safetyService,
    this.voiceCapture,
  });
  final String matchId, uid;
  // Ficha pública que Mis Matches ya obtuvo; nunca consultar users ajenos.
  final DiscoveryCandidate? profile;
  final ChatService? service;
  final UnmatchService? unmatchService;
  final SafetyService? safetyService;
  final VoiceCapture? voiceCapture;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _reading = <String>{};
  late final _service = widget.service ?? ChatService();
  late Stream<StudentMatch> _match;
  late Stream<List<ChatMessage>> _messages;
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  String? _lastMessage, _enteringMessage;
  bool _newMessages = false;
  void _bottom() {
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _arrival(List<ChatMessage> messages) {
    if (messages.isEmpty || messages.last.id == _lastMessage) return;
    final first = _lastMessage == null;
    _lastMessage = messages.last.id;
    final follow =
        first ||
        !_scroll.hasClients ||
        _scroll.offset < 100 ||
        messages.last.isOwn(widget.uid);
    _enteringMessage = !first && follow ? _lastMessage : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (follow) {
        _bottom();
      } else {
        setState(() => _newMessages = true);
      }
    });
  }

  bool _sending = false;
  bool _voiceBusy = false;
  bool _allowVoiceExit = false, _exitDialogOpen = false;
  bool _closing = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
    _service.recoverPendingMedia(widget.uid).catchError((_) {});
  }

  void _listen() {
    _match = _service.watchMatch(widget.matchId, widget.uid);
    _messages = _service.watchMessages(widget.matchId);
  }

  void _readVisible(ChatMessage message, BuildContext rowContext) {
    if (message.isOwn(widget.uid) ||
        message.readAt != null ||
        message.createdAt == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive ||
        ModalRoute.of(context)?.isCurrent != true ||
        !_reading.add(message.id)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        _reading.remove(message.id);
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final box = rowContext.mounted ? rowContext.findRenderObject() : null;
      final scrollable = rowContext.mounted
          ? Scrollable.maybeOf(rowContext)
          : null;
      final viewport = scrollable?.context.findRenderObject();
      if ((lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
          box is! RenderBox ||
          viewport is! RenderBox ||
          !box.attached ||
          !viewport.attached ||
          !box.hasSize ||
          !viewport.hasSize ||
          !(box.localToGlobal(Offset.zero) & box.size).overlaps(
            viewport.localToGlobal(Offset.zero) & viewport.size,
          )) {
        _reading.remove(message.id);
        return;
      }
      try {
        await _service.markRead(widget.matchId, widget.uid, message);
      } catch (_) {
        _reading.remove(message.id);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  Future<void> _attach(bool audio) async {
    if (_sending || _closing || _voiceBusy) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      if (audio) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg'],
          withData: false,
          withReadStream: true,
        );
        if (!mounted || result == null) return;
        final file = result.files.single;
        final mime = {
          'mp3': 'audio/mpeg',
          'm4a': 'audio/mp4',
          'wav': 'audio/wav',
          'ogg': 'audio/ogg',
        }[file.extension?.toLowerCase()];
        if (mime == null || file.readStream == null) {
          throw const ChatException('Formato de audio no compatible.');
        }
        if (file.size <= 0 || file.size > ChatMediaValidation.audioLimit) {
          throw const ChatException('Audio: máximo 15 MB.');
        }
        final bytes = await ChatMediaValidation.readBounded(
          file.readStream!,
          ChatMediaValidation.audioLimit,
        );
        if (!mounted) return;
        await _service.sendMedia(
          widget.matchId,
          widget.uid,
          bytes,
          'audio',
          mime,
        );
      } else {
        final file = await pickLigoPhoto(context, ImagePicker());
        if (!mounted || file == null) return;
        if (await file.length() > ChatMediaValidation.imageLimit) {
          throw const ChatException('Imagen: máximo 5 MB.');
        }
        final bytes = await file.readAsBytes();
        final mime = bytes.length >= 3 && bytes[0] == 255 && bytes[1] == 216
            ? 'image/jpeg'
            : bytes.length >= 8 && bytes[0] == 137 && bytes[1] == 80
            ? 'image/png'
            : bytes.length >= 12 &&
                  String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
                  String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP'
            ? 'image/webp'
            : null;
        if (mime == null) {
          throw const ChatException('Selecciona una imagen JPG, PNG o WebP.');
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Enviar fotografía'),
            content: SizedBox(
              width: 420,
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Enviar fotografía'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await _service.sendMedia(
          widget.matchId,
          widget.uid,
          bytes,
          'image',
          mime,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _sendError = chatError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _retry() => setState(_listen);

  Future<void> _safety(String target, SafetyAction action) async {
    if (_closing || _sending) return;
    setState(() => _closing = true);
    try {
      final done = await showSafetyDialog(
        context,
        target: target,
        action: action,
        service: widget.safetyService,
      );
      if (!mounted || !done) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == SafetyAction.block
                ? 'Usuario bloqueado. El historial se conserva.'
                : 'Reporte enviado.',
          ),
        ),
      );
      if (action == SafetyAction.block && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _confirmUnmatch() async {
    if (_closing || _sending) return;
    setState(() => _closing = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.heart_broken_outlined,
            color: AppColors.danger,
          ),
          title: const Text('¿Deshacer match?'),
          content: const Text(
            'Ya no podrán enviarse mensajes nuevos. El historial se conservará.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('confirm-unmatch'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Deshacer match'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await (widget.unmatchService ?? UnmatchService()).unmatch(widget.matchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Match finalizado. El historial se conserva.'),
        ),
      );
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(unmatchError(error))));
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _closing) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await _service.send(widget.matchId, widget.uid, _draft.text);
      if (mounted) _draft.clear();
    } catch (error) {
      if (mounted) setState(() => _sendError = chatError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmVoiceExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir del chat?'),
        content: const Text(
          'Si tienes una nota de voz sin enviar, se descartará al salir. Los envíos que ya comenzaron pueden completarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir en el chat'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir del chat'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _exitDialogOpen = false;
      if (leave == true) _allowVoiceExit = true;
    });
    if (leave == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return PopScope(
      canPop: !_voiceBusy || _allowVoiceExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _voiceBusy) unawaited(_confirmVoiceExit());
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).scaffoldBackgroundColor
            : const Color(0xFFF4F1F5),
        appBar: AppBar(
          actions: [
            StreamBuilder<StudentMatch>(
              stream: _match,
              builder: (context, snapshot) {
                if (snapshot.hasError || snapshot.data?.isActive != true) {
                  return const SizedBox.shrink();
                }
                return PopupMenuButton<String>(
                  key: const ValueKey('chat-options'),
                  tooltip: 'Opciones del chat',
                  enabled: !_closing && !_sending && !_voiceBusy,
                  onSelected: (value) => value == 'unmatch'
                      ? _confirmUnmatch()
                      : _safety(
                          snapshot.data!.otherUser(widget.uid),
                          value == 'block'
                              ? SafetyAction.block
                              : SafetyAction.report,
                        ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'unmatch',
                      child: Text('Deshacer match'),
                    ),
                    const PopupMenuItem(
                      value: 'block',
                      child: Text('Bloquear usuario'),
                    ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Reportar usuario'),
                    ),
                  ],
                );
              },
            ),
          ],
          leading: BackButton(onPressed: () => Navigator.of(context).pop()),
          title: InkWell(
            onTap: profile == null || _voiceBusy || _sending
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MatchProfileScreen(
                        viewer: widget.uid,
                        target: profile.id,
                      ),
                    ),
                  ),
            child: Tooltip(
              message: 'Ver perfil del match',
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: AppPhoto(url: profile?.mainPhotoUrl),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      profile?.firstName ?? 'Perfil no disponible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: StreamBuilder<StudentMatch>(
                stream: _match,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _error(chatError(snapshot.error!));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final active = snapshot.data!.isActive;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Conversación privada · últimos ${ChatLimits.historyLimit} mensajes',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      if (_newMessages)
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _newMessages = false);
                            _bottom();
                          },
                          icon: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                          ),
                          label: const Text('Ver mensajes nuevos'),
                        ),
                      Expanded(
                        child: StreamBuilder<List<ChatMessage>>(
                          stream: _messages,
                          builder: (context, history) {
                            if (history.hasError) {
                              return _error(chatError(history.error!));
                            }
                            if (!history.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final messages = history.data!;
                            if (messages.isEmpty) {
                              return const Center(
                                child: AppEmptyState(
                                  icon: Icons.waving_hand_outlined,
                                  title: 'Aún no hay mensajes. ¡Saluda!',
                                  message:
                                      'Un hola puede ser el comienzo de una buena conversación.',
                                ),
                              );
                            }
                            _arrival(messages);
                            // reverse ancla la vista al final; arriba sigue lo más antiguo.
                            return NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollEndNotification &&
                                    mounted) {
                                  setState(() {
                                    if (_scroll.hasClients &&
                                        _scroll.offset < 40) {
                                      _newMessages = false;
                                    }
                                  });
                                }
                                return false;
                              },
                              child: ListView.builder(
                                controller: _scroll,
                                reverse: true,
                                padding: const EdgeInsets.all(16),
                                itemCount: messages.length,
                                findChildIndexCallback: (key) {
                                  if (key is! ValueKey<String> ||
                                      !key.value.startsWith('chat-row:')) {
                                    return null;
                                  }
                                  final position = messages.indexWhere(
                                    (m) => m.id == key.value.substring(9),
                                  );
                                  return position < 0
                                      ? null
                                      : messages.length - 1 - position;
                                },
                                itemBuilder: (context, index) {
                                  final message =
                                      messages[messages.length - 1 - index];
                                  return Builder(
                                    key: ValueKey('chat-row:${message.id}'),
                                    builder: (rowContext) {
                                      final older = index + 1 < messages.length
                                          ? messages[messages.length -
                                                    2 -
                                                    index]
                                                .createdAt
                                          : null;
                                      final day = message.createdAt;
                                      final separator =
                                          day != null &&
                                          (older == null ||
                                              !DateUtils.isSameDay(
                                                day.toLocal(),
                                                older.toLocal(),
                                              ));
                                      return Column(
                                        children: [
                                          if (separator)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.surface,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  chatDay(day),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          Builder(
                                            builder: (bubbleContext) {
                                              if (active) {
                                                _readVisible(
                                                  message,
                                                  bubbleContext,
                                                );
                                              }
                                              final bubble = MessageBubble(
                                                key: ValueKey(message.id),
                                                message: message,
                                                service: _service,
                                                own: message.isOwn(widget.uid),
                                                mediaAllowed: active,
                                              );
                                              return MotionEntrance(
                                                enabled:
                                                    _enteringMessage ==
                                                    message.id,
                                                child: bubble,
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      if (!active)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: AppNotice(
                            'Este match ha finalizado. Ya no puedes enviar mensajes. Puedes consultar el historial.',
                          ),
                        ),
                      if (_sendError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            _sendError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      VoiceNoteRecorder(
                        capture: widget.voiceCapture,
                        enabled: active && !_sending && !_closing,
                        onBusy: (busy) {
                          if (!mounted) return;
                          if (busy) {
                            FocusManager.instance.primaryFocus?.unfocus();
                          }
                          setState(() => _voiceBusy = busy);
                        },
                        onSend: (bytes) => _service.sendMedia(
                          widget.matchId,
                          widget.uid,
                          bytes,
                          'audio',
                          'audio/wav',
                          durationMs: ((bytes.length - 44) / 32).round(),
                        ),
                        composer: (microphone) => Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Enviar imagen',
                                icon: const Icon(Icons.image_outlined),
                                onPressed:
                                    active &&
                                        !_sending &&
                                        !_closing &&
                                        !_voiceBusy
                                    ? () => _attach(false)
                                    : null,
                              ),
                              IconButton(
                                tooltip: 'Enviar audio',
                                icon: const Icon(Icons.audio_file_outlined),
                                onPressed:
                                    active &&
                                        !_sending &&
                                        !_closing &&
                                        !_voiceBusy
                                    ? () => _attach(true)
                                    : null,
                              ),
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('chat-draft'),
                                  controller: _draft,
                                  enabled:
                                      active &&
                                      !_sending &&
                                      !_closing &&
                                      !_voiceBusy,
                                  minLines: 1,
                                  maxLines: 4,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    hintText: 'Escribe un mensaje…',
                                    labelText: 'Mensaje',
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _draft.text.trim().isEmpty
                                    ? microphone
                                    : IconButton.filled(
                                        key: const ValueKey('chat-send'),
                                        style: IconButton.styleFrom(
                                          minimumSize: const Size(52, 52),
                                        ),
                                        tooltip: _sending
                                            ? 'Enviando'
                                            : 'Enviar',
                                        onPressed:
                                            active &&
                                                !_sending &&
                                                !_closing &&
                                                !_voiceBusy &&
                                                _draft.text.trim().isNotEmpty
                                            ? _send
                                            : null,
                                        icon: _sending
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.send),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _error(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: _retry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

String chatDay(DateTime date, {DateTime? now}) {
  final local = date.toLocal(), today = (now ?? DateTime.now()).toLocal();
  if (DateUtils.isSameDay(local, today)) return 'Hoy';
  if (DateUtils.isSameDay(local, today.subtract(const Duration(days: 1)))) {
    return 'Ayer';
  }
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.own,
    this.service,
    this.mediaAllowed = true,
  });
  final ChatService? service;
  final ChatMessage message;
  final bool own, mediaAllowed;
  @override
  Widget build(BuildContext context) {
    final date = message.createdAt?.toLocal();
    final label = date == null
        ? 'Enviando…'
        : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width > 800
              ? 460
              : MediaQuery.sizeOf(context).width * .83,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 6),
          decoration: BoxDecoration(
            color: own ? AppColors.wine : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(19),
              topRight: const Radius.circular(19),
              bottomLeft: Radius.circular(own ? 19 : 5),
              bottomRight: Radius.circular(own ? 5 : 19),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                offset: Offset(0, 2),
                blurRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.mediaPath != null && mediaAllowed)
                Container(
                  constraints: const BoxConstraints(minWidth: 230),
                  padding: const EdgeInsets.all(3),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ChatMediaWidget(
                    key: ValueKey(message.mediaPath),
                    path: message.mediaPath!,
                    type: message.type,
                    durationMs: message.durationMs,
                    service: service,
                  ),
                ),
              if (message.mediaPath != null && !mediaAllowed)
                const Text('Archivo no disponible: el match está inactivo.'),
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: own
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: own
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (own) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: message.readAt != null
                          ? const EdgeInsets.all(1)
                          : EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: message.readAt != null
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        message.createdAt == null
                            ? Icons.schedule
                            : Icons.done_all,
                        size: 16,
                        color: message.readAt != null
                            ? Colors.blue.shade900
                            : Colors.white,
                        semanticLabel: message.createdAt == null
                            ? 'Enviando'
                            : message.readAt != null
                            ? 'Visto'
                            : 'Enviado',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
