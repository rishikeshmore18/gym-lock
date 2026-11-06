/**
 * Matrix Dynamic: drift ("WEEK 4"). One scene per day, Monday first (index 0) to Sunday (index 6).
 * Every day shows the drift once, slow enough to see, then the correction, quick and firm; then it holds.
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 */
import {CX, CY, G, MScn, back, cl, eio, ez, lerp, spr} from '../mxlib';
import {TAU} from './common';

/** a free particle placed in cell coordinates (x, y may be fractional) */
const F = (g: G, x: number, y: number, b: number, c = 0) => g.fr(x + 0.5, y + 0.5, b, c);
/** a soft bump: 1 at 0, 0 beyond |x| >= 1 */
const bump = (x: number) => (Math.abs(x) >= 1 ? 0 : 0.5 + 0.5 * Math.cos(Math.PI * x));
const DEG = Math.PI / 180;

// Fri: the navigation arrow
const NAV = ['....#....', '...###...', '...###...', '..#####..', '..#####..', '.#######.', '.#######.', '#########', '###...###'];

// Sat: a running track (two straights, two bends), by distance along it
const TR = {a: 6, R: 8};
const TL = 4 * TR.a + 2 * Math.PI * TR.R;
const track = (s: number, off = 0): [number, number] => {
  const {a, R} = TR, half = Math.PI * R, Q = R + off;
  s = ((s % TL) + TL) % TL;
  if (s < a) return [CX + s, CY + Q];
  s -= a;
  if (s < half) {
    const t = s / R;
    return [CX + a + Math.sin(t) * Q, CY + Math.cos(t) * Q];
  }
  s -= half;
  if (s < 2 * a) return [CX + a - s, CY - Q];
  s -= 2 * a;
  if (s < half) {
    const t = s / R;
    return [CX - a - Math.sin(t) * Q, CY - Math.cos(t) * Q];
  }
  s -= half;
  return [CX - a + s, CY + Q];
};

