/**
 * Matrix Dynamic: stilltime. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * The evening, as an instrument. Every day shows the track (the whole evening, six hours) and what is
 * left on it. The beat: the card arrives showing a full evening, then drains to what's left (0.45 s to
 * 1.3 s). After that a calm idle: one soft light runs along what's left, toward the end of the day.
 * Coral is "now": the needle tip, the tile being used up, the cursor, the neck of the glass.
 */
import {G, MC, MScn, cl, eio, lerp} from '../mxlib';
import {TAU, slP} from './common';

/** a point on a circle around (cx, cy); angle 0 = up, clockwise */
const P = (cx: number, cy: number, r: number, a: number): [number, number] => [cx + Math.sin(a) * r, cy - Math.cos(a) * r];
/** a straight run of lit cells between two points in board space (cell centres at .5) */
const seg = (g: G, x0: number, y0: number, x1: number, y1: number, b: number, c = 0) => {
  const n = Math.max(1, Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) * 1.5));
  for (let i = 0; i <= n; i++) g.on(lerp(x0, x1, i / n), lerp(y0, y1, i / n), b, c);
};
/** the evening on the board: full when the card arrives, then it drains to what's left */
const AT = 0.45, DUR = 0.85;
const shown = (c: MC) => lerp(1, slP(c), eio((c.T - AT) / DUR));
/** the same, with a small physical settle (needles, knobs) */
const shownSpring = (c: MC) => {
  const x = (c.T - AT) / DUR;
  return lerp(1, slP(c), eio(x) + 0.045 * Math.sin(Math.PI * cl((x - 0.62) / 0.6)));
};
/** a soft light passing along a path (u = 0..1): one pass of `dur` seconds every `per` seconds, from `start` */
const glow = (u: number, T: number, start: number, per: number, dur: number, w = 0.14) => {
  if (T < start) return 0;
  const p = ((((T - start) % per) / dur) * (1 + 2 * w)) - w;
  return Math.exp(-(((u - p) / w) ** 2));
};
/** 3 x 5 capitals for the week header */
const FONT3: Record<string, string[]> = {
  M: ['#.#', '###', '###', '#.#', '#.#'],
  T: ['###', '.#.', '.#.', '.#.', '.#.'],
  W: ['#.#', '#.#', '###', '###', '#.#'],
  F: ['###', '#..', '##.', '#..', '#..'],
  S: ['.##', '#..', '.#.', '..#', '##.'],
};
const letter = (g: G, ch: string, x: number, y: number, b: number) => FONT3[ch].forEach((row, j) => [...row].forEach((q, i) => q === '#' && g.on(x + i, y + j, b)));
/** a 3 x 3 tile with soft corners */
const tile = (g: G, x: number, y: number, b: number) => {
  for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) g.on(x + i, y + j, (i === 1 || j === 1 ? 1 : 0.7) * b);
};

