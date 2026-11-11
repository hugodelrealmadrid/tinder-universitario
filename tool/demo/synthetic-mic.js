// Fixture opt-in: no accede al micrófono físico ni modifica permisos.
export function installSyntheticMic() {
  if(location.origin!=='http://127.0.0.1:7357'||new URL(location.href).searchParams.get('syntheticMic')!=='1')
    throw new Error('Fixture solo para el demo local explícito.');
  const devices=navigator.mediaDevices;
  if(!devices)throw new Error('MediaDevices no disponible.');
  devices.getUserMedia=async constraints=>{
    if(!constraints?.audio||constraints.video)throw new Error('Fixture únicamente de audio.');
    const context=new AudioContext(),oscillator=context.createOscillator(),gain=context.createGain();
    gain.gain.value=0.04;const destination=context.createMediaStreamDestination();
    oscillator.frequency.value=440;oscillator.connect(gain).connect(destination);oscillator.start();
    await context.resume();
    for(const track of destination.stream.getTracks()) {
      const stop=track.stop.bind(track);
      track.stop=()=>{stop();try{oscillator.stop();}catch{}void context.close().catch(()=>{});};
    }
    return destination.stream;
  };
  window.__demoSyntheticMic=true;
}
