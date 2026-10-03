// Offline source/CSS checks and static canvas/SVG renders. No browser or app
// is launched; these artifacts cannot establish fullscreen or audio acceptance.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict'), {execFileSync} = require('node:child_process');
const {createCanvas, Image, loadImage, GlobalFonts} = require('@napi-rs/canvas');
// Offline renderer needs an explicit system CJK font. Browser uses its ordinary
// PingFang fallback; registering this font changes only these static artifacts.
const cjkFont = '/System/Library/Fonts/STHeiti Light.ttc';
if (fs.existsSync(cjkFont)) GlobalFonts.registerFromPath(cjkFont, 'PingFang SC');
const proto = __dirname, root = path.resolve(proto, '../..');
const output = path.resolve(process.argv[2] || path.join(root, 'output/verification/v0.1.1-intro-revision-7'));
const read = name => fs.readFileSync(path.join(proto, name), 'utf8');
const baseline = name => execFileSync('git', ['show', `32c94f2:prototypes/v0.1.1-review/${name}`], {cwd: root, encoding: 'utf8'});
const source = read('intro-scene.js'), oldSource = baseline('intro-scene.js');
for (const [start, end] of [['function gatherScene(', 'function mediaScene('], ['function island(', 'function draw(']]) {
  assert.equal(source.slice(source.indexOf(start), source.indexOf(end)), oldSource.slice(oldSource.indexOf(start), oldSource.indexOf(end)));
}
assert.equal(read('intro-audio.js'), baseline('intro-audio.js'));
assert.equal(read('review.js'), baseline('review.js'));
assert.equal(source.match(/const timeline = .*;/)[0], oldSource.match(/const timeline = .*;/)[0]);

