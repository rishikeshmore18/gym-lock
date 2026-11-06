/**
 * Matrix Dynamic: ready. One scene per day, Monday first (index 0) to Sunday (index 6).
 * Board: 38 x 35 cells, centre (CX, CY) = (22, 17). See ../MATRIX-DESIGN.md.
 * The alarm is beaten: every day shows one clear "you're up, get going" object, with one beat after the
 * entrance and a calm board after it. Anything that moves is a free particle, pushed in the same order and
 * count every frame; static structure is lit cells.
 */
import {G, MScn, back, cl, eio, ez, lerp} from '../mxlib';

type Pt = [number, number, number];
/** '#' lit, 'o' coral, '+' dim */
const bmp = (rows: string[]): Pt[] => {
  const o: Pt[] = [];
  rows.forEach((r, j) => [...r].forEach((ch, i) => {
    const k = '#o+'.indexOf(ch);
    if (k >= 0) o.push([i, j, k]);
  }));
  return o;
};
const rotP = (x: number, y: number, px: number, py: number, a: number): [number, number] => {
  const c = Math.cos(a), s = Math.sin(a), dx = x - px, dy = y - py;
  return [px + dx * c - dy * s, py + dx * s + dy * c];
};
const TAU = Math.PI * 2;
const gauss = (x: number, s: number) => Math.exp(-((x / s) ** 2));

// ---------- Mon: power ----------
const PW = {cx: 22.5, cy: 18.5, r: 8.5, gap: 0.62};

// ---------- Tue: the front door (hinge on the left, opening toward you) ----------
const DOOR: Pt[] = (() => {
  const o: Pt[] = [];
  const x0 = 16, x1 = 29, y0 = 5, y1 = 30;
  for (let x = x0; x <= x1; x++) o.push([x, y0, 0], [x, y1, 0]);
  for (let y = y0 + 1; y < y1; y++) o.push([x0, y, 0], [x1, y, 0]);
  for (const [a, b] of [[7, 15], [18, 28]]) {
    for (let x = 18; x <= 27; x++) o.push([x, a, 2], [x, b, 2]);
    for (let y = a + 1; y < b; y++) o.push([18, y, 2], [27, y, 2]);
  }
  o.push([27, 17, 1]);
  return o;
})();

// ---------- Wed: a location signal locking on ----------
const GP = {cx: 22.5, cy: 17.5};

// ---------- Fri: the gym bag ----------
const BAG = bmp([
  '.....#######.....',
  '....#.......#....',
  '....#.......#....',
  '.###############.',
  '#...............#',
  '#.++++++++++++o.#',
  '#...............#',
  '#...............#',
  '#...............#',
  '#...............#',
  '.###############.',
]);
const CHEV = [[0, -3], [1, -2], [2, -1], [3, 0], [2, 1], [1, 2], [0, 3]];

// ---------- Sat: a key on a split ring (key cells relative to the ring's centre) ----------
const KEYP: Pt[] = (() => {
  const o: Pt[] = [];
  const bx = 6.5; // the bow's centre, linked through the ring
  for (let i = 0; i < 22; i++) {
    const a = (i / 22) * TAU;
    o.push([bx + Math.sin(a) * 3.6, -Math.cos(a) * 3.6, 0]);
  }
  for (let x = 10.5; x <= 24.5; x++) o.push([x, -0.5, 0], [x, 0.5, 0]);
  o.push([25.5, -0.5, 1]);
  for (const [x, y] of [[16.5, 1.5], [17.5, 1.5], [17.5, 2.5], [19.5, 1.5], [21.5, 1.5], [22.5, 1.5], [22.5, 2.5]]) o.push([x, y, 0]);
  return o;
})();

