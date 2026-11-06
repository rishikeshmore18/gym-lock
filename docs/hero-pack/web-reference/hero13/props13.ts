/**
 * Dynamic: every moment on every day is its own short scene, directed like a shot.
 *
 * Each scene has
 *   bd    the painted world behind it (Ridge only): the day's place, lit for the hour
 *   draw  the scene's own objects, as shapes both modes render
 *   cam   a camera move: reveal, push, pan, crane, punch, shake
 *   hap   haptics on the same frames as the visual beats
 *
 * Rules the table follows
 *   - Inside a day no two moments share their main object. The world (the lake, the rock, the pine)
 *     stays, so the day still reads as one place, but the alarm, the countdown, the gym and the done
 *     card each bring something of their own.
 *   - Across days the same moment never uses the same object. Each moment keeps one idea so it reads
 *     instantly (the alarm always breaks a stillness in beats; bedtime always fills; the gym always
 *     counts 20 minute marks; week kept always counts to five), drawn in that day's world.
 *   - Motion onset, not constant motion, is what catches the eye (Abrams & Christ 2003), so scenes hold,
 *     then fire a beat, then settle, and re-fire every few seconds instead of looping endlessly.
 *   - Anticipation before the main action, follow-through after it (Chang & Ungar 1993).
 *   - New things light up the brain's reward system and familiar ones stop doing so
 *     (Bunzeck & Düzel 2006): hence 133 different scenes.
 */
import type {D4, S4} from '../hero4/card4';
import {PROOF} from '../hero4/card4';
import type {Pos} from '../hero11/copy11';
import {grow} from '../hero11/scenes11';
import type {Data11} from '../hero11/scenes11';
import {boulderGeom, layoutFor} from '../hero10/wash';
import {pathLayout, routeOf} from '../hero10/wash2';
import type {Scene3} from '../hero12/wash3';
import type {Day} from '../hero12/days12';
import {WSEED} from '../hero12/scenes12';
import {Cam, Mat, Shape, toStage} from './stage13';

// ---------- the world's anchor points, in stage units (same for both modes) ----------
const L = layoutFor(1000, 488);
const RB = boulderGeom(1000, 488, WSEED[1]);
const [rockX, rockBot] = toStage(RB.cx, RB.by);
const rockW = RB.bw / 4.75, rockH = RB.bh / 4.75;
const ROUTE = routeOf(1000, 488, L, pathLayout(L, 1000, 488)).map(([x, y, , m]) => [...toStage(x, y), m ? 1 : 0] as [number, number, number]);
const SUMMIT = ROUTE[ROUTE.length - 1];
export const A = {
  cloud: toStage(0, 0.6 * 488)[1],
  sunX: toStage(700, 0)[0],
  sunY: (s: number) => toStage(0, 0.6 * 488 - (s + 0.1) * 488 * 0.35)[1],
  sunR: (0.07 * 488) / 4.75,
  peak2: toStage(880, 0.36 * 488),
  ledge: toStage(0, L.ledgeTop)[1],
  rock: {x: rockX, bot: rockBot, w: rockW, h: rockH, top: rockBot - rockH},
  treeX: toStage(L.treeX, 0)[0],
  treeTop: (g: number) => toStage(0, L.ledgeTop - L.treeH * g * 0.85)[1],
  water: toStage(0, 0.64 * 488)[1],
  boat: toStage(700, 0.8 * 488),
  route: ROUTE,
  summit: [SUMMIT[0], SUMMIT[1]] as [number, number],
  horizon: toStage(0, 0.6 * 488)[1],
  sand: toStage(0, 0.78 * 488)[1],
  seaSun: toStage(660, 0.6 * 488 - 0.08 * 488),
  nightWater: toStage(0, 0.66 * 488)[1],
};
export const routeAt = (u: number): [number, number] => {
  const k = Math.max(0, Math.min(1, u)) * (ROUTE.length - 1), i = Math.floor(k), f = k - i;
  const a = ROUTE[i], b = ROUTE[Math.min(ROUTE.length - 1, i + 1)];
  return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
};

// ---------- motion helpers ----------
const cl = (x: number) => Math.min(1, Math.max(0, x));
export const ez = (x: number) => 1 - Math.pow(1 - cl(x), 3);
const eio = (x: number) => {
  const t = cl(x);
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
};
/** ease out with overshoot (follow-through) */
const back = (x: number, k = 1.7) => {
  const t = cl(x) - 1;
  return 1 + (k + 1) * t * t * t + k * t * t;
};
/** a small pull the other way before the move (anticipation) */
const antic = (x: number) => (x < 0.18 ? -0.12 * Math.sin((x / 0.18) * Math.PI) : back((x - 0.18) / 0.82));
/** a damped spring from 0 to 1 */
const spr = (x: number, w = 12, z = 5) => (x <= 0 ? 0 : 1 - Math.exp(-x * z) * Math.cos(x * w));
/** sharp onset, quick decay, once per period */
const pulse = (t: number, P: number, w = 0.14, off = 0) => Math.exp(-((((t - off) % P) + P) % P) / w);
const since = (T: number, at: number) => T - at;
const rnd = (i: number) => {
  let x = (Math.floor(i * 997) ^ 0x9e3779b9) >>> 0;
  x = Math.imul(x ^ (x >>> 16), 0x85ebca6b) >>> 0;
  x = Math.imul(x ^ (x >>> 13), 0xc2b2ae35) >>> 0;
  return ((x ^ (x >>> 16)) >>> 0) / 4294967296;
};
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// ---------- shape helpers ----------
const ln = (p: number[], m: Mat, a = 1, w = 0.8, dash?: number): Shape => ({k: 'line', p, m, a, w, dash});
const dk = (x: number, y: number, r: number, m: Mat, a = 1): Shape => ({k: 'disc', x, y, r, m, a});
const rg = (x: number, y: number, r: number, m: Mat, a = 1, w = 0.7, ry?: number, a0?: number, a1?: number, dash?: number): Shape => ({k: 'ring', x, y, r, ry, m, a, w, a0, a1, dash});
const pg = (p: number[], m: Mat, a = 1): Shape => ({k: 'poly', p, m, a});
/** a feathered wash (fog, cloud, light): no rim */
const pgs = (p: number[], m: Mat, a = 1): Shape => ({k: 'poly', p, m, a, soft: true});
/** shapes that already sit at their true size in the world (a snowfield, a shadow): embolden leaves them be */
const FIX = new WeakSet<Shape>();
/** a tapered shaft from (x0,y0) to (x1,y1), w0 wide at the start and w1 at the end */
const wedge = (x0: number, y0: number, x1: number, y1: number, w0: number, w1: number): number[] => {
  const L = Math.hypot(x1 - x0, y1 - y0) || 1, nx = -(y1 - y0) / L, ny = (x1 - x0) / L;
  return [x0 + nx * w0 / 2, y0 + ny * w0 / 2, x1 + nx * w1 / 2, y1 + ny * w1 / 2, x1 - nx * w1 / 2, y1 - ny * w1 / 2, x0 - nx * w0 / 2, y0 - ny * w0 / 2];
};
const fx = <T extends Shape | Shape[]>(q: T): T => {
  (Array.isArray(q) ? q : [q]).forEach((z) => FIX.add(z));
  return q;
};
const ds = (p: number[], r: number, m: Mat, a = 1): Shape => ({k: 'dots', p, r, m, a});
const gl = (x: number, y: number, r: number, m: Mat, a = 1): Shape => ({k: 'glow', x, y, r, m, a});
const fl = (a: number, m: Mat = 'light'): Shape => ({k: 'flash', a, m});
const ell = (x: number, y: number, rx: number, ry: number, n = 12, rot = 0): number[] => {
  const o: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const ex = Math.cos(a) * rx, ey = Math.sin(a) * ry;
    o.push(x + ex * Math.cos(rot) - ey * Math.sin(rot), y + ex * Math.sin(rot) + ey * Math.cos(rot));
  }
  return o;
};
/** a small bird, wings by flap phase */
const bird = (x: number, y: number, s0: number, ph: number, m: Mat = 'ink', a = 1): Shape => {
  const s = s0 * 1.6;
  const f = Math.sin(ph) * 0.7;
  return ln([x - s, y - s * (0.2 + f * 0.5), x - s * 0.4, y - s * 0.05, x, y + s * 0.1, x + s * 0.4, y - s * 0.05, x + s, y - s * (0.2 + f * 0.5)], m, a, 0.48);
};
/** a small pine */
const pine = (x: number, base: number, h: number, m: Mat = 'ink', a = 1): Shape[] => {
  const o: Shape[] = [ln([x, base, x, base - h * 0.3], m, a, 0.7)];
  for (let k = 0; k < 3; k++) {
    const top = base - h + k * h * 0.24, b = top + h * 0.42, hw = h * (0.16 + k * 0.08);
    o.push(pg([x, top, x + hw, b, x - hw, b], m, a));
  }
  return o;
};
const star4 = (x: number, y: number, r: number, m: Mat, a = 1): Shape[] => [dk(x, y, r * 0.45, m, a), ln([x - r, y, x + r, y], m, a * 0.8, r * 0.18), ln([x, y - r, x, y + r], m, a * 0.8, r * 0.18)];
const zig = (x0: number, y0: number, x1: number, y1: number, n: number, amp: number, seed: number): number[] => {
  const o: number[] = [];
  for (let i = 0; i <= n; i++) {
    const u = i / n;
    const j = i === 0 || i === n ? 0 : (rnd(seed + i) - 0.5) * amp;
    o.push(lerp(x0, x1, u) + j, lerp(y0, y1, u) + j * 0.3);
  }
  return o;
};
const fallers = (n: number, t: number, x0: number, x1: number, y0: number, y1: number, speed: number, seed: number, sway = 0): number[] => {
  const o: number[] = [];
  for (let i = 0; i < n; i++) {
    const p = (rnd(seed + i) + t * speed * (0.7 + rnd(seed + i + 50) * 0.6)) % 1;
    o.push(lerp(x0, x1, rnd(seed + i + 100)) + Math.sin(t * 1.3 + i) * sway, lerp(y0, y1, p));
  }
  return o;
};
const burstPts = (x: number, y: number, n: number, age: number, sp: number, grav: number, seed: number, up = true): number[] => {
  const o: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = up ? -Math.PI * (0.08 + rnd(seed + i) * 0.84) : rnd(seed + i) * Math.PI * 2;
    const v = sp * (0.5 + rnd(seed + i + 7) * 0.7);
    o.push(x + Math.cos(a) * v * age, y + Math.sin(a) * v * age + grav * age * age);
  }
  return o;
};

// ---------- the scene context ----------
export type PC = {t: number; T: number; at: number; d: D4; day: Day; pos: Pos; n: number; D: Data11; N: number; matrix: boolean};
type HK = 'light' | 'medium' | 'heavy' | 'success';
export type Hap = {t: number; kind: HK}[];
export type TypeStyle = 'slam' | 'rise' | 'track' | 'type' | 'blur' | 'wipe' | 'drop' | 'stamp' | 'jolt';
type P = Partial<Scene3> & {kind?: Scene3['kind']};
export type Scn = {bd?: (c: PC) => P; draw: (c: PC) => Shape[]; cam?: (c: PC) => Partial<Cam>; hap?: Hap; type?: TypeStyle; zoom?: number};

const charge = (t: number) => Math.min(0.98, 0.18 + ((t * 0.02) % 0.8));
const liveP = (c: PC) => cl(c.d.atgym / PROOF);
const hitAt = (c: PC) => (c.d.atgym >= PROOF ? c.T - (c.d.atgym - PROOF) : null); // in state time
const cdP = (c: PC) => 1 - cl(c.d.countdown / 7200);
const slP = (c: PC) => cl(c.d.stillLeft / (6 * 3600));
const RINGS = [0.35, 0.85, 1.35, 1.85, 2.35];
/** the alarm's beats: five fast, then one every 2.5 s */
const ringBeat = (T: number) => {
  let v = 0;
  for (const b of RINGS) if (T >= b) v = Math.max(v, Math.exp(-(T - b) / 0.13));
  if (T > 2.6) v = Math.max(v, pulse(T, 2.5, 0.13, 0.35));
  return v;
};
const lastRing = (T: number) => {
  let last = -1;
  for (const b of RINGS) if (T >= b) last = b;
  if (T > 2.6) last = Math.floor((T - 0.35) / 2.5) * 2.5 + 0.35;
  return last;
};
const ringHap: Hap = [...RINGS.map((t, i) => ({t, kind: (i % 2 ? 'medium' : 'heavy') as HK}))];

/** the minute marks of the 20 minutes: the newest one flares when it lands */
const minuteFlare = (c: PC) => {
  const m = c.d.atgym / 60;
  return Math.exp(-(m % 1) * 60 / 0.9); // seconds since the last minute mark
};

