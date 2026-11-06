/**
 * Matrix Dynamic: automatic (day 66, the habit runs on its own). One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * The biggest milestone in the app: every scene builds to one big beat, then idles on its own, calmly.
 */
import {CX, CY, MScn, back, cl, eio, ez, lerp, rnd} from '../mxlib';
import {TAU} from './common';

// ---------- helpers (local to this file) ----------
/** a point on a circle: angle 0 = up, clockwise */
const pol = (cx: number, cy: number, r: number, a: number): [number, number] => [cx + Math.sin(a) * r, cy - Math.cos(a) * r];
/** the centre of the cell a point falls in */
const snap = (x: number, y: number): [number, number] => [Math.floor(x) + 0.5, Math.floor(y) + 0.5];
/** a soft bump travelling along 0..1 every P seconds (for idle light sweeps) */
const sweep = (t: number, P: number, u: number, w = 0.12) => {
  const ph = (((t % P) + P) % P) / P;
  const d = (u - ph * 1.4 + 0.2) / w;
  return Math.exp(-d * d);
};
/** a light going round and round: closeness of angle a to a head that turns once every P seconds */
const orbitGlow = (t: number, P: number, a: number, w = 0.5) => {
  const h = (((t / P) % 1) + 1) % 1 * TAU, d = Math.abs(((a - h + Math.PI) % TAU + TAU) % TAU - Math.PI);
  return Math.exp(-((d / w) ** 2));
};
const hit = (T: number, at: number, d = 0.15) => (T >= at ? Math.exp(-(T - at) / d) : 0);

/** a squared "6" in 33 blocks of 2 x 2, in pen order: top bar right to left, down the side, along the bottom, up, and the middle bar */
const SIX: [number, number][] = (() => {
  const o: [number, number][] = [];
  for (let c = 6; c >= 0; c--) o.push([c, 0]);
  for (let r = 1; r <= 10; r++) o.push([0, r]);
  for (let c = 1; c <= 6; c++) o.push([c, 10]);
  for (let r = 9; r >= 6; r--) o.push([6, r]);
  for (let c = 6; c >= 1; c--) o.push([c, 5]);
  return o;
})();
/** the 66: piece i (0..65) in pen order, top-left cell of its 2 x 2 block */
const block66 = (i: number): [number, number] => {
  const d = i < 33 ? 0 : 1, k = i % 33;
  return [8 + d * 16 + SIX[k][0] * 2, 6 + SIX[k][1] * 2];
};
/** an up arrow, as cell offsets from its centre: head first, then the shaft */
const ARROW: [number, number][] = [[0, -3], [-1, -2], [1, -2], [-2, -1], [2, -1], [0, -2], [0, -1], [0, 0], [0, 1], [0, 2]];

