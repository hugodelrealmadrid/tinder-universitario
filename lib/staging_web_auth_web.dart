import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:firebase_core/firebase_core.dart';

/// Connect Auth before FlutterFire waits for persisted credentials to load.
Future<void> initializeStagingWebAuth(FirebaseOptions options) async {
  const sdk = 'https://www.gstatic.com/firebasejs/12.19.0';
  final core = await importModule('$sdk/firebase-app.js'.toJS).toDart;
  final auth = await importModule('$sdk/firebase-auth.js'.toJS).toDart;
  final app = core.callMethod<JSObject>(
    'initializeApp'.toJS,
    options.asMap.jsify(),
  );
  JSAny export(String name) => auth.getProperty<JSAny>(name.toJS);
  // Match FlutterFire's dependencies so its later initialization reuses Auth.
  final instance = auth.callMethod<JSObject>(
    'initializeAuth'.toJS,
    app,
    {
      'errorMap': export('debugErrorMap'),
      'persistence': [
        export('indexedDBLocalPersistence'),
        export('browserLocalPersistence'),
        export('browserSessionPersistence'),
      ],
      'popupRedirectResolver': export('browserPopupRedirectResolver'),
    }.jsify(),
  );
  auth.callMethod<JSAny?>(
    'connectAuthEmulator'.toJS,
    instance,
    'http://127.0.0.1:9399'.toJS,
  );
  await auth
      .callMethod<JSPromise<JSAny?>>(
        'setPersistence'.toJS,
        instance,
        auth.getProperty<JSAny>('browserSessionPersistence'.toJS),
      )
      .toDart;
}
