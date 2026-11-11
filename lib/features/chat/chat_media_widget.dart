import 'package:flutter/material.dart';
import 'audio_playback.dart';

import 'chat_service.dart';

class ChatMediaWidget extends StatefulWidget {
  const ChatMediaWidget({
    super.key,
    required this.path,
    required this.type,
    this.service,
    this.durationMs,
  });
  final String path, type;
  final ChatService? service;
  final int? durationMs;
  @override
  State<ChatMediaWidget> createState() => _ChatMediaWidgetState();
}

class _ChatMediaWidgetState extends State<ChatMediaWidget> {
  DialogRoute<void>? _viewer;
  NavigatorState? _viewerNavigator;
  MemoryImage? _imageProvider;

  void _showImage(ChatMediaData data) {
    final navigator = Navigator.of(context);
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.memory(
                data.bytes,
                errorBuilder: (_, _, _) => const Text('Imagen no disponible'),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                tooltip: 'Cerrar imagen',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
    _viewer = route;
    _viewerNavigator = navigator;
    navigator.push(route).whenComplete(() {
      if (_viewer == route) _viewer = null;
    });
  }

  @override
  void dispose() {
    final route = _viewer, navigator = _viewerNavigator;
    // Si se retira el mensaje por revocación, retirar también su visor abierto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route?.isActive == true && navigator?.mounted == true) {
        navigator!.removeRoute(route!);
      }
    });
    _imageProvider?.evict();
    super.dispose();
  }

  late Future<ChatMediaData>? _data = widget.type == 'image' ? _load() : null;
  Future<ChatMediaData> _load() {
    final future = (widget.service ?? ChatService()).mediaData(
      widget.path,
      type: widget.type,
    );
    // El FutureBuilder se suscribe en el siguiente frame tras pulsar cargar.
    future.ignore();
    return future;
  }

  @override
  void didUpdateWidget(covariant ChatMediaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.type != widget.type) {
      _imageProvider?.evict();
      _imageProvider = null;
      _data = widget.type == 'image' ? _load() : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Descargar audio solo a petición evita cargar todo el historial en memoria.
    if (_data == null) {
      return TextButton.icon(
        onPressed: () => setState(() {
          _data = _load();
        }),
        icon: const Icon(Icons.download),
        label: Text(
          widget.durationMs == null
              ? 'Cargar audio'
              : 'Cargar audio · ${audioTime(Duration(milliseconds: widget.durationMs!))}',
        ),
      );
    }
    return FutureBuilder<ChatMediaData>(
      key: ValueKey('${widget.type}:${widget.path}'),
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TextButton(
            onPressed: () => setState(() {
              _data = _load();
            }),
            child: const Text('Reintentar archivo'),
          );
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final data = snapshot.data!;
        if (widget.type == 'image') {
          _imageProvider ??= MemoryImage(data.bytes);
          return InkWell(
            onTap: () => _showImage(data),
            child: Image.memory(
              data.bytes,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) =>
                  const Text('Imagen no disponible'),
            ),
          );
        }
        return AudioPlayback(
          bytes: data.bytes,
          mime: data.contentType,
          durationMs: widget.durationMs,
        );
      },
    );
  }
}
