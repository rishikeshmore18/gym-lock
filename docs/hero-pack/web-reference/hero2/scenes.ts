/**
 * The seven hero states as painted landscapes. Each builder pre-paints its ranges into bitmaps and
 * returns draw(ctx, f, g, data): f = frames since the state appeared (30 fps), g = global frames.
 * Entrance: the ranges slide in from the right with parallax (near ranges travel further) while the
 * camera eases back; then only mist, light and water keep moving.
 */
import {springFast} from '../../src/springFast';
import {LayerSpec, hash, ridgeY} from '../../src/done/geom';
import {makeStroke, drawBrush, curvePts, InkPal} from '../../src/ink/core';
import {CORAL, H, LayerBmp, Look, Mode, Range, W, birds, blit, clamp01, eio, eo, glow, mist, mix, paintRange, rgba, sky, stone} from './paint';

export type StateId = 'setup' | 'night' | 'rest' | 'week' | 'countdown' | 'ready' | 'verified';
export type DemoData = {setupDone: boolean[]; bedtime: string; wake: string; nextDay: string; nextTime: string; weekDone: number; weekGoal: number; streakWeeks: number; lockIn: number; countdown: {remaining: number; window: number}};
export type Scene = {draw: (ctx: CanvasRenderingContext2D, f: number, g: number, d: DemoData) => void};

const M = (mode: Mode) =>
  mode === 'bold'
    ? {damping: 15, stiffness: 150, travel: 460, lift: 80, stagger: 1.8, push: 0.2}
    : {damping: 26, stiffness: 120, travel: 260, lift: 30, stagger: 2.6, push: 0.07};

export const enter = (mode: Mode, f: number, i: number, depth: number, g: number) => {
  const m = M(mode);
  const local = f - i * m.stagger;
  const p = springFast(local, 30, {damping: m.damping, stiffness: m.stiffness});
  return {dx: (1 - p) * m.travel * (0.25 + 0.75 * depth) + Math.sin(g * 0.01 + i * 1.3) * depth * 3, dy: (1 - p) * m.lift * depth, a: clamp01(local / 7)};
};

export const camera = (ctx: CanvasRenderingContext2D, mode: Mode, f: number, g: number) => {
  const m = M(mode);
  const p = springFast(f, 30, {damping: 24, stiffness: 60});
  const s = 1 + m.push * (1 - p) + Math.sin(g * 0.008) * 0.004;
  ctx.translate(760, H);
  ctx.scale(s, s);
  ctx.translate(-760, -H);
};

export const R = (seed: number, o: Partial<LayerSpec> & {depth: number; lit?: number; rim?: number; fog?: number}): Range => ({
  spec: {depth: o.depth, base: o.base ?? 300, amp: o.amp ?? 30, wave: o.wave ?? 220, detail: o.detail ?? 5, seed, peaks: o.peaks},
  depth: o.depth,
  lit: o.lit,
  rim: o.rim,
  fog: o.fog,
});

export type Ctx = {look: Look; px: number; mode: Mode};

