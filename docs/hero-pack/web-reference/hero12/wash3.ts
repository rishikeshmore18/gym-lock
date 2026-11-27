/**
 * Ridge, one more layer of life: the small things each day's world needs, drawn over the painted scene
 * every frame. Snow and ice for a frozen streak, fireflies in the pines, a drip that keeps time on the
 * lake, the tide creeping up to a stick, footprints, a beacon on the summit, paper lanterns, a
 * constellation lighting star by star, a shooting star, skipping stones, birds bursting from a crown,
 * and a flash of sunlight.
 */
import {Layout, Pal, Pt, RGB, Theme, css, layoutFor, mixc, palette} from '../hero10/wash';
import {Cone, Gully, Painter2, Scene2, pathLayout, routeOf, vcClamp, vcCl, vcConeOf, vcGPt, vcGulliesOf, vcLerp, vcRimAt, vcRnd, vcSurf, vcVn, vcConePath, vcRib, vcBrush} from '../hero10/wash2';

export type Scene3 = Scene2 & {
  snow?: number;
  frozen?: boolean;
  fireflies?: number;
  drip?: boolean;
  tide?: number;
  steps?: number;
  beacon?: number; // the summit volcano: 0 dormant, rising to 1 fully erupting (no `eruptAt`)
  rumble?: number; // 0..1 how far the climb has got: the dormant volcano warms with it
  tapAt?: number | null; // time of the newest climb tap: a small rumble and a puff
  eruptAt?: number | null; // time of the burst: flash, shake, flung rock, an ash column, then the long eruption
  still?: boolean; // Reduce Motion: no fountain, no flung rock, a static plume, a gentle glow
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

    // ---- the summit volcano: a wisp and a faint glow, rumbling on the climb, erupting when lit ----
    if (S.kind === 'path') volcano(ctx, w, h, L, pal, S, t);

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

// ---------- the summit volcano, every frame ----------
// The cone itself is painted once into the path world's base layer (wash2.ts `vcPaintCone`). Everything that
// moves is here: the glow in the throat, the smoke, the lava following the painted gullies (clipped to the cone),
// flung rock landing on the slopes, the ash column of the burst. Colours: greys and coral with its hot tints.
const VC_CORAL: RGB = [232, 93, 78];
const VC_ORANGE: RGB = [255, 150, 95];
const VC_HOT: RGB = [255, 214, 170];
const vcA = (c: RGB, a: number) => css(c, Math.round(Math.max(0, Math.min(1, a)) * 1000) / 1000);

/** one soft puff of smoke, lit coral from below while it is young */
const vcPuff = (ctx: CanvasRenderingContext2D, x: number, y: number, r: number, seed: number, t: number, al: number, lit: number, tone: number) => {
  if (al < 0.008) return;
  const c = Math.round(48 + 112 * tone);
  for (let k = 0; k < 2; k++) {
    const ox = (vcVn(seed + k * 3.1 + t * 0.1) - 0.5) * r * 0.9, oy = (vcVn(seed + k * 5.3 + 9 + t * 0.1) - 0.5) * r * 0.7, rr = r * (0.6 + 0.4 * vcRnd(seed + k));
    const g = ctx.createRadialGradient(x + ox, y + oy, 0, x + ox, y + oy, rr);
    g.addColorStop(0, css([c, c - 2, c + 4], Math.min(1, al * 0.62)));
    g.addColorStop(0.5, css([c + 8, c + 6, c + 12], Math.min(1, al * 0.32)));
    g.addColorStop(1, css([c + 14, c + 12, c + 18], 0));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x + ox, y + oy, rr, 0, Math.PI * 2);
    ctx.fill();
  }
  if (lit > 0.02) {
    const g = ctx.createRadialGradient(x, y + r * 0.45, 0, x, y + r * 0.45, r * 0.9);
    g.addColorStop(0, vcA(VC_ORANGE, 0.55 * lit * Math.min(1, al * 1.4)));
    g.addColorStop(0.5, vcA(VC_CORAL, 0.26 * lit * Math.min(1, al * 1.4)));
    g.addColorStop(1, vcA(VC_CORAL, 0));
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y + r * 0.45, r * 0.9, 0, Math.PI * 2);
    ctx.fill();
  }
};

