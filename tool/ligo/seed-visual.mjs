import {readFile} from 'node:fs/promises';import {Timestamp} from 'firebase-admin/firestore';import {emulatorServices} from '../backend/emulator.mjs';import {VerificationBackend} from '../backend/verification.mjs';import {uploadPhoto} from '../backend/profile-media.mjs';
if(process.argv[2]!=='--create-fictitious-only')throw Error('Se requiere --create-fictitious-only');
const s=await emulatorServices('demo-ligo-staging',{auth:9399,firestore:8288,storage:9498,hub:4420});const b=new VerificationBackend(s);const stamp=Timestamp.now();
for(const [uid,name,gender,image,birth]of [['ligo_visual_ana','Ana','femenino','ana-ficticia.png','2002-04-17'],['ligo_visual_bob','Bob','masculino','bob-ficticio.png','2001-08-09']]){
 if((await s.db.doc('users/'+uid).get()).exists)throw Error('Fixture ya existe: no se sobrescribe '+uid);
 await s.auth.createUser({uid,email:uid+'@ligo.test',emailVerified:true,password:'Ligo-staging-2026!'});
 await s.db.doc('accountAccess/'+uid).create({role:'user',verificationStatus:'approved',suspended:false,latestRequestId:null,createdAt:stamp,updatedAt:stamp});
 const path='profile_photos/'+uid+'/visual_portrait';await uploadPhoto(b,uid,path,await readFile(new URL('../../staging/fixtures/'+image,import.meta.url)),'image/png');
 const profile={firstName:name,lastName:'Ficticio',email:uid+'@ligo.test',birthDate:Timestamp.fromDate(new Date(birth)),gender,description:'Perfil ficticio del staging. Me gustan la música, los planes al aire libre y las buenas conversaciones.',careerId:'career_a',universityId:'uni_a',interestIds:['fixture_interest'],photoUrls:[path],mainPhotoUrl:path,role:'user',isActive:true,datingAllowed:true,createdAt:stamp,updatedAt:stamp};await s.db.doc('users/'+uid).create(profile);
 const now=new Date(),date=new Date(birth),age=now.getFullYear()-date.getFullYear()-(now.getMonth()<date.getMonth()||(now.getMonth()===date.getMonth()&&now.getDate()<date.getDate())?1:0);
 const card={firstName:name,age,gender,description:profile.description,careerId:profile.careerId,universityId:profile.universityId,interestIds:profile.interestIds,mainPhotoUrl:path,isActive:true,updatedAt:stamp};await s.db.doc('discoveryIndex/'+uid).create({isActive:true,updatedAt:stamp});await s.db.doc('discoveryCards/'+uid).create(card);await s.db.doc('matchProfiles/'+uid).create({...card,photoUrls:[path]});await s.db.doc('preferences/'+uid).create({minAge:18,maxAge:100,preferredGender:'ambos',careerIds:[],updatedAt:stamp});
}
console.log('Dos perfiles ficticios nuevos creados solo en staging. Ningún documento anterior modificado.');await s.db.terminate();