// =====================================================================================
//                                  THE SCENES
// =====================================================================================
const W: Record<S4, Scn[]> = {
  // ---------------- setup: the system assembles, one piece per checklist item (endowed progress) ----------------
  setup: [
    // Mon: three foothills rise out of the cloud sea
    {
      draw: (c) => {
        const o: Shape[] = [];
        const xs = [34, 58, 78], hs = [13, 17, 11];
        xs.forEach((x, i) => {
          const on = i < c.n;
          const h = hs[i] * (on ? back(since(c.T, 0.25 + i * 0.18) / 0.7) : 0.12);
          o.push(pg([x - 9, A.cloud + 1, x - 2, A.cloud - h * 0.8, x, A.cloud - h, x + 3, A.cloud - h * 0.75, x + 10, A.cloud + 1], on ? 'mid' : 'mist', on ? 0.9 : 0.5));
          if (on) o.push(pg([x - 2, A.cloud - h * 0.8, x, A.cloud - h, x + 3, A.cloud - h * 0.75, x + 1, A.cloud - h * 0.62], 'light', 0.9));
          else o.push(ln([x - 8, A.cloud - 1, x, A.cloud - hs[i], x + 9, A.cloud - 1], 'mist', 0.5, 0.4, 1));
        });
        if (c.n > 0) o.push(dk(xs[c.n - 1], A.cloud - hs[c.n - 1] - 3, 0.9, 'coral', 0.6 + 0.4 * Math.sin(c.t * 4)));
        return o;
      },
    },
    // Tue: a foundation of three stones, laid one by one
    {
      draw: (c) => {
        const o: Shape[] = [];
        [62, 70.5, 79].forEach((x, i) => {
          const on = i < c.n;
          const drop = on ? 1 - back(since(c.T, 0.3 + i * 0.2) / 0.55, 1.2) : 0;
          const y = A.ledge - 2.6 - drop * 16;
          o.push(on ? pg(ell(x, y, 4, 2.7, 12), 'ink') : rg(x, A.ledge - 2.6, 4, 'mid', 0.5, 0.35, 2.7, 0, Math.PI * 2, 1));
          if (on && drop < 0.05 && since(c.T, 0.3 + i * 0.2) < 1.2) o.push(rg(x, A.ledge, 4 + since(c.T, 0.85 + i * 0.2) * 9, 'mist', cl(1 - since(c.T, 0.85 + i * 0.2) * 2), 0.5, 1.2));
        });
        return o;
      },
    },
    // Wed: three cattails grow from the shallows
    {
      draw: (c) => {
        const o: Shape[] = [];
        [56, 63, 70].forEach((x, i) => {
          const on = i < c.n;
          const h = (on ? ez(since(c.T, 0.2 + i * 0.22) / 0.8) : 0.15) * (16 + i * 3);
          const sw = Math.sin(c.t * 1.1 + i) * 0.6;
          o.push(ln([x, A.water + 6, x + sw * 0.5, A.water + 6 - h * 0.5, x + sw, A.water + 6 - h], on ? 'ink' : 'mist', on ? 1 : 0.5, 0.5));
          if (on) o.push(pg(ell(x + sw, A.water + 6 - h + 2, 0.9, 2.4, 10), 'ink'));
          o.push(rg(x, A.water + 6.5, 2.5, 'mist', 0.6, 0.3, 0.6));
        });
        return o;
      },
    },
    // Thu: seed, sprout, sapling
    {
      draw: (c) => {
        const o: Shape[] = [];
        const x = 60, g = A.ledge;
        o.push(...pine(x, g, 34, 'mist', 0.35).map((s) => (s.k === 'poly' ? ({...s, a: 0.2} as Shape) : s)));
        const st = c.n;
        const k = back(since(c.T, 0.25) / 0.7);
        if (st === 0) o.push(dk(x, g - 1, 1.1, 'ink'));
        if (st >= 1) o.push(ln([x, g, x, g - 4 * k], 'ink', 1, 0.5), pg(ell(x - 1.6, g - 4 * k, 1.6, 0.7, 8, -0.5), 'ink'), pg(ell(x + 1.6, g - 4 * k, 1.6, 0.7, 8, 0.5), 'ink'));
        if (st >= 2) o.push(...pine(x, g, 9 + 5 * k * (st - 1)));
        if (st >= 1) o.push(dk(x, g - (st >= 2 ? 9 + 5 * (st - 1) : 4.6) - 1.2, 0.7, 'coral', 0.8));
        return o;
      },
    },
    // Fri: contour lines map the climb; three waypoints placed
    {
      draw: (c) => {
        const o: Shape[] = [];
        const [sx, sy] = A.summit;
        for (let k = 0; k < 4; k++) {
          const p = ez(since(c.T, 0.15 + k * 0.12) / 0.6);
          o.push(rg(sx, sy + 6 + k * 5, (8 + k * 7) * p, 'mid', 0.5, 0.35, (4 + k * 4) * p, 0, Math.PI * 2, 1.2));
        }
        [0.3, 0.6, 0.88].forEach((u, i) => {
          const [x, y] = routeAt(u);
          const on = i < c.n;
          const s = on ? back(since(c.T, 0.4 + i * 0.15) / 0.5) : 1;
          o.push(pg([x, y - 1.8 * s, x + 1.4 * s, y, x, y + 1.8 * s, x - 1.4 * s, y], i === c.n - 1 ? 'coral' : on ? 'ink' : 'mist', on ? 1 : 0.6));
        });
        return o;
      },
    },
    // Sat: three driftwood posts planted in the sand
    {
      draw: (c) => {
        const o: Shape[] = [];
        const xs = [40, 49, 58];
        xs.forEach((x, i) => {
          const on = i < c.n;
          const h = on ? back(since(c.T, 0.25 + i * 0.2) / 0.5) * 9 : 0;
          const y = A.sand + 3 - i * 0.6;
          if (on) o.push(pg([x - 0.9, y, x - 0.6, y - h, x + 0.6, y - h - 0.4, x + 0.9, y], 'ink'));
          else o.push(rg(x, y, 1.6, 'mist', 0.6, 0.35, 0.5));
          if (on && i > 0 && i < c.n) o.push(ln([xs[i - 1], y - 7 + 0.6, (xs[i - 1] + x) / 2, y - 5.6, x, y - 7], 'mid', 0.9, 0.3));
        });
        return o;
      },
    },
    // Sun: three stars ignite and join into a triangle
    {
      draw: (c) => {
        const o: Shape[] = [];
        const P = [
          [42, 22],
          [58, 10],
          [68, 28],
        ];
        for (let i = 1; i < Math.min(3, c.n); i++) o.push(ln([P[i - 1][0], P[i - 1][1], P[i][0], P[i][1]], 'light', 0.6, 0.35));
        if (c.n === 3) o.push(ln([P[2][0], P[2][1], P[0][0], P[0][1]], 'light', 0.6 * ez(since(c.T, 0.8) / 0.6), 0.35));
        P.forEach(([x, y], i) => {
          const on = i < c.n;
          const s = on ? back(since(c.T, 0.2 + i * 0.2) / 0.5) : 0.4;
          o.push(...star4(x, y, 2.2 * s, i === c.n - 1 ? 'coral' : 'light', on ? 1 : 0.35));
        });
        return o;
      },
    },
  ],

  // ---------------- night before day one: something waits for tomorrow ----------------
  firstnight: [
    // Mon: a glow line on the horizon and a dotted path where tomorrow's sun will climb
    {
      bd: () => ({sun: -0.6}),
      draw: (c) => {
        const o: Shape[] = [];
        const g = 0.5 + 0.2 * Math.sin(c.t * 1.2);
        o.push(gl(A.sunX, A.cloud, 16, 'light', g * ez(c.T / 1.5)), ln([A.sunX - 18, A.cloud - 0.3, A.sunX + 18, A.cloud - 0.3], 'light', g, 0.4));
        const n = 14, shown = Math.floor(ez(since(c.T, 0.6) / 1.6) * n);
        for (let i = 0; i < shown; i++) {
          const u = i / (n - 1);
          o.push(dk(A.sunX + Math.sin(u * 2.2) * 6, A.cloud - 3 - u * 40, 0.45, 'light', 0.8 - u * 0.4));
        }
        o.push(dk(A.sunX, A.cloud - 1.5, 0.9, 'coral', pulse(c.t, 2, 0.5) * 0.8 + 0.2));
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.06 * ez(c.T / 3), y: -3 * (1 - ez(c.T / 3))}),
    },
    // Tue: a chalk target drawn on the rock for tomorrow's first strike
    {
      draw: (c) => {
        const p = ez(since(c.T, 0.4) / 1.2);
        const x = A.rock.x + 3, y = A.rock.top + A.rock.h * 0.45;
        return [rg(x, y, 5, 'paper', 0.85, 0.45, 5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p), ln([x - 2, y - 2, x + 2 * ez(since(c.T, 1.6) / 0.3) - 2 * (1 - ez(since(c.T, 1.6) / 0.3)), y + 2 * ez(since(c.T, 1.6) / 0.3) - 2 * (1 - ez(since(c.T, 1.6) / 0.3))], 'paper', 0.85, 0.45), ln([x + 2, y - 2, x + 2 - 4 * ez(since(c.T, 1.9) / 0.3), y - 2 + 4 * ez(since(c.T, 1.9) / 0.3)], 'paper', 0.85 * cl(since(c.T, 1.9) * 9), 0.45)];
      },
    },
    // Wed: a lamp on the boat's bow, its reflection wobbling
    {
      draw: (c) => {
        const [bx, by] = A.boat;
        const x = bx - 4, y = by - 4;
        const fl2 = 0.8 + 0.2 * Math.sin(c.t * 7) * Math.sin(c.t * 3.1);
        const o: Shape[] = [ln([x, by - 1, x, y], 'ink', 1, 0.35), gl(x, y, 7, 'light', 0.6 * fl2 * ez(c.T / 1)), dk(x, y, 0.8, 'light', fl2), dk(x, y + 0.4, 0.35, 'coral', fl2)];
        for (let k = 0; k < 6; k++) o.push(ln([x - 1 + Math.sin(c.t * 2 + k) * 0.8, by + 2 + k * 1.6, x + 1 + Math.sin(c.t * 2 + k) * 0.8, by + 2 + k * 1.6], 'light', 0.6 * (1 - k / 6) * fl2, 0.35));
        return o;
      },
    },
    // Thu: a crescent moon rises behind the pine; stars open between the branches
    {
      bd: () => ({night: 1}),
      draw: (c) => {
        const r = ez(c.T / 2.2);
        const mx = A.treeX - 14, my = 30 - r * 14;
        const o: Shape[] = [dk(mx, my, 4.2, 'light', 0.95), dk(mx + 1.7, my - 1.1, 3.8, 'paper', 1)];
        for (let i = 0; i < 9; i++) {
          const on = since(c.T, 0.8 + i * 0.18);
          if (on > 0) o.push(dk(30 + rnd(i) * 60, 4 + rnd(i + 9) * 26, 0.45, 'light', cl(on * 3) * (0.5 + 0.5 * Math.sin(c.t * 2 + i))));
        }
        return o;
      },
    },
    // Fri: base camp: a tent glowing at the foot of the trail
    {
      bd: () => ({night: 1}),
      draw: (c) => {
        const [x, y] = routeAt(0.22);
        const tx = x + 6, ty = y;
        const g = 0.55 + 0.15 * Math.sin(c.t * 1.7);
        return [gl(tx, ty - 2, 9, 'light', g * ez(c.T)), pg([tx - 4, ty, tx, ty - 5, tx + 4, ty], 'ink'), pg([tx - 1.2, ty, tx, ty - 2.6, tx + 1.2, ty], 'light', g + 0.2), dk(tx, ty - 0.5, 0.35, 'coral', 0.9)];
      },
    },
    // Sat: bioluminescent waves: light running along the shoreline
    {
      bd: () => ({night: 1}),
      draw: (c) => {
        const o: Shape[] = [];
        const ph = (c.t * 0.33) % 1;
        const p: number[] = [];
        for (let i = 0; i < 46; i++) {
          const u = i / 45;
          const x = 4 + u * 96;
          const k = Math.exp(-Math.pow((u - ph) * 6, 2));
          if (k > 0.08) p.push(x, A.sand - 0.6 + Math.sin(x * 0.4 + c.t * 2) * 0.4 - u * 1.4);
          if (k > 0.5) o.push(gl(x, A.sand - 0.6 - u * 1.4, 3, 'light', k * 0.3));
        }
        o.push(ds(p, 0.4, 'light', 0.95));
        return o;
      },
    },
    // Sun: the first star of the evening blooms
    {
      draw: (c) => {
        const k = back(since(c.T, 0.7) / 0.7);
        const tw = 0.85 + 0.15 * Math.sin(c.t * 3);
        const o: Shape[] = [gl(48, 18, 10 * k, 'light', 0.5 * tw), ...star4(48, 18, 4.5 * k * tw, 'light'), dk(48, 18, 0.6, 'coral', cl(since(c.T, 1.2) * 3))];
        return o;
      },
      cam: (c) => ({s: 1.12 - 0.1 * ez(c.T / 2.5), px: 48, py: 18}),
    },
  ],

  // ---------------- locked for sleep: something fills while you recharge ----------------
  bedtime: [
    // Mon: the moon fills from crescent to full; five stars mark 20, 40, 60, 80, 100%
    {
      bd: () => ({sun: -0.6, night: 1}),
      draw: (c) => {
        const ch = charge(c.t);
        const mx = 64, my = 16, r = 5;
        const o: Shape[] = [dk(mx, my, r, 'mist', 0.35)];
        // the lit part of the disc: everything left of a line that sweeps across with the charge
        const p: number[] = [];
        for (let i = 0; i <= 16; i++) {
          const a = -Math.PI / 2 + (i / 16) * Math.PI;
          p.push(mx + Math.cos(a) * r, my + Math.sin(a) * r);
        }
        const k = 1 - 2 * ch;
        for (let i = 16; i >= 0; i--) {
          const a = -Math.PI / 2 + (i / 16) * Math.PI;
          p.push(mx + Math.cos(a) * r * k, my + Math.sin(a) * r);
        }
        o.push(pg(p, 'light', 0.95));
        for (let i = 0; i < 5; i++) {
          const on = ch >= (i + 1) * 0.19;
          o.push(...star4(mx - 20 + i * 6, my + 12, on ? 1.4 : 0.7, i === 4 && on ? 'coral' : 'light', on ? 0.95 : 0.35));
        }
        return o;
      },
      cam: (c) => ({s: 1.03, y: Math.sin(c.t * 0.5) * 0.5}),
    },
    // Tue: a seam of light rises up the crack in the rock
    {
      bd: () => ({night: 1}),
      draw: (c) => {
        const ch = charge(c.t);
        const P = zig(A.rock.x + 1, A.rock.bot - 1, A.rock.x - 1, A.rock.top + 2, 9, 3, 7);
        const o: Shape[] = [ln(P, 'ink', 0.9, 0.55)];
        const n = P.length / 2 - 1, k = ch * n, i0 = Math.floor(k);
        const lit = P.slice(0, (i0 + 1) * 2);
        const hx = lerp(P[i0 * 2], P[Math.min(n, i0 + 1) * 2], k - i0), hy = lerp(P[i0 * 2 + 1], P[Math.min(n, i0 + 1) * 2 + 1], k - i0);
        lit.push(hx, hy);
        o.push(ln(lit, 'light', 0.95, 0.45), gl(hx, hy, 4, 'light', 0.8), dk(hx, hy, 0.5, 'coral', 0.9));
        return o;
      },
    },
    // Wed: the moon's reflection lengthens down the lake
    {
      bd: () => ({night: 1}),
      draw: (c) => {
        const ch = charge(c.t);
        const x = 66;
        const o: Shape[] = [dk(x, 12, 3.6, 'light', 0.95), gl(x, 12, 9, 'light', 0.4)];
        const n = Math.round(ch * 14);
        for (let k = 0; k < n; k++) {
          const w = 2.6 - k * 0.12 + Math.sin(c.t * 2.2 + k) * 0.6;
          o.push(ln([x - w, A.water + 1.5 + k * 2, x + w, A.water + 1.5 + k * 2], 'light', 0.85 - k * 0.03, 0.4));
        }
        return o;
      },
    },
    // Thu: fireflies fill the pine from the roots up
    {
      bd: () => ({night: 0.75}),
      draw: (c) => {
        const ch = charge(c.t);
        const top = A.treeTop(0.78), base = A.ledge;
        const p: number[] = [];
        const q: number[] = [];
        for (let i = 0; i < 44; i++) {
          const u = rnd(i + 3);
          const y = base - u * (base - top);
          const hw = (1 - u) * 9 + 1;
          const x = A.treeX + (rnd(i + 40) - 0.5) * 2 * hw + Math.sin(c.t + i) * 0.5;
          if (u < ch) (Math.sin(c.t * (2 + rnd(i) * 2) + i) > -0.3 ? p : q).push(x, y);
        }
        return [ds(q, 0.4, 'light', 0.35), ds(p, 0.5, 'light', 1), gl(A.treeX, base - ch * (base - top), 7, 'light', 0.35)];
      },
    },
    // Fri: moonlight pours down the snowfield from the summit
    {
      bd: () => ({night: 1}),
      draw: (c) => {
        const ch = charge(c.t);
        const [sx, sy] = A.summit;
        const H = 16 * ch;
        return [fx(pgs([sx, sy - 0.5, sx + H * 0.75, sy + H, sx + H * 0.35, sy + H * 0.85, sx - H * 0.1, sy + H * 1.05, sx - H * 0.6, sy + H * 0.9], 'light', 0.8)), gl(sx, sy + H * 0.5, 4 + H * 0.6, 'light', 0.35), dk(sx, sy, 0.6, 'coral', 0.8)];
      },
    },
    // Sat: a lighthouse lamp charges; its glow and gauge grow
    {
      bd: () => ({kind: 'beach', night: 1}),
      draw: (c) => {
        const ch = charge(c.t);
        const x = 14, y0 = A.sand - 2, y1 = 44;
        return [pg([x - 2.4, y0, x - 1.4, y1, x + 1.4, y1, x + 2.4, y0], 'ink'), ln([x - 2.1, y0 - 6, x + 2.1, y0 - 6.4], 'paper', 0.8, 0.5), ln([x - 1.8, y0 - 13, x + 1.8, y0 - 13.3], 'paper', 0.8, 0.5), pg([x - 1.7, y1, x - 1.7, y1 - 3, x + 1.7, y1 - 3, x + 1.7, y1], 'ink'), gl(x, y1 - 1.5, 4 + ch * 14, 'light', 0.3 + ch * 0.5), dk(x, y1 - 1.5, 0.9, 'light', 0.4 + ch * 0.6), rg(x, y1 - 1.5, 4.5, 'light', 0.85, 0.4, 4.5, -Math.PI / 2, -Math.PI / 2 + ch * Math.PI * 2), pg([x - 2.2, y1 - 3, x, y1 - 5, x + 2.2, y1 - 3], 'ink')];
      },
    },
    // Sun: the Milky Way fills in across the sky
    {
      draw: (c) => {
        const ch = charge(c.t);
        const p: number[] = [];
        const n = Math.round(ch * 70);
        for (let i = 0; i < n; i++) {
          const u = rnd(i + 11);
          const x = 8 + u * 92, y = 44 - u * 38 + (rnd(i + 90) - 0.5) * 10 * (1 - Math.abs(u - 0.5));
          p.push(x, y);
        }
        return [pg([8, 40, 54, 21, 100, 2, 100, 10, 54, 29, 8, 48], 'light', 0.08 + ch * 0.1), ds(p, 0.32, 'light', 0.85)];
      },
    },
  ],

  // ---------------- the alarm: the stillness breaks, in beats ----------------
  wake: [
    // Mon: a blade of light sweeps the cloud tops on every ring; the peaks flash
    {
      bd: (c) => ({sun: -0.2 + 0.4 * ez(c.T / 3), night: 0.5 * (1 - ez(c.T / 2))}),
      draw: (c) => {
        const o: Shape[] = [];
        const lr = lastRing(c.T);
        if (lr >= 0) {
          const p = (c.T - lr) / 0.45;
          if (p < 1) {
            const x = -10 + p * 120;
            o.push(ln([x - 26, A.cloud - 0.8, x, A.cloud - 0.8], 'light', 0.95 * (1 - p * 0.4), 1.4), gl(x, A.cloud - 1, 16, 'light', 0.75 * (1 - p)), pg([x - 30, A.cloud - 1, x, A.cloud - 2.5, x + 2, A.cloud - 1, x, A.cloud + 0.5], 'light', 0.35 * (1 - p)));
          }
        }
        const b = ringBeat(c.T);
        const [px, py] = A.peak2;
        o.push(pg([px - 3.5, py + 3.6, px, py - 0.2, px + 3.2, py + 3.4], 'coral', 0.25 + 0.65 * b));
        o.push(fl(0.12 * b));
        return o;
      },
      cam: (c) => {
        const b = ringBeat(c.T);
        return {s: 1.04 + 0.03 * b, x: Math.sin(c.T * 63) * 0.6 * b};
      },
      hap: ringHap,
      type: 'slam',
    },
    // Tue: rockfall: pebbles tumble down to the ledge on every ring
    {
      draw: (c) => {
        const o: Shape[] = [];
        const beats = [...RINGS, ...Array.from({length: 4}, (_, k) => 2.85 + k * 2.5)];
        beats.forEach((b, j) => {
          const age = c.T - b;
          if (age < 0 || age > 1.6) return;
          for (let i = 0; i < 3; i++) {
            const x0 = 58 + rnd(j * 3 + i) * 22, y0 = 14 + rnd(j * 7 + i) * 8;
            const vx = -4 - rnd(j + i * 5) * 6;
            const tFall = Math.sqrt((A.ledge - 1.5 - y0) / 40);
            let x = x0 + vx * age, y: number;
            if (age < tFall) y = y0 + 40 * age * age;
            else {
              const a2 = age - tFall;
              y = A.ledge - 1.5 - Math.abs(Math.sin(a2 * 9)) * 4 * Math.exp(-a2 * 4);
              if (a2 < 0.35) o.push(rg(x, A.ledge, 1 + a2 * 12, 'mist', 0.8 * (1 - a2 / 0.35), 0.5, 1.2));
            }
            o.push(pg(ell(x, y, 2 + rnd(i + j) * 0.9, 1.5, 9, age * 6), 'ink'));
          }
        });
        return o;
      },
      cam: (c) => {
        const b = ringBeat(c.T - 0.25);
        return {s: 1.05, x: Math.sin(c.T * 71) * 0.8 * b, y: Math.cos(c.T * 53) * 0.6 * b};
      },
      hap: RINGS.map((t) => ({t: t + 0.25, kind: 'heavy' as HK})),
      type: 'jolt',
    },
    // Wed: a fish leaps clear on every ring
    {
      bd: (c) => ({sun: -0.1 + 0.4 * ez(c.T / 3)}),
      draw: (c) => {
        const o: Shape[] = [];
        const beats = [0.35, 1.2, 2.05, 3.6, 5.6, 7.6, 9.6];
        beats.forEach((b, j) => {
          const age = c.T - b;
          if (age < 0 || age > 1.8) return;
          const x0 = 48 + (j % 3) * 14, x1 = x0 + 10;
          if (age < 0.7) {
            const u = age / 0.7;
            const x = lerp(x0, x1, u), y = A.water + 3 - Math.sin(u * Math.PI) * 16;
            const ang = Math.atan2(Math.cos(u * Math.PI) * -11 * Math.PI, 10);
            o.push(pg(ell(x, y, 3.6, 1.3, 12, ang), 'ink'), pg([x - Math.cos(ang) * 3.2, y - Math.sin(ang) * 3.2, x - Math.cos(ang) * 5.6 - 1.4, y - Math.sin(ang) * 5.6 - 1.5, x - Math.cos(ang) * 5.6 + 1.4, y - Math.sin(ang) * 5.6 + 1.5], 'ink'));
          }
          for (const [sx, at] of [
            [x0, 0],
            [x1, 0.7],
          ]) {
            const a2 = age - at;
            if (a2 > 0 && a2 < 1.1) {
              o.push(rg(sx, A.water + 3, 1 + a2 * 7, 'mist', 0.9 * (1 - a2 / 1.1), 0.45, 0.4 + a2 * 1.5));
              if (a2 < 0.35) o.push(ds(burstPts(sx, A.water + 2.5, 6, a2, 18, 60, j * 9 + at), 0.35, 'light', 1 - a2 / 0.35));
            }
          }
        });
        return o;
      },
      cam: (c) => ({s: 1.04 + 0.02 * ringBeat(c.T - 0.3)}),
      hap: [0.35, 1.2, 2.05].flatMap((t) => [{t, kind: 'medium' as HK}, {t: t + 0.7, kind: 'heavy' as HK}]),
      type: 'drop',
    },
    // Thu: pine cones drop and bounce, needles shake loose on every ring
    {
      draw: (c) => {
        const o: Shape[] = [];
        const top = A.treeTop(0.78);
        RINGS.concat([3.6, 6.1, 8.6]).forEach((b, j) => {
          const age = c.T - b;
          if (age < 0 || age > 1.6) return;
          const x0 = A.treeX - 4 - rnd(j) * 8, y0 = top + 10 + rnd(j + 3) * 20;
          const tF = Math.sqrt((A.ledge - 1 - y0) / 45);
          let x = x0 - age * 3, y: number;
          if (age < tF) y = y0 + 45 * age * age;
          else {
            const a2 = age - tF;
            y = A.ledge - 1 - Math.abs(Math.sin(a2 * 10)) * 3 * Math.exp(-a2 * 5);
            x = x0 - tF * 3 - a2 * 6;
          }
          o.push(pg(ell(x, y, 1.6, 2.4, 10, age * 4), 'ink'));
          if (age < 0.5) o.push(ds(burstPts(x0 + 3, y0, 9, age, 18, 12, j * 13, false), 0.45, 'mid', 1 - age * 2));
        });
        return o;
      },
      cam: (c) => ({s: 1.04, x: Math.sin(c.T * 60) * 0.5 * ringBeat(c.T)}),
      hap: ringHap,
      type: 'jolt',
    },
    // Fri: a gust tears a plume of snow off the summit on every ring
    {
      bd: (c) => ({sun: 0.05 + 0.3 * ez(c.T / 3), night: 0.25}),
      draw: (c) => {
        const o: Shape[] = [];
        const [sx, sy] = A.summit;
        const b = ringBeat(c.T);
        const p: number[] = [];
        for (let i = 0; i < 40; i++) {
          const ph = (rnd(i) + c.T * 0.8) % 1;
          const amp = 0.35 + 0.65 * ringBeat(c.T - ph * 0.6);
          p.push(sx + ph * 34 * amp, sy - 1 + Math.sin(ph * 6 + i) * 2 - ph * 5 + (rnd(i + 5) - 0.5) * ph * 8);
        }
        o.push(ds(p, 0.4, 'paper', 0.9));
        for (let k = 0; k < 3; k++) {
          const ph = (c.T * 1.6 + k / 3) % 1;
          o.push(ln([sx - 30 + ph * 70, sy + 6 + k * 5, sx - 22 + ph * 70, sy + 6 + k * 5], 'mist', 0.7 * b + 0.15, 0.35));
        }
        return o;
      },
      cam: (c) => ({s: 1.05, x: Math.sin(c.T * 50) * 0.5 * ringBeat(c.T)}),
      hap: ringHap,
      type: 'slam',
    },
    // Sat: a wave detonates on the rocks on every ring
    {
      bd: (c) => ({sun: 0.05 + 0.25 * ez(c.T / 3)}),
      draw: (c) => {
        const o: Shape[] = [];
        const rx = 36, ry = A.sand - 2;
        o.push(pg([rx - 12, ry + 3, rx - 8, ry - 5, rx - 1, ry - 8, rx + 6, ry - 5.5, rx + 11, ry + 3], 'ink'));
        const lr = lastRing(c.T);
        if (lr >= 0) {
          const age = c.T - lr;
          o.push(ds(burstPts(rx - 2, ry - 7, 34, age, 34, 40, Math.floor(lr * 10)), 0.6, 'paper', cl(1 - age / 0.9)));
          o.push(ln([rx - 30 + age * 34, ry, rx - 16 + age * 34, ry - 3], 'paper', cl(1 - age * 2), 0.9));
        }
        return o;
      },
      cam: (c) => {
        const b = ringBeat(c.T);
        return {s: 1.05 + 0.03 * b, y: Math.sin(c.T * 55) * 0.6 * b};
      },
      hap: ringHap,
      type: 'slam',
    },
    // Sun: dawn climbs the sky and the stars go out, one by one
    {
      bd: (c) => ({night: c.T < 1.5 ? 1 : c.T < 3 ? 0.75 : 0.5, moonY: 0.2 + 0.25 * ez(c.T / 4)}),
      draw: (c) => {
        const o: Shape[] = [];
        const line = 92 - ez(c.T / 3.2) * 100;
        for (let k = 0; k < 6; k++) o.push(gl(10 + k * 18, line + 4, 16, 'light', 0.45));
        o.push(ln([0, line, 100, line], 'light', 0.5, 0.4));
        for (let i = 0; i < 22; i++) {
          const x = 8 + rnd(i + 1) * 90, y = 3 + rnd(i + 2) * 52;
          const gone = y > line;
          const pop = gone ? cl(1 - (y - line) / 3) : 1;
          o.push(dk(x, y, gone ? 0.9 * pop : 0.5, 'light', gone ? pop : 0.85));
        }
        o.push(fl(0.08 * ringBeat(c.T)));
        return o;
      },
      cam: (c) => ({s: 1.04 + 0.02 * ringBeat(c.T)}),
      hap: ringHap,
      type: 'track',
    },
  ],

  // ---------------- countdown: time runs, each world keeping its own clock ----------------
  countdown: [
    // Mon: the sun climbs a ladder of twelve marks; the current mark blinks every second
    {
      bd: (c) => ({sun: -0.35 + 0.6 * cdP(c), night: 0.4 * (1 - cdP(c))}),
      draw: (c) => {
        const o: Shape[] = [];
        const x = A.sunX + 11;
        const sy = A.sunY(-0.35 + 0.6 * cdP(c));
        for (let i = 0; i < 12; i++) {
          const y = A.cloud - 2 - i * 3.6;
          const lit = y >= sy;
          const cur = lit && y - 3.6 < sy;
          o.push(ln([x - (i % 3 === 0 ? 2 : 1), y, x + (i % 3 === 0 ? 2 : 1), y], cur ? 'coral' : lit ? 'light' : 'mist', cur ? 0.4 + 0.6 * pulse(c.t, 1, 0.25) : lit ? 0.9 : 0.5, 0.45));
        }
        o.push(ln([x, A.cloud - 2, x, A.cloud - 2 - 11 * 3.6], 'mist', 0.4, 0.25));
        return o;
      },
      cam: () => ({s: 1.04}),
    },
    // Tue: the hourglass; a bright grain drops through the neck every second
    {
      bd: (c) => ({kind: 'hourglass', sand: c.d.countdown / 7200, sun: 0.4}),
      draw: (c) => {
        const x = toStage(665 + 30, 0)[0], top = toStage(0, 390 + 5.9 - 322)[1], bot = toStage(0, 390 + 5.9)[1], mid = (top + bot) / 2;
        const ph = c.t % 1;
        const o: Shape[] = [dk(x, mid + ph * (bot - mid - 6), 0.55, 'light', 1 - ph * 0.3)];
        if (ph < 0.3) o.push(rg(x, bot - 6, 1 + ph * 12, 'light', 0.8 * (1 - ph / 0.3), 0.35, 0.5 + ph * 2));
        if (c.matrix) {
          const hw = 10, q = 1 - cdP(c);
          o.push(ln([x - hw, top, x + hw, top, x + 0.8, mid, x + hw, bot, x - hw, bot, x - 0.8, mid, x - hw, top], 'mid', 0.8, 0.5));
          o.push(pg([x - hw * q * 0.9, mid - (mid - top) * q * 0.9, x + hw * q * 0.9, mid - (mid - top) * q * 0.9, x, mid - 1], 'ink', 0.9));
          o.push(pg([x - hw * 0.9 * (1 - q), bot - 1, x + hw * 0.9 * (1 - q), bot - 1, x, bot - 1 - (bot - mid) * (1 - q) * 0.8], 'ink', 0.9));
        }
        return o;
      },
      cam: (c) => ({s: 1.03 + 0.03 * ez(c.T / 6), px: 43, py: 44}),
      zoom: 1.3,
    },
    // Wed: the drip from the bough, with sixty seconds marked around where it lands
    {
      bd: () => ({drip: true, sun: 0.3}),
      draw: (c) => {
        const o: Shape[] = [];
        const x = 64.8, y = 71.4;
        const sec = Math.floor(c.d.countdown) % 60;
        for (let i = 0; i < 60; i += 2) {
          const a = -Math.PI / 2 + (i / 60) * Math.PI * 2;
          const lit = i <= 59 - sec;
          o.push(dk(x + Math.cos(a) * 17, y + Math.sin(a) * 4.2, 0.32, lit ? 'light' : 'mist', lit ? 0.85 : 0.35));
        }
        const a = -Math.PI / 2 + ((59 - sec) / 60) * Math.PI * 2;
        o.push(dk(x + Math.cos(a) * 17, y + Math.sin(a) * 4.2, 0.55, 'coral', 0.9));
        if (c.matrix) {
          const ph = c.t % 1;
          o.push(ln([100, 14, 86, 18, x, 22], 'ink', 1, 0.8));
          o.push(dk(x, ph < 0.55 ? 23 : 23 + (y - 23) * Math.pow((ph - 0.55) / 0.45, 2), 0.7, 'light'));
          for (let k = 0; k < 2; k++) {
            const age = (c.t % 1) + k;
            o.push(rg(x, y, 1 + age * 6, 'light', 0.9 * (1 - age / 2), 0.4, 0.4 + age * 1.5));
          }
        }
        return o;
      },
    },
    // Thu: the candle in the lantern; heat rises and a spark pops every second
    {
      bd: (c) => ({kind: 'hourglass', prop: 'lantern', candle: cl(c.d.countdown / 7200), night: 0.5, mist: 1}),
      draw: (c) => {
        const x = toStage(665 + 20, 0)[0];
        const bot = toStage(0, 395.9)[1], H = (322 * 0.8) / 4.75;
        const cand = cl(c.d.countdown / 7200);
        const fy = bot - H * 0.15 - H * 0.55 * (0.12 + 0.88 * cand);
        const o: Shape[] = [];
        for (let k = 0; k < 3; k++) {
          const ph = (c.t * 0.5 + k / 3) % 1;
          o.push(ln([x - 1 + Math.sin(ph * 9 + k) * 1.2, fy - 4 - ph * 14, x + Math.sin(ph * 9 + k + 1) * 1.6, fy - 6 - ph * 14], 'mist', 0.6 * (1 - ph), 0.3));
        }
        const sp = c.t % 1;
        if (sp < 0.5) o.push(dk(x + Math.sin(Math.floor(c.t) * 7) * 3 * sp * 2, fy - 2 - sp * 10, 0.4, 'coral', 1 - sp * 2));
        if (c.matrix) {
          o.push(ln([x - 6, bot - H, x + 6, bot - H, x + 6, bot, x - 6, bot, x - 6, bot - H], 'mid', 0.8, 0.5));
          o.push(pg([x - 1.5, bot, x - 1.5, fy + 1, x + 1.5, fy + 1, x + 1.5, bot], 'paper', 0.9), dk(x, fy, 0.9, 'coral'));
        }
        return o;
      },
      zoom: 1.3,
    },
    // Fri: the light walks the trail; the way ahead pulses toward a waiting flag
    {
      bd: (c) => ({noYou: false, trail: 0.81 * cdP(c), sun: 0.3 + 0.2 * cdP(c)}),
      draw: (c) => {
        const o: Shape[] = [];
        const u0 = 0.81 * cdP(c);
        for (let i = 0; i < 16; i++) {
          const u = u0 + (i / 15) * (1 - u0);
          const [x, y] = routeAt(u);
          const wave = Math.exp(-Math.pow(((c.t * 0.8) % 1) * 16 - i, 2) / 3);
          o.push(dk(x, y, 0.35 + wave * 0.35, 'light', 0.25 + wave * 0.7));
        }
        const [sx, sy] = A.summit;
        o.push(ln([sx, sy, sx, sy - 6], 'ink', 1, 0.35), pg([sx, sy - 6, sx + 3.2 + Math.sin(c.t * 5) * 0.4, sy - 5, sx, sy - 4], 'ink'));
        if (c.matrix) {
          const [x, y] = routeAt(u0);
          o.push(dk(x, y, 1.1, 'coral'));
        }
        return o;
      },
    },
    // Sat: the tide climbs toward the flag; foam bursts every few seconds
    {
      bd: (c) => ({tide: cdP(c), sun: 0.3}),
      draw: (c) => {
        const sandY = A.sand, target = sandY + (0.13 * 488) / 4.75;
        const ty = sandY + (target - sandY) * cdP(c);
        const o: Shape[] = [];
        const age = c.t % 3.5;
        if (age < 0.8) o.push(ds(burstPts(20 + (Math.floor(c.t / 3.5) % 4) * 15, ty - 0.5, 14, age, 9, 12, Math.floor(c.t / 3.5)), 0.38, 'paper', 1 - age / 0.8));
        const sx = toStage(600, 0)[0];
        o.push(ln([0, target - 0.5, 100, target - 2.5], 'mist', 0.5, 0.3, 1.2));
        if (c.matrix) o.push(ln([0, ty, 50, ty - 1, 100, ty - 2], 'paper', 0.9, 0.5), ln([sx, target, sx + 0.4, target - 7], 'ink', 1, 0.4), pg([sx + 0.4, target - 7, sx + 3, target - 6.2, sx + 0.4, target - 5.4], 'coral'));
        return o;
      },
    },
    // Sun: the moon sets along a path: walked part dotted, the rest dashed to the horizon
    {
      bd: (c) => ({moonX: 0.62 + 0.25 * cdP(c), moonY: 0.1 + 0.48 * cdP(c), charge: 0.98, night: 1}),
      draw: (c) => {
        const o: Shape[] = [];
        const P = (u: number): [number, number] => toStage(1000 * (0.62 + 0.25 * u), 488 * (0.1 + 0.48 * u));
        const p = cdP(c);
        for (let i = 0; i <= 20; i++) {
          const u = i / 20;
          const [x, y] = P(u);
          if (u < p - 0.03) o.push(dk(x, y, 0.3, 'light', 0.5));
          else if (u > p + 0.06 && i % 2 === 0) o.push(dk(x, y, 0.25, 'mist', 0.6));
        }
        const [mx, my] = P(p);
        o.push(rg(mx, my, 5 + pulse(c.t, 1, 0.3) * 2, 'light', 0.35 * pulse(c.t, 1, 0.3), 0.3));
        if (c.matrix) o.push(dk(mx, my, 3.6, 'light'));
        return o;
      },
    },
  ],

  // ---------------- get ready: something starts moving ----------------
  ready: [
    // Mon: clouds pour like a waterfall through the gap between the peaks
    {
      draw: (c) => {
        const o: Shape[] = [];
        const top = 30, bot = A.cloud;
        o.push(fx(pgs([61.5, top, 66.5, top, 70, bot, 58, bot], 'paper', 0.5)));
        for (let i = 0; i < 40; i++) {
          const ph = (rnd(i) + c.t * 0.55) % 1;
          const x = 61.5 + rnd(i + 3) * 5 + (rnd(i + 5) - 0.5) * ph * 12;
          const y = top + Math.pow(ph, 1.5) * (bot - top);
          o.push(ln([x, y, x + (rnd(i + 5) - 0.5) * 0.8, y + 1.2 + ph * 3.2], 'paper', 0.9 * Math.sin(ph * Math.PI), 0.4));
        }
        for (let i = 0; i < 3; i++) {
          const ph = (c.t * 0.5 + i / 3) % 1;
          o.push(rg(64, bot - 0.6, 2 + ph * 11, 'paper', 0.6 * (1 - ph), 0.45, (2 + ph * 11) * 0.28));
        }
        o.push(gl(64, bot - 1, 12, 'paper', 0.45));
        return o;
      },
      cam: (c) => ({s: 1 + 0.06 * back(c.T / 0.8, 1.2)}),
      type: 'drop',
    },
    // Tue: flint sparks fly off the rock on every strike
    {
      draw: (c) => {
        const o: Shape[] = [];
        const P = 0.95;
        const k = Math.floor(c.t / P), age = c.t % P;
        const sx = A.rock.x + A.rock.w * 0.42, sy = A.rock.top + A.rock.h * 0.35;
        const pts = burstPts(sx, sy, 14, age, 34, 60, k * 17);
        const was = burstPts(sx, sy, 14, Math.max(0, age - 0.06), 34, 60, k * 17);
        for (let i = 0; i < pts.length; i += 2) {
          const m: Mat = i % 6 === 0 ? 'coral' : 'light', a = cl(1 - age / 0.65);
          o.push(ln([was[i], was[i + 1], pts[i], pts[i + 1]], m, a, 0.45), dk(pts[i], pts[i + 1], 0.5, m, a));
        }
        if (age < 0.14) o.push(gl(sx, sy, 10, 'light', 1 - age / 0.14), dk(sx, sy, 1.2 * (1 - age / 0.14), 'light'));
        return o;
      },
      cam: (c) => ({s: 1.04 + 0.03 * pulse(c.t, 0.95, 0.1)}),
      hap: [0.95, 1.9, 2.85].map((t) => ({t, kind: 'medium' as HK})),
      type: 'stamp',
    },
    // Wed: gusts race across the lake as dark cat's-paws
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let g = 0; g < 3; g++) {
          const ph = (c.t * 0.45 + g / 3) % 1;
          const x0 = -20 + ph * 140, y0 = A.water + 4 + g * 5, a = Math.sin(ph * Math.PI);
          o.push(pgs(ell(x0 + 7, y0 + 0.4, 10, 1.5, 14), 'mid', 0.5 * a));
          for (let k = 0; k < 7; k++) o.push(ln([x0 + k * 2.2, y0 + (k % 2) * 0.8, x0 + k * 2.2 + 1.6, y0 + (k % 2) * 0.8], 'ink', 0.85 * a, 0.5));
        }
        for (let k = 0; k < 3; k++) {
          const ph = (c.t * 0.9 + k / 3) % 1;
          o.push(ln([-10 + ph * 120, 20 + k * 9, -2 + ph * 120, 20 + k * 9], 'mist', 0.6, 0.3));
        }
        return o;
      },
      cam: (c) => ({s: 1.05, x: 1 - 2 * ez(c.T / 2)}),
      type: 'wipe',
    },
    // Thu: wind rips through the pines, needles streaming sideways
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 30; i++) {
          const ph = (rnd(i) + c.t * (0.6 + rnd(i + 4) * 0.5)) % 1;
          const x = 100 - ph * 110, y = 10 + rnd(i + 7) * 62 + Math.sin(ph * 8 + i) * 2;
          o.push(ln([x, y, x + 1.6, y - 0.4], 'ink', 0.8, 0.3));
        }
        for (let k = 0; k < 4; k++) {
          const ph = (c.t * 1.2 + k / 4) % 1;
          o.push(ln([100 - ph * 120, 16 + k * 14, 112 - ph * 120, 16 + k * 14 + 1], 'mist', 0.5, 0.3));
        }
        return o;
      },
      cam: (c) => ({s: 1.05, x: Math.sin(c.t * 1.1) * 0.8}),
      type: 'wipe',
    },
    // Fri: the clouds part like curtains and reveal the summit
    {
      draw: (c) => {
        const [sx, sy] = A.summit;
        const p = eio(since(c.T, 0.3) / 1.6);
        const cloud = (x: number, y: number, s: number) => fx(pgs(ell(x, y, 16 * s, 6 * s, 18), 'paper', 0.95));
        return [cloud(sx - 8 - p * 30, sy + 6, 1), cloud(sx + 10 + p * 30, sy + 9, 1.1), cloud(sx - 2 - p * 22, sy + 15, 0.8), ...star4(sx, sy - 1, 2.6 * back(since(c.T, 1.6) / 0.5), 'light', cl(since(c.T, 1.6) * 3))];
      },
      cam: (c) => ({s: 1.12 - 0.08 * eio(c.T / 2)}),
      hap: [{t: 0.3, kind: 'light'}, {t: 1.7, kind: 'heavy'}, {t: 1.8, kind: 'success'}],
      type: 'blur',
    },
    // Sat: gulls lift off the sand
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 6; i++) {
          const age = c.T - 0.3 - i * 0.22;
          const x0 = 36 + i * 7, y0 = A.sand + 2;
          if (age < 0) {
            o.push(pg(ell(x0, y0, 1.4, 0.7, 8), 'ink'));
            continue;
          }
          const x = x0 + age * (8 + i), y = y0 - Math.pow(age, 0.8) * 16;
          o.push(bird(x, y, 2.2 + age * 0.3, c.t * 12 + i, 'ink', cl(1.2 - age / 5)));
        }
        return o;
      },
      cam: (c) => ({s: 1.04, y: 1.2 * (1 - ez(c.T / 2))}),
      hap: [{t: 0.3, kind: 'medium'}, {t: 0.52, kind: 'light'}, {t: 0.74, kind: 'light'}],
      type: 'rise',
    },
    // Sun: planets line up and light one after another
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 5; i++) {
          const x = 30 + i * 13, y = 38 - i * 6;
          const k = back(since(c.T, 0.3 + i * 0.18) / 0.45);
          o.push(dk(x, y, (0.9 + (i % 3) * 0.45) * k, i === 4 ? 'coral' : 'light', 0.95));
          if (i > 0 && k > 0.5) o.push(ln([x - 13 + 1.5, y + 6 - 0.7, x - 1.5, y + 0.7], 'light', 0.3, 0.25, 1));
        }
        return o;
      },
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.18, kind: (i === 4 ? 'heavy' : 'light') as HK})),
      type: 'drop',
    },
  ],

  // ---------------- on the way: travel ----------------
  commute: [
    // Mon: a V of birds crosses; the camera tracks with them
    {
      draw: (c) => {
        const o: Shape[] = [];
        const lead = -10 + ((c.T * 9) % 130);
        for (let i = 0; i < 7; i++) {
          const k = i === 0 ? 0 : Math.ceil(i / 2) * (i % 2 ? 1 : -1);
          o.push(bird(lead - Math.abs(k) * 3.4, 20 + k * 2.6, 2, c.t * 9 + i));
        }
        return o;
      },
      cam: (c) => ({s: 1.08, x: Math.sin(c.T * 0.35) * 2.5}),
      type: 'wipe',
      zoom: 1.35,
    },
    // Tue: a pebble rolls down the ledge path to a flag, leaving a dotted trail
    {
      draw: (c) => {
        const o: Shape[] = [];
        const ph = (c.T % 3.4) / 3.4;
        const x = lerp(56, 92, ez(ph)), y = A.ledge - 1.4 - Math.abs(Math.sin(ph * 14)) * 2 * (1 - ph);
        for (let k = 0; k < 10; k++) {
          const u = k / 10;
          if (u < ez(ph)) o.push(dk(lerp(56, 92, u), A.ledge - 0.6, 0.3, 'mist', 0.8));
        }
        o.push(pg(ell(x, y, 1.4, 1.3, 10, ph * 20), 'ink'), ln([94, A.ledge, 94, A.ledge - 8], 'ink', 1, 0.35), pg([94, A.ledge - 8, 97 + Math.sin(c.t * 6) * 0.4, A.ledge - 7, 94, A.ledge - 6], 'coral'));
        return o;
      },
      cam: (c) => ({s: 1.06, x: -1.5 * Math.sin(c.T * 0.4)}),
      type: 'wipe',
    },
    // Wed: the boat crosses with a widening V of wake
    {
      bd: (c) => ({boatX: 0.5 + ((c.T * 0.02) % 0.4)}),
      draw: (c) => {
        const bx = toStage(1000 * (0.5 + ((c.T * 0.02) % 0.4)), 0)[0], by = A.boat[1] + 1;
        const o: Shape[] = [];
        for (let k = 1; k <= 3; k++) {
          const d = k * 6;
          o.push(ln([bx - 4, by, bx - 4 - d, by - k * 1.2], 'light', 0.7 - k * 0.15, 0.4), ln([bx - 4, by + 0.6, bx - 4 - d, by + k * 1.6], 'light', 0.7 - k * 0.15, 0.4));
        }
        if (c.matrix) o.push(ln([bx - 4, by - 0.6, bx + 4, by - 0.6], 'ink', 1, 0.7), ln([bx - 3, by + 0.6, bx + 3, by + 0.6], 'ink', 1, 0.6));
        return o;
      },
      cam: (c) => ({s: 1.07, x: -Math.sin(c.T * 0.3) * 2}),
      type: 'wipe',
    },
    // Thu: a tracking shot through the trunks, foreground racing past
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 5; i++) {
          const x = 110 - (((c.T * 22 + i * 26) % 130));
          const w = 1.4 + rnd(i) * 1.8;
          o.push(pg([x - w, 92, x - w * 0.8, -2, x + w * 0.8, -2, x + w, 92], 'ink', 0.85));
        }
        return o;
      },
      cam: () => ({s: 1.06}),
      type: 'wipe',
    },
    // Fri: footprints appear up the trail, the camera tilting up after them
    {
      draw: (c) => {
        const o: Shape[] = [];
        const shown = (c.T * 3) % 24;
        for (let i = 0; i < Math.floor(shown); i++) {
          const u = 0.05 + (i / 24) * 0.7;
          const [x, y] = routeAt(u);
          const side = i % 2 ? 1 : -1;
          o.push(pg(ell(x + side * 0.9, y, 0.7, 0.45, 8, -0.5), 'ink', 0.4 + 0.6 * cl(1 - (shown - i) / 8)));
        }
        return o;
      },
      cam: (c) => ({s: 1.06, y: 3 - 3 * ez((c.T % 8) / 8)}),
      type: 'rise',
    },
    // Sat: a sail glides along the horizon, its reflection trailing
    {
      draw: (c) => {
        const x = -5 + ((c.T * 6) % 115), y = A.horizon;
        const o: Shape[] = [pg([x - 3, y - 0.3, x + 3, y - 0.3, x + 2, y + 0.8, x - 2, y + 0.8], 'ink'), pg([x - 0.2, y - 0.5, x - 0.2, y - 8, x + 3.6, y - 1], 'ink'), pg([x - 0.6, y - 0.5, x - 0.6, y - 6, x - 3, y - 1], 'mid')];
        for (let k = 0; k < 3; k++) o.push(ln([x - 2 + Math.sin(c.t * 3 + k), y + 2 + k * 1.4, x + 2 + Math.sin(c.t * 3 + k), y + 2 + k * 1.4], 'mid', 0.5 - k * 0.12, 0.35));
        return o;
      },
      cam: (c) => ({s: 1.06, x: Math.sin(c.T * 0.3) * 2}),
      type: 'wipe',
    },
    // Sun: a comet crosses slowly; the camera follows
    {
      draw: (c) => {
        const ph = (c.T % 9) / 9;
        const x = 105 - ph * 110, y = 10 + ph * 20;
        const o: Shape[] = [gl(x, y, 5, 'light', 0.6), dk(x, y, 0.9, 'light')];
        for (let k = 1; k <= 8; k++) o.push(ln([x + k * 2.2, y - k * 0.4, x + (k + 1) * 2.2, y - (k + 1) * 0.4], 'light', 0.8 - k * 0.09, 1.2 - k * 0.12));
        return o;
      },
      cam: (c) => ({s: 1.06, x: Math.sin(c.T * 0.7) * 1.5}),
      type: 'wipe',
    },
  ],

  // ---------------- at the gym: twenty minute marks, each world counting its own way ----------------
  atgym: [
    // Mon: sunlight spreads across the cloud sea, one of twenty segments a minute
    {
      draw: (c) => {
        const o: Shape[] = [];
        const lit = Math.floor(liveP(c) * 20);
        const fz = minuteFlare(c);
        for (let i = 0; i < 20; i++) {
          const x0 = 8 + i * 4.5;
          o.push(ln([x0, A.cloud - 0.5, x0 + 3.4, A.cloud - 0.5], i < lit ? 'light' : 'mist', i < lit ? 0.95 : 0.4, 0.7));
          if (i === lit - 1) o.push(gl(x0 + 1.7, A.cloud - 0.5, 4 + fz * 6, 'light', 0.5 + fz * 0.5), dk(x0 + 1.7, A.cloud - 0.5, 0.6, 'coral'));
        }
        const h = hitAt(c);
        if (h != null) o.push(fl(0.4 * Math.exp(-(c.T - h) / 0.3)), gl(A.sunX, A.sunY(0.6), 30 * ez((c.T - h) / 0.8), 'light', 0.5));
        return o;
      },
      bd: (c) => ({sun: -0.1 + 0.6 * liveP(c)}),
      cam: (c) => ({s: 1.03 + 0.02 * minuteFlare(c)}),
    },
    // Tue: twenty notches chiselled around the rock; the 20th breaks it
    {
      bd: (c) => ({cracks: c.d.atgym >= PROOF ? 5 : 0, broken: c.d.atgym >= PROOF ? ez((c.d.atgym - PROOF) / 0.8) : 0}),
      draw: (c) => {
        const o: Shape[] = [];
        const lit = Math.floor(liveP(c) * 20);
        const cx = A.rock.x, cy = A.rock.top + A.rock.h * 0.55;
        for (let i = 0; i < 20; i++) {
          const a = Math.PI * (1.05 + (i / 19) * 0.9);
          const r1 = A.rock.w * 0.62, r2 = r1 + (i < lit ? 2.6 : 1.4);
          o.push(ln([cx + Math.cos(a) * r1, cy + Math.sin(a) * r1 * 0.85, cx + Math.cos(a) * r2, cy + Math.sin(a) * r2 * 0.85], i === lit - 1 ? 'coral' : i < lit ? 'ink' : 'mist', i < lit ? 1 : 0.5, 0.5));
        }
        const fz = minuteFlare(c);
        if (lit > 0 && fz > 0.05) {
          const a = Math.PI * (1.05 + ((lit - 1) / 19) * 0.9);
          o.push(ds(burstPts(cx + Math.cos(a) * A.rock.w * 0.62, cy + Math.sin(a) * A.rock.w * 0.53, 6, (1 - fz) * 0.6, 14, 30, lit), 0.3, 'ink', fz));
        }
        return o;
      },
    },
    // Wed: stepping stones surface across the lake, one a minute
    {
      draw: (c) => {
        const o: Shape[] = [];
        const lit = Math.floor(liveP(c) * 20);
        const fz = minuteFlare(c);
        for (let i = 0; i < 20; i++) {
          const u = i / 19;
          const x = 14 + u * 80, y = 86 - Math.pow(u, 0.8) * 22, s = 1 - u * 0.55;
          if (i < lit) {
            o.push(pg(ell(x, y, 1.15 * s, 0.42 * s, 10), 'ink'));
            if (i === lit - 1 && fz > 0.05) o.push(rg(x, y, (1 + (1 - fz) * 6) * s, 'light', fz, 0.4, (0.5 + (1 - fz) * 1.6) * s));
          } else o.push(dk(x, y, 0.3 * s + 0.15, 'mist', 0.5));
        }
        const h = hitAt(c);
        if (h != null) {
          const p = (c.T - h) / 1.2;
          if (p < 1) for (let i = 0; i < 20; i++) {
            const u = i / 19, q = Math.exp(-Math.pow((p * 1.3 - u) * 8, 2));
            o.push(gl(14 + u * 80, 86 - Math.pow(u, 0.8) * 22, 4, 'light', q));
          }
        }
        return o;
      },
    },
    // Thu: light climbs the trunk to the crown
    {
      draw: (c) => {
        const top = A.treeTop(0.78), base = A.ledge;
        const y = lerp(base, top, liveP(c));
        const fz = minuteFlare(c);
        const o: Shape[] = [ln([A.treeX, base, A.treeX, y], 'light', 0.9, 0.5), gl(A.treeX, y, 5 + fz * 6, 'light', 0.55 + fz * 0.4), dk(A.treeX, y, 0.6, 'coral')];
        for (let i = 0; i < 20; i++) {
          const yy = lerp(base, top, i / 19);
          o.push(ln([A.treeX - 1, yy, A.treeX + 1, yy], yy >= y ? 'light' : 'mist', yy >= y ? 0.8 : 0.4, 0.25));
        }
        const h = hitAt(c);
        if (h != null) o.push(gl(A.treeX, top, 20 * ez((c.T - h) / 0.8), 'light', 0.6), fl(0.3 * Math.exp(-(c.T - h) / 0.3)));
        return o;
      },
    },
    // Fri: a flag climbs the summit pole; at 20:00 it snaps out in the wind
    {
      draw: (c) => {
        const [sx, sy] = A.summit;
        const ph = 8.5;
        const fy = sy - 1 - (ph - 4) * liveP(c);
        const h = hitAt(c);
        const snap = h != null ? back((c.T - h) / 0.5) : 0;
        const wv = Math.sin(c.t * (h != null ? 12 : 4)) * (0.5 + snap);
        const o: Shape[] = [ln([sx, sy, sx, sy - ph], 'ink', 1, 0.4), pg([sx, fy - 3, sx + 4 + snap * 2 + wv * 0.3, fy - 2.2 + wv * 0.4, sx + 3.6 + snap * 2, fy - 1 + wv * 0.3, sx, fy], h != null ? 'coral' : 'ink')];
        for (let i = 0; i < 20; i++) o.push(ln([sx - 0.8, sy - 1 - (i / 19) * (ph - 4), sx - 0.3, sy - 1 - (i / 19) * (ph - 4)], i < liveP(c) * 20 ? 'ink' : 'mist', 0.7, 0.2));
        if (h != null) for (let k = 0; k < 3; k++) {
          const p2 = ((c.T - h) * 1.5 + k / 3) % 1;
          o.push(ln([sx - 20 + p2 * 40, sy - 8 + k * 3, sx - 14 + p2 * 40, sy - 8 + k * 3], 'mist', 0.6, 0.3));
        }
        return o;
      },
      cam: (c) => ({s: 1.04 + 0.04 * ez(c.T / 4), px: A.summit[0], py: A.summit[1] + 8}),
    },
    // Sat: every minute a wave leaves an arc on the sand
    {
      draw: (c) => {
        const o: Shape[] = [];
        const lit = Math.floor(liveP(c) * 20);
        const fz = minuteFlare(c);
        for (let i = 0; i < lit; i++) {
          const y = A.sand + 1.5 + (i / 20) * 13;
          const x0 = 20 + (i % 3) * 6;
          const pts: number[] = [];
          for (let k = 0; k <= 10; k++) pts.push(x0 + k * 7, y + Math.sin(k * 0.9 + i) * 0.7 - k * 0.15);
          o.push(ln(pts, i === lit - 1 ? 'ink' : 'mid', i === lit - 1 ? 0.7 + fz * 0.3 : 0.5, 0.35));
        }
        const h = hitAt(c);
        if (h != null) {
          const p = (c.T - h) / 1.4;
          if (p < 1) o.push(fl(0.25 * (1 - p)));
        }
        return o;
      },
      bd: (c) => ({sun: 0.5 - 0.3 * liveP(c)}),
    },
    // Sun: twenty stars, one a minute, form a ring around the moon
    {
      bd: () => ({moonX: 0.68, moonY: 0.3, charge: 0.98}),
      draw: (c) => {
        const o: Shape[] = [];
        const [mx, my] = toStage(680, 0.3 * 488);
        const lit = Math.floor(liveP(c) * 20);
        const h = hitAt(c);
        const spin = h != null ? (c.T - h) * 0.6 : 0;
        for (let i = 0; i < 20; i++) {
          const a = -Math.PI / 2 + (i / 20) * Math.PI * 2 + spin;
          const x = mx + Math.cos(a) * 13, y = my + Math.sin(a) * 13;
          if (i < lit) o.push(...star4(x, y, i === lit - 1 ? 1.6 + minuteFlare(c) : 1, i === lit - 1 ? 'coral' : 'light'));
          else o.push(dk(x, y, 0.25, 'mist', 0.5));
        }
        if (c.matrix) o.push(dk(mx, my, 4, 'light'));
        if (h != null) o.push(fl(0.25 * Math.exp(-(c.T - h) / 0.3)));
        return o;
      },
    },
  ],

  // ---------------- the Done card: the day's finish ----------------
  verified: [
    // Mon: the sun breaks free, glory rings spreading, light rising
    {
      bd: (c) => ({sun: c.pos === 'last' ? 0.62 : 0.52}),
      draw: (c) => {
        const o: Shape[] = [];
        const sx = A.sunX, sy = A.sunY(c.pos === 'last' ? 0.62 : 0.52);
        const n = c.pos === 'last' ? 4 : 3;
        for (let k = 0; k < n; k++) {
          const p = (c.T - 0.3 - k * 0.22) / 1.6;
          if (p > 0 && p < 1) o.push(rg(sx, sy, A.sunR + 2 + ez(p) * 22, 'light', 0.85 * (1 - p), 0.7));
        }
        const p2: number[] = [];
        for (let i = 0; i < 18; i++) {
          const ph = (rnd(i) + c.t * 0.18) % 1;
          p2.push(sx - 16 + rnd(i + 4) * 32, A.cloud - ph * 30);
        }
        o.push(ds(p2, 0.35, 'light', 0.7), fl(0.35 * Math.exp(-c.T / 0.35)));
        return o;
      },
      cam: (c) => ({s: 1.14 - 0.11 * ez(c.T / 1.2), px: A.sunX, py: 40}),
      hap: [{t: 0.05, kind: 'heavy'}, {t: 0.1, kind: 'success'}, {t: 0.52, kind: 'light'}, {t: 0.74, kind: 'light'}],
      type: 'slam',
    },
    // Tue: the rock splits; chips and dust fly
    {
      bd: (c) => ({cracks: 5, broken: ez((c.T - 0.15) / 0.6), rubble: c.pos === 'last' ? 7 : 4}),
      draw: (c) => {
        const o: Shape[] = [];
        const age = c.T - 0.15;
        if (age > 0 && age < 1.6) {
          o.push(ds(burstPts(A.rock.x, A.rock.top + 3, 22, age, 30, 46, 3), 0.42, 'ink', cl(1 - age / 1.4)));
          o.push(rg(A.rock.x, A.ledge - 1, 4 + age * 26, 'mist', cl(0.9 - age / 1.2), 1, 2 + age * 4));
        }
        if (c.matrix) {
          const sep = ez(age / 0.6) * 6;
          o.push(pg([A.rock.x - 1 - sep, A.ledge, A.rock.x - A.rock.w / 2 - sep, A.ledge - 1, A.rock.x - A.rock.w / 2.4 - sep, A.rock.top + 3, A.rock.x - 1 - sep, A.rock.top], 'ink'), pg([A.rock.x + 1 + sep, A.ledge, A.rock.x + A.rock.w / 2 + sep, A.ledge - 1, A.rock.x + A.rock.w / 2.4 + sep, A.rock.top + 3, A.rock.x + 1 + sep, A.rock.top], 'ink'));
        }
        return o;
      },
      cam: (c) => ({s: 1.12 - 0.09 * ez(c.T / 1), y: Math.sin(c.T * 60) * Math.exp(-c.T * 5) * 1.6}),
      hap: [{t: 0.15, kind: 'heavy'}, {t: 0.2, kind: 'heavy'}, {t: 0.28, kind: 'success'}],
      type: 'slam',
    },
    // Wed: the stone skips to the far shore and a ring of light runs back
    {
      draw: (c) => {
        const o: Shape[] = [];
        const N = c.N;
        const P = Array.from({length: N}, (_, i) => {
          const u = i / (N - 1);
          return [28 + u * 66, 86 - Math.pow(u, 0.8) * 22, 1 - u * 0.6];
        });
        P.forEach(([x, y, s], i) => {
          const age = c.T - 0.3 - i * 0.3;
          if (age < 0) return;
          const q = Math.min(1, age / 1.4);
          o.push(rg(x, y, (1.5 + q * 10) * s, 'light', 0.95 * (1 - q * 0.7), 0.55, (0.5 + q * 2.4) * s));
          if (age < 0.5) {
            const sp = burstPts(x, y, 7, age, 16 * s, 60, i * 7);
            o.push(ds(sp, 0.32 * s + 0.1, 'light', 1 - age / 0.5));
          }
        });
        const done = c.T - 0.3 - N * 0.3;
        if (done > 0 && done < 1.6) P.forEach(([x, y, s], i) => o.push(rg(x, y, 5 * s, 'light', Math.sin(cl(done * 1.3 - (N - 1 - i) * 0.08) * Math.PI) * 0.8, 0.6, 1.2 * s)));
        const k = Math.floor((c.T - 0.3) / 0.3);
        if (k >= 0 && k < N - 1) {
          const f = ((c.T - 0.3) % 0.3) / 0.3;
          const [x0, y0, s0] = P[k], [x1, y1] = P[k + 1];
          o.push(dk(lerp(x0, x1, f), lerp(y0, y1, f) - Math.sin(f * Math.PI) * 4 * s0, 0.7, 'coral'));
        }
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.05 * ez(c.T / 2), x: 2 - 4 * ez(c.T / 2.4)}),
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.3, kind: (i === 4 ? 'heavy' : 'light') as HK})),
      type: 'rise',
    },
    // Thu: birds burst from the crown; a growth ring spreads from the top
    {
      draw: (c) => {
        const o: Shape[] = [];
        const top = A.treeTop(0.78);
        const age = c.T - 0.4;
        if (age > 0 && age < 3) for (let i = 0; i < (c.pos === 'last' ? 12 : 8); i++) {
          const a = -Math.PI * (0.15 + rnd(i) * 0.6);
          const v = 12 + rnd(i + 3) * 14;
          o.push(bird(A.treeX + Math.cos(a) * v * age, top + Math.sin(a) * v * age * 0.8, 1.6 + age * 0.4, c.t * 12 + i, 'ink', cl(1.3 - age / 2.5)));
        }
        for (let k = 0; k < 2; k++) {
          const p = (c.T - 0.35 - k * 0.25) / 1.4;
          if (p > 0 && p < 1) o.push(rg(A.treeX, top + 6, 4 + ez(p) * 20, 'light', 0.8 * (1 - p), 0.6));
        }
        o.push(fl(0.25 * Math.exp(-(c.T - 0.4) / 0.3) * (c.T > 0.4 ? 1 : 0)));
        return o;
      },
      cam: (c) => ({s: 1.12 - 0.09 * ez(c.T / 1.3), px: A.treeX - 10, py: A.treeTop(0.78) + 10}),
      hap: [{t: 0.4, kind: 'heavy'}, {t: 0.45, kind: 'success'}],
      type: 'slam',
    },
    // Fri: the beacon on the summit catches and blazes
    {
      draw: (c) => {
        const o: Shape[] = [];
        const [sx, sy] = A.summit;
        const b = ez((c.T - 0.25) / 1);
        const fh = 2 + 8 * b;
        const f = Math.sin(c.t * 11) * 0.5;
        o.push(gl(sx, sy - 2, 6 + 16 * b, 'light', 0.6 * b));
        if (b > 0) o.push(fx(pgs([sx - fh * 0.42, sy, sx + f, sy - fh * 1.3, sx + fh * 0.42, sy], 'light', 0.95)), fx(pg([sx - fh * 0.14, sy, sx + f * 0.6, sy - fh * 0.5, sx + fh * 0.14, sy], 'coral')));
        const p: number[] = [];
        for (let i = 0; i < Math.round(16 * b); i++) {
          const ph = (rnd(i) + c.t * 0.5) % 1;
          p.push(sx + Math.sin(ph * 6 + i) * 3 * (1 + ph), sy - fh - ph * 18);
        }
        o.push(ds(p, 0.3, 'light', 0.85), ds(p.slice(0, 6), 0.32, 'coral', 0.9), fl(0.3 * Math.exp(-(c.T - 0.3) / 0.3) * (c.T > 0.3 ? 1 : 0)));
        return o;
      },
      cam: (c) => ({s: 1.14 - 0.1 * ez(c.T / 1.4), px: A.summit[0], py: A.summit[1] + 6}),
      hap: [{t: 0.3, kind: 'heavy'}, {t: 0.35, kind: 'success'}],
      type: 'slam',
    },
    // Sat: lanterns go up from the shore, one after another
    {
      bd: () => ({kind: 'sunset', sun: 0.15, night: 0.25}),
      draw: (c) => {
        const o: Shape[] = [];
        const N = c.N;
        for (let i = 0; i < N; i++) {
          const age = c.T - 0.3 - i * 0.3;
          if (age < 0) continue;
          const rise = Math.min(1, age / 8);
          const x = 30 + (i % 7) * 9 + Math.sin(age * 0.7 + i) * 1.6;
          const y = A.horizon + 2 - (A.horizon + 4) * (1 - Math.pow(1 - rise, 1.6)) * (0.75 + rnd(i) * 0.3);
          const s = 1.6 * (1 - rise * 0.5);
          o.push(gl(x, y, s * 4, 'light', 0.45), pg([x - s * 0.5, y - s * 0.65, x + s * 0.5, y - s * 0.65, x + s * 0.4, y + s * 0.65, x - s * 0.4, y + s * 0.65], 'light', 0.95), dk(x, y + s * 0.45, s * 0.2, 'coral'));
        }
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.06 * ez(c.T / 3), y: -2 + 2 * ez(c.T / 3)}),
      hap: Array.from({length: 5}, (_, i) => ({t: 0.3 + i * 0.3, kind: 'light' as HK})),
      type: 'rise',
    },
    // Sun: the week's constellation joins up; a shooting star seals it
    {
      draw: (c) => {
        const o: Shape[] = [];
        const P = [
          [30, 42],
          [40, 26],
          [52, 33],
          [60, 14],
          [70, 26],
          [82, 10],
          [92, 24],
        ];
        const lines = ez((c.T - 0.3) / 1.2);
        for (let i = 1; i < 7; i++) {
          const q = cl(lines * 6 - (i - 1));
          if (q > 0) o.push(ln([P[i - 1][0], P[i - 1][1], lerp(P[i - 1][0], P[i][0], q), lerp(P[i - 1][1], P[i][1], q)], 'light', 0.6, 0.35));
        }
        P.forEach(([x, y], i) => o.push(...star4(x, y, 1.6 + (i === 6 && lines >= 1 ? 0.8 : 0), i === 6 && lines >= 1 ? 'coral' : 'light')));
        const s = (c.T - 1.6) / 0.9;
        if (s > 0 && s < 1) for (let k = 0; k < 6; k++) {
          const q = s - k * 0.04;
          if (q > 0) o.push(dk(100 - q * 60, 4 + q * 26, 0.6 - k * 0.07, 'light', 1 - k / 6));
        }
        return o;
      },
      cam: (c) => ({s: 1.1 - 0.08 * ez(c.T / 1.6)}),
      hap: [{t: 0.3, kind: 'light'}, {t: 0.7, kind: 'light'}, {t: 1.1, kind: 'medium'}, {t: 1.5, kind: 'heavy'}, {t: 1.6, kind: 'success'}],
      type: 'slam',
    },
  ],

  // ---------------- evening, not gone yet: the light runs out ----------------
  stilltime: [
    // Mon: a pillar of light under the low sun, shrinking as the evening goes
    {
      bd: (c) => ({sun: 0.05 + slP(c) * 0.3, night: 0.25}),
      draw: (c) => {
        const sx = A.sunX, sy = A.sunY(0.05 + slP(c) * 0.3);
        const H = 4 + slP(c) * 26;
        const o: Shape[] = [fx(pgs(wedge(sx, sy + A.sunR * 0.6, sx, A.cloud + H, 2.4, 6 + H * 0.12), 'light', 0.7)), gl(sx, A.cloud + 1, 7 + H * 0.3, 'light', 0.4)];
        for (let k = 0; k < 5; k++) o.push(ln([sx - 2 - k * 0.4, A.cloud + 2 + k * H / 5, sx + 2 + k * 0.4, A.cloud + 2 + k * H / 5], 'light', 0.7 * (0.6 + 0.4 * Math.sin(c.t * 3 + k)), 0.4));
        return o;
      },
    },
    // Tue: the rock's shadow swings across the ledge like a sundial
    {
      bd: () => ({sun: 0.15, night: 0.25}),
      draw: (c) => {
        const o: Shape[] = [];
        const cx = A.rock.x, cy = A.ledge - 0.5;
        const ang = Math.PI * (0.05 + (1 - slP(c)) * 0.3);
        const L2 = 24 + (1 - slP(c)) * 18;
        o.push(pg([cx - A.rock.w * 0.35, cy, cx + A.rock.w * 0.35, cy, cx + A.rock.w * 0.35 + Math.cos(ang) * L2, cy + Math.sin(ang) * 3 + 2, cx - A.rock.w * 0.35 + Math.cos(ang) * L2, cy + Math.sin(ang) * 3 + 3], 'ink', 0.4));
        for (let i = 0; i < 7; i++) {
          const a = Math.PI * (0.05 + (i / 6) * 0.3);
          const x = cx + Math.cos(a) * 44, y = cy + Math.sin(a) * 4 + 3;
          o.push(ln([x, y - 0.8, x, y + 0.8], i === Math.round((1 - slP(c)) * 6) ? 'coral' : 'paper', 0.9, 0.35));
        }
        return o;
      },
    },
    // Wed: the mountain's shadow creeps across the lake
    {
      bd: () => ({sun: 0.15, night: 0.25}),
      draw: (c) => {
        const cov = 0.25 + (1 - slP(c)) * 0.7;
        const edge = A.water + cov * (92 - A.water);
        const pts: number[] = [0, A.water];
        for (let k = 0; k <= 20; k++) pts.push(100 - k * 5, edge + Math.sin(k * 0.9 + c.t * 0.8) * 0.8);
        pts.splice(2, 0, 100, A.water);
        return [pg(pts, 'ink', 0.38), ln(pts.slice(4), 'light', 0.5, 0.35)];
      },
    },
    // Thu: the pine's shadow stretches long across the ledge
    {
      bd: () => ({sun: 0.15, night: 0.25}),
      draw: (c) => {
        const len = 20 + (1 - slP(c)) * 50;
        const x = A.treeX, y = A.ledge + 1;
        return [pg([x - 2, y, x + 2, y, x - len * 0.2, y + 4, x - len, y + 6, x - len * 0.8, y + 4.5], 'ink', 0.45), ln([x - len, y + 6, x - len - 3, y + 6.3], 'coral', 0.5 + 0.5 * Math.sin(c.t * 3), 0.4)];
      },
    },
    // Fri: alpenglow on the summit, sinking as the light goes
    {
      bd: () => ({sun: 0.12, night: 0.25}),
      draw: (c) => {
        const [sx, sy] = A.summit;
        const H = 3 + slP(c) * 14;
        return [fx(pgs([sx, sy - 0.4, sx + H * 0.7, sy + H, sx - H * 0.6, sy + H * 0.9], 'light', 0.85)), ln([sx - H * 0.6, sy + H * 0.9, sx + H * 0.7, sy + H], 'coral', 0.9, 0.35), gl(sx, sy + H * 0.4, H * 1.4, 'light', 0.4)];
      },
    },
    // Sat: the sun's glitter path narrows on the water
    {
      bd: (c) => ({kind: 'sunset', sun: 0.1 + slP(c) * 0.45}),
      draw: (c) => {
        const o: Shape[] = [];
        const x = A.seaSun[0];
        const w = 1 + slP(c) * 7;
        for (let k = 0; k < 12; k++) {
          const y = A.horizon + 1.5 + k * 2.6;
          const ww = w * (0.6 + k * 0.07) * (0.8 + 0.2 * Math.sin(c.t * 3 + k * 2));
          o.push(ln([x - ww, y, x + ww, y], 'light', 0.85 - k * 0.04, 0.45));
        }
        return o;
      },
    },
    // Sun: the evening's stars come out one by one as the time runs down
    {
      bd: (c) => ({moonY: 0.15 + 0.45 * slP(c), charge: 0.6, night: 0.75}),
      draw: (c) => {
        const o: Shape[] = [];
        const n = Math.round((1 - slP(c)) * 20) + 2;
        for (let i = 0; i < 22; i++) {
          const x = 10 + rnd(i + 31) * 88, y = 4 + rnd(i + 61) * 44;
          o.push(i < n ? dk(x, y, i === n - 1 ? 0.9 : 0.5, i === n - 1 ? 'coral' : 'light', 0.9) : dk(x, y, 0.2, 'mist', 0.3));
        }
        return o;
      },
    },
  ],

  // ---------------- rest day: slow, regenerating ----------------
  rest: [
    // Mon: cloud shadows drift over the cloud sea
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let k = 0; k < 3; k++) {
          const x = -20 + (((c.t * 1.2 + k * 45) % 150));
          o.push(pg(ell(x, A.cloud + 6 + k * 4, 14, 2.6, 16), 'mid', 0.22));
        }
        return o;
      },
      cam: (c) => ({s: 1.02 + 0.01 * Math.sin(c.t * 0.5)}),
      type: 'blur',
    },
    // Tue: dust motes turn slowly in a shaft of sun
    {
      draw: (c) => {
        const p: number[] = [];
        for (let i = 0; i < 26; i++) {
          const u = rnd(i + 2), v = (rnd(i + 5) + c.t * 0.03 * (0.5 + rnd(i))) % 1;
          p.push(48 + u * 26 - v * 18 + Math.sin(c.t * 0.6 + i) * 1.2, 4 + v * 66);
        }
        return [fx(pgs([56, -6, 78, -6, 62, 80, 36, 80], 'light', 0.3)), ds(p, 0.4, 'light', 0.9)];
      },
      type: 'blur',
    },
    // Wed: bubbles rise and pop softly at the surface
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 8; i++) {
          const ph = (rnd(i) + c.t * 0.12) % 1;
          const x = 40 + rnd(i + 8) * 50;
          if (ph < 0.85) o.push(rg(x + Math.sin(c.t + i) * 0.6, 90 - ph * (90 - A.water - 2) / 0.85, 0.5 + ph * 0.5, 'light', 0.8, 0.3));
          else o.push(rg(x, A.water + 1, 1 + (ph - 0.85) * 40, 'light', 1 - (ph - 0.85) / 0.15, 0.3, 0.3 + (ph - 0.85) * 6));
        }
        return o;
      },
      type: 'blur',
    },
    // Thu: a fern unfurls slowly at the foot of the pine
    {
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 4);
        for (let f = 0; f < 3; f++) {
          const x0 = A.treeX - 12 - f * 6, y0 = A.ledge;
          const H = 9 + f * 2;
          const pts: number[] = [];
          const unf = cl(p * 1.2 - f * 0.1);
          for (let i = 0; i <= 20; i++) {
            const u = i / 20;
            if (u <= 0.55 + 0.45 * unf) pts.push(x0 + Math.sin(u * 1.2) * 3 * (f % 2 ? -1 : 1), y0 - u * H);
          }
          const [hx, hy] = [pts[pts.length - 2], pts[pts.length - 1]];
          o.push(ln(pts, 'ink', 1, 0.4));
          if (unf < 1) o.push(rg(hx + 0.8, hy, 1.2 * (1 - unf) + 0.4, 'ink', 1, 0.35, undefined, 0, Math.PI * 2 * (1 - unf * 0.8)));
          for (let i = 3; i < pts.length / 2; i += 2) {
            const x = pts[i * 2], y = pts[i * 2 + 1];
            const l = 2.2 * cl(unf * 2 - i / (pts.length / 2));
            o.push(ln([x, y, x - l, y + l * 0.4], 'ink', 0.9, 0.3), ln([x, y, x + l, y + l * 0.4], 'ink', 0.9, 0.3));
          }
        }
        return o;
      },
      type: 'blur',
    },
    // Fri: a hawk circles the summit, slow and high
    {
      draw: (c) => {
        const [sx, sy] = A.summit;
        const a = c.t * 0.35;
        return [bird(sx + Math.cos(a) * 16, sy - 8 + Math.sin(a) * 4, 2.4, Math.sin(c.t * 0.8) * 0.4 + 1.6), ln([sx + Math.cos(a - 0.4) * 16, sy - 8 + Math.sin(a - 0.4) * 4, sx + Math.cos(a - 0.15) * 16, sy - 8 + Math.sin(a - 0.15) * 4], 'mist', 0.4, 0.25, 0.8)];
      },
      type: 'blur',
    },
    // Sat: gentle swells roll in toward the shore
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let k = 0; k < 4; k++) {
          const ph = (c.t * 0.08 + k / 4) % 1;
          const y = A.horizon + 2 + ph * (A.sand - A.horizon - 3);
          const pts: number[] = [];
          for (let i = 0; i <= 12; i++) pts.push(i * 9, y + Math.sin(i * 0.8 + k) * 0.5 - i * 0.12);
          o.push(ln(pts, 'paper', 0.7 * Math.sin(ph * Math.PI), 0.35));
        }
        return o;
      },
      type: 'blur',
    },
    // Sun: a slow wave of light breathes through the stars
    {
      draw: (c) => {
        const p: number[] = [];
        const q: number[] = [];
        const ph = (c.t / 7) % 1;
        for (let i = 0; i < 40; i++) {
          const x = 6 + rnd(i + 3) * 94, y = 3 + rnd(i + 7) * 50;
          const k = Math.exp(-Math.pow((x / 100 - ph * 1.4 + 0.2) * 5, 2));
          (k > 0.35 ? p : q).push(x, y);
        }
        return [ds(q, 0.3, 'light', 0.5), ds(p, 0.6, 'light', 1)];
      },
      type: 'blur',
    },
  ],

  // ---------------- paused: frozen ----------------
  paused: [
    // Mon: sundogs: two mock suns and a halo in icy air
    {
      bd: () => ({sun: 0.3, mist: 1}),
      draw: (c) => {
        const sx = A.sunX, sy = A.sunY(0.3), R = 16;
        const tw = (i: number) => 0.6 + 0.4 * Math.sin(c.t * 2 + i);
        const p: number[] = [];
        for (let i = 0; i < 18; i++) p.push(sx - 30 + rnd(i) * 60, sy - 20 + rnd(i + 9) * 34);
        return [rg(sx, sy, R, 'light', 0.55 * ez(c.T / 1.5), 0.45, R, Math.PI * 1.05, Math.PI * 1.95), gl(sx - R, sy, 4, 'light', 0.8 * tw(1)), gl(sx + R, sy, 4, 'light', 0.8 * tw(2)), dk(sx - R, sy, 1, 'light', 0.9), dk(sx + R, sy, 1, 'light', 0.9), ds(p, 0.25, 'light', 0.6 + 0.3 * Math.sin(c.t * 4))];
      },
      cam: (c) => ({s: 1.06 - 0.02 * ez(c.T / 0.4)}),
      type: 'stamp',
    },
    // Tue: icicles grow along the ledge; snow caps the rock
    {
      bd: () => ({snow: 0.5, sun: 0.3}),
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 12; i++) {
          const x = 54 + i * 3.6, L2 = (1.5 + rnd(i) * 4) * ez(since(c.T, i * 0.08) / 1.4);
          o.push(pg([x - 0.7, A.ledge + 0.5, x + 0.7, A.ledge + 0.5, x, A.ledge + 0.5 + L2], 'paper', 0.95));
        }
        o.push(pg([A.rock.x - A.rock.w * 0.36, A.rock.top + 3, A.rock.x - A.rock.w * 0.1, A.rock.top + 0.6, A.rock.x + A.rock.w * 0.2, A.rock.top + 0.8, A.rock.x + A.rock.w * 0.38, A.rock.top + 3.4, A.rock.x, A.rock.top + 2.6], 'paper', 0.95));
        return o;
      },
      type: 'stamp',
    },
    // Wed: ice spreads across the lake from the shores
    {
      bd: () => ({frozen: true, sun: 0.35}),
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 2.2);
        for (let i = 0; i < 7; i++) {
          const x0 = i % 2 ? 100 : 10 + i * 8, y0 = A.water + 2 + rnd(i) * 22;
          const dir = i % 2 ? -1 : 1;
          const pts = zig(x0, y0, x0 + dir * 40 * p, y0 + (rnd(i + 4) - 0.5) * 10 * p, 7, 4, i * 11);
          o.push(ln(pts, 'paper', 0.9, 0.35));
        }
        o.push(ds(fallers(10, c.t, 20, 100, A.water + 2, 90, 0, 3).map((v, i) => (i % 2 ? v : v)), 0.3, 'light', 0.5 + 0.4 * Math.sin(c.t * 5)));
        return o;
      },
      type: 'stamp',
    },
    // Thu: snow piles onto the pine's branches; now and then a load slides off
    {
      bd: () => ({snow: 0.7, sun: 0.25}),
      draw: (c) => {
        const o: Shape[] = [];
        const top = A.treeTop(0.78), H = A.ledge - top;
        for (let k = 0; k < 4; k++) {
          const y = top + H * (0.18 + k * 0.2), hw = 3 + k * 2.6;
          const g = ez(since(c.T, k * 0.25) / 1.6);
          o.push(pg([A.treeX - hw * g, y + 1, A.treeX, y - 0.8 * g, A.treeX + hw * g, y + 1, A.treeX, y + 0.4], 'paper', 0.95));
        }
        const dump = c.t % 5;
        if (dump < 1) o.push(ds(burstPts(A.treeX - 8, top + H * 0.5, 10, dump, 6, 40, Math.floor(c.t / 5)), 0.45, 'paper', 1 - dump));
        return o;
      },
      type: 'stamp',
    },
    // Fri: snow drifts over the trail and buries it
    {
      bd: () => ({snow: 0.8, sun: 0.3}),
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 2.5);
        for (let i = 0; i < 18; i++) {
          const u = 0.2 + (i / 17) * 0.75;
          const [x, y] = routeAt(u);
          if (rnd(i) < p) o.push(pg(ell(x, y, 1.4 + rnd(i + 3), 0.7, 8), 'paper', 0.95));
        }
        for (let k = 0; k < 3; k++) {
          const ph = (c.t * 0.9 + k / 3) % 1;
          o.push(ln([110 - ph * 130, 18 + k * 12, 118 - ph * 130, 18 + k * 12 + 0.6], 'paper', 0.7, 0.3));
        }
        return o;
      },
      type: 'stamp',
    },
    // Sat: away: a bottle bobs on the sea, a message inside
    {
      draw: (c) => {
        const x = 71 + Math.sin(c.t * 0.3) * 3, y = A.horizon + 7 + Math.sin(c.t * 1.4) * 0.6;
        const r = Math.sin(c.t * 1.1) * 0.25;
        const pt = (dx: number, dy: number): [number, number] => [x + dx * Math.cos(r) - dy * Math.sin(r), y + dx * Math.sin(r) + dy * Math.cos(r)];
        const body = [pt(-4, -0.9), pt(1.4, -0.9), pt(2.6, -0.5), pt(4, -0.4), pt(4, 0.4), pt(2.6, 0.5), pt(1.4, 0.9), pt(-4, 0.9)].flat();
        const [cx, cy] = pt(4.4, 0);
        return [pg(body, 'ink', 0.9), ln([...pt(-3, 0), ...pt(0.8, 0)], 'paper', 0.8, 0.3), dk(cx, cy, 0.5, 'coral'), rg(x, y + 1, 6, 'mist', 0.5, 0.3, 0.8)];
      },
      type: 'blur',
    },
    // Sun: an aurora sways across the frozen sky
    {
      bd: () => ({night: 1, charge: 0.4}),
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 2);
        for (let i = 0; i < 26; i++) {
          const x = 14 + i * 3.4;
          const top = 8 + Math.sin(i * 0.5 + c.t * 0.6) * 4;
          const len = (12 + Math.sin(i * 0.9 + c.t * 0.9) * 5) * p;
          o.push(ln([x + Math.sin(c.t + i * 0.3) * 0.8, top, x, top + len], 'light', (0.25 + 0.3 * Math.sin(i * 0.7 + c.t * 1.3)) * p, 0.7));
        }
        return o;
      },
      type: 'stamp',
    },
  ],

  // ---------------- a new week: a clean start ----------------
  freshstart: [
    // Mon: the sun's first rim breaks the horizon and swells into a dome
    {
      bd: () => ({sun: -0.6}),
      draw: (c) => {
        const p = ez(since(c.T, 0.4) / 1.6);
        const r = 2 + p * 7;
        const pts: number[] = [];
        for (let i = 0; i <= 16; i++) {
          const a = Math.PI + (i / 16) * Math.PI;
          pts.push(A.sunX + Math.cos(a) * r, A.cloud + Math.sin(a) * r * p);
        }
        return [pg(pts, 'light', 0.95), ln([A.sunX - r - 6, A.cloud, A.sunX + r + 6, A.cloud], 'coral', 0.9 * (1 - p * 0.5), 0.5), gl(A.sunX, A.cloud - 2, 10 + p * 10, 'light', 0.5)];
      },
      cam: (c) => ({s: 1.1 - 0.08 * ez(c.T / 2), y: 5 * (1 - ez(c.T / 2))}),
      hap: [{t: 0.4, kind: 'medium'}, {t: 2, kind: 'heavy'}],
      type: 'rise',
    },
    // Tue: last week's rubble slides off the ledge; a new rock settles
    {
      bd: (c) => ({rockIn: ez((c.T - 1.1) / 0.9), rubble: 0}),
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 5; i++) {
          const age = c.T - 0.2 - i * 0.08;
          const x0 = A.rock.x - 8 + i * 4;
          const x = x0 - Math.max(0, age) * 26, y = A.ledge - 1.2 + (x < 8 ? Math.pow((8 - x) * 0.25, 2) : 0) - Math.abs(Math.sin(Math.max(0, age) * 9)) * 1.2;
          if (y < 95) o.push(pg(ell(x, y, 1.6, 1, 8, age * 4), 'ink'));
        }
        const land = c.T - 2;
        if (land > 0 && land < 0.6) o.push(rg(A.rock.x, A.ledge, 4 + land * 30, 'mist', 0.9 * (1 - land / 0.6), 0.8, 1.5));
        if (c.matrix) {
          const y = A.rock.top - (1 - ez((c.T - 1.1) / 0.9)) * 40;
          o.push(pg(ell(A.rock.x, y + A.rock.h / 2, A.rock.w / 2, A.rock.h / 2, 16), 'ink'));
        }
        return o;
      },
      cam: (c) => ({s: 1.05, y: Math.sin(c.T * 60) * Math.exp(-Math.max(0, c.T - 2) * 6) * (c.T > 2 ? 1.4 : 0)}),
      hap: [{t: 0.2, kind: 'light'}, {t: 2, kind: 'heavy'}, {t: 2.05, kind: 'medium'}],
      type: 'stamp',
    },
    // Wed: mist lifts off the water in curls and leaves a mirror
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 9; i++) {
          const ph = (rnd(i) * 0.4 + c.T * 0.22) % 1.4;
          const x = 22 + i * 8.5, y = A.water + 3 - ph * 20;
          const pts: number[] = [];
          for (let k = 0; k <= 6; k++) pts.push(x + Math.sin(k * 1.1 + c.t + i) * 1.6, y - k * 1.6);
          o.push(ln(pts, 'paper', 0.8 * cl(1 - ph / 1.2), 0.5));
        }
        o.push(ln([20, A.water + 0.6, 98, A.water + 0.6], 'light', 0.5 * ez(c.T / 3), 0.3));
        return o;
      },
      type: 'rise',
    },
    // Thu: new growth: bright buds open at the branch tips
    {
      draw: (c) => {
        const o: Shape[] = [];
        const top = A.treeTop(0.78), H = A.ledge - top;
        for (let i = 0; i < 9; i++) {
          const k = i % 3, side = i % 2 ? 1 : -1;
          const y = top + H * (0.12 + Math.floor(i / 2) * 0.17), x = A.treeX + side * (2 + Math.floor(i / 2) * 2.4);
          const s = back(since(c.T, 0.3 + i * 0.15) / 0.4);
          o.push(dk(x, y, 0.8 * s, i === 0 ? 'coral' : 'light', 0.95));
          void k;
        }
        return o;
      },
      type: 'rise',
    },
    // Fri: the trailhead: chevrons light one after another, pointing up the trail
    {
      draw: (c) => {
        const o: Shape[] = [];
        const [x, y] = routeAt(0.06);
        o.push(ln([x + 5, y, x + 5, y - 7], 'ink', 1, 0.5), pg([x + 5, y - 7, x + 10, y - 6.2, x + 10, y - 4.4, x + 5, y - 5.2], 'ink'));
        for (let i = 0; i < 4; i++) {
          const [cx, cy] = routeAt(0.12 + i * 0.06);
          const on = pulse(c.t - i * 0.18, 1.6, 0.25);
          o.push(ln([cx - 1.6, cy + 1.2, cx, cy - 0.6, cx + 1.6, cy + 1.2], on > 0.5 ? 'coral' : 'light', 0.4 + on * 0.6, 0.5));
        }
        return o;
      },
      cam: (c) => ({s: 1.06, y: 2 * (1 - ez(c.T / 2))}),
      type: 'rise',
    },
    // Sat: a wave sheets up the sand and leaves it smooth and shining
    {
      draw: (c) => {
        const ph = (c.T % 5) / 5;
        const reach = Math.sin(Math.min(1, ph * 2.5) * Math.PI * 0.5) * (ph < 0.4 ? 1 : 1 - (ph - 0.4) / 0.6);
        const y = A.sand + 14 - reach * 12;
        const pts: number[] = [0, 92, 0, y];
        for (let i = 0; i <= 10; i++) pts.push(i * 10, y + Math.sin(i * 1.3) * 0.8 - i * 0.2);
        pts.push(100, 92);
        return [pg(pts, 'mist', 0.4), ln(pts.slice(2, pts.length - 2), 'paper', 0.9, 0.45), ln([10, A.sand + 13, 90, A.sand + 11], 'light', 0.5 * (1 - reach), 0.4)];
      },
      type: 'wipe',
    },
    // Sun: a new moon's first sliver; seven dots for the week, the first one lit
    {
      bd: () => ({charge: 0.08, moonX: 0.75, moonY: 0.22}),
      draw: (c) => {
        const o: Shape[] = [];
        const [mx, my] = toStage(750, 0.22 * 488);
        const g = (c.T % 3) / 3;
        o.push(dk(mx - 2.6 + Math.cos(-0.9 + g * 1.8) * 3.4, my + Math.sin(-0.9 + g * 1.8) * 3.4, 0.5, 'light', 0.9));
        for (let i = 0; i < 7; i++) {
          const a = Math.PI * (0.15 + i * 0.12);
          o.push(dk(mx + Math.cos(a) * 14, my + Math.sin(a) * 14, i === 0 ? 0.8 : 0.35, i === 0 ? 'coral' : 'mist', i === 0 ? cl(since(c.T, 0.6) * 3) : 0.7));
        }
        if (c.matrix) o.push(rg(mx, my, 3.4, 'light', 0.9, 0.5, 3.4, Math.PI * 0.55, Math.PI * 1.45));
        return o;
      },
      type: 'rise',
    },
  ],

  // ---------------- missed yesterday: a gap, then today ----------------
  missed: [
    // Mon: a storm cell over the cloud sea; one bolt, then rain
    {
      bd: () => ({sun: 0.05, night: 0.25, mist: 1.2}),
      draw: (c) => {
        const o: Shape[] = [pgs(ell(62, 17, 22, 5.5, 20), 'mid', 0.85), pgs(ell(70, 13, 13, 5.5, 18), 'mid', 0.85), pgs(ell(55, 13.5, 9, 4.5, 16), 'mid', 0.8), pgs(ell(64, 19, 18, 2.6, 16), 'ink', 0.45)];
        const bolt = c.T - 0.9;
        if ((bolt > 0 && bolt < 0.35) || (c.t % 6 < 0.15 && c.T > 2)) o.push(ln(zig(64, 20, 56, A.cloud - 1, 6, 7, 3), 'paper', 1, 0.6), fl(0.4));
        o.push(...fallers(26, c.t * 3, 44, 92, 18, A.cloud, 1, 9).reduce<Shape[]>((acc, v, i, arr) => (i % 2 ? acc : [...acc, ln([arr[i], arr[i + 1], arr[i] - 0.6, arr[i + 1] + 2.2], 'mist', 0.6, 0.25)]), []));
        return o;
      },
      cam: (c) => ({s: 1.05, x: c.T > 0.9 && c.T < 1.3 ? Math.sin(c.T * 70) * 0.8 : 0, r: 0.012 * (1 - ez(c.T / 2))}),
      hap: [{t: 0.9, kind: 'heavy'}, {t: 0.95, kind: 'heavy'}],
      type: 'jolt',
    },
    // Tue: a pebble falls from the ledge, then rewinds back into place
    {
      draw: (c) => {
        const ph = c.T % 4;
        let x = 70, y = A.ledge - 1.4;
        if (ph > 0.4 && ph < 1.4) {
          const u = (ph - 0.4) / 1;
          x = 70 + u * 8;
          y = A.ledge - 1.4 + u * u * 22;
        } else if (ph >= 1.4 && ph < 1.9) {
          x = 78;
          y = A.ledge + 20.6;
        } else if (ph >= 1.9 && ph < 2.6) {
          const u = 1 - eio((ph - 1.9) / 0.7);
          x = 70 + u * 8;
          y = A.ledge - 1.4 + u * u * 22;
        }
        const o: Shape[] = [pg(ell(x, y, 1.6, 1.3, 10), 'ink')];
        if (ph >= 1.9 && ph < 2.6) for (let k = 1; k < 4; k++) {
          const u = 1 - eio((ph - 1.9 - k * 0.05) / 0.7);
          o.push(dk(70 + u * 8, A.ledge - 1.4 + u * u * 22, 1.1 - k * 0.25, 'mist', 0.7 - k * 0.15));
        }
        if (ph >= 2.6 && ph < 3) o.push(rg(70, A.ledge - 1.4, 2 + (ph - 2.6) * 12, 'coral', 1 - (ph - 2.6) / 0.4, 0.4));
        return o;
      },
      hap: [{t: 2.6, kind: 'heavy'}],
      type: 'jolt',
    },
    // Wed: rain on the lake: rings everywhere
    {
      bd: () => ({sun: 0.15, mist: 1.2}),
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 16; i++) {
          const ph = (rnd(i) + c.t * (0.6 + rnd(i + 3) * 0.3)) % 1;
          const x = 16 + rnd(i + 9 + Math.floor(rnd(i) + c.t * 0.7) * 17) * 84, y = A.water + 3 + rnd(i + 13 + Math.floor(rnd(i) + c.t * 0.7) * 11) * 26;
          o.push(rg(x, y, 0.5 + ph * 3.5, 'light', 0.8 * (1 - ph), 0.3, 0.2 + ph * 0.8));
        }
        o.push(...fallers(18, c.t * 2.5, 10, 100, 0, A.water, 1, 4).reduce<Shape[]>((acc, v, i, arr) => (i % 2 ? acc : [...acc, ln([arr[i], arr[i + 1], arr[i] - 0.5, arr[i + 1] + 2.4], 'mist', 0.55, 0.22)]), []));
        return o;
      },
      type: 'jolt',
    },
    // Thu: seven young pines with a gap; a light pulses where today's goes
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 7; i++) {
          const x = 30 + i * 8;
          if (i === 4) {
            o.push(dk(x, A.ledge - 3, 0.6 + 0.5 * pulse(c.t, 1.4, 0.4), 'coral'), rg(x, A.ledge - 3, 1 + (1 - pulse(c.t, 1.4, 0.4)) * 4, 'coral', 0.6 * pulse(c.t, 1.4, 0.5), 0.3));
            continue;
          }
          o.push(...pine(x, A.ledge, 8 * back(since(c.T, i * 0.08) / 0.4), i < 4 ? 'ink' : 'mid', i < 4 ? 1 : 0.5));
        }
        return o;
      },
      type: 'jolt',
    },
    // Fri: a rockslide blocks the trail; a detour draws itself around it
    {
      bd: () => ({sun: 0.2, mist: 1.1}),
      draw: (c) => {
        const o: Shape[] = [];
        const [x, y] = routeAt(0.55);
        for (let i = 0; i < 6; i++) {
          const age = c.T - 0.2 - i * 0.06;
          const yy = age < 0 ? -20 : Math.min(y - 1 + (i % 3) * 0.6, y - 30 + age * age * 60);
          o.push(pg(ell(x - 3 + i * 1.3, yy, 1.4, 1, 8, i), 'ink'));
        }
        const p = ez(since(c.T, 1.1) / 1.2);
        const det: number[] = [];
        for (let k = 0; k <= 16; k++) {
          const u = k / 16;
          if (u > p) break;
          det.push(x - 8 + u * 16, y + 3 - Math.sin(u * Math.PI) * 9);
        }
        if (det.length > 2) o.push(ln(det, 'coral', 0.9, 0.4, 0.8));
        return o;
      },
      cam: (c) => ({s: 1.08, y: Math.sin(c.T * 60) * Math.exp(-Math.max(0, c.T - 0.6) * 6) * (c.T > 0.6 ? 1 : 0), px: routeAt(0.55)[0], py: routeAt(0.55)[1]}),
      hap: [{t: 0.6, kind: 'heavy'}, {t: 1.1, kind: 'light'}],
      type: 'jolt',
    },
    // Sat: footprints along the shore; a wave takes one; a new one appears ahead
    {
      draw: (c) => {
        const o: Shape[] = [];
        const ph = c.T % 5;
        const wave = ph > 0.8 && ph < 2.2 ? Math.sin(((ph - 0.8) / 1.4) * Math.PI) : 0;
        for (let i = 0; i < 9; i++) {
          const x = 24 + i * 7, y = A.sand + 6 - i * 0.4 + (i % 2 ? -1.2 : 0);
          let a = 0.9;
          if (i === 5) a = ph < 1.5 ? 0.9 : 0;
          if (i === 8) a = ph > 2.6 ? cl((ph - 2.6) * 3) : 0;
          if (a > 0) o.push(pg(ell(x, y, 1.1, 0.55, 8, -0.2), i === 8 ? 'coral' : 'ink', a));
        }
        if (wave > 0) o.push(pg([40, A.sand + 1, 52 + wave * 6, A.sand + 1 + wave * 7, 70, A.sand + 1], 'mist', 0.55), ln([40, A.sand + 1, 52 + wave * 6, A.sand + 1 + wave * 7, 70, A.sand + 1], 'paper', 0.9, 0.4));
        return o;
      },
      type: 'jolt',
    },
    // Sun: a dark cloud drifts over one star, then lets it shine through again
    {
      draw: (c) => {
        const ph = (c.T % 6) / 6;
        const cx = -20 + ph * 140;
        const o: Shape[] = [];
        for (let i = 0; i < 12; i++) o.push(dk(14 + rnd(i + 3) * 84, 6 + rnd(i + 8) * 38, 0.45, 'light', 0.6));
        const sx = 56, sy = 20;
        const hidden = Math.abs(cx - sx) < 11;
        o.push(...star4(sx, sy, hidden ? 0.6 : 2 + (Math.abs(cx - sx) < 20 ? 1 : 0), hidden ? 'mist' : cx > sx ? 'coral' : 'light', hidden ? 0.3 : 1));
        o.push(pgs(ell(cx, sy + 1.5, 12, 3.6, 18), 'mid', 0.9), pgs(ell(cx - 3, sy - 1.2, 6, 3, 14), 'mid', 0.85), pgs(ell(cx + 4, sy - 0.6, 5, 2.6, 14), 'mid', 0.85));
        return o;
      },
      type: 'jolt',
    },
  ],

  // ---------------- week kept: five ----------------
  weekkept: [
    // Mon: five beams fan out from behind the peak, lit in turn
    {
      draw: (c) => {
        const o: Shape[] = [];
        const [px, py] = A.peak2;
        for (let i = 0; i < 5; i++) {
          const k = ez(since(c.T, 0.3 + i * 0.25) / 0.4);
          const a = -Math.PI * (0.38 + i * 0.09);
          if (k > 0.02) o.push(fx(pgs(wedge(px, py + 2, px + Math.cos(a) * 60 * k, py + 2 + Math.sin(a) * 60 * k, 1, 9 * k), 'light', 0.5 * k)));
          o.push(dk(px - 20 + i * 5, py + 12, 0.8, i === 4 && k > 0.9 ? 'coral' : 'light', k > 0.5 ? 1 : 0.3));
        }
        return o;
      },
      cam: (c) => ({s: 1.03 + 0.025 * [0.3, 0.55, 0.8, 1.05, 1.3].reduce((m, b) => Math.max(m, c.T > b ? Math.exp(-(c.T - b) / 0.15) : 0), 0)}),
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.25, kind: (i === 4 ? 'heavy' : 'medium') as HK})).concat([{t: 1.35, kind: 'success'}]),
      type: 'drop',
    },
    // Tue: five tally marks carved in turn
    {
      draw: (c) => {
        const o: Shape[] = [];
        const x0 = A.rock.x - 5.5, y0 = A.rock.top + A.rock.h * 0.3, h = A.rock.h * 0.36;
        for (let i = 0; i < 5; i++) {
          const k = ez(since(c.T, 0.3 + i * 0.28) / 0.18);
          if (i < 4) o.push(ln([x0 + i * 2.6, y0, x0 + i * 2.6 + 0.3, y0 + h * k], 'paper', 0.95, 0.55));
          else o.push(ln([x0 - 1.4, y0 + h * 0.8, x0 - 1.4 + 11 * k, y0 + h * 0.8 - h * 0.6 * k], 'coral', 0.95, 0.55));
          const age = c.T - 0.3 - i * 0.28 - 0.18;
          if (age > 0 && age < 0.5) o.push(ds(burstPts(x0 + i * 2.6, y0 + h, 5, age, 12, 30, i * 7), 0.28, 'ink', 1 - age * 2));
        }
        return o;
      },
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.48 + i * 0.28, kind: (i === 4 ? 'heavy' : 'medium') as HK})).concat([{t: 1.7, kind: 'success'}]),
      type: 'stamp',
    },
    // Wed: five lotus blooms open on the water
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 5; i++) {
          const x = 36 + i * 13, y = A.water + 8 + (i % 2) * 5;
          const k = back(since(c.T, 0.3 + i * 0.25) / 0.5);
          o.push(pg(ell(x, y + 0.8, 3.4, 0.8, 12), 'ink', 0.8));
          for (let p = -2; p <= 2; p++) {
            const a = -Math.PI / 2 + p * 0.5 * k;
            o.push(pg([x, y, x + Math.cos(a - 0.2) * 2.6 * k, y + Math.sin(a - 0.2) * 2.6 * k, x + Math.cos(a) * 3.4 * k, y + Math.sin(a) * 3.4 * k, x + Math.cos(a + 0.2) * 2.6 * k, y + Math.sin(a + 0.2) * 2.6 * k], i === 4 && p === 0 ? 'coral' : 'paper', 0.95));
          }
        }
        return o;
      },
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.25, kind: (i === 4 ? 'heavy' : 'light') as HK})),
      type: 'rise',
    },
    // Thu: five tiers of the pine light up, bottom to top
    {
      draw: (c) => {
        const o: Shape[] = [];
        const top = A.treeTop(0.78), H = A.ledge - top;
        for (let i = 0; i < 5; i++) {
          const k = ez(since(c.T, 0.3 + i * 0.25) / 0.3);
          const y = A.ledge - H * (0.18 + i * 0.17), hw = (5 - i) * 1.9 + 1;
          o.push(ln([A.treeX - hw * k, y, A.treeX + hw * k, y], i === 4 ? 'coral' : 'light', 0.95, 0.6), gl(A.treeX, y, hw * 1.2, 'light', 0.35 * k));
        }
        return o;
      },
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.25, kind: (i === 4 ? 'heavy' : 'medium') as HK})),
      type: 'drop',
    },
    // Fri: five ridgelines light from front to back
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 5; i++) {
          const k = ez(since(c.T, 0.3 + i * 0.25) / 0.35);
          const y = 74 - i * 7;
          const pts: number[] = [];
          for (let j = 0; j <= 12; j++) pts.push(j * 8.6, y - Math.abs(Math.sin(j * 0.7 + i * 1.3)) * 5);
          o.push(ln(pts, i === 4 ? 'coral' : 'light', 0.3 + 0.6 * k, 0.45 + 0.2 * k));
        }
        return o;
      },
      cam: (c) => ({s: 1.03 + 0.04 * ez(c.T / 2)}),
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.25, kind: (i === 4 ? 'heavy' : 'medium') as HK})),
      type: 'rise',
    },
    // Sat: a starfish on the sand; its five arms light one by one
    {
      draw: (c) => {
        const o: Shape[] = [];
        const x = 30, y = A.sand + 8, R = 5;
        for (let i = 0; i < 5; i++) {
          const a = -Math.PI / 2 + (i / 5) * Math.PI * 2;
          const k = ez(since(c.T, 0.3 + i * 0.25) / 0.3);
          o.push(pg([x + Math.cos(a - 0.5) * 1.6, y + Math.sin(a - 0.5) * 1.6 * 0.6, x + Math.cos(a) * R, y + Math.sin(a) * R * 0.6, x + Math.cos(a + 0.5) * 1.6, y + Math.sin(a + 0.5) * 1.6 * 0.6, x, y], k > 0.5 ? (i === 4 ? 'coral' : 'paper') : 'ink', 0.95));
        }
        o.push(gl(x, y, 10, 'light', 0.4 * ez(since(c.T, 1.6) / 0.4)));
        return o;
      },
      cam: (c) => ({s: 1.06 + 0.04 * ez(c.T / 2), px: 52, py: A.sand + 4}),
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.25, kind: (i === 4 ? 'heavy' : 'medium') as HK})),
      type: 'stamp',
    },
    // Sun: a meteor shower: five bright ones among the small
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let i = 0; i < 12; i++) {
          const big = i < 5;
          const st = big ? 0.3 + i * 0.25 : 0.5 + rnd(i) * 3 + Math.floor(c.T / 4) * 4;
          const age = (c.T - st) / (big ? 0.8 : 0.5);
          if (age < 0 || age > 1) continue;
          const x0 = 40 + rnd(i + 5) * 60, y0 = 2 + rnd(i + 9) * 16;
          const x = x0 - age * 30, y = y0 + age * 16;
          o.push(ln([x, y, x + 7 * (big ? 1.6 : 1), y - 3.7 * (big ? 1.6 : 1)], big && i === 4 ? 'coral' : 'light', 1 - age, big ? 0.7 : 0.35), dk(x, y, big ? 0.6 : 0.3, 'light', 1 - age));
        }
        return o;
      },
      hap: [0, 1, 2, 3, 4].map((i) => ({t: 0.3 + i * 0.25, kind: (i === 4 ? 'heavy' : 'light') as HK})),
      type: 'drop',
    },
  ],

  // ---------------- comeback after a lapse: something returns ----------------
  comeback: [
    // Mon: a rainbow forms over the cloud sea, band by band
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let k = 0; k < 4; k++) {
          const p = ez(since(c.T, 0.3 + k * 0.2) / 1.2);
          o.push(rg(56, A.cloud + 4, 30 - k * 2.2, k === 3 ? 'coral' : 'light', k === 3 ? 0.45 : 0.4 + k * 0.08, 1, 30 - k * 2.2, Math.PI, Math.PI + Math.PI * p));
        }
        return o;
      },
      cam: (c) => ({s: 1.12 - 0.1 * ez(c.T / 2.2)}),
      type: 'wipe',
    },
    // Tue: a sprout pushes up through a crack in the rock
    {
      draw: (c) => {
        const x = A.rock.x + 2, y = A.rock.top + 2;
        const g = back(since(c.T, 0.4) / 1);
        const l = ez(since(c.T, 1.1) / 0.6);
        return [ln(zig(x, y + 6, x - 1, y - 1, 4, 1.6, 21), 'ink', 1, 0.5), ln([x, y, x + 0.4, y - 6 * g], 'ink', 1, 0.45), pg(ell(x - 1.8 * l, y - 6 * g, 1.8 * l, 0.8 * l, 8, -0.5), 'ink'), pg(ell(x + 2 * l, y - 6.6 * g, 2 * l, 0.9 * l, 8, 0.5), 'ink'), dk(x + 0.4, y - 6 * g - 0.8, 0.4, 'coral', l)];
      },
      cam: (c) => ({s: 1.1 - 0.07 * ez(c.T / 1.8), px: A.rock.x, py: A.rock.top}),
      hap: [{t: 0.4, kind: 'light'}, {t: 1.1, kind: 'medium'}],
      type: 'rise',
    },
    // Wed: the lake refills; the cracked mud disappears under it
    {
      draw: (c) => {
        const p = ez(since(c.T, 0.3) / 2.4);
        const low = 88, wl = lerp(low, A.water + 2, p);
        const o: Shape[] = [];
        for (let i = 0; i < 10; i++) {
          const x = 24 + i * 7.6, y = A.water + 6 + (i % 3) * 7;
          if (y < wl - 1) o.push(ln(zig(x, y, x + 5, y + 1, 3, 2, i * 5), 'ink', 0.5, 0.3));
        }
        o.push(pg([0, 92, 0, wl, 100, wl, 100, 92], 'mid', 0.25), ln([0, wl, 100, wl], 'light', 0.9, 0.45));
        return o;
      },
      type: 'rise',
    },
    // Thu: a young pine bent low springs upright
    {
      draw: (c) => {
        const x = A.treeX - 22, base = A.ledge;
        const bend = 1 - spr(since(c.T, 0.6) / 1.4, 9, 3.2);
        const H = 18;
        const tip = [x + Math.sin(bend * 1.3) * H, base - Math.cos(bend * 1.3) * H];
        const o: Shape[] = [ln([x, base, x + (tip[0] - x) * 0.5 + bend * 2, base + (tip[1] - base) * 0.5, tip[0], tip[1]], 'ink', 1, 0.6)];
        for (let k = 0; k < 4; k++) {
          const u = 0.35 + k * 0.17;
          const px = x + (tip[0] - x) * u, py = base + (tip[1] - base) * u;
          const hw = (1 - u) * 6 + 1;
          const nx = -(tip[1] - base) / H, ny = (tip[0] - x) / H;
          o.push(pg([px - nx * hw - (tip[0] - x) / H * 2, py - ny * hw - (tip[1] - base) / H * 2, px + (tip[0] - x) / H * 2.6, py + (tip[1] - base) / H * 2.6, px + nx * hw - (tip[0] - x) / H * 2, py + ny * hw - (tip[1] - base) / H * 2], 'ink'));
        }
        return o;
      },
      hap: [{t: 0.6, kind: 'heavy'}, {t: 0.9, kind: 'light'}],
      type: 'drop',
    },
    // Fri: the old trail fades; a new line draws itself over it to the top
    {
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(since(c.T, 0.4) / 2.2);
        const old: number[] = [], nw: number[] = [];
        for (let i = 0; i <= 40; i++) {
          const u = i / 40;
          const [x, y] = routeAt(u);
          old.push(x, y);
          if (u <= p) nw.push(x, y);
        }
        o.push(ln(old, 'mist', 0.6, 0.4, 0.8));
        if (nw.length > 2) o.push(ln(nw, 'ink', 1, 0.5), dk(nw[nw.length - 2], nw[nw.length - 1], 0.8, 'coral'));
        return o;
      },
      cam: (c) => ({s: 1.05, y: 2.5 * (1 - ez(c.T / 2.6))}),
      type: 'wipe',
    },
    // Sat: a whale surfaces and spouts
    {
      draw: (c) => {
        const o: Shape[] = [];
        const x = 71, y = A.horizon + 5;
        const up = back(since(c.T, 0.4) / 0.8);
        const s = since(c.T, 1.1);
        o.push(pg([x - 7, y, x - 4, y - 1.6 * up, x + 3, y - 2.2 * up, x + 7, y - 0.6 * up, x + 8, y], 'ink'));
        if (s > 0 && s < 2) o.push(ds(burstPts(x - 2, y - 2.4, 18, s * 0.6, 10, 18, 5), 0.38, 'paper', cl(1 - s / 2)));
        o.push(rg(x, y + 0.4, 9 + up * 2, 'paper', 0.5, 0.35, 1));
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.04 * ez(c.T / 2)}),
      hap: [{t: 0.4, kind: 'medium'}, {t: 1.1, kind: 'heavy'}],
      type: 'rise',
    },
    // Sun: a faint star flares into a brilliant one
    {
      draw: (c) => {
        const k = since(c.T, 0.6);
        const s = k < 0 ? 0.5 : 0.5 + back(k / 0.5) * 3;
        const o: Shape[] = [gl(50, 20, s * 4, 'light', 0.5), ...star4(50, 20, s, k > 0.3 ? 'light' : 'mist', 1), dk(50, 20, 0.5, 'coral', cl(k * 2))];
        if (k > 0 && k < 1.4) o.push(rg(50, 20, 2 + k * 20, 'light', 0.8 * (1 - k / 1.4), 0.5));
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.06 * ez(c.T / 2), px: 50, py: 20}),
      hap: [{t: 0.6, kind: 'heavy'}, {t: 0.65, kind: 'success'}],
      type: 'blur',
    },
  ],

  // ---------------- week 4, the drift zone: losing the way, then finding it ----------------
  drift: [
    // Mon: a fog bank rises and swallows the peaks
    {
      bd: () => ({mist: 1.5, peak: 0.2, sun: 0.25}),
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 3);
        for (let k = 0; k < 4; k++) {
          const x = 50 + Math.sin(c.t * 0.2 + k * 1.5) * 20;
          o.push(fx(pgs(ell(x, A.cloud - p * (10 + k * 6), 34, 6, 20), 'paper', 0.6)));
        }
        return o;
      },
      cam: (c) => ({s: 1.05, x: Math.sin(c.t * 0.3) * 1.5, r: Math.sin(c.t * 0.25) * 0.006}),
      type: 'blur',
    },
    // Tue: a rock balanced on a point rocks wildly, then steadies
    {
      draw: (c) => {
        const x = 70, y = A.ledge;
        const amp = 0.35 * Math.exp(-Math.max(0, c.T - 1.5) * 0.9) + 0.03;
        const r = Math.sin(c.T * 3.2) * amp;
        const pt = (dx: number, dy: number): [number, number] => [x + dx * Math.cos(r) - dy * Math.sin(r), y - 4 + dx * Math.sin(r) + dy * Math.cos(r)];
        return [pg(ell(x, y - 1.6, 2.6, 1.6, 10), 'ink'), pg([...pt(-5, -0.2), ...pt(-3, -3), ...pt(2, -3.6), ...pt(5, -1), ...pt(0, 0.2)], 'ink'), pg([...pt(-3, -3.2), ...pt(-0.5, -6), ...pt(2.5, -5), ...pt(2, -3.6)], 'mid')];
      },
      type: 'blur',
    },
    // Wed: the boat drifts loose, turning slowly, its rope trailing
    {
      bd: () => ({boatX: 1.6, mist: 1.4, peak: 0.2}),
      draw: (c) => {
        const x = 50 + Math.sin(c.t * 0.15) * 10, y = A.boat[1] - 2;
        const r = c.t * 0.15;
        const pt = (dx: number, dy: number): [number, number] => [x + dx * Math.cos(r) - dy * Math.sin(r) * 0.3, y + dx * Math.sin(r) * 0.3 + dy * Math.cos(r)];
        const hull = [...pt(-5, -0.6), ...pt(5, -0.6), ...pt(3.6, 0.8), ...pt(-3.6, 0.8)];
        const [rx, ry] = pt(-5, -0.4);
        return [pg(hull, 'ink'), ln([rx, ry, rx - 4, ry + 1.6, rx - 7, ry + 1, rx - 10, ry + 2], 'mid', 0.8, 0.3), rg(x, y + 1.4, 8, 'mist', 0.4, 0.3, 1)];
      },
      type: 'blur',
    },
    // Thu: the path forks in the fog; a blaze on a trunk marks the way
    {
      bd: () => ({mist: 1.4, peak: 0.25}),
      draw: (c) => {
        const o: Shape[] = [ln([40, 92, 52, 80, 58, A.ledge], 'mid', 0.7, 1.4), ln([52, 80, 44, A.ledge - 1], 'mid', 0.4, 1)];
        o.push(pg([62, A.ledge, 62.6, 40, 64, 40, 64.6, A.ledge], 'ink'), pg([62.4, 52, 64.2, 52, 64.2, 55, 62.4, 55], 'coral', 0.6 + 0.4 * pulse(c.t, 2, 0.6)));
        for (let k = 0; k < 3; k++) {
          const x = (c.t * 3 + k * 40) % 140 - 20;
          o.push(fx(pgs(ell(x, 60 + k * 8, 20, 3, 16), 'paper', 0.55)));
        }
        return o;
      },
      type: 'blur',
    },
    // Fri: whiteout; a compass needle swings, then settles north
    {
      bd: () => ({mist: 1.4, peak: 0.2, snow: 0.3}),
      draw: (c) => {
        const o: Shape[] = [];
        const cx = 66, cy = 40, R = 7;
        o.push(rg(cx, cy, R, 'ink', 0.9, 0.5));
        for (let i = 0; i < 4; i++) {
          const a = (i / 4) * Math.PI * 2;
          o.push(ln([cx + Math.cos(a) * (R - 1.4), cy + Math.sin(a) * (R - 1.4), cx + Math.cos(a) * R, cy + Math.sin(a) * R], 'ink', 1, 0.4));
        }
        const ang = -Math.PI / 2 + Math.sin(c.T * 4) * 1.6 * Math.exp(-c.T * 0.9);
        o.push(pg([cx + Math.cos(ang) * (R - 1.2), cy + Math.sin(ang) * (R - 1.2), cx + Math.cos(ang + Math.PI / 2) * 0.9, cy + Math.sin(ang + Math.PI / 2) * 0.9, cx - Math.cos(ang + Math.PI / 2) * 0.9, cy - Math.sin(ang + Math.PI / 2) * 0.9], 'coral'), pg([cx - Math.cos(ang) * (R - 1.2), cy - Math.sin(ang) * (R - 1.2), cx + Math.cos(ang + Math.PI / 2) * 0.9, cy + Math.sin(ang + Math.PI / 2) * 0.9, cx - Math.cos(ang + Math.PI / 2) * 0.9, cy - Math.sin(ang + Math.PI / 2) * 0.9], 'mid'));
        for (let k = 0; k < 4; k++) {
          const ph = (c.t * 1.3 + k / 4) % 1;
          o.push(ln([110 - ph * 130, 14 + k * 16, 120 - ph * 130, 14 + k * 16], 'paper', 0.7, 0.35));
        }
        return o;
      },
      hap: [{t: 0.2, kind: 'light'}, {t: 0.9, kind: 'light'}, {t: 2.4, kind: 'medium'}],
      type: 'blur',
    },
    // Sat: a channel buoy rocks in the fog, its light blinking
    {
      bd: () => ({kind: 'beach', mist: 1.3}),
      draw: (c) => {
        const x = 71, y = A.horizon + 7;
        const r = Math.sin(c.t * 1.2) * 0.2;
        const pt = (dx: number, dy: number): [number, number] => [x + dx * Math.cos(r) - dy * Math.sin(r), y + dx * Math.sin(r) + dy * Math.cos(r)];
        const blink = pulse(c.t, 2.4, 0.35);
        const [lx, ly] = pt(0, -8.5);
        const o: Shape[] = [pg([...pt(-3, 0), ...pt(-1.4, -7), ...pt(1.4, -7), ...pt(3, 0)], 'ink'), ln([...pt(-1.8, -3.4), ...pt(1.8, -3.4)], 'paper', 0.8, 0.5), gl(lx, ly, 3 + blink * 8, 'light', 0.3 + blink * 0.6), dk(lx, ly, 0.8, blink > 0.5 ? 'coral' : 'light', 0.9), rg(x, y + 0.6, 6, 'mist', 0.5, 0.3, 1)];
        for (let k = 0; k < 2; k++) o.push(fx(pgs(ell((c.t * 2 + k * 60) % 140 - 20, A.horizon + 2 + k * 7, 26, 3, 16), 'paper', 0.55)));
        return o;
      },
      type: 'blur',
    },
    // Sun: find north: the pointer stars guide the eye to the pole star
    {
      bd: () => ({mist: 1.2, night: 1, charge: 0.3}),
      draw: (c) => {
        const o: Shape[] = [];
        const D = [
          [34, 40],
          [42, 38],
          [48, 42],
          [54, 40],
          [57, 46],
          [66, 47],
          [66, 40],
        ];
        for (let i = 1; i < D.length; i++) o.push(ln([D[i - 1][0], D[i - 1][1], D[i][0], D[i][1]], 'light', 0.35, 0.3));
        D.forEach(([x, y]) => o.push(dk(x, y, 0.7, 'light', 0.9)));
        const p = ez(since(c.T, 0.8) / 1.4);
        const [px, py] = [74, 14];
        o.push(ln([66, 40, lerp(66, px, p), lerp(40, py, p)], 'light', 0.6, 0.3, 1), ...star4(px, py, 1 + p * 1.6, p > 0.95 ? 'coral' : 'light', 0.4 + p * 0.6));
        return o;
      },
      hap: [{t: 2.2, kind: 'medium'}],
      type: 'blur',
    },
  ],

  // ---------------- day 33 of 66: halfway ----------------
  halfway: [
    // Mon: the sun high; a peak's shadow splits the cloud sea, half lit, half dark
    {
      bd: () => ({sun: 0.5}),
      draw: (c) => {
        const p = ez(c.T / 1.6);
        return [fx(pgs([A.peak2[0], A.peak2[1] + 4, A.peak2[0] + 4, A.cloud, 0, A.cloud + 10 * p, 0, A.cloud + 2], 'ink', 0.32 * p)), ln([A.peak2[0] + 4, A.cloud, 0, A.cloud + 10 * p], 'coral', 0.5 * p, 0.35)];
      },
      cam: (c) => ({s: 1.05, x: 3 * (1 - ez(c.T / 2))}),
      type: 'track',
    },
    // Tue: an arch, half built; the keystone's place glows
    {
      draw: (c) => {
        const o: Shape[] = [];
        const cx = 72, base = A.ledge, R = 12;
        for (let i = 0; i < 9; i++) {
          const a0 = Math.PI + (i / 9) * Math.PI, a1 = Math.PI + ((i + 1) / 9) * Math.PI;
          const quad = [cx + Math.cos(a0) * R, base - 2 + Math.sin(a0) * R, cx + Math.cos(a0) * (R + 3), base - 2 + Math.sin(a0) * (R + 3), cx + Math.cos(a1) * (R + 3), base - 2 + Math.sin(a1) * (R + 3), cx + Math.cos(a1) * R, base - 2 + Math.sin(a1) * R];
          if (i < 4) {
            const k = back(since(c.T, 0.2 + i * 0.15) / 0.4);
            o.push(pg(quad.map((v, j) => (j % 2 ? v - (1 - k) * 12 : v)), 'ink'));
          } else if (i === 4) o.push(ln([...quad, quad[0], quad[1]], 'coral', 0.5 + 0.5 * Math.sin(c.t * 3), 0.35));
          else o.push(ln([...quad, quad[0], quad[1]], 'mist', 0.6, 0.3, 0.8));
        }
        return o;
      },
      type: 'track',
    },
    // Wed: a gauge post in the lake: marks to 66, the water at 33
    {
      draw: (c) => {
        const o: Shape[] = [];
        const x = 66, top = 30, bot = 84;
        o.push(pg([x - 1, bot, x - 1, top, x + 1, top, x + 1, bot], 'ink'));
        for (let i = 0; i <= 6; i++) {
          const y = bot - (i / 6) * (bot - top);
          o.push(ln([x + 1, y, x + (i % 3 === 0 ? 4 : 2.4), y], 'ink', 0.9, 0.35));
        }
        const lvl = bot - ez(c.T / 1.6) * 0.5 * (bot - top);
        o.push(ln([x - 14, lvl, x + 14, lvl], 'light', 0.9, 0.45), pg([x + 5, lvl - 1, x + 7, lvl, x + 5, lvl + 1], 'coral'));
        return o;
      },
      type: 'track',
    },
    // Thu: a log's cross-section by the pine: sixty-six rings, the middle one marked
    {
      draw: (c) => {
        const o: Shape[] = [];
        const x = 62, y = A.ledge - 4.5;
        const p = ez(c.T / 1.6);
        for (let k = 0; k < 11; k++) {
          const r = 0.6 + k * 0.42;
          if (k / 11 <= p) o.push(rg(x, y, r * 1.0, k === 5 ? 'coral' : 'ink', k === 5 ? 1 : 0.6, k === 5 ? 0.35 : 0.2, r * 0.9));
        }
        o.push(rg(x, y, 5.2, 'ink', 1, 0.45, 4.7), pg([x - 5.2, y, x - 5.2, y + 2.4, x + 5.2, y + 2.4, x + 5.2, y], 'ink', 0.9));
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.04 * ez(c.T / 2), px: 62, py: A.ledge - 6}),
      type: 'track',
    },
    // Fri: a marker post halfway up the trail: 0, 33, 66
    {
      draw: (c) => {
        const o: Shape[] = [];
        const [x, y] = routeAt(0.62);
        const px = x + 6;
        o.push(ln([px, y, px, y - 14], 'ink', 1, 0.45));
        for (let i = 0; i <= 2; i++) o.push(ln([px, y - i * 6.5, px + (i === 1 ? 3.2 : 2), y - i * 6.5], i === 1 ? 'coral' : 'ink', 1, i === 1 ? 0.5 : 0.35));
        const lit: number[] = [];
        const p = ez(c.T / 1.6) * 0.62;
        for (let i = 0; i <= 30; i++) {
          const u = (i / 30) * p;
          lit.push(...routeAt(u));
        }
        o.push(ln(lit, 'light', 0.7, 0.45));
        return o;
      },
      type: 'track',
    },
    // Sat: a half moon over the sea; its reflection completes the circle
    {
      bd: () => ({kind: 'sunset', sun: -0.1, night: 0.5}),
      draw: (c) => {
        const x = A.seaSun[0], y = A.horizon;
        const p = ez(since(c.T, 0.4) / 1.4);
        const top: number[] = [];
        const bot: number[] = [];
        for (let i = 0; i <= 14; i++) {
          const a = Math.PI + (i / 14) * Math.PI;
          top.push(x + Math.cos(a) * 6, y + Math.sin(a) * 6);
          bot.push(x + Math.cos(-a) * 6, y + Math.sin(-a) * 6 * p);
        }
        const o: Shape[] = [pgs(top, 'light', 1), gl(x, y - 2, 12, 'light', 0.45)];
        for (let k = 0; k < 6; k++) {
          const yy = y + 1 + k * 1;
          const w = Math.sqrt(Math.max(0, 36 - Math.pow(k + 1, 2))) * p;
          o.push(ln([x - w + Math.sin(c.t * 2 + k) * 0.5, yy, x + w + Math.sin(c.t * 2 + k) * 0.5, yy], 'light', 0.6, 0.45));
        }
        return o;
      },
      type: 'track',
    },
    // Sun: sixty-six stars; thirty-three lit
    {
      draw: (c) => {
        const p: number[] = [];
        const q: number[] = [];
        const lit = Math.floor(ez(c.T / 1.8) * 33);
        for (let i = 0; i < 66; i++) {
          const col = i % 11, row = Math.floor(i / 11);
          const x = 30 + col * 6.2 + (row % 2) * 3, y = 6 + row * 6;
          (i < lit ? p : q).push(x, y);
        }
        const o: Shape[] = [ds(q, 0.28, 'mist', 0.6), ds(p, 0.5, 'light', 1)];
        if (lit > 0) o.push(dk(p[p.length - 2], p[p.length - 1], 0.8, 'coral'));
        return o;
      },
      type: 'track',
    },
  ],

  // ---------------- day 66: automatic ----------------
  automatic: [
    // Mon: the sun's whole arc across the sky, sixty-six marks, all lit
    {
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 2);
        for (let i = 0; i < 66; i += 2) {
          const u = i / 65;
          if (u > p) break;
          const a = Math.PI + u * Math.PI;
          o.push(dk(55 + Math.cos(a) * 40, A.cloud + Math.sin(a) * 40 * 0.95, i % 22 === 0 ? 0.7 : 0.35, 'light', 0.9));
        }
        o.push(dk(55 + Math.cos(Math.PI + p * Math.PI) * 40, A.cloud + Math.sin(Math.PI + p * Math.PI) * 38, 0.9, 'coral'));
        return o;
      },
      cam: (c) => ({s: 1.12 - 0.1 * ez(c.T / 2.6)}),
      type: 'stamp',
    },
    // Tue: an ammonite spiral, traced in light on the rock: set in stone
    {
      draw: (c) => {
        const p = ez(c.T / 2.2);
        const pts: number[] = [];
        const x = A.rock.x + 1, y = A.rock.top + A.rock.h * 0.5;
        for (let i = 0; i <= 80; i++) {
          const u = i / 80;
          if (u > p) break;
          const a = u * Math.PI * 5;
          const r = 0.4 + u * 5.4;
          pts.push(x + Math.cos(a) * r, y + Math.sin(a) * r * 0.85);
        }
        const o: Shape[] = [];
        if (pts.length > 2) o.push(ln(pts, 'paper', 0.95, 0.4), dk(pts[pts.length - 2], pts[pts.length - 1], 0.5, 'coral'));
        return o;
      },
      cam: (c) => ({s: 1.1 - 0.06 * ez(c.T / 2.6), px: A.rock.x, py: A.rock.top + 4}),
      type: 'stamp',
    },
    // Wed: a pulse of light runs the mountain's outline and its mirror at once
    {
      draw: (c) => {
        const o: Shape[] = [];
        const ridge = (u: number) => A.water - 2 - Math.abs(Math.sin(u * 5 + 1)) * 10 - Math.sin(u * 13) * 1.5;
        const ph = (c.t * 0.18) % 1;
        for (let i = 0; i <= 40; i++) {
          const u = i / 40, x = 10 + u * 90;
          const k = Math.exp(-Math.pow((u - ph) * 14, 2));
          if (k > 0.05) {
            o.push(dk(x, ridge(u), 0.3 + k * 0.5, 'light', k));
            o.push(dk(x, 2 * A.water - ridge(u) + 1, 0.3 + k * 0.4, 'light', k * 0.7));
          }
        }
        return o;
      },
      type: 'stamp',
    },
    // Thu: roots spread out beneath the pine
    {
      draw: (c) => {
        const o: Shape[] = [];
        const p = ez(c.T / 2.4);
        for (let i = 0; i < 7; i++) {
          const dir = (i / 6 - 0.5) * 2;
          const len = (10 + rnd(i) * 14) * p;
          const pts = zig(A.treeX, A.ledge + 0.5, A.treeX + dir * len * 1.6, A.ledge + 3 + rnd(i + 3) * 9 * p, 6, 1.6, i * 5);
          o.push(ln(pts, 'light', 0.7, 0.35));
          if (p > 0.6) o.push(ln(zig(pts[6], pts[7], pts[6] + dir * 5, pts[7] + 3, 3, 1, i * 7), 'light', 0.5, 0.25));
        }
        return o;
      },
      type: 'stamp',
    },
    // Fri: light flows up the whole trail, again and again: a path worn in
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let k = 0; k < 4; k++) {
          const u = ((c.t * 0.12 + k / 4) % 1);
          const [x, y] = routeAt(u);
          o.push(gl(x, y, 3, 'light', 0.6), dk(x, y, 0.5, k === 0 ? 'coral' : 'light'));
        }
        const [sx, sy] = A.summit;
        o.push(gl(sx, sy, 9, 'light', 0.5 + 0.2 * Math.sin(c.t * 2)));
        return o;
      },
      type: 'stamp',
    },
    // Sat: waves roll in on a perfect beat, each crest glinting in turn
    {
      draw: (c) => {
        const o: Shape[] = [];
        for (let k = 0; k < 5; k++) {
          const ph = (c.t * 0.2 + k / 5) % 1;
          const y = A.horizon + 2 + ph * (A.sand - A.horizon);
          const g = Math.exp(-Math.pow((ph - 0.5) * 6, 2));
          o.push(ln([0, y, 100, y - 2], g > 0.6 ? 'paper' : 'mist', 0.4 + g * 0.6, 0.3 + g * 0.3));
        }
        return o;
      },
      type: 'stamp',
    },
    // Sun: star trails: the whole sky turning around the pole
    {
      draw: (c) => {
        const o: Shape[] = [];
        const px = 70, py = 18;
        const p = ez(c.T / 3);
        for (let i = 0; i < 9; i++) {
          const r = 3 + i * 3.2;
          const a0 = rnd(i) * Math.PI * 2;
          o.push(rg(px, py, r, i === 4 ? 'coral' : 'light', 0.5, 0.25, r, a0, a0 + Math.PI * 2 * (0.15 + 0.85 * p)));
        }
        o.push(dk(px, py, 0.6, 'light'));
        return o;
      },
      cam: (c) => ({s: 1.08 - 0.06 * ez(c.T / 3), px: 70, py: 18}),
      type: 'stamp',
    },
  ],
};

