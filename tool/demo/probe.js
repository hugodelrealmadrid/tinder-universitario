const result=document.getElementById('probe-result');
document.getElementById('blob-probe').addEventListener('click',()=>{
  const url=URL.createObjectURL(new Blob(['demo-local'],{type:'text/plain'}));
  const xhr=new XMLHttpRequest();xhr.open('GET',url);
  xhr.onload=async()=>{
    const passed=xhr.status===200&&xhr.responseText==='demo-local';
    document.getElementById('blob-result').textContent=passed?'Blob local leído correctamente mediante XHR.':'Falló la lectura local.';
    URL.revokeObjectURL(url);
    await fetch('/__demo/audit',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({kind:'blob-probe',passed})});
  };
  xhr.onerror=()=>{URL.revokeObjectURL(url);document.getElementById('blob-result').textContent='Falló la lectura local.';};xhr.send();
});
document.addEventListener('securitypolicyviolation',async event=>{
  if(event.effectiveDirective==='connect-src'&&event.blockedURI.startsWith('https://isolation-probe.invalid')) {
    result.textContent='Bloqueo CSP confirmado: el navegador impidió la conexión externa.';
    await fetch('/__demo/audit',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({kind:'csp-probe',passed:true,blocked:'https://isolation-probe.invalid'})});
  }
});
document.getElementById('probe').addEventListener('click',async()=>{
  result.textContent='Comprobando bloqueo…';
  try {await fetch('https://isolation-probe.invalid/no-data');result.textContent='ERROR: no se bloqueó la conexión.';}
  catch (_) { /* La confirmación se obtiene del evento CSP del navegador, no solo del error HTTP. */ }
});
