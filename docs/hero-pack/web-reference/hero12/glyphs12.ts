/**
 * Matrix glyphs for the seven worlds, drawn in dots on the same grid as the rest of the panel.
 * Each world has one main object that works as a meter, so a moment can show "how far along" in that
 * day's own language:
 *   Mon sun      height of the sun over a sea of cloud
 *   Tue stone    cracks in a rock, then the break
 *   Wed water    a boat crossing, a drip keeping time, stones skipping
 *   Thu pine     the height of a pine; fireflies; a candle in a lantern
 *   Fri summit   a light walking the trail; the beacon on top
 *   Sat sea      a low sun, the tide creeping to a flag, lanterns rising
 *   Sun stars    seven stars lighting one by one, then the lines; the moon
 * Plus weather layers (snow, rain, fog) and the month as a calendar of dots.
 */
import {Tgt, hash, raster} from '../hero4/dots';
import {Frame, flame} from '../hero4/glyphs';

const K = (f: Frame, name: string) => `g12:${name}:${f.cols}x${f.rows}:${f.cx}:${f.cy}:${f.u}`;
const cl = (x: number) => Math.min(1, Math.max(0, x));
const ez = (x: number) => 1 - Math.pow(1 - cl(x), 3);
const snapC = (v: number) => Math.floor(v) + 0.5;

/** filled disc, clipped above a line */
const disc = (cx: number, cy: number, r: number, clipY = Infinity): {x: number; y: number}[] => {
  const out: {x: number; y: number}[] = [];
  for (let y = snapC(cy - r); y <= cy + r; y++) {
    if (y >= clipY) break;
    for (let x = snapC(cx - r); x <= cx + r; x++) if (Math.hypot(x - cx, y - cy) <= r) out.push({x, y});
  }
  return out;
};
const ring = (cx: number, cy: number, rx: number, ry: number, n: number) => Array.from({length: n}, (_, k) => {
  const a = (k / n) * Math.PI * 2;
  return {x: cx + Math.cos(a) * rx, y: cy + Math.sin(a) * ry};
});
const seg = (x0: number, y0: number, x1: number, y1: number, step = 1) => {
  const n = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0) / step));
  return Array.from({length: n + 1}, (_, k) => ({x: x0 + ((x1 - x0) * k) / n, y: y0 + ((y1 - y0) * k) / n}));
};

// ================= Monday: the sun over a sea of cloud =================
export const sun = (f: Frame, t: number, h: number, o: {rays?: number; birds?: number; dim?: number} = {}): Tgt[] => {
  const u = f.u;
  const hy = f.cy + u * 0.8;
  const out: Tgt[] = [];
  const dim = o.dim ?? 1;
  const r = u * 0.85;
  const sy = hy + u * 0.4 - h * u * 1.9;
  // the sea of cloud: soft rolling rows below the horizon
  for (let row = 0; row < 4; row++) {
    const y = snapC(hy + 1 + row * u * 0.32);
    for (let x = 0.5; x < f.cols; x += row % 2 ? 2 : 1.5) {
      const wv = Math.sin(x * 0.35 + t * 0.4 + row * 1.7);
      out.push({x, y: y + wv * 0.35, b: (0.5 - row * 0.09 + wv * 0.08) * dim});
    }
  }
  for (const p of disc(f.cx, sy, r, hy + 0.5)) out.push({x: p.x, y: p.y, b: 1 * dim, c: Math.hypot(p.x - f.cx, p.y - sy) < 0.8 && (o.rays ?? 0) > 0.5 ? 1 : 0});
  const rays = o.rays ?? cl(h);
  for (let k = 0; k < 11; k++) {
    const a = Math.PI + (k + 0.5) * (Math.PI / 11);
    const len = u * (0.4 + 0.35 * (0.5 + 0.5 * Math.sin(t * 2 + k * 1.3))) * rays;
    for (let s = 0; s < 4; s++) {
      const rr = r + u * 0.3 + (s / 3) * len;
      const y = sy + Math.sin(a) * rr;
      if (y > hy - 0.5) continue;
      out.push({x: f.cx + Math.cos(a) * rr, y, b: (0.9 - s * 0.2) * rays * dim});
    }
  }
  for (let i = 0; i < (o.birds ?? 0); i++) {
    const x = ((hash(i, 41) * f.cols + t * (1.2 + hash(i, 42))) % (f.cols + 6)) - 3;
    const y = f.cy - u * 1.6 + hash(i, 43) * u * 0.8 + Math.sin(t * 2 + i) * 0.3;
    const fl = Math.sin(t * 9 + i * 2) > 0 ? 0.5 : 0;
    out.push({x: x - 1, y: y - fl, b: 0.8 * dim}, {x, y, b: 0.8 * dim}, {x: x + 1, y: y - fl, b: 0.8 * dim});
  }
  return out;
};

