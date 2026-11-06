/**
 * Matrix Dynamic: verified. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * The home card's done state shows the same object the full-screen done flow builds with taps
 * (mxstory.ts), finished: a short build-and-land (about 1 to 2 s), one beat with flash and haptics
 * on the visual hit, then a calm idle. Nothing is broken; everything is built up and stays built.
 * Particles lag a moving target (spring, about 0.1 s per unit of speed), so every hit is timed to
 * when the dots actually arrive, not when the target does.
 */
import {CX, CY, G, MC, MScn, back, cl, eio, ez, lerp} from '../mxlib';
import {TAU} from './common';

/** a decaying flash that starts at age 0 */
const fl = (a: number, d = 0.15, k = 0.3) => (a >= 0 ? Math.exp(-a / d) * k : 0);
/** taps in the done flow: five, seven for the week's last */
const nOf = (c: MC) => Math.max(3, Math.min(7, c.N || 5));
/** a soft band of light that crosses a coordinate every P seconds, after `from` */
const sweep = (T: number, from: number, P: number, pos: number, lo: number, hi: number, w = 2.5) => {
  if (T < from) return 0;
  const q = (((T - from) / P) % 1) * (hi - lo + 2 * w * 3) + lo - w * 3;
  return Math.exp(-(((pos - q) / w) ** 2)) * cl((T - from) / 0.6);
};

// ---------------------------------------------------------------- Mon: SUNRISE
const HY = 24, SX = 22, SY = 17;
const DISC: [number, number][] = [];
for (let dy = -5; dy <= 5; dy++) for (let dx = -5; dx <= 5; dx++) if (dx * dx + dy * dy <= 28) DISC.push([dx, dy]);
const sunY = (T: number) => lerp(HY + 6, SY, eio((T - 0.25) / 0.8));

const sunrise: MScn = {
  draw: (g, c) => {
    const T = c.T;
    // the horizon, and two quiet rows under it
    g.line(8, HY, 36, HY, 0.8);
    for (let x = 11; x <= 33; x += 2) g.on(x, HY + 2, 0.36);
    for (let x = 15; x <= 29; x += 2) g.on(x, HY + 4, 0.18);
    // the sun rises from behind the line; dots below it stay dark (allowing for the spring's lag)
    const sy = sunY(T), v = (sunY(T) - sunY(T - 0.03)) / 0.03, seen = sy - 0.11 * v;
    const lit = T > 1.15;
    for (const [dx, dy] of DISC) g.fr(SX + dx + 0.5, sy + dy + 0.5, seen + dy + 0.5 < HY - 0.6 ? 1 : 0, lit && !dx && !dy ? 1 : 0);
    // eleven rays fan out over the top half, the middle one first, then breathe
    for (let k = 0; k < 11; k++) {
      const a = Math.PI + ((k + 0.5) * Math.PI) / 11;
      const e = back(cl((T - 0.98 - Math.abs(k - 5) * 0.035) / 0.32), 1.5);
      const len = (3.6 + 0.55 * Math.sin(c.t * 1.5 - k * 0.55) * cl((T - 1.6) / 1)) * e;
      for (let s = 0; s < 4; s++) {
        const rr = 7 + (s / 3) * len;
        g.fr(SX + 0.5 + Math.cos(a) * rr, sy + 0.5 + Math.sin(a) * rr, e > 0.02 ? (0.95 - s * 0.2) * cl(e * 1.6) : 0);
      }
    }
    return {o: {stagger: 0.3}, flash: fl(T - 1.15, 0.16, 0.28), shake: T > 1.15 && T < 1.3 ? 0.2 : 0};
  },
  hap: [{t: 0.45, kind: 'light'}, {t: 1.15, kind: 'heavy'}, {t: 1.22, kind: 'success'}],
};

// ---------------------------------------------------------------- Tue: THE WALL
const wallSlots = (N: number) => {
  const s = N >= 7 ? 5 : 6, st = s + 1, nb = N >= 7 ? 4 : 3, nt = N - nb;
  const yT = Math.round(CY - (2 * st - 1) / 2), yB = yT + st;
  const o: [number, number][] = [];
  for (let i = 0; i < nb; i++) o.push([Math.round(CX - (nb * st - 1) / 2 + i * st), yB]);
  for (let i = 0; i < nt; i++) o.push([Math.round(CX - (nt * st - 1) / 2 + i * st), yT]);
  return {s, o};
};
const DROP0 = 0.3, DROPK = 0.15, FALL = 0.18, ARRIVE = 0.33; // a block's dots settle ~0.33 s after its drop starts
const lands = (N: number) => Array.from({length: N}, (_, k) => DROP0 + k * DROPK + ARRIVE);

