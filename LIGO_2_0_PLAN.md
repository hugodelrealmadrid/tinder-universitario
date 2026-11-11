# LIGO 2.0 — implementación por fases

## 0. Auditoría y recuperación

El release 1.5.1 (8) está finalizado en Hosting con la referencia `sites/tinder-universitario/versions/85d3ef92b90cdc29`. Su JavaScript publicado coincide con el artefacto local de Motion Edition. La APK privada anterior sigue referenciada por la distribución `4m5d57kt38eeg`. Conservar ambos artefactos y el respaldo cifrado fuera del control de versiones. Una recuperación de Hosting debe republicar esa referencia, previa autorización. La APK anterior se conserva como artefacto de recuperación y no presupone que Android permita instalarla encima de una versión con código superior.

Flutter consume Firebase Authentication y Firestore. El servicio privado de Cloud Run comprueba roles y entrega medios privados. Las reglas mantienen acceso a chats por participación y el backend ya dispone de métricas agregadas y listado administrativo paginado. Los perfiles históricos pueden carecer de universidad. La adaptación debe conservar esa ausencia y mantener las carreras históricas.

La revisión del dashboard de MagicPath se hizo sobre la revisión `469846156818677761`. La composición combina una barra lateral agrupada, métricas compactas y superficies oscuras con acentos violetas. Las cifras y los controles del prototipo solo se trasladarán cuando tengan una operación real.

## Orden de implementación y validación

1. Móvil. Historial interno de navegación, retroceso Android, barras del sistema, contraste, accesibilidad, tamaños y teclado. Verificar tanto rutas reales de chat como vistas internas.
2. Administración. Aplicar la composición de MagicPath sobre los módulos actuales. Conservar operaciones y roles existentes, mostrar errores y utilizar métricas reales. Universidades se conecta después de habilitar su API en la fase 4.
3. Expedientes. Endpoint administrativo paginado y autorizado en cada solicitud. Usar conteos Firestore por consulta, sin obtener cuerpos de mensajes. Definir permisos y auditoría para evidencia antes de exponerla.
4. Multiuniversidad. Esquema aditivo, catálogo histórico intacto y nueva afiliación obligatoria solo bajo una política habilitada. Validar carrera vinculada, estado de ambos catálogos y edad en reglas y servidor. Las preferencias de todas las universidades incluyen perfiles históricos si cumplen el resto de filtros. Un filtro específico exige afiliación verificada.
5. Notificaciones. Escrituras idempotentes desde operaciones confiables, bandeja propia, estado de lectura y preferencias. Registrar tokens por instalación y usar mensajes de pantalla bloqueada sin contenido privado por defecto. Validar Android y Web con infraestructura de pruebas separada de producción.
6. Historias. Metadatos separados de medios privados, autorización por audiencia, vencimiento comprobado en el servidor, límites por formato, eliminación y reconciliación de archivos huérfanos. Las respuestas reutilizan únicamente el acceso autorizado al chat.
7. Integración. Probar roles, datos históricos, reglas, Storage, flujos nuevos, rendimiento y retroceso en Android. Generar Web y APK de staging, capturas y resultados. Producción requiere autorización posterior.

Los cambios y verificaciones deben mantenerse en `codex/ligo`. Los demos existentes quedan fuera del entorno de pruebas de esta implementación.
