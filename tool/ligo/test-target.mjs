// Solo pruebas locales; nunca selecciona un proyecto Firebase remoto.
export function ligoTestTarget(env=process.env){
 const offset=Number(env.LIGO_TEST_PORT_OFFSET??0);
 if(![0,200].includes(offset))throw Error('unsupported-test-port-offset');
 const project=offset===200?'demo-ligo-validation':'demo-ligo-staging';
 return {project,offset,ports:{auth:9399+offset,firestore:8288+offset,storage:9498+offset,hub:4420+offset},logging:4520+offset,websocket:9165+offset};
}
