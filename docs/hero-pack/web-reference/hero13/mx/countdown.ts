/**
 * Matrix Dynamic: countdown. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * The headline is a flip clock, so the board never repeats the digits: each day is a different
 * instrument of time, ticking on the same second boundary as the clock's flip.
 */
import {CX, CY, G, MC, MScn, back, cl, eio, ez, lerp} from '../mxlib';
import {TAU} from './common';

/** K = whole seconds left (what the clock shows), q = seconds since the last flip (0..1) */
const tick = (c: MC) => {
  const s = Math.max(0, c.d.countdown), K = Math.floor(s);
  return {s, K, q: 1 - (s - K)};
};
/** cell-centre coordinates of the board's centre */
const OX = CX + 0.5, OY = CY + 0.5;
const polar = (r: number, a: number, ox = OX, oy = OY): [number, number] => [ox + Math.sin(a) * r, oy - Math.cos(a) * r];

export const SCENES: MScn[] = [
  // Mon: THE RAY DIAL. Twelve rays of five lights hold the minute's sixty seconds. Every flip, the
  // last light leaves its ray and radiates away; when the minute turns, all twelve rays shoot back out.
  {
    draw: (g, c) => {
      const {K, q} = tick(c);
      const n = (K % 60) + 1; // lights still on this minute: 60 at :59, 1 at :00
      const fresh = n === 60 ? q : 9; // seconds since the minute turned
      for (let i = 0; i < 60; i++) {
        const k = Math.floor(i / 5), j = i % 5, a = (k / 12) * TAU, R = 4.6 + j * 2;
        // rays grow out of the hub: on entry, and again each new minute
        const grow = Math.min(ez((c.T - 0.05 - k * 0.035 - j * 0.02) / 0.4), fresh < 1 ? ez((fresh - k * 0.03 - j * 0.015) / 0.32) : 1);
        if (i < n) {
          const [x, y] = polar(lerp(1.2, R, grow), a);
          const cur = i === n - 1 && fresh > 0.4;
          g.fr(x, y, (cur ? 1 : j === 4 ? 0.95 : 0.78) * (0.25 + 0.75 * grow), cur ? 1 : 0);
        } else if (i === n && q < 0.6) {
          // the second that just went: it slides out along its ray and fades
          const [x, y] = polar(R + ez(q / 0.6) * 5.5, a);
          g.fr(x, y, 0.9 * (1 - ez(q / 0.55)));
        } else if (i === n && q < 1) {
          const [x, y] = polar(R, a);
          g.fr(x, y, 0.2 * ez((q - 0.6) / 0.4));
        } else {
          const [x, y] = polar(lerp(1.2, R, grow), a);
          g.fr(x, y, 0.2 * grow);
        }
      }
      // the hub, and a faint bezel the rays point at
      g.on(CX, CY, 0.55);
      for (let k = 0; k < 12; k++) {
        const [x, y] = polar(15, (k / 12) * TAU);
        g.on(x, y, 0.18 * ez((c.T - 0.3 - k * 0.03) / 0.3));
      }
      return {o: {stagger: 0.3}, flash: fresh < 0.25 ? (1 - fresh / 0.25) * 0.06 : 0};
    },
  },
  // Tue: THE TILE BOARD. Sixty tiles, one for every second of the minute. Each flip turns the last
  // tile over; when the minute turns, the board flips back face up in one diagonal wave.
  {
    draw: (g, c) => {
      const {K, q} = tick(c);
      const n = (K % 60) + 1;
      const x0 = 8, y0 = 8;
      for (let i = 0; i < 60; i++) {
        const col = i % 10, row = Math.floor(i / 10);
        const tx = x0 + col * 3 + 1, ty = y0 + row * 3 + 1;
        // f: 0 face up (lit) .. 1 face down (dim)
        let f = i < n ? 0 : 1;
        if (i === n && n < 60) f = ez(q / 0.34);
        if (n === 60 && i > 0) f = 1 - ez((q - 0.04 - (col + row) * 0.03) / 0.3);
        if (i < n) f = Math.max(f, 1 - ez((c.T - (col + row) * 0.028) / 0.3));
        const w = Math.abs(Math.cos(f * Math.PI)), up = f < 0.5;
        const b = (up ? 0.9 : 0.16) * (0.45 + 0.55 * w);
        const cor = up && i === n - 1 && (n < 60 || q > 0.7) ? 1 : 0;
        for (let v = -0.5; v <= 0.5; v += 1) for (let u = -0.5; u <= 0.5; u += 1) g.fr(tx + u * w, ty + v, b, cor);
      }
      return {o: {stagger: 0.25}};
    },
  },
  // Wed: THE WATER CLOCK. The tank holds the time left (full is two hours). Every second a drop
  // swells at the spout, lets go and lands on the flip; the surface barely moves.
  {
    draw: (g, c) => {
      const {s, K, q} = tick(c);
      const L = cl(s / 7200), top = 5, bend = 20, floor = 25, xl = 14, xr = 30;
      const rise = ez((c.T - 0.1) / 0.7);
      // the vessel: open top, straight sides, a funnel down to the spout
      for (let y = top; y <= bend; y++) {
        g.on(xl, y, 0.55);
        g.on(xr, y, 0.55);
      }
      g.line(xl, bend, CX - 1, floor + 1, 0.55);
      g.line(xr, bend, CX + 1, floor + 1, 0.55);
      g.on(CX - 1, floor + 2, 0.4);
      g.on(CX + 1, floor + 2, 0.4);
      // half the inside width at a row
      const span = (y: number) => (y <= bend ? 7.5 : 7.5 - ((y - bend) / (floor + 1 - bend)) * 6.6);
      // graduations every half hour, the hours longer
      for (let m = 30; m <= 120; m += 30) {
        const y = floor + 0.5 - (m / 120) * (floor - top);
        g.on(xl - 2, y, 0.32);
        if (m % 60 === 0) g.on(xl - 3, y, 0.32);
      }
      // the water: a quiet surface over a dim body
      const sy = floor + 0.5 - L * (floor - top - 0.5) * rise;
      for (let y = Math.ceil(sy + 0.6); y <= floor; y++) {
        const hw = span(y + 0.5);
        for (let x = xl + 1; x < xr; x++) if (Math.abs(x + 0.5 - OX) < hw) g.on(x, y, 0.36);
      }
      for (let x = xl + 1; x < xr; x++) {
        const inside = Math.abs(x + 0.5 - OX) < span(sy) ? 1 : 0;
        g.fr(x + 0.5, sy + 0.22 * Math.sin(x * 0.55 - c.t * 1.1) + 0.12 * Math.sin(x * 1.3 + c.t * 0.7), 0.95 * rise * inside);
      }
      // two drops take turns: one swells and falls this second, the other has just landed
      const spout = floor + 2.3, land = 32.5;
      for (let p = 0; p < 2; p++) {
        if (K % 2 === p) {
          if (q < 0.56) g.fr(OX, spout + 0.5 * ez(q / 0.56), 0.3 + 0.7 * ez(q / 0.5), 1);
          else {
            const a = q - 0.56;
            g.fr(OX, spout + 0.5 + 0.5 * ((land - spout - 0.5) / (0.44 * 0.44)) * a * a, 1, 1);
          }
        } else if (q < 0.14) g.fr(OX, land, 1 - q / 0.14);
        else g.fr(OX, spout, 0);
      }
      // the splash on the flip
      for (let k = 0; k < 4; k++) {
        const sd = k % 2 ? 1 : -1, far = k < 2 ? 1 : 0.55, a = cl(q / 0.42);
        g.fr(OX + sd * (0.4 + 3.2 * far * ez(a)), land + 0.3 - 1.5 * far * Math.sin(Math.PI * a), q < 0.42 ? 0.7 * (1 - a) : 0);
      }
      for (let x = CX - 4; x <= CX + 4; x++) g.on(x, 33, 0.22 + 0.4 * Math.exp(-q / 0.25) * (1 - Math.abs(x - CX) / 5));
      return {o: {stagger: 0.3}};
    },
  },
  // Thu: THE TAPE. A scale of bars, one per second, steps left under a fixed pointer on every flip.
  // What's to the right is still to come; the tall bar is the next whole minute.
  {
    draw: (g, c) => {
      const {K, q} = tick(c);
      const se = K + 1 - ez(q / 0.3), base = 26, N = 19, H = 19;
      const ent = ez((c.T - 0.05) / 0.6);
      for (let jj = 0; jj < N; jj++) {
        const v = K - 9 + ((((jj - (K - 9)) % N) + N) % N);
        const x = OX + 2 * (se - v) + (1 - ent) * 6;
        const h = v % 60 === 0 ? H : v % 10 === 0 ? 12 : v % 5 === 0 ? 8 : 4;
        const isNow = v === K, fut = v < K;
        const edge = cl((x - 8) / 5) * cl((37.5 - x) / 2);
        const b = (isNow ? 1 : fut ? 0.82 : 0.26) * edge * ent;
        for (let k = 0; k < H; k++) {
          const hk = Math.round(h * lerp(0.2, 1, ez((c.T - 0.1 - (37 - x) * 0.012) / 0.35)));
          g.fr(x, base + 0.5 - Math.min(k, hk - 1), k < hk ? b : 0);
        }
      }
      // the pointer, the rail, and now
      for (let x = 9; x <= 36; x++) g.on(x, base + 1, 0.2 * ent);
      g.on(CX - 1, 4, 0.75);
      g.on(CX, 4, 0.75);
      g.on(CX + 1, 4, 0.75);
      g.on(CX, 5, 0.75);
      g.on(CX, base + 2, 1, 1);
      return {o: {stagger: 0.25}};
    },
  },
  // Fri: THE METRONOME. The arm beats once a second, at the end of every swing exactly when the clock
  // flips; a small arrow kicks out on each beat. The weight slides down as the time runs short.
  {
    draw: (g, c) => {
      const {s, K, q} = tick(c);
      const px = OX, py = 27.5, Lr = 21, A = 0.36;
      const ent = eio(c.T / 0.9);
      const side = K % 2 ? 1 : -1, th = A * Math.cos(Math.PI * q) * side * ent;
      // the body: a tall pyramid, its base, and the tempo scale
      g.line(13, 31, 19, 4, 0.5);
      g.line(31, 31, 25, 4, 0.5);
      g.line(19, 4, 25, 4, 0.5);
      g.line(11, 31, 33, 31, 0.5);
      for (let y = 10; y <= 22; y += 2) g.on(CX, y, 0.2);
      g.on(CX, 28, 0.6);
      // the arm
      for (let k = 0; k < 19; k++) {
        const [x, y] = polar(1.5 + (k / 18) * (Lr - 1.5), th, px, py);
        g.fr(x, y, k === 18 ? 1 : 0.8);
      }
      // the weight (2 x 2), riding lower as the minutes run out
      const rw = lerp(7.5, 15, cl(s / 5400));
      for (let u = -0.5; u <= 0.5; u += 1)
        for (let v = -0.5; v <= 0.5; v += 1) {
          const [x, y] = polar(rw + v, th, px, py);
          g.fr(x + Math.cos(th) * u, y + Math.sin(th) * u, 1, 1);
        }
      // the beat: a short arrow kicks out from the end of the swing
      const kick = c.T > 0.9 ? Math.exp(-q / 0.18) : 0, sd = side;
      for (let k = 0; k < 3; k++) {
        const [tx, ty] = polar(Lr, A * sd, px, py);
        const x = tx + sd * (2.2 + k * 0.9 + q * 3);
        g.fr(x, ty + (k === 1 ? 0 : k === 0 ? -1 : 1) * (k === 1 ? 0 : 1), 0.8 * kick);
      }
      return {o: {stagger: 0.3}};
    },
  },
  // Sat: THE MAINSPRING. A coil of sixty lights winds out from the centre, one per second of the
  // minute. Its free end creeps back along the coil as the seconds go; when the minute turns, the
  // spring winds itself out again in one quick spin.
  {
    draw: (g, c) => {
      const {s, K, q} = tick(c);
      // sixty points spaced evenly along an Archimedean spiral, three and a half turns
      const turns = 2.6, r0 = 2, r1 = 14, M = 400, P: [number, number][] = [];
      let acc = 0, prev: [number, number] = polar(r0, 0), lens: number[] = [0], pts: [number, number][] = [prev];
      for (let k = 1; k <= M; k++) {
        const th = (k / M) * turns * TAU, p = polar(lerp(r0, r1, k / M), th);
        acc += Math.hypot(p[0] - prev[0], p[1] - prev[1]);
        lens.push(acc);
        pts.push(p);
        prev = p;
      }
      const at = (u: number): [number, number] => {
        const target = cl(u / 59) * acc;
        let k = 1;
        while (k < M && lens[k] < target) k++;
        const f = (target - lens[k - 1]) / Math.max(1e-6, lens[k] - lens[k - 1]);
        return [lerp(pts[k - 1][0], pts[k][0], f), lerp(pts[k - 1][1], pts[k][1], f)];
      };
      for (let i = 0; i < 60; i++) P.push(at(i));
      const wind = K % 60 === 59 && q < 0.55 ? ez(q / 0.55) : 1; // the rewind each minute
      const ent = ez((c.T - 0.05) / 0.7);
      const u = (s % 60) * Math.min(wind, ent); // where the free end is, in seconds
      // the coil, drawn densely: wound part bright, the run-down part faint
      const NS = Math.floor(acc / 0.95);
      for (let k = 0; k <= NS; k++) {
        const [x, y] = at((k / NS) * 59);
        g.on(x, y, (k / NS) * 59 < u ? 0.85 : 0.3);
      }
      void P;
      const [ex, ey] = at(u);
      g.fr(ex, ey, 1, 1);
      g.on(CX, CY, 0.6);
      return {o: {stagger: 0.3}, flash: wind < 1 ? (1 - wind) * 0.06 : 0};
    },
  },
  // Sun: THE PAGE. A page-a-day pad with this week on it, Sunday the last square. A row of marks
  // along the foot of the page counts the minute down; when the minute turns, the page tears off
  // and flies away, and the next one is already underneath.
  {
    draw: (g, c) => {
      const {K, q} = tick(c);
      const x0 = 12, y0 = 6, w = 21, h = 22;
      const tear = K % 60 === 59 && c.T > 1 ? q : 9; // seconds since this page went
      const ent = ez((c.T - 0.05) / 0.6);
      // the pad behind: the next page's edges, and the binding
      g.rect(x0 + 1, y0 + 1, w, h, 0.22 * ent);
      for (let x = x0; x < x0 + w; x++) g.on(x, y0 - 1, 0.7 * ent);
      g.on(x0 + 5, y0 - 2, 0.7 * ent);
      g.on(x0 + w - 6, y0 - 2, 0.7 * ent);
      // the page itself, as free dots so it can fly
      const fly = tear < 0.7 ? ez(tear / 0.7) : 0, back = tear < 1 ? ez((tear - 0.7) / 0.3) : 1;
      const vis = (tear < 0.7 ? 1 - fly : back) * ent;
      const put = (x: number, y: number, b: number, cc = 0) => {
        const dx = x - x0, dy = y - y0;
        const ox = fly * (6 + dy * 0.25), oy = -fly * (9 - dx * 0.2);
        g.fr(x + 0.5 + ox, y + 0.5 + oy, b * vis, cc);
      };
      for (let x = x0; x < x0 + w; x++) {
        put(x, y0, 0.75);
        put(x, y0 + h - 1, 0.75);
      }
      for (let y = y0 + 1; y < y0 + h - 1; y++) {
        put(x0, y, 0.75);
        put(x0 + w - 1, y, 0.75);
      }
      // the week: six days done, today the big square
      for (let i = 0; i < 6; i++) for (let v = 0; v < 2; v++) for (let u = 0; u < 2; u++) put(x0 + 2 + i * 3 + u, y0 + 3 + v, 0.5);
      for (let v = 0; v < 8; v++) for (let u = 0; u < 15; u++) put(x0 + 3 + u, y0 + 7 + v, 0.92, u === 7 && v === 3 ? 1 : 0);
      // the minute: twelve marks along the foot, one goes every five seconds
      const left = (K % 60) + 1 - (1 - q) * 0; // seconds left this minute
      for (let k = 0; k < 12; k++) {
        const on = k * 5 < left;
        put(x0 + 2 + k * 1.5, y0 + h - 4, on ? 0.85 : 0.15);
      }
      return {o: {stagger: 0.3}};
    },
  },
];
