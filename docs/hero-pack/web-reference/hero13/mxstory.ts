/**
 * Matrix Dynamic: the full-screen done flow, every screen and every day, in one dot language.
 * Static structure is lit cells; anything that moves is a free dot that keeps its slot, so it glides;
 * a new phase re-deals every dot and they fly to the next form. Each screen has one beat, on the same
 * frame as its haptic (screens12 CFG_M), then holds still. Coral is one small accent: you, now, or the
 * last piece. The finish is built tap by tap and stays built: raise the sun, lay the wall, charge the
 * battery, load the bar, push to +1, close the ring, run the week's sand through and turn it over.
 */
import type {Opts} from '../hero4/dots';
import {hash} from '../hero4/dots';
import {G, cl, eio, ez, lerp, spr} from './mxlib';

const TAU = Math.PI * 2;
type P = [number, number];

export type Climax = {eyebrow: string; lastEyebrow: string; title: string; sub: (n: number) => string; idle: string; mid: string; end: string};
export const MX_CLIMAX: Record<number, Climax> = {
  0: {eyebrow: 'TODAY’S SUNRISE', lastEyebrow: 'THE WEEK’S LAST SUNRISE', title: 'Raise it.', sub: (n) => `Tap **${n} times** to lift the sun over the horizon.`, idle: 'Tap to raise the sun', mid: 'Higher', end: 'The sun is up, and so is the count.'},
  1: {eyebrow: 'TODAY’S BLOCK', lastEyebrow: 'THE WEEK’S LAST BLOCK', title: 'Build it.', sub: (n) => `Tap **${n} times.** Every session is a block in the wall.`, idle: 'Tap to place a block', mid: 'Next block', end: 'Set in place. The wall gets taller every session.'},
  2: {eyebrow: 'TODAY’S CHARGE', lastEyebrow: 'THE WEEK’S LAST CHARGE', title: 'Charge it.', sub: (n) => `Tap **${n} times** to fill today’s charge.`, idle: 'Tap to charge', mid: 'Charging', end: 'Fully charged. Training gives back more than it takes.'},
  3: {eyebrow: 'TODAY’S BAR', lastEyebrow: 'THE WEEK’S LAST LIFT', title: 'Load it.', sub: (n) => `Tap **${n} times.** Every tap adds a plate.`, idle: 'Tap to add a plate', mid: 'Add another', end: 'Loaded and lifted. One more rep for the habit.'},
  4: {eyebrow: 'TODAY’S PUSH', lastEyebrow: 'THE WEEK’S LAST PUSH', title: 'Push it.', sub: (n) => `Tap **${n} times** to push today to the top.`, idle: 'Tap to push', mid: 'Higher', end: 'Top reached. One more on the count.'},
  5: {eyebrow: 'TODAY’S RING', lastEyebrow: 'THE WEEK’S LAST RING', title: 'Close it.', sub: (n) => `Tap **${n} times** to close today’s ring.`, idle: 'Tap to close the ring', mid: 'Keep closing', end: 'Ring closed. Habits are loops you keep closing.'},
  6: {eyebrow: 'THE WEEK’S SAND', lastEyebrow: 'THE WEEK’S LAST GRAINS', title: 'Turn it.', sub: (n) => `Tap **${n} times.** One day of sand for each.`, idle: 'Tap to let a day fall', mid: 'Next day', end: 'Every day through. Turn it over and a new week starts.'},
};
export const MX_TALLY = ['SUNRISES', 'BLOCKS LAID', 'CHARGES', 'BARS LIFTED', 'PUSHES', 'RINGS CLOSED', 'WEEKS TURNED'];

export type MCal = {lead: number; cells: string[]; target: number; sessions: number};
export type SC = {
  t: number; lt: number; cx: number; cy: number; cols: number; rows: number;
  N: number; taps: number; tapTimes: number[]; tapAt: number | null; sealT: number | null; since: number;
  D: {day: number; sessions: number}; day: number; pos: string; PW: {done: number; today: number};
  cal?: MCal; pick?: boolean; picked?: boolean; pickAt?: number | null;
};
export type Glow = {x: number; y: number; r: number; a: number};
export type Out = {g: G; ph?: string | number; o?: Opts; flash?: number; glow?: Glow[]} | null;
type Res = {ph?: string | number; o?: Opts; flash?: number; glow?: Glow[]} | void;

// ---------- helpers ----------
const seg = (x: number, a: number, d: number) => cl((x - a) / d);
/** a quick spring 0 → 1 from a = 0: lands in about 0.14 s, a small overshoot, settled by 0.4 s */
const sp = (a: number) => (a <= 0 ? 0 : a > 0.6 ? 1 : spr(a, 11, 9));
/** a pulse that decays after an event at a = 0 */
const hit = (a: number, d = 0.25) => (a >= 0 ? Math.exp(-a / d) : 0);
const C = (v: number) => Math.floor(v) + 0.5;
const eo5 = (x: number) => 1 - Math.pow(1 - cl(x), 5);
const gb = (x: number) => Math.exp(-x * x);
const path = (V: P[]) => {
  const L = [0];
  for (let i = 1; i < V.length; i++) L.push(L[i - 1] + Math.hypot(V[i][0] - V[i - 1][0], V[i][1] - V[i - 1][1]));
  const len = L[L.length - 1];
  const idx = (s: number) => {
    let i = 1;
    while (i < V.length - 1 && L[i] < s) i++;
    return i;
  };
  const at = (s: number): P => {
    const q = Math.max(0, Math.min(len, s)), i = idx(q), u = (q - L[i - 1]) / (L[i] - L[i - 1] || 1);
    return [lerp(V[i - 1][0], V[i][0], u), lerp(V[i - 1][1], V[i][1], u)];
  };
  const dir = (s: number): P => {
    const i = idx(Math.max(0, Math.min(len, s))), dx = V[i][0] - V[i - 1][0], dy = V[i][1] - V[i - 1][1], d = Math.hypot(dx, dy) || 1;
    return [dx / d, dy / d];
  };
  return {len, at, dir, L};
};
/** a ring of free dots thrown out from (x, y) at a = 0; always pushed, dark when idle */
const ripple = (g: G, x: number, y: number, r0: number, r1: number, a: number, d: number, n: number, b = 0.6) => {
  const live = a >= 0 && a < d, p = live ? ez(a / d) : 0;
  for (let i = 0; i < n; i++) {
    const an = (i / n) * TAU, r = lerp(r0, r1, p);
    g.fr(x + Math.sin(an) * r, y - Math.cos(an) * r, live ? b * (1 - a / d) : 0);
  }
};
/** a diagonal band of light that crosses the art once every `per` seconds (calm idle) */
const sheen = (dx: number, dy: number, t: number, per = 3.4, span = 34, w = 3.5) => {
  const u = ((((t % per) + per) % per) / per) * (2 * span + 6 * w) - span - 3 * w;
  const d = dx + dy * 0.55 - u;
  return Math.exp(-(d * d) / (w * w));
};

// LED digits (5 x 7) and a small 3 x 5 type for labels
const F5: Record<string, string[]> = {
  '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  '3': ['11110', '00001', '00001', '01110', '00001', '00001', '11110'],
  '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
  ':': ['0', '0', '1', '0', '1', '0', '0'],
};
const F3: Record<string, string[]> = {
  M: ['#...#', '##.##', '#.#.#', '#...#', '#...#'], T: ['###', '.#.', '.#.', '.#.', '.#.'], W: ['#...#', '#...#', '#.#.#', '##.##', '#...#'],
  F: ['###', '#..', '##.', '#..', '#..'], S: ['.##', '#..', '.#.', '..#', '##.'],
  '0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'], '2': ['##.', '..#', '.#.', '#..', '###'],
  '3': ['##.', '..#', '.#.', '..#', '##.'], '4': ['#.#', '#.#', '###', '..#', '..#'], '5': ['###', '#..', '##.', '..#', '##.'],
  '6': ['.##', '#..', '###', '#.#', '###'], '7': ['###', '..#', '.#.', '.#.', '.#.'], '8': ['###', '#.#', '###', '#.#', '###'], '9': ['###', '#.#', '###', '..#', '##.'],
};
const txt3 = (g: G, s: string, cx: number, y: number, b: number) => {
  const w = [...s].reduce((a, ch) => a + (F3[ch]?.[0].length ?? 3) + 1, -1);
  let x = Math.round(cx - w / 2);
  for (const ch of s) {
    F3[ch]?.forEach((row, j) => [...row].forEach((c, i) => c === '#' && g.on(x + i, y + j, b)));
    x += (F3[ch]?.[0].length ?? 3) + 1;
  }
};
/** LED digits on fixed slots laid out for `fmt`: unlit cells dim, so a changing number flips in place */
const led = (g: G, s: string, fmt: string, cx: number, y: number, k: number, b: number, dim: number, gap: number, coral = -1) => {
  const W = [...fmt].reduce((a, ch) => a + F5[ch][0].length * k + gap, -gap);
  let x = Math.round(cx - W / 2);
  const sv = s.padStart(fmt.length, ' ');
  [...fmt].forEach((fch, i) => {
    const R = F5[sv[i]] ?? null, w = F5[fch][0].length;
    for (let r = 0; r < 7; r++)
      for (let c = 0; c < w; c++) {
        const on = R ? R[r][c] === '1' : false;
        if (!on && dim <= 0) continue;
        for (let v = 0; v < k; v++) for (let u = 0; u < k; u++) g.on(x + c * k + u, y + r * k + v, on ? b : dim, on && i === coral ? 1 : 0);
      }
    x += w * k + gap;
  });
};
/** the cells of a polyline with thickness (1 or 2), up to arc length upTo */
const stroke = (g: G, V: P[], upTo: number, b: number, thick = 1, c = 0) => {
  const pt = path(V);
  for (let s = 0; s <= Math.min(upTo, pt.len) + 1e-6; s += 0.35) {
    const [x, y] = pt.at(s);
    g.on(x, y, b, c);
    if (thick > 1) g.on(x + 1, y, b, c), g.on(x, y + 1, b, c);
  }
  return pt;
};
const cellsOf = (V: P[], thick = 2) => {
  const pt = path(V), S = new Set<number>();
  for (let s = 0; s <= pt.len; s += 0.3) {
    const [x, y] = pt.at(s);
    S.add(Math.floor(y) * 256 + Math.floor(x));
    if (thick > 1) S.add(Math.floor(y) * 256 + Math.floor(x + 1)), S.add(Math.floor(y + 1) * 256 + Math.floor(x));
  }
  return S;
};

