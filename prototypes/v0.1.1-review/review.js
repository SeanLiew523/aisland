"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const duration = AIslandIntroScene.duration;
  const canvas = $("stage"), ctx = canvas.getContext("2d");
  const colors = {paper:"#f1ead9", blue:"#6ea7ff", approval:"#f4a4a4", answer:"#ffd58a", mint:"#9ad3ad"};
  const events = {completion:{title:"任务完成",caption:"文档已经整理好。",color:colors.mint}, approval:{title:"等待审批",caption:"这一步，需要你的许可。",color:colors.approval}, answer:{title:"等待回答",caption:"给一点方向，任务就能继续。",color:colors.answer}};
  const choices = Object.fromEntries(Object.keys(events).map((key) => [key, {buffer:null,name:"默认试听样音"}]));
  let audioContext, master, activeSources = new Set(), playing = false, setup = false;
  let startClock = 0, clockUsesAudio = false, lastTime = 0, frame = 0, pendingCategory = null, importVersion = 0, soundGeneration = 0;
  let muted = false, reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  $("reduce-motion").checked = reduceMotion;

  async function ensureAudio() {
    if (!audioContext) {
      audioContext = new AudioContext();
      master = audioContext.createGain(); master.gain.value = 0.7;
      const compressor = audioContext.createDynamicsCompressor();
      compressor.threshold.value = -10; compressor.knee.value = 18; compressor.ratio.value = 4;
      compressor.attack.value = .006; compressor.release.value = .18;
      master.connect(compressor); compressor.connect(audioContext.destination);
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
    // Deterministic noise keeps the audio revision repeatable during review.
    let seed = 91; for (let i=0;i<pcm.length;i++) { seed=(seed*16807)%2147483647; pcm[i]=(seed/2147483647*2-1); }
    source.buffer=buffer;
    const filter=audioContext.createBiquadFilter(), gain=audioContext.createGain(), panner=audioContext.createStereoPanner();
    filter.type="lowpass"; filter.frequency.setValueAtTime(500,at); filter.frequency.linearRampToValueAtTime(2600,at+length*0.5); filter.frequency.linearRampToValueAtTime(600,at+length);
    gain.gain.setValueAtTime(0,at); gain.gain.linearRampToValueAtTime(volume,at+length*0.4); gain.gain.linearRampToValueAtTime(0,at+length);
    panner.pan.value=pan; source.connect(filter); filter.connect(gain); gain.connect(panner); panner.connect(master);
    source.start(at); source.stop(at+length);
    source.addEventListener("ended",()=>{filter.disconnect();gain.disconnect();panner.disconnect();},{once:true});
  }
  function swell(freq, at, length, volume, pan) {
    const osc=track(audioContext.createOscillator()),gain=audioContext.createGain(),panner=audioContext.createStereoPanner();
    osc.frequency.value=freq;osc.type="sine";
    gain.gain.setValueAtTime(0,at);gain.gain.linearRampToValueAtTime(volume*.12,at+length*.15);
    gain.gain.exponentialRampToValueAtTime(volume,at+length*.63);
    gain.gain.linearRampToValueAtTime(0,at+length);
    panner.pan.value=pan;osc.connect(gain);gain.connect(panner);panner.connect(master);osc.start(at);osc.stop(at+length+.02);
    osc.addEventListener("ended",()=>{gain.disconnect();panner.disconnect();},{once:true});
  }
  function signature(at, volume=1) {
    [261.63,392,523.25].forEach((f,i)=>tone(f,at+i*.12,.95-i*.1,.12*volume));
  }
  function eventSound(key,at) {
    if(key==="completion") { tone(392,at,.65,.14); tone(587.33,at+.14,.65,.1); }
    if(key==="approval") { tone(293.66,at,.39,.12); tone(293.66,at+.24,.39,.09); }
    if(key==="answer") { tone(329.63,at,.65,.12); tone(440,at+.13,.65,.1); }
  }
  function scheduleIntro(base) {
    // Anticipation, a low/mid resonant arrival, then space. Impact is not a global volume increase.
    swell(65.41,base+.08,1.57,.12,-.25);
    swell(130.81,base+.2,1.42,.065,.25);
    air(base+.28,1.36,.095,-.45);
    tone(65.41,base+1.65,1.6,.23,"sine",49);
    tone(130.81,base+1.65,1.2,.14,"sine",123.47);
    tone(196,base+1.67,1.15,.075);
    signature(base+1.65);
    air(base+1.72,1.5,.038,.5);
    air(base+4.3,1.05,.07,-.35);
    [196,261.63,392].forEach((f,i)=>swell(f,base+4.5+i*.08,3.0,.022,i*.25-.25));
    tone(164.81,base+8.6,.65,.12,"sine",130.81);
    eventSound("completion",base+11.4);eventSound("approval",base+14);eventSound("answer",base+17);
    tone(659.25,base+20,.15,.055);
    air(base+20,.5,.035,.2);
    air(base+23,1.35,.04,.35);
    signature(base+26.4,.65);
  }
  const clamp=(x)=>Math.max(0,Math.min(1,x));
  function fitCanvas() { const r=canvas.getBoundingClientRect(),d=Math.min(devicePixelRatio||1,2);canvas.width=Math.round(r.width*d);canvas.height=Math.round(r.height*d);ctx.setTransform(d,0,0,d,0,0);draw(lastTime); }
  function draw(t) {
    AIslandIntroScene.draw(ctx,canvas.clientWidth,canvas.clientHeight,t,{reduceMotion,setup});
    $("stage-shell").dataset.surface=setup||t>=5&&t<10.75||t>=20.65?"light":"dark";
  }
  function updateCopy(t) {
    const scenes=t<4.3?["HELLO, AISLAND","让等待<br>有回应。","任务在继续，你可以做自己的事。"]:t<10?["ONE PLACE, MANY TASKS","把分散的任务，<br>汇到一起。","文档、页面、资料。各有进展，一眼可见。"]:t<11.4?["TASK 01 · DEMO","它们在忙，<br>你不必守着。","演示 · 整理文档，正在进行。"]:t<14?["TASK 01 · DEMO","完成了。","演示 · 12 份文档，目录与摘要已整理。"]:t<17?["TASK 02 · DEMO","这一步，<br>需要你点头。","演示 · 看清修改，再决定是否允许。"]:t<20?["TASK 03 · DEMO","给一点方向，<br>它就能继续。","演示 · 先核对数据，还是文档结论？"]:t<23?["BACK TO TASK 02 · DEMO","一点，<br>回到那个任务。","演示 · 返回修改页面，继续这次审批。"]:["ALWAYS WITHIN REACH","小小一座岛，<br>就在你眼前。","留在屏幕顶部，随时给你回应。"];
    $("scene-kicker").textContent=scenes[0];$("scene-title").innerHTML=scenes[1];$("scene-caption").textContent=scenes[2];
    const index=t<4.3?0:t<10?1:t<14?2:t<17?3:t<20?4:t<23?5:6;document.querySelectorAll(".scene-list li").forEach((el,i)=>el.classList.toggle("active",i===index));
    $("progress-fill").style.width=`${clamp(t/duration)*100}%`;
    $("play-state").textContent=playing?`${t.toFixed(1)} / ${duration} 秒${muted?" · 静音":""}`:"等待播放";
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
  document.querySelectorAll("[data-inspect]").forEach(el=>el.addEventListener("click",()=>{
    stopIntro();setup=false;lastTime=Number(el.dataset.inspect);
    $("setup-preview").hidden=true;$("stage-copy").hidden=false;$("start-curtain").hidden=true;
    draw(lastTime);updateCopy(lastTime);$("play-state").textContent=`静帧审阅 · ${lastTime.toFixed(1)} 秒 · 无声音`;
  }));
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
