/**
 * Glyph builders. Each returns targets in grid cells for a field of `cols` × `rows`, centred on
 * (cx, cy) with a size unit `u` (cells), so the same glyph works on the card and full screen.
 */
import {FLAME_INNER, FLAME_OUTER} from '../hero2/strip';
import {Tgt, hash, raster} from './dots';

export type Frame = {cols: number; rows: number; cx: number; cy: number; u: number};
const K = (f: Frame, name: string) => `${name}:${f.cols}x${f.rows}:${f.cx}:${f.cy}:${f.u}`;
const pts = (a: {x: number; y: number}[], b: number, c = 0): Tgt[] => a.map((p) => ({x: p.x, y: p.y, b, c}));

// ---------- flame ----------
const flameRaster = (f: Frame, h: number, part: 'outer' | 'inner', dx = 0, dy = 0) =>
  raster(K(f, `flame${part}${h}:${dx}:${dy}`), f.cols, f.rows, (g) => {
    const s = h / 120;
    g.translate(f.cx + dx - 50 * s, f.cy + dy - 62 * s);
    g.scale(s, s);
    g.fill(new Path2D(part === 'outer' ? FLAME_OUTER : FLAME_INNER));
  });
/** flame: core in coral, tongue tips flicker sideways */
export const flame = (f: Frame, t: number, o: {h?: number; dim?: number; dx?: number; dy?: number; ignite?: number; drift?: number; seed?: number} = {}): Tgt[] => {
  const h = o.h ?? f.u * 2.2;
  const outer = flameRaster(f, h, 'outer', o.dx, o.dy), inner = flameRaster(f, h, 'inner', o.dx, o.dy);
  const inSet = new Set(inner.map((p) => `${p.x},${p.y}`));
  let top = Infinity, bot = -Infinity;
  for (const p of outer) {
    top = Math.min(top, p.y);
    bot = Math.max(bot, p.y);
  }
  const ig = o.ignite ?? 1;
  return outer.map((p, i) => {
    const up = (bot - p.y) / Math.max(1, bot - top); // 0 bottom … 1 tip
    const fl = Math.pow(up, 1.6) * (Math.sin(t * 7 + p.y * 0.9 + i * 0.03) * 0.5 + Math.sin(t * 11.3 + p.y * 1.7) * 0.3);
    const core = inSet.has(`${p.x},${p.y}`);
    let b = core ? 1 : 0.92 - up * 0.25 + Math.sin(t * 9 + i) * 0.06;
    if (o.dim != null && !core) b *= o.dim;
    const lit = up <= ig * 1.15 ? 1 : 0.12;
    let x = p.x + fl * 0.9, y = p.y - Math.max(0, fl) * 0.2;
    // smoke: the upper part peels away and drifts off
    if (o.drift && up > 0.55 && hash(i, 3) < o.drift) {
      const k = (t * 0.22 + hash(i, 4)) % 1;
      x += k * 11 + Math.sin(k * 6 + i) * 1.2;
      y -= k * 5;
      b *= 1 - k;
    }
    return {x, y, b: b * lit, c: core && lit === 1 ? 1 : 0};
  });
};

// ---------- lock ----------
export const lock = (f: Frame, t: number, parts: [number, number, number], open = 0): Tgt[] => {
  const u = f.u;
  const shackle = raster(K(f, 'shk'), f.cols, f.rows, (g) => {
    g.lineWidth = u * 0.34;
    g.beginPath();
    g.moveTo(f.cx - u * 0.68, f.cy - u * 0.05);
    g.lineTo(f.cx - u * 0.68, f.cy - u * 0.55);
    g.arc(f.cx, f.cy - u * 0.55, u * 0.68, Math.PI, 0);
    g.lineTo(f.cx + u * 0.68, f.cy - u * 0.05);
    g.stroke();
  });
  const body = raster(K(f, 'body'), f.cols, f.rows, (g) => {
    g.beginPath();
    g.roundRect(f.cx - u * 1.12, f.cy - u * 0.1, u * 2.24, u * 1.62, u * 0.26);
    g.fill();
    g.globalCompositeOperation = 'destination-out';
    g.beginPath();
    g.arc(f.cx, f.cy + u * 0.52, u * 0.26, 0, Math.PI * 2);
    g.rect(f.cx - u * 0.1, f.cy + u * 0.52, u * 0.2, u * 0.5);
    g.fill();
  });
  const key = raster(K(f, 'key'), f.cols, f.rows, (g) => {
    g.beginPath();
    g.arc(f.cx, f.cy + u * 0.52, u * 0.24, 0, Math.PI * 2);
    g.rect(f.cx - u * 0.08, f.cy + u * 0.52, u * 0.16, u * 0.46);
    g.fill();
  }, 0.3);
  const lift = open * u * 0.34;
  return [
    ...shackle.map((p) => {
      // open: the shackle rises and swings a little around its left leg
      const a = -open * 0.32;
      const px = f.cx - u * 0.68, py = f.cy;
      const x = px + (p.x - px) * Math.cos(a) - (p.y - py) * Math.sin(a);
      const y = py + (p.x - px) * Math.sin(a) + (p.y - py) * Math.cos(a) - lift;
      return {x, y, b: parts[1] ? 1 : 0.22};
    }),
    ...pts(body, parts[0] ? 1 : 0.22),
    ...key.map((p) => ({x: p.x, y: p.y, b: parts[2] ? 1 : 0.18, c: parts[2] ? 1 : 0})),
  ];
};

