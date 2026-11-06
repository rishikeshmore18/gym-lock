/**
 * Matrix Dynamic: atgym. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * A live 20-minute session, as seven different instruments. Each shows the track (all twenty
 * minutes, dim), the progress on it (one mark a minute), something small that moves with the
 * seconds, and a clear payoff at 20:00 (the app fires the haptics then; the done flow opens 1.3 s
 * later). None of them is the day's done object; each one points toward it.
 */
import {CX, CY, MC, MScn, back, cl, eio, ez, lerp} from '../mxlib';
import {PROOF, TAU, flare, hitAge} from './common';

/** the session: whole minutes done, how far into the current one, seconds since 20:00 (or -1) */
const live = (c: MC) => {
  const s = c.d.atgym, h = hitAge(c);
  return {m: Math.min(20, Math.floor(s / 60)), f: h >= 0 ? 1 : (s / 60) % 1, h, fl: h >= 0 ? 0 : flare(c)};
};
const fl = (a: number, d = 0.15, k = 0.3) => (a >= 0 ? Math.exp(-a / d) * k : 0);
/** a soft band of light crossing `pos` every P seconds */
const sweep = (t: number, P: number, pos: number, lo: number, hi: number, w = 2.5) => {
  const q = (((t / P) % 1) + 1) % 1 * (hi - lo + 6 * w) + lo - 3 * w;
  return Math.exp(-(((pos - q) / w) ** 2));
};
const ENTRY = [{t: 0.45, kind: 'light' as const}];

/** the Matrix support line at the gym, after "MM:SS " (Mon..Sun) */
export const MX_LIVE: {live: string; liveDone: string}[] = [
  {live: 'until the sun is up', liveDone: '20:00. Sun up. Verified.'},
  {live: 'until today’s block is laid', liveDone: '20:00. Block laid. Verified.'},
  {live: 'until today’s battery is full', liveDone: '20:00. Charged. Verified.'},
  {live: 'until the bar goes up', liveDone: '20:00. Lifted. Verified.'},
  {live: 'until your +1', liveDone: '20:00. Plus one. Verified.'},
  {live: 'until the ring closes', liveDone: '20:00. Ring closed. Verified.'},
  {live: 'until the week turns over', liveDone: '20:00. Week turned. Verified.'},
];

// ---------------------------------------------------------------- Mon: SUNBURST DIAL
// twenty rays round a small core, one a minute; the current ray grows with the seconds; at 20:00
// every ray throws out at once. A sun gathering itself, before it rises.
const MC0 = CX + 0.5, MC1 = CY + 0.5, RIN = 6, ROUT = 13;
const rayCells = (i: number, r1: number) => {
  const a = (i / 20) * TAU, o: {x: number; y: number; r: number}[] = [], seen = new Set<number>();
  for (let r = RIN; r <= r1 + 0.01; r += 0.5) {
    const x = Math.floor(MC0 + Math.sin(a) * r), y = Math.floor(MC1 - Math.cos(a) * r);
    if (!seen.has(y * 256 + x)) seen.add(y * 256 + x), o.push({x, y, r});
  }
  return o;
};
const RAYS = Array.from({length: 20}, (_, i) => rayCells(i, ROUT + 2.4));

