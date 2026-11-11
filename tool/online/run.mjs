import {provisionalBootstrap} from './provisional-bootstrap.mjs';
import {loadEncrypted,saveEncrypted,canonical} from './private-backup.mjs';
import {buildPlan} from './migration-plan.mjs';
import {verifiedBackup,migrate,revoke,bootstrap} from './operator.mjs';
import {validateMedia} from '../backend/media-validation.mjs';
import {readFileSync,existsSync} from 'node:fs';
const [action,dir,...flags]=process.argv.slice(2);
try{
 if(!['plan','migrate','revoke','bootstrap','bootstrap-provisional'].includes(action)||!dir)throw Error('use-plan-and-verified-backup-directory');
 const {data}=verifiedBackup(dir);
 if(action==='plan'){
  const p=buildPlan(data);for(const photo of p.photos){const f=data.storage.files.find(f=>f.metadata.name===photo.source&&f.metadata.generation===photo.sourceGeneration);await validateMedia(Buffer.from(f.bytesBase64,'base64'),photo.mime);}
  if(!existsSync(dir+'/migration-plan-v1.dpapi'))saveEncrypted(dir+'/migration-plan-v1.dpapi',p);
  console.log(JSON.stringify({ready:true,preserved:p.preserved,photos:p.photos.length,grants:0}));
 }else{
  const options={apply:flags.includes('--apply-existing-project'),maintenance:flags.includes('--maintenance-confirmed')};
  const plan=loadEncrypted(dir+'/migration-plan-v1.dpapi');if(canonical(plan)!==canonical(buildPlan(data)))throw Error('plan-revalidation-required');
  if(action==='bootstrap'||action==='bootstrap-provisional'){const cf=flags.find(f=>f.startsWith('--confirmation-file='))?.slice('--confirmation-file='.length);if(!cf)throw Error('confirmed-account-file-required');const c=JSON.parse(readFileSync(cf,'utf8'));console.log(JSON.stringify(await (action==='bootstrap'?bootstrap:provisionalBootstrap)({...c,...options,exceptionConfirmed:flags.includes('--provisional-exception-confirmed'),bucket:plan.bucket})));}
  else console.log(JSON.stringify(await (action==='migrate'?migrate({plan,backup:data,...options}):revoke({plan,...options}))));
 }
}catch(e){console.error(JSON.stringify({ready:false,code:/^[a-z0-9-]+$/.test(e.message)?e.message:'operator-failed-no-sensitive-details'}));process.exitCode=1;}