export const SCENES: MScn[] = [
  // Mon: THE GAUGE. A dial of the evening; the needle drops from full to what's left, the lit arc is the
  // time you still have, the hour rays outside go dark as the hours go
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 21, R = 11.5, A0 = -TAU / 3, A1 = TAU / 3, T = c.T;
      const s = shownSpring(c), aN = lerp(A0, A1, cl(s));
      g.ring(cx, cy, R, 0.26, 0, A0, A1);
      const n = Math.max(1, Math.round((aN - A0) * R * 1.3));
      for (let i = 0; i <= n; i++) {
        const a = A0 + ((aN - A0) * i) / n, gl = glow(1 - i / n, T, 1.7, 3.8, 1.6);
        g.on(...P(cx, cy, R, a), 0.82 + 0.18 * gl);
        g.on(...P(cx, cy, R - 1, a), 0.36 + 0.34 * gl);
      }
      for (let h = 0; h <= 6; h++) {
        const a = lerp(A0, A1, h / 6), on = h / 6 <= slP(c) + 1e-4 || h / 6 <= s, L = h % 3 === 0 ? 2.2 : 1.2;
        seg(g, ...P(cx, cy, R + 1.5, a), ...P(cx, cy, R + 1.5 + L, a), on ? 0.65 : 0.3);
      }
      for (let k = 0; k < 10; k++) {
        const [x, y] = P(cx, cy, 1.4 + k * 0.92, aN);
        g.fr(x, y, k === 9 ? 1 : 0.9, k === 9 ? 1 : 0);
      }
      g.disc(cx, cy, 1.25, 0.95);
    },
    hap: [{t: 1.3, kind: 'light'}],
  },
  // Tue: TIME BLOCKS. The evening in ten-minute tiles, an hour a row. The spent ones go dark from the end
  // back to what's left; the tile being used up drains cell by cell, its next cell in coral
  {
    draw: (g, c) => {
      const N = 36, v = shown(c) * N, T = c.T;
      const cur = Math.ceil(v) - 1, m = Math.min(9, Math.max(1, Math.ceil((v - cur) * 9 - 1e-6)));
      for (let i = 0; i < N; i++) {
        const x = 11 + (i % 6) * 4, y = 6 + Math.floor(i / 6) * 4;
        if (i < cur) tile(g, x, y, 0.8 + 0.2 * glow(i / Math.max(1, cur), T, 1.7, 4.2, 1.9, 0.1));
        else if (i === cur) {
          for (let k = 0; k < 9; k++) g.on(x + (k % 3), y + Math.floor(k / 3), k < m ? 0.82 : 0.1, k === m - 1 ? 1 : 0);
        } else tile(g, x, y, 0.1);
      }
    },
  },
  // Wed: THE LIVE LINE. Six hours on a line: behind the cursor the evening has gone flat; ahead of it the
  // signal is still alive and flows on toward the end of the day
  {
    draw: (g, c) => {
      const s = shown(c), T = c.T, x0 = 9, x1 = 36, yb = 17.5;
      const xn = lerp(x0, x1, 1 - s) + 0.5;
      for (let i = 0; i <= 2 * (x1 - x0); i++) {
        const x = x0 + 0.5 + i / 2, d = x - xn;
        const env = cl(d / 3) * cl((x1 + 0.5 - x) / 2.5);
        g.fr(x, yb + env * 3.2 * Math.sin(0.72 * x - 1.15 * T), d < 0 ? 0.24 : 0.9);
      }
      g.fr(xn, yb, 1, 1);
      for (const dy of [-3, -2, 2, 3]) g.fr(xn, yb + dy, Math.abs(dy) === 2 ? 0.75 : 0.45);
      for (let y = 13; y <= 21; y++) g.on(36, y, y === 17 ? 0.9 : 0.6);
      for (let h = 0; h <= 6; h++) g.on(lerp(x0, x1, h / 6) + 0.5, 25, h / 6 >= 1 - s - 1e-4 ? 0.55 : 0.18);
    },
  },
  // Thu: THE FADER. A long fader marked in hours to closing; the cap slides down to what's left and the
  // lit track under it is the time you still have
  {
    draw: (g, c) => {
      const s = shownSpring(c), T = c.T, top = 5.5, bot = 29.5, yk = lerp(bot, top, s);
      for (let h = 0; h <= 6; h++) {
        const y = bot - 4 * h, on = h <= slP(c) * 6 + 1e-4, L = h % 3 === 0 ? 4 : 3;
        for (let i = 0; i < L; i++) g.on(16 - i, y, on ? 0.6 : 0.22), g.on(28 + i, y, on ? 0.6 : 0.22);
      }
      for (let y = 5; y <= 29; y++) {
        const below = y + 0.5 > yk;
        g.on(22, y, below ? 0.72 + 0.28 * glow((y + 0.5 - yk) / Math.max(1, bot - yk), T, 1.7, 3.6, 1.4) : 0.16);
      }
      for (let j = -1; j <= 1; j++)
        for (let i = -4; i <= 4; i++) {
          const corner = Math.abs(i) === 4 && j !== 0;
          g.fr(22.5 + i, yk + j, j === 0 ? 1 : corner ? 0.5 : 0.74, i === 0 && j === 0 ? 1 : 0);
        }
    },
    hap: [{t: 1.3, kind: 'light'}],
  },
  // Fri: THE SAND GLASS. Sand drains from the top bulb to what's left, a calm trickle runs through the
  // neck and settles on the pile. The neck is coral: now
  {
    draw: (g, c) => {
      const s = shown(c), T = c.T;
      // glass walls, caps
      for (let d = 1; d <= 12; d++) {
        const w = HG.wi[d];
        for (const sg of [-1, 1]) g.on(22 + sg * (w + 1), 17 - d, 0.42), g.on(22 + sg * (w + 1), 17 + d, 0.42);
      }
      g.on(21, 17, 0.42);
      g.on(23, 17, 0.42);
      for (let x = 12; x <= 32; x++) g.on(x, 4, 0.85), g.on(x, 30, 0.85);
      // sand: the top keeps its cells nearest the neck and the walls (a crater drains first)
      const nTop = Math.round(cl(s) * HG.S), nBot = HG.S - nTop;
      for (let k = 0; k < nTop; k++) g.on(22 + HG.top[k][0], 17 - HG.top[k][1], 0.8);
      for (let k = 0; k < nBot; k++) g.on(22 + HG.bot[k][0], 17 + HG.bot[k][1], 0.8);
      g.on(22, 17, 1, 1);
      // the trickle: grains fall from the neck onto the pile, then wait out of sight
      let dTop = 13;
      for (let k = 0; k < nBot; k++) if (HG.bot[k][0] === 0) dTop = Math.min(dTop, HG.bot[k][1]);
      const yLand = 17 + dTop - 0.5, Dist = Math.max(0.5, yLand - 17.5), Tf = Math.sqrt((2 * Dist) / 60), P = 1.4, N = 7;
      for (let k = 0; k < N; k++) {
        const tau = ((((T + 50) / P + k / N) % 1) + 1) % 1 * P;
        let y = 17.5, b = 0;
        if (s > 0.002 && tau < Tf) {
          y = 17.5 + 30 * tau * tau;
          b = 0.85 * cl(tau / 0.05);
        } else if (tau < Tf + 0.3) y = yLand;
        g.fr(22.5, y, b);
      }
    },
  },
  // Sat: THE TIME TIMER. A stopwatch whose lit wedge is the evening left; it winds back to now, then the
  // wedge shrinks toward twelve as the evening goes
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 18.5, s = shown(c), A = cl(s) * TAU, T = c.T;
      g.ring(cx, cy, 12.6, 0.5);
      g.rect(21, 3, 3, 2, 0.85, true);
      g.on(22, 5, 0.6);
      seg(g, ...P(cx, cy, 13.6, TAU / 8), ...P(cx, cy, 14.6, TAU / 8), 0.7);
      for (let k = 0; k < 12; k++) g.on(...P(cx, cy, 11, (k / 12) * TAU), k % 3 === 0 ? 0.5 : 0.28);
      for (let y = 8; y <= 29; y++)
        for (let x = 12; x <= 33; x++) {
          const dx = x + 0.5 - cx, dy = y + 0.5 - cy, r = Math.hypot(dx, dy);
          if (r > 9.3 || r < 0.5) continue;
          const a = (Math.atan2(dx, -dy) + TAU) % TAU;
          if (a <= A) g.on(x, y, 0.42 + 0.3 * glow(1 - a / Math.max(0.01, A), T, 1.7, 4.2, 1.8, 0.16));
        }
      for (let k = 0; k < 9; k++) g.on(...P(cx, cy, 1.4 + k, 0), 0.85);
      for (let k = 0; k < 9; k++) g.fr(...P(cx, cy, 1.4 + k * 1.02, A), 0.95);
      g.fr(...P(cx, cy, 11, A), 1, 1);
      g.disc(cx, cy, 1.2, 1);
    },
  },
  // Sun: THE DAY VIEW. The week across the top, Sunday lit; under it tonight like a calendar day, the now
  // line sliding down to the present. The open block under it is what's left before Monday
  {
    draw: (g, c) => {
      const s = shown(c), T = c.T, y0 = 9.5, yN = y0 + (1 - cl(s)) * 23;
      'MTWTFSS'.split('').forEach((ch, i) => letter(g, ch, 9 + i * 4, 2, i === 6 ? 1 : 0.45));
      for (let h = 0; h <= 6; h++) {
        const y = Math.round(y0 - 0.5 + (23 * h) / 6), ahead = y + 0.5 >= yN - 0.01;
        g.on(9, y, ahead ? 0.55 : 0.22);
        g.on(10, y, ahead ? 0.55 : 0.22);
        if (!ahead) for (let x = 13; x <= 35; x += 2) g.on(x, y, 0.13);
      }
      const yb = Math.ceil(yN + 1);
      for (let y = yb; y <= 32; y++) {
        const gl = glow((y - yN) / Math.max(1, 32.5 - yN), T, 1.7, 4, 1.6);
        g.on(13, y, 0.8 + 0.2 * gl);
        g.on(14, y, 0.8 + 0.2 * gl);
        g.on(35, y, 0.42);
        for (let x = 16; x <= 33; x += 2) if ((y - yb) % 2 === 1) g.on(x, y, 0.12 + 0.2 * gl);
      }
      for (let x = 15; x <= 35; x++) g.on(x, 32, 0.42);
      for (let k = 0; k < 24; k++) g.fr(12.5 + k, yN, 0.95);
      g.fr(11.5, yN, 1, 1);
    },
  },
];

/** the sand glass: interior half-widths by rows from the neck, and the order sand cells fill in */
const HG = (() => {
  const H = 12;
  const wi = Array.from({length: H + 1}, (_, d) => (d === 0 ? 0 : Math.round(1 + 7 * Math.pow(Math.sin((d / H) * (Math.PI / 2)), 1.4) - 0.25)));
  const cells: [number, number][] = [];
  for (let d = 1; d <= H; d++) for (let x = -wi[d]; x <= wi[d]; x++) cells.push([x, d]);
  const S = Math.round(cells.length * 0.6);
  const top = [...cells].sort((a, b) => a[1] - 0.25 * Math.abs(a[0]) - (b[1] - 0.25 * Math.abs(b[0])));
  const bot = [...cells].sort((a, b) => H - a[1] + 0.3 * Math.abs(a[0]) - (H - b[1] + 0.3 * Math.abs(b[0])));
  return {wi, S, top, bot};
})();
