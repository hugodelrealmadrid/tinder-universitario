import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'audio_playback.dart';
import 'voice_note_controller.dart';

/// Gestos y accesibilidad comparten el mismo controlador; nunca abre otro micrófono.
class VoiceNoteRecorder extends StatefulWidget {
  const VoiceNoteRecorder({
    super.key,
    required this.enabled,
    required this.onSend,
    required this.onBusy,
    this.capture,
    this.composer,
  });
  final bool enabled;
  final Future<void> Function(Uint8List) onSend;
  final ValueChanged<bool> onBusy;
  final VoiceCapture? capture;
  final Widget Function(Widget action)? composer;
  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder>
    with WidgetsBindingObserver {
  late final _controller = VoiceNoteController(
    widget.capture ?? RecordVoiceCapture(),
  );
  bool _cancelled = false, _locked = false, _lastBusy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final busy = _controller.busy;
    if (busy != _lastBusy) {
      _lastBusy = busy;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBusy(busy);
      });
    }
  }

  @override
  void didUpdateWidget(covariant VoiceNoteRecorder old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && old.enabled) unawaited(_controller.discard());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive && !_controller.starting)) {
      unawaited(_controller.discard());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _start({bool locked = false}) {
    if (!widget.enabled || _controller.busy) return;
    _cancelled = false;
    _locked = locked;
    unawaited(_controller.begin());
  }

  Future<void> _released() async {
    final c = _controller;
    if (_cancelled || _locked) return;
    // Si el permiso seguía abierto o la voz es breve/baja, se revisa antes de enviar.
    final send = c.recording && !c.starting && !c.signal.quiet;
    await c.finish();
    if (!mounted || _cancelled || !widget.enabled) return;
    if (send && c.draft != null) await c.send(widget.onSend);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final panel = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  c.error!,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            if (c.warning != null)
              Text(c.warning!, style: const TextStyle(color: AppColors.muted)),
            if (c.draft != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Escucha tu nota',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    AudioPlayback(
                      key: ValueKey(c.draft),
                      bytes: c.draft!,
                      mime: 'audio/wav',
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: c.sending ? null : c.discard,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Descartar nota'),
                        ),
                        FilledButton.icon(
                          onPressed:
                              !widget.enabled ||
                                  c.sending ||
                                  c.deliveryUncertain
                              ? null
                              : () => c.send(widget.onSend),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            c.sending ? 'Enviando nota…' : 'Enviar nota de voz',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else if (widget.composer == null || c.busy)
              Row(
                children: [
                  if (widget.composer == null) _microphone(c),
                  if (widget.composer == null) const SizedBox(width: 12),

                  Expanded(
                    child: c.recording || c.starting || c.stopping
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.starting
                                    ? 'Preparando micrófono…'
                                    : c.stopping
                                    ? 'Preparando nota…'
                                    : '${c.seconds.toString().padLeft(2, '0')}s · ${_locked ? 'Grabación bloqueada' : '← Cancelar · ↑ Bloquear'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              if (c.recording && !c.stopping)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    c.signal.samples == 0
                                        ? 'Esperando señal…'
                                        : c.signal.silent
                                        ? 'Sin sonido: revisa el micrófono'
                                        : 'Se recibe señal del micrófono',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          c.signal.samples > 0 &&
                                              c.signal.silent
                                          ? AppColors.danger
                                          : AppColors.muted,
                                    ),
                                  ),
                                ),
                              if (c.recording && !c.stopping)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: LinearProgressIndicator(
                                    value: c.signal.meter,
                                    semanticsLabel:
                                        'Nivel de entrada del micrófono',
                                    minHeight: 3,
                                  ),
                                ),
                            ],
                          )
                        : const Text(
                            'Mantén para hablar\n← cancela · ↑ bloquea para revisar',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                  ),
                  if (c.recording || c.starting) ...[
                    IconButton(
                      tooltip: 'Cancelar grabación',
                      onPressed: () {
                        _cancelled = true;
                        unawaited(c.discard());
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    IconButton(
                      tooltip: 'Detener y escuchar',
                      onPressed: c.stopping ? null : c.finish,
                      icon: const Icon(Icons.stop_circle_outlined),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
    if (widget.composer == null) return panel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        panel,
        widget.composer!(
          c.draft == null ? _microphone(c) : const SizedBox(width: 52),
        ),
      ],
    );
  }

  Widget _microphone(VoiceNoteController c) => GestureDetector(
    onTap: !widget.enabled
        ? null
        : () {
            if (c.recording) {
              unawaited(c.finish());
            } else {
              _start(locked: true);
            }
          },
    onLongPressStart: !widget.enabled ? null : (_) => _start(),
    onLongPressMoveUpdate: (d) {
      if (_locked || _cancelled) return;
      if (d.offsetFromOrigin.dx < -80) {
        _cancelled = true;
        unawaited(c.discard());
      } else if (d.offsetFromOrigin.dy < -75) {
        setState(() => _locked = true);
      }
    },
    onLongPressEnd: (_) => unawaited(_released()),
    onLongPressCancel: () {
      if (!_locked && c.busy) {
        _cancelled = true;
        unawaited(c.discard());
      }
    },
    child: Semantics(
      label: 'Grabar nota de voz',
      button: true,
      onTap: !widget.enabled ? null : () => _start(locked: true),
      child: Tooltip(
        message: 'Mantén para grabar · ← cancelar · ↑ bloquear',
        triggerMode: TooltipTriggerMode.manual,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.fast,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: widget.enabled ? AppColors.coral : AppColors.line,
            shape: BoxShape.circle,
            boxShadow: c.recording && !MediaQuery.disableAnimationsOf(context)
                ? [
                    BoxShadow(
                      color: AppColors.coral.withValues(
                        alpha: .2 + .25 * c.signal.meter,
                      ),
                      blurRadius: 18,
                      spreadRadius: 4 * c.signal.meter,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            _locked && c.recording ? Icons.lock_rounded : Icons.mic,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}
