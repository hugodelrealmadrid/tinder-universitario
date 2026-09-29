# Bloque 4 — Matches

Proyecto: `C:\Users\HP\Desktop\tinder_universitario`.
Firebase: `tinder-universitario`.
Implementación local del último bloque funcional del Sprint 2: match mutuo y Mis Matches.
No se hicieron operaciones remotas, despliegues, migraciones ni cambios a cuentas o datos existentes.
No se implementaron chat, unmatch, bloqueos, reportes, notificaciones ni Cloud Functions.

## Modelo exacto

```text
matches/{uidMenor}.{uidMayor}
  users: [uidMenor, uidMayor]   // exactamente dos strings diferentes y ordenados
  createdAt: timestamp         // servidor
  isActive: true
```

No incluye emails, perfiles duplicados ni updatedAt. No admite actualización ni borrado desde clientes.
`StudentMatch.idFor(a,b)` es la función central: reutiliza la validación de
`SwipeDecision.idFor`, ordena ambos UID con comparación lexicográfica y los une con punto.
Los UID solo admiten 1..128 caracteres de `[A-Za-z0-9_-]`; el punto no puede aparecer dentro de un UID.
El orden ASCII utilizado coincide en Dart y reglas Firestore; no se convierte a minúsculas.
`idFor(A,B) == idFor(B,A)` y un usuario no puede hacer match consigo mismo.

## Transacción LIKE → MATCH

`DiscoveryService.decide` conserva la validación de candidato y devuelve si creó un match nuevo.
Todas las lecturas se hacen antes de las escrituras:

1. Leer swipe propio; si existe se rechaza la nueva decisión.
2. Leer ficha del destino mediante las reglas vigentes de descubrimiento.
3. Si es LIKE, leer el swipe inverso (incluso su inexistencia) y el match de ID canónico.
4. Crear el swipe propio con timestamp del servidor.
5. Si el inverso es LIKE y el match no existe, crear el match en la misma transacción.

LIKE unilateral: solo swipe. LIKE + PASS o PASS + LIKE: solo swipes.
LIKE recíproco: dos swipes y un match. No se reescriben matches existentes ni se cambia su createdAt.
Al confirmar un match nuevo se muestra un SnackBar «¡Es un match!» y se avanza al siguiente candidato.
El aviso lo ve el cliente cuya transacción crea el match; el otro lo verá al entrar/actualizar Mis Matches.
No hay notificación push ni suscripción de avisos en segundo plano.

Si dos LIKE leen simultáneamente el inverso inexistente, Firestore detecta que cambió una de las
lecturas y reintenta la transacción en conflicto. En el reintento existe el LIKE inverso y se crea el match.
El ID fijo y la prohibición de update evitan duplicados. La prueba de concurrencia en el emulador
fuerza ambas lecturas iniciales antes de permitir los commits y verifica dos swipes y un solo match.
Las transacciones requieren conexión; si finalmente fallan, la UI permite reintentar y no simula éxito.

Las reglas pueden comprobar el nuevo LIKE inverso antes de que el SDK detecte el conflicto de versión.
En ese caso el commit recibe permission-denied por faltar el match en su propuesta antigua.
Para un LIKE, se permite UN reintento adicional de la transacción completa con lecturas nuevas.
Un rechazo persistente se devuelve a la UI; no hay bucles ni se debilita la validación de reglas.

No hay migración de pares de LIKE anteriores al Bloque 4. Una pareja que ya tiene dos swipes
del Bloque 3 no se vuelve a evaluar automáticamente. Para probar utilizar una pareja aún no evaluada.

## Reglas y privacidad

* `matches`: get/list solo participantes. La consulta debe incluir `array-contains` del UID actual.
* La lectura de un match inexistente se permite solo cuando el ID corresponde al usuario; necesaria
  para la transacción. Esto no autoriza leer matches existentes de terceros.
* Create exige dos UID válidos diferentes y ordenados, ID exacto, esquema mínimo, isActive true,
  createdAt del servidor y ambos swipes LIKE con remitentes/destinatarios exactos.
* `getAfter` verifica los LIKE incluso cuando uno se crea en el mismo commit.
* El segundo LIKE recíproco exige un match en el estado final del commit: un cliente no puede guardar
  solamente ese segundo LIKE omitiendo el match. Actualizar y borrar matches está denegado.
* `swipes`: se permite get puntual al remitente o destinatario, incluida la inexistencia del ID.
  Es necesario para leer el inverso. Las consultas siguen limitadas a decisiones enviadas por el usuario.
  Esto permite técnicamente inspeccionar una decisión entrante si se conoce su ID, pero no listarlas.
* `discoveryCards`: además del acceso original por compatibilidad, un participante de un match activo
  puede leer la ficha del otro, aunque ya haya swipe o hayan cambiado las preferencias.
  La ficha debe coincidir con el usuario actual y el perfil debe seguir completo y activo.
* `users` y `preferences` siguen privados. Catálogos, Storage y Authentication conservan sus reglas/comportamiento.

Actualización del cierre técnico: Mis Matches reutiliza la ficha con `age`, sin `birthDate`,
email ni preferencias. Las reglas rechazan el contrato antiguo y edades vencidas después de
un cumpleaños. El match permanece y muestra «Perfil no disponible» hasta que el otro
participante guarde su perfil actualizado. Esta corrección está probada localmente, sin deploy.
Ver [QA Sprint 1 y 2](README_QA_SPRINT_1_2.md) para resultados y límites de la solución.