// ============================== 1. VERIFIED ==============================
// One beat at 0.75 s on every day (CFG_M.verified haptics: heavy 0.75, success 0.8). Never the day's done object.
const BEAT_V = 0.75;
const vMon = (g: G, s: SC): Res => {
  // a verified seal: an eight-lobed rosette, the check cut out of it
  const {cx, cy, lt: T, t} = s;
  const X = cx, Y = C(cy) - 2, a = T - BEAT_V;
  const V: P[] = [[X - 7, Y + 0.5], [X - 2.5, Y + 5], [X + 6.5, Y - 4.5]];
  const pt = path(V), pen = pt.len * eio(seg(T, 0.42, BEAT_V - 0.42));
  const cut = cellsOf(V.map(([x, y]) => [x, y] as P), 2);
  const cutTo = new Set<number>();
  for (let q = 0; q <= pen; q += 0.3) {
    const [x, y] = pt.at(q);
    for (const [u, v] of [[0, 0], [1, 0], [0, 1]]) cutTo.add(Math.floor(y + v) * 256 + Math.floor(x + u));
  }
  void cut;
  const pls = hit(a, 0.2);
  for (let y = Math.floor(Y - 15); y <= Y + 15; y++)
    for (let x = Math.floor(X - 15); x <= X + 15; x++) {
      const dx = x + 0.5 - X, dy = y + 0.5 - Y, r = Math.hypot(dx, dy), th = Math.atan2(dx, -dy);
      const rr = 12.2 + 1.25 * Math.cos(8 * th);
      if (r > rr) continue;
      if (cutTo.has(y * 256 + x)) continue;
      const rim = r > rr - 1.1;
      g.on(x, y, (rim ? 0.95 : 0.72) + 0.25 * pls + (T > 1.2 ? 0.16 * sheen(dx, dy, t - 1.2, 3.6, 18, 3) : 0));
    }
  const [tx, ty] = pt.at(pt.len);
  g.on(tx, ty, T > BEAT_V - 0.03 ? 1 : 0, 1);
  ripple(g, X, Y, 13, 23, a, 0.6, 64, 0.55);
  return {o: {stagger: 0.3}, glow: [{x: X, y: Y, r: 22, a: 0.22 * hit(a, 0.35)}], flash: 0.08 * hit(a, 0.12)};
};
const vTue = (g: G, s: SC): Res => {
  // the padlock opens: verified means unlocked
  const {cx, cy, lt: T, t} = s;
  const bx = Math.floor(cx) - 9, by = Math.floor(cy) - 1, BW = 19, BH = 14, a = T - BEAT_V;
  const kx = Math.floor(cx);
  const key = new Set([by + 4, by + 5].flatMap((y) => [kx - 1, kx, kx + 1].map((x) => y * 256 + x)).concat([by + 6, by + 7, by + 8].map((y) => y * 256 + kx)));
  for (let j = 0; j < BH; j++)
    for (let i = 0; i < BW; i++) {
      if ((i === 0 || i === BW - 1) && (j === 0 || j === BH - 1)) continue;
      const x = bx + i, y = by + j;
      if (key.has(y * 256 + x)) {
        if (T > BEAT_V && (y === by + 6 || y === by + 7) && x === kx) g.on(x, y, 1, 1);
        continue;
      }
      g.on(x, y, 0.78 + (T > 1.2 ? 0.16 * sheen(i - 9, j - 7, t - 1.2, 3.6, 16, 3) : 0) + 0.18 * hit(a, 0.2));
    }
  // the shackle: free dots, so it lifts in one piece. The left leg is long, so it stays in the body.
  const lift = 5 * sp(T - 0.62);
  const ax = cx, ay = by - 5;
  for (let y = ay - 7; y <= by + 6; y++)
    for (let x = Math.floor(ax - 7); x <= ax + 7; x++) {
      const dx = x + 0.5 - ax, dy = y + 0.5 - ay;
      let on = false;
      if (dy <= 0) on = Math.hypot(dx, dy) >= 4.4 && Math.hypot(dx, dy) <= 6.4;
      else on = (dx >= -6.5 && dx <= -4.5 && y <= by + 5) || (dx >= 4.5 && dx <= 6.5 && y <= by + 1);
      if (!on) continue;
      const yy = y + 0.5 - lift;
      g.fr(x + 0.5, yy, yy < by - 0.2 ? 0.95 : 0);
    }
  ripple(g, cx, by + 6, 3, 17, a, 0.55, 48, 0.45);
  return {o: {stagger: 0.3}, glow: [{x: cx, y: by + 6, r: 18, a: 0.2 * hit(a, 0.35)}], flash: 0.06 * hit(a, 0.12)};
};
const vWed = (g: G, s: SC): Res => {
  // a heartbeat that writes the check
  const {cx, cy, lt: T, t} = s;
  const X = C(cx), Y = C(cy) - 1, a = T - BEAT_V;
  const V: P[] = [[X - 24, Y + 2], [X - 15, Y + 2], [X - 13, Y], [X - 11, Y + 2], [X - 9, Y + 2], [X - 8, Y + 4], [X - 6, Y - 9], [X - 4, Y + 7], [X - 2, Y + 2], [X + 1, Y + 2], [X + 7, Y + 8], [X + 21, Y - 6]];
  const K = 9; // the check starts at V[9]
  const pt = path(V), head = pt.len * eio(seg(T, 0.05, BEAT_V - 0.05));
  const ck = pt.L[K];
  const ref = T > 1.2 ? ((t - 1.2) % 2.8) / 1.6 : -1;
  for (let q = 0; q <= Math.min(head, pt.len); q += 0.3) {
    const [x, y] = pt.at(q);
    if (q < ck) {
      const w = ref >= 0 && ref <= 1 ? Math.exp(-(((q / ck - ref) * 9) ** 2)) : 0;
      g.on(x, y, 0.5 + 0.4 * w);
    } else {
      const b = 0.95 + 0.05 * hit(a, 0.3);
      g.on(x, y, b), g.on(x + 1, y, b);
    }
  }
  // the pen: a bright head with a short tail; at the end it becomes the coral tip
  const done = T >= BEAT_V;
  for (let k = 0; k < 7; k++) {
    const [x, y] = pt.at(head - k * 0.9);
    g.fr(x + 0.5, y, done ? 0 : k === 0 ? 1 : 0.7 * (1 - k / 7));
  }
  const [tx, ty] = pt.at(pt.len);
  g.on(tx + 1, ty, done ? 1 : 0, 1);
  ripple(g, tx + 1, ty, 1, 9, a, 0.5, 28, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: tx, y: ty, r: 12, a: 0.25 * hit(a, 0.3)}, {x: pt.at(head)[0], y: pt.at(head)[1], r: 5, a: done ? 0 : 0.12}]};
};
const vThu = (g: G, s: SC): Res => {
  // twenty bars, one a minute, each a level higher: the meter tops out
  const {cx, cy, lt: T, t} = s;
  const yb = Math.floor(cy) + 9, a = T - BEAT_V;
  for (let i = 0; i < 20; i++) {
    const x = Math.floor(cx) - 19 + i * 2, h = 3 + i;
    const st = 0.1 + i * 0.027, k = sp(T - st), top = h * Math.min(1.08, k);
    const wave = T > BEAT_V ? 0.25 * hit(a - i * 0.02, 0.12) : 0;
    const sh = T > 1.3 ? 0.14 * sheen(i * 2 - 19, 0, t - 1.3, 3.6, 22, 3) : 0;
    for (let j = 0; j < Math.min(h, Math.floor(top + 0.2)); j++) g.on(x, yb - j, 0.72 + wave + sh);
    g.fr(x + 0.5, yb + 0.5 - top + (top > 0 ? 0 : 0), k > 0.02 ? (i === 19 && T >= BEAT_V ? 1 : 0.95) : 0, i === 19 && T >= BEAT_V ? 1 : 0);
  }
  g.line(Math.floor(cx) - 20, yb + 2, Math.floor(cx) + 20, yb + 2, 0.22);
  return {o: {stagger: 0.25}, glow: [{x: cx + 19, y: yb - 20, r: 10, a: 0.22 * hit(a, 0.3)}]};
};
const vFri = (g: G, s: SC): Res => {
  // a tick written upward at speed: the long stroke shoots up-right, an arrowhead at its tip, speed lines behind
  const {cx, cy, lt: T, t} = s;
  const X = C(cx), Y = C(cy) - 1, a = T - BEAT_V;
  const V: P[] = [[X - 13, Y + 1], [X - 6, Y + 8], [X + 13, Y - 11]];
  const pt = path(V), k1 = pt.L[1];
  const u = seg(T, 0.3, BEAT_V - 0.3);
  // slow into the corner, then accelerate up the long stroke
  const pen = u < 0.35 ? k1 * ez(u / 0.35) : k1 + (pt.len - k1) * ((u - 0.35) / 0.65) ** 1.6;
  const sh = T > 1.3 ? (q: number) => 0.14 * gb((q / pt.len - ((t - 1.3) % 3.4) / 1.4) * 6) : () => 0;
  for (let q = 0; q <= Math.min(pen, pt.len); q += 0.3) {
    const [x, y] = pt.at(q), b = 0.95 + 0.05 * hit(a, 0.3) + sh(q);
    g.on(x, y, b), g.on(x + 1, y, b), g.on(x, y + 1, b);
  }
  const [hx, hy] = pt.at(pen), [ux, uy] = pt.dir(pen);
  const done = T >= BEAT_V;
  // the arrowhead rides the tip (free dots) and snaps open on the beat
  const op = done ? 1 + 0.25 * hit(a, 0.12) : pen > k1 ? 1 : 0;
  const wing = (bk: number, sd: number): P => [hx - ux * bk * op - uy * sd * bk * op, hy - uy * bk * op + ux * sd * bk * op];
  [wing(1, 1), wing(2, 1), wing(3, 1), wing(1, -1), wing(2, -1), wing(3, -1)].forEach(([x, y]) => g.fr(x + 0.5, y + 0.5, pen > k1 ? 1 : 0));
  g.fr(hx + 0.5, hy + 0.5, pen > 0.2 ? 1 : 0, done ? 1 : 0);
  // speed lines: parallel streaks below the long stroke, trailing the tip, gone after the beat
  for (let l = 0; l < 4; l++) {
    const off = 3 + l * 2.2, lag = 3 + l * 2.5 + (l % 2) * 2, live = pen > k1 + 2 ? cl(1 - Math.max(0, a) / 0.35) : 0;
    for (let i = 0; i < 5; i++) {
      const q = pen - lag - i * 1.1, [x, y] = pt.at(Math.max(k1, q));
      g.fr(x + uy * off + 0.5, y - ux * off + 0.5, q > k1 ? live * 0.55 * (1 - i / 5) : 0);
    }
  }
  ripple(g, hx + 0.5, hy + 0.5, 1, 9, a, 0.5, 28, 0.55);
  return {o: {stagger: 0.25}, glow: [{x: hx, y: hy, r: 12, a: 0.25 * hit(a, 0.3)}], flash: 0.06 * hit(a, 0.1)};
};
const vSat = (g: G, s: SC): Res => {
  // the stopwatch runs its lap and stops on twenty
  const {cx, cy, lt: T} = s;
  const X = C(cx), Y = C(cy) + 1, a = T - BEAT_V;
  g.ring(X, Y, 13.5, 0.8);
  for (let i = 0; i < 20; i++) {
    const q = (i / 20) * TAU, big = i % 5 === 0, fl = 0.55 * hit(a - (i / 20) * 0.15, 0.2);
    g.on(X + Math.sin(q) * 10.8, Y - Math.cos(q) * 10.8, (big ? 0.6 : 0.3) + fl);
    if (big) g.on(X + Math.sin(q) * 9.8, Y - Math.cos(q) * 9.8, 0.6 + fl);
  }
  g.on(X + Math.sin(0.8) * 15.2, Y - Math.cos(0.8) * 15.2, 0.6), g.on(X + Math.sin(0.8) * 16.2, Y - Math.cos(0.8) * 16.2, 0.6);
  g.on(X, Y - 14.5, 0.8), g.on(X, Y - 15.5, 0.8);
  const press = a > 0 && a < 0.16 ? 1 : 0;
  for (let i = -2; i <= 2; i++) for (const r of [0, 1]) g.fr(X + i, Y - 17.5 + r + press, 0.9);
  const th = TAU * eio(seg(T, 0.1, BEAT_V - 0.12));
  for (let k = 0; k <= 9; k++) g.fr(X + Math.sin(th) * k, Y - Math.cos(th) * k, k === 9 ? 1 : 0.92, k === 9 ? 1 : 0);
  if (T > BEAT_V) led(g, '20', '20', X, Y + 3, 1, cl((T - BEAT_V) / 0.15), 0, 1);
  ripple(g, X, Y, 14, 21, a, 0.5, 60, 0.45);
  return {o: {stagger: 0.25}, glow: [{x: X, y: Y - 16, r: 9, a: 0.25 * hit(a, 0.25)}]};
};
const vSun = (g: G, s: SC): Res => {
  // today's page on the calendar: the old one is torn off, today gets its check
  const {cx, cy, lt: T, t} = s;
  const x0 = Math.floor(cx) - 11, y0 = Math.floor(cy) - 10, W = 23, H = 21, a = T - BEAT_V;
  for (let j = 0; j < 5; j++) for (let i = 0; i < W; i++) if (!((i === 0 || i === W - 1) && j === 0)) g.on(x0 + i, y0 + j, 0.8 + (T > 1.2 ? 0.15 * sheen(i - 11, j, t - 1.2, 3.6, 16, 3) : 0));
  for (let j = 5; j < H; j++) for (const i of [0, W - 1]) g.on(x0 + i, y0 + j, 0.5);
  for (let i = 1; i < W - 1; i++) g.on(x0 + i, y0 + H - 1, 0.5);
  for (const rx of [x0 + 5, x0 + 17]) for (let j = -2; j <= 1; j++) g.on(rx, y0 + j, j < 0 ? 0.95 : 0.15);
  // yesterday's page lifts away
  const u = seg(T, 0.3, 0.32);
  for (let j = 6; j < H - 1; j += 2)
    for (let i = 3; i < W - 3; i += 2) {
      const dx = i - 11, dy = j - 5;
      g.fr(x0 + i + 0.5 + dx * u * 0.4 + u * 6, y0 + 5.5 + dy * (1 - u * 1.3) - u * 9, u >= 1 ? 0 : (u > 0 ? 0.3 * (1 - u) : 0.22));
    }
  const V: P[] = [[x0 + 5.5, y0 + 12.5], [x0 + 9.5, y0 + 16.5], [x0 + 17.5, y0 + 8.5]];
  const pen = path(V).len * ez(seg(T, 0.5, BEAT_V - 0.5));
  if (T > 0.5) stroke(g, V, pen, 0.95 + 0.05 * hit(a), 2);
  g.on(x0 + 17.5, y0 + 8.5, T >= BEAT_V ? 1 : 0, 1);
  ripple(g, cx, y0 + 10, 12, 20, a, 0.55, 56, 0.45);
  return {o: {stagger: 0.25}, glow: [{x: x0 + 12, y: y0 + 13, r: 14, a: 0.2 * hit(a, 0.3)}], flash: 0.05 * hit(a, 0.1)};
};
const VERIFIED = [vMon, vTue, vWed, vThu, vFri, vSat, vSun];

