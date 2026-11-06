/**
 * Ink-wash landscape painter (Canvas 2D). Realistic atmospheric perspective — far ranges pale and
 * misty, near ranges dark with lit faces — painted with soft washes, dry-brush ridges and grain.
 * Every layer is rendered once to an offscreen bitmap; animation only moves bitmaps, so it is cheap.
 */
import {LayerSpec, hash, litPath} from '../../src/done/geom';
import {drawBrush, paperTile, ridgePoints, ridgeStroke, InkPal} from '../../src/ink/core';

export const W = 1000;
export const H = 488;
export type Mode = 'calm' | 'bold';
export type Theme = 'light' | 'dark';

export type Look = {
  card: string;
  skyTop: string;
  skyBot: string;
  far: string;
  near: string;
  fog: string;
  lit: string;
  ink: string;
  ink2: string;
  ink3: string;
  border: string;
  sun: string;
  dark: boolean;
};

export const LOOKS: Record<'light' | 'dark' | 'night', Look> = {
  light: {card: '#FFFFFF', skyTop: '#E9E8E4', skyBot: '#FFFFFF', far: '#D3D2CD', near: '#1C1C1C', fog: '#FFFFFF', lit: '#FFFFFF', ink: '#1A1A1A', ink2: '#6B6B6B', ink3: '#9A9A9A', border: '#E8E8E8', sun: '#FFFFFF', dark: false},
  dark: {card: '#151517', skyTop: '#0E0E10', skyBot: '#26262A', far: '#47474C', near: '#060607', fog: '#1F1F23', lit: '#A6A6AC', ink: '#F2F2F0', ink2: '#A3A3A3', ink3: '#6E6E6E', border: 'rgba(255,255,255,.08)', sun: '#F4F4F0', dark: true},
  night: {card: '#111113', skyTop: '#0A0A0C', skyBot: '#2A2A2F', far: '#3B3B41', near: '#050506', fog: '#18181B', lit: '#8E8E95', ink: '#F2F2F0', ink2: 'rgba(242,242,240,.66)', ink3: 'rgba(242,242,240,.4)', border: 'rgba(255,255,255,.08)', sun: '#F2F2EE', dark: true},
};
export const CORAL = '#E85D4E';

const rgb = (h: string) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
export const mix = (a: string, b: string, t: number) => {
  const A = rgb(a), B = rgb(b);
  return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join('');
};
export const rgba = (h: string, a: number) => {
  const [r, g, b] = rgb(h);
  return `rgba(${r},${g},${b},${Math.max(0, Math.min(1, a)).toFixed(4)})`;
};
export const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
export const eo = (t: number) => 1 - Math.pow(1 - clamp01(t), 3);
export const eo5 = (t: number) => 1 - Math.pow(1 - clamp01(t), 5);
export const eio = (t: number) => {
  const x = clamp01(t);
  return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
};

export type Range = {spec: LayerSpec; depth: number; fog?: number; lit?: number; rim?: number};
/** bitmap of one painted range, covering x0..x1 (scene units) at `px` pixels per unit */
export type LayerBmp = {c: HTMLCanvasElement; x0: number; y0: number; px: number; depth: number};

const toInkPal = (hex: string): InkPal => {
  const [r, g, b] = rgb(hex);
  return {paper: '#ffffff', paper2: '#ffffff', ink: [r, g, b] as unknown as readonly [20, 20, 20], text: '', sub: '', hair: ''} as unknown as InkPal;
};