// ---------- moon and stars ----------
export const moon = (f: Frame, t: number): Tgt[] => {
  const u = f.u;
  const m = raster(K(f, 'moon'), f.cols, f.rows, (g) => {
    g.beginPath();
    g.arc(f.cx + u * 0.15, f.cy, u * 1.15, 0, Math.PI * 2);
    g.fill();
    g.globalCompositeOperation = 'destination-out';
    g.beginPath();
    g.arc(f.cx + u * 0.7, f.cy - u * 0.4, u * 1.0, 0, Math.PI * 2);
    g.fill();
  });
  const out: Tgt[] = m.map((p, i) => ({x: p.x, y: p.y + Math.sin(t * 0.8) * 0.15, b: 0.85 + 0.15 * Math.sin(t * 1.3 + i * 0.2)}));
  for (let i = 0; i < 14; i++) {
    const x = Math.floor(hash(i, 21) * f.cols) + 0.5, y = Math.floor(hash(i, 22) * f.rows * 0.9) + 0.5;
    if (Math.hypot(x - f.cx, y - f.cy) < u * 1.6) continue;
    const tw = 0.5 + 0.5 * Math.sin(t * (1.2 + hash(i, 23) * 2) + i * 2.1);
    out.push({x, y, b: 0.2 + 0.8 * Math.pow(tw, 3)});
  }
  return out;
};

// ---------- phone going dark: locked for sleep ----------
export const phoneLock = (f: Frame, t: number, lt: number): Tgt[] => {
  const u = f.u;
  const frame = raster(K(f, 'phone'), f.cols, f.rows, (g) => {
    g.lineWidth = u * 0.2;
    g.beginPath();
    g.roundRect(f.cx - u * 0.95, f.cy - u * 1.6, u * 1.9, u * 3.2, u * 0.35);
    g.stroke();
  });
  const screen = raster(K(f, 'phonescr'), f.cols, f.rows, (g) => {
    g.beginPath();
    g.roundRect(f.cx - u * 0.72, f.cy - u * 1.36, u * 1.44, u * 2.72, u * 0.2);
    g.fill();
  });
  const lk = lock({...f, u: u * 0.42, cy: f.cy + u * 0.05}, t, [1, 1, 0], 0).map((p) => ({...p, b: 1}));
  const lkSet = new Set(lk.map((p) => `${Math.floor(p.x)},${Math.floor(p.y)}`));
  const dark = Math.min(1, lt / 1.4);
  return [
    ...pts(frame, 1),
    ...screen.filter((p) => !lkSet.has(`${Math.floor(p.x)},${Math.floor(p.y)}`)).map((p, i) => ({x: p.x, y: p.y, b: 0.9 * (1 - dark) + 0.1 + 0.06 * Math.sin(t + i)})),
    ...lk.map((p) => ({...p, b: dark})),
  ];
};

