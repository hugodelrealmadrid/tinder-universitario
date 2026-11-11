import 'dart:typed_data';

import 'package:flutter/material.dart';

class AdminDossierPhoto extends StatefulWidget {
  const AdminDossierPhoto({
    super.key,
    required this.path,
    required this.load,
    required this.label,
  });

  final String path, label;
  final Future<Uint8List> Function(String) load;

  @override
  State<AdminDossierPhoto> createState() => _AdminDossierPhotoState();
}

class _AdminDossierPhotoState extends State<AdminDossierPhoto> {
  late Future<MemoryImage> _photo = _load();
  MemoryImage? _image;

  Future<MemoryImage> _load() async {
    final image = MemoryImage(await widget.load(widget.path));
    if (mounted) _image = image;
    return image;
  }

  void _retry() => setState(() {
    _image?.evict();
    _image = null;
    _photo = _load();
  });

  @override
  void dispose() {
    _image?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 104,
    child: FutureBuilder<MemoryImage>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(semanticsLabel: 'Cargando foto'),
          );
        }
        if (snapshot.hasError) return _error();
        final image = snapshot.requireData;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Semantics(
            button: true,
            label: 'Ampliar ${widget.label.toLowerCase()}',
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Cerrar foto',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                        Flexible(
                          child: InteractiveViewer(
                            child: Image(
                              image: image,
                              fit: BoxFit.contain,
                              semanticLabel: widget.label,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: Image(
                image: image,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stackTrace) => _error(),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _error() => Center(
    child: TextButton(
      onPressed: _retry,
      child: const Text('Foto no disponible. Reintentar'),
    ),
  );
}
