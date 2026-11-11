import 'package:web/web.dart' as web;

String? consumeNotificationLink() {
  final uri = Uri.base;
  final parameters = Map<String, String>.from(uri.queryParameters);
  final notice = parameters.remove('notice');
  if (notice != null) {
    final cleaned = uri.replace(queryParameters: parameters);
    web.window.history.replaceState(null, '', cleaned.toString());
  }
  return notice;
}
