/* Scroll choreography moves the presentation, never the native movie's time. */
(() => {
  if (!window.gsap || !window.ScrollTrigger) return;
  gsap.registerPlugin(ScrollTrigger);
  const hero = document.querySelector('.hero');
  const copy = hero.querySelector('.hero-top');
  const demo = hero.querySelector('.demo-wrap');
  const stage = demo.querySelector('.demo-stage');
  const controls = demo.querySelector('.demo-ui');
  const atmosphere = hero.querySelector('.spectrum-lines');
  let media;
  let queued = 0;

  function rebuild() {
    media?.revert();
    copy.inert = false;
    delete hero.dataset.focusProgress;
    media = gsap.matchMedia();
    media.add('(min-width: 1051px) and (min-height: 700px) and (prefers-reduced-motion: no-preference)', () => {
      const pin = hero;
      const pinTop = 76;
      function destination() {
        // Measure unanimated wrappers, so refresh/reverse never compound scale.
        const box = demo.getBoundingClientRect();
        const parent = pin.getBoundingClientRect();
        const naturalTop = pinTop + box.top - parent.top;
        const top = 90;
        const viewportWidth = document.documentElement.clientWidth;
        const scale = Math.max(1, Math.min(1.52,
          (viewportWidth - 96) / demo.offsetWidth,
          (innerHeight - top - 140) / (stage.offsetHeight * .70)));
        return {
          x: viewportWidth / 2 - (box.left + box.width / 2),
          y: top - naturalTop,
          scale,
          controlsY: innerHeight - controls.offsetHeight - 28 - naturalTop - controls.offsetTop,
        };
      }
      gsap.set(stage, { transformOrigin: '50% 0%' });
      const timeline = gsap.timeline({
        defaults: { ease: 'power1.inOut' },
        scrollTrigger: {
          id: 'native-demo-focus', refreshPriority: 10, trigger: pin, pin: true,
          start: `top ${pinTop}px`,
          end: () => `+=${Math.min(900, innerHeight * .95)}`,
          scrub: .45, anticipatePin: 1, invalidateOnRefresh: true,
        },
        onUpdate() {
          const progress = this.progress();
          hero.dataset.focusProgress = progress.toFixed(3);
          copy.inert = progress > .5;
        },
      });
      timeline
        .to(copy, { opacity: 0, x: -32, duration: .5 }, 0)
        .to(atmosphere, { opacity: 0, y: -20, duration: .5 }, 0)
        .to(stage, {
          x: () => destination().x,
          y: () => destination().y,
          scale: () => destination().scale,
          duration: .82,
        }, 0)
        .to(controls, {
          x: () => destination().x,
          y: () => destination().controlsY,
          duration: .82,
        }, 0)
        .to({}, { duration: .18 });
      return () => {
        copy.inert = false;
        delete hero.dataset.focusProgress;
      };
    });
  }
  function queueRebuild() {
    cancelAnimationFrame(queued);
    queued = requestAnimationFrame(rebuild);
  }
  document.fonts.ready.then(queueRebuild);
  document.addEventListener('aisland:languagechange', () => requestAnimationFrame(() => ScrollTrigger.refresh()));
  // Fonts, breakpoints and reduced-motion changes are handled by matchMedia.
  queueRebuild();
})();