// ---------- setup: a cairn waiting for its stones ----------
const setupScene = ({look, px, mode}: Ctx): Scene => {
  const sunX = 640;
  const ranges = [
    R(11, {depth: 0.1, base: 250, amp: 28, wave: 260, detail: 3}),
    R(12, {depth: 0.38, base: 292, amp: 32, wave: 200, detail: 6, lit: 0.6, rim: 1.1, peaks: [{x: 600, y: 205, sl: 0.7, sr: 0.75}]}),
    R(13, {depth: 0.62, base: 342, amp: 26, wave: 170, detail: 8, lit: 0.7, rim: 1.5}),
    R(14, {depth: 1, base: 600, amp: 0, wave: 100, detail: 3, lit: 0.6, rim: 2.2, fog: 0.15, peaks: [{x: 830, y: 404, sl: 0.5, sr: 0.42, flat: 120}]}),
  ];
  const L = ranges.map((r) => paintRange(r, look, sunX, px));
  const ledge = ridgeY(ranges[3].spec, 830);
  const stones = [
    {rx: 72, ry: 28, dy: 0, seed: 3},
    {rx: 54, ry: 23, dy: -47, seed: 5},
    {rx: 37, ry: 17, dy: -84, seed: 8},
  ];
  const changed: {v: boolean; t: number}[] = [];
  return {
    draw(ctx, f, g, d) {
      sky(ctx, look, 0, 320);
      ctx.save();
      camera(ctx, mode, f, g);
      glow(ctx, sunX, 150, 260, look.sun, look.dark ? 0.12 : 0.9);
      L.forEach((l, i) => {
        const e = enter(mode, f, i, l.depth, g);
        blit(ctx, l, e.dx, e.dy, e.a);
        if (i === 1) mist(ctx, look.fog, 300, W, 318, 70, g, 3, 0.25, 0.75);
        if (i === 2) mist(ctx, look.fog, 300, W, 372, 60, g, 5, 0.4, 0.6);
        if (i === 3) {
          const now = performance.now();
          stones.forEach((s, k) => {
            const on = d.setupDone[k];
            if (!changed[k]) changed[k] = {v: on, t: 0};
            if (changed[k].v !== on) changed[k] = {v: on, t: now};
            const fr = changed[k].t ? ((now - changed[k].t) / 1000) * 30 : 99;
            const drop = on ? springFast(fr, 30, mode === 'bold' ? {damping: 9, stiffness: 300} : {damping: 16, stiffness: 260}) : 1;
            const introDrop = springFast(f - 12 - k * 4, 30, mode === 'bold' ? {damping: 10, stiffness: 260} : {damping: 18, stiffness: 220});
            const fall = on ? (1 - drop) * -90 + (1 - introDrop) * -60 : 0;
            stone(ctx, look, 830 + e.dx + (k === 1 ? -3 : k === 2 ? 4 : 0), ledge - s.ry * 0.82 + s.dy + e.dy + fall, s.rx, s.ry, s.seed, on ? 0 : 1);
          });
        }
      });
      birds(ctx, look.ink, 560, 96, 3, g, 0.9, look.dark ? 0.5 : 0.55, 4);
      ctx.restore();
    },
  };
};