// ---------- hourglass with real falling sand ----------
export const hourglass = (f: Frame, t: number, frac: number, state: {drained: number[]}): Tgt[] => {
  const u = f.u;
  const top = f.cy - u * 1.5, bot = f.cy + u * 1.5, w = u * 1.05;
  const outline = raster(K(f, 'hg'), f.cols, f.rows, (g) => {
    g.lineWidth = u * 0.16;
    g.beginPath();
    g.moveTo(f.cx - w - u * 0.25, top);
    g.lineTo(f.cx + w + u * 0.25, top);
    g.moveTo(f.cx - w - u * 0.25, bot);
    g.lineTo(f.cx + w + u * 0.25, bot);
    g.moveTo(f.cx - w, top);
    g.lineTo(f.cx - u * 0.12, f.cy);
    g.lineTo(f.cx - w, bot);
    g.moveTo(f.cx + w, top);
    g.lineTo(f.cx + u * 0.12, f.cy);
    g.lineTo(f.cx + w, bot);
    g.stroke();
  });
  const inside = (y0: number, y1: number, up: boolean) => {
    const out: {x: number; y: number}[] = [];
    for (let y = Math.ceil(y0) + 0.5; y < y1 - 0.4; y++) {
      const k = up ? (y - top) / (f.cy - top) : (bot - y) / (bot - f.cy);
      const half = (1 - k) * (w - u * 0.12) + u * 0.12 - 0.9;
      for (let x = Math.ceil(f.cx - half - 0.5) + 0.5; x <= f.cx + half; x++) out.push({x, y});
    }
    return out;
  };
  const tops = inside(top + 0.6, f.cy - 0.8, true).sort((a, b) => a.y - b.y || Math.abs(a.x - f.cx) - Math.abs(b.x - f.cx));
  const bots = inside(f.cy + 1.2, bot - 0.4, false).sort((a, b) => b.y - a.y || Math.abs(a.x - f.cx) - Math.abs(b.x - f.cx));
  const S = Math.min(tops.length, bots.length);
  const topSlots = tops.slice(tops.length - S);
  const drained = Math.floor(Math.min(1, Math.max(0, frac)) * S);
  const out: Tgt[] = pts(outline, 0.55);
  // bottom pile fills from the bottom; the top surface sinks from the top
  for (let i = 0; i < S; i++) {
    const gone = i < drained;
    if (gone && state.drained[i] == null) state.drained[i] = t;
    if (!gone) state.drained[i] = undefined as unknown as number;
    if (gone) {
      const since = t - state.drained[i];
      if (since < 0.35) out.push({x: f.cx, y: f.cy + since * 6, b: 1});
      else out.push({x: bots[i].x, y: bots[i].y, b: 1});
    } else out.push({x: topSlots[i].x, y: topSlots[i].y, b: 1});
  }
  // a thin stream through the neck, always running
  for (let k = 0; k < 4; k++) {
    const p = (t * 1.6 + k / 4) % 1;
    out.push({x: f.cx, y: f.cy - 0.3 + p * (u * 1.2), b: (1 - p) * 0.9});
  }
  return out;
};

// ---------- sunrise ----------
export const sunrise = (f: Frame, t: number, lt: number): Tgt[] => {
  const u = f.u;
  const hy = f.cy + u * 0.9;
  const rise = Math.min(1, lt / 1.6);
  const ease = 1 - Math.pow(1 - rise, 3);
  const cy = hy + u * 1.1 - ease * u * 1.1;
  const out: Tgt[] = [];
  for (let x = 0.5; x < f.cols; x++) out.push({x, y: Math.floor(hy) + 0.5, b: 0.55});
  const r = u * 0.95;
  for (let y = Math.floor(cy - r) + 0.5; y < hy; y++)
    for (let x = Math.floor(f.cx - r) + 0.5; x <= f.cx + r; x++) if (Math.hypot(x - f.cx, y - cy) <= r) out.push({x, y, b: 1});
  for (let k = 0; k < 9; k++) {
    const a = Math.PI + (k + 0.5) * (Math.PI / 9);
    const len = u * (0.5 + 0.35 * (0.5 + 0.5 * Math.sin(t * 2 + k * 1.3))) * ease;
    for (let s = 0; s < 4; s++) {
      const rr = r + u * 0.35 + (s / 3) * len;
      const y = cy + Math.sin(a) * rr;
      if (y > hy - 0.5) continue;
      out.push({x: f.cx + Math.cos(a) * rr, y, b: 1 - s * 0.2});
    }
  }
  return out;
};

