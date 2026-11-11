import '../../theme/app_theme.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio_object_url_stub.dart'
    if (dart.library.js_interop) 'audio_object_url_web.dart';

String audioTime(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class AudioPlayback extends StatefulWidget {
  const AudioPlayback({
    super.key,
    required this.bytes,
    this.mime,
    this.durationMs,
  });
  final Uint8List bytes;
  final String? mime;
  final int? durationMs;
  @override
  State<AudioPlayback> createState() => _AudioPlaybackState();
}

class _AudioPlaybackState extends State<AudioPlayback> {
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Duration _duration = Duration.zero, _position = Duration.zero;
  bool _playing = false, _busy = false, _loaded = false;
  String? _error, _objectUrl;
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
    if (widget.durationMs case final milliseconds? when milliseconds > 0) {
      _duration = Duration(milliseconds: milliseconds);
    } else if (widget.mime == 'audio/wav' && widget.bytes.length >= 44) {
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
        if (!mounted) return;
        final url = _objectUrl ??= createAudioObjectUrl(
          widget.bytes,
          widget.mime,
        );
        await _player.setSource(
          url == null
              ? BytesSource(widget.bytes, mimeType: widget.mime)
              : UrlSource(url, mimeType: widget.mime),
        );
        _loaded = true;
      }
      if (_playing) {
        await _player.pause();
      } else {
        await _player.resume();
      }
    } catch (error) {
      if (!mounted) return;
      _loaded = false;
      final url = _objectUrl;
      if (url != null) revokeAudioObjectUrl(url);
      _objectUrl = null;
      final code = error is PlatformException ? error.code : error.runtimeType;
      debugPrint('Audio LIGO: $code');
      setState(() => _error = 'No se pudo reproducir el audio.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    final url = _objectUrl;
    if (url != null) revokeAudioObjectUrl(url);
    unawaited(
      _player.dispose().catchError((Object error) {
        debugPrint('Audio LIGO: no se pudo liberar el reproductor.');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: AppColors.rose,
                foregroundColor: AppColors.wine,
              ),
              tooltip: _playing ? 'Pausar audio' : 'Reproducir audio',
              onPressed: _busy ? null : _toggle,
              icon: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppMotion.fast,
                child: Icon(
                  _playing ? Icons.pause : Icons.play_arrow,
                  key: ValueKey(_playing),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
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
                              await _player.seek(
                                Duration(milliseconds: v.round()),
                              );
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'No se pudo cambiar la posición.',
                                );
                              }
                            }
                          },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      audioTime(
                        _playing || _position > Duration.zero
                            ? _position
                            : _duration,
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.graphic_eq_rounded,
              size: 20,
              color: AppColors.wine,
            ),
          ],
        ),
        if (_error != null) Text(_error!),
      ],
    ),
  );
}
