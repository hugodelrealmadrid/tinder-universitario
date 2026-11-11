// Preparación offline y operación de operador; importar no realiza I/O.
import {encode,value,PROJECT} from './migration-plan.mjs';
import {assertExecution,assertRules,createOperatorClient} from './operator.mjs';
const prefix=`projects/${PROJECT}/databases/(default)/documents/`;
export function provisionalBootstrapWrites({uid,email,authUser,access,registry,profile,request,existingGrant,ownerAuthorization,now=new Date()}){
 if(ownerAuthorization!=='initial_admin_online_test'||!/^[A-Za-z0-9_-]{1,128}$/.test(uid??'')||typeof email!=='string'||!email.includes('@')||uid.startsWith('demo_')||!authUser||authUser.localId!==uid||authUser.email!==email||!authUser.emailVerified||authUser.disabled||/(@demo\.|@example\.|\.(test|invalid|localhost)$)/i.test(email??''))throw Error('explicit-owner-real-verified-account-required');
 if(existingGrant){if(value(existingGrant.fields.uid)!==uid)throw Error('provisional-bootstrap-consumed');return [];}
 const a=access?.fields,r=value(registry?.fields.superadminIds),q=request?.fields;
 if(!a||!Array.isArray(r)||r.length||value(a.role)!=='user'||value(a.verificationStatus)!=='pending'||value(a.suspended)!==false||!profile)throw Error('initial-pending-account-required');
 const requestId=value(a.latestRequestId),expiration=value(q?.expiresAt);
 if(!requestId||request?.name!==prefix+'verificationRequests/'+requestId||value(q?.uid)!==uid||value(q?.status)!=='pending'||value(q?.documentStage)!=='ready'||value(q?.institution)!=='univalle_cochabamba'||!(expiration instanceof Date)||expiration<=now||value(q?.documentPath)!==`university_cards/${uid}/${requestId}/document`||!value(q?.generation)||value(q?.reviewedBy)||q?.resolvedAt)throw Error('private-document-pending-independent-review-required');
 const until=new Date(Math.min(expiration.getTime(),now.getTime()+72*3600000));
 const patch=(d,f)=>({update:{name:d.name,fields:encode(f).mapValue.fields},updateMask:{fieldPaths:Object.keys(f)},currentDocument:{updateTime:d.updateTime}});
 const create=(path,f)=>({update:{name:prefix+path,fields:encode(f).mapValue.fields},currentDocument:{exists:false}});
 const reasonCode='owner_authorized_online_test_pending_independent_review';
 return [patch(access,{role:'superadmin',verificationStatus:'pending',provisionalAdminUntil:until,updatedAt:now}),patch(registry,{superadminIds:[uid],updatedAt:now}),patch(profile,{datingAllowed:false}),create('administration/provisionalBootstrap',{uid,requestId,state:'active',scope:'online_test',independentReview:false,reasonCode,consumedAt:now,expiresAt:until}),create('administrativeAudit/first_provisional_superadmin_bootstrap',{actorId:'authorized_operator',targetId:uid,action:'provisional_superadmin_bootstrap',reasonCode,requestId,at:now,expiresAt:until,ownerAuthorized:true,independentReview:false})];
}
export async function provisionalBootstrap({uid,email,ownerAuthorization,apply,exceptionConfirmed,bucket,clientFactory=createOperatorClient}){
 assertExecution({apply,kind:'bootstrap'});if(exceptionConfirmed!==true)throw Error('provisional-exception-confirmation-required');
 if(!/^[A-Za-z0-9_-]{1,128}$/.test(uid??'')||bucket!=='tinder-universitario.firebasestorage.app')throw Error('confirmed-project-account-required');
 const client=await clientFactory(bucket),root='https://firestore.googleapis.com/v1/'+prefix.slice(0,-1);
 await assertRules(client.read,'strict');const state=await client.read(root+'/migrationState/five-phases-v1');if(value(state.fields.state)!=='revoked')throw Error('revocation-required-before-bootstrap');
 const [access,registry,profile,existingGrant,accounts]=await Promise.all([client.read(root+'/accountAccess/'+uid),client.read(root+'/administration/roles'),client.read(root+'/users/'+uid),client.get(root+'/administration/provisionalBootstrap'),client.read(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet?maxResults=1000&fields=users(localId,email,emailVerified,disabled),nextPageToken`)]);
 if(accounts.nextPageToken)throw Error('account-pagination-review-required');
 const requestId=value(access.fields.latestRequestId);if(requestId&&!/^[A-Za-z0-9_-]{1,128}$/.test(requestId))throw Error('invalid-request-id');
 const request=requestId?await client.read(root+'/verificationRequests/'+requestId):null;
 if(!existingGrant&&request){const path=value(request.fields.documentPath);if(path!==`university_cards/${uid}/${requestId}/document`)throw Error('invalid-document-path');const meta=await client.read(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(path)}?projection=full`);const policy=await client.read(`https://storage.googleapis.com/storage/v1/b/${bucket}/iam`);if(policy.bindings?.some(b=>b.members?.some(m=>['allUsers','allAuthenticatedUsers'].includes(m)))||meta.acl?.some(a=>['allUsers','allAuthenticatedUsers'].includes(a.entity)))throw Error('public-document-access-denied');if(meta.cacheControl!=='private, no-store'||meta.generation!==value(request.fields.generation)||meta.metadata?.firebaseStorageDownloadTokens||meta.contentType!=='image/png'||Number(meta.size)<=0||Number(meta.size)>5*1024*1024)throw Error('private-document-not-verified');}
 const writes=provisionalBootstrapWrites({uid,email,ownerAuthorization,authUser:accounts.users?.find(u=>u.localId===uid),access,registry,profile,request,existingGrant});if(writes.length)await client.commit(writes);return {provisionalBootstrap:writes.length>0,consumed:!writes.length,universityApproved:false};
}
