/**
 * Particle board for Matrix Dynamic. Unlike the shared engine, a target keeps its particle by
 * identity (cell or slot id), so a growing shape doesn't make every later dot shuffle: new cells light
 * in place like an LED, things that move keep their own dot, and a new phase (key) re-deals
 * everything so the dots fly to the next form.
 */
import type {Opts, Tgt} from '../hero4/dots';

export type ITgt = Tgt & {id: number};
const hash = (i: number, k: number) => {
  let h = (i * 374761393 + k * 668265263) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};

export class MDots {
  n: number;
  x: Float32Array;
  y: Float32Array;
  vx: Float32Array;
  vy: Float32Array;
  b: Float32Array;
  c: Uint8Array;
  tx: Float32Array;
  ty: Float32Array;
  tb: Float32Array;
  act: Uint8Array;
  start: Float32Array;
  idOf = new Map<number, number>();
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
    this.tx = new Float32Array(n);
    this.ty = new Float32Array(n);
    this.tb = new Float32Array(n);
    this.act = new Uint8Array(n);
    this.start = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      this.x[i] = hash(i, 1) * cols;
      this.y[i] = hash(i, 2) * rows;
    }
  }

  private deal(T: ITgt[], t: number, o: Opts) {
    const L = Math.min(T.length, this.n);
    let cx = 0, cy = 0;
    for (let j = 0; j < L; j++) {
      cx += T[j].x;
      cy += T[j].y;
    }
    cx /= L || 1;
    cy /= L || 1;
    const vis: number[] = [], idle: number[] = [];
    for (let i = 0; i < this.n; i++) (this.b[i] > 0.04 ? vis : idle).push(i);
    const chosen = vis.slice(0, L);
    for (let k = 0; chosen.length < L && k < idle.length; k++) chosen.push(idle[k]);
    const ang = (x: number, y: number) => Math.atan2(y - cy, x - cx);
    const tOrd = Array.from({length: L}, (_, j) => j).sort((a, b) => ang(T[a].x, T[a].y) - ang(T[b].x, T[b].y));
    chosen.sort((a, b) => ang(this.x[a], this.y[a]) - ang(this.x[b], this.y[b]));
    this.idOf.clear();
    this.act.fill(0);
    for (let k = 0; k < L; k++) {
      const p = chosen[k], j = tOrd[k];
      this.idOf.set(T[j].id, p);
      this.start[p] = t + (o.stagger ?? 0.18) * (k / Math.max(1, L));
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

  update(key: string, T: ITgt[], t: number, o: Opts = {}) {
    if (key !== this.key) {
      this.deal(T, t, o);
      this.key = key;
    }
    // targets by identity: keep a dot on its cell; a new cell lights in place; a gone cell lets go
    const seen = new Set<number>();
    const used = new Uint8Array(this.n);
    for (const p of this.idOf.values()) used[p] = 1;
    let free = 0;
    const nextFree = () => {
      while (free < this.n && (used[free] || this.b[free] > 0.03)) free++;
      return free < this.n ? free : -1;
    };
    this.act.fill(0);
    for (const q of T) {
      let p = this.idOf.get(q.id);
      if (p == null) {
        p = nextFree();
        if (p < 0) continue;
        used[p] = 1;
        this.idOf.set(q.id, p);
        this.x[p] = q.x;
        this.y[p] = q.y;
        this.vx[p] = this.vy[p] = 0;
        this.b[p] = 0;
        this.start[p] = t;
      }
      seen.add(q.id);
      if (t < this.start[p]) continue;
      this.act[p] = 1;
      this.tx[p] = q.x;
      this.ty[p] = q.y;
      this.tb[p] = q.b;
      this.c[p] = q.c ? 1 : 0;
    }
    for (const [id, p] of this.idOf) if (!seen.has(id)) this.idOf.delete(id), (this.tb[p] = 0);

    if (this.last < 0) this.last = t;
    let dt = Math.min(0.1, Math.max(0, t - this.last));
    this.last = t;
    const h = 1 / 120, P = this.pointer;
    while (dt > 1e-6) {
      const s = Math.min(h, dt);
      dt -= s;
      for (let i = 0; i < this.n; i++) {
        if (this.act[i]) {
          this.vx[i] += ((this.tx[i] - this.x[i]) * this.stiff - this.vx[i] * this.damp) * s;
          this.vy[i] += ((this.ty[i] - this.y[i]) * this.stiff - this.vy[i] * this.damp) * s;
        } else {
          this.vx[i] *= 1 - 6 * s;
          this.vy[i] *= 1 - 6 * s;
        }
        if (P) {
          const dx = this.x[i] - P.x, dy = this.y[i] - P.y, d = Math.hypot(dx, dy);
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
      const target = this.act[i] ? this.tb[i] : 0;
      this.b[i] += (target - this.b[i]) * (this.act[i] ? 0.3 : 0.42);
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
