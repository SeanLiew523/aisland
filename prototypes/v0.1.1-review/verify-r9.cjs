// Offline source/CSS checks and static canvas/SVG renders. No browser or app
// is launched; these artifacts cannot establish fullscreen or audio acceptance.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict'), {execFileSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const {createCanvas, Image, loadImage, GlobalFonts} = require('@napi-rs/canvas');
// Offline renderer needs an explicit system CJK font. Browser uses its ordinary
// PingFang fallback; registering this font changes only these static artifacts.
const cjkFont = '/System/Library/Fonts/STHeiti Light.ttc';
if (fs.existsSync(cjkFont)) GlobalFonts.registerFromPath(cjkFont, 'PingFang SC');
const proto = __dirname, root = path.resolve(proto, '../..');
const output = path.resolve(process.argv[2] || path.join(root, 'output/verification/v0.1.1-intro-revision-9'));
const read = name => fs.readFileSync(path.join(proto, name), 'utf8');
const baseline = name => execFileSync('git', ['show', `32c94f2:prototypes/v0.1.1-review/${name}`], {cwd: root, encoding: 'utf8'});
const source = read('intro-scene.js'), oldSource = baseline('intro-scene.js');
for(const name of ['intro-bloub-source.json','intro-audio-source.json']) {
  const provenance=JSON.parse(read(`assets/${name}`));assert.equal(provenance.revision,9);
  for(const [file,hash] of Object.entries(provenance.source_files_sha256))assert.equal(createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex'),hash);
  if(provenance.bundle_sha256)assert.equal(createHash('sha256').update(read('assets/intro-bloub.js')).digest('hex'),provenance.bundle_sha256);
}
for (const [start, end] of [['function gatherScene(', 'function mediaScene('], ['function island(', 'function draw(']]) {
  assert.equal(source.slice(source.indexOf(start), source.indexOf(end)), oldSource.slice(oldSource.indexOf(start), oldSource.indexOf(end)));
}
// R9 changes only the post-dock sound and the adapter call. Every original cue
// before dock remains structurally equal, including its arguments and stopAt.
const audioContext = {window:{}}; vm.createContext(audioContext);
vm.runInContext(read('intro-audio.js'),audioContext);
const originalAudioContext = {window:{}}; vm.createContext(originalAudioContext);
vm.runInContext(baseline('intro-audio.js'),originalAudioContext);
const audio = audioContext.window.AIslandIntroAudio;
const timeline = JSON.parse(vm.runInNewContext(`${source.match(/const timeline = .*;/)[0]} JSON.stringify(timeline)`));
const originalScore = originalAudioContext.window.AIslandIntroAudio.cueSheet(timeline);
const score = audio.cueSheet(timeline);
const json = value => JSON.stringify(value);
assert.equal(json(score.filter(c=>c.at<timeline.dock)), json(originalScore.filter(c=>c.at<timeline.dock)));
assert.equal(score.filter(c=>c.at>=timeline.dock).length,1);
const dockCue=score.find(c=>c.kind==='dock');
assert.equal(dockCue.at,timeline.dock); assert.equal(dockCue.stopAt,21.5);
assert(score.every(c=>c.stopAt<=22));
const calls=[];
audio.schedule(100,timeline,Object.fromEntries(['tone','air','swell','dock'].map(kind=>[kind,(...args)=>calls.push({kind,args})])));
assert.equal(calls.length,score.length);
score.forEach((cue,index)=>{
  const expected=cue.args.slice();expected[['air','dock'].includes(cue.kind)?0:1]+=100;
  assert.equal(json(calls[index]),json({kind:cue.kind,args:expected}));
});
assert.throws(()=>audio.schedule(0,timeline,{tone(){},air(){},swell(){}}),/dock primitives/);
const review=read('review.js');
const hostStart=review.indexOf('  function dock('),hostEnd=review.indexOf('  function eventSound(',hostStart);
// Comparing to the immediate R8 parent guards setup/install and review behavior.
const r8Review=execFileSync('git',['show','11037b9:prototypes/v0.1.1-review/review.js'],{cwd:root,encoding:'utf8'});
assert.equal(review.slice(0,hostStart)+review.slice(hostEnd).replace('{tone,air,swell,dock}','{tone,air,swell}'),r8Review);
assert(!read('review.js').includes('$("stage-copy")'));
assert(!read('index.html').includes('id="stage-copy"'));
assert(!read('intro-bloub.ts').includes('<span>AGENT'));
assert.equal(source.match(/const timeline = .*;/)[0], oldSource.match(/const timeline = .*;/)[0]);

function ReviewImage() {
  const image = new Image(), property = Object.getOwnPropertyDescriptor(Image.prototype, 'src');
  let onload;
  Object.defineProperty(image, 'onload', {set(callback) { onload = (...args) => { void callback(...args); }; }, get() { return onload; }});
  Object.defineProperty(image, 'src', {set(value) { property.set.call(image, fs.readFileSync(path.resolve(proto, value))); },
    get() { return property.get.call(image); }});
  return image;
}
const surfaces = Object.fromEntries(['gather-bloub','home-orbit'].map(id => [id,{style:{},dataset:{},hidden:true,innerHTML:''}]));
const sandbox = { Image:ReviewImage, document:{getElementById:id=>surfaces[id]},
  createImageBitmap: async (image,x,y,w,h) => { const c=createCanvas(w,h); c.getContext('2d').drawImage(image,x,y,w,h,0,0,w,h); return c; }, console };
sandbox.window = sandbox; vm.createContext(sandbox);
for (const name of ['assets/native-media.js','intro-i18n.js','assets/intro-bloub.js','intro-scene.js']) vm.runInContext(read(name), sandbox, {filename:name});
const bloub=sandbox.AIslandIntroBloub, scene=sandbox.AIslandIntroScene;
const resizeChecks=[];
for (const reduceMotion of [false,true]) {
  for (const [w,h] of [[380,500],[1702,1016],[380,500]]) {
    const input={w,h,t:21.1,x:w/2,y:h*.43,iw:100,ih:30,gather:5.3,arrived:7.95,
      approval:8.2,dock:18.1,motion:!reduceMotion,setup:false};
    bloub.render(input);
    const geometry=bloub.layout(input).orbit, actual=surfaces['home-orbit'];
    assert.equal(geometry.size,Math.min(w*.68,h*.66)*.7);
    assert.equal(geometry.x,w/2); assert.equal(geometry.y,h*.55);
    assert(actual.style.cssText.includes(`width:${geometry.size}px;height:${geometry.size}px`));
    assert.equal((actual.innerHTML.match(/<svg/g)||[]).length,1);
    assert(!actual.innerHTML.includes('<span>')); assert(!actual.innerHTML.includes('NaN'));
    assert.equal(actual.dataset.state,'orbit');
    resizeChecks.push({w,h,reduceMotion,time:21.1,size:geometry.size,r8Size:Math.min(w*.68,h*.66),ratio:.7,x:geometry.x,y:geometry.y});
  }
}
const morphChecks=[];
for (const time of [.4,.9,1.6,2,2.5,3.3]) {
  const frame=bloub.sample('orbit',time), svg=bloub.svg(frame,'intro-orbit');
  assert(frame.arcs.length > 0 && frame.arcs.length <= 6); assert(svg.includes(frame.bodyPath));
  assert(svg.includes('<mask')); assert(!svg.includes('NaN')); assert(!svg.includes('<text'));
  bloub.render({w:1702,h:1016,t:18.9+time/1.1,x:851,y:400,iw:100,ih:30,
    gather:5.3,arrived:7.95,approval:8.2,dock:18.1,motion:true,setup:false});
  // The actual adapter must paint this exact original-engine frame, not a
  // substitute/crossfaded body. Replay and backward static inspection are pure.
  const actualTime=+surfaces['home-orbit'].dataset.time;
  assert.equal(surfaces['home-orbit'].innerHTML,bloub.svg(bloub.sample('orbit',actualTime),'intro-orbit'));
  morphChecks.push({time,arcs:frame.arcs.length});
}
assert.notEqual(bloub.sample('orbit',.9).bodyPath,bloub.sample('orbit',2.5).bodyPath);
let reducedFrame;
for (const t of [19.3,21.8,19.5]) {
  bloub.render({w:1702,h:1016,t,x:851,y:400,iw:100,ih:30,gather:5.3,
    arrived:7.95,approval:8.2,dock:18.1,motion:false,setup:false});
  const current=surfaces['home-orbit'].innerHTML;
  if(reducedFrame)assert.equal(current,reducedFrame); reducedFrame=current;
}
async function capture(width,height,time,language,reduceMotion=false) {
  const canvas=createCanvas(width,height), ctx=canvas.getContext('2d');
  scene.draw(ctx,width,height,time,{playing:true,language,reduceMotion});
  const size = Math.min(width/(width<640?780:1040),height/720);
  const geometry = bloub.layout({w:width,h:height,t:time,x:width/2,y:height*.43,
    iw:282*size*.77,ih:83*size*.84,gather:5.3,arrived:7.95,approval:8.2,dock:18.1,motion:!reduceMotion,setup:false});
  if (geometry.glyph.visible) {
    const g=geometry.glyph; assert(g.x-g.size/2 > width/2-282*size*.77/2);
    assert.equal(surfaces['gather-bloub'].dataset.state,time>=7.95?'thinking':'idle');
    const image=await loadImage(Buffer.from(surfaces['gather-bloub'].innerHTML));
    ctx.drawImage(image,g.x-g.size/2,g.y-g.size/2,g.size,g.size);
  }
  if (geometry.orbit.visible) {
    const o=geometry.orbit;
    assert(o.y-o.size/2 > 0); assert(o.y+o.size/2 < height);
    ctx.save(); ctx.globalAlpha=+surfaces['home-orbit'].style.opacity;
    ctx.beginPath();ctx.arc(o.x,o.y,o.size/2,0,Math.PI*2);ctx.strokeStyle='#6c7dca30';ctx.stroke();
    const image=await loadImage(Buffer.from(surfaces['home-orbit'].innerHTML));
    ctx.drawImage(image,o.x-o.size/2,o.y-o.size/2,o.size,o.size);ctx.restore();
  }
  const name=`offline-${language}-${width}x${height}-${time.toFixed(2)}${reduceMotion?'-reduced':''}.png`;
  fs.writeFileSync(path.join(output,name),canvas.toBuffer('image/png'));return name;
}
(async()=>{
  await scene.ready; fs.mkdirSync(output,{recursive:true});
  const audioChecks=[];
  for (const rate of [32000,44100,48000,96000,192000]) {
    const channels=audio.dockPCM(rate,dockCue.length,dockCue.volume,dockCue.args[3]);
    const repeat=audio.dockPCM(rate,dockCue.length,dockCue.volume,dockCue.args[3]);
    let peak=0,sum=0,maxStep=0;
    for(let channel=0;channel<2;channel++) {
      assert.equal(channels[channel].length,Math.ceil(rate*dockCue.length));
      assert.equal(Buffer.compare(Buffer.from(channels[channel].buffer),Buffer.from(repeat[channel].buffer)),0);
      assert.equal(channels[channel][0],0);assert.equal(channels[channel].at(-1),0);
      for(let i=0;i<channels[channel].length;i++) {
        const value=channels[channel][i]; assert(Number.isFinite(value));
        peak=Math.max(peak,Math.abs(value));sum+=value*value;
        if(i)maxStep=Math.max(maxStep,Math.abs(value-channels[channel][i-1]));
      }
    }
    assert(peak>.05&&peak<.25);assert(maxStep<.025);
    // Slowing contact spacing is actually audible energy separated by decays;
    // the final centered contact starts exactly at the settled visual marker.
    const windows=[.03,.15,.32,.56,.9,1.36,1.95,2.63];
    for(const at of windows) {
      let energy=0;for(let i=Math.floor((at-.01)*rate);i<Math.floor((at+.02)*rate);i++) energy+=channels[0][i]**2+channels[1][i]**2;
      assert(energy>rate*.000005);
    }
    const lastStart=Math.ceil(dockCue.args[3]*rate);
    for(let i=lastStart;i<channels[0].length;i++)assert.equal(channels[0][i],channels[1][i]);
    audioChecks.push({rate,frames:channels[0].length,peak,rms:Math.sqrt(sum/(channels[0].length*2)),maxStep,
      finalContactAt:timeline.settled,stopAt:dockCue.stopAt,deterministic:true,clippedSamples:0});
    if(rate===48000) {
      // Shared original PCM, scaled by review's master gain. Compressor is not
      // applied in this isolated excerpt; this is not a native/full-score WAV.
      const frames=channels[0].length, wav=Buffer.alloc(44+frames*4);
      wav.write('RIFF');wav.writeUInt32LE(wav.length-8,4);wav.write('WAVEfmt ',8);wav.writeUInt32LE(16,16);
      wav.writeUInt16LE(1,20);wav.writeUInt16LE(2,22);wav.writeUInt32LE(rate,24);wav.writeUInt32LE(rate*4,28);
      wav.writeUInt16LE(4,32);wav.writeUInt16LE(16,34);wav.write('data',36);wav.writeUInt32LE(frames*4,40);
      for(let i=0;i<frames;i++)for(let channel=0;channel<2;channel++)wav.writeInt16LE(Math.round(channels[channel][i]*.7*32767),44+i*4+channel*2);
      fs.writeFileSync(path.join(output,'dock-r9-48000-stereo-excerpt.wav'),wav);
    }
  }
  // Execute the actual browser host primitive without opening a browser. It
  // owns the buffer source in the existing tracking/cancellation lifetime.
  const nodes=[],active=new Set();const host={AIslandIntroAudio:audio,master:{},activeSources:active,soundGeneration:0,canvas:{dataset:{}},
    audioContext:{sampleRate:48000,
      createBufferSource(){const node={connect(target){this.target=target;},disconnect(){this.disconnected=true;},start(at){this.startAt=at;},stop(at){this.stopAt=at;}};nodes.push(node);return node;},
      createBuffer(channels,length,rate){return {channels:Array.from({length:channels},()=>new Float32Array(length)),length,rate,
        copyToChannel(pcm,index){this.channels[index].set(pcm);}};}}};
  const lifetime=review.slice(review.indexOf('  function track('),review.indexOf('  function tone('));
  vm.createContext(host);vm.runInContext(lifetime+review.slice(hostStart,hostEnd)+'\ndock(118.1,3.4,.25,2.6);',host);
  assert.equal(nodes.length,1);assert(active.has(nodes[0]));assert.equal(nodes[0].startAt,118.1);assert.equal(nodes[0].stopAt,121.5);
  assert.equal(nodes[0].target,host.master);assert.equal(nodes[0].buffer.channels.length,2);
  const shared=audio.dockPCM(48000,3.4,.25,2.6);
  for(let channel=0;channel<2;channel++)assert.equal(Buffer.compare(Buffer.from(nodes[0].buffer.channels[channel].buffer),Buffer.from(shared[channel].buffer)),0);
  const pcmStarted=nodes[0].startAt;vm.runInContext('stopSounds();',host);
  assert.equal(active.size,0);assert.equal(nodes[0].stopAt,undefined);assert.equal(nodes[0].startAt,pcmStarted);
  assert.equal(host.canvas.dataset.activeAudioSources,'0');assert.equal(host.soundGeneration,1);
  nodes[0].onended();assert.equal(nodes[0].disconnected,true);
  const renders=[];
  for (const language of ['zh','en']) {
    for (const time of [1.3,6.6,8.1,19.3,19.8,20.5,21.1,21.8]) renders.push(await capture(1702,1016,time,language));
    for (const time of [1.3,6.6,21.1]) renders.push(await capture(380,500,time,language));
    renders.push(await capture(970,606,21.1,language,true));
  }
  fs.writeFileSync(path.join(output,'offline-checks.json'),JSON.stringify({result:'passed',resizeChecks,morphChecks,audioChecks,
    unchanged:['V6 island drawing','V6 four-card paths','all pre-dock audio cues','22-second timeline','R8 setup/install and review behavior'],
    states:['idle','thinking','orbit'],renders,limitations:'Offline source/CSS model and static canvas/SVG rendering only. Browser fullscreen, timing, output audio and user visual acceptance pending.'},null,2)+'\n');
  console.log(`PASS: ${resizeChecks.length} same-time resize checks at .7 diameter; ${morphChecks.length} original-engine morph samples; reduced motion frozen; ${audioChecks.length} deterministic PCM rates without clipping; actual host buffer/schedule/cancel; pre-dock cues and setup unchanged; ${renders.length} offline renders.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