// ---------- defaults: camera, type and haptics per moment ----------
const CAM_DEF: Record<S4, (c: PC) => Partial<Cam>> = {
  setup: (c) => ({s: 1 + 0.04 * ez(c.T / 6)}),
  firstnight: (c) => ({s: 1.06 - 0.03 * ez(c.T / 3), y: -2 * (1 - ez(c.T / 3))}),
  bedtime: (c) => ({s: 1.03, y: Math.sin(c.t * 0.5) * 0.4}),
  wake: (c) => ({s: 1.04}),
  countdown: () => ({s: 1.03}),
  ready: (c) => ({s: 1 + 0.05 * back(c.T / 0.6)}),
  commute: (c) => ({s: 1.07, x: Math.sin(c.T * 0.3) * 2}),
  atgym: (c) => ({s: 1.03 + 0.02 * minuteFlare(c)}),
  verified: (c) => ({s: 1.12 - 0.1 * ez(c.T / 1.2)}),
  stilltime: (c) => ({s: 1.08 - 0.06 * ez(c.T / 8)}),
  rest: (c) => ({s: 1.02 + 0.008 * Math.sin(c.t * 0.5)}),
  paused: (c) => ({s: 1.06 - 0.02 * ez(c.T / 0.3)}),
  freshstart: (c) => ({s: 1.08 - 0.06 * ez(c.T / 1.6), y: 4 * (1 - ez(c.T / 1.6))}),
  missed: (c) => ({s: 1.04, r: 0.01 * (1 - ez(c.T / 1.5))}),
  weekkept: (c) => ({s: 1.04}),
  comeback: (c) => ({s: 1.14 - 0.12 * ez(c.T / 2)}),
  drift: (c) => ({s: 1.06, x: Math.sin(c.t * 0.3) * 1.5, r: Math.sin(c.t * 0.25) * 0.006}),
  halfway: (c) => ({s: 1.05, x: 3 * (1 - ez(c.T / 2))}),
  automatic: (c) => ({s: 1.12 - 0.1 * ez(c.T / 3)}),
};
const TYPE_DEF: Record<S4, TypeStyle> = {
  setup: 'rise', firstnight: 'type', bedtime: 'blur', wake: 'slam', countdown: 'track', ready: 'drop', commute: 'wipe', atgym: 'track', verified: 'slam', stilltime: 'track', rest: 'blur', paused: 'stamp', freshstart: 'rise', missed: 'jolt', weekkept: 'drop', comeback: 'wipe', drift: 'blur', halfway: 'track', automatic: 'stamp',
};
const HAP_DEF: Record<S4, Hap> = {
  setup: [{t: 0.07, kind: 'light'}, {t: 0.25, kind: 'medium'}],
  firstnight: [{t: 0.1, kind: 'light'}],
  bedtime: [{t: 0.1, kind: 'light'}],
  wake: ringHap,
  countdown: [{t: 0.07, kind: 'light'}, {t: 0.2, kind: 'medium'}],
  ready: [{t: 0.1, kind: 'medium'}, {t: 0.3, kind: 'heavy'}],
  commute: [{t: 0.1, kind: 'light'}, {t: 0.35, kind: 'medium'}],
  atgym: [{t: 0.07, kind: 'light'}, {t: 0.2, kind: 'medium'}],
  verified: [{t: 0.1, kind: 'heavy'}, {t: 0.15, kind: 'success'}],
  stilltime: [{t: 0.1, kind: 'medium'}],
  rest: [{t: 0.1, kind: 'light'}],
  paused: [{t: 0.05, kind: 'medium'}],
  freshstart: [{t: 0.1, kind: 'medium'}],
  missed: [{t: 0.1, kind: 'heavy'}],
  weekkept: [{t: 0.1, kind: 'medium'}],
  comeback: [{t: 0.1, kind: 'medium'}, {t: 0.6, kind: 'heavy'}],
  drift: [{t: 0.1, kind: 'light'}],
  halfway: [{t: 0.1, kind: 'medium'}],
  automatic: [{t: 0.1, kind: 'heavy'}, {t: 0.2, kind: 'success'}],
};

