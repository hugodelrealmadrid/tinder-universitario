import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'audio_playback.dart';
import 'voice_note_controller.dart';

class VoiceNoteRecorder extends StatefulWidget {
  const VoiceNoteRecorder({
    super.key,
    required this.enabled,
    required this.onSend,
    required this.onBusy,
    this.capture,
  });
  final bool enabled;
  final Future<void> Function(Uint8List) onSend;
  final ValueChanged<bool> onBusy;
  final VoiceCapture? capture;
  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder>
    with WidgetsBindingObserver {
  late final _controller = VoiceNoteController(
    widget.capture ?? RecordVoiceCapture(),
  );
  bool _cancelGesture = false, _lastBusy = false;
  bool _choosingDevice = false;
  Future<void> _chooseDevice() async {
    final capture = _controller.capture;
    if (capture is! RecordVoiceCapture || _choosingDevice) return;
    setState(() => _choosingDevice = true);
    try {
      final devices = await capture.devices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se encontraron micrófonos. Revisa los permisos del sitio y del sistema.',
            ),
          ),
        );
        return;
      }
      final selected = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Selecciona el micrófono'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, -1),
              child: const Text('Predeterminado del sistema'),
            ),
            for (var i = 0; i < devices.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, i),
                child: Text(
                  devices[i].label.isEmpty
                      ? 'Micrófono ${i + 1}'
                      : devices[i].label,
                ),
              ),
          ],
        ),
      );
      if (!mounted || selected == null) return;
      setState(() => capture.device = selected < 0 ? null : devices[selected]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo consultar el micrófono. Revisa los permisos.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _choosingDevice = false);
    }
  }

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
    if (state != AppLifecycleState.resumed) unawaited(_controller.discard());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) {
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

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.error != null) Text(c.error!),
          if (c.warning != null) Text(c.warning!),
          if (c.recording) ...[
            LinearProgressIndicator(
              value: c.signal.meter,
              semanticsLabel: 'Nivel de entrada del micrófono',
            ),
            Text(
              c.signal.samples == 0
                  ? 'Esperando señal del micrófono…'
                  : c.signal.silent
                  ? 'Sin sonido: habla y comprueba el micrófono'
                  : 'Se recibe señal del micrófono',
            ),
          ],
          if (!c.busy && c.capture is RecordVoiceCapture)
            TextButton.icon(
              onPressed: !widget.enabled || _choosingDevice
                  ? null
                  : _chooseDevice,
              icon: const Icon(Icons.settings_voice),
              label: Text(
                _choosingDevice
                    ? 'Consultando micrófonos…'
                    : 'Micrófono: ${(c.capture as RecordVoiceCapture).device?.label ?? 'predeterminado'}',
              ),
            ),
          if (c.draft != null) ...[
            AudioPlayback(
              key: ValueKey(c.draft),
              bytes: c.draft!,
              mime: 'audio/wav',
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: c.sending ? null : c.discard,
                  child: const Text('Descartar nota'),
                ),
                FilledButton(
                  onPressed: !widget.enabled || c.sending
                      ? null
                      : () => c.send(widget.onSend),
                  child: Text(
                    c.sending ? 'Enviando nota…' : 'Enviar nota de voz',
                  ),
                ),
              ],
            ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: !widget.enabled
                      ? null
                      : () => c.recording ? c.finish() : c.begin(),
                  onLongPressStart: !widget.enabled
                      ? null
                      : (_) {
                          _cancelGesture = false;
                          unawaited(c.begin());
                        },
                  onLongPressMoveUpdate: (d) {
                    if (d.offsetFromOrigin.dx < -70) {
                      _cancelGesture = true;
                      unawaited(c.discard());
                    }
                  },
                  onLongPressEnd: (_) {
                    if (!_cancelGesture) unawaited(c.finish());
                  },
                  child: Tooltip(
                    triggerMode: TooltipTriggerMode.manual,
                    message:
                        'Mantén presionado para grabar; desliza a la izquierda para cancelar',
                    child: Semantics(
                      label: 'Grabar nota de voz',
                      button: true,
                      onTap: !widget.enabled
                          ? null
                          : () => c.recording ? c.finish() : c.begin(),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.mic,
                          color: c.recording ? Colors.red : null,
                        ),
                      ),
                    ),
                  ),
                ),
                if (c.recording || c.starting || c.stopping) ...[
                  Flexible(
                    child: Text(
                      c.starting
                          ? 'Preparando micrófono…'
                          : '${c.seconds}s / 60s · Desliza ← para cancelar',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Detener y escuchar',
                    onPressed: c.finish,
                    icon: const Icon(Icons.stop),
                  ),
                  IconButton(
                    tooltip: 'Cancelar grabación',
                    onPressed: c.discard,
                    icon: const Icon(Icons.close),
                  ),
                ] else
                  const Flexible(
                    child: Text('Mantén presionado para grabar una nota'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
