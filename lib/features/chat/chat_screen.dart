import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_media_widget.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_ui.dart';

import 'package:flutter/material.dart';

import '../discovery/discovery_models.dart';
import '../matches/student_match.dart';
import '../matches/unmatch_service.dart';
import 'chat_message.dart';
import 'chat_service.dart';
import '../safety/safety_dialog.dart';
import '../safety/safety_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.matchId,
    required this.uid,
    this.profile,
    this.service,
    this.unmatchService,
    this.safetyService,
  });
  final String matchId, uid;
  // Ficha pública que Mis Matches ya obtuvo; nunca consultar users ajenos.
  final DiscoveryCandidate? profile;
  final ChatService? service;
  final UnmatchService? unmatchService;
  final SafetyService? safetyService;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _reading = <String>{};
  late final _service = widget.service ?? ChatService();
  late Stream<StudentMatch> _match;
  late Stream<List<ChatMessage>> _messages;
  final _draft = TextEditingController();
  bool _sending = false;
  bool _closing = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  void _listen() {
    _match = _service.watchMatch(widget.matchId, widget.uid);
    _messages = _service.watchMessages(widget.matchId);
  }

  void _readVisible(ChatMessage message) {
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
    if (_sending || _closing) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      if (audio) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg'],
          withData: true,
        );
        if (!mounted || result == null) return;
        final file = result.files.single;
        final mime = {
          'mp3': 'audio/mpeg',
          'm4a': 'audio/mp4',
          'wav': 'audio/wav',
          'ogg': 'audio/ogg',
        }[file.extension?.toLowerCase()];
        if (mime == null || file.bytes == null) {
          throw const ChatException('Formato de audio no compatible.');
        }
        await _service.sendMedia(
          widget.matchId,
          widget.uid,
          file.bytes!,
          'audio',
          mime,
        );
      } else {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 85,
        );
        if (!mounted || file == null) return;
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(unmatchError(error))));
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
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
                enabled: !_closing && !_sending,
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
        title: Row(
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
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        'Últimos ${ChatLimits.historyLimit} mensajes',
                      ),
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
                                message: 'Un hola puede ser el comienzo de una buena conversación.',
                              ),
                            );
                          }
                          // reverse ancla la vista al final; arriba sigue lo más antiguo.
                          return ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message =
                                  messages[messages.length - 1 - index];
                              _readVisible(message);
                              return MessageBubble(
                                key: ValueKey(message.id),
                                message: message,
                                service: _service,
                                own: message.isOwn(widget.uid),
                              );
                            },
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: 'Enviar imagen',
                            icon: const Icon(Icons.image_outlined),
                            onPressed: active && !_sending && !_closing
                                ? () => _attach(false)
                                : null,
                          ),
                          IconButton(
                            tooltip: 'Enviar audio',
                            icon: const Icon(Icons.audio_file_outlined),
                            onPressed: active && !_sending && !_closing
                                ? () => _attach(true)
                                : null,
                          ),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('chat-draft'),
                              controller: _draft,
                              enabled: active && !_sending && !_closing,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Mensaje',
                                prefixIcon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                ),
                                counterText:
                                    '${_draft.text.trim().length}/${ChatLimits.maxTextLength}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: IconButton.filled(
                              key: const ValueKey('chat-send'),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(52, 52),
                              ),
                              tooltip: _sending ? 'Enviando' : 'Enviar',
                              onPressed: active && !_sending && !_closing
                                  ? _send
                                  : null,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
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

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.own,
    this.service,
  });
  final ChatService? service;
  final ChatMessage message;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final date = message.createdAt?.toLocal();
    final label = date == null
        ? 'Enviando…'
        : '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .82,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: own ? AppColors.coral : Colors.white,
            border: own ? null : Border.all(color: const Color(0xFFECE7ED)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(own ? 20 : 6),
              bottomRight: Radius.circular(own ? 6 : 20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.mediaPath != null)
                ChatMediaWidget(
                  path: message.mediaPath!,
                  type: message.type,
                  service: service,
                ),
              if (message.text.isNotEmpty)
                Text(
                  message.text,
                  style: TextStyle(
                    color: own ? Colors.white : AppColors.ink,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 4),
              if (own)
                Icon(
                  message.createdAt == null ? Icons.schedule : Icons.done_all,
                  size: 18,
                  color: message.readAt != null
                      ? Colors.blue.shade900
                      : Colors.white,
                  semanticLabel: message.createdAt == null
                      ? 'Enviando'
                      : message.readAt != null
                      ? 'Visto'
                      : 'Enviado',
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: own ? Colors.white : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
