/**
 * Shared helpers for the Matrix Dynamic scene files. Read-only for scene authors: put anything new in your own file.
 */
import {PROOF} from '../../hero4/card4';
import {CX, CY, G, MC, RINGS, cl, lerp, rnd} from '../mxlib';

export {PROOF};
export const TAU = Math.PI * 2;
export const ringHap = RINGS.map((t, i) => ({t, kind: (i % 2 ? 'medium' : 'heavy') as 'medium' | 'heavy'}));
export const charge = (t: number) => Math.min(0.98, 0.18 + ((t * 0.02) % 0.8));
export const twinkle = (g: G, n: number, seed: number, t: number, x0 = 4, x1 = 37, y0 = 1, y1 = 33, b = 0.7) => {
  for (let i = 0; i < n; i++) g.on(x0 + rnd(seed + i) * (x1 - x0), y0 + rnd(seed + i + 50) * (y1 - y0), b * (0.25 + 0.75 * (0.5 + 0.5 * Math.sin(t * (1 + rnd(i + seed) * 2) + i * 2.3))));
};
export const twinkleB = (g: G, n: number, seed: number, t: number, b = 0.6) => {
  for (let i = 0; i < n; i++) g.on(4 + rnd(seed + i) * 33, 1 + rnd(seed + i + 50) * 32, b * (0.25 + 0.75 * (0.5 + 0.5 * Math.sin(t * (1 + rnd(i + seed) * 2) + i * 2.3))));
};
export const chevron = (g: G, x: number, y: number, w: number, h: number, dir: 'up' | 'down' | 'right', b: number, c = 0) => {
  if (dir === 'up') {
    g.line(x - w, y + h, x, y, b, c);
    g.line(x, y, x + w, y + h, b, c);
  } else if (dir === 'down') {
    g.line(x - w, y, x, y + h, b, c);
    g.line(x, y + h, x + w, y, b, c);
  } else {
    g.line(x, y - h, x + w, y, b, c);
    g.line(x + w, y, x, y + h, b, c);
  }
};
export const chevronUp = (g: G, x: number, y: number, w: number, h: number, b: number, c = 0) => {
  g.line(x - w, y + h, x, y, b, c);
  g.line(x, y, x + w, y + h, b, c);
};
/** live session progress 0..1 (20 minutes) */
export const liveP = (c: MC) => cl(c.d.atgym / PROOF);
/** whole minutes done at the gym, 0..20 */
export const mins = (c: MC) => Math.min(20, Math.floor(c.d.atgym / 60));
/** a flare at the start of every new minute */
export const flare = (c: MC) => Math.exp(-((((c.d.atgym / 60) % 1) * 60) / 0.9));
/** seconds since the 20-minute proof was reached, or -1 */
export const hitAge = (c: MC) => (c.d.atgym >= PROOF ? c.d.atgym - PROOF : -1);
/** evening time left, 0..1 of six hours */
export const slP = (c: MC) => cl(c.d.stillLeft / (6 * 3600));
export const weekRow = (g: G, y: number, lit: (i: number) => number, coral = -1) => {
  for (let i = 0; i < 7; i++) {
    const b = lit(i);
    if (b < 0) g.rect(7 + i * 4.3, y - 1, 3, 3, 0.35);
    else {
      g.rect(7 + i * 4.3, y - 1, 3, 3, b, true);
      if (i === coral) g.on(8 + i * 4.3, y, 1, 1);
    }
  }
};
export const rot = (x: number, y: number, a: number): [number, number] => [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)];
export const starPts = (cx: number, cy: number, R: number, r: number, per = 6) => {
  const V: [number, number][] = [];
  for (let k = 0; k < 10; k++) {
    const a = (k / 10) * TAU, rr = k % 2 ? r : R;
    V.push([cx + Math.sin(a) * rr, cy - Math.cos(a) * rr]);
  }
  const o: [number, number][] = [];
  for (let k = 0; k < 10; k++) {
    const [x0, y0] = V[k], [x1, y1] = V[(k + 1) % 10];
    for (let i = 0; i < per; i++) o.push([lerp(x0, x1, i / per), lerp(y0, y1, i / per)]);
  }
  return o;
};
void CX;
void CY;
