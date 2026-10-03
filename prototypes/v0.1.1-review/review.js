"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const duration = AIslandIntroScene.duration;
  const timeline = AIslandIntroScene.timeline;
  const nativeReview = Boolean(window.AIslandReviewHost?.native);
  const systemLanguage=window.AIslandReviewHost?.preferredLanguage||navigator.language||"en";
  const defaultIntroLocale=/^zh/i.test(systemLanguage)?"zh":"en";
  let introLocale=defaultIntroLocale;
  const introText=()=>AIslandIntroText[introLocale];
  const format=(template,values)=>template.replace(/\{(\w+)\}/g,(_,key)=>values[key]??"");
  if(nativeReview)document.documentElement.dataset.nativeReview="true";
  const canvas = $("stage"), ctx = canvas.getContext("2d");
  const colors = {paper:"#f1ead9", blue:"#6ea7ff", approval:"#f4a4a4", answer:"#ffd58a", mint:"#9ad3ad"};
  const events = {completion:{title:"任务完成",caption:"文档已经整理好。",color:colors.mint}, approval:{title:"等待审批",caption:"这一步，需要你的许可。",color:colors.approval}, answer:{title:"等待回答",caption:"给一点方向，任务就能继续。",color:colors.answer}};
  const choices = Object.fromEntries(Object.keys(events).map((key) => [key, {buffer:null,name:"默认试听样音"}]));
  let audioContext, master, activeSources = new Set(), playing = false, setup = false;
  let startClock = 0, clockUsesAudio = false, lastTime = 0, frame = 0, pendingCategory = null, importVersion = 0, soundGeneration = 0;
  let muted = false, reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let stageWidth=0,stageHeight=0,copyIndex=-1,framePrevious=0,frameGaps=[];
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
    if (audioContext.state !== "running") throw new Error(introText().status.audioUnavailable);
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
    if(key==="approval") { tone(246.94,at,.31,.12,"sine",220); }
    if(key==="answer") { tone(329.63,at,.72,.1,"sine",392); tone(659.25,at,.48,.035); }
  }
  function scheduleIntro(base) {
    // Anticipation, a low/mid resonant arrival, then space. Impact is not a global volume increase.
    swell(65.41,base+.08,1.27,.12,-.25);
    swell(130.81,base+.2,1.12,.065,.25);
    air(base+.28,1.06,.095,-.45);
    tone(65.41,base+1.35,1.45,.23,"sine",49);
    tone(130.81,base+1.35,1.1,.14,"sine",123.47);
    tone(196,base+1.37,1,.075);
    signature(base+1.35);
    air(base+1.42,1.18,.038,.5);
    // Each convergence has its own gesture; nine logos share one sound envelope.
    // The rejected opening tail stays removed. This begins in the separate logo scene.
    air(base+timeline.agents+.62,1.05,.08,-.3);
    swell(174.61,base+timeline.agents+.83,.83,.085,.3);
    tone(349.23,base+timeline.agents+1.47,.38,.065,"sine",261.63);
    // Task rows arrive with a short, low landing rather than the opening motif.
    tone(146.83,base+timeline.gather+.15,.23,.12,"sine",82.41);
    air(base+timeline.gather+.08,.32,.045,.25);
    tone(220,base+7.74,.24,.075,"sine",164.81);
    // A quiet mechanical seating sound lands at the hardware notch, not another fanfare.
    tone(110,base+timeline.settled,.2,.085,"sine",73.42);
    air(base+timeline.settled,.13,.035);
    eventSound("completion",base+timeline.completed);
    eventSound("approval",base+timeline.approval);
    eventSound("answer",base+timeline.answer);
  }
  const clamp=(x)=>Math.max(0,Math.min(1,x));
  function fitCanvas() { const r=canvas.getBoundingClientRect(),d=Math.min(devicePixelRatio||1,2);stageWidth=r.width;stageHeight=r.height;canvas.width=Math.round(r.width*d);canvas.height=Math.round(r.height*d);ctx.setTransform(d,0,0,d,0,0);draw(lastTime); }
  function draw(t) {
    AIslandIntroScene.syncMedia(t,{reduceMotion,setup,playing});
    AIslandIntroScene.draw(ctx,stageWidth,stageHeight,t,{reduceMotion,setup,playing,language:introLocale});
    $("stage-shell").dataset.surface=setup||t>=timeline.gather+.7&&t<timeline.approval||t>=timeline.back+.7?"light":"dark";
  }
  function updateCopy(t) {
    const index=t<timeline.agents?0:t<timeline.gather?1:t<timeline.approval?2:t<timeline.answer?3:t<timeline.back?4:t<timeline.completed?5:t<timeline.dock?6:7;
    const scene=introText().scenes[index];
    if(index!==copyIndex){
      copyIndex=index;$("scene-kicker").textContent=scene.kicker;$("scene-title").innerHTML=scene.title;$("scene-caption").textContent=nativeReview&&scene.nativeCaption?scene.nativeCaption:scene.caption;
      document.querySelectorAll(".scene-list li").forEach((el,i)=>el.classList.toggle("active",i===index));
    }
    $("progress-fill").style.transform=`scaleX(${clamp(t/duration)})`;
    $("play-state").textContent=playing?format(introText().status.playing,{time:t.toFixed(1),duration,muted:muted?introText().status.mutedSuffix:""}):introText().status.waiting;
  }
  function applyIntroLanguage() {
    const {page,controls,status,setup:copy,sceneList,description}=introText();
    document.documentElement.lang=introLocale==="zh"?"zh-CN":"en";
    document.documentElement.dataset.introLocale=introLocale;
    document.documentElement.dataset.systemLanguage=systemLanguage;
    document.title=page.title;
    const set=(selector,value,html=false)=>{const el=document.querySelector(selector);if(el){if(html)el.innerHTML=value;else el.textContent=value;}};
    set(".edition",page.edition);set("#intro .section-heading .eyebrow",page.eyebrow);
    set("#intro-heading",page.heading);set("#intro .section-heading>p",page.previewDescription);
    set(".curtain-label",page.curtainLabel);set("#start-curtain>p",page.curtainDescription);
    set(".director-panel>h3",page.directorTitle);set(".direction-description",page.directorDescription,true);
    set(".director-panel>.review-note",page.reviewNote);set("#language-note",description.languagePreview);
    set("#play",`▶ ${controls.play}`);set("#replay",controls.replay);set("#skip",controls.skip);
    set("#stage-mute",muted?controls.soundOff:controls.soundOn);
    set("#fullscreen",nativeReview?controls.exitReview:document.fullscreenElement?controls.exitFullscreen:controls.fullscreen);
    for(const [id,label] of [["intro-mute",controls.mute],["reduce-motion",controls.reduceMotion]]) {
      const input=$(id);input.parentElement.lastChild.textContent=label;
    }
    $("intro-language").setAttribute("aria-label",controls.languageLabel);
    $("intro-language").querySelector('[value="system"]').textContent=controls.followSystem;
    $("stage").setAttribute("aria-label",page.canvasLabel);
    document.querySelector(".brand").setAttribute("aria-label",page.brandLabel);
    document.querySelector(".review-tabs").setAttribute("aria-label",page.tabsLabel);
    for(const [id,label] of [["intro",page.introTab],["sound",page.soundTab],["sources",page.sourcesTab]])set(`[data-view="${id}"]`,label);
    document.querySelectorAll("[data-inspect]").forEach((el,i)=>{
      el.querySelector("span").textContent=sceneList[i].time;el.querySelector("b").textContent=sceneList[i].title;el.querySelector("small").textContent=sceneList[i].description;
    });
    set("#setup-preview>.eyebrow",copy.kicker);set("#setup-preview>h2",copy.title,true);
    set("#setup-preview>p",copy.description);set("#setup-next",copy.next);set("#setup-preview>small",copy.hint);
    document.querySelectorAll(".setup-options label").forEach((el,i)=>el.lastChild.textContent=copy.tools[i]);
    const footer=document.querySelector("footer");footer.firstChild.textContent=page.footer;footer.querySelector("span").textContent=page.footerHint;
    if($("native-review-exit")){$("native-review-exit").textContent=controls.nativeExit;$("native-review-exit").setAttribute("aria-label",controls.nativeExitLabel);}
    $("play-state").textContent=setup?status.chooseTools:status.waiting;copyIndex=-1;
  }
  function stopIntro() {playing=false;cancelAnimationFrame(frame);stopSounds();AIslandIntroScene.stopMedia();}
  function finishIntro() {
    stopIntro();setup=true;lastTime=duration;$("setup-preview").hidden=false;$("stage-copy").hidden=true;$("start-curtain").hidden=true;$("play-state").textContent=introText().status.chooseTools;$("progress-fill").style.transform="scaleX(1)";draw(duration);
    canvas.dataset.playbackMetrics=JSON.stringify({frames:frameGaps.length,maxGapMs:Math.max(0,...frameGaps.map(f=>f.gap)),gapsOver50:frameGaps.filter(f=>f.gap>50),transitions:frameGaps.filter(f=>[timeline.approval,timeline.answer].some(at=>Math.abs(f.at-at)<.3))});
  }
  function tick() {
    if(!playing)return;
    const now=performance.now();if(framePrevious)frameGaps.push({at:lastTime,gap:Math.round((now-framePrevious)*10)/10});framePrevious=now;
    const time=clockUsesAudio?audioContext.currentTime-startClock:performance.now()/1000-startClock;
    lastTime=Math.max(0,time);draw(lastTime);updateCopy(lastTime);
    if(lastTime>=duration)finishIntro();else frame=requestAnimationFrame(tick);
  }
  async function playIntro() {
    stopIntro();setup=false;$("setup-preview").hidden=true;$("stage-copy").hidden=false;
    copyIndex=-1;framePrevious=0;frameGaps=[];delete canvas.dataset.playbackMetrics;
    const generation=soundGeneration;
    $("play").disabled=true;
    try {
      await AIslandIntroScene.ready;
      if(generation!==soundGeneration||document.hidden)return;
      if(!muted) {await ensureAudio();if(generation!==soundGeneration||document.hidden)return;startClock=audioContext.currentTime+0.06;clockUsesAudio=true;scheduleIntro(startClock);}
      else {startClock=performance.now()/1000;clockUsesAudio=false;}
      playing=true;$("start-curtain").hidden=true;tick();
    } catch(error) {$("play-state").textContent=error.message;$("start-curtain").hidden=false;}
    finally {$("play").disabled=false;}
  }
  function showView(id) {
    stopIntro();document.querySelectorAll(".view").forEach(el=>el.classList.toggle("active",el.id===id));
    document.querySelectorAll("[data-view]").forEach(el=>el.setAttribute("aria-pressed",String(el.dataset.view===id)));
    if(id==="intro"&&!setup) {$("start-curtain").hidden=false;$("play-state").textContent=introText().status.waiting;}
    history.replaceState(null,"",`#${id}`);if(id==="intro")fitCanvas();
  }
  function setMuted(value) {
    muted=value;$("intro-mute").checked=value;$("stage-mute").setAttribute("aria-pressed",String(value));$("stage-mute").textContent=value?introText().controls.soundOff:introText().controls.soundOn;
    if(playing) {stopSounds();if(!value){stopIntro();$("start-curtain").hidden=false;$("play-state").textContent=introText().status.soundEnabled;}}
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
    draw(lastTime);updateCopy(lastTime);$("play-state").textContent=format(introText().status.still,{time:lastTime.toFixed(1)});
  }));
  document.querySelectorAll("[data-event]").forEach(el=>el.addEventListener("click",()=>playEvent(el.dataset.event)));
  $("play").addEventListener("click",playIntro);$("replay").addEventListener("click",playIntro);$("skip").addEventListener("click",finishIntro);
  $("stage-mute").addEventListener("click",()=>setMuted(!muted));$("intro-mute").addEventListener("change",e=>setMuted(e.target.checked));
  $("reduce-motion").addEventListener("change",e=>{reduceMotion=e.target.checked;draw(lastTime);});
  $("intro-language").addEventListener("change",e=>{
    stopIntro();introLocale=e.target.value==="system"?defaultIntroLocale:e.target.value;
    setup=false;lastTime=0;$("setup-preview").hidden=true;$("stage-copy").hidden=false;$("start-curtain").hidden=false;
    applyIntroLanguage();updateCopy(0);draw(0);
  });
  $("notification-mute").addEventListener("change",()=>{stopSounds();$("import-status").textContent=$("notification-mute").checked?"自动任务提示已静音。":"自动任务提示已开启。";});
  $("stop-audio").addEventListener("click",()=>{stopSounds();$("import-status").textContent="播放已停止。";});
  $("fullscreen").addEventListener("click",async()=>{try{if(nativeReview){stopIntro();window.webkit.messageHandlers.reviewHost.postMessage("close");}else if(document.fullscreenElement)await document.exitFullscreen();else await $("stage-shell").requestFullscreen();}catch(_){$("play-state").textContent=introText().status.fullscreenUnavailable;}});
  document.addEventListener("fullscreenchange",()=>{$("fullscreen").textContent=document.fullscreenElement?introText().controls.exitFullscreen:introText().controls.fullscreen;});
  $("setup-next").addEventListener("click",()=>{if(nativeReview){window.webkit.messageHandlers.reviewHost.postMessage("close");return;}if(document.fullscreenElement)document.exitFullscreen().catch(()=>{});showView("sources");});
  document.addEventListener("keydown",e=>{if(e.key==="Escape"&&playing)finishIntro();});
  document.addEventListener("visibilitychange",()=>{if(document.hidden){const wasPlaying=playing;stopIntro();if(wasPlaying){$("start-curtain").hidden=false;$("play-state").textContent=introText().status.paused;}}});
  window.addEventListener("pagehide",stopIntro);new ResizeObserver(fitCanvas).observe(canvas);
  renderSoundRows();showView(["intro","sound","sources"].includes(location.hash.slice(1))?location.hash.slice(1):"intro");applyIntroLanguage();updateCopy(0);
  AIslandIntroScene.ready.then(()=>draw(lastTime)).catch(()=>{$("play-state").textContent=introText().status.previewUnavailable;});
})();