const wall: MScn = {
  draw: (g, c) => {
    const T = c.T, N = nOf(c), {s, o: S} = wallSlots(N), L = lands(N), key = L[N - 1];
    const xs = S.map(([x]) => x), ys = S.map(([, y]) => y);
    const x0 = Math.min(...xs) - 2, y0 = Math.min(...ys) - 2, x1 = Math.max(...xs) + s + 2, y1 = Math.max(...ys) + s + 2;
    // the empty slots, until each block lands in its own
    S.forEach(([x, y], k) => {
      if (T < L[k] - 0.05) g.rect(x, y, s, s, 0.16);
    });
    // the lock: an outline drawn from the top centre both ways, closing at the bottom
    const W = x1 - x0, H = y1 - y0, per = 2 * (W + H) - 4, prog = ez((T - key - 0.08) / 0.32);
    if (prog > 0) {
      for (let i = 0; i < W; i++)
        for (const y of [y0, y1 - 1]) {
          const d = y === y0 ? Math.abs(i - (W - 1) / 2) : W / 2 + H - 1 + ((W - 1) / 2 - Math.abs(i - (W - 1) / 2));
          if (d <= (prog * per) / 2 + 0.5) g.on(x0 + i, y, 0.9);
        }
      for (let j = 1; j < H - 1; j++) {
        const d = W / 2 + j;
        if (d <= (prog * per) / 2 + 0.5) g.on(x0, y0 + j, 0.9), g.on(x1 - 1, y0 + j, 0.9);
      }
    }
    // the blocks drop in one by one, bottom row first; the last one is the keystone
    S.forEach(([x, y], k) => {
      const t0 = DROP0 + k * DROPK, a = T - t0;
      const yy = a < 0 ? y - 9 : a < FALL ? lerp(y - 9, y, (a / FALL) ** 2) : y;
      const on = a >= 0;
      for (let v = 0; v < s; v++)
        for (let u = 0; u < s; u++) {
          const core = k === N - 1 && (s === 6 ? (u === 2 || u === 3) && (v === 2 || v === 3) : u === 2 && v === 2);
          const b = (0.84 + 0.16 * sweep(T, key + 0.7, 5, x + u - (y + v) * 0.5, 0, 40, 3)) * cl(a / 0.08);
          g.fr(x + u + 0.5, yy + v + 0.5, on ? b : 0, core && T > key ? 1 : 0);
        }
    });
    const small = L.slice(0, -1).reduce((m, l) => m + fl(T - l, 0.08, 0.07), 0);
    return {o: {stagger: 0.3}, flash: small + fl(T - key, 0.15, 0.28), shake: T > key && T < key + 0.16 ? 0.35 : 0};
  },
  hap: [...lands(5).slice(0, 4).map((t) => ({t, kind: 'light' as const})), {t: lands(5)[4], kind: 'heavy'}, {t: lands(5)[4] + 0.4, kind: 'success'}],
};

// ---------------------------------------------------------------- Wed: BATTERY
const BOLT = ['....#####', '...#####.', '..#####..', '.#####...', '#########', '#########', '....####.', '...####..', '..####...', '.####....', '###......', '#........'];
const BX = 9, BW = 25, BY = 18, BH = 12; // body 9..33 x 18..29, terminal 34..35
const segT = (N: number, k: number) => 0.35 + k * (0.7 / N);
const FULL = (N: number) => segT(N, N - 1) + 0.16;