/** clips to the sky above the broken rim, so smoke comes out of the notch instead of lying on the cone */
const vcClipAboveRim = (ctx: CanvasRenderingContext2D, C: Cone, w: number) => {
  const n = C.rim.length;
  ctx.beginPath();
  ctx.moveTo(-10, -10);
  ctx.lineTo(w + 10, -10);
  ctx.lineTo(w + 10, C.rim[n - 1][1] + 2 * C.sc);
  for (let i = n - 1; i >= 0; i--) ctx.lineTo(C.rim[i][0], C.rim[i][1] + 1.5 * C.sc);
  ctx.lineTo(-10, C.rim[0][1] + 2 * C.sc);
  ctx.closePath();
  ctx.clip();
};

/** the smoke plume: dense near the vent, fading as it rises and drifts right, coral underlight on the lower third */
const vcPlume = (ctx: CanvasRenderingContext2D, C: Cone, t: number, pw: number, front: number, hmax: number, lean: number, capY: number, rs: number, rate: number, n: number) => {
  const sc = C.sc;
  const rTop = sc * rs * (8 + 36 * pw) * 1.3;
  const Hm = Math.min(hmax, C.vy - capY - rTop * 0.9);
  const live: number[][] = [];
  for (let i = 0; i < n; i++) {
    const ph = (t * rate + i / n) % 1;
    if (ph <= front) live.push([i, ph]);
  }
  live.sort((a, b) => b[1] - a[1]);
  for (const [fi, ph] of live) {
    const i = fi;
    const vis = vcCl((front - ph) / 0.12);
    const e = 1 - Math.pow(1 - ph, 1.8);
    const r = sc * rs * (8 + 36 * Math.pow(ph, 0.62) * pw) * (0.72 + 0.55 * vcRnd(i * 3.7 + 1));
    const xx = C.vx + lean * Math.pow(ph, 1.5) + (vcRnd(i * 5.1 + 2) - 0.5) * r * (0.9 + 1.0 * ph) + Math.sin(ph * 5 + i * 1.7) * r * 0.1;
    const yy = Math.max(C.vy - Hm * e + (vcRnd(i * 2.3 + 4) - 0.5) * r * 0.5, capY + r * 0.8);
    const al = pw * vis * Math.min(1, ph / 0.05) * (1 - vcCl((ph - 0.6) / 0.4)) * (1 - 0.5 * ph) * 1.7;
    vcPuff(ctx, xx, yy, r, i * 7.7, t, al, vcCl(1 - ph * 3), ph);
  }
};

/** the burst's ash column: dark, lit coral from below, a few seconds */
const vcColumn = (ctx: CanvasRenderingContext2D, C: Cone, t: number, burst: number, hmax: number, lean: number, capY: number, rs: number) => {
  if (burst < 0 || burst > 4) return;
  const sc = C.sc;
  const rTop = sc * rs * 44;
  const Hc = Math.min(hmax, C.vy - capY - rTop * 0.9);
  for (let i = 11; i >= 0; i--) {
    const u = vcCl((burst - 0.05 * i) / 1.5);
    if (u <= 0) continue;
    const e = 1 - Math.pow(1 - u, 2.2);
    const r = sc * rs * (9 + 30 * u);
    const xx = C.vx + (vcRnd(i + 5) - 0.5) * r * 0.5 + lean * 0.4 * u * u;
    const yy = Math.max(C.vy - Hc * e * (0.6 + 0.4 * vcRnd(i)), capY + r * 0.85);
    vcPuff(ctx, xx, yy, r, i * 3.3 + 200, t, 1.3 * (1 - vcCl((burst - 1.0) / 2.8)), vcCl(1.1 - u * 1.6), 0.1 * u);
  }
};

/** the dormant smoke: a thin wisp that sways */
const vcWisp = (ctx: CanvasRenderingContext2D, C: Cone, t: number, a: number) => {
  const sc = C.sc;
  const P: Pt[] = [], Q: Pt[] = [];
  for (let i = 0; i < 9; i++) {
    P.push([C.vx + i * 2.6 * sc + Math.sin(t * 1.4 + i * 0.7) * 2.4 * sc * (i / 4), C.vy - 4 * sc - i * 9 * sc]);
    Q.push([C.vx + i * 2.6 * sc + Math.sin(t * 1.4 + i * 0.7) * 2.4 * sc * (i / 4) + Math.sin(t * 1.1 + i) * 1.2 * sc, C.vy - 4 * sc - i * 9 * sc]);
  }
  vcBrush(ctx, P, 4.5 * sc, 1.2 * sc, `rgba(80,78,84,${(0.16 * a).toFixed(3)})`, 5, 0.3);
  vcBrush(ctx, Q, 2.4 * sc, 0.6 * sc, `rgba(60,58,64,${(0.2 * a).toFixed(3)})`, 9, 0.3);
};

