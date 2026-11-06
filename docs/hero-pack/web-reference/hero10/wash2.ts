/**
 * Ridge, more scenes: the same black and white watercolour language, a different place for each moment.
 *   ridge     the ledge, the pine, the boulder (the session's rock)
 *   hourglass sand running out before gym time
 *   night     a moon over still water, filling like a battery while you sleep
 *   beach     two palms and an empty hammock: the streak is frozen, rest
 *   sunrise   a sun coming up over a sea of clouds
 *   path      a winding path into the hills and up the mountain
 *   fog       pines receding into fog
 *   lake      a mountain lake, a moored boat, still water
 *   sunset    the sun low over the sea, the day running out
 *   cairn     stones stacked on the ledge: this week's sessions
 * Water shimmers, sand falls, the hammock sways, birds cross, every frame.
 */
import {
  Layout, Painter, Pal, Pt, R, RGB, Scene, Theme,
  css, deform, fbm1, fillPoly, grain, granulate, layoutFor, mixc, paintFar, paintMist, paintPine, palette, ridgePts, rng, trees, wash,
} from './wash';

export type Kind = 'ridge' | 'hourglass' | 'night' | 'beach' | 'sunrise' | 'path' | 'fog' | 'lake' | 'sunset' | 'cairn';
export type Scene2 = Scene & {kind: Kind; noYou?: boolean; hgBg?: Kind; prop?: 'hourglass' | 'lantern' | 'none'; candle?: number; moonX?: number; moonY?: number; boatX?: number; sand?: number; charge?: number; stones?: number; trail?: number; birds?: number; chipsAt?: number | null};

const mk = (w: number, h: number) => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
};

// ---------- shared pieces ----------
const skyGrad = (ctx: CanvasRenderingContext2D, w: number, h: number, horizon: number, pal: Pal) => {
  const g = ctx.createLinearGradient(0, 0, 0, horizon);
  g.addColorStop(0, css(pal.sky0));
  g.addColorStop(1, css(pal.sky1));
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
};
const clouds = (ctx: CanvasRenderingContext2D, w: number, h: number, top: number, pal: Pal, r: R, n = 6) => {
  for (let i = 0; i < n; i++) {
    const cy = top * (0.15 + r() * 0.7), cx = w * (0.3 + r() * 0.8), cw = w * (0.12 + r() * 0.25), ch = h * (0.012 + r() * 0.02);
    const pts: Pt[] = [];
    for (let k = 0; k < 14; k++) {
      const a = (k / 14) * Math.PI * 2;
      pts.push([cx + Math.cos(a) * cw * (0.8 + r() * 0.3), cy + Math.sin(a) * ch * (0.7 + r() * 0.5)]);
    }
    wash(ctx, pts, mixc(pal.sky1, pal.sun, 0.35), r, {body: 0.3, layers: 6, a: 0.05, v: 0.05, edge: 0});
  }
};
const sunDisc = (ctx: CanvasRenderingContext2D, x: number, y: number, rad: number, pal: Pal, glow: number) => {
  const g = ctx.createRadialGradient(x, y, 0, x, y, rad * 7);
  g.addColorStop(0, css(pal.sun, 0.6 * glow));
  g.addColorStop(1, css(pal.sun, 0));
  ctx.fillStyle = g;
  ctx.fillRect(x - rad * 7, y - rad * 7, rad * 14, rad * 14);
  ctx.fillStyle = css(pal.sun, 0.95);
  ctx.beginPath();
  ctx.arc(x, y, rad, 0, Math.PI * 2);
  ctx.fill();
};
/** a still-water reflection of everything above the waterline, rippling */
const reflect = (ctx: CanvasRenderingContext2D, src: HTMLCanvasElement, w: number, h: number, wl: number, t: number, pal: Pal, dark: number) => {
  const step = Math.max(2, Math.round(h / 220));
  for (let y = wl; y < h; y += step) {
    const d = y - wl;
    const sy = wl - d * 1.05 - step;
    if (sy < 0) break;
    const amp = (1.2 + d * 0.035) * (w / 1000);
    const off = Math.sin(y * 0.09 + t * 1.6) * amp + Math.sin(y * 0.031 - t * 0.9) * amp * 1.6;
    ctx.drawImage(src, 0, sy, w, step, off, y, w, step);
  }
  const g = ctx.createLinearGradient(0, wl, 0, h);
  g.addColorStop(0, css(pal.mid2, 0.18 + dark * 0.2));
  g.addColorStop(1, css(pal.near, 0.55 + dark * 0.2));
  ctx.fillStyle = g;
  ctx.fillRect(0, wl, w, h - wl);
  // a few light ripple lines
  ctx.strokeStyle = css(pal.mist, 0.18);
  ctx.lineWidth = Math.max(1, w / 900);
  const r = rng(41);
  ctx.beginPath();
  for (let i = 0; i < 26; i++) {
    const y = wl + Math.pow(r(), 1.4) * (h - wl), x = r() * w, l = w * (0.03 + r() * 0.08) * (1 + (y - wl) / (h - wl));
    const ox = Math.sin(t * 0.7 + i) * w * 0.006;
    ctx.moveTo(x + ox, y);
    ctx.lineTo(x + l + ox, y);
  }
  ctx.stroke();
};
/** a column of glitter on the water under a light */
const glitter = (ctx: CanvasRenderingContext2D, x: number, wl: number, h: number, w: number, t: number, pal: Pal, k: number) => {
  const r = rng(77);
  for (let i = 0; i < 90; i++) {
    const u = Math.pow(r(), 0.9);
    const y = wl + 2 + u * (h - wl) * 0.9;
    const spread = w * (0.012 + u * 0.06);
    const xx = x + (r() - 0.5) * spread * 2;
    const tw = 0.5 + 0.5 * Math.sin(t * (2 + r() * 3) + i);
    ctx.fillStyle = css(pal.sun, 0.55 * tw * k * (1 - u * 0.6));
    ctx.fillRect(xx, y, w * (0.006 + r() * 0.018) * (1 + u), Math.max(1, h * 0.003));
  }
};
const birds = (ctx: CanvasRenderingContext2D, w: number, h: number, t: number, pal: Pal, n: number, top: number) => {
  ctx.strokeStyle = css(pal.near, 0.75);
  ctx.lineWidth = Math.max(1, w / 700);
  ctx.lineCap = 'round';
  for (let i = 0; i < n; i++) {
    const sp = 0.012 + (i % 3) * 0.004;
    const x = ((0.35 + i * 0.07 + t * sp) % 1.1) * w;
    const y = top * (0.35 + 0.18 * Math.sin(i * 2.3)) + Math.sin(t * 0.8 + i) * h * 0.01;
    const s = h * (0.012 + (i % 2) * 0.004);
    const flap = Math.sin(t * 6 + i * 1.7) * 0.5;
    ctx.beginPath();
    ctx.moveTo(x - s, y - s * (0.3 + flap * 0.4));
    ctx.quadraticCurveTo(x - s * 0.4, y - s * 0.1, x, y);
    ctx.quadraticCurveTo(x + s * 0.4, y - s * 0.1, x + s, y - s * (0.3 + flap * 0.4));
    ctx.stroke();
  }
};
const shoreline = (ctx: CanvasRenderingContext2D, w: number, h: number, y0: number, pal: Pal, r: R, fromRight: boolean, reach: number, seed: number) => {
  // a dark rocky shore with pines, entering from one side
  const pts: Pt[] = [];
  const x0 = fromRight ? w * (1 - reach) : -0.02 * w, x1 = fromRight ? 1.02 * w : w * reach;
  for (let i = 0; i <= 60; i++) {
    const u = i / 60, x = x0 + (x1 - x0) * u;
    const edge = fromRight ? u : 1 - u;
    pts.push([x, y0 - Math.pow(edge, 0.6) * h * 0.06 - (fbm1(x / (w * 0.03) + seed, 4, true) - 0.5) * h * 0.02]);
  }
  wash(ctx, [...pts, [x1, h], [x0, h]], pal.near, r, {body: 0.95, layers: 6, a: 0.06, v: 0.004, edge: 0.2});
  const tH = h * 0.16;
  ctx.fillStyle = css(pal.near);
  for (let k = 0; k < 9; k++) {
    const u = 0.15 + r() * 0.8;
    const x = x0 + (x1 - x0) * (fromRight ? u : 1 - u);
    const i = Math.round(u * 60);
    const by = pts[Math.min(60, Math.max(0, fromRight ? i : 60 - i))][1];
    const th = tH * (0.5 + r() * 0.8) * (0.6 + u * 0.6);
    const tw = th * 0.18;
    ctx.beginPath();
    ctx.moveTo(x, by - th);
    for (let q = 1; q <= 5; q++) {
      ctx.lineTo(x + tw * (q / 5) * (1 + r() * 0.4), by - th + (th * q) / 5.4);
      ctx.lineTo(x + tw * (q / 5) * 0.4, by - th + (th * q) / 5.4 - th * 0.03);
    }
    ctx.lineTo(x + tw * 0.12, by + 2);
    ctx.lineTo(x - tw * 0.12, by + 2);
    for (let q = 5; q >= 1; q--) {
      ctx.lineTo(x - tw * (q / 5) * 0.4, by - th + (th * q) / 5.4 - th * 0.03);
      ctx.lineTo(x - tw * (q / 5) * (1 + r() * 0.4), by - th + (th * q) / 5.4);
    }
    ctx.closePath();
    ctx.fill();
  }
  return pts;
};

