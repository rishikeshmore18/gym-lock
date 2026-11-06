/**
 * Matrix Dynamic: freshstart. A new week begins: a clean slate, day one. One scene per day, Monday first.
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * Anything that moves is a free particle pushed in a fixed order and count; static structure is lit cells.
 */
import {CX, CY, G, MScn, back, cl, eio, ez, lerp} from '../mxlib';
import {text, textWidth} from '../../hero4/dots';

const TAU = Math.PI * 2;
/** a free particle at the centre of the cell (x, y): same place g.on(x, y) would light */
const P = (g: G, x: number, y: number, b: number, c = 0) => g.fr(x + 0.5, y + 0.5, b, c);
/** LED digits as points (cell centres), centred on cx, top at y */
const digits = (s: string, cx: number, y: number, scale: number) => {
  const x0 = Math.round(cx - textWidth(s, scale) / 2);
  return text(s, x0, y, {scale}).map((q) => [q.x, q.y] as [number, number]);
};
/** soft travelling highlight, 0..1, centred on `at` */
const bump = (x: number, at: number, w: number) => Math.exp(-(((x - at) / w) ** 2));

export const SCENES: MScn[] = [
  // Mon: THE WEEK DIAL. Last week's marks sit on the dial, the hand on Sunday. The hand steps to
  // Monday, a ripple clears the old marks, and Monday's mark grows into a ray.
  {
    draw: (g, c) => {
      const T = c.T, R = 11.5, at = 1.0;
      const last = [0, 1, 1, 0, 1, 0, 1]; // last week: four sessions
      const clr = ez((T - at - 0.08) / 0.3);
      g.ring(CX + 0.5, CY + 0.5, R + 1.6, 0.24, 0, 0, TAU, R + 1.6, 1);
      for (let i = 1; i < 7; i++) {
        const a = (i / 7) * TAU, b = lerp(last[i] ? 0.95 : 0.5, 0.5, clr);
        for (let r = R - 2.5; r <= R; r++) g.on(CX + 0.5 + Math.sin(a) * r, CY + 0.5 - Math.cos(a) * r, b);
      }
      g.disc(CX + 0.5, CY + 0.5, 1.6, 0.9);
      // Monday: a tick that becomes a ray (free, it grows past the rim)
      const grow = back(cl((T - at) / 0.4), 2.4), on = T >= at;
      for (let j = 0; j < 7; j++) {
        const r = R - 2.5 + j, vis = j < 3 || (on && j < 3 + 4 * grow);
        const b = !vis ? 0 : on ? 0.88 + 0.12 * Math.sin(c.t * 1.7 - j * 0.4) : 0.4;
        P(g, CX, CY - r, b);
      }
      // the hand: Sunday to Monday with a mechanical overshoot; coral tip is now
      const h = lerp((6 / 7) * TAU, TAU, back(cl((T - 0.65) / 0.35), 2));
      for (let j = 0; j < 7; j++) {
        const r = 2.2 + j * 0.8;
        P(g, CX + Math.sin(h) * r, CY - Math.cos(h) * r, 0.9, j === 6 ? 1 : 0);
      }
      // the ripple that clears last week
      const age = T - at;
      for (let i = 0; i < 44; i++) {
        const a = (i / 44) * TAU, r = 2 + Math.max(0, age) * 24;
        P(g, CX + Math.sin(a) * r, CY - Math.cos(a) * r, age > 0 && age < 0.6 ? 0.7 * (1 - age / 0.6) : 0);
      }
      return {flash: age > 0 ? Math.exp(-age / 0.12) * 0.15 : 0};
    },
    hap: [{t: 1.0, kind: 'medium'}],
  },
  // Tue: THE BOARD RESETS. A split-flap row still shows last week. Card by card it flips to blank,
  // then the first card flips over to today.
  {
    draw: (g, c) => {
      const T = c.T, H = 5, yh = CY, FL = 0.3, t2 = 1.5;
      const last = [0, 1, 1, 0, 1, 0, 1];
      const X = (k: number) => 9 + k * 4;
      const sweepX = 4 + ((c.t * 7) % 60);
      // a face's brightness: 0 blank, 1 last week's session, 2 today (open, bright frame)
      const face = (f: number, x: number, u: number, d: number) => {
        if (f === 1) return 0.9;
        if (f === 2) return u === 1 && d < H ? 0 : 1;
        return 0.28 + 0.14 * bump(x, sweepX, 2.5) * cl(T - 2.4);
      };
      for (let k = 0; k < 7; k++) {
        let oldF = last[k], newF = 0, p = cl((T - 0.7 - k * 0.085) / FL);
        if (k === 0 && T >= t2) (oldF = 0), (newF = 2), (p = cl((T - t2) / FL));
        const cs = Math.cos(p * Math.PI);
        const coverTop = p < 0.5 ? H * cs : 0, coverBot = p >= 0.5 ? -H * cs : 0;
        const fTop = p > 0 ? newF : oldF, fBot = p >= 1 ? newF : oldF;
        for (let u = 0; u < 3; u++) {
          const x = X(k) + u;
          for (let d = 1; d <= H; d++) {
            if (!(p > 0 && p < 0.5 && d <= coverTop)) g.on(x, yh - d, face(fTop, x, u, d));
            if (!(p >= 0.5 && p < 1 && d <= coverBot)) g.on(x, yh + d, face(fBot, x, u, d));
          }
        }
        // the flap: 3 x H free particles that fold over the hinge
        for (let u = 0; u < 3; u++)
          for (let d = 1; d <= H; d++) {
            const x = X(k) + u;
            if (p <= 0) P(g, x, yh - d, 0);
            else if (p < 0.5) P(g, x, yh - d * cs, face(oldF, x, u, d) * (0.45 + 0.55 * cs));
            else if (p < 1) P(g, x, yh - d * cs, face(newF, x, u, d) * (0.45 - 0.55 * cs));
            else P(g, x, yh + d, 0);
          }
      }
      g.on(X(0) + 1, yh, T >= t2 + FL * 0.6 ? 1 : 0, 1);
      return {flash: T > t2 + FL ? Math.exp(-(T - t2 - FL) / 0.12) * 0.12 : 0};
    },
    hap: [{t: 0.75, kind: 'light'}, {t: 1.8, kind: 'medium'}],
  },
  // Wed: NEWTON'S CRADLE. Five balls at rest: zero of five. The first one swings, and the push runs
  // through all five to the far side. The week is moving.
  {
    draw: (g, c) => {
      const T = c.T, top = 7, base = 27, L = 13, py = top + 1;
      g.line(9, top, 35, top, 0.6);
      g.line(9, top + 1, 9, base - 1, 0.2);
      g.line(35, top + 1, 35, base - 1, 0.2);
      g.line(8, base, 36, base, 0.45);
      const th = cradle(T);
      for (let k = 0; k < 5; k++) {
        const X = 14 + k * 4, a = th[k];
        const bx = X + Math.sin(a) * L, by = py + Math.cos(a) * L;
        for (let s = 0; s < 11; s++) {
          const u = (s / 10) * (L - 2.2);
          g.fr(X + Math.sin(a) * u, py + Math.cos(a) * u, 0.34);
        }
        for (const [ox, oy] of BALL) {
          const core = Math.abs(ox) < 1 && Math.abs(oy) < 1;
          g.fr(bx + ox, by + oy, 0.95, k === 0 && core ? 1 : 0);
        }
      }
    },
    hap: [{t: 1.43, kind: 'heavy'}, {t: 1.99, kind: 'light'}],
  },
  // Thu: LAST WEEK, BANKED. Last week's bars drain down and leave their outlines behind as the mark
  // to beat. The board is empty; the first slot is ready.
  {
    draw: (g, c) => {
      const T = c.T, fl = 27, Hs = [16, 20, 13, 0, 18];
      g.line(9, fl + 1, 35, fl + 1, 0.45);
      Hs.forEach((h, k) => {
        const x = 11 + k * 5, d = eio((T - 0.75 - k * 0.07) / 0.5);
        const lv = h * (1 - d);
        const breath = k === 0 && T > 1.6 ? 0.25 + 0.15 * (0.5 + 0.5 * Math.sin(c.t * 1.8)) : 0;
        if (h) {
          g.rect(x, fl - h + 1, 3, h, 0.3 + breath);
          g.line(x, fl - h + 1, x + 2, fl - h + 1, 0.6 + breath);
        }
        const full = Math.floor(lv);
        for (let j = 0; j < full; j++) for (let u = 0; u < 3; u++) g.on(x + u, fl - j, 0.85);
        for (let u = 0; u < 3; u++) P(g, x + u, fl - lv + 1, h && lv > 0.15 ? 0.85 : 0);
      });
      const at = 1.5;
      g.on(12, fl, T > at ? 1 : 0, 1);
      g.line(11, fl + 1, 13, fl + 1, T > at ? 0.9 : 0.4);
      return {flash: T > at ? Math.exp(-(T - at) / 0.12) * 0.1 : 0};
    },
    hap: [{t: 0.8, kind: 'light'}, {t: 1.5, kind: 'medium'}],
  },
  // Fri: WEEK 8. Seven weeks behind you as dim chevrons, the eighth slides in bright; a wave of light
  // rides along them into this week.
  {
    draw: (g, c) => {
      const T = c.T, y = 22, at = 0.95;
      g.num('8', CX, 3, 2, 1);
      for (let i = 0; i < 8; i++) {
        const x0 = 9 + i * 3.3, last = i === 7;
        const slide = last ? (1 - back(cl((T - at + 0.25) / 0.35), 2.2)) * 7 : (1 - ez((T - 0.2 - i * 0.06) / 0.4)) * -6;
        const ride = T > 2 ? bump(i, ((c.t * 2.6) % 16) - 3, 0.9) : 0;
        const b = last ? (T > at ? 1 : 0.6) : 0.4 + 0.5 * ride + 0.45 * bump(i, (T - 0.55) * 14, 1);
        CHEV.forEach(([u, v]) => P(g, x0 + u + slide, y + v, b, last && u === 3 && T > at ? 1 : 0));
      }
      return {flash: T > at ? Math.exp(-(T - at) / 0.12) * 0.15 : 0};
    },
    hap: [{t: 0.95, kind: 'medium'}],
  },
  // Sat: THE START LINE. An empty running track. Your dot takes its mark, the line lights, and the
  // first lap of the week begins at an easy pace.
  {
    draw: (g, c) => {
      const T = c.T, cy = CY + 1, hs = 5, at = 0.85;
      stadium(g, CX, cy, hs, 8, 0.5);
      stadium(g, CX, cy, hs, 5, 0.18);
      for (let y = cy + 5; y <= cy + 8; y++) g.on(CX, y, T > at ? 0.95 : 0.45);
      const v = 6.5, s = T < 1.2 ? 0 : v * (T - 1.2 - 0.45 * (1 - Math.exp(-(T - 1.2) / 0.45)));
      const drop = (1 - back(cl((T - 0.45) / 0.4), 1.8)) * -6;
      for (let j = 5; j >= 1; j--) {
        const [x, y] = lane(CX, cy, hs, 6.5, s - j * 0.85);
        P(g, x, y, s > j * 0.85 ? 0.5 * (1 - j / 6) : 0);
      }
      const [x, y] = lane(CX, cy, hs, 6.5, s);
      for (const [ox, oy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) g.fr(x + ox, y + oy + drop, T > 0.45 ? 1 : 0, 1);
      return {flash: T > at ? Math.exp(-(T - at) / 0.12) * 0.12 : 0};
    },
    hap: [{t: 0.85, kind: 'light'}, {t: 1.2, kind: 'medium'}],
  },
  // Sun: THE PAGE TURNS. The calendar still shows last week's seventh day. It flips over the rings
  // and leaves a clean page: day 1, the week ahead, today first.
  {
    draw: (g, c) => {
      const T = c.T, x0 = 11, x1 = 33, top = 9, bot = 29, at = 0.8, FL = 0.5;
      const p = cl((T - at) / FL), th = Math.PI * 0.82 * eio(p);
      const cs = Math.cos(th);
      // where the old page's lower edge is now: the new page shows below it
      const edge = top + (bot - top) * Math.max(0, cs);
      const page = (num: string, plan: number[]) => {
        const o: [number, number, number, number][] = [];
        for (let x = x0; x <= x1; x++) for (let y = top; y <= top + 2; y++) o.push([x, y, 0.75, 0]);
        for (let y = top + 3; y <= bot; y++) o.push([x0, y, 0.45, 0], [x1, y, 0.45, 0]);
        for (let x = x0 + 1; x < x1; x++) o.push([x, bot, 0.45, 0]);
        for (const [x, y] of digits(num, CX, 13, 2)) o.push([x - 0.5, y - 0.5, 1, 0]);
        plan.forEach((q, i) => o.push([13 + i * 3, 26, q, 0]));
        return o;
      };
      // the new page: lit cells, hidden where the old page still covers them
      for (const [x, y, b] of page('1', [1, 0.55, 0.18, 0.55, 0.55, 0.18, 0.55])) if (p >= 1 || y > edge || y <= top + 2) g.on(x, y, b);
      g.on(13, 26, p >= 0.85 ? 1 : 0, 1);
      // the old page, free: it turns over the rings and fades as it goes past upright
      for (const [x, y, b] of page('7', [0.8, 0.8, 0.2, 0.8, 0.2, 0.8, 0.8])) {
        const k = (y - top) / (bot - top);
        const xx = CX + (x - CX) * (1 + 0.1 * Math.sin(th) * k);
        P(g, xx, top + (y - top) * cs, p <= 0 ? b : p >= 1 ? 0 : b * cl(0.35 + cs) * (0.65 + 0.35 * cs));
      }
      for (const x of [16, 28]) for (let y = top - 3; y < top + 1; y++) g.on(x, y, 0.9);
      return {flash: p >= 1 ? Math.exp(-(T - at - FL) / 0.12) * 0.12 : 0};
    },
    hap: [{t: 0.8, kind: 'light'}, {t: 1.3, kind: 'medium'}],
  },
];

// ---------- local helpers ----------
/** a ball four cells across, as points around its centre */
const BALL: [number, number][] = [];
for (const oy of [-1.5, -0.5, 0.5, 1.5]) for (const ox of [-1.5, -0.5, 0.5, 1.5]) if (!(Math.abs(ox) === 1.5 && Math.abs(oy) === 1.5)) BALL.push([ox, oy]);
/** swing angles of the cradle's five balls at time T */
function cradle(T: number): number[] {
  const th = [0, 0, 0, 0, 0], A0 = 0.4, HALF = 0.56, t0 = 1.15;
  if (T < 0.75) return th;
  if (T < t0) {
    th[0] = -A0 * eio((T - 0.75) / (t0 - 0.75));
    return th;
  }
  const w = Math.PI / HALF, q = HALF / 2;
  if (T < t0 + q) {
    th[0] = -A0 * Math.cos(w * (T - t0));
    return th;
  }
  const s = T - t0 - q, n = Math.floor(s / HALF), u = (s - n * HALF) / HALF;
  const amp = Math.max(0.06, A0 * Math.pow(0.8, n));
  if (n % 2 === 0) th[4] = amp * Math.sin(Math.PI * u);
  else th[0] = -amp * Math.sin(Math.PI * u);
  return th;
}
/** a chevron pointing right, three across and five down */
const CHEV: [number, number][] = [[0, 0], [1, 1], [2, 2], [3, 3], [2, 4], [1, 5], [0, 6]];
/** a running track: two straights and two half circles */
function stadium(g: G, cx: number, cy: number, hs: number, r: number, b: number) {
  g.line(cx - hs, cy - r, cx + hs, cy - r, b);
  g.line(cx - hs, cy + r, cx + hs, cy + r, b);
  g.ring(cx + hs, cy, r, b, 0, 0, Math.PI);
  g.ring(cx - hs, cy, r, b, 0, Math.PI, TAU);
}
/** a point s cells along a lane of radius m, from the start line (bottom middle), anticlockwise */
function lane(cx: number, cy: number, hs: number, m: number, s: number): [number, number] {
  const Lc = Math.PI * m, tot = 4 * hs + 2 * Lc;
  let d = ((s % tot) + tot) % tot;
  if (d < hs) return [cx + d, cy + m];
  d -= hs;
  if (d < Lc) {
    const a = Math.PI - d / m;
    return [cx + hs + Math.sin(a) * m, cy - Math.cos(a) * m];
  }
  d -= Lc;
  if (d < 2 * hs) return [cx + hs - d, cy - m];
  d -= 2 * hs;
  if (d < Lc) {
    const a = -d / m;
    return [cx - hs + Math.sin(a) * m, cy - Math.cos(a) * m];
  }
  d -= Lc;
  return [cx - hs + d, cy + m];
}