// ============================== 2. TODAY ==============================
// The session time counts up 0.3 to 2.1 s (light ticks), lands with a heavy beat at 2.12 s.
const SES = 52 + 14 / 60;
const HR: number[] = (() => {
  const out: number[] = [];
  for (let i = 0; i < 40; i++) {
    const m = (i / 39) * SES;
    let v: number;
    if (m < 7) v = 96 + (m / 7) * 34;
    else if (m > 46) v = 132 - ((m - 46) / 6.2) * 28;
    else {
      const c = (m - 7) % 5.2;
      const peak = 150 + [4, 8, 12, 18, 14, 10, 6, 4][Math.floor((m - 7) / 5.2) % 8];
      v = c < 1.7 ? 124 + (peak - 124) * Math.sin((c / 1.7) * Math.PI * 0.5) : peak - (peak - 122) * (1 - Math.pow(1 - cl((c - 1.7) / 2.2), 3));
    }
    out.push(v + (hash(i, 5) - 0.5) * 6);
  }
  return out;
})();
const today = (g: G, s: SC): Res => {
  const {cx, cy, lt: T, t} = s;
  const m = eo5(seg(T, 0.3, 1.8)) * SES, a = T - 2.12;
  const sec = Math.floor(m * 60), str = `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(sec % 60).padStart(2, '0')}`;
  led(g, str, '00:00', cx, Math.floor(cy) - 13, 2, 0.95 + 0.05 * hit(a, 0.3), 0.045, 1);
  // the session as heart rate: a bar every two minutes, rising as the clock passes it
  const yb = Math.floor(cy) + 13, nb = 26;
  const hv = (i: number) => {
    const f = ((i * 2 + 1) / SES) * 39, k = Math.min(38, Math.floor(f));
    return lerp(HR[k], HR[k + 1], f - k);
  };
  let pk = 0;
  for (let i = 1; i < nb; i++) if (hv(i) > hv(pk)) pk = i;
  for (let i = 0; i < nb; i++) {
    const x = Math.floor(cx) - 25 + i * 2, h = 2 + Math.round(((hv(i) - 92) / 72) * 10);
    const mi = Math.min(0.999, (i * 2 + 1) / SES), st = 0.3 + 1.8 * (1 - Math.pow(1 - mi, 1 / 5));
    const k = sp(T - st), top = h * Math.min(1.08, k);
    const sh = T > 2.6 ? 0.18 * sheen(i * 2 - 25, 0, t - 2.6, 3.8, 28, 3) : 0;
    for (let j = 0; j < Math.min(h - 1, Math.floor(top)); j++) g.on(x, yb - j, 0.55 + sh);
    const isPk = i === pk && T >= 2.12;
    g.fr(x + 0.5, yb + 1.5 - top, k > 0.02 ? 0.95 : 0, isPk ? 1 : 0);
  }
  const px = Math.floor(cx) - 25 + pk * 2 + 0.5, py = yb + 1.5 - (2 + Math.round(((hv(pk) - 92) / 72) * 10));
  ripple(g, px, py, 1, 7, a, 0.45, 24, 0.55);
  return {o: {stagger: 0.25}, glow: [{x: cx, y: cy - 6, r: 24, a: 0.12 * hit(a, 0.35)}, {x: px, y: py, r: 6, a: 0.2 * hit(a, 0.4)}]};
};

