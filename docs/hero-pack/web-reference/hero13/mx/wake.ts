/**
 * Matrix Dynamic: wake. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * The alarm rings six times fast (0.35 s to 2.85 s, every 0.5 s), then once every 2.5 s. Every ring is
 * one bold beat that starts on the ring's own frame (haptic on the same time); between rings the board
 * is still. Anything that moves is a free particle, pushed in the same order and count every frame.
 */
import {G, MHap, MScn, cl, ez} from '../mxlib';
import {ringHap} from './common';

// ---------- the alarm's clock (own copy: mxlib's lastRing jumps back between 2.6 s and 2.85 s) ----------
const ringT = (k: number) => (k < 6 ? 0.35 + k * 0.5 : 2.85 + (k - 5) * 2.5);
const ringK = (T: number) => (T < 0.35 ? -1 : T < 2.85 ? Math.floor((T - 0.35) / 0.5 + 1e-6) : 5 + Math.floor((T - 2.85) / 2.5 + 1e-6));
const ringAge = (T: number) => {
  const k = ringK(T);
  return k < 0 ? 99 : T - ringT(k);
};
/** a sharp hit on every ring */
const hit = (T: number, w = 0.12) => Math.exp(-ringAge(T) / w);
/** age of the latest ring with this parity: effects that alternate between two particle slots */
const slotAge = (T: number, s: number) => {
  let k = ringK(T);
  if (k >= 0 && k % 2 !== s) k--;
  return k < 0 ? 99 : T - ringT(k);
};
/** ringHap covers the first five rings; the sixth and the slow rings get theirs too */
const HAP: MHap = [...ringHap, {t: 2.85, kind: 'medium'}, ...Array.from({length: 24}, (_, i) => ({t: 5.35 + i * 2.5, kind: 'heavy' as const}))];

// ---------- small helpers ----------
type Pt = [number, number, number];
/** '#' lit, 'o' coral, '+' dim */
const bmp = (rows: string[]): Pt[] => {
  const o: Pt[] = [];
  rows.forEach((r, j) => [...r].forEach((ch, i) => {
    const k = '#o+'.indexOf(ch);
    if (k >= 0) o.push([i, j, k]);
  }));
  return o;
};
const rotP = (x: number, y: number, px: number, py: number, a: number): [number, number] => {
  const c = Math.cos(a), s = Math.sin(a), dx = x - px, dy = y - py;
  return [px + dx * c - dy * s, py + dx * s + dy * c];
};

// ---------- Mon: the bell ----------
const BELL = bmp([
  '........#........',
  '......#####......',
  '.....##...##.....',
  '....#.......#....',
  '....#.......#....',
  '....#.......#....',
  '...#.........#...',
  '...#.........#...',
  '...#.........#...',
  '..#...........#..',
  '..#...........#..',
  '.#.............#.',
  '#...............#',
  '#################',
  '#################',
]);
/** the bell's tilt: a 1 Hz pendulum through the fast rings (fully over on every ring), then one swing per slow ring */
const bellSwing = (T: number) => {
  const A = 0.2;
  if (T < 0.1) return 0;
  if (T < 0.35) return A * Math.sin((Math.PI / 2) * ((T - 0.1) / 0.25));
  if (T < 2.85) return A * Math.cos((Math.PI * (T - 0.35)) / 0.5);
  const k = ringK(T), R = ringT(k), s = k % 2 ? -1 : 1;
  let th = s * A * Math.cos(2 * Math.PI * (T - R)) * Math.exp(-(T - R) / 0.45);
  const nx = ringT(k + 1);
  if (T > nx - 0.25) th += -s * A * Math.sin((Math.PI / 2) * ((T - (nx - 0.25)) / 0.25));
  return th;
};

// ---------- Tue: the clock digits ----------
const F35: Record<string, string[]> = {
  '6': ['###', '#..', '###', '#.#', '###'],
  '3': ['###', '..#', '###', '..#', '###'],
  '0': ['###', '#.#', '#.#', '#.#', '###'],
  ':': ['.', '#', '.', '#', '.'],
};

// ---------- Fri: the phone ----------
const PHONE: Pt[] = (() => {
  const o: Pt[] = [];
  const x0 = 16, x1 = 28, y0 = 5, y1 = 29;
  for (let x = x0 + 1; x < x1; x++) o.push([x, y0, 0], [x, y1, 0]);
  for (let y = y0 + 1; y < y1; y++) o.push([x0, y, 0], [x1, y, 0]);
  for (let x = 20; x <= 23; x++) o.push([x, 7, 2]);
  o.push([24, 7, 1]);
  for (let x = 20; x <= 24; x++) o.push([x, 27, 2]);
  return o;
})();
const CHEV = [[0, -3], [1, -2], [2, -1], [3, 0], [2, 1], [1, 2], [0, 3]];

