import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {programs,universities,verifiedOn} from '../ligo/bolivia-academic-catalog.mjs';
import {verifiedBackup} from './operator.mjs';

const productionIds=new Map([
 ['univalle',['2307e355-9b85-4079-842a-308fab8efb4f','univalle']],
 ['umss',['7faf0476-37f3-4d30-9ad0-3ea0f16a8e09','san simon']],
 ['ucb',['e8af3144-cc9f-4a6a-ae4e-4695445524cc','u catolica']],
]);
const prefix='projects/tinder-universitario/databases/(default)/documents/';

export function planAcademicCatalog(documents){
 const current=new Map(documents.map(doc=>[doc.name.slice(prefix.length),doc]));
 const additions=new Map(), activations=[];
 function add(path,data){
  const old=current.get(path);
  if(!old){additions.set(path,data);return true;}
  if(old.fields?.name?.stringValue!==data.name)throw Error('catalog-name-conflict:'+path);
  return old.fields?.isActive?.booleanValue===true;
 }
 for(const [key,,,campuses] of universities){
  if(!productionIds.has(key))continue;
  const [id,expectedName]=productionIds.get(key),root='universities/'+id;
  const parent=current.get(root);
  if(parent?.fields?.name?.stringValue!==expectedName||parent.fields?.isActive?.booleanValue!==true||!parent.updateTime)throw Error('catalog-parent-conflict:'+id);
  let available=false;
  for(const [site,name,city,source,ids] of campuses){
   const campus=root+'/campuses/'+site;
   if(!add(campus,{name,city,source,verifiedOn,isActive:true,revision:1}))continue;
   for(const career of ids){
    if(!add('careers/'+career,{name:programs[career],isActive:true,revision:1}))continue;
    if(add(campus+'/offerings/'+career,{name:programs[career],source,verifiedOn,isActive:true,revision:1}))available=true;
   }
  }
  if(!available)throw Error('catalog-no-active-offerings:'+id);
  if(parent.fields.directory?.booleanValue!==true)activations.push({path:root,updateTime:parent.updateTime,fields:{directory:true}});
 }
 return {createIfAbsent:[...additions].map(([path,fields])=>({path,fields})),activateAfterVerification:activations};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.length!==3)throw Error('verified-backup-directory-required');
 const {data}=verifiedBackup(process.argv[2]);
 console.log(JSON.stringify(planAcademicCatalog(data.firestore.documents),null,2));
}
