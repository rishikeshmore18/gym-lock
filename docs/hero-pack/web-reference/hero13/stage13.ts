/**
 * The Dynamic stage: one description of what's on screen, drawn two ways.
 *
 * A scene is a list of shapes in stage units (x 0..100 across the panel, y 0..92 down it, so circles
 * stay round). Ridge paints them with watercolour-style soft strokes and washes over the painted
 * world; Matrix turns them into dot targets. Both modes therefore show the same objects, moving the
 * same way, at the same moments.
 *
 * The camera is part of the scene too: a push, a pan, a punch or a shake is applied to the shapes in
 * both modes, and to the painted backdrop in Ridge.
 */
import {Pal, Theme, css, mixc} from '../hero10/wash';
import type {Tgt} from '../hero4/dots';

export type Mat = 'ink' | 'mid' | 'mist' | 'light' | 'coral' | 'paper';
export type Shape =
  | {k: 'disc'; x: number; y: number; r: number; m: Mat; a?: number}
  | {k: 'ring'; x: number; y: number; r: number; ry?: number; m: Mat; a?: number; w?: number; a0?: number; a1?: number; dash?: number}
  | {k: 'line'; p: number[]; m: Mat; a?: number; w?: number; dash?: number}
  | {k: 'poly'; p: number[]; m: Mat; a?: number; soft?: boolean}
  | {k: 'dots'; p: number[]; r: number; m: Mat; a?: number}
  | {k: 'glow'; x: number; y: number; r: number; m: Mat; a?: number}
  | {k: 'flash'; a: number; m?: Mat};

export type Cam = {s: number; x: number; y: number; r: number; px?: number; py?: number};
export const CAM0: Cam = {s: 1, x: 0, y: 0, r: 0};

/** stage → card design units */
export const SX = (x: number) => 492 + x * 4.75;
export const SY = (y: number) => 26 + y * 4.75;
export const toStage = (X: number, Y: number): [number, number] => [(X - 492) / 4.75, (Y - 26) / 4.75];

// ---------- camera ----------
const camPt = (c: Cam, x: number, y: number): [number, number] => {
  const px = c.px ?? 55, py = c.py ?? 46;
  let dx = x - px, dy = y - py;
  if (c.r) {
    const cs = Math.cos(c.r), sn = Math.sin(c.r);
    [dx, dy] = [dx * cs - dy * sn, dx * sn + dy * cs];
  }
  return [px + dx * c.s + c.x, py + dy * c.s + c.y];
};
export const applyCam = (S: Shape[], c: Cam): Shape[] => {
  if (c.s === 1 && !c.x && !c.y && !c.r) return S;
  const P = (p: number[]) => {
    const o: number[] = [];
    for (let i = 0; i < p.length; i += 2) o.push(...camPt(c, p[i], p[i + 1]));
    return o;
  };
  return S.map((s) => {
    switch (s.k) {
      case 'disc':
      case 'glow': {
        const [x, y] = camPt(c, s.x, s.y);
        return {...s, x, y, r: s.r * c.s};
      }
      case 'ring': {
        const [x, y] = camPt(c, s.x, s.y);
        return {...s, x, y, r: s.r * c.s, ry: s.ry != null ? s.ry * c.s : undefined};
      }
      case 'line':
        return {...s, p: P(s.p), w: (s.w ?? 0.8) * c.s};
      case 'poly':
        return {...s, p: P(s.p)};
      case 'dots':
        return {...s, p: P(s.p), r: s.r * c.s};
      default:
        return s;
    }
  });
};
/** the same camera as a canvas transform (card design units → canvas pixels), for the painted backdrop */
export const camMatrix = (c: Cam, px: number): [number, number, number, number, number, number] => {
  const pxs = SX(c.px ?? 55), pys = SY(c.py ?? 46);
  const s = Math.max(1, c.s);
  const cs = Math.cos(c.r) * s, sn = Math.sin(c.r) * s;
  // X' = pxs + (X - pxs)·R·s + dx
  const tx = pxs - (pxs * cs - pys * sn) + c.x * 4.75;
  const ty = pys - (pxs * sn + pys * cs) + c.y * 4.75;
  return [cs, sn, -sn, cs, tx * px, ty * px];
};

