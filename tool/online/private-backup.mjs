import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
export const sha=b=>createHash('sha256').update(b).digest('hex');
export function canonical(v){if(Array.isArray(v))return '['+v.map(canonical).join(',')+']';if(v&&typeof v==='object')return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';return JSON.stringify(v);}
const shell='powershell.exe';
function crypt(bytes,mode){
 if(process.platform!=='win32')throw Error('windows-dpapi-required');
 const command=`Add-Type -AssemblyName System.Security; $m=New-Object System.IO.MemoryStream; [Console]::OpenStandardInput().CopyTo($m); $r=[System.Security.Cryptography.ProtectedData]::${mode}($m.ToArray(),[Text.Encoding]::UTF8.GetBytes('TinderUniversitarioBackup/v1'),[System.Security.Cryptography.DataProtectionScope]::CurrentUser); [Console]::OpenStandardOutput().Write($r,0,$r.Length)`;
 return execFileSync(shell,['-NoProfile','-NonInteractive','-Command',command],{input:bytes,maxBuffer:128*1024*1024,windowsHide:true,stdio:['pipe','pipe','pipe']});
}
export function privateDirectory(path){
 mkdirSync(path,{recursive:true});
 execFileSync(shell,['-NoProfile','-NonInteractive','-Command',"$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value; & icacls.exe $env:TINDER_PRIVATE_DIR /inheritance:r /grant:r ('*'+$sid+':(OI)(CI)F') '*S-1-5-18:(OI)(CI)F' | Out-Null; if($LASTEXITCODE -ne 0){exit 1}"],{env:{...process.env,TINDER_PRIVATE_DIR:path},windowsHide:true,stdio:'pipe'});
}
export function saveEncrypted(file,value){const plain=Buffer.from(JSON.stringify(value)),cipher=crypt(plain,'Protect');writeFileSync(file,cipher,{flag:'wx'});const recovered=crypt(readFileSync(file),'Unprotect');if(sha(plain)!==sha(recovered))throw Error('backup-roundtrip-failed');return {cipherSha256:sha(cipher),payloadSha256:sha(plain)};}
export function loadEncrypted(file){return JSON.parse(crypt(readFileSync(file),'Unprotect').toString('utf8'));}
