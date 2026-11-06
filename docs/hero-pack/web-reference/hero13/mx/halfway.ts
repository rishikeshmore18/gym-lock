/**
 * Matrix Dynamic: halfway (day 33 of 66). One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * Every scene shows exactly half, with one beat when the half is reached, then a calm idle.
 */
import {CX, CY, G, MScn, back, cl, eio, ez, lerp, spr} from '../mxlib';
import {TAU} from './common';

// ---------- helpers (local to this file) ----------
/** a point on a circle: angle 0 = up, clockwise */
const pol = (cx: number, cy: number, r: number, a: number): [number, number] => [cx + Math.sin(a) * r, cy - Math.cos(a) * r];
/** a soft bump travelling along 0..1 every P seconds (for idle light sweeps) */
const sweep = (t: number, P: number, u: number, w = 0.12) => {
  const ph = ((t % P) + P) % P / P; // 0..1
  const d = (u - ph * 1.4 + 0.2) / w;
  return Math.exp(-d * d);
};
/** the hit: a quick decay after a moment */
const hit = (T: number, at: number, d = 0.15) => (T >= at ? Math.exp(-(T - at) / d) : 0);

/** a running track (stadium) centred on (22.5, 17.5): straights of 11, bends of radius r; s runs anticlockwise from the bottom centre */
const track = (s: number, r = 7): [number, number] => {
  const L = 11, cx = 22.5, cy = 17.5, half = L / 2, arc = Math.PI * r, P = 2 * L + 2 * arc;
  let u = ((s % P) + P) % P;
  if (u < half) return [cx + u, cy + r];
  u -= half;
  if (u < arc) return [cx + half + Math.sin(Math.PI - u / r) * r, cy - Math.cos(Math.PI - u / r) * r];
  u -= arc;
  if (u < L) return [cx + half - u, cy - r];
  u -= L;
  if (u < arc) return [cx - half - Math.sin(u / r) * r, cy - Math.cos(u / r) * r];
  u -= arc;
  return [cx - half + u, cy + r];
};
const trackLen = (r = 7) => 22 + 2 * Math.PI * r;

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
/** the 66: block k of digit d (0 left, 1 right), top-left cell of the block */
const block66 = (d: number, k: number): [number, number] => [8 + d * 16 + SIX[k][0] * 2, 6 + SIX[k][1] * 2];

