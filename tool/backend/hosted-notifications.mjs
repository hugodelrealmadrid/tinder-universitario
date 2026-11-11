import {createServer} from 'node:http';
import {Notifications} from './notifications.mjs';
import {hostedServices} from './hosted-services.mjs';

// Deploy this entrypoint only as an IAM-private service.
const services=hostedServices();
const webOrigin=new URL(process.env.LIGO_NOTIFICATION_WEB_ORIGIN??'');
if(webOrigin.protocol!=='https:'||webOrigin.origin!==webOrigin.href.slice(0,-1))throw Error('notification-web-origin');
const worker=new Notifications({...services,webOrigin:webOrigin.origin});
const source='//firestore.googleapis.com/projects/'+services.config.project+'/databases/(default)';
const server=createServer(async(req,res)=>{
 req.resume(); // Firestore sends protobuf. The path is authenticated by Cloud Run IAM.
 const type=req.headers['ce-type'];
 const subject=req.headers['ce-subject'];
 if(req.method!=='POST'||req.url!=='/events'||req.headers['ce-source']!==source||
   !['google.cloud.firestore.document.v1.created','google.cloud.firestore.document.v1.written'].includes(type)||
   typeof subject!=='string'||!subject.startsWith('documents/')){
   res.writeHead(204).end();return;
 }
 try{await worker.event(subject.slice('documents/'.length));res.writeHead(204).end();}
 catch{console.error('notification-event-retry');res.writeHead(503).end();}
});
server.requestTimeout=60000;
server.listen(services.config.port,'0.0.0.0');
process.on('SIGTERM',()=>server.close(()=>services.close().then(()=>process.exit(0))));
