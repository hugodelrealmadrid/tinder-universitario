import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'account_access.dart';
import 'backend_client.dart';
import 'university_verification_screen.dart';

/// Solo bytes autenticados en memoria: RawImage evita la caché global de Image.memory.
class PrivateDocumentView extends StatefulWidget {
  const PrivateDocumentView({
    super.key,
    required this.client,
    required this.requestId,
  });
  final VerificationClient client;
  final String requestId;
  @override
  State<PrivateDocumentView> createState() => _PrivateDocumentViewState();
}

class _PrivateDocumentViewState extends State<PrivateDocumentView>
    with WidgetsBindingObserver {
  ui.Image? _image;
  String? _error;
  late final Timer _expiry;
  bool _closed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _expiry = Timer(const Duration(seconds: 60), _clear);
    _load();
  }

  Future<void> _load() async {
    ui.Codec? codec;
    try {
      final Uint8List bytes = await widget.client.document(widget.requestId);
      codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      if (!mounted || _closed) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (e) {
      if (mounted && !_closed) setState(() => _error = verificationError(e));
    } finally {
      codec?.dispose();
    }
  }

  void _clear() {
    if (mounted) {
      setState(() {
        _closed = true;
        _image?.dispose();
        _image = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _clear();
  }

  @override
  void dispose() {
    _closed = true;
    _expiry.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Carnet privado · vista temporal'),
    content: SizedBox(
      width: 520,
      height: 380,
      child: Column(
        children: [
          const Text(
            'Se oculta al cambiar de ventana o después de 60 segundos. No descargues ni compartas este documento.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: _closed
                  ? const Text(
                      'Vista cerrada. Vuelve a abrirla si necesitas revisar.',
                    )
                  : _error != null
                  ? Text(_error!)
                  : _image == null
                  ? const CircularProgressIndicator()
                  : Semantics(
                      label: 'Fotografía privada del carnet universitario',
                      image: true,
                      child: RawImage(image: _image, fit: BoxFit.contain),
                    ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  );
}

class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({
    super.key,
    required this.client,
    required this.access,
    required this.uid,
    required this.logout,
    required this.onDating,
  });
  final VerificationClient client;
  final AccountAccess access;
  final String uid;
  final Widget logout;
  final VoidCallback onDating;
  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  String _section = 'requests', _status = 'pending';
  List<Map<String, dynamic>> _items = [];
  bool _busy = false, _more = false;
  String? _error, _notice;
  Map<String, dynamic>? _account;
  final _uid = TextEditingController();
  bool get _root => widget.access.role == AccountRole.superadmin;
  @override
  void initState() {
    super.initState();
    if (widget.access.canAdminister) _load();
  }

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!more) _items = [];
    });
    try {
      final cursor = more && _items.isNotEmpty
          ? _items.last['id'] as String
          : null;
      final raw = _section == 'audit'
          ? await widget.client.audit(cursor: cursor)
          : _section == 'reports'
          ? await widget.client.reports()
          : await widget.client.requests(status: _status, cursor: cursor);
      if (mounted) {
        setState(() {
          _items = [
            ..._items,
            ...raw.map((e) => Map<String, dynamic>.from(e as Map)),
          ];
          _more = raw.length == 20 && _section != 'reports';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = verificationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool refresh = true,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _notice = 'Operación completada.');
      if (refresh) await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = verificationError(e));
        if (e is VerificationFailure && e.code == 'conflict') {
          final message = verificationError(e);
          await _load();
          if (mounted) setState(() => _error = message);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decision(Map<String, dynamic> item, bool approve) async {
    String? reason = 'verified';
    if (approve) {
      if (!await confirmAction(
        context,
        'Aprobar verificación',
        'Confirma que el carnet vigente corresponde a este estudiante y a Univalle sede Cochabamba.',
      )) {
        return;
      }
    } else {
      reason = await _reason('Motivo de rechazo', {
        'unreadable': 'Fotografía ilegible',
        'expired': 'Carnet vencido',
        'not_univalle_cochabamba': 'No corresponde a Univalle Cochabamba',
        'information_mismatch': 'Datos no coincidentes',
        'other': 'Documento insuficiente',
      });
      if (reason == null) return;
    }
    if (!mounted) return;
    await _run(
      () => widget.client.decide(
        item['id'] as String,
        approve ? 'approved' : 'rejected',
        reason!,
      ),
    );
  }

  Future<String?> _reason(String title, Map<String, String> reasons) =>
      showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final r in reasons.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, r.key),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(r.value),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
  Future<void> _lookup() => _run(() async {
    setState(() => _account = null);
    final a = await widget.client.account(_uid.text.trim());
    if (mounted) setState(() => _account = a);
  }, refresh: false);
  Future<void> _suspend(bool value) async {
    final reason = await _reason(
      value ? 'Motivo de suspensión' : 'Motivo de restablecimiento',
      {
        'abuse': 'Abuso',
        'spam': 'Spam',
        'safety': 'Seguridad',
        'other': 'Otro motivo',
      },
    );
    if (reason == null || !mounted) return;
    if (!await confirmAction(
      context,
      value ? 'Suspender cuenta' : 'Restablecer cuenta',
      'Se aplicará inmediatamente a la cuenta ${_account!['uid']}. Su visibilidad voluntaria no cambiará.',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      await widget.client.suspend(_account!['uid'] as String, value, reason);
      final a = await widget.client.account(_account!['uid'] as String);
      if (mounted) setState(() => _account = a);
    }, refresh: false);
  }

  Future<void> _role(String role) async {
    if (!await confirmAction(
      context,
      'Cambiar rol administrativo',
      'Asignar rol $role a ${_account!['uid']}. La acción quedará auditada y no modifica la verificación.',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      await widget.client.role(_account!['uid'] as String, role);
      final a = await widget.client.account(_account!['uid'] as String);
      if (mounted) setState(() => _account = a);
    }, refresh: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.access.canAdminister) {
      return const Scaffold(
        body: Center(child: Text('Acceso administrativo no autorizado.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_root ? 'Superadministración' : 'Administración'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    'requests': 'Solicitudes',
                    'reports': 'Reportes',
                    'accounts': 'Cuentas',
                    if (_root) 'audit': 'Auditoría',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _section == entry.key,
                      onSelected: _busy
                          ? null
                          : (_) {
                              setState(() {
                                _section = entry.key;
                                _notice = null;
                                _error = null;
                                _items = [];
                                _account = null;
                              });
                              if (_section != 'accounts') _load();
                            },
                    ),
                  TextButton(
                    onPressed: widget.onDating,
                    child: const Text('Abrir aplicación'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_section == 'requests') ...[
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Estado de solicitudes',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Pendientes'),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Aprobadas'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rechazadas'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() => _status = value!);
                          _load();
                        },
                ),
                const Text(
                  'Historial por solicitud. Los carnets resueltos se eliminan y no pueden consultarse. Se excluye la revisión propia.',
                ),
              ],
              if (_busy)
                const LinearProgressIndicator(
                  semanticsLabel: 'Procesando administración',
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_notice != null) Text(_notice!),
              if (_section != 'accounts') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _load(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar lista'),
                  ),
                ),
                if (!_busy && _items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No hay registros para mostrar.'),
                  ),
                for (final item in _items) _card(item),
                if (_more)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _load(more: true),
                    child: const Text('Cargar más registros'),
                  ),
              ] else ...[
                const Text(
                  'Busca por identificador de cuenta (UID). No se publican correos ni documentos privados.',
                ),
                TextField(
                  controller: _uid,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'UID de la cuenta',
                  ),
                  onSubmitted: (_) {
                    if (!_busy) _lookup();
                  },
                ),
                FilledButton(
                  onPressed: _busy ? null : _lookup,
                  child: const Text('Consultar cuenta'),
                ),
                if (_account != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText('UID: ${_account!['uid']}'),
                          Text('Rol: ${_account!['role']}'),
                          Text(
                            'Verificación: ${statusLabel(_account!['verificationStatus'] as String?)}',
                          ),
                          Text(
                            'Suspendida: ${_account!['suspended'] == true ? 'Sí' : 'No'}',
                          ),
                          if (_account!['uid'] == widget.uid)
                            const Text(
                              'No puedes modificar tu propia cuenta administrativa.',
                            )
                          else ...[
                            if (_root || _account!['role'] == 'user')
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _suspend(
                                        _account!['suspended'] != true,
                                      ),
                                child: Text(
                                  _account!['suspended'] == true
                                      ? 'Restablecer cuenta'
                                      : 'Suspender cuenta',
                                ),
                              ),
                            if (_root && _account!['role'] != 'superadmin')
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _role(
                                        _account!['role'] == 'admin'
                                            ? 'user'
                                            : 'admin',
                                      ),
                                child: Text(
                                  _account!['role'] == 'admin'
                                      ? 'Revocar rol de administrador'
                                      : 'Asignar rol de administrador',
                                ),
                              ),
                            if (_account!['role'] == 'superadmin')
                              const Text(
                                'Los cambios de superadministrador requieren el procedimiento privilegiado; este panel solo gestiona administradores.',
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              widget.logout,
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> item) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_section == 'requests') ...[
            SelectableText('Solicitud: ${item['id']}'),
            SelectableText('Estudiante: ${item['uid']}'),
            Text(
              '${statusLabel(item['status'] as String?)} · Enviada: ${displayDate(item['createdAt'])}',
            ),
            if (item['resolvedAt'] != null)
              Text(
                'Resuelta: ${displayDate(item['resolvedAt'])} · ${item['reviewedBy'] ?? 'Sistema'}',
              ),
            if (item['reasonCode'] != null)
              Text(
                item['status'] == 'approved'
                    ? 'Pertenencia universitaria verificada.'
                    : rejectionReasons[item['reasonCode']] ??
                          'Solicitud resuelta.',
              ),
            if (item['status'] == 'pending' && item['canReview'] != true)
              const Text(
                'Todavía no hay un carnet listo o la solicitud es propia.',
              ),
            if (item['canReview'] == true)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) => PrivateDocumentView(
                              client: widget.client,
                              requestId: item['id'] as String,
                            ),
                          ),
                    child: const Text('Ver carnet privado'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _decision(item, true),
                    child: const Text('Aprobar'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _decision(item, false),
                    child: const Text('Rechazar'),
                  ),
                ],
              ),
          ] else if (_section == 'reports') ...[
            SelectableText('Reporte: ${item['id']}'),
            SelectableText('Cuenta reportada: ${item['reportedId']}'),
            Text(
              'Motivo: ${item['reason'] ?? item['reasonCode'] ?? 'Sin detalle'}',
            ),
            Text('Fecha: ${displayDate(item['createdAt'])}'),
            if (item['details'] is String &&
                (item['details'] as String).isNotEmpty)
              Text(item['details'] as String),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _uid.text = item['reportedId'] as String;
                          setState(() {
                            _section = 'accounts';
                            _account = null;
                          });
                          _lookup();
                        },
                  child: const Text('Consultar / suspender cuenta'),
                ),
                for (final r in {
                  'reviewed': 'Marcar revisado',
                  'dismissed': 'Descartar reporte',
                }.entries)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            if (await confirmAction(
                                  context,
                                  r.value,
                                  'La resolución del reporte quedará auditada.',
                                ) &&
                                mounted) {
                              await _run(
                                () => widget.client.reviewReport(
                                  item['id'] as String,
                                  r.key,
                                ),
                              );
                            }
                          },
                    child: Text(r.value),
                  ),
              ],
            ),
          ] else ...[
            Text('${item['action']} · ${displayDate(item['at'])}'),
            SelectableText(
              'Actor: ${item['actorId']}\nCuenta: ${item['targetId']}',
            ),
            Text('Motivo: ${item['reasonCode']}'),
            if (item['requestId'] != null)
              SelectableText('Solicitud: ${item['requestId']}'),
          ],
        ],
      ),
    ),
  );
}
