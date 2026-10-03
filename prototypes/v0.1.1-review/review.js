"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const duration = 22;
  const canvas = $("stage"), ctx = canvas.getContext("2d");
  const colors = {paper:"#f1ead9", blue:"#6ea7ff", approval:"#f4a4a4", answer:"#ffd58a", mint:"#9ad3ad"};
  const events = {completion:{title:"任务完成",caption:"文档已经整理好。",color:colors.mint}, approval:{title:"等待审批",caption:"这一步，需要你的许可。",color:colors.approval}, answer:{title:"等待回答",caption:"给一点方向，任务就能继续。",color:colors.answer}};
  const choices = Object.fromEntries(Object.keys(events).map((key) => [key, {buffer:null,name:"默认试听样音"}]));
  let audioContext, master, activeSources = new Set(), playing = false, setup = false;
  let startClock = 0, clockUsesAudio = false, lastTime = 0, frame = 0, pendingCategory = null, importVersion = 0, soundGeneration = 0;
  let muted = false, direction = "warm", reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const cueTimes = [1.65,3.7,6.4,9.4,11.8,14.2,16.2,18,20.5];
  $("reduce-motion").checked = reduceMotion;

  async function ensureAudio() {
    if (!audioContext) {
      audioContext = new AudioContext();
      master = audioContext.createGain(); master.gain.value = 0.7; master.connect(audioContext.destination);
    }
    if (audioContext.state === "suspended") await audioContext.resume();
    if (audioContext.state !== "running") throw new Error("浏览器未能开启声音，请重试。");
    return audioContext;
  }
  function track(node) {
    activeSources.add(node);
    node.onended = () => { activeSources.delete(node); node.disconnect(); };
    return node;
  }
  function stopSounds() {
    soundGeneration++;
    for (const source of activeSources) { try { source.stop(); } catch (_) {} }
    activeSources.clear();
  }
  function tone(freq, at, length, volume = 0.16, type = "sine", endFreq = freq) {
    const osc = track(audioContext.createOscillator()), gain = audioContext.createGain();
    osc.type = type; osc.frequency.setValueAtTime(freq,at); osc.frequency.exponentialRampToValueAtTime(endFreq,at+length);
    gain.gain.setValueAtTime(0,at); gain.gain.linearRampToValueAtTime(volume,at+Math.min(0.028,length/5));
    gain.gain.exponentialRampToValueAtTime(0.0001,at+length);
    osc.connect(gain); gain.connect(master); osc.start(at); osc.stop(at+length+0.02);
    osc.addEventListener("ended", () => gain.disconnect(), {once:true});
  }
  function air(at, length, volume = 0.05, pan = 0) {
    const source = track(audioContext.createBufferSource());
    const buffer = audioContext.createBuffer(1,Math.ceil(audioContext.sampleRate*length),audioContext.sampleRate);
    const pcm = buffer.getChannelData(0);
    // Deterministic noise keeps both directions repeatable during review.
    let seed = 91; for (let i=0;i<pcm.length;i++) { seed=(seed*16807)%2147483647; pcm[i]=(seed/2147483647*2-1); }
    source.buffer=buffer;
    const filter=audioContext.createBiquadFilter(), gain=audioContext.createGain(), panner=audioContext.createStereoPanner();
    filter.type="lowpass"; filter.frequency.setValueAtTime(500,at); filter.frequency.linearRampToValueAtTime(2600,at+length*0.5); filter.frequency.linearRampToValueAtTime(600,at+length);
    gain.gain.setValueAtTime(0,at); gain.gain.linearRampToValueAtTime(volume,at+length*0.4); gain.gain.linearRampToValueAtTime(0,at+length);
    panner.pan.value=pan; source.connect(filter); filter.connect(gain); gain.connect(panner); panner.connect(master);
    source.start(at); source.stop(at+length);
    source.addEventListener("ended",()=>{filter.disconnect();gain.disconnect();panner.disconnect();},{once:true});
  }
  function signature(at) {
    if (direction === "warm") { [261.63,392,523.25].forEach((f,i)=>tone(f,at+i*0.12,0.95-i*0.1,0.12)); }
    else { [523.25,659.25,783.99].forEach((f,i)=>tone(f,at+i*0.085,0.42,0.09,"triangle")); }
  }
  function eventSound(key,at) {
    const bright=direction==="digital", length=bright?0.32:0.65, type=bright?"triangle":"sine";
    if(key==="completion") { tone(bright?659.25:392,at,length,0.14,type); tone(bright?987.77:587.33,at+0.14,length,0.1,type); }
    if(key==="approval") { tone(bright?440:293.66,at,length*.6,0.12,type); tone(bright?440:293.66,at+0.24,length*.6,0.09,type); }
    if(key==="answer") { tone(bright?587.33:329.63,at,length,0.12,type); tone(bright?783.99:440,at+0.13,length,0.1,type); }
  }
  function scheduleIntro(base) {
    if (direction==="warm") {
      [130.81,196,261.63].forEach((f,i)=>tone(f,base+0.4+i*0.04,3.2,0.027));
      [196,261.63,392].forEach((f,i)=>tone(f,base+4.3+i*0.08,3.4,0.018));
    } else {
      [261.63,392,523.25].forEach((f,i)=>tone(f,base+0.45+i*0.16,1.1,0.025,"triangle"));
    }
    signature(base+1.65);
    air(base+3.7,direction==="warm"?0.75:0.38,0.065,-0.15);
    tone(direction==="warm"?164.81:329.63,base+6.4,0.36,0.11,"sine",direction==="warm"?130.81:261.63);
    eventSound("completion",base+9.4); eventSound("approval",base+11.8); eventSound("answer",base+14.2);
    tone(659.25,base+16.2,0.15,0.055);
    air(base+18,1.05,0.035,0.2);
    signature(base+20.5);
  }
  const clamp=(x)=>Math.max(0,Math.min(1,x));
  const ease=(x)=>{ x=clamp(x);return 1-Math.pow(1-x,3); };
  const smooth=(x)=>{x=clamp(x);return x*x*(3-2*x);};
  const lerp=(a,b,t)=>a+(b-a)*t;
  function rounded(x,y,w,h,r,fill) {ctx.fillStyle=fill;ctx.beginPath();ctx.roundRect(x,y,w,h,r);ctx.fill();}
  function disk(x,y,r,color,alpha=1) {ctx.globalAlpha=alpha;ctx.fillStyle=color;ctx.beginPath();ctx.arc(x,y,r,0,Math.PI*2);ctx.fill();ctx.globalAlpha=1;}
  function fitCanvas() { const r=canvas.getBoundingClientRect(),d=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(r.width*d);canvas.height=Math.round(r.height*d);ctx.setTransform(d,0,0,d,0,0);draw(lastTime); }
  function draw(t) {
    const w=canvas.clientWidth,h=canvas.clientHeight;
    ctx.clearRect(0,0,w,h);
    const glow=ctx.createRadialGradient(w*.68,h*.36,1,w*.6,h*.45,w*.75);
    glow.addColorStop(0,setup?"#1e3761":"#163a83");glow.addColorStop(.42,"#121e37");glow.addColorStop(1,"#0b0e16");ctx.fillStyle=glow;ctx.fillRect(0,0,w,h);
    if(setup) {disk(w*.77,h*.68,w*.26,"#173368",.15);return;}
    const collapse=reduceMotion?(t>=18?1:0):ease((t-18)/2.5);
    const awaken=reduceMotion?(t>=1?1:0):ease((t-.25)/1.45);
    const gather=reduceMotion?(t>=6.4?1:0):smooth((t-3.7)/2.7);
    const centerX=lerp(w*.64,w*.5,collapse),centerY=lerp(h*.38,27,collapse);
    const iw=lerp(lerp(18,Math.min(w*.38,320),awaken),136,collapse),ih=lerp(lerp(18,Math.min(h*.23,117),awaken),32,collapse);
    if(t>=16.2&&t<18.8) {
      const reveal=reduceMotion?1:ease((t-16.2)/.45),alpha=clamp((18.8-t)/.8)*reveal;
      const cw=Math.min(w*.42,350),ch=h*.24,x=w*.54-cw/2,y=h*.58;
      ctx.globalAlpha=alpha;rounded(x,y,cw,ch,10,"#23324d");
      ctx.fillStyle="#dce5f6";ctx.font='11px "PingFang SC",sans-serif';ctx.fillText("修改页面 · 演示会话",x+16,y+25);
      ctx.fillStyle="#7e94b8";ctx.font='9px "PingFang SC",sans-serif';ctx.fillText("已回到需要你审批的这个任务",x+16,y+47);
      rounded(x+16,y+64,cw*.65,4,2,"#6e8ab155");rounded(x+16,y+76,cw*.45,4,2,"#6e8ab133");ctx.globalAlpha=1;
    }
    // Sparse orbits converge into a single surface; no strobe or scene shake.
    if(!reduceMotion && t>2.4 && t<8) {
      const alpha=clamp((t-2.4)/.8)*clamp((8-t)/1.1);ctx.strokeStyle="#7aa6ff";ctx.lineWidth=1;
      for(let i=0;i<3;i++) {ctx.globalAlpha=alpha*.13;ctx.beginPath();ctx.ellipse(centerX,centerY,iw*.75+i*25,ih*.9+i*19,-.22,0,Math.PI*2);ctx.stroke();}ctx.globalAlpha=1;
    }
    const cardNames=["整理文档","修改页面","核对资料"];
    for(let i=0;i<3;i++) {
      const theta=(-.8+i*2.1)+(reduceMotion?0:t*.075), orbitX=centerX+Math.cos(theta)*w*.29, orbitY=centerY+Math.sin(theta)*h*.27;
      const arrival=reduceMotion?gather:ease((t-4.0-i*.3)/2.25), fade=clamp((t-2.7-i*.2)/.55)*(1-clamp((t-7.3)/.5));
      if(fade>0) {ctx.globalAlpha=fade;const x=lerp(orbitX,centerX,arrival),y=lerp(orbitY,centerY,arrival),scale=lerp(1,.28,arrival);ctx.save();ctx.translate(x,y);ctx.scale(scale,scale);
        rounded(-62,-22,124,44,10,"#263753");ctx.strokeStyle="#99b8ff55";ctx.lineWidth=1;ctx.stroke();disk(-43,0,3,[colors.blue,colors.paper,colors.mint][i]);ctx.fillStyle="#d6e1f5";ctx.font='10px "PingFang SC",sans-serif';ctx.fillText(cardNames[i],-30,4);ctx.restore();ctx.globalAlpha=1;}
    }
    // The flat top and rounded underside preserve AIsland's established notch silhouette.
    ctx.save();ctx.translate(centerX,centerY);ctx.shadowColor="#517eff40";ctx.shadowBlur=40*(1-collapse);
    rounded(-iw/2,-ih/2,iw,ih,[0,0,ih*.45,ih*.45],"#020308");ctx.shadowBlur=0;
    const running=t>=7.4&&t<9.4, approval=t>=11.8&&t<14.2, answer=t>=14.2&&t<16.2, complete=t>=9.4&&t<11.8;
    const tint=approval?colors.approval:answer?colors.answer:colors.paper;
    const e=ih*.18, gap=ih*.15;
    if(running) {for(let i=0;i<3;i++) disk((i-1)*ih*.26,Math.sin((t*4)-i*.9)*(reduceMotion?0:ih*.055),ih*.055,colors.paper);}
    else {const eyeWidth=ih*.083,eyeHeight=ih*.3;for(let i=0;i<2;i++) rounded((i===0?-gap:gap)-eyeWidth/2,-eyeHeight/2,eyeWidth,eyeHeight,eyeWidth/2,tint);}
    if(t>=9.4&&t<18) {const pulse=reduceMotion?1:1+Math.sin(t*1.5)*.06;disk(iw*.24,-ih*.11,e*.23*pulse,complete?colors.mint:colors.blue);}
    if(t>=16.2&&t<18) {ctx.strokeStyle="#80abff";ctx.lineWidth=1.7;ctx.beginPath();ctx.moveTo(iw*.35,ih*.1);ctx.lineTo(iw*.4,0);ctx.lineTo(iw*.33,-ih*.025);ctx.stroke();}
    ctx.restore();
    const shock=cueTimes.some(c=>t>=c&&t<c+.65)?cueTimes.filter(c=>c<=t).at(-1):null;
    if(shock!==null&&!reduceMotion) {const k=(t-shock)/.65;ctx.strokeStyle="#6ea7ff";ctx.globalAlpha=(1-k)*.13;ctx.lineWidth=1;ctx.beginPath();ctx.ellipse(centerX,centerY,iw*.55+k*35,ih*.55+k*20,0,0,Math.PI*2);ctx.stroke();ctx.globalAlpha=1;}
    if(t>=11.8&&t<16.2&&collapse===0) {const a=clamp((t-(answer?14.2:11.8))/.3);ctx.globalAlpha=a;rounded(centerX-iw*.42,centerY+ih*.65,iw*.84,31,8,"#25314b");ctx.fillStyle=approval?colors.approval:colors.answer;ctx.font='10px "PingFang SC",sans-serif';ctx.textAlign="center";ctx.fillText(approval?"允许一次    ·    拒绝":"告诉它，你想怎么继续",centerX,centerY+ih*.65+20);ctx.textAlign="start";ctx.globalAlpha=1;}
  }
  function updateCopy(t) {
    const scenes=t<3?["HELLO, AISLAND","让等待<br>有回应。","任务在继续，你可以做自己的事。"]:t<8?["ONE PLACE, MANY TASKS","把分散的任务，<br>汇到一起。","一眼，看见它们正在做什么。"]:t<9.4?["TASK A · DEMO","它们在忙，<br>你不必守着。","演示 · 整理文档，正在进行。"]:t<11.8?["TASK A · DEMO","完成了。","演示 · 整理文档，任务完成。"]:t<14.2?["TASK B · DEMO","这一步，<br>需要你点头。","演示 · 修改页面，等待审批。"]:t<16.2?["TASK C · DEMO","给一点方向，<br>它就能继续。","演示 · 核对资料，等待回答。"]:t<18?["BACK TO TASK B · DEMO","一点，<br>回到那个任务。","演示 · 返回修改页面的会话。"]:["ALWAYS WITHIN REACH","小小一座岛，<br>就在你眼前。","然后，选择你常用的工具。"];
    $("scene-kicker").textContent=scenes[0];$("scene-title").innerHTML=scenes[1];$("scene-caption").textContent=scenes[2];
    const index=t<3?0:t<8?1:t<16?2:3;document.querySelectorAll(".scene-list li").forEach((el,i)=>el.classList.toggle("active",i===index));
    $("progress-fill").style.width=`${clamp(t/duration)*100}%`;
    $("play-state").textContent=playing?`${t.toFixed(1)} / 22 秒${muted?" · 静音":""}`:"等待播放";
  }
  function stopIntro() {playing=false;cancelAnimationFrame(frame);stopSounds();}
  function finishIntro() {
    stopIntro();setup=true;lastTime=duration;$("setup-preview").hidden=false;$("stage-copy").hidden=true;$("start-curtain").hidden=true;$("play-state").textContent="选择工具 · 流程演示";$("progress-fill").style.width="100%";draw(duration);
  }
  function tick() {
    if(!playing)return;
    const time=clockUsesAudio?audioContext.currentTime-startClock:performance.now()/1000-startClock;
    lastTime=Math.max(0,time);draw(lastTime);updateCopy(lastTime);
    if(lastTime>=duration)finishIntro();else frame=requestAnimationFrame(tick);
  }
  async function playIntro() {
    stopIntro();setup=false;$("setup-preview").hidden=true;$("stage-copy").hidden=false;
    const generation=soundGeneration;
    $("play").disabled=true;
    try {
      if(!muted) {await ensureAudio();if(generation!==soundGeneration||document.hidden)return;startClock=audioContext.currentTime+0.06;clockUsesAudio=true;scheduleIntro(startClock);}
      else {startClock=performance.now()/1000;clockUsesAudio=false;}
      playing=true;$("start-curtain").hidden=true;tick();
    } catch(error) {$("play-state").textContent=error.message;$("start-curtain").hidden=false;}
    finally {$("play").disabled=false;}
  }
  function showView(id) {
    stopIntro();document.querySelectorAll(".view").forEach(el=>el.classList.toggle("active",el.id===id));
    document.querySelectorAll("[data-view]").forEach(el=>el.setAttribute("aria-pressed",String(el.dataset.view===id)));
    if(id==="intro"&&!setup) {$("start-curtain").hidden=false;$("play-state").textContent="等待播放";}
    history.replaceState(null,"",`#${id}`);if(id==="intro")fitCanvas();
  }
  function setMuted(value) {
    muted=value;$("intro-mute").checked=value;$("stage-mute").setAttribute("aria-pressed",String(value));$("stage-mute").textContent=value?"声音关闭":"声音开启";
    if(playing) {stopSounds();if(!value){stopIntro();$("start-curtain").hidden=false;$("play-state").textContent="声音已开启 · 请从头播放";}}
  }
  function renderSoundRows() {
    $("sound-rows").replaceChildren();
    for(const [key,event] of Object.entries(events)) {
      const row=document.createElement("div");row.className="sound-row";
      const top=document.createElement("div"), dot=document.createElement("span"), title=document.createElement("strong");dot.className=`status-dot ${key}`;title.textContent=event.title;top.append(dot,title);
      const detail=document.createElement("small");detail.textContent=choices[key].name+(choices[key].buffer?` · ${choices[key].buffer.duration.toFixed(1)} 秒`:"");
      const actions=document.createElement("div");actions.className="sound-actions";
      for(const [label,action] of [["试听",()=>playEvent(key,true)],[choices[key].buffer?"替换 MP3":"导入 MP3",()=>{pendingCategory=key;$("mp3-file").value="";$("mp3-file").click();}],["恢复默认",()=>{importVersion++;choices[key]={buffer:null,name:"默认试听样音"};stopSounds();renderSoundRows();$("import-status").textContent=`${event.title}已恢复默认试听样音。`;}]] ) {const button=document.createElement("button");button.textContent=label;button.setAttribute("aria-label",`${event.title} · ${label}`);button.addEventListener("click",action);actions.append(button);}
      row.append(top,detail,actions);$("sound-rows").append(row);
    }
  }
  async function playEvent(key,preview=false) {
    stopIntro();$("event-title").textContent=events[key].title;$("event-caption").textContent=events[key].caption;
    const generation=soundGeneration;
    if(!preview&&$("notification-mute").checked) {$("import-status").textContent="任务提示已静音；主动试听仍可播放。";return;}
    try {
      await ensureAudio();if(generation!==soundGeneration||document.hidden)return;stopSounds();const choice=choices[key];
      if(choice.buffer) {
        const source=track(audioContext.createBufferSource()),gain=audioContext.createGain();source.buffer=choice.buffer;source.connect(gain);gain.connect(master);
        const length=preview||$("clip-policy").value==="full"?choice.buffer.duration:Math.min(5,choice.buffer.duration),at=audioContext.currentTime;
        gain.gain.setValueAtTime(1,at);gain.gain.setValueAtTime(1,at+Math.max(0,length-.12));gain.gain.linearRampToValueAtTime(0,at+length);source.start(at,0,length);source.stop(at+length+.02);source.addEventListener("ended",()=>gain.disconnect(),{once:true});
        $("import-status").textContent=`${preview?"完整试听":"自动提示"}：${choice.name} · ${length.toFixed(1)} 秒`;
      } else {eventSound(key,audioContext.currentTime+.02);$("import-status").textContent=`${events[key].title} · 播放默认试听样音`;}
    }catch(error){$("import-status").textContent=error.message;}
  }
  $("mp3-file").addEventListener("change",async (event)=>{
    const file=event.target.files[0],key=pendingCategory;if(!file||!key)return;
    const version=++importVersion;$("import-status").textContent="正在检查音频…";
    try {
      if(!/\.mp3$/i.test(file.name))throw new Error("请选择 MP3 文件；原有选择已保留。");
      await ensureAudio();const buffer=await audioContext.decodeAudioData(await file.arrayBuffer());
      if(!Number.isFinite(buffer.duration)||buffer.duration<=0)throw new Error("音频没有可播放的内容。");
      if(version!==importVersion)return;
      choices[key]={buffer,name:file.name};renderSoundRows();$("import-status").textContent=`已为${events[key].title}选择 ${file.name}，可以试听。`;
    } catch (_) {if(version===importVersion)$("import-status").textContent="无法读取这个 MP3；原有选择已保留。";}
  });
  document.querySelectorAll("[data-view]").forEach(el=>el.addEventListener("click",()=>showView(el.dataset.view)));
  document.querySelectorAll("[name=direction]").forEach(el=>el.addEventListener("change",()=>{direction=el.value;stopIntro();if(!setup){$("start-curtain").hidden=false;$("play-state").textContent="声音方向已修改 · 从头播放";}}));
  document.querySelectorAll("[data-event]").forEach(el=>el.addEventListener("click",()=>playEvent(el.dataset.event)));
  $("play").addEventListener("click",playIntro);$("replay").addEventListener("click",playIntro);$("skip").addEventListener("click",finishIntro);
  $("stage-mute").addEventListener("click",()=>setMuted(!muted));$("intro-mute").addEventListener("change",e=>setMuted(e.target.checked));
  $("reduce-motion").addEventListener("change",e=>{reduceMotion=e.target.checked;draw(lastTime);});
  $("notification-mute").addEventListener("change",()=>{stopSounds();$("import-status").textContent=$("notification-mute").checked?"自动任务提示已静音。":"自动任务提示已开启。";});
  $("stop-audio").addEventListener("click",()=>{stopSounds();$("import-status").textContent="播放已停止。";});
  $("fullscreen").addEventListener("click",async()=>{try{if(document.fullscreenElement)await document.exitFullscreen();else await $("stage-shell").requestFullscreen();}catch(_){$("play-state").textContent="当前浏览器不支持全屏，可在浏览器窗口中观看。";}});
  document.addEventListener("fullscreenchange",()=>{$("fullscreen").textContent=document.fullscreenElement?"退出全屏 ↙":"全屏观看 ↗";});
  $("setup-next").addEventListener("click",()=>{if(document.fullscreenElement)document.exitFullscreen().catch(()=>{});showView("sources");});
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&playing)finishIntro();});
  document.addEventListener("visibilitychange",()=>{if(document.hidden){const wasPlaying=playing;stopIntro();if(wasPlaying){$("start-curtain").hidden=false;$("play-state").textContent="已暂停 · 返回后从头重播";}}});
  window.addEventListener("pagehide",stopIntro);new ResizeObserver(fitCanvas).observe(canvas);
  renderSoundRows();showView(["intro","sound","sources"].includes(location.hash.slice(1))?location.hash.slice(1):"intro");updateCopy(0);
})();
