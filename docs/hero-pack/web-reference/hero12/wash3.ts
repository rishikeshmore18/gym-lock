/**
 * Ridge, one more layer of life: the small things each day's world needs, drawn over the painted scene
 * every frame. Snow and ice for a frozen streak, fireflies in the pines, a drip that keeps time on the
 * lake, the tide creeping up to a stick, footprints, a beacon on the summit, paper lanterns, a
 * constellation lighting star by star, a shooting star, skipping stones, birds bursting from a crown,
 * and a flash of sunlight.
 */
import {Layout, Theme, css, layoutFor, mixc, palette} from '../hero10/wash';
import {Painter2, Scene2, pathLayout, routeOf} from '../hero10/wash2';

export type Scene3 = Scene2 & {
  snow?: number;
  frozen?: boolean;
  fireflies?: number;
  drip?: boolean;
  tide?: number;
  steps?: number;
  beacon?: number;
  lanterns?: number[]; // release times
  stars?: number; // constellation stars lit, 0..7 (fractional while the next one ignites)
  starLines?: number; // 0..1 the lines between lit stars drawing in
  shoot?: number | null; // time of a shooting star
  skips?: number[]; // times the stone touched the water
  skipN?: number; // touches it takes to reach the far shore
  skipDone?: number | null; // time the stone came to rest on the far shore
  burst?: number | null; // time birds burst up
  burstAt?: 'tree' | 'summit' | 'sun' | 'center';
  flash?: number | null; // time of a flash of light
  ripples?: number; // static rings on still water, one per session
};

/** integer hash, the same on every device */
const rnd = (i: number) => {
  let x = (Math.floor(i * 1000) ^ 0x9e3779b9) >>> 0;
  x = Math.imul(x ^ (x >>> 16), 0x85ebca6b) >>> 0;
  x = Math.imul(x ^ (x >>> 13), 0xc2b2ae35) >>> 0;
  return ((x ^ (x >>> 16)) >>> 0) / 4294967296;
};

/** where the water starts, per kind (matches the painter) */
export const waterline = (kind: string, L: Layout, h: number) => (kind === 'lake' ? (L.tall ? h * 0.8 : h * 0.64) : kind === 'night' ? (L.tall ? h * 0.8 : h * 0.66) : kind === 'beach' ? (L.tall ? h * 0.74 : h * 0.6) : kind === 'sunset' ? (L.tall ? h * 0.76 : h * 0.62) : L.horizon);

/** the constellation: seven stars in the open sky */
export const starPts = (L: Layout, w: number, h: number): [number, number][] => {
  const P = [
    [0.08, 0.62],
    [0.22, 0.38],
    [0.4, 0.5],
    [0.55, 0.22],
    [0.7, 0.42],
    [0.84, 0.18],
    [0.96, 0.4],
  ];
  if (L.tall) return P.map(([x, y]) => [w * (0.12 + x * 0.76), h * (0.47 + y * 0.2)]);
  return P.map(([x, y]) => [w * (0.5 + x * 0.46), h * (0.06 + y * 0.4)]);
};

export class Painter3 extends Painter2 {
  render3(ctx: CanvasRenderingContext2D, w: number, h: number, S: Scene3, theme: Theme, t: number) {
    this.render(ctx, w, h, S, theme, t, () => this.overlay(ctx, w, h, S, theme, t));
  }

