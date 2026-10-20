import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

String audioTime(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class AudioPlayback extends StatefulWidget {
  const AudioPlayback({super.key, required this.bytes, this.mime});
  final Uint8List bytes;
  final String? mime;
  @override
  State<AudioPlayback> createState() => _AudioPlaybackState();
}

class _AudioPlaybackState extends State<AudioPlayback> {
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Duration _duration = Duration.zero, _position = Duration.zero;
  bool _playing = false, _busy = false, _loaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      _player.onPositionChanged.listen((d) {
        if (mounted) setState(() => _position = d);
      }),
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playing = false;
            _position = Duration.zero;
          });
        }
      }),
    ]);
    // WAV PCM de las notas: duración disponible antes de la primera escucha.
    if (widget.mime == 'audio/wav' && widget.bytes.length >= 44) {
      final v = ByteData.sublistView(widget.bytes);
      final rate = v.getUint32(28, Endian.little);
      if (rate > 0) {
        _duration = Duration(
          milliseconds: ((widget.bytes.length - 44) * 1000 / rate).round(),
        );
      }
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_loaded) {
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setSource(
          BytesSource(widget.bytes, mimeType: widget.mime),
        );
        _loaded = true;
      }
      if (_playing) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo reproducir el audio.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          IconButton(
            tooltip: _playing ? 'Pausar audio' : 'Reproducir audio',
            onPressed: _busy ? null : _toggle,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Slider(
              label: audioTime(_position),
              value: _position.inMilliseconds.toDouble().clamp(
                0,
                _duration.inMilliseconds.toDouble(),
              ),
              max: _duration.inMilliseconds > 0
                  ? _duration.inMilliseconds.toDouble()
                  : 1,
              onChanged: !_loaded
                  ? null
                  : (v) async {
                      try {
                        await _player.seek(Duration(milliseconds: v.round()));
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => _error = 'No se pudo cambiar la posición.',
                          );
                        }
                      }
                    },
            ),
          ),
          Text('${audioTime(_position)} / ${audioTime(_duration)}'),
        ],
      ),
      if (_error != null) Text(_error!),
    ],
  );
}