/** a spruce: many drooping tiers with ragged edges */
const spruce = (c: CanvasRenderingContext2D, x: number, by: number, th: number, col: RGB, r: R) => {
  const tiers = 9;
  const tw = th * (0.2 + r() * 0.05);
  c.fillStyle = css(col);
  c.beginPath();
  c.moveTo(x, by - th);
  for (let k = 1; k <= tiers; k++) {
    const u = k / tiers;
    const y = by - th + th * u * 0.92;
    c.lineTo(x + tw * u * (0.9 + r() * 0.35), y + th * 0.02);
    c.lineTo(x + tw * u * 0.72, y - th * 0.012);
  }
  c.lineTo(x + th * 0.012, by);
  c.lineTo(x - th * 0.012, by);
  for (let k = tiers; k >= 1; k--) {
    const u = k / tiers;
    const y = by - th + th * u * 0.92;
    c.lineTo(x - tw * u * 0.72, y - th * 0.012);
    c.lineTo(x - tw * u * (0.9 + r() * 0.35), y + th * 0.02);
  }
  c.closePath();
  c.fill();
};

// ---------- the moon that fills like a battery ----------
const moonPhase = (ctx: CanvasRenderingContext2D, x: number, y: number, rad: number, p: number, lit: RGB, darkC: RGB) => {
  const g = ctx.createRadialGradient(x, y, rad * 0.8, x, y, rad * (3 + 3 * p));
  g.addColorStop(0, css(lit, 0.28 * (0.3 + p)));
  g.addColorStop(1, css(lit, 0));
  ctx.fillStyle = g;
  ctx.fillRect(x - rad * 7, y - rad * 7, rad * 14, rad * 14);
  ctx.fillStyle = css(darkC);
  ctx.beginPath();
  ctx.arc(x, y, rad, 0, Math.PI * 2);
  ctx.fill();
  // lit right half, then the terminator ellipse either eats into it or extends it
  ctx.fillStyle = css(lit);
  ctx.beginPath();
  ctx.arc(x, y, rad, -Math.PI / 2, Math.PI / 2);
  ctx.closePath();
  ctx.fill();
  const rx = Math.abs(1 - 2 * p) * rad;
  ctx.fillStyle = css(p < 0.5 ? darkC : lit);
  ctx.beginPath();
  ctx.ellipse(x, y, Math.max(0.01, rx), rad, 0, -Math.PI / 2, Math.PI / 2, p >= 0.5);
  ctx.closePath();
  ctx.fill();
  // maria: soft darker blotches on the lit part
  ctx.save();
  ctx.beginPath();
  ctx.arc(x, y, rad, 0, Math.PI * 2);
  ctx.clip();
  const r = rng(5);
  for (let i = 0; i < 6; i++) {
    ctx.fillStyle = css(mixc(lit, darkC, 0.25), 0.35);
    ctx.beginPath();
    ctx.ellipse(x + (r() - 0.4) * rad, y + (r() - 0.5) * rad, rad * (0.12 + r() * 0.2), rad * (0.1 + r() * 0.15), r() * 3, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.restore();
};

// ---------- palms and a hammock ----------
const palm = (ctx: CanvasRenderingContext2D, bx: number, by: number, H: number, lean: number, c: RGB, r: R, scale: number): Pt => {
  const top: Pt = [bx + lean * H, by - H];
  const cp: Pt = [bx + lean * H * 0.15, by - H * 0.55];
  const tw = H * 0.028;
  const left: Pt[] = [], right: Pt[] = [];
  const at = (u: number): Pt => [(1 - u) * (1 - u) * bx + 2 * (1 - u) * u * cp[0] + u * u * top[0], (1 - u) * (1 - u) * by + 2 * (1 - u) * u * cp[1] + u * u * top[1]];
  for (let i = 0; i <= 24; i++) {
    const u = i / 24, p = at(u), wd = tw * (1.15 - u * 0.5);
    left.push([p[0] - wd, p[1]]);
    right.push([p[0] + wd, p[1]]);
  }
  ctx.fillStyle = css(c);
  fillPoly(ctx, [...left, ...right.reverse()]);
  // growth rings
  ctx.strokeStyle = css(mixc(c, [255, 255, 255], 0.25), 0.5);
  ctx.lineWidth = Math.max(0.6, scale * 0.8);
  for (let i = 1; i < 24; i += 1) {
    const p = at(i / 24), wd = tw * (1.15 - (i / 24) * 0.5);
    ctx.beginPath();
    ctx.moveTo(p[0] - wd, p[1] + 1);
    ctx.lineTo(p[0] + wd, p[1] - 1);
    ctx.stroke();
  }
  // fronds: a spine with leaflets swept back and drooping
  const fronds = 11;
  for (let i = 0; i < fronds; i++) {
    const a = -Math.PI / 2 + ((i / (fronds - 1)) - 0.5) * Math.PI * 1.9 + (r() - 0.5) * 0.2;
    const L = H * (0.32 + r() * 0.14) * (Math.abs(Math.cos(a)) * 0.4 + 0.75);
    const ex = top[0] + Math.cos(a) * L, ey = top[1] + Math.sin(a) * L * 0.55 + L * 0.35;
    const mx = top[0] + Math.cos(a) * L * 0.5, my = top[1] + Math.sin(a) * L * 0.5 - L * 0.05;
    ctx.strokeStyle = css(c);
    ctx.lineWidth = Math.max(1, tw * 0.35);
    ctx.beginPath();
    ctx.moveTo(top[0], top[1]);
    ctx.quadraticCurveTo(mx, my, ex, ey);
    ctx.stroke();
    ctx.lineWidth = Math.max(1, tw * 0.3);
    ctx.beginPath();
    for (let k = 2; k <= 22; k++) {
      const u = k / 22;
      const px = (1 - u) * (1 - u) * top[0] + 2 * (1 - u) * u * mx + u * u * ex;
      const py = (1 - u) * (1 - u) * top[1] + 2 * (1 - u) * u * my + u * u * ey;
      const ll = L * 0.26 * Math.sin(u * Math.PI * 0.85 + 0.25);
      for (const side of [-1, 1]) {
        const la = a + side * 0.9;
        ctx.moveTo(px, py);
        ctx.quadraticCurveTo(px + Math.cos(la) * ll * 0.45, py + Math.sin(la) * ll * 0.3, px + Math.cos(la) * ll * 0.6, py + ll * 0.75);
      }
    }
    ctx.stroke();
  }
  // coconuts
  ctx.fillStyle = css(c);
  for (let k = 0; k < 3; k++) {
    ctx.beginPath();
    ctx.arc(top[0] + (k - 1) * tw * 1.3, top[1] + tw * 1.4, tw * 0.9, 0, Math.PI * 2);
    ctx.fill();
  }
  return at(0.55);
};
const hammock = (ctx: CanvasRenderingContext2D, a: Pt, b: Pt, sag: number, sway: number, c: RGB, fabric: RGB, lw: number) => {
  const mid: Pt = [(a[0] + b[0]) / 2 + sway, (a[1] + b[1]) / 2 + sag];
  const pa: Pt = [a[0] + (b[0] - a[0]) * 0.14, a[1] + sag * 0.35], pb: Pt = [b[0] - (b[0] - a[0]) * 0.14, b[1] + sag * 0.35];
  ctx.strokeStyle = css(c);
  ctx.lineWidth = lw * 0.6;
  for (const k of [-1, 0, 1]) {
    ctx.beginPath();
    ctx.moveTo(a[0], a[1]);
    ctx.lineTo(pa[0], pa[1] + k * sag * 0.08);
    ctx.moveTo(b[0], b[1]);
    ctx.lineTo(pb[0], pb[1] + k * sag * 0.08);
    ctx.stroke();
  }
  // the bed: top edge and a deeper bottom edge
  ctx.fillStyle = css(fabric);
  ctx.beginPath();
  ctx.moveTo(pa[0], pa[1]);
  ctx.quadraticCurveTo(mid[0], mid[1] + sag * 0.6, pb[0], pb[1]);
  ctx.quadraticCurveTo(mid[0], mid[1] + sag * 1.5, pa[0], pa[1] + sag * 0.06);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = css(c, 0.7);
  ctx.lineWidth = lw * 0.45;
  for (let k = 1; k < 7; k++) {
    const u = k / 7;
    const x0 = pa[0] + (pb[0] - pa[0]) * u;
    ctx.beginPath();
    ctx.moveTo(x0, pa[1] + (pb[1] - pa[1]) * u + Math.sin(u * Math.PI) * sag * 0.6);
    ctx.lineTo(x0 + sway * 0.1, pa[1] + (pb[1] - pa[1]) * u + Math.sin(u * Math.PI) * sag * 1.42);
    ctx.stroke();
  }
};

// ---------- hourglass ----------
const hourglass = (ctx: CanvasRenderingContext2D, cx: number, by: number, Hh: number, sand: number, t: number, pal: Pal, theme: Theme) => {
  const W = Hh * 0.42, plate = Hh * 0.07;
  const top = by - Hh, gTop = top + plate, gBot = by - plate, neck = (gTop + gBot) / 2;
  const bw = W * 0.4, nk = W * 0.035;
  const wood = pal.near, glassEdge = mixc(pal.mid, pal.near, 0.3);
  const sandC = theme === 'light' ? mixc(pal.rock, pal.rockLight, 0.55) : mixc(pal.rock, pal.rockLight, 0.7);
  // shadow
  const sh = ctx.createRadialGradient(cx, by, 0, cx, by, W * 0.8);
  sh.addColorStop(0, css(pal.near, 0.5));
  sh.addColorStop(1, css(pal.near, 0));
  ctx.save();
  ctx.translate(cx, by);
  ctx.scale(1, 0.12);
  ctx.translate(-cx, -by);
  ctx.fillStyle = sh;
  ctx.beginPath();
  ctx.arc(cx, by, W * 0.8, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  const bulb = (upper: boolean) => {
    const y0 = upper ? gTop : gBot, y1 = neck;
    const p = new Path2D();
    p.moveTo(cx - bw, y0);
    p.bezierCurveTo(cx - bw * 1.05, y0 + (y1 - y0) * 0.55, cx - nk * 2.5, y1 - (y1 - y0) * 0.12, cx - nk, y1);
    p.lineTo(cx + nk, y1);
    p.bezierCurveTo(cx + nk * 2.5, y1 - (y1 - y0) * 0.12, cx + bw * 1.05, y0 + (y1 - y0) * 0.55, cx + bw, y0);
    p.closePath();
    return p;
  };
  const up = bulb(true), lo = bulb(false);
  // glass body: faint wash
  ctx.fillStyle = css(mixc(pal.sky1, pal.mist, 0.5), 0.35);
  ctx.fill(up);
  ctx.fill(lo);
  // sand in the top bulb, a shallow funnel in its surface
  const bh = neck - gTop;
  const lvl = neck - bh * 0.85 * Math.max(0, sand);
  if (sand > 0.005) {
    ctx.save();
    ctx.clip(up);
    ctx.fillStyle = css(sandC);
    ctx.beginPath();
    ctx.moveTo(cx - bw * 1.2, lvl);
    ctx.quadraticCurveTo(cx, lvl + bh * 0.08 * Math.min(1, sand * 3), cx + bw * 1.2, lvl);
    ctx.lineTo(cx + bw * 1.2, neck + 2);
    ctx.lineTo(cx - bw * 1.2, neck + 2);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
  // the pile below grows into a cone
  const filled = 1 - Math.max(0, sand);
  const ph = (gBot - neck) * 0.8 * filled;
  ctx.save();
  ctx.clip(lo);
  ctx.fillStyle = css(sandC);
  ctx.beginPath();
  ctx.moveTo(cx - bw * 1.2, gBot + 2);
  ctx.lineTo(cx - bw * 1.2, gBot - ph * 0.45);
  ctx.quadraticCurveTo(cx - bw * 0.3, gBot - ph * 0.6, cx, gBot - ph - (gBot - neck) * 0.05 * (sand > 0 ? 1 : 0));
  ctx.quadraticCurveTo(cx + bw * 0.3, gBot - ph * 0.6, cx + bw * 1.2, gBot - ph * 0.45);
  ctx.lineTo(cx + bw * 1.2, gBot + 2);
  ctx.closePath();
  ctx.fill();
  // grains on the slope
  const r = rng(Math.floor(t * 20));
  ctx.fillStyle = css(mixc(sandC, pal.near, 0.4), 0.6);
  for (let i = 0; i < 30; i++) ctx.fillRect(cx + (r() - 0.5) * bw * 1.4, gBot - r() * ph, Math.max(1, W * 0.006), Math.max(1, W * 0.006));
  ctx.restore();
  // the falling stream
  if (sand > 0.005) {
    ctx.strokeStyle = css(sandC);
    ctx.lineWidth = Math.max(1, W * 0.014);
    ctx.beginPath();
    ctx.moveTo(cx, neck);
    ctx.lineTo(cx, gBot - ph);
    ctx.stroke();
    const rr = rng(3);
    for (let i = 0; i < 10; i++) {
      const u = (rr() + t * (1.2 + rr())) % 1;
      ctx.fillStyle = css(sandC);
      ctx.fillRect(cx - W * 0.006 + (rr() - 0.5) * W * 0.01, neck + u * (gBot - ph - neck), Math.max(1, W * 0.01), Math.max(1, W * 0.01));
    }
  }
  // glass edges and highlights
  ctx.strokeStyle = css(glassEdge, 0.85);
  ctx.lineWidth = Math.max(1, W * 0.012);
  ctx.stroke(up);
  ctx.stroke(lo);
  ctx.strokeStyle = css(pal.sun, 0.75);
  ctx.lineWidth = Math.max(1.5, W * 0.025);
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(cx - bw * 0.72, gTop + bh * 0.12);
  ctx.quadraticCurveTo(cx - bw * 0.8, gTop + bh * 0.4, cx - bw * 0.45, gTop + bh * 0.72);
  ctx.moveTo(cx - bw * 0.45, neck + bh * 0.28);
  ctx.quadraticCurveTo(cx - bw * 0.8, neck + bh * 0.6, cx - bw * 0.72, gBot - bh * 0.12);
  ctx.stroke();
  // frame: two plates and three turned posts
  ctx.fillStyle = css(wood);
  const plateW = W * 1.08;
  for (const y of [top, gBot]) {
    ctx.beginPath();
    ctx.roundRect(cx - plateW / 2, y, plateW, plate, plate * 0.35);
    ctx.fill();
  }
  ctx.fillStyle = css(mixc(wood, pal.rockLight, 0.18));
  for (const y of [top, gBot]) ctx.fillRect(cx - plateW / 2 + plate * 0.3, y + plate * 0.15, plateW - plate * 0.6, plate * 0.12);
  ctx.fillStyle = css(wood);
  for (const px of [-0.46, 0.46]) {
    const x = cx + px * W;
    const pw = W * 0.045;
    ctx.beginPath();
    ctx.moveTo(x - pw, gTop);
    for (let k = 0; k <= 10; k++) {
      const u = k / 10;
      ctx.lineTo(x - pw * (0.7 + 0.35 * Math.abs(Math.sin(u * Math.PI * 3))), gTop + u * (gBot - gTop));
    }
    for (let k = 10; k >= 0; k--) {
      const u = k / 10;
      ctx.lineTo(x + pw * (0.7 + 0.35 * Math.abs(Math.sin(u * Math.PI * 3))), gTop + u * (gBot - gTop));
    }
    ctx.closePath();
    ctx.fill();
  }
};

// ---------- a lantern with a candle burning down ----------
export const lantern = (ctx: CanvasRenderingContext2D, cx: number, by: number, Hh: number, candle: number, t: number, pal: Pal) => {
  const W = Hh * 0.5, top = by - Hh;
  const metal = pal.near;
  const sh = ctx.createRadialGradient(cx, by, 0, cx, by, W);
  sh.addColorStop(0, css(pal.near, 0.5));
  sh.addColorStop(1, css(pal.near, 0));
  ctx.save();
  ctx.translate(cx, by);
  ctx.scale(1, 0.12);
  ctx.translate(-cx, -by);
  ctx.fillStyle = sh;
  ctx.beginPath();
  ctx.arc(cx, by, W, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  const gTop = top + Hh * 0.2, gBot = by - Hh * 0.08;
  // warm glow through the glass
  const fy = gBot - (gBot - gTop) * (0.08 + 0.72 * Math.max(0.05, candle)) - Hh * 0.06;
  const flick = 0.85 + 0.15 * Math.sin(t * 13) * Math.sin(t * 7.3);
  if (candle > 0.01) {
    const g = ctx.createRadialGradient(cx, fy, 0, cx, fy, Hh * 0.9);
    g.addColorStop(0, `rgba(255,236,214,${(0.55 * flick).toFixed(3)})`);
    g.addColorStop(0.3, `rgba(255,220,190,${(0.18 * flick).toFixed(3)})`);
    g.addColorStop(1, 'rgba(255,220,190,0)');
    ctx.fillStyle = g;
    ctx.fillRect(cx - Hh, fy - Hh, Hh * 2, Hh * 2);
  }
  // glass
  ctx.fillStyle = css(mixc(pal.sky1, pal.mist, 0.5), 0.3);
  ctx.fillRect(cx - W * 0.42, gTop, W * 0.84, gBot - gTop);
  // the candle
  const ch = (gBot - gTop) * 0.72 * Math.max(0.05, candle);
  const cw = W * 0.22;
  ctx.fillStyle = css(mixc(pal.paper, pal.rockLight, 0.25));
  ctx.beginPath();
  ctx.roundRect(cx - cw / 2, gBot - ch, cw, ch, cw * 0.15);
  ctx.fill();
  ctx.fillStyle = css(mixc(pal.paper, pal.rockLight, 0.5));
  ctx.beginPath();
  ctx.ellipse(cx - cw * 0.25, gBot - ch + cw * 0.3, cw * 0.08, cw * 0.4, 0, 0, Math.PI * 2);
  ctx.fill();
  if (candle > 0.01) {
    // flame: a coral core inside a pale tongue
    const fh = Hh * 0.11 * flick, fw = cw * 0.38;
    const fx = cx + Math.sin(t * 5) * fw * 0.15;
    ctx.fillStyle = 'rgba(255,246,232,0.95)';
    ctx.beginPath();
    ctx.moveTo(fx, gBot - ch - fh);
    ctx.quadraticCurveTo(fx + fw, gBot - ch - fh * 0.3, fx, gBot - ch + fw * 0.2);
    ctx.quadraticCurveTo(fx - fw, gBot - ch - fh * 0.3, fx, gBot - ch - fh);
    ctx.fill();
    ctx.fillStyle = '#E85D4E';
    ctx.beginPath();
    ctx.ellipse(fx, gBot - ch - fh * 0.22, fw * 0.32, fh * 0.28, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  // frame: cap, ring, base, posts
  ctx.fillStyle = css(metal);
  ctx.beginPath();
  ctx.moveTo(cx - W * 0.5, gTop);
  ctx.lineTo(cx - W * 0.2, top + Hh * 0.08);
  ctx.lineTo(cx + W * 0.2, top + Hh * 0.08);
  ctx.lineTo(cx + W * 0.5, gTop);
  ctx.closePath();
  ctx.fill();
  ctx.strokeStyle = css(metal);
  ctx.lineWidth = Math.max(1.5, W * 0.05);
  ctx.beginPath();
  ctx.arc(cx, top + Hh * 0.04, W * 0.13, Math.PI, 0);
  ctx.stroke();
  ctx.fillRect(cx - W * 0.52, gBot, W * 1.04, Hh * 0.08);
  for (const px of [-0.45, 0.45]) ctx.fillRect(cx + px * W - W * 0.03, gTop, W * 0.06, gBot - gTop);
  ctx.lineWidth = Math.max(1, W * 0.02);
  ctx.beginPath();
  ctx.moveTo(cx - W * 0.45, (gTop + gBot) / 2);
  ctx.lineTo(cx + W * 0.45, (gTop + gBot) / 2);
  ctx.stroke();
};

// ---------- a cairn of stones ----------
const STONES = [
  {w: 1, h: 0.42},
  {w: 0.82, h: 0.36},
  {w: 0.66, h: 0.32},
  {w: 0.5, h: 0.28},
  {w: 0.36, h: 0.25},
];
const stone = (ctx: CanvasRenderingContext2D, cx: number, cy: number, sw: number, sh: number, pal: Pal, seed: number, ghost: boolean) => {
  const r = rng(seed);
  const pts: Pt[] = [];
  for (let k = 0; k < 24; k++) {
    const a = (k / 24) * Math.PI * 2;
    const rad = 1 + (fbm1(k * 0.45 + seed, 4) - 0.5) * 0.34 + (r() - 0.5) * 0.04;
    pts.push([cx + Math.cos(a) * sw * 0.5 * rad, cy + Math.sin(a) * sh * 0.5 * rad * (Math.sin(a) > 0 ? 0.85 : 1)]);
  }
  if (ghost) {
    ctx.setLineDash([sw * 0.04, sw * 0.05]);
    ctx.strokeStyle = css(pal.near, 0.45);
    ctx.lineWidth = Math.max(1.5, sw * 0.014);
    ctx.beginPath();
    pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
    ctx.closePath();
    ctx.stroke();
    ctx.setLineDash([]);
    return;
  }
  ctx.fillStyle = css(pal.rock);
  fillPoly(ctx, pts);
  ctx.save();
  ctx.beginPath();
  pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
  ctx.closePath();
  ctx.clip();
  const g = ctx.createRadialGradient(cx - sw * 0.2, cy - sh * 0.35, 0, cx - sw * 0.2, cy - sh * 0.35, sw * 0.7);
  g.addColorStop(0, css(pal.rockLight, 0.9));
  g.addColorStop(1, css(pal.rockLight, 0));
  ctx.fillStyle = g;
  ctx.fillRect(cx - sw, cy - sh, sw * 2, sh * 2);
  const d = ctx.createLinearGradient(0, cy - sh * 0.1, 0, cy + sh * 0.5);
  d.addColorStop(0, css(pal.rockDark, 0));
  d.addColorStop(1, css(pal.rockDark, 0.85));
  ctx.fillStyle = d;
  ctx.fillRect(cx - sw, cy - sh, sw * 2, sh * 2);
  for (let k = 0; k < 8; k++) {
    const pts2: Pt[] = [];
    const px = cx + (r() - 0.5) * sw * 0.8, py = cy + (r() - 0.5) * sh * 0.7, rw = sw * (0.08 + r() * 0.15);
    for (let q = 0; q < 8; q++) {
      const a = (q / 8) * Math.PI * 2;
      pts2.push([px + Math.cos(a) * rw * (0.6 + r() * 0.5), py + Math.sin(a) * rw * 0.4 * (0.6 + r() * 0.5)]);
    }
    ctx.globalAlpha = 0.14;
    ctx.fillStyle = css(r() < 0.5 ? pal.rockDark : pal.rockLight);
    fillPoly(ctx, deform(pts2, 2, 0.06, r));
  }
  ctx.globalAlpha = 1;
  for (let k = 0; k < 70; k++) {
    ctx.fillStyle = css(r() < 0.6 ? pal.rockDark : pal.rockLight, 0.35);
    ctx.fillRect(cx + (r() - 0.5) * sw, cy + (r() - 0.5) * sh, Math.max(1, sw * 0.007), Math.max(1, sw * 0.007));
  }
  ctx.strokeStyle = css(pal.rockDark, 0.4);
  ctx.lineWidth = Math.max(1, sw * 0.008);
  ctx.beginPath();
  pts.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
  ctx.closePath();
  ctx.stroke();
  ctx.restore();
};
export const cairnTops = (L: Layout, n: number) => {
  const base = L.rockW * 0.95;
  let y = L.ledgeTop + L.rockW * 0.02;
  const out: {cx: number; cy: number; w: number; h: number}[] = [];
  for (let i = 0; i < n; i++) {
    const s = STONES[i];
    const sw = base * s.w, sh = base * s.h;
    out.push({cx: L.rockX + (i % 2 ? 1 : -1) * base * 0.03 * i, cy: y - sh * 0.45, w: sw, h: sh});
    y -= sh * 0.82;
  }
  return out;
};
const cairn = (ctx: CanvasRenderingContext2D, L: Layout, pal: Pal, stones: number, seed: number) => {
  const all = cairnTops(L, 5);
  const shadowW = all[0].w;
  ctx.fillStyle = css(pal.near, 0.45);
  ctx.beginPath();
  ctx.ellipse(L.rockX + shadowW * 0.05, L.ledgeTop + L.rockW * 0.02, shadowW * 0.6, shadowW * 0.05, 0, 0, Math.PI * 2);
  ctx.fill();
  const k = Math.floor(stones), fr = stones - k;
  all.forEach((s, i) => {
    if (i < k) stone(ctx, s.cx, s.cy, s.w, s.h, pal, seed + i * 9, false);
    else if (i === k && fr > 0.001) {
      const e = 1 - fr;
      stone(ctx, s.cx, s.cy - e * e * L.rockW * 1.6, s.w, s.h, pal, seed + i * 9, false);
    } else stone(ctx, s.cx, s.cy, s.w, s.h, pal, seed + i * 9, true);
  });
};

// ---------- the painter ----------
type Cache = {key: string; c: HTMLCanvasElement};
export class Painter2 {
  ridge = new Painter();
  /** the transform the scene is drawn with (a camera can move it) */
  xf: [number, number, number, number, number, number] = [1, 0, 0, 1, 0, 0];
  caches: Record<string, Cache> = {};
  layer = (slot: string, key: string, w: number, h: number, paint: (ctx: CanvasRenderingContext2D) => void) => {
    const cur = this.caches[slot];
    if (cur && cur.key === key) return cur.c;
    const c = cur && cur.c.width === w && cur.c.height === h ? cur.c : mk(w, h);
    const ctx = c.getContext('2d')!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, w, h);
    paint(ctx);
    this.caches[slot] = {key, c};
    return c;
  };

  render(ctx: CanvasRenderingContext2D, w: number, h: number, S: Scene2, theme: Theme, t: number, extra?: () => void) {
    const L = layoutFor(w, h);
    if (S.kind === 'ridge') {
      this.ridge.xf = this.xf;
      this.ridge.render(ctx, w, h, S, theme, t);
    } else {
      const night = Math.round(S.night * 4) / 4;
      const pal = palette(theme, night);
      const key = `${S.kind}:${w}x${h}:${theme}:${S.seed}:${night}:${S.peak.toFixed(2)}`;
      ctx.setTransform(...this.xf);
      ctx.globalAlpha = 1;
      this.kinds[S.kind](ctx, w, h, L, pal, S, theme, t, key);
    }
    if (S.birds) birds(ctx, w, h, t, palette(theme, S.night), S.birds, L.horizon);
    if (extra) extra();
    // paper
    const paper = this.layer('paper', `${w}x${h}`, w, h, (c) => {
      c.fillStyle = c.createPattern(grain(), 'repeat')!;
      c.fillRect(0, 0, w, h);
    });
    ctx.globalAlpha = theme === 'light' ? 0.55 : 0.3;
    ctx.globalCompositeOperation = theme === 'light' ? 'multiply' : 'screen';
    ctx.drawImage(paper, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }

  kinds: Record<Exclude<Kind, 'ridge'>, (ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, S: Scene2, theme: Theme, t: number, key: string) => void> = {
    // ---- night: a moon over still water, charging ----
    night: (ctx, w, h, L, pal, S, theme, t, key) => {
      const wl = L.tall ? h * 0.8 : h * 0.66;
      const Lw: Layout = {...L, horizon: wl - h * 0.01, peakTop: L.tall ? h * 0.62 : h * 0.26, ridgeY: wl - h * 0.06};
      const sky = this.layer('n-sky', key, w, h, (c) => {
        skyGrad(c, w, h, wl, pal);
        const r = rng(S.seed + 50);
        for (let i = 0; i < 70; i++) {
          c.fillStyle = css(pal.sun, 0.25 + r() * 0.5);
          const s2 = Math.max(0.8, (w / 1000) * (0.6 + r() * 1.2));
          c.fillRect(r() * w, r() * wl * 0.8, s2, s2);
        }
      });
      const mtn = this.layer('n-mtn', key, w, h, (c) => {
        paintFar(c, w, h, Lw, pal, rng(S.seed + 1), S.seed, S, {ridges: false});
        paintFar(c, w, h, {...Lw, ridgeY: wl - h * 0.12}, pal, rng(S.seed + 2), S.seed, S, {back: false, peak: false});
        c.clearRect(0, wl, w, h - wl);
      });
      const mx = S.moonX != null ? w * S.moonX : L.tall ? w * 0.72 : w * 0.8, my = S.moonY != null ? h * S.moonY : L.tall ? h * 0.6 : h * 0.2, mr = Math.min(w, h) * (L.tall ? 0.05 : 0.075);
      ctx.drawImage(sky, 0, 0);
      moonPhase(ctx, mx, my, mr, S.charge ?? 0.5, pal.sun, mixc(pal.sky0, pal.sky1, 0.6));
      ctx.drawImage(mtn, 0, 0);
      ctx.fillStyle = css(pal.mid2);
      ctx.fillRect(0, wl, w, h - wl);
      reflect(ctx, ctx.canvas, w, h, wl, t, pal, 0.3);
      glitter(ctx, mx, wl, h, w, t, pal, 0.5 + 0.5 * (S.charge ?? 0.5));
      const shore = this.layer('n-shore', key, w, h, (c) => {
        shoreline(c, w, h, L.tall ? h * 0.93 : h * 0.86, pal, rng(S.seed + 9), true, L.tall ? 0.45 : 0.32, S.seed);
        shoreline(c, w, h, L.tall ? h * 0.95 : h * 0.92, pal, rng(S.seed + 10), false, L.tall ? 0.3 : 0.15, S.seed + 4);
        granulate(c, w, h, 0.12);
      });
      ctx.drawImage(shore, 0, 0);
    },

    // ---- beach: two palms, an empty hammock, the sea ----
    beach: (ctx, w, h, L, pal, S, theme, t, key) => {
      const hz = L.tall ? h * 0.74 : h * 0.6;
      const back = this.layer('b-back', key, w, h, (c) => {
        skyGrad(c, w, hz, hz, pal);
        clouds(c, w, h, hz, pal, rng(S.seed), 6);
        sunDisc(c, L.tall ? w * 0.36 : w * 0.66, hz - h * 0.08, Math.min(w, h) * (L.tall ? 0.045 : 0.06), pal, 1);
        // a far island on the horizon
        const r = rng(S.seed + 3);
        const ix = L.tall ? w * 0.2 : w * 0.56, iw = L.tall ? w * 0.4 : w * 0.18;
        const isl = ridgePts(ix - iw / 2, ix + iw / 2, 60, (x) => hz - Math.pow(Math.sin(((x - ix + iw / 2) / iw) * Math.PI), 0.8) * h * 0.06 - (fbm1(x / (w * 0.01), 3) - 0.5) * h * 0.008);
        wash(c, [...isl, [ix + iw / 2, hz], [ix - iw / 2, hz]], mixc(pal.far, pal.sky1, 0.4), r, {body: 0.85, layers: 5, a: 0.05, v: 0.004, edge: 0.05});
        // sea
        const g = c.createLinearGradient(0, hz, 0, h);
        g.addColorStop(0, css(mixc(pal.mid, pal.sky1, 0.45)));
        g.addColorStop(1, css(mixc(pal.mid, pal.mid2, 0.4)));
        c.fillStyle = g;
        c.fillRect(0, hz, w, h - hz);
        c.strokeStyle = css(pal.mist, 0.35);
        c.lineWidth = Math.max(1, w / 900);
        for (let i = 0; i < 80; i++) {
          const y = hz + Math.pow(r(), 1.6) * (h - hz) * 0.7, x = r() * w, l = w * (0.01 + r() * 0.04) * (1 + (y - hz) / (h * 0.2));
          c.beginPath();
          c.moveTo(x, y);
          c.quadraticCurveTo(x + l / 2, y - h * 0.003, x + l, y);
          c.stroke();
        }
        granulate(c, w, h, 0.15);
      });
      ctx.drawImage(back, 0, 0);
      glitter(ctx, L.tall ? w * 0.36 : w * 0.66, hz, h * 0.86, w, t, pal, 0.9);
      // the beach: pale sand, a wet band, foam that comes and goes
      const sandY = L.tall ? h * 0.84 : h * 0.78;
      const sand = this.layer('b-sand', key, w, h, (c) => {
        const pts = ridgePts(-0.02 * w, 1.02 * w, 60, (x) => sandY + Math.sin(x / w * 3 + 1) * h * 0.02 - (x / w) * h * 0.03);
        wash(c, [...pts, [1.02 * w, h], [-0.02 * w, h]], mixc(pal.paper, pal.rockLight, theme === 'light' ? 0.35 : 0.5), rng(S.seed + 4), {body: 0.97, layers: 6, a: 0.06, v: 0.003, edge: 0.1});
        granulate(c, w, h, 0.18);
        const r = rng(S.seed + 6);
        c.fillStyle = css(pal.rockDark, 0.4);
        for (let i = 0; i < 9; i++) {
          c.beginPath();
          c.ellipse(r() * w, sandY + h * (0.05 + r() * 0.15), w * 0.006 * (1 + r()), h * 0.004, 0, 0, Math.PI * 2);
          c.fill();
        }
      });
      const foam = (Math.sin(t * 0.8) * 0.5 + 0.5) * h * 0.012;
      ctx.drawImage(sand, 0, 0);
      ctx.strokeStyle = css(pal.mist, 0.75);
      ctx.lineWidth = Math.max(1.5, w / 500);
      ctx.beginPath();
      for (let i = 0; i <= 80; i++) {
        const x = (i / 80) * w * 1.04 - w * 0.02;
        const y = sandY - h * 0.004 + Math.sin(x / w * 3 + 1) * h * 0.02 - (x / w) * h * 0.03 - foam + Math.sin(x * 0.05 + t * 2) * h * 0.003;
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      ctx.stroke();
      // palms and the hammock between them
      const palmsKey = `${key}`;
      const pa = L.tall ? [w * 0.6, h * 0.93] : [w * 0.72, h * 0.9], pb = L.tall ? [w * 0.92, h * 0.94] : [w * 0.93, h * 0.92];
      const H1 = L.tall ? h * 0.27 : h * 0.6, H2 = L.tall ? h * 0.23 : h * 0.5;
      let ha: Pt = [0, 0], hb: Pt = [0, 0];
      const palms = this.layer('b-palms', palmsKey, w, h, (c) => {
        const r = rng(S.seed + 8);
        ha = palm(c, pa[0], pa[1], H1, -0.16, pal.near, r, w / 1000);
        hb = palm(c, pb[0], pb[1], H2, 0.2, pal.near, r, w / 1000);
      });
      // recompute hammock anchors (cheap) so they also exist when the cache is reused
      {
        const at = (bx: number, by: number, H: number, lean: number, u: number): Pt => {
          const top: Pt = [bx + lean * H, by - H], cp: Pt = [bx + lean * H * 0.15, by - H * 0.55];
          return [(1 - u) * (1 - u) * bx + 2 * (1 - u) * u * cp[0] + u * u * top[0], (1 - u) * (1 - u) * by + 2 * (1 - u) * u * cp[1] + u * u * top[1]];
        };
        ha = at(pa[0], pa[1], H1, -0.16, L.tall ? 0.42 : 0.36);
        hb = at(pb[0], pb[1], H2, 0.2, L.tall ? 0.48 : 0.42);
      }
      ctx.drawImage(palms, 0, 0);
      const sway = Math.sin(t * 0.9) * w * 0.006;
      hammock(ctx, ha, hb, h * (L.tall ? 0.025 : 0.05), sway, pal.near, mixc(pal.near, pal.rockLight, 0.25), Math.max(1.2, w / 500));
    },

    // ---- sunrise over a sea of clouds ----
    sunrise: (ctx, w, h, L, pal, S, theme, t, key) => {
      const ct = L.tall ? h * 0.76 : h * 0.6;
      const sx = L.tall ? w * 0.5 : w * 0.7;
      const sy = ct - (S.sun + 0.1) * h * (L.tall ? 0.34 : 0.35);
      const sky = this.layer('s-sky', key, w, h, (c) => {
        skyGrad(c, w, h, ct, pal);
        clouds(c, w, h, ct * 0.8, pal, rng(S.seed), 5);
      });
      ctx.drawImage(sky, 0, 0);
      sunDisc(ctx, sx, sy, Math.min(w, h) * (L.tall ? 0.05 : 0.07), pal, 1);
      // rays fanning from behind the clouds
      if (S.sun > -0.05) {
        ctx.save();
        ctx.globalCompositeOperation = theme === 'light' ? 'source-over' : 'screen';
        const R2 = Math.max(w, h) * 1.2;
        for (let k = 0; k < 14; k++) {
          const a = -Math.PI + (k / 13) * Math.PI + Math.sin(k * 3.1) * 0.08 + Math.sin(t * 0.15 + k) * 0.01;
          const wd = 0.015 + ((k * 0.37) % 1) * 0.025;
          const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, R2);
          g.addColorStop(0, css(pal.sun, 0.22 * Math.min(1, S.sun + 0.3)));
          g.addColorStop(1, css(pal.sun, 0));
          ctx.fillStyle = g;
          ctx.beginPath();
          ctx.moveTo(sx, sy);
          ctx.lineTo(sx + Math.cos(a - wd) * R2, sy + Math.sin(a - wd) * R2);
          ctx.lineTo(sx + Math.cos(a + wd) * R2, sy + Math.sin(a + wd) * R2);
          ctx.closePath();
          ctx.fill();
        }
        ctx.restore();
      }
      const peaks = this.layer('s-peaks', key, w, h, (c) => {
        const Lp: Layout = {...L, horizon: ct + h * 0.02, peakX: L.tall ? w * 0.3 : w * 0.52, peakTop: L.tall ? h * 0.6 : h * 0.18, peakHalf: L.tall ? w * 0.5 : w * 0.22};
        paintFar(c, w, h, Lp, pal, rng(S.seed + 1), S.seed, S, {back: false, ridges: false});
        const Lq: Layout = {...Lp, peakX: L.tall ? w * 0.85 : w * 0.88, peakTop: L.tall ? h * 0.68 : h * 0.36, peakHalf: L.tall ? w * 0.3 : w * 0.14};
        paintFar(c, w, h, Lq, pal, rng(S.seed + 5), S.seed + 2, S, {back: false, ridges: false});
      });
      ctx.drawImage(peaks, 0, 0);
      // the sea of clouds: billows lit from the sun's side
      const sea = this.layer('s-sea', key, w * 2, h, (c) => {
        const r = rng(S.seed + 7);
        const W2 = w * 2;
        c.fillStyle = css(pal.mist);
        c.fillRect(0, ct + h * 0.06, W2, h);
        for (let row = 0; row < 6; row++) {
          const y0 = ct - h * 0.01 + row * h * 0.035;
          for (let i = 0; i < 110; i++) {
            const x = r() * W2, y = y0 + (r() - 0.5) * h * 0.02, rad = h * (0.025 + r() * 0.04) * (1 + row * 0.25);
            c.save();
            c.translate(x, y);
            c.scale(1.9, 0.75);
            const g = c.createRadialGradient(-rad * 0.2, -rad * 0.35, 0, 0, 0, rad);
            g.addColorStop(0, css(pal.mist, 0.95));
            g.addColorStop(0.6, css(mixc(pal.mist, pal.far, 0.12), 0.8));
            g.addColorStop(1, css(mixc(pal.mist, pal.far, 0.2), 0));
            c.fillStyle = g;
            c.beginPath();
            c.arc(0, 0, rad, 0, Math.PI * 2);
            c.fill();
            c.restore();
          }
        }
      });
      const off = -((t * w * 0.004) % w);
      ctx.drawImage(sea, off, 0);
    },

    // ---- a winding path into the hills, a trail up the mountain ----
    path: (ctx, w, h, L, pal, S, theme, t, key) => {
      const Lp = pathLayout(L, w, h);
      const base = this.layer('p-base', key, w, h, (c) => {
        skyGrad(c, w, h, Lp.horizon, pal);
        clouds(c, w, h, Lp.horizon, pal, rng(S.seed), 5);
        paintFar(c, w, h, Lp, pal, rng(S.seed + 1), S.seed, S);
        // near hills
        const hy = (x: number) => (L.tall ? h * 0.86 : h * 0.8) - Math.pow(fbm1(x / (w * 0.3) + S.seed, 4), 1.4) * h * 0.12;
        const hp = ridgePts(-0.02 * w, 1.02 * w, 80, hy);
        wash(c, [...hp, [1.02 * w, h], [-0.02 * w, h]], mixc(pal.mid2, pal.near, 0.55), rng(S.seed + 3), {body: 0.95, layers: 6, a: 0.06, v: 0.003, edge: 0.15});
        trees(c, w, hy, h * 0.06, mixc(pal.mid2, pal.near, 0.55), rng(S.seed + 4), 1.2);
        granulate(c, w, h, 0.15);
      });
      ctx.drawImage(base, 0, 0);
      // the route: from the foreground, winding to the foot of the mountain, then switchbacks to the top
      const route = routeOf(w, h, L, Lp);
      ctx.save();
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      // the walked path on the hills: a pale band narrowing with distance
      for (let i = 0; i < route.length - 1; i++) {
        const [x0, y0, wd0, onM] = route[i], [x1, y1] = route[i + 1];
        if (onM) continue;
        ctx.strokeStyle = css(mixc(pal.rockLight, pal.mid, 0.35), 0.85);
        ctx.lineWidth = wd0;
        ctx.beginPath();
        ctx.moveTo(x0, y0);
        ctx.lineTo(x1, y1);
        ctx.stroke();
      }
      // the trail up the mountain: dashes
      ctx.setLineDash([w * 0.006, w * 0.008]);
      ctx.strokeStyle = css(pal.near, 0.6);
      ctx.lineWidth = Math.max(1, w * 0.0025);
      ctx.beginPath();
      let started = false;
      for (const [x, y, , onM] of route) {
        if (!onM) continue;
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else ctx.lineTo(x, y);
      }
      ctx.stroke();
      ctx.setLineDash([]);
      ctx.restore();
      // you, as a small coral light on the route
      if (S.noYou) return;
      const u = Math.max(0, Math.min(1, S.trail ?? 0));
      const k = u * (route.length - 1), i0 = Math.floor(k), f = k - i0;
      const a = route[i0], b = route[Math.min(route.length - 1, i0 + 1)];
      const px = a[0] + (b[0] - a[0]) * f, py = a[1] + (b[1] - a[1]) * f;
      const rad = Math.min(w, h) * 0.012;
      const g = ctx.createRadialGradient(px, py, 0, px, py, rad * 5);
      g.addColorStop(0, `rgba(232,93,78,${(0.55 + 0.25 * Math.sin(t * 4)).toFixed(3)})`);
      g.addColorStop(1, 'rgba(232,93,78,0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(px, py, rad * 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#E85D4E';
      ctx.beginPath();
      ctx.arc(px, py, rad, 0, Math.PI * 2);
      ctx.fill();
      // the summit, a small white flag-less marker
      const top = route[route.length - 1];
      ctx.strokeStyle = css(pal.near, 0.8);
      ctx.lineWidth = Math.max(1, w * 0.002);
      ctx.beginPath();
      ctx.arc(top[0], top[1], rad * 1.2, 0, Math.PI * 2);
      ctx.stroke();
    },

    // ---- fog: pines receding into it ----
    fog: (ctx, w, h, L, pal, S, theme, t, key) => {
      const base = this.layer('f-base', key, w, h, (c) => {
        skyGrad(c, w, h, h, {...pal, sky0: mixc(pal.sky0, pal.mist, 0.3), sky1: pal.mist});
        const rows = 4;
        for (let row = 0; row < rows; row++) {
          const u = row / (rows - 1);
          const col = mixc(pal.mist, pal.near, 0.18 + u * u * 0.8);
          const gy = h * (L.tall ? 0.8 + u * 0.14 : 0.62 + u * 0.3);
          const r = rng(S.seed + row * 13);
          const tH = h * (L.tall ? 0.07 + u * 0.12 : 0.16 + u * 0.38);
          c.fillStyle = css(col);
          c.fillRect(0, gy, w, h - gy);
          for (let x = -0.05 * w; x < 1.05 * w; x += tH * (0.18 + r() * 0.3)) {
            if (fbm1(x / (w * 0.08) + row * 5, 3) < 0.38) continue;
            spruce(c, x, gy + tH * 0.04, tH * (0.6 + r() * 0.6), col, r);
          }
          const g = c.createLinearGradient(0, gy - tH * 0.3, 0, gy + h * 0.05);
          g.addColorStop(0, css(pal.mist, 0));
          g.addColorStop(1, css(pal.mist, 0.85));
          c.fillStyle = g;
          c.fillRect(0, gy - tH * 0.3, w, tH * 0.3 + h * 0.08);
        }
        granulate(c, w, h, 0.12);
      });
      ctx.drawImage(base, 0, 0);
      const mist = this.layer('f-mist', `${w}x${h}:${theme}:${S.night}`, w * 2, h, (c) => paintMist(c, w * 2, h, [h * 0.55, h * 0.75, h * 0.92], pal, rng(9)));
      const off = -((t * w * 0.01) % w);
      ctx.globalAlpha = Math.min(1, S.mist * 0.22);
      ctx.drawImage(mist, off, 0);
      ctx.globalAlpha = 1;
    },

    // ---- a mountain lake, a boat, still water ----
    lake: (ctx, w, h, L, pal, S, theme, t, key) => {
      const wl = L.tall ? h * 0.8 : h * 0.64;
      const Lw: Layout = {...L, horizon: wl - h * 0.01, peakTop: L.tall ? h * 0.6 : h * 0.12, ridgeY: wl - h * 0.1};
      const above = this.layer('l-above', key, w, h, (c) => {
        skyGrad(c, w, h, wl, pal);
        clouds(c, w, h, wl, pal, rng(S.seed), 5);
        paintFar(c, w, h, Lw, pal, rng(S.seed + 1), S.seed, S);
        c.clearRect(0, wl, w, h - wl);
      });
      ctx.drawImage(above, 0, 0, w, wl, 0, 0, w, wl);
      ctx.fillStyle = css(pal.mid);
      ctx.fillRect(0, wl, w, h - wl);
      reflect(ctx, above, w, h, wl, t * 0.6, pal, 0);
      // a moored rowboat, rocking slightly
      const bx = S.boatX != null ? w * S.boatX : L.tall ? w * 0.62 : w * 0.7, by = L.tall ? h * 0.88 : h * 0.8, bw = L.tall ? w * 0.22 : w * 0.11;
      const moored = S.boatX == null;
      const rock = Math.sin(t * 1.1) * 0.03;
      ctx.save();
      ctx.translate(bx, by);
      ctx.rotate(rock);
      ctx.fillStyle = css(pal.near);
      ctx.beginPath();
      ctx.moveTo(-bw / 2, -bw * 0.06);
      ctx.quadraticCurveTo(-bw * 0.35, bw * 0.12, 0, bw * 0.12);
      ctx.quadraticCurveTo(bw * 0.4, bw * 0.12, bw / 2, -bw * 0.09);
      ctx.lineTo(bw * 0.42, -bw * 0.02);
      ctx.lineTo(-bw * 0.44, -bw * 0.01);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = css(pal.near);
      ctx.lineWidth = Math.max(1, bw * 0.02);
      ctx.beginPath();
      ctx.moveTo(-bw * 0.1, -bw * 0.01);
      ctx.lineTo(bw * 0.25, -bw * 0.14);
      ctx.stroke();
      ctx.restore();
      // its reflection
      ctx.save();
      ctx.globalAlpha = 0.35;
      ctx.translate(bx, by + bw * 0.24);
      ctx.scale(1, -0.6);
      ctx.rotate(-rock);
      ctx.fillStyle = css(pal.near);
      ctx.beginPath();
      ctx.moveTo(-bw / 2, -bw * 0.06);
      ctx.quadraticCurveTo(-bw * 0.35, bw * 0.12, 0, bw * 0.12);
      ctx.quadraticCurveTo(bw * 0.4, bw * 0.12, bw / 2, -bw * 0.09);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
      // mooring line to a post
      if (moored) {
      ctx.strokeStyle = css(pal.near, 0.8);
      ctx.lineWidth = Math.max(1, w / 1200);
      ctx.beginPath();
      ctx.moveTo(bx + bw * 0.48, by - bw * 0.06);
      ctx.quadraticCurveTo(bx + bw * 0.7, by + bw * 0.02, bx + bw * 0.95, by - bw * 0.15);
      ctx.stroke();
      ctx.fillStyle = css(pal.near);
      ctx.fillRect(bx + bw * 0.93, by - bw * 0.3, bw * 0.035, bw * 0.4);
      } else {
        // a wake behind a moving boat
        ctx.strokeStyle = css(pal.mist, 0.4);
        ctx.lineWidth = Math.max(1, w / 900);
        for (let k = 1; k <= 4; k++) {
          ctx.beginPath();
          ctx.moveTo(bx - bw * 0.5 - k * bw * 0.25, by + k * bw * 0.02);
          ctx.lineTo(bx - bw * 0.5 - k * bw * 0.55, by + k * bw * 0.05);
          ctx.stroke();
        }
      }
      // reeds in the foreground
      const reeds = this.layer('l-reeds', key, w, h, (c) => {
        const r = rng(S.seed + 12);
        c.strokeStyle = css(pal.near);
        c.lineCap = 'round';
        for (let i = 0; i < 70; i++) {
          const side = i < 40 ? 1 : 0;
          const x = side ? w * (0.82 + r() * 0.2) : w * (L.tall ? r() * 0.25 : 0.45 + r() * 0.12);
          const y = h * (0.97 + r() * 0.05);
          const ht = h * (L.tall ? 0.05 + r() * 0.08 : 0.1 + r() * 0.18);
          c.lineWidth = Math.max(1, (w / 1000) * (1 + r() * 1.5));
          c.beginPath();
          c.moveTo(x, y);
          c.quadraticCurveTo(x + (r() - 0.3) * ht * 0.2, y - ht * 0.6, x + (r() - 0.2) * ht * 0.35, y - ht);
          c.stroke();
          if (r() < 0.2) {
            c.fillStyle = css(pal.near);
            c.beginPath();
            c.ellipse(x + (r() - 0.2) * ht * 0.3, y - ht * 0.85, Math.max(1.5, w * 0.003), ht * 0.08, 0.1, 0, Math.PI * 2);
            c.fill();
          }
        }
      });
      ctx.drawImage(reeds, 0, 0);
    },

    // ---- sunset over the sea ----
    sunset: (ctx, w, h, L, pal, S, theme, t, key) => {
      const hz = L.tall ? h * 0.76 : h * 0.62;
      const sx = L.tall ? w * 0.42 : w * 0.66;
      const sy = hz - (S.sun + 0.05) * h * (L.tall ? 0.2 : 0.4);
      const sky = this.layer('ss-sky', key, w, h, (c) => {
        skyGrad(c, w, h, hz, pal);
        clouds(c, w, h, hz, pal, rng(S.seed), 7);
      });
      ctx.drawImage(sky, 0, 0);
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, w, hz);
      ctx.clip();
      sunDisc(ctx, sx, sy, Math.min(w, h) * (L.tall ? 0.06 : 0.085), pal, 1);
      ctx.restore();
      const sea = this.layer('ss-sea', key, w, h, (c) => {
        const g = c.createLinearGradient(0, hz, 0, h);
        g.addColorStop(0, css(mixc(pal.mid, pal.sky1, 0.3)));
        g.addColorStop(1, css(mixc(pal.mid2, pal.near, 0.3)));
        c.fillStyle = g;
        c.fillRect(0, hz, w, h - hz);
        const r = rng(S.seed + 2);
        c.strokeStyle = css(pal.mid2, 0.4);
        c.lineWidth = Math.max(1, w / 900);
        for (let i = 0; i < 90; i++) {
          const y = hz + Math.pow(r(), 1.5) * (h - hz), x = r() * w, l = w * (0.015 + r() * 0.05) * (1 + (y - hz) / (h * 0.25));
          c.beginPath();
          c.moveTo(x, y);
          c.quadraticCurveTo(x + l / 2, y + h * 0.003, x + l, y);
          c.stroke();
        }
      });
      ctx.drawImage(sea, 0, 0);
      glitter(ctx, sx, hz, h, w, t, pal, 1);
      const rocks = this.layer('ss-rocks', key, w, h, (c) => {
        const r = rng(S.seed + 3);
        const blob = (x: number, y: number, rw: number, rh: number) => {
          const pts: Pt[] = [];
          for (let k = 0; k <= 16; k++) {
            const a = Math.PI + (k / 16) * Math.PI;
            pts.push([x + Math.cos(a) * rw * (0.85 + fbm1(k * 0.5 + x, 3) * 0.3), y + Math.sin(a) * rh * (0.75 + fbm1(k * 0.7 + y, 3) * 0.4)]);
          }
          wash(c, deform([...pts, [x + rw, y + rh * 0.4], [x - rw, y + rh * 0.4]], 3, 0.06, r), pal.near, r, {body: 0.97, layers: 4, a: 0.07, v: 0.01, edge: 0.2});
        };
        const by = L.tall ? h * 0.95 : h * 0.9;
        blob(w * (L.tall ? 0.82 : 0.86), by, w * (L.tall ? 0.22 : 0.12), h * (L.tall ? 0.07 : 0.17));
        blob(w * (L.tall ? 0.6 : 0.74), by + h * 0.02, w * (L.tall ? 0.1 : 0.05), h * (L.tall ? 0.035 : 0.08));
        blob(w * (L.tall ? 0.1 : 0.55), by + h * 0.03, w * (L.tall ? 0.12 : 0.04), h * (L.tall ? 0.03 : 0.05));
        granulate(c, w, h, 0.12);
      });
      ctx.drawImage(rocks, 0, 0);
    },

    // ---- the cairn: this week's sessions, stacked ----
    cairn: (ctx, w, h, L, pal, S, theme, t, key) => {
      const base = this.layer('c-base', key, w, h, (c) => {
        skyGrad(c, w, h, L.horizon, pal);
        clouds(c, w, h, L.horizon, pal, rng(S.seed), 5);
        paintFar(c, w, h, L, pal, rng(S.seed + 1), S.seed, S);
      });
      ctx.drawImage(base, 0, 0);
      const mist = this.layer('c-mist', `${w}x${h}:${theme}:${S.night}`, w * 2, h, (c) => paintMist(c, w * 2, h, [L.horizon, L.ridgeY + h * 0.1], pal, rng(7)));
      ctx.globalAlpha = Math.min(1, S.mist);
      ctx.drawImage(mist, -((t * w * 0.006) % w), 0);
      ctx.globalAlpha = 1;
      // the ledge (with the pine and rubble), from the ridge painter's near layer
      const near = this.layer('c-near', `${key}:${S.tree.toFixed(3)}:${S.rubble}`, w, h, (c) => {
        paintLedge(c, w, h, L, pal, rng(S.seed + 2), S);
      });
      ctx.drawImage(near, 0, 0);
      const st = this.layer('c-stones', `${key}:${(S.stones ?? 0).toFixed(3)}`, w, h, (c) => cairn(c, L, pal, S.stones ?? 0, S.seed * 3 + 1));
      ctx.drawImage(st, 0, 0);
    },

    // ---- the hourglass on the ledge ----
    hourglass: (ctx, w, h, L, pal, S, theme, t, key) => {
      if (S.hgBg && S.hgBg !== 'hourglass' && S.hgBg !== 'ridge') {
        // the hourglass set into another place: draw that place, then a rock to stand on
        this.kinds[S.hgBg](ctx, w, h, L, pal, S, theme, t, key + ':bg');
        const ledge = this.layer('h-ledge2', key, w, h, (c) => paintLedge(c, w, h, {...L, ledgeX: L.tall ? w * 0.25 : w * 0.56}, pal, rng(S.seed + 2), {...S, tree: 0, rubble: 0}, true));
        ctx.drawImage(ledge, 0, 0);
        const Hb = L.tall ? h * 0.32 : h * 0.66;
        if (S.prop === 'lantern') lantern(ctx, L.tall ? w * 0.55 : L.rockX + w * 0.06, L.ledgeTop + h * 0.012, Hb * 0.8, S.candle ?? 1, t, pal);
        else if (S.prop !== 'none') hourglass(ctx, L.tall ? w * 0.55 : L.rockX + w * 0.06, L.ledgeTop + h * 0.012, Hb, S.sand ?? 1, t, pal, theme);
        return;
      }
      const base = this.layer('h-base', key, w, h, (c) => {
        skyGrad(c, w, h, L.horizon, pal);
        clouds(c, w, h, L.horizon, pal, rng(S.seed), 5);
        paintFar(c, w, h, L, pal, rng(S.seed + 1), S.seed, S);
      });
      ctx.drawImage(base, 0, 0);
      const mist = this.layer('h-mist', `${w}x${h}:${theme}:${S.night}`, w * 2, h, (c) => paintMist(c, w * 2, h, [L.horizon, L.ridgeY + h * 0.1], pal, rng(7)));
      ctx.globalAlpha = Math.min(1, S.mist);
      ctx.drawImage(mist, -((t * w * 0.006) % w), 0);
      ctx.globalAlpha = 1;
      const near = this.layer('h-near', key, w, h, (c) => paintLedge(c, w, h, L, pal, rng(S.seed + 2), {...S, tree: 0, rubble: 0}, true));
      ctx.drawImage(near, 0, 0);
      const Hh = L.tall ? h * 0.32 : h * 0.66;
      if (S.prop === 'lantern') lantern(ctx, L.tall ? w * 0.5 : L.rockX + w * 0.03, L.ledgeTop + h * 0.012, Hh * 0.8, S.candle ?? 1, t, pal);
      else if (S.prop !== 'none') hourglass(ctx, L.tall ? w * 0.5 : L.rockX + w * 0.03, L.ledgeTop + h * 0.012, Hh, S.sand ?? 1, t, pal, theme);
    },
  };
}

/** the dark rock shelf (and optionally the pine), shared by cairn and hourglass */
const paintLedge = (c: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, r: R, S: Scene, noTree = false) => {
  const top = (x: number) => L.ledgeTop + (fbm1(x / (w * 0.05) + S.seed * 5.3, 6, true) - 0.5) * h * 0.035 + Math.max(0, (L.ledgeX + w * 0.06 - x) / (w * 0.06)) * h * 0.06;
  const edge: Pt[] = [];
  for (let i = 0; i <= 30; i++) {
    const u = i / 30;
    edge.push([L.ledgeX + (fbm1(u * 6 + S.seed * 5.3 + 3, 5) - 0.5) * w * 0.05 + u * u * w * 0.02, h + 2 - u * (h + 2 - top(L.ledgeX + w * 0.02))]);
  }
  const shelf = ridgePts(L.ledgeX + w * 0.02, w * 1.05, 120, (x) => top(x));
  wash(c, [...edge, ...shelf, [w * 1.05, h + 2]], pal.near, r, {body: 0.94, layers: 10, a: 0.06, v: 0.004, edge: 0.2});
  if (!noTree && S.tree > 0) paintPine(c, L.treeX, top(L.treeX) + h * 0.004, L.treeH, S.tree, pal.near, r, w / 1000);
  granulate(c, w, h, 0.15);
};

export const pathLayout = (L: Layout, w: number, h: number): Layout => ({...L, peakX: L.tall ? w * 0.55 : w * 0.7, peakTop: L.tall ? h * 0.56 : h * 0.1, peakHalf: L.tall ? w * 0.55 : w * 0.25, ridgeY: L.tall ? h * 0.78 : h * 0.62});
/** the route for the path scene: [x, y, width, onMountain] */
export const routeOf = (w: number, h: number, L: Layout, Lp: Layout): [number, number, number, boolean][] => {
  const out: [number, number, number, boolean][] = [];
  const startY = h * 1.02, footY = Lp.ridgeY + h * 0.02;
  const n = 30;
  for (let i = 0; i <= n; i++) {
    const u = i / n;
    const y = startY + (footY - startY) * Math.pow(u, 0.7);
    const x = (L.tall ? w * 0.4 : w * 0.62) + Math.sin(u * Math.PI * 2.2) * w * (L.tall ? 0.25 : 0.12) * (1 - u * 0.7);
    out.push([x, y, Math.max(1.5, w * 0.05 * Math.pow(1 - u, 1.5) + w * 0.004), false]);
  }
  // switchbacks up to the summit
  const [fx, fy] = out[out.length - 1];
  const sx = Lp.peakX, sy = Lp.peakTop + h * 0.01;
  const m = 7;
  for (let i = 1; i <= m; i++) {
    const u = i / m;
    out.push([fx + (sx - fx) * u + (i < m ? (i % 2 ? 1 : -1) * w * 0.035 * (1 - u) : 0), fy + (sy - fy) * u, 1, true]);
  }
  return out;
};