// ================= Tuesday: the rock =================
const CRACKS: [number, number][][] = [
  [[0, -1], [-0.15, -0.55], [0.1, -0.2], [-0.05, 0.25]],
  [[-0.7, -0.6], [-0.45, -0.25], [-0.55, 0.15], [-0.3, 0.6]],
  [[0.65, -0.65], [0.4, -0.3], [0.55, 0.05], [0.3, 0.5]],
  [[-0.05, 0.25], [-0.3, 0.55], [-0.15, 0.95]],
  [[0.1, -0.2], [0.35, 0.1], [0.2, 0.55], [0.35, 0.95]],
];
export const stone = (f: Frame, t: number, cracks: number, broken: number, o: {snow?: boolean; dim?: number; y?: number} = {}): Tgt[] => {
  const u = f.u;
  const dim = o.dim ?? 1;
  const cx = f.cx + u * 0.2, cy = f.cy + u * 0.25 + (o.y ?? 0), rx = u * 1.45, ry = u * 1.05;
  const ledge = f.cy + u * 1.3 + (o.y ?? 0);
  const out: Tgt[] = [];
  for (let x = 0.5; x < f.cols; x += 1) out.push({x, y: snapC(ledge) + (hash(Math.floor(x), 5) > 0.7 ? 0 : 0), b: (0.45 + 0.1 * hash(Math.floor(x), 6)) * dim});
  const body = raster(K(f, `stone${o.y ?? 0}`), f.cols, f.rows, (g) => {
    g.beginPath();
    g.moveTo(cx - rx, ledge - 0.2);
    g.bezierCurveTo(cx - rx * 1.05, cy - ry * 0.6, cx - rx * 0.5, cy - ry * 1.1, cx + rx * 0.05, cy - ry);
    g.bezierCurveTo(cx + rx * 0.7, cy - ry * 0.95, cx + rx * 1.1, cy - ry * 0.3, cx + rx, ledge - 0.2);
    g.closePath();
    g.fill();
  });
  // crack cells: the polylines of every crack drawn so far
  const crackSet = new Map<string, number>();
  const nC = Math.min(5, cracks);
  for (let k = 0; k < Math.ceil(nC); k++) {
    const P = CRACKS[k];
    const frac = Math.min(1, nC - k);
    const segs = P.length - 1;
    for (let i = 0; i < segs; i++) {
      const q = cl(frac * segs - i);
      if (q <= 0) break;
      const [ax, ay] = P[i], [bx, by] = P[i + 1];
      for (const p of seg(cx + ax * rx, cy + ay * ry, cx + (ax + (bx - ax) * q) * rx, cy + (ay + (by - ay) * q) * ry, 0.5)) crackSet.set(`${snapC(p.x)},${snapC(p.y)}`, k);
    }
  }
  const sep = ez(broken);
  for (const p of body) {
    const ck = crackSet.get(`${p.x},${p.y}`);
    const left = p.x < cx - (p.y - cy) * 0.08;
    let x = p.x, y = p.y;
    if (sep > 0) {
      const side = left ? -1 : 1;
      x += side * sep * u * 0.9 + side * Math.max(0, cy - p.y) * sep * 0.25;
      y += sep * Math.max(0, cy - p.y) * 0.12;
    }
    if (ck != null && sep === 0) out.push({x, y, b: 0.12 * dim, c: 0});
    else {
      const sh = 0.75 + 0.25 * cl((p.x - (cx - rx)) / (rx * 2));
      const snowCap = o.snow && p.y < cy - ry * 0.55;
      out.push({x, y, b: (snowCap ? 1 : sh) * dim, c: ck != null && ck === Math.ceil(nC) - 1 && sep > 0 && sep < 1 ? 1 : 0});
    }
  }
  // chips flying when it splits
  if (broken > 0 && broken < 1) {
    for (let i = 0; i < 18; i++) {
      const a = -Math.PI * (0.15 + hash(i, 61) * 0.7), sp = u * (0.8 + hash(i, 62) * 1.6);
      const k = broken;
      out.push({x: cx + Math.cos(a) * sp * k, y: cy - ry * 0.3 + Math.sin(a) * sp * k + k * k * u * 1.5, b: (1 - k) * dim, c: i < 3 ? 1 : 0});
    }
  }
  return out;
};

