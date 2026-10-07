// Native sprite export of the actual approved prototype SVG painter/Bloub engine.
// No browser, app, source profile or task session is opened. PNGs retain original
// masks, colors, paths and alpha. Only sampling/rasterization is new.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const {createCanvas,loadImage}=require('@napi-rs/canvas');
const root=path.resolve(__dirname,'..'),proto=path.join(root,'prototypes/v0.1.1-review');
const output=path.resolve(process.argv[2]||path.join(root,'Sources/OpenIslandApp/Resources/Onboarding'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const sandbox={window:{}};vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(proto,'assets/intro-bloub.js'),'utf8'),sandbox);
const engine=sandbox.window.AIslandIntroBloub;
const definitions={idle:{sampleStart:5.3,frames:80,size:256,stillTime:1},
  thinking:{sampleStart:7.95,frames:8,size:256,stillTime:1},
  orbit:{sampleStart:0,frames:100,size:1024,stillTime:2.5}};
async function render(state,time,size,name) {
  const frame=engine.sample(state,time),colors=state==='orbit'?[]:['#f2ead8','#04070d'];
  // The SVG viewBox spans 316 logical units. Without intrinsic dimensions,
  // loadImage rasterizes it at 316px before drawImage enlarges that bitmap.
  // Rasterize the unchanged paths directly at the existing resource size.
  const svg=engine.svg(frame,'native-bloub',...colors).replace('<svg ',`<svg width="${size}" height="${size}" `);
  const canvas=createCanvas(size,size),ctx=canvas.getContext('2d');
  const image=await loadImage(Buffer.from(svg));
  if(image.width!==size||image.height!==size)throw new Error(`SVG decoder dimensions differ from resource size: ${state}`);
  ctx.drawImage(image,0,0,size,size);
  const bytes=canvas.toBuffer('image/png');fs.writeFileSync(path.join(output,name),bytes);return hash(bytes);
}
(async()=>{
 fs.mkdirSync(output,{recursive:true});const manifest={revision:9,fps:30,sequences:{}},generated={};
 for(const [state,definition]of Object.entries(definitions)) {
  const files=[];
  for(let index=0;index<definition.frames;index++) {
   const name=`bloub-r9-${state}-${String(index).padStart(3,'0')}.png`;
   const sampleTime=index===0?definition.sampleStart:(Math.floor(definition.sampleStart*30+1e-9)+index)/30;
   generated[name]=await render(state,sampleTime,definition.size,name);files.push(name);
  }
  const stillFile=`bloub-r9-${state}-still.png`;
  generated[stillFile]=await render(state,definition.stillTime,definition.size,stillFile);
  manifest.sequences[state]={sampleStart:definition.sampleStart,sampleStep:1/30,width:definition.size,
   height:definition.size,files,stillFile,stillTime:definition.stillTime};
 }
 const manifestBytes=Buffer.from(JSON.stringify(manifest,null,2)+'\n');fs.writeFileSync(path.join(output,'bloub-r9.json'),manifestBytes);
 const sourceFiles=['prototypes/v0.1.1-review/intro-bloub.ts','prototypes/v0.1.1-review/assets/intro-bloub.js',
  'prototypes/v0.1.1-review/assets/intro-bloub-source.json','aisland-website/src/integrated-motion.ts',
  'prototypes/v0.1.1-review/assets/bloub-MIT.txt','scripts/generate-onboarding-r9-visuals.cjs',
  ...fs.readdirSync(path.join(root,'aisland-website/src/vendor/bloub')).filter(n=>n.endsWith('.ts')).map(n=>'aisland-website/src/vendor/bloub/'+n)];
 const provenance={revision:9,approvedVisual:'R9 user-approved visual; original website orbit state; R8 score handled separately',
  sourceCommit:'dec44c5e1b16e93e723f2c3335c385c0ad2f540c',
  generator:'scripts/generate-onboarding-r9-visuals.cjs; @napi-rs/canvas SVG decode at explicit intrinsic resource dimensions, transparent PNG at fixed sizes',
  rasterization:{svgIntrinsicDimensions:'width=height=resource size; viewBox and paths unchanged',avoids:'implicit 316px decode followed by bitmap enlargement',sizes:{idle:256,thinking:256,orbit:1024}},
  source_files_sha256:Object.fromEntries(sourceFiles.map(n=>[n,hash(fs.readFileSync(path.join(root,n)))])),
  manifest_file:'bloub-r9.json',manifest_sha256:hash(manifestBytes),generated_files_sha256:generated,
  geometry:{orbitDiameter:'min(viewportWidth*.68,viewportHeight*.66)*.7',orbitCenter:['viewportWidth/2','viewportHeight*.55'],
   leftCharacter:'centerX = island.centerX - island.width*.35; centerY = island.centerY; size = island.height*.82'},
  timing:{duration:22,gather:5.3,arrived:7.95,approval:8.2,orbitStart:18.1,orbitSettled:20.7,orbitSpeed:3.3/(20.7-18.1),orbitSourceEnd:3.3,
   orbitOpacity:'clamp((sceneTime-18.1)/.35)',reducedTime:{idle:1,thinking:1,orbit:2.5}},
  sampling:'30fps original engine samples, absolute scene ticks for glyphs and source-time ticks for orbit, matching prototype cache keys. Thinking enters at 7.95 (half-tick), then 7.96667/8.0/...; its first partial frame samples 7.95. Native samples hold until the next tick. No silhouette redraw or screenshot crossfade.',
  cache:'Native preloads compressed bytes, keeps only one decoded frame per sequence plus three reduced-motion stills. No full 100-frame retina predecode.',
  scope:'Brand illustration, not real task sessions or source integration evidence.'};
 fs.writeFileSync(path.join(output,'bloub-r9-provenance.json'),JSON.stringify(provenance,null,2)+'\n');
 fs.copyFileSync(path.join(proto,'assets/bloub-MIT.txt'),path.join(output,'bloub-MIT.txt'));
 console.log(`Exported ${Object.keys(generated).length} original-engine PNGs and manifest; ${Object.values(definitions).reduce((sum,d)=>sum+d.frames,0)} motion frames.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
