# Fixtures visuales ficticios

Los dos retratos son personas adultas ficticias generadas con la herramienta integrada imagegen. No pertenecen a usuarios reales ni se cargan en producción.

Prompts finales: retrato editorial vertical 1024x1536, persona latinoamericana adulta (mujer de 24 años con cabello oscuro ondulado y camiseta coral; hombre de 25 años con cabello corto oscuro y camiseta azul marino), expresión natural, encuadre de cabeza y torso, patio universitario frondoso desenfocado, luz cálida, textura natural; sin texto, logos, marcas de agua ni documentos. Personajes enteramente ficticios.

`node tool/ligo/seed-visual.mjs --create-fictitious-only` solo admite los emuladores de demo-ligo-staging. Crea ligo_visual_ana y ligo_visual_bob; rechaza sobrescrituras. No crea matches ni mensajes: pueden generarse con los flujos normales. La aprobación de estas cuentas es exclusivamente un fixture de pruebas local, nunca una acreditación de personas reales.
