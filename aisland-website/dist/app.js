const designs = ['signal', 'matrix', 'spectrum'];
const colors = { signal: [172, 129, 255], matrix: [150, 255, 70], spectrum: [255, 82, 61] };
const video = document.querySelector('#native-demo');
const playButton = document.querySelector('#play-toggle');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const chapters = DEMO_TIMELINE.chapters;
const captions = ['等待下一步，也有自己的表情。', '思考中，三点轻轻脉冲。', '需要授权，粉色提醒等你决定。', '等待回答，暖黄色提醒接住问题。', '多个 Agent，一眼看清。', '完成之后，回到你的工作。'];
let design = 'signal';
let inView = true;
let userPaused = reduced.matches;
let pendingTime = null;
function syncPlayback() {
  if (userPaused || !inView || document.hidden) { video.pause(); updatePlayback(); }
  else play();
}
function setDesign(value, update = true) {
  value = ({ aurora: 'signal', mono: 'matrix', glass: 'spectrum' })[value] || value;
  design = designs.includes(value) ? value : 'signal';
  document.body.dataset.design = design;
  if (video.dataset.wallpaper !== design) {
    pendingTime = pendingTime ?? video.currentTime;
    const suffix = design === 'signal' ? '' : `-${design}`;
    video.dataset.wallpaper = design;
    video.poster = `assets/demo-poster${suffix}.jpg`;
    video.src = `assets/native-demo${suffix}.mp4?v=demo-20-v1`;
    video.load();
  }
  document.querySelectorAll('[data-style]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.style === design)));
  if (update) { const url = new URL(location.href); url.searchParams.set('style', design); history.replaceState(null, '', url); }
  paint(performance.now(), true);
}
function updatePlayback() {
  playButton.textContent = video.paused ? '▶ 播放' : 'Ⅱ 暂停';
  playButton.setAttribute('aria-label', video.paused ? '播放原生演示' : '暂停原生演示');
}
async function play() { try { await video.play(); } catch { /* Browser may require a user gesture. */ } updatePlayback(); }
video.addEventListener('loadedmetadata', () => {
  if (pendingTime !== null) { video.currentTime = Math.min(pendingTime, video.duration); pendingTime = null; }
  syncPlayback();
});
playButton.addEventListener('click', () => { userPaused = !video.paused; syncPlayback(); });
video.addEventListener('play', updatePlayback); video.addEventListener('pause', updatePlayback);
video.addEventListener('timeupdate', () => {
  const t = video.currentTime;
  const chapter = DEMO_TIMELINE.segments.find(segment => t >= segment.start && t < segment.end)?.chapter ?? -1;
  document.querySelectorAll('[data-chapter]').forEach(b => b.setAttribute('aria-pressed', String(Number(b.dataset.chapter) === chapter)));
  document.querySelector('#scene-caption').textContent = captions[chapter + 1];
  document.querySelector('.timeline i').style.width = `${t / (video.duration || DEMO_TIMELINE.duration) * 100}%`;
  const clock = seconds => `00:${String(Math.floor(seconds)).padStart(2, '0')}`;
  document.querySelector('#timecode').textContent = `${clock(t)} / ${clock(video.duration || DEMO_TIMELINE.duration)}`;
});
document.querySelectorAll('[data-chapter]').forEach(b => b.addEventListener('click', () => { const time = chapters[Number(b.dataset.chapter)]; if (pendingTime !== null) pendingTime = time; else video.currentTime = time; userPaused = true; video.pause(); updatePlayback(); }));
document.querySelectorAll('[data-style]').forEach(b => b.addEventListener('click', () => setDesign(b.dataset.style)));
new IntersectionObserver(entries => { inView = entries[0].isIntersecting; syncPlayback(); }, { threshold: .12 }).observe(video);
document.addEventListener('visibilitychange', syncPlayback);
reduced.addEventListener('change', e => { if (e.matches) { userPaused = true; video.pause(); paint(performance.now(), true); } });
// Decorative signal geometry. This canvas never draws product interface elements.
const canvas = document.querySelector('#signal-field');
const ctx = canvas.getContext('2d');
let width = 0, height = 1450, lastPaint = 0;
function resize() { width = innerWidth; const ratio = Math.min(devicePixelRatio || 1, 1.5); canvas.width = width * ratio; canvas.height = height * ratio; ctx.setTransform(ratio, 0, 0, ratio, 0, 0); paint(performance.now(), true); }
function paint(now, force = false) {
  if (!width || !ctx || (!force && (document.hidden || now - lastPaint < 45 || reduced.matches))) return;
  lastPaint = now; ctx.clearRect(0, 0, width, height);
  const c = colors[design].join(','); const t = reduced.matches ? 0 : now / 1000;
  const cx = width * (design === 'matrix' ? .76 : .51); const cy = design === 'spectrum' ? 430 : 340;
  const glow = ctx.createRadialGradient(cx, cy, 1, cx, cy, width * .52);
  glow.addColorStop(0, `rgba(${c},${design === 'spectrum' ? .24 : .16})`); glow.addColorStop(1, `rgba(${c},0)`);
  ctx.fillStyle = glow; ctx.fillRect(0, 0, width, height);
  if (design === 'matrix') {
    for (let x = 12; x < width; x += 30) {
      const length = 15 + (x % 110), y = (t * 27 + x * 13) % 1000;
      for (let j = 0; j < 14; j++) { const a = .13 * (1 - j / 14); ctx.fillStyle = `rgba(${c},${a})`; ctx.font = '8px monospace'; ctx.fillText((x + j) % 3 ? '1' : '0', x, y - j * length / 5); }
    }
  } else {
    // Point-cloud rays converge toward an abstract signal source.
    for (let ray = -30; ray <= 30; ray++) {
      const angle = ray * .046 + Math.sin(t * .08) * .045;
      for (let p = 0; p < 38; p++) {
        const r = 70 + p * 22 + (t * 22 % 22), x = cx + Math.sin(angle) * r * 1.6, y = cy + Math.cos(angle) * r;
        const edge = Math.max(0, 1 - Math.abs(ray) / 35), fade = Math.max(0, 1 - r / 1100);
        ctx.fillStyle = `rgba(${c},${edge * fade * (design === 'spectrum' ? .6 : .48)})`;
        const s = design === 'spectrum' ? 2.2 : 1.5; ctx.fillRect(x, y, s, s);
      }
    }
    for (let k = 0; k < 4; k++) { const r = ((t * 25 + k * 190) % 760) + 10; ctx.strokeStyle = `rgba(${c},${.065 * (1 - r / 780)})`; ctx.lineWidth = .6; ctx.beginPath(); ctx.ellipse(cx, cy + r * .68, r, r * .23, 0, 0, Math.PI * 2); ctx.stroke(); }
  }
}
let wordStep = 0;
const names = ['CLAUDE CODE', 'CODEX', 'GEMINI CLI', 'CURSOR', 'ZCODE', 'WORKBUDDY'];
function animate(now) { paint(now); if (!document.hidden && !reduced.matches && Math.floor(now / 2600) !== wordStep) { wordStep = Math.floor(now / 2600); document.querySelector('#agent-name').textContent = names[wordStep % names.length]; } requestAnimationFrame(animate); }
window.addEventListener('resize', resize);
resize(); setDesign(new URLSearchParams(location.search).get('style') || 'matrix', false);
updatePlayback();
requestAnimationFrame(animate);

function updateStatusPreviews() { document.querySelectorAll(".status-gallery img").forEach(img => { img.src = reduced.matches ? img.dataset.static : img.dataset.static.replace(".png", ".webp"); }); }
updateStatusPreviews(); reduced.addEventListener("change", updateStatusPreviews);