// ============================== 3. WEEK ==============================
// Light ticks 0.2 to 1.46 s as the days go in, today lands at 1.9 s, its coral cap at 2.15 s.
const EARLIER: Record<string, number[]> = {first: [], middle: [48, 54], last: [52, 48, 54, 61]};
const week = (g: G, s: SC): Res => {
  const {cx, cy, lt: T, t, day, pos, PW} = s;
  const yb = Math.floor(cy) + 7, ago = Math.max(0, PW.done - 1);
  const earlier = EARLIER[pos] ?? [];
  const first = day - ago;
  const done = (i: number) => i >= first && i < day;
  const ghosts: number[] = [];
  for (let i = day + 1; i < 7 && ghosts.length < 5 - PW.done; i++) ghosts.push(i);
  const a1 = T - 1.9, a2 = T - 2.15;
  let k = 0;
  for (let i = 0; i < 7; i++) {
    const xc = Math.floor(cx) + (i - 3) * 7, x0 = xc - 1;
    const isT = i === day, isD = done(i);
    const st = isT ? 1.76 : 0.2 + k * 0.18;
    const mins = isT ? 52 : isD ? earlier[Math.max(0, earlier.length - (day - i))] ?? 50 : 0;
    if (isD) k++;
    const h = Math.round(mins / 3);
    txt3(g, 'MTWTFSS'[i], xc + 0.5, yb + 3, isT ? 0.95 : isD ? 0.6 : 0.3);
    if (ghosts.includes(i)) for (let j = 0; j < 17; j += 2) for (let u = 0; u < 3; u++) g.on(x0 + u, yb - j, j === 0 || j === 16 || u !== 1 ? 0.13 : 0);
    if (!isT && !isD && !ghosts.includes(i)) g.on(xc, yb, 0.2);
    // the bar: free dots that stretch up from the base
    const q = sp(T - st);
    const wave = pos === 'last' && (isD || isT) ? 0.2 * hit(a2 - (i - first) * 0.06, 0.15) : 0;
    for (let j = 0; j < 20; j++)
      for (let u = 0; u < 3; u++) {
        const on = j < h && (isT || isD) && T > st;
        const cap = isT && j === h - 1 && u === 1 && T >= 2.15;
        const sh = T > 2.6 ? 0.14 * sheen(i * 7 - 21, -j, t - 2.6, 3.8, 26, 3) : 0;
        g.fr(x0 + u + 0.5, yb + 0.5 - j * q, on ? (isT ? 0.98 : 0.8) + wave + sh : 0, cap ? 1 : 0);
      }
  }
  const tx = Math.floor(cx) + (day - 3) * 7 + 0.5, ty = yb + 0.5 - Math.round(52 / 3) + 1;
  ripple(g, tx, ty, 1, 7, a2, 0.45, 24, 0.55);
  return {o: {stagger: 0.3}, glow: [{x: tx, y: yb - 8, r: 9, a: 0.16 * hit(a1, 0.3)}, {x: tx, y: ty, r: 6, a: 0.25 * hit(a2, 0.35)}]};
};

// ============================== 4. MONTH ==============================
// Light ticks 0.25 to 0.95 s as the weeks go in, heavy at 1.3 s: today lands.
const month = (g: G, s: SC): Res => {
  const {cx, cy, lt: T, cal, t} = s;
  if (!cal) return;
  const showT = !s.pick || s.picked;
  const X0 = Math.floor(cx) - 16, rowsN = Math.ceil((cal.lead + cal.cells.length) / 7);
  const Y0 = Math.floor(cy) - Math.round((rowsN * 4 - 1) / 2) + 2, a = T - 1.3;
  for (let i = 0; i < 7; i++) txt3(g, 'MTWTFSS'[i], X0 + i * 5 + 1.5, Y0 - 7, 0.3);
  let doneN = 0, fut = 0;
  const need = Math.max(0, cal.target - cal.sessions);
  const pa = s.pickAt != null ? s.t - s.pickAt : 1e3;
  cal.cells.forEach((c, i) => {
    const k = cal.lead + i, col = k % 7, row = Math.floor(k / 7);
    const x = X0 + col * 5, y = Y0 + row * 4;
    const app = T - (0.25 + row * 0.14 + col * 0.012), pop = hit(app, 0.14) * 0.25;
    if (app < 0) return;
    const sh = T > 2 ? 0.12 * sheen(col * 5 - 16, row * 4 - 10, t - 2, 4, 24, 3) : 0;
    if (c === 'done') {
      doneN++;
      for (let v = 0; v < 3; v++) for (let u = 0; u < 3; u++) g.on(x + u, y + v, 0.78 + pop + sh);
    } else if (c === 'today') {
      const land = T >= 1.3;
      for (let v = 0; v < 3; v++) for (let u = 0; u < 3; u++) g.on(x + u, y + v, land ? (u === 1 && v === 1 ? 1 : 0.98) : u === 1 && v === 1 ? 0 : 0.3, land && u === 1 && v === 1 ? 1 : 0);
    } else if (c === 'future' && showT && fut < need) {
      const ord = fut++, ap2 = Math.min(T - 1.35, pa) - ord * 0.035;
      if (ap2 > 0) for (let v = 0; v < 3; v++) for (let u = 0; u < 3; u++) if (u !== 1 || v !== 1) g.on(x + u, y + v, 0.26 + 0.4 * hit(ap2, 0.15));
    } else g.on(x + 1, y + 1, c === 'miss' ? 0.45 : 0.16);
  });
  void doneN;
  const ti = cal.cells.indexOf('today'), tk = cal.lead + Math.max(0, ti);
  const tx = X0 + (tk % 7) * 5 + 1.5, ty = Y0 + Math.floor(tk / 7) * 4 + 1.5;
  ripple(g, tx, ty, 2, 9, a, 0.5, 28, 0.55);
  return {o: {stagger: 0.35}, glow: [{x: tx, y: ty, r: 8, a: 0.25 * hit(a, 0.35)}]};
};

