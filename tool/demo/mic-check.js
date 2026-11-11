// Diagnóstico explícito, sin Firebase, red, audio sintético ni persistencia.
if(location.origin!=='http://127.0.0.1:7357')throw new Error('Solo demo local.');
const $=id=>document.getElementById(id);
let stream,context,recorder,frame,timer,url,active=false,peak=0,squares=0,count=0,session=0;
function release(){
 session++;
 cancelAnimationFrame(frame);clearTimeout(timer);
 stream?.getTracks().forEach(t=>t.stop());stream=null;
 void context?.close().catch(()=>{});context=null;
 active=false;$('start').disabled=false;$('stop').disabled=true;
}
function stop(){if(recorder?.state==='recording')recorder.stop();release();}
$('stop').onclick=stop;
$('start').onclick=async()=>{
 const requestId=++session;
 active=true;peak=0;squares=0;count=0;$('start').disabled=true;$('status').textContent='Esperando permiso del navegador…';
 if(url){URL.revokeObjectURL(url);url=null;}$('preview').removeAttribute('src');
 try{
  context=new AudioContext();await context.resume();
  // Se invoca directamente desde el botón; no pasa por permisos del plugin.
  const request=navigator.mediaDevices.getUserMedia({audio:true,video:false});
  timer=setTimeout(()=>{if(!stream){$('status').textContent='No llegó respuesta al permiso. Revisa el icono de permisos o abre Chrome/Edge.';release();}},15000);
  const obtained=await request;
  if(!active||requestId!==session){obtained.getTracks().forEach(t=>t.stop());return;}
  stream=obtained;clearTimeout(timer);
  const track=stream.getAudioTracks()[0];
  $('track').textContent=`Entrada: ${track.label || 'sin etiqueta'} · estado ${track.readyState} · muted=${track.muted} · enabled=${track.enabled}`;
  const analyser=context.createAnalyser();analyser.fftSize=2048;
  context.createMediaStreamSource(stream).connect(analyser);
  const samples=new Float32Array(analyser.fftSize);
  const measure=()=>{if(!active)return;analyser.getFloatTimeDomainData(samples);let sum=0;
   for(const v of samples){peak=Math.max(peak,Math.abs(v));squares+=v*v;sum+=v*v;count++;}
   const rms=Math.sqrt(sum/samples.length);$('level').value=Math.min(1,rms*10);
   $('track').textContent=`Entrada: ${track.label || 'sin etiqueta'} · estado ${track.readyState} · muted=${track.muted} · enabled=${track.enabled} · AudioContext=${context.state}`;
   $('signal').textContent=`Pico ${peak.toExponential(3)} · RMS ${Math.sqrt(squares/Math.max(1,count)).toExponential(3)} · ${peak<1/32768?'SIN SEÑAL PCM16 útil':'Se detecta señal'}`;
   frame=requestAnimationFrame(measure);
  };measure();
  const mime=['audio/webm;codecs=opus','audio/webm','audio/ogg;codecs=opus'].find(t=>MediaRecorder.isTypeSupported(t));
  if(!mime)throw new Error('Unsupported');
  recorder=new MediaRecorder(stream,{mimeType:mime});const chunks=[];
  recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};
  recorder.onstop=()=>{const blob=new Blob(chunks,{type:mime});url=URL.createObjectURL(blob);$('preview').src=url;$('status').textContent=`Finalizada · ${blob.size} bytes · ${blob.type} · ${peak<1/32768?'No hubo señal PCM16 útil: revisar entrada/permisos del sistema.':'Señal detectada; pulsa reproducir para comprobar salida.'}`;};
  recorder.start();$('stop').disabled=false;$('status').textContent='Grabando micrófono real. Habla y observa el medidor.';timer=setTimeout(stop,15000);
 }catch(e){if(requestId!==session)return;$('status').textContent=e.name==='NotAllowedError'?'Permiso denegado.':e.name==='NotFoundError'?'No hay micrófono disponible.':'No se pudo abrir el micrófono. Revisa permisos y entrada.';release();}
};
addEventListener('pagehide',()=>{stop();if(url)URL.revokeObjectURL(url);});
