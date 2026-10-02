import { BotEngine, type BotFrame } from './vendor/bloub/engine';
import { NOTIF_BLUE } from './vendor/bloub/decor';
import { mixHex } from './vendor/bloub/skins';
import { DEMI_VIEWBOX, RAYON } from './vendor/bloub/repere';
import type { StateId } from './vendor/bloub/states';

const $ = <T extends HTMLElement = HTMLElement>(s: string) => document.querySelector<T>(s)!;
const clamp = (v: number) => Math.max(0, Math.min(1, v));
const smooth = (a: number, b: number, p: number) => { const t = clamp((p - a) / (b - a)); return t * t * (3 - 2 * t); };
const ink = '#09090b', paper = '#f4f4f0';
const tx = (zh: string, en: string) => document.documentElement.lang === 'en' ? en : zh;
const media = matchMedia('(prefers-reduced-motion: reduce)');
const experiment = $('.motion-experiment'), visual = $('.scene-visual'), art = $('.scene-art');
const central = $('#central-bot'), arrival = $('.island-arrival'), satellites = $('.satellites'), grid = $('.scene-grid');
const toggle = $<HTMLButtonElement>('.motion-toggle');
const PLAYBACK_RATE = 1.5, BASE_DURATION = 16, DURATION = BASE_DURATION / PLAYBACK_RATE;
const HOLD = .65, RESET_FADE = .18, CYCLE_DURATION = DURATION + HOLD + RESET_FADE;
const ids = new WeakMap<Element, string>();
let uid = 0;

// Back arcs → opaque paper backing → body with eye holes → front arcs.
// Eye holes must not reveal arcs that are physically behind the body.
function paint(host: HTMLElement, f: BotFrame, color = ink, background = paper) {
  let id = ids.get(host); if (!id) { id = `bloub-${++uid}`; ids.set(host, id); }
  const half = DEMI_VIEWBOX, side = half * 2;
  const gradients = f.arcs.map(a => `<linearGradient id="${id}-${a.id}" gradientUnits="userSpaceOnUse" x1="${a.grad.x1}" y1="${a.grad.y1}" x2="${a.grad.x2}" y2="${a.grad.y2}">${a.grad.stops.map((c, i, stops) => `<stop offset="${i / (stops.length - 1)}" stop-color="${c}"/>`).join('')}</linearGradient>`).join('');
  const rings = (side: 'back' | 'front') => `<g fill="none" stroke-linecap="round">${f.arcs.map(a => `<path d="${a[side]}" stroke="url(#${id}-${a.id})" stroke-width="${a.width}" opacity="${a.opacity}"/>`).join('')}</g>`;
  const dots = () => f.dots.map(d => {
    const color = d.color ?? (d.depth === undefined ? ink : mixHex(background, ink, d.depth));
    return d.d ? `<path d="${d.d}" transform="translate(${d.x} ${d.y}) rotate(${d.rot ?? 0}) scale(${RAYON})" fill="${color}" opacity="${d.opacity}"/>` : `<circle cx="${d.x}" cy="${d.y}" r="${d.r}" fill="${color}" opacity="${d.opacity}"/>`;
  }).join('');
  host.innerHTML = `<svg viewBox="-${half} -${half} ${side} ${side}" aria-hidden="true"><defs>${gradients}<mask id="${id}-eyes" maskUnits="userSpaceOnUse" x="-${half}" y="-${half}" width="${side}" height="${side}"><path d="${f.bodyPath}" fill="white"/>${f.eyes.map(e => `<path d="${e.d}" transform="${e.matrix}" fill="black" opacity="${e.alpha}"/>`).join('')}${f.notch ? `<circle cx="${f.notch.x}" cy="${f.notch.y}" r="${f.notch.r}" fill="black"/>` : ''}</mask></defs>${rings('back')}${f.dotsBehind ? dots() : ''}<g opacity="${f.bodyAlpha}"><path d="${f.bodyPath}" fill="${background}"/><g mask="url(#${id}-eyes)"><rect x="-${half}" y="-${half}" width="${side}" height="${side}" fill="${color}"/></g></g>${!f.dotsBehind ? dots() : ''}${f.notif ? `<circle cx="${f.notif.x}" cy="${f.notif.y}" r="${f.notif.r}" fill="${NOTIF_BLUE}"/>` : ''}${rings('front')}</svg>`;
}



