export const SHOWCASE_PROJECT='tinder-universitario-showcase';
export function requireShowcaseProject(project,bucket){if(project!==SHOWCASE_PROJECT||bucket!==SHOWCASE_PROJECT+'.firebasestorage.app')throw Error('isolated-project-required');}
export function requireNonProductionMutation(url,method='GET'){
 const u=new URL(url);if(u.protocol!=='https:'||u.username||u.password)throw Error('unsafe-operator-url');
 let decoded=decodeURIComponent(u.href);
 if(method!=='GET'&&/(?:projects\/|\/b\/|project=)(?:tinder-universitario|208598232745)(?:[/:?&#]|$)/.test(decoded))throw Error('production-mutation-denied');
 if(method!=='GET'&&decoded.includes('tinder-universitario.firebasestorage.app'))throw Error('production-mutation-denied');
}