/** the light of the hour, per moment (Ridge's painted world) */
const LIGHT: Record<S4, P> = {
  setup: {sun: 0.4}, firstnight: {sun: 0.05, night: 0.75}, bedtime: {sun: 0.05, night: 1}, wake: {sun: 0.2}, countdown: {sun: 0.25}, ready: {sun: 0.4}, commute: {sun: 0.45}, atgym: {sun: 0.5}, verified: {sun: 0.55}, stilltime: {sun: 0.1, night: 0.25}, rest: {sun: 0.45, mist: 1.1}, paused: {sun: 0.3, mist: 1}, freshstart: {sun: 0.2}, missed: {sun: 0.12, night: 0.25, mist: 1.2}, weekkept: {sun: 0.55}, comeback: {sun: 0.3}, drift: {sun: 0.3, mist: 1.5, peak: 0.2}, halfway: {sun: 0.5}, automatic: {sun: 0.6},
};
const BASE: ((s: S4) => P)[] = [
  () => ({kind: 'sunrise'}),
  () => ({kind: 'ridge', tree: 0.32}),
  () => ({kind: 'lake'}),
  () => ({kind: 'ridge', noRock: true, tree: 0.78}),
  () => ({kind: 'path', trail: 0, noYou: true}),
  (s) => ({kind: s === 'stilltime' || s === 'bedtime' || s === 'firstnight' ? 'sunset' : 'beach'}),
  (s) => ({kind: 'night', night: s === 'wake' || s === 'ready' || s === 'commute' ? 0.75 : 1, charge: 0.7, moonX: 0.8, moonY: 0.2}),
];

