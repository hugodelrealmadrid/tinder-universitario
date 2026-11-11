/// No acepta HTTP externo ni otros buckets/rutas. Nunca devuelve el token.
String? demoPhotoObjectPath(String value, {bool demoMode = false}) {
  if (!demoMode) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.userInfo.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      uri.port != 9198 ||
      uri.pathSegments.length != 5 ||
      uri.pathSegments[0] != 'v0' ||
      uri.pathSegments[1] != 'b' ||
      uri.pathSegments[2] != 'demo-tinder-universitario.appspot.com' ||
      uri.pathSegments[3] != 'o' ||
      uri.queryParameters['alt'] != 'media') {
    return null;
  }
  final path = uri.pathSegments[4];
  return RegExp(
        r'^profile_photos/[A-Za-z0-9_-]{1,128}/[A-Za-z0-9_-]+$',
      ).hasMatch(path)
      ? path
      : null;
}
