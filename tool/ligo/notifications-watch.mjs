import {Timestamp} from 'firebase-admin/firestore';
import {Notifications} from '../backend/notifications.mjs';

export function watchStagingNotifications(services){
 if(services.db.projectId!=='demo-ligo-staging')throw Error('staging-only');
 const worker=new Notifications(services);
 const cutoff=Timestamp.fromMillis(Date.now()-10*60_000);
 const queries=[
  services.db.collectionGroup('messages').where('createdAt','>=',cutoff),
  services.db.collectionGroup('messages').where('readAt','>=',cutoff),
  services.db.collection('matches').where('createdAt','>=',cutoff),
  services.db.collection('verificationRequests').where('updatedAt','>=',cutoff),
 ];
 for(const query of queries)query.onSnapshot(snapshot=>{
  for(const event of snapshot.docChanges()){
   if(event.type!=='removed')worker.event(event.doc.ref.path).catch(()=>console.error('staging-notification-event-failed'));
  }
 },()=>console.error('staging-notification-listener-failed'));
}
