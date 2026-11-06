/**
 * Matrix Dynamic: comeback ("WELCOME BACK"). One scene per day, Monday first (index 0) to Sunday (index 6).
 * Every day, something that went dark lights back up or starts again, with one satisfying beat, then rests.
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 */
import {CX, CY, G, MScn, back, cl, eio, ez, lerp, spr} from '../mxlib';
import {TAU} from './common';

/** a free particle placed in cell coordinates (x, y may be fractional) */
const F = (g: G, x: number, y: number, b: number, c = 0) => g.fr(x + 0.5, y + 0.5, b, c);
/** a soft bump: 1 at 0, 0 beyond |x| >= 1 */
const bump = (x: number) => (Math.abs(x) >= 1 ? 0 : 0.5 + 0.5 * Math.cos(Math.PI * x));
/** a bump on a loop of n slots */
const bumpLoop = (x: number, n: number) => {
  const d = ((x % n) + n) % n;
  return bump(Math.min(d, n - d));
};

export const SCENES: MScn[] = [
  // Mon: START. A dark start button; one press and it lights, rays fly out and settle round it as a dial
  {
    draw: (g, c) => {
      const T = c.T, P = 0.95, age = T - P;
      const dip = age < 0 ? 0 : age < 0.07 ? age / 0.07 : 1 - spr((age - 0.07) / 0.5, 11, 5.5);
      const on = age >= 0;
      const pre = cl((T - 0.4) / 0.55);
      const R = 10 * (1 - 0.1 * dip);
      // the rim: free, so it can squish under the press
      for (let i = 0; i < 60; i++) {
        const a = (i / 60) * TAU;
        F(g, CX + Math.sin(a) * R, CY - Math.cos(a) * R, on ? 0.9 : 0.3 + 0.12 * pre);
      }
      // the play triangle
      const tb = on ? 1 : 0.24 + 0.16 * pre;
      for (let dy = -4; dy <= 4; dy++) {
        const w = 9 - 2 * Math.abs(dy);
        for (let k = 0; k < w; k++) g.on(CX - 3 + k, CY + dy, tb, on && dy === 0 && k === w - 1 ? 1 : 0);
      }
      // twelve rays: thrown out by the press, then they settle into a dial round the button
      const sweep = T > 1.9 ? ((T - 1.9) / 3.2) * 12 : -99;
      for (let k = 0; k < 12; k++) {
        const a = (k / 12) * TAU;
        const tick = 0.26 + 0.5 * (T > 1.9 ? bumpLoop(sweep - k, 12) : 0);
        for (let j = 0; j < 3; j++) {
          let r = 10, b = 0;
          if (on) {
            const out = 16.5 - j * 1.4;
            const o = ez(age / 0.28), s = eio((age - 0.28) / 0.55);
            r = lerp(lerp(11, out, o), 13.6, s);
            b = lerp(1 - j * 0.22, j === 0 ? tick : 0, s);
          }
          F(g, CX + Math.sin(a) * r, CY - Math.cos(a) * r, b);
        }
      }
      return {o: {stagger: 0.35}, flash: on ? Math.exp(-age / 0.12) * 0.24 : 0};
    },
    hap: [{t: 0.95, kind: 'heavy'}],
  },
  // Tue: a dark panel of tiles flips back on, a wave running out from your tile
  {
    draw: (g, c) => {
      const T = c.T, OI = 2, OJ = 2;
      for (let j = 0; j < 5; j++)
        for (let i = 0; i < 6; i++) {
          const cx = 10 + i * 5, cy = 7 + j * 5, d = Math.hypot(i - OI, j - OJ);
          const th = Math.PI * eio((T - 0.75 - d * 0.085) / 0.38);
          const onFace = th > Math.PI / 2, cs = Math.cos(th), pop = Math.sin(th);
          const me = i === OI && j === OJ;
          const rip = T > 1.8 ? bump((((T - 1.8) % 4.8) * 3 - d) / 1.3) : 0;
          for (let v = -1; v <= 1; v++)
            for (let u = -1; u <= 1; u++) {
              const edge = u !== 0 || v !== 0;
              const b0 = onFace ? 0.7 + 0.22 * rip : edge ? 0.2 : 0;
              F(g, cx + u * cs, cy + v * (1 + 0.16 * pop), Math.min(1, b0 * (1 + 0.5 * pop)), onFace && me && !edge ? 1 : 0);
            }
        }
      return {o: {stagger: 0.3}};
    },
    hap: [{t: 0.75, kind: 'light'}, {t: 1.4, kind: 'success'}],
  },
  // Wed: BACK ONLINE. The signal searches, arc by arc, then connects all at once
  {
    draw: (g, c) => {
      const T = c.T, TC = 1.35, age = T - TC;
      const px = CX, py = 26, RS = [7, 13, 19], span = TAU / 8;
      for (let k = 0; k < 3; k++) {
        let b: number, r: number;
        if (age < 0) {
          const q = (T - 0.45) / 0.22;
          b = 0.16 + (T > 0.45 ? 0.5 * bump((q % 3.6) - k - 0.5) : 0);
          r = RS[k] - 1.4;
        } else {
          const pulse = T > 2.3 ? bump(((T - 2.3) % 3.4) * 4.5 - k - 1) : 0;
          b = 0.84 + 0.16 * pulse;
          r = RS[k] - 1.4 + 1.4 * spr((age - k * 0.05) / 0.42, 12, 5.5);
        }
        for (const dr of [-0.5, 0.5]) {
          const rr = r + dr, n = Math.ceil(((RS[k] + dr) * 2 * span) / 0.9) + 1;
          for (let i = 0; i < n; i++) {
            const a = -span + (2 * span * i) / (n - 1);
            g.fr(px + 0.5 + Math.sin(a) * rr, py + 0.5 - Math.cos(a) * rr, b);
          }
        }
      }
      // the dot: you
      const s = age > 0 ? 1 + 0.35 * Math.exp(-age / 0.15) : 1;
      for (let v = 0; v < 2; v++) for (let u = 0; u < 2; u++) g.fr(px + (u - 0.5) * s + 0.5, py + (v - 0.5) * s + 0.5, age < 0 ? 0.6 : 1, 1);
      return {o: {stagger: 0.3}, flash: age > 0 ? Math.exp(-age / 0.12) * 0.18 : 0};
    },
    hap: [{t: 1.35, kind: 'success'}],
  },
  // Thu: PICK IT UP. The bars are down on the floor; one by one they swing back up, each taller
  {
    draw: (g, c) => {
      const T = c.T, H = [8, 11, 14, 17, 20, 23];
      g.line(7, 30, 37, 30, 0.3);
      for (let i = 0; i < 6; i++) {
        const x0 = 9 + i * 5, p = cl((T - 0.7 - i * 0.17) / 0.45);
        const phi = (-Math.PI / 2) * (1 - back(p, 1.5)), cs = Math.cos(phi), sn = Math.sin(phi);
        const wave = T > 2.5 ? bump(((T - 2.5) % 4.4) * 3 - i) : 0;
        const b = Math.min(1, 0.32 + 0.53 * ez(p) + 0.12 * wave);
        for (let j = 0; j < H[i]; j++)
          for (let u = 0; u < 2; u++) {
            const lx = u + 0.5, ly = -(j + 0.5);
            g.fr(x0 + lx * cs - ly * sn, 30 + lx * sn + ly * cs, b, i === 5 && j === H[i] - 1 && u === 1 ? 1 : 0);
          }
      }
      return {o: {stagger: 0.3}};
    },
    hap: [{t: 1.05, kind: 'light'}, {t: 1.39, kind: 'light'}, {t: 1.73, kind: 'medium'}, {t: 1.9, kind: 'heavy'}],
  },
  // Fri: SLINGSHOT. The arrow is drawn back on its band, then let go: it launches higher than it started
  {
    draw: (g, c) => {
      const T = c.T, TR = 1.4, age = T - TR;
      const ax = CX + 0.5, A = [11.5, 24.5], B = [33.5, 24.5];
      g.line(11, 24, 11, 27, 0.45);
      g.line(33, 24, 33, 27, 0.45);
      let tip: number, my: number;
      if (age < 0) {
        tip = lerp(11, 18.5, eio((T - 0.65) / 0.7));
        my = tip + 13.5;
      } else {
        tip = lerp(18.5, 7.5, spr(age / 0.45, 10, 6));
        my = 24.5 + 7.5 * Math.exp(-age / 0.1) * Math.cos(age * 24);
      }
      // the band
      for (let i = 0; i < 10; i++) g.fr(lerp(A[0], ax, i / 10), lerp(A[1], my, i / 10), 0.5);
      for (let i = 0; i <= 10; i++) g.fr(lerp(ax, B[0], i / 10), lerp(my, B[1], i / 10), 0.5);
      // the arrow: a head on a three-wide shaft; a light runs up it now and then
      const ab = age < 0 ? 0.55 + 0.35 * cl((T - 0.65) / 0.7) : 1;
      const run = T > 2.4 ? ((T - 2.4) % 3.6) * 22 : -99;
      for (let r = 0; r < 14; r++) {
        const w = r < 4 ? 2 * r + 1 : 3, glow = 0.25 * bump((13 - r - run) / 2.5);
        for (let k = 0; k < w; k++) g.fr(ax + k - (w - 1) / 2, tip + r, Math.min(1, ab + glow), r === 0 ? 1 : 0);
      }
      // speed lines off the tail
      for (let k = 0; k < 5; k++) g.fr(ax + (k % 2 ? 1 : -1) * (1 + (k % 3) * 0.6), tip + 14.5 + k * 1.6, age > 0 ? (1 - k / 5) * 0.6 * Math.exp(-age / 0.22) : 0);
      return {o: {stagger: 0.3}, flash: age > 0 ? Math.exp(-age / 0.12) * 0.15 : 0, shake: age > 0 && age < 0.14 ? 0.2 : 0};
    },
    hap: [{t: 0.65, kind: 'light'}, {t: 1.4, kind: 'heavy'}],
  },
  // Sat: THE WHEEL TURNS AGAIN. A still flywheel gets one hard push, spins up, then cruises
  {
    draw: (g, c) => {
      const T = c.T, K = 0.75, u = Math.max(0, T - K), go = T > K;
      const wc = 0.75, wp = 4.2, tau = 0.32;
      const th = 0.2 + (go ? wc * u + wp * Math.E * tau * (1 - (1 + u / tau) * Math.exp(-u / tau)) : 0);
      const w = go ? wc + wp * (u / tau) * Math.exp(1 - u / tau) : 0;
      const lit = go ? ez(u / 0.5) : 0;
      for (let i = 0; i < 64; i++) F(g, CX + Math.sin((i / 64) * TAU) * 12, CY - Math.cos((i / 64) * TAU) * 12, 0.3 + 0.5 * lit);
      g.disc(CX, CY, 1.8, 0.5 + 0.4 * lit);
      const blur = cl((w - 1.2) / 3);
      for (let s = 0; s < 5; s++)
        for (let m = 0; m < 4; m++) {
          const a = th + (s / 5) * TAU - m * 0.075 * w;
          const b = m === 0 ? 0.4 + 0.5 * lit : (0.55 - m * 0.14) * blur;
          for (let j = 0; j < 9; j++) {
            const r = 2.6 + j * 1.05;
            F(g, CX + Math.sin(a) * r, CY - Math.cos(a) * r, b);
          }
        }
      const va = th + TAU / 10;
      F(g, CX + Math.sin(va) * 10, CY - Math.cos(va) * 10, 1, 1);
      return {o: {stagger: 0.3}, flash: go ? Math.exp(-u / 0.12) * 0.12 : 0};
    },
    hap: [{t: 0.75, kind: 'heavy'}],
  },
  // Sun: today checks in at the end of an empty week; the light carries over and next week lights up
  {
    draw: (g, c) => {
      const T = c.T, TC = 0.85, age = T - TC, TA = 1.72;
      const X = (i: number) => 9 + i * 4, YA = 16, YB = 25;
      const breath = T > 2.2 ? 0.1 * (0.5 + 0.5 * Math.sin((T - 2.2) * 1.6)) : 0;
      // the old habit, then the weeks away
      const old = [1, 1, 0, 1, 1, 0, 0];
      for (let i = 0; i < 7; i++) g.rect(X(i), 4, 3, 3, old[i] ? 0.6 : 0.32, !!old[i]);
      for (let i = 0; i < 7; i++) g.rect(X(i), 10, 3, 3, 0.3);
      // this week: nothing yet, until today
      for (let i = 0; i < 6; i++) g.rect(X(i), YA, 3, 3, 0.32);
      // today: a firm pop as it checks in
      const pop = age > 0 ? 1 + 0.45 * Math.exp(-age / 0.12) * Math.cos(age * 18) : 1;
      for (let v = -1; v <= 1; v++)
        for (let u = -1; u <= 1; u++) {
          const edge = u !== 0 || v !== 0;
          const b = age > 0 ? 0.92 + breath : edge ? 0.32 + 0.4 * cl((T - 0.4) / 0.45) : 0;
          F(g, X(6) + 1 + u * pop, YA + 1 + v * pop, Math.min(1, b), age > 0 && !edge ? 1 : 0);
        }
      // the check-in ripple
      for (let w = 0; w < 2; w++) {
      const aw = age - w * 0.12, s = 1.5 + 6 * ez(aw / 0.55), rb = aw > 0 ? (0.85 - w * 0.3) * cl(1 - aw / 0.55) : 0;
      for (let k = 0; k < 20; k++) {
        const q = k / 20, side = Math.floor(q * 4), f = (q * 4) % 1 * 2 - 1;
        const dx = side === 0 ? f : side === 1 ? 1 : side === 2 ? -f : -1, dy = side === 0 ? -1 : side === 1 ? f : side === 2 ? 1 : -f;
        F(g, X(6) + 1 + dx * s, YA + 1 + dy * s, rb);
      }
      }
      // the light carries over: down, back along, into next Monday
      const path: [number, number][] = [[X(6) + 1, YA + 3], [X(6) + 1, 21.5], [X(0) + 1, 21.5], [X(0) + 1, YB - 1]];
      const seg = path.slice(1).map((p, i) => Math.hypot(p[0] - path[i][0], p[1] - path[i][1]));
      const L = seg.reduce((a, b) => a + b, 0);
      const at = (d: number): [number, number] => {
        let k = 0;
        d = Math.max(0, Math.min(L, d));
        while (k < seg.length - 1 && d > seg[k]) d -= seg[k++];
        const f = d / seg[k];
        return [lerp(path[k][0], path[k + 1][0], f), lerp(path[k][1], path[k + 1][1], f)];
      };
      const head = L * eio((T - 1.05) / 0.67);
      for (let d = 0; d <= L; d += 2) if (d < head - 1) {
        const [x, y] = at(d);
        g.on(x, y, 0.36);
      }
      for (let k = 0; k < 6; k++) {
        const d = head - k * 1.1, [x, y] = at(d);
        F(g, x, y, T > 1.05 && T < TA + 0.1 && d > 0 ? (1 - k * 0.15) * cl((TA + 0.1 - T) / 0.1) : 0);
      }
      // next week: Monday first, then the planned days
      const plan = [0, 1, 3, 4, 5];
      for (let i = 0; i < 7; i++) {
        if (i === 0 && T > TA) g.rect(X(0), YB, 3, 3, 0.9 + breath, true);
        else {
          const k = plan.indexOf(i), lt = k > 0 ? cl((T - TA - 0.05 - k * 0.07) / 0.15) : 0;
          g.rect(X(i), YB, 3, 3, 0.32 + 0.48 * lt);
        }
      }
      return {o: {stagger: 0.3}, flash: age > 0 ? Math.exp(-age / 0.12) * 0.2 : 0};
    },
    hap: [{t: 0.85, kind: 'heavy'}, {t: 1.72, kind: 'light'}],
  },
];
