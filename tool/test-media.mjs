import sharp from 'sharp';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,readFile,unlink,rmdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
const cache=new Map(),run=promisify(execFile);
export async function imageFixture(mime='image/png'){
 const key='image:'+mime;if(cache.has(key))return cache.get(key);
 const img=sharp({create:{width:8,height:8,channels:3,background:'#557799'}});
 const b=await ({'image/png':()=>img.png().toBuffer(),'image/jpeg':()=>img.jpeg().toBuffer(),'image/webp':()=>img.webp().toBuffer()})[mime]();cache.set(key,b);return b;
}
export async function audioFixture(mime='audio/wav'){
 const key='audio:'+mime;if(cache.has(key))return cache.get(key);
 const samples=16000,wav=Buffer.alloc(44+samples*2);wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);wav.writeUInt16LE(1,20);wav.writeUInt16LE(1,22);wav.writeUInt32LE(16000,24);wav.writeUInt32LE(32000,28);wav.writeUInt16LE(2,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(samples*2,40);for(let i=0;i<samples;i++)wav.writeInt16LE(Math.round(8000*Math.sin(i*2*Math.PI*440/16000)),44+i*2);
 if(mime==='audio/wav'){cache.set(key,wav);return wav;}
 const dir=await mkdtemp(fileURLToPath(new URL('../build/audio-fixture-',import.meta.url))),extension={'audio/mpeg':'mp3','audio/mp4':'m4a','audio/ogg':'ogg'}[mime],input=join(dir,'input.wav'),output=join(dir,'out.'+extension);
 try{await writeFile(input,wav);await run(fileURLToPath(new URL('ffmpeg/release/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe',import.meta.url)),['-v','error','-i',input,'-map_metadata','-1',output],{windowsHide:true,timeout:15000});const bytes=await readFile(output);cache.set(key,bytes);return bytes;}finally{await unlink(input).catch(()=>{});await unlink(output).catch(()=>{});await rmdir(dir);}
}
