import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

import 'chat_service.dart';

class ChatMediaWidget extends StatefulWidget {
  const ChatMediaWidget({
    super.key,
    required this.path,
    required this.type,
    this.service,
  });
  final String path, type;
  final ChatService? service;
  @override
  State<ChatMediaWidget> createState() => _ChatMediaWidgetState();
}

class _ChatMediaWidgetState extends State<ChatMediaWidget> {
  late Future<String> _url = (widget.service ?? ChatService()).mediaUrl(
    widget.path,
  );
  AudioPlayer? _player;
  bool _busy = false;
  Future<void> _toggle(String url) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final player = _player ??= AudioPlayer();
      if (player.state == PlayerState.playing) {
        await player.pause();
      } else {
        await player.play(UrlSource(url));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo reproducir el audio.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() {
            _url = (widget.service ?? ChatService()).mediaUrl(widget.path);
          }),
          child: const Text('Reintentar archivo'),
        );
      }
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final url = snapshot.data!;
      if (widget.type == 'image') {
        return InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              child: Stack(
                children: [
                  InteractiveViewer(
                    child: Image.network(
                      url,
                      errorBuilder: (_, error, stack) =>
                          const Text('Imagen no disponible'),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: Image.network(
            url,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) =>
                const Text('Imagen no disponible'),
          ),
        );
      }
      return StreamBuilder<PlayerState>(
        stream: _player?.onPlayerStateChanged,
        builder: (context, state) => TextButton.icon(
          onPressed: _busy ? null : () => _toggle(url),
          icon: Icon(
            state.data == PlayerState.playing ||
                    _player?.state == PlayerState.playing
                ? Icons.pause
                : Icons.play_arrow,
          ),
          label: const Text('Audio'),
        ),
      );
    },
  );
}