const orbitEngine = new BotEngine(RAYON, 'orbit');
const outerStates: StateId[] = ['egg', 'hexagon', 'play', 'idle', 'thinking', 'notify'];
const outer = outerStates.map((state, i) => {
  const el = document.createElement('div'); el.className = 'satellite';
  const bot = document.createElement('div'); bot.className = 'bot-surface';
  const label = document.createElement('span'); label.className = 'satellite-label'; label.textContent = `AGENT / 0${i + 1}`;
  el.append(bot, label); satellites.append(el);
  return { el, bot, engine: new BotEngine(RAYON, state), angle: i * Math.PI / 3 - Math.PI / 2 };
});

let progress = media.matches ? 1 : 0, elapsed = media.matches ? DURATION : 0;
let playing = false, hasStarted = false, manuallyPaused = false, visible = false, eligible = false;
let pointerX = 0, pointerY = 0, cycles = 0, raf = 0, lastStamp = 0, paintElapsed = 0;
experiment.dataset.playbackRate = String(PLAYBACK_RATE);
experiment.dataset.duration = DURATION.toFixed(3);
experiment.dataset.cycleDuration = CYCLE_DURATION.toFixed(3);
experiment.dataset.cycles = '0';

function updateCopy() {
  $('#motion-heading').innerHTML = tx('不同的伙伴。<br>同一个岛。', 'Different agents.<br>One island.');
  $('#motion-copy').innerHTML = tx('把分散的会话聚在一起。<br>少些切换，把注意力留给眼前的工作。', 'Bring your sessions together.<br>Less switching. More focus on the work in front of you.');
  visual.setAttribute('aria-label', tx('从多个角色汇聚到 AIsland 的品牌动效', 'Brand animation: scattered characters converge into AIsland'));
  $('.island-arrival img').setAttribute('alt', tx('AIsland 标识', 'AIsland logo'));
  updateState();
}
function updateState() {
  const active = playing && visible && !document.hidden && !media.matches;
  experiment.dataset.playing = String(active);
  toggle.hidden = media.matches;
  const label = manuallyPaused ? tx('继续动效', 'Resume animation') : tx('暂停动效', 'Pause animation');
  toggle.setAttribute('aria-label', label); toggle.title = label;
  toggle.setAttribute('aria-pressed', String(manuallyPaused));
}
function stopClock() { cancelAnimationFrame(raf); raf = 0; lastStamp = 0; paintElapsed = 0; }
function start() {
  if (media.matches || manuallyPaused) return;
  hasStarted = true; playing = true; updateState(); wake();
}
function render() {
  visual.dataset.progress = progress.toFixed(3);
  const gather = smooth(.15, .72, progress);
  const appear = smooth(.46, .49, progress), outerFade = 1 - smooth(.45, .48, progress);
  const final = smooth(.92, .96, progress);
  // Rest briefly on the logo, then fade to paper before the next scattered frame.
  // This reset has no simultaneous bodies or extra crossfade shadows.
  const reset = clamp((elapsed - DURATION - HOLD) / RESET_FADE);
  art.style.opacity = String(media.matches ? 1 : smooth(0, .02, progress) * (1 - reset));
  paint(central, orbitEngine.sample(clamp((progress - .23) / .64) * 3.3));
  central.style.transform = `scale(${.6 + appear * .4 - final * .48})`;
  central.style.opacity = String(appear * (1 - final));
  arrival.style.opacity = String(final); arrival.setAttribute('aria-hidden', String(final < .8));
  arrival.style.transform = `translateY(${(1 - final) * 10}px) scale(${.97 + final * .03})`;
  grid.style.opacity = String(.65 * (1 - final));
  const radius = Math.min(visual.clientWidth * .34, 154) * (1 - gather);
  outer.forEach(({ el, bot, engine, angle }, i) => {
    const x = Math.cos(angle) * radius + pointerX * 5 * (1 - gather);
    const y = Math.sin(angle) * radius * .9 + pointerY * 5 * (1 - gather);
    el.style.transform = `translate(${x.toFixed(2)}px, ${y.toFixed(2)}px) scale(${1 - gather * .45})`;
    el.style.opacity = String(outerFade);
    paint(bot, engine.sample(media.matches ? 1 : progress * BASE_DURATION * .7 + i * .3));
  });
  visual.dataset.state = progress < .46 ? 'SCATTERED' : progress < .96 ? 'ORBIT' : 'ONE ISLAND';
  $('#pose-name').textContent = progress < .15 ? 'MANY AGENTS' : progress < .92 ? 'IN SYNC' : 'ONE ISLAND';
}
function wake() {
  if (raf || !playing || !visible || document.hidden || media.matches) return;
  lastStamp = 0; paintElapsed = 0; raf = requestAnimationFrame(tick);
}
function tick(stamp: number) {
  raf = 0; if (!playing || !visible || document.hidden || media.matches) return;
  const dt = lastStamp ? Math.min(.1, (stamp - lastStamp) / 1000) : 0;
  lastStamp = stamp; paintElapsed += dt;
  if (paintElapsed >= 1 / 30) {
    elapsed += paintElapsed; paintElapsed = 0;
    if (elapsed >= CYCLE_DURATION) {
      elapsed %= CYCLE_DURATION; experiment.dataset.cycles = String(++cycles);
    }
    progress = clamp(elapsed / DURATION); render();
  }
  raf = requestAnimationFrame(tick);
}
const observer = new IntersectionObserver(entries => {
  for (const entry of entries) {
    visible = entry.isIntersecting && entry.intersectionRatio > .1;
    eligible = entry.isIntersecting && entry.intersectionRatio >= .55;
    if (eligible && !hasStarted && !document.hidden) start();
    if (!visible) stopClock();
  }
  updateState(); wake();
}, { threshold: [0, .1, .55] });
observer.observe(visual);
// The graphic itself provides keyboard/click pause without preview controls.
toggle.addEventListener('click', () => {
  if (media.matches) return;
  manuallyPaused = !manuallyPaused;
  if (manuallyPaused) { playing = false; stopClock(); updateState(); }
  else start();
});
visual.addEventListener('pointermove', e => {
  if (media.matches || e.pointerType !== 'mouse') return;
  const box = visual.getBoundingClientRect();
  pointerX = Math.max(-1, Math.min(1, (e.clientX - box.left - box.width / 2) / (box.width / 2)));
  pointerY = Math.max(-1, Math.min(1, (e.clientY - box.top - box.height / 2) / (box.height / 2)));
  if (!playing) render();
});
visual.addEventListener('pointerleave', () => { pointerX = pointerY = 0; if (!playing) render(); });
document.addEventListener('visibilitychange', () => {
  if (document.hidden) stopClock();
  else { if (eligible && !hasStarted) start(); wake(); }
  updateState();
});
document.addEventListener('aisland:languagechange', updateCopy);
media.addEventListener('change', () => {
  playing = false; stopClock(); hasStarted = false;
  elapsed = media.matches ? DURATION : 0; progress = media.matches ? 1 : 0;
  render(); if (eligible) start(); updateState();
});
window.addEventListener('resize', render);
window.addEventListener('pagehide', () => { stopClock(); observer.disconnect(); });
window.addEventListener('pageshow', () => { observer.observe(visual); wake(); });
updateCopy(); render();