// ---------- night: moonlit ranges ----------
const nightScene = ({look, px, mode}: Ctx): Scene => {
  const moon = {x: 846, y: 116};
  const ranges = [
    R(21, {depth: 0.12, base: 262, amp: 30, wave: 260, detail: 3}),
    R(22, {depth: 0.4, base: 300, amp: 36, wave: 210, detail: 6, lit: 0.55, rim: 1.1, peaks: [{x: 720, y: 220, sl: 0.7, sr: 0.8}]}),
    R(23, {depth: 0.68, base: 352, amp: 28, wave: 170, detail: 8, lit: 0.6, rim: 1.4}),
    R(24, {depth: 1, base: 412, amp: 20, wave: 150, detail: 8, lit: 0.5, rim: 2, fog: 0.2}),
  ];
  const L = ranges.map((r) => paintRange(r, look, moon.x, px));
  return {
    draw(ctx, f, g) {
      sky(ctx, look, 0, 360);
      ctx.save();
      camera(ctx, mode, f, g);
      for (let i = 0; i < 46; i++) {
        const x = 420 + hash(i, 5) * 580, y = 14 + hash(i, 6) * 250;
        const tw = 0.45 + 0.55 * (0.5 + 0.5 * Math.sin(g * (mode === 'bold' ? 0.1 : 0.05) + i * 2.3));
        const a = clamp01((f - 4 - i * 0.4) / 8) * tw * (0.35 + hash(i, 7) * 0.65);
        ctx.fillStyle = rgba('#FFFFFF', a);
        ctx.beginPath();
        ctx.arc(x, y, 0.6 + hash(i, 8) * 1.3, 0, Math.PI * 2);
        ctx.fill();
      }
      const mp = springFast(f - 2, 30, {damping: 22, stiffness: 70});
      const my = moon.y + (1 - mp) * 50;
      glow(ctx, moon.x, my, 190, '#FFFFFF', 0.18 * mp);
      ctx.beginPath();
      ctx.arc(moon.x, my, 27, 0, Math.PI * 2);
      const mg = ctx.createRadialGradient(moon.x - 8, my - 8, 2, moon.x, my, 28);
      mg.addColorStop(0, rgba('#FFFFFF', mp));
      mg.addColorStop(1, rgba('#D9D9D4', mp));
      ctx.fillStyle = mg;
      ctx.fill();
      // faint maria so it reads as the moon, not a dot
      [[-7, -4, 7], [6, 6, 5], [8, -9, 3.5]].forEach(([dx, dy, r]) => {
        ctx.beginPath();
        ctx.arc(moon.x + dx, my + dy, r, 0, Math.PI * 2);
        ctx.fillStyle = rgba('#9C9C96', 0.25 * mp);
        ctx.fill();
      });
      if (mode === 'bold') {
        const st = (g % 240) / 240;
        if (st < 0.1) {
          const t = st / 0.1;
          const x = 980 - t * 340, y = 30 + t * 110;
          const gr = ctx.createLinearGradient(x, y, x + 60, y - 20);
          gr.addColorStop(0, rgba('#FFFFFF', 1 - t));
          gr.addColorStop(1, rgba('#FFFFFF', 0));
          ctx.strokeStyle = gr;
          ctx.lineWidth = 1.6;
          ctx.beginPath();
          ctx.moveTo(x, y);
          ctx.lineTo(x + 60, y - 20);
          ctx.stroke();
        }
      }
      L.forEach((l, i) => {
        const e = enter(mode, f, i, l.depth, g);
        blit(ctx, l, e.dx, e.dy, e.a);
        if (i === 1) mist(ctx, look.fog, 300, W, 330, 70, g, 7, 0.2, 0.6);
        if (i === 2) mist(ctx, look.fog, 300, W, 392, 60, g, 9, 0.32, 0.5);
      });
      ctx.restore();
    },
  };
};

