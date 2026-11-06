/**
 * Matrix Dynamic: rest. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * A planned rest day: nothing to unlock. Every scene settles: one soft beat as the card arrives (a ring
 * fills, a shackle springs open, a busy line calms), then a slow, quiet idle. Coral is you, at rest.
 */
import {G, MC, MScn, cl, eio, ez, lerp, spr} from '../mxlib';
import {TAU} from './common';

const P = (cx: number, cy: number, r: number, a: number): [number, number] => [cx + Math.sin(a) * r, cy - Math.cos(a) * r];
const seg = (g: G, x0: number, y0: number, x1: number, y1: number, b: number) => {
  const n = Math.max(1, Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) * 1.5));
  for (let i = 0; i <= n; i++) g.on(lerp(x0, x1, i / n), lerp(y0, y1, i / n), b);
};
/** a soft light passing along a path (u = 0..1): one pass of `dur` seconds every `per` seconds, from `start` */
const glow = (u: number, T: number, start: number, per: number, dur: number, w = 0.14) => {
  if (T < start) return 0;
  const p = ((((T - start) % per) / dur) * (1 + 2 * w)) - w;
  return Math.exp(-(((u - p) / w) ** 2));
};
const FONT3: Record<string, string[]> = {
  M: ['#.#', '###', '###', '#.#', '#.#'],
  T: ['###', '.#.', '.#.', '.#.', '.#.'],
  W: ['#.#', '#.#', '###', '###', '#.#'],
  F: ['###', '#..', '##.', '#..', '#..'],
  S: ['.##', '#..', '.#.', '..#', '##.'],
};
const letter = (g: G, ch: string, x: number, y: number, b: number) => FONT3[ch].forEach((row, j) => [...row].forEach((q, i) => q === '#' && g.on(x + i, y + j, b)));
const ICON_MOON = ['..####...', '.###.....', '###......', '###......', '###......', '###......', '.###.....', '..####...'];
/** the breath: in for 4 s, out for 6 s (0..1) */
const breath = (T: number) => {
  const k = ((T % 10) + 10) % 10;
  return k < 4 ? eio(k / 4) : 1 - eio((k - 4) / 6);
};
/** a stateless phase for a line whose speed eases from w0 to w1 between t0 and t0 + d */
const phaseOf = (T: number, w0: number, w1: number, t0: number, d: number) => {
  let ph = 0;
  const n = 24, h = T / n;
  for (let i = 0; i < n; i++) ph += lerp(w0, w1, eio(((i + 0.5) * h - t0) / d)) * h;
  return ph;
};