Referencias oficiales usadas: [transacciones y getAfter](https://firebase.google.com/docs/firestore/manage-data/transactions)
y [comparación lexicográfica en reglas](https://firebase.google.com/docs/reference/rules/rules.String).

## Mis Matches y navegación

La navegación tiene Inicio, Descubrir, Matches y Perfil. Preferencias permanece en Inicio y Descubrir.
La pantalla consulta `matches.where('users', arrayContains: uid)`, ordena los resultados por createdAt
descendente en memoria y carga la ficha reducida del otro participante, nunca su documento users.
Resuelve el nombre de carrera desde careers y muestra foto, nombre, edad calculada y carrera.
Tiene loading, estado vacío, errores con reintento y actualización manual.
Un perfil desactivado, eliminado o sin ficha vigente se muestra como «Perfil no disponible»;
el documento del match se conserva. Fallos de red se muestran como errores, no como lista vacía.

La consulta usa el índice array automático predeterminado. No se añadió orderBy de servidor,
índice compuesto ni archivo de índices. El orden local mantiene la solución sencilla para este alcance;
la lista completa y las lecturas de fichas deben paginarse si crece mucho en el futuro.

## Archivos

Creados:

* `lib/features/matches/student_match.dart`
* `lib/features/matches/matches_service.dart`
* `lib/features/matches/matches_screen.dart`
* `test/matches_test.dart`
* `README_BLOQUE_4.md`

Modificados:

* `lib/features/discovery/discovery_service.dart`
* `lib/features/discovery/discovery_screen.dart`
* `lib/features/home/home_screen.dart`
* `firestore.rules`
* `tool/rules.test.mjs`
* `README_BLOQUE_3.md`

No se cambiaron dependencias, catálogos, Storage, modelos de perfil ni Authentication.
Los comandos de prueba/build generan logs y artefactos locales habituales.

## Validación local

Resultado final del 24/09/2026:

| Comprobación | Resultado |
|---|---|
| flutter pub get | Correcto, sin añadir dependencias |
| flutter analyze | No issues found |
| flutter test | 50/50, incluidos los 40 anteriores |
| Reglas Firestore/Storage | 32/32, incluidos los 24 anteriores y concurrencia real en emulador |
| flutter build web | Correcto: build/web |
| flutter build apk --debug | Correcto: build/app/outputs/flutter-apk/app-debug.apk |

Android emitió la advertencia de compatibilidad futura de Kotlin de los plugins Firebase;
no hubo errores de compilación. La prueba real y el despliegue quedan pendientes de tu ejecución.

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

Los tests de seguridad usan exclusivamente emuladores del proyecto demo. No usar las funciones de seed
del archivo de tests contra Firebase remoto. Los rechazos PERMISSION_DENIED esperados son parte de las pruebas.

## Despliegue manual — NO ejecutado

Actualizar reglas y usar la nueva versión de la app en ambas sesiones. Un cliente anterior no implementa
la creación atómica obligatoria del match y su segundo LIKE recíproco será rechazado por las nuevas reglas.

```powershell
Set-Location -LiteralPath 'C:\Users\HP\Desktop\tinder_universitario'
node .\tool\node_modules\firebase-tools\lib\bin\firebase.js deploy --only firestore:rules --project tinder-universitario
```

No se requiere comando de despliegue de índices. No desplegar reglas Storage para este cambio.

## Prueba real con dos usuarios (pendiente de ejecución por el usuario)

1. Ejecutar personalmente el despliegue anterior y arrancar la app actualizada:
   `flutter run -d chrome`. Abrir la misma URL en una ventana normal y otra de incógnito.
2. Iniciar sesión con A y B, una pareja sin swipes previos entre sí. No borrar swipes existentes.
3. Ambos deben tener perfil completo y activo, carrera y foto principal. Guardar perfil si aún no
   publicaron su discoveryCard. No es necesario cambiar fotografías existentes.
4. Ejemplo: A masculino de 22 años, preferencias femenino 20–25; B femenino de 21,
   preferencias masculino 20–24. Guardar preferencias en ambos.
5. Abrir Descubrir. A pulsa LIKE sobre B. En Firebase Console → Firestore → Datos comprobar
   `swipes/{uidA}.{uidB}` tipo like y que aún no existe el match de esa pareja.
6. B pulsa LIKE sobre A. Debe ver «¡Es un match!». En Console comprobar ambos swipes like y
   exactamente `matches/{uidMenor}.{uidMayor}`, users ordenados, createdAt timestamp, isActive true.
7. Entrar en Matches en ambas sesiones (o actualizar si ya estaba abierto): cada una muestra al otro
   con foto, nombre, edad y carrera. No muestra UID, email ni fecha exacta. Cambiar preferencias no borra el match.
8. Recargar y cerrar/iniciar sesión: el match sigue visible y la pareja no reaparece en Descubrir.
9. Para probar LIKE + PASS y concurrencia usar otras parejas sin swipes previos. En concurrencia
   cargar ambos candidatos antes de pulsar LIKE casi simultáneamente: deben quedar dos swipes y un match.
10. Un tercero no puede leer ese match; las pruebas locales verifican este permiso. La Console
    administrativa no aplica las reglas del cliente y no sirve para comprobar un rechazo de seguridad.

No hay chat, navegación hacia conversación, botón unmatch ni edición de matches en este bloque.