export type Built = {scene: Scene3; shapes: Shape[]; cam: Cam; type: TypeStyle};

/**
 * Framing: each scene is shot closer on its own subject, so the main object fills the frame and every
 * moment gets its own composition. Found once per scene from the shapes it draws, then the camera
 * pushes in to it over the first second (the establishing shot narrows to the subject).
 */
type Frame = {px: number; py: number; s: number; x0?: number; x1?: number; y0?: number; y1?: number};
const FRAME = new Map<string, Frame>();
const frameOf = (key: string, sc: Scn, c: PC) => {
  const hit = FRAME.get(key);
  if (hit) return hit;
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  const add = (x: number, y: number) => {
    if (x < -5 || x > 105 || y < -5 || y > 97) return;
    x0 = Math.min(x0, x);
    x1 = Math.max(x1, x);
    y0 = Math.min(y0, y);
    y1 = Math.max(y1, y);
  };
  for (const T of [1.2, 2.4, 3.6]) {
    const shapes = embolden(sc.draw({...c, T, t: 100 + T, at: 100, d: {...c.d, atgym: Math.min(c.d.atgym, PROOF - 30)}}));
    for (const q of shapes) {
      if (q.k === 'flash' || q.k === 'glow') continue;
      if (q.k === 'disc' || q.k === 'ring') {
        const r = q.k === 'ring' ? q.r : q.r;
        if (r > 30) continue;
        add(q.x - r, q.y - (q.k === 'ring' ? q.ry ?? r : r));
        add(q.x + r, q.y + (q.k === 'ring' ? q.ry ?? r : r));
        continue;
      }
      let a0 = Infinity, a1 = -Infinity;
      for (let i = 0; i < q.p.length; i += 2) {
        a0 = Math.min(a0, q.p[i]);
        a1 = Math.max(a1, q.p[i]);
      }
      if (q.k !== 'dots' && a1 - a0 > 70) continue;
      for (let i = 0; i < q.p.length; i += 2) add(q.p[i], q.p[i + 1]);
    }
  }
  let f: Frame = {px: 55, py: 46, s: 1};
  if (x0 < x1) {
    const size = Math.max(x1 - x0, (y1 - y0) * 1.15, 1);
    f = {px: (x0 + x1) / 2, py: (y0 + y1) / 2, s: Math.min(sc.zoom ?? 1.85, Math.max(1, 46 / size)), x0, x1, y0, y1};
  }
  FRAME.set(key, f);
  return f;
};
export const scnFor = (s: S4, day: Day) => W[s][day];
export const typeFor = (s: S4, day: Day): TypeStyle => W[s][day].type ?? TYPE_DEF[s];
export const hapFor = (s: S4, day: Day): Hap => W[s][day].hap ?? HAP_DEF[s];