/** Paint a range into its own bitmap. sunX decides which faces catch the light. */
export const paintRange = (R: Range, look: Look, sunX: number, px: number, x0 = -380, x1 = W + 60, y0 = -40, y1 = H + 40): LayerBmp => {
  const c = document.createElement('canvas');
  c.width = Math.ceil((x1 - x0) * px);
  c.height = Math.ceil((y1 - y0) * px);
  const g = c.getContext('2d')!;
  g.setTransform(px, 0, 0, px, -x0 * px, -y0 * px);
  const pts = ridgePoints(R.spec, x0, x1, 3);
  let minY = Infinity;
  for (const p of pts) minY = Math.min(minY, p[1]);
  const tone = mix(look.far, look.near, Math.pow(R.depth, 1.35));
  const fogAmt = R.fog ?? (1 - R.depth) * 0.9;
  const depthPx = 90 + 260 * R.depth;
  const grad = g.createLinearGradient(0, minY, 0, minY + depthPx);
  grad.addColorStop(0, tone);
  grad.addColorStop(0.45, mix(tone, look.fog, fogAmt * 0.45));
  grad.addColorStop(1, mix(tone, look.fog, fogAmt));
  g.beginPath();
  g.moveTo(pts[0][0], y1 + 10);
  for (const p of pts) g.lineTo(p[0], p[1]);
  g.lineTo(pts[pts.length - 1][0], y1 + 10);
  g.closePath();
  g.fillStyle = grad;
  g.fill();
  // sunlit faces
  if (R.lit) {
    const lp = new Path2D(litPath(pts, sunX, R.spec.seed));
    const lg = g.createLinearGradient(0, minY, 0, minY + 150);
    const litCol = mix(tone, look.lit, R.lit * (look.dark ? 0.35 : 0.42));
    lg.addColorStop(0, rgba(litCol, 1));
    lg.addColorStop(1, rgba(litCol, 0));
    g.fillStyle = lg;
    g.fill(lp);
  }
  // dry-brush ridge: just enough texture to read as painted
  if (R.rim) {
    const rs = ridgeStroke(pts, {spec: R.spec, tone: 0.4, depth: 0, ridge: R.rim});
    drawBrush(g, rs, 1, {bristles: 7, dry: 0.8, seed: R.spec.seed, alpha: look.dark ? 0.5 : 0.55, core: 0.25, jitter: 0.9}, toInkPal(mix(tone, look.dark ? '#000000' : look.near, 0.35)));
  }
  // grain only where there is paint
  g.setTransform(1, 0, 0, 1, 0, 0);
  g.globalCompositeOperation = 'source-atop';
  g.globalAlpha = look.dark ? 0.06 : 0.1;
  g.fillStyle = g.createPattern(paperTile(look.dark ? 'dark' : 'light'), 'repeat')!;
  g.fillRect(0, 0, c.width, c.height);
  g.globalAlpha = 1;
  g.globalCompositeOperation = 'source-over';
  return {c, x0, y0, px, depth: R.depth};
};

/** draw a layer bitmap at an offset (scene units), current transform = scene units */
export const blit = (ctx: CanvasRenderingContext2D, L: LayerBmp, dx: number, dy: number, alpha = 1, flipY?: number) => {
  if (alpha <= 0) return;
  ctx.save();
  ctx.globalAlpha *= alpha;
  if (flipY != null) {
    ctx.translate(0, flipY * 2);
    ctx.scale(1, -1);
  }
  ctx.drawImage(L.c, L.x0 + dx, L.y0 + dy, L.c.width / L.px, L.c.height / L.px);
  ctx.restore();
};

export const sky = (ctx: CanvasRenderingContext2D, look: Look, yTop: number, yBot: number, x0 = 0, x1 = W, h = H) => {
  const g = ctx.createLinearGradient(0, yTop, 0, yBot);
  g.addColorStop(0, look.skyTop);
  g.addColorStop(1, look.skyBot);
  ctx.fillStyle = g;
  ctx.fillRect(x0 - 400, -3000, x1 - x0 + 800, h + 6000);
};

const sprites: Record<string, HTMLCanvasElement> = {};
/** radial falloff sprite, made once per colour; scaling a bitmap is far cheaper than new gradients */
const sprite = (color: string, kind: 'glow' | 'puff') => {
  const key = color + kind;
  if (sprites[key]) return sprites[key];
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d')!;
  const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  if (kind === 'glow') {
    gr.addColorStop(0, rgba(color, 1));
    gr.addColorStop(0.35, rgba(color, 0.45));
    gr.addColorStop(1, rgba(color, 0));
  } else {
    gr.addColorStop(0, rgba(color, 1));
    gr.addColorStop(0.55, rgba(color, 0.55));
    gr.addColorStop(1, rgba(color, 0));
  }
  g.fillStyle = gr;
  g.fillRect(0, 0, 128, 128);
  sprites[key] = c;
  return c;
};

export const glow = (ctx: CanvasRenderingContext2D, x: number, y: number, r: number, color: string, a: number) => {
  if (a <= 0) return;
  ctx.save();
  ctx.globalAlpha *= Math.min(1, a);
  ctx.drawImage(sprite(color, 'glow'), x - r, y - r, r * 2, r * 2);
  if (a > 1) {
    ctx.globalAlpha = Math.min(1, a - 1);
    ctx.drawImage(sprite(color, 'glow'), x - r, y - r, r * 2, r * 2);
  }
  ctx.restore();
};