export const SCENES: MScn[] = [
  // Mon: POWER ON. The symbol forms dim, then switches on: the stem lights, the ring fills round, one shockwave
  {
    draw: (g: G, c) => {
      const T = c.T, {cx, cy, r, gap} = PW;
      const sweep = (T - 0.6) / 0.35;
      for (let i = 0; i < 10; i++) {
        const on = cl((T - 0.6 - i * 0.012) / 0.06);
        g.fr(cx, cy - 11 + i, 0.3 + 0.7 * on, i === 0 ? 1 : 0);
      }
      const N = 44, idle = T > 1.6 ? (((T - 1.6) / 3.2) % 1) * TAU : -9;
      for (let i = 0; i < N; i++) {
        const a = gap + (i / (N - 1)) * (TAU - 2 * gap), d = Math.min(a - gap, TAU - gap - a) / (Math.PI - gap);
        const on = cl((sweep - d) / 0.25), glow = 0.12 * gauss(Math.atan2(Math.sin(a - idle), Math.cos(a - idle)), 0.5);
        g.fr(cx + Math.sin(a) * r, cy - Math.cos(a) * r, 0.3 + 0.62 * on + glow);
      }
      // the shockwave when the ring closes
      const w = T - 0.95, live = w >= 0 && w < 0.8;
      for (let i = 0; i < 40; i++) {
        const a = (i / 40) * TAU, rr = live ? r + 1.5 + 6 * ez(w / 0.7) : r + 1.5;
        g.fr(cx + Math.sin(a) * rr, cy - Math.cos(a) * rr, live ? 0.75 * (1 - w / 0.8) : 0);
      }
      const hb = w >= 0 ? Math.exp(-w / 0.12) : 0;
      return {flash: 0.14 * hb, shake: 0.12 * hb, o: {stagger: 0.25}};
    },
    hap: [{t: 0.6, kind: 'light'}, {t: 0.95, kind: 'heavy'}],
  },
  // Tue: THE FRONT DOOR. It unlatches and swings open toward you; daylight fills the frame
  {
    draw: (g: G, c) => {
      const T = c.T, th = 1.05 * back((T - 0.7) / 0.65, 1.1), hx = 16;
      const edge = hx + 14 * Math.cos(th);
      for (let y = 5; y <= 30; y++)
        for (let x = 17; x <= 28; x++) g.on(x, y, x + 0.5 > edge + 0.6 ? 0.3 + 0.12 * cl((x + 0.5 - edge) / 6) : 0);
      for (let y = 4; y <= 30; y++) g.on(15, y, 0.45), g.on(30, y, 0.45);
      for (let x = 15; x <= 30; x++) g.on(x, 4, 0.45);
      g.line(9, 31, 36, 31, 0.3);
      for (const [x, y, k] of DOOR) {
        const u = x + 0.5 - hx, X = hx + u * Math.cos(th), Y = 18 + (y + 0.5 - 18) * (1 + 0.13 * (u / 14) * Math.sin(th));
        g.fr(X, Y, k === 2 ? 0.5 : 0.95, k === 1 ? 1 : 0);
      }
      const hb = T > 0.7 ? Math.exp(-(T - 0.7) / 0.15) : 0;
      return {shake: 0.12 * hb, o: {stagger: 0.25}};
    },
    hap: [{t: 0.7, kind: 'medium'}],
  },
  // Wed: SIGNAL LOCKED. Search rings close in on you; the fix locks with a snap, then pings out steadily
  {
    draw: (g: G, c) => {
      const T = c.T, {cx, cy} = GP, L = 1.02, lk = T - L;
      // three search rings, each closing from the edge onto the point
      for (let k = 0; k < 3; k++) {
        const u = (T - 0.1 - k * 0.18) / 0.55, live = u >= 0 && u < 1;
        const r = live ? lerp(14, 2.5, eio(u)) : 14;
        for (let i = 0; i < 36; i++) {
          const a = (i / 36) * TAU;
          g.fr(cx + Math.sin(a) * r, cy - Math.cos(a) * r, live ? 0.25 + 0.6 * u : 0);
        }
      }
      // the lock: four brackets snap in around the fix
      const d = lk < 0 ? 13 : 5.5 + 7.5 * Math.exp(-lk / 0.07);
      for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]])
        for (let q = 0; q < 3; q++) {
          g.fr(cx + sx * d, cy + sy * (d - q), lk < 0 ? 0 : 1);
          if (q) g.fr(cx + sx * (d - q), cy + sy * d, lk < 0 ? 0 : 1);
        }
      // the fix: you, with a steady ring around you
      for (let i = 0; i < 12; i++) {
        const a = (i / 12) * TAU;
        g.fr(cx + Math.sin(a) * 1.9, cy - Math.cos(a) * 1.9, lk < 0 ? 0.3 : 0.9);
      }
      g.fr(cx, cy, 1, 1);
      // locked: one calm ping out every 2.6 s
      const pa = lk < 0.2 ? 9 : (lk - 0.2) % 2.6, live = pa < 1.2;
      for (let i = 0; i < 40; i++) {
        const a = (i / 40) * TAU, r = live ? 3 + 10 * ez(pa / 1.1) : 3;
        g.fr(cx + Math.sin(a) * r, cy - Math.cos(a) * r, live ? 0.45 * (1 - pa / 1.2) : 0);
      }
      const hb = lk >= 0 ? Math.exp(-lk / 0.12) : 0;
      return {flash: 0.1 * hb, shake: 0.14 * hb, o: {stagger: 0.25}};
    },
    hap: [{t: 1.02, kind: 'heavy'}],
  },
  // Thu: FADER UP. The master fader shoots from the floor to the top; the level lights behind it
  {
    draw: (g: G, c) => {
      const T = c.T, yc = lerp(26.5, 7.5, back((T - 0.45) / 0.45, 1.3));
      const pulse = T > 1.4 ? 29 - (((T - 1.4) / 2.6) % 1) * 30 : -9;
      for (let y = 5; y <= 29; y++) {
        const lit = y + 0.5 > yc + 2.5, b = 0.8 + 0.2 * gauss(y - pulse, 1.6);
        g.on(22, y, lit ? b : 0.22);
      }
      for (let i = 0; i <= 8; i++) {
        const y = 5 + i * 3, lit = y + 0.5 > yc + 1.2, b = lit ? 0.75 : 0.22, L = i % 2 ? 2 : 3;
        for (let q = 0; q < L; q++) g.on(15 - q, y, b), g.on(29 + q, y, b);
      }
      // the knob: a 9 x 5 cap with grip lines, the centre line in coral
      for (const dy of [-2, 2]) for (let x = 18; x <= 26; x++) g.fr(x + 0.5, yc + dy, 1);
      for (const dy of [-1, 0, 1]) {
        g.fr(18.5, yc + dy, 1);
        g.fr(26.5, yc + dy, 1);
        for (let x = 20; x <= 24; x++) g.fr(x + 0.5, yc + dy, dy ? 0.4 : x === 22 ? 1 : 0.85, !dy && x === 22 ? 1 : 0);
      }
      const hb = T > 0.9 ? Math.exp(-(T - 0.9) / 0.12) : 0;
      return {flash: 0.12 * hb, shake: 0.15 * hb, o: {stagger: 0.25}};
    },
    hap: [{t: 0.9, kind: 'heavy'}],
  },
  // Fri: GRAB THE BAG. It lifts off the floor; the chevrons fire toward the door, then keep pointing the way
  {
    draw: (g: G, c) => {
      const T = c.T, u = T - 0.6;
      const lift = u < 0 ? 0 : -1.6 * Math.sin(Math.min(1, u / 0.5) * Math.PI) - 0.9 * cl(u / 0.3);
      for (const [x, y, k] of BAG) g.fr(9.5 + x, 12.5 + y + lift, k === 2 ? 0.45 : 0.95, k === 1 ? 1 : 0);
      for (let i = 0; i < 3; i++) {
        const shot = u >= 0 ? Math.exp(-((u - i * 0.07) ** 2) / 0.012) : 0;
        const flow = T > 1.4 ? gauss(((((T - 1.4) / 1.8) % 1) * 5 - 1) - i, 0.55) : 0;
        const b = 0.45 + 0.55 * Math.max(shot, flow);
        for (const [dx, dy] of CHEV) g.fr(28.5 + i * 3 + dx + 0.8 * shot, 17.5 + dy, b);
      }
      const hb = u >= 0 ? Math.exp(-u / 0.14) : 0;
      return {shake: 0.12 * hb, o: {stagger: 0.25}};
    },
    hap: [{t: 0.6, kind: 'medium'}],
  },
  // Sat: THE KEYS. Picked up off the hook: the key swings on its ring and settles. Easy pace.
  {
    draw: (g: G, c) => {
      const T = c.T, u = T - 0.6, cx = 10.5, cy = 18;
      const e = u > 0 ? Math.exp(-u / 0.7) : 0, lift = u > 0 ? -1.4 * Math.sin(Math.min(1, u / 0.6) * Math.PI) : 0;
      const ra = 0.9 * (1 - e) * (u > 0 ? 1 : 0) + 0.5 * e * Math.sin(u * 9), ka = u > 0 ? 0.32 * e * Math.sin(u * 7.5) : 0;
      // the split ring turns as the key runs round it
      for (let i = 0; i < 22; i++) {
        const a = 0.35 + (i / 22) * (TAU - 0.5) + ra;
        g.fr(cx + Math.sin(a) * 3.4, cy + lift - Math.cos(a) * 3.4, 0.8);
      }
      for (const [x, y, k] of KEYP) {
        const [X, Y] = rotP(cx + x, cy + lift + y, cx + 3.4, cy + lift, ka);
        g.fr(X, Y, 0.95, k === 1 ? 1 : 0);
      }
      const hb = u > 0 ? Math.exp(-u / 0.12) : 0;
      return {shake: 0.1 * hb, o: {stagger: 0.25}};
    },
    hap: [{t: 0.6, kind: 'medium'}],
  },
  // Sun: OUT BY 06:45. The minute hand sweeps the quarter hour from 06:30 to 06:45, where you leave
  {
    draw: (g: G, c) => {
      const T = c.T, cx = 22.5, cy = 18.5, p = eio((T - 0.4) / 1.0);
      const am = Math.PI + (Math.PI / 2) * p, ah = Math.PI + Math.PI / 12 + (Math.PI / 24) * p;
      g.ring(cx, cy, 11, 0.75);
      for (let i = 0; i < 12; i++) {
        const a = (i / 12) * TAU, maj = i % 3 === 0;
        if (i === 9) {
          g.on(cx - 9, cy, 1, 1);
          g.on(cx - 8, cy, 0.9);
          continue;
        }
        g.on(cx + Math.sin(a) * 9, cy - Math.cos(a) * 9, maj ? 0.85 : 0.35);
        if (maj) g.on(cx + Math.sin(a) * 8, cy - Math.cos(a) * 8, 0.85);
      }
      // the quarter hour, lit as the hand passes
      const arrive = T > 1.4 ? Math.exp(-(T - 1.4) / 0.35) : 0;
      for (let y = Math.floor(cy); y <= cy + 8; y++)
        for (let x = Math.floor(cx - 8); x <= cx; x++) {
          const dx = x + 0.5 - cx, dy = y + 0.5 - cy, d = Math.hypot(dx, dy);
          if (d > 7.2 || d < 1.5) continue;
          const a = Math.atan2(dx, -dy) + TAU;
          g.on(x, y, a <= am + 0.05 ? 0.3 + 0.35 * arrive : 0);
        }
      for (let q = 1; q <= 8; q++) g.fr(cx + Math.sin(am) * q, cy - Math.cos(am) * q, 1);
      for (let q = 1; q <= 5; q++) g.fr(cx + Math.sin(ah) * q, cy - Math.cos(ah) * q, 0.9);
      g.on(cx, cy, 1);
      return {flash: 0.08 * arrive, o: {stagger: 0.25}};
    },
    hap: [{t: 1.4, kind: 'medium'}],
  },
];