  overlay(ctx: CanvasRenderingContext2D, w: number, h: number, S: Scene3, theme: Theme, t: number) {
    const L = layoutFor(w, h);
    const pal = palette(theme, Math.round(S.night * 4) / 4);
    const s = Math.min(w, h);
    const wl = waterline(S.kind, L, h);

    // ---- the sun over the sea of cloud reads clearly once it clears the cloud tops ----
    if (S.kind === 'sunrise') {
      const ct = L.tall ? h * 0.76 : h * 0.6;
      const sx = L.tall ? w * 0.5 : w * 0.7;
      const sy = ct - (S.sun + 0.1) * h * (L.tall ? 0.34 : 0.35);
      const r = Math.min(w, h) * (L.tall ? 0.05 : 0.07);
      const up = Math.min(1, Math.max(0, (ct - r - sy) / (r * 2)));
      if (up > 0) {
        const g = ctx.createRadialGradient(sx, sy, r * 1.05, sx, sy, r * 3.2);
        if (theme === 'light') {
          g.addColorStop(0, css(pal.mid2, 0.26 * up));
          g.addColorStop(1, css(pal.mid2, 0));
        } else {
          g.addColorStop(0, css(pal.sun, 0.3 * up));
          g.addColorStop(1, css(pal.sun, 0));
        }
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(sx, sy, r * 3.2, 0, Math.PI * 2);
        ctx.arc(sx, sy, r * 1.02, 0, Math.PI * 2, true);
        ctx.fill();
      }
    }

    // ---- ripples on still water: one ring per session this week ----
    if (S.ripples) {
      for (let i = 0; i < S.ripples; i++) {
        const x = w * (L.tall ? 0.25 + i * 0.13 : 0.55 + i * 0.08), y = wl + (h - wl) * (0.35 - i * 0.04);
        const ph = (t * 0.35 + i * 0.2) % 1;
        for (let k = 0; k < 2; k++) {
          const p = (ph + k * 0.5) % 1;
          ctx.strokeStyle = css(pal.mist, 0.45 * (1 - p));
          ctx.lineWidth = Math.max(1, w / 800);
          ctx.beginPath();
          ctx.ellipse(x, y, s * 0.06 * (0.3 + p), s * 0.012 * (0.3 + p), 0, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
    }

    // ---- ice on the water ----
    if (S.frozen) {
      const g = ctx.createLinearGradient(0, wl, 0, h);
      g.addColorStop(0, css(pal.mist, 0.55));
      g.addColorStop(1, css(pal.mist, 0.25));
      ctx.fillStyle = g;
      ctx.fillRect(0, wl, w, h - wl);
      ctx.strokeStyle = css(pal.mid2, 0.35);
      ctx.lineWidth = Math.max(1, w / 1000);
      for (let i = 0; i < 9; i++) {
        let x = rnd(i) * w, y = wl + rnd(i + 9) * (h - wl);
        ctx.beginPath();
        ctx.moveTo(x, y);
        for (let k = 0; k < 5; k++) {
          x += (rnd(i * 7 + k) - 0.3) * w * 0.05;
          y += (rnd(i * 5 + k) - 0.5) * (h - wl) * 0.08;
          ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }

    // ---- a drip keeping time on the lake: one drop a second ----
    if (S.drip) {
      const x = L.tall ? w * 0.7 : w * 0.8;
      const y0 = L.tall ? h * 0.66 : h * 0.26;
      const pool = wl + (h - wl) * 0.3;
      // an overhanging pine bough the drops fall from: a curved branch, needles both sides
      const bx0 = w * 1.03, by0 = y0 - s * 0.12;
      const P = (u: number): [number, number] => [bx0 + (x - bx0) * u, by0 + (y0 - by0) * u + Math.sin(u * Math.PI) * s * 0.03];
      ctx.strokeStyle = css(pal.near);
      ctx.lineCap = 'round';
      ctx.lineWidth = Math.max(2, s * 0.012);
      ctx.beginPath();
      for (let k = 0; k <= 20; k++) {
        const [px, py] = P(k / 20);
        k ? ctx.lineTo(px, py) : ctx.moveTo(px, py);
      }
      ctx.stroke();
      ctx.lineWidth = Math.max(1, s * 0.0045);
      ctx.beginPath();
      for (let k = 0; k < 44; k++) {
        const u = k / 44;
        const [px, py] = P(u);
        const len = s * (0.025 + 0.035 * Math.sin(u * Math.PI * 0.9 + 0.2)) * (0.8 + rnd(k) * 0.4);
        // needles sweep toward the tip, one up one down
        ctx.moveTo(px, py);
        ctx.lineTo(px - len * 0.75, py - len * 0.55);
        ctx.moveTo(px, py);
        ctx.lineTo(px - len * 0.7, py + len * 0.65);
      }
      ctx.stroke();
      // the drop gathers at the tip, then falls: one a second
      const ph = t % 1;
      if (ph < 0.55) {
        const g = Math.min(1, ph / 0.55);
        ctx.fillStyle = css(pal.mist, 0.95);
        ctx.beginPath();
        ctx.ellipse(x, y0 + s * 0.012 * g, s * 0.008 * (0.5 + g * 0.5), s * 0.011 * (0.5 + g * 0.5), 0, 0, Math.PI * 2);
        ctx.fill();
      } else {
        const fall = (ph - 0.55) / 0.45;
        const y = y0 + (pool - y0) * fall * fall;
        ctx.fillStyle = css(pal.mist, 0.95);
        ctx.beginPath();
        ctx.ellipse(x, y, s * 0.007, s * 0.014, 0, 0, Math.PI * 2);
        ctx.fill();
      }
      // rings from the last three drops
      for (let k = 0; k < 3; k++) {
        const age = (t % 1) + k; // drops land on the whole second
        if (age > 2.4) continue;
        const p = age / 2.4;
        ctx.strokeStyle = css(pal.mist, 0.8 * (1 - p));
        ctx.lineWidth = Math.max(1.2, w / 600);
        ctx.beginPath();
        ctx.ellipse(x, pool, s * 0.2 * p + 2, s * 0.03 * p + 1, 0, 0, Math.PI * 2);
        ctx.stroke();
      }
    }

    // ---- the tide creeping up the sand towards a stick ----
    if (S.tide != null) {
      const sandY = L.tall ? h * 0.84 : h * 0.78;
      const target = sandY + h * (L.tall ? 0.07 : 0.13);
      const ty = sandY + (target - sandY) * S.tide + Math.sin(t * 1.2) * h * 0.004;
      ctx.fillStyle = css(mixc(pal.mid, pal.mist, 0.35), 0.6);
      ctx.beginPath();
      ctx.moveTo(-5, sandY - h * 0.01);
      for (let i = 0; i <= 40; i++) {
        const x = (i / 40) * w;
        ctx.lineTo(x, ty + Math.sin(x * 0.02 + t * 1.5) * h * 0.006 - (x / w) * h * 0.02);
      }
      ctx.lineTo(w + 5, sandY - h * 0.03);
      ctx.closePath();
      ctx.fill();
      ctx.strokeStyle = css(pal.mist, 0.85);
      ctx.lineWidth = Math.max(1.5, w / 450);
      ctx.beginPath();
      for (let i = 0; i <= 40; i++) {
        const x = (i / 40) * w;
        const y = ty + Math.sin(x * 0.02 + t * 1.5) * h * 0.006 - (x / w) * h * 0.02;
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      ctx.stroke();
      // the stick the water is coming for
      const sx = L.tall ? w * 0.42 : w * 0.6;
      ctx.strokeStyle = css(pal.near);
      ctx.lineWidth = Math.max(2, s * 0.008);
      ctx.beginPath();
      ctx.moveTo(sx, target - (sx / w) * h * 0.02 + h * 0.005);
      ctx.lineTo(sx + s * 0.01, target - (sx / w) * h * 0.02 - s * 0.12);
      ctx.stroke();
      ctx.fillStyle = '#E85D4E';
      ctx.beginPath();
      ctx.moveTo(sx + s * 0.01, target - (sx / w) * h * 0.02 - s * 0.12);
      ctx.lineTo(sx + s * 0.05, target - (sx / w) * h * 0.02 - s * 0.105);
      ctx.lineTo(sx + s * 0.009, target - (sx / w) * h * 0.02 - s * 0.09);
      ctx.closePath();
      ctx.fill();
    }

    // ---- footprints along the shore ----
    if (S.steps != null && S.steps > 0) {
      const n = 16, shown = Math.floor(n * S.steps);
      const sandY = L.tall ? h * 0.84 : h * 0.78;
      for (let i = 0; i < shown; i++) {
        const u = i / n;
        const x = w * (L.tall ? 0.05 + u * 0.6 : 0.42 + u * 0.36);
        const y = h * 0.995 - (h * 0.995 - sandY - h * 0.03) * u + (i % 2 ? -1 : 1) * s * 0.012;
        const sz = s * 0.012 * (1 - u * 0.5);
        ctx.fillStyle = css(pal.rockDark, 0.5 * (0.4 + 0.6 * Math.min(1, (shown - i) / 4)));
        ctx.beginPath();
        ctx.ellipse(x, y, sz * 1.4, sz * 0.7, -0.4, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    // ---- the beacon on the summit ----
    if (S.beacon != null && S.beacon > 0 && S.kind === 'path') {
      const route = routeOf(w, h, L, pathLayout(L, w, h));
      const [bx, by] = route[route.length - 1];
      const b = S.beacon;
      const glow = ctx.createRadialGradient(bx, by, 0, bx, by, s * (0.06 + 0.2 * b));
      glow.addColorStop(0, `rgba(255,236,220,${(0.6 * b).toFixed(3)})`);
      glow.addColorStop(0.35, `rgba(255,200,170,${(0.22 * b).toFixed(3)})`);
      glow.addColorStop(1, 'rgba(255,200,170,0)');
      ctx.fillStyle = glow;
      ctx.fillRect(bx - s, by - s, s * 2, s * 2);
      const fh = s * (0.02 + 0.09 * b);
      for (let k = 0; k < 3; k++) {
        const fl = Math.sin(t * (9 + k * 3) + k) * 0.25;
        const fw = fh * (0.42 - k * 0.1);
        ctx.fillStyle = k === 0 ? '#E85D4E' : k === 1 ? 'rgba(255,170,120,0.95)' : 'rgba(255,240,220,0.95)';
        ctx.beginPath();
        ctx.moveTo(bx + fl * fw, by - fh * (1 - k * 0.25));
        ctx.quadraticCurveTo(bx + fw, by - fh * 0.3, bx, by + fh * 0.05);
        ctx.quadraticCurveTo(bx - fw, by - fh * 0.3, bx + fl * fw, by - fh * (1 - k * 0.25));
        ctx.fill();
      }
      // embers
      for (let i = 0; i < Math.round(18 * b); i++) {
        const p = (t * (0.3 + rnd(i) * 0.4) + rnd(i + 3)) % 1;
        ctx.fillStyle = `rgba(255,${150 + Math.round(rnd(i) * 80)},120,${(0.9 * (1 - p)).toFixed(3)})`;
        ctx.fillRect(bx + Math.sin(p * 6 + i) * s * 0.03 * (1 + p), by - fh - p * s * 0.25, Math.max(1, s * 0.004), Math.max(1, s * 0.004));
      }
    }

    // ---- fireflies ----
    if (S.fireflies) {
      for (let i = 0; i < S.fireflies; i++) {
        const x = w * (L.tall ? 0.1 + rnd(i) * 0.85 : 0.5 + rnd(i) * 0.48) + Math.sin(t * 0.5 + i * 2) * s * 0.03;
        const y = h * (L.tall ? 0.78 + rnd(i + 5) * 0.18 : 0.45 + rnd(i + 5) * 0.45) + Math.cos(t * 0.4 + i) * s * 0.02;
        const bl = Math.max(0, Math.sin(t * (1.5 + rnd(i + 2)) + i * 3));
        const g = ctx.createRadialGradient(x, y, 0, x, y, s * 0.02);
        g.addColorStop(0, `rgba(255,248,220,${(0.85 * bl).toFixed(3)})`);
        g.addColorStop(1, 'rgba(255,248,220,0)');
        ctx.fillStyle = g;
        ctx.fillRect(x - s * 0.02, y - s * 0.02, s * 0.04, s * 0.04);
      }
    }

    // ---- the constellation ----
    if (S.stars != null) {
      const P = starPts(L, w, h);
      const lit = S.stars;
      const lines = S.starLines ?? 0;
      ctx.strokeStyle = css(pal.sun, 0.55);
      ctx.lineWidth = Math.max(1, w / 700);
      ctx.setLineDash([s * 0.008, s * 0.006]);
      ctx.beginPath();
      for (let i = 1; i < P.length; i++) {
        const show = Math.max(lines, Math.min(1, Math.max(0, lit - i)));
        if (show <= 0) continue;
        const [x0, y0] = P[i - 1], [x1, y1] = P[i];
        ctx.moveTo(x0, y0);
        ctx.lineTo(x0 + (x1 - x0) * show, y0 + (y1 - y0) * show);
      }
      ctx.stroke();
      ctx.setLineDash([]);
      P.forEach(([x, y], i) => {
        const on = Math.min(1, Math.max(0, lit - i));
        const tw = 0.8 + 0.2 * Math.sin(t * 3 + i);
        const r = s * (on > 0 ? 0.012 + 0.006 * on : 0.006);
        const g = ctx.createRadialGradient(x, y, 0, x, y, r * 4);
        g.addColorStop(0, css(pal.sun, (on > 0 ? 0.9 : 0.25) * tw));
        g.addColorStop(1, css(pal.sun, 0));
        ctx.fillStyle = g;
        ctx.fillRect(x - r * 4, y - r * 4, r * 8, r * 8);
        ctx.fillStyle = on > 0.99 && i === P.length - 1 ? '#E85D4E' : css(pal.sun, on > 0 ? 1 : 0.4);
        ctx.beginPath();
        // a four-point sparkle
        ctx.moveTo(x, y - r * 1.6);
        ctx.lineTo(x + r * 0.35, y - r * 0.35);
        ctx.lineTo(x + r * 1.6, y);
        ctx.lineTo(x + r * 0.35, y + r * 0.35);
        ctx.lineTo(x, y + r * 1.6);
        ctx.lineTo(x - r * 0.35, y + r * 0.35);
        ctx.lineTo(x - r * 1.6, y);
        ctx.lineTo(x - r * 0.35, y - r * 0.35);
        ctx.closePath();
        ctx.fill();
      });
    }

    // ---- a shooting star ----
    if (S.shoot != null) {
      const p = (t - S.shoot) / 1.1;
      if (p >= 0 && p < 1) {
        const x0 = L.tall ? w * 0.9 : w * 0.98, y0 = L.tall ? h * 0.48 : h * 0.05;
        const x1 = L.tall ? w * 0.1 : w * 0.5, y1 = L.tall ? h * 0.62 : h * 0.4;
        const hx = x0 + (x1 - x0) * p, hy = y0 + (y1 - y0) * p;
        const g = ctx.createLinearGradient(hx, hy, hx - (x1 - x0) * 0.25, hy - (y1 - y0) * 0.25);
        g.addColorStop(0, css(pal.sun, 0.95 * (1 - p * 0.5)));
        g.addColorStop(1, css(pal.sun, 0));
        ctx.strokeStyle = g;
        ctx.lineWidth = Math.max(2, s * 0.006);
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(hx, hy);
        ctx.lineTo(hx - (x1 - x0) * 0.25, hy - (y1 - y0) * 0.25);
        ctx.stroke();
      }
    }

    // ---- skipping stones ----
    if (S.skips && S.skips.length) {
      const NS = S.skipN ?? 7;
      const pts: [number, number, number][] = Array.from({length: NS}, (_, i) => {
        const u = i / (NS - 1);
        return [w * (L.tall ? 0.15 + u * 0.75 : 0.5 + u * 0.44), wl + (h - wl) * (0.62 - Math.pow(u, 0.8) * 0.58), 1 - u * 0.7];
      });
      S.skips.forEach((st, i) => {
        const age = t - st;
        if (age < 0 || i >= pts.length) return;
        const [x, y, sc] = pts[i];
        for (let k = 0; k < 3; k++) {
          const p = Math.min(1, (age - k * 0.25) / 2.2);
          if (p <= 0) continue;
          ctx.strokeStyle = css(pal.mist, 0.75 * (1 - p));
          ctx.lineWidth = Math.max(1, (w / 600) * sc);
          ctx.beginPath();
          ctx.ellipse(x, y, s * 0.13 * p * sc + 2, s * 0.022 * p * sc + 1, 0, 0, Math.PI * 2);
          ctx.stroke();
        }
        // the splash
        if (age < 0.35) {
          ctx.fillStyle = css(pal.mist, 0.8 * (1 - age / 0.35));
          for (let k = 0; k < 7; k++) {
            const a = -Math.PI * (0.1 + (k / 6) * 0.8);
            ctx.fillRect(x + Math.cos(a) * s * 0.04 * sc * (age / 0.35), y + Math.sin(a) * s * 0.03 * sc * (age / 0.35), 2, 2);
          }
        }
      });
      // the stone in flight to the next touch
      const n = S.skips.length;
      const last = S.skips[n - 1];
      const flight = Math.min(1, (t - last) / 0.4);
      if (S.skipDone == null && n < pts.length && flight < 1) {
        const [x0, y0] = pts[n - 1], [x1, y1] = pts[n];
        const x = x0 + (x1 - x0) * flight, y = y0 + (y1 - y0) * flight - Math.sin(flight * Math.PI) * s * 0.06 * pts[n - 1][2];
        ctx.fillStyle = css(pal.near);
        ctx.beginPath();
        ctx.ellipse(x, y, s * 0.012 * pts[n][2] + 1, s * 0.006 * pts[n][2] + 1, 0, 0, Math.PI * 2);
        ctx.fill();
      }
      if (S.skipDone != null) {
        // it reaches the far shore: a ring of light runs back along every touch
        const p = (t - S.skipDone) / 1.6;
        if (p > 0 && p < 1)
          pts.forEach(([x, y, sc], i) => {
            const q = Math.min(1, Math.max(0, p * 1.4 - (pts.length - 1 - i) * 0.08));
            ctx.strokeStyle = css(pal.sun, 0.8 * Math.sin(q * Math.PI));
            ctx.lineWidth = Math.max(1.5, (w / 500) * sc);
            ctx.beginPath();
            ctx.ellipse(x, y, s * 0.08 * sc, s * 0.014 * sc, 0, 0, Math.PI * 2);
            ctx.stroke();
          });
      }
    }

    // ---- a flash of light ----
    if (S.flash != null) {
      const p = (t - S.flash) / 1.2;
      if (p >= 0 && p < 1) {
        ctx.fillStyle = css(pal.sun, 0.55 * (1 - p) * (1 - p));
        ctx.fillRect(0, 0, w, h);
      }
    }

    // ---- birds bursting up ----
    if (S.burst != null) {
      const age = t - S.burst;
      if (age >= 0 && age < 3.5) {
        let ox = w * 0.5, oy = h * 0.5;
        if (S.burstAt === 'tree') {
          ox = L.treeX;
          oy = L.ledgeTop - L.treeH * S.tree * 0.85;
        } else if (S.burstAt === 'summit') {
          const route = routeOf(w, h, L, pathLayout(L, w, h));
          [ox, oy] = route[route.length - 1];
        } else if (S.burstAt === 'sun') {
          ox = L.tall ? w * 0.5 : w * 0.7;
          oy = L.tall ? h * 0.7 : h * 0.45;
        }
        ctx.strokeStyle = css(pal.near, 0.85 * Math.min(1, (3.5 - age) / 0.8));
        ctx.lineCap = 'round';
        for (let i = 0; i < 14; i++) {
          const a = -Math.PI * (0.1 + rnd(i) * 0.8);
          const sp = s * (0.18 + rnd(i + 4) * 0.25);
          const x = ox + Math.cos(a) * sp * age + Math.sin(age * 2 + i) * s * 0.01;
          const y = oy + Math.sin(a) * sp * age * 0.8;
          const sz = s * (0.012 + rnd(i + 8) * 0.01) * (1 + age * 0.3);
          const flap = Math.sin(age * 14 + i * 2) * 0.6;
          ctx.lineWidth = Math.max(1, s * 0.004);
          ctx.beginPath();
          ctx.moveTo(x - sz, y - sz * (0.3 + flap * 0.5));
          ctx.quadraticCurveTo(x - sz * 0.4, y - sz * 0.1, x, y);
          ctx.quadraticCurveTo(x + sz * 0.4, y - sz * 0.1, x + sz, y - sz * (0.3 + flap * 0.5));
          ctx.stroke();
        }
      }
    }

    // ---- paper lanterns rising over the water ----
    if (S.lanterns && S.lanterns.length) {
      S.lanterns.forEach((rt, i) => {
        const age = t - rt;
        if (age < 0) return;
        const x0 = w * (L.tall ? 0.3 + (i % 5) * 0.11 : 0.56 + (i % 5) * 0.08);
        const y0 = wl + (h - wl) * 0.2;
        const rise = Math.min(1, age / 9);
        const x = x0 + Math.sin(age * 0.6 + i) * s * 0.03 + rise * s * 0.05 * (i % 2 ? 1 : -1);
        const y = y0 - (y0 - h * (L.tall ? 0.45 : 0.04)) * (1 - Math.pow(1 - rise, 1.6)) * (0.8 + rnd(i) * 0.25);
        const sz = s * 0.035 * (1 - rise * 0.55);
        const fl = 0.85 + 0.15 * Math.sin(t * 9 + i * 3);
        const g = ctx.createRadialGradient(x, y, 0, x, y, sz * 3);
        g.addColorStop(0, `rgba(255,200,160,${(0.45 * fl).toFixed(3)})`);
        g.addColorStop(1, 'rgba(255,200,160,0)');
        ctx.fillStyle = g;
        ctx.fillRect(x - sz * 3, y - sz * 3, sz * 6, sz * 6);
        ctx.fillStyle = `rgba(255,236,214,${(0.95 * fl).toFixed(3)})`;
        ctx.beginPath();
        ctx.moveTo(x - sz * 0.42, y - sz * 0.55);
        ctx.lineTo(x + sz * 0.42, y - sz * 0.55);
        ctx.lineTo(x + sz * 0.34, y + sz * 0.55);
        ctx.lineTo(x - sz * 0.34, y + sz * 0.55);
        ctx.closePath();
        ctx.fill();
        ctx.fillStyle = '#E85D4E';
        ctx.fillRect(x - sz * 0.12, y + sz * 0.3, sz * 0.24, sz * 0.18);
        // its reflection on the water while it is still low
        if (y > wl - (h - wl)) {
          ctx.fillStyle = `rgba(255,220,190,${(0.25 * (1 - rise)).toFixed(3)})`;
          ctx.fillRect(x - sz * 0.3, wl + (wl - y) * -0.2 + (h - wl) * 0.3, sz * 0.6, sz * 1.2);
        }
      });
    }

    // ---- rain: fine slanted strokes, a darker sky band ----
    if (S.rain) {
      const g = ctx.createLinearGradient(0, 0, 0, h * 0.6);
      g.addColorStop(0, css(pal.mid2, 0.25 * S.rain));
      g.addColorStop(1, css(pal.mid2, 0));
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, w, h * 0.6);
      ctx.strokeStyle = css(theme === 'light' ? pal.mid2 : pal.mist, 0.45);
      ctx.lineWidth = Math.max(1, s * 0.0025);
      ctx.lineCap = 'round';
      ctx.beginPath();
      const n = Math.round(160 * S.rain);
      for (let i = 0; i < n; i++) {
        const sp = 0.9 + rnd(i) * 0.5;
        const y = ((rnd(i + 1) + t * sp) % 1) * h * 1.1 - h * 0.05;
        const x = ((rnd(i + 2) + t * sp * 0.12) % 1) * w * 1.1 - w * 0.05;
        const len = s * (0.03 + rnd(i + 3) * 0.03);
        ctx.moveTo(x, y);
        ctx.lineTo(x - len * 0.25, y + len);
      }
      ctx.stroke();
    }

    // ---- snow ----
    if (S.snow) {
      ctx.fillStyle = theme === 'light' ? css(mixc(pal.mid2, pal.mist, 0.35), 0.85) : css([230, 230, 232], 0.9);
      const n = Math.round(140 * S.snow);
      for (let i = 0; i < n; i++) {
        const sp = 0.04 + rnd(i) * 0.06;
        const y = ((rnd(i + 1) + t * sp) % 1) * h;
        const x = ((rnd(i + 2) * w + Math.sin(t * 0.8 + i) * s * 0.02) % w + w) % w;
        const r = Math.max(1, s * (0.002 + rnd(i + 3) * 0.004));
        ctx.globalAlpha = 0.5 + rnd(i + 4) * 0.5;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      // a dusting settling on the ground
      const g = ctx.createLinearGradient(0, h * 0.82, 0, h);
      g.addColorStop(0, css(pal.mist, 0));
      g.addColorStop(1, css(pal.mist, 0.35 * S.snow));
      ctx.fillStyle = g;
      ctx.fillRect(0, h * 0.82, w, h * 0.18);
    }
  }
}
