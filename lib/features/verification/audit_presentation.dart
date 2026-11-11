import '../safety/safety_models.dart' show ReportReasons;

/// Catálogo central de eventos: las etiquetas no alteran el registro original.
const auditActions = <String, String>{
  'academic_create': 'Creó un elemento académico',
  'academic_save': 'Actualizó un elemento académico',
  'academic_deactivate': 'Desactivó un elemento académico',
  'profile_photo_viewed': 'Consultó una fotografía de perfil',
  'verification_approved': 'Aprobó la verificación',
  'verification_rejected': 'Rechazó la verificación',
  'role_admin': 'Asignó el rol Administrador',
  'role_user': 'Retiró el rol Administrador',
  'role_superadmin': 'Asignó el rol Superadministrador',
  'suspend': 'Suspendió la cuenta',
  'restore': 'Restableció la cuenta',
  'document_review': 'Consultó un carnet privado',
  'report_reviewed': 'Revisó el reporte',
  'report_dismissed': 'Descartó el reporte',
  'catalog_create': 'Creó un elemento del catálogo',
  'catalog_edit': 'Editó un elemento del catálogo',
  'catalog_activate': 'Activó un elemento del catálogo',
  'catalog_deactivate': 'Desactivó un elemento del catálogo',
  'provisional_superadmin_regularized':
      'Registró la acreditación independiente de administración',
  'provisional_superadmin_bootstrap': 'Autorizó una administración provisional',
  'academic_policy_activation': 'Activó la política multiuniversidad',
};
const adminRoles = {
  'user': 'Estudiante',
  'admin': 'Administrador',
  'superadmin': 'Superadministrador',
};
const reportReasons = ReportReasons.labels;
const reportStatuses = {
  'pending': 'Pendiente',
  'reviewed': 'Revisado',
  'dismissed': 'Descartado',
};
String personName(dynamic person) {
  if (person is Map) {
    final name = person['name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
  }
  return 'Persona no disponible';
}

String eventAction(dynamic code) =>
    auditActions[code] ?? 'Acción histórica sin descripción disponible';
String eventResult(dynamic result) => switch (result) {
  'success' => 'Exitosa',
  'error' || 'failed' => 'Fallida',
  'warning' => 'Con advertencia',
  _ => 'No consignado',
};
String eventDescription(Map<String, dynamic> row) {
  final entity = row['entity'];
  final noun = entity is Map
      ? {
          'universities': 'la universidad',
          'careers': 'la carrera',
          'interests': 'el interés',
        }[entity['kind']]
      : null;
  final verb = {
    'catalog_create': 'Creó',
    'catalog_edit': 'Editó',
    'catalog_activate': 'Activó',
    'catalog_deactivate': 'Desactivó',
  }[row['action']];
  return noun != null && verb != null
      ? '$verb $noun'
      : eventAction(row['action']);
}

String eventSentence(Map<String, dynamic> row) {
  final entity = row['entity'];
  final target = entity is Map
      ? (entity['name'] as String? ?? 'Elemento de catálogo no disponible')
      : personName(row['target']);
  final action = eventDescription(row), code = row['action'];
  if (code is! String || !auditActions.containsKey(code)) {
    return '${personName(row['actor'])} · $action · $target';
  }
  final link = code.startsWith('catalog_')
      ? ''
      : code.startsWith('role_')
      ? ' a'
      : ' de';
  return '${personName(row['actor'])} ${action[0].toLowerCase()}${action.substring(1)}$link $target';
}

String adminDate(dynamic raw) {
  final d = raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
  if (d == null) return 'Fecha no disponible';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
