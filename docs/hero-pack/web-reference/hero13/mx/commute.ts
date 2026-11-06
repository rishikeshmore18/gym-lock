/**
 * Matrix Dynamic: commute. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 *
 * You are on the way: every day shows the distance closing a different way. You are the one coral
 * dot; everything that moves is a free particle with a fixed slot, so nothing smears or re-keys.
 */
import {CX, CY, G, MScn, cl, eio, ez, lerp} from '../mxlib';
import {TAU} from './common';

const OX = CX + 0.5, OY = CY + 0.5;
const polar = (r: number, a: number, ox = OX, oy = OY): [number, number] => [ox + Math.sin(a) * r, oy - Math.cos(a) * r];
/** trip progress: a quick glide to p1 on entry (the beat), then a slow creep toward p2 */
const trip = (T: number, p0: number, p1: number, p2: number, glide = 1.4) =>
  T < glide ? lerp(p0, p1, eio(T / glide)) : p1 + (p2 - p1) * (1 - Math.exp(-(T - glide) / 120));
/** a point along a polyline, by distance */
const along = (W: [number, number][], d: number): [number, number] => {
  for (let i = 1; i < W.length; i++) {
    const [ax, ay] = W[i - 1], [bx, by] = W[i], L = Math.hypot(bx - ax, by - ay);
    if (d <= L || i === W.length - 1) {
      const u = cl(d / L);
      return [lerp(ax, bx, u), lerp(ay, by, u)];
    }
    d -= L;
  }
  return W[W.length - 1];
};
const plen = (W: [number, number][]) => W.slice(1).reduce((s, p, i) => s + Math.hypot(p[0] - W[i][0], p[1] - W[i][1]), 0);
const glyph = (g: G, rows: string[], x: number, y: number, b: number) =>
  rows.forEach((r, j) => [...r].forEach((ch, i) => ch === '#' && g.on(x + i, y + j, b)));
const LOCK = ['..###..', '.#...#.', '.#...#.', '#######', '#######', '###.###', '###.###', '#######'];
const FLAG = ['#####', '#####', '#####', '#....', '#....', '#....', '#....', '#....', '#....', '#....'];

