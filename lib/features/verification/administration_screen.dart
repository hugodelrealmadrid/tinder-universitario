import 'academic_admin_screen.dart';
import 'admin_dossier.dart';
import 'admin_theme.dart';
import 'admin_visual.dart';
import 'admin_workspace.dart';
import 'audit_presentation.dart';
import '../../widgets/app_ui.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'account_access.dart';
import '../academics/catalog_admin_screen.dart';
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
    this.initialPage = 'dashboard',
  });
  final VerificationClient client;
  final AccountAccess access;
  final String uid;
  final Widget logout;
  final VoidCallback onDating;
  final String initialPage;
  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  String _section = 'requests', _status = 'pending';
  String _page = 'dashboard';
  String? _dossierUid;
  List<Map<String, dynamic>> _items = [];
  bool _busy = false, _more = false;
  String? _error, _notice;
  Map<String, dynamic>? _account;
  final _uid = TextEditingController();
  bool get _root => widget.access.role == AccountRole.superadmin;
  @override
  void initState() {
    super.initState();
    _page = widget.access.canDate ? widget.initialPage : 'requests';
    _section = _page == 'roles' || _page == 'accounts' ? 'accounts' : _page;
    if (widget.access.canAdminister && _page == 'requests') {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant AdministrationScreen old) {
    super.didUpdateWidget(old);
    if (!widget.access.canAdminister) {
      _items = [];
      _account = null;
      _page = 'requests';
      return;
    }
    final forbidden =
        (!_root && ['audit', 'roles', 'universities'].contains(_page)) ||
        (!widget.access.canDate &&
            [
              'dashboard',
              'users',
              'dossier',
              'roles',
              'careers',
              'interests',
            ].contains(_page));
    if (forbidden) {
      _items = [];
      _account = null;
      _error = null;
      _notice = null;
      _page = widget.access.canDate ? 'dashboard' : 'requests';
      _section = 'requests';
      if (_page == 'requests') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.access.canAdminister && _page == 'requests') {
            _load();
          }
        });
      }
    }
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
    final requestedStatus = _status;
    final canResolveIdentities = widget.access.canDate;
    try {
      final cursor = more && _items.isNotEmpty
          ? _items.last['id'] as String
          : null;
      final raw = await widget.client.requests(
        status: requestedStatus,
        cursor: cursor,
      );
      final rows = raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final ids = rows
          .expand((item) => [item['uid'], item['reviewedBy']])
          .whereType<String>()
          .where(
            (id) =>
                RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) &&
                id != 'authorized_operator',
          )
          .toSet()
          .toList();
      final people = <String, Map<String, dynamic>>{};
      if (canResolveIdentities && ids.isNotEmpty) {
        try {
          for (final person in await widget.client.identities(ids)) {
            if (person['uid'] case final String uid) people[uid] = person;
          }
        } catch (_) {
          // Una consulta de presentación fallida no impide revisar solicitudes.
        }
      }
      for (final row in rows) {
        row['student'] = people[row['uid']];
        row['reviewer'] = people[row['reviewedBy']];
      }
      if (mounted &&
          _section == 'requests' &&
          _status == requestedStatus &&
          widget.access.canAdminister &&
          (!canResolveIdentities || widget.access.canDate)) {
        setState(() {
          _items = [..._items, ...rows];
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
        'Confirma que el carnet vigente identifica a este estudiante y acredita su pertenencia a una universidad.',
      )) {
        return;
      }
    } else {
      reason = await _reason('Motivo de rechazo', {
        'unreadable': 'Fotografía ilegible',
        'expired': 'Carnet vencido',
        'not_university_student':
            'El carnet no acredita que sea estudiante universitario',
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
    final uid = _uid.text.trim();
    final raw = await widget.client.account(uid);
    final people = widget.access.canDate
        ? await widget.client.identities([uid])
        : <Map<String, dynamic>>[];
    if (mounted) {
      setState(
        () => _account = {...raw, if (people.isNotEmpty) ...people.first},
      );
    }
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
      'Se aplicará inmediatamente a ${personName(_account)}. Su visibilidad voluntaria no cambiará.',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      await widget.client.suspend(_account!['uid'] as String, value, reason);
      final a = await widget.client.account(_account!['uid'] as String);
      if (mounted) setState(() => _account = {...?_account, ...a});
    }, refresh: false);
  }

  Future<void> _role(String role) async {
    if (!await confirmAction(
      context,
      'Cambiar rol administrativo',
      '${role == 'admin' ? 'Asignar el rol Administrador' : 'Retirar el rol Administrador'} a ${personName(_account)}. La acción quedará auditada y no modifica la acreditación.',
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      await widget.client.role(_account!['uid'] as String, role);
      final a = await widget.client.account(_account!['uid'] as String);
      if (mounted) setState(() => _account = {...?_account, ...a});
    }, refresh: false);
  }

  void _navigate(String page) {
    if (_busy) return;
    setState(() {
      _page = page;
      if ([
        'requests',
        'reports',
        'audit',
        'accounts',
        'roles',
      ].contains(page)) {
        _section = page == 'roles' ? 'accounts' : page;
        _items = [];
        _account = null;
        _notice = null;
        _error = null;
      }
    });
    if (page == 'requests') _load();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AdminTheme.dark,
    child: Builder(builder: _buildPanel),
  );

  Widget _buildPanel(BuildContext context) {
    if (!widget.access.canAdminister) {
      return const Scaffold(
        body: Center(child: Text('Acceso administrativo no autorizado.')),
      );
    }
    final content = switch (_page) {
      'dashboard' => AdminOverview(
        client: widget.client,
        onNavigate: _navigate,
        showAudit: _root,
      ),
      'users' => AdminPeopleView(
        client: widget.client,
        onInspect: (uid) => setState(() {
          _dossierUid = uid;
          _page = 'dossier';
        }),
      ),
      'dossier' when widget.access.canDate && _dossierUid != null => PopScope(
        canPop: false,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _navigate('users');
        },
        child: AdminDossier(
          key: ValueKey(_dossierUid),
          client: widget.client,
          uid: _dossierUid!,
          onBack: () => _navigate('users'),
          onManage: () {
            _navigate('accounts');
            _uid.text = _dossierUid!;
            _lookup();
          },
        ),
      ),
      'roles' =>
        _account == null
            ? Column(
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: AppNotice(_error!, error: true),
                    ),
                  Expanded(
                    child: AdminPeopleView(
                      client: widget.client,
                      selecting: true,
                      onInspect: (uid) {
                        if (_busy) return;
                        _uid.text = uid;
                        _lookup();
                      },
                    ),
                  ),
                ],
              )
            : _operations(context),
      'audit' => AdminHistoryView(
        key: ValueKey(
          'audit:${widget.uid}:${widget.access.role}:${widget.access.status}:${widget.access.suspended}',
        ),
        client: widget.client,
      ),
      'reports' => AdminHistoryView(
        key: ValueKey(
          'reports:${widget.uid}:${widget.access.role}:${widget.access.status}:${widget.access.suspended}',
        ),
        client: widget.client,
        reports: true,
        onInspect: (uid) {
          _navigate('accounts');
          _uid.text = uid;
          _lookup();
        },
        onReview: widget.client.reviewReport,
      ),
      'universities' => AcademicAdminScreen(client: widget.client),
      'careers' || 'interests' => CatalogAdminScreen(
        key: ValueKey(_page),
        client: widget.client,
        access: widget.access,
        kind: _page,
        embedded: true,
      ),
      'settings' => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SectionHeading(
            'Tu espacio de administración',
            icon: Icons.settings_outlined,
          ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'La verificación, la suspensión y los roles se validan en el servidor. Los documentos privados se muestran temporalmente y no forman parte del perfil público.',
              ),
            ),
          ),
          Text(
            _root
                ? 'Rol actual · Superadministrador'
                : 'Rol actual · Administrador',
          ),
          const SizedBox(height: 24),
          widget.logout,
        ],
      ),
      _ => _operations(context),
    };
    return AdminShell(
      root: _root,
      selected: _page == 'dossier' ? 'users' : _page,
      catalogsAllowed: widget.access.canDate,
      onSelected: _navigate,
      logout: widget.logout,
      onDating: widget.onDating,
      child: content,
    );
  }

  Widget _operations(BuildContext context) {
    if (!widget.access.canAdminister) {
      return const Scaffold(
        body: Center(child: Text('Acceso administrativo no autorizado.')),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
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
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final selected = await showDialog<String>(
                            context: context,
                            builder: (ctx) => Dialog(
                              child: SizedBox(
                                width: 1000,
                                height: 650,
                                child: AdminPeopleView(
                                  client: widget.client,
                                  selecting: true,
                                  onInspect: (uid) => Navigator.pop(ctx, uid),
                                ),
                              ),
                            ),
                          );
                          if (selected != null && mounted) {
                            _uid.text = selected;
                            _lookup();
                          }
                        },
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('Seleccionar persona'),
                ),
                if (_account != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            personName(_account),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (_account!['email'] != null)
                            Text(_account!['email'] as String),
                          Text(
                            'Rol: ${adminRoles[_account!['role']] ?? 'No disponible'}',
                          ),
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
                            if (_root &&
                                widget.access.canDate &&
                                _account!['role'] != 'superadmin')
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

  Widget _card(Map<String, dynamic> item) {
    final student = item['student'] as Map<String, dynamic>? ?? const {};
    final reviewer = item['reviewer'] as Map<String, dynamic>? ?? const {};
    final reviewerName = item['reviewedBy'] == 'authorized_operator'
        ? 'Operador autorizado'
        : item['reviewedBy'] == null
        ? 'Responsable no disponible'
        : personName(reviewer);
    final academic = [
      item['universityName'],
      item['campusName'],
      student['career'],
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AdminIdentity(person: student),
                StatusPill(
                  statusLabel(item['status'] as String?),
                  positive: item['status'] == 'approved',
                ),
              ],
            ),
            if (academic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(academic),
              ),
            const SizedBox(height: 12),
            Text('Enviada · ${displayDate(item['createdAt'])}'),
            if (item['resolvedAt'] != null)
              Text(
                'Resuelta · ${displayDate(item['resolvedAt'])} · $reviewerName',
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
          ],
        ),
      ),
    );
  }
}
