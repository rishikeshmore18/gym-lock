/**
 * Matrix Dynamic: setup. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * The card lists three tappable items (Apps locked, Alarm ready, Gym selected); c.d.setupDone is
 * bool[3]. Every scene shows how many are done and pays off when the third one is set.
 * A small tracker below remembers when each item last changed, so taps animate (and the entrance
 * lights the done items one after another once the dots have flown in).
 */
import {G, MC, MScn, cl, eio, ez, lerp, spr} from '../mxlib';
import {TAU} from './common';

// ---------- tap tracker ----------
const NEVER = -1e4;
type Mem = {t: number; T: number; on: boolean[]; at: number[]};
const MEM = new Map<number, Mem>();
/** remembers, per day, when each item last flipped. A fresh entry (T went back, or a gap in frames)
 *  restarts it: items already done then light in sequence after the dots have flown in. */
const track = (c: MC): Mem => {
  const on = [0, 1, 2].map((i) => !!c.d.setupDone[i]);
  let m = MEM.get(c.day);
  if (!m || c.T < m.T - 1e-4 || c.t < m.t - 1e-4 || c.t - m.t > 0.5) {
    let k = 0;
    m = {t: c.t, T: c.T, on, at: on.map((v) => (v ? c.t + 0.5 + 0.24 * k++ : NEVER))};
    MEM.set(c.day, m);
  }
  for (let i = 0; i < 3; i++) if (on[i] !== m.on[i]) m.at[i] = c.t;
  m.on = on;
  m.t = c.t;
  m.T = c.T;
  return m;
};
/** item i's progress toward its current state (0 = off, 1 = on), eased over dur seconds */
const prog = (m: Mem, c: MC, i: number, dur: number, f: (x: number) => number = ez) => {
  const a = (c.t - m.at[i]) / dur;
  return m.on[i] ? (a < 0 ? 0 : f(a)) : 1 - f(Math.max(0, a));
};
/** springy version (overshoots), over about a second */
const progS = (m: Mem, c: MC, i: number, w = 12, z = 6.5) => {
  const a = c.t - m.at[i];
  return m.on[i] ? (a < 0 ? 0 : spr(a, w, z)) : 1 - spr(Math.max(0, a), w, z);
};
/** seconds since the third item was set (negative: not all three yet / still to come) */
const allAge = (m: Mem, c: MC) => (m.on.every(Boolean) ? c.t - Math.max(...m.at) : -1);
/** seconds since the most recent change */
const lastAt = (m: Mem) => Math.max(...m.at);
const lastOn = (m: Mem) => {
  let k = -1, best = -Infinity;
  for (let i = 0; i < 3; i++) if (m.on[i] && m.at[i] > best) (best = m.at[i]), (k = i);
  return k;
};

// ---------- small glyphs (7 wide) ----------
const GL: Record<string, string[]> = {
  lock: ['..###..', '.#...#.', '.#...#.', '#######', '###.###', '###.###', '#######'],
  bell: ['...#...', '..###..', '.#####.', '.#####.', '.#####.', '#######', '...#...'],
  pin: ['.#####.', '##...##', '##...##', '##...##', '.#####.', '..###..', '...#...'],
  check: ['......#', '.....##', '#...##.', '##.##..', '.###...', '..#....'],
};
const has = (rows: string[], i: number, j: number) => j >= 0 && j < rows.length && i >= 0 && i < rows[j].length && rows[j][i] === '#';
/** 3 x 5 day letters */
const DL: Record<string, string[]> = {
  M: ['#.#', '###', '###', '#.#', '#.#'],
  T: ['###', '.#.', '.#.', '.#.', '.#.'],
  W: ['#.#', '#.#', '###', '###', '#.#'],
  F: ['###', '#..', '##.', '#..', '#..'],
  S: ['.##', '#..', '.#.', '..#', '##.'],
};
const letter = (g: G, ch: string, x: number, y: number, b: number) => DL[ch].forEach((r, j) => [...r].forEach((q, i) => q === '#' && g.on(x + i, y + j, b)));

