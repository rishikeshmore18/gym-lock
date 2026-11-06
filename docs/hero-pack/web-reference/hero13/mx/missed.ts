/**
 * Matrix Dynamic: missed. Yesterday slipped; today counts. The gap is shown honestly, small and dim;
 * today is the bright, inviting thing. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * Anything that moves is a free particle pushed in a fixed order and count; static structure is lit cells.
 */
import {CX, CY, G, MScn, back, cl, eio, ez, lerp} from '../mxlib';

const TAU = Math.PI * 2;
/** a free particle at the centre of the cell (x, y): same place g.on(x, y) would light */
const P = (g: G, x: number, y: number, b: number, c = 0) => g.fr(x + 0.5, y + 0.5, b, c);
/** soft travelling highlight, 0..1, centred on `at` */
const bump = (x: number, at: number, w: number) => Math.exp(-(((x - at) / w) ** 2));

export const SCENES: MScn[] = [
  // Mon: NEVER TWICE. The streak runs along a line, breaks once where yesterday was, and picks up
  // again in today: the one bright dot, sending out slow rings.
  {
    draw: (g, c) => {
      const T = c.T, y = CY, at = 0.9;
      const done = [9, 13, 17, 21], yx = 26, tx = 31;
      const draw = ez((T - 0.15) / 0.6) * 22;
      for (let x = 9; x <= 31; x++) if (x - 9 <= draw && (x < yx - 2 || x > yx + 2) && (x < tx - 2)) g.on(x, y, 0.32);
      for (const x of done) g.rect(x - 1, y - 1, 3, 3, 0.8, true);
      g.ring(yx + 0.5, y + 0.5, 1.6, 0.45);
      const on = T >= at, b = on ? 1 : 0.3;
      g.disc(tx + 0.5, y + 0.5, 2.3, b);
      g.on(tx, y, on ? 1 : 0, 1);
      // rings from today: one big one on the beat, then a slow breath every 2.6 s
      for (let k = 0; k < 2; k++) {
        const t0 = k === 0 ? at : at + 1.4 + Math.floor((T - at - 1.4) / 2.6) * 2.6;
        const age = T - t0, dur = k === 0 ? 0.9 : 2.2, rr = 2.6 + cl(age / dur) * (k === 0 ? 9 : 5);
        const vis = age > 0 && age < dur && (k === 0 || T > at + 1.4);
        for (let i = 0; i < 36; i++) {
          const a = (i / 36) * TAU;
          P(g, tx + Math.sin(a) * rr, y - Math.cos(a) * rr, vis ? (k === 0 ? 0.8 : 0.4) * (1 - age / dur) : 0);
        }
      }
      return {flash: on ? Math.exp(-(T - at) / 0.12) * 0.15 : 0};
    },
    hap: [{t: 0.9, kind: 'medium'}],
  },
  // Tue: BACK TODAY. Weeks of sessions on a grid; yesterday's square is empty. Today's square flips
  // over and opens: one gap barely changes the picture.
  {
    draw: (g, c) => {
      const T = c.T, at = 0.85;
      const W = [[1, 1, 0, 1, 1, 0, 1], [1, 1, 1, 0, 1, 0, 1], [1, 0, 1, 1, 1, 0, 1]];
      const X = (i: number) => 9 + i * 4, Y = (j: number) => 10 + j * 4;
      const sw = 2 + ((c.t * 9) % 70);
      for (let j = 0; j < 3; j++)
        for (let i = 0; i < 7; i++) {
          if (W[j][i]) g.rect(X(i), Y(j), 3, 3, 0.72 + 0.25 * bump(X(i) + Y(j), sw, 4) * cl(T - 2), true);
          else g.on(X(i) + 1, Y(j) + 1, 0.25);
        }
      g.rect(X(0), Y(3), 3, 3, 0.4);
      for (let i = 2; i < 7; i++) g.on(X(i) + 1, Y(3) + 1, 0.16);
      // today: a free square that flips from blank to an open, bright frame
      const p = cl((T - at) / 0.32), sx = Math.abs(Math.cos(p * Math.PI));
      for (let v = 0; v < 3; v++)
        for (let u = 0; u < 3; u++) {
          const mid = u === 1 && v === 1;
          const b = p < 0.5 ? (mid ? 0.25 : 0) : mid ? 1 : 1;
          P(g, X(1) + 1 + (u - 1) * sx, Y(3) + v, b, mid && p >= 0.5 ? 1 : 0);
        }
      return {flash: p >= 1 ? Math.exp(-(T - at - 0.32) / 0.12) * 0.12 : 0};
    },
    hap: [{t: 1.17, kind: 'medium'}],
  },
  // Wed: ONE BLIP. A steady trace with one beat missing, its ghost in faint dots. Then today's beat
  // lands, the tallest of all, right on time.
  {
    draw: (g, c) => {
      const T = c.T, base = 20, x0 = 8, x1 = 36;
      const pen = lerp(x0, x1, cl((T - 0.15) / 1.5));
      const ys: number[] = [];
      for (let x = x0; x <= x1; x++) ys.push(base + ecg(x - x0));
      // yesterday's beat, as a ghost
      for (let x = 22; x < 29; x++) {
        const gy = base + BEAT[x - 22];
        if (gy !== base) g.line(x, base, x, gy, 0.14, 0, 1);
      }
      const lp = T > 2 ? ((c.t * 9) % 60) + x0 - 10 : -99;
      for (let x = x0; x < x1; x++) {
        if (x + 1 > pen) break;
        const today = x >= 29;
        g.line(x, ys[x - x0], x + 1, ys[x + 1 - x0], (today ? 1 : 0.7) + 0.3 * bump(x, lp, 2.5));
      }
      const k = Math.min(x1 - x0 - 1, Math.floor(pen - x0)), f = pen - x0 - k;
      P(g, pen, lerp(ys[k], ys[k + 1], f), 1, 1);
      const hit = T - (0.15 + ((33 - x0) / (x1 - x0)) * 1.5);
      return {flash: hit > 0 ? Math.exp(-hit / 0.12) * 0.15 : 0};
    },
    hap: [{t: 1.49, kind: 'heavy'}],
  },
  // Thu: RESET. The days as bars, like a screen time chart. Yesterday's row is empty; today's bar is
  // drawn as an outline, twenty minutes long, waiting to be filled.
  {
    draw: (g, c) => {
      const T = c.T, x0 = 9, Ys = [8, 14, 20, 26], at = 0.75;
      const L = [21, 17];
      L.forEach((len, k) => {
        const n = Math.round(len * ez((T - 0.1 - k * 0.1) / 0.5));
        g.rect(x0, Ys[k], Math.max(1, n), 3, 0.75, true);
      });
      g.line(x0, Ys[2] + 1, x0 + 24, Ys[2] + 1, 0.13, 0, 1);
      g.on(x0, Ys[2] + 1, 0.4);
      const w = Math.round(20 * ez((T - at) / 0.4));
      if (w > 1) g.rect(x0, Ys[3], w, 3, 0.85);
      g.on(x0 + 1, Ys[3] + 1, T > at ? 1 : 0, 1);
      // a soft light glides inside today's bar: the twenty minutes, still to fill
      const ph = (c.T - 1.6) % 3.2, gx = x0 + 2 + ph * 6;
      P(g, gx, Ys[3] + 1, T > 1.6 && gx < x0 + 18.5 ? 0.55 * Math.sin((Math.PI * (gx - x0 - 2)) / 16.5) : 0);
      return {flash: T > at + 0.4 ? Math.exp(-(T - at - 0.4) / 0.12) * 0.1 : 0};
    },
    hap: [{t: 1.15, kind: 'medium'}],
  },
  // Fri: NOT TWO. The trend climbs, dips once where yesterday was, then turns hard upward: today's
  // arrow, pushing up off the dip.
  {
    draw: (g, c) => {
      const T = c.T, at = 1.2;
      const V: [number, number][] = [[9, 28], [14, 23], [18, 19], [21, 22], [30, 10]];
      const seg = V.slice(1).map((q, i) => Math.hypot(q[0] - V[i][0], q[1] - V[i][1]));
      const tot = seg.reduce((a, b) => a + b, 0);
      let d = ez((T - 0.15) / (at - 0.15)) * tot;
      const lp = T > 2 ? ((c.t * 10) % 70) - 5 : -99;
      let hx = V[0][0], hy = V[0][1], acc = 0;
      for (let i = 0; i < 4; i++) {
        const u = cl(d / seg[i]);
        if (u <= 0) break;
        const [ax, ay] = V[i], [bx, by] = V[i + 1];
        hx = lerp(ax, bx, u);
        hy = lerp(ay, by, u);
        const b = (i === 2 ? 0.38 : i === 3 ? 1 : 0.7) + 0.3 * bump(acc + seg[i] / 2, lp, 6);
        g.line(ax, ay, hx, hy, b, 0, i === 2 ? 1 : 0);
        d -= seg[i];
        acc += seg[i];
      }
      // the arrowhead: free, it snaps open when the line arrives
      const k = back(cl((T - at) / 0.3), 2.5), dir = Math.atan2(V[4][1] - V[3][1], V[4][0] - V[3][0]);
      for (const s of [-1, 1])
        for (let j = 1; j <= 5; j++) {
          const a = dir + Math.PI + s * 0.62, r = j * 0.95 * k;
          P(g, V[4][0] + 0.5 + Math.cos(a) * r, V[4][1] + Math.sin(a) * r, T > at ? 1 : 0);
        }
      P(g, V[4][0] + 0.5, V[4][1], T > at - 0.05 ? 1 : 0, 1);
      return {flash: T > at ? Math.exp(-(T - at) / 0.12) * 0.15 : 0};
    },
    hap: [{t: 1.2, kind: 'medium'}],
  },
  // Sat: CATCH UP. On the lap, you are behind your own pace by a day. You surge, the gap closes to a
  // step, and you run on right behind it.
  {
    draw: (g, c) => {
      const T = c.T, R = 11;
      g.ring(CX + 0.5, CY + 0.5, R, 0.32);
      g.ring(CX + 0.5, CY + 0.5, R - 2.5, 0.12);
      const w = 0.5, aP = 0.3 + w * T;
      const dlt = lerp(1.35, 0.42, eio((T - 0.9) / 0.8));
      const surge = Math.max(0, Math.sin(Math.PI * cl((T - 0.9) / 0.8)));
      const aY = aP - dlt, m = R - 1.25;
      const at = (a: number, r = m): [number, number] => [CX + 0.5 + Math.sin(a) * r, CY + 0.5 - Math.cos(a) * r];
      // the gap: a dotted arc between you and your pace
      for (let i = 1; i <= 9; i++) {
        const [x, y] = at(lerp(aY, aP, i / 10));
        g.fr(x, y, 0.3 * cl(dlt * 2 - 0.6));
      }
      for (let j = 1; j <= 5; j++) {
        const [x, y] = at(aY - j * 0.07);
        g.fr(x, y, 0.55 * surge * (1 - j / 6));
      }
      for (const [ox, oy] of SQ) {
        const [px, py] = at(aP), [yx, yy] = at(aY);
        g.fr(px + ox, py + oy, 0.95);
        g.fr(yx + ox, yy + oy, 1, 1);
      }
    },
    hap: [{t: 0.9, kind: 'medium'}],
  },
  // Sun: STILL TIME. The week as a dial. Saturday is an empty slot; the hand runs round to now, part
  // way through Sunday, and the rest of today lights: the week isn't over.
  {
    draw: (g, c) => {
      const T = c.T, R = 11, gp = 0.07, at = 1.3, now = 0.45;
      const done = [1, 1, 0, 1, 1];
      const seg = (i: number, f0: number, f1: number, b: number, w = 2) => {
        const a0 = ((i + f0) / 7) * TAU + gp * (f0 === 0 ? 1 : 0), a1 = ((i + f1) / 7) * TAU - gp * (f1 === 1 ? 1 : 0);
        for (let k = 0; k < w; k++) g.ring(CX + 0.5, CY + 0.5, R - k, b, 0, a0, a1);
      };
      for (let i = 0; i < 5; i++) seg(i, 0, 1, done[i] ? 0.85 : 0.22);
      seg(5, 0, 1, 0.3, 1);
      const lit = T >= at, br = lit ? 0.85 + 0.15 * Math.sin(c.t * 1.6) : 0.35;
      seg(6, 0, now, 0.3);
      seg(6, now, 1, br);
      g.disc(CX + 0.5, CY + 0.5, 1.5, 0.9);
      const h = lerp(0, ((6 + now) / 7) * TAU, back(cl((T - 0.35) / (at - 0.35)), 1.2));
      for (let j = 0; j < 8; j++) {
        const r = 2 + j * 0.85;
        P(g, CX + Math.sin(h) * r, CY - Math.cos(h) * r, 0.9, j === 7 ? 1 : 0);
      }
      return {flash: lit ? Math.exp(-(T - at) / 0.12) * 0.15 : 0};
    },
    hap: [{t: 1.3, kind: 'medium'}],
  },
];

// ---------- local helpers ----------
/** one heartbeat, as a height per column (negative is up) */
const BEAT = [0, -1, 0, 1, -8, 3, -1];
/** the trace: four beats of seven columns; the third (yesterday) is missing; the fourth (today) is tall */
function ecg(x: number) {
  const k = Math.floor(x / 7), u = x - k * 7;
  if (k === 2 || k > 3) return 0;
  return BEAT[u] * (k === 3 ? 1.35 : 1);
}
const SQ: [number, number][] = [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]];