// ============================== 5. HOW FAR ==============================
// Beat at 0.7 s (heavy + success): today's mark lands. A light touch at 1.5 s: the way still to go.
const BEAT_F = 0.7;
const fMon = (g: G, s: SC, dd: number): Res => {
  // a dial of 66 days
  const {cx, cy, lt: T} = s;
  const X = C(cx), Y = C(cy) + 1, R = 15, a0 = -0.75 * Math.PI, a1 = 0.75 * Math.PI, a = T - BEAT_F;
  const n = dd * eio(seg(T, 0.12, BEAT_F - 0.12)), rest = seg(T, 1.5, 0.6);
  for (let i = 0; i < 66; i++) {
    const th = lerp(a0, a1, i / 65), lit = i < n;
    const w = !lit && rest > 0 && rest < 1 ? 0.35 * gb(((i - dd) / 21 - rest) * 7) : 0;
    g.on(X + Math.sin(th) * R, Y - Math.cos(th) * R, lit ? 0.9 : 0.15 + w);
    if (i % 7 === 0) g.on(X + Math.sin(th) * (R - 2.4), Y - Math.cos(th) * (R - 2.4), lit ? 0.6 : 0.25);
  }
  const th = lerp(a0, a1, Math.max(0, n - 1) / 65);
  for (let k = 0; k < 3; k++) g.fr(X + Math.sin(th) * (R + k - 1), Y - Math.cos(th) * (R + k - 1), n > 0.5 ? 1 : 0, k === 1 ? 1 : 0);
  led(g, String(Math.round(n)), String(dd), X, Y - 7, 2, 1, 0, 2);
  txt3(g, '66', X, Y + 11, 0.35);
  const hx = X + Math.sin(th) * R, hy = Y - Math.cos(th) * R;
  ripple(g, hx, hy, 1, 7, a, 0.45, 24, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: hx, y: hy, r: 7, a: 0.3 * hit(a, 0.35)}]};
};
const fTue = (g: G, s: SC, dd: number): Res => {
  // 66 tiles, one a day
  const {cx, cy, lt: T} = s;
  const X0 = Math.floor(cx) - 15, Y0 = Math.floor(cy) - 9, a = T - BEAT_F, rest = seg(T, 1.5, 0.6);
  let tx = 0, ty = 0;
  for (let i = 0; i < 66; i++) {
    const x = X0 + (i % 11) * 3, y = Y0 + Math.floor(i / 11) * 3;
    const st = 0.12 + (i / Math.max(1, dd - 1)) * (BEAT_F - 0.12), lit = i < dd && T >= st, me = i === dd - 1;
    if (me) (tx = x + 1), (ty = y + 1);
    const w = i >= dd && rest > 0 && rest < 1 ? 0.3 * gb(((i - dd) / (66 - dd) - rest) * 6) : 0;
    const b = lit ? 0.82 + 0.18 * hit(T - st, 0.12) : 0.12 + w;
    for (let v = 0; v < 2; v++) for (let u = 0; u < 2; u++) g.on(x + u, y + v, me && lit ? 1 : b, me && lit ? 1 : 0);
  }
  ripple(g, tx, ty, 1.5, 8, a, 0.45, 28, 0.55);
  return {o: {stagger: 0.25}, glow: [{x: tx, y: ty, r: 7, a: 0.3 * hit(a, 0.35)}]};
};
const fWed = (g: G, s: SC, dd: number): Res => {
  // the signal, stronger every week
  const {cx, cy, lt: T} = s;
  const X0 = Math.floor(cx) - 24, Y = C(cy) - 1, a = T - BEAT_F, rest = seg(T, 1.5, 0.6);
  const yAt = (d: number) => Y - (1.2 + 6.5 * Math.pow(d / 66, 1.1)) * Math.sin((TAU * d) / 13.2);
  const n = dd * eio(seg(T, 0.12, BEAT_F - 0.12));
  let px = X0 + 0.5, py = Y;
  for (let x = 0; x < 48; x++) {
    const d0 = (x / 48) * 66, d1 = ((x + 1) / 48) * 66;
    if (d0 < n) {
      const e = Math.min(d1, n), xe = X0 + 0.5 + (e / 66) * 48;
      g.line(X0 + x, yAt(d0) - 0.5, xe - 0.5, yAt(e) - 0.5, 0.88);
      (px = xe), (py = yAt(e));
    } else if (x % 2 === 0) {
      const w = rest > 0 && rest < 1 ? 0.3 * gb(((d0 - dd) / (66 - dd) - rest) * 6) : 0;
      g.on(X0 + x, Y, 0.16 + w);
    }
  }
  g.fr(px, py, n > 0.3 ? 1 : 0, 1);
  ripple(g, px, py, 1, 7, a, 0.45, 24, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: px, y: py, r: 7, a: 0.3 * hit(a, 0.35) + 0.06}]};
};
const WEEKMIN = [38, 70, 96, 88, 120, 141];
const CURMIN: Record<string, number> = {first: 52, middle: 154, last: 267};
const fThu = (g: G, s: SC): Res => {
  // minutes a week, week 1 to this one: the bars climb
  const {cx, cy, lt: T, pos} = s;
  const X0 = Math.floor(cx) - 23, yb = Math.floor(cy) + 9, a = T - BEAT_F;
  const W = [...WEEKMIN, CURMIN[pos] ?? 154], top = Math.max(160, ...W);
  const hs = W.map((m) => Math.max(2, Math.round((20 * m) / top)));
  for (let i = 0; i < 10; i++) {
    const x0 = X0 + i * 5, cur = i === 6;
    if (i > 6) {
      const ap = T - 1.5 - (i - 7) * 0.08;
      if (ap > 0) for (let j = 0; j < hs[6]; j += 2) for (let u = 0; u < 3; u++) g.on(x0 + u, yb - j, u === 1 && j > 0 && j < hs[6] - 1 ? 0 : 0.14 + 0.25 * hit(ap, 0.15));
      continue;
    }
    const st = cur ? 0.56 : 0.12 + i * 0.07, k = sp(T - st), h = hs[i] * Math.min(1.06, k);
    for (let j = 0; j < Math.floor(h - 0.5); j++) for (let u = 0; u < 3; u++) g.on(x0 + u, yb - j, cur ? 0.95 : 0.72);
    for (let u = 0; u < 3; u++) g.fr(x0 + u + 0.5, yb + 0.5 - Math.max(0, h - 1), k > 0.02 ? 1 : 0, cur && u === 1 && T >= BEAT_F ? 1 : 0);
  }
  txt3(g, '1', X0 + 1.5, yb + 3, 0.35);
  txt3(g, '7', X0 + 31.5, yb + 3, 0.8);
  const tx = X0 + 31.5, ty = yb + 0.5 - hs[6] + 1;
  ripple(g, tx, ty, 1, 7, a, 0.45, 24, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: tx, y: ty, r: 7, a: 0.3 * hit(a, 0.35)}]};
};
const fFri = (g: G, s: SC, dd: number): Res => {
  // up and to the right: the arrow is two thirds of the way to the line
  const {cx, cy, lt: T} = s;
  const X0 = Math.floor(cx) - 22, yb = Math.floor(cy) + 9, a = T - BEAT_F, rest = seg(T, 1.5, 0.5);
  const xAt = (d: number) => X0 + 0.5 + (d / 66) * 42;
  const yAt = (d: number) => yb + 0.5 - (20 * (1 - Math.exp(-d / 22))) / (1 - Math.exp(-3));
  const n = dd * eio(seg(T, 0.12, BEAT_F - 0.12));
  for (let d = 0; d <= 66; d += 0.4) {
    if (d <= n) g.on(xAt(d), yAt(d), 0.9);
    else if (Math.round(d / 0.4) % 4 === 0) {
      const w = rest > 0 && rest < 1 ? 0.35 * gb(((d - dd) / (66 - dd) - rest) * 6) : 0;
      g.on(xAt(d), yAt(d), 0.18 + w);
    }
  }
  for (let y = yb; y >= yb - 22; y -= 2) g.on(xAt(66) + 1, y, 0.25);
  txt3(g, '66', xAt(66) + 1, yb - 28, 0.4);
  const hx = xAt(n), hy = yAt(n), dx = xAt(n + 0.5) - hx, dy = yAt(n + 0.5) - hy, dl = Math.hypot(dx, dy) || 1;
  const ux = dx / dl, uy = dy / dl;
  const wing = (b: number, s2: number): P => [hx - ux * b - uy * s2, hy - uy * b + ux * s2];
  const pts: P[] = [[hx, hy], wing(1, 1), wing(2, 2), wing(1, -1), wing(2, -2), wing(3, 3), wing(3, -3)];
  pts.forEach(([x, y], k) => g.fr(x, y, n > 0.5 ? 1 : 0, k === 0 ? 1 : 0));
  ripple(g, hx, hy, 1, 7, a, 0.45, 24, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: hx, y: hy, r: 7, a: 0.3 * hit(a, 0.35)}]};
};
const fSat = (g: G, s: SC, dd: number): Res => {
  // a lap of the track: day 45 is two thirds round
  const {cx, cy, lt: T} = s;
  const X = C(cx), Y = C(cy) - 1, L = 9, a = T - BEAT_F, rest = seg(T, 1.5, 0.6);
  const tot = 4 * L + TAU * 10;
  const at = (s2: number, r: number): P => {
    let q = ((s2 % tot) + tot) % tot;
    const k = r / 10;
    if (q < L) return [X + q, Y + r];
    q -= L;
    if (q < Math.PI * 10) return [X + L + Math.sin(q / 10) * r, Y + Math.cos(q / 10) * r];
    q -= Math.PI * 10;
    if (q < 2 * L) return [X + L - q, Y - r];
    q -= 2 * L;
    if (q < Math.PI * 10) return [X - L - Math.sin(q / 10) * r, Y - Math.cos(q / 10) * r];
    q -= Math.PI * 10;
    return [X - L + q * k, Y + r];
  };
  for (let q = 0; q < tot; q += 0.6) {
    g.on(...at(q, 7.5), 0.22);
    g.on(...at(q, 12.5), 0.22);
  }
  const n = (dd / 66) * tot * eio(seg(T, 0.12, BEAT_F - 0.12));
  for (let q = 0; q < tot; q += 0.5) {
    if (q <= n) g.on(...at(q, 10), 0.9);
    else if (Math.round(q / 0.5) % 4 === 0) {
      const w = rest > 0 && rest < 1 ? 0.35 * gb(((q - n) / (tot - n) - rest) * 6) : 0;
      g.on(...at(q, 10), 0.16 + w);
    }
  }
  for (let r = 7; r <= 13; r++) g.on(X - 0.5, Y + r, 0.6);
  for (let k = 0; k < 6; k++) {
    const [x, y] = at(n - k * 0.9, 10);
    g.fr(x, y, n > 0.5 ? (k === 0 ? 1 : 0.6 * (1 - k / 6)) : 0, k === 0 ? 1 : 0);
  }
  const [hx, hy] = at(n, 10);
  ripple(g, hx, hy, 1, 7, a, 0.45, 24, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: hx, y: hy, r: 7, a: 0.3 * hit(a, 0.35)}]};
};
const fSun = (g: G, s: SC, dd: number): Res => {
  // the 66-day ruler, a mark every week, the number on top
  const {cx, cy, lt: T} = s;
  const X0 = Math.floor(cx) - 24, y = Math.floor(cy) + 5, a = T - BEAT_F, rest = seg(T, 1.5, 0.6);
  const n = dd * eio(seg(T, 0.12, BEAT_F - 0.12)), xAt = (d: number) => X0 + (d / 66) * 49;
  for (let i = 0; i < 49; i++) {
    const d = (i / 49) * 66, lit = d < n;
    const w = !lit && rest > 0 && rest < 1 ? 0.3 * gb(((d - dd) / (66 - dd) - rest) * 6) : 0;
    g.on(X0 + i, y, lit ? 0.9 : 0.16 + w), g.on(X0 + i, y + 1, lit ? 0.9 : 0.16 + w);
  }
  for (let w = 0; w <= 9; w++) g.on(xAt(w * 7), y + 3, w * 7 < n ? 0.55 : 0.25);
  txt3(g, '1', X0 + 1.5, y + 5, 0.35);
  txt3(g, '66', X0 + 45.5, y + 5, 0.35);
  const mx = xAt(n);
  for (let k = 0; k < 6; k++) g.fr(Math.floor(mx) + 0.5, y - 4.5 + k, n > 0.5 ? 1 : 0, k === 0 ? 1 : 0);
  led(g, String(Math.round(n)), String(dd), C(cx), y - 22, 2, 1, 0, 2);
  ripple(g, Math.floor(mx) + 0.5, y - 4.5, 1, 7, a, 0.45, 24, 0.6);
  return {o: {stagger: 0.25}, glow: [{x: mx, y: y - 4, r: 7, a: 0.3 * hit(a, 0.35)}]};
};