// ================= Wednesday: the lake =================
export const water = (f: Frame, t: number, o: {boat?: number | null; drip?: boolean; ripples?: number; skips?: number[]; skipN?: number; skipDone?: number | null; frozen?: boolean; dim?: number; moon?: boolean} = {}): Tgt[] => {
  const u = f.u;
  const dim = o.dim ?? 1;
  const bg = o.skips && o.skips.length ? 0.45 : 1; // quieter water so the skips read
  const wl = f.cy + u * 0.35;
  const out: Tgt[] = [];
  // the far shore: a low line of hills and its reflection
  for (let x = 0.5; x < f.cols; x += 1) {
    const hh = (Math.sin(x * 0.21 + 1) * 0.5 + 0.5) * u * 0.55 + (Math.sin(x * 0.53) * 0.5 + 0.5) * u * 0.2;
    out.push({x, y: snapC(wl - hh), b: 0.4 * dim * bg});
    if (Math.floor(x) % 2 === 0) out.push({x, y: snapC(wl + hh * 0.6), b: 0.14 * dim * bg});
  }
  // the water: dotted lines, shimmering (or still and white when frozen)
  for (let row = 0; row < 5; row++) {
    const y = snapC(wl + 1 + row * u * 0.32);
    for (let x = 0.5 + (row % 2); x < f.cols; x += 2) {
      const sh = o.frozen ? 0.62 : 0.3 + 0.22 * Math.sin(x * 0.6 - t * 1.6 + row * 2);
      out.push({x, y, b: sh * dim * bg});
    }
  }
  if (o.frozen)
    for (let i = 0; i < 4; i++) for (const p of seg(f.cx - u * 1.6 + i * u * 1.1, wl + 2, f.cx - u * 1.2 + i * u * 1.1, wl + u * 1.4, 0.8)) out.push({x: p.x, y: p.y, b: 0.95 * dim});
  if (o.moon) for (const p of disc(f.cx + u * 1.6, f.cy - u * 1.5, u * 0.5)) out.push({x: p.x, y: p.y, b: 0.95 * dim});
  // the boat
  if (o.boat != null) {
    const bx = f.cx - u * 1.9 + o.boat * u * 3.8, by = wl + u * 0.55 + Math.sin(t * 1.3) * 0.15;
    for (let k = -3; k <= 3; k++) out.push({x: bx + k * 0.7, y: by, b: 1 * dim});
    for (let k = -2; k <= 2; k++) out.push({x: bx + k * 0.7, y: by + 0.8, b: 1 * dim});
    out.push({x: bx, y: by - 1, b: 0.9 * dim}, {x: bx, y: by - 2, b: 0.9 * dim, c: 1});
  }
  // a drip from above: one drop a second, a ring where it lands
  if (o.drip) {
    const dx = f.cx + u * 1.2, y0 = f.cy - u * 2, pool = wl + u * 0.9;
    for (const p of seg(f.cols + 1, y0 - u * 0.5, dx, y0, 0.9)) out.push({x: p.x, y: p.y, b: 0.8 * dim});
    const ph = t % 1;
    const y = ph < 0.55 ? y0 + 0.8 : y0 + 0.8 + (pool - y0) * Math.pow((ph - 0.55) / 0.45, 2);
    out.push({x: dx, y, b: 1 * dim, c: 1});
    for (let k = 0; k < 2; k++) {
      const age = (t % 1) + k;
      const q = age / 2;
      for (const p of ring(dx, pool, u * 0.25 + q * u * 1.6, 0.3 + q * u * 0.3, 16)) out.push({x: p.x, y: p.y, b: 0.8 * (1 - q) * dim});
    }
  }
  // still rings, one per session this week
  for (let i = 0; i < (o.ripples ?? 0); i++) {
    const x = f.cx - u * 1.4 + i * u * 0.8, y = wl + u * (0.75 + (i % 2) * 0.35);
    const q = (t * 0.3 + i * 0.23) % 1;
    for (const p of ring(x, y, u * 0.2 + q * u * 0.5, 0.25 + q * u * 0.12, 10)) out.push({x: p.x, y: p.y, b: 0.75 * (1 - q) * dim});
  }
  // skipping: a ring at every touch, in order across the lake
  if (o.skips && o.skips.length) {
    const N = o.skipN ?? 7;
    const P = Array.from({length: N}, (_, i) => {
      const s = i / (N - 1);
      return {x: f.cx - u * 2 + s * u * 4, y: wl + u * (1.25 - Math.pow(s, 0.8) * 0.75), sc: 1 - s * 0.55};
    });
    o.skips.forEach((st, i) => {
      if (i >= N) return;
      const age = t - st;
      if (age < 0) return;
      const q = Math.min(1, age / 1.6);
      for (const p of ring(P[i].x, P[i].y, (u * 0.2 + q * u * 0.8) * P[i].sc, (0.3 + q * u * 0.2) * P[i].sc, 16)) out.push({x: p.x, y: p.y, b: (1 - q * 0.6) * dim});
      if (age < 0.3) for (let k = 0; k < 4; k++) out.push({x: P[i].x + (k - 1.5) * 0.7, y: P[i].y - age * 8 + Math.abs(k - 1.5) * 0.6, b: 1 * dim});
    });
    const n = o.skips.length, last = o.skips[n - 1];
    const fl = cl((t - last) / 0.4);
    if (o.skipDone == null && n < N && fl < 1) out.push({x: P[n - 1].x + (P[n].x - P[n - 1].x) * fl, y: P[n - 1].y + (P[n].y - P[n - 1].y) * fl - Math.sin(fl * Math.PI) * u * 0.4, b: 1, c: 1});
    if (o.skipDone != null) {
      const q = (t - o.skipDone) / 1.4;
      if (q > 0 && q < 1) for (const p of ring(P[N - 1].x, P[N - 1].y, u * 0.3 + q * u * 2.2, 0.4 + q * u * 0.5, 22)) out.push({x: p.x, y: p.y, b: 1 - q, c: q < 0.4 ? 1 : 0});
    }
  }
  return out;
};

