import {execFileSync} from 'node:child_process';
import {emulatorServices} from '../backend/emulator.mjs';
import {programs,universities,verifiedOn} from './bolivia-academic-catalog.mjs';
if(process.argv[2]!=='--local-only'||execFileSync('git',['branch','--show-current'],{encoding:'utf8'}).trim()!=='codex/ligo')throw Error('Se requiere codex/ligo y --local-only.');
const {db}=await emulatorServices('demo-ligo-staging',{auth:9399,firestore:8288,storage:9498,hub:4420});
try{
 await db.runTransaction(async tx=>{
  const writes=new Map();
  for(const [id,name] of Object.entries(programs))writes.set('careers/'+id,{name,isActive:true,revision:1});
  for(const [id,name,abbreviation,campuses] of universities){
   const root='universities/'+id;
   writes.set(root,{name,abbreviation,countryCode:'BO',city:campuses[0][2],directory:true,isActive:true,revision:1});
   for(const [campusId,campus,city,source,ids] of campuses){
    const path=root+'/campuses/'+campusId;
    writes.set(path,{name:campus,city,source,verifiedOn,isActive:true,revision:1});
    for(const career of ids)writes.set(path+'/offerings/'+career,{name:programs[career],source,verifiedOn,isActive:true,revision:1});
   }
  }
  const refs=[...writes.keys()].map(path=>db.doc(path));
  const existing=await tx.getAll(...refs);
  for(const doc of existing){
    const requested=writes.get(doc.ref.path);
    if(doc.exists&&doc.data().name!==requested.name&&doc.ref.path!=='universities/univalle')throw Error('Colisión de catálogo: '+doc.ref.path);
  }
  for(const doc of existing){
    const requested=writes.get(doc.ref.path);
    if(!doc.exists)tx.create(doc.ref,requested);
    else if(requested.directory&&!doc.data().directory)tx.update(doc.ref,{directory:true,abbreviation:requested.abbreviation});
  }
  tx.set(db.doc('platformSettings/academic'),{campusRegistrationEnabled:true},{merge:true});
 });
 console.log('Catálogo boliviano inicial instalado en staging local.');
}finally{await db.terminate();}