// ---------- route to the gym ----------
export const route = (f: Frame, t: number, p: number): Tgt[] => {
  const u = f.u;
  const P = (s: number) => {
    const x0 = f.cx - u * 1.9, y0 = f.cy + u * 1.4, x1 = f.cx + u * 1.6, y1 = f.cy - u * 0.9;
    const x = x0 + (x1 - x0) * s, y = y0 + (y1 - y0) * s - Math.sin(s * Math.PI) * u * 0.9 + Math.sin(s * Math.PI * 3) * u * 0.25;
    return [x, y];
  };
  const out: Tgt[] = [];
  const N = 30;
  for (let k = 0; k <= N; k++) {
    const s = k / N;
    const [x, y] = P(s);
    out.push({x, y, b: s <= p ? 0.95 : 0.28});
  }
  // pin
  const [px, py] = P(1);
  const pin = raster(K(f, 'pin'), f.cols, f.rows, (g) => {
    g.beginPath();
    g.arc(px, py - u * 0.55, u * 0.42, Math.PI * 0.85, Math.PI * 0.15);
    g.lineTo(px, py);
    g.closePath();
    g.fill();
  });
  out.push(...pin.map((q) => ({x: q.x, y: q.y, b: 1, c: Math.hypot(q.x - px, q.y - (py - u * 0.55)) < u * 0.18 ? 1 : 0})));
  // you: a bright cluster that breathes along the line
  const [mx, my] = P(p);
  const br = 0.5 + 0.5 * Math.sin(t * 5);
  for (let k = 0; k < 6; k++) {
    const a = (k / 6) * Math.PI * 2 + t * 1.5;
    out.push({x: mx + Math.cos(a) * (0.9 + br * 0.5), y: my + Math.sin(a) * (0.9 + br * 0.5), b: 0.9});
  }
  out.push({x: mx, y: my, b: 1, c: 1});
  return out;
};

// ---------- the 20 minute ring ----------
export const ring20 = (f: Frame, t: number, secs: number): Tgt[] => {
  const u = f.u;
  const R = u * 1.55;
  const out: Tgt[] = [];
  const mins = secs / 60;
  for (let m = 0; m < 20; m++) {
    for (let k = 0; k < 3; k++) {
      const a = -Math.PI / 2 + ((m + 0.15 + k * 0.3) / 20) * Math.PI * 2;
      const done = m + 1 <= mins;
      const cur = m === Math.floor(mins) && mins < 20;
      const b = done ? 1 : cur ? 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(t * 6)) : 0.2;
      out.push({x: f.cx + Math.cos(a) * R, y: f.cy + Math.sin(a) * R, b, c: mins >= 20 ? 1 : 0});
    }
  }
  // the pulse: a heart-rate beat in the middle
  const beat = Math.pow(Math.max(0, Math.sin(t * Math.PI * 2 * 2.2)), 6);
  for (let k = 0; k < 12; k++) {
    const a = (k / 12) * Math.PI * 2;
    const r = u * (0.32 + beat * 0.22);
    out.push({x: f.cx + Math.cos(a) * r, y: f.cy + Math.sin(a) * r, b: 0.7 + beat * 0.3});
  }
  out.push({x: f.cx, y: f.cy, b: 1, c: 1});
  return out;
};

// ---------- recovery wave ----------
export const wave = (f: Frame, t: number): Tgt[] => {
  const out: Tgt[] = [];
  for (let k = 0; k < 3; k++)
    for (let x = 1.5; x < f.cols - 1; x += 1) {
      const y = f.cy - f.u * 0.8 + k * f.u * 0.8 + Math.sin(x * 0.32 + t * 0.9 + k * 0.9) * f.u * 0.32 * (1 - k * 0.2);
      out.push({x, y, b: 0.9 - k * 0.25});
    }
  return out;
};

// ---------- pause ----------
export const pause = (f: Frame, t: number): Tgt[] => {
  const u = f.u;
  const bars = raster(K(f, 'pause'), f.cols, f.rows, (g) => {
    g.beginPath();
    g.roundRect(f.cx - u * 0.6, f.cy - u * 0.85, u * 0.38, u * 1.7, u * 0.1);
    g.roundRect(f.cx + u * 0.22, f.cy - u * 0.85, u * 0.38, u * 1.7, u * 0.1);
    g.fill();
  });
  const ringP: Tgt[] = [];
  for (let k = 0; k < 44; k++) {
    const a = (k / 44) * Math.PI * 2;
    ringP.push({x: f.cx + Math.cos(a) * u * 1.55, y: f.cy + Math.sin(a) * u * 1.55, b: 0.25 + 0.2 * Math.sin(t * 0.8 - k * 0.3)});
  }
  return [...pts(bars, 0.9 + 0.1 * Math.sin(t)), ...ringP];
};

