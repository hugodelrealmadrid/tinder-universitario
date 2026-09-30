import 'package:flutter/material.dart';
import 'safety_models.dart';
import 'safety_service.dart';

enum SafetyAction { block, report }

Future<bool> showSafetyDialog(
  BuildContext context, {
  required String target,
  required SafetyAction action,
  SafetyService? service,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          SafetyDialog(target: target, action: action, service: service),
    ) ??
    false;

class SafetyDialog extends StatefulWidget {
  const SafetyDialog({
    super.key,
    required this.target,
    required this.action,
    this.service,
  });
  final String target;
  final SafetyAction action;
  final SafetyService? service;
  @override
  State<SafetyDialog> createState() => _SafetyDialogState();
}

class _SafetyDialogState extends State<SafetyDialog> {
  final _form = GlobalKey<FormState>();
  final _details = TextEditingController();
  String? _reason, _error;
  bool _busy = false;
  bool get _block => widget.action == SafetyAction.block;
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || (!_block && !_form.currentState!.validate())) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = widget.service ?? SafetyService();
      if (_block) {
        await service.block(widget.target);
      } else {
        await service.report(widget.target, _reason!, _details.text);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = safetyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(_block ? '¿Bloquear usuario?' : 'Reportar usuario'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_block)
                  const Text(
                    'Ya no podrán encontrarse en Descubrir ni enviarse mensajes. Esta acción no se puede deshacer actualmente.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('report-reason'),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                    items: ReportReasons.labels.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _reason = value),
                    validator: (value) => ReportReasons.isValid(value)
                        ? null
                        : 'Selecciona un motivo.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('report-details'),
                    controller: _details,
                    enabled: !_busy,
                    maxLength: ReportReasons.maxDetailsLength,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Detalles (opcional)',
                    ),
                    validator: (value) =>
                        (value?.length ?? 0) > ReportReasons.maxDetailsLength
                        ? 'Máximo 500 caracteres.'
                        : null,
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('safety-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(_block ? 'Bloquear' : 'Enviar reporte'),
        ),
      ],
    ),
  );
}
