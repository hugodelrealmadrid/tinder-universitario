import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

String createAudioObjectUrl(Uint8List bytes, String? mime) {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mime ?? 'audio/mpeg'),
  );
  return web.URL.createObjectURL(blob);
}

void revokeAudioObjectUrl(String url) => web.URL.revokeObjectURL(url);
