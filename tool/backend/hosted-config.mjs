// Validación pura: nunca busca credenciales ni inicia Firebase.
export function hostedConfig(env){
 const fail=()=>{throw new Error('hosted-configuration-required');};
 if(!['development','production'].includes(env.APP_ENV))fail();
 if(Object.keys(env).some(k=>(k.endsWith('_EMULATOR_HOST')||k==='FIREBASE_EMULATOR_HUB')&&env[k]))fail();
 if(env.GOOGLE_APPLICATION_CREDENTIALS||env.FIREBASE_CONFIG)fail(); // Solo identidad de servicio, sin claves JSON.
 const project=env.TINDER_PROJECT_ID,bucket=env.TINDER_STORAGE_BUCKET;
 if(!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(project??'')||project.startsWith('demo-')||project!==env.GOOGLE_CLOUD_PROJECT)fail();
 if(!/^[a-z0-9][a-z0-9._-]{2,221}$/.test(bucket??'')||bucket.startsWith('demo-'))fail();
 const origins=(env.TINDER_WEB_ORIGINS??'').split(',').map(v=>v.trim());
 if(!origins.length||origins.some(v=>{try{const u=new URL(v);return u.protocol!=='https:'||u.origin!==v||u.hostname==='localhost'||u.hostname==='127.0.0.1'||u.hostname.endsWith('.example');}catch{return true;}}))fail();
 const port=Number(env.PORT??8080);if(!Number.isInteger(port)||port<1||port>65535)fail();
 return Object.freeze({project,bucket,origins,port});
}