export const SCENES: MScn[] = [
  // Mon: RADAR. The gym is the centre of the scope; you are the blip. Each pass of the sweep pings you
  // a little closer in, and the old fix fades.
  {
    draw: (g, c) => {
      const T = c.T, P = 2.8, ya = 0.95;
      const rTrue = (t: number) => 3.6 + 9.6 * Math.exp(-t / 26);
      const open = ez(T / 0.6);
      [4.5, 9, 13.5].forEach((r, k) => g.ring(CX, CY, r * open, k === 2 ? 0.34 : 0.24, 0, 0, TAU, r * open, 2));
      g.rect(CX - 1, CY - 1, 3, 3, 0.9 * open, true);
      // the sweep, with a short fading wedge behind it (free particles)
      const a = (T / P) * TAU;
      for (let w = 0; w < 3; w++)
        for (let k = 0; k < 13; k++) {
          const [x, y] = polar(2.2 + k, a - w * 0.13);
          g.fr(x, y, [0.85, 0.36, 0.14][w] * open);
        }
      // the blip updates when the sweep crosses it
      const n = Math.floor(T / P - ya / TAU), Tn = (n + ya / TAU) * P, age = T - Tn;
      const rNow = n < 0 ? rTrue(0) : rTrue(Tn), rOld = n < 1 ? rTrue(0) : rTrue(Tn - P);
      const ping = n < 0 ? 0 : Math.exp(-age / 0.9);
      const [bx, by] = polar(rNow, ya), [gx, gy] = polar(rOld, ya);
      for (let u = -0.5; u <= 0.5; u += 1) for (let v = -0.5; v <= 0.5; v += 1) g.fr(bx + u, by + v, (0.5 + 0.5 * ping) * open, 1);
      g.fr(gx, gy, n < 1 ? 0 : 0.55 * Math.exp(-age / 0.6));
      for (let k = 0; k < 10; k++) {
        const [x, y] = polar(1.2 + cl(age / 0.6) * 2.6, (k / 10) * TAU, bx, by);
        g.fr(x, y, n < 0 ? 0 : 0.55 * (1 - cl(age / 0.6)));
      }
      return {o: {stagger: 0.25}};
    },
  },
  // Tue: THE CITY GRID. Blocks of the map as tiles; the route runs up the streets to the lit gym
  // block. You move along it, and only the way ahead is drawn.
  {
    draw: (g, c) => {
      const T = c.T, bx = (i: number) => 10 + i * 7, by = (j: number) => 5 + j * 7;
      for (let j = 0; j < 4; j++)
        for (let i = 0; i < 4; i++) {
          const gym = i === 3 && j === 0, vis = ez((T - (i + 3 - j) * 0.05) / 0.3);
          g.rect(bx(i), by(j), 4, 4, (gym ? 0.8 + 0.12 * Math.sin(c.t * 1.6) : 0.2) * vis, true);
        }
      const W: [number, number][] = [[15.5, 33.5], [15.5, 24.5], [22.5, 24.5], [22.5, 17.5], [29.5, 17.5], [29.5, 10.5], [33, 10.5]];
      const L = plen(W), d = trip(T, 0.12, 0.5, 0.93, 1.6) * L;
      // the way ahead, dotted
      const draw = ez((T - 0.2) / 0.6);
      for (let e = Math.ceil(d / 2) * 2 + 2; e <= L; e += 2) {
        if ((e - d) / (L - d) > draw) break;
        const [x, y] = along(W, e);
        g.on(x, y, 0.62);
      }
      // a light runs ahead of you to the gym every few seconds
      const lp = ((T - 0.8) % 2.6) / 0.9;
      for (let k = 0; k < 2; k++) {
        const [x, y] = along(W, d + (L - d) * cl(lp - k * 0.06));
        g.fr(x, y, T > 0.8 && lp < 1 ? (k ? 0.4 : 0.85) * (1 - lp * 0.5) : 0);
      }
      // you
      const [x, y] = along(W, d);
      g.fr(x, y, 1, 1);
      for (const [u, v] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) g.fr(x + u, y + v, 0.5);
      return {o: {stagger: 0.25}};
    },
  },
  // Wed: THE CARRIER. A signal wave runs from you to the lock. The closer you are, the shorter and
  // stronger it gets; you keep riding in on it, and the lock opens when you walk in.
  {
    draw: (g, c) => {
      const T = c.T, y0 = 19.5, x0 = 8, x1 = 27;
      const p = trip(T, 0, 0.55, 0.9, 1.8), xu = lerp(x0 + 0.5, x1 - 3, p);
      const draw = ez((T - 0.05) / 0.6);
      for (let i = 0; i < 40; i++) {
        const x = x0 + 0.5 + i * 0.5;
        const ahead = x >= xu, fr = (x - xu) / Math.max(1, x1 - xu);
        const A = (1.2 + 4.2 * (0.35 + 0.65 * p) * fr) * draw;
        const y = ahead ? y0 + A * Math.sin((x - xu) * 1.15 - c.t * 4.2) : y0;
        g.fr(x, y, ahead ? (0.45 + 0.5 * fr) * draw : x > x0 + 1 ? 0.18 : 0);
      }
      g.fr(xu, y0, 1, 1);
      const pulse = 0.5 + 0.5 * Math.sin(c.t * 4.2 - 1.2);
      glyph(g, LOCK, 29, 15, (0.7 + 0.3 * pulse * p) * ez((T - 0.3) / 0.4));
      return {o: {stagger: 0.25}};
    },
  },
  // Thu: THE RAMP. Home, then ten bars climbing to the flag. The bars you've passed are lit, the one
  // you're on fills under you; showing up is most of it.
  {
    draw: (g, c) => {
      const T = c.T, base = 29, p = trip(T, 0.05, 0.72, 0.97, 1.8) * 10;
      glyph(g, ['..#..', '.###.', '#####', '#.#.#', '#####'], 8, base - 4, 0.75);
      for (let i = 0; i < 10; i++) {
        const x = 14 + i * 2.2, h = Math.round(3 + i * 2), fill = cl(p - i), vis = ez((T - i * 0.04) / 0.3);
        const lit = Math.round(h * fill);
        for (let j = 0; j < h; j++) g.on(x, base - j, (j < lit ? 0.85 : j === h - 1 ? 0.3 : 0.12) * vis);
      }
      // you: the top of what's filled
      const i = Math.min(9, Math.floor(p)), h = 3 + i * 2, x = 14 + i * 2.2;
      g.fr(Math.floor(x) + 0.5, base + 0.5 - Math.max(0, h * cl(p - i) - 1) - 1, 1, 1);
      glyph(g, FLAG, 34, base - 25, 0.85 * ez((T - 0.4) / 0.4));
      return {o: {stagger: 0.25}};
    },
  },
  // Fri: THE ROAD. Arrows painted on the lane stream toward you; the gym's pin waits where the road
  // meets the distance.
  {
    draw: (g, c) => {
      const T = c.T, vy = 9, open = ez(T / 0.6);
      g.line(21, vy + 1, 9, 33, 0.42 * open, 0, 2);
      g.line(23, vy + 1, 35, 33, 0.42 * open, 0, 2);
      // the pin (its centre is the gym)
      // the gym: a lit gate across the road where it meets the distance
      for (let x = 17; x <= 27; x++) g.on(x, vy, 0.9 * open, x === 22 ? 1 : 0);
      g.line(17, vy - 3, 17, vy, 0.7 * open);
      g.line(27, vy - 3, 27, vy, 0.7 * open);
      g.line(17, vy - 3, 27, vy - 3, 0.7 * open);
      const AR: [number, number][] = [[0, -3], [-1, -2], [1, -2], [-2, -1], [2, -1], [0, -2], [0, -1], [0, 0], [0, 1], [0, 2]];
      const sp = 0.3 * (0.7 + 0.3 * Math.exp(-T / 3));
      for (let k = 0; k < 6; k++) {
        const z = ((T * sp + k / 6) % 1 + 1) % 1, y = vy + 1.5 + 23 * z * z, s = 0.25 + 1.45 * z * z;
        const b = cl(z * 4) * cl((1 - z) / 0.18) * open, lane = (k % 2 ? 1 : -1) * (0.6 + 5.5 * z * z);
        for (const [u, v] of AR) g.fr(OX + lane + u * s, y + v * s, b * 0.85);
      }
      return {o: {stagger: 0.25}};
    },
  },
  // Sat: ROLLING IN. A wheel rolls in from the left along the road toward the gym's flag, then keeps
  // turning slowly, closing the last stretch.
  {
    draw: (g, c) => {
      const T = c.T, gy = 29, R = 7.5, cy = gy - R - 0.5;
      for (let x = 8; x <= 37; x += 2) g.on(x, gy, 0.3);
      glyph(g, FLAG, 33, gy - 10, 0.85);
      const xc = lerp(-6, 25, trip(T, 0, 0.7, 0.9, 2.2)), rot = (xc + 6) / R;
      for (let k = 0; k < 34; k++) {
        const [x, y] = polar(R, rot + (k / 34) * TAU, xc, cy);
        g.fr(x, y, k === 0 ? 1 : 0.8, k === 0 ? 1 : 0);
      }
      for (let sk = 0; sk < 6; sk++)
        for (let k = 1; k <= 5; k++) {
          const [x, y] = polar(k * 1.15, rot + (sk / 6) * TAU + 0.26, xc, cy);
          g.fr(x, y, 0.45);
        }
      g.fr(xc, cy, 0.9);
      return {o: {stagger: 0.25}};
    },
  },
  // Sun: THE CALENDAR. Today's column of the week, the gym at 07:00, and the travel time before it.
  // The now line slides into the travel block and moves down it, minute by minute: six to go.
  {
    draw: (g, c) => {
      const T = c.T, top = 8, ev = 23, xl = 13, xr = 36;
      const vis = ez(T / 0.5);
      // the week strip, today lit
      for (let i = 0; i < 7; i++) g.rect(9 + i * 4, 3, 3, 2, (i === 6 ? 0.9 : 0.26) * vis, true);
      // travel time, hatched
      for (let y = top; y < ev; y++) for (let x = xl; x <= xr; x++) if ((x + y) % 3 === 0) g.on(x, y, 0.2 * vis);
      // the session block, a dumbbell cut out of it
      const DB = ['##.......##', '##.......##', '###########', '##.......##', '##.......##'];
      for (let y = ev; y <= 31; y++)
        for (let x = xl; x <= xr; x++) {
          const u = x - 19, v = y - 25;
          const hole = v >= 0 && v < 5 && u >= 0 && u < 11 && DB[v][u] === '#';
          if (!hole) g.on(x, y, 0.78 * vis);
        }
      // minute ticks on the time axis; the ones still ahead are bright
      const nowM = Math.min(14.6, 9 * eio(T / 1.4) + T / 60); // minutes after 06:45, real time
      for (let m = 0; m <= 15; m++) g.on(10, top + m, (m > nowM ? 0.62 : 0.14) * vis);
      // the now line: a coral dot and a line, free so it slides
      const yn = top + 0.5 + nowM;
      g.fr(10.5, yn, 1, 1);
      for (let x = 11; x <= xr; x++) g.fr(x + 0.5, yn, 0.85 * ez((T - 0.1 - (x - 11) * 0.01) / 0.4));
      return {o: {stagger: 0.25}};
    },
  },
];