// ---------- rest: still water, the ranges reflected ----------
const restScene = ({look, px, mode}: Ctx): Scene => {
  const HZ = 312;
  const sun = {x: 820, y: 262};
  const ranges = [
    R(31, {depth: 0.1, base: 262, amp: 24, wave: 280, detail: 3}),
    R(32, {depth: 0.4, base: 290, amp: 26, wave: 220, detail: 5, lit: 0.5, rim: 1, peaks: [{x: 640, y: 222, sl: 0.6, sr: 0.7}]}),
    R(33, {depth: 0.7, base: 308, amp: 12, wave: 180, detail: 5, lit: 0.4, rim: 1.2}),
  ];
  const L = ranges.map((r) => paintRange(r, look, sun.x, px, -380, W + 60, -40, HZ + 2));
  return {
    draw(ctx, f, g) {
      sky(ctx, look, 0, HZ);
      ctx.save();
      camera(ctx, mode, f, g);
      const sp = springFast(f - 3, 30, {damping: 22, stiffness: 70});
      glow(ctx, sun.x, sun.y + (1 - sp) * 30, 230, look.sun, (look.dark ? 0.16 : 1) * sp);
      ctx.beginPath();
      ctx.arc(sun.x, sun.y + (1 - sp) * 30, 26, 0, Math.PI * 2);
      ctx.fillStyle = rgba(look.dark ? '#E8E8E4' : '#FFFFFF', sp);
      ctx.fill();
      const es = L.map((l, i) => enter(mode, f, i, l.depth, g));
      L.forEach((l, i) => blit(ctx, l, es[i].dx, es[i].dy, es[i].a));
      // water
      const wg = ctx.createLinearGradient(0, HZ, 0, H);
      wg.addColorStop(0, look.skyBot);
      wg.addColorStop(1, mix(look.skyBot, look.near, look.dark ? 0.25 : 0.08));
      ctx.fillStyle = wg;
      ctx.fillRect(0, HZ, W, H - HZ + 20);
      // reflection, broken into slices by the ripples
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, HZ, W, H - HZ);
      ctx.clip();
      const amp = mode === 'bold' ? 4 : 2.2;
      for (let y = HZ; y < H; y += 4) {
        const k = (y - HZ) / (H - HZ);
        const off = Math.sin(y * 0.18 + g * 0.08) * amp * (0.3 + k);
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, y, W, 4.2);
        ctx.clip();
        L.forEach((l, i) => blit(ctx, l, es[i].dx + off, -es[i].dy, es[i].a * (0.32 - k * 0.22), HZ));
        ctx.restore();
      }
      ctx.restore();
      // sun on the water
      for (let i = 0; i < 12; i++) {
        const y = HZ + 6 + i * 11;
        const w = (34 - i * 2) * (0.6 + 0.4 * Math.sin(g * 0.09 + i * 1.7)) * sp;
        ctx.strokeStyle = rgba(look.dark ? '#FFFFFF' : '#FFFFFF', (0.85 - i * 0.06) * (look.dark ? 0.35 : 1));
        ctx.lineWidth = 2;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(sun.x - w / 2 + Math.sin(g * 0.05 + i) * 4, y);
        ctx.lineTo(sun.x + w / 2 + Math.sin(g * 0.05 + i) * 4, y);
        ctx.stroke();
      }
      for (let i = 0; i < 8; i++) {
        const y = HZ + 18 + i * 20;
        const x0 = 380 + hash(i, 3) * 300, len = 80 + hash(i, 4) * 220;
        ctx.strokeStyle = rgba(look.ink, 0.06);
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(x0 + Math.sin(g * 0.02 + i) * 10, y);
        ctx.lineTo(x0 + len + Math.sin(g * 0.02 + i) * 10, y);
        ctx.stroke();
      }
      mist(ctx, look.fog, 300, W, HZ - 6, 34, g, 11, 0.18, 0.7);
      birds(ctx, look.ink, 520 + ((g * 0.4) % 600) * -0 + 0, 150, 2, g, 0.8, 0.45, 9);
      ctx.restore();
    },
  };
};

