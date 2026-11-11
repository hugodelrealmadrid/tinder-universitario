import {createServer} from 'node:http';
import {hostedServices} from './hosted-services.mjs';
import {requestHandler} from './http-handler.mjs';
const services=hostedServices();
const server=createServer(requestHandler(services,{
 origins:services.config.origins,
 operationsEnabled:process.env.TINDER_PRE_CUTOVER!=='true',
 publicRegistrationEnabled:process.env.LIGO_PUBLIC_REGISTRATION_ENABLED==='true',
 notificationsEnabled:process.env.LIGO_NOTIFICATIONS_ENABLED==='true',
 storiesEnabled:process.env.LIGO_STORIES_ENABLED==='true',
}));
server.requestTimeout=60000;server.headersTimeout=15000;server.keepAliveTimeout=5000;
server.listen(services.config.port,'0.0.0.0');
process.on('SIGTERM',()=>server.close(()=>services.close().then(()=>process.exit(0))));
// La limpieza se ejecuta en un Job autenticado; no depende de CPU en reposo.
