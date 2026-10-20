# Pruebas manuales: demo local de fases 1 a 5

Esta guía sustituye las instrucciones antiguas de fases 1 y 2. No ejecutar
migradores retirados ni importar exports antiguos como si tuvieran el esquema actual.
Los informes de cada fase son evidencia histórica, no instrucciones de reinicio.

## Demo existente

Abrir http://127.0.0.1:7357/__demo/start.html en Chrome o Edge. Debe aparecer
la franja verde de demo local. Para sesiones independientes, usar dos navegadores
o una ventana privada. Mantener los servicios de la PC encendidos.

Contraseña ficticia común: **DemoTinder2026!**. No usar contraseñas ni carnets reales.

| Cuenta | Correo | Uso |
| --- | --- | --- |
| Ana | ana.manual@demo.test | Aprobada, perfil y match con Bob |
| Bob | bob.manual@demo.test | Aprobado, perfil y match con Ana |
| Administración | admin@demo.test | Solicitudes, reportes y suspensión |
| Superadministración | superadmin@demo.test | También gestión de roles y auditoría |
| Estudiante | estudiante@demo.test | Cuenta de ensayo de verificación |
| Pendiente | pendiente@demo.test | El estado puede haber cambiado manualmente |
| Rechazado | rechazado@demo.test | Ensayo de reenvío |
| Suspendido | suspendido@demo.test | Ensayo de bloqueo de citas |

Consultar el estado actual en la aplicación; los nombres de fixtures no garantizan
que sigan pendientes/rechazados después de una aprobación manual. No restablecerlos
con scripts sobre un demo con datos que se quieren conservar.

Comprobar perfil, principal y galería; borrador de vista previa sin guardar;
Descubrir y preferencias; perfil de match; texto, imagen, adjunto de audio y voz.
Para voz real, comprobar permiso e indicador del micrófono, grabar hablando,
escuchar la previa y escuchar el mensaje desde la otra cuenta. Un tono sintético
no valida captura física. Los checks blancos cambian a azules cuando el receptor
ve el mensaje. Bloqueo, suspensión y cierre del match deben denegar medios y citas.

Para administración usar solo documentos ficticios, rechazar con motivo, reenviar,
aprobar y comprobar que las cuentas pendientes/suspendidas no acceden a citas.
La resolución modifica el demo: no esperar que el seed conserve su estado inicial.
Android físico requiere el flavor aislado y los túneles de PRUEBAS_ANDROID_USB.md.

## Servicios y conservación

Proyecto demo-tinder-universitario; Auth 9099, Firestore 8088, Storage 9198,
backend privado 7360 y Web/proxy 7357; todos en 127.0.0.1. Las reglas Firestore demo
son idénticas a las del producto. El SDK de Storage está cerrado: los bytes se
obtienen del backend autenticado, sin URLs permanentes.

El servidor demo impone CSP y un guard bloquea conexiones externas de la aplicación.
No usar main.dart ni standard para pruebas; no sustituir el servidor por uno genérico.
No es un firewall global de la computadora. Mantener el teléfono sin conectividad
externa durante las pruebas USB.

Si los servicios funcionan, no reiniciarlos. Antes de un reinicio, exportar a una
carpeta nueva con el CLI local, proyecto demo y firebase.demo.json explícitos.
Para recuperar, arrancar emuladores con --import apuntando al export actual,
además de --project demo-tinder-universitario --config firebase.demo.json.
No importar datos mientras los emuladores están funcionando ni copiar bases activas.
Luego iniciar tool/backend/server.mjs y tool/demo/server.mjs, en terminales separadas.

README_NUEVAS_FUNCIONES.md documenta dependencias, compilación y servicios desde
una instalación nueva. Solo en un demo completamente vacío: seed.mjs --new-empty-demo,
bootstrap-superadmin.mjs --create-demo-superadmin y prepare-phase4.mjs --synthetic-only,
todos bajo tool/demo/. Revisar guards antes de usarlos; no ejecutarlos sobre el demo
actual. Los scripts no son migradores para producción.

## Validación automatizada

node tool/demo/android-usb-check.mjs comprueba estado actual y bytes privados sin
restablecer fixtures. node --test tool/demo/*.test.mjs valida aislamiento y acceso.
Las pruebas de reglas/backend limpian un proyecto secundario: usar exclusivamente
firebase.phase3-tests.json y las variables de prueba indicadas en el README.
No apuntarlas al demo manual. No ejecutar firebase deploy ni cambiar reglas para
hacer pasar pruebas.
