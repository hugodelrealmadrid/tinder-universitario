// Transporte de las herramientas anteriores adaptado al backend privado fase 3.
let token;
export async function authenticatedMedia(path){
 if(!token){
  const r=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo-tinder-universitario-key',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'ana.manual@demo.test',password:'DemoTinder2026!',returnSecureToken:true})});
  if(!r.ok)throw new Error('Login local falló');token=(await r.json()).idToken;
 }
 const base='http://127.0.0.1:7357/__demo/api/chat/',headers={Authorization:'Bearer '+token};
 const meta=await fetch(base+'metadata/'+encodeURIComponent(path),{headers});
 if(!meta.ok)throw new Error('Metadatos privados no autorizados');
 const data=await fetch(base+'media/'+encodeURIComponent(path),{headers});
 if(!data.ok)throw new Error('Archivo privado no autorizado');
 return {metadata:await meta.json(),bytes:new Uint8Array(await data.arrayBuffer())};
}