// ================= Thursday: the pine =================
export const pine = (f: Frame, t: number, g: number, o: {fireflies?: number; snow?: boolean; dim?: number; burst?: number | null} = {}): Tgt[] => {
  const u = f.u;
  const dim = o.dim ?? 1;
  const gq = Math.round(cl(g) * 20) / 20;
  const gy = f.cy + u * 1.6;
  const H = u * 3.5 * (0.2 + 0.8 * gq);
  const tx = f.cx + u * 0.3;
  const out: Tgt[] = [];
  for (let x = 0.5; x < f.cols; x += 1) out.push({x, y: snapC(gy) + (Math.sin(x * 0.4) > 0.6 ? -1 : 0), b: 0.5 * dim});
  const tree = raster(K(f, `pine${gq}`), f.cols, f.rows, (c) => {
    c.fillRect(tx - u * 0.07, gy - H * 0.25, u * 0.14, H * 0.25);
    const tiers = 4;
    for (let k = 0; k < tiers; k++) {
      const top = gy - H + (k * H * 0.75) / tiers;
      const base = top + H * 0.42;
      const half = u * (0.45 + k * 0.22) * (0.35 + 0.65 * gq);
      c.beginPath();
      c.moveTo(tx, top);
      c.lineTo(tx + half, base);
      c.lineTo(tx - half, base);
      c.closePath();
      c.fill();
    }
  });
  const sway = Math.sin(t * 0.9) * 0.25;
  for (const p of tree) {
    const up = cl((gy - p.y) / H);
    out.push({x: p.x + sway * up * up, y: p.y, b: (o.snow && hash(Math.floor(p.x * 3 + p.y * 7), 3) > 0.6 ? 1 : 0.92) * dim, c: p.y < gy - H + 1.2 && Math.abs(p.x - tx) < 0.6 ? 1 : 0});
  }
  // background pines, small and faint
  for (const bx of [f.cx - u * 1.9, f.cx - u * 1.1, f.cx + u * 1.7]) {
    const hh = u * (0.9 + hash(Math.floor(bx), 7) * 0.6);
    for (let r = 0; r < hh; r++) {
      const half = (r / hh) * u * 0.32;
      for (let x = snapC(bx - half); x <= bx + half; x++) out.push({x, y: snapC(gy - hh + r), b: 0.3 * dim});
    }
  }
  for (let i = 0; i < (o.fireflies ?? 0); i++) {
    const x = f.cx - u * 2 + hash(i, 71) * u * 4.2 + Math.sin(t * 0.6 + i * 2) * 1.2;
    const y = f.cy - u * 0.6 + hash(i, 72) * u * 2 + Math.cos(t * 0.5 + i) * 0.8;
    const bl = Math.max(0, Math.sin(t * (1.6 + hash(i, 73)) + i * 3));
    out.push({x, y, b: bl, c: i === 0 && bl > 0.5 ? 1 : 0});
  }
  if (o.burst != null) {
    const age = t - o.burst;
    if (age >= 0 && age < 2.4)
      for (let i = 0; i < 16; i++) {
        const a = -Math.PI * (0.1 + hash(i, 74) * 0.8), sp = u * (1 + hash(i, 75) * 1.8);
        out.push({x: tx + Math.cos(a) * sp * age, y: gy - H + Math.sin(a) * sp * age * 0.7, b: Math.max(0, 1 - age / 2.4), c: i < 2 ? 1 : 0});
      }
  }
  return out;
};