// Evaluate selector specificity and media predicates on the actual CSS. The
// synthetic fullscreen state represents :fullscreen; it does not invoke it.
function cssRules(css, width, rules = []) {
  css = css.replace(/\/\*[\s\S]*?\*\//g, '');
  let at = 0;
  while (at < css.length) {
    const open = css.indexOf('{', at); if (open < 0) break;
    const selector = css.slice(at, open).trim(); let end = open + 1, depth = 1;
    while (depth && end < css.length) { if (css[end] === '{') depth++; if (css[end] === '}') depth--; end++; }
    const body = css.slice(open + 1, end - 1); at = end;
    if (selector.startsWith('@media')) {
      const maximum = selector.match(/max-width\s*:\s*(\d+)px/);
      if (!selector.includes('prefers-reduced-motion') && (!maximum || width <= +maximum[1])) cssRules(body, width, rules);
    } else if (!selector.startsWith('@')) {
      for (const entry of selector.split(',')) rules.push({selector: entry.trim(), declarations: Object.fromEntries(body.split(';').filter(x => x.includes(':')).map(x => { const p = x.indexOf(':'); return [x.slice(0,p).trim(), x.slice(p+1).trim()]; }))});
    }
  }
  return rules;
}
function matches(part, node) {
  const tag = part.match(/^[a-z][\w-]*/)?.[0]; if (tag && tag !== node.tag) return false;
  if ([...part.matchAll(/\.([\w-]+)/g)].some(x => !node.classes.includes(x[1]))) return false;
  if (part.includes(':fullscreen') && !node.fullscreen) return false;
  if ([...part.matchAll(/\[([\w-]+)(?:=["']?([^\]"']+)["']?)?\]/g)].some(x => node.attrs[x[1]] !== x[2])) return false;
  return true;
}
function style(css, {lang, fullscreen, native = false, scene = '0', width}, title = false) {
  const nodes = [{tag:'html',classes:[],attrs:{lang,...(native?{'data-native-review':'true'}:{})}},
    {tag:'div',classes:['stage-shell'],attrs:{'data-scene':scene},fullscreen},
    {tag:'div',classes:['stage-copy'],attrs:{}}];
  if (title) nodes.push({tag:'h2',classes:[],attrs:{}});
  const applied = {};
  cssRules(css, width).forEach(({selector,declarations}, order) => {
    const parts = selector.split(/\s+/); let index = nodes.length - 1;
    if (!matches(parts.pop(), nodes[index--])) return;
    while (parts.length) {
      const part = parts.pop(); while (index >= 0 && !matches(part, nodes[index])) index--;
      if (index-- < 0) return;
    }
    const weight = [(selector.match(/#/g)||[]).length, (selector.match(/\.|\[|:(?!:)/g)||[]).length,
      (selector.match(/(^|\s)[a-z][\w-]*/g)||[]).length, order];
    for (const [key,value] of Object.entries(declarations)) {
      const previous = applied[key]?.weight;
      if (!previous || weight.some((v,i) => v > previous[i] && weight.slice(0,i).every((x,j) => x === previous[j]))) applied[key] = {weight,value};
    }
  });
  return Object.fromEntries(Object.entries(applied).map(([key,{value}]) => [key,value]));
}
const css = read('review.css'), oldCSS = baseline('review.css');
const oldChinese = style(oldCSS,{lang:'zh-CN',fullscreen:true,width:1702});
assert.equal(oldChinese.left,'7%'); assert.equal(oldChinese.transform,'translateX(-50%)');
assert.equal(style(oldCSS,{lang:'en',fullscreen:true,width:1702}).left,'50%');
const cases = [];
for (const lang of ['zh-CN','en']) for (const [width,height] of [[380,500],[970,606],[1702,1016],[3440,1440]]) {
  for (const fullscreen of [false,true]) {
    const current = style(css,{lang,fullscreen,width});
    assert.equal(current.left,'50%'); assert.equal(current.width,'84%');
    assert.equal(current['max-width'],'none'); assert.equal(current.transform,'translateX(-50%)');
    assert.equal(style(css,{lang,fullscreen,width,scene:'7'}).top,'81%');
    if (width <= 640) assert.equal(style(css,{lang,fullscreen,width},true)['font-size'],'25px');
    const native = style(css,{lang,fullscreen:false,native:true,width}); assert.equal(native.left,'50%');
    cases.push({lang,width,height,fullscreen,left:current.left,widthPercent:current.width,homeTop:'81%'});
  }
}

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
assert.deepEqual(Array.from(bloub.outerStates),['egg','hexagon','play','idle','thinking','notify']);
for (const state of bloub.outerStates) {
  const frame = bloub.sample(state,1), svg = bloub.svg(frame,'test-'+state);
  assert(svg.includes(frame.bodyPath)); assert(svg.includes('<mask')); assert(!svg.includes('NaN'));
  assert.notEqual(svg,bloub.svg(bloub.sample(state,2),'test-'+state));
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
    assert(o.y-o.radius-o.size/2 > 0);
    assert(o.y+o.radius+o.size/2 < height*.81);
    ctx.save(); ctx.globalAlpha=+surfaces['home-orbit'].style.opacity;
    ctx.beginPath(); ctx.arc(o.x,o.y,o.radius,0,Math.PI*2);ctx.strokeStyle='#6c7dca30';ctx.stroke();
    for (const [i,{angle,state}] of o.agents.entries()) {
      const x=o.x+Math.cos(angle)*o.radius,y=o.y+Math.sin(angle)*o.radius;
      const svg=bloub.svg(bloub.sample(state,reduceMotion?1:time+i*.3),'capture-'+i);
      ctx.drawImage(await loadImage(Buffer.from(svg)),x-o.size/2,y-o.size/2,o.size,o.size);
      ctx.fillStyle='#60718f';ctx.font=`${Math.max(7,Math.min(11,width*.01))}px Menlo`;ctx.textAlign='center';
      ctx.fillText(`AGENT / 0${i+1}`,x,y+o.size*.5+10);
    }
    ctx.restore();
  }
  if(time<3||time>=20.7) {
    const title=sandbox.AIslandIntroText[language].scenes[time<3?0:7].title;
    const font=Math.max(width<=640?25:34,Math.min(74,width*.038));
    ctx.fillStyle=time<3?'#f1ead9':'#24354f';ctx.font=`500 ${font}px "Avenir Next", "PingFang SC",sans-serif`;
    ctx.textAlign='center';ctx.textBaseline='top';
    for (const [i,line] of title.split('<br>').entries()) {
      assert(ctx.measureText(line).width < width*.84);ctx.fillText(line,width/2,height*(time<3?.61:.81)+i*font*1.2);
    }
  }
  const name=`offline-${language}-${width}x${height}-${time.toFixed(2)}${reduceMotion?'-reduced':''}.png`;
  fs.writeFileSync(path.join(output,name),canvas.toBuffer('image/png'));return name;
}
(async()=>{
  await scene.ready; fs.mkdirSync(output,{recursive:true});
  const renders=[];
  for (const language of ['zh','en']) {
    for (const time of [1.3,6.6,8.1,21.1]) renders.push(await capture(1702,1016,time,language));
    for (const time of [1.3,6.6,21.1]) renders.push(await capture(380,500,time,language));
    renders.push(await capture(970,606,21.1,language,true));
  }
  fs.writeFileSync(path.join(output,'offline-checks.json'),JSON.stringify({result:'passed',cases,
    unchanged:['V6 island drawing','V6 four-card paths','22-second audio source','review controls/clock'],
    oldChineseFullscreen:{left:oldChinese.left,width:oldChinese.width,translate:oldChinese.transform,leftEdgePercent:-35},
    states:bloub.outerStates,renders,limitations:'Offline source/CSS model and static canvas/SVG rendering only. Browser fullscreen, timing, output audio and user visual acceptance pending.'},null,2)+'\n');
  console.log(`PASS: ${cases.length} CSS cases; V6 shell/cards/audio/controls unchanged; six exact engine states; ${renders.length} offline renders.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