export const SCENES: MScn[] = [
  // Mon: THE RECOVERY RING. A recovery score fills round the ring to where your body is today, the cross
  // of recovery in the middle; a slow light keeps circling the filled part
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 17.5, R = 11.5, T = c.T, v = 0.78 * eio((T - 0.3) / 1.3), aH = v * TAU;
      g.ring(cx, cy, R, 0.16);
      g.ring(cx, cy, R - 1, 0.1);
      const n = Math.max(1, Math.round(aH * R * 1.3));
      for (let i = 0; i <= n; i++) {
        const a = (aH * i) / n, gl = glow(i / n, T, 1.8, 5, 2.4, 0.12);
        g.on(...P(cx, cy, R, a), 0.8 + 0.2 * gl);
        g.on(...P(cx, cy, R - 1, a), 0.45 + 0.35 * gl);
      }
      g.fr(...P(cx, cy, R - 0.5, aH), 1, 1);
      for (let i = -3; i <= 3; i++) for (let w = 0; w < 2; w++) {
        g.on(22 + w, 17 + i, 0.62);
        g.on(22 + i + (i > 0 ? 1 : 0), 17 + w, 0.62);
      }
    },
    hap: [{t: 1.5, kind: 'light'}],
  },
  // Tue: THE PLAN. The week in tiles: training days solid, rest days open. Today is an open tile, in the
  // plan, and the streak line runs straight through it
  {
    draw: (g, c) => {
      const T = c.T, rest = [false, true, false, false, false, true, false];
      'MTWTFSS'.split('').forEach((ch, i) => letter(g, ch, 9 + i * 4, 12, i === 1 ? 1 : 0.38));
      for (let i = 0; i < 7; i++) {
        const x = 9 + i * 4, y = 19, b = i === 1 ? 1 : rest[i] ? 0.34 : i === 0 ? 0.85 : 0.45;
        for (let j = 0; j < 3; j++)
          for (let k = 0; k < 3; k++) {
            if (rest[i] && j === 1 && k === 1) continue;
            g.on(x + k, y + j, b * (rest[i] || j === 1 || k === 1 ? 1 : 0.75));
          }
      }
      const draw = ez((T - 0.35) / 0.9);
      for (let x = 9; x <= 35; x++) {
        const u = (x - 9) / 26;
        if (u > draw) continue;
        g.on(x, 25, (x <= 15 ? 0.8 : 0.32) + 0.3 * glow(u, T, 1.6, 4.6, 2.2, 0.1), x === 14 ? 1 : 0);
      }
    },
  },
  // Wed: STILL. A busy signal settles into a long, low, slow line; you float on it, and nothing pulls
  {
    draw: (g, c) => {
      const T = c.T, e = eio((T - 0.25) / 1.5);
      const A = lerp(4.6, 0.75, e), k = lerp(0.95, 0.26, e), ph = phaseOf(T, 3.2, 0.42, 0.25, 1.5);
      for (let i = 0; i <= 54; i++) {
        const x = 9 + i / 2, env = cl((x - 8.5) / 4) * cl((36.5 - x) / 4);
        const y = 17.5 + env * A * Math.sin(k * (x - 22.5) - ph);
        g.fr(x, y, 0.3 + 0.6 * env, i === 27 ? 1 : 0);
      }
    },
  },
  // Thu: BREATHE. One level, slowly rising and falling: in for four, out for six. Follow it
  {
    draw: (g, c) => {
      const T = c.T, f = 0.06 + 0.86 * breath(Math.max(0, T - 0.4)), yl = lerp(29.5, 6.5, f);
      for (let y = 6; y <= 29; y++) g.on(18, y, 0.32), g.on(26, y, 0.32);
      for (let x = 19; x <= 25; x++) g.on(x, 5, 0.32), g.on(x, 30, 0.32);
      for (const h of [0.25, 0.5, 0.75]) {
        const y = Math.round(lerp(29.5, 6.5, 0.06 + 0.86 * h) - 0.5);
        g.on(28, y, 0.32);
        g.on(29, y, 0.32);
      }
      for (let y = 7; y <= 29; y++) if (y + 0.5 > yl + 0.6) for (let x = 20; x <= 24; x++) g.on(x, y, 0.58);
      for (let i = -2; i <= 2; i++) g.fr(22.5 + i, yl, i === 0 ? 1 : 0.95, i === 0 ? 1 : 0);
    },
  },
  // Fri: THE LANDING. The plan climbs, levels out for today, then climbs again. You arrive on the landing
  // and stop there; the path ahead is lit, waiting for tomorrow
  {
    draw: (g, c) => {
      const T = c.T;
      seg(g, 9.5, 29.5, 16.5, 20.5, 0.72);
      seg(g, 16.5, 20.5, 28.5, 20.5, 0.95);
      seg(g, 16.5, 21.5, 28.5, 21.5, 0.4);
      const n = 12;
      for (let i = 0; i <= n; i++) {
        const u = i / n;
        g.on(lerp(28.5, 35.5, u), lerp(20.5, 11.5, u), 0.3 + 0.45 * glow(u, T, 1.8, 5, 2, 0.16));
      }
      seg(g, 35.5, 11.5, 32.5, 11.5, 0.5);
      seg(g, 35.5, 11.5, 35.5, 14.5, 0.5);
      // you: along the climb, then onto the landing
      const k = eio((T - 0.25) / 1.15), L1 = Math.hypot(7, 9), L2 = 6, d = k * (L1 + L2);
      const [x, y] = d < L1 ? [lerp(9.5, 16.5, d / L1), lerp(29.5, 20.5, d / L1)] : [16.5 + (d - L1), 20.5];
      for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) g.fr(x + i, y - 2 + j, 1, 1);
    },
    hap: [{t: 1.4, kind: 'light'}],
  },
  // Sat: NOTHING TO UNLOCK. The padlock springs open and stays open; a slow light runs round the shackle
  {
    draw: (g, c) => {
      const T = c.T, dy = -3.6 * (T < 0.55 ? 0 : spr(T - 0.55, 12, 6));
      for (let y = 18; y <= 27; y++)
        for (let x = 16; x <= 28; x++) {
          if ((x === 16 || x === 28) && (y === 18 || y === 27)) continue;
          if (x === 22 && (y === 22 || y === 23)) continue;
          g.on(x, y, x === 22 && y === 21 ? 1 : 0.74, x === 22 && y === 21 ? 1 : 0);
        }
      const cx = 22.5, ay = 13.5 + dy, path: [number, number][] = [];
      for (let k = 0; k < 5; k++) path.push([26.5, lerp(17.5, ay, k / 4)]);
      for (let k = 1; k < 14; k++) path.push(P(cx, ay, 4, Math.PI / 2 - (Math.PI * k) / 14));
      for (let k = 0; k < 5; k++) path.push([18.5, ay + k]);
      path.forEach(([x, y], i) => {
        const hide = i >= path.length - 5 && y > 17.6;
        g.fr(x, y, hide ? 0 : 0.88 + 0.12 * glow(i / (path.length - 1), T, 1.6, 4.6, 1.8, 0.12));
      });
    },
    hap: [{t: 0.6, kind: 'medium'}],
  },
  // Sun: SLEEP EARLY. The sleep dial: tonight's sleep is drawn from an early bedtime round to the new
  // week's alarm. Bedtime is coral; a slow light walks the night
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 18, T = c.T, a0 = (21.5 / 24) * TAU - TAU, a1 = (6.5 / 24) * TAU;
      for (let h = 0; h < 24; h++) {
        const a = (h / 24) * TAU, major = h % 6 === 0;
        g.on(...P(cx, cy, 12.6, a), major ? 0.62 : 0.26);
        if (major) g.on(...P(cx, cy, 13.6, a), 0.62);
      }
      g.ring(cx, cy, 9.5, 0.12);
      const aE = lerp(a0, a1, ez((T - 0.35) / 1.1)), n = Math.max(1, Math.round((aE - a0) * 13));
      for (let i = 0; i <= n; i++) {
        const a = a0 + ((aE - a0) * i) / n, gl = glow(i / n, T, 1.8, 6, 3, 0.12);
        g.on(...P(cx, cy, 10, a), 0.82 + 0.18 * gl);
        g.on(...P(cx, cy, 9, a), 0.42 + 0.35 * gl);
      }
      for (const [a, cor] of [[a0, 1], [aE, 0]] as [number, number][]) {
        const [x, y] = P(cx, cy, 9.5, a);
        for (const [u, v] of [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1]]) g.fr(x + u, y + v, 1, cor && !u && !v ? 1 : 0);
      }
      g.glyph(ICON_MOON, 18, 14, 1, 0.9);
    },
    hap: [{t: 1.45, kind: 'light'}],
  },
];
void ({} as MC);
