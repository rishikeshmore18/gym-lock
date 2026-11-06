/**
 * Matrix Dynamic: a dot-matrix instrument, not a landscape in dots.
 * Everything here is drawn in grid cells (38 × 35), lit like an LED board: crisp cells for forms,
 * free particles for things in flight. Coral is one dot: you, now, or the last piece.
 */
import type {Opts} from '../hero4/dots';
import type {ITgt as Tgt} from './mdots';
import {text as dtext, textWidth} from '../hero4/dots';

export const COLS = 38, ROWS = 35, CX = 22, CY = 17;
const TAU = Math.PI * 2;

export const cl = (x: number) => Math.min(1, Math.max(0, x));
export const ez = (x: number) => 1 - Math.pow(1 - cl(x), 3);
export const eio = (x: number) => {
  const k = cl(x);
  return k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;
};
export const back = (x: number, k = 1.7) => {
  const u = cl(x) - 1;
  return 1 + (k + 1) * u * u * u + k * u * u;
};
/** springy settle from 0 to 1 */
export const spr = (x: number, w = 13, z = 5) => (x <= 0 ? 0 : 1 - Math.exp(-x * z) * Math.cos(x * w));
/** a sharp hit every P seconds that decays over w */
export const pulse = (t: number, P: number, w = 0.14, off = 0) => Math.exp(-((((t - off) % P) + P) % P) / w);
export const rnd = (i: number) => {
  let h = (i * 374761393 + 668265263) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const since = (T: number, at: number) => T - at;

// the alarm's rhythm: five fast rings, then one every 2.5 s
export const RINGS = [0.35, 0.85, 1.35, 1.85, 2.35];
export const ringBeat = (T: number) => {
  let v = 0;
  for (const b of RINGS) if (T >= b) v = Math.max(v, Math.exp(-(T - b) / 0.13));
  if (T > 2.6) v = Math.max(v, pulse(T, 2.5, 0.13, 0.35));
  return v;
};
export const lastRing = (T: number) => {
  let last = -1;
  for (const b of RINGS) if (T >= b) last = b;
  if (T > 2.6) last = Math.floor((T - 0.35) / 2.5) * 2.5 + 0.35;
  return last;
};
export const ringIndex = (T: number) => {
  let k = -1;
  for (const b of RINGS) if (T >= b) k++;
  if (T > 2.6) k = 4 + Math.floor((T - 0.35 - 2.5) / 2.5) + 1;
  return k;
};

/** one frame of the board */
export class G {
  private m = new Map<number, Tgt>();
  private f: Tgt[] = [];
  constructor(private W = COLS, private H = ROWS, private cap = 720) {}
  /** a lit cell, snapped to the grid; the brighter of two writes wins */
  on(x: number, y: number, b = 1, c = 0) {
    const ix = Math.floor(x), iy = Math.floor(y);
    if (ix < 0 || iy < 0 || ix >= this.W || iy >= this.H) return;
    const k = iy * 256 + ix;
    const o = this.m.get(k);
    const bb = cl(b);
    if (!o) this.m.set(k, {x: ix + 0.5, y: iy + 0.5, b: bb, c, id: k});
    else if (bb > o.b || (c && bb >= o.b * 0.7)) {
      o.b = Math.max(o.b, bb);
      if (c) o.c = 1;
    }
  }
  /** a free particle (not snapped, not merged): for things in flight. Keep counts fixed per element. */
  fr(x: number, y: number, b = 1, c = 0) {
    const off = x < -0.5 || y < -0.5 || x > this.W + 0.5 || y > this.H + 0.5;
    this.f.push({x, y, b: off ? 0 : cl(b), c, id: 1000000 + this.f.length});
  }
  /** a free particle that sits on a cell centre (crisp, but keeps its own slot) */
  fs(x: number, y: number, b = 1, c = 0) {
    this.fr(Math.floor(x) + 0.5, Math.floor(y) + 0.5, b, c);
  }
  line(x0: number, y0: number, x1: number, y1: number, b = 1, c = 0, dash = 0) {
    const n = Math.max(1, Math.round(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0))));
    for (let i = 0; i <= n; i++) {
      if (dash && Math.floor(i / dash) % 2) continue;
      this.on(x0 + ((x1 - x0) * i) / n + 0.5, y0 + ((y1 - y0) * i) / n + 0.5, b, c);
    }
  }
  /** an arc from a0 to a1 (radians, 0 = up, clockwise) */
  ring(cx: number, cy: number, r: number, b = 1, c = 0, a0 = 0, a1 = TAU, ry = r, step = 1) {
    const L = Math.abs(a1 - a0) * Math.max(r, ry);
    const n = Math.max(6, Math.round(L / step));
    for (let i = 0; i <= n; i++) {
      const a = a0 + ((a1 - a0) * i) / n;
      this.on(cx + Math.sin(a) * r, cy - Math.cos(a) * ry, b, c);
    }
  }
  disc(cx: number, cy: number, r: number, b = 1, c = 0) {
    for (let y = Math.floor(cy - r); y <= cy + r; y++)
      for (let x = Math.floor(cx - r); x <= cx + r; x++) if ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r) this.on(x, y, b, c);
  }
  rect(x: number, y: number, w: number, h: number, b = 1, fill = false, c = 0) {
    for (let j = 0; j < h; j++)
      for (let i = 0; i < w; i++) if (fill || i === 0 || j === 0 || i === w - 1 || j === h - 1) this.on(x + i, y + j, b, c);
  }
  /** a pixel icon: '#' lit, 'o' coral, '+' dim, anything else off */
  glyph(rows: string[], x: number, y: number, s = 1, b = 1, free = false) {
    for (let j = 0; j < rows.length; j++)
      for (let i = 0; i < rows[j].length; i++) {
        const ch = rows[j][i];
        if (ch !== '#' && ch !== 'o' && ch !== '+') continue;
        const bb = ch === '+' ? 0.22 * b : b, cc = ch === 'o' ? 1 : 0;
        for (let v = 0; v < s; v++) for (let u = 0; u < s; u++) (free ? this.fs.bind(this) : this.on.bind(this))(x + i * s + u, y + j * s + v, bb, cc);
      }
  }
  /** LED digits, centred on cx; dim draws the unlit font cells too (a board that flips in place) */
  num(s: string, cx: number, y: number, scale = 1, b = 1, dim?: number, coral?: number[]) {
    const x0 = Math.round(cx - textWidth(s, scale) / 2);
    for (const q of dtext(s, x0, y, {scale, dim, coral})) this.on(q.x, q.y, q.b === 1 ? b : q.b, q.c ?? 0);
  }
  out(): Tgt[] {
    return [...this.m.values(), ...this.f].slice(0, this.cap);
  }
}