const battery: MScn = {
  draw: (g, c) => {
    const T = c.T, N = nOf(c), full = FULL(N), done = T > full + 0.04;
    g.rect(BX, BY, BW, BH, 0.8);
    g.rect(BX + BW, BY + 3, 2, BH - 6, 0.8, true);
    if (done) g.on(BX + BW + 1, BY + 5, 1, 1), g.on(BX + BW + 1, BY + 6, 1, 1);
    // cells fill one after another, an anti-aliased edge sweeping left to right
    let lv = 0;
    for (let k = 0; k < N; k++) lv += ez((T - segT(N, k)) / 0.16);
    const IW = BW - 4, fx = (lv / N) * IW;
    for (let i = 0; i < IW; i++) {
      const f = cl(fx - i);
      const b = f * (0.86 + 0.14 * sweep(T, full + 0.6, 3.2, i, 0, IW, 2.2));
      for (let y = BY + 2; y < BY + BH - 2; y++) if (f > 0.01) g.on(BX + 2 + i, y, b);
    }
    for (let k = 1; k < N; k++) {
      const i = Math.round((k / N) * IW);
      if (i > fx) for (let y = BY + 3; y < BY + BH - 3; y += 2) g.on(BX + 2 + i, y, 0.22);
    }
    // the bolt flickers up with each cell, then holds at full
    let pop = 0;
    for (let k = 0; k < N; k++) pop = Math.max(pop, fl(T - segT(N, k) - 0.16, 0.22, 0.45));
    const bb = done ? 1 : 0.28 + pop;
    g.glyph(BOLT, CX - 4, 4, 1, bb);
    // two rings go out at full charge
    for (let r = 0; r < 2; r++) {
      const a = T - full - 0.05 - r * 0.2, R = 15 + a * 22;
      for (let k = 0; k < 44; k++) {
        const q = (k / 44) * TAU;
        g.fr(CX + 0.5 + Math.sin(q) * R, BY + BH / 2 - Math.cos(q) * R * 0.55, a > 0 && a < 0.75 ? (1 - a / 0.75) * 0.75 : 0);
      }
    }
    const tick = Array.from({length: N - 1}, (_, k) => fl(T - segT(N, k) - 0.16, 0.08, 0.06)).reduce((a, b) => a + b, 0);
    return {o: {stagger: 0.3}, flash: tick + fl(T - full, 0.15, 0.28), shake: T > full && T < full + 0.14 ? 0.25 : 0};
  },
  hap: [...Array.from({length: 4}, (_, k) => ({t: segT(5, k) + 0.16, kind: 'light' as const})), {t: FULL(5), kind: 'heavy'}, {t: FULL(5) + 0.07, kind: 'success'}],
};

// ---------------------------------------------------------------- Thu: BARBELL
const plateSet = (N: number) => {
  // one-cell plates with a cell between them, so each reads on its own; the week's last bar packs the small ones
  const H = N >= 7 ? [16, 16, 16, 14, 14, 10, 8] : [16, 16, 16, 14, 12].slice(0, N);
  const Wd = H.map(() => 1);
  const co = N >= 7 ? 3 : 13 - 2 * (N - 1);
  const off = H.map((_, k) => (k < 5 ? co + 1 + 2 * k : co + 9 + (k - 4)));
  return {H, Wd, co, off};
};
const PL0 = 0.3, PLK = 0.12, PLA = 0.3; // plate k slides at PL0 + k * PLK, its dots seat ~PLA later
const LIFT0 = (N: number) => PL0 + (N - 1) * PLK + PLA + 0.04;
const LOCK = (N: number) => LIFT0(N) + 0.36;