/** Thursday's countdown: a candle burning down inside a lantern */
export const candle = (f: Frame, t: number, frac: number): Tgt[] => {
  const u = f.u;
  const out: Tgt[] = [];
  const top = f.cy - u * 1.5, bot = f.cy + u * 1.5, w = u * 0.95;
  const frame = raster(K(f, 'lantern'), f.cols, f.rows, (g) => {
    g.lineWidth = u * 0.15;
    g.strokeRect(f.cx - w, top, w * 2, bot - top);
    g.beginPath();
    g.moveTo(f.cx - w - u * 0.2, top);
    g.lineTo(f.cx + w + u * 0.2, top);
    g.moveTo(f.cx - w - u * 0.2, bot);
    g.lineTo(f.cx + w + u * 0.2, bot);
    g.stroke();
    g.beginPath();
    g.arc(f.cx, top - u * 0.35, u * 0.3, Math.PI, 0);
    g.stroke();
  });
  for (const p of frame) out.push({x: p.x, y: p.y, b: 0.55});
  const ch = (bot - top - u * 0.6) * (0.12 + 0.88 * cl(frac));
  const ctop = bot - 0.5 - ch;
  for (let y = snapC(ctop); y < bot - 0.5; y++) for (const dx of [-1, 0, 1]) out.push({x: f.cx + dx, y, b: 0.95});
  // drips of wax down the side
  out.push({x: f.cx + 1.6, y: snapC(ctop + 1), b: 0.6}, {x: f.cx + 1.6, y: snapC(ctop + 2), b: 0.4});
  const fl = Math.sin(t * 9) * 0.35 + Math.sin(t * 13.7) * 0.2;
  out.push({x: f.cx + fl * 0.5, y: ctop - 2.4, b: 0.9}, {x: f.cx + fl * 0.3, y: ctop - 1.5, b: 1, c: 1}, {x: f.cx, y: ctop - 0.8, b: 1, c: 1});
  // the glow
  for (let k = 0; k < 10; k++) {
    const a = (k / 10) * Math.PI * 2;
    const r = u * (0.55 + 0.08 * Math.sin(t * 5 + k));
    out.push({x: f.cx + Math.cos(a) * r, y: ctop - 1.5 + Math.sin(a) * r * 0.9, b: 0.3 + 0.15 * Math.sin(t * 7 + k)});
  }
  return out;
};

