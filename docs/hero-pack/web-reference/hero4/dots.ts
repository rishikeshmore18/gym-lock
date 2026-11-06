/**
 * Dot engine. A fixed grid of unlit dots plus a pool of lit particles that fly between glyphs.
 * Everything is in grid cells; the caller decides where the grid sits and how big a cell is.
 *   - every glyph is a list of targets {x, y, b, c}: cell position, brightness, coral or not
 *   - when the glyph key changes, particles are re-dealt by angle so the morph swirls instead of
 *     crossing, with a small stagger so it reads as a wave
 *   - within one key the target list keeps its order, so moving targets drag their particles
 *     (falling sand, flicker, flowing loops) with spring physics
 */
export type Tgt = {x: number; y: number; b: number; c?: number};

const hash = (i: number, s: number) => {
  const x = Math.sin(i * 127.1 + s * 311.7) * 43758.5453;
  return x - Math.floor(x);
};
export {hash};

export class Dots {
  n: number;
  x: Float32Array;
  y: Float32Array;
  vx: Float32Array;
  vy: Float32Array;
  b: Float32Array;
  c: Uint8Array;
  start: Float32Array;
  map: Int32Array = new Int32Array(0); // target index → particle
  owner: Int32Array; // particle → target index or -1
  key = '';
  last = -1;
  pointer: {x: number; y: number} | null = null;
  stiff = 210;
  damp = 21;

  constructor(n: number, cols: number, rows: number) {
    this.n = n;
    this.x = new Float32Array(n);
    this.y = new Float32Array(n);
    this.vx = new Float32Array(n);
    this.vy = new Float32Array(n);
    this.b = new Float32Array(n);
    this.c = new Uint8Array(n);
    this.start = new Float32Array(n);
    this.owner = new Int32Array(n).fill(-1);
    for (let i = 0; i < n; i++) {
      this.x[i] = hash(i, 1) * cols;
      this.y[i] = hash(i, 2) * rows;
    }
  }

  /** re-deal particles to a new glyph */
  private deal(T: Tgt[], t: number, o: Opts) {
    const L = Math.min(T.length, this.n);
    let cx = 0, cy = 0;
    for (let j = 0; j < L; j++) {
      cx += T[j].x;
      cy += T[j].y;
    }
    cx /= L || 1;
    cy /= L || 1;
    // prefer particles already on screen, then idle ones
    const vis: number[] = [], idle: number[] = [];
    for (let i = 0; i < this.n; i++) (this.b[i] > 0.04 ? vis : idle).push(i);
    const chosen = vis.slice(0, L);
    for (let k = 0; chosen.length < L && k < idle.length; k++) chosen.push(idle[k]);
    const ang = (x: number, y: number) => Math.atan2(y - cy, x - cx);
    const tOrd = Array.from({length: L}, (_, j) => j).sort((a, b) => ang(T[a].x, T[a].y) - ang(T[b].x, T[b].y));
    chosen.sort((a, b) => ang(this.x[a], this.y[a]) - ang(this.x[b], this.y[b]));
    this.owner.fill(-1);
    this.map = new Int32Array(L);
    for (let k = 0; k < L; k++) {
      const p = chosen[k], j = tOrd[k];
      this.map[j] = p;
      this.owner[p] = j;
      this.start[p] = t + (o.stagger ?? 0.18) * (o.order === 'y' ? clamp((T[j].y - o.oy!) / 30, 0, 1) : k / Math.max(1, L));
      if (o.scatter) {
        this.x[p] = cx + (hash(p, 7) - 0.5) * o.scatter;
        this.y[p] = cy + (hash(p, 8) - 0.5) * o.scatter;
        this.vx[p] = this.vy[p] = 0;
        this.b[p] = Math.min(this.b[p], 0.3);
      }
      if (o.burst) {
        const a = hash(p, 9) * Math.PI * 2, s = (0.3 + hash(p, 10)) * o.burst;
        this.vx[p] = Math.cos(a) * s;
        this.vy[p] = Math.sin(a) * s;
      }
    }
  }

