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
// Approved hybrid: exact R9 geometry and complete R8 score, including docking.
const audioContext = {window:{}}; vm.createContext(audioContext);
vm.runInContext(read('intro-audio.js'),audioContext);
const r8Audio=execFileSync('git',['show','11037b9:prototypes/v0.1.1-review/intro-audio.js'],{cwd:root,encoding:'utf8'});
assert.equal(read('intro-audio.js'),r8Audio);
const originalAudioContext = {window:{}}; vm.createContext(originalAudioContext);
vm.runInContext(r8Audio,originalAudioContext);
const audio = audioContext.window.AIslandIntroAudio;
const timeline = JSON.parse(vm.runInNewContext(`${source.match(/const timeline = .*;/)[0]} JSON.stringify(timeline)`));
const score = audio.cueSheet(timeline), originalScore=originalAudioContext.window.AIslandIntroAudio.cueSheet(timeline);
const json = value => JSON.stringify(value);
assert.equal(json(score),json(originalScore));
assert.equal(json(score.filter(c=>c.at>=timeline.dock).map(c=>c.label)),json(['dock-low','dock-breath','dock-mid','settled','settled-breath']));
assert(!score.some(c=>c.kind==='dock'));
assert(score.every(c=>c.stopAt<=22));
const calls=[];
audio.schedule(100,timeline,Object.fromEntries(['tone','air','swell'].map(kind=>[kind,(...args)=>calls.push({kind,args})])));
assert.equal(calls.length,score.length);
score.forEach((cue,index)=>{
  const expected=cue.args.slice();expected[cue.kind==='air'?0:1]+=100;
  assert.equal(json(calls[index]),json({kind:cue.kind,args:expected}));
});
assert.throws(()=>audio.schedule(0,timeline,{tone(){},swell(){}}),/tone, air and swell primitives/);
const review=read('review.js');
const r8Review=execFileSync('git',['show','11037b9:prototypes/v0.1.1-review/review.js'],{cwd:root,encoding:'utf8'});
assert.equal(review,r8Review);
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
  const audioChecks=[{completeScoreEqualToR8:true,nativeWAVUnchanged:true,cueCount:score.length,homeCues:score.filter(c=>c.at>=timeline.dock)}];
  const renders=[];
  for (const language of ['zh','en']) {
    for (const time of [1.3,6.6,8.1,19.3,19.8,20.5,21.1,21.8]) renders.push(await capture(1702,1016,time,language));
    for (const time of [1.3,6.6,21.1]) renders.push(await capture(380,500,time,language));
    renders.push(await capture(970,606,21.1,language,true));
  }
  fs.writeFileSync(path.join(output,'offline-checks.json'),JSON.stringify({result:'passed',resizeChecks,morphChecks,audioChecks,
    unchanged:['V6 island drawing','V6 four-card paths','complete R8 audio score','22-second timeline','R8 setup/install and review behavior'],
    states:['idle','thinking','orbit'],renders,limitations:'Offline source/CSS model and static canvas/SVG rendering only. Browser fullscreen, timing, output audio and user visual acceptance pending.'},null,2)+'\n');
  console.log(`PASS: ${resizeChecks.length} same-time resize checks at .7 diameter; ${morphChecks.length} original-engine morph samples; reduced motion frozen; complete R8 score/source/schedule restored; native WAV preserved; setup unchanged; ${renders.length} offline renders.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
