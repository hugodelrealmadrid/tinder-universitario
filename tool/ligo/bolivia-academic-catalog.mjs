import {readFileSync} from 'node:fs';
const historical=JSON.parse(readFileSync(new URL('../catalogs.seed.json',import.meta.url))).careers;
// Asociaciones confirmadas en fuentes de la institución. La oferta inicial es parcial.
const uc='https://www.ucb.edu.bo/formacion_grado/ingenieria-sistemas/';
const uv='https://www.univalle.edu/wp-content/uploads/2026/03/brochure-FINAL-1.pdf';
const uf='https://unifranz.edu.bo/carreras/medicina/';
const uagrm='https://www.uagrm.edu.bo/admisiones/carreras/187-3-ingenieria-informatica';
export const verifiedOn='2026-11-07';
export const programs={
 ...Object.fromEntries(Object.entries(historical).map(([id,value])=>[id,value.name])),
 sistemas_general:'Ingeniería de Sistemas',
 medicina:'Medicina',
 psicologia:'Psicología',
 informatica:'Ingeniería Informática',
 industrial_sistemas:'Ingeniería Industrial y Sistemas',
 minas:'Ingeniería de Minas',
};
export const universities=[
 ['univalle','Universidad Privada del Valle','Univalle',[
  ['cochabamba','Sede Cochabamba','Cochabamba',uv,Object.keys(historical)],
  ['la-paz','Sede La Paz','La Paz',uv,Object.keys(historical).filter(id=>!['enfermeria','ingenieria_aeronautica','ingenieria_energia'].includes(id))],
  ['sucre','Sede Sucre','Sucre',uv,['ingenieria_comercial','comercio_internacional','derecho','psicologia','sistemas','arquitectura','ingenieria_civil']],
  ['trinidad','Sede Trinidad','Trinidad',uv,['ingenieria_comercial','comercio_internacional','derecho','sistemas']],
  ['santa-cruz','Sede Santa Cruz','Santa Cruz de la Sierra',uv,['medicina','bioquimica_farmacia','fisioterapia_kinesiologia','nutricion_dietetica','ingenieria_comercial','comercio_internacional','derecho','administracion_empresas','psicologia','ciencia_datos','ingenieria_biomedica','sistemas','arquitectura','diseno_grafico','ingenieria_civil','ingenieria_aeronautica','mecanica_automatizacion','ingenieria_industrial']],
 ]],
 ['umss','Universidad Mayor de San Simón','UMSS',[
  ['central','Campus central','Cochabamba','https://sistemas.cs.umss.edu.bo/',['sistemas_general']],
 ]],
 ['ucb','Universidad Católica Boliviana San Pablo','UCB',[
  ['cochabamba','Sede Cochabamba','Cochabamba','https://cba.ucb.edu.bo/oferta-pregrado-ucb-cochabamba/',['sistemas_general','medicina','psicologia','ingenieria_civil']],
  ['la-paz','Sede La Paz','La Paz',uc,['sistemas_general']],
  ['tarija','Sede Tarija','Tarija',uc,['sistemas_general']],
  ['la-plata','Sede La Plata','Sucre',uc,['sistemas_general']],
 ]],
 ['unifranz','Universidad Privada Franz Tamayo','UNIFRANZ',
  [['cochabamba','Cochabamba'],['el-alto','El Alto'],['la-paz','La Paz'],['santa-cruz','Santa Cruz de la Sierra']]
   .map(([id,city])=>[id,city,city,uf,['medicina']])],
 ['upb','Universidad Privada Boliviana','UPB',[
  ['cochabamba','Campus Cochabamba','Cochabamba','https://www.upb.edu/programas/pregrado/cb-ingenieria-industrial-y-sistemas',['industrial_sistemas']],
 ]],
 ['umsa','Universidad Mayor de San Andrés','UMSA',[
  ['la-paz','Sede La Paz','La Paz','https://transparencia.umsa.bo/ofertaacademica',['ingenieria_civil','medicina']],
 ]],
 ['uagrm','Universidad Autónoma Gabriel René Moreno','UAGRM',[
  ['santa-cruz','Sede Santa Cruz','Santa Cruz de la Sierra',uagrm,['informatica']],
  ['camiri','Facultad Integral del Chaco','Camiri',uagrm,['informatica']],
 ]],
 ['usfx','Universidad Mayor, Real y Pontificia de San Francisco Xavier de Chuquisaca','USFX',[
  ['sucre','Sede Sucre','Sucre','https://feriaprofesiografica.usfx.bo/explora-tu-carrera-usfx-2026/carreras/medicina',['medicina']],
 ]],
 ['uto','Universidad Técnica de Oruro','UTO',[
  ['oruro','Facultad Nacional de Ingeniería','Oruro','https://www.uto.edu.bo/facultad-nacional-de-ingenieria/',['ingenieria_civil','minas']],
 ]],
];