/**
 * Objects read at card size only if they're big: every object is drawn larger around its own centre,
 * so it stays where it belongs in the world (a pebble on the ledge, a mark on the rock) but fills more
 * of the frame. Wide washes (bands, shadows, clouds) keep their size.
 */
const embolden = (S: Shape[]): Shape[] =>
  S.map((q) => {
    if (FIX.has(q)) return q;
    switch (q.k) {
      case 'disc':
        return {...q, r: q.r * 1.55};
      case 'dots':
        return {...q, r: q.r * 1.5};
      case 'ring':
        return {...q, r: q.r * 1.2, ry: q.ry != null ? q.ry * 1.2 : undefined, w: (q.w ?? 0.7) * 1.35};
      case 'line':
        return {...q, w: (q.w ?? 0.8) * 1.35};
      case 'poly': {
        let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, cx = 0, cy = 0;
        const n = q.p.length / 2;
        for (let i = 0; i < q.p.length; i += 2) {
          x0 = Math.min(x0, q.p[i]);
          x1 = Math.max(x1, q.p[i]);
          y0 = Math.min(y0, q.p[i + 1]);
          y1 = Math.max(y1, q.p[i + 1]);
          cx += q.p[i] / n;
          cy += q.p[i + 1] / n;
        }
        if (x1 - x0 > 26 || y1 - y0 > 26) return q;
        const k = 1.65;
        // grow around the centre, but keep the base where it sits (things stay on the ground)
        const by = y1;
        return {...q, p: q.p.map((v, i) => (i % 2 ? by + (v - by) * k - (by - cy) * 0 : cx + (v - cx) * k))};
      }
      default:
        return q;
    }
  });

