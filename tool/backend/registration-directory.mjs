import {AccessError} from './access-error.mjs';

const valid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const options = docs => docs
  .filter(doc => doc.data()?.isActive === true && typeof doc.data().name === 'string')
  .map(doc => ({id: doc.id, name: doc.data().name}));

export async function registrationOptions(db, kind, university, campus) {
  if (['interests','universities'].includes(kind) && university === null && campus === null) {
    let query=db.collection(kind).where('isActive','==',true);
    if(kind==='universities')query=query.where('directory','==',true);
    const page=await query.limit(101).get();
    if (page.size > 100) throw new AccessError('catalog-too-large');
    return options(page.docs);
  }
  if (kind === 'campuses' && valid(university) && campus === null) {
    const parent=db.doc('universities/'+university);
    const institution=(await parent.get()).data();
    if(institution?.directory!==true||institution.isActive!==true)return [];
    const page=await parent.collection('campuses').where('isActive','==',true).limit(101).get();
    if(page.size>100)throw new AccessError('catalog-too-large');
    return options(page.docs);
  }
  if (kind !== 'careers' || !valid(university) || !valid(campus)) {
    throw new AccessError('invalid-argument');
  }
  const parent = db.doc('universities/'+university);
  const site = parent.collection('campuses').doc(campus);
  const [institution, location] = await db.getAll(parent,site);
  if (!institution.data()?.directory || institution.data().isActive !== true ||
      location.data()?.isActive !== true) return [];
  const offerings = await site.collection('offerings').where('isActive','==',true).limit(101).get();
  if (offerings.size > 100) throw new AccessError('catalog-too-large');
  if (offerings.empty) return [];
  const careers = await db.getAll(...offerings.docs.map(doc=>db.doc('careers/'+doc.id)));
  return options(careers);
}
