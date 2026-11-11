// Inspección local: no lee Firebase remoto ni imprime material sensible.
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {verifiedBackup} from './operator.mjs';
const backupDir=process.argv[2];if(!backupDir)throw Error('verified-backup-directory-required');
const {data}=verifiedBackup(backupDir),config=JSON.parse(readFileSync('deploy/existing-project.local.json'));
const android=JSON.parse(readFileSync('deploy/existing-project.android.local.json')),native=JSON.parse(readFileSync('android/app/src/production/google-services.json'));
const nativeClient=native.client.find(c=>c.client_info.android_client_info.package_name==='com.example.tinder_universitario');
if(!nativeClient.api_key.some(k=>k.current_key===android.FIREBASE_API_KEY)||nativeClient.client_info.mobilesdk_app_id!==android.FIREBASE_ANDROID_APP_ID||android.FIREBASE_PROJECT_ID!==config.FIREBASE_PROJECT_ID||android.VERIFICATION_BACKEND_URL!==config.VERIFICATION_BACKEND_URL)throw Error('android-native-config-mismatch');
const needles=new Set();const add=s=>{if(typeof s==='string'&&s.length>=12)needles.add(s);};
for(const u of data.auth.users){add(u.email);add(u.localId);add(u.passwordHash);add(u.salt);add(u.rawPassword);}
for(const v of Object.values(data.auth.config.signIn?.hashConfig??{}))add(v);
for(const f of data.storage.files)for(const t of (f.metadata.metadata?.firebaseStorageDownloadTokens??'').split(','))add(t);
const python=String.raw`
import sys,json,os,zipfile,hashlib,re
p=json.load(sys.stdin); needles=[s.encode('utf-8') for s in p['needles']]+[s.encode('utf-16le') for s in p['needles']]
forbidden=['.dpapi','.jks','.keystore','service-account','accounts.json','firebase-export-metadata.json','google-services.json','migration-plan','_demo/','mic-check.html']
pem=re.compile(b'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[A-Za-z0-9+/='+bytes([9,10,13,32])+b']{128,}-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')
assert pem.search(b'-----BEGIN PRIVATE KEY-----'+bytes([10])+b'A'*160+bytes([10])+b'-----END PRIVATE KEY-----')
assert not pem.search(b'-----BEGIN PRIVATE KEY----- -----END PRIVATE KEY-----')
def inspect(name,b):
 if any(x in name.lower() for x in forbidden): raise Exception('unexpected-private-or-demo-file')
 if any(x in b for x in needles): raise Exception('sensitive-content-detected-known-value-in-'+os.path.basename(name))
 # Bibliotecas Android contienen encabezados PEM literales; exigir bloque completo.
 normalized=b.replace(bytes([92,110]),bytes([10])).replace(bytes([92,114]),bytes([13]))
 if pem.search(normalized): raise Exception('sensitive-content-detected-key-marker-in-'+os.path.basename(name))
 return 1
web='build/hosted/production'; count=0; inventory=[]
for root,dirs,files in os.walk(web):
 for file in files:
  path=os.path.join(root,file); rel=os.path.relpath(path,web).replace(chr(92),'/'); b=open(path,'rb').read(); count+=inspect(rel,b);inventory.append({'file':rel,'sha256':hashlib.sha256(b).hexdigest()})
js=open(web+'/main.dart.js','rb').read()
assert p['project'].encode() in js and p['backend'].encode() in js,'web-online-endpoints-missing'
apk='build/app/outputs/flutter-apk/app-production-debug.apk'; acount=0; project=False; backend=False
with zipfile.ZipFile(apk) as z:
 for i in z.infolist():
  if i.is_dir():continue
  b=z.read(i);acount+=inspect(i.filename,b)
  if p['project'].encode() in b or p['project'].encode('utf-16le') in b:project=True
  if p['backend'].encode() in b or p['backend'].encode('utf-16le') in b:backend=True
assert project and backend,'android-online-endpoints-missing'
manifest={'webFiles':count,'apkEntries':acount,'knownPrivateValuesAbsent':True,'noPrivateFiles':True,'realProjectAndBackendFound':True,'apkSha256':hashlib.sha256(open(apk,'rb').read()).hexdigest(),'webFilesSha256':inventory}
json.dump(manifest,open('build/online-readiness/artifact-verification.json','w'),indent=2)
print(json.dumps({k:v for k,v in manifest.items() if k!='webFilesSha256'}))
`;
mkdirSync('build/online-readiness',{recursive:true});
const bundledPython='build/cloud-preparation/sdk/google-cloud-sdk/platform/bundledpython/python.exe';
try{const result=execFileSync(existsSync(bundledPython)?bundledPython:'python',['-c',python],{input:JSON.stringify({needles:[...needles],project:config.FIREBASE_PROJECT_ID,backend:config.VERIFICATION_BACKEND_URL}),maxBuffer:1024*1024,windowsHide:true,stdio:['pipe','pipe','pipe']});process.stdout.write(result);}catch(e){const err=String(e.stderr??'');const code=['unexpected-private-or-demo-file','sensitive-content-detected','web-online-endpoints-missing','android-online-endpoints-missing','SyntaxError','FileNotFoundError'].find(c=>err.includes(c))??'scanner-execution-error';const detail=err.match(/sensitive-content-detected-(?:known-value|key-marker)-in-[A-Za-z0-9_.-]+/)?.[0]??code;console.error('artifact-verification-failed: '+detail+'; no sensitive values printed');process.exitCode=1;}
