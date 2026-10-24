// Entrada local conservada: no inicializa servicios remotos.
import {createServer} from 'node:http';
import {emulatorServices} from './emulator.mjs';
import {VerificationBackend} from './verification.mjs';
import {cleanupMedia} from './media-cleanup.mjs';
import {requestHandler} from './http-handler.mjs';
const services=await emulatorServices(),backend=new VerificationBackend(services);
createServer(requestHandler(services)).listen(7360,'127.0.0.1',()=>console.log('Backend demo: 127.0.0.1:7360; sin credenciales ni recursos remotos.'));
let cleaning=false;
const clean=async()=>{if(cleaning)return;cleaning=true;try{await backend.cleanupDue();await cleanupMedia(backend);}catch{console.error('private-cleanup-retry');}finally{cleaning=false;}};
setInterval(clean,5000).unref();void clean();