export const SCENES: MScn[] = [
  // Mon: THE GAUGE. A 270-degree dial; the needle swings up and stops dead on 12 o'clock, exactly half
  {
    draw: (g, c) => {
      const T = c.T, cx = CX + 0.5, cy = CY + 3.5, R = 13;
      const A0 = (-3 * Math.PI) / 4, p = cl((T - 0.3) / 0.85);
      const th = A0 * (1 - back(p, 1.25));
      const lit = Math.min(th, 0) + 1e-3;
      const at = HIT_MON;
      // the track: a continuous arc, lit up to the needle (never past half), ghost beyond
      g.ring(cx, cy, R, 0.16, 0, Math.max(lit, A0), -A0);
      if (lit > A0) {
        const n = Math.max(1, Math.round((lit - A0) * R));
        for (let i = 0; i <= n; i++) {
          const a = A0 + ((lit - A0) * i) / n;
          g.on(...pol(cx, cy, R, a), 0.8 + 0.2 * sweep(c.t, 4.5, (a - A0) / -A0));
        }
      }
      // seven ticks inside the track, one every eleven days; the half mark is long
      for (let k = 0; k <= 6; k++) {
        const a = A0 + (k / 6) * (-2 * A0), on = a <= lit, major = k === 3;
        if (major) for (let r = R + 2; r <= R + 3; r++) g.on(...pol(cx, cy, r, a), on ? 1 : 0.3);
        else g.on(...pol(cx, cy, R - 2, a), on ? 0.7 : k === 6 ? 0.45 : 0.25);
      }
      // a short ping off the half mark when the needle lands
      const age = T - at;
      for (let s = -1; s <= 1; s++) {
        const a = s * 0.22, r = R + 3 + (age > 0 ? ez(age / 0.5) * 3 : 0), b = age > 0 && age < 0.55 ? (1 - age / 0.55) * (s ? 0.6 : 0.9) : 0;
        g.fr(...pol(cx, cy, r, a), b);
      }
      // the needle: free particles, one per cell of its length; the tip is you
      for (let r = 2; r <= 11; r++) g.fr(...pol(cx, cy, r, th), r === 11 ? 1 : 0.92, r === 11 ? 1 : 0);
      g.disc(cx, cy, 1.6, 0.9);
      // the readout counts to 33 as the needle climbs
      const n = Math.round(33 * cl(1 - th / A0));
      g.num(String(n).padStart(2, '0'), cx, cy + 5, 1, 0.75, 0.08);
      return {flash: hit(T, at, 0.14) * 0.22, shake: T > at && T < at + 0.16 ? 0.25 : 0};
    },
    hap: [{t: 0.3, kind: 'light'}, {t: 0.68, kind: 'heavy'}],
  },
  // Tue: THE TILE BOARD. Thirty-six tiles; the left half flips over from hollow to solid, column by column
  {
    draw: (g, c) => {
      const T = c.T, X0 = 11, Y0 = 6;
      const at = (col: number, r: number) => 0.3 + col * 0.16 + (2.5 - Math.abs(r - 2.5)) * 0.05 + (r === 2 ? 0.03 : 0);
      const end = at(2, 2) + 0.3;
      // the right half: hollow tiles, waiting (static structure)
      for (let col = 3; col < 6; col++)
        for (let r = 0; r < 6; r++) g.rect(X0 + col * 4, Y0 + r * 4, 3, 3, 0.3);
      // the left half: every tile is nine free dots that turn over in place
      for (let col = 0; col < 3; col++)
        for (let r = 0; r < 6; r++) {
          const k = cl((T - at(col, r)) / 0.3), ph = Math.PI * eio(k), w = Math.abs(Math.cos(ph)), front = ph > Math.PI / 2;
          const x = X0 + col * 4 + 1.5, y = Y0 + r * 4 + 1.5;
          const glow = front ? 0.82 + 0.18 * sweep(c.t, 5, (col * 4 + r * 4) / 40, 0.16) : 0;
          for (let v = -1; v <= 1; v++)
            for (let u = -1; u <= 1; u++) {
              const centre = u === 0 && v === 0, you = centre && col === 2 && r === 2;
              const b = front ? (you ? 1 : glow) : centre ? 0 : 0.3;
              g.fr(x + u * w, y + v, b, you && front ? 1 : 0);
            }
        }
      // the split: a notch above and below the board, lit once the half is turned
      const s = T > end ? 0.85 : 0.25;
      g.line(22, 2, 22, 4, s);
      g.line(22, 30, 22, 32, s);
      return {flash: hit(T, end, 0.14) * 0.2, shake: T > end && T < end + 0.15 ? 0.22 : 0};
    },
    hap: [{t: 0.3, kind: 'light'}, {t: 0.62, kind: 'light'}, {t: 1.16, kind: 'heavy'}],
  },
  // Wed: THE TRACK. A recorded waveform; the playhead glides to the exact middle, and the sound hits there
  {
    draw: (g, c) => {
      const T = c.T, mid = 22, cy = CY + 0.5;
      const H = [2, 4, 7, 3, 8, 5, 3, 4, 7, 4, 8, 5, 3, 2];
      const p = eio(cl((T - 0.3) / 0.85)), px = lerp(7, mid, p), end = 1.15;
      H.forEach((h0, i) => {
        const x = i < 7 ? 8 + i * 2 : 24 + (i - 7) * 2, played = x < px;
        const age = T - end - Math.abs(x - mid) * 0.025;
        const h = h0 + (age > 0 ? Math.round(2.4 * Math.exp(-age / 0.16)) : 0);
        const b = played ? 0.8 + 0.2 * sweep(c.t, 4.5, (x - 8) / 12) : 0.2;
        for (let j = -h; j <= h; j++) g.on(x, cy + j, b);
      });
      // the playhead: free dots that glide; the knob on top is you
      for (let y = 5; y <= 29; y++) g.fr(px + 0.5, y + 0.5, 0.95);
      for (const [u, v] of [[0, -1], [-1, 0], [1, 0], [0, 1], [0, 0]] as const) g.fr(px + 0.5 + u, 3.5 + v, 1, u === 0 && v === 0 ? 1 : 0);
      return {flash: hit(T, end, 0.14) * 0.2, shake: T > end && T < end + 0.15 ? 0.2 : 0};
    },
    hap: [{t: 0.3, kind: 'light'}, {t: 1.15, kind: 'heavy'}],
  },
  // Thu: THE WEIGHT STACK. The pin clicks into the middle plate, and exactly half the stack lifts
  {
    draw: (g, c) => {
      const T = c.T, pinIn = 0.7, lift0 = 0.85;
      const pin = ez(cl((T - 0.3) / 0.4)), up = 4 * back(cl((T - lift0) / 0.5), 1.2);
      const lifted = T > lift0;
      // guide rods, both sides
      for (const x of [13, 31]) g.line(x, 4, x, 31, 0.3);
      // ten plates: the top five ride the pin, the bottom five stay down
      for (let k = 0; k < 10; k++) {
        const top = k < 5, y = 13 + k * 2 - (top ? up : 0);
        const b = top ? (lifted ? 0.85 + 0.15 * sweep(c.t, 4.5, k / 5) : 0.6) : lifted ? 0.32 : 0.6;
        if (top) for (let x = 15; x <= 29; x++) g.fr(x + 0.5, y + 0.5, b);
        else g.line(15, y, 29, y, b);
      }
      // the head plate and the cable up to the pulley
      const hy = 11 - up;
      for (let x = 18; x <= 26; x++) g.fr(x + 0.5, hy + 0.5, lifted ? 0.9 : 0.6);
      for (let i = 0; i < 6; i++) g.fr(22.5, lerp(3.5, hy - 0.5, i / 5), 0.5);
      g.line(19, 2, 25, 2, 0.45);
      // the selector pin slides in under plate five; its head is you
      const py = 13 + 4 * 2 - up, px = lerp(37, 30, pin);
      for (let i = 0; i < 4; i++) g.fr(px + i + 0.5, py + 0.5, 0.9, i === 3 ? 1 : 0);
      const at = HIT_THU;
      return {flash: hit(T, at, 0.14) * 0.2 + hit(T, pinIn, 0.08) * 0.08, shake: T > at && T < at + 0.16 ? 0.25 : 0};
    },
    hap: [{t: 0.7, kind: 'medium'}, {t: 1.08, kind: 'heavy'}],
  },
  // Fri: THE VECTOR. A path corner to corner; the arrow fires and lands its tip on the exact midpoint
  {
    draw: (g, c) => {
      const T = c.T, at = 0.63;
      const k = 10 * back(cl((T - 0.35) / 0.5), 0.8), tx = 12 + k, ty = 27 - k;
      // the half still ahead: the same arrow again, as a ghost, ending in the far corner
      for (let x = 23; x <= 32; x++) g.on(x, 39 - x, 0.2), g.on(x + 1, 39 - x, 0.2);
      for (let j = 0; j <= 5; j++) for (let i = 0; i <= 5 - j; i++) g.on(35 - i, 4 + j, i + j === 5 || i === 0 || j === 0 ? 0.32 : 0.14);
      // the shaft lights up behind the head
      const tail = Math.floor(tx) - 3;
      for (let x = 9; x <= tail; x++) {
        const b = 0.78 + 0.22 * sweep(c.t, 4, (x - 9) / 11);
        g.on(x, 39 - x, b), g.on(x + 1, 39 - x, b);
      }
      // the head: a solid corner of free dots, the tip is you
      for (let j = 0; j <= 5; j++)
        for (let i = 0; i <= 5 - j; i++) g.fr(tx - i + 0.5, ty + j + 0.5, 1, i === 0 && j === 0 ? 1 : 0);
      // on landing, an echo of the head carries on along the path and fades
      const e = T - at;
      for (let i = 0; i <= 4; i++) {
        const d = e > 0 ? ez(e / 0.8) * 6 : 0, b = e > 0 && e < 0.8 ? 0.55 * (1 - e / 0.8) : 0;
        g.fr(22 - i + 0.5 + d, 17 + 0.5 - d, b);
        g.fr(22 + 0.5 + d, 17 + i + 0.5 - d, i ? b : 0);
      }
      return {flash: hit(T, at, 0.12) * 0.22, shake: T > at && T < at + 0.16 ? 0.3 : 0};
    },
    hap: [{t: 0.35, kind: 'light'}, {t: 0.63, kind: 'heavy'}],
  },
  // Sat: THE TRACK. One lap is 66 days; the runner goes half a lap and stands on the far side
  {
    draw: (g, c) => {
      const T = c.T, at = 1.4, HALF = trackLen() / 2;
      const s = HALF * eio(cl((T - 0.3) / 1.1));
      // the lane: two lines, the start line and the halfway line across it
      for (const r of [5, 9]) {
        const P = trackLen(r);
        for (let u = 0; u < P; u += 0.5) g.on(...track((u / P) * trackLen(), r).map((v, i) => (i ? v + (r - 7) * 0 : v)) as [number, number], 0.2);
      }
      g.line(22, 22, 22, 26, 0.6);
      g.line(22, 8, 22, 12, T > at ? 1 : 0.3);
      // the lap so far, lit along the middle of the lane
      for (let u = 0; u <= s; u += 0.5) g.on(...track(u), 0.8 + 0.2 * sweep(c.t, 4.5, u / HALF));
      // the runner: you, with a short tail
      for (let i = 3; i >= 0; i--) g.fr(...track(Math.max(0, s - i * 0.9)), i ? (s > 0.5 ? 0.7 - i * 0.18 : 0) : 1, i ? 0 : 1);
      return {flash: hit(T, at, 0.14) * 0.2, shake: T > at && T < at + 0.15 ? 0.22 : 0};
    },
    hap: [{t: 0.3, kind: 'light'}, {t: 1.4, kind: 'heavy'}],
  },
  // Sun: HALF THE SHAPE. A 66 made of 66 day-pieces; the first 33 set themselves into place, the rest wait as a ghost
  {
    draw: (g, c) => {
      const T = c.T, at = 0.25 + 32 * 0.022 + 0.2;
      // the second 6: thirty-three empty places
      for (let k = 0; k < 33; k++) {
        const [x, y] = block66(1, k);
        g.rect(x, y, 2, 2, 0.18, true);
      }
      // the first 6: each piece drops into its place in pen order; the last piece is you
      for (let k = 0; k < 33; k++) {
        const [x, y] = block66(0, k), a = cl((T - 0.25 - k * 0.022) / 0.2), dy = (1 - ez(a)) * -2.5;
        const last = k === 32, b = a <= 0 ? 0 : last ? 1 : 0.84 + 0.16 * sweep(c.t, 5, k / 33);
        for (let v = 0; v < 2; v++) for (let u = 0; u < 2; u++) g.fr(x + u + 0.5, y + v + 0.5 + dy, b, last ? 1 : 0);
      }
      return {flash: hit(T, at, 0.14) * 0.2, shake: T > at && T < at + 0.14 ? 0.2 : 0};
    },
    hap: [{t: 0.25, kind: 'light'}, {t: 1.15, kind: 'heavy'}],
  },
];

// the needle first reaches 12 o'clock here (back easing crosses 1 at about 64% of the swing)
const HIT_MON = 0.68;
// the top half first reaches full height here
const HIT_THU = 1.08;

void CY;
void G;
void eio;
void lerp;
void spr;
void TAU;