// ============================== 6. THE FINISH ==============================
type Fin = (g: G, s: SC, age: (k: number) => number) => Res;
const lastAge = (s: SC) => (s.tapAt != null ? s.t - s.tapAt : -1);

// ---- Mon: SUNRISE. Each tap lifts the sun and fans out more rays; the last clears the horizon ----
const sunGeo = (cx: number, cy: number, N: number) => {
  const yh = Math.floor(cy) + 6, R = 8;
  const disc: P[] = [];
  for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) if (dx * dx + dy * dy <= R * R + 1) disc.push([dx, dy]);
  const rays = Array.from({length: 2 * N - 1}, (_, j) => ({th: ((j - (N - 1)) * (Math.PI / 2)) / N, q: Math.abs(j - (N - 1)), L: Math.abs(j - (N - 1)) % 2 ? 3 : 4}));
  return {yh, R, disc, rays, y0: yh + 0.5 + R - 2, y1: yh + 0.5 - R - 3};
};
const finMon: Fin = (g, s, age) => {
  const {cx, cy, N, t, sealT, since} = s;
  const {yh, R, disc, rays, y0, y1} = sunGeo(cx, cy, N);
  let lv = 0;
  for (let k = 0; k < N; k++) lv += sp(age(k)) / N;
  const yc = lerp(y0, y1, lv), sealed = sealT != null;
  for (let x = Math.floor(cx) - 21; x <= Math.floor(cx) + 21; x++) g.on(x, yh, 0.7 - (Math.abs(x + 0.5 - cx) / 21) * 0.45 + 0.2 * hit(since, 0.3));
  const la = lastAge(s), pls = sealed ? 0 : 0.1 * hit(la, 0.2);
  for (const [dx, dy] of disc) {
    const y = yc + dy;
    g.fr(C(cx) + dx, y, y < yh ? 0.88 + pls + 0.12 * hit(since, 0.3) : 0, dx === 0 && dy === -R ? 1 : 0);
  }
  rays.forEach((r) => {
    const a = age(r.q), len = r.L * sp(a) + (sealed ? 1.6 * hit(since - 0.05, 0.25) : 0);
    const shim = sealed && since > 0.8 ? 0.15 * Math.cos(r.th * 2 - (t - sealT!) * 2.2) : 0;
    for (let i = 0; i < 4; i++) {
      const rr = R + 2 + Math.min(i, Math.max(0, len - 1));
      const x = cx + Math.sin(r.th) * rr, y = yc - Math.cos(r.th) * rr;
      g.fr(x, y, a >= 0 && i < len && y < yh ? 0.85 + shim : 0);
    }
  });
  ripple(g, cx, yc, R + 2, R + 15, since, 0.7, 72, 0.45);
  return {glow: [{x: cx, y: yc, r: R + 6, a: 0.14 * hit(la, 0.25)}, {x: cx, y: yc, r: 24, a: 0.3 * hit(since, 0.5)}], flash: 0.1 * hit(since, 0.15)};
};

// ---- Tue: THE WALL. Bricks drop into place; the keystone is pressed in last; the wall is framed ----
const wallSlots = (N: number, cx: number, cy: number) => {
  const X0 = Math.floor(cx) - 19, nc = N >= 7 ? 3 : 2, Hw = nc * 7 - 1, top = Math.floor(cy) - Math.floor(Hw / 2) - 1;
  const ry = (c: number) => top + (nc - 1 - c) * 7;
  const full = (c: number) => [[X0, ry(c), 19], [X0 + 20, ry(c), 19]];
  const mid = (c: number) => [[X0, ry(c), 9], [X0 + 10, ry(c), 19], [X0 + 30, ry(c), 9]];
  const [a, b] = full(0), [h1, f, h2] = mid(1);
  const S = nc === 2 ? [a, b, h1, h2, f] : [a, b, h1, h2, ...full(2), f];
  return {S, X0, top, Hw};
};
const finTue: Fin = (g, s, age) => {
  const {cx, cy, N, t, sealT, since, taps} = s;
  const {S, X0, top, Hw} = wallSlots(N, cx, cy);
  const sealed = sealT != null;
  S.forEach(([x, y, w], k) => {
    if (k < taps) return;
    g.rect(x, y, w, 6, 0.13);
    if (k === N - 1) for (let v = 2; v < 4; v++) for (let u = 0; u < 2; u++) g.on(x + (w >> 1) + u - 1 + 0.5, y + v, 0.5, 1);
  });
  S.forEach(([x, y, w], k) => {
    const a = age(k), key = k === N - 1;
    let dy = 0, sc = 1, b = 0;
    if (a >= 0) {
      if (key) {
        sc = 1 + 0.7 * (1 - seg(a, 0, 0.13)) ** 2 - 0.04 * Math.sin(Math.PI * seg(a, 0.13, 0.14));
        b = cl(a / 0.05);
      } else {
        dy = a < 0.13 ? -7 * (1 - (a / 0.13) ** 2) : -0.8 * Math.sin(Math.PI * seg(a, 0.13, 0.16));
        b = cl(a / 0.06);
      }
    } else dy = -7;
    const mx = x + w / 2, my = y + 3;
    for (let v = 0; v < 6; v++)
      for (let u = 0; u < w; u++) {
        const edge = u === 0 || v === 0 || u === w - 1 || v === 5;
        const coral = key && v >= 2 && v < 4 && (u === (w >> 1) - 1 || u === w >> 1);
        const sh = sealed && since > 0.9 ? 0.15 * sheen(x + u - cx, y + v - cy, t - sealT! - 0.9, 3.6, 26, 3) : 0;
        const bb = (edge ? 0.95 : 0.6) + 0.15 * hit(a - 0.13, 0.15) + sh;
        g.fr(mx + (u + 0.5 - w / 2) * sc, my + (v + 0.5 - 3) * sc + dy, b * bb, coral ? 1 : 0);
      }
  });
  // the lock: an outline drawn round the finished wall, from the keystone both ways
  if (sealed) {
    const x0 = X0 - 2, y0 = top - 2, x1 = X0 + 40, y1 = top + Hw + 1;
    const per: P[] = [];
    for (let x = x0; x <= x1; x++) per.push([x, y0]);
    for (let y = y0 + 1; y <= y1; y++) per.push([x1, y]);
    for (let x = x1 - 1; x >= x0; x--) per.push([x, y1]);
    for (let y = y1 - 1; y > y0; y--) per.push([x0, y]);
    const n = per.length, c0 = Math.round((x1 - x0) / 2), p = ez(seg(since, 0.12, 0.42)) * (n / 2 + 1);
    per.forEach(([x, y], i) => {
      const d = Math.min((i - c0 + n) % n, (c0 - i + n) % n);
      if (d <= p) g.on(x, y, 0.85);
    });
  }
  const ks = S[N - 1];
  return {glow: [{x: cx, y: top + Hw / 2, r: 26, a: 0.28 * hit(since - 0.13, 0.45)}, {x: ks[0] + ks[2] / 2, y: ks[1] + 3, r: 9, a: sealed ? 0 : 0.18 * hit(age(taps - 1) - 0.13, 0.2)}], flash: 0.08 * hit(since - 0.13, 0.15)};
};

