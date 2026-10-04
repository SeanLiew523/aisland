// Prototype adapter only. Geometry, expressions and animation come unchanged
// from the website's vendored Bloub engine; do not draw substitute silhouettes.
import { BotEngine, type BotFrame } from '../../aisland-website/src/vendor/bloub/engine';
import { NOTIF_BLUE } from '../../aisland-website/src/vendor/bloub/decor';
import { mixHex } from '../../aisland-website/src/vendor/bloub/skins';
import { DEMI_VIEWBOX, RAYON } from '../../aisland-website/src/vendor/bloub/repere';
import type { StateId } from '../../aisland-website/src/vendor/bloub/states';

// Same SVG layer order and masks as aisland-website/src/integrated-motion.ts.
// Only colors and the caller-owned unique mask prefix vary for this scene.
function svg(frame: BotFrame, id: string, color = '#09090b', background = '#f4f4f0', pixelSize?: number) {
  const half = DEMI_VIEWBOX, side = half * 2, f = frame;
  const gradients = f.arcs.map(a => `<linearGradient id="${id}-${a.id}" gradientUnits="userSpaceOnUse" x1="${a.grad.x1}" y1="${a.grad.y1}" x2="${a.grad.x2}" y2="${a.grad.y2}">${a.grad.stops.map((c, i, stops) => `<stop offset="${i / (stops.length - 1)}" stop-color="${c}"/>`).join('')}</linearGradient>`).join('');
  const rings = (layer: 'back' | 'front') => `<g fill="none" stroke-linecap="round">${f.arcs.map(a => `<path d="${a[layer]}" stroke="url(#${id}-${a.id})" stroke-width="${a.width}" opacity="${a.opacity}"/>`).join('')}</g>`;
  const dots = () => f.dots.map(d => {
    const fill = d.color ?? (d.depth === undefined ? color : mixHex(background, color, d.depth));
    return d.d ? `<path d="${d.d}" transform="translate(${d.x} ${d.y}) rotate(${d.rot ?? 0}) scale(${RAYON})" fill="${fill}" opacity="${d.opacity}"/>` : `<circle cx="${d.x}" cy="${d.y}" r="${d.r}" fill="${fill}" opacity="${d.opacity}"/>`;
  }).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg"${pixelSize ? ` width="${pixelSize}" height="${pixelSize}"` : ''} viewBox="-${half} -${half} ${side} ${side}" aria-hidden="true"><defs>${gradients}<mask id="${id}-eyes" maskUnits="userSpaceOnUse" x="-${half}" y="-${half}" width="${side}" height="${side}"><path d="${f.bodyPath}" fill="white"/>${f.eyes.map(e => `<path d="${e.d}" transform="${e.matrix}" fill="black" opacity="${e.alpha}"/>`).join('')}${f.notch ? `<circle cx="${f.notch.x}" cy="${f.notch.y}" r="${f.notch.r}" fill="black"/>` : ''}</mask></defs>${rings('back')}${f.dotsBehind ? dots() : ''}<g opacity="${f.bodyAlpha}"><path d="${f.bodyPath}" fill="${background}"/><g mask="url(#${id}-eyes)"><rect x="-${half}" y="-${half}" width="${side}" height="${side}" fill="${color}"/></g></g>${!f.dotsBehind ? dots() : ''}${f.notif ? `<circle cx="${f.notif.x}" cy="${f.notif.y}" r="${f.notif.r}" fill="${NOTIF_BLUE}"/>` : ''}${rings('front')}</svg>`;
}
// The website's central orbit state continuously relaxes a spinning triangle
// into a sphere. Sample the original state, rather than blending screenshots.
const orbitEngine = new BotEngine(RAYON, 'orbit');
const idle = new BotEngine(RAYON, 'idle'), thinking = new BotEngine(RAYON, 'thinking');

interface Scene { w: number; h: number; t: number; x: number; y: number; iw: number; ih: number;
  gather: number; arrived: number; approval: number; dock: number; settled: number; motion: boolean; setup: boolean }
function layout(scene: Scene) {
  const { w, h, t, x, y, iw, ih, gather, arrived, approval, dock, settled, setup } = scene;
  const size = Math.min(w * .68, h * .66) * .7, start = dock;
  return {
    glyph: { visible: !setup && t >= gather && t < approval, state: t >= arrived ? 'thinking' : 'idle',
      x: x - iw * .35, y, size: ih * .82 },
    // Finish the full original morph as the pill reaches its hardware position.
    // Both use the existing dock-to-settled interval; hold the final pose after it.
    orbit: { visible: !setup && t >= start, x: w / 2, y: h * .55, size,
      time: scene.motion ? Math.min(3.3, Math.max(0, (t - start) * 3.3 / (settled - dock))) : 2.5, start }
  };
}
let lastGlyphFrame = '', lastOrbitFrame = '';
function render(scene: Scene) {
  const geometry = layout(scene), glyph = document.getElementById('gather-bloub'), orbit = document.getElementById('home-orbit');
  if (!glyph || !orbit) throw new Error('Bloub review surfaces are unavailable.');
  glyph.hidden = !geometry.glyph.visible; orbit.hidden = !geometry.orbit.visible;
  const time = scene.motion ? scene.t : 1, tick = Math.floor(time * 30);
  if (geometry.glyph.visible) {
    const g = geometry.glyph, pixels = Math.ceil(g.size * (window.devicePixelRatio || 1)), key = `${g.state}:${tick}:${pixels}`;
    glyph.style.cssText = `left:${g.x}px;top:${g.y}px;width:${g.size}px;height:${g.size}px`;
    glyph.dataset.state = g.state;
    if (key !== lastGlyphFrame) {
      glyph.innerHTML = svg((g.state === 'idle' ? idle : thinking).sample(time), 'intro-left', '#f2ead8', '#04070d', pixels);
      lastGlyphFrame = key;
    }
  }
  if (geometry.orbit.visible) {
    const o = geometry.orbit, pixels = Math.ceil(o.size * (window.devicePixelRatio || 1)), key = `${Math.floor(o.time * 30)}:${o.size}:${pixels}`;
    orbit.style.cssText = `left:${o.x}px;top:${o.y}px;width:${o.size}px;height:${o.size}px`;
    orbit.dataset.state = 'orbit'; orbit.dataset.time = String(o.time);
    if (key !== lastOrbitFrame) {
      orbit.innerHTML = svg(orbitEngine.sample(o.time), 'intro-orbit', '#09090b', '#f4f4f0', pixels);
      lastOrbitFrame = key;
    }
    orbit.style.opacity = scene.motion ? String(Math.min(1, Math.max(0, (scene.t - o.start) / .35))) : '1';
  }
}
// Clock and lifetime belong to the existing intro. No independent RAF, timers,
// pointer listeners, autoplay, audio or preference IO are added.
Object.assign(window, { AIslandIntroBloub: { render, layout, svg,
  sample: (state: StateId, time: number) => new BotEngine(RAYON, state).sample(time) } });
