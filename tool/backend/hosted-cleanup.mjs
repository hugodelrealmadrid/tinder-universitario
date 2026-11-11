import {Notifications} from './notifications.mjs';
import {hostedServices} from './hosted-services.mjs';
import {VerificationBackend} from './verification.mjs';
import {runCleanupTask} from './cleanup-task.mjs';
if(!process.env.CLOUD_RUN_JOB||process.env.K_SERVICE)throw new Error('cleanup-job-required');
const services=hostedServices();
try{
 const notifications=process.env.LIGO_NOTIFICATIONS_ENABLED==='true'?new Notifications(services):null;
 const result=await runCleanupTask(new VerificationBackend({...services,notifications}),process.env.TINDER_CLEANUP_SCOPE??'all',{
  storiesEnabled:process.env.LIGO_STORIES_CLEANUP_ENABLED==='true',
 });
 if(result){
  console.log(JSON.stringify({task:'story-cleanup',...result}));
  if(result.failed)process.exitCode=1;
 }
}
finally{await services.close();}
