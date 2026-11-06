/**
 * Matrix Dynamic: bedtime. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * Phone locked for sleep, alarm set for the morning. Night card: one calm beat, then stillness.
 */
import {G, ICON, MScn, cl, eio, ez, lerp, spr} from '../mxlib';
import {TAU} from './common';

const breath = (t: number, P = 4.8) => 0.5 - 0.5 * Math.cos((t / P) * TAU);
/** 3 x 5 day letters */
const DL: Record<string, string[]> = {
  M: ['#.#', '###', '###', '#.#', '#.#'],
  T: ['###', '.#.', '.#.', '.#.', '.#.'],
  W: ['#.#', '#.#', '###', '###', '#.#'],
  F: ['###', '#..', '##.', '#..', '#..'],
  S: ['.##', '#..', '.#.', '..#', '##.'],
};
const letter = (g: G, ch: string, x: number, y: number, b: number) => DL[ch].forEach((r, j) => [...r].forEach((q, i) => q === '#' && g.on(x + i, y + j, b)));
/** seven-segment digit, 5 x 11: a top, b top-right, c bottom-right, d bottom, e bottom-left, f top-left, g middle */
const SEG: Record<string, string> = {'0': 'abcdef', '7': 'abc', '6': 'acdefg', '3': 'abcdg'};
const seg7 = (g: G, ch: string, x: number, y: number, on: number, off: number) => {
  const s = SEG[ch] ?? '';
  const put = (k: string, pts: [number, number][]) => pts.forEach(([i, j]) => g.on(x + i, y + j, s.includes(k) ? on : off));
  const H = (j: number): [number, number][] => [1, 2, 3].map((i) => [i, j]);
  const V = (i: number, j0: number): [number, number][] => [0, 1, 2, 3].map((j) => [i, j0 + j]);
  put('a', H(0));
  put('g', H(5));
  put('d', H(10));
  put('f', V(0, 1));
  put('b', V(4, 1));
  put('e', V(0, 6));
  put('c', V(4, 6));
};

