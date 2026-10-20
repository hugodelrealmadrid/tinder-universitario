import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../chat/chat_media_validation.dart';
import 'account_access.dart';
import 'backend_client.dart';

const rejectionReasons = <String, String>{
  'unreadable':
      'La fotografía no es legible. Envía una imagen nítida del carnet completo.',
  'expired': 'El carnet o la solicitud venció. Presenta un carnet vigente.',
  'not_univalle_cochabamba':
      'El documento no acredita pertenencia a Univalle sede Cochabamba.',
  'information_mismatch': 'Los datos del carnet no coinciden con la solicitud.',
  'other':
      'El documento no permite acreditar tu pertenencia universitaria. Revisa las instrucciones y reenvíalo.',
  'withdrawn': 'Retiraste la solicitud. Puedes enviar otra fotografía.',
  'upload_failed': 'La subida no se completó. Vuelve a enviar la fotografía.',
};
String statusLabel(String? status) => switch (status) {
  'approved' => 'Aprobado',
  'rejected' => 'Rechazado',
  _ => 'Pendiente',
};
String displayDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Fecha no disponible';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}

/// La misma validación de contenido de imágenes del chat, más la extensión del selector.
Future<void> validateUniversityPhoto(Uint8List bytes, String extension) async {
  final mime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  }[extension.toLowerCase()];
  if (mime == null) throw const VerificationFailure('invalid-image');
  try {
    await ChatMediaValidation.validate(bytes, 'image', mime);
  } catch (_) {
    throw const VerificationFailure('invalid-image');
  }
}

class UniversityVerificationScreen extends StatefulWidget {
  const UniversityVerificationScreen({
    super.key,
    required this.client,
    required this.access,
    required this.logout,
    this.picker,
  });
  final VerificationClient client;
  final AccountAccess access;
  final Widget logout;
  final Future<(Uint8List, String)?> Function()? picker;
  @override
  State<UniversityVerificationScreen> createState() =>
      _UniversityVerificationScreenState();
}

class _UniversityVerificationScreenState
    extends State<UniversityVerificationScreen> {
  Map<String, dynamic>? _request;
  Uint8List? _photo;
  bool _busy = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UniversityVerificationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.access.status != widget.access.status ||
        oldWidget.access.suspended != widget.access.suspended) {
      if (widget.access.suspended) {
        _photo = null;
        _request = null;
        _notice = null;
      } else if (!_busy) {
        _load();
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.access.suspended && widget.access.role != null) return;
      await widget.client.provision();
      final request = await widget.client.ownRequest();
      if (mounted) setState(() => _request = request);
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _photo = null;
    });
    try {
      if (widget.picker != null) {
        final selected = await widget.picker!();
        if (selected == null) return;
        await validateUniversityPhoto(selected.$1, selected.$2);
        if (mounted) {
          setState(() {
            _photo = selected.$1;
            _notice =
                'Foto validada. Pulsa Enviar carnet para subirla de forma privada.';
          });
        }
        return;
      }
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: false,
        withReadStream: true,
      );
      if (result == null) return;
      final file = result.files.single;
      if (file.size > ChatMediaValidation.imageLimit || file.size <= 0) {
        throw const VerificationFailure('invalid-image');
      }
      final bytes = file.readStream != null
          ? await ChatMediaValidation.readBounded(
              file.readStream!,
              ChatMediaValidation.imageLimit,
            )
          : file.bytes;
      if (bytes == null) throw const VerificationFailure('invalid-image');
      await validateUniversityPhoto(bytes, file.extension ?? '');
      if (mounted) {
        setState(() {
          _photo = bytes;
          _notice =
              'Foto validada. Pulsa Enviar carnet para subirla de forma privada.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final bytes = _photo;
    if (bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.client.begin();
      await widget.client.upload(id, bytes);
      _photo = null;
      final request = await widget.client.ownRequest();
      if (mounted) {
        setState(() {
          _request = request;
          _notice = 'Carnet enviado. Espera la revisión de un administrador.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw() async {
    final yes = await confirmAction(
      context,
      'Retirar solicitud',
      'Se eliminará el carnet y podrás enviar una nueva solicitud.',
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.withdraw(_request!['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suspended = widget.access.suspended;
    final stage = _request?['documentStage'];
    final waiting =
        _request?['status'] == 'pending' &&
        ['ready', 'uploading'].contains(stage);
    final status = _request?['status'] as String? ?? widget.access.status?.name;
    return Scaffold(
      appBar: AppBar(title: const Text('Verificación universitaria')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.school_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Univalle · Sede Cochabamba',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(
                suspended
                    ? 'Tu cuenta está suspendida administrativamente.'
                    : 'Estado: ${statusLabel(status)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!suspended) ...[
                const Text(
                  'Tu verificación universitaria está pendiente de aprobación hasta que se acepte tu carnet. Las funciones de citas requieren aprobación.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Envía una foto nítida y completa de tu carnet físico o virtual vigente. Deben leerse tu nombre, institución y vigencia. Solo se admite Univalle sede Cochabamba. No envíes documentos de identidad ni información adicional.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'JPG, PNG o WebP; hasta 5 MB y 4096 píxeles por lado. El servidor valida y elimina los metadatos. El carnet es privado, solo se revisa para esta solicitud y se programa su eliminación al resolverla o al vencer (24 horas). Nunca aparecerá en tu perfil.',
                ),
                if (status == 'rejected')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      rejectionReasons[_request?['reasonCode']] ??
                          'Solicitud rechazada. Envía un carnet vigente y legible.',
                    ),
                  ),
                if (_request != null)
                  Text('Enviada: ${displayDate(_request!['createdAt'])}'),
                if (waiting)
                  const Text(
                    'Solicitud recibida. Actualiza el estado para consultar la revisión.',
                  ),
                if (!waiting) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      status == 'rejected'
                          ? 'Seleccionar nuevo carnet'
                          : 'Seleccionar foto del carnet',
                    ),
                  ),
                  if (_photo != null) ...[
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Enviar carnet'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _photo = null;
                              _notice = null;
                            }),
                      child: const Text('Descartar foto'),
                    ),
                  ],
                ],
                if (waiting)
                  TextButton(
                    onPressed: _busy ? null : _withdraw,
                    child: const Text('Retirar solicitud'),
                  ),
              ],
              if (_busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Procesando solicitud',
                ),
              if (_notice != null) Text(_notice!, semanticsLabel: _notice),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TextButton(
                onPressed: _busy || suspended ? null : _load,
                child: const Text('Actualizar estado'),
              ),
              widget.logout,
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;
