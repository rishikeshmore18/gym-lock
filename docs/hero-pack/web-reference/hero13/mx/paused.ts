/**
 * Matrix Dynamic: paused. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * The streak is frozen, safely on hold: nothing is lost. Each scene has one beat, the moment things stop
 * and hold (a second hand stops, ice closes round a tile, a moving line freezes onto the grid, two levels
 * rise into a pause sign and hold), then stays still with a slow cold sheen passing over it.
 * Coral is the held moment: you, kept where you left off.
 */
import {G, ICON, MC, MScn, cl, eio, lerp, spr} from '../mxlib';
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
/** a cold sheen: a diagonal band of light crossing the board every `per` seconds */
const sheen = (x: number, y: number, T: number, start: number, per = 6) => glow((x + y * 0.6 - 8) / 40, T, start, per, 2.2, 0.08);
/** the outline of a rounded box, as cells in order round the edge (clockwise from the top left) */
const boxEdge = (x0: number, y0: number, w: number, h: number): [number, number][] => {
  const o: [number, number][] = [];
  for (let x = x0 + 1; x < x0 + w - 1; x++) o.push([x, y0]);
  for (let y = y0 + 1; y < y0 + h - 1; y++) o.push([x0 + w - 1, y]);
  for (let x = x0 + w - 2; x > x0; x--) o.push([x, y0 + h - 1]);
  for (let y = y0 + h - 2; y > y0; y--) o.push([x0, y]);
  return o;
};

