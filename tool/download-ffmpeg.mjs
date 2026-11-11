import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const run=promisify(execFile),url='https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-essentials_build.zip',size=114768076,count=16;
await mkdir('tool/ffmpeg',{recursive:true});
await Promise.all(Array.from({length:count},async(_,i)=>{const start=Math.floor(size*i/count),end=Math.floor(size*(i+1)/count)-1;await run('curl.exe',['--fail','--silent','--show-error','--retry','2','--max-time','240','--range',`${start}-${end}`,url,'-o',`tool/ffmpeg/part-${i}`],{windowsHide:true,timeout:750000});const b=await readFile(`tool/ffmpeg/part-${i}`);if(b.length!==end-start+1)throw Error('range-size');console.log('Parte '+(i+1)+' verificada');}));
const all=Buffer.concat(await Promise.all(Array.from({length:count},(_,i)=>readFile(`tool/ffmpeg/part-${i}`))));
if(createHash('sha256').update(all).digest('hex')!=='60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba')throw Error('checksum');await writeFile('tool/ffmpeg/verified.zip',all);console.log('SHA-256 publicado verificado.');