// ---------- Ridge: paint the shapes ----------
const matRGB = (m: Mat, pal: Pal, theme: Theme): [number, number, number] => {
  switch (m) {
    case 'ink':
      return pal.near;
    case 'mid':
      return mixc(pal.mid2, pal.near, 0.35);
    case 'mist':
      return theme === 'light' ? mixc(pal.mid, pal.mist, 0.35) : pal.mist;
    case 'light':
      return pal.sun;
    case 'paper':
      return pal.paper;
    case 'coral':
      return [232, 93, 78];
  }
};
const matCol = (m: Mat, pal: Pal, theme: Theme) => matRGB(m, pal, theme);
const withA = (c: [number, number, number], a: number) => css(c, Math.max(0, Math.min(1, a)));

/** watercolour-ish: every stroke is a soft bleed plus a firmer core; every fill a wash with a darker rim */
export const paintShapes = (ctx: CanvasRenderingContext2D, S: Shape[], px: number, pal: Pal, theme: Theme, W: number, H: number) => {
  const k = 4.75 * px;
  const X = (x: number) => SX(x) * px, Y = (y: number) => SY(y) * px;
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (const s of S) {
    const a = s.a ?? 1;
    if (a <= 0.004) continue;
    if (s.k === 'flash') {
      ctx.fillStyle = withA(matCol(s.m ?? 'light', pal, theme), Math.min(0.7, a));
      ctx.fillRect(0, 0, W, H);
      continue;
    }
    const col = matCol(s.m, pal, theme);
    const lightish = s.m === 'light' || s.m === 'paper';
    // pale objects on pale paper get a soft darker bleed under them, like pigment pooling at the edge
    const under: [number, number, number] = mixc(pal.mid2, pal.near, 0.25);
    const needUnder = lightish && theme === 'light';
    if (s.k === 'glow') {
      if (!(s.r > 0.01)) continue;
      const g = ctx.createRadialGradient(X(s.x), Y(s.y), 0, X(s.x), Y(s.y), s.r * k);
      g.addColorStop(0, withA(col, a * 0.75));
      g.addColorStop(0.4, withA(col, a * 0.28));
      g.addColorStop(1, withA(col, 0));
      ctx.fillStyle = g;
      ctx.fillRect(X(s.x) - s.r * k, Y(s.y) - s.r * k, s.r * k * 2, s.r * k * 2);
      continue;
    }
    if (s.k === 'disc') {
      const r = Math.max(0.5, s.r * k * 1.3);
      if (needUnder) {
        ctx.fillStyle = withA(under, a * 0.22);
        ctx.beginPath();
        ctx.arc(X(s.x), Y(s.y), r * 1.5, 0, Math.PI * 2);
        ctx.fill();
      }
      if (lightish) {
        const g = ctx.createRadialGradient(X(s.x), Y(s.y), r * 0.6, X(s.x), Y(s.y), r * 2.6);
        g.addColorStop(0, withA(col, a * 0.35));
        g.addColorStop(1, withA(col, 0));
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(X(s.x), Y(s.y), r * 2.6, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.fillStyle = withA(col, a * 0.35);
      ctx.beginPath();
      ctx.arc(X(s.x), Y(s.y), r * 1.12, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = withA(col, a * 0.92);
      ctx.beginPath();
      ctx.arc(X(s.x), Y(s.y), r, 0, Math.PI * 2);
      ctx.fill();
      continue;
    }
    if (s.k === 'dots') {
      const r = Math.max(0.6, s.r * k * 1.45);
      if (needUnder) {
        ctx.fillStyle = withA(under, a * 0.2);
        ctx.beginPath();
        for (let i = 0; i < s.p.length; i += 2) {
          ctx.moveTo(X(s.p[i]) + r * 1.6, Y(s.p[i + 1]));
          ctx.arc(X(s.p[i]), Y(s.p[i + 1]), r * 1.6, 0, Math.PI * 2);
        }
        ctx.fill();
      }
      ctx.fillStyle = withA(col, a * 0.9);
      ctx.beginPath();
      for (let i = 0; i < s.p.length; i += 2) {
        ctx.moveTo(X(s.p[i]) + r, Y(s.p[i + 1]));
        ctx.arc(X(s.p[i]), Y(s.p[i + 1]), r, 0, Math.PI * 2);
      }
      ctx.fill();
      if (lightish) {
        ctx.fillStyle = withA(col, a * 0.18);
        ctx.beginPath();
        for (let i = 0; i < s.p.length; i += 2) {
          ctx.moveTo(X(s.p[i]) + r * 2.6, Y(s.p[i + 1]));
          ctx.arc(X(s.p[i]), Y(s.p[i + 1]), r * 2.6, 0, Math.PI * 2);
        }
        ctx.fill();
      }
      continue;
    }
    if (s.k === 'poly') {
      if (s.p.length < 6) continue;
      ctx.beginPath();
      ctx.moveTo(X(s.p[0]), Y(s.p[1]));
      for (let i = 2; i < s.p.length; i += 2) ctx.lineTo(X(s.p[i]), Y(s.p[i + 1]));
      ctx.closePath();
      if (s.soft) {
        // feathered wash: no rim, edges fade outward (fog, cloud, light wedges)
        for (const [lw, al] of [[3.2, 0.07], [1.8, 0.1], [0.8, 0.14]] as const) {
          ctx.strokeStyle = withA(col, a * al);
          ctx.lineWidth = lw * k;
          ctx.stroke();
        }
        ctx.fillStyle = withA(col, a * 0.62);
        ctx.fill();
        continue;
      }
      if (needUnder) {
        ctx.strokeStyle = withA(under, a * 0.3);
        ctx.lineWidth = Math.max(1.5, 1.2 * k);
        ctx.stroke();
      }
      ctx.fillStyle = withA(col, a * 0.88);
      ctx.fill();
      if (a > 0.45) {
        ctx.strokeStyle = withA(col, a * 0.35);
        ctx.lineWidth = Math.max(1, 0.45 * k);
        ctx.stroke();
      }
      continue;
    }
    // wide lines are beams of light or shadow: layered soft passes, no rim (a rim reads as a capsule)
    if (s.k === 'line' && (s.w ?? 0.8) >= 2.4 && s.p.length >= 4) {
      const bw = (s.w ?? 0.8) * k;
      ctx.beginPath();
      ctx.moveTo(X(s.p[0]), Y(s.p[1]));
      for (let i = 2; i < s.p.length; i += 2) ctx.lineTo(X(s.p[i]), Y(s.p[i + 1]));
      ctx.lineCap = 'butt';
      if (needUnder) {
        ctx.strokeStyle = withA(under, a * 0.06);
        ctx.lineWidth = bw * 1.25;
        ctx.stroke();
      }
      for (let i = 0; i < 6; i++) {
        ctx.strokeStyle = withA(col, a * 0.13);
        ctx.lineWidth = bw * (1 - i / 6.5);
        ctx.stroke();
      }
      ctx.lineCap = 'round';
      continue;
    }
    // strokes: ring and line
    const w = Math.max(0.8, (s.w ?? 0.8) * k * 1.6);
    ctx.beginPath();
    if (s.k === 'ring') ctx.ellipse(X(s.x), Y(s.y), Math.max(0.1, s.r * k), Math.max(0.1, (s.ry ?? s.r) * k), 0, s.a0 ?? 0, s.a1 ?? Math.PI * 2);
    else {
      ctx.moveTo(X(s.p[0]), Y(s.p[1]));
      for (let i = 2; i < s.p.length; i += 2) ctx.lineTo(X(s.p[i]), Y(s.p[i + 1]));
    }
    if (s.dash) ctx.setLineDash([s.dash * k, s.dash * k * 0.9]);
    if (needUnder) {
      ctx.strokeStyle = withA(under, a * 0.24);
      ctx.lineWidth = w * 2.6;
      ctx.stroke();
    }
    ctx.strokeStyle = withA(col, a * (lightish ? 0.22 : 0.25));
    ctx.lineWidth = w * (lightish ? 3.2 : 2.1);
    ctx.stroke();
    ctx.strokeStyle = withA(col, a * 0.95);
    ctx.lineWidth = w;
    ctx.stroke();
    if (s.dash) ctx.setLineDash([]);
  }
  ctx.restore();
};

// ---------- Matrix: shapes → dot targets ----------
const CELL = 100 / 38; // stage units per dot
const B: Record<Mat, number> = {ink: 1, mid: 0.6, mist: 0.32, light: 0.95, coral: 1, paper: 0.7};
export const toTargets = (S: Shape[], cap = 700): Tgt[] => {
  const out: Tgt[] = [];
  const push = (x: number, y: number, m: Mat, a: number) => {
    if (out.length >= cap) return;
    out.push({x: x / CELL, y: y / CELL, b: Math.min(1, B[m] * a), c: m === 'coral' ? 1 : 0});
  };
  const snap = (v: number) => (Math.floor(v / CELL) + 0.5) * CELL;
  const seg = (x0: number, y0: number, x1: number, y1: number, m: Mat, a: number, dash = 0) => {
    const n = Math.max(1, Math.round(Math.hypot(x1 - x0, y1 - y0) / CELL));
    for (let i = 0; i <= n; i++) {
      if (dash && Math.floor(i / Math.max(1, dash)) % 2) continue;
      push(x0 + ((x1 - x0) * i) / n, y0 + ((y1 - y0) * i) / n, m, a);
    }
  };
  for (const s of S) {
    const a = s.a ?? 1;
    if (a <= 0.04) continue;
    switch (s.k) {
      case 'disc': {
        if (s.r < CELL * 0.6) {
          push(s.x, s.y, s.m, a);
          break;
        }
        for (let y = snap(s.y - s.r); y <= s.y + s.r; y += CELL) for (let x = snap(s.x - s.r); x <= s.x + s.r; x += CELL) if (Math.hypot(x - s.x, y - s.y) <= s.r) push(x, y, s.m, a);
        break;
      }
      case 'ring': {
        const a0 = s.a0 ?? 0, a1 = s.a1 ?? Math.PI * 2;
        const ry = s.ry ?? s.r;
        const len = Math.abs(a1 - a0) * Math.max(s.r, ry);
        const n = Math.max(3, Math.round(len / CELL));
        for (let i = 0; i <= n; i++) {
          if (s.dash && i % 2) continue;
          const t = a0 + ((a1 - a0) * i) / n;
          push(s.x + Math.cos(t) * s.r, s.y + Math.sin(t) * ry, s.m, a);
        }
        break;
      }
      case 'line':
        for (let i = 2; i < s.p.length; i += 2) seg(s.p[i - 2], s.p[i - 1], s.p[i], s.p[i + 1], s.m, a, s.dash ? 1 : 0);
        break;
      case 'poly': {
        let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
        for (let i = 0; i < s.p.length; i += 2) {
          x0 = Math.min(x0, s.p[i]);
          x1 = Math.max(x1, s.p[i]);
          y0 = Math.min(y0, s.p[i + 1]);
          y1 = Math.max(y1, s.p[i + 1]);
        }
        for (let y = snap(y0); y <= y1; y += CELL)
          for (let x = snap(x0); x <= x1; x += CELL) {
            let inside = false;
            for (let i = 0, j = s.p.length - 2; i < s.p.length; j = i, i += 2) {
              const xi = s.p[i], yi = s.p[i + 1], xj = s.p[j], yj = s.p[j + 1];
              if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
            }
            if (inside) push(x, y, s.m, a);
          }
        break;
      }
      case 'dots':
        for (let i = 0; i < s.p.length; i += 2) push(s.p[i], s.p[i + 1], s.m, a);
        break;
      default:
        break;
    }
  }
  return out;
};
