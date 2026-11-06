/**
 * Matrix Dynamic: weekkept. The weekly target is hit: a proud, earned moment. Each day builds the five
 * sessions in, then pays off with one beat, then settles. Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * Anything that moves is a free particle pushed in a fixed order and count; static structure is lit cells.
 */
import {CX, CY, G, MScn, back, cl, eio, ez, lerp} from '../mxlib';

const TAU = Math.PI * 2;
/** a free particle at the centre of the cell (x, y): same place g.on(x, y) would light */
const P = (g: G, x: number, y: number, b: number, c = 0) => g.fr(x + 0.5, y + 0.5, b, c);
/** soft travelling highlight, 0..1, centred on `at` */
const bump = (x: number, at: number, w: number) => Math.exp(-(((x - at) / w) ** 2));
/** decaying hit, 0 before `at` */
const hit = (T: number, at: number, w = 0.12) => (T >= at ? Math.exp(-(T - at) / w) : 0);
const five = (t0: number, dt: number, last: 'heavy' | 'success' = 'success') =>
  [0, 1, 2, 3, 4].map((i) => ({t: t0 + i * dt, kind: (i === 4 ? 'heavy' : 'light') as 'light' | 'heavy'})).concat([{t: t0 + 4 * dt + 0.03, kind: last as 'heavy'}]);

