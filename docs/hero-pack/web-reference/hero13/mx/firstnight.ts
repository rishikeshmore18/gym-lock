/**
 * Matrix Dynamic: firstnight. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * The night before day one: calm, anticipatory, a night card. One beat, then stillness.
 */
import {G, ICON, MScn, cl, eio, ez, lerp} from '../mxlib';
import {TAU} from './common';

const DIGIT1 = ['00100', '01100', '00100', '00100', '00100', '00100', '01110'];
/** 3 x 5 day letters */
const DL: Record<string, string[]> = {
  M: ['#.#', '###', '###', '#.#', '#.#'],
  T: ['###', '.#.', '.#.', '.#.', '.#.'],
  W: ['#.#', '#.#', '###', '###', '#.#'],
  F: ['###', '#..', '##.', '#..', '#..'],
  S: ['.##', '#..', '.#.', '..#', '##.'],
};
const letter = (g: G, ch: string, x: number, y: number, b: number) => DL[ch].forEach((r, j) => [...r].forEach((q, i) => q === '#' && g.on(x + i, y + j, b)));
const breath = (t: number, P = 4.5) => 0.5 - 0.5 * Math.cos((t / P) * TAU);

export const SCENES: MScn[] = [
  // Mon: CHARGE UP. Energy streams in from all round and builds the big 1 of day one, cell by cell;
  // the last cell to land is coral. After that, a slow trickle keeps it topped up.
  {
    draw: (g, c) => {
      const cx = 23, cy = 17.5, x0 = 16, y0 = 7, SC = 3;
      const cells: [number, number][] = [];
      DIGIT1.forEach((r, j) => [...r].forEach((q, i) => {
        if (q === '1') for (let v = 0; v < SC; v++) for (let u = 0; u < SC; u++) cells.push([x0 + i * SC + u, y0 + j * SC + v]);
      }));
      cells.sort((a, b) => b[1] - a[1] || a[0] - b[0]);
      const N = cells.length, FL = 0.55;
      // the socket: where the digit will be
      for (const [x, y] of cells) g.on(x, y, 0.1);
      cells.forEach(([x, y], k) => {
        const land = 0.5 + 1.85 * Math.pow(k / (N - 1), 0.9), u = (c.T - (land - FL)) / FL;
        const a = k * 2.39996 + 0.4, sx = cx + Math.sin(a) * 17, sy = cy - Math.cos(a) * 15;
        const q = eio(u), last = k === N - 1;
        // idle: every 5 s a soft charge band climbs the digit, bottom to top
        const sw = c.T > 3.2 ? ((c.T - 3.2) % 5) / 1.4 : -1, yy = (y0 + 21 - y) / 21;
        const glow = sw >= 0 && sw <= 1.2 ? Math.exp(-((yy - sw) ** 2) / 0.01) : 0;
        g.fr(lerp(sx, x + 0.5, q), lerp(sy, y + 0.5, q), u <= 0 ? 0 : u < 1 ? 0.25 + 0.7 * q : last ? 1 : Math.min(1, 0.78 + 0.22 * glow), last ? 1 : 0);
      });
      const hit = c.T - 2.35;
      return {flash: hit > 0 ? 0.12 * Math.exp(-hit / 0.16) : 0};
    },
    hap: [{t: 0.5, kind: 'light'}, {t: 2.35, kind: 'medium'}],
  },

  // Tue: LIGHTS LOW. The month's calendar lights up, then the lights go low, tile by tile, toward
  // one tile that stays on: tomorrow, Wednesday, the plan with a time and a place.
  {
    draw: (g, c) => {
      const tc = 2, tr = 1, DAYS = 'MTWTFSS';
      const low = (d: number) => 1.25 + (5.2 - d) * 0.24;
      for (let k = 0; k < 7; k++) {
        const isT = k === tc, d = Math.abs(k - tc) + 1.5, dim = ez((c.T - low(d)) / 0.4);
        letter(g, DAYS[k], 9 + k * 4, 5, isT ? 0.85 : lerp(0.5, 0.16, dim) * cl((c.T - 0.05 - k * 0.05) / 0.2));
      }
      for (let r = 0; r < 5; r++)
        for (let k = 0; k < 7; k++) {
          const x = 9 + k * 4, y = 11 + r * 4, isT = k === tc && r === tr;
          const appear = cl((c.T - 0.1 - (k + r) * 0.055) / 0.18);
          const d = Math.hypot(k - tc, (r - tr) * 1.1), dim = isT ? 0 : ez((c.T - low(d)) / 0.45);
          const b = appear * (isT ? 0.9 : lerp(0.62, 0.15, dim));
          for (let j = 0; j < 3; j++) for (let i = 0; i < 3; i++) if (!(isT && i === 1 && j === 1)) g.on(x + i, y + j, b);
          if (isT) {
            const s = c.T - 2.55;
            g.on(x + 1, y + 1, appear * (s > 0 ? 0.78 + 0.22 * Math.max(Math.exp(-s / 0.3), breath(c.t)) : 0.9), s > 0 ? 1 : 0);
          }
        }
    },
    hap: [{t: 2.55, kind: 'light'}],
  },

  // Wed: BAG PACKED. The gym bag; its zip runs shut, left to right, and a ready signal passes
  // over it. The coral zip pull rests at the end.
  {
    draw: (g, c) => {
      const X0 = 12, X1 = 33, Y0 = 13, Y1 = 26;
      const zp = eio((c.T - 0.7) / 1.15), px = lerp(14.5, 31.5, zp);
      const ping = c.T - 1.95, band = ping > 0 && ping < 0.7 ? lerp(X0 - 3, X1 + 3, ping / 0.7) : -99;
      const lum = (x: number) => (band > -50 ? 0.32 * Math.exp(-((x - band) ** 2) / 6) : 0);
      const B = (x: number, b: number) => Math.min(1, b + lum(x + 0.5));
      // body, with rounded corners
      for (let x = X0 + 1; x <= X1 - 1; x++) {
        g.on(x, Y0, B(x, 0.82));
        g.on(x, Y1, B(x, 0.82));
      }
      for (let y = Y0 + 1; y <= Y1 - 1; y++) {
        g.on(X0, y, B(X0, 0.82));
        g.on(X1, y, B(X1, 0.82));
      }
      // end panels and base
      for (let y = Y0 + 4; y <= Y1 - 2; y++) {
        g.on(X0 + 3, y, B(X0 + 3, 0.28));
        g.on(X1 - 3, y, B(X1 - 3, 0.28));
      }
      for (let x = X0 + 1; x <= X1 - 1; x++) g.on(x, Y1 - 1, B(x, 0.3));
      // handle
      for (let y = 9; y <= Y0 - 1; y++) {
        g.on(17, y, B(17, 0.82));
        g.on(28, y, B(28, 0.82));
      }
      for (let x = 18; x <= 27; x++) g.on(x, 8, B(x, 0.82));
      // the zip: shut behind the pull, open teeth ahead of it
      for (let x = 14; x <= 31; x++) {
        if (x + 0.5 <= px) g.on(x, Y0 + 2, B(x, 0.78));
        else {
          g.on(x, Y0 + 2 - (x % 2), B(x, 0.32));
        }
      }
      // pull: coral head and a short tab that swings a little as it moves
      const sway = Math.sin(c.T * 9) * Math.exp(-Math.max(0, c.T - 1.85) * 3) * (c.T > 0.7 ? 0.6 : 0);
      g.fr(px, Y0 + 2.5, 1, 1);
      g.fr(px - sway * 0.5, Y0 + 3.6, 0.9);
      g.fr(px - sway, Y0 + 4.6, 0.75);
      return {flash: ping > 0 ? 0.08 * Math.exp(-ping / 0.2) : 0};
    },
    hap: [{t: 0.7, kind: 'light'}, {t: 1.9, kind: 'medium'}],
  },

  // Thu: LEVEL ONE. The 66-day scale stands empty, a ruler from the floor to automatic. The coral
  // pointer slides in and stops on the first mark: tomorrow. All you have to reach is level one.
  {
    draw: (g, c) => {
      const X = 22, Y0 = 30, Y1 = 4, lv = (d: number) => Y0 - (d / 66) * (Y0 - Y1);
      const up = ez((c.T - 0.1) / 0.9);
      for (let y = Y0; y >= Y1; y--) if ((Y0 - y) / (Y0 - Y1) <= up) g.on(X, y, 0.4);
      for (let d = 0; d <= 66; d += 5) {
        const y = Math.round(lv(d)), w = d % 10 === 0 || d === 66 ? 4 : 2;
        if ((Y0 - y) / (Y0 - Y1) > up + 0.01) continue;
        for (let i = 1; i <= w; i++) g.on(X - i, y, d === 0 ? 0.75 : 0.32);
      }
      // the top: automatic
      if (up > 0.98) for (let i = -4; i <= 4; i++) g.on(X + i, Y1 - 1, i ? 0.3 : 0.6);
      // the pointer: a 5-row wedge sliding in from the right to day one
      const q = c.T < 1.0 ? 0 : 1 - Math.exp(-(c.T - 1.0) * 6) * Math.cos((c.T - 1.0) * 9);
      const px = lerp(33, X + 2.5, q), py = Math.round(lv(1)) + 0.5 - 1;
      for (let j = -2; j <= 2; j++)
        for (let i = Math.abs(j) * 2; i <= 6; i++) g.fr(px + i, py + j, c.T > 0.95 ? (i === 0 && j === 0 ? 1 : 0.85) : 0, i === 0 && j === 0 ? 1 : 0);
      // a lit stub of scale from the floor to day one
      const st = c.T - 1.6;
      if (st > 0) for (let y = Y0; y >= Math.round(lv(1)); y--) g.on(X + 1, y, 0.9 * ez(st / 0.3));
    },
    hap: [{t: 1.55, kind: 'light'}],
  },

  // Fri: SLEEP FIRST. The moon, then an arrow up to the dumbbell: sleep first, then the gym.
  // Every few seconds the coral dot (you) travels the arrow from the moon to tomorrow's session.
  {
    draw: (g, c) => {
      const mx = 9.5, my = 21.5;
      g.glyph(ICON.moon, Math.round(mx), Math.round(my), 1, 0.92);
      const DB = ['.##.........##.', '###.........###', '###############', '###.........###', '.##.........##.'];
      const dbIn = cl((c.T - 1.25) / 0.4);
      // the arrow draws itself out of the moon
      const S: [number, number] = [19.5, 21.5], E: [number, number] = [27.5, 13.5];
      const grow = ez((c.T - 0.55) / 0.7), n = 8;
      for (let i = 0; i <= n; i++) {
        if (i / n > grow) break;
        g.on(lerp(S[0], E[0], i / n), lerp(S[1], E[1], i / n), 0.6);
      }
      const head = cl((c.T - 1.2) / 0.2);
      if (head > 0)
        for (let i = 0; i <= 3; i++) {
          g.on(E[0] - i, E[1], 0.9 * head);
          g.on(E[0], E[1] + i, 0.9 * head);
        }
      // you: rests on the moon, then every 6 s travels the arrow
      const cyc = c.T < 2.2 ? -1 : (c.T - 2.2) % 6;
      let x = 16.5, y = 23.5, b = cl((c.T - 0.4) / 0.3);
      let glow = 0;
      if (cyc >= 0) {
        if (cyc < 0.35) [x, y] = [lerp(16.5, S[0], ez(cyc / 0.35)), lerp(23.5, S[1], ez(cyc / 0.35))];
        else if (cyc < 1.75) {
          const q = eio((cyc - 0.35) / 1.4);
          [x, y] = [lerp(S[0], E[0] - 1, q), lerp(S[1], E[1] + 1, q)];
        } else if (cyc < 2.1) {
          [x, y] = [E[0] - 1, E[1] + 1];
          b = 1 - (cyc - 1.75) / 0.35;
          glow = Math.exp(-(cyc - 1.75) / 0.6);
        } else if (cyc < 2.5) b = 0;
        else b = cl((cyc - 2.5) / 0.5);
        if (cyc >= 2.1) glow = Math.exp(-(cyc - 1.75) / 0.6);
      }
      g.glyph(DB, 23, 6, 1, dbIn * Math.min(1, 0.62 + 0.38 * glow));
      g.fr(x, y, b, 1);
    },
    hap: [{t: 1.25, kind: 'light'}],
  },

  // Sat: EARLY NIGHT. Sleep comes in loops of about 90 minutes; an early night fits five of them.
  // The coil of five loops draws itself across the night and ends on the coral point: morning.
  {
    draw: (g, c) => {
      const A = 0.8, Bm = 5, BX = 2.9, X0 = 8.8, Y = 17.5, S = 5 * TAU;
      const at = (s: number): [number, number] => [X0 + 2 + A * s - BX * Math.sin(s), Y - Bm * Math.cos(s)];
      const pen = eio((c.T - 0.3) / 2.2) * S, N = 150;
      const gl = c.T > 3.2 ? ((c.T - 3.2) % 6) / 1.8 : -1;
      for (let k = 0; k <= N; k++) {
        const s = (k / N) * S;
        if (s > pen) break;
        const [x, y] = at(s), u = k / N;
        const lum = gl >= 0 && gl <= 1.1 ? 0.3 * Math.exp(-((u - gl) ** 2) / 0.003) : 0;
        g.on(x, y, Math.min(1, 0.62 + lum));
      }
      // a dim mark under each finished loop
      for (let i = 0; i < 5; i++) if (pen >= (i + 1) * TAU - 0.01) g.on(at((i + 0.5) * TAU)[0], Y + Bm + 2.5, 0.35);
      const [hx, hy] = at(pen);
      g.fr(hx, hy, c.T > 0.25 ? 1 : 0, 1);
    },
    hap: [{t: 2.5, kind: 'light'}],
  },

  // Sun: MONDAY, DAY ONE. Which day people start on: Monday's column stacks up highest; then you
  // (coral) fly in and land on top of it. Join them.
  {
    draw: (g, c) => {
      const H = [13, 8, 7, 6, 5, 3, 3], DAYS = 'MTWTFSS', base = 25;
      for (let d = 0; d < 7; d++) {
        const x = 9 + d * 4;
        letter(g, DAYS[d], x, 28, d === 0 ? 0.9 : 0.4);
        for (let j = 0; j < H[d]; j++) {
          const a = cl((c.T - 0.25 - j * 0.06 - d * 0.03) / 0.12);
          const b = (d === 0 ? 0.88 : 0.5) * a;
          if (b > 0) for (let i = 0; i < 3; i++) g.on(x + i, base - j, i === 1 ? b : b * 0.85);
        }
      }
      // you: an arc in from the right, landing on Monday's column
      const u = eio((c.T - 1.2) / 0.85), tx = 10.5, ty = base - H[0] - 0.5;
      const x = lerp(37, tx, u), y = lerp(9, ty, u) - Math.sin(u * Math.PI) * 5;
      const land = c.T - 2.05;
      g.fr(x, y, c.T < 1.15 ? 0 : 1, 1);
      return {flash: land > 0 ? 0.07 * Math.exp(-land / 0.2) : 0};
    },
    hap: [{t: 2.05, kind: 'light'}],
  },
];