// ---------- the week, as seven empty bars; today's fills ----------
export const weekGrid = (f: Frame, t: number, lt: number, done: number, today: number): Tgt[] => {
  const out: Tgt[] = [];
  const sp = 5, hgt = 18;
  for (let d = 0; d < 7; d++)
    for (let r = 0; r < hgt; r++)
      for (let w = 0; w < 2; w++) {
        const x = Math.round(f.cx + (d - 3) * sp - 0.5) + w, y = Math.round(f.cy + hgt / 2 - r) - 0.5;
        let b = 0.26;
        if (d < done) {
          const fh = Math.min(1, Math.max(0, (lt - 0.2 - d * 0.16) / 0.45)) * hgt;
          b = r < fh ? 1 : 0.26;
          if (r < fh && r >= fh - 1 && fh >= hgt - 0.01) {
            out.push({x: Math.round(f.cx + (d - 3) * sp - 0.5) + w, y: Math.round(f.cy + hgt / 2 - r) - 0.5, b: 1, c: 1});
            continue;
          }
        }
        if (d === today) {
          const fill = Math.min(1, Math.max(0, (lt - 0.6) / 1.4)) * hgt * 0.35;
          b = r < fill ? 1 : 0.32 + 0.2 * Math.sin(t * 4 - r * 0.4);
        }
        out.push({x, y, b, c: d === today && r < Math.min(1, Math.max(0, (lt - 0.6) / 1.4)) * hgt * 0.35 && r >= Math.floor(Math.min(1, Math.max(0, (lt - 0.6) / 1.4)) * hgt * 0.35) - 1 ? 1 : 0});
      }
  return out;
};

// ---------- the days of this week as markers ----------
export const dayRow = (f: Frame, t: number, marks: ('done' | 'missed' | 'today' | 'future')[]): Tgt[] => {
  const out: Tgt[] = [];
  const sp = 5;
  marks.forEach((m, d) => {
    const x0 = Math.round(f.cx + (d - (marks.length - 1) / 2) * sp), y0 = Math.round(f.cy);
    for (let v = -1.5; v <= 1.5; v++)
      for (let w = -1.5; w <= 1.5; w++) {
        const edge = Math.abs(v) > 1 || Math.abs(w) > 1;
        const corner = Math.abs(v) > 1 && Math.abs(w) > 1;
        let b = 0;
        if (m === 'done') b = corner ? 0 : 1;
        else if (m === 'missed') b = edge && !corner ? 0.55 : 0;
        else if (m === 'today') b = corner ? 0 : 0.5 + 0.5 * Math.sin(t * 5);
        else b = corner ? 0 : 0.16;
        if (b > 0) out.push({x: x0 + w, y: y0 + v, b, c: m === 'today' && !edge ? 1 : 0});
      }
  });
  // the rule: never two in a row. A bracket under yesterday and today
  const xm = Math.round(f.cx + (2 - 3) * sp), xt = Math.round(f.cx + (3 - 3) * sp);
  for (let x = xm - 1.5; x <= xt + 1.5; x++) out.push({x, y: Math.round(f.cy) + 4.5, b: 0.5});
  return out;
};

// ---------- alarm clock, ringing ----------
export const alarm = (f: Frame, t: number, lt: number): Tgt[] => {
  const u = f.u;
  const body = raster(K(f, 'alarm'), f.cols, f.rows, (g) => {
    g.lineWidth = u * 0.24;
    g.beginPath();
    g.arc(f.cx, f.cy + u * 0.25, u * 1.25, 0, Math.PI * 2);
    g.stroke();
    // bells
    g.beginPath();
    g.arc(f.cx - u * 0.95, f.cy - u * 0.95, u * 0.42, Math.PI * 0.9, Math.PI * 1.95);
    g.closePath();
    g.fill();
    g.beginPath();
    g.arc(f.cx + u * 0.95, f.cy - u * 0.95, u * 0.42, Math.PI * 1.05, Math.PI * 2.1);
    g.closePath();
    g.fill();
    // legs
    g.lineWidth = u * 0.2;
    g.beginPath();
    g.moveTo(f.cx - u * 0.7, f.cy + u * 1.3);
    g.lineTo(f.cx - u * 1.0, f.cy + u * 1.75);
    g.moveTo(f.cx + u * 0.7, f.cy + u * 1.3);
    g.lineTo(f.cx + u * 1.0, f.cy + u * 1.75);
    g.stroke();
  });
  const out: Tgt[] = body.map((p) => ({x: p.x, y: p.y, b: 1}));
  // hands at 6:30, drawn as dots
  for (let k = 0; k <= 6; k++) out.push({x: f.cx, y: f.cy + u * 0.25 + (k / 6) * u * 0.85, b: 1});
  for (let k = 0; k <= 4; k++) out.push({x: f.cx + (k / 4) * u * 0.12, y: f.cy + u * 0.25 + (k / 4) * u * 0.55, b: 0.8});
  out.push({x: f.cx, y: f.cy + u * 0.25, b: 1, c: 1});
  // ringing: shake in bursts, with sound arcs
  const ring = lt < 1.6 || t % 1.4 < 0.45;
  const sh = ring ? Math.sin(t * 55) * 0.45 : 0;
  for (const p of out) {
    const k = (p.y - (f.cy + u * 1.75)) / (u * 3);
    p.x += sh * (-k);
  }
  for (let side = -1; side <= 1; side += 2)
    for (let k = 0; k < 2; k++)
      for (let a = 0; a < 5; a++) {
        const ang = -Math.PI / 2 + side * (0.5 + a * 0.13);
        const r = u * (1.85 + k * 0.4);
        out.push({x: f.cx + Math.cos(ang) * r, y: f.cy - u * 0.2 + Math.sin(ang) * r, b: ring ? 0.8 - k * 0.35 : 0.1});
      }
  return out;
};