const barbell: MScn = {
  draw: (g, c) => {
    const T = c.T, N = nOf(c), {H, Wd, co, off} = plateSet(N), l0 = LIFT0(N), lock = LOCK(N);
    const yb = 21 - 7 * back(cl((T - l0) / 0.45), 1.3);
    const gl = (x: number) => 0.22 * sweep(T, lock + 0.8, 4.5, x, 6, 38, 2);
    g.line(8, 30, 36, 30, 0.28);
    // the bar and its collars
    for (let x = -15; x <= 15; x++) for (const w of [0, 1]) g.fr(CX + x + 0.5, yb + w + 0.5, 0.62 + gl(CX + x));
    for (const sd of [-1, 1]) for (let v = -2; v <= 3; v++) g.fr(CX + sd * co + 0.5, yb + v + 0.5, 0.92);
    // a plate slides onto both ends at once, biggest first
    for (const sd of [-1, 1])
      for (let k = 0; k < N; k++) {
        const a = T - PL0 - k * PLK, slide = a < 0 ? 12 : (1 - ez(a / 0.2)) * 12;
        for (let u = 0; u < Wd[k]; u++)
          for (let v = 0; v < H[k]; v++) {
            const x = CX + sd * (off[k] + u + slide);
            g.fr(x + 0.5, yb + 1 - H[k] / 2 + v + 0.5, a >= 0 ? 0.95 + gl(x) : 0);
          }
      }
    g.fr(CX + 0.5, yb - 0.5, T > lock ? 1 : 0, 1);
    const clack = Array.from({length: N}, (_, k) => fl(T - PL0 - k * PLK - PLA, 0.08, 0.06)).reduce((a, b) => a + b, 0);
    return {o: {stagger: 0.3}, flash: clack + fl(T - lock, 0.16, 0.26), shake: T > lock && T < lock + 0.15 ? 0.22 : 0};
  },
  hap: [...Array.from({length: 5}, (_, k) => ({t: PL0 + k * PLK + PLA, kind: (k === 4 ? 'medium' : 'light') as 'medium' | 'light'})), {t: LOCK(5), kind: 'heavy'}, {t: LOCK(5) + 0.07, kind: 'success'}],
};

// ---------------------------------------------------------------- Fri: +1
const ONE = ['00100', '01100', '00100', '00100', '00100', '00100', '01110'];
const PLUS = ['..#..', '..#..', '#####', '..#..', '..#..'];
const BURST = 1.12;
const chevT = (k: number) => 0.22 + k * 0.09;

const plusOne: MScn = {
  draw: (g, c) => {
    const T = c.T, N = nOf(c);
    if (T >= BURST) {
      // the +1, as the owner likes it: a plus and a tall 1, a soft glint crossing now and then
      const px = CX - 12, py = CY - 5, ox = Math.round(CX + 5 - 7.5), oy = CY - 10;
      const b = (x: number, y: number) => 0.88 + 0.12 * sweep(T, BURST + 1.2, 4.5, x - y * 0.6, 0, 40, 2.2);
      PLUS.forEach((r, j) => [...r].forEach((ch, i) => {
        if (ch === '#') for (let v = 0; v < 2; v++) for (let u = 0; u < 2; u++) g.on(px + i * 2 + u, py + j * 2 + v, b(px + i * 2 + u, py + j * 2 + v));
      }));
      ONE.forEach((r, j) => [...r].forEach((ch, i) => {
        if (ch === '1') for (let v = 0; v < 3; v++) for (let u = 0; u < 3; u++) g.on(ox + i * 3 + u, oy + j * 3 + v, b(ox + i * 3 + u, oy + j * 3 + v));
      }));
      g.on(CX - 8, CY - 1, 1, 1);
      return {ph: 'plus', o: {burst: 36, stagger: 0.04}, flash: fl(T - BURST, 0.15, 0.3), shake: T < BURST + 0.18 ? 0.38 : 0};
    }
    // the chevrons light bottom to top, then the stack climbs
    const sp = N >= 7 ? 3.4 : 4.5, rise = -12 * eio((T - 0.66) / 0.4);
    let last = -1;
    for (let k = 0; k < N; k++) if (T >= chevT(k)) last = k;
    for (let k = 0; k < N; k++) {
      const w = 8 - Math.round(k * (N >= 7 ? 0.67 : 1)), ay = Math.round(27 - k * sp) + rise;
      const a = T - chevT(k), b = a < 0 ? 0.15 : a < 0.12 ? 1 : 0.84;
      for (let i = -8; i <= 8; i++)
        for (const dy of [0, 1]) {
          const show = Math.abs(i) <= w;
          g.fr(CX + i + 0.5, ay + Math.floor(Math.abs(i) / 2) + dy + 0.5, show ? b : 0, show && k === last && i === 0 && dy === 0 ? 1 : 0);
        }
    }
    return {ph: 'track', o: {stagger: 0.25}, flash: last >= 0 ? fl(T - chevT(last), 0.08, 0.05) : 0};
  },
  hap: [{t: 0.22, kind: 'light'}, {t: 0.4, kind: 'light'}, {t: 0.58, kind: 'medium'}, {t: BURST, kind: 'heavy'}, {t: BURST + 0.06, kind: 'success'}],
};