// ---------- week: the week as a painting — one peak per session, painted when it is done ----------
const weekScene = ({look, px, mode}: Ctx, goal: number): Scene => {
  const sunX = 640;
  const back = paintRange(R(41, {depth: 0.08, base: 268, amp: 26, wave: 260, detail: 3}), look, sunX, px);
  const xs = Array.from({length: goal}, (_, k) => 560 + ((940 - 560) * (k + 0.5)) / goal + (goal === 1 ? 0 : 0));
  const peaks = xs.map((x, k) => {
    const h = 210 - k * (90 / Math.max(1, goal - 1)) * (goal > 1 ? 1 : 0);
    const spec: LayerSpec = {depth: 0.5 + k * 0.15, base: 620, amp: 0, wave: 100, detail: 5, seed: 50 + k, peaks: [{x, y: h, sl: 0.85, sr: 0.75, flat: 4}]};
    const depth = 0.45 + (k / Math.max(1, goal - 1)) * 0.5;
    const bmp = paintRange({spec, depth, lit: 0.85, rim: 1.6, fog: 0.75 - depth * 0.5}, look, sunX, px);
    // pencil sketch of the same ridge, for weeks not yet earned
    const pts: [number, number][] = [];
    for (let xx = x - 170; xx <= x + 170; xx += 4) pts.push([xx, ridgeY(spec, xx)]);
    const sketch = makeStroke(pts, () => 1.1, 3);
    const hatch = Array.from({length: 7}, (_, j) => {
      const hx = x - 18 + j * 10 + hash(j, k) * 6;
      const hy = ridgeY(spec, hx) + 12;
      return makeStroke([[hx, hy], [hx - 10, hy + 26 + hash(j, k + 3) * 22]], () => 0.9, 2);
    });
    return {bmp, sketch, hatch, x, top: h};
  });
  const pal = (hex: string): InkPal => ({paper: '#fff', paper2: '#fff', ink: [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)], text: '', sub: '', hair: ''}) as unknown as InkPal;
  const pencil = pal(look.dark ? '#BDBDC2' : '#5E5E5E');
  return {
    draw(ctx, f, g, d) {
      sky(ctx, look, 0, 330);
      ctx.save();
      camera(ctx, mode, f, g);
      glow(ctx, sunX, 130, 240, look.sun, look.dark ? 0.12 : 0.9);
      const e0 = enter(mode, f, 0, 0.08, g);
      blit(ctx, back, e0.dx, e0.dy, e0.a);
      mist(ctx, look.fog, 300, W, 300, 60, g, 13, 0.2, 0.6);
      // pencil first (weeks still to earn), then the painted peaks on top of it
      peaks.forEach((p, k) => {
        if (k < d.weekDone) return;
        const e = enter(mode, f, k + 1, p.bmp.depth, g);
        drawBrush(ctx, shift(p.sketch, e.dx, e.dy), eio((f - 4 - k * 3) / 16), {bristles: 2, dry: 0.3, seed: k, alpha: 0.5, core: 1}, pencil);
        p.hatch.forEach((h, j) => drawBrush(ctx, shift(h, e.dx, e.dy), eo((f - 14 - k * 3 - j) / 6), {bristles: 1, dry: 0, seed: j, alpha: 0.3, core: 1}, pencil));
      });
      peaks.forEach((p, k) => {
        if (k >= d.weekDone) return;
        const e = enter(mode, f, k + 1, p.bmp.depth, g);
        const at = 12 + k * (mode === 'bold' ? 4 : 6);
        drawBrush(ctx, shift(p.sketch, e.dx, e.dy), eio((f - 4 - k * 3) / 16) * (1 - eo((f - at) / 10)), {bristles: 2, dry: 0.3, seed: k, alpha: 0.4, core: 1}, pencil);
        const bleed = mode === 'bold' ? springFast(f - at, 30, {damping: 12, stiffness: 220}) : eo((f - at) / 18);
        blit(ctx, p.bmp, e.dx, e.dy + (1 - bleed) * 24, clamp01(bleed) * e.a);
      });
      mist(ctx, look.fog, 300, W, 420, 80, g, 17, 0.3, 0.85);
      ctx.restore();
    },
  };
};
const shift = (s: ReturnType<typeof makeStroke>, dx: number, dy: number) => {
  if (dx === 0 && dy === 0) return s;
  const x = new Float32Array(s.x.length), y = new Float32Array(s.y.length);
  for (let i = 0; i < x.length; i++) {
    x[i] = s.x[i] + dx;
    y[i] = s.y[i] + dy;
  }
  return {...s, x, y};
};

