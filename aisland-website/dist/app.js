/* One fixed visual direction. Playback is independent of page scrolling. */
const video = document.querySelector('#native-demo');
const playButton = document.querySelector('#play-toggle');
const reduced = matchMedia('(prefers-reduced-motion: reduce)');
const chapterButtons = [...document.querySelectorAll('[data-chapter]')];
const translate = window.AIslandI18n.t;
let inView = true;
let userPaused = reduced.matches;
let pendingTime = null;

function updatePlayback() {
  playButton.textContent = translate(video.paused ? 'play' : 'pause');
  playButton.setAttribute('aria-label', translate(video.paused ? 'playLabel' : 'pauseLabel'));
}
function updateTime() {
  const t = video.currentTime;
  const chapter = DEMO_TIMELINE.segments.find(segment => t >= segment.start && t < segment.end)?.chapter ?? -1;
  chapterButtons.forEach(button => button.setAttribute('aria-pressed', String(Number(button.dataset.chapter) === chapter)));
  document.querySelector('#scene-caption').textContent = translate(`caption${chapter + 1}`);
  document.querySelector('.timeline i').style.width = `${t / (video.duration || DEMO_TIMELINE.duration) * 100}%`;
  const clock = seconds => `00:${String(Math.floor(seconds)).padStart(2, '0')}`;
  document.querySelector('#timecode').textContent = `${clock(t)} / ${clock(video.duration || DEMO_TIMELINE.duration)}`;
}
async function play() {
  try { await video.play(); } catch { /* A user gesture can resume blocked autoplay. */ }
  updatePlayback();
}
function syncPlayback() {
  if (userPaused || !inView || document.hidden) { video.pause(); updatePlayback(); }
  else play();
}
video.addEventListener('loadedmetadata', () => {
  if (pendingTime !== null) { video.currentTime = Math.min(pendingTime, video.duration); pendingTime = null; }
  updateTime();
  syncPlayback();
});
playButton.addEventListener('click', () => { userPaused = !video.paused; syncPlayback(); });
video.addEventListener('play', updatePlayback);
video.addEventListener('pause', updatePlayback);
video.addEventListener('timeupdate', updateTime);
chapterButtons.forEach(button => button.addEventListener('click', () => {
  const time = DEMO_TIMELINE.chapters[Number(button.dataset.chapter)];
  if (video.readyState === 0) pendingTime = time;
  else video.currentTime = time;
  userPaused = true;
  video.pause();
  updatePlayback();
  updateTime();
}));
new IntersectionObserver(entries => { inView = entries[0].isIntersecting; syncPlayback(); }, { threshold: .12 }).observe(video);
document.addEventListener('visibilitychange', syncPlayback);
document.addEventListener('aisland:languagechange', () => { updatePlayback(); updateTime(); });
function updateStatusPreviews() {
  document.querySelectorAll('.status-gallery img').forEach(img => {
    img.src = reduced.matches ? img.dataset.static : img.dataset.static.replace('.png', '.webp');
  });
}
reduced.addEventListener('change', () => {
  if (reduced.matches) { userPaused = true; video.pause(); }
  updateStatusPreviews();
});
updateStatusPreviews();
updatePlayback();
updateTime();
