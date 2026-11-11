import {createHash} from 'node:crypto';
import {FieldValue,Timestamp} from 'firebase-admin/firestore';
import {AccessError} from './access-error.mjs';

const uid = value => typeof value==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const tokenKey = value => createHash('sha256').update(value).digest('hex');
const tokenValid = value => typeof value==='string' && /^[A-Za-z0-9_:.\-]{30,512}$/.test(value);
const notificationId = (kind,path,extra='') => tokenKey(kind+':'+path+':'+extra);
const chatNotice = kind => kind==='message'||kind==='story_reply';
const now = () => FieldValue.serverTimestamp();
const day=86400000;
const active = data => data?.suspended===false;
const dating = data => active(data) && data.verificationStatus==='approved';
const matchParts = data => Array.isArray(data?.users)&&data.users.length===2&&data.users.every(uid)&&data.users[0]<data.users[1]
  ? data.users : null;
const invalidToken = code => ['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(code);

export class Notifications {
  constructor({db,messaging,webOrigin}){
    this.db=db;
    this.messaging=messaging;
    this.webOrigin=webOrigin;
  }
  account(uid){return this.db.doc('accountAccess/'+uid);}
  inbox(uid){return this.db.collection('notificationInboxes/'+uid+'/items');}
  totals(uid){return this.db.doc('notificationInboxes/'+uid);}
  settings(uid){return this.db.doc('notificationSettings/'+uid);}
  async pair(tx,id){
    const row=(await tx.get(this.db.doc('matches/'+id))).data();
    const members=matchParts(row);
    if (!members||members.join('.')!==id||row.isActive!==true) return null;
    const [a,b]=members;
    const checks=await tx.getAll(this.account(a),this.account(b),this.db.doc('blocks/'+a+'.'+b),this.db.doc('blocks/'+b+'.'+a));
    return dating(checks[0].data())&&dating(checks[1].data())&&!checks[2].exists&&!checks[3].exists?members:null;
  }
  async mark(actor,id){
    if(!/^[a-f0-9]{64}$/.test(id??''))throw new AccessError('invalid-argument');
    return this.db.runTransaction(async tx=>{
      if(!active((await tx.get(this.account(actor))).data()))throw new AccessError('permission-denied');
      const ref=this.inbox(actor).doc(id);
      const row=(await tx.get(ref)).data();
      if(!row)throw new AccessError('not-found');
      this.markRow(tx,actor,ref,row);
      return {read:true};
    });
  }
  markRow(tx,recipient,ref,row){
    if(row.readAt!=null)return;
    tx.update(ref,{readAt:now()});
    tx.set(this.totals(recipient),{unread:FieldValue.increment(-1),
      ...(chatNotice(row.kind)?{messages:FieldValue.increment(-1)}:{})},{merge:true});
  }
  async preferences(actor,enabled){
    if(typeof enabled!=='boolean')throw new AccessError('invalid-argument');
    await this.db.runTransaction(async tx=>{
      if(!active((await tx.get(this.account(actor))).data()))throw new AccessError('permission-denied');
      tx.set(this.settings(actor),{push:enabled},{merge:true});
    });
    return {push:enabled};
  }
  async device(actor,token,platform,remove=false){
    if(!tokenValid(token)||(!remove&&!['android','web'].includes(platform)))throw new AccessError('invalid-argument');
    const ref=this.db.doc('notificationDevices/'+tokenKey(token));
    await this.db.runTransaction(async tx=>{
      const previous=(await tx.get(ref)).data();
      if(remove){
        if(previous?.uid===actor)tx.delete(ref);
        return;
      }
      if(!active((await tx.get(this.account(actor))).data()))throw new AccessError('permission-denied');
      tx.set(ref,{uid:actor,token,platform,expiresAt:Timestamp.fromMillis(Date.now()+30*day)});
    });
    return {ok:true};
  }
  writeNotice(tx,recipient,ref,data){
    tx.create(ref,{...data,readAt:null});
    tx.set(this.totals(recipient),{unread:FieldValue.increment(1),
      ...(chatNotice(data.kind)?{messages:FieldValue.increment(1)}:{})},{merge:true});
  }
  messageRef(recipient,matchId,message){
    const path='matches/'+matchId+'/messages/'+message;
    return this.inbox(recipient).doc(notificationId('message',path));
  }
  writeMessage(tx,recipient,matchId,message,sender,kind='message'){
    const ref=this.messageRef(recipient,matchId,message);
    this.writeNotice(tx,recipient,ref,{kind,matchId,sender,createdAt:now()});
  }
  writeStoryReply(tx,recipient,matchId,message,sender){
    this.writeMessage(tx,recipient,matchId,message,sender,'story_reply');
  }
  writeMatch(tx,matchId,[a,b]){
    const key=notificationId('match','matches/'+matchId);
    for(const [recipient,sender] of [[a,b],[b,a]]){
      this.writeNotice(tx,recipient,this.inbox(recipient).doc(key),{kind:'match',matchId,sender,createdAt:now()});
    }
  }
  writeVerification(tx,recipient,request,status){
    const ref=this.inbox(recipient).doc(notificationId('verification','verificationRequests/'+request,status));
    this.writeNotice(tx,recipient,ref,{kind:'verification',status,createdAt:now()});
  }
  async event(path){
    const segments=path.split('/');
    const [collection,id,sub,message]=segments;
    const kind=collection==='matches'&&segments.length===2?'match':
      collection==='matches'&&sub==='messages'&&segments.length===4?'message':
      collection==='verificationRequests'&&segments.length===2?'verification':null;
    if(!kind || !/^[A-Za-z0-9_.-]{1,257}$/.test(id??'') ||
       (kind==='message'&&!uid(message))) return [];
    const entries=await this.db.runTransaction(async tx=>{
      const source=(await tx.get(this.db.doc(path))).data();
      if(!source)return [];
      let candidates=[];
      let createdAt=source.createdAt;
      let extra='';
      if(kind==='verification'){
        const pending=source.status==='pending'&&source.documentStage==='ready';
        if(!uid(source.uid)||!(pending||(['approved','rejected'].includes(source.status)&&source.resolvedAt)))return [];
        const account=(await tx.get(this.account(source.uid))).data();
        if(!active(account)||account.latestRequestId!==id||account.verificationStatus!==source.status)return [];
        candidates=[{recipient:source.uid,status:source.status}];
        createdAt=pending?source.updatedAt:source.resolvedAt;
        extra=source.status;
      }else{
        const pair=await this.pair(tx,id);
        if(!pair)return [];
        if(kind==='message'){
          if(!pair.includes(source.senderId))return [];
          candidates=[{recipient:pair.find(person=>person!==source.senderId),sender:source.senderId,matchId:id}];
        }else{
          candidates=pair.map(recipient=>({recipient,sender:pair.find(person=>person!==recipient),matchId:id}));
        }
      }
      if(typeof createdAt?.toMillis!=='function')return [];
      // Keep the message key across both presentations, retries and read receipts.
      const key=notificationId(kind,path,extra);
      const noticeKind=kind==='message'&&source.storyReply===true?'story_reply':kind;
      const records=await Promise.all(candidates.map(async ({recipient,...data})=>{
        const ref=this.inbox(recipient).doc(key);
        const existing=(await tx.get(ref)).data();
        return {recipient,data,ref,existing};
      }));
      const deliveries=[];
      for(const {recipient,data,ref,existing} of records){
        if(kind==='message'&&source.readAt!=null){
          if(existing)this.markRow(tx,recipient,ref,existing);
          continue;
        }
        if(!existing)this.writeNotice(tx,recipient,ref,{...data,kind:noticeKind,createdAt});
        deliveries.push({recipient,id:key});
      }
      return deliveries;
    });
    if(this.messaging){
      for(const entry of entries)await this.deliver(entry.recipient,entry.id);
    }
    return entries;
  }
  async deliver(recipient,id){
    const noteRef=this.inbox(recipient).doc(id);
    const claim=this.db.doc('notificationPushClaims/'+recipient+'.'+id);
    const permitted=await this.db.runTransaction(async tx=>{
      const [notice,settings,previous,account]=await tx.getAll(noteRef,this.settings(recipient),claim,this.account(recipient));
      const row=notice.data();
      if(!row||row.readAt!=null||settings.data()?.push!==true||previous.exists||!active(account.data())||
        row.createdAt?.toMillis()<Date.now()-3600000)return false;
      if(row.matchId&&!(await this.pair(tx,row.matchId))?.includes(recipient))return false;
      tx.create(claim,{expiresAt:Timestamp.fromMillis(Date.now()+7*day)});
      return true;
    });
    if(!permitted)return;
    const devices=await this.db.collection('notificationDevices').where('uid','==',recipient)
      .limit(30).get();
    for(const doc of devices.docs){
      const current=await doc.ref.get();
      const device=current.data();
      if(device?.uid!==recipient)continue;
      if(!device.expiresAt||device.expiresAt.toMillis()<=Date.now()){
        await this.removeIfCurrent(current);
        continue;
      }
      const title='LIGO',body='Tienes una nueva notificación.';
      try{
        const link=this.webOrigin?new URL('/?notice='+id,this.webOrigin).href:null;
        await this.messaging.send({token:device.token,notification:{title,body},data:{notice:id},
          android:{ttl:3600000,notification:{tag:id}},
          ...(link?{webpush:{headers:{TTL:'3600'},notification:{tag:id},fcmOptions:{link}}}:{})});
      }catch(error){
        if(invalidToken(error?.code))await this.removeIfCurrent(current);
        // El buzón sigue disponible. No registrar errores del SDK que puedan incluir el token.
      }
    }
  }
  async removeIfCurrent(snapshot){
    await this.db.runTransaction(async tx=>{
      const current=await tx.get(snapshot.ref);
      if(current.updateTime?.isEqual(snapshot.updateTime))tx.delete(snapshot.ref);
    });
  }
}
