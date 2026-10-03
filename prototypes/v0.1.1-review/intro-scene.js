"use strict";
// A presentation-only scene. All task content is a demonstration, never runtime evidence.
window.AIslandIntroScene = (() => {
  const clamp = x => Math.max(0, Math.min(1, x));
  const smooth = x => { x = clamp(x); return x * x * (3 - 2 * x); };
  const ease = x => 1 - Math.pow(1 - clamp(x), 3);
  const lerp = (a, b, t) => a + (b - a) * t;
  const ink = "#202d43", blue = "#3878f4", paper = "#f7f5ee";
  const cueTimes = [1.65, 4.3, 8.6, 11.4, 14, 17, 20, 23, 26.4];
  const palettes = [
    {at: 0, top: "#030711", bottom: "#091638", glow: "#2050c4"},
    {at: 1.65, top: "#071d53", bottom: "#123987", glow: "#487ffa"},
    {at: 4.3, top: "#eef2fd", bottom: "#c8d7f5", glow: "#f9f7f0"},
    {at: 10, top: "#0c1527", bottom: "#1a2f4e", glow: "#294968"},
    {at: 14, top: "#1a1728", bottom: "#382b42", glow: "#65465f"},
    {at: 17, top: "#191d28", bottom: "#35322d", glow: "#706346"},
    {at: 20, top: "#e7edf9", bottom: "#c1d3f3", glow: "#f7f6f0"},
    {at: 23, top: "#f0f2f8", bottom: "#dadfe9", glow: "#eef0f8"}
  ];
  function mix(a, b, t) {
    const aa = a.match(/\w\w/g).map(x => parseInt(x, 16));
    const bb = b.match(/\w\w/g).map(x => parseInt(x, 16));
    return `rgb(${aa.map((v, i) => Math.round(lerp(v, bb[i], t))).join(",")})`;
  }
  function rect(c, x, y, w, h, r, fill, stroke) {
    c.beginPath(); c.roundRect(x, y, w, h, r);
    if (fill) { c.fillStyle = fill; c.fill(); }
    if (stroke) { c.strokeStyle = stroke; c.lineWidth = 1; c.stroke(); }
  }
  function line(c, x, y, xx, yy, color, width = 1) {
    c.beginPath(); c.moveTo(x, y); c.lineTo(xx, yy); c.strokeStyle = color; c.lineWidth = width; c.stroke();
  }
  function text(c, value, x, y, size = 11, color = ink, weight = 400, mono = false) {
    c.fillStyle = color;
    c.font = `${weight} ${size}px ${mono ? '"SFMono-Regular", Menlo' : '"Avenir Next", "PingFang SC"'}, sans-serif`;
    c.fillText(value, x, y);
  }
  function dot(c, x, y, r, color) {
    c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.fillStyle = color; c.fill();
  }
  function check(c, x, y, color, s = 1) {
    c.save(); c.translate(x, y); c.scale(s, s); c.lineCap = "round"; c.lineJoin = "round";
    c.beginPath(); c.moveTo(-4, 0); c.lineTo(-1, 3); c.lineTo(5, -4); c.strokeStyle = color; c.lineWidth = 1.5; c.stroke(); c.restore();
  }
  function sheet(c, width, height, tint = paper) {
    c.shadowColor = "#142d6630"; c.shadowBlur = 26; c.shadowOffsetY = 12;
    rect(c, -width / 2, -height / 2, width, height, 14, tint);
    c.shadowBlur = 0; c.shadowOffsetY = 0;
    rect(c, -width / 2 + .5, -height / 2 + .5, width - 1, height - 1, 14, null, "#ffffffab");
  }
  function label(c, number, title, status, tint = blue) {
    rect(c, -102, -68, 22, 22, 6, `${tint}18`);
    text(c, number, -96, -53, 9, tint, 600);
    text(c, title, -72, -53, 12, ink, 600);
    text(c, status, 59, -53, 8, "#7b8698");
    line(c, -101, -36, 101, -36, "#23385910");
  }
  function documentCard(c) {
    sheet(c, 236, 174); label(c, "01", "整理文档", "进行中");
    rect(c, -99, -25, 61, 87, 4, "#ffffff", "#dce3ec");
    rect(c, -88, -12, 35, 3, 1.5, "#354761");
    for (let i = 0; i < 5; i++) rect(c, -88, 1 + i * 9, i === 3 ? 22 : 39, 2, 1, i === 1 ? "#669cff" : "#aebaca");
    rect(c, -27, -23, 82, 17, 4, "#ebf0fa"); text(c, "项目资料 / 春季", -19, -12, 8, "#657790");
    text(c, "12 份文档", -26, 16, 16, ink, 600);
    text(c, "目录与摘要 · 正在整理", -26, 35, 8, "#78889b");
    rect(c, -26, 49, 119, 3, 1.5, "#dce4f2"); rect(c, -26, 49, 76, 3, 1.5, "#5d8cef");
    text(c, "AISLAND / DEMO", -99, 76, 7, "#8c99ac", 500);
  }
  function codeCard(c) {
    sheet(c, 236, 190, "#f1f4fa");
    c.save(); c.translate(0, -8); label(c, "02", "修改页面", "待确认"); c.restore();
    rect(c, -101, -33, 202, 94, 7, "#18263e");
    text(c, "hero.tsx", -88, -17, 8, "#a8b8d1", 400, true);
    line(c, -90, -8, 90, -8, "#ffffff10");
    text(c, "12", -89, 10, 8, "#536e94", 400, true); text(c, "<Hero", -70, 10, 9, "#8eb9ff", 400, true);
    text(c, "13", -89, 27, 8, "#536e94", 400, true); text(c, '  title="让等待有回应"', -70, 27, 9, "#b8d2ba", 400, true);
    text(c, "14", -89, 44, 8, "#536e94", 400, true); text(c, "  spacing={24} />", -70, 44, 9, "#e5bc92", 400, true);
    dot(c, -96, 78, 3, "#d39a9f"); text(c, "1 个文件修改 · 等待你的审批", -84, 81, 8, "#758298");
  }
  function reviewCard(c) {
    sheet(c, 236, 174, "#fffaf0"); label(c, "03", "审核资料", "待回答", "#ac8640");
    text(c, "资料核对清单", -98, -17, 10, ink, 600);
    ["数据来源已归档", "关键结论已标注", "确认审核范围"].forEach((value, i) => {
      const y = 7 + i * 23;
      rect(c, -99, y - 8, 12, 12, 4, i < 2 ? "#e4ebdf" : "#f1e5c9");
      if (i < 2) check(c, -93, y - 2, "#6d8861", .7);
      else text(c, "?", -95.5, y + 1, 9, "#b18a3c", 600);
      text(c, value, -77, y + 2, 9, "#667184");
      if (i < 2) text(c, "已核对", 67, y + 2, 7, "#91a18d");
    });
    text(c, "AISLAND / DEMO", -99, 76, 7, "#a7987a", 500);
  }
  function background(c, w, h, t, motion, setup) {
    const time = setup ? 28 : t;
    let index = palettes.findLastIndex(p => p.at <= time);
    index = Math.max(0, index);
    const current = palettes[index], previous = palettes[Math.max(0, index - 1)];
    const fade = motion ? smooth((time - current.at) / 1.25) : 1;
    const top = mix(previous.top, current.top, fade), bottom = mix(previous.bottom, current.bottom, fade);
    const gradient = c.createLinearGradient(0, 0, w * .16, h);
    gradient.addColorStop(0, top); gradient.addColorStop(1, bottom); c.fillStyle = gradient; c.fillRect(0, 0, w, h);
    const gx = w * (.63 + (motion ? Math.sin(time * .12) * .06 : 0));
    const gy = h * (.34 + (motion ? Math.cos(time * .18) * .06 : 0));
    const halo = c.createRadialGradient(gx, gy, 0, gx, gy, w * .65);
    halo.addColorStop(0, mix(previous.glow, current.glow, fade)); halo.addColorStop(1, "#ffffff00");
    c.globalAlpha = .45; c.fillStyle = halo; c.fillRect(0, 0, w, h); c.globalAlpha = 1;
    if (time < 4.3) {
      const opening = motion ? ease((time - .4) / 2.2) : 1;
      c.save(); c.translate(w * .64, h * .36); c.rotate(-.28);
      const sweep = c.createLinearGradient(-w * .7, 0, w * .7, 0);
      sweep.addColorStop(0, "#6c9aff00"); sweep.addColorStop(.5, "#91b4ff"); sweep.addColorStop(1, "#6c9aff00");
      c.globalAlpha = opening * .15; c.fillStyle = sweep; c.fillRect(-w, -h * .12, w * 2, h * .17);
      c.globalAlpha = opening * .12; c.fillRect(-w, h * .11, w * 2, 1);
      c.restore();
      // A continuous aperture opens into depth; no brightness flashes or camera shake.
      c.save(); c.translate(w * .64, h * .36); c.scale(1, .45);
      for (let i = 0; i < 5; i++) {
        const radius = (w * .13 + i * w * .056) * (.35 + opening * .9);
        c.globalAlpha = opening * (.17 - i * .025); c.strokeStyle = "#adc9ff"; c.lineWidth = i === 0 ? 1.5 : .6;
        c.beginPath(); c.arc(0, 0, radius, 0, Math.PI * 2); c.stroke();
      }
      c.restore();
    } else if (time < 10 || time >= 20) {
      c.save(); c.globalAlpha = .16; c.translate(w * .88, h * .47); c.rotate(-.5);
      c.fillStyle = "#7f9cca"; c.fillRect(-w * .08, -h, w * .17, h * 2);
      c.fillStyle = "#ffffff"; c.fillRect(-w * .22, -h, w * .12, h * 2); c.restore();
      if (time >= 23) {
        c.globalAlpha = smooth((time - 23) / 1.7) * .52;
        rect(c, w * .18, h * .33, w * .7, h * .57, 16, "#ffffff88", "#ffffffa0");
        c.globalAlpha = 1;
      }
    } else {
      c.save(); c.globalAlpha = .18;
      for (let i = 0; i < 35; i++) dot(c, ((i * 137.5) % 997) / 997 * w, ((i * 213.2) % 631) / 631 * h, .7, "#b4c8e4");
      c.restore();
    }
    // A restrained grain supplies material detail without independent motion.
    c.save(); c.globalAlpha = .023;
    for (let i = 0; i < 500; i++) {
      const x = ((i * 73.13) % 997) / 997 * w, y = ((i * 39.71) % 631) / 631 * h;
      c.fillStyle = "#fff"; c.fillRect(x, y, 1, 1);
    }
    c.restore();
  }
  function island(c, width, height, t, scale, collapse) {
    c.save(); c.shadowColor = t < 4.3 ? "#000c" : "#07163050";
    c.shadowBlur = 30 * scale; c.shadowOffsetY = 12 * scale;
    rect(c, -width / 2, -height / 2, width, height, [0, 0, height * .44, height * .44], "#04070d");
    c.shadowBlur = 0; c.shadowOffsetY = 0;
    const running = t >= 10 && t < 11.4, approval = t >= 14 && t < 17, answer = t >= 17 && t < 20;
    const tint = approval ? "#eeb4b5" : answer ? "#eed18e" : "#f2ead8";
    if (running) {
      for (let i = 0; i < 3; i++) dot(c, (i - 1) * height * .23, 0, height * .047, tint);
    } else {
      const gap = height * .13, ew = height * .075, eh = height * .3;
      [-gap, gap].forEach(x => rect(c, x - ew / 2, -eh / 2, ew, eh, ew / 2, tint));
    }
    if (collapse < .8) dot(c, width * .27, -height * .11, Math.max(2, 3 * scale), t >= 11.4 && t < 14 ? "#add0aa" : "#6ea7ff");
    line(c, -width * .36, -height / 2 + 1, width * .36, -height / 2 + 1, "#ffffff0e");
    c.restore();
  }
  function response(c, t, x, y, s, motion) {
    let start, end, kind;
    if (t >= 10 && t < 14) { start = 10; end = 14; kind = "document"; }
    else if (t >= 14 && t < 17) { start = 14; end = 17; kind = "approval"; }
    else if (t >= 17 && t < 20) { start = 17; end = 20; kind = "answer"; }
    else return;
    const enter = motion ? ease((t - start) / .5) : 1;
    const exit = motion ? 1 - smooth((t - (end - .25)) / .25) : 1;
    c.save(); c.translate(x, y + 36 * s + (1 - enter) * 15 * s); c.scale(s, s); c.globalAlpha = enter * exit;
    const width = 320, height = kind === "document" ? 160 : 186;
    c.shadowColor = "#00000025"; c.shadowBlur = 25; c.shadowOffsetY = 12;
    rect(c, -width / 2, 0, width, height, 15, paper); c.shadowBlur = 0; c.shadowOffsetY = 0;
    const color = kind === "document" ? "#6e9879" : kind === "approval" ? "#ba7f91" : "#a78442";
    rect(c, -140, 17, 27, 27, 8, `${color}18`);
    if (kind === "document") check(c, -126, 31, color, 1.25);
    else text(c, kind === "approval" ? "↗" : "?", -131, 36, 17, color, 500);
    text(c, kind === "document" ? "整理文档" : kind === "approval" ? "修改页面" : "审核资料", -102, 31, 12, ink, 600);
    text(c, kind === "document" ? t < 11.4 ? "正在生成目录与摘要" : "已完成 · 12 份文档" : kind === "approval" ? "正在等你审批" : "正在等你回答", -102, 46, 8, "#79869a");
    text(c, "演示", 117, 30, 8, "#9ca6b3");
    line(c, -140, 58, 140, 58, "#22375412");
    if (kind === "document") {
      rect(c, -140, 70, 280, 65, 8, "#eaf0f8");
      rect(c, -128, 81, 33, 41, 3, "#fff", "#cfdaeb");
      for (let i = 0; i < 4; i++) rect(c, -120, 90 + i * 6, i === 3 ? 10 : 18, 2, 1, "#97aac6");
      text(c, "项目资料 · 整理版", -82, 95, 10, ink, 500);
      text(c, "目录 / 摘要 / 来源索引", -82, 112, 8, "#7c8ea9");
      if (t >= 11.4) { dot(c, 122, 95, 8, "#dae8dc"); check(c, 122, 95, "#6a9374", .85); }
    } else if (kind === "approval") {
      text(c, "即将修改 hero.tsx", -138, 77, 9, "#67758b");
      rect(c, -140, 87, 280, 40, 5, "#e4ebe4");
      text(c, "+  spacing={24}", -128, 104, 9, "#4c7359", 400, true);
      text(c, "+  title=\"让等待有回应\"", -128, 119, 9, "#4c7359", 400, true);
      rect(c, -140, 141, 166, 28, 7, "#243650"); text(c, "允许这一次", -93, 159, 10, "#f1f4f9", 500);
      rect(c, 36, 141, 104, 28, 7, null, "#ccd3df"); text(c, "拒绝", 76, 159, 10, "#7b8696");
    } else {
      text(c, "这次优先核对哪一部分？", -139, 81, 11, ink, 500);
      ["关键数据及来源", "文档中的结论"].forEach((value, i) => {
        const yy = 98 + i * 32;
        rect(c, -140, yy, 280, 27, 7, i === 0 ? "#f0e7d2" : "#ffffff44", i === 0 ? "#d7bf8a" : "#d8dce4");
        dot(c, -126, yy + 13, 4, i === 0 ? "#b59553" : "#c3c8d2"); text(c, value, -113, yy + 17, 9, "#737b85");
      });
    }
    c.restore();
  }
  function workspace(c, t, x, y, s, motion) {
    if (t < 20 || t >= 23.8) return;
    const enter = motion ? ease((t - 20) / .8) : 1, exit = motion ? 1 - smooth((t - 23) / .8) : 1;
    c.save(); c.translate(x, y + 46 * s + (1 - enter) * 35 * s); c.scale(s, s); c.globalAlpha = enter * exit;
    c.shadowColor = "#24447b35"; c.shadowBlur = 32; c.shadowOffsetY = 16;
    rect(c, -224, 0, 448, 221, 12, "#f9fafc", "#fff"); c.shadowBlur = 0; c.shadowOffsetY = 0;
    rect(c, -224, 0, 448, 30, [12, 12, 0, 0], "#e9edf5");
    ["#e39794", "#dfc28c", "#95baa2"].forEach((col, i) => dot(c, -208 + i * 11, 15, 3.5, col));
    text(c, "修改页面 · 演示会话", -158, 19, 9, "#64738a", 500);
    rect(c, -224, 30, 93, 191, [0, 0, 0, 12], "#eef1f6");
    text(c, "任务", -209, 53, 8, "#94a0b1");
    ["整理文档", "修改页面", "审核资料"].forEach((value, i) => {
      if (i === 1) rect(c, -215, 94, 76, 26, 5, "#d9e4f9");
      text(c, value, -204, 82 + i * 29, 9, i === 1 ? "#2e5aab" : "#8793a4", i === 1 ? 600 : 400);
    });
    text(c, "修改首页的标题与间距", -111, 57, 12, ink, 600);
    text(c, "页面预览已准备好；等待你的许可。", -111, 78, 9, "#8290a3");
    rect(c, -110, 93, 312, 60, 7, "#e8eef8");
    text(c, "让等待，有回应。", -96, 116, 16, "#315491", 500);
    text(c, "你去做自己的事，小岛帮你看着进展。", -95, 135, 8, "#7f96b8");
    rect(c, -110, 167, 312, 35, 7, "#f2e8e8"); dot(c, -95, 184, 3, "#b88790");
    text(c, "等待审批 · hero.tsx", -83, 188, 9, "#8c707c");
    rect(c, 116, 174, 76, 21, 5, "#3c6098"); text(c, "查看修改", 136, 188, 8, "#fff");
    c.restore();
  }
  function draw(c, w, h, t, {reduceMotion = false, setup = false} = {}) {
    const motion = !reduceMotion;
    c.clearRect(0, 0, w, h); background(c, w, h, t, motion, setup);
    if (setup) return;
    const narrow = w < 640;
    const s = Math.min(w / (narrow ? 740 : 1010), h / 630);
    const cx = w * (narrow ? .53 : .64), cy = h * (narrow ? .31 : .35);
    const awaken = motion ? ease((t - .4) / 1.25) : t >= .4 ? 1 : 0;
    const collapse = motion ? ease((t - 23) / 3.4) : t >= 23 ? 1 : 0;
    const arrival = motion ? smooth((t - 8) / 1.7) : t >= 8.6 ? 1 : 0;
    const gather = smooth((t - 4.3) / 1.1);
    const x = lerp(cx, w * .5, collapse), y = lerp(cy, 17 * s, collapse);
    const iw = lerp(lerp(20, 282 * s, awaken) * (1 - gather * .42 + arrival * .26), 136 * s, collapse);
    const ih = lerp(lerp(20, 83 * s, awaken) * (1 - gather * .28 + arrival * .05), 32 * s, collapse);
    if (t >= 4.3 && t < 10) {
      const locations = [[-173, -10, -.08], [27, -74, .035], [194, 43, .09]];
      const cards = [documentCard, codeCard, reviewCard];
      cards.forEach((render, i) => {
        const enter = motion ? ease((t - 4.45 - i * .14) / 1.0) : 1;
        const pull = motion ? ease((t - 8.05 - i * .13) / 1.55) : arrival;
        const alpha = enter * (1 - smooth((t - 9.3) / .4));
        c.save(); c.translate(lerp(cx + locations[i][0] * s, cx, pull), lerp(cy + locations[i][1] * s + (1 - enter) * 60 * s, cy, pull));
        c.rotate(locations[i][2] * (1 - pull));
        const size = s * (1 - pull * .84); c.scale(size, size); c.globalAlpha = alpha;
        render(c); c.restore();
      });
      if (t >= 8) {
        c.save(); c.globalAlpha = (1 - arrival) * .3;
        c.strokeStyle = "#618cce"; c.lineWidth = .8;
        locations.forEach(([xx, yy]) => {
          c.beginPath(); c.moveTo(cx + xx * s, cy + yy * s); c.quadraticCurveTo(cx + xx * s * .25, cy - 100 * s, cx, cy); c.stroke();
        }); c.restore();
      }
    }
    response(c, t, cx, cy, s, motion);
    workspace(c, t, cx, cy, s, motion);
    c.save(); c.translate(x, y); island(c, iw, ih, t, s, collapse); c.restore();
    const cue = cueTimes.findLast(at => t >= at && t < at + 1.1);
    if (cue !== undefined && motion) {
      const elapsed = (t - cue) / 1.1;
      c.save(); c.translate(x, y); c.globalAlpha = (1 - elapsed) * (t < 4.3 ? .38 : .16);
      c.strokeStyle = t >= 4.3 && t < 10 || t >= 20 ? "#3b6bb5" : "#bfd8ff"; c.lineWidth = .9;
      c.beginPath(); c.ellipse(0, 0, iw * .6 + elapsed * 75 * s, ih * .64 + elapsed * 28 * s, 0, 0, Math.PI * 2); c.stroke(); c.restore();
    }
    if (t >= 26.4) {
      const alpha = motion ? smooth((t - 26.4) / .6) : 1;
      c.save(); c.globalAlpha = alpha; text(c, "AISLAND", w * .5 - 25 * s, 58 * s, 9 * s, "#7a8ba6", 600); c.restore();
    }
  }
  return {draw, duration: 28, cueTimes};
})();
