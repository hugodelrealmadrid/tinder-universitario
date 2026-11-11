# Corte definitivo de LIGO 2.0

## Antes del corte

1. Avisar a los usuarios de 1.5.1 por un canal autorizado con una fecha de cambio y el enlace de actualización. En Android deben comprobar primero que pueden iniciar sesión en la Web, desinstalar 1.5.1, instalar la nueva APK e ingresar con la misma cuenta. La reinstalación elimina la sesión y los datos exclusivamente locales. Se conservan UID, perfiles, fotos, conversaciones y demás datos sincronizados. La Web requiere recargar después de publicar.
2. Verificar el respaldo cifrado contra Auth, Firestore y las generaciones de Storage. Conservar la revisión estable, el release de Hosting y los IDs de las reglas. Validar que el plan de catálogo crea solo documentos faltantes y habilita las universidades preparadas mediante una precondición de versión. No modificar perfiles históricos.
3. Construir el backend nuevo en la infraestructura existente y comprobar su revisión al 0 %. El digest anterior no incluye el directorio corregido. Recompilar Web y Android con configuración productiva y con el directorio HTTP. Conservar la firma Release validada. Si la APK 2.0.0 (9) anterior se distribuyó a alguien, aumentar versionCode antes de entregar el artefacto corregido.
4. Validar el registro y las notificaciones con cuentas ficticias aisladas. Comprobar que el catálogo anónimo solo devuelve id y nombre, que el acceso directo a Firestore queda denegado y que el panel administrativo sigue autenticado. Mantener FCM apagado.

## Ventana de corte

1. Con el aviso ya enviado y la nueva versión disponible para distribución, aplicar los documentos de catálogo de forma aditiva y las reglas verificadas de Firestore. Las reglas de Storage no requieren cambios si siguen coincidiendo. No borrar índices. Mantener campusRegistrationEnabled apagado mientras se comprueba el nuevo frontend en su canal de preflight.
2. Verificar que cada universidad publicada devuelve únicamente los campos permitidos y tiene una sede y carrera disponibles. Promover el backend ya validado y publicar Hosting. Distribuir la nueva APK firmada mediante el canal privado autorizado.
3. Activar campusRegistrationEnabled para exigir universidad, sede y carrera a las altas nuevas. Confirmar que un usuario anterior puede iniciar sesión con su UID original y completar la sede cuando su carrera existente se ofrece en el catálogo. Si la oferta histórica no está verificada, conservar la afiliación y pedir su revisión administrativa. No asignar una sede o carrera automáticamente.
4. Desactivar las escrituras directas de chat, recibos y swipes únicamente tras avisar y comprobar que los clientes 2.0 usan las rutas de Cloud Run. Publicar ese endurecimiento como paso separado con pruebas de reglas. Mantener las operaciones vigentes de perfil y cierre de match. No eliminar cuentas ni bloquear su inicio de sesión por usar la versión anterior.
5. Activar la limpieza de historias en el Job existente al validar su alcance. No crear Eventarc, Pub/Sub ni infraestructura nueva.

## Recuperación

Detener la promoción ante un fallo y conservar las revisiones existentes. Si ya hay clientes Android 2.0, mantener disponibles las rutas 2.0 aunque se revierta Hosting. Una vuelta total a 1.5.1 requiere evaluar primero los perfiles creados por 2.0 y sus reglas. No restaurar datos automáticamente. Mantener el respaldo y el procedimiento de recuperación de firma en Drive privado.