// ---------------------------------------------------------------- Sat: RING
type Cell = {x: number; y: number; a: number};
const ringCells = (cx: number, cy: number, r: number): Cell[] => {
  const m = new Map<number, Cell>();
  const n = Math.round(TAU * r * 1.5);
  for (let i = 0; i < n; i++) {
    const a = (i / n) * TAU, x = Math.floor(cx + Math.sin(a) * r), y = Math.floor(cy - Math.cos(a) * r);
    const k = y * 256 + x;
    if (!m.has(k)) m.set(k, {x, y, a});
  }
  return [...m.values()];
};
const RR = 12, RCX = CX + 0.5, RCY = CY + 0.5;
const RING = [...ringCells(RCX, RCY, RR).map((q) => ({...q, b: 1})), ...ringCells(RCX, RCY, RR - 1).map((q) => ({...q, b: 0.82}))];
const arcT = (N: number, k: number) => 0.3 + k * (0.7 / N);
const SEAL = (N: number) => arcT(N, N - 1) + 0.24;

const ring: MScn = {
  draw: (g, c) => {
    const T = c.T, N = nOf(c), seal = SEAL(N), sealed = T >= seal, gap = sealed ? 0 : 0.07;
    // how far round the light has come: N arcs, each closing in turn
    const arcEnd = (k: number) => lerp((k / N) * TAU + gap, ((k + 1) / N) * TAU - gap, ez((T - arcT(N, k)) / 0.22));
    let head = -1;
    for (let k = 0; k < N; k++) if (T >= arcT(N, k)) head = arcEnd(k);
    for (const q of RING) {
      const k = Math.min(N - 1, Math.floor((q.a / TAU) * N)), a0 = (k / N) * TAU + gap, a1 = ((k + 1) / N) * TAU - gap;
      const inGap = q.a < a0 - 0.02 || q.a > a1 + 0.02;
      const lit = sealed || (T >= arcT(N, k) && q.a <= arcEnd(k) + 0.02);
      const da = Math.abs(((q.a - (T - seal - 1) * (TAU / 4.5)) % TAU + TAU + Math.PI) % TAU - Math.PI);
      const shine = sealed ? 0.16 * Math.exp(-((da / 0.4) ** 2)) * cl((T - seal - 1) / 0.6) : 0;
      if (lit) g.on(q.x, q.y, q.b * 0.86 + shine);
      else if (!inGap) g.on(q.x, q.y, 0.13);
    }
    // the head of the light, coral; it ends on the top when the ring closes
    const ha = sealed ? TAU : head;
    g.fr(RCX + Math.sin(ha) * (RR - 0.5), RCY - Math.cos(ha) * (RR - 0.5), head >= 0 || sealed ? 1 : 0, 1);
    if (sealed) g.disc(RCX, RCY, 2.6 * back(cl((T - seal) / 0.35), 2), 0.9);
    for (let r = 0; r < 2; r++) {
      const a = T - seal - 0.04 - r * 0.18, R = RR + 1.5 + a * 13;
      for (let k = 0; k < 48; k++) {
        const q = (k / 48) * TAU;
        g.fr(RCX + Math.sin(q) * R, RCY - Math.cos(q) * R, a > 0 && a < 0.7 ? (1 - a / 0.7) * 0.7 : 0);
      }
    }
    const tick = Array.from({length: N - 1}, (_, k) => fl(T - arcT(N, k) - 0.22, 0.08, 0.05)).reduce((a, b) => a + b, 0);
    return {o: {stagger: 0.3}, flash: tick + fl(T - seal, 0.15, 0.28), shake: sealed && T < seal + 0.14 ? 0.22 : 0};
  },
  hap: [...Array.from({length: 4}, (_, k) => ({t: arcT(5, k) + 0.22, kind: 'light' as const})), {t: SEAL(5), kind: 'heavy'}, {t: SEAL(5) + 0.07, kind: 'success'}],
};

