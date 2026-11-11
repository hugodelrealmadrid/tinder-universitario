import {FieldPath} from 'firebase-admin/firestore';
import {AccessError} from './access-error.mjs';
import {dossierPhotoPaths} from './profile-media.mjs';

const pageSize = 20;
const validId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const date = timestamp => timestamp?.toDate?.()?.toISOString() ?? null;
const label = value => typeof value === 'string' && value.trim() ? value.trim() : null;
const name = profile => profile ? [profile.firstName, profile.lastName].map(label).filter(Boolean).join(' ') || null : null;
const count = async query => query.count().get().then(r=>r.data().count,()=>null);

function age(birth) {
  const birthday = birth?.toDate?.();
  if (!birthday || !Number.isFinite(birthday.getTime())) return null;
  const now = new Date();
  const year = now.getUTCFullYear() - birthday.getUTCFullYear();
  const beforeBirthday = now.getUTCMonth() < birthday.getUTCMonth() ||
    (now.getUTCMonth() === birthday.getUTCMonth() && now.getUTCDate() < birthday.getUTCDate());
  const years = year - Number(beforeBirthday);
  return years >= 0 && years <= 130 ? years : null;
}

export async function readDossier(backend, actorId, targetId) {
  const {db, auth} = backend;
  const authorize = async () => {
    const actor = await db.runTransaction(tx => backend.actor(tx, actorId, true));
    if (actor.verificationStatus !== 'approved') throw new AccessError('permission-denied');
    return actor.role;
  };
  const role = await authorize();
  if (!validId(targetId)) throw new AccessError('invalid-argument');
  const [profileDoc, accessDoc] = await db.getAll(db.doc('users/' + targetId), db.doc('accountAccess/' + targetId));
  if (!profileDoc.exists) throw new AccessError('not-found');
  const profile = profileDoc.data();
  const access = accessDoc.data();
  const catalog = async (collection, id) => validId(id)
    ? label((await db.doc(collection + '/' + id).get()).data()?.name)
    : null;
  const matches = db.collection('matches').where('users', 'array-contains', targetId);
  const reports = db.collection('reports');
  const swipes = db.collection('swipes').where('type', '==', 'like');
  const recent = (collection, field) =>
    db.collection(collection).where(field, '==', targetId).orderBy(FieldPath.documentId()).limit(pageSize).get();
  const [university, career, interestNames, identity, sent, received, matchTotal, matchPage,
    reportsReceived, reportsSent, verifications, audit] = await Promise.all([
    catalog('universities', profile.universityId),
    catalog('careers', profile.careerId),
    Promise.all((Array.isArray(profile.interestIds) ? profile.interestIds : []).slice(0, 20).map(id => catalog('interests', id))),
    auth.getUser(targetId).catch(error => {
      if (error.code === 'auth/user-not-found') return null;
      throw error;
    }),
    count(swipes.where('fromUserId', '==', targetId)),
    count(swipes.where('toUserId', '==', targetId)),
    count(matches),
    matches.orderBy(FieldPath.documentId()).limit(pageSize).get(),
    count(reports.where('reportedId', '==', targetId)),
    count(reports.where('reporterId', '==', targetId)),
    recent('verificationRequests', 'uid'),
    role === 'superadmin' ? recent('administrativeAudit', 'targetId') : null,
  ]);

  const partners = new Set();
  const conversations = await Promise.all(matchPage.docs.map(async match => {
    const users = match.data().users;
    const other = Array.isArray(users) && users.length === 2 && users.includes(targetId)
      ? users.find(uid => uid !== targetId && validId(uid)) : null;
    if (!other) return null;
    partners.add(other);
    return {other, messages: await count(match.ref.collection('messages')), active: match.data().isActive === true};
  }));
  const reviewers = verifications.docs.map(doc => doc.data().reviewedBy);
  const actors = audit?.docs.map(doc => doc.data().actorId) ?? [];
  const ids = [...new Set([...partners, ...reviewers, ...actors].filter(validId))];
  const people = ids.length ? await db.getAll(...ids.map(id => db.doc('users/' + id))) : [];
  const names = new Map(people.map(doc => [doc.id, name(doc.data())]));
  const complete = matchTotal === matchPage.size && conversations.every(row=>row?.messages != null);
  const connections = conversations.filter(Boolean);
  const finalRole = await authorize();
  if (finalRole !== role) throw new AccessError('permission-denied');
  const campus = validId(profile.universityId)&&validId(profile.campusId)
    ? label((await db.doc('universities/'+profile.universityId+'/campuses/'+profile.campusId).get()).data()?.name) : null;
  const approvedRequest = access?.verificationStatus==='approved' && validId(access.latestRequestId)
    ? (await db.doc('verificationRequests/'+access.latestRequestId).get()).data() : null;
  if (await authorize()!==role) throw new AccessError('permission-denied');
  const photoPaths = dossierPhotoPaths(profile,targetId);
  return {
    profile: {
      name: name(profile), email: label(identity?.email) ?? label(profile.email),
      age: age(profile.birthDate), university, campus,
      accreditedUniversity: approvedRequest?.uid===targetId&&approvedRequest.status==='approved' ? label(approvedRequest.universityName) : null,
      career, interests: interestNames.filter(Boolean),
      photoPath: photoPaths[0] ?? null,
      photoPaths,
      registeredAt: date(profile.createdAt) ?? date(profileDoc.createTime),
      lastSignInAt: identity?.metadata?.lastSignInTime ? new Date(identity.metadata.lastSignInTime).toISOString() : null,
      role: access?.role ?? null, suspended: access?.suspended ?? null,
      verificationStatus: access?.verificationStatus ?? null,
    },
    activity: {
      sent, received, matches: matchTotal, reportsReceived, reportsSent,
      sampledMatches: connections.length, complete,
      messages: complete ? connections.reduce((sum, row) => sum + row.messages, 0) : null,
      active: complete ? connections.filter(row => row.active).length : null,
      contacts: connections.filter(row => row.messages > 0).sort((a, b) => b.messages - a.messages)
        .slice(0, 5).map(row => ({name: names.get(row.other) ?? null, messages: row.messages})),
    },
    verifications: verifications.docs.map(doc => {
      const row = doc.data();
      return {status: row.status, date: date(row.resolvedAt) ?? date(row.createdAt), reviewer: names.get(row.reviewedBy) ?? null};
    }).sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '')),
    audit: audit?.docs.map(doc => {
      const row = doc.data();
      return {action: row.action, date: date(row.at), actor: names.get(row.actorId) ?? null, result: row.result ?? null};
    }).sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '')) ?? null,
  };
}