// ---------- countdown: dawn — the sun climbs as gym time gets closer ----------
const countdownScene = ({look, px, mode}: Ctx): Scene => {
  const sunX = 790;
  const ranges = [
    R(61, {depth: 0.12, base: 300, amp: 26, wave: 260, detail: 3}),
    R(62, {depth: 0.45, base: 336, amp: 30, wave: 200, detail: 6, lit: 0.6, rim: 1.2, peaks: [{x: 700, y: 268, sl: 0.6, sr: 0.7}]}),
    R(63, {depth: 0.75, base: 386, amp: 22, wave: 170, detail: 8, lit: 0.6, rim: 1.6}),
    R(64, {depth: 1, base: 438, amp: 14, wave: 150, detail: 7, lit: 0.5, rim: 2, fog: 0.2}),
  ];
  const L = ranges.map((r) => paintRange(r, look, sunX, px));
  return {
    draw(ctx, f, g, d) {
      const frac = clamp01(1 - d.countdown.remaining / d.countdown.window);
      // the sky warms from pre-dawn grey to morning white as the window runs out
      const pre = look.dark ? '#0C0C0E' : '#DAD9D4';
      const skyLook = {...look, skyTop: mix(pre, look.skyTop, frac), skyBot: mix(mix(pre, '#FFFFFF', 0.4), look.skyBot, frac)};
      sky(ctx, skyLook, 0, 380);
      ctx.save();
      camera(ctx, mode, f, g);
      const intro = springFast(f, 30, {damping: 24, stiffness: 90});
      const sy = 398 - frac * 190 + (1 - intro) * 40;
      glow(ctx, sunX, sy, 250, look.sun, (look.dark ? 0.2 : 0.95) * (0.5 + frac * 0.5));
      ctx.beginPath();
      ctx.arc(sunX, sy, 30, 0, Math.PI * 2);
      ctx.fillStyle = rgba(look.dark ? '#EDEDE8' : '#FFFFFF', 1);
      ctx.fill();
      L.forEach((l, i) => {
        const e = enter(mode, f, i, l.depth, g);
        blit(ctx, l, e.dx, e.dy, e.a);
        if (i === 1) mist(ctx, look.fog, 300, W, 360, 60, g, 19, 0.25, 0.65);
        if (i === 2) mist(ctx, look.fog, 300, W, 418, 60, g, 21, 0.4, 0.5);
      });
      // the window: a hairline ring around the sun, filling in coral
      const ra = clamp01((f - 8) / 10);
      const rr = 54;
      ctx.lineCap = 'round';
      ctx.lineWidth = 3;
      ctx.strokeStyle = rgba(look.ink, 0.12 * ra);
      ctx.beginPath();
      ctx.arc(sunX, sy, rr, 0, Math.PI * 2);
      ctx.stroke();
      ctx.strokeStyle = rgba(CORAL, ra);
      ctx.beginPath();
      ctx.arc(sunX, sy, rr, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac * eo((f - 8) / 22));
      ctx.stroke();
      if (mode === 'bold') {
        const tick = 1 - (Math.ceil(d.countdown.remaining) - d.countdown.remaining);
        const pulse = clamp01(1 - tick * 3.5);
        if (pulse > 0) {
          ctx.strokeStyle = rgba(CORAL, pulse * 0.6);
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.arc(sunX, sy, rr + 4 + (1 - pulse) * 20, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
      ctx.restore();
    },
  };
};

// ---------- ready: the mist lifts off the summit, first light ----------
const readyScene = ({look, px, mode}: Ctx): Scene => {
  const sunX = 870, sunY = 96;
  const ranges = [
    R(71, {depth: 0.12, base: 290, amp: 26, wave: 260, detail: 3}),
    R(72, {depth: 0.5, base: 520, amp: 0, wave: 100, detail: 7, lit: 0.95, rim: 1.6, fog: 0.6, peaks: [{x: 760, y: 150, sl: 0.85, sr: 0.7, flat: 3}]}),
    R(73, {depth: 0.8, base: 400, amp: 22, wave: 170, detail: 8, lit: 0.7, rim: 1.8}),
  ];
  const L = ranges.map((r) => paintRange(r, look, sunX, px));
  return {
    draw(ctx, f, g) {
      sky(ctx, look, 0, 300);
      ctx.save();
      camera(ctx, mode, f, g);
      const light = eo((f - 6) / 26);
      glow(ctx, sunX, sunY, 300, look.sun, (look.dark ? 0.22 : 1) * light);
      // rays of first light
      ctx.save();
      ctx.translate(sunX, sunY);
      ctx.rotate(g * (mode === 'bold' ? 0.0025 : 0.0008));
      for (let i = 0; i < 9; i++) {
        const a = Math.PI * 0.55 + (i / 8) * Math.PI * 0.75;
        const w = 0.05 + hash(i, 3) * 0.05;
        const L2 = 700;
        const rg = ctx.createRadialGradient(0, 0, 0, 0, 0, L2);
        rg.addColorStop(0, rgba(look.dark ? '#FFFFFF' : '#FFFFFF', (look.dark ? 0.1 : 0.55) * light));
        rg.addColorStop(1, rgba('#FFFFFF', 0));
        ctx.fillStyle = rg;
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(Math.cos(a - w) * L2, Math.sin(a - w) * L2);
        ctx.lineTo(Math.cos(a + w) * L2, Math.sin(a + w) * L2);
        ctx.closePath();
        ctx.fill();
      }
      ctx.restore();
      L.forEach((l, i) => {
        const e = enter(mode, f, i, l.depth, g);
        blit(ctx, l, e.dx, e.dy, e.a);
      });
      // the mist parts: banks slide off left and right and thin out
      const part = mode === 'bold' ? springFast(f - 4, 30, {damping: 14, stiffness: 120}) : eio((f - 4) / 34);
      for (let k = 0; k < 3; k++) {
        const y = 200 + k * 70;
        mist(ctx, look.fog, 300 - part * (200 + k * 60), W - part * (200 + k * 60), y, 90, g, 23 + k, 0.2, (1 - part) * 0.95 + 0.15 * (k === 2 ? 1 : 0), 5);
        mist(ctx, look.fog, 700 + part * 300, W + 400 + part * 300, y + 20, 80, g, 31 + k, 0.2, (1 - part) * 0.9, 4);
      }
      mist(ctx, look.fog, 300, W, 440, 70, g, 41, 0.35, 0.75);
      ctx.restore();
    },
  };
};

// ---------- verified: the summit, above a sea of clouds ----------
const verifiedScene = ({look, px, mode}: Ctx): Scene => {
  const sunX = 880, sunY = 110;
  const ranges = [
    R(81, {depth: 0.15, base: 330, amp: 30, wave: 240, detail: 4, lit: 0.4, peaks: [{x: 560, y: 268, sl: 0.7, sr: 0.8}]}),
    R(82, {depth: 0.85, base: 640, amp: 0, wave: 100, detail: 8, lit: 1, rim: 2, fog: 0.5, peaks: [{x: 790, y: 118, sl: 0.9, sr: 0.72, flat: 3}]}),
  ];
  const L = ranges.map((r) => paintRange(r, look, sunX, px));
  return {
    draw(ctx, f, g) {
      sky(ctx, look, 0, 300);
      ctx.save();
      camera(ctx, mode, f, g);
      const light = eo((f - 4) / 22);
      glow(ctx, sunX, sunY, 320, look.sun, (look.dark ? 0.25 : 1) * light);
      ctx.beginPath();
      ctx.arc(sunX, sunY, 24, 0, Math.PI * 2);
      ctx.fillStyle = rgba(look.dark ? '#EDEDE8' : '#FFFFFF', light);
      ctx.fill();
      L.forEach((l, i) => {
        const e = enter(mode, f, i, l.depth, g);
        blit(ctx, l, e.dx, e.dy, e.a);
        if (i === 0) mist(ctx, look.fog, 300, W, 318, 70, g, 43, 0.25, 0.85);
      });
      // the sea of clouds, flowing past the peak
      mist(ctx, look.fog, 280, W, 380, 110, g, 47, mode === 'bold' ? 0.9 : 0.45, 0.95, 8);
      mist(ctx, look.fog, 280, W, 452, 110, g, 53, mode === 'bold' ? 1.3 : 0.65, 1, 8);
      birds(ctx, look.ink, 610, 150, 2, g, 1, look.dark ? 0.5 : 0.55, 13);
      ctx.restore();
    },
  };
};

export const buildScene = (s: StateId, ctx: Ctx, d: DemoData): Scene => {
  switch (s) {
    case 'setup':
      return setupScene(ctx);
    case 'night':
      return nightScene(ctx);
    case 'rest':
      return restScene(ctx);
    case 'week':
      return weekScene(ctx, d.weekGoal);
    case 'countdown':
      return countdownScene(ctx);
    case 'ready':
      return readyScene(ctx);
    case 'verified':
      return verifiedScene(ctx);
  }
};

export {curvePts};
