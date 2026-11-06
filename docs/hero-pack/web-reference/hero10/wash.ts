/**
 * Ridge: a black and white watercolour landscape painted procedurally on a 2D canvas.
 * Layered silhouettes with mist between them (far peak, forested ridge, a dark rock ledge),
 * a lone pine that grows over the 66 days, and this week's boulder that cracks with every session
 * and splits when the week is kept. Broken rocks from past weeks lie on the ledge.
 *
 * Painted with deformed-polygon washes (many translucent layers), pigment granulation and paper
 * texture, then cached in layers so each frame is only a few image draws.
 */
export type Theme = 'light' | 'dark';
export type Scene = {
  seed: number;
  tree: number; // 0..1 growth
  cracks: number; // 0..5, fractional while the newest crack is drawing
  broken: number; // 0..1 the boulder splitting apart
  rubble: number; // past weeks' broken rocks lying on the ledge
  sun: number; // -1..1 height of the sun (negative: below the ridge)
  night: number; // 0..1
  mist: number; // 0..1.5
  rain: number; // 0..1
  peak: number; // 0..1 how clearly the far peak shows through the haze
  rockIn?: number; // 0..1 a new boulder settling in
  noRock?: boolean; // the ledge without this week's boulder
};

export type RGB = [number, number, number];
export const mixc = (a: RGB, b: RGB, t: number): RGB => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
export const css = (c: RGB, a = 1) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`;

export type Pal = {paper: RGB; sky0: RGB; sky1: RGB; far: RGB; farShade: RGB; snow: RGB; mid: RGB; mid2: RGB; near: RGB; rock: RGB; rockLight: RGB; rockDark: RGB; mist: RGB; crack: RGB; sun: RGB};
const P: Record<string, Pal> = {
  lightDay: {paper: [246, 246, 244], sky0: [214, 214, 213], sky1: [246, 246, 244], far: [176, 176, 176], farShade: [140, 140, 142], snow: [244, 244, 242], mid: [126, 126, 128], mid2: [92, 92, 95], near: [24, 24, 26], rock: [92, 92, 95], rockLight: [160, 160, 162], rockDark: [38, 38, 41], mist: [250, 250, 248], crack: [16, 16, 18], sun: [255, 255, 253]},
  lightNight: {paper: [246, 246, 244], sky0: [96, 96, 101], sky1: [168, 168, 172], far: [128, 128, 132], farShade: [104, 104, 108], snow: [190, 190, 194], mid: [84, 84, 88], mid2: [62, 62, 66], near: [16, 16, 18], rock: [70, 70, 74], rockLight: [112, 112, 116], rockDark: [30, 30, 33], mist: [200, 200, 204], crack: [10, 10, 12], sun: [236, 236, 238]},
  darkDay: {paper: [14, 14, 16], sky0: [26, 26, 29], sky1: [70, 70, 74], far: [88, 88, 92], farShade: [66, 66, 70], snow: [150, 150, 154], mid: [48, 48, 52], mid2: [34, 34, 37], near: [7, 7, 8], rock: [74, 74, 78], rockLight: [122, 122, 126], rockDark: [30, 30, 33], mist: [128, 128, 132], crack: [6, 6, 7], sun: [230, 230, 232]},
  darkNight: {paper: [14, 14, 16], sky0: [9, 9, 11], sky1: [30, 30, 34], far: [44, 44, 48], farShade: [34, 34, 38], snow: [86, 86, 90], mid: [26, 26, 29], mid2: [18, 18, 20], near: [4, 4, 5], rock: [50, 50, 54], rockLight: [84, 84, 88], rockDark: [20, 20, 22], mist: [64, 64, 68], crack: [3, 3, 4], sun: [200, 200, 204]},
};
export const palette = (theme: Theme, night: number): Pal => {
  const a = theme === 'light' ? P.lightDay : P.darkDay, b = theme === 'light' ? P.lightNight : P.darkNight;
  const o = {} as Pal;
  for (const k of Object.keys(a) as (keyof Pal)[]) o[k] = mixc(a[k], b[k], night);
  return o;
};

// ---------- deterministic randomness ----------
export const rng = (seed: number) => {
  let s = (seed * 2654435761) >>> 0 || 1;
  const r = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return r;
};
export type R = () => number;
export const gauss = (r: R) => {
  const u = Math.max(1e-6, r()), v = r();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
};
const h1 = (n: number) => {
  const x = Math.sin(n * 127.1) * 43758.5453;
  return x - Math.floor(x);
};
const vn1 = (x: number) => {
  const i = Math.floor(x), f = x - i;
  const u = f * f * (3 - 2 * f);
  return h1(i) + (h1(i + 1) - h1(i)) * u;
};
export const fbm1 = (x: number, oct = 6, ridged = false) => {
  let s = 0, a = 0.5, fq = 1, n = 0;
  for (let i = 0; i < oct; i++) {
    let v = vn1(x * fq + i * 17.3);
    if (ridged) v = 1 - Math.abs(v * 2 - 1);
    s += v * a;
    n += a;
    a *= 0.5;
    fq *= 2.07;
  }
  return s / n;
};

export type Pt = [number, number];
/** midpoint displacement: the wobbly edge of a watercolour wash */
export const deform = (pts: Pt[], depth: number, v: number, r: R): Pt[] => {
  let cur = pts;
  for (let d = 0; d < depth; d++) {
    const out: Pt[] = [];
    for (let i = 0; i < cur.length; i++) {
      const a = cur[i], b = cur[(i + 1) % cur.length];
      out.push(a);
      const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
      out.push([(a[0] + b[0]) / 2 + gauss(r) * len * v, (a[1] + b[1]) / 2 + gauss(r) * len * v]);
    }
    cur = out;
    v *= 0.6;
  }
  return cur;
};
export const fillPoly = (ctx: CanvasRenderingContext2D, pts: Pt[]) => {
  ctx.beginPath();
  ctx.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
  ctx.closePath();
  ctx.fill();
};
/** a watercolour wash: a solid body plus translucent bleeding layers around its edge */
export const wash = (ctx: CanvasRenderingContext2D, pts: Pt[], c: RGB, r: R, o: {body?: number; layers?: number; a?: number; v?: number; edge?: number} = {}) => {
  const {body = 0.75, layers = 10, a = 0.06, v = 0.02, edge = 0.18} = o;
  ctx.fillStyle = css(c);
  ctx.globalAlpha = body;
  const base = deform(pts, 1, v, r);
  fillPoly(ctx, base);
  ctx.globalAlpha = a;
  for (let i = 0; i < layers; i++) fillPoly(ctx, deform(base, 2, v * 1.6, r));
  if (edge > 0) {
    // pigment pools at the drying edge
    ctx.globalAlpha = edge;
    ctx.strokeStyle = css(mixc(c, [0, 0, 0], 0.25));
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(base[0][0], base[0][1]);
    for (let i = 1; i < base.length; i++) ctx.lineTo(base[i][0], base[i][1]);
    ctx.closePath();
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
};

// ---------- textures ----------
let grainTex: HTMLCanvasElement | null = null;
export const grain = () => {
  if (grainTex) return grainTex;
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const x = c.getContext('2d')!;
  const r = rng(99);
  const img = x.createImageData(256, 256);
  for (let i = 0; i < 256 * 256; i++) {
    const v = r();
    img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = 0;
    img.data[i * 4 + 3] = v > 0.9 ? Math.floor((v - 0.9) * 300) : Math.floor(v * 10);
  }
  x.putImageData(img, 0, 0);
  // fibres
  x.strokeStyle = 'rgba(0,0,0,0.035)';
  for (let i = 0; i < 70; i++) {
    x.beginPath();
    const a = r() * Math.PI, l = 6 + r() * 20, px = r() * 256, py = r() * 256;
    x.moveTo(px, py);
    x.quadraticCurveTo(px + Math.cos(a) * l * 0.5 + r() * 4, py + Math.sin(a) * l * 0.5, px + Math.cos(a) * l, py + Math.sin(a) * l);
    x.stroke();
  }
  grainTex = c;
  return c;
};
export const granulate = (ctx: CanvasRenderingContext2D, w: number, h: number, amt: number) => {
  ctx.save();
  ctx.globalCompositeOperation = 'source-atop';
  ctx.globalAlpha = amt;
  ctx.fillStyle = ctx.createPattern(grain(), 'repeat')!;
  ctx.fillRect(0, 0, w, h);
  ctx.restore();
};

// ---------- layout ----------
export type Layout = {
  // positions of everything, in canvas pixels
 horizon: number; peakX: number; peakTop: number; peakHalf: number; ridgeY: number; ledgeTop: number; ledgeX: number; rockX: number; rockW: number; treeX: number; treeH: number; sunX: number; tall: boolean};
export const layoutFor = (w: number, h: number): Layout => {
  if (w / h > 1.2)
    return {horizon: 0.64 * h, peakX: 0.6 * w, peakTop: 0.1 * h, peakHalf: 0.3 * w, ridgeY: 0.6 * h, ledgeTop: 0.8 * h, ledgeX: 0.47 * w, rockX: 0.665 * w, rockW: 0.15 * w, treeX: 0.9 * w, treeH: 0.7 * h, sunX: 0.79 * w, tall: false};
  return {horizon: 0.8 * h, peakX: 0.44 * w, peakTop: 0.57 * h, peakHalf: 0.62 * w, ridgeY: 0.77 * h, ledgeTop: 0.885 * h, ledgeX: 0.02 * w, rockX: 0.42 * w, rockW: 0.36 * w, treeX: 0.84 * w, treeH: 0.36 * h, sunX: 0.7 * w, tall: true};
};

// ---------- the layers ----------
export const paintSky = (ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, r: R) => {
  const g = ctx.createLinearGradient(0, 0, 0, L.horizon);
  g.addColorStop(0, css(pal.sky0));
  g.addColorStop(1, css(pal.sky1));
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  // soft cloud washes, long and thin
  for (let i = 0; i < 7; i++) {
    const cy = L.horizon * (0.12 + r() * 0.6), cx = w * (0.3 + r() * 0.8), cw = w * (0.15 + r() * 0.3), ch = h * (0.012 + r() * 0.025);
    const pts: Pt[] = [];
    for (let k = 0; k < 14; k++) {
      const a = (k / 14) * Math.PI * 2;
      pts.push([cx + Math.cos(a) * cw * (0.8 + r() * 0.3), cy + Math.sin(a) * ch * (0.7 + r() * 0.5)]);
    }
    wash(ctx, pts, mixc(pal.sky1, pal.sky0, 0.25), r, {body: 0.2, layers: 6, a: 0.04, v: 0.05, edge: 0});
  }
};

export const ridgePts = (x0: number, x1: number, n: number, f: (x: number, u: number) => number): Pt[] => {
  const pts: Pt[] = [];
  for (let i = 0; i <= n; i++) {
    const u = i / n, x = x0 + (x1 - x0) * u;
    pts.push([x, f(x, u)]);
  }
  return pts;
};

export const softmin = (a: number, b: number, k: number) => -k * Math.log(Math.exp(-a / k) + Math.exp(-b / k));
/** mist rising from the valley: each layer dissolves toward its base */
export const fadeBase = (ctx: CanvasRenderingContext2D, poly: Pt[], y0: number, y1: number, mist: RGB, amt: number) => {
  ctx.save();
  ctx.beginPath();
  ctx.moveTo(poly[0][0], poly[0][1]);
  for (const p of poly) ctx.lineTo(p[0], p[1]);
  ctx.closePath();
  ctx.clip();
  const g = ctx.createLinearGradient(0, y0, 0, y1);
  g.addColorStop(0, css(mist, 0));
  g.addColorStop(1, css(mist, amt));
  ctx.fillStyle = g;
  ctx.fillRect(-10, y0, 1e5, y1 - y0 + 1e4);
  ctx.restore();
};
export const trees = (ctx: CanvasRenderingContext2D, w: number, ry: (x: number) => number, tH: number, c: RGB, r: R, dens: number) => {
  ctx.fillStyle = css(c);
  for (let x = -0.03 * w; x < 1.03 * w; x += tH * dens * (0.25 + r() * 0.5)) {
    const patch = fbm1(x / (w * 0.06) + dens * 10, 3);
    if (patch < 0.45) continue;
    const th = tH * (0.45 + r() * 0.9) * (0.6 + patch), by = ry(x) + th * 0.3, tw = th * (0.16 + r() * 0.08);
    ctx.beginPath();
    ctx.moveTo(x, by - th);
    // a ragged spruce: three stacked tiers
    for (let k = 1; k <= 3; k++) {
      ctx.lineTo(x + tw * (k / 3) * (1 + r() * 0.3), by - th + (th * k) / 3.2);
      ctx.lineTo(x + tw * (k / 3) * 0.45, by - th + (th * k) / 3.2 - th * 0.04);
    }
    ctx.lineTo(x + tw * 0.15, by);
    ctx.lineTo(x - tw * 0.15, by);
    for (let k = 3; k >= 1; k--) {
      ctx.lineTo(x - tw * (k / 3) * 0.45, by - th + (th * k) / 3.2 - th * 0.04);
      ctx.lineTo(x - tw * (k / 3) * (1 + r() * 0.3), by - th + (th * k) / 3.2);
    }
    ctx.closePath();
    ctx.fill();
  }
};

export const paintFar = (ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, r: R, seed: number, S: Scene, o: {back?: boolean; peak?: boolean; ridges?: boolean} = {}) => {
  const {back: doBack = true, peak: doPeak = true, ridges: doRidges = true} = o;
  const sx = seed * 3.1;
  // distant range behind the peak, very pale
  const back = ridgePts(-0.05 * w, 1.05 * w, 200, (x) => L.horizon - h * 0.05 - fbm1(x / (w * 0.1) + sx, 6, true) * h * 0.12 - fbm1(x / (w * 0.02) + sx, 3, true) * h * 0.015);
  const backPoly: Pt[] = [...back, [1.05 * w, h], [-0.05 * w, h]];
  if (doBack) wash(ctx, backPoly, mixc(pal.far, pal.sky1, 0.55), r, {body: 0.8, layers: 6, a: 0.05, v: 0.004, edge: 0.06});
  if (doBack) fadeBase(ctx, backPoly, L.horizon - h * 0.12, L.horizon + h * 0.02, pal.mist, 0.9);
  if (doPeak) {
  // the massif: a main summit with two lower shoulders, craggy at every scale
  const base = L.horizon + h * 0.02;
  const cone = (x: number, cx: number, top: number, half: number) => top + Math.pow(Math.abs(x - cx) / half, 0.8) * (base - top);
  const vis = 0.5 + 0.5 * S.peak;
  const peakY = (x: number) => {
    const m = softmin(
      softmin(cone(x, L.peakX, L.peakTop, L.peakHalf), cone(x, L.peakX + L.peakHalf * 0.55, L.peakTop + (base - L.peakTop) * 0.3, L.peakHalf * 0.6), h * 0.02),
      cone(x, L.peakX - L.peakHalf * 0.6, L.peakTop + (base - L.peakTop) * 0.42, L.peakHalf * 0.55),
      h * 0.02,
    );
    const hf = Math.max(0, (base - m) / (base - L.peakTop));
    return m - (fbm1(x / (w * 0.08) + sx + 9, 5, true) - 0.5) * h * 0.09 * (0.3 + hf) - (fbm1(x / (w * 0.022) + sx + 4, 4, true) - 0.5) * h * 0.028 * (0.2 + hf) - (fbm1(x / (w * 0.006) + sx, 3) - 0.5) * h * 0.008;
  };
  const N = 320;
  const x0 = L.peakX - L.peakHalf * 1.6, x1 = L.peakX + L.peakHalf * 1.6;
  const pk = ridgePts(x0, x1, N, (x) => Math.min(base, peakY(x)));
  const peakPoly: Pt[] = [...pk, [x1, h], [x0, h]];
  wash(ctx, peakPoly, mixc(pal.sky1, pal.far, vis), r, {body: 0.92, layers: 8, a: 0.05, v: 0.003, edge: 0.14});
  ctx.save();
  ctx.beginPath();
  ctx.moveTo(peakPoly[0][0], peakPoly[0][1]);
  for (const p of peakPoly) ctx.lineTo(p[0], p[1]);
  ctx.closePath();
  ctx.clip();
  // shade: every face that falls away to the right, down from its own summit
  const shade = mixc(pal.sky1, pal.farShade, vis);
  for (let i = 2; i < N - 2; i++) {
    const isMax = pk[i][1] < pk[i - 1][1] && pk[i][1] <= pk[i + 1][1] && pk[i][1] < pk[i - 2][1] && pk[i][1] <= pk[i + 2][1];
    if (!isMax) continue;
    let j = i + 1;
    while (j < N - 1 && pk[j + 1][1] >= pk[j][1] - 0.5) j++;
    if (pk[j][0] - pk[i][0] < w * 0.008) continue;
    const top = pk[i], len = base - top[1];
    const spine: Pt[] = [];
    for (let k = 0; k <= 16; k++) {
      const u = k / 16;
      spine.push([top[0] + u * (pk[j][0] - top[0]) * 0.45 + (r() - 0.5) * w * 0.008 + u * u * len * 0.15, top[1] + u * len]);
    }
    const poly: Pt[] = [...pk.slice(i, j + 1), [pk[j][0] + len * 0.2, base + 4], ...spine.reverse()];
    ctx.globalAlpha = 0.85;
    ctx.fillStyle = css(shade);
    fillPoly(ctx, deform(poly, 1, 0.004, r));
    ctx.globalAlpha = 1;
  }
  // gullies
  ctx.lineCap = 'round';
  for (let k = 0; k < 26; k++) {
    const x = L.peakX + (r() - 0.5) * L.peakHalf * 2.2;
    const y0 = peakY(x) + h * 0.01;
    const len = (base - y0) * (0.2 + r() * 0.5);
    ctx.strokeStyle = css(shade, 0.12 + r() * 0.12);
    ctx.lineWidth = Math.max(2, w * 0.006 * (0.5 + r()));
    ctx.beginPath();
    ctx.moveTo(x, y0);
    let px = x, py = y0;
    for (let s2 = 0; s2 < 6; s2++) {
      px += (r() - 0.45) * len * 0.12;
      py += len / 6;
      ctx.lineTo(px, py);
    }
    ctx.stroke();
  }
  // snow, lifted out of the wash along the upper slopes
  for (let k = 0; k < 420; k++) {
    const x = L.peakX + (r() - 0.5) * L.peakHalf * 2.4;
    const y0 = peakY(x) + r() * h * 0.004;
    const hf = (base - y0) / (base - L.peakTop);
    if (hf < 0.5 + r() * 0.15) continue;
    const len = h * (0.015 + r() * 0.06) * hf;
    const dir = x < L.peakX ? -0.4 : 0.35;
    ctx.strokeStyle = css(pal.snow, (0.3 + r() * 0.55) * vis);
    ctx.lineWidth = Math.max(0.7, w * 0.0016 * (0.4 + r()));
    ctx.beginPath();
    ctx.moveTo(x, y0);
    let px = x, py = y0;
    for (let s2 = 0; s2 < 4; s2++) {
      px += dir * len * 0.25 + (r() - 0.5) * len * 0.12;
      py += len * 0.25;
      ctx.lineTo(px, py);
    }
    ctx.stroke();
  }
  ctx.restore();
  fadeBase(ctx, peakPoly, base - (base - L.peakTop) * 0.45, base, pal.mist, 0.95);
  }
  if (doRidges) {
  // forested ridges, each dissolving into the valley mist
  const tH = h * (L.tall ? 0.02 : 0.034);
  const ry = (x: number) => L.ridgeY + h * 0.07 - Math.pow(fbm1(x / (w * 0.22) + sx + 30, 5), 1.6) * h * 0.3 - (fbm1(x / (w * 0.03) + sx, 3, true) - 0.5) * h * 0.02;
  const ridge = ridgePts(-0.05 * w, 1.05 * w, 200, ry);
  const rp: Pt[] = [...ridge, [1.05 * w, h], [-0.05 * w, h]];
  wash(ctx, rp, pal.mid, r, {body: 0.9, layers: 6, a: 0.05, v: 0.003, edge: 0.12});
  trees(ctx, w, ry, tH, pal.mid, r, 0.9);
  fadeBase(ctx, rp, L.ridgeY - h * 0.02, L.ridgeY + h * 0.08, pal.mist, 0.95);
  const ry2 = (x: number) => L.ridgeY + h * (L.tall ? 0.1 : 0.17) - Math.pow(fbm1(x / (w * 0.16) + sx + 60, 5), 1.6) * h * 0.24 - (fbm1(x / (w * 0.025) + sx + 2, 3, true) - 0.5) * h * 0.016;
  const ridge2 = ridgePts(-0.05 * w, 1.05 * w, 200, ry2);
  const rp2: Pt[] = [...ridge2, [1.05 * w, h], [-0.05 * w, h]];
  wash(ctx, rp2, pal.mid2, r, {body: 0.92, layers: 6, a: 0.05, v: 0.003, edge: 0.12});
  trees(ctx, w, ry2, tH * 1.5, pal.mid2, r, 0.8);
  fadeBase(ctx, rp2, L.ridgeY + h * 0.06, L.ridgeY + h * 0.18, pal.mist, 0.92);
  }
  granulate(ctx, w, h, 0.25);
};

/** a wind-swept pine on a cliff: gnarled trunk, branches reaching for the open air, needle tufts */
export const paintPine = (ctx: CanvasRenderingContext2D, bx: number, by: number, H: number, g: number, c: RGB, r: R, scale: number) => {
  const hh = H * (0.14 + 0.86 * g);
  const ph = r() * 6;
  const tp = (u: number): Pt => [bx + hh * (-0.1 * u - 0.05 * u * u + 0.045 * Math.sin(u * 5.5 + ph) * u), by - u * hh];
  const tw = Math.max(1.4, hh * 0.04);
  const left: Pt[] = [], right: Pt[] = [];
  for (let i = 0; i <= 30; i++) {
    const u = i / 30, p = tp(u), wd = tw * Math.pow(1 - u, 0.8) * (1 + (i < 3 ? (3 - i) * 0.35 : 0)) + 0.5;
    left.push([p[0] - wd, p[1]]);
    right.push([p[0] + wd, p[1]]);
  }
  ctx.fillStyle = css(c);
  fillPoly(ctx, [...left, ...right.reverse()]);
  ctx.strokeStyle = css(c);
  ctx.lineCap = 'round';
  for (let k = 0; k < 5; k++) {
    ctx.lineWidth = tw * (0.35 + r() * 0.35);
    const d = (k < 2 ? -1 : 1) * (0.6 + r() * 1.2) * tw * 3;
    ctx.beginPath();
    ctx.moveTo(bx, by - tw * 0.5);
    ctx.quadraticCurveTo(bx + d * 0.5, by + tw * 0.1, bx + d, by + tw * (0.6 + r()));
    ctx.stroke();
  }
  const lw = Math.max(0.55, 0.75 * scale);
  const tuft = (x: number, y: number, sz: number) => {
    // dense core, then needles fanning up and out, a few drooping
    ctx.globalAlpha = 0.9;
    ctx.fillStyle = css(c);
    const core: Pt[] = [];
    for (let k = 0; k < 10; k++) {
      const a = (k / 10) * Math.PI * 2;
      core.push([x + Math.cos(a) * sz * (0.35 + r() * 0.2), y + Math.sin(a) * sz * (0.14 + r() * 0.1) + sz * 0.05]);
    }
    fillPoly(ctx, core);
    ctx.lineWidth = lw;
    ctx.globalAlpha = 0.8;
    ctx.beginPath();
    const n = 18 + Math.floor(sz * 0.8);
    for (let k = 0; k < n; k++) {
      const up = r() < 0.78;
      const a = up ? -Math.PI / 2 + (r() - 0.5) * 2.5 : Math.PI / 2 + (r() - 0.5) * 1.8;
      const l = sz * (up ? 0.3 + r() * 0.45 : 0.15 + r() * 0.25);
      const ox = x + (r() - 0.5) * sz * 0.8, oy = y + (r() - 0.5) * sz * 0.18;
      ctx.moveTo(ox, oy);
      ctx.quadraticCurveTo(ox + Math.cos(a) * l * 0.5 + (r() - 0.5) * l * 0.2, oy + Math.sin(a) * l * 0.5, ox + Math.cos(a) * l, oy + Math.sin(a) * l * (up ? 0.8 : 1));
    }
    ctx.stroke();
    ctx.globalAlpha = 1;
  };
  const n = Math.max(2, Math.round(3 + 8 * g));
  const tsz = hh * 0.055;
  for (let i = 0; i < n; i++) {
    const u = 0.28 + 0.68 * Math.pow(i / Math.max(1, n - 1), 0.9);
    const [tx, ty] = tp(u);
    const side = r() < 0.66 ? -1 : 1;
    const len = hh * (0.42 * (1 - u) + 0.1) * (side < 0 ? 1.25 : 0.75) * (0.8 + r() * 0.4);
    const rise = -hh * (0.03 + r() * 0.04);
    const ex = tx + side * len, ey = ty + rise + hh * 0.04 * r();
    const cx = tx + side * len * 0.45, cy = ty + rise * 1.6;
    ctx.strokeStyle = css(c);
    ctx.lineWidth = Math.max(0.9, tw * 0.55 * (1 - u * 0.6));
    ctx.beginPath();
    ctx.moveTo(tx, ty);
    ctx.quadraticCurveTo(cx, cy, ex, ey);
    ctx.stroke();
    // tufts along the outer two thirds of the branch, the pad thickest near its end
    const m = Math.max(3, Math.round(len / (tsz * 0.55)));
    for (let k = 0; k < m; k++) {
      const v = 0.35 + 0.65 * (k / (m - 1));
      const bxp = (1 - v) * (1 - v) * tx + 2 * (1 - v) * v * cx + v * v * ex;
      const byp = (1 - v) * (1 - v) * ty + 2 * (1 - v) * v * cy + v * v * ey;
      const sz = tsz * (0.75 + Math.sin(v * Math.PI) * 0.6) * (0.85 + r() * 0.3);
      tuft(bxp + (r() - 0.5) * tsz * 0.4, byp - sz * 0.1 + (r() - 0.5) * tsz * 0.2, sz);
      if (r() < 0.45) tuft(bxp + (r() - 0.5) * tsz, byp - sz * 0.35, sz * 0.7);
    }
  }
  const top = tp(1);
  for (let k = 0; k < 5; k++) tuft(top[0] + (r() - 0.5) * tsz * 1.6, top[1] + (r() - 0.2) * tsz * 0.6, tsz * (0.9 + r() * 0.4));
};

export const paintNear = (ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, r: R, seed: number, S: Scene) => {
  const sx = seed * 5.3;
  // the ledge: a dark rock shelf breaking off on its left
  const top = (x: number) => L.ledgeTop + (fbm1(x / (w * 0.05) + sx, 6, true) - 0.5) * h * 0.035 + Math.max(0, (L.ledgeX + w * 0.06 - x) / (w * 0.06)) * h * 0.06;
  const edge: Pt[] = [];
  for (let i = 0; i <= 30; i++) {
    const u = i / 30;
    edge.push([L.ledgeX + (fbm1(u * 6 + sx + 3, 5) - 0.5) * w * 0.05 + u * u * w * 0.02, h + 2 - u * (h + 2 - top(L.ledgeX + w * 0.02))]);
  }
  const shelf = ridgePts(L.ledgeX + w * 0.02, w * 1.05, 120, (x) => top(x));
  const poly: Pt[] = [...edge, ...shelf, [w * 1.05, h + 2]];
  wash(ctx, poly, pal.near, r, {body: 0.94, layers: 10, a: 0.06, v: 0.004, edge: 0.2});
  // strata on the cliff face, lifted a touch lighter
  ctx.strokeStyle = css(mixc(pal.near, pal.rockLight, 0.35), 0.35);
  ctx.lineWidth = Math.max(1, w / 900);
  for (let i = 0; i < 26; i++) {
    const x0 = L.ledgeX + r() * w * 0.35, y0 = top(x0) + r() * (h - top(x0));
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    let px = x0, py = y0;
    for (let k = 0; k < 5; k++) {
      px += w * 0.012 * (0.5 + r());
      py += (r() - 0.35) * h * 0.012;
      ctx.lineTo(px, py);
    }
    ctx.stroke();
  }
  // past weeks' rocks, broken in two, lying on the shelf
  const n = Math.min(7, S.rubble);
  for (let i = 0; i < n; i++) {
    const rr = rng(seed * 31 + i * 7);
    const u = L.tall ? [0.1, 0.2, 0.66, 0.74, 0.04, 0.6, 0.28][i] : [0.53, 0.585, 0.785, 0.745, 0.505, 0.83, 0.61][i];
    const x = u * w, s2 = L.rockW * (0.2 + rr() * 0.1);
    const y = top(x) + s2 * 0.1;
    for (const side of [-1, 1]) {
      const pts: Pt[] = [];
      const m = 8;
      for (let k = 0; k <= m; k++) {
        const a = Math.PI + (k / m) * Math.PI;
        const rad = 0.75 + rr() * 0.3;
        pts.push([x + side * s2 * 0.32 + Math.cos(a) * s2 * 0.42 * rad, y + Math.sin(a) * s2 * 0.5 * rad * (side < 0 ? 1 : 0.8)]);
      }
      const body = mixc(pal.rock, pal.near, 0.45);
      ctx.fillStyle = css(body);
      fillPoly(ctx, deform(pts, 1, 0.03, rr));
      ctx.save();
      ctx.beginPath();
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (const p of pts) ctx.lineTo(p[0], p[1]);
      ctx.closePath();
      ctx.clip();
      const gr = ctx.createLinearGradient(0, y - s2 * 0.5, 0, y);
      gr.addColorStop(0, css(pal.rockLight, 0.35));
      gr.addColorStop(1, css(pal.near, 0.5));
      ctx.fillStyle = gr;
      ctx.fillRect(x - s2, y - s2, s2 * 2, s2);
      ctx.restore();
    }
  }
  // the pine, growing at the shelf's edge
  paintPine(ctx, L.treeX, top(L.treeX) + h * 0.004, L.treeH, S.tree, pal.near, r, w / 1000);
  granulate(ctx, w, h, 0.15);
};

// ---------- the boulder ----------
type Boulder = {outline: Pt[]; cracks: Pt[][]; cx: number; by: number; bw: number; bh: number};
const boulderOf = (L: Layout, seed: number, w: number, h: number): Boulder => {
  const r = rng(seed * 13 + 5);
  const bw = L.rockW, bh = bw * 0.8, cx = L.rockX, by = L.ledgeTop + h * 0.01;
  const cy = by - bh * 0.42;
  const outline: Pt[] = [];
  const M = 56;
  for (let k = 0; k < M; k++) {
    const a = (k / M) * Math.PI * 2;
    const rad = 1 + (fbm1(k * 0.22 + seed * 1.7, 4) - 0.5) * 0.24 + (fbm1(k * 0.9 + seed, 2) - 0.5) * 0.05;
    const sq = 1;
    outline.push([cx + Math.cos(a) * bw * 0.5 * rad, Math.min(by + 2, cy + Math.sin(a) * bh * 0.55 * rad * sq)]);
  }
  const topAt = (x: number) => {
    let best = by;
    for (const p of outline) if (Math.abs(p[0] - x) < bw * 0.04 && p[1] < best) best = p[1];
    return best;
  };
  const cracks: Pt[][] = [];
  const starts = [0.5, 0.3, 0.68, 0.4, 0.6];
  for (let c = 0; c < 5; c++) {
    const pts: Pt[] = [];
    const sx = cx + (starts[c] - 0.5) * bw * 0.9;
    let x = sx, y = topAt(sx) + bh * 0.02;
    const end = c === 0 ? by : y + bh * (0.3 + r() * 0.25);
    const drift = c === 0 ? 0 : (c % 2 ? -1 : 1) * bw * 0.06;
    pts.push([x, y]);
    const steps = c === 0 ? 14 : 8;
    for (let k = 1; k <= steps; k++) {
      y += (end - y) / (steps - k + 1);
      x += drift / steps + (r() - 0.5) * bw * 0.05;
      pts.push([x, y]);
    }
    cracks.push(pts);
  }
  return {outline, cracks, cx, by, bw, bh};
};
const partial = (pts: Pt[], p: number): Pt[] => {
  if (p >= 1) return pts;
  const n = (pts.length - 1) * Math.max(0, p);
  const k = Math.floor(n), f = n - k;
  const out = pts.slice(0, k + 1);
  if (k < pts.length - 1) out.push([pts[k][0] + (pts[k + 1][0] - pts[k][0]) * f, pts[k][1] + (pts[k + 1][1] - pts[k][1]) * f]);
  return out;
};
export const paintBoulder = (ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, seed: number, S: Scene) => {
  const B = boulderOf(L, seed, w, h);
  const r = rng(seed * 7 + 1);
  const drop = S.rockIn != null ? -Math.pow(1 - S.rockIn, 2) * h * 0.25 : 0;
  const halves = S.broken > 0.001 ? [-1, 1] : [0];
  const shadow = ctx.createRadialGradient(B.cx + B.bw * 0.08, B.by, 0, B.cx + B.bw * 0.08, B.by, B.bw * 0.7);
  shadow.addColorStop(0, css(pal.near, 0.75));
  shadow.addColorStop(1, css(pal.near, 0));
  ctx.save();
  ctx.translate(B.cx, B.by);
  ctx.scale(1, 0.12);
  ctx.translate(-B.cx, -B.by);
  ctx.fillStyle = shadow;
  ctx.beginPath();
  ctx.arc(B.cx + B.bw * 0.08, B.by, B.bw * 0.7, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
  for (const side of halves) {
    ctx.save();
    if (side !== 0) {
      const ang = side * S.broken * 0.11;
      const dx = side * S.broken * B.bw * 0.13;
      const pivot: Pt = [B.cx + side * B.bw * 0.42, B.by];
      ctx.translate(pivot[0] + dx, pivot[1]);
      ctx.rotate(ang);
      ctx.translate(-pivot[0], -pivot[1]);
      ctx.beginPath();
      const c0 = B.cracks[0];
      ctx.moveTo(c0[0][0], c0[0][1] - B.bh);
      for (const p of c0) ctx.lineTo(p[0], p[1]);
      ctx.lineTo(c0[c0.length - 1][0], B.by + 4);
      ctx.lineTo(B.cx + side * B.bw, B.by + 4);
      ctx.lineTo(B.cx + side * B.bw, B.by - B.bh * 1.5);
      ctx.closePath();
      ctx.clip();
    }
    ctx.translate(0, drop);
    const body = B.outline;
    ctx.fillStyle = css(pal.rock);
    fillPoly(ctx, body);
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(body[0][0], body[0][1]);
    for (const p of body) ctx.lineTo(p[0], p[1]);
    ctx.closePath();
    ctx.clip();
    // light from the upper left, the underside in shadow
    const hx = B.cx - B.bw * 0.2, hy = B.by - B.bh * 0.78;
    const lg = ctx.createRadialGradient(hx, hy, 0, hx, hy, B.bw * 0.7);
    lg.addColorStop(0, css(pal.rockLight, 0.95));
    lg.addColorStop(0.5, css(pal.rockLight, 0.35));
    lg.addColorStop(1, css(pal.rockLight, 0));
    ctx.fillStyle = lg;
    ctx.fillRect(B.cx - B.bw, B.by - B.bh * 1.5, B.bw * 2, B.bh * 1.6);
    const dg = ctx.createLinearGradient(B.cx - B.bw * 0.2, B.by - B.bh * 0.7, B.cx + B.bw * 0.3, B.by);
    dg.addColorStop(0, css(pal.rockDark, 0));
    dg.addColorStop(0.55, css(pal.rockDark, 0.35));
    dg.addColorStop(1, css(pal.rockDark, 0.95));
    ctx.fillStyle = dg;
    ctx.fillRect(B.cx - B.bw, B.by - B.bh * 1.5, B.bw * 2, B.bh * 1.6);
    // watercolour mottling, facets and pits
    for (let k = 0; k < 10; k++) {
      const px = B.cx + (r() - 0.5) * B.bw * 0.9, py = B.by - r() * B.bh * 0.9, rw = B.bw * (0.08 + r() * 0.16);
      const pts: Pt[] = [];
      for (let q = 0; q < 9; q++) {
        const a = (q / 9) * Math.PI * 2;
        pts.push([px + Math.cos(a) * rw * (0.6 + r() * 0.5), py + Math.sin(a) * rw * 0.5 * (0.6 + r() * 0.5)]);
      }
      ctx.globalAlpha = 0.12;
      ctx.fillStyle = css(r() < 0.5 ? pal.rockDark : pal.rockLight);
      fillPoly(ctx, deform(pts, 2, 0.06, r));
    }
    ctx.globalAlpha = 0.28;
    ctx.strokeStyle = css(pal.rockDark);
    ctx.lineWidth = Math.max(0.8, B.bw * 0.006);
    for (let k = 0; k < 7; k++) {
      const px = B.cx + (r() - 0.5) * B.bw * 0.8, py = B.by - (0.15 + r() * 0.7) * B.bh;
      ctx.beginPath();
      ctx.moveTo(px, py);
      ctx.lineTo(px + B.bw * (0.05 + r() * 0.12), py + (r() - 0.3) * B.bh * 0.12);
      ctx.stroke();
    }
    for (let k = 0; k < 120; k++) {
      const x = B.cx + (r() - 0.5) * B.bw, y = B.by - r() * B.bh;
      ctx.globalAlpha = 0.3;
      ctx.fillStyle = r() < 0.6 ? css(pal.rockDark) : css(pal.rockLight);
      ctx.beginPath();
      ctx.arc(x, y, Math.max(0.5, r() * B.bw * 0.006), 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
    ctx.restore();
    // a dark rim where it meets the light
    ctx.globalAlpha = 0.35;
    ctx.strokeStyle = css(pal.rockDark);
    ctx.lineWidth = Math.max(1, B.bw * 0.008);
    ctx.beginPath();
    ctx.moveTo(body[0][0], body[0][1]);
    for (const p of body) ctx.lineTo(p[0], p[1]);
    ctx.closePath();
    ctx.stroke();
    ctx.globalAlpha = 1;
    // cracks: a dark fissure with a lit lip
    const lw = Math.max(1.2, B.bw * 0.013);
    for (let c = 0; c < 5; c++) {
      const p = Math.min(1, Math.max(0, S.cracks - c));
      if (p <= 0 || (side !== 0 && c === 0)) continue;
      const pts = partial(B.cracks[c], p);
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      ctx.strokeStyle = css(pal.rockLight, 0.6);
      ctx.lineWidth = lw * 0.7;
      ctx.beginPath();
      pts.forEach((q, i) => (i ? ctx.lineTo(q[0] - lw * 0.75, q[1] - lw * 0.4) : ctx.moveTo(q[0] - lw * 0.75, q[1] - lw * 0.4)));
      ctx.stroke();
      ctx.strokeStyle = css(pal.crack, 0.95);
      ctx.lineWidth = lw * (c === 0 ? 1.4 : 1);
      ctx.beginPath();
      pts.forEach((q, i) => (i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1])));
      ctx.stroke();
      ctx.lineWidth = lw * 0.4;
      for (let k = 2; k < pts.length - 1; k += 3) {
        const q = pts[k];
        const d = (k % 2 ? 1 : -1) * B.bw * 0.045;
        ctx.beginPath();
        ctx.moveTo(q[0], q[1]);
        ctx.lineTo(q[0] + d, q[1] + B.bh * 0.035);
        ctx.lineTo(q[0] + d * 1.5, q[1] + B.bh * 0.025);
        ctx.stroke();
      }
    }
    ctx.restore();
  }
  if (S.broken > 0.3) {
    for (let k = 0; k < 8; k++) {
      const x = B.cx + (r() - 0.5) * B.bw * 1.1, s2 = B.bw * (0.02 + r() * 0.035);
      ctx.fillStyle = css(mixc(pal.rock, pal.near, 0.3), Math.min(1, (S.broken - 0.3) * 2));
      ctx.beginPath();
      ctx.moveTo(x - s2, B.by + 1);
      ctx.lineTo(x - s2 * 0.3, B.by - s2 * 0.9);
      ctx.lineTo(x + s2, B.by - s2 * 0.3);
      ctx.lineTo(x + s2 * 0.8, B.by + 1);
      ctx.closePath();
      ctx.fill();
    }
  }
};
export const boulderGeom = (w: number, h: number, seed: number) => boulderOf(layoutFor(w, h), seed, w, h);

// ---------- mist ----------
export const paintMist = (ctx: CanvasRenderingContext2D, w: number, h: number, ys: number[], pal: Pal, r: R) => {
  for (const y of ys) {
    for (let i = 0; i < 22; i++) {
      const cx = r() * w, cy = y + (r() - 0.5) * h * 0.06, cw = w * (0.12 + r() * 0.22), ch = h * (0.02 + r() * 0.035);
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, cw);
      g.addColorStop(0, css(pal.mist, 0.5));
      g.addColorStop(1, css(pal.mist, 0));
      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(1, ch / cw);
      ctx.translate(-cx, -cy);
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(cx, cy, cw, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
  }
};

// ---------- the painter with its caches ----------
type Cache = {key: string; c: HTMLCanvasElement};
const mk = (w: number, h: number) => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
};

export class Painter {
  /** the transform the scene is drawn with (a camera can move it) */
  xf: [number, number, number, number, number, number] = [1, 0, 0, 1, 0, 0];
  sky: Cache | null = null;
  far: Cache | null = null;
  near: Cache | null = null;
  rock: Cache | null = null;
  mist: Cache | null = null;
  front: Cache | null = null;
  paper: Cache | null = null;
  layer = (slot: 'sky' | 'far' | 'near' | 'rock' | 'mist' | 'front' | 'paper', key: string, w: number, h: number, paint: (ctx: CanvasRenderingContext2D) => void) => {
    const cur = this[slot];
    if (cur && cur.key === key) return cur.c;
    const c = cur && cur.c.width === w && cur.c.height === h ? cur.c : mk(w, h);
    const ctx = c.getContext('2d')!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    paint(ctx);
    this[slot] = {key, c};
    return c;
  };
  /** paints the scene into ctx at device size w×h */
  render(ctx: CanvasRenderingContext2D, w: number, h: number, S: Scene, theme: Theme, t: number) {
    const night = Math.round(S.night * 4) / 4;
    const pal = palette(theme, night);
    const L = layoutFor(w, h);
    const base = `${w}x${h}:${theme}:${S.seed}:${night}`;
    const sky = this.layer('sky', base, w, h, (c) => paintSky(c, w, h, L, pal, rng(S.seed)));
    const far = this.layer('far', `${base}:${S.peak.toFixed(2)}`, w, h, (c) => paintFar(c, w, h, L, pal, rng(S.seed + 1), S.seed, S));
    const near = this.layer('near', `${base}:${S.tree.toFixed(3)}:${S.rubble}`, w, h, (c) => paintNear(c, w, h, L, pal, rng(S.seed + 2), S.seed, S));
    const rock = this.layer('rock', `${base}:${S.cracks.toFixed(3)}:${S.broken.toFixed(3)}:${(S.rockIn ?? 1).toFixed(3)}`, w, h, (c) => paintBoulder(c, w, h, L, pal, S.seed, S));
    const mist = this.layer('mist', `${w}x${h}:${theme}:${night}`, w * 2, h, (c) => paintMist(c, w * 2, h, [L.horizon, L.ridgeY + h * 0.1], pal, rng(7)));
    const front = this.layer('front', `${w}x${h}:${theme}:${night}`, w * 2, h, (c) => paintMist(c, w * 2, h, [L.ledgeTop + h * 0.1, h * 0.98], pal, rng(8)));
    const paper = this.layer('paper', `${w}x${h}`, w, h, (c) => {
      c.fillStyle = c.createPattern(grain(), 'repeat')!;
      c.fillRect(0, 0, w, h);
    });

    ctx.setTransform(...this.xf);
    const px = Math.sin(t * 0.12) * w * 0.004;
    ctx.drawImage(sky, 0, 0);
    // the sun (or moon), low behind the peak
    const sy = L.horizon - (S.sun + 0.15) * (L.horizon - L.peakTop) * 0.9;
    const sr = Math.min(w, h) * (L.tall ? 0.05 : 0.07);
    const glow = ctx.createRadialGradient(L.sunX, sy, 0, L.sunX, sy, sr * 6);
    glow.addColorStop(0, css(pal.sun, 0.55 * (1 - night * 0.5)));
    glow.addColorStop(1, css(pal.sun, 0));
    ctx.fillStyle = glow;
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = css(pal.sun, 0.92);
    ctx.beginPath();
    ctx.arc(L.sunX, sy, sr * (night > 0.5 ? 0.45 : 0.55), 0, Math.PI * 2);
    ctx.fill();
    ctx.drawImage(far, px * 0.4, 0);
    const mo = S.mist;
    if (mo > 0.01) {
      const off = ((t * w * 0.006) % w) - w;
      ctx.globalAlpha = Math.min(1, mo);
      ctx.drawImage(mist, off, 0);
      ctx.globalAlpha = 1;
    }
    ctx.drawImage(near, px, 0);
    if (!S.noRock) ctx.drawImage(rock, px, 0);
    if (mo > 0.6) {
      const off = ((t * w * 0.012) % w) - w;
      ctx.globalAlpha = Math.min(1, (mo - 0.6) * 1.5);
      ctx.drawImage(front, off, 0);
      ctx.globalAlpha = 1;
    }
    if (S.rain > 0.01) {
      ctx.strokeStyle = css(pal.mist, 0.35 * S.rain);
      ctx.lineWidth = Math.max(1, w / 1200);
      ctx.beginPath();
      const rr = rng(3);
      for (let i = 0; i < 160; i++) {
        const x = (rr() * w * 1.2 + t * w * 0.05) % (w * 1.2) - w * 0.1;
        const y = (rr() * h + t * h * 1.6 * (0.7 + rr() * 0.6)) % h;
        const l = h * 0.04;
        ctx.moveTo(x, y);
        ctx.lineTo(x - l * 0.25, y + l);
      }
      ctx.stroke();
    }
    ctx.globalAlpha = theme === 'light' ? 0.55 : 0.3;
    ctx.globalCompositeOperation = theme === 'light' ? 'multiply' : 'screen';
    ctx.drawImage(paper, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
  }
}

/** a chip of rock flying off as a crack lands (screen space) */
export const drawChips = (ctx: CanvasRenderingContext2D, w: number, h: number, seed: number, at: Pt, bt: number, theme: Theme) => {
  if (bt < 0 || bt > 1.4) return;
  const r = rng(seed * 3 + 11);
  const pal = palette(theme, 0);
  const s = Math.min(w, h);
  for (let i = 0; i < 16; i++) {
    const a = -Math.PI * (0.15 + r() * 0.7), v = s * (0.25 + r() * 0.5);
    const x = at[0] + Math.cos(a) * v * bt, y = at[1] + Math.sin(a) * v * bt + 0.9 * s * bt * bt;
    const z = s * (0.004 + r() * 0.006);
    ctx.fillStyle = css(i % 3 ? pal.rockDark : pal.rockLight, Math.max(0, 1 - bt / 1.4));
    ctx.beginPath();
    ctx.moveTo(x - z, y);
    ctx.lineTo(x, y - z);
    ctx.lineTo(x + z, y + z * 0.4);
    ctx.closePath();
    ctx.fill();
  }
  // a puff of dust
  const g = ctx.createRadialGradient(at[0], at[1], 0, at[0], at[1], s * 0.12 * (0.4 + bt));
  g.addColorStop(0, css(pal.mist, 0.35 * Math.max(0, 1 - bt / 1.2)));
  g.addColorStop(1, css(pal.mist, 0));
  ctx.fillStyle = g;
  ctx.fillRect(at[0] - s * 0.3, at[1] - s * 0.3, s * 0.6, s * 0.6);
};
