import 'package:flutter/material.dart';
import '../discovery/discovery_models.dart';
import '../matches/student_match.dart';
import 'chat_message.dart';
import 'chat_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.matchId,
    required this.uid,
    this.profile,
    this.service,
  });
  final String matchId, uid;
  // Ficha pública que Mis Matches ya obtuvo; nunca consultar users ajenos.
  final DiscoveryCandidate? profile;
  final ChatService? service;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _service = widget.service ?? ChatService();
  late Stream<StudentMatch> _match;
  late Stream<List<ChatMessage>> _messages;
  final _draft = TextEditingController();
  bool _sending = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _match = _service.watchMatch(widget.matchId, widget.uid);
    _messages = _service.watchMessages(widget.matchId);
  }

  void _retry() => setState(_listen);

  Future<void> _send() async {
    if (_sending) return;
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
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 36,
                height: 36,
                child: profile == null || profile.mainPhotoUrl.isEmpty
                    ? const Icon(Icons.person_outline)
                    : Image.network(
                        profile.mainPhotoUrl,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (context, error, stack) =>
                            const Icon(Icons.person_outline),
                      ),
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
                              child: Text('Aún no hay mensajes. ¡Saluda!'),
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
                              return MessageBubble(
                                key: ValueKey(message.id),
                                message: message,
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
                        child: Text(
                          'Este match está inactivo. Puedes consultar el historial.',
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
                          Expanded(
                            child: TextField(
                              key: const ValueKey('chat-draft'),
                              controller: _draft,
                              enabled: active && !_sending,
                              minLines: 1,
                              maxLines: 4,
                              textCapitalization: TextCapitalization.sentences,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Mensaje',
                                border: const OutlineInputBorder(),
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
                              tooltip: _sending ? 'Enviando' : 'Enviar',
                              onPressed: active && !_sending ? _send : null,
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
  const MessageBubble({super.key, required this.message, required this.own});
  final ChatMessage message;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = message.createdAt?.toLocal();
    final label = date == null
        ? 'Enviando…'
        : '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: .85,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: own
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.text),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