/** the glow in the throat; `flare` is the burst's flash */
const vcVent = (ctx: CanvasRenderingContext2D, C: Cone, t: number, gl: number, flare: number, still: boolean) => {
  const sc = C.sc;
  const pul = still ? 0.92 + 0.08 * Math.sin(t * 1.6) : 0.9 + 0.1 * Math.sin(t * 2.3) + 0.05 * Math.sin(t * 7.1);
  const R = sc * (11 + 24 * gl + 70 * flare);
  const g = ctx.createRadialGradient(C.vx, C.vy - sc, 0, C.vx, C.vy - sc, R);
  g.addColorStop(0, vcA(VC_HOT, 0.85 * gl));
  g.addColorStop(0.3, vcA(VC_ORANGE, 0.55 * gl * pul));
  g.addColorStop(0.7, vcA(VC_CORAL, 0.2 * gl * pul));
  g.addColorStop(1, vcA(VC_CORAL, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(C.vx, C.vy - sc, R, 0, Math.PI * 2);
  ctx.fill();
};

/** a wide coral halo around the summit */
const vcHalo = (ctx: CanvasRenderingContext2D, C: Cone, gl: number, flare: number) => {
  const sc = C.sc;
  const R = sc * (75 + 60 * flare);
  const g = ctx.createRadialGradient(C.vx, C.vy - 8 * sc, 0, C.vx, C.vy - 8 * sc, R);
  g.addColorStop(0, vcA(VC_CORAL, 0.2 * gl + 0.25 * flare));
  g.addColorStop(1, vcA(VC_CORAL, 0));
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(C.vx, C.vy - 8 * sc, R, 0, Math.PI * 2);
  ctx.fill();
};

/** the lava: rim overflow, then the main flows growing down the gullies and flowing, clipped inside the cone */
const vcLava = (ctx: CanvasRenderingContext2D, C: Cone, G: Gully[], t: number, flow: number, pw: number, still: boolean) => {
  const sc = C.sc, vD = 16 * sc;
  ctx.save();
  vcConePath(ctx, C, 60);
  ctx.clip();
  if (flow > 0.01) {
    const P: Pt[] = [], Wd: number[] = [];
    for (let f = -0.34; f <= 0.301; f += 0.05) {
      const r = vcRimAt(C, f);
      P.push([r[0], r[1] + 2.5 * sc]);
      Wd.push((6 + 4 * vcVn(f * 9 + 4)) * sc * pw);
    }
    const k = Math.min(1, flow * 3);
    vcRib(ctx, P, Wd.map((q) => q * 3));
    ctx.fillStyle = vcA(VC_CORAL, 0.16 * pw * k);
    ctx.fill();
    vcRib(ctx, P, Wd);
    ctx.fillStyle = vcA(VC_ORANGE, 0.95 * k);
    ctx.fill();
    vcRib(ctx, P, Wd.map((q) => q * 0.45));
    ctx.fillStyle = vcA(VC_HOT, 0.95 * k);
    ctx.fill();
  }
  for (let gi = 0; gi < G.length; gi++) {
    const g = G[gi];
    if (!g.lava) continue;
    const p = vcCl((flow - g.delay) / (1 - g.delay));
    if (p <= 0.01) continue;
    const e = 1 - Math.pow(1 - p, 2.2);
    const d0 = g.par >= 0 ? g.dStart - 4 * sc : vD - 2 * sc;
    const dEnd = d0 + (g.dEnd - d0) * e;
    if (dEnd - d0 < 4 * sc) continue;
    const n = Math.max(3, Math.ceil((dEnd - d0) / (5 * sc)));
    const P: Pt[] = [], Wd: number[] = [];
    for (let i = 0; i <= n; i++) {
      const d = d0 + ((dEnd - d0) * i) / n;
      const u = (d - d0) / (g.dEnd - d0);
      P.push(vcGPt(C, G, g, d));
      let wd = g.wid * 9.2 * pw * sc * (1 - 0.92 * Math.pow(vcCl(u), 0.8)) + 0.5 * sc;
      wd *= 0.6 + 0.8 * vcVn(g.seed * 3 + d / (15 * sc));
      if (u > 0.45) wd *= vcClamp((vcVn(g.seed * 7 + d / (9 * sc)) - (u - 0.45) * 1.3) * 5 + 0.12, 0.08, 1);
      if (i > n - 3) wd *= i === n ? 0.4 : 0.7;
      Wd.push(wd);
    }
    const a = P[0], b = P[n];
    vcRib(ctx, P, Wd.map((q) => q * 3.4));
    ctx.fillStyle = vcA(VC_CORAL, 0.12 * pw);
    ctx.fill();
    vcRib(ctx, P, Wd.map((q) => q * 1.8 + 1.2 * sc));
    ctx.fillStyle = 'rgba(24,24,28,0.34)';
    ctx.fill();
    const gr = ctx.createLinearGradient(a[0], a[1], b[0], b[1] + 0.01);
    gr.addColorStop(0, vcA(VC_ORANGE, 0.98));
    gr.addColorStop(0.4, vcA(mixc(VC_ORANGE, VC_CORAL, 0.7), 0.96));
    gr.addColorStop(0.8, vcA(VC_CORAL, 0.92));
    gr.addColorStop(1, vcA(e < 0.98 ? mixc(VC_CORAL, VC_ORANGE, 0.7) : mixc(VC_CORAL, [44, 38, 42], 0.4), 0.9));
    vcRib(ctx, P, Wd);
    ctx.fillStyle = gr;
    ctx.fill();
    const gc = ctx.createLinearGradient(a[0], a[1], b[0], b[1] + 0.01);
    gc.addColorStop(0, vcA(VC_HOT, 0.95));
    gc.addColorStop(0.7, vcA(VC_HOT, 0));
    vcRib(ctx, P, Wd.map((q) => q * 0.4));
    ctx.fillStyle = gc;
    ctx.fill();
    // bright clots sliding down the run (still under Reduce Motion)
    for (let j = 0; j < 3; j++) {
      const u = (still ? 0.2 + j * 0.3 : t * (0.1 + 0.04 * vcRnd(g.seed + j)) + j / 3 + vcRnd(g.seed * 2 + j)) % 1;
      const fi = u * n, i0 = Math.min(n - 1, Math.floor(fi)), f = fi - i0;
      const x0 = vcLerp(P[i0][0], P[i0 + 1][0], f), y0 = vcLerp(P[i0][1], P[i0 + 1][1], f), wc = vcLerp(Wd[i0], Wd[i0 + 1], f);
      const ang = Math.atan2(P[i0 + 1][1] - P[i0][1], P[i0 + 1][0] - P[i0][0]);
      ctx.save();
      ctx.translate(x0, y0);
      ctx.rotate(ang);
      ctx.fillStyle = vcA(VC_ORANGE, 0.35 * pw * (1 - u * 0.5));
      ctx.beginPath();
      ctx.ellipse(0, 0, wc * 1.9, wc * 0.9, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = vcA(VC_HOT, 0.95 * (1 - u * 0.55));
      ctx.beginPath();
      ctx.ellipse(wc * 0.2, 0, wc * 1.1, wc * 0.5, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    if (e < 0.97) {
      ctx.fillStyle = vcA(VC_HOT, 0.9);
      ctx.beginPath();
      ctx.ellipse(b[0], b[1], Wd[n - 1] * 0.9 + 0.6, Wd[n - 1] * 0.9 + 0.6, 0, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  ctx.restore();
};

/** molten flecks: short brush flicks on ballistic arcs that land on the cone. `once` is the burst (age `burst`). */
const vcFountain = (ctx: CanvasRenderingContext2D, C: Cone, t: number, n: number, seed: number, vmax: number, once: boolean, burst: number) => {
  const sc = C.sc, G = 260 * sc;
  ctx.lineCap = 'round';
  for (let i = 0; i < n; i++) {
    const r1 = vcRnd(seed + i), r2 = vcRnd(seed + i + 500), r3 = vcRnd(seed + i + 900);
    let tau = 0;
    if (once) {
      tau = burst - r3 * 0.38;
      if (tau < 0) continue;
    } else {
      const Lf = 1.1 + 0.6 * r1;
      tau = (((t / Lf + r2) % 1) * Lf);
    }
    const ang = -Math.PI / 2 + (r2 - 0.5) * (once ? 1.0 : 0.8), v = vmax * sc * (0.3 + 0.7 * r3 * r3);
    const vx = Math.cos(ang) * v, vy = Math.sin(ang) * v + G * tau;
    const px = C.vx + (r1 - 0.5) * sc * 10 + Math.cos(ang) * v * tau + 6 * sc * tau, py = C.vy - 2 * sc + Math.sin(ang) * v * tau + 0.5 * G * tau * tau;
    const sf = vcSurf(C, px);
    if (py > C.vy + 4 * sc && (py >= sf - 0.5 || (sf > 1e8 && py > C.vy + 60 * sc))) continue;
    const near = sf < 1e8 ? vcCl((sf - py) / (8 * sc)) : 1;
    const age = vcCl(tau / (once ? 2.2 : 1.5));
    const sp = Math.hypot(vx, vy) || 1, L2 = Math.max(2.6 * sc, Math.min(14 * sc, sp * 0.034));
    ctx.strokeStyle = vcA(mixc(VC_HOT, VC_CORAL, vcCl(age * 1.5)), 0.95 * (1 - age * 0.45) * near);
    ctx.lineWidth = Math.max(1, sc * (2.1 - age * 0.9) * (once ? 1.25 : 1));
    ctx.beginPath();
    ctx.moveTo(px, py);
    ctx.lineTo(px - (vx / sp) * L2, py - (vy / sp) * L2);
    ctx.stroke();
  }
};

/** coral spatter flung from the throat at the burst, fading over about two seconds */
const vcSpatter = (ctx: CanvasRenderingContext2D, C: Cone, burst: number) => {
  if (burst < 0) return;
  const sc = C.sc;
  const sp = vcCl(burst / 0.3), fade = 1 - vcCl((burst - 0.7) / 1.3);
  if (fade <= 0) return;
  for (let i = 0; i < 18; i++) {
    const an = -Math.PI * (0.1 + 0.8 * vcRnd(i + 300)), len = sc * (40 + 78 * vcRnd(i + 301)) * sp;
    const p0: Pt = [C.vx + Math.cos(an) * sc * 8, C.vy - sc * 2 + Math.sin(an) * sc * 5];
    const p1: Pt = [C.vx + Math.cos(an) * len, C.vy + Math.sin(an) * len * 0.9];
    const mid: Pt = [(p0[0] + p1[0]) / 2 + (vcRnd(i + 302) - 0.5) * sc * 14, (p0[1] + p1[1]) / 2];
    vcBrush(ctx, [p0, mid, p1], sc * 4, sc * 0.4, vcA(i % 4 === 0 ? VC_ORANGE : VC_CORAL, 0.6 * fade), i * 13, 0.6);
    ctx.fillStyle = vcA(VC_CORAL, 0.7 * fade);
    ctx.beginPath();
    ctx.arc(p1[0], p1[1], Math.max(1, sc * 1.8), 0, Math.PI * 2);
    ctx.fill();
  }
};

/** embers rising and drifting right */
const vcEmbers = (ctx: CanvasRenderingContext2D, C: Cone, t: number, n: number, drift: number, rise: number) => {
  const sc = C.sc;
  for (let i = 0; i < n; i++) {
    const ph = (t * (0.2 + vcRnd(i) * 0.2) + vcRnd(i + 4)) % 1;
    const ex = C.vx + (vcRnd(i + 9) - 0.5) * sc * 30 + Math.sin(ph * 6 + i) * sc * 8 * (1 + ph) + ph * drift * sc, ey = C.vy - sc * 8 - ph * rise * sc;
    ctx.fillStyle = vcA(i % 3 === 0 ? VC_HOT : VC_ORANGE, 0.9 * (1 - ph));
    const q = Math.max(1, sc * 1.8);
    ctx.fillRect(ex, ey, q, q);
  }
};

/** the small puffs thrown up by a climb tap */
const vcTapPuffs = (ctx: CanvasRenderingContext2D, C: Cone, t: number, tapAt: number) => {
  const d = t - tapAt;
  if (d < 0 || d > 1.5) return;
  const sc = C.sc, u = d / 1.5;
  for (let i = 0; i < 3; i++) {
    const r = sc * (8 + u * 14);
    vcPuff(ctx, C.vx + u * 16 * sc + (i - 1) * 5 * sc, C.vy - 8 * sc - u * 52 * sc - i * 5 * sc, r, i * 5 + 600, t, 0.9 * (1 - u) * (1 - u * 0.3), 0, 0);
  }
};

/**
 * The volcano for this frame. `S.beacon` (0..1) lights it with no burst (the card, the lit screens);
 * `S.eruptAt` is the story's burst (the last climb tap); before it `S.rumble` and `S.tapAt` warm it tap by tap.
 * The card is the same volcano smaller and calmer: two flows, a lighter fountain, a low plume.
 */
export const volcano = (ctx: CanvasRenderingContext2D, w: number, h: number, L: Layout, pal: Pal, S: Scene3, t: number) => {
  const C = vcConeOf(w, h, L);
  const G = vcGulliesOf(C, L.tall);
  const sc = C.sc;
  const still = S.still ?? false;
  const tall = L.tall;
  const tt = still ? 6 : t;
  const b = S.beacon ?? 0;
  const burstOn = S.eruptAt != null && t >= S.eruptAt;
  const a = burstOn ? t - (S.eruptAt ?? 0) : -1;
  const lv = vcCl((b - 0.1) / 0.4);
  const erupting = burstOn || lv > 0.02;
  let glow = 0.12 + 0.6 * Math.min(b, 0.2);
  let flow = 0, fountain = 0, embers = 0, flare = 0, front = 1, burst = -1;
  if (burstOn) {
    flow = vcCl(a / 2.4);
    glow = vcCl(0.5 + a / 0.8);
    fountain = vcCl((a - 0.8) / 1.2);
    embers = Math.round(26 * vcCl(a / 1.2));
    flare = Math.exp(-a / 0.45);
    front = vcCl(a / 2.2);
    burst = a;
  } else if (lv > 0.02) {
    flow = lv;
    glow = 0.2 + 0.8 * lv;
    fountain = vcCl((lv - 0.35) / 0.65);
    embers = Math.round(26 * lv);
    front = lv;
  } else {
    glow = 0.16 + 0.52 * (S.rumble ?? 0) + 0.4 * Math.min(b, 0.1);
    if (S.tapAt != null && t - S.tapAt >= 0 && t - S.tapAt < 0.5) glow += 0.25 * (1 - (t - S.tapAt) / 0.5);
  }
  if (still) {
    // Reduce Motion: the lava stands, the glow breathes, nothing flies or drifts
    if (erupting) {
      flow = 1;
      glow = Math.max(glow, 0.9);
    }
    fountain = 0;
    embers = 0;
    flare = 0;
    burst = -1;
    front = 1;
  }
  const pw = tall ? 1 : 0.78;
  const rs = tall ? 1 : 0.6;
  const hmax = (tall ? 400 : 200) * sc;
  const lean = (tall ? 150 : 100) * sc;
  const capY = Math.max(0, C.vy - 215 * sc);

  vcHalo(ctx, C, glow, flare);
  ctx.save();
  vcClipAboveRim(ctx, C, w);
  if (erupting) {
    vcPlume(ctx, C, tt, pw, front, hmax, lean, capY, rs, 0.09, 40);
    if (burst >= 0) vcColumn(ctx, C, t, burst, hmax, lean, capY, rs);
  } else vcWisp(ctx, C, tt, 0.5 + glow);
  ctx.restore();
  if (flow > 0.01) vcLava(ctx, C, G, tt, flow, pw, still);
  vcVent(ctx, C, t, glow, flare, still);
  if (fountain > 0.02) vcFountain(ctx, C, t, Math.round((tall ? 44 : 26) * fountain), 1, tall ? 170 : 150, false, 0);
  if (burst >= 0 && burst < 2.7) {
    vcFountain(ctx, C, t, tall ? 160 : 90, 3000, tall ? 270 : 220, true, burst);
    vcSpatter(ctx, C, burst);
  }
  if (embers > 0) vcEmbers(ctx, C, t, tall ? embers : Math.round(embers * 0.35), 60, tall ? 180 : 70);
  if (!erupting && !still && S.tapAt != null) vcTapPuffs(ctx, C, t, S.tapAt);
};