export const build = (s: S4, day: Day, c: PC): Built => {
  const sc = W[s][day];
  const light = day === 6 ? {sun: 0.1} : LIGHT[s];
  const base: Scene3 = {kind: 'sunrise', seed: WSEED[day], tree: grow(c.D.day), cracks: 0, broken: 0, rubble: Math.min(7, Math.floor(c.D.sessions / 3)), sun: 0.4, night: 0, mist: 0.8, rain: 0, peak: 1, birds: 0};
  const scene = {...base, ...light, ...BASE[day](s), ...(sc.bd ? sc.bd(c) : {})} as Scene3;
  const mv = {s: 1, x: 0, y: 0, r: 0, ...CAM_DEF[s](c), ...(sc.cam ? sc.cam(c) : {})};
  const fr = frameOf(`${s}:${day}:${c.pos}`, sc, c);
  const k = ez(c.T / 1.3);
  const push = 1 + (fr.s - 1) * k;
  // push in on the subject and bring it toward the middle of the picture
  const cam: Cam = {...mv, s: mv.s * push, px: mv.px ?? fr.px, py: mv.py ?? fr.py, x: mv.x + (mv.px == null ? (64 - fr.px) * 0.8 * k * (fr.s - 1) : 0), y: mv.y + (mv.py == null ? (42 - fr.py) * 0.6 * k * (fr.s - 1) : 0)};
  // never crop the subject: slide the shot so the subject's box stays inside the picture
  if (fr.y0 != null) {
    const px = cam.px!, py = cam.py!, sc2 = cam.s;
    const ty = (y: number) => py + (y - py) * sc2 + cam.y, tx = (x: number) => px + (x - px) * sc2 + cam.x;
    if (ty(fr.y0) < -1.5) cam.y += -1.5 - ty(fr.y0);
    else if (ty(fr.y1!) > 95) cam.y -= Math.min(ty(fr.y1!) - 95, ty(fr.y0) + 1.5);
    if (tx(fr.x1!) > 104) cam.x -= tx(fr.x1!) - 104;
    if (tx(fr.x0!) < 3) cam.x += 3 - tx(fr.x0!);
  }
  return {scene, shapes: embolden(sc.draw(c)), cam, type: sc.type ?? TYPE_DEF[s]};
};

