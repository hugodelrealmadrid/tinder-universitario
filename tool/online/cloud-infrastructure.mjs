import {sessionToken} from './read-client.mjs';
import {readFileSync,writeFileSync,mkdirSync,readdirSync,copyFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const project='tinder-universitario',number='208598232745',region='us-east1';
const root='build/cloud-preparation';mkdirSync(root,{recursive:true});
const apiSA=`tinder-api@${project}.iam.gserviceaccount.com`,buildSA=`tinder-builder@${project}.iam.gserviceaccount.com`;
const stage=`${project}-build-source-us-east1`,repo=`projects/${project}/locations/${region}/repositories/tinder`;
const allowed=new Set(['serviceusage.googleapis.com','iam.googleapis.com','cloudresourcemanager.googleapis.com','artifactregistry.googleapis.com','storage.googleapis.com','cloudbuild.googleapis.com','run.googleapis.com']);
async function call(url,method='GET',body,ok404=false){const u=new URL(url);if(u.protocol!=='https:'||!allowed.has(u.hostname))throw Error('host-denied');const token=await sessionToken();const r=await fetch(url,{method,headers:{Authorization:'Bearer '+token,...(body?{'Content-Type':Buffer.isBuffer(body)?'application/gzip':'application/json'}:{})},...(body?{body:Buffer.isBuffer(body)?body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(60000)});const d=await r.json().catch(()=>({}));if(!r.ok&&!(ok404&&r.status===404)){console.error(JSON.stringify({host:u.hostname,path:u.pathname,status:r.status,code:d.error?.status,message:d.error?.message?.replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/g,'[identity]').slice(0,700)}));throw Error('cloud-request-failed');}return {status:r.status,data:d};}
async function bind(getUrl,setUrl,method,bindings){const {data:p}=await call(getUrl,method,method==='POST'?{}:undefined);p.bindings??=[];for(const [role,member] of bindings){let b=p.bindings.find(b=>b.role===role&&!b.condition);if(!b){b={role,members:[]};p.bindings.push(b);}if(!b.members.includes(member))b.members.push(member);}await call(setUrl,'POST',{policy:p});}
async function setup(){
for(const id of ['run.googleapis.com','cloudbuild.googleapis.com','artifactregistry.googleapis.com','iam.googleapis.com']){const {data}=await call(`https://serviceusage.googleapis.com/v1/projects/${number}/services/${id}`);if(data.state!=='ENABLED')throw Error('api-not-enabled');}
for(const id of ['tinder-api','tinder-builder']){const url=`https://iam.googleapis.com/v1/projects/${project}/serviceAccounts/${id}@${project}.iam.gserviceaccount.com`;if((await call(url,'GET',undefined,true)).status===404)await call(`https://iam.googleapis.com/v1/projects/${project}/serviceAccounts`,'POST',{accountId:id,serviceAccount:{displayName:id==='tinder-api'?'Tinder private API runtime':'Tinder isolated image builder'}});}
const repoURL='https://artifactregistry.googleapis.com/v1/'+repo;
if((await call(repoURL,'GET',undefined,true)).status===404){const r=await call(`https://artifactregistry.googleapis.com/v1/projects/${project}/locations/${region}/repositories?repositoryId=tinder`,'POST',{format:'DOCKER',description:'Private Tinder backend images'});console.log(JSON.stringify({repositoryOperation:r.data.name}));}
const bucketURL=`https://storage.googleapis.com/storage/v1/b/${stage}`;
if((await call(bucketURL,'GET',undefined,true)).status===404)await call(`https://storage.googleapis.com/storage/v1/b?project=${project}`,'POST',{name:stage,location:region,storageClass:'STANDARD',iamConfiguration:{uniformBucketLevelAccess:{enabled:true},publicAccessPrevention:'enforced'},lifecycle:{rule:[{action:{type:'Delete'},condition:{age:7}}]}});
await bind(`https://cloudresourcemanager.googleapis.com/v1/projects/${project}:getIamPolicy`,`https://cloudresourcemanager.googleapis.com/v1/projects/${project}:setIamPolicy`,'POST',[
['roles/datastore.user','serviceAccount:'+apiSA],['roles/firebaseauth.viewer','serviceAccount:'+apiSA],['roles/logging.logWriter','serviceAccount:'+buildSA]]);
await bind(repoURL+':getIamPolicy',repoURL+':setIamPolicy','GET',[['roles/artifactregistry.writer','serviceAccount:'+buildSA]]);

// Storage setIamPolicy uses PUT rather than resource-manager POST.
for(const [bucket,role,member]of [[stage,'roles/storage.objectViewer','serviceAccount:'+buildSA],['tinder-universitario.firebasestorage.app','roles/storage.objectUser','serviceAccount:'+apiSA]]){const url=`https://storage.googleapis.com/storage/v1/b/${bucket}/iam`;const {data:p}=await call(url);p.bindings??=[];let b=p.bindings.find(b=>b.role===role&&!b.condition);if(!b){b={role,members:[]};p.bindings.push(b);}if(!b.members.includes(member))b.members.push(member);await call(url,'PUT',p);}
console.log(JSON.stringify({setup:true,apiSA,buildSA,region,stage}));
}
async function build(){
const src=root+'/source';mkdirSync(src+'/tool/backend',{recursive:true});mkdirSync(src+'/deploy',{recursive:true});
const files=['.dockerignore','deploy/Dockerfile','tool/package.json','tool/package-lock.json',...readdirSync('tool/backend').filter(f=>f.endsWith('.mjs')&&!f.endsWith('.test.mjs')&&!['emulator.mjs','server.mjs'].includes(f)).map(f=>'tool/backend/'+f)];
for(const f of files){const bytes=readFileSync(f);if(/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|"private_key"\s*:/.test(bytes.toString()))throw Error('source-secret-marker');copyFileSync(f,src+'/'+f);}
const tar=root+'/source.tgz';execFileSync('tar.exe',['-czf',tar,'-C',src,...files],{stdio:'pipe',windowsHide:true});const bytes=readFileSync(tar),sha=createHash('sha256').update(bytes).digest('hex'),object=`backend/${sha}.tgz`;
const uploaded=await call(`https://storage.googleapis.com/upload/storage/v1/b/${stage}/o?uploadType=media&name=${encodeURIComponent(object)}&ifGenerationMatch=0`,'POST',bytes);
const tag='online-'+sha.slice(0,12),image=`${region}-docker.pkg.dev/${project}/tinder/backend:${tag}`;
const config=JSON.parse(readFileSync('deploy/cloudbuild.json','utf8'));Object.assign(config,{serviceAccount:`projects/${project}/serviceAccounts/${buildSA}`,source:{storageSource:{bucket:stage,object,generation:uploaded.data.generation}},substitutions:{_IMAGE:image},options:{logging:'CLOUD_LOGGING_ONLY',machineType:'E2_MEDIUM',diskSizeGb:100}});
const r=await call(`https://cloudbuild.googleapis.com/v1/projects/${project}/locations/${region}/builds`,'POST',config);const receipt=JSON.stringify({operation:r.data.name,image,sourceSha256:sha,files},null,2);writeFileSync(root+'/build-'+sha.slice(0,12)+'.json',receipt,{flag:'wx'});writeFileSync(root+'/build.json',receipt);console.log(JSON.stringify({operation:r.data.name,image,sourceFiles:files.length,bytes:bytes.length}));
}
async function status(){const state=JSON.parse(readFileSync(root+'/build.json'));const buildId=Buffer.from(state.operation.split('/').at(-1),'base64').toString();const {data:b}=await call(`https://cloudbuild.googleapis.com/v1/projects/${project}/locations/${region}/builds/${buildId}`);const op={done:['SUCCESS','FAILURE','INTERNAL_ERROR','TIMEOUT','CANCELLED','EXPIRED'].includes(b.status)};console.log(JSON.stringify({done:op.done??false,status:b?.status,error:op.error,buildId:b?.id,logUrl:b?.logUrl,images:b?.results?.images}));if(op.done&&b?.status==='SUCCESS')writeFileSync(root+'/validated-image.json',JSON.stringify({image:state.image,digest:b.results.images[0].digest,buildId:b.id,validated:true},null,2));}
async function deploy(){
 const image=JSON.parse(readFileSync(root+'/validated-image.json'));if(!image.validated)throw Error('linux-validation-required');
 const resource=`projects/${project}/locations/${region}/services/tinder-api`,url='https://run.googleapis.com/v2/'+resource;
 if((await call(url,'GET',undefined,true)).status!==404)throw Error('existing-service-review-required');
 const env={APP_ENV:'production',GOOGLE_CLOUD_PROJECT:project,TINDER_PROJECT_ID:project,TINDER_STORAGE_BUCKET:'tinder-universitario.firebasestorage.app',TINDER_WEB_ORIGINS:'https://tinder-universitario.web.app,https://tinder-universitario.firebaseapp.com',TINDER_PRE_CUTOVER:'true'};
 const body={description:'Private Firebase API; data operations locked until authorized cutover',ingress:'INGRESS_TRAFFIC_ALL',scaling:{minInstanceCount:0,maxInstanceCount:1},template:{serviceAccount:apiSA,scaling:{minInstanceCount:0,maxInstanceCount:1},maxInstanceRequestConcurrency:8,timeout:'60s',containers:[{image:image.image.split(':').slice(0,-1).join(':')+'@'+image.digest,ports:[{containerPort:8080}],env:Object.entries(env).map(([name,value])=>({name,value})),resources:{limits:{cpu:'1',memory:'1Gi'},cpuIdle:true,startupCpuBoost:false}}]}};
 const r=await call(`https://run.googleapis.com/v2/projects/${project}/locations/${region}/services?serviceId=tinder-api`,'POST',body);
 writeFileSync(root+'/deployment.json',JSON.stringify({resource,operation:r.data.name,image,preCutover:true},null,2));console.log(JSON.stringify({deploymentOperation:r.data.name}));
}
async function serviceStatus(){
 const state=JSON.parse(readFileSync(root+'/deployment.json'));const url='https://run.googleapis.com/v2/'+state.resource;
 const {data:d}=await call(url);console.log(JSON.stringify({url:d.uri,ready:d.terminalCondition?.state,reason:d.terminalCondition?.reason,message:d.terminalCondition?.message,min:d.scaling?.minInstanceCount??0,max:d.scaling?.maxInstanceCount,concurrency:d.template?.maxInstanceRequestConcurrency,revision:d.latestReadyRevision}));
 if(d.terminalCondition?.state==='CONDITION_SUCCEEDED'){
 await bind(url+':getIamPolicy',url+':setIamPolicy','GET',[['roles/run.invoker','allUsers']]);
 writeFileSync(root+'/backend-ready.json',JSON.stringify({url:d.uri,image:state.image,preCutover:true,maxInstances:d.scaling?.maxInstanceCount,concurrency:d.template?.maxInstanceRequestConcurrency},null,2));
 }
}
const action=process.argv[2];if(!process.argv.includes('--authorized-infrastructure-only'))throw Error('explicit-infrastructure-flag-required');
try{if(action==='setup')await setup();else if(action==='build')await build();else if(action==='status')await status();else if(action==='deploy')await deploy();else if(action==='service-status')await serviceStatus();else throw Error('unknown-action');}catch(e){console.error(e.message==='cloud-request-failed'?e.message:'infrastructure-step-failed');process.exitCode=1;}
