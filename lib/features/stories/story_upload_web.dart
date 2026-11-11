import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

Future<http.Response> storyBrowserUpload(
  Uri uri,
  Map<String, String> headers,
  Uint8List bytes,
  void Function(double) progress,
) {
  final completion = Completer<http.Response>();
  final xhr = web.XMLHttpRequest()
    ..open('POST', uri.toString())
    ..timeout = 60000;
  headers.forEach((name, value) => xhr.setRequestHeader(name, value));
  void failed(web.Event _) {
    if (!completion.isCompleted) {
      completion.completeError(http.ClientException('Upload interrupted', uri));
    }
  }

  xhr.upload.onprogress = ((web.ProgressEvent event) {
    if (event.lengthComputable && event.total > 0) {
      progress(event.loaded / event.total);
    }
  }).toJS;
  xhr.onload = ((web.Event _) {
    completion.complete(http.Response(xhr.responseText, xhr.status));
  }).toJS;
  xhr.onerror = failed.toJS;
  xhr.ontimeout = failed.toJS;
  xhr.onabort = failed.toJS;
  xhr.send(bytes.toJS);
  return completion.future.whenComplete(() {
    xhr.upload.onprogress = null;
    xhr.onload = null;
    xhr.onerror = null;
    xhr.ontimeout = null;
    xhr.onabort = null;
  });
}