export const SCENES: MScn[] = [
  // Mon: THE SEAL. Everything pulls into one bright core, then bursts out into a radiant seal around 66
  {
    draw: (g, c) => {
      const T = c.T, cx = CX + 0.5, cy = CY + 0.5, at = 0.95, N = 16;
      const gather = ez(T / 0.5), out = back(cl((T - at + 0.12) / 0.32), 1.6);
      const core = 1 + 2 * ez(T / 0.9) + 0.35 * Math.sin(Math.min(T, at) * 14) * cl(T / 0.4);
      // the rays: free dots that gather in the core, then fly out to their cells
      for (let k = 0; k < N; k++) {
        const a = (k / N) * TAU;
        const glow = T > at + 0.4 ? 0.62 + 0.38 * orbitGlow(c.t, 6, a) : 1;
        for (let r = 10.5; r <= 13.5; r++) {
          const [ex, ey] = snap(...pol(cx, cy, r, a));
          const [qx, qy] = pol(cx, cy, core * (0.3 + (r - 10.5) * 0.25), a + r);
          const x = lerp(qx, ex, out), y = lerp(qy, ey, out);
          const you = k === 0 && r === 13.5;
          g.fr(x, y, (T < at ? 0.55 + 0.45 * gather : glow) * (r === 10.5 ? 0.75 : 1), you ? 1 : 0);
        }
      }
      // the shockwave
      const age = T - at;
      for (let k = 0; k < 40; k++) {
        const [x, y] = pol(cx, cy, 13 + (age > 0 ? ez(age / 0.7) * 10 : 0), (k / 40) * TAU);
        g.fr(x, y, age > 0 && age < 0.7 ? 0.8 * (1 - age / 0.7) : 0);
      }
      // the seal: an inner ring, and 66 in the middle
      if (T > at + 0.1) {
        const f = cl((T - at - 0.1) / 0.3);
        g.ring(cx, cy, 8, 0.4 * f);
        g.num('66', cx, cy - 3, 1, f);
      }
      return {flash: hit(T, at, 0.16) * 0.3, shake: T > at && T < at + 0.22 ? 0.4 : 0};
    },
    hap: [{t: 0.2, kind: 'light'}, {t: 0.95, kind: 'heavy'}, {t: 1.0, kind: 'success'}],
  },
  // Tue: THE CASCADE. You turn the first tile; every other tile turns itself, faster and faster, until the board is full
  {
    draw: (g, c) => {
      const T = c.T, X0 = 11, Y0 = 6;
      const at = (col: number, r: number) => (col + r === 0 ? 0.35 : 0.62 + 0.62 * Math.sqrt((col + r) / 10));
      const end = at(5, 5) + 0.3;
      const pop = hit(T, end, 0.3);
      for (let col = 0; col < 6; col++)
        for (let r = 0; r < 6; r++) {
          const dur = col + r === 0 ? 0.42 : 0.3, k = cl((T - at(col, r)) / dur), ph = Math.PI * eio(k);
          const w = Math.abs(Math.cos(ph)), front = ph > Math.PI / 2;
          const x = X0 + col * 4 + 1.5, y = Y0 + r * 4 + 1.5;
          const glow = T > end + 0.6 ? 0.8 + 0.2 * sweep(c.t, 5.5, (col + r) / 10, 0.14) : 0.85 + 0.15 * pop;
          for (let v = -1; v <= 1; v++)
            for (let u = -1; u <= 1; u++) {
              const centre = u === 0 && v === 0, you = centre && col === 0 && r === 0;
              const b = front ? (you ? 1 : glow) : centre ? (you ? 0.9 : 0) : 0.3;
              g.fr(x + u * w, y + v, b, you ? 1 : 0);
            }
        }
      return {flash: hit(T, end, 0.16) * 0.3, shake: T > end && T < end + 0.2 ? 0.35 : 0};
    },
    hap: [{t: 0.35, kind: 'medium'}, {t: 0.9, kind: 'light'}, {t: 1.15, kind: 'light'}, {t: 1.54, kind: 'heavy'}, {t: 1.6, kind: 'success'}],
  },
  // Wed: THE LOOP. On a scope, one beam draws an infinity sign; when the loop closes it locks, and keeps running on its own
  {
    draw: (g, c) => {
      const T = c.T, cx = CX + 0.5, cy = CY + 0.5, A = 14, at = 1.25;
      const lem = (u: number): [number, number] => {
        const d = 1 + Math.sin(u) ** 2;
        return [cx + (A * Math.cos(u)) / d, cy + (A * Math.sin(u) * Math.cos(u)) / d * 1.25];
      };
      // the beam's travel: one full loop to draw it, accelerating; then a calm lap every six seconds
      const draw = TAU * eio(cl((T - 0.25) / 1.0));
      const u = T < at ? draw : TAU + ((T - at) / 6) * TAU;
      // the trace: what the beam has drawn stays lit
      const lock = hit(T, at, 0.35);
      for (let k = 0; k < 96; k++) {
        const v = (k / 96) * TAU;
        if (T < at && v > draw) continue;
        const behind = (((u - v) % TAU) + TAU) % TAU;
        const b = T < at ? 0.55 : 0.42 + 0.5 * Math.exp(-behind / 0.9) + 0.4 * lock;
        g.on(...lem(v), b);
      }
      // the beam: a head and a short glowing tail
      for (let i = 0; i < 6; i++) g.fr(...lem(u - i * 0.07), i ? 0.9 - i * 0.14 : 1, i ? 0 : 1);
      // the scope: four corner marks
      for (const [x, y, sx, sy] of [[8, 6, 1, 1], [37, 6, -1, 1], [8, 29, 1, -1], [37, 29, -1, -1]]) {
        g.line(x, y, x + sx * 2, y, 0.3);
        g.line(x, y, x, y + sy * 2, 0.3);
      }
      return {flash: hit(T, at, 0.16) * 0.28, shake: T > at && T < at + 0.18 ? 0.3 : 0};
    },
    hap: [{t: 0.25, kind: 'light'}, {t: 1.25, kind: 'heavy'}, {t: 1.3, kind: 'success'}],
  },
  // Thu: THE CURVE. Bars for the weeks of the habit: steep at first, then level. The last one reaches automatic
  {
    draw: (g, c) => {
      const T = c.T, N = 15, base = 30, top = 8, at = 0.35 + 14 * 0.055 + 0.3;
      const H = (i: number) => Math.round((base - top) * (1 - Math.exp(-(i + 1) / 3.2)) / (1 - Math.exp(-N / 3.2)));
      // the automatic line, at the top
      const line = hit(T, at, 0.4);
      for (let x = 7; x <= 37; x++) g.on(x, top - 1, x % 2 ? 0.28 + 0.6 * line : T > at ? 0.6 : 0.28);
      g.line(7, base + 1, 37, base + 1, 0.3);
      for (let i = 0; i < N; i++) {
        const x = 8 + i * 2, a = (T - 0.35 - i * 0.055) / 0.3;
        const h = Math.round(H(i) * back(cl(a), 1.4));
        const last = i === N - 1;
        for (let j = 0; j < 23; j++) {
          const on = j < h, tip = j === h - 1;
          const lv = j >= h - 2 ? 1 : 0.42;
          const b = on ? lv * (T > at + 0.5 ? 0.78 + 0.22 * sweep(c.t, 5, i / N) : 0.95) : 0;
          g.fs(x, base - j, last && tip ? 1 : b, last && tip && a >= 1 ? 1 : 0);
        }
      }
      return {flash: hit(T, at, 0.16) * 0.28, shake: T > at && T < at + 0.2 ? 0.35 : 0};
    },
    hap: [{t: 0.35, kind: 'light'}, {t: 1.42, kind: 'heavy'}, {t: 1.47, kind: 'success'}],
  },
  // Fri: LOCKED IN. A field of arrows, each pointing its own way, turns as one and locks straight up
  {
    draw: (g, c) => {
      const T = c.T, at = 1.15;
      for (let r = 0; r < 4; r++)
        for (let q = 0; q < 5; q++) {
          const i = r * 5 + q, cx = 10.5 + q * 6, cy = 7.5 + r * 7;
          const d = Math.hypot(q - 2, (r - 1.5) * 1.2) / 2.6;
          const a0 = (rnd(i * 7 + 3) - 0.5) * 4.4 + 0.3 * Math.sin(T * 2.2 + i);
          const k = back(cl((T - 0.55 - d * 0.3) / 0.3), 1.6), ang = a0 * (1 - k);
          const flow = T > at + 0.4 ? 0.7 + 0.3 * sweep(c.t, 3.6, (3 - r) / 3.4 + 0.1, 0.2) : 0.95;
          ARROW.forEach(([x, y], j) => {
            const you = q === 2 && r === 1 && j === 0;
            g.fr(cx + x * Math.cos(ang) - y * Math.sin(ang), cy + x * Math.sin(ang) + y * Math.cos(ang), j < 5 ? flow : flow * 0.8, you && T > at ? 1 : 0);
          });
        }
      return {flash: hit(T, at, 0.16) * 0.28, shake: T > at && T < at + 0.2 ? 0.35 : 0};
    },
    hap: [{t: 0.55, kind: 'light'}, {t: 1.15, kind: 'heavy'}, {t: 1.2, kind: 'success'}],
  },
  // Sat: ON REPEAT. The repeat control switches on: two arrows draw a loop, the light comes on, and the loop keeps turning by itself
  {
    draw: (g, c) => {
      const T = c.T, cx = CX + 0.5, cy = CY + 0.5, at = 1.0, R = 11.5, SPAN = 2.55, n = 34;
      const rot = T > at ? 0.32 * (T - at) * ez((T - at) / 1.5) : 0;
      const p = ez(cl((T - 0.25) / 0.65));
      for (let half = 0; half < 2; half++) {
        const a0 = -SPAN / 2 + half * Math.PI + rot;
        // the arc: free dots along it, drawn on from its tail
        for (let i = 0; i < n; i++) {
          const u = i / (n - 1), a = a0 + u * SPAN, on = u <= p;
          const b = on ? (T > at + 0.4 ? 0.75 + 0.25 * sweep(c.t, 5, u, 0.2) : 0.9) : 0;
          for (const r of [R - 0.5, R + 0.5]) g.fr(...pol(cx, cy, r, a), b);
        }
        // the arrowhead at its leading end
        const ae = a0 + SPAN * p, hb = p > 0.05 ? 1 : 0;
        for (let k = 1; k <= 3; k++) {
          g.fr(...pol(cx, cy, R + k, ae - k * 0.1), hb);
          g.fr(...pol(cx, cy, R - k, ae - k * 0.1), hb);
        }
        g.fr(...pol(cx, cy, R, ae + 0.04), hb);
      }
      // repeat is on: the light in the middle
      const on = T > at;
      g.disc(cx, cy, 2.2, on ? 0.35 + 0.2 * hit(T, at, 0.4) : 0.12);
      g.on(cx, cy, on ? 1 : 0.2, on ? 1 : 0);
      return {flash: hit(T, at, 0.16) * 0.28, shake: T > at && T < at + 0.2 ? 0.35 : 0};
    },
    hap: [{t: 0.25, kind: 'light'}, {t: 1.0, kind: 'heavy'}, {t: 1.05, kind: 'success'}],
  },
  // Sun: EVERY PIECE IN PLACE. Sixty-six days on the calendar; the last one lands, and every day flies into 66
  {
    draw: (g, c) => {
      const T = c.T, last = 0.6, fly0 = 0.85, at = 1.85;
      for (let i = 0; i < 66; i++) {
        const [cx0, cy0] = [12 + (i % 7) * 3, 3 + Math.floor(i / 7) * 3];
        const [cx1, cy1] = block66(i);
        const isLast = i === 65;
        const dep = isLast ? 1.4 : fly0 + i * 0.0075, dur = isLast ? 0.45 : 0.42;
        const p = eio(cl((T - dep) / dur)), arc = Math.sin(Math.PI * p) * (isLast ? 4 : 1.5);
        const lit = isLast ? T > last : true;
        const b = !lit ? 0.22 : T > at + 0.6 ? 0.82 + 0.18 * sweep(c.t, 5.5, i / 66, 0.08) : isLast ? 1 : 0.85;
        for (let v = 0; v < 2; v++)
          for (let u = 0; u < 2; u++) g.fr(lerp(cx0, cx1, p) + u + 0.5, lerp(cy0, cy1, p) + v + 0.5 - arc, b, isLast && lit ? 1 : 0);
      }
      return {flash: hit(T, at, 0.16) * 0.3 + hit(T, last, 0.1) * 0.08, shake: T > at && T < at + 0.2 ? 0.4 : 0};
    },
    hap: [{t: 0.6, kind: 'light'}, {t: 0.85, kind: 'light'}, {t: 1.85, kind: 'heavy'}, {t: 1.9, kind: 'success'}],
  },
];
