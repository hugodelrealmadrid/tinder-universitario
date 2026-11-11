import {FieldPath, Timestamp} from 'firebase-admin/firestore';
import {AccessError} from './access-error.mjs';
import {dossierPhotoPaths} from './profile-media.mjs';

const pageSize = 10;
const id = value => typeof value === 'string' && /^[A-Za-z0-9_.-]{1,257}$/.test(value) && value !== '.' && value !== '..';
const uid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const date = value => value?.toDate?.()?.toISOString() ?? null;
const unavailable = async promise => promise.catch(() => null);
const querySpec = {
  likesSent: ['swipes','fromUserId','createdAt'],
  likesReceived: ['swipes','toUserId','createdAt'],
  matches: ['matches','users','createdAt','array-contains'],
  conversations: ['matches','users','createdAt','array-contains'],
  reportsReceived: ['reports','reportedId','createdAt'],
  reportsSent: ['reports','reporterId','createdAt'],
  verifications: ['verificationRequests','uid','createdAt'],
  audit: ['administrativeAudit','targetId','at'],
};

function decodeCursor(cursor,target,kind) {
  try {
    if (!/^[A-Za-z0-9_-]{1,900}$/.test(cursor)) throw Error();
    const [scope,type,seconds,nanos,documentId] = JSON.parse(Buffer.from(cursor,'base64url'));
    if (scope!==target || type!==kind || !Number.isInteger(seconds) ||
        !Number.isInteger(nanos) || !id(documentId)) throw Error();
    return [new Timestamp(seconds,nanos),documentId];
  } catch {
    throw new AccessError('invalid-argument');
  }
}

async function messageStats(ref) {
  const messages = ref.collection('messages');
  const ordered = messages.orderBy('createdAt').select('createdAt');
  const [total, first, last] = await Promise.all([
    unavailable(messages.count().get()),
    unavailable(ordered.limit(1).get()),
    unavailable(messages.orderBy('createdAt','desc').select('createdAt').limit(1).get()),
  ]);
  return {messages:total?.data().count ?? null,
    firstMessageAt:date(first?.docs[0]?.data().createdAt),
    lastMessageAt:date(last?.docs[0]?.data().createdAt)};
}

export async function readDossierHistory(backend,actorId,target,kind,cursor) {
  const {db} = backend;
  const authorize = async () => {
    const actor = await db.runTransaction(tx => backend.actor(tx,actorId,true));
    if (actor.verificationStatus!=='approved' || (kind==='audit' && actor.role!=='superadmin')) {
      throw new AccessError('permission-denied');
    }
    return actor.role;
  };
  const role = await authorize();
  if (!uid(target) || !Object.hasOwn(querySpec,kind)) throw new AccessError('invalid-argument');
  const [collection,field,stamp,op='=='] = querySpec[kind];
  let query = db.collection(collection).where(field,op,target);
  if (collection==='swipes') query=query.where('type','==','like');
  query=query.orderBy(stamp,'desc').orderBy(FieldPath.documentId(),'desc');
  if (cursor!==null) query=query.startAfter(...decodeCursor(cursor,target,kind));
  if (!(await db.doc('users/'+target).get()).exists) throw new AccessError('not-found');
  const page = await query.limit(pageSize+1).get();
  const docs = page.docs.slice(0,pageSize);
  const isMatch = collection==='matches';
  const actorFields = {
    likesSent:['toUserId'], likesReceived:['fromUserId'],
    reportsReceived:['reporterId','reviewedBy'], reportsSent:['reportedId','reviewedBy'],
    verifications:['reviewedBy'], audit:['actorId'],
  };
  const partner = row => Array.isArray(row.users) && row.users.length===2 && row.users.includes(target)
    ? row.users.find(other => other!==target && uid(other)) : null;
  const peopleIds = [...new Set(docs.flatMap(doc=>{
    const row=doc.data();
    return isMatch?[partner(row)]:actorFields[kind].map(key=>row[key]);
  }).filter(uid))];
  const people = new Map(peopleIds.length
    ? (await db.getAll(...peopleIds.map(value=>db.doc('users/'+value)))).map(doc=>[doc.id,doc.data()])
    : []);
  const person = (value,photo=false) => {
    const profile=people.get(value);
    const fullName=[profile?.firstName,profile?.lastName].filter(part=>typeof part==='string' && part.trim()).join(' ').trim();
    return {name:fullName||null,...(photo?{photoPath:dossierPhotoPaths(profile,value)[0]??null}:{})};
  };
  const items = await Promise.all(docs.map(async doc => {
    const row=doc.data();
    const at=date(row[stamp]);
    if (isMatch) return {date:at,person:person(partner(row),true),
      active:typeof row.isActive==='boolean'?row.isActive:null,closedAt:date(row.closedAt),
      ...(kind==='conversations'?await messageStats(doc.ref):{})};
    if (collection==='swipes') return {date:at,person:person(row[actorFields[kind][0]],true)};
    if (collection==='reports') return {date:at,person:person(row[actorFields[kind][0]]),
      reason:row.reason??row.reasonCode??null,status:row.status??null,reviewedAt:date(row.reviewedAt),reviewer:person(row.reviewedBy)};
    if (collection==='verificationRequests') return {date:at,status:row.status??null,
      reviewedAt:date(row.resolvedAt),reviewer:person(row.reviewedBy)};
    return {date:at,action:row.action??null,actor:person(row.actorId),result:row.result??null};
  }));
  if (await authorize()!==role) throw new AccessError('permission-denied');
  const last=docs.at(-1);
  const value=last?.get(stamp);
  const nextCursor=page.size>pageSize
    ? Buffer.from(JSON.stringify([target,kind,value.seconds,value.nanoseconds,last.id])).toString('base64url')
    : null;
  return {items,nextCursor};
}
