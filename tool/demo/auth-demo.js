// Configurar Auth antes de que FlutterFire espere la restauración de sesión.
// Su inicializador puede restaurar/renovar un token antes de useAuthEmulator.
export function demoAuthModule(auth) {
  return {...auth, initializeAuth(app, options) {
    if(app.options.projectId!=='demo-tinder-universitario')throw new Error('Auth demo: proyecto ajeno.');
    const instance=auth.initializeAuth(app,{...options,persistence:auth.browserSessionPersistence});
    if(!instance.emulatorConfig)auth.connectAuthEmulator(instance,'http://127.0.0.1:9099');
    if(instance.emulatorConfig?.host!=='127.0.0.1'||instance.emulatorConfig?.port!==9099)
      throw new Error('Auth demo: endpoint ajeno.');
    return instance;
  }};
}
