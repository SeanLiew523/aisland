/* Background planes stay independent of recorded UI and brand characters. */
(() => {
  if (!window.gsap || !window.ScrollTrigger) return;
  const sections = [...document.querySelectorAll('[data-chapter-art]')];
  const mm = gsap.matchMedia();

  mm.add('(prefers-reduced-motion: no-preference)', () => {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) entry.target.dataset.artVisible = String(entry.isIntersecting);
    }, { rootMargin: '80px' });
    const tweens = sections.flatMap(section => {
      observer.observe(section);
      return [...section.querySelectorAll('.chapter-scroll')].map((plane, index) =>
        gsap.fromTo(plane, { y: index ? 26 : -30, rotation: index ? 4 : -4 }, {
          y: index ? -38 : 32, rotation: index ? -4 : 4, ease: 'none',
          scrollTrigger: { trigger: section, start: 'top bottom', end: 'bottom top', scrub: .6 },
        }));
    });
    return () => {
      observer.disconnect();
      tweens.forEach(tween => { tween.scrollTrigger?.kill(); tween.kill(); });
      sections.forEach(section => delete section.dataset.artVisible);
    };
  });

  mm.add('(prefers-reduced-motion: no-preference) and (pointer: fine)', () => {
    const cleanups = sections.map(section => {
      const moves = [...section.querySelectorAll('.chapter-depth')].map((plane, index) => ({
        x: gsap.quickTo(plane, 'x', { duration: .9, ease: 'power3.out' }),
        y: gsap.quickTo(plane, 'y', { duration: .9, ease: 'power3.out' }),
        rotate: gsap.quickTo(plane, 'rotationY', { duration: 1, ease: 'power3.out' }),
        depth: index ? -.6 : 1,
      }));
      const move = event => {
        const x = event.clientX / innerWidth - .5;
        const y = event.clientY / innerHeight - .5;
        moves.forEach(m => { m.x(x * 22 * m.depth); m.y(y * 16 * m.depth); m.rotate(x * 10 * m.depth); });
      };
      const reset = () => moves.forEach(m => { m.x(0); m.y(0); m.rotate(0); });
      section.addEventListener('pointermove', move);
      section.addEventListener('pointerleave', reset);
      return () => { section.removeEventListener('pointermove', move); section.removeEventListener('pointerleave', reset); };
    });
    return () => cleanups.forEach(cleanup => cleanup());
  });
})();