// ---------------------------------------------------------------- Sun: HOURGLASS
const HG = 11, GX = CX + 0.5, GY = CY + 0.5; // the neck is the cell (22, 17)
const wo = (d: number) => 1 + Math.round((d * 7) / HG); // wall offset at distance d from the neck
const FRAME: [number, number][] = [];
for (let x = -9; x <= 9; x++) FRAME.push([x, -HG - 1], [x, HG + 1]);
for (let d = 0; d <= HG; d++) for (const sy of d ? [-1, 1] : [1]) for (const sx of [-1, 1]) FRAME.push([sx * wo(d), sy * d]);
// the sand: packed down to the neck in the top bulb, or piled from the floor of the bottom one
const rowCells = (d: number) => {
  const w = wo(d) - 1, o: number[] = [];
  for (let x = 0; x <= w; x++) o.push(x, ...(x ? [-x] : []));
  return o; // centre first
};
const TOPS: [number, number][] = [], BOTS: [number, number][] = [];
for (let d = 1; d <= 8; d++) for (const x of rowCells(d)) TOPS.push([x, -d]);
for (let d = HG; d >= 8; d--) for (const x of rowCells(d)) BOTS.push([x, d]);
const M = Math.min(TOPS.length, BOTS.length);
TOPS.length = M;
BOTS.length = M;
// leaving order: from the surface down; arriving order: from the floor up (both centre first)
const LEAVE = [...TOPS].sort((p, q) => p[1] - q[1] || Math.abs(p[0]) - Math.abs(q[0]));
// after the turn, the pile becomes the top bulb and slides down to the neck: nearest the neck goes lowest
const SETTLE = (() => {
  const rotd = BOTS.map(([x, y], i) => ({i, d: y, x: -x}));
  rotd.sort((p, q) => p.d - q.d || Math.abs(p.x) - Math.abs(q.x));
  const tops = [...TOPS].sort((p, q) => q[1] - p[1] || Math.abs(p[0]) - Math.abs(q[0]));
  const o: [number, number][] = new Array(M);
  rotd.forEach((r, k) => (o[r.i] = tops[k]));
  return o;
})();
const RUN0 = 0.45, RUN = 0.55, FALLT = 0.26, TURN0 = RUN0 + RUN + FALLT + 0.08, TURN = 0.5, NEWWK = TURN0 + TURN;

const hourglass: MScn = {
  draw: (g, c) => {
    const T = c.T;
    const th = Math.PI * eio((T - TURN0) / TURN);
    const P = (x: number, y: number): [number, number] => {
      const dx = x - GX, dy = y - GY;
      return [GX + dx * Math.cos(th) - dy * Math.sin(th), GY + dx * Math.sin(th) + dy * Math.cos(th)];
    };
    const settled = T >= NEWWK;
    for (const [x, y] of FRAME) {
      const [a, b] = P(GX + x, GY + y);
      g.fr(a, b, Math.abs(y) === HG + 1 ? 0.85 : 0.55);
    }
    // the sand runs through: each grain leaves the surface, drops through the neck, lands on the pile
    for (let i = 0; i < M; i++) {
      const s = RUN0 + (i / M) * RUN, u = (T - s) / FALLT;
      const [bx, by] = BOTS[i];
      let x: number, y: number;
      if (settled) [x, y] = [GX + SETTLE[i][0], GY + SETTLE[i][1]];
      else if (u < 0) {
        const [tx, ty] = LEAVE[i];
        [x, y] = [GX + tx, GY + ty];
      } else if (u < 1) [x, y] = [GX, GY + lerp(-0.6, by - 0.4, u * u)];
      else [x, y] = [GX + bx, GY + by];
      const [a, b] = settled ? [x, y] : P(x, y);
      g.fr(a, b, 0.86);
    }
    // a new week: one grain at a time starts to fall again; the neck is now
    const tq = ((T - NEWWK - 0.8) / 1.8) % 1, on = T > NEWWK + 0.8;
    g.fr(GX, GY + 0.6 + (tq * tq) * (HG - 0.6), on ? 0.5 * cl(tq * 8) * cl((1 - tq) * 6) : 0);
    g.fr(GX, GY, settled ? 1 : 0, 1);
    return {o: {stagger: 0.3}, flash: fl(T - NEWWK, 0.16, 0.26), shake: T > NEWWK && T < NEWWK + 0.14 ? 0.2 : 0};
  },
  hap: [{t: RUN0, kind: 'light'}, {t: TURN0, kind: 'medium'}, {t: NEWWK, kind: 'heavy'}, {t: NEWWK + 0.07, kind: 'success'}],
};

export const SCENES: MScn[] = [sunrise, wall, battery, barbell, plusOne, ring, hourglass];
void G;