const sunDial: MScn = {
  draw: (g, c) => {
    const {m, f, h, fl: mf} = live(c), hit = h >= 0;
    const ext = hit ? ROUT + 2.4 * back(cl((h - 0.05) / 0.4), 2) : ROUT;
    g.disc(MC0, MC1, hit ? 2.6 + 0.8 * back(cl(h / 0.3), 2) : 2.6, hit ? 1 : 0.8 + 0.12 * Math.sin(c.t * 1.6));
    if (hit) g.on(CX, CY, 1, 1);
    RAYS.forEach((cells, i) => {
      for (const q of cells) {
        if (q.r > ext + 0.01) continue;
        let b = 0.12;
        if (hit) b = q.r <= ROUT ? 0.9 : 0.75;
        else if (i < m) b = 0.82 + (i === m - 1 ? 0.18 * mf : 0);
        else if (i === m && q.r <= RIN + f * (ROUT - RIN)) b = 0.92;
        if (q.r > ROUT && !hit) continue;
        g.on(q.x, q.y, b * (hit ? 1 : 1 - (q.r - RIN) * 0.012));
      }
    });
    // the tip of the growing ray: now
    const a = (m / 20) * TAU, rt = RIN + f * (ROUT - RIN);
    g.fr(MC0 + Math.sin(a) * rt, MC1 - Math.cos(a) * rt, hit ? 0 : 1, 1);
    // at 20:00 a ring of light goes out
    for (let k = 0; k < 40; k++) {
      const q = (k / 40) * TAU, R = 14 + h * 14;
      g.fr(MC0 + Math.sin(q) * R, MC1 - Math.cos(q) * R, hit && h < 0.7 ? (1 - h / 0.7) * 0.8 : 0);
    }
    return {o: {stagger: 0.45}, flash: hit ? fl(h, 0.2, 0.3) : mf * 0.05, shake: hit && h < 0.16 ? 0.3 : 0};
  },
  hap: ENTRY,
};

// ---------------------------------------------------------------- Tue: TILE BOARD
// twenty tiles, one a minute; the current tile fills cell by cell and flips over when its minute
// is done; at 20:00 the whole board flips in a wave.
const tileXY = (k: number) => [10 + (k % 5) * 5, 8 + Math.floor(k / 5) * 5];
const FILL = Array.from({length: 16}, (_, n) => [n % 4, 3 - Math.floor(n / 4)]); // bottom row first

const tiles: MScn = {
  draw: (g, c) => {
    const {m, f, h, fl: mf} = live(c), hit = h >= 0, s = c.d.atgym;
    const lit = Math.floor(f * 16);
    for (let k = 0; k < 20; k++) {
      const [x0, y0] = tileXY(k), i = k % 5, j = Math.floor(k / 5);
      // flip: once when the tile's minute ends, and once more in the 20:00 wave
      const u = hit ? cl((h - 0.08 - (i + j) * 0.07) / 0.4) : k < m ? cl((s - 60 * (k + 1)) / 0.45) : 1;
      const sx = Math.max(0.08, Math.abs(Math.cos(Math.PI * u)));
      for (let n = 0; n < 16; n++) {
        const [cu, cv] = FILL[n];
        let b = 0.09, cc = 0;
        if (hit) b = u >= 1 ? 0.86 : 0.9, cc = k === 19 && (cu === 1 || cu === 2) && (cv === 1 || cv === 2) && u >= 1 ? 1 : 0;
        else if (k < m) b = 0.8 + (k === m - 1 ? 0.15 * mf : 0);
        else if (k === m) b = n < lit ? 0.92 : n === lit ? 0.14 + 0.7 * (f * 16 - lit) : 0.14, cc = n === lit - 1 ? 1 : 0;
        g.fr(x0 + 2 + (cu - 1.5) * sx, y0 + cv + 0.5, b * (0.3 + 0.7 * sx), cc);
      }
    }
    return {o: {stagger: 0.4}, flash: hit ? fl(h, 0.2, 0.3) : mf * 0.05, shake: hit && h < 0.14 ? 0.25 : 0};
  },
  hap: ENTRY,
};

// ---------------------------------------------------------------- Wed: HEART MONITOR
// the live heartbeat, written by a sweeping head, and twenty minute dots in groups of five. At
// 20:00 the line lights end to end and the last dot fills: charged.
const ECG: [number, number][] = [[0, 0], [2, 0], [3, -1], [4, 0], [5, 1], [6, -8], [7, 3], [8, 0], [9, -2], [10, 0]];
const YB = 14, X0 = 8, X1 = 37, SPAN = X1 - X0;
const ecgY = (x: number) => {
  const u = (((x - X0 - 1) % 10) + 10) % 10;
  for (let k = 1; k < ECG.length; k++) if (u <= ECG[k][0]) return YB + lerp(ECG[k - 1][1], ECG[k][1], (u - ECG[k - 1][0]) / (ECG[k][0] - ECG[k - 1][0]));
  return YB;
};
const TRACE: {x: number; y: number}[] = (() => {
  const m = new Map<number, {x: number; y: number}>();
  for (let x = X0; x <= X1; x += 0.125) {
    const cx = Math.floor(x), cy = Math.floor(ecgY(x) + 0.5);
    m.set(cy * 256 + cx, {x: cx, y: cy});
  }
  return [...m.values()];
})();