export const SCENES: MScn[] = [
  // Mon: THE READINESS DIAL. A gauge in three segments; the needle swings one third per item.
  // The third slams it to the stop: flash, the ticks shoot out, the segments fuse into one arc.
  {
    draw: (g, c) => {
      const m = track(c);
      const cx = 22.5, cy = 20.5, R = 12, A0 = -2.2, A1 = 2.2, span = A1 - A0;
      let Lf = 0, Ln = 0;
      for (let i = 0; i < 3; i++) {
        Lf += prog(m, c, i, 0.42, eio);
        Ln += progS(m, c, i, 11, 5.5);
      }
      const n = m.on.filter(Boolean).length, a3 = allAge(m, c), all = a3 >= 0;
      const fuse = all ? ez((a3 - 0.08) / 0.3) : 0;
      // after the payoff, a slow light runs along the full arc every 4.5 s
      const sw = all && a3 > 1.2 ? ((a3 - 1.2) % 4.5) / 1.3 : -1;
      const nextSeg = Math.min(2, Math.floor(Lf + 1e-3));
      const breath = 0.5 - 0.5 * Math.cos(c.t * 2.2);
      const N = 120;
      for (let k = 0; k <= N; k++) {
        const u = (3 * k) / N, si = Math.min(2, Math.floor(u)), fr = u - si;
        const a = A0 + (span * k) / N;
        const gapC = (fr < 0.06 && si > 0) || (fr > 0.94 && si < 2);
        const lit = u <= Lf + 0.02;
        let b = lit ? 0.85 : !all && si === nextSeg ? 0.3 + 0.12 * breath : 0.3;
        if (gapC) b = lit ? 0.78 * fuse : 0;
        if (sw >= 0 && sw <= 1) b = Math.min(1, b + 0.22 * Math.exp(-((u / 3 - sw) ** 2) / 0.006));
        if (b <= 0.01) continue;
        for (const r of [R, R - 1]) g.on(cx + Math.sin(a) * r, cy - Math.cos(a) * r, b);
      }
      // ticks
      for (let j = 0; j <= 12; j++) {
        const a = A0 + (span * j) / 12, lit = j / 4 <= Lf + 0.02;
        const b = lit ? 0.55 : 0.22;
        g.on(cx + Math.sin(a) * (R + 2), cy - Math.cos(a) * (R + 2), b);
        if (j % 4 === 0) g.on(cx + Math.sin(a) * (R + 3), cy - Math.cos(a) * (R + 3), b);
      }
      // readout under the hub (an LED digit that flips in place)
      // hub
      g.disc(cx, cy, 1.6, 1);
      // the needle (free particles: it swings)
      const na = Math.min(A1 + 0.06, A0 + (span * Math.max(0, Ln)) / 3);
      for (let j = 0; j < 8; j++) {
        const r = 2.2 + j * 0.95;
        g.fr(cx + Math.sin(na) * r, cy - Math.cos(na) * r, j === 7 ? 1 : 0.92, j === 7 ? 1 : 0);
      }
      // the payoff: every tick throws a short ray outward
      for (let j = 0; j <= 12; j++) {
        const a = A0 + (span * j) / 12, p = all ? a3 / 0.75 : 2;
        const on = p >= 0 && p <= 1, r = R + 3.5 + ez(p) * 9;
        for (let s = 0; s < 2; s++) g.fr(cx + Math.sin(a) * (r + s * 1.3), cy - Math.cos(a) * (r + s * 1.3), on ? (1 - p) * (1 - s * 0.35) : 0);
      }
      return {flash: all ? 0.26 * Math.exp(-a3 / 0.12) : 0, shake: all ? 0.22 * Math.exp(-a3 / 0.09) : 0};
    },
  },

  // Tue: CONTROL CENTRE. Three toggle tiles (lock, alarm, pin) switch on with a ripple; the fourth
  // tile is "ready": when the third goes on, dots stream out of all three and build its tick.
  {
    draw: (g, c) => {
      const m = track(c);
      const S = 11, X = [11, 24, 11, 24], Y = [6, 6, 19, 19], icons = ['lock', 'bell', 'pin'];
      const a3 = allAge(m, c), all = a3 >= 0;
      const corner = (i: number, j: number) => (i === 0 || i === S - 1) && (j === 0 || j === S - 1);
      for (let k = 0; k < 3; k++) {
        const p = prog(m, c, k, 0.32, eio), ic = GL[icons[k]];
        const ox = X[k] + 2, oy = Y[k] + 2 + (icons[k] === 'check' ? 1 : 0);
        for (let j = 0; j < S; j++)
          for (let i = 0; i < S; i++) {
            if (corner(i, j)) continue;
            const edge = i === 0 || j === 0 || i === S - 1 || j === S - 1;
            const isIc = has(ic, X[k] + i - ox, Y[k] + j - oy);
            const d = Math.hypot(i - 5, j - 5);
            const filled = p > 0 && d <= p * 8.2;
            const b = filled ? (isIc ? 0 : 0.86) : isIc ? 0.6 : edge ? 0.26 : 0;
            if (b > 0) g.on(X[k] + i, Y[k] + j, b);
          }
      }
      // the ready tile: dashed until all three are on, then its outline lights and the tick is built
      const rx = X[3], ry = Y[3], ring = all ? ez(a3 / 0.5) : 0;
      for (let j = 0; j < S; j++)
        for (let i = 0; i < S; i++) {
          if (corner(i, j)) continue;
          const edge = i === 0 || j === 0 || i === S - 1 || j === S - 1;
          if (!edge) continue;
          const ang = (Math.atan2(i - 5, -(j - 5)) / TAU + 1) % 1;
          const b = ring > 0 && ang <= ring ? 0.86 : (i + j) % 2 ? 0 : 0.2;
          if (b > 0) g.on(rx + i, ry + j, b);
        }
      const ck: [number, number][] = [];
      GL.check.forEach((r, j) => [...r].forEach((q, i) => q === '#' && ck.push([rx + 2 + i + 0.5, ry + 3 + j + 0.5])));
      ck.sort((a, b) => a[0] - b[0]);
      if (!all) ck.forEach(([x, y]) => g.on(x, y, 0.14));
      ck.forEach(([x, y], j) => {
        const src = j % 3, sx = X[src] + 5.5, sy = Y[src] + 5.5;
        const q = all ? eio((a3 - 0.06 - j * 0.035) / 0.42) : 0;
        g.fr(lerp(sx, x, q), lerp(sy, y, q) - Math.sin(q * Math.PI) * 2, all && q > 0 ? 0.35 + 0.65 * q : 0);
      });
      // status light: the last piece
      g.on(rx + S - 3, ry + 2, all ? 1 : 0.55, 1);
      return {flash: all ? 0.2 * Math.exp(-a3 / 0.13) : 0};
    },
  },

  // Wed: THE TRACE. A monitor line with three beat slots; each item puts a beat in its slot.
  // The third beat brings it to life: the sweep starts and runs every few seconds.
  {
    draw: (g, c) => {
      const m = track(c);
      const y0 = 18.5, X0 = 8, X1 = 37, SX = [12.5, 21.5, 30.5];
      const a3 = allAge(m, c), all = a3 >= 0;
      const P = SX.map((_, i) => progS(m, c, i, 14, 7));
      // spike template: [dx, dy per unit height, dy fixed scale]
      const tmpl = (H: number, h: number): [number, number][] => [[-2, 0], [-1, 0.9 * h], [0, -H], [1, 3.2 * h], [2, 0], [3.5, -1.7 * h], [5, 0]];
      const yAt = (x: number) => {
        for (let i = 0; i < 3; i++) {
          const dx = x - SX[i];
          if (dx < -2 || dx > 5) continue;
          const T = tmpl(10.5 * P[i], cl(P[i]));
          for (let k = 0; k < T.length - 1; k++)
            if (dx >= T[k][0] && dx <= T[k + 1][0]) return y0 + lerp(T[k][1], T[k + 1][1], (dx - T[k][0]) / (T[k + 1][0] - T[k][0]));
        }
        return y0;
      };
      // sweep: head runs 8 -> 37 in 1.7 s, every 3.8 s
      const cyc = all ? a3 % 3.8 : -1, xh = all ? (cyc < 1.7 ? lerp(X0, X1, ez(cyc / 1.7) * 0.25 + (cyc / 1.7) * 0.75) : X1) : X0;
      const glow = (x: number) => {
        if (!all) return 0;
        const d = xh - x;
        return d >= 0 && d < 12 && cyc < 2.6 ? (1 - d / 12) * (cyc < 1.7 ? 1 : 1 - (cyc - 1.7) / 0.9) : 0;
      };
      const base = all ? 0.55 : 0.45;
      // flat stretches: snapped
      for (let x = X0; x <= X1; x++) {
        const nearDone = SX.some((s, i) => x + 0.5 - s >= -1.5 && x + 0.5 - s <= 2.5 && P[i] > 0.04);
        if (!nearDone) g.on(x, y0, Math.min(1, base + 0.45 * glow(x + 0.5)));
      }
      // empty slots: a faint ghost of the beat that belongs there
      SX.forEach((s, i) => {
        if (m.on[i] && P[i] > 0.6) return;
        const T = tmpl(10.5, 1);
        for (let k = 0; k < T.length - 1; k++) {
          const n = 10;
          for (let q = 0; q <= n; q++) g.on(s + lerp(T[k][0], T[k + 1][0], q / n), y0 + lerp(T[k][1], T[k + 1][1], q / n), 0.12);
        }
      });
      // beats: fixed particle counts per stroke
      const SEG = [2, 12, 15, 4, 3, 3];
      SX.forEach((s, i) => {
        const T = tmpl(10.5 * P[i], cl(P[i])), on = P[i] > 0.02;
        for (let k = 0; k < T.length - 1; k++)
          for (let q = 0; q < SEG[k]; q++) {
            const x = s + lerp(T[k][0], T[k + 1][0], q / SEG[k]), y = y0 + lerp(T[k][1], T[k + 1][1], q / SEG[k]);
            g.fr(x, y, on ? Math.min(1, 0.92 * cl(P[i] * 3) + 0.3 * glow(x)) : 0);
          }
      });
      // the head (coral): parked at the start until the system is complete, then it sweeps
      const fade = !all ? 1 : cyc < 1.7 ? 1 : cyc < 1.95 ? 1 - (cyc - 1.7) / 0.25 : cyc > 3.6 ? (cyc - 3.6) / 0.2 : 0;
      const hx = all && cyc > 1.95 && cyc <= 3.6 ? X0 : xh;
      g.fr(hx, yAt(hx), 0.95 * fade, 1);
      return {flash: all ? 0.18 * Math.exp(-a3 / 0.12) : 0};
    },
  },

  // Thu: THE MIXER. Three faders, one per item; a set item pushes its fader to the top.
  // All three up: the peak lights fire in a chase and the master line lights across.
  {
    draw: (g, c) => {
      const m = track(c);
      const XS = [14.5, 23.5, 32.5], YT = 7.5, YB = 28.5;
      const a3 = allAge(m, c), all = a3 >= 0, last = lastOn(m);
      for (let k = 0; k < 3; k++) {
        const x = XS[k], p = progS(m, c, k, 10, 6), ky = lerp(YB, YT, p);
        // slot and scale
        for (let y = 5; y <= 31; y++) g.on(x, y, 0.16);
        for (let y = 5; y <= 31; y += 2) g.on(x - 3, y, (y - 5) % 8 === 0 ? 0.32 : 0.16);
        // level under the knob
        const lv = cl(p);
        if (lv > 0.02) for (let y = Math.ceil(ky + 2); y <= 31; y++) g.on(x, y, 0.62 * Math.min(1, lv * 1.5));
        // peak light
        const pk = all ? Math.exp(-Math.max(0, a3 - 0.15 - k * 0.09) / 0.35) * (a3 > 0.15 + k * 0.09 ? 1 : 0) : 0;
        g.on(x, 3, m.on[k] && p > 0.9 ? 0.7 + 0.3 * pk : 0.14);
        // knob: 5 x 3 free particles with a cap line
        const coralHere = all ? k === last : last >= 0 ? k === last : k === 0;
        for (let v = -1; v <= 1; v++)
          for (let u = -2; u <= 2; u++) {
            const mid = v === 0 && u === 0;
            g.fr(x + u, ky + v, v === 0 && !mid ? 0.42 : 1, mid && coralHere ? 1 : 0);
          }
        // chase up the slot when all three land
        const q = all ? (a3 - 0.05 - k * 0.09) / 0.32 : -1;
        g.fr(x, lerp(31.5, YT, ez(q)), q > 0 && q < 1 ? 1 - q * 0.4 : 0);
      }
      // master line across the tops once everything is up
      const ml = all ? ez((a3 - 0.3) / 0.5) : 0;
      if (ml > 0) for (let x = Math.round(lerp(23.5, 12, ml)); x <= Math.round(lerp(23.5, 35, ml)); x++) if (!XS.includes(x + 0.5)) g.on(x, 3, 0.4);
      return {flash: all ? 0.18 * Math.exp(-((a3 - 0.15) ** 2) / 0.01) : 0};
    },
  },

  // Fri: BUILD THE ARROW. Three parts, one per item: base, shaft, head, each rising into place.
  // The head completes it: the arrow kicks up, speed lines stream off its sides, then it holds.
  {
    draw: (g, c) => {
      const m = track(c);
      let L = 0;
      for (let i = 0; i < 3; i++) L += prog(m, c, i, 0.42, eio);
      const a3 = allAge(m, c), all = a3 >= 0;
      const kick = all ? -2.2 * Math.sin(Math.PI * cl(a3 / 0.42)) * (a3 < 0.42 ? 1 : 0) + (a3 >= 0.42 ? 0.5 * Math.sin((a3 - 0.42) * 14) * Math.exp(-(a3 - 0.42) * 7) : 0) : 0;
      const band = all && a3 > 1.2 ? ((a3 - 1.2) % 4.2) / 0.9 : -1;
      const lum = (y: number) => (band >= 0 && band <= 1.2 ? 0.16 * Math.exp(-(((31 - y) / 26 - band) ** 2) / 0.012) : 0);
      // parts: 0 = base (rows 23-29), 1 = shaft (15-21), 2 = head (5-13)
      const parts: [number, number][][] = [[], [], []];
      for (let y = 23; y <= 29; y++) for (let x = 19; x <= 25; x++) parts[0].push([x, y]);
      for (let y = 15; y <= 21; y++) for (let x = 19; x <= 25; x++) parts[1].push([x, y]);
      for (let r = 0; r <= 8; r++) for (let x = 22 - r; x <= 22 + r; x++) parts[2].push([x, 5 + r]);
      parts.forEach((pts, k) => {
        const q = cl(L - k);
        // ghost outline of a missing part
        if (q < 0.98)
          for (const [x, y] of pts) {
            const edge = !pts.some(([a, b]) => a === x - 1 && b === y) || !pts.some(([a, b]) => a === x + 1 && b === y) || !pts.some(([a, b]) => a === x && b === y - 1) || !pts.some(([a, b]) => a === x && b === y + 1);
            if (edge) g.on(x, y, 0.13);
          }
        pts.forEach(([x, y], j) => {
          const tip = k === 2 && j === 0;
          const yy = y + 0.5 + (1 - q) * 7 + kick;
          if (tip) g.fr(x + 0.5, y + 0.5 + kick, Math.max(0.62, q), 1);
          else g.fr(x + 0.5, yy, q > 0.01 ? Math.min(1, 0.86 * q + lum(y)) : 0);
        });
      });
      // speed lines off both sides when the arrow kicks
      for (const sx of [15.5, 17.5, 27.5, 29.5])
        for (let s = 0; s < 3; s++) {
          const p = all ? (a3 - (sx === 17.5 || sx === 27.5 ? 0.05 : 0)) / 0.55 : 2;
          const on = p >= 0 && p <= 1;
          g.fr(sx, 12 + ez(p) * 16 + s * 1.6, on ? (1 - p) * (1 - s * 0.3) : 0);
        }
      return {flash: all ? 0.22 * Math.exp(-a3 / 0.12) : 0, shake: all ? 0.18 * Math.exp(-a3 / 0.1) : 0};
    },
  },

  // Sat: THREE LOOPS. One ring per item, set round a centre; a set item lights its ring with a pop.
  // All three: the rings draw in and interlock, and the shared centre lights coral.
  {
    draw: (g, c) => {
      const m = track(c);
      const cx = 22.5, cy = 18, AN = [0, (2 * TAU) / 3, TAU / 3];
      const a3 = allAge(m, c), all = a3 >= 0, lock = all ? eio(a3 / 0.5) : 0;
      const d = lerp(7.4, 5.4, lock), gl = all && a3 > 1.2 ? ((a3 - 1.2) % 6) / 1.6 : -1;
      for (let i = 0; i < 3; i++) {
        const p = progS(m, c, i, 12, 6), q = cl(p);
        const rx = cx + Math.sin(AN[i]) * d, ry = cy - Math.cos(AN[i]) * d, r = 6 + 0.9 * p;
        for (let k = 0; k < 44; k++) {
          const a = (k / 44) * TAU, u = k / 44;
          const lum = gl >= 0 && gl <= 1 ? 0.25 * Math.exp(-((u - gl) ** 2) / 0.004) : 0;
          g.fr(rx + Math.sin(a) * r, ry - Math.cos(a) * r, Math.min(1, 0.16 + 0.72 * q + lum));
        }
      }
      g.fr(cx, cy, all ? 0.55 + 0.45 * ez(a3 / 0.4) : 0.5, 1);
      return {flash: all ? 0.18 * Math.exp(-((a3 - 0.45) ** 2) / 0.01) : 0};
    },
  },

  // Sun: THE WEEK PLANNER. Rows are the three items, columns are the coming week; a set item lights
  // its row Monday to Sunday. All three: a column sweep runs the week and lands on Monday.
  {
    draw: (g, c) => {
      const m = track(c);
      const X0 = 9, YR = [18, 22, 26], DAYS = 'MTWTFSS';
      const a3 = allAge(m, c), all = a3 >= 0;
      // a highlight column runs Mon -> Sun after the third item, then once every 5 s, slowly
      const sweepCol = (t: number) => (t >= 0 && t < 1.1 ? t / 0.14 : -9);
      const sc = all ? (a3 < 1.6 ? sweepCol(a3 - 0.25) : sweepCol(((a3 - 1.6) % 5.5) - 0.2) * 0.999) : -9;
      for (let d = 0; d < 7; d++) {
        const x = X0 + d * 4, hl = Math.max(0, 1 - Math.abs(sc - d) / 1.2);
        letter(g, DAYS[d], x, 10, Math.min(1, (d === 0 ? 0.85 : 0.45) + 0.5 * hl));
        for (let r = 0; r < 3; r++) {
          // the row lights tile by tile from Monday (and goes out from Sunday)
          const age = c.t - m.at[r];
          const on = m.on[r] ? age >= 0.045 * d : age < 0.045 * (6 - d);
          const fresh = m.on[r] && age >= 0.045 * d ? Math.exp(-(age - 0.045 * d) / 0.18) : 0;
          for (let j = 0; j < 3; j++)
            for (let i = 0; i < 3; i++) {
              const mid = i === 1 && j === 1;
              const b = on ? Math.min(1, 0.8 + 0.2 * fresh + 0.2 * hl) : mid ? 0.3 + 0.3 * hl : 0;
              if (b > 0) g.on(x + i, YR[r] + j, b);
            }
        }
      }
      // Monday marker: the start of the week, you are on it
      g.on(X0 + 1, 16, all ? 1 : 0.7, 1);
      return {flash: all ? 0.16 * Math.exp(-a3 / 0.12) : 0};
    },
  },
];
