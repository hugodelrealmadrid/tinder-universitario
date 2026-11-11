# Activos LIGO

Concepto definitivo: propuesta 1, llama moderna. SVG autónomos con símbolo y letras trazadas como paths: horizontal, vertical, símbolo, claro, oscuro y monocromático. `app-icon.svg`, `favicon.svg` y `splash.svg` son los maestros de sus derivados. La geometría se reproduce con CustomPainter en Flutter; no depende de descargar fuentes para mostrar la marca.

Paleta: #FF315A, #E91E63, #FF526B, #D81B60, #FFFFFF, #F5F5F7, #282832, #17171D. Los botones fucsia con texto blanco conservan contraste de al menos 4.5. El tema central está en lib/theme/app_theme.dart.

`campus-hero.png` se generó con la herramienta integrada imagegen. Personas y campus ficticios; no representa a una institución ni a usuarios reales.

Prompt final de portada: «Wide editorial lifestyle photograph, 1536x1024 landscape. A small diverse group of clearly adult university students aged 22-27 chatting and smiling while walking through a leafy contemporary Latin American campus courtyard at golden hour. Natural candid expressions, casual clothing, subtle warm coral highlights, realistic photographic texture. People on the right half and gently blurred architectural/leafy negative space on the left for white headline overlay. Premium commercial photography. No text, logos, badges, watermarks or real identifiable institution. Fictional people and campus.»

Los retratos ficticios para probar fotografías privadas se guardan fuera de los activos Flutter, en staging/fixtures. No incluir documentos personales, exportaciones ni credenciales en esta carpeta.