/** soft horizontal mist bank of overlapping puffs, drifting */
export const mist = (ctx: CanvasRenderingContext2D, color: string, x0: number, x1: number, y: number, h: number, t: number, seed: number, speed: number, alpha: number, n = 7) => {
  if (alpha <= 0) return;
  const span = x1 - x0 + 700;
  const sp = sprite(color, 'puff');
  ctx.save();
  ctx.globalAlpha *= Math.min(1, alpha);
  for (let j = 0; j < n; j++) {
    const rx = 160 + hash(j, seed) * 240;
    const base = (span * (j + hash(j, seed + 1) * 0.7)) / n;
    const x = x0 - 350 + ((((base + t * speed * (0.7 + hash(j, seed + 4) * 0.6)) % span) + span) % span);
    const yy = y + (hash(j, seed + 2) - 0.5) * h * 0.5;
    const ry = h * (0.32 + hash(j, seed + 3) * 0.3);
    ctx.drawImage(sp, x - rx, yy - ry, rx * 2, ry * 2);
  }
  ctx.restore();
};

/** distant birds: two tapered wing strokes each */
export const birds = (ctx: CanvasRenderingContext2D, color: string, x: number, y: number, n: number, t: number, s = 1, alpha = 0.8, seed = 1) => {
  ctx.save();
  ctx.strokeStyle = rgba(color, alpha);
  ctx.lineCap = 'round';
  for (let i = 0; i < n; i++) {
    const bx = x + i * 22 * s + hash(i, seed) * 14 * s, by = y + (hash(i, seed + 1) - 0.5) * 18 * s;
    const f = Math.sin(t * 0.32 + i * 1.7);
    const w = (6 + hash(i, seed + 2) * 3) * s;
    ctx.lineWidth = 1.3 * s;
    ctx.beginPath();
    ctx.moveTo(bx - w, by - f * w * 0.5);
    ctx.quadraticCurveTo(bx - w * 0.4, by - w * 0.25 - f * w * 0.25, bx, by);
    ctx.quadraticCurveTo(bx + w * 0.4, by - w * 0.25 - f * w * 0.25, bx + w, by - f * w * 0.5);
    ctx.stroke();
  }
  ctx.restore();
};

/** a river stone with soft light from the upper left */
export const stone = (ctx: CanvasRenderingContext2D, look: Look, cx: number, cy: number, rx: number, ry: number, seed: number, ghost: number) => {
  const pathOf = () => {
    ctx.beginPath();
    for (let i = 0; i <= 36; i++) {
      const a = (i / 36) * Math.PI * 2;
      const k = 1 + (hash(i % 36, seed) - 0.5) * 0.06 + 0.05 * Math.sin(a * 2 + seed);
      const flat = Math.sin(a) > 0 ? 0.88 : 1; // flatter underside so it sits
      const x = cx + Math.cos(a) * rx * k, y = cy + Math.sin(a) * ry * k * flat;
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
    ctx.closePath();
  };
  // ghost: the stone that is not there yet
  if (ghost > 0) {
    pathOf();
    ctx.fillStyle = rgba(look.ink, 0.045 * ghost);
    ctx.fill();
    ctx.setLineDash([2, 5]);
    ctx.lineWidth = 1.4;
    ctx.strokeStyle = rgba(look.ink, 0.28 * ghost);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  const solid = 1 - ghost;
  if (solid <= 0) return;
  ctx.save();
  ctx.globalAlpha *= solid;
  // contact shadow
  const sg = ctx.createRadialGradient(cx, cy + ry * 0.85, 0, cx, cy + ry * 0.85, rx * 1.1);
  sg.addColorStop(0, rgba('#000000', look.dark ? 0.5 : 0.22));
  sg.addColorStop(1, rgba('#000000', 0));
  ctx.fillStyle = sg;
  ctx.save();
  ctx.translate(cx, cy + ry * 0.85);
  ctx.scale(1, 0.28);
  ctx.beginPath();
  ctx.arc(0, 0, rx * 1.1, 0, Math.PI * 2);
  ctx.restore();
  ctx.fill();
  pathOf();
  const base = look.dark ? '#5C5C61' : '#3A3936';
  const g = ctx.createRadialGradient(cx - rx * 0.35, cy - ry * 0.55, rx * 0.05, cx, cy, rx * 1.15);
  g.addColorStop(0, mix(base, '#FFFFFF', look.dark ? 0.35 : 0.42));
  g.addColorStop(0.55, base);
  g.addColorStop(1, mix(base, '#000000', 0.55));
  ctx.fillStyle = g;
  ctx.fill();
  ctx.clip();
  ctx.globalAlpha *= look.dark ? 0.1 : 0.16;
  ctx.globalCompositeOperation = 'overlay';
  ctx.fillStyle = ctx.createPattern(paperTile('light'), 'repeat')!;
  ctx.fillRect(cx - rx, cy - ry, rx * 2, ry * 2);
  ctx.restore();
};
