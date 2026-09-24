import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PROJECT = 'tinder-universitario';
const careerIds = 'medicina odontologia bioquimica_farmacia fisioterapia_kinesiologia enfermeria nutricion_dietetica ingenieria_comercial comercio_internacional derecho comunicacion administracion_empresas psicologia ingenieria_financiera ciencia_datos ingenieria_biomedica ingenieria_electronica sistemas arquitectura diseno_interiores diseno_grafico gastronomia ingenieria_civil tecnologia_alimentaria ingenieria_aeronautica electromecanica mecanica_automatizacion ingenieria_industrial ingenieria_energia'.split(' ');
const interestIds = ['musica', 'deportes', 'lectura', 'cine', 'tecnologia'];

export function validateCatalogs(catalogs) {
  if (!catalogs || Object.keys(catalogs).sort().join(',') !== 'careers,interests') {
    throw new Error('Solo se permiten careers e interests.');
  }
  const entries = [];
  for (const [collection, ids] of [['careers', careerIds], ['interests', interestIds]]) {
    const data = catalogs[collection];
    if (!data || Object.keys(data).sort().join(',') !== [...ids].sort().join(',')) {
      throw new Error(`IDs no autorizados o faltantes en ${collection}.`);
    }
    for (const id of ids) {
      const value = data[id];
      if (!value || Object.keys(value).sort().join(',') !== 'isActive,name' ||
          typeof value.name !== 'string' || !value.name.trim() || value.isActive !== true) {
        throw new Error(`Datos inválidos en ${collection}/${id}.`);
      }
      entries.push({collection, id, name: value.name, isActive: true});
    }
  }
  return entries;
}

export async function createMissing(catalogs, accessToken, fetchImpl = fetch) {
  const entries = validateCatalogs(catalogs); // Validar todo antes de escribir.
  const results = [];
  for (const entry of entries) {
    const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${entry.collection}?documentId=${encodeURIComponent(entry.id)}`;
    const response = await fetchImpl(url, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: {Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json'},
      body: JSON.stringify({fields: {name: {stringValue: entry.name}, isActive: {booleanValue: true}}}),
    });
    let status;
    if (response.ok) {
      status = 'creado';
    } else if (response.status === 409 && (await response.json()).error?.status === 'ALREADY_EXISTS') {
      status = 'existente, sin cambios';
    } else {
      // No imprimir cuerpos de errores, credenciales ni headers.
      throw new Error(`HTTP ${response.status} en ${entry.collection}/${entry.id}. Se detuvo la carga; puedes repetirla sin sobrescribir documentos.`);
    }
    results.push({path: `${entry.collection}/${entry.id}`, status});
  }
  return results;
}

async function cliToken() {
  const require = createRequire(import.meta.url);
  // Adaptador a la versión local inspeccionada, no una API pública de la CLI.
  const version = require('firebase-tools/package.json').version;
  if (version !== '15.31.0') throw new Error('Este adaptador requiere firebase-tools 15.31.0; revisarlo antes de usar otra versión.');
  const auth = require('firebase-tools/lib/auth.js');
  const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
  const account = auth.getProjectDefaultAccount(root);
  if (!account?.tokens?.refresh_token) throw new Error('No hay una sesión compatible de Firebase CLI. Ejecuta firebase login con tu cuenta autorizada.');
  try {
    const tokens = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
    if (!tokens?.access_token) throw new Error('Sin token');
    return tokens.access_token;
  } catch {
    throw new Error('No se pudo renovar la sesión de Firebase CLI. Usa firebase login --reauth y reintenta.');
  }
}

async function main() {
  const [project, mode, ...extra] = process.argv.slice(2);
  if (project !== PROJECT || (mode !== undefined && mode !== '--apply') || extra.length) {
    throw new Error('Uso: node tool/seed_catalogs_cli.mjs tinder-universitario [--apply]');
  }
  const catalogs = JSON.parse((await readFile(new URL('./catalogs.seed.json', import.meta.url), 'utf8')).replace(/^\uFEFF/, ''));
  const entries = validateCatalogs(catalogs);
  console.log(`Proyecto fijo: ${PROJECT}; base de datos: (default).`);
  if (mode !== '--apply') {
    console.log('VISTA LOCAL: no se consulta autenticación ni se realizan solicitudes remotas.');
    for (const entry of entries) console.log(`${entry.collection}/${entry.id}: ${entry.name}; isActive=true`);
    console.log('28 carreras y 5 intereses. Usa --apply únicamente cuando quieras crear los documentos faltantes.');
    return;
  }
  const token = await cliToken();
  const results = await createMissing(catalogs, token);
  for (const result of results) console.log(`${result.path}: ${result.status}`);
  console.log(`Finalizado: ${results.filter(result => result.status === 'creado').length} creados; los demás se conservaron sin cambios.`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(error instanceof TypeError ? 'Fallo de conexión. Puedes reintentar: solo se crean documentos faltantes.' : error.message);
    process.exitCode = 1;
  });
}