export const SCENES: MScn[] = [
  // Mon: OFF THE CLOCK. A clock face; the second hand ticks twice more and stops dead. Frozen time: a
  // small pause mark settles under the hands
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 17.5, T = c.T;
      for (let h = 0; h < 12; h++) {
        const a = (h / 12) * TAU, major = h % 3 === 0, [x, y] = P(cx, cy, 12.5, a);
        g.on(x, y, (major ? 0.75 : 0.42) + 0.25 * sheen(x, y, T, 2));
        if (major) g.on(...P(cx, cy, 11.5, a), 0.75);
      }
      g.ring(cx, cy, 14.3, 0.2);
      for (let k = 0; k < 6; k++) g.fr(...P(cx, cy, 1.2 + k, -TAU / 6), 0.92);
      for (let k = 0; k < 9; k++) g.fr(...P(cx, cy, 1.2 + k, TAU / 6), 0.92);
      let a = (22 / 60) * TAU;
      for (const t of [0.35, 0.85, 1.35]) if (T > t) a += (spr(T - t, 34, 13) * TAU) / 60;
      for (let k = 0; k < 10; k++) g.fr(...P(cx, cy, 1.5 + k, a), k === 9 ? 1 : 0.55, k === 9 ? 1 : 0);
      g.disc(cx, cy, 1.2, 1);
      const p = cl((T - 1.45) / 0.35);
      for (let y = 22; y <= 25; y++) g.on(21, y, 0.6 * p), g.on(23, y, 0.6 * p);
    },
    hap: [{t: 0.35, kind: 'light'}, {t: 0.85, kind: 'light'}, {t: 1.35, kind: 'medium'}],
  },
  // Tue: ON ICE. Your streak tile, held right here: ice closes round it and keeps it. A glint crosses the
  // ice now and then
  {
    draw: (g, c) => {
      const T = c.T, E = boxEdge(15, 10, 15, 15), k = Math.round(E.length * eio((T - 0.4) / 0.6));
      for (let y = 15; y <= 19; y++) for (let x = 20; x <= 24; x++) g.on(x, y, (x === 20 || x === 24) && (y === 15 || y === 19) ? 0.7 : 0.95);
      g.on(22, 17, 1, 1);
      for (let i = 0; i < E.length; i++) {
        const j = (i + 10) % E.length, [x, y] = E[j];
        if (Math.min(i, E.length - i) * 2 <= k) g.on(x, y, 0.5 + 0.45 * sheen(x, y, T, 2.2, 5));
      }
      if (T > 1.0)
        for (let y = 12; y <= 22; y++)
          for (let x = 17; x <= 27; x++) {
            if (x >= 19 && x <= 25 && y >= 14 && y <= 20) continue;
            if ((x + y) % 2 === 0) g.on(x, y, (0.1 + 0.35 * sheen(x, y, T, 2.2, 5)) * cl((T - 1.0) / 0.4));
          }
      seg(g, 17, 14, 18, 13, 0.62);
    },
    hap: [{t: 1.0, kind: 'medium'}],
  },
  // Wed: FREEZE FRAME. The signal is running, then it stops and sets onto the grid, crisp, kept exactly as
  // it was. A cold sheen passes over it
  {
    draw: (g, c) => {
      const T = c.T, xs0 = cl((T - 0.75) / 0.5), ph = 2.4 * Math.min(T, 0.75) + 1.2 * (xs0 - eioInt(xs0));
      const snap = eio((T - 1.2) / 0.25);
      for (let i = 0; i <= 54; i++) {
        const x = 9 + i / 2, env = cl((x - 8.5) / 3) * cl((36.5 - x) / 3);
        const y = 17.5 + env * 4.2 * Math.sin(0.55 * (x - 9) - ph);
        const xs = Math.floor(x) + 0.5, ys = Math.floor(y) + 0.5;
        g.fr(lerp(x, xs, snap), lerp(y, ys, snap), (0.35 + 0.55 * env) * (1 + 0.25 * sheen(x, y, T, 2.2, 5)), i === 27 ? 1 : 0);
      }
      return {flash: T > 1.2 ? Math.exp(-(T - 1.2) / 0.12) * 0.12 : 0};
    },
    hap: [{t: 1.2, kind: 'medium'}],
  },
  // Thu: HOLD. Two levels rise like meters and hold at the top: a pause sign. A peak marker stays lit over
  // each; the plan waits
  {
    draw: (g, c) => {
      const T = c.T;
      [15, 25].forEach((x0, bi) => {
        const n = Math.round(9 * eio((T - 0.3 - bi * 0.08) / 0.7));
        for (let s = 0; s < 9; s++) {
          const y = 26 - s * 2, lit = s < n;
          for (let x = x0; x < x0 + 5; x++) g.on(x, y, lit ? 0.85 + 0.15 * glow(s / 8, T, 2, 6, 1.6, 0.14) : 0.1);
        }
        const pk = cl((T - 1.0 - bi * 0.08) / 0.2);
        for (let x = x0 + 1; x < x0 + 4; x++) g.on(x, 7, pk, bi === 1 && x === x0 + 2 ? 1 : 0);
      });
    },
    hap: [{t: 1.05, kind: 'light'}],
  },
  // Fri: HOLD POSITION. The arrow climbs its track toward the summit flag, stops, and holds there; the
  // track above stays lit, waiting
  {
    draw: (g, c) => {
      const T = c.T, x0 = eio((T - 0.25) / 0.85), tip = lerp(25, 14, x0) + 0.5 * Math.sin(Math.PI * cl((T - 0.95) / 0.4)) * (T > 0.95 ? 1 : 0);
      for (let y = 9; y <= 30; y++) g.on(22, y, y < tip ? 0.22 + 0.4 * glow((tip - y) / (tip - 9), T, 1.8, 5, 1.6) : 0.55);
      for (let y = 2; y <= 8; y++) g.on(22, y, 0.75);
      for (let y = 2; y <= 4; y++) for (let x = 23; x <= 27; x++) g.on(x, y, x === 27 && y !== 3 ? 0.5 : 0.85);
      ICON.arrowU.forEach((row, j) => [...row].forEach((q, i) => q === '#' && g.fr(19.5 + i, tip + j, j === 0 ? 1 : 0.92, j === 0 ? 1 : 0)));
      const hp = cl((T - 1.25) / 0.3);
      for (const x of [16, 17, 27, 28]) g.on(x, Math.round(tip + 3), 0.55 * hp);
    },
    hap: [{t: 1.1, kind: 'light'}],
  },
  // Sat: THE CHAIN. The streak as a chain; today's link is frozen in ice, and the chain holds through it.
  // A light runs the length of the chain, unbroken
  {
    draw: (g, c) => {
      const T = c.T, u = (x: number) => (x - 8) / 28, gl = (x: number) => 0.3 * glow(u(x), T, 1.8, 5, 2, 0.08);
      const face = (x0: number, b: number) => {
        for (const [x, y] of boxEdge(x0, 15, 7, 5)) g.on(x, y, b + gl(x));
      };
      face(8, 0.7);
      face(17, 0.95);
      face(26, 0.7);
      for (const [a, z] of [[12, 18], [21, 27], [30, 36]]) for (let x = a; x <= z; x++) g.on(x, 17, 0.75 + gl(x));
      g.on(20, 15, 1, 1);
      const E = boxEdge(15, 13, 11, 9), k = Math.round(E.length * eio((T - 0.55) / 0.5));
      for (let i = 0; i < E.length; i++) if (Math.min(i, E.length - i) * 2 <= k) g.on(E[i][0], E[i][1], 0.38 + 0.4 * sheen(E[i][0], E[i][1], T, 2, 5));
    },
    hap: [{t: 1.05, kind: 'light'}],
  },
  // Sun: THE COUNT. Your day count rolls up to where you left it and stops. The 66-day track under it is
  // paused at the same place, a pause mark standing on it
  {
    draw: (g, c) => {
      const T = c.T, d = c.D.day || 47, n = Math.round(lerp(Math.max(0, d - 9), d, eio(T / 1.0)));
      g.num(String(n), 22.5, 5, 2, 1, 0.07);
      const xm = Math.round(9 + (26 * d) / 66);
      for (let x = 9; x <= 35; x++) g.on(x, 26, x < xm ? 0.62 + 0.3 * glow((x - 9) / (xm - 9), T, 1.8, 6, 1.8, 0.12) : x === xm ? 1 : 0.2, x === xm ? 1 : 0);
      const p = cl((T - 1.05) / 0.3);
      for (let y = 21; y <= 24; y++) g.on(xm - 1, y, 0.8 * p), g.on(xm + 1, y, 0.8 * p);
    },
    hap: [{t: 1.0, kind: 'medium'}],
  },
];

/** integral of eio over 0..x (x in 0..1), so a slowing line's phase stays continuous */
function eioInt(x: number) {
  const n = 16;
  let s = 0;
  for (let i = 0; i < n; i++) s += eio(((i + 0.5) / n) * x) * (x / n);
  return s;
}
void ({} as MC);
