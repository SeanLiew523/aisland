"use strict";
// A presentation-only scene. All task content is a demonstration, never runtime evidence.
window.AIslandIntroScene = (() => {
  const clamp = x => Math.max(0, Math.min(1, x));
  const smooth = x => { x = clamp(x); return x * x * (3 - 2 * x); };
  const ease = x => 1 - Math.pow(1 - clamp(x), 3);
  const lerp = (a, b, t) => a + (b - a) * t;
  const ink = "#202d43", blue = "#3878f4", paper = "#f7f5ee";
  const timeline = {agents:3, gather:5.3, running:8.2, approval:8.2, answer:10.7, back:13.2, completed:15.7, dock:18.1, settled:20.7, duration:22};
  // Logos are a separate brand scene, never a claim about runtime capability.
  const agents = [
    ["claude","Claude","png"],["chatgpt","ChatGPT","png"],["gemini","Gemini","png"],
    ["grok","Grok","svg"],["kimi","Kimi","png"],["minimax","MiniMax","png"],
    ["zcode","ZCode","png"],["deepseek","DeepSeek","svg"],["workbuddy","WorkBuddy","png"]
  ].map(([key,name,ext])=>({key,name,ext,image:new Image()}));
  const images = {};
  const clips = {};
  function loadImage(image,src) {
    return new Promise((resolve,reject)=>{image.onload=async()=>{
      try {await image.decode();resolve();}catch(error){reject(error);}
    };image.onerror=()=>reject(new Error(`素材未能载入：${src}`));image.src=src;});
  }
  const loads=agents.map(a=>loadImage(a.image,`assets/${a.key}.${a.ext}`));
  for(const lang of ["en","zh"])for(const key of ["sessions","approval","answer","completion","closed"]) {
    const still=new Image(),meta=window.AIslandNativeMedia[lang][key];
    const clip={still,meta,frames:[]};clips[`${lang}:${key}`]=clip;
    loads.push(loadImage(still,`assets/native-${key}-${lang}-still.png`));
    for(const page of meta.pages) {
      const atlas=new Image();
      loads.push(loadImage(atlas,`assets/${page.file}`).then(async()=>{
        for(let i=0;i<page.frames;i++) {
          const sx=(i%meta.columns)*meta.width,sy=Math.floor(i/meta.columns)*meta.height;
          // Pre-crop small textures before the audio clock starts. Large atlas uploads
          // at scene boundaries would stall frames even though the images were loaded.
          if(typeof createImageBitmap==="function") {
            clip.frames[page.offset+i]=await createImageBitmap(atlas,sx,sy,meta.width,meta.height);
          } else {
            const frame=document.createElement("canvas");frame.width=meta.width;frame.height=meta.height;
            frame.getContext("2d").drawImage(atlas,sx,sy,meta.width,meta.height,0,0,meta.width,meta.height);
            clip.frames[page.offset+i]=frame;
          }
        }
      }));
    }
  }
  images.rows={en:[],zh:[]};
  for(const lang of ["en","zh"])for(const key of ["claude","codex","gemini","workbuddy"]) {
    const image=new Image();images.rows[lang].push(image);
    loads.push(loadImage(image,`assets/native-row-${key}-${lang==="zh"?"zh-Hans":"en"}@2x.png`));
  }
  const ready=Promise.all(loads);
  const cueTimes = [1.35,4.47,5.45,7.74,timeline.completed,timeline.approval,timeline.answer];
  const palettes = [
    {at: 0, top: "#030711", bottom: "#091638", glow: "#2050c4"},
    {at: 1.35, top: "#071d53", bottom: "#123987", glow: "#487ffa"},
    {at: timeline.gather, top: "#eef2fd", bottom: "#c8d7f5", glow: "#f9f7f0"},
    {at: timeline.approval, top: "#1a1728", bottom: "#382b42", glow: "#65465f"},
    {at: timeline.answer, top: "#191d28", bottom: "#35322d", glow: "#706346"},
    {at: timeline.back, top: "#e7edf9", bottom: "#c1d3f3", glow: "#f7f6f0"},
    {at: timeline.completed, top: "#eaf1ef", bottom: "#cededc", glow: "#f7f6f0"},
    {at: timeline.dock, top: "#f0f2f8", bottom: "#dadfe9", glow: "#eef0f8"}
  ];
  function mix(a, b, t) {
    const aa = a.match(/\w\w/g).map(x => parseInt(x, 16));
    const bb = b.match(/\w\w/g).map(x => parseInt(x, 16));
    return `rgb(${aa.map((v, i) => Math.round(lerp(v, bb[i], t))).join(",")})`;
  }
  function rect(c, x, y, w, h, r, fill, stroke) {
    c.beginPath(); c.roundRect(x, y, w, h, r);
    if (fill) { c.fillStyle = fill; c.fill(); }
    if (stroke) { c.strokeStyle = stroke; c.lineWidth = 1; c.stroke(); }
  }
  function line(c, x, y, xx, yy, color, width = 1) {
    c.beginPath(); c.moveTo(x, y); c.lineTo(xx, yy); c.strokeStyle = color; c.lineWidth = width; c.stroke();
  }
  function text(c, value, x, y, size = 11, color = ink, weight = 400, mono = false) {
    c.fillStyle = color;
    c.font = `${weight} ${size}px ${mono ? '"SFMono-Regular", Menlo' : '"Avenir Next", "PingFang SC"'}, sans-serif`;
    c.fillText(value, x, y);
  }
  function dot(c, x, y, r, color) {
    c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fillStyle = color; c.fill();
  }
  function check(c, x, y, color, s = 1) {
    c.save(); c.translate(x, y); c.scale(s, s); c.lineCap = "round"; c.lineJoin = "round";
    c.beginPath(); c.moveTo(-4, 0); c.lineTo(-1, 3); c.lineTo(5, -4); c.strokeStyle = color; c.lineWidth = 1.5; c.stroke(); c.restore();
  }
  function agentMark(c,a,x,y,size) {
    if(a.image.complete&&a.image.naturalWidth)c.drawImage(a.image,x,y,size,size);
    else text(c,a.name,x,y+size*.7,Math.max(7,size*.22),"#7586a0",600);
  }
  function logoScene(c,t,x,y,s,motion) {
    if(t<timeline.agents||t>=timeline.gather)return;
    const coords=[[-190,-65],[-98,-120],[4,-143],[111,-113],[195,-48],[177,52],[83,95],[-38,100],[-148,53]];
    agents.forEach((a,i)=>{
      const local=t-timeline.agents-i*.045;
      const enter=motion?smooth(local/.35):1;
      const jump=motion?smooth((local-.83)/.74):0;
      const out=motion?1-smooth((local-1.44)/.18):1;
      const [dx,dy]=coords[i];
      const size=(37-jump*20)*s;
      const xx=x+dx*s*(1-jump),yy=y+dy*s*(1-jump)-(motion?Math.sin(jump*Math.PI)*32*s:0);
      c.save();c.globalAlpha=enter*out;c.translate(xx,yy);
      c.rotate(motion?(1-jump)*dx*.00022:0);
      rect(c,-size*.5,-size*.5,size,size,size*.23,"#f7f8fc");
      agentMark(c,a,-size*.45,-size*.45,size*.9);c.restore();
    });
  }
  function nativeTile(c,image,crop,x,y,width,rotation,alpha) {
    if(!image.naturalWidth)return;
    const [sx,sy,sw,sh]=crop,height=width*sh/sw;
    c.save();c.globalAlpha=alpha;c.translate(x,y);c.rotate(rotation);
    c.shadowColor="#142d6633";c.shadowBlur=17;c.shadowOffsetY=9;
    rect(c,-width/2,-height/2,width,height,10,"#0c0c0e");c.shadowBlur=0;c.shadowOffsetY=0;
    c.beginPath();c.roundRect(-width/2,-height/2,width,height,10);c.clip();
    c.drawImage(image,sx,sy,sw,sh,-width/2,-height/2,width,height);c.restore();
  }
  function gatherScene(c,t,x,y,s,motion,language) {
    if(t<timeline.gather||t>=timeline.running)return;
    // Native production rows, captured offline with four fixed example agents.
    // No label replacement or synthetic re-drawing of the native task form.
    images.rows[language].forEach((image,i)=>{
      const enter=motion?ease((t-timeline.gather-i*.09)/.45):1;
      const exit=motion?1-smooth((t-7.55)/.45):1;
      const travel=motion?smooth((t-7.55)/.45):0;
      const side=i%2===0?-1:1;
      const xx=x+side*(240+(1-enter)*70-travel*28)*s,yy=y+(i<2?-52:52)*s+(1-enter)*18*s;
      nativeTile(c,image,[0,0,image.naturalWidth,image.naturalHeight],xx,yy,(190-travel*40)*s,side*.025,enter*exit);
    });
    if(motion&&t>=7.55){
      c.save();c.globalAlpha=(1-smooth((t-7.55)/.55))*.3;
      [-1,1].forEach(side=>{c.beginPath();c.moveTo(x+side*145*s,y);c.quadraticCurveTo(x+side*113*s,y-29*s,x+side*106*s,y);c.strokeStyle="#6088c4";c.lineWidth=.8;c.stroke();});c.restore();
    }
  }
  function mediaScene(t) {
    if(t>=timeline.completed&&t<timeline.dock)return {key:"completion",start:timeline.completed,end:timeline.dock};
    if(t>=timeline.approval&&t<timeline.answer)return {key:"approval",start:timeline.approval,end:timeline.answer};
    if(t>=timeline.answer&&t<timeline.back)return {key:"answer",start:timeline.answer,end:timeline.back};
    if(t>=timeline.back&&t<timeline.completed)return {key:"sessions",start:timeline.back,end:timeline.completed};
    return null;
  }
  // Captured sprites share the same clock as the audio. No decoder drift or hidden loop.
  function stopMedia() {}
  function syncMedia() {}
  function nativeScene(c,t,x,y,s,motion,playing,language) {
    const scene=mediaScene(t);if(!scene)return 0;
    const enter=motion?ease((t-scene.start)/.16):1;
    const {frames,still,meta}=clips[`${language}:${scene.key}`],useMovie=playing&&motion&&frames.length===meta.frames;
    const index=Math.min(meta.frames-1,Math.floor(Math.max(0,t-scene.start)*meta.fps));
    const frame=useMovie?frames[index]:still;if(!frame?.width)return 1;
    const width=490*s,height=width*meta.height/meta.width;
    // A single opaque panel reveals vertically. Never crossfade two black surfaces,
    // and never play the source's translucent expansion a second time.
    c.save();c.translate(x,y-32*s);
    c.beginPath();c.rect(-width/2-2,0,width+4,height*enter);c.clip();
    c.drawImage(frame,-width/2,0,width,height);
    c.restore();
    const visible=meta.visible_heights[useMovie?index:meta.still_frame]/meta.width*width;
    if(enter>.98)text(c,language==="zh"?"AISLAND · 站点原生录制 / 示例会话":"AISLAND · Native recording / example sessions",x-width/2,y-32*s+visible+14*s,7*s,t>=timeline.back?"#6a7f9f":"#8fa4c6",500);
    return 1;
  }
  function closedIsland(c,x,y,width,height,t,playing,motion,language) {
    const {frames,still,meta}=clips[`${language}:closed`];
    const index=Math.floor(Math.max(0,t-timeline.dock)*meta.fps)%meta.frames;
    const frame=playing&&motion&&frames.length===meta.frames?frames[index]:still;
    if(frame?.width)c.drawImage(frame,x-width/2,y-height/2,width,height);
  }
  function background(c, w, h, t, motion, setup) {
    const time = setup ? timeline.duration : t;
    let index = palettes.findLastIndex(p => p.at <= time);
    index = Math.max(0, index);
    const current = palettes[index], previous = palettes[Math.max(0, index - 1)];
    const fade = motion ? smooth((time - current.at) / 1.25) : 1;
    const top = mix(previous.top, current.top, fade), bottom = mix(previous.bottom, current.bottom, fade);
    const gradient = c.createLinearGradient(0, 0, w * .16, h);
    gradient.addColorStop(0, top); gradient.addColorStop(1, bottom); c.fillStyle = gradient; c.fillRect(0, 0, w, h);
    const gx = w * (.63 + (motion ? Math.sin(time * .12) * .06 : 0));
    const gy = h * (.34 + (motion ? Math.cos(time * .18) * .06 : 0));
    const halo = c.createRadialGradient(gx, gy, 0, gx, gy, w * .65);
    halo.addColorStop(0, mix(previous.glow, current.glow, fade)); halo.addColorStop(1, "#ffffff00");
    c.globalAlpha = .45; c.fillStyle = halo; c.fillRect(0, 0, w, h); c.globalAlpha = 1;
    if (time < timeline.gather) {
      const opening = motion ? ease((time - .4) / 2.2) : 1;
      c.save(); c.translate(w * .64, h * .36); c.rotate(-.28);
      const sweep = c.createLinearGradient(-w * .7, 0, w * .7, 0);
      sweep.addColorStop(0, "#6c9aff00"); sweep.addColorStop(.5, "#91b4ff"); sweep.addColorStop(1, "#6c9aff00");
      c.globalAlpha = opening * .15; c.fillStyle = sweep; c.fillRect(-w, -h * .12, w * 2, h * .17);
      c.globalAlpha = opening * .12; c.fillRect(-w, h * .11, w * 2, 1);
      c.restore();
      // A continuous aperture opens into depth; no brightness flashes or camera shake.
      c.save(); c.translate(w * .64, h * .36); c.scale(1, .45);
      for (let i = 0; i < 5; i++) {
        const radius = (w * .13 + i * w * .056) * (.35 + opening * .9);
        c.globalAlpha = opening * (.17 - i * .025); c.strokeStyle = "#adc9ff"; c.lineWidth = i === 0 ? 1.5 : .6;
        c.beginPath(); c.arc(0, 0, radius, 0, Math.PI * 2); c.stroke();
      }
      c.restore();
    } else if (time < timeline.running || time >= timeline.back) {
      c.save(); c.globalAlpha = .16; c.translate(w * .88, h * .47); c.rotate(-.5);
      c.fillStyle = "#7f9cca"; c.fillRect(-w * .08, -h, w * .17, h * 2);
      c.fillStyle = "#ffffff"; c.fillRect(-w * .22, -h, w * .12, h * 2); c.restore();
      if (time >= timeline.dock) {
        c.globalAlpha = smooth((time - timeline.dock) / 1.1) * .52;
        rect(c, w * .18, h * .33, w * .7, h * .57, 16, "#ffffff88", "#ffffffa0");
        c.globalAlpha = 1;
      }
    } else {
      c.save(); c.globalAlpha = .18;
      for (let i = 0; i < 35; i++) dot(c, ((i * 137.5) % 997) / 997 * w, ((i * 213.2) % 631) / 631 * h, .7, "#b4c8e4");
      c.restore();
    }
    // A restrained grain supplies material detail without independent motion.
    c.save(); c.globalAlpha = .023;
    for (let i = 0; i < 500; i++) {
      const x = ((i * 73.13) % 997) / 997 * w, y = ((i * 39.71) % 631) / 631 * h;
      c.fillStyle = "#fff"; c.fillRect(x, y, 1, 1);
    }
    c.restore();
  }
  function island(c, width, height, t, scale, collapse, host) {
    c.save(); c.shadowColor = t < timeline.gather ? "#000c" : "#07163050";
    c.shadowBlur = 30 * scale; c.shadowOffsetY = 12 * scale;
    rect(c, -width / 2, -height / 2, width, height, [0, 0, height * .44, height * .44], "#04070d");
    c.shadowBlur = 0; c.shadowOffsetY = 0;
    const running = false, approval = t >= timeline.approval && t < timeline.answer, answer = t >= timeline.answer && t < timeline.back;
    const tint = approval ? "#eeb4b5" : answer ? "#eed18e" : "#f2ead8";
    if (running) {
      for (let i = 0; i < 3; i++) dot(c, (i - 1) * height * .23, 0, height * .047, tint);
    } else {
      const gap = height * .13, ew = height * .075, eh = height * .3;
      const wings=host ? [host.hardwareLeft-host.x-host.width/2-22,host.hardwareRight-host.x-host.width/2+22] : [-width*.39,width*.39];
      [-gap,gap].forEach((x,i)=>{x=lerp(x,wings[i],collapse);rect(c,x-ew/2,-eh/2,ew,eh,ew/2,tint);});
    }
    if (collapse < .8) dot(c, width * .27, -height * .11, Math.max(2, 3 * scale), t >= timeline.completed && t < timeline.approval ? "#add0aa" : "#6ea7ff");
    line(c, -width * .36, -height / 2 + 1, width * .36, -height / 2 + 1, "#ffffff0e");
    c.restore();
  }
  function draw(c,w,h,t,{reduceMotion=false,setup=false,playing=false,language="zh"}={}) {
    const motion=!reduceMotion;c.clearRect(0,0,w,h);background(c,w,h,t,motion,setup);
    const narrow=w<640;
    const s=Math.min(w/(narrow?740:1010),h/630);
    const cx=w*(narrow?.53:.65),cy=h*(narrow?.27:.34);
    const awaken=motion?ease((t-.4)/.95):t>=.4?1:0;
    const collapse=motion?smooth((t-timeline.dock)/2.6):t>=timeline.dock?1:0;
    const host=window.AIslandReviewHost?.notch;
    const targetW=host?host.width:Math.min(277,w*.27),targetH=host?host.height:Math.min(32,32*s);
    const targetX=host?host.x+host.width/2:w*.5;
    const x=lerp(cx,targetX,collapse),y=lerp(cy,targetH/2,collapse);
    const gather=smooth((t-timeline.agents)/.4);
    const iw=lerp(lerp(20,282*s,awaken)*(1-gather*.23),targetW,collapse);
    const ih=lerp(lerp(20,83*s,awaken)*(1-gather*.16),targetH,collapse);
    if(!setup){logoScene(c,t,cx,cy,s,motion);gatherScene(c,t,cx,cy,s,motion,language);}
    const nativeAlpha=setup?0:nativeScene(c,t,cx,cy,s*(narrow?.88:1),motion,playing,language);
    if(setup||t>=timeline.dock) {
      // The actual website collapsed pill: character on the left, agent grid on the
      // right. Its empty middle lies behind the hardware notch in the native host.
      const width=setup?targetW:lerp(277*s,targetW,collapse);
      const height=setup?targetH:lerp(32*s,targetH,collapse);
      closedIsland(c,setup?targetX:x,setup?targetH/2:y,width,height,t,playing,motion,language);
    } else if(!nativeAlpha) {
      c.save();c.translate(x,y);island(c,iw,ih,t,s,0,host);c.restore();
    }
    // Native clips provide their own production animation; only the opening gets an extra pulse.
    if(t>=1.35&&t<2.45&&motion){
      const elapsed=(t-1.35)/1.1;c.save();c.translate(x,y);c.globalAlpha=(1-elapsed)*.32;
      c.strokeStyle="#bfd8ff";c.lineWidth=.9;c.beginPath();c.ellipse(0,0,iw*.6+elapsed*75*s,ih*.64+elapsed*28*s,0,0,Math.PI*2);c.stroke();c.restore();
    }
  }
  return {draw,syncMedia,stopMedia,duration:timeline.duration,timeline,cueTimes,ready};
})();