  update(key: string, T: Tgt[], t: number, o: Opts = {}) {
    if (key !== this.key) {
      this.deal(T, t, o);
      this.key = key;
    }
    // target list grew within the same glyph: hand out idle particles
    if (T.length > this.map.length) {
      const m = new Int32Array(Math.min(this.n, T.length));
      m.set(this.map);
      let k = 0;
      for (let j = this.map.length; j < m.length; j++) {
        while (k < this.n && this.owner[k] !== -1) k++;
        if (k >= this.n) break;
        m[j] = k;
        this.owner[k] = j;
        this.start[k] = t;
        k++;
      }
      this.map = m;
    }
    if (this.last < 0) this.last = t;
    let dt = Math.min(0.1, Math.max(0, t - this.last));
    this.last = t;
    const h = 1 / 120;
    const tb = new Float32Array(this.n); // target brightness
    const tx = new Float32Array(this.n), ty = new Float32Array(this.n);
    const active = new Uint8Array(this.n);
    for (let j = 0; j < this.map.length; j++) {
      const p = this.map[j];
      if (j >= T.length) {
        this.owner[p] = -1;
        continue;
      }
      if (t < this.start[p]) continue;
      active[p] = 1;
      tx[p] = T[j].x;
      ty[p] = T[j].y;
      tb[p] = T[j].b;
      this.c[p] = T[j].c ? 1 : 0;
    }
    if (this.map.length > T.length) this.map = this.map.slice(0, T.length);
    const P = this.pointer;
    while (dt > 1e-6) {
      const s = Math.min(h, dt);
      dt -= s;
      for (let i = 0; i < this.n; i++) {
        if (active[i]) {
          this.vx[i] += ((tx[i] - this.x[i]) * this.stiff - this.vx[i] * this.damp) * s;
          this.vy[i] += ((ty[i] - this.y[i]) * this.stiff - this.vy[i] * this.damp) * s;
        } else {
          this.vx[i] *= 1 - 6 * s;
          this.vy[i] *= 1 - 6 * s;
        }
        if (P) {
          const dx = this.x[i] - P.x, dy = this.y[i] - P.y;
          const d = Math.hypot(dx, dy);
          if (d < 4.5 && d > 0.01) {
            const k = (1 - d / 4.5) * 520 * s;
            this.vx[i] += (dx / d) * k;
            this.vy[i] += (dy / d) * k;
          }
        }
        this.x[i] += this.vx[i] * s;
        this.y[i] += this.vy[i] * s;
      }
    }
    for (let i = 0; i < this.n; i++) {
      const target = active[i] ? tb[i] : this.owner[i] >= 0 ? this.b[i] : 0;
      this.b[i] += (target - this.b[i]) * (active[i] ? 0.22 : 0.12);
    }
  }

  draw(ctx: CanvasRenderingContext2D, ox: number, oy: number, pitch: number, color: string, coral: string, r: number, clip?: (x: number) => number) {
    const LV = 7;
    const paths: Path2D[] = Array.from({length: LV}, () => new Path2D());
    const cp = new Path2D();
    let anyC = false;
    for (let i = 0; i < this.n; i++) {
      let b = this.b[i];
      if (b < 0.03) continue;
      const X = ox + this.x[i] * pitch, Y = oy + this.y[i] * pitch;
      if (clip) b *= clip(X);
      if (b < 0.03) continue;
      const rr = r * (0.42 + 0.58 * Math.min(1, b));
      if (this.c[i] && b > 0.3) {
        cp.moveTo(X + rr, Y);
        cp.arc(X, Y, rr, 0, Math.PI * 2);
        anyC = true;
        continue;
      }
      const lv = Math.min(LV - 1, Math.floor(b * LV));
      paths[lv].moveTo(X + rr, Y);
      paths[lv].arc(X, Y, rr, 0, Math.PI * 2);
    }
    ctx.save();
    ctx.fillStyle = color;
    for (let k = 0; k < LV; k++) {
      ctx.globalAlpha = 0.12 + 0.88 * ((k + 0.5) / LV);
      ctx.fill(paths[k]);
    }
    if (anyC) {
      ctx.globalAlpha = 1;
      ctx.fillStyle = coral;
      ctx.fill(cp);
    }
    ctx.restore();
  }
}
export type Opts = {stagger?: number; scatter?: number; burst?: number; order?: 'angle' | 'y'; oy?: number};
export const clamp = (v: number, a: number, b: number) => Math.min(b, Math.max(a, v));

