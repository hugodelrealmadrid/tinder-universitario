import {FieldValue} from 'firebase-admin/firestore';
import {AccessError} from './access-error.mjs';
import {assetRef,chatAccess} from './chat-upload.mjs';

const id=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(value);
const need=(ok,code='permission-denied')=>{if(!ok)throw new AccessError(code);};
const stamp=()=>FieldValue.serverTimestamp();

function age(date,now){
 if(typeof date?.toDate!=='function')return NaN;
 const birth=date.toDate(),month=now.getUTCMonth()-birth.getUTCMonth();
 return now.getUTCFullYear()-birth.getUTCFullYear()-(month<0||month===0&&now.getUTCDate()<birth.getUTCDate()?1:0);
}
function complete(profile,years,career){
 return profile?.datingAllowed===true&&profile.isActive===true&&years>=18&&
  ['masculino','femenino'].includes(profile.gender)&&career&&
  typeof profile.firstName==='string'&&profile.firstName.trim()&&
  typeof profile.lastName==='string'&&profile.lastName.trim()&&
  typeof profile.mainPhotoUrl==='string'&&Array.isArray(profile.photoUrls)&&profile.photoUrls.includes(profile.mainPhotoUrl);
}
function accepts(p,profile,viewer,years){
 if(!p||!Number.isInteger(p.minAge)||!Number.isInteger(p.maxAge)||p.minAge<18||p.maxAge>100||
  years<p.minAge||years>p.maxAge||!['ambos',profile.gender].includes(p.preferredGender))return false;
 const {careerIds=[],interestIds=[],universityMode='all',universityIds=[]}=p;
 if(![careerIds,interestIds,universityIds].every(Array.isArray))return false;
 return (!careerIds.length||careerIds.includes(profile.careerId))&&
  (!interestIds.length||interestIds.some(x=>profile.interestIds?.includes(x)))&&
  (universityMode==='all'||universityMode==='mine'&&!!profile.universityId&&profile.universityId===viewer.universityId||
   universityMode==='selected'&&universityIds.includes(profile.universityId));
}

export async function decideDiscovery(backend,uid,{target,type}){
 need(id(uid)&&id(target)&&uid!==target&&['like','pass'].includes(type),'invalid-argument');
 const db=backend.db,users=[uid,target].sort(),matchId=users.join('.');
 return db.runTransaction(async tx=>{
  for(const member of users)need((await backend.actor(tx,member)).verificationStatus==='approved');
  const paths=['users/'+uid,'users/'+target,'preferences/'+uid,'preferences/'+target,
   'blocks/'+uid+'.'+target,'blocks/'+target+'.'+uid,'swipes/'+uid+'.'+target,
   'swipes/'+target+'.'+uid,'matches/'+matchId,'discoveryCards/'+target];
  const [a,b,pa,pb,ab,ba,own,reverse,match,card]=await tx.getAll(...paths.map(path=>db.doc(path)));
  if(own.exists){
   need(own.get('type')===type,'already-decided');
   return {createdMatch:false};
  }
  need(!ab.exists&&!ba.exists&&card.get('isActive')===true);
  const from=a.data(),to=b.data(),now=new Date(),fromAge=age(from?.birthDate,now),toAge=age(to?.birthDate,now);
  need(id(from?.careerId)&&id(to?.careerId));
  const [careerA,careerB]=await tx.getAll(db.doc('careers/'+from.careerId),db.doc('careers/'+to.careerId));
  need(complete(from,fromAge,careerA.exists)&&complete(to,toAge,careerB.exists)&&
   accepts(pa.data(),to,from,toAge)&&accepts(pb.data(),from,to,fromAge));
  const mutual=type==='like'&&reverse.get('type')==='like';
  if(mutual)need(reverse.get('fromUserId')===target&&reverse.get('toUserId')===uid&&
   (!match.exists||JSON.stringify(match.get('users'))===JSON.stringify(users)));
  tx.create(own.ref,{fromUserId:uid,toUserId:target,type,createdAt:stamp()});
  if(mutual&&!match.exists){
   tx.create(match.ref,{users,isActive:true,createdAt:stamp()});
   backend.notifications.writeMatch(tx,matchId,users);
  }
  return {createdMatch:mutual&&!match.exists};
 });
}

async function access(backend,tx,uid,matchId,messageId){
 need(id(messageId),'invalid-argument');
 const path='chat_media/'+matchId+'/'+uid+'/'+messageId;
 await chatAccess(backend,tx,uid,path);
 const pair=await tx.get(backend.db.doc('matches/'+matchId));
 need(typeof pair.get('createdAt')?.toMillis==='function');
 const accounts=await tx.getAll(...pair.get('users').map(member=>backend.db.doc('users/'+member)));
 need(accounts.every(doc=>doc.get('datingAllowed')===true));
 return {path,recipient:pair.get('users').find(member=>member!==uid)};
}
export async function sendChat(backend,uid,{matchId,messageId,text,type='text',durationMs}){
 const edge=/^[\s\u0085]|[\s\u0085]$/u;
 need(typeof matchId==='string'&&typeof text==='string'&&['text','audio','image'].includes(type),'invalid-argument');
 need(type==='text'?text.length>0&&text.length<=1000&&!edge.test(text):text==='','invalid-argument');
 need(durationMs===undefined||type==='audio'&&Number.isInteger(durationMs)&&durationMs>0&&durationMs<=60000,'invalid-argument');
 return backend.db.runTransaction(async tx=>{
  const {path,recipient}=await access(backend,tx,uid,matchId,messageId);
  const ref=backend.db.doc('matches/'+matchId+'/messages/'+messageId);
  const previous=await tx.get(ref);
  const fields={senderId:uid,text,type,...(type==='text'?{}:{mediaPath:path}),...(durationMs===undefined?{}:{durationMs})};
  if(previous.exists){
   need(previous.get('storyReply')!==true&&Object.entries(fields).every(([key,value])=>previous.get(key)===value)&&
    previous.get('durationMs')===durationMs,'conflict');
   return {sent:true};
  }
  if(type!=='text'){
   const asset=(await tx.get(assetRef(backend,path))).data();
   need(asset?.state==='ready'&&asset.expiresAt?.toMillis()>Date.now()&&asset.path===path&&
    asset.uid===uid&&asset.matchId===matchId&&asset.type===type);
   if(durationMs!==undefined)need(Number.isInteger(asset.durationMs)&&asset.durationMs>0&&asset.durationMs<=61500&&Math.abs(durationMs-asset.durationMs)<=1500);
  }
  tx.create(ref,{...fields,createdAt:stamp()});
  backend.notifications.writeMessage(tx,recipient,matchId,messageId,uid);
  return {sent:true};
 });
}

export async function readChatReceipt(backend,uid,{matchId,messageId}){
 need(typeof matchId==='string','invalid-argument');
 return backend.db.runTransaction(async tx=>{
  const {recipient:other}=await access(backend,tx,uid,matchId,messageId);
  const message=await tx.get(backend.db.doc('matches/'+matchId+'/messages/'+messageId));
  need(message.get('senderId')===other);
  const notice=await tx.get(backend.notifications.messageRef(uid,matchId,messageId));
  if(message.get('readAt')==null)tx.update(message.ref,{readAt:stamp()});
  if(notice.exists)backend.notifications.markRow(tx,uid,notice.ref,notice.data());
  return {read:true};
 });
}