export type MC = {t: number; T: number; d: {setupDone: boolean[]; countdown: number; atgym: number; stillLeft: number}; day: number; pos: string; N: number; D: {day: number; week: number; sessions: number}};
export type MOut = {ph?: string | number; o?: Opts; flash?: number; shake?: number};
export type MHap = {t: number; kind: 'light' | 'medium' | 'heavy' | 'success'}[];
export type MScn = {draw: (g: G, c: MC) => MOut | void; hap?: MHap};

/** particles thrown from a point: positions at a given age */
export const burst = (n: number, age: number, speed: number, grav: number, seed: number, up = false) => {
  const o: number[] = [];
  for (let i = 0; i < n; i++) {
    const a = up ? -Math.PI / 2 + (rnd(seed + i * 3) - 0.5) * 2.4 : rnd(seed + i * 3) * TAU;
    const s = speed * (0.45 + rnd(seed + i * 3 + 1) * 0.75);
    o.push(Math.cos(a) * s * age, Math.sin(a) * s * age + 0.5 * grav * age * age);
  }
  return o;
};

// ---------- pixel icons ----------
export const ICON: Record<string, string[]> = {
  bell: ['....#....', '..#####..', '.##...##.', '.#.....#.', '.#.....#.', '.#.....#.', '##.....##', '#########', '.........', '...###...'],
  sun: ['....#....', '.#..#..#.', '..#...#..', '....#....', '#..###..#', '...###...', '....#....', '..#...#..', '.#..#..#.', '....#....'],
  moon: ['..####...', '.###.....', '###......', '###......', '###......', '###......', '.###.....', '..####...'],
  lock: ['..#####..', '.##...##.', '.#.....#.', '.#.....#.', '#########', '#########', '####o####', '####o####', '#########', '#########'],
  dumbbell: ['##.......##', '##.......##', '###########', '##.......##', '##.......##'],
  check: ['.........##', '........##.', '.......##..', '##....##...', '.##..##....', '..####.....', '...##......'],
  pause: ['###..###', '###..###', '###..###', '###..###', '###..###', '###..###', '###..###', '###..###'],
  plane: ['.....#......', '.....##.....', '#....###....', '############', '#....###....', '.....##.....', '.....#......'],
  flag: ['#######', '#######o', '#######', '#......', '#......', '#......', '#......', '#......'],
  pin: ['..###..', '.#####.', '##...##', '##.o.##', '.#####.', '..###..', '...#...'],
  house: ['....#....', '...###...', '..#####..', '.#######.', '#########', '.##...##.', '.##...##.', '.##.o.##.', '.##...##.'],
  bag: ['...###...', '..#...#..', '#########', '#########', '#########', '####o####', '#########', '#########'],
  shoe: ['#####.....', '#####.....', '######....', '#########.', '##########', '##########'],
  plus: ['..#..', '..#..', '#####', '..#..', '..#..'],
  power: ['....#....', '.#..#..#.', '#...#...#', '#...#...#', '#.......#', '#.......#', '.#.....#.', '..#####..'],
  flake: ['....#....', '.#..#..#.', '..#.#.#..', '...###...', '#########', '...###...', '..#.#.#..', '.#..#..#.', '....#....'],
  arrowR: ['....#...', '....##..', '#######.', '########', '#######.', '....##..', '....#...'],
  arrowU: ['...#...', '..###..', '.#####.', '#######', '..###..', '..###..', '..###..', '..###..'],
  z: ['####', '..#.', '.#..', '####'],
  bolt: ['...###', '..###.', '.###..', '######', '..###.', '.###..', '###...', '#.....'],
};
export const iconW = (k: string) => Math.max(...ICON[k].map((r) => r.length));
export const iconH = (k: string) => ICON[k].length;
/** draw an icon centred on (cx, cy) */
export const icon = (g: G, k: string, cx: number, cy: number, s = 1, b = 1, free = false) =>
  g.glyph(ICON[k], Math.round(cx - (iconW(k) * s) / 2), Math.round(cy - (iconH(k) * s) / 2), s, b, free);
/** an icon as points (for morphs and free motion) */
export const iconPts = (k: string, s = 1): [number, number, number][] => {
  const o: [number, number, number][] = [];
  const R = ICON[k], w = iconW(k), h = iconH(k);
  R.forEach((row, j) => [...row].forEach((ch, i) => {
    if (ch === '#' || ch === 'o') for (let v = 0; v < s; v++) for (let u = 0; u < s; u++) o.push([i * s + u - (w * s) / 2, j * s + v - (h * s) / 2, ch === 'o' ? 1 : 0]);
  }));
  return o;
};
