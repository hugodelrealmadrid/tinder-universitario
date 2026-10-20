import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../verification/backend_client.dart';
import 'private_photo_path.dart';

class PrivateProfilePhoto extends StatefulWidget {
  const PrivateProfilePhoto({
    super.key,
    required this.path,
    required this.placeholder,
    required this.failure,
    this.loader,
  });
  final String path;
  final Widget placeholder;
  final Widget Function(Object, VoidCallback) failure;
  final Future<Uint8List> Function(String)? loader;
  @override
  State<PrivateProfilePhoto> createState() => _PrivateProfilePhotoState();
}

class _PrivateProfilePhotoState extends State<PrivateProfilePhoto>
    with WidgetsBindingObserver {
  ui.Image? _image;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant PrivateProfilePhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<Uint8List> _read() async {
    final client = VerificationClient();
    try {
      return await client.photoBytes(widget.path);
    } finally {
      client.close();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _image?.dispose();
        _image = null;
        _error = null;
      });
    }
    ui.Codec? codec;
    try {
      if (!isPrivatePhotoPath(widget.path)) {
        throw StateError('private-reference-required');
      }
      final bytes = await (widget.loader?.call(widget.path) ?? _read());
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1024,
        allowUpscaling: false,
      );
      final image = (await codec.getNextFrame()).image;
      if (!mounted || generation != _generation) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (e) {
      if (mounted && generation == _generation) {
        debugPrint('AppPhoto: load-failed');
        setState(() => _error = e);
      }
    } finally {
      codec?.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    } else {
      _generation++;
      setState(() {
        _image?.dispose();
        _image = null;
        _error = StateError('view-hidden');
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? widget.failure(_error!, _load)
      : _image != null
      ? RawImage(
          image: _image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        )
      : Stack(
          fit: StackFit.expand,
          children: [
            widget.placeholder,
            const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ],
        );
}
