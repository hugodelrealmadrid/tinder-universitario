import {hostedServices} from './hosted-services.mjs';
import {VerificationBackend} from './verification.mjs';
import {cleanupMedia} from './media-cleanup.mjs';
if(!process.env.CLOUD_RUN_JOB||process.env.K_SERVICE)throw new Error('cleanup-job-required');
const services=hostedServices();
try{const backend=new VerificationBackend(services);await backend.cleanupDue();await cleanupMedia(backend);}
finally{await services.close();}
