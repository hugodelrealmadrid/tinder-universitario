import {Timestamp} from 'firebase-admin/firestore';import {emulatorServices} from '../backend/emulator.mjs';
const s=await emulatorServices('demo-ligo-staging',{auth:9399,firestore:8288,storage:9498,hub:4420});
if((await s.db.doc('platformSettings/academic').get()).exists)throw Error('staging-not-empty-no-overwrite');
const stamp=Timestamp.now();
for(const [uid,role]of [['ligo_root','superadmin'],['ligo_admin','admin'],['ligo_student','user']]){
 await s.auth.createUser({uid,email:uid+'@ligo.test',emailVerified:true,password:'Ligo-staging-2026!'});
 await s.db.doc('accountAccess/'+uid).create({role,verificationStatus:'approved',suspended:false,latestRequestId:null,createdAt:stamp,updatedAt:stamp});
 await s.db.doc('users/'+uid).create({firstName:uid==='ligo_root'?'Superadmin ficticio':uid==='ligo_admin'?'Admin ficticio':'Estudiante ficticio',lastName:'Staging',email:uid+'@ligo.test',birthDate:Timestamp.fromDate(new Date('2000-01-01')),gender:'femenino',description:'Cuenta ficticia exclusiva del staging local',careerId:'career_a',universityId:'uni_a',interestIds:[],photoUrls:[],mainPhotoUrl:null,isActive:false,datingAllowed:true,role:'user',createdAt:stamp,updatedAt:stamp});
}
await s.db.doc('administration/roles').create({superadminIds:['ligo_root']});
await s.db.doc('universities/uni_a').create({name:'Universidad ficticia A',countryCode:'BO',city:'Ciudad de prueba A',isActive:true,revision:1});await s.db.doc('universities/uni_b').create({name:'Universidad ficticia B',countryCode:'PE',city:'Ciudad de prueba B',isActive:true,revision:1});
await s.db.doc('careers/career_a').create({name:'Sistemas A',universityId:'uni_a',isActive:true,revision:1});await s.db.doc('careers/career_b').create({name:'Diseño B',universityId:'uni_b',isActive:true,revision:1});await s.db.doc('interests/fixture_interest').create({name:'Lectura ficticia',isActive:true,revision:1});
await s.db.doc('platformSettings/academic').create({multiUniversityEnabled:true,legacyBefore:stamp});
console.log('Solo fixtures creados en demo-ligo-staging: ligo_root, ligo_admin, ligo_student @ligo.test.');await s.db.terminate();