// ---------- Matrix only: the day's world as a few faint lines, so the objects have a place ----------
export const worldShapes = (day: Day, sc: Scene3, c: PC): Shape[] => {
  const o: Shape[] = [];
  const wave = (y: number, amp: number, m: Mat, a: number, step = 2.6) => {
    const p: number[] = [];
    for (let x = 0; x <= 100; x += step) p.push(x, y + Math.sin(x * 0.12 + c.t * 0.5) * amp);
    return ln(p, m, a, 0.5);
  };
  switch (day) {
    case 0: {
      o.push(wave(A.cloud, 0.6, 'mist', 0.9), ln([0, 44, 10, 30, 20, 40], 'mid', 0.5, 0.5), ln([60, A.cloud - 1, A.peak2[0], A.peak2[1], 100, A.cloud - 4], 'mid', 0.5, 0.5));
      const sy = A.sunY(sc.sun);
      if (sy < A.cloud - 1) o.push(rg(A.sunX, sy, A.sunR, 'light', 0.8, 0.5, A.sunR, 0, Math.PI * 2), dk(A.sunX, sy, 1.2, 'light', 0.9));
      break;
    }
    case 1:
      o.push(ln([0, A.ledge, 100, A.ledge], 'mid', 0.6, 0.5));
      if (!(sc.broken > 0.05) && sc.kind !== 'hourglass') o.push(ln([...ell(A.rock.x, A.rock.top + A.rock.h / 2, A.rock.w / 2, A.rock.h / 2, 18), A.rock.x + A.rock.w / 2, A.rock.top + A.rock.h / 2], 'mid', 0.7, 0.5));
      break;
    case 2:
      o.push(ln([0, A.water, 100, A.water], 'mid', 0.7, 0.5), ln([0, A.water - 6, 20, A.water - 12, 40, A.water - 7, 62, A.water - 14, 100, A.water - 5], 'mist', 0.6, 0.4), wave(A.water + 7, 0.4, 'mist', 0.6, 4));
      if (sc.boatX == null) o.push(ln([A.boat[0] - 4, A.boat[1], A.boat[0] + 4, A.boat[1]], 'mid', 0.8, 0.6));
      break;
    case 3:
      if (sc.kind !== 'hourglass') o.push(ln([0, A.ledge, 100, A.ledge], 'mid', 0.6, 0.5), ...pine(A.treeX, A.ledge, A.ledge - A.treeTop(0.78), 'mid', 0.55));
      else o.push(ln([0, A.ledge, 100, A.ledge], 'mid', 0.6, 0.5));
      break;
    case 4: {
      const [sx, sy] = A.summit;
      o.push(ln([0, 70, sx - 18, sy + 22, sx, sy, sx + 22, sy + 26, 100, 64], 'mid', 0.6, 0.5));
      const p: number[] = [];
      for (let i = 0; i < ROUTE.length; i += 2) p.push(ROUTE[i][0], ROUTE[i][1]);
      o.push(ln(p, 'mist', 0.5, 0.35, 1));
      break;
    }
    case 5:
      o.push(ln([0, A.horizon, 100, A.horizon], 'mid', 0.7, 0.5), wave(A.sand, 0.5, 'mist', 0.7, 3));
      if (sc.kind === 'beach') o.push(ln([88, A.sand, 87, A.sand - 10, 85, A.sand - 20], 'mid', 0.7, 0.6), ln([85, A.sand - 20, 79, A.sand - 18], 'mid', 0.6, 0.4), ln([85, A.sand - 20, 91, A.sand - 17], 'mid', 0.6, 0.4), ln([85, A.sand - 20, 82, A.sand - 15], 'mid', 0.6, 0.4));
      break;
    case 6: {
      o.push(wave(A.nightWater + 6, 1.2, 'mid', 0.6, 3));
      const mx = sc.moonX != null ? toStage(sc.moonX * 1000, 0)[0] : 64.8, my = sc.moonY != null ? toStage(0, sc.moonY * 488)[1] : 15.1;
      o.push(dk(mx, my, 3.4, 'light', 0.85));
      for (let i = 0; i < 8; i++) o.push(dk(8 + rnd(i + 70) * 90, 4 + rnd(i + 80) * 50, 0.3, 'mist', 0.6));
      break;
    }
  }
  return o;
};