const monitor: MScn = {
  draw: (g, c) => {
    const {m, f, h, fl: mf} = live(c), hit = h >= 0;
    const xh = X0 + ((c.t * 12.5) % SPAN);
    for (const q of TRACE) {
      const d = (xh - q.x - 0.5 + SPAN) % SPAN;
      let b = d > SPAN - 2.5 ? 0 : 0.16 + 0.84 * Math.exp(-d / 7);
      if (hit) b = Math.max(b, 1 - cl(h / 1.4) * 0.6);
      if (b > 0.01) g.on(q.x, q.y, b);
    }
    const edge = cl((xh - X0) / 1.2) * cl((X1 - xh) / 1.2);
    g.fr(xh + 0.5, ecgY(xh) + 0.5, edge, 1);
    for (let i = 0; i < 20; i++) {
      const x = 10 + Math.floor(i / 5) * 6 + (i % 5);
      let b = i < m ? 0.85 + (i === m - 1 ? 0.15 * mf : 0) : i === m ? 0.24 + 0.5 * f : 0.13;
      if (hit) b = 0.88 + 0.12 * Math.exp(-Math.max(0, h - i * 0.025) / 0.2) * (h > i * 0.025 ? 1 : 0);
      g.on(x, 26, b);
      g.on(x, 27, b * 0.55);
    }
    return {o: {stagger: 0.35}, flash: hit ? fl(h, 0.2, 0.3) : mf * 0.05, shake: hit && h < 0.14 ? 0.25 : 0};
  },
  hap: ENTRY,
};

// ---------------------------------------------------------------- Thu: LEVEL WEDGE
// twenty columns, one a minute, each a little taller: the level rising. The current column climbs
// with the seconds; at 20:00 a light runs up the wedge and a peak mark lands on top.
const colX = (i: number) => 10 + i + Math.floor(i / 5);
const colH = (i: number) => Math.round(5 + (i * 17) / 19);
const BASE = 28;

const wedge: MScn = {
  draw: (g, c) => {
    const {m, f, h, fl: mf} = live(c), hit = h >= 0;
    for (let i = 0; i < 20; i++) {
      const H = colH(i), x = colX(i), lvl = i < m || hit ? H : i === m ? f * H : 0;
      const wave = hit ? Math.exp(-Math.max(0, h - i * 0.03) / 0.18) * (h > i * 0.03 ? 1 : 0) : 0;
      const sw = hit ? 0 : 0.1 * sweep(c.t, 4.5, x, 8, 34);
      for (let j = 0; j < H; j++) {
        const fill = cl(lvl - j);
        const on = (i < m ? 0.8 + (i === m - 1 ? 0.18 * mf : 0) + sw : hit ? 0.88 + 0.12 * wave : 0.88) * (j === H - 1 ? 1.08 : 1);
        g.on(x, BASE - j, fill > 0 ? Math.max(0.09, fill * on) : 0.09);
      }
    }
    // now: the top of the rising column; at 20:00 it flies up to sit on the peak
    const cx = colX(Math.min(19, m)), cy = BASE - (m < 20 ? f * colH(m) : 0);
    const py = BASE - colH(19) - 1;
    const tx = hit ? lerp(cx, colX(19), ez(h / 0.45)) : cx, ty = hit ? lerp(BASE - colH(19), py, ez(h / 0.45)) : cy;
    g.fr(tx + 0.5, ty + (hit ? 0.5 : 0), 1, 1);
    return {o: {stagger: 0.35}, flash: hit ? fl(h, 0.2, 0.3) : mf * 0.05, shake: hit && h < 0.14 ? 0.22 : 0};
  },
  hap: ENTRY,
};

