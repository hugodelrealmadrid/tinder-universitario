import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,unlink,rmdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import sharp from 'sharp';
import {AccessError} from './verification.mjs';
const run=promisify(execFile);
const binaries=fileURLToPath(new URL('../ffmpeg/release/ffmpeg-9.0.2-essentials_build/bin/',import.meta.url));
const executable=name=>process.platform==='win32'?join(binaries,name+'.exe'):'/usr/bin/'+name;
let decoding=0;
export async function validateMedia(bytes,mime){
 if(!Buffer.isBuffer(bytes)||!bytes.length||bytes.length>(mime?.startsWith('image/')?5:15)*1024*1024)throw new AccessError('invalid-media');
 if(decoding>=2)throw new AccessError('rate-limited');decoding++;
 let dir;
 try{
  if(mime?.startsWith('image/')){
   const format={'image/jpeg':'jpeg','image/png':'png','image/webp':'webp'}[mime];
   if(!format)throw Error();
   const image=sharp(bytes,{limitInputPixels:16000000,failOn:'warning'}),m=await image.metadata();
   if(m.format!==format||(m.pages??1)!==1||m.width>4096||m.height>4096)throw Error();
   await image.raw().toBuffer();return {type:'image',durationMs:null};
  }
  const formats={'audio/mpeg':['mp3'],'audio/wav':['wav'],'audio/ogg':['ogg'],'audio/mp4':['mov','mp4','m4a','3gp','3g2','mj2']}[mime];
  if(!formats)throw Error();
  // Ficheros temporales exclusivamente en esta copia. Sin shell ni red en FFmpeg.
  dir=await mkdtemp(join(tmpdir(),'tinder-media-'));
  const input=join(dir,'input');await writeFile(input,bytes,{flag:'wx'});
  const options={timeout:15000,maxBuffer:20000000,windowsHide:true};
  const mov=mime==='audio/mp4'?['-enable_drefs','0','-use_absolute_path','0']:[];
  const probe=await run(executable('ffprobe'),['-v','error','-max_alloc','33554432','-protocol_whitelist','file,pipe','-format_whitelist','mp3,wav,ogg,mov',...mov,'-show_format','-show_streams','-of','json',input],{...options,maxBuffer:131072});
  const info=JSON.parse(probe.stdout),audio=info.streams.filter(s=>s.codec_type==='audio');
  if(audio.length!==1||info.streams.some(s=>s.codec_type!=='audio'&&!s.disposition?.attached_pic)||!info.format.format_name.split(',').some(f=>formats.includes(f))||audio[0].channels>8)throw Error();
  const output=await run(executable('ffmpeg'),['-v','error','-nostdin','-xerror','-max_alloc','33554432','-protocol_whitelist','file,pipe','-format_whitelist','mp3,wav,ogg,mov',...mov,'-threads','1','-i',input,'-map','0:a:0','-vn','-ac','1','-ar','16000','-f','s16le','pipe:1'],{...options,encoding:'buffer'});
  if(!output.stdout.length||output.stderr.length||output.stdout.length>19200000)throw Error();
  return {type:'audio',durationMs:Math.round(output.stdout.length/32)};
 }catch(e){if(e instanceof AccessError)throw e;throw new AccessError('invalid-media');}
 finally{decoding--;if(dir){await unlink(join(dir,'input')).catch(()=>{});await rmdir(dir).catch(()=>{});}}
}
