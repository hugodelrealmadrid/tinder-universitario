# Bloque 3: preferencias, descubrimiento y decisiones

> Documento del alcance original del Bloque 3. El Bloque 4 amplía la lectura puntual
> de swipes al destinatario para comprobar reciprocidad, incorpora matches y permite
> leer fichas vigentes de participantes de un match. Ver `README_BLOQUE_4.md`.
> No cambia la privacidad de `users` ni de `preferences`.
>
> Actualización de cierre: la ficha entrega solo `age` y las reglas rechazan
> fechas exactas y edades vencidas. Ver [QA Sprint 1 y 2](README_QA_SPRINT_1_2.md).
> El cambio está validado localmente; no se ha desplegado.

Proyecto local: `C:\Users\HP\Desktop\tinder_universitario`. Firebase: `tinder-universitario`.
No se ejecutaron despliegues, migraciones ni operaciones sobre datos remotos.

## Modelos

`preferences/{uid}` contiene exactamente:

```text
minAge: int (18..100)
maxAge: int (minAge..100)
preferredGender: "masculino" | "femenino" | "ambos"
updatedAt: timestamp del servidor
```

Solo el propietario puede obtener, crear y actualizar su documento. No se permite listar ni borrar.
Los selectores impiden escribir género o edades manualmente. `DiscoveryLimits` centraliza los límites;
`PreferredGender` reutiliza `ProfileGender` del Bloque 2. Las reglas replican estos límites porque se ejecutan independientemente de Dart.

`swipes/{fromUid}.{toUid}` contiene exactamente:

```text
fromUserId: string
toUserId: string
type: "like" | "pass"
createdAt: timestamp del servidor
```

`SwipeDecision.idFor` valida identificadores de 1..128 caracteres alfanuméricos, guion o guion bajo,
y los separa con punto. El punto no pertenece al alfabeto permitido: no hay colisiones por separadores.
Se rechazan IDs personalizados fuera de ese alfabeto y decisiones sobre uno mismo.
La dirección A→B es diferente de B→A. Una transacción comprueba la inexistencia y crea la decisión;
las reglas prohíben actualizarla o borrarla, incluso por su propietario. El remitente puede leer sus propias decisiones.

## Descubrimiento y privacidad

Firestore no permite que una consulta cliente haga un join con preferencias privadas ajenas.
Las reglas no filtran resultados de consultas. Para conservar `users` y `preferences` privados se añaden:

* `discoveryIndex/{uid}`: `isActive: bool`, `updatedAt: timestamp`.
* `discoveryCards/{uid}`: `firstName`, `age`, `gender`, `description`, `careerId`,
  `mainPhotoUrl`, `interestIds`, `isActive`, `updatedAt`. Solo `age` se deriva;
  la fecha exacta permanece en el perfil privado.

El índice solo admite consultas autenticadas de activos y páginas de hasta 25 documentos.
Las fichas no pueden listarse: se solicitan individualmente. Las reglas consultan internamente los dos
usuarios y sus dos preferencias. Solo autorizan la ficha si ambos perfiles están completos y activos,
las edades y géneros son mutuamente aceptados, la ficha coincide con el usuario actual y no existe una decisión previa del solicitante.
`ambos` admite los dos géneros del perfil. Los extremos de edad son inclusivos.

La edad se calcula restando años y descontando uno si todavía no ocurrió el cumpleaños,
con fechas de calendario UTC tanto en Dart como en reglas. Se guarda una edad derivada
al publicar; si vence tras un cumpleaños, la ficha deja de ser legible por terceros
hasta que su propietario guarde el perfil. No se publican fechas de cumpleaños ni de próxima actualización.
El 29 de febrero cumple años el 1 de marzo en años no bisiestos según esta comparación.

La UI muestra foto principal, nombre, edad calculada, nombres de carrera e intereses y descripción.
No muestra email, UID ni fecha exacta. La ficha tampoco transporta `birthDate`, email
ni preferencias; las reglas rechazan fichas legadas con esos campos incluso para matches.
El índice revela IDs de documentos activos a clientes autenticados; no contiene nombres ni preferencias.
Las preferencias ajenas y documentos completos de usuarios nunca se entregan al cliente.

Se cargan las decisiones propias y se excluyen del recorrido, también después de recargar o iniciar sesión.
Los permisos de ficha refuerzan esa exclusión. Los rechazos por incompatibilidad se omiten y el recorrido
continúa a la página siguiente; una página sin candidatos no termina prematuramente la búsqueda.
El recorrido puede hacer numerosas lecturas en catálogos grandes, incluidas lecturas dependientes de reglas.
Es una solución cliente sencilla para este alcance universitario, no un motor de recomendaciones masivo.
La compatibilidad se comprueba al cargar y nuevamente al decidir; no hay una suscripción en tiempo real
que retire una ficha ya visible en el instante en que otra persona cambie sus preferencias.

## Publicación explícita

Guardar el perfil sincroniza usuario, índice y ficha en la misma transacción.
Las operaciones explícitas de fotografías también sincronizan la referencia de la ficha, conservando
el funcionamiento existente de Storage. No se movieron ni modificaron archivos remotos.
Las reglas verifican que las proyecciones coincidan exactamente con el usuario después de la transacción.
Un usuario existente debe abrir Perfil y pulsar **Guardar perfil** una vez. Iniciar sesión no migra datos.
Desplegar las nuevas reglas ANTES de probar guardados con esta versión: las antiguas no autorizan las colecciones nuevas.