// ---------------------------------------------------------------- Fri: THE ARROW
// a big up arrow: twenty rows of shaft, one a minute, lit from the bottom; a pulse of light runs up
// what you've done. At 20:00 the head lights and the arrow pushes up.
const SHAFT: [number, number][] = [], HEAD: [number, number][] = [];
for (let k = 0; k < 20; k++) for (const d of [0, -1, 1, -2, 2]) SHAFT.push([CX + d, 31 - k]);
for (let r = 7; r >= 0; r--) for (let x = -r; x <= r; x++) HEAD.push([CX + x, 4 + r]);

const arrow: MScn = {
  draw: (g, c) => {
    const {m, f, h, fl: mf} = live(c), hit = h >= 0;
    const push = hit ? -2.2 * Math.sin(Math.PI * cl((h - 0.32) / 0.42)) : 0;
    const band = 31 - ((c.t * 7) % 30);
    const done = Math.floor(f * 5);
    SHAFT.forEach(([x, y], n) => {
      const k = Math.floor(n / 5), d = n % 5;
      let b = 0.1, cc = 0;
      if (hit || k < m) b = 0.84 + (k === m - 1 ? 0.16 * mf : 0) + (hit ? 0 : 0.14 * Math.exp(-(((y - band) / 1.6) ** 2)) * (31 - band < m ? 1 : 0));
      else if (k === m) b = d < done ? 0.92 : d === done ? 0.12 + 0.6 * (f * 5 - done) : 0.12, cc = d === done - 1 ? 1 : 0;
      g.fr(x + 0.5, y + 0.5 + push, b, cc);
    });
    HEAD.forEach(([x, y]) => {
      const r = y - 4, on = hit && h > (7 - r) * 0.04;
      g.fr(x + 0.5, y + 0.5 + push, on ? 0.95 : 0.1, hit && r === 0 && h > 0.32 ? 1 : 0);
    });
    return {o: {stagger: 0.35}, flash: hit ? fl(h - 0.3, 0.18, 0.3) + fl(h, 0.1, 0.1) : mf * 0.05, shake: hit && h > 0.3 && h < 0.46 ? 0.3 : 0};
  },
  hap: ENTRY,
};

// ---------------------------------------------------------------- Sat: STOPWATCH
// a stopwatch on a twenty-minute dial: the long hand sweeps the seconds, the short hand walks the
// minutes to the top. At 20:00 both stand at the top and the crown clicks: stopped.
const SC0 = CX + 0.5, SC1 = CY + 1.5, SR = 11;
const RIM: {x: number; y: number}[] = (() => {
  const mm = new Map<number, {x: number; y: number}>();
  for (let i = 0; i < 160; i++) {
    const a = (i / 160) * TAU, x = Math.floor(SC0 + Math.sin(a) * SR), y = Math.floor(SC1 - Math.cos(a) * SR);
    mm.set(y * 256 + x, {x, y});
  }
  return [...mm.values()];
})();

const stopwatch: MScn = {
  draw: (g, c) => {
    const {h, fl: mf} = live(c), hit = h >= 0, s = Math.min(c.d.atgym, PROOF);
    const rimB = hit ? 0.62 + 0.38 * Math.exp(-h / 0.5) : 0.6;
    for (const q of RIM) g.on(q.x, q.y, rimB);
    for (let i = 0; i < 20; i++) {
      const a = (i / 20) * TAU, major = i % 5 === 0;
      const b = hit ? 0.55 + 0.4 * Math.exp(-h / 0.6) : major ? (i === 0 ? 0.8 : 0.55) : 0.26;
      g.on(SC0 + Math.sin(a) * 9.3, SC1 - Math.cos(a) * 9.3, b);
      if (major) g.on(SC0 + Math.sin(a) * 8.2, SC1 - Math.cos(a) * 8.2, b * 0.8);
    }
    g.line(CX + 8, CY - 7, CX + 9, CY - 8, 0.6); // the lap button
    // the crown: it clicks down at 20:00
    const press = hit ? Math.sin(Math.PI * cl(h / 0.28)) : 0;
    for (let u = -1; u <= 1; u++) for (let v = 0; v < 2; v++) g.fr(CX + u + 0.5, 4.5 + v + press, 0.85);
    g.fr(CX + 0.5, 6.5 + press * 0.5, 0.7);
    // hands: minutes (short, two dots wide) and seconds (long, thin, tipped in coral)
    const am = (s / PROOF) * TAU, as = hit ? 0 : ((s % 60) / 60) * TAU;
    for (let k = 0; k < 8; k++)
      for (const o of [-0.45, 0.45]) {
        const r = 0.6 + k * 0.75;
        g.fr(SC0 + Math.sin(am) * r + Math.cos(am) * o, SC1 - Math.cos(am) * r + Math.sin(am) * o, 0.95);
      }
    for (let k = 0; k < 11; k++) {
      const r = 0.8 + k * 0.8;
      g.fr(SC0 + Math.sin(as) * r, SC1 - Math.cos(as) * r, k === 10 ? 1 : 0.55, k === 10 ? 1 : 0);
    }
    g.on(CX, CY + 1, 1);
    return {o: {stagger: 0.4}, flash: hit ? fl(h, 0.2, 0.3) : mf * 0.04, shake: hit && h < 0.14 ? 0.2 : 0};
  },
  hap: ENTRY,
};

