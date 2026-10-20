import './browser.js';
import * as core from './firebase/firebase-app.js';
import * as auth from './firebase/firebase-auth.js';
import * as firestore from './firebase/firebase-firestore.js';
import * as pipelines from './firebase/firebase-firestore-pipelines.js';
import * as storage from './firebase/firebase-storage.js';
import {demoAuthModule} from './auth-demo.js';
if(navigator.serviceWorker?.controller) throw new Error('Abre /__demo/start.html para quitar el service worker anterior.');
if(new URL(location.href).searchParams.get('syntheticMic')==='1') {
  const {installSyntheticMic}=await import('./synthetic-mic.js');installSyntheticMic();
}
window.firebase_core=core;
window.firebase_auth=demoAuthModule(auth);
window.firebase_firestore=firestore;
window.firebase_firestore_pipelines=pipelines;
window.firebase_storage=storage;
const flutter=document.createElement('script');
flutter.src='/flutter_bootstrap.js';
document.body.appendChild(flutter);