// ---- Wed: BATTERY. Each tap charges a cell; full, the cells join and a bolt strikes through ----
const BOLT = ['.....####', '....####.', '...####..', '..####...', '.########', '########.', '...####..', '..####...', '.####....', '.##......', '#........'];
const finWed: Fin = (g, s, age) => {
  const {cx, cy, N, t, sealT, since, taps} = s;
  const cw = N >= 7 ? 4 : 5, inner = N * cw + N - 1, W = inner + 4, H = 17;
  const x0 = Math.round(cx - (W + 2) / 2), y0 = Math.floor(cy) - 9, sealed = sealT != null;
  for (let i = 0; i < W; i++)
    for (let j = 0; j < H; j++) {
      const edge = i === 0 || j === 0 || i === W - 1 || j === H - 1, corner = (i === 0 || i === W - 1) && (j === 0 || j === H - 1);
      if (edge && !corner) g.on(x0 + i, y0 + j, 0.85 + 0.15 * hit(since - 0.3, 0.3));
    }
  for (let i = 0; i < 2; i++) for (let j = 0; j < 7; j++) g.on(x0 + W + i, y0 + 5 + j, 0.85);
  // the bolt, cut out of the full battery top to bottom
  const bx = Math.round(x0 + W / 2 - 4.5), by = y0 + 3;
  const strike = sealed ? seg(since, 0.3, 0.12) * BOLT.length : -1;
  const cut = new Set<number>();
  BOLT.forEach((row, j) => [...row].forEach((c, i) => c === '#' && j < strike && cut.add((by + j) * 256 + bx + i)));
  const bolt = (x: number, y: number) => cut.has(Math.floor(y) * 256 + Math.floor(x));
  const shim = (x: number) => (sealed && since > 1 ? 0.12 * sheen(x - cx, 0, t - sealT! - 1, 2.6, 24, 3) : 0);
  for (let k = 0; k < N; k++) {
    const sx = x0 + 2 + k * (cw + 1), a = age(k), f = a >= 0 ? ez(a / 0.14) : 0;
    if (k >= taps) g.rect(sx, y0 + 2, cw, 13, 0.12);
    for (let u = 0; u < cw; u++)
      for (let v = 0; v < 13; v++) {
        const vis = a >= 0 && u < f * cw + 0.05, x = vis ? sx + u + 0.5 : sx + 0.5, y = y0 + 2.5 + v;
        const front = !sealed && k === taps - 1 && u === cw - 1 && v === 6 && f > 0.98;
        g.fr(x, y, vis && !bolt(x, y) ? 0.88 + 0.12 * hit(a, 0.2) + shim(x) : 0, front ? 1 : 0);
      }
  }
  // the gaps between cells fill once it is full
  for (let k = 0; k < N - 1; k++) {
    const gx = x0 + 2 + k * (cw + 1) + cw + 0.5;
    for (let v = 0; v < 13; v++) {
      const y = y0 + 2.5 + v, vis = sealed && since > 0.16 + Math.abs(v - 6) * 0.012;
      g.fr(gx, vis ? y : y0 + 8.5, vis && !bolt(gx, y) ? 0.9 + shim(gx) : 0);
    }
  }
  g.on(bx + 4, by + 5, sealed && since > 0.42 ? 1 : 0, 1);
  return {glow: [{x: x0 + W / 2, y: y0 + 8.5, r: 22, a: 0.3 * hit(since - 0.3, 0.45)}, {x: x0 + 2 + (taps - 0.5) * (cw + 1), y: y0 + 8.5, r: 6, a: sealed ? 0 : 0.16 * hit(lastAge(s), 0.2)}], flash: 0.08 * hit(since - 0.3, 0.15)};
};

// ---- Thu: BARBELL. Each tap slides a plate onto both ends; the last one and the bar goes up ----
const finThu: Fin = (g, s, age) => {
  const {cx, cy, N, sealT, since, taps} = s;
  const PL = N >= 7 ? [15, 15, 15, 15, 13, 13, 11] : [15, 15, 15, 13, 11];
  const yr = Math.floor(cy) + 4.5, hl = Math.min(25, 9 + 2 * N + 3), floorY = Math.floor(cy) + 12, sealed = sealT != null;
  g.line(Math.floor(cx) - 23, floorY, Math.floor(cx) + 23, floorY, 0.28);
  const u = seg(since, 0.18, 0.55);
  const lift = sealed ? -17 * eio(u) - 0.8 * Math.sin(Math.PI * seg(since, 0.73, 0.25)) : 0;
  let bend = sealed ? 1.6 * Math.sin(Math.PI * u) * (u < 0.5 ? 1 : -0.7) : 0;
  if (sealed && since > 0.73) bend += -0.7 * Math.sin((since - 0.73) * 30) * Math.exp(-(since - 0.73) / 0.15);
  // each plate that lands makes the bar ring
  let vib = 0;
  for (let k = 0; k < taps; k++) {
    const a = age(k) - 0.13;
    if (a > 0) vib += 0.7 * Math.sin(a * 46) * Math.exp(-a / 0.14);
  }
  const yOf = (x: number) => yr + lift + (bend + vib) * ((x - cx) / hl) ** 2;
  for (let x = -hl; x <= hl; x++) g.fr(C(cx) + x, yOf(C(cx) + x), x === 0 ? 1 : 0.8, x === 0 ? 1 : 0);
  for (const sd of [-1, 1]) {
    for (let v = -2; v <= 2; v++) g.fr(C(cx) + sd * 8, yOf(C(cx) + sd * 8) + v, 0.9);
    for (let k = 0; k < N; k++) {
      const a = age(k), H = PL[k], on = a >= 0;
      const slide = !on ? 14 : a < 0.13 ? 12 * (1 - ez(a / 0.13)) : -0.5 * Math.sin(Math.PI * seg(a, 0.13, 0.12));
      for (let c = 0; c < 2; c++) {
        const px = C(cx) + sd * (9 + 2 * k + c + slide);
        for (let v = 0; v < H; v++) {
          const bev = c === 1 && (v === 0 || v === H - 1);
          g.fr(px, yOf(px) - (H - 1) / 2 + v, on && !bev ? (c ? 0.58 : 0.95) + 0.08 * hit(a - 0.13, 0.15) : 0);
        }
      }
    }
  }
  return {glow: [{x: cx, y: yr + lift, r: 26, a: 0.24 * hit(since - 0.73, 0.4)}, {x: cx + 9 + 2 * taps, y: yr, r: 7, a: sealed ? 0 : 0.14 * hit(lastAge(s) - 0.13, 0.2)}, {x: cx - 9 - 2 * taps, y: yr, r: 7, a: sealed ? 0 : 0.14 * hit(lastAge(s) - 0.13, 0.2)}], flash: 0.07 * hit(since - 0.73, 0.15)};
};

// ---- Fri: +1. Each tap lights the next chevron and the stack climbs; the last launches it into +1 ----
const chevCells = () => {
  const o: P[] = [];
  const seen = new Set<string>();
  for (let i = 0; i <= 7; i++)
    for (const sd of [-1, 1])
      for (const t2 of [0, 1]) {
        const p: P = [sd * i, Math.round((i * 5) / 7) + t2];
        if (!seen.has(p.join())) seen.add(p.join()), o.push(p);
      }
  return o;
};
const CHEV = chevCells();
const plusOne = (g: G, cx: number, cy: number, b: number, t: number) => {
  const x0 = Math.round(cx - 16), y0 = Math.floor(cy) - 12;
  const sh = (x: number, y: number) => 0.14 * sheen(x - cx, y - cy, t, 3.4, 22, 3);
  for (let j = 0; j < 13; j++) for (let i = 0; i < 13; i++) if ((i >= 5 && i < 8) || (j >= 5 && j < 8)) g.on(x0 + i, y0 + 4 + j, b + sh(x0 + i, y0 + 4 + j), i === 6 && j === 6 ? 1 : 0);
  F5['1'].forEach((row, r) => [...row].forEach((ch, c) => {
    if (ch === '1') for (let v = 0; v < 3; v++) for (let u = 0; u < 3; u++) g.on(x0 + 17 + c * 3 + u, y0 + r * 3 + v, b + sh(x0 + 17 + c * 3 + u, y0 + r * 3 + v));
  }));
};
const finFri: Fin = (g, s, age) => {
  const {cx, cy, N, t, sealT, since, taps} = s;
  const sealed = sealT != null;
  if (sealed && since > 0.42) {
    plusOne(g, cx, cy, 0.95, since > 1 ? t - sealT! - 1 : -9);
    return {ph: 'plus', o: {burst: 34, stagger: 0.05}, flash: 0.12 * hit(since - 0.42, 0.15), glow: [{x: cx, y: cy - 2, r: 24, a: 0.3 * hit(since - 0.42, 0.45)}]};
  }
  const gap = N >= 7 ? 3 : 4;
  let climb = 0;
  for (let k = 0; k < taps; k++) climb += sp(age(k));
  let off = -climb * 1.1, sc = 1;
  if (sealed) {
    sc = 1 - 0.3 * Math.sin(Math.PI * seg(since, 0.05, 0.13)) + 0.45 * seg(since, 0.18, 0.24);
    off -= 10 * seg(since, 0.18, 0.24) ** 2;
  }
  const base = Math.floor(cy) + 7.5;
  for (let k = 0; k < N; k++) {
    const ay = base + off - k * gap * sc, on = k < taps, a = age(k);
    const lift = on ? -1.5 * (1 - sp(a)) : 0;
    for (const [dx, dy] of CHEV) {
      const top = on && k === taps - 1 && dx === 0 && dy === 0;
      g.fr(C(cx) + dx, ay + dy + lift, on ? 0.9 + 0.1 * hit(a, 0.2) : 0.13, top ? 1 : 0);
    }
  }
  return {ph: 'track', glow: [{x: cx, y: base + off - (taps - 1) * gap, r: 8, a: 0.16 * hit(lastAge(s), 0.22)}]};
};

// ---- Sat: RING. N arcs; each tap sweeps the next one closed; the last tap closes the ring ----
const RING: {x: number; y: number; th: number}[] = [];
for (let y = -16; y <= 16; y++)
  for (let x = -16; x <= 16; x++) {
    const r = Math.hypot(x, y);
    if (r >= 11.6 && r <= 15.3) RING.push({x, y, th: (Math.atan2(x, -y) + TAU) % TAU});
  }