// ---------------------------------------------------------------- Sun: THE WEEK, ZOOMED IN
// the week on top, today's square outlined; under it, today drawn large: twenty minutes on a ruler
// with a playhead. At 20:00 the minutes fly up into today's square and fill it.
const PAST: Record<string, number[]> = {first: [], middle: [0, 2], last: [0, 1, 2, 3]};
const RX = 12, RY = 22;

const weekZoom: MScn = {
  draw: (g, c) => {
    const {m, f, h, fl: mf} = live(c), hit = h >= 0;
    const past = PAST[c.pos] ?? PAST.middle, land = 0.62, full = hit && h > land;
    for (let d = 0; d < 7; d++) {
      const x = 9 + d * 4;
      if (d === 6) g.rect(x, 5, 3, 3, full ? 1 : 0.9, full);
      else if (past.includes(d)) g.rect(x, 5, 3, 3, 0.7, true);
      else g.rect(x, 5, 3, 3, 0.22);
    }
    if (full) g.on(34, 6, 1, 1);
    // the zoom: today, drawn large below
    g.line(33, 9, RX, RY - 3, 0.3, 0, 1);
    g.line(35, 9, RX + 19, RY - 3, 0.3, 0, 1);
    for (let k = 0; k < 20; k++) {
      g.on(RX + k, RY + 2, k % 5 === 0 || k === 19 ? 0.5 : 0.2);
      if (k % 5 === 0 || k === 19) g.on(RX + k, RY + 3, 0.5);
      g.on(RX + k, RY, 0.12);
    }
    // the minutes: lit cells on the ruler; at 20:00 they fly up into today's square
    for (let k = 0; k < 20; k++)
      for (const v of [0, 1]) {
        const n = k * 2 + v, b = hit || k < m ? 0.86 + (k === m - 1 ? 0.14 * mf : 0) : k === m ? (v ? 0.2 + 0.6 * f : 0.12 + 0.5 * f) : 0;
        let x = RX + k + 0.5, y = RY - v + 0.5;
        if (hit) {
          const u = eio((h - 0.04 - (19 - k) * 0.012) / 0.45), sq = n % 9;
          x = lerp(x, 33 + (sq % 3) + 0.5, u);
          y = lerp(y, 5 + Math.floor(sq / 3) + 0.5, u);
        }
        g.fr(x, y, b);
      }
    // the playhead: now
    const px = RX + Math.min(20, m + f);
    for (let v = 0; v < 4; v++) g.fr(px, RY - 2.5 + v, hit ? 0 : v ? 0.55 : 1, v ? 0 : 1);
    return {o: {stagger: 0.4}, flash: hit ? fl(h, 0.1, 0.12) + fl(h - land, 0.18, 0.3) : mf * 0.05, shake: hit && h > land && h < land + 0.14 ? 0.22 : 0};
  },
  hap: ENTRY,
};

export const SCENES: MScn[] = [sunDial, tiles, monitor, wedge, arrow, stopwatch, weekZoom];
void eio;