// ---------- five flames ----------
export const flames = (f: Frame, t: number, lt: number, n: number): Tgt[] => {
  const out: Tgt[] = [];
  const sp = 6.6;
  for (let k = 0; k < n; k++) {
    const ff: Frame = {...f, cx: Math.round(f.cx + (k - (n - 1) / 2) * sp) + 0.5};
    out.push(...flame(ff, t + k, {h: f.u * 0.9, ignite: Math.min(1, Math.max(0, (lt - 0.3 - k * 0.18) * 3))}));
  }
  return out;
};

// ---------- 66 days ----------
export const grid66 = (f: Frame, t: number, lt: number, day: number, cols = 11): Tgt[] => {
  const out: Tgt[] = [];
  const rows = Math.ceil(66 / cols);
  const sp = Math.max(1, Math.round(f.u * 0.38));
  for (let i = 0; i < 66; i++) {
    const c = i % cols, r = Math.floor(i / cols);
    const x = Math.round(f.cx + (c - (cols - 1) / 2) * sp) + 0.5, y = Math.round(f.cy + (r - (rows - 1) / 2) * sp) + 0.5;
    const fill = Math.min(day, lt * 40);
    const isToday = i === day;
    const b = i < fill ? 1 : isToday ? 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(t * 5)) : 0.18;
    out.push({x, y, b, c: isToday || (i === day - 1 && day === 66) ? 1 : 0});
  }
  return out;
};

// ---------- infinity: the loop runs itself ----------
export const infinity = (f: Frame, t: number): Tgt[] => {
  const out: Tgt[] = [];
  const N = 70;
  const A = f.u * 1.9;
  for (let k = 0; k < N; k++) {
    const s = (k / N) * Math.PI * 2 + t * 0.9;
    const d = 1 + Math.sin(s) * Math.sin(s);
    const x = f.cx + (A * Math.cos(s)) / d, y = f.cy + (A * Math.sin(s) * Math.cos(s)) / d;
    const head = k / N;
    out.push({x, y, b: 0.15 + 0.85 * Math.pow(head, 1.5), c: k === N - 1 ? 1 : 0});
  }
  return out;
};

// ---------- equaliser of the session's heart rate ----------
export const equalizer = (f: Frame, t: number, lt: number, series: number[], H: number, peakAt: number): Tgt[] => {
  const out: Tgt[] = [];
  const n = series.length;
  for (let c = 0; c < n; c++) {
    const x = Math.round(f.cx - n / 2 + c) + 0.5;
    const grow = Math.min(1, Math.max(0, (lt - c * 0.035) * 3.2));
    const hgt = Math.round(series[c] * H * grow);
    for (let r = 0; r < H; r++) {
      const y = Math.round(f.cy + H / 2 - r) - 0.5;
      const on = r < hgt;
      out.push({x, y, b: on ? (r === hgt - 1 ? 1 : 0.85) : 0.08, c: on && c === peakAt && r === hgt - 1 ? 1 : 0});
    }
  }
  return out;
};

export const scatterField = (f: Frame, t: number, n: number, seed = 31): Tgt[] => {
  const out: Tgt[] = [];
  for (let i = 0; i < n; i++) out.push({x: Math.floor(hash(i, seed) * f.cols) + 0.5, y: Math.floor(hash(i, seed + 1) * f.rows) + 0.5, b: 0.12 + 0.3 * Math.pow(0.5 + 0.5 * Math.sin(t * (0.6 + hash(i, seed + 2)) + i), 4)});
  return out;
};
