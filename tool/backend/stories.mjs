import {randomUUID} from 'node:crypto';
import {Timestamp,FieldValue,FieldPath} from 'firebase-admin/firestore';
import sharp from 'sharp';
import {AccessError} from './access-error.mjs';
import {sealPrivateObject} from './private-object.mjs';
import {digest,chatAccess} from './chat-upload.mjs';
import {validateMedia,prepareStoryVideo} from './media-validation.mjs';
const day=86400000;
const idOk = id => typeof id==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(id);
const need = (v,code='permission-denied') => {if(!v)throw new AccessError(code);};
const server = () => FieldValue.serverTimestamp();
const pair = (a,b) => [a,b].sort().join('.');
export class Stories {
 constructor(backend,{clock=Date.now}={}){this.b=backend;this.db=backend.db;this.clock=clock;}
 ref(id){need(idOk(id),'invalid-argument');return this.db.doc('storyAssets/'+id);}
 async actor(tx,uid){need((await this.b.actor(tx,uid)).verificationStatus==='approved');}
 async access(tx,uid,id){
   const doc=this.ref(id), story=(await tx.get(doc)).data();
   need(story?.state==='published'&&story.expiresAt.toMillis()>this.clock());
   if(uid===story.owner)await this.actor(tx,uid);
   else await chatAccess(this.b,tx,uid,'chat_media/'+pair(uid,story.owner)+'/'+story.owner+'/story');
   return {doc,story};
 }
 async publish(uid,bytes,mime,caption){
   need(typeof caption==='string'&&[...caption].length<=200,'invalid-argument');
   await this.db.runTransaction(tx=>this.actor(tx,uid));
   let durationMs=null;
   if(mime==='video/mp4'){
     ({bytes,durationMs}=await prepareStoryVideo(bytes));
   }else{
     await validateMedia(bytes,mime);
     bytes=await sharp(bytes).rotate().jpeg({quality:88}).toBuffer();mime='image/jpeg';
     need(bytes.length<=5*1024*1024,'invalid-media');
   }
   const id=randomUUID(),ref=this.ref(id),path='story_media/'+uid+'/'+id;
   const file=this.b.bucket.file(path);
   await this.db.runTransaction(async tx=>{
     await this.actor(tx,uid);
     const existing=await tx.get(this.db.collection('storyAssets').where('owner','==',uid)
       .where('expiresAt','>',Timestamp.fromMillis(this.clock())).limit(12));
     need(existing.size<12,'rate-limited');
     tx.create(ref,{owner:uid,path,mime,state:'uploading',expiresAt:Timestamp.fromMillis(this.clock()+900000)});
   });
   try{
     await file.save(bytes,{resumable:false,preconditionOpts:{ifGenerationMatch:0},
       metadata:{contentType:mime,cacheControl:'private, no-store',metadata:{storyId:id,storyOwner:uid}}});
     await sealPrivateObject(file);
     const [metadata]=await file.getMetadata();
     await this.db.runTransaction(async tx=>{
       await this.actor(tx,uid);
       const row=(await tx.get(ref)).data();
       need(row?.state==='uploading'&&row.expiresAt.toMillis()>this.clock(),'conflict');
       const published=this.clock();
       tx.update(ref,{state:'published',caption:caption.trim(),publishedAt:Timestamp.fromMillis(published),
         expiresAt:Timestamp.fromMillis(published+day),durationMs,generation:metadata.generation,hash:digest(bytes)});
     });
   }catch(error){
     await ref.update({expiresAt:Timestamp.fromMillis(this.clock())}).catch(async failure=>{
       if(failure.code===5) {
         try{
           const [metadata]=await file.getMetadata();
           if(metadata.metadata?.storyId===id&&metadata.metadata?.storyOwner===uid){
             await file.delete({ifGenerationMatch:metadata.generation});
           }
         }catch(cleanupError){if(cleanupError.code!==404)throw cleanupError;}
       }
     });
     throw error;
   }
   return {id};
 }
 async feed(uid,cursor){
   await this.db.runTransaction(tx=>this.actor(tx,uid));
   let query=this.db.collection('matches').where('users','array-contains',uid).orderBy(FieldPath.documentId());
   if(cursor){need(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(cursor),'invalid-argument');query=query.startAfter(cursor);}
   const matches=await query.limit(25).get();
   const owners=new Set(cursor?[]:[uid]);
   for(const match of matches.docs){
     const row=match.data(),other=row.users.find(v=>v!==uid);
     if(row.isActive===true&&idOk(other))owners.add(other);
   }
   const groups=await Promise.all([...owners].map(async owner=>{
     try{
       return await this.db.runTransaction(async tx=>{
         if(owner!==uid)await chatAccess(this.b,tx,uid,'chat_media/'+pair(uid,owner)+'/'+owner+'/story');
         else await this.actor(tx,uid);
         const profile=(await tx.get(this.db.doc('users/'+owner))).data();
         const items=await tx.get(this.db.collection('storyAssets').where('owner','==',owner)
           .where('expiresAt','>',Timestamp.fromMillis(this.clock())).limit(12));
         const active=items.docs.filter(d=>d.get('state')==='published'&&d.get('expiresAt').toMillis()>this.clock());
         const views=active.length&&owner!==uid?await tx.getAll(...active.map(d=>d.ref.collection('views').doc(uid))):[];
         if(!active.length)return null;
         return {own:owner===uid,name:profile?.firstName||'Estudiante',
           photo:typeof profile?.mainPhotoUrl==='string'&&profile.mainPhotoUrl.startsWith('profile_photos/'+owner+'/')?profile.mainPhotoUrl:null,
           stories:active.map((d,i)=>({id:d.id,mime:d.get('mime'),caption:d.get('caption'),
             durationMs:d.get('durationMs'),seen:owner===uid||views[i]?.exists===true,
             publishedAt:d.get('publishedAt').toMillis(),expiresAt:d.get('expiresAt').toMillis()}))};
       });
     }catch(e){if(e instanceof AccessError&&e.code==='permission-denied')return null;throw e;}
   }));
   return {groups:groups.filter(Boolean),nextCursor:matches.size===25?matches.docs.at(-1).id:null,serverNow:this.clock()};
 }
 async media(uid,id){
   const {story}=await this.db.runTransaction(tx=>this.access(tx,uid,id));
   const file=this.b.bucket.file(story.path);
   const [meta]=await file.getMetadata();
   need(meta.generation===story.generation&&meta.contentType===story.mime&&!meta.metadata?.firebaseStorageDownloadTokens);
   const [bytes]=await file.download();
   need(digest(bytes)===story.hash);
   await this.db.runTransaction(tx=>this.access(tx,uid,id));
   return {bytes,mime:story.mime};
 }
 async view(uid,id){
   await this.db.runTransaction(async tx=>{
     const {doc,story}=await this.access(tx,uid,id);
     if(story.owner===uid)return;
     const ref=doc.collection('views').doc(uid);
     if(!(await tx.get(ref)).exists)tx.create(ref,{at:server()});
   });
   return {ok:true};
 }
 async viewers(uid,id,cursor){
   return this.db.runTransaction(async tx=>{
     const {doc,story}=await this.access(tx,uid,id);
     need(story.owner===uid);
     let query=doc.collection('views').orderBy(FieldPath.documentId());
     if(cursor){need(idOk(cursor),'invalid-argument');query=query.startAfter(cursor);}
     const page=await tx.get(query.limit(26));
     const visible=page.docs.slice(0,25);
     const profiles=visible.length?await tx.getAll(...visible.map(v=>this.db.doc('users/'+v.id))):[];
     return {items:visible.map((v,i)=>({name:profiles[i].get('firstName')||'Estudiante',at:v.get('at')?.toMillis()})),
       nextCursor:page.size>25?visible.at(-1).id:null};
   });
 }
 async reply(uid,id,text){
   need(typeof text==='string','invalid-argument');
   text=text.trim();
   need(text.length>0&&text.length<=1000,'invalid-argument');
   const message=await this.db.runTransaction(async tx=>{
     const {story}=await this.access(tx,uid,id);
     need(story.owner!==uid);
     const matchId=pair(uid,story.owner);
     const doc=this.db.collection('matches/'+matchId+'/messages').doc();
     tx.create(doc,{senderId:uid,text,type:'text',storyReply:true,createdAt:server()});
     this.b.notifications?.writeStoryReply(tx,story.owner,matchId,doc.id,uid);
     return doc.id;
   });
   return {message};
 }
 async report(uid,id){
   await this.db.runTransaction(async tx=>{
     const {story}=await this.access(tx,uid,id);
     need(story.owner!==uid);
     const report=this.db.doc('reports/story_'+id+'_'+uid);
     if((await tx.get(report)).exists)return;
     tx.create(report,{reporterId:uid,reportedId:story.owner,reason:'inappropriate_content',
       details:'Reporte de una historia.',storyId:id,status:'pending',createdAt:server()});
   });
   return {ok:true};
 }
 async remove(uid,id){
   await this.db.runTransaction(async tx=>{
     await this.actor(tx,uid);
     const ref=this.ref(id),story=(await tx.get(ref)).data();
     need(story?.owner===uid&&['published','deleting'].includes(story.state));
     tx.update(ref,{state:'deleting',expiresAt:Timestamp.fromMillis(this.clock())});
   });
   await this.purge(this.ref(id));
   return {ok:true};
 }
 async purge(ref){
   const row=await this.db.runTransaction(async tx=>{
     const story=(await tx.get(ref)).data(),now=this.clock();
     if(!story||story.expiresAt.toMillis()>now||story.cleanupLeaseUntil?.toMillis()>now)return null;
     tx.update(ref,{state:'deleting',cleanupLeaseUntil:Timestamp.fromMillis(now+300000)});
     return story;
   });
   if(!row)return false;
   const path='story_media/'+row.owner+'/'+ref.id;
   need(idOk(row.owner)&&path===row.path);
   const file=this.b.bucket.file(path);
   try{
     const [meta]=await file.getMetadata();
     const owned=row.generation!=null?String(row.generation)===String(meta.generation):
       meta.metadata?.storyId===ref.id&&meta.metadata?.storyOwner===row.owner;
     need(owned,'conflict');
     await file.delete({ifGenerationMatch:meta.generation});
   }catch(e){if(Number(e.code)!==404)throw e;}
   await this.db.recursiveDelete(ref);
   return true;
 }
 async cleanup(){
   const expired=this.db.collection('storyAssets').where('expiresAt','<=',Timestamp.fromMillis(this.clock())).orderBy('expiresAt');
   const result={deleted:0,skipped:0,failed:0};
   let cursor;
   for(let batch=0;batch<4;batch++){
     const page=await (cursor?expired.startAfter(cursor):expired).limit(30).get();
     for(const doc of page.docs){
       try{
         if(await this.purge(doc.ref))result.deleted++;
         else result.skipped++;
       }catch{result.failed++;}
     }
     if(page.size<30)break;
     cursor=page.docs.at(-1);
   }
   return result;
 }
}
