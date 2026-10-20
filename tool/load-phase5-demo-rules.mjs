import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
const env=await initializeTestEnvironment({projectId:'demo-tinder-universitario',firestore:{host:'127.0.0.1',port:8088,rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')},storage:{host:'127.0.0.1',port:9198,rules:await readFile(new URL('../storage.rules',import.meta.url),'utf8')}});await env.cleanup();console.log('Reglas estrictas cargadas solo en emuladores demo.');