export const SCENES: MScn[] = [
  // Mon: THE MEDAL. A medal on its ribbon. Five studs light round the rim, one per session; on the
  // fifth the 5 lights up and rays burst out. Then a slow shine crosses it.
  {
    draw: (g, c) => {
      const T = c.T, mx = CX + 0.5, my = 20.5, at = 1.3;
      const shine = T > 2 ? ((c.t * 9) % 64) - 14 : -99;
      const sh = (x: number, y: number) => 0.25 * bump(x - y * 0.6, shine, 2.2);
      // the ribbon: one broad band from the top of the board down to the medal's loop
      for (let y = 2; y <= 10; y++) {
        const hw = Math.round(lerp(5, 2, (y - 2) / 8));
        for (let x = -hw; x <= hw; x++) g.on(mx - 0.5 + x, y, Math.abs(x) === hw ? 0.65 : 0.32);
      }
      g.ring(mx, my, 9.5, 0.9);
      g.ring(mx, my, 8, 0.28);
      const lit = T >= at;
      g.num('5', CX, 14, 2, lit ? 1 : 0.3);
      for (let k = 0; k < 5; k++) {
        const a = ((36 + 72 * k) * Math.PI) / 180, on = T >= 0.45 + k * 0.2;
        const x = mx + Math.sin(a) * 9.5, y = my - Math.cos(a) * 9.5;
        g.disc(x, y, 1.1, on ? 1 : 0.35, k === 4 && on ? 1 : 0);
      }
      // the shine, applied as a brightness lift over the rim and the 5
      if (shine > -20) for (let x = 12; x < 34; x++) for (let y = 10; y < 31; y++) {
        const r = Math.hypot(x + 0.5 - mx, y + 0.5 - my);
        if (Math.abs(r - 9.5) < 0.6) g.on(x, y, 0.9 + sh(x, y));
      }
      // rays: they burst on the payoff and settle as a faint halo
      const age = T - at;
      for (let k = 0; k < 20; k++) {
        const a = (k / 20) * TAU + TAU / 40, top = Math.abs(((a + Math.PI) % TAU) - Math.PI) < 0.55;
        const r = 11.5 + 2.2 * ez(age / 0.5);
        for (let j = 0; j < 2; j++)
          P(g, mx - 0.5 + Math.sin(a) * (r + j * 1.2), my - 0.5 - Math.cos(a) * (r + j * 1.2), top || age < 0 ? 0 : 0.25 + 0.75 * Math.exp(-age / 0.35));
      }
      return {flash: hit(T, at, 0.15) * 0.3, shake: T > at && T < at + 0.18 ? 0.3 : 0};
    },
    hap: [{t: 0.45, kind: 'light'}, {t: 0.65, kind: 'light'}, {t: 0.85, kind: 'light'}, {t: 1.05, kind: 'light'}, {t: 1.25, kind: 'light'}, {t: 1.3, kind: 'heavy'}, {t: 1.33, kind: 'success'}],
  },
  // Tue: FIVE PLANNED, FIVE DONE. Five open tiles flip over one by one and land solid. On the fifth
  // the row jumps once together, and stays.
  {
    draw: (g, c) => {
      const T = c.T, y0 = CY - 2, FL = 0.28, at = 0.35 + 4 * 0.2 + FL;
      const sw = T > 2.2 ? ((c.t * 8) % 60) - 5 : -99;
      for (let k = 0; k < 5; k++) {
        const x0 = 8 + k * 6, p = cl((T - 0.35 - k * 0.2) / FL), sx = Math.abs(Math.cos(p * Math.PI));
        const hop = 2.2 * Math.sin(Math.PI * cl((T - at - k * 0.06) / 0.32));
        for (let v = 0; v < 5; v++)
          for (let u = 0; u < 5; u++) {
            const edge = u === 0 || v === 0 || u === 4 || v === 4, mid = u === 2 && v === 2;
            const bF = p < 0.5 ? (edge ? 0.5 : 0) : 0.9 + 0.1 * bump(x0 + u, sw, 3);
            P(g, x0 + 2 + (u - 2) * sx, y0 + v - hop, bF * (0.55 + 0.45 * sx), k === 4 && mid && p >= 0.5 ? 1 : 0);
          }
      }
      return {flash: hit(T, at, 0.15) * 0.25, shake: T > at && T < at + 0.15 ? 0.2 : 0};
    },
    hap: five(0.63, 0.2),
  },
  // Wed: FULL SIGNAL. Five bars, short to tall. They fill one after another; on the fifth the whole
  // meter kicks, every bar jumping to full strength.
  {
    draw: (g, c) => {
      const T = c.T, bot = 27, at = 1.4;
      const sw = T > 2.2 ? 30 - ((c.t * 9) % 50) : -99;
      for (let k = 0; k < 5; k++) {
        const x = 11 + k * 5, h = 4 + k * 4, lv = h * ez((T - 0.35 - k * 0.2) / 0.25);
        const kick = 1.4 * Math.sin(Math.PI * cl((T - at - k * 0.05) / 0.3));
        const full = Math.floor(lv);
        for (let j = 0; j < h; j++)
          for (let u = 0; u < 3; u++) {
            const y = bot - j;
            g.on(x + u, y, j < full ? 0.85 + 0.15 * bump(y, sw, 2.5) : 0.14, k === 4 && j === h - 1 && u === 1 && T >= at ? 1 : 0);
          }
        for (let u = 0; u < 3; u++) P(g, x + u, bot - lv + 1 - kick, lv > 0.1 && (lv < h - 0.05 || kick > 0.05) ? 1 : 0);
      }
      return {flash: hit(T, at, 0.15) * 0.28, shake: T > at && T < at + 0.15 ? 0.25 : 0};
    },
    hap: five(0.6, 0.2),
  },
  // Thu: ALL FIVE TO THE TOP. Five faders pushed up one by one. When the fifth hits the top, the max
  // line lights across all of them.
  {
    draw: (g, c) => {
      const T = c.T, top = 8, bot = 28, at = 1.42;
      const sw = T > 2.2 ? 34 - ((c.t * 9) % 50) : -99;
      for (let k = 0; k < 5; k++) {
        const x = 12 + k * 5, q = cl((T - 0.3 - k * 0.2) / 0.4), y = lerp(bot - 1, top, back(q, 1.4));
        for (let j = top; j <= bot; j++) g.on(x, j, j > y + 1 ? 0.75 + 0.25 * bump(j, sw, 2.5) : 0.2);
        for (let u = -1; u <= 1; u++) for (let v = 0; v < 2; v++) P(g, x + u, y + v, 1, k === 4 && u === 0 && v === 0 ? 1 : 0);
      }
      const w = Math.round(27 * ez((T - at) / 0.2));
      if (T >= at) g.line(9, top - 3, 9 + w, top - 3, 0.95);
      return {flash: hit(T, at, 0.15) * 0.3, shake: T > at && T < at + 0.16 ? 0.3 : 0};
    },
    hap: five(0.58, 0.2),
  },
  // Fri: FIVE FOR FIVE. Five arrows fly in one after another and land in the bullseye, fanned out.
  // The fifth sets the target ringing.
  {
    draw: (g, c) => {
      const T = c.T, tx = 27.5, ty = 17.5, at = 0.45 + 4 * 0.25;
      g.ring(tx, ty, 7.2, 0.45);
      g.ring(tx, ty, 4.6, 0.6);
      g.ring(tx, ty, 2.2, 0.75);
      g.on(tx - 0.5, ty - 0.5, 1, 1);
      const ANG = [0, -17, 17, -34, 34];
      ANG.forEach((deg, k) => {
        const a = (deg * Math.PI) / 180, dx = -Math.cos(a), dy = Math.sin(a);
        const land = 0.45 + k * 0.25, p = cl((T - land + 0.2) / 0.2), off = (1 - p) * 26;
        const age = T - land, q = age > 0 ? 0.7 * Math.exp(-age / 0.14) * Math.sin(age * 55) : 0;
        const vis = T > land - 0.2 ? 1 : 0;
        for (let j = 0; j < 11; j++) {
          const r = 1.6 + j + off, wob = q * (j / 10);
          g.fr(tx + dx * r - dy * wob, ty + dy * r + dx * wob, vis * (j === 0 ? 1 : 0.85));
        }
        for (const s of [-1, 1])
          for (let j = 0; j < 2; j++) {
            const r = 11.6 + off - j * 1.1, n = (j + 1) * 0.8 * s;
            g.fr(tx + dx * r - dy * (n + q), ty + dy * r + dx * (n + q), vis * 0.7);
          }
      });
      const age = T - at;
      for (let i = 0; i < 40; i++) {
        const a = (i / 40) * TAU, r = 7.5 + Math.max(0, age) * 14;
        g.fr(tx + Math.sin(a) * r, ty - Math.cos(a) * r, age > 0 && age < 0.55 ? 0.7 * (1 - age / 0.55) : 0);
      }
      const sk = [0, 1, 2, 3, 4].some((k) => T > 0.45 + k * 0.25 && T < 0.53 + k * 0.25);
      return {flash: hit(T, at, 0.15) * 0.3, shake: T > at && T < at + 0.16 ? 0.35 : sk ? 0.12 : 0};
    },
    hap: five(0.45, 0.25),
  },
  // Sat: EVERYTHING IN LINE. Five planets on five orbits, each at its own speed. They come round into
  // one straight line on the fifth beat, lock, and turn together from then on.
  {
    draw: (g, c) => {
      const T = c.T, sx = CX + 0.5, sy = CY + 0.5, at = 1.4;
      const W = [3.2, 2.5, 1.9, 1.45, 1.1];
      g.disc(sx, sy, 1.5, 0.9);
      const rot = T < at ? 0 : 0.28 * (T - at);
      const th = (k: number) => (T < at ? Math.PI / 2 - W[k] * (at - T) * (1 - 0.35 * (at - T) / at) : Math.PI / 2 + rot);
      for (let k = 0; k < 5; k++) {
        const rx = 3.8 + 2.55 * k, ry = rx * 0.75;
        g.ring(sx, sy, rx, 0.16, 0, 0, TAU, ry, 1);
        const a = th(k), x = sx + Math.sin(a) * rx, y = sy - Math.cos(a) * ry;
        for (const [ox, oy] of SQ) g.fr(x + ox, y + oy, 1, k === 4 ? 1 : 0);
      }
      // the line through them: bright on the lock, then a faint spoke that turns with them
      const age = T - at, a = th(4), rx = 3.8 + 2.55 * 4;
      for (let j = 0; j < 14; j++) {
        const f = (j + 1) / 15;
        g.fr(sx + Math.sin(a) * rx * f, sy - Math.cos(a) * rx * 0.75 * f, age > 0 ? 0.2 + 0.7 * Math.exp(-age / 0.35) : 0);
      }
      return {flash: hit(T, at, 0.15) * 0.3, shake: T > at && T < at + 0.15 ? 0.25 : 0};
    },
    hap: [{t: 1.4, kind: 'heavy'}, {t: 1.43, kind: 'success'}],
  },
  // Sun: START TO FINISH. A playhead runs the week from Monday to Sunday and every planned day
  // lights as it passes. At Sunday the week is underlined, and the line points on to tomorrow.
  {
    draw: (g, c) => {
      const T = c.T, y0 = 11, at = 1.4;
      const plan = [1, 1, 0, 1, 1, 0, 1];
      const px = lerp(7.5, 35.5, cl((T - 0.25) / 1.15));
      const sw = T > 2.3 ? ((c.t * 8) % 60) - 6 : -99;
      for (let i = 0; i < 7; i++) {
        const x = 9 + i * 4, on = px > x + 1.5;
        if (!plan[i]) {
          g.on(x + 1, y0 + 3, 0.28);
          continue;
        }
        const b = on ? 0.88 + 0.12 * bump(x, sw, 3) : 0.35;
        g.rect(x, y0, 3, 7, b, on);
        if (i === 6 && on) g.on(x + 1, y0 + 3, 1, 1);
      }
      for (let j = 0; j < 11; j++) P(g, px, y0 - 2 + j, T > 0.2 && T < at + 0.05 ? 0.9 : 0);
      const w = 27 * ez((T - at) / 0.3);
      if (T >= at) g.line(9, y0 + 10, 9 + w, y0 + 10, 0.85);
      for (const [u, v] of [[-1, -1], [0, 0], [-1, 1], [-2, -2], [-2, 2]]) P(g, 36 + u, y0 + 10 + v, T > at + 0.25 ? 0.85 : 0);
      return {flash: hit(T, at, 0.15) * 0.3, shake: T > at && T < at + 0.15 ? 0.25 : 0};
    },
    hap: [0.37, 0.53, 0.86, 1.02, 1.36].map((t) => ({t, kind: 'light' as 'light' | 'heavy' | 'success'})).concat([{t: 1.4, kind: 'heavy'}, {t: 1.43, kind: 'success'}]),
  },
];

const SQ: [number, number][] = [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]];
void CY;
