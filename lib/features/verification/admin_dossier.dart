import 'package:flutter/material.dart';
import '../../widgets/app_ui.dart';
import 'admin_theme.dart';
import 'admin_dossier_photo.dart';
import 'admin_dossier_history.dart';
import 'admin_visual.dart' show StatusPill;
import 'audit_presentation.dart';
import 'backend_client.dart';
import 'university_verification_screen.dart' show statusLabel;

class AdminDossier extends StatefulWidget {
  const AdminDossier({
    super.key,
    required this.client,
    required this.uid,
    required this.onBack,
    required this.onManage,
  });

  final VerificationClient client;
  final String uid;
  final VoidCallback onBack, onManage;

  @override
  State<AdminDossier> createState() => _AdminDossierState();
}

class _AdminDossierState extends State<AdminDossier> {
  late Future<Map<String, dynamic>> _data = widget.client.administrationDossier(
    widget.uid,
  );

  void _reload() => setState(() {
    _data = widget.client.administrationDossier(widget.uid);
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _data,
    builder: (context, snapshot) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
            label: const Text('Volver a usuarios'),
          ),
        ),
        Text(
          'Expediente individual',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        if (snapshot.connectionState != ConnectionState.done)
          const LinearProgressIndicator(semanticsLabel: 'Cargando expediente')
        else if (snapshot.hasError) ...[
          AppNotice(verificationError(snapshot.error!), error: true),
          TextButton(onPressed: _reload, child: const Text('Reintentar')),
        ] else if (snapshot.hasData)
          _content(context, snapshot.data!),
      ],
    ),
  );

  Widget _content(BuildContext context, Map<String, dynamic> data) {
    final profile = Map<String, dynamic>.from(data['profile'] as Map);
    final photos =
        (profile['photoPaths'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final activity = data['activity'] as Map;
    final status = profile['verificationStatus'] as String?;
    final account = switch (profile['suspended']) {
      true => 'Suspendida',
      false => 'Sin suspensión',
      _ => 'Estado de cuenta no disponible',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF38204D), Color(0xFF191321), Color(0xFF2F183C)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AdminTheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 18,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (photos.isNotEmpty)
                  AdminDossierPhoto(
                    key: ValueKey(photos.first),
                    path: photos.first,
                    load: widget.client.administrationPhoto,
                    label: 'Foto principal',
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXPEDIENTE · COMUNIDAD',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      personName(profile),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(profile['email'] as String? ?? 'Correo no disponible'),
                    if (profile['age'] != null) Text('${profile['age']} años'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusPill(
                          adminRoles[profile['role']] ?? 'Rol no disponible',
                        ),
                        StatusPill(
                          account,
                          positive: profile['suspended'] == false,
                        ),
                        StatusPill(
                          statusLabel(status),
                          positive: status == 'approved',
                        ),
                      ],
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: widget.onManage,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Gestionar cuenta'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'Galería de fotografías',
          icon: Icons.photo_library_outlined,
          child: photos.isEmpty
              ? const Text('El usuario todavía no tiene fotografías.')
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (index, path) in photos.skip(1).indexed)
                      AdminDossierPhoto(
                        key: ValueKey(path),
                        path: path,
                        load: widget.client.administrationPhoto,
                        label: 'Foto ${index + 2}',
                      ),
                    if (photos.length == 1)
                      const Text('Solo hay una foto, visible en la cabecera.'),
                  ],
                ),
        ),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 850
                ? 4
                : box.maxWidth >= 300
                ? 2
                : 1;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in [
                  ('Likes enviados', 'sent', Icons.send_outlined),
                  ('Likes recibidos', 'received', Icons.favorite_border),
                  ('Matches', 'matches', Icons.people_outline),
                  (
                    'Reportes recibidos',
                    'reportsReceived',
                    Icons.flag_outlined,
                  ),
                ])
                  SizedBox(
                    width: (box.maxWidth - 10 * (columns - 1)) / columns,
                    child: _Panel(
                      title: item.$1,
                      icon: item.$3,
                      child: Text(
                        '${activity[item.$2] ?? 'No disponible'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth >= 760
                ? (box.maxWidth - 12) / 2
                : box.maxWidth;
            return Wrap(
              spacing: 12,
              children: [
                for (final panel in [
                  _Panel(
                    title: 'Perfil y datos',
                    icon: Icons.person_outline,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _line(
                          'Universidad declarada',
                          profile['university'] ?? 'Sin afiliación registrada',
                        ),
                        if (profile['campus'] != null)
                          _line('Sede', profile['campus']),
                        if (profile['university'] != null)
                          _line(
                            'Universidad acreditada',
                            profile['accreditedUniversity'] ??
                                (status == 'pending'
                                    ? 'Pendiente de revisión'
                                    : 'Sin constancia de institución'),
                          ),
                        _line('Carrera', profile['career'] ?? 'No disponible'),
                        _line('Registro', adminDate(profile['registeredAt'])),
                        _line(
                          'Último inicio de sesión',
                          adminDate(profile['lastSignInAt']),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final interest in profile['interests'] as List)
                              Chip(label: Text(interest as String)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Panel(
                    title: 'Estado y actividad',
                    icon: Icons.monitor_heart_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _line('Acreditación', statusLabel(status)),
                        _line('Cuenta', account),
                        _line('Mensajes totales', activity['messages']),
                        _line('Conversaciones activas', activity['active']),
                        if (activity['complete'] != true)
                          const Text(
                            'El total no está disponible. Consultá las conversaciones por página.',
                            style: TextStyle(color: AdminTheme.muted),
                          ),
                      ],
                    ),
                  ),
                ])
                  SizedBox(width: width, child: panel),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'Relaciones e historial',
          icon: Icons.timeline,
          child: AdminDossierHistory(
            key: ValueKey(widget.uid),
            uid: widget.uid,
            client: widget.client,
            canReadAudit: data['audit'] != null,
          ),
        ),
      ],
    );
  }

  Widget _line(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label · ',
            style: const TextStyle(color: AdminTheme.muted),
          ),
          TextSpan(text: value?.toString() ?? 'No disponible'),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