export const SCENES: MScn[] = [
  // Mon: THE GAUGE. The needle sags slowly into the drift zone, then is pushed back up hard
  {
    draw: (g, c) => {
      const T = c.T, gx = CX, gy = 20, TC = 2.05;
      const ang = (v: number) => (-125 + (v / 5) * 250) * DEG;
      const v = T < TC ? 3.7 - 2.9 * eio((T - 0.65) / 1.35) : 0.8 + 2.9 * spr((T - TC) / 0.6, 10, 5.2);
      const arc = (r: number, v0: number, v1: number, n: number, b: number) => {
        for (let i = 0; i < n; i++) {
          const a = lerp(ang(v0), ang(v1), n > 1 ? i / (n - 1) : 0);
          F(g, gx + Math.sin(a) * r, gy - Math.cos(a) * r, b);
        }
      };
      arc(12, 1.4, 5, 44, 0.5);
      for (let k = 0; k <= 5; k++) {
        const a = ang(k);
        for (const r of [13.7, 14.7]) g.on(gx + Math.sin(a) * r, gy - Math.cos(a) * r, k <= 1 ? 0.3 : 0.62);
      }
      // the drift zone: dashed, and it lights up while the needle is in it
      const zone = cl((1.7 - v) / 0.6);
      arc(12, 0, 1.2, 7, 0.24 + 0.46 * zone);
      arc(10.6, 0.1, 1.2, 6, 0.1 + 0.42 * zone);
      const a = ang(v), nb = T < TC ? 1 - 0.35 * cl((3 - v) / 1.8) : 1;
      for (let j = 0; j < 9; j++) {
        const r = 1.6 + j;
        F(g, gx + Math.sin(a) * r, gy - Math.cos(a) * r, nb, j === 8 ? 1 : 0);
      }
      g.disc(gx, gy, 1.6, 0.9);
      return {o: {stagger: 0.3}, flash: T > TC ? Math.exp(-(T - TC) / 0.12) * 0.15 : 0};
    },
    hap: [{t: 2.05, kind: 'heavy'}],
  },
  // Tue: FOCUS. Week four's row goes soft and fades; focus brackets close in and it snaps sharp
  {
    draw: (g, c) => {
      const T = c.T, TL2 = 2.0;
      const X = (i: number) => 12 + i * 5, Y = (j: number) => 6 + j * 6;
      for (let j = 0; j < 3; j++) for (let i = 0; i < 5; i++) g.rect(X(i) - 1, Y(j) - 1, 3, 3, 0.62, true);
      const bl = T < TL2 ? eio((T - 0.6) / 1.1) : 1 - spr((T - TL2) / 0.4, 12, 6);
      const DX = [-0.6, 0.4, -0.2, 0.7, -0.5], DY = [0.5, -0.4, 0.6, -0.3, 0.4];
      for (let i = 0; i < 5; i++)
        for (let v = -1; v <= 1; v++)
          for (let u = -1; u <= 1; u++) {
            const s = 1 + 0.75 * bl;
            const b = T > TL2 ? 0.62 + 0.38 * Math.exp(-(T - TL2) / 0.4) : 0.62 * (1 - 0.62 * bl);
            F(g, X(i) + u * s + DX[i] * 1.6 * bl, Y(3) + v * s + DY[i] * 1.4 * bl, b, i === 2 && u === 0 && v === 0 ? 1 : 0);
          }
      // the brackets: in from wide, then lock round the row
      const p = back(cl((T - 1.15) / 0.8), 1.2);
      const L = lerp(7, 9, p), R = lerp(37, 35, p), Tp = lerp(1, 21, p), B = lerp(33, 27, p);
      const bb = T < TL2 ? 0.8 * cl((T - 1.1) / 0.3) : 0.55 + 0.45 * Math.exp(-(T - TL2) / 0.25);
      for (const [cx, cy, sx, sy] of [[L, Tp, 1, 1], [R, Tp, -1, 1], [L, B, 1, -1], [R, B, -1, -1]] as const) {
        F(g, cx, cy, bb);
        for (let k = 1; k <= 2; k++) {
          F(g, cx + sx * k, cy, bb);
          F(g, cx, cy + sy * k, bb);
        }
      }
      return {o: {stagger: 0.3}};
    },
    hap: [{t: 2.0, kind: 'medium'}],
  },
  // Wed: THE MIDDLE. Your line rides the plan, sags off it once through the middle, then climbs back onto it
  {
    draw: (g, c) => {
      const T = c.T, x0 = 8, x1 = 36, MZ = 6, base = CY - 2;
      const dip = (x: number) => Math.exp(-(((x - CX - 0.5) / 4.2) ** 2));
      const you = (x: number) => base + 8 * dip(x);
      // the middle, marked top and bottom
      for (const [mx, s] of [[CX - MZ, 1], [CX + MZ, -1]]) {
        g.line(mx, base - 6, mx, base - 4, 0.36);
        g.on(mx + s, base - 6, 0.36);
        g.line(mx, base + 10, mx, base + 12, 0.36);
        g.on(mx + s, base + 12, 0.36);
      }
      // the plan: a dotted straight line
      for (let x = x0; x <= x1; x += 2) g.on(x, base, 0.36);
      const u = cl((T - 0.35) / 2.3), pen = x0 + (x1 - x0) * (u + 0.08 * Math.sin(u * TAU));
      const run = T > 3.2 ? x0 + ((T - 3.2) % 5) * 16 : -99;
      // your line: free dots every half cell, drawn as the pen passes
      for (let i = 0; i <= 56; i++) {
        const x = x0 + i * 0.5, b = x <= pen ? Math.min(1, 0.85 + 0.15 * bump((x - run) / 3)) : 0;
        F(g, x, you(x), b);
      }
      const struggle = 1 - 0.35 * dip(pen);
      for (let k = 0; k < 4; k++) {
        const x = Math.max(x0, pen - k * 0.6);
        F(g, x, you(x), k === 0 ? struggle : (0.6 - k * 0.15) * struggle, k === 0 ? 1 : 0);
      }
      return {o: {stagger: 0.3}};
    },
    hap: [{t: 2.12, kind: 'medium'}],
  },
  // Thu: HOLD THE LINE. Most people slide from three a week to one; your week four sags toward them, then pushes back
  {
    draw: (g, c) => {
      const T = c.T, TC = 1.95, X = (i: number) => 9 + i * 5;
      g.line(7, 30, 37, 30, 0.3);
      // the line you hold: three a week; a light runs along it when you get back to it
      const sw = T > TC ? 7 + (T - TC) * 34 : -99;
      for (let x = 7; x <= 37; x += 2) g.on(x, 11, 0.3 + 0.6 * bump((x - sw) / 4) + (T > TC + 1 ? 0.12 : 0));
      // most people: a thin dim bar beside yours, falling from three a week to one
      const H = [3, 3, 2.5, 2, 1.5, 1];
      for (let i = 0; i < 6; i++) g.line(X(i) + 3, 29, X(i) + 3, 30 - Math.round(6 * H[i]), 0.26);
      // your weeks: held at three; the weeks ahead are dotted
      for (let i = 0; i < 3; i++) g.rect(X(i), 12, 2, 18, 0.55, true);
      for (let i = 4; i < 6; i++) for (let y = 12; y < 30; y += 2) g.line(X(i), y, X(i) + 1, y, 0.22);
      const h = T < TC ? 18 - 7 * eio((T - 0.7) / 1.15) : 11 + 7 * spr((T - TC) / 0.5, 11, 6);
      const top = 30 - h, wb = T < TC ? 0.66 - 0.2 * cl((18 - h) / 7) : 0.82;
      for (let y = Math.floor(top) + 1; y < 30; y++) g.rect(X(3), y, 2, 1, wb, true);
      for (let u = 0; u < 2; u++) F(g, X(3) + u, top, 1, u === 1 ? 1 : 0);
      return {o: {stagger: 0.3}, flash: T > TC ? Math.exp(-(T - TC) / 0.12) * 0.12 : 0};
    },
    hap: [{t: 1.95, kind: 'heavy'}],
  },
  // Fri: STAY THE COURSE. Your arrow drifts off the line, steers back onto it, and the way ahead clears
  {
    draw: (g, c) => {
      const T = c.T, TC = 1.75;
      const pos = (t: number): [number, number] => {
        const d = t < TC ? eio((t - 0.75) / 0.9) : 1 - spr((t - TC) / 0.6, 9, 5.5);
        return [CX + 7 * d, 28 - 11 * eio((t - 0.5) / 2.7)];
      };
      const [ax, ay] = pos(T), [bx, by] = pos(T + 0.05);
      const psi = Math.max(-0.7, Math.min(0.7, Math.atan2(bx - ax, ay - by + 0.004)));
      // the course: faint ahead (fog) until you are back on it, then it clears up the board
      const lift = T > TC + 0.35 ? (T - TC - 0.35) * 28 : -1;
      const pulse = T > 3.4 ? ((T - 3.4) % 4) * 14 : -99;
      for (let y = 2; y <= 32; y++) {
        if (y % 4 >= 2) continue;
        const ahead = ay - y;
        const b = ahead < -4 ? 0.42 : ahead < lift ? 0.42 + 0.35 * bump((ahead - pulse) / 3) : 0.12;
        g.on(CX, y, b);
      }
      // the drift, as a fading trail
      for (let k = 1; k <= 8; k++) {
        const [tx, ty] = pos(T - k * 0.07), [ux, uy] = pos(T - k * 0.07 + 0.02);
        const sp = Math.hypot(ux - tx, uy - ty) / 0.02;
        F(g, tx, ty + 4, 0.38 * (1 - k / 9) * cl(sp / 3));
      }
      const cs = Math.cos(psi), sn = Math.sin(psi);
      NAV.forEach((row, j) =>
        [...row].forEach((ch, i) => {
          if (ch !== '#') return;
          const lx = i - 4, ly = j - 4;
          F(g, ax + lx * cs - ly * sn, ay + lx * sn + ly * cs, 1, j === 0 ? 1 : 0);
        }),
      );
      return {o: {stagger: 0.3}};
    },
    hap: [{t: 0.8, kind: 'light'}, {t: 2.05, kind: 'medium'}],
  },
  // Sat: THE PACER. A pacing light laps the track; you drop back off it, the gap glows, then you close it and tuck in
  {
    draw: (g, c) => {
      const T = c.T, v = TL / 7, sP = 2 + v * T, TC = 2.3, lock = 2.55;
      const gap = T < TC ? 7 + 19 * eio((T - 0.8) / 1.4) : 26 - 19 * spr((T - TC) / 0.7, 8, 5);
      const sY = sP - gap, open = cl((gap - 9) / 6);
      const hit = T > lock ? Math.exp(-(T - lock) / 0.3) : 0;
      // the lane: two lines; the stretch between you and the pacer lights up while you are dropped
      for (let s = 0; s < TL; s += 1)
        for (const off of [-1.3, 1.3]) {
          const [x, y] = track(s, off);
          const rel = (((sP - s) % TL) + TL) % TL;
          g.on(x, y, rel > 7 && rel < gap ? 0.34 + 0.36 * open : 0.34);
        }
      // the pacer: a glowing band, two dots wide, bright head and fading tail
      for (let k = 0; k < 9; k++)
        for (const off of [-0.45, 0.45]) {
          const [x, y] = track(sP - k * 0.75, off);
          F(g, x - 0.5, y - 0.5, Math.min(1, (1 - k * 0.095) * (0.9 + 0.3 * hit)));
        }
      // you, with a short tail
      for (let k = 3; k >= 0; k--) {
        const [x, y] = track(sY - k * 0.7);
        F(g, x - 0.5, y - 0.5, k === 0 ? 1 : 0.6 - k * 0.14, k === 0 ? 1 : 0);
      }
      return {o: {stagger: 0.3}, flash: hit * 0.12};
    },
    hap: [{t: 2.55, kind: 'medium'}],
  },
  // Sun: THE PLAN. Day after day the session slips later and fades; then all five snap back onto the plan line
  {
    draw: (g, c) => {
      const T = c.T, TC = 2.1, X = (i: number) => 9 + i * 4, PL = 10;
      const back2 = T > TC ? 1 : 0;
      // the week: seven day columns, the hours running down them (later is lower)
      for (let i = 0; i < 7; i++) {
        g.line(X(i), 6, X(i) + 2, 6, i < 5 ? 0.55 : 0.3);
        for (let y = 14; y <= 29; y += 3) g.on(X(i) + 1, y, 0.14);
      }
      // the plan line, 07:00
      const sw = T > TC + 0.15 ? 6 + (T - TC - 0.15) * 40 : -99;
      for (let x = 7; x <= 37; x++) g.on(x, PL, Math.min(1, 0.4 + 0.55 * bump((x - sw) / 4) + 0.1 * back2));
      for (let k = 0; k < 5; k++) {
        const slip = T < TC ? eio((T - 0.6 - k * 0.2) / 0.8) : 1 - spr((T - TC - k * 0.04) / 0.42, 10, 5.5);
        const dy = slip * (2.5 + 2.6 * k);
        const b = 0.92 - 0.42 * cl(slip) * (0.4 + 0.15 * k);
        // a drop line shows how far it slipped
        for (let y = PL + 2; y < PL + dy - 1; y++) g.on(X(k) + 1, y, 0.3);
        for (let vv = -1; vv <= 1; vv++) for (let uu = 0; uu < 3; uu++) F(g, X(k) + uu, PL + vv + dy, b, k === 4 && uu === 1 && vv === 0 ? 1 : 0);
      }
      return {o: {stagger: 0.3}, flash: T > TC ? Math.exp(-(T - TC) / 0.12) * 0.14 : 0};
    },
    hap: [{t: 0.6, kind: 'light'}, {t: 2.1, kind: 'heavy'}],
  },
];