/** the grid of unlit dots, painted once */
export const gridBitmap = (cols: number, rows: number, pitch: number, r: number, color: string, alpha: number, px: number) => {
  const c = document.createElement('canvas');
  c.width = Math.ceil(cols * pitch * px);
  c.height = Math.ceil(rows * pitch * px);
  const g = c.getContext('2d')!;
  g.scale(px, px);
  g.fillStyle = color;
  g.globalAlpha = alpha;
  g.beginPath();
  for (let i = 0; i < cols; i++)
    for (let j = 0; j < rows; j++) {
      g.moveTo((i + 0.5) * pitch + r, (j + 0.5) * pitch);
      g.arc((i + 0.5) * pitch, (j + 0.5) * pitch, r, 0, Math.PI * 2);
    }
  g.fill();
  return c;
};

// ---------- rasterising shapes onto the grid ----------
const rcache = new Map<string, {x: number; y: number}[]>();
/** draw with canvas primitives in cell units; every cell more than half covered becomes a point */
export const raster = (key: string, cols: number, rows: number, draw: (g: CanvasRenderingContext2D) => void, thr = 0.45) => {
  const hit = rcache.get(key);
  if (hit) return hit;
  const S = 4;
  const c = document.createElement('canvas');
  c.width = cols * S;
  c.height = rows * S;
  const g = c.getContext('2d', {willReadFrequently: true})!;
  g.scale(S, S);
  g.fillStyle = '#000';
  g.strokeStyle = '#000';
  draw(g);
  const data = g.getImageData(0, 0, c.width, c.height).data;
  const out: {x: number; y: number}[] = [];
  for (let j = 0; j < rows; j++)
    for (let i = 0; i < cols; i++) {
      let a = 0;
      for (let v = 0; v < S; v++) for (let u = 0; u < S; u++) a += data[((j * S + v) * c.width + i * S + u) * 4 + 3];
      if (a / (S * S * 255) > thr) out.push({x: i + 0.5, y: j + 0.5});
    }
  rcache.set(key, out);
  return out;
};

// ---------- 5 × 7 dot font ----------
const FONT: Record<string, string[]> = {
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
  D: ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
  O: ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
  N: ['10001', '11001', '10101', '10011', '10001', '10001', '10001'],
  E: ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
  '.': ['0', '0', '0', '0', '0', '0', '1'],
  ' ': ['000', '000', '000', '000', '000', '000', '000'],
};
/** every font pixel of a string becomes a target: lit pixels bright, unlit ones faint, so a
 *  changing number flips dots in place like an LED board */
export const text = (s: string, x0: number, y0: number, opt: {dim?: number; scale?: number; gap?: number; coral?: number[]} = {}) => {
  const out: Tgt[] = [];
  const sc = opt.scale ?? 1, gap = opt.gap ?? 1;
  let x = x0;
  [...s].forEach((ch, k) => {
    const g = FONT[ch] ?? FONT[' '];
    for (let r = 0; r < 7; r++)
      for (let c = 0; c < g[r].length; c++)
        for (let v = 0; v < sc; v++)
          for (let u = 0; u < sc; u++) {
            const on = g[r][c] === '1';
            if (!on && opt.dim == null) continue;
            out.push({x: x + c * sc + u + 0.5, y: y0 + r * sc + v + 0.5, b: on ? 1 : opt.dim!, c: on && opt.coral?.includes(k) ? 1 : 0});
          }
    x += (g[0].length + gap) * sc;
  });
  return out;
};
export const textWidth = (s: string, scale = 1, gap = 1) => [...s].reduce((w, ch) => w + ((FONT[ch] ?? FONT[' '])[0].length + gap) * scale, 0) - gap * scale;