// ---------- Sat: the alarm clock ----------
const CLK = {cx: 22.5, cy: 19.5, r: 8.5};

// ---------- Sun: the night sky, in six even rows (cleared one row per ring, from the horizon up) ----------
const SKY: [number, number, number][] = (() => {
  const o: [number, number, number][] = [];
  for (let j = 0; j < 6; j++) {
    const y = 22 - j * 3;
    for (let x = 10 + (j % 2) * 2; x <= 35; x += 4) {
      if (Math.abs(x + 0.5 - 22.5) < 8 && y > 11) continue; // the sun's place
      o.push([x + 0.5, y + 0.5, j]);
    }
  }
  return o;
})();
const SUN: [number, number][] = (() => {
  const o: [number, number][] = [];
  for (let dy = -5; dy <= 5; dy++) for (let dx = -5; dx <= 5; dx++) if (dx * dx + dy * dy <= 30.5) o.push([dx, dy]);
  return o;
})();

export const SCENES: MScn[] = [
  // Mon: THE BELL. It swings over on every ring; the clapper strikes and sound arcs radiate out both sides
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T), th = bellSwing(T);
      const px = 22.5, py = 8.5;
      for (const [x, y] of BELL) {
        const [X, Y] = rotP(14.5 + x, 9.5 + y, px, py, th);
        g.fr(X, Y, 0.82 + 0.18 * h);
      }
      const [kx, ky] = rotP(px, py + 17, px, py, th * 0.35);
      g.fr(kx, ky, 1, 1);
      // two slots of arcs, so a new ring never takes the dots of one still in flight
      for (let s = 0; s < 2; s++) {
        const a = slotAge(T, s), live = a < 0.65;
        for (let w = 0; w < 2; w++) {
          const r = live ? 11.5 - w * 2.2 + 4 * ez(a / 0.55) : 11.5 - w * 2.2, b = live ? Math.pow(1 - a / 0.65, 1.3) * (w ? 0.6 : 1) : 0;
          for (const side of [-1, 1])
            for (let i = 0; i < 9; i++) {
              const ang = side * (Math.PI / 2 + (i / 8 - 0.5) * (w ? 0.75 : 0.95));
              g.fr(22.5 + Math.sin(ang) * r, 17.5 - Math.cos(ang) * r, b);
            }
        }
      }
      return {flash: 0.1 * h, shake: 0.16 * h, o: {stagger: 0.12}};
    },
    hap: HAP,
  },
  // Tue: 6:30 IN TILES. The clock digits stomp down on every ring, a ripple from left to right
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T), x0 = 10, y0 = 12, yb = y0 + 10;
      let x = x0;
      [...'6:30'].forEach((ch, j) => {
        const rows = F35[ch], w = rows[0].length * 2, xc = x + w / 2;
        const a = ringAge(T) - 0.03 * j, s = a >= 0 ? 0.38 * Math.exp(-a / 0.13) : 0;
        // after each slow ring a soft light passes across the digits
        const sa = ringK(T) >= 5 ? ringAge(T) - 0.7 : -9, sx = 8 + sa * 26;
        rows.forEach((r, py) => [...r].forEach((p, px) => {
          if (p !== '#') return;
          for (let v = 0; v < 2; v++)
            for (let u = 0; u < 2; u++) {
              const X = x + px * 2 + u + 0.5, Y = y0 + py * 2 + v + 0.5;
              const sw = Math.exp(-(((X - sx) / 2.5) ** 2));
              g.fr(xc + (X - xc) * (1 + 0.35 * s), yb - (yb - Y) * (1 - s), 0.8 + 0.2 * Math.max(h, sw));
            }
        }));
        x += w + 2;
      });
      // the alarm's days, today in coral
      for (let i = 0; i < 7; i++) g.on(16 + i * 2, 26, i === 1 ? 1 : 0.3, i === 1 ? 1 : 0);
      return {flash: 0.1 * h, shake: 0.22 * h, o: {stagger: 0.12}};
    },
    hap: HAP,
  },
  // Wed: THE BEEP. A scope: every ring throws a burst on the line, and it rings down flat
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T), k = ringK(T);
      const ys: number[] = [];
      for (let x = 9; x <= 36; x++) {
        const X = x + 0.5;
        let y = 0;
        for (const kk of [k, k - 1]) {
          if (kk < 0) continue;
          const a = T - ringT(kk), sg = kk % 2 ? -1 : 1;
          y += -sg * 7.5 * Math.exp(-a / 0.3) * Math.exp(-(((X - 22.5) / 6.5) ** 2)) * Math.cos((2 * Math.PI * (X - 22.5)) / 7);
        }
        ys.push(17.5 + y);
      }
      ys.forEach((y, i) => g.fr(9.5 + i, y, 0.72 + 0.28 * h, i === 13 ? 1 : 0));
      // fill the steep parts so the line stays a line
      for (let i = 0; i < ys.length - 1; i++) {
        const dy = ys[i + 1] - ys[i], b = cl((Math.abs(dy) - 1.2) / 1.5) * (0.72 + 0.28 * h);
        for (const f of [0.25, 0.5, 0.75]) g.fr(9.5 + i + f, ys[i] + dy * f, b);
      }
      // the screen's corners
      for (const [cx, cy, dx, dy] of [[8, 6, 1, 1], [37, 6, -1, 1], [8, 28, 1, -1], [37, 28, -1, -1]]) {
        g.on(cx, cy, 0.35);
        g.on(cx + dx, cy, 0.35);
        g.on(cx, cy + dy, 0.35);
      }
      return {flash: 0.1 * h, shake: 0.12 * h, o: {stagger: 0.12}};
    },
    hap: HAP,
  },
  // Thu: VOLUME UP. Each ring lights the next, taller bar; at full volume every ring pumps the whole meter
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T), k = ringK(T), base = 28.5;
      for (let i = 0; i < 6; i++) {
        const x = 11 + i * 4, n = 3 + i * 2;
        for (let s = 0; s < n; s++) {
          const top = i === 5 && s === n - 1;
          g.on(x, 28 - s * 2, top ? 0.6 : 0.22, top ? 1 : 0);
          g.on(x + 1, 28 - s * 2, top ? 0.6 : 0.22, top ? 1 : 0);
        }
      }
      for (let i = 0; i < 6; i++) {
        const x = 11 + i * 4, n = 3 + i * 2, lit = k >= i;
        const a = ringAge(T) - 0.025 * i, p = lit && k > i && a >= 0 ? 0.28 * Math.exp(-a / 0.1) : 0;
        for (let s = 0; s < n; s++) {
          const Y = 28 - s * 2 + 0.5, y = lit ? base - (base - Y) * (1 - p) : base;
          const top = i === 5 && s === n - 1;
          for (let u = 0; u < 2; u++) g.fr(x + u + 0.5, y, lit ? 0.92 + 0.08 * h : 0, top ? 1 : 0);
        }
      }
      return {flash: 0.1 * h, shake: 0.14 * h, o: {stagger: 0.12}};
    },
    hap: HAP,
  },
  // Fri: THE PHONE. It buzzes on every ring and fires chevrons out both sides
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T), k = ringK(T), side = k % 2 ? -1 : 1;
      const e = Math.exp(-ringAge(T) / 0.1), dx = side * 1.1 * e, th = side * 0.045 * Math.exp(-ringAge(T) / 0.13);
      for (const [x, y, kd] of PHONE) {
        const [X, Y] = rotP(x + 0.5 + dx, y + 0.5, 22.5 + dx, 17.5, th);
        g.fr(X, Y, kd === 2 ? 0.45 : 0.9 + 0.1 * h, kd === 1 ? 1 : 0);
      }
      for (let s = 0; s < 2; s++)
        for (const sd of [-1, 1])
          for (let q = 0; q < 2; q++) {
            const a = slotAge(T, s) - q * 0.08, live = a >= 0 && a < 0.5;
            const d = live ? 1.5 + q * 2 + 3.5 * ez(a / 0.45) : 1.5 + q * 2, b = live ? Math.pow(1 - a / 0.5, 1.2) * (q ? 0.6 : 1) : 0;
            const xb = sd > 0 ? 28.5 + d : 16.5 - d;
            for (const [u, v] of CHEV) g.fr(xb + sd * u, 17.5 + v, b);
          }
      return {flash: 0.06 * h, shake: 0.32 * h, o: {stagger: 0.12}};
    },
    hap: HAP,
  },
  // Sat: THE ALARM CLOCK. The hammer strikes one bell, then the other; the clock rocks on its legs
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T);
      const k2 = ringK(T + 0.05), a2 = k2 < 0 ? 99 : T + 0.05 - ringT(k2), sd = k2 % 2 ? -1 : 1;
      const strike = a2 < 0.05 ? a2 / 0.05 : Math.exp(-(a2 - 0.05) / 0.14);
      const tilt = sd * 0.05 * Math.exp(-ringAge(T) / 0.16) * (ringAge(T) < 50 ? 1 : 0);
      const {cx, cy, r} = CLK, P = (x: number, y: number) => rotP(x, y, cx, 28.5, tilt);
      const F = (x: number, y: number, b: number, cc = 0) => {
        const [X, Y] = P(x, y);
        g.fr(X, Y, b, cc);
      };
      for (let i = 0; i < 56; i++) {
        const a = (i / 56) * Math.PI * 2;
        F(cx + Math.sin(a) * r, cy - Math.cos(a) * r, 0.9);
      }
      for (let i = 0; i < 12; i++) {
        const a = (i / 12) * Math.PI * 2;
        F(cx + Math.sin(a) * 6.4, cy - Math.cos(a) * 6.4, i % 3 ? 0.35 : 0.85);
      }
      const hand = (ang: number, len: number) => {
        for (let q = 1; q <= len; q++) F(cx + Math.sin(ang) * q, cy - Math.cos(ang) * q, 1);
      };
      hand(Math.PI, 5.5);
      hand((6.5 / 12) * Math.PI * 2, 3.5);
      F(cx, cy, 1);
      // the bells: two domes, the struck one rings
      for (const s of [-1, 1]) {
        const phi = s * 0.78, bx = cx + Math.sin(phi) * 10.6, by = cy - Math.cos(phi) * 10.6;
        const struck = strike > 0.3 && s === sd ? 1 : 0, push = s === sd ? 0.5 * h : 0;
        for (let u = -3; u <= 3; u++)
          for (let v = 0; v <= 3; v++) {
            if (u * u + v * v > 10) continue;
            const vv = v + push;
            F(bx + Math.cos(phi) * u + Math.sin(phi) * vv, by + Math.sin(phi) * u - Math.cos(phi) * vv, 0.7 + 0.3 * struck);
          }
      }
      // the hammer between the bells
      const ht = sd * 0.85 * strike * (a2 < 50 ? 1 : 0);
      for (let q = 0; q < 3; q++) {
        const [X, Y] = rotP(cx, cy - r - 0.8 - q, cx, cy - r + 0.2, ht);
        F(X, Y, 0.8);
      }
      const [hx, hy] = rotP(cx, cy - r - 3.9, cx, cy - r + 0.2, ht);
      F(hx, hy, 1, 1);
      // the legs
      for (const s of [-1, 1]) for (let q = 0; q < 3; q++) F(cx + s * (5.9 + q * 0.9), cy + 6.4 + q * 0.9, 0.8);
      return {flash: 0.1 * h, shake: 0.2 * h, o: {stagger: 0.12}};
    },
    hap: HAP,
  },
  // Sun: DAWN. Each ring clears one row of the night, from the horizon up, and lifts the sun a step
  {
    draw: (g: G, c) => {
      const T = c.T, h = hit(T), k = ringK(T);
      for (const [x, y, j] of SKY) {
        const a = j <= k ? T - ringT(j) : -1;
        const b = a < 0 ? 0.42 : a < 0.06 ? 1 : Math.max(0, 1 - (a - 0.06) / 0.45) ** 1.5;
        g.fr(x, y - (a < 0 ? 0 : 2 * ez(a / 0.6)), b);
      }
      const steps = Math.min(6, k + 1), yc = 31.5 - 2 * steps;
      for (const [dx, dy] of SUN) {
        const y = yc + dy;
        g.fr(22.5 + dx, y, y < 26 ? 0.9 : 0, dx === 0 && dy === -5 ? 1 : 0);
      }
      // once the sun is up, every ring sends a soft halo out of it
      const ha = k >= 6 ? ringAge(T) : 9, live = ha < 0.9;
      for (let i = 0; i < 26; i++) {
        const ang = -1.75 + (i / 25) * 3.5, rr = live ? 7 + 5 * ez(ha / 0.8) : 7;
        const y = 19.5 - Math.cos(ang) * rr;
        g.fr(22.5 + Math.sin(ang) * rr, y, live && y < 25.5 ? 0.55 * (1 - ha / 0.9) : 0);
      }
      g.line(8, 26, 37, 26, 0.3 + 0.45 * Math.min(1, steps / 6));
      return {flash: 0.08 * h, shake: 0.1 * h, o: {stagger: 0.15}};
    },
    hap: HAP,
  },
];
