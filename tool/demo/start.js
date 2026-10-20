// Eliminar únicamente cachés de assets de Flutter de este origen de pruebas.
const registrations=await navigator.serviceWorker?.getRegistrations()??[];
await Promise.all(registrations.map(r=>r.unregister()));
if('caches' in window) {
  for(const name of await caches.keys()) {
    if(['flutter-app-cache','flutter-temp-cache','flutter-app-manifest'].includes(name)) await caches.delete(name);
  }
}
location.replace('/');
