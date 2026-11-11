import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<http.Response>? storyBrowserUpload(
  Uri uri,
  Map<String, String> headers,
  Uint8List bytes,
  void Function(double) progress,
) => null;