// ================= Friday: the summit =================
const ROUTE = (f: Frame) => {
  const u = f.u;
  const P: [number, number][] = [
    [f.cx - u * 2.2, f.cy + u * 1.7],
    [f.cx - u * 1.2, f.cy + u * 1.35],
    [f.cx - u * 0.4, f.cy + u * 1.5],
    [f.cx + u * 0.3, f.cy + u * 1.1],
    [f.cx - u * 0.35, f.cy + u * 0.55],
    [f.cx + u * 0.55, f.cy + u * 0.05],
    [f.cx - u * 0.05, f.cy - u * 0.5],
    [f.cx + u * 0.45, f.cy - u * 1.0],
    [f.cx + u * 0.2, f.cy - u * 1.55],
  ];
  const out: [number, number][] = [];
  for (let i = 0; i < P.length - 1; i++) for (const p of seg(P[i][0], P[i][1], P[i + 1][0], P[i + 1][1], 0.9).slice(i ? 1 : 0)) out.push([p.x, SY(f, p.y)]);
  return out;
};
/** the mountain sits a little low so the beacon's flame has sky above it */
const SY = (f: Frame, y: number) => f.cy + f.u * 0.3 + (y - f.cy) * 0.8;
export const summit = (f: Frame, t: number, p: number, beacon: number, o: {snow?: boolean; dim?: number; fog?: boolean} = {}): Tgt[] => {
  const u = f.u;
  const dim = o.dim ?? 1;
  const out: Tgt[] = [];
  const px = f.cx + u * 0.2, py = SY(f, f.cy - u * 1.75);
  const base = SY(f, f.cy + u * 1.75);
  const outline = raster(K(f, 'summit2'), f.cols, f.rows, (g) => {
    g.lineWidth = u * 0.13;
    g.beginPath();
    g.moveTo(f.cx - u * 2.8, base);
    g.lineTo(f.cx - u * 1.6, SY(f, f.cy + u * 0.3));
    g.lineTo(f.cx - u * 1.1, SY(f, f.cy + u * 0.7));
    g.lineTo(px, py);
    g.lineTo(f.cx + u * 1.5, SY(f, f.cy + u * 0.2));
    g.lineTo(f.cx + u * 1.9, SY(f, f.cy + u * 0.5));
    g.lineTo(f.cx + u * 2.9, base);
    g.stroke();
  });
  for (const q of outline) out.push({x: q.x, y: q.y, b: (o.snow && q.y < f.cy - u * 0.6 ? 1 : 0.55) * dim});
  if (o.snow) for (const q of disc(px, py + u * 0.35, u * 0.3)) out.push({x: q.x, y: q.y, b: 0.9 * dim});
  const R = ROUTE(f);
  R.forEach(([x, y], i) => {
    const s = i / (R.length - 1);
    if (i % 2 && s > p) return;
    out.push({x, y, b: (s <= p ? 0.95 : 0.25) * dim});
  });
  const k = cl(p) * (R.length - 1), i0 = Math.floor(k), fr = k - i0;
  const a = R[i0], b = R[Math.min(R.length - 1, i0 + 1)];
  const mx = a[0] + (b[0] - a[0]) * fr, my = a[1] + (b[1] - a[1]) * fr;
  const br = 0.5 + 0.5 * Math.sin(t * 5);
  if (beacon <= 0) {
    for (let j = 0; j < 6; j++) {
      const an = (j / 6) * Math.PI * 2 + t * 1.5;
      out.push({x: mx + Math.cos(an) * (0.9 + br * 0.5), y: my + Math.sin(an) * (0.9 + br * 0.5), b: 0.85 * dim});
    }
    out.push({x: mx, y: my, b: 1, c: 1});
  } else {
    const fh = u * (0.45 + 0.6 * ez(beacon));
    out.push(...flame(f, t, {h: fh, dx: px - f.cx, dy: py - f.cy - fh * 0.45}));
    for (let j = 0; j < Math.round(10 * beacon); j++) {
      const q = (t * (0.4 + hash(j, 81) * 0.4) + hash(j, 82)) % 1;
      out.push({x: px + Math.sin(q * 6 + j) * 1.5 * (1 + q), y: py - fh - q * u * 1.2, b: 1 - q});
    }
  }
  return out;
};