## Archivos

Creados:

* `lib/features/preferences/discovery_preferences.dart`
* `lib/features/preferences/preferences_service.dart`
* `lib/features/preferences/preferences_screen.dart`
* `lib/features/discovery/discovery_models.dart`
* `lib/features/discovery/discovery_publication.dart`
* `lib/features/discovery/discovery_service.dart`
* `lib/features/discovery/discovery_screen.dart`
* `test/discovery_test.dart`
* `README_BLOQUE_3.md`

Modificados:

* `lib/features/home/home_screen.dart`: navegación Inicio/Descubrir/Perfil y acceso a Preferencias.
* `lib/features/profile/profile_service.dart`: sincronización transaccional de ficha e índice.
* `firestore.rules`: preferencias privadas, proyecciones verificadas, compatibilidad recíproca y swipes inmutables.
* `tool/rules.test.mjs`: pruebas de las reglas nuevas; se conservan las anteriores.

Sin cambios a Authentication, catálogos, reglas Storage, configuración Firebase ni dependencias del proyecto.
Los builds generan sus salidas locales habituales. No hay matches, chat ni otras funciones del Bloque 4.

## Validación local

Resultado de esta ejecución: `flutter pub get` correcto; `flutter analyze` sin observaciones;
40/40 tests Flutter; 24/24 tests de reglas Firestore/Storage en emuladores; build Web correcto
(`build/web`); build Android debug correcto (`build/app/outputs/flutter-apk/app-debug.apk`).
Android emitió una advertencia de compatibilidad futura de Kotlin en plugins Firebase, sin impedir el build.
No se validó contra datos remotos ni se desplegaron reglas.

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
flutter pub get
flutter analyze
flutter test
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --config firebase.emulators.json --project demo-tinder-universitario --only firestore,storage "node --test tool/rules.test.mjs"
flutter build web
$env:GRADLE_OPTS = '-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx2048m'
flutter build apk --debug
```

Los tests de reglas usan exclusivamente el proyecto demo del emulador. Los PERMISSION_DENIED esperados
verifican que las operaciones inválidas se rechazan; no son fallos cuando la suite termina correctamente.

## Despliegue manual (NO ejecutado)

No hacen falta índices compuestos adicionales con la indexación automática predeterminada:
el índice filtra `isActive` y ordena por ID; swipes filtra solo `fromUserId`.
No hay archivo nuevo de índices ni un despliegue de índices pendiente.

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --project tinder-universitario
```

El comando solo publica reglas Firestore. No publica Storage ni cambia datos.

## Prueba con dos cuentas reales

1. Ejecutar personalmente el despliegue de reglas anterior. Iniciar la app con `flutter run -d chrome`.
   Usar una ventana normal para A y una ventana de incógnito con la misma URL para B.
2. Usar dos cuentas de prueba adultas existentes o registrarlas manualmente. No reutilizar una pareja que ya tenga swipes.
3. En A: Perfil completo, masculino, fecha que dé 22 años hoy, una carrera activa, foto principal y perfil activo.
   Pulsar Guardar perfil. En B: perfil completo, femenino, 21 años, carrera activa, foto principal y activo; Guardar perfil.
   Si ya cumplen estas condiciones, basta con guardar; no es necesario cambiar fotos.
4. En Preferencias de A: Femenino, 20–25; guardar. En B: Masculino, 20–24; guardar.
5. En Console → Firestore → Datos verificar `preferences/{uid}` de ambos; `updatedAt` debe ser timestamp.
   Verificar que existen sus `discoveryIndex` y `discoveryCards` sincronizados. No se crea ninguna colección de fotografías.
6. Abrir Descubrir en ambos: deberían verse mutuamente. Con más usuarios de prueba puede haber otros candidatos primero.
   Comprobar nombres de carrera/intereses, edad calculada y ausencia de email, UID y fecha exacta en pantalla.
7. ANTES de votar, cambiar la preferencia de B a Femenino y guardar. Actualizar descubrimiento en A: B ya no aparece.
   Restablecer B a Masculino; actualizar A. También probar un rango de B que excluya 22 y después restablecerlo.
8. A pulsa LIKE sobre B. Verificar en Console `swipes/{uidA}.{uidB}` con remitente A, destino B y `type: like`.
   A avanza al siguiente candidato. Actualizar, cerrar sesión y volver a entrar: B no debe reaparecer.
9. B actualiza Descubrir y pulsa PASS sobre A. Verificar `swipes/{uidB}.{uidA}` con `type: pass`.
   Tras recargar B, A no debe reaparecer. No se crea ningún match.
10. Para probar nuevamente esa secuencia utilizar otra pareja de cuentas de prueba; no borrar ni reciclar swipes.
    La Console usa privilegios administrativos y no sirve para probar restricciones del cliente: esas están cubiertas por el emulador.

No se efectuó esta prueba remota durante la implementación, respetando la prohibición de operaciones remotas.