export const SCENES: MScn[] = [
  // Mon: THE BEDTIME DIAL. A 24-hour dial; the sleep arc runs from the moon (22:30) to the bell
  // (06:30), drawn in on entry. In the middle, the padlock: apps locked until the alarm.
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 17.5, R = 12.5, a0 = (22.5 / 24) * TAU, a1 = (30.5 / 24) * TAU;
      const sw = ez((c.T - 0.35) / 0.9), ae = lerp(a0, a1, sw);
      g.ring(cx, cy, R, 0.22);
      for (let h = 0; h < 24; h += 3) {
        const a = (h / 24) * TAU, r = R - 3;
        g.on(cx + Math.sin(a) * r, cy - Math.cos(a) * r, h % 6 ? 0.22 : 0.45);
      }
      // the arc, with a slow glint travelling along it every 5 s
      const gl = c.T > 2.4 ? ((c.T - 2.4) % 5) / 1.6 : -1;
      const N = 60;
      for (let k = 0; k <= N; k++) {
        const u = k / N, a = lerp(a0, a1, u);
        if (a > ae) break;
        const b = Math.min(1, 0.72 + (gl >= 0 && gl <= 1.1 ? 0.28 * Math.exp(-((u - gl) ** 2) / 0.006) : 0));
        for (const r of [R, R - 1]) g.on(cx + Math.sin(a) * r, cy - Math.cos(a) * r, b);
      }
      // handles: moon at bedtime (fixed), bell at the alarm (rides the sweep)
      const hr = R - 0.5;
      g.disc(cx + Math.sin(a0) * hr, cy - Math.cos(a0) * hr, 1.7, 1);
      g.on(cx + Math.sin(a0) * hr + 0.6, cy - Math.cos(a0) * hr - 0.4, 0);
      for (let k = 0; k < 9; k++) {
        const u = (k % 3) - 1, v = Math.floor(k / 3) - 1;
        g.fr(cx + Math.sin(ae) * hr + u, cy - Math.cos(ae) * hr + v, c.T > 0.3 ? (k === 4 ? 0.35 : 1) : 0);
      }
      // the lock: shackle drops shut when the arc is set
      const drop = c.T < 1.3 ? 3 : Math.round(3 * (1 - spr(c.T - 1.3, 16, 7)));
      const L = ICON.lock;
      g.glyph(L.slice(4), 18, 15, 1, 0.92);
      L.slice(0, 4).forEach((row, j) => [...row].forEach((q, i) => q === '#' && g.fr(18.5 + i, 11.5 + j - drop, 0.92)));
      return {shake: c.T > 1.3 && c.T < 1.45 ? 0.2 : 0};
    },
    hap: [{t: 1.33, kind: 'medium'}],
  },

  // Tue: LIGHTS OUT. The home screen of apps; then the screen switches off the old way: it folds
  // into a bright line, the line into a point, and what's left is a sleep light, breathing.
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 18, sy = eio((c.T - 1.1) / 0.32), sx = eio((c.T - 1.5) / 0.3);
      const gone = cl((c.T - 1.8) / 0.18);
      // the phone's frame fades as the screen goes
      const fb = 0.3 * (1 - cl((c.T - 1.05) / 0.3));
      if (fb > 0.01) {
        for (let x = 12; x <= 33; x++) (g.on(x, 3, fb), g.on(x, 32, fb));
        for (let y = 4; y <= 31; y++) (g.on(11, y, fb), g.on(34, y, fb));
      }
      const line = sy * (1 - sx);
      for (let r = 0; r < 5; r++)
        for (let k = 0; k < 4; k++)
          for (let j = 0; j < 4; j++)
            for (let i = 0; i < 4; i++) {
              if ((i === 0 || i === 3) && (j === 0 || j === 3)) continue;
              const x0 = 13.5 + k * 5 + i, y0 = 6.5 + r * 5 + j;
              const x = cx + (x0 - cx) * (1 - sx), y = cy + (y0 - cy) * (1 - sy);
              g.fr(x, y, (0.68 + 0.32 * line) * (1 - gone) * cl(c.T / 0.2));
            }
      // the sleep light and its faint halo
      const on = cl((c.T - 1.75) / 0.25), br = breath(c.T - 1.75);
      if (on > 0) for (let k = 0; k < 8; k++) {
        const a = (k / 8) * TAU;
        g.on(cx + Math.sin(a) * 2, cy - Math.cos(a) * 2, on * 0.3 * br);
      }
      if (on > 0) for (let k = 0; k < 16; k++) {
        const a = (k / 16) * TAU;
        g.on(cx + Math.sin(a) * 3.6, cy - Math.cos(a) * 3.6, on * 0.12 * br);
      }
      g.fr(cx, cy, on * (0.34 + 0.66 * br), 1);
      const fl = c.T - 1.4;
      return {flash: fl > 0 ? 0.14 * Math.exp(-fl / 0.12) : 0};
    },
    hap: [{t: 1.1, kind: 'light'}, {t: 1.8, kind: 'medium'}],
  },

  // Wed: POWER DOWN. The battery the owner liked, kept and polished: a big cell charging overnight,
  // its level a gently moving liquid edge, the bolt cut out of the charge. It never jumps back.
  {
    draw: (g, c) => {
      const X0 = 10, X1 = 32, Y0 = 11, Y1 = 24, fx0 = 12, fx1 = 30;
      for (let x = X0 + 1; x < X1; x++) (g.on(x, Y0, 0.8), g.on(x, Y1, 0.8));
      for (let y = Y0 + 1; y < Y1; y++) (g.on(X0, y, 0.8), g.on(X1, y, 0.8));
      for (let y = 15; y <= 20; y++) (g.on(33, y, 0.7), g.on(34, y, 0.7));
      const k = Math.min(0.94, 0.24 + 0.44 * ez(c.T / 2.6) + 0.004 * Math.max(0, c.T - 2.6));
      const edge = fx0 + k * (fx1 - fx0 + 1);
      const BOLT = ['...###', '..###.', '.###..', '######', '..###.', '.###..', '###...', '#.....'];
      const bx = 16, by = 14;
      const isB = (x: number, y: number) => {
        const r = BOLT[y - by];
        return !!r && x - bx >= 0 && x - bx < r.length && r[x - bx] === '#';
      };
      const sw = c.T > 2.8 ? ((c.T - 2.8) % 4.5) / 1.5 : -1;
      for (let y = 13; y <= 22; y++) {
        const ex = edge + Math.sin(y * 0.75 + c.t * 1.5) * 0.55;
        for (let x = fx0; x <= fx1; x++) {
          const inF = x + 0.5 < ex - 0.4;
          const lum = sw >= 0 && sw <= 1.1 ? 0.2 * Math.exp(-(((x - fx0) / (fx1 - fx0) - sw) ** 2) / 0.01) : 0;
          if (isB(x, y)) {
            if (!inF) g.on(x, y, 0.8);
          } else if (inF) g.on(x, y, 0.72 + lum);
        }
        g.fr(ex, y + 0.5, 1, y === 17 ? 1 : 0);
      }
    },
  },

  // Thu: OFF DUTY. Tonight's sleep, as a sleep tracker draws it: stages stepping down to deep sleep
  // and back up through the night, ending at the alarm (coral). A soft glint replays it.
  {
    draw: (g, c) => {
      const LV = [9, 14, 19, 24];
      const plan: [number, number][] = [[1, 0], [2, 2], [4, 3], [2, 2], [2, 1], [2, 2], [4, 3], [2, 2], [3, 1], [2, 2], [2, 3], [2, 2], [2, 1], [1, 0]];
      const cols: number[] = [];
      for (const [n, l] of plan) for (let i = 0; i < n; i++) cols.push(l);
      const X0 = 8, rev = ez((c.T - 0.3) / 2.0) * cols.length;
      for (let x = X0; x < X0 + cols.length; x++) g.on(x, 28, 0.22);
      for (let h = 0; h <= cols.length; h += 4) g.on(X0 + h, 29, 0.3);
      const gl = c.T > 3 ? ((c.T - 3) % 6) / 2 : -1;
      for (let i = 0; i < cols.length && i < rev; i++) {
        const x = X0 + i, y = LV[cols[i]];
        const lum = gl >= 0 && gl <= 1.1 ? 0.25 * Math.exp(-((i / cols.length - gl) ** 2) / 0.004) : 0;
        const b = Math.min(1, (cols[i] === 3 ? 0.9 : 0.7) + lum);
        g.on(x, y, b);
        g.on(x, y + 1, b * 0.8);
        if (cols[i] === 3) for (let yy = y + 2; yy < 28; yy++) g.on(x, yy, 0.16);
        if (i > 0 && cols[i - 1] !== cols[i]) {
          const ya = LV[cols[i - 1]], lo = Math.min(ya, y), hi = Math.max(ya, y);
          for (let yy = lo; yy <= hi + 1; yy++) g.on(x, yy, 0.42);
        }
      }
      // the pen draws the night, then rests as the alarm marker
      const i = Math.min(cols.length - 1, Math.floor(rev)), done = rev >= cols.length - 0.01;
      g.fr(X0 + i + 0.5, LV[cols[i]] + 0.5, c.T > 0.25 ? 1 : 0, done ? 1 : 0);
    },
    hap: [{t: 2.3, kind: 'light'}],
  },

  // Fri: REST UP. The arrow that pushed all week lies down: it tips from upright to flat and comes
  // to rest, pointing right, toward tomorrow. Every few seconds a light runs along it to the tip.
  {
    draw: (g, c) => {
      const px = 11.5, py = 22.5, Ln = 20;
      const p = c.T < 0.6 ? 0 : 1 - Math.exp(-(c.T - 0.6) * 5.2) * Math.cos((c.T - 0.6) * 4.2);
      const a = (Math.PI / 2) * Math.min(1.02, p);
      const dx = Math.sin(a), dy = -Math.cos(a), nx = -dy, ny = dx;
      for (let x = 8; x <= 36; x += 2) g.on(x, 25, 0.2);
      const pl = c.T > 2.8 ? ((c.T - 2.8) % 5) / 1.3 : -1;
      for (let i = 0; i <= 26; i++) {
        const s = (i / 26) * (Ln - 1);
        const lum = pl >= 0 && pl <= 1.1 ? 0.3 * Math.exp(-((s / Ln - pl) ** 2) / 0.006) : 0;
        for (const o of [0, 1]) g.fr(px + dx * s + nx * o, py + dy * s + ny * o, Math.min(1, 0.7 + lum));
      }
      const tx = px + dx * Ln + nx * 0.5, ty = py + dy * Ln + ny * 0.5;
      for (const sd of [-1, 1])
        for (let i = 1; i <= 5; i++) {
          const ba = a + Math.PI + sd * 0.72;
          g.fr(tx + Math.sin(ba) * i, ty - Math.cos(ba) * i, 0.92);
        }
      g.fr(tx, ty, 1, 1);
      return {shake: c.T > 1.0 && c.T < 1.15 ? 0.12 : 0};
    },
    hap: [{t: 1.02, kind: 'light'}],
  },

  // Sat: WIND DOWN. A light races round the ring like a busy feed, and winds down, lap by lap,
  // to a slow drift round the moon. Nothing to scroll till morning.
  {
    draw: (g, c) => {
      const cx = 22.5, cy = 17.5, R = 11.5, w0 = 9, w1 = 0.3, tau = 1.1;
      g.ring(cx, cy, R, 0.16);
      for (let y = 11; y <= 24; y++)
        for (let x = 15; x <= 30; x++) {
          const d1 = Math.hypot(x + 0.5 - 21.5, y + 0.5 - 17.5), d2 = Math.hypot(x + 0.5 - 24.3, y + 0.5 - 15.8);
          if (d1 <= 5.6 && d2 > 4.6) g.on(x, y, 0.85 * cl(c.T / 0.4));
        }
      const T = c.T, th = w1 * T + (w0 - w1) * tau * (1 - Math.exp(-T / tau)), w = w1 + (w0 - w1) * Math.exp(-T / tau);
      const tail = Math.min(1.6, Math.max(0.12, w * 0.16));
      for (let k = 0; k < 12; k++) {
        const a = th - (k / 11) * tail;
        g.fr(cx + Math.sin(a) * R, cy - Math.cos(a) * R, k === 0 ? 1 : 0.85 * (1 - k / 12), k === 0 ? 1 : 0);
      }
    },
  },

  // Sun: REFUEL. A bedside alarm display: 07:00, and the day row under it steps from Sunday round
  // to Monday. New week at 07:00; the colon breathes while you sleep.
  {
    draw: (g, c) => {
      const y0 = 8, XS = [10, 16, 24, 30], D = '0700';
      XS.forEach((x, i) => seg7(g, D[i], x, y0, 0.92 * cl((c.T - 0.3 - i * 0.12) / 0.25), 0.07));
      const cb = 0.35 + 0.45 * breath(c.t);
      g.on(22, y0 + 3, cb);
      g.on(22, y0 + 7, cb);
      const DAYS = 'MTWTFSS';
      const mv = eio((c.T - 1.2) / 0.75), at = lerp(6, 0, mv);
      for (let d = 0; d < 7; d++) {
        const near = Math.max(0, 1 - Math.abs(at - d));
        letter(g, DAYS[d], 9 + d * 4, 24, 0.28 + 0.6 * near);
        g.on(10 + d * 4, 30, 0.12);
      }
      g.fr(10.5 + at * 4, 30.5, 1, 1);
    },
    hap: [{t: 1.95, kind: 'light'}],
  },
];