// ================= Saturday: the sea =================
export const sea = (f: Frame, t: number, o: {sun?: number; lanterns?: number[]; tide?: number | null; dim?: number; night?: boolean} = {}): Tgt[] => {
  const u = f.u;
  const dim = o.dim ?? 1;
  const hy = f.cy + u * 0.2;
  const out: Tgt[] = [];
  for (let x = 0.5; x < f.cols; x += 1) out.push({x, y: snapC(hy), b: 0.6 * dim});
  for (let row = 0; row < 4; row++) {
    const y = snapC(hy + 1.5 + row * u * 0.3);
    for (let x = 0.5 + (row % 2); x < f.cols; x += 2) out.push({x: x + Math.sin(t * 0.8 + row) * 0.4, y, b: (0.28 + 0.12 * Math.sin(x * 0.5 + t * 1.4 + row)) * dim});
  }
  const sh = o.sun ?? 0.2;
  const sx = f.cx + u * 0.9, sy = hy + u * 0.3 - sh * u * 1.6, r = u * 0.75;
  if (o.night) for (const p of disc(f.cx + u * 1.4, f.cy - u * 1.5, u * 0.45)) out.push({x: p.x, y: p.y, b: 0.9 * dim});
  if (!o.night) {
    for (const p of disc(sx, sy, r, hy)) out.push({x: p.x, y: p.y, b: 1 * dim});
    // its path on the water
    for (let k = 0; k < 6; k++) {
      const y = snapC(hy + 1 + k * 1.2);
      const half = r * (1 - k * 0.12);
      for (let x = snapC(sx - half); x <= sx + half; x += 1.4) out.push({x: x + Math.sin(t * 2 + k + x) * 0.3, y, b: (0.7 - k * 0.08) * dim});
    }
  }
  if (o.tide != null) {
    const sand0 = f.cy + u * 1.85;
    const flagY = f.cy + u * 1.1;
    const ty = sand0 - (sand0 - flagY - 1) * cl(o.tide);
    for (let x = 0.5; x < f.cols; x += 1) out.push({x, y: ty + Math.sin(x * 0.4 + t * 1.5) * 0.4, b: 0.85 * dim});
    const fx = f.cx - u * 0.6;
    for (let y = flagY; y > flagY - u * 1.1; y--) out.push({x: fx, y: snapC(y), b: 0.9 * dim});
    out.push({x: fx + 1, y: snapC(flagY - u * 1.1 + 1), b: 1, c: 1}, {x: fx + 2, y: snapC(flagY - u * 1.1 + 1.5), b: 1, c: 1}, {x: fx + 1, y: snapC(flagY - u * 1.1 + 2), b: 1, c: 1});
  }
  (o.lanterns ?? []).forEach((rt, i) => {
    const age = t - rt;
    if (age < 0) return;
    const rise = Math.min(1, age / 7);
    const x0 = f.cx - u * 1.6 + (i % 7) * u * 0.55;
    const x = x0 + Math.sin(age * 0.7 + i) * 1.2;
    const y = hy - 0.5 - (hy - f.cy + u * 2.1) * (1 - Math.pow(1 - rise, 1.5)) * (0.8 + hash(i, 91) * 0.25);
    const b = (1 - rise * 0.5) * (0.85 + 0.15 * Math.sin(t * 8 + i));
    out.push({x, y, b, c: 1}, {x: x - 0.8, y: y - 0.8, b: b * 0.85}, {x: x + 0.8, y: y - 0.8, b: b * 0.85}, {x, y: y - 1.4, b: b * 0.85});
  });
  return out;
};

// ================= Sunday: the stars =================
export const STARS = (f: Frame): [number, number][] => {
  const u = f.u;
  return [
    [-2.2, 0.7],
    [-1.4, -0.1],
    [-0.5, 0.35],
    [0.2, -0.9],
    [0.9, -0.1],
    [1.7, -1.3],
    [2.3, -0.2],
  ].map(([x, y]) => [f.cx + x * u, f.cy + y * u] as [number, number]);
};
export const stars = (f: Frame, t: number, lit: number, lines: number, o: {moon?: {x: number; y: number; phase: number} | null; shoot?: number | null; dim?: number; ridge?: boolean} = {}): Tgt[] => {
  const u = f.u;
  const dim = o.dim ?? 1;
  const out: Tgt[] = [];
  const P = STARS(f);
  // dust: faint background stars twinkling
  for (let i = 0; i < 18; i++) {
    const x = snapC(hash(i, 101) * f.cols), y = snapC(hash(i, 102) * (f.cy + u * 1.2));
    if (P.some(([px, py]) => Math.hypot(px - x, py - y) < 2)) continue;
    const tw = 0.5 + 0.5 * Math.sin(t * (1 + hash(i, 103) * 2) + i * 2.1);
    out.push({x, y, b: (0.12 + 0.35 * tw * tw) * dim});
  }
  // the lines between lit stars
  for (let i = 1; i < P.length; i++) {
    const show = Math.max(lines, cl(lit - i));
    if (show <= 0) continue;
    const [x0, y0] = P[i - 1], [x1, y1] = P[i];
    const pts = seg(x0, y0, x0 + (x1 - x0) * show, y0 + (y1 - y0) * show, 1.6).slice(1, -1);
    for (const p of pts) out.push({x: p.x, y: p.y, b: 0.42 * dim});
  }
  P.forEach(([x, y], i) => {
    const on = cl(lit - i);
    const tw = 0.85 + 0.15 * Math.sin(t * 3 + i);
    const coral = on > 0.99 && i === P.length - 1 ? 1 : 0;
    out.push({x, y, b: (on > 0 ? 1 : 0.5) * dim, c: coral});
    if (on <= 0) for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) out.push({x: x + dx, y: y + dy, b: 0.18 * dim});
    if (on > 0) {
      const arm = on * (1 + 0.3 * Math.sin(t * 4 + i));
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) out.push({x: x + dx * arm, y: y + dy * arm, b: 0.75 * tw * on * dim});
    }
  });
  if (o.moon) {
    const {x, y, phase} = o.moon;
    const r = u * 0.6;
    for (const p of disc(x, y, r)) {
      const lit2 = (p.x - x) / r > 1 - 2 * cl(phase);
      out.push({x: p.x, y: p.y, b: (lit2 ? 0.95 : 0.14) * dim});
    }
  }
  if (o.ridge !== false) {
    const gy = f.cy + u * 1.7;
    for (let x = 0.5; x < f.cols; x += 1) out.push({x, y: snapC(gy - (Math.sin(x * 0.18 + 2) * 0.5 + 0.5) * u * 0.5), b: 0.5 * dim});
  }
  if (o.shoot != null) {
    const q = (t - o.shoot) / 1;
    if (q >= 0 && q < 1) {
      const x0 = f.cx + u * 2.6, y0 = f.cy - u * 2, x1 = f.cx - u * 1.5, y1 = f.cy + u * 0.2;
      for (let k = 0; k < 6; k++) {
        const qq = q - k * 0.04;
        if (qq < 0) continue;
        out.push({x: x0 + (x1 - x0) * qq, y: y0 + (y1 - y0) * qq, b: (1 - k / 6) * (1 - q * 0.6), c: k === 0 ? 1 : 0});
      }
    }
  }
  return out;
};

