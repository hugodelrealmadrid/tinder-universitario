import {cleanupMedia} from './media-cleanup.mjs';
import {Stories} from './stories.mjs';
// El Job de carnets no debe reconciliar ni eliminar medios de perfiles o chats.
export async function runCleanupTask(backend,scope='all',{storiesEnabled=false}={}){
 if(!['all','university_cards','stories'].includes(scope))throw Error('invalid-cleanup-scope');
 if(scope!=='stories'){
  await backend.cleanupDue();
  if(scope==='all')await cleanupMedia(backend);
 }
 if(scope==='stories'||storiesEnabled)return new Stories(backend).cleanup();
}
