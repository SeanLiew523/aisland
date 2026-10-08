/* Scroll changes the camera; native playback retains recorded timing. */
(() => {
  if (!window.gsap || !window.ScrollTrigger) return;
  gsap.registerPlugin(ScrollTrigger);
  const hero = document.querySelector('.hero-reveal');
  const header = document.querySelector('.site-header');
  const copy = hero.querySelector('.hero-top');
  const camera = hero.querySelector('.device-camera');
  const idle = hero.querySelector('#idle-demo');
  const controls = hero.querySelector('.demo-ui');
  const metadata = hero.querySelector('.demo-topline');
  const softness = hero.querySelectorAll('.edge-softness, .bottom-softness');
  const atmosphere = hero.querySelector('.hero-atmosphere');
  const cue = hero.querySelector('.scroll-cue');
  const art = hero.querySelectorAll('.art-parallax');
  const mm = gsap.matchMedia();
  let phase;

  function presentDemo(active) {
    if (phase === active) return;
    phase = active;
    hero.dataset.demoActive = String(active);
    gsap.to(idle, { autoAlpha: active ? 0 : 1, duration: matchMedia('(prefers-reduced-motion: reduce)').matches ? 0 : .12, overwrite: true });
    document.dispatchEvent(new CustomEvent('aisland:demoreveal'));
  }

  mm.add({ animate: '(prefers-reduced-motion: no-preference)', reduced: '(prefers-reduced-motion: reduce)' }, context => {
    const animate = context.conditions.animate;
    const mobile = () => innerWidth <= 760;
    const controlsRoom = () => mobile() ? 215 : 143;
    function geometry() {
      const height = hero.clientHeight;
      const width = Math.min(mobile() ? innerWidth - 38 : innerWidth - 112,
        mobile() ? 680 : 1180, (height - controlsRoom() - 30) * 3072 / 1984);
      const compactNotchRatio = 500 / 3072;
      const targetNotchWidth = Math.min(innerWidth * (mobile() ? .74 : .56), 720);
      const initialY = copy.offsetTop + copy.offsetHeight + (mobile() ? 58 : 42);
      return {
        width,
        initialY: Math.min(initialY, height - (mobile() ? 210 : 190)),
        initialScale: Math.max(1.8, targetNotchWidth / (width * compactNotchRatio)),
        finalY: mobile() ? Math.max(48, (height - controlsRoom() - width * 1984 / 3072) / 2) : 16,
      };
    }
    function sizeCamera() {
      document.documentElement.style.setProperty('--viewport-width', `${document.documentElement.clientWidth}px`);
      const { width, initialY, initialScale, finalY } = geometry();
      gsap.set(camera, { width, xPercent: -50, x: 0, transformOrigin: '50% 0%' });
      gsap.set([controls, metadata], { width: Math.min(width, innerWidth - 36) });
      // Fade begins beneath the captured compact notch, never over its face.
      gsap.set(hero.querySelector('.bottom-softness'), {
        top: initialY + (mobile() ? 5 : 7) * initialScale
          + (width - (mobile() ? 10 : 14)) * initialScale * 58 / 3072 + 20,
      });
      const frameEnd = finalY + camera.offsetHeight;
      gsap.set(metadata, { top: frameEnd + 18, bottom: 'auto' });
      gsap.set(controls, { top: frameEnd + 42, bottom: 'auto' });
    }
    sizeCamera();
    hero.dataset.ready = 'true';

    if (!animate) {
      gsap.set(camera, { scale: 1, y: () => geometry().finalY + copy.offsetHeight });
      gsap.set(metadata, { top: geometry().finalY + copy.offsetHeight + camera.offsetHeight + 18 });
      gsap.set(controls, { top: geometry().finalY + copy.offsetHeight + camera.offsetHeight + 42 });
      gsap.set(idle, { autoAlpha: 0 });
      gsap.set(softness, { opacity: 0 });
      gsap.set(cue, { autoAlpha: 0 });
      gsap.set([controls, metadata], { autoAlpha: 1 });
      hero.style.height = `${copy.offsetHeight + camera.offsetHeight + controlsRoom() + 48}px`;
      copy.inert = false;
      controls.inert = false;
      presentDemo(true);
      return () => { hero.style.height = ''; };
    }

    gsap.set([controls, metadata], { autoAlpha: 0 });
    controls.inert = true;
    presentDemo(false);
    let guidedProgress = 0;
    const nativeVideo = hero.querySelector('#native-demo');
    const timeline = gsap.timeline({
      paused: true,
      defaults: { ease: 'power2.inOut' },
      onUpdate() {
        const progress = this.progress();
        hero.dataset.focusProgress = progress.toFixed(3);
        copy.inert = progress > .34;
        controls.inert = progress < .85;
      },
    });
    timeline
      .fromTo(camera, { scale: () => geometry().initialScale, y: () => geometry().initialY },
        { scale: 1, y: () => geometry().finalY, duration: .86 }, 0)
      .fromTo(copy, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -45, duration: .32 }, 0)
      .fromTo(cue, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -15, duration: .18 }, 0)
      .fromTo(atmosphere, { opacity: 1 }, { opacity: .48, duration: .66 }, 0)
      .fromTo(softness, { opacity: 1 }, { opacity: 0, duration: .24 }, 0)
      .fromTo(art[0], { y: 0, rotation: -8 }, { y: -56, rotation: -2, duration: .98 }, 0)
      .fromTo(art[1], { y: 0, rotation: 8 }, { y: 36, rotation: 2, duration: .98 }, 0)
      .fromTo([controls, metadata], { autoAlpha: 0 }, { autoAlpha: 1, duration: .14 }, .84)
      .to({}, { duration: .12 });

    const trigger = ScrollTrigger.create({
      id: 'notch-pullback', trigger: hero, pin: true,
      start: () => `top ${header.offsetHeight}px`,
      end: () => `+=${Math.round(innerHeight * (mobile() ? 1.05 : 1.45))}`,
      anticipatePin: 1, refreshPriority: 10,
      onRefreshInit: sizeCamera,
      onRefresh: () => timeline.invalidate().progress(timeline.progress()),
      onUpdate: self => presentDemo(self.progress > .0005),
    });
    // A short guided pull-back finishes before the first panel opens. Scrolling
    // can advance it sooner; stopping a small scroll never leaves the UI cropped.
    function frame(_time, delta) {
      if (!phase) guidedProgress = 0;
      else guidedProgress = Math.max(guidedProgress, Math.min(nativeVideo.currentTime / 1.6, 1));
      const target = phase ? Math.max(trigger.progress, guidedProgress) : 0;
      const current = timeline.progress();
      // Do not repaint a completed or resting camera at every display tick.
      if (document.hidden || Math.abs(target - current) < .00001) return;
      const next = current + (target - current) * Math.min(1, delta / 85);
      timeline.progress(Math.abs(target - next) < .0001 ? target : next);
    }
    gsap.ticker.add(frame);
    presentDemo(trigger.progress > .0005);

    return () => {
      gsap.ticker.remove(frame);
      trigger.kill();
      copy.inert = false;
      controls.inert = false;
      delete hero.dataset.focusProgress;
      delete hero.dataset.ready;
    };
  });
  document.fonts.ready.then(() => ScrollTrigger.refresh());
  // Pointer depth lives on an inner wrapper, separate from scroll transforms.
  mm.add('(prefers-reduced-motion: no-preference) and (pointer: fine)', () => {
    const planes = [...hero.querySelectorAll('.art-pointer')];
    const moves = planes.map((plane, index) => ({
      x: gsap.quickTo(plane, 'x', { duration: .7, ease: 'power3.out' }),
      y: gsap.quickTo(plane, 'y', { duration: .7, ease: 'power3.out' }),
      rotate: gsap.quickTo(plane, 'rotationY', { duration: .8, ease: 'power3.out' }),
      depth: index ? 1 : -.65,
    }));
    const move = event => {
      const x = event.clientX / innerWidth - .5;
      const y = event.clientY / innerHeight - .5;
      moves.forEach(m => { m.x(x * 28 * m.depth); m.y(y * 20 * m.depth); m.rotate(x * 12 * m.depth); });
    };
    const reset = () => moves.forEach(m => { m.x(0); m.y(0); m.rotate(0); });
    hero.addEventListener('pointermove', move);
    hero.addEventListener('pointerleave', reset);
    return () => { hero.removeEventListener('pointermove', move); hero.removeEventListener('pointerleave', reset); };
  });
  // The hero has fixed geometry in both languages. Refreshing a pinned trigger
  // during a language toggle can move its pin start; leave the camera in place.
})();