// ================= weather =================
export const snow = (f: Frame, t: number, n = 26): Tgt[] => Array.from({length: n}, (_, i) => {
  const sp = 1.2 + hash(i, 111) * 1.5;
  return {x: ((hash(i, 112) * f.cols + Math.sin(t * 0.7 + i) * 1.5) % f.cols + f.cols) % f.cols, y: (hash(i, 113) * f.rows + t * sp) % f.rows, b: 0.5 + 0.4 * hash(i, 114)};
});
export const rain = (f: Frame, t: number, n = 22): Tgt[] => {
  const out: Tgt[] = [];
  for (let i = 0; i < n; i++) {
    const sp = 9 + hash(i, 121) * 5;
    const y = (hash(i, 122) * f.rows + t * sp) % f.rows;
    const x = (hash(i, 123) * f.cols + t * sp * 0.15) % f.cols;
    out.push({x, y, b: 0.5}, {x: x - 0.2, y: y - 1, b: 0.3});
  }
  return out;
};
/** fog: the scene dimmed, with drifting bands */
export const fog = (T: Tgt[], f: Frame, t: number, k = 0.45): Tgt[] => {
  const out: Tgt[] = T.map((p) => ({...p, b: p.b * k, c: 0}));
  for (let row = 0; row < 3; row++) {
    const y = snapC(f.cy - f.u * 0.6 + row * f.u * 0.9);
    for (let x = 0.5; x < f.cols; x += 1.5) {
      const v = Math.sin(x * 0.2 + t * 0.35 + row * 2);
      if (v > 0.1) out.push({x, y, b: 0.18 + 0.15 * v});
    }
  }
  return out;
};

// ================= the month as a calendar of dots (full-screen frame) =================
export const monthGrid = (f: Frame, t: number, lt: number, lead: number, cells: string[], target: number | null): Tgt[] => {
  const out: Tgt[] = [];
  const cw = 4, chh = 3.2;
  const rowsN = Math.ceil((lead + cells.length) / 7);
  const x0 = f.cx - (7 * cw) / 2 + 0.5, y0 = f.cy - (rowsN * chh) / 2;
  let doneSeen = 0;
  cells.forEach((c, i) => {
    const k = lead + i;
    const x = snapC(x0 + (k % 7) * cw), y = snapC(y0 + Math.floor(k / 7) * chh);
    const appear = cl((lt - 0.2 - i * 0.025) / 0.25);
    if (c === 'done') doneSeen++;
    const inTarget = target != null && c === 'future' && doneSeen + 1 + (cells.slice(0, i).filter((q) => q === 'future').length) <= target;
    let b = 0.14;
    if (c === 'done') b = 0.95;
    else if (c === 'miss') b = 0.3;
    else if (c === 'today') b = 1;
    else if (c === 'future') b = inTarget ? 0.38 + 0.12 * Math.sin(t * 3 - i * 0.3) : 0.14;
    const cor = c === 'today' ? 1 : 0;
    for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) out.push({x: x + dx, y: y + dy, b: b * appear, c: cor});
  });
  return out;
};