const finSat: Fin = (g, s, age) => {
  const {cx, cy, N, t, sealT, since, taps} = s;
  const X = C(cx), Y = C(cy) - 1, sealed = sealT != null;
  const la = lastAge(s), head = taps === 0 ? 0 : ((taps - 1 + ez(la / 0.3)) / N) * TAU;
  const closed = sealed && since > 0.3;
  const glint = closed && since > 1 ? (t - sealT! - 1) * 2.2 : -99;
  for (const c of RING) {
    let gapC = false;
    if (!closed) for (let k = 1; k < N; k++) if (Math.abs(c.th - (k / N) * TAU) < 0.045) gapC = true;
    if (!closed && c.th < 0.045) gapC = true;
    if (gapC && c.th > head) continue;
    const lit = c.th <= head + 1e-6 || closed;
    const d = Math.abs(((c.th - glint) % TAU + TAU) % TAU - Math.PI) - Math.PI;
    g.on(X + c.x, Y + c.y, lit ? 0.92 + 0.08 * hit(since - 0.3, 0.3) + (glint > -9 ? 0.12 * Math.exp(-((d / 0.35) ** 2)) : 0) : 0.12);
  }
  // the head: a round cap that leads the sweep; coral is now
  const hx = X + Math.sin(head) * 13.4, hy = Y - Math.cos(head) * 13.4;
  for (let v = -1; v <= 1; v++) for (let u = -1; u <= 1; u++) g.fr(hx + u, hy + v, taps > 0 && (u === 0 || v === 0) ? 1 : 0, u === 0 && v === 0 ? 1 : 0);
  ripple(g, X, Y, 15.5, 25, since - 0.3, 0.65, 72, 0.45);
  return {glow: [{x: hx, y: hy, r: 6, a: sealed ? 0 : 0.18 * hit(la, 0.25)}, {x: X, y: Y, r: 26, a: 0.28 * hit(since - 0.3, 0.45)}], flash: 0.08 * hit(since - 0.3, 0.15)};
};

// ---- Sun: HOURGLASS. Each tap runs a day of sand through; after the seventh it turns over ----
const glassGeo = (() => {
  const H = 13, top: P[] = [], bot: P[] = [];
  const hw = (j: number) => Math.floor((j * 10) / H);
  for (let j = 1; j <= H - 2; j++) for (let i = -hw(j) + (j > 2 ? 1 : 0); i <= hw(j) - (j > 2 ? 1 : 0); i++) top.push([i, -j]), bot.push([i, j]);
  top.sort((p, q) => p[1] - q[1] || Math.abs(p[0]) - Math.abs(q[0]));
  bot.sort((p, q) => (q[1] - Math.abs(q[0]) * 0.45) - (p[1] - Math.abs(p[0]) * 0.45));
  const frame: P[] = [];
  for (let i = -12; i <= 12; i++) frame.push([i, -H - 1], [i, H + 1], [i, -H - 2], [i, H + 2]);
  for (let j = 0; j <= H; j++) {
    const w = 1 + (j * 10) / H;
    frame.push([-w - 0.5, -j], [w + 0.5, -j], [-w - 0.5, j], [w + 0.5, j]);
  }
  return {H, top, bot, frame};
})();
const finSun: Fin = (g, s, age) => {
  const {cx, cy, N, sealT, since} = s;
  const {top, bot, frame} = glassGeo;
  const X = C(cx), Y = C(cy) - 1, sealed = sealT != null;
  const rot = sealed ? Math.PI * eio(seg(since, 0.62, 0.62)) : 0;
  const cs = Math.cos(rot), sn = Math.sin(rot);
  const P2 = (x: number, y: number): P => [X + x * cs - y * sn, Y + x * sn + y * cs];
  for (const [x, y] of frame) {
    const [a, b] = P2(x, y);
    g.fr(a, b, Math.abs(y) > 13 ? 0.9 : 0.62);
  }
  const G2 = Math.min(top.length, bot.length), per = G2 / N;
  for (let i = 0; i < G2; i++) {
    const d = Math.min(N - 1, Math.floor(i / per)), q = (i - d * per) / per, a = age(d);
    const flowT = d === N - 1 ? 0.32 : 0.45, travel = 0.24;
    const u = a < 0 ? 0 : seg(a, q * flowT, travel);
    let x: number, y: number;
    const [tx, ty] = top[i], [bx, by] = bot[i];
    if (u <= 0) (x = tx), (y = ty);
    else if (u >= 1) (x = bx), (y = by);
    else if (u < 0.25) {
      const k = u / 0.25;
      (x = lerp(tx, 0, k * k)), (y = lerp(ty, 0, Math.sqrt(k)));
    } else {
      const k = (u - 0.25) / 0.75;
      (x = lerp(0, bx, k ** 3)), (y = lerp(0.5, by, k * k));
    }
    const [px, py] = P2(x, y);
    const last = sealed ? i === G2 - 1 : i === Math.min(G2, Math.round(s.taps * per)) - 1 && s.taps > 0;
    g.fr(px, py, u > 0 && u < 1 ? 1 : 0.86, last ? 1 : 0);
  }
  return {glow: [{x: X, y: Y, r: 6, a: sealed ? 0 : 0.14 * hit(lastAge(s), 0.4)}, {x: X, y: Y, r: 24, a: 0.26 * hit(since - 1.24, 0.45)}], flash: 0.07 * hit(since - 1.24, 0.15)};
};
const FINISH = [finMon, finTue, finWed, finThu, finFri, finSat, finSun];

// ============================== 7. THE COUNT ==============================
// 1.6 s after the seal the finished object becomes the session count; the last digit ticks up.
const mini = (g: G, day: number, x: number, y: number) => {
  const X = Math.floor(x), Y = Math.floor(y);
  if (day === 0) {
    g.line(X - 7, Y + 3, X + 7, Y + 3, 0.6);
    for (let dy = -4; dy <= 2; dy++) for (let dx = -4; dx <= 4; dx++) if (dx * dx + (dy + 1) ** 2 <= 17) g.on(X + dx, Y + dy, 0.9, dx === 0 && dy === -4 ? 1 : 0);
    for (const [dx, dy] of [[0, -7], [-5, -5], [5, -5], [-7, -1], [7, -1]]) g.on(X + dx, Y + dy, 0.8);
  } else if (day === 1) {
    for (const [ox, oy, w] of [[-8, 1, 8], [1, 1, 8], [-8, -3, 3], [-4, -3, 8], [5, -3, 4]]) for (let v = 0; v < 3; v++) for (let u = 0; u < w; u++) g.on(X + ox + u, Y + oy + v, 0.85, ox === -4 && u >= 3 && u < 5 && v === 1 ? 1 : 0);
  } else if (day === 2) {
    g.rect(X - 8, Y - 4, 16, 9, 0.85);
    g.rect(X + 8, Y - 2, 1, 5, 0.85, true);
    for (let v = 0; v < 7; v++) for (let u = 0; u < 14; u++) g.on(X - 7 + u, Y - 3 + v, 0.85);
    g.on(X, Y, 1, 1);
  } else if (day === 3) {
    g.line(X - 11, Y, X + 11, Y, 0.8);
    for (const sd of [-1, 1]) for (const [o, h] of [[5, 9], [6, 9], [7, 7], [8, 7]]) g.line(X + sd * o, Y - (h - 1) / 2, X + sd * o, Y + (h - 1) / 2, 0.9);
    g.on(X, Y, 1, 1);
  } else if (day === 4) {
    for (let i = -3; i <= 3; i++) g.on(X - 6 + i, Y, 0.9), g.on(X - 6, Y + i, 0.9);
    g.on(X - 6, Y, 1, 1);
    for (let j = -3; j <= 3; j++) g.on(X + 4, Y + j, 0.9);
    g.on(X + 3, Y - 2, 0.9), g.on(X + 3, Y + 3, 0.9), g.on(X + 5, Y + 3, 0.9);
  } else if (day === 5) {
    for (let yy = -6; yy <= 6; yy++) for (let xx = -6; xx <= 6; xx++) {
      const r = Math.hypot(xx, yy);
      if (r >= 3.6 && r <= 5.6) g.on(X + xx, Y + yy, 0.92);
    }
    g.on(X, Y - 5, 1, 1);
  } else {
    for (let i = -5; i <= 5; i++) g.on(X + i, Y - 6, 0.85), g.on(X + i, Y + 6, 0.85);
    for (let j = 0; j <= 5; j++) {
      const w = 1 + j * 0.8;
      g.on(X - w, Y - j, 0.5), g.on(X + w, Y - j, 0.5), g.on(X - w, Y + j, 0.5), g.on(X + w, Y + j, 0.5);
      if (j >= 1 && j <= 4) for (let x = Math.ceil(X - w + 1); x < X + w; x++) g.on(x, Y - j, 0.85, j === 1 && x === X ? 1 : 0);
    }
  }
};
const count = (g: G, s: SC): Res => {
  const {cx, cy, since, D, day, t} = s;
  const a = since - 1.6, tick = a > 0.55, n = tick ? D.sessions : D.sessions - 1;
  const fmt = '8'.repeat(String(D.sessions).length);
  led(g, String(n), fmt, cx, Math.floor(cy) - 18, 3, 0.95 + 0.05 * hit(a - 0.55, 0.3), 0, 3);
  mini(g, day, cx, Math.floor(cy) + 11);
  void t;
  return {o: {burst: 24, stagger: 0.12}, glow: [{x: cx, y: cy - 8, r: 22, a: 0.2 * hit(a - 0.55, 0.4)}]};
};

// ============================== entry ==============================
export const mxStory = (id: string, counted: boolean, s: SC): Out => {
  const g = new G(s.cols, s.rows, 1400);
  const age = (k: number) => (s.tapTimes[k] != null ? s.t - s.tapTimes[k] : -1);
  const dd = s.D.day;
  let r: Res;
  if (counted) r = count(g, s);
  else if (id === 'verified') r = VERIFIED[s.day](g, s);
  else if (id === 'today') r = today(g, s);
  else if (id === 'week') r = week(g, s);
  else if (id === 'month') r = month(g, s);
  else if (id === 'far') r = s.day === 3 ? fThu(g, s) : [fMon, fTue, fWed, fMon, fFri, fSat, fSun][s.day](g, s, dd);
  else if (id === 'climax') r = FINISH[s.day](g, s, age);
  else return null;
  return {g, ...(r || {})};
};
