// SDK oficial sin wrappers demo. Precarga externa para evitar scripts inline.
import * as core from '/firebase-sdk/firebase-app.js';
import * as auth from '/firebase-sdk/firebase-auth.js';
import * as firestore from '/firebase-sdk/firebase-firestore.js';
import * as pipelines from '/firebase-sdk/firebase-firestore-pipelines.js';
import * as storage from '/firebase-sdk/firebase-storage.js';
window.firebase_core=core;
window.firebase_auth=auth;
window.firebase_firestore=firestore;
window.firebase_firestore_pipelines=pipelines;
window.firebase_storage=storage;
const script=document.createElement('script');script.src='/flutter_bootstrap.js';document.body.appendChild(script);
