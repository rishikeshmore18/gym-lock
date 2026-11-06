/**
 * Ridge scenes: one painted world per day of the week, and every moment of that day happens in it.
 * The world keeps its seed all day, so Wednesday's lake at bedtime is the same lake at the countdown
 * and on the Done card, just at a different hour.
 *
 *   Mon  dawn    a sea of clouds; the sun is the meter
 *   Tue  stone   the ridge and this week's rock; the rock is the meter
 *   Wed  water   a mountain lake and a rowboat; the boat and the ripples are the meter
 *   Thu  pine    the pine on the ledge, fog, fireflies; the tree is the meter
 *   Fri  summit  a trail to the top and a beacon; the climb is the meter
 *   Sat  sea     a shore at sunset, the tide, paper lanterns
 *   Sun  stars   a night sky and the week's constellation; the stars are the meter
 */
import type {D4, S4} from '../hero4/card4';
import {PROOF} from '../hero4/card4';
import type {Pos} from '../hero11/copy11';
import {DATA11, Data11, grow} from '../hero11/scenes11';
import {DONE_DATA} from '../hero11/copy11';
import {Kind} from '../hero10/wash2';
import {Scene3} from './wash3';
import {Day, tapsFor12} from './days12';

export const dataFor12 = (s: S4, pos: Pos): Data11 => (s === 'verified' ? {...DATA11.verified, ...DONE_DATA[pos]} : DATA11[s]);

const cl = (x: number) => Math.min(1, Math.max(0, x));
export const ease = (x: number) => 1 - Math.pow(1 - cl(x), 3);
export const charge = (t: number) => Math.min(0.98, 0.18 + ((t * 0.02) % 0.8));
/** one seed per world: the same place all day */
export const WSEED = [17, 3, 8, 11, 5, 14, 19];

type P = Partial<Scene3> & {kind: Kind};
type Ctx = {d: D4; T: number; t: number; at: number; pos: Pos; D: Data11; n: number};
type Row = [(c: Ctx) => P, (c: Ctx) => P, (c: Ctx) => P, (c: Ctx) => P, (c: Ctx) => P, (c: Ctx) => P, (c: Ctx) => P];

const cdP = (c: Ctx) => 1 - cl(c.d.countdown / 7200); // progress toward gym time
const slP = (c: Ctx) => cl(c.d.stillLeft / (6 * 3600)); // evening time left
const liveP = (c: Ctx) => cl(c.d.atgym / PROOF);
const proofAt = (c: Ctx) => (c.d.atgym >= PROOF ? c.t - (c.d.atgym - PROOF) : null);
const every = (t: number, k: number) => Math.floor(t / k) * k;
const times = (at: number, n: number, gap: number) => Array.from({length: n}, (_, i) => at + i * gap);

const V: Record<S4, Row> = {
  setup: [
    (c) => ({kind: 'sunrise', sun: -0.08 + 0.12 * c.n, mist: 0.8, birds: 2}),
    (c) => ({kind: 'ridge', sun: 0.45, mist: 0.6}),
    (c) => ({kind: 'lake', sun: 0.45, mist: 0.9, ripples: Math.round(c.n)}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.35, mist: 1.1}),
    (c) => ({kind: 'path', trail: 0.27 * c.n, sun: 0.4}),
    (c) => ({kind: 'beach', sun: 0.35, birds: 2}),
    (c) => ({kind: 'night', night: 1, charge: 0.3, stars: c.n * 1.2, mist: 0.6}),
  ],
  firstnight: [
    (c) => ({kind: 'sunrise', night: 0.75, sun: -0.3, mist: 0.8}),
    (c) => ({kind: 'night', night: 1, charge: 0.12, mist: 0.6}),
    (c) => ({kind: 'lake', night: 1, sun: 0.2, mist: 0.6}),
    (c) => ({kind: 'ridge', noRock: true, night: 0.75, sun: 0.1, mist: 0.6, fireflies: 9}),
    (c) => ({kind: 'path', night: 0.75, trail: 0, sun: 0.1}),
    (c) => ({kind: 'sunset', night: 0.5, sun: -0.02}),
    (c) => ({kind: 'night', night: 1, charge: 0.2, stars: 0, shoot: every(c.t, 6), mist: 0.5}),
  ],
  bedtime: [
    (c) => ({kind: 'night', night: 1, charge: charge(c.t), mist: 0.7}),
    (c) => ({kind: 'ridge', night: 1, sun: 0.2, mist: 0.6}),
    (c) => ({kind: 'lake', night: 1, sun: 0.2, mist: 0.6, ripples: 1}),
    (c) => ({kind: 'ridge', noRock: true, night: 0.75, sun: 0.1, mist: 0.8, fireflies: 12}),
    (c) => ({kind: 'path', night: 0.75, trail: 0, sun: 0.1, beacon: 0.12}),
    (c) => ({kind: 'beach', night: 0.75, sun: 0.05}),
    (c) => ({kind: 'night', night: 1, charge: charge(c.t), stars: charge(c.t) * 7, mist: 0.5}),
  ],
  wake: [
    (c) => ({kind: 'sunrise', sun: -0.35 + 0.6 * ease(c.T / 3.2), night: 0.5 * (1 - ease(c.T / 3.2)), birds: 4}),
    (c) => ({kind: 'ridge', sun: -0.1 + 0.5 * ease(c.T / 3), night: 0.25 * (1 - ease(c.T / 2)), mist: 0.9}),
    (c) => ({kind: 'lake', sun: -0.1 + 0.35 * ease(c.T / 3), night: 0.25, mist: 1.2}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.2, mist: 1.1, burst: c.at + 1, burstAt: 'tree'}),
    (c) => ({kind: 'path', trail: 0.02, sun: 0.1 + 0.3 * ease(c.T / 3), night: 0.25, birds: 2}),
    (c) => ({kind: 'beach', sun: 0.05 + 0.25 * ease(c.T / 3), birds: 3}),
    (c) => ({kind: 'night', night: 0.5, charge: 0.98, stars: 7, starLines: 0, shoot: c.at + 0.8, mist: 0.6}),
  ],
  countdown: [
    (c) => ({kind: 'sunrise', sun: -0.35 + 0.6 * cdP(c), night: 0.5 * (1 - cdP(c)), birds: 2}),
    (c) => ({kind: 'hourglass', sand: c.d.countdown / 7200, sun: 0.45, mist: 0.9}),
    (c) => ({kind: 'lake', drip: true, sun: 0.3, mist: 0.9}),
    (c) => ({kind: 'hourglass', prop: 'lantern', candle: cl(c.d.countdown / 7200), hgBg: 'fog', night: 0.5, mist: 1, fireflies: 5}),
    (c) => ({kind: 'path', trail: 0.81 * cdP(c), sun: 0.3 + 0.2 * cdP(c)}),
    (c) => ({kind: 'beach', tide: cdP(c), sun: 0.3}),
    (c) => ({kind: 'night', night: cdP(c) > 0.75 ? 0.75 : 1, charge: 0.98, moonX: 0.62 + 0.25 * cdP(c), moonY: 0.1 + 0.48 * cdP(c), stars: 7, mist: 0.5}),
  ],
  ready: [
    (c) => ({kind: 'sunrise', sun: 0.45, birds: 5}),
    (c) => ({kind: 'ridge', sun: 0.4, mist: 0.7, birds: 3}),
    (c) => ({kind: 'lake', sun: 0.35, mist: 0.9}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.4, mist: 0.9, birds: 3}),
    (c) => ({kind: 'path', trail: 0.03, sun: 0.4, birds: 2}),
    (c) => ({kind: 'beach', steps: 0.25, sun: 0.3}),
    (c) => ({kind: 'night', night: 0.5, charge: 0.98, moonX: 0.9, moonY: 0.5, stars: 7, mist: 0.7}),
  ],
  commute: [
    (c) => ({kind: 'sunrise', sun: 0.3, birds: 7}),
    (c) => ({kind: 'path', trail: 0.05 + ((c.T * 0.04) % 0.3), sun: 0.45, mist: 1, peak: 0.4}),
    (c) => ({kind: 'lake', boatX: 0.5 + ((c.T * 0.02) % 0.4), sun: 0.4, mist: 0.8}),
    (c) => ({kind: 'path', trail: 0.1 + ((c.T * 0.035) % 0.3), sun: 0.3, mist: 1.4, peak: 0.3}),
    (c) => ({kind: 'path', trail: 0.4 + ((c.T * 0.03) % 0.38), sun: 0.5, birds: 3}),
    (c) => ({kind: 'beach', steps: (c.T * 0.06) % 1, sun: 0.35}),
    (c) => ({kind: 'night', night: 0.5, charge: 0.9, stars: 4, shoot: every(c.t, 4), mist: 0.5}),
  ],
  atgym: [
    (c) => ({kind: 'sunrise', sun: -0.25 + 0.75 * ease(liveP(c)), flash: proofAt(c), burst: proofAt(c), burstAt: 'sun', birds: 2}),
    (c) => ({kind: 'ridge', cracks: liveP(c) * 5, broken: c.d.atgym >= PROOF ? ease((c.d.atgym - PROOF) / 0.8) : 0, sun: 0.45, mist: 0.8}),
    (c) => ({kind: 'lake', boatX: 0.52 + 0.38 * liveP(c), sun: 0.45, mist: 0.8, flash: proofAt(c)}),
    (c) => ({kind: 'ridge', noRock: true, tree: grow(c.D.day) * (0.8 + 0.2 * Math.round(liveP(c) * 20) / 20), sun: 0.45, mist: 0.8, burst: proofAt(c), burstAt: 'tree'}),
    (c) => ({kind: 'path', trail: 0.81 + 0.19 * liveP(c), sun: 0.5, beacon: c.d.atgym >= PROOF ? ease((c.d.atgym - PROOF) / 1.2) : 0, flash: proofAt(c)}),
    (c) => ({kind: 'sunset', sun: 0.55 - 0.45 * liveP(c), night: liveP(c) > 0.85 ? 0.25 : 0, lanterns: proofAt(c) != null ? times(proofAt(c)!, 5, 0.3) : []}),
    (c) => ({kind: 'night', night: 0.75, charge: 0.98, stars: liveP(c) * 7, starLines: c.d.atgym >= PROOF ? ease((c.d.atgym - PROOF) / 1) : 0, shoot: proofAt(c) != null ? proofAt(c)! + 0.6 : null, mist: 0.5}),
  ],
  verified: [
    (c) => ({kind: 'sunrise', sun: c.pos === 'last' ? 0.6 : 0.5, birds: 4, flash: c.at + 0.15, burst: c.at + 0.3, burstAt: 'sun'}),
    (c) => ({kind: 'ridge', cracks: 5, broken: 1, sun: 0.5, mist: 0.7, rubble: c.pos === 'last' ? 7 : Math.min(7, Math.floor(c.D.sessions / 3))}),
    (c) => ({kind: 'lake', sun: 0.5, mist: 0.8, skipN: tapsFor12(2, c.pos), skips: times(c.at + 0.3, tapsFor12(2, c.pos), 0.32), skipDone: c.at + 0.3 + tapsFor12(2, c.pos) * 0.32}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.5, mist: 0.7, burst: c.at + 0.4, burstAt: 'tree'}),
    (c) => ({kind: 'path', trail: 1, beacon: ease((c.T - 0.2) / 1.2), sun: 0.45, flash: c.at + 0.3}),
    (c) => ({kind: 'sunset', sun: 0.15, night: 0.25, lanterns: times(c.at + 0.3, tapsFor12(5, c.pos), 0.3)}),
    (c) => ({kind: 'night', night: 1, charge: 0.98, stars: 7, starLines: ease((c.T - 0.3) / 1), shoot: c.at + 0.9, mist: 0.5}),
  ],
  stilltime: [
    (c) => ({kind: 'sunrise', sun: 0.05 + slP(c) * 0.4, night: 0.25, birds: 2}),
    (c) => ({kind: 'hourglass', sand: slP(c), sun: 0.1, night: 0.25}),
    (c) => ({kind: 'lake', sun: 0.05 + slP(c) * 0.4, night: 0.25, mist: 0.8}),
    (c) => ({kind: 'hourglass', prop: 'lantern', candle: slP(c), hgBg: 'fog', night: 0.5, mist: 1, fireflies: 8}),
    (c) => ({kind: 'path', trail: 0.81, sun: 0.1 + slP(c) * 0.4, night: 0.25}),
    (c) => ({kind: 'sunset', sun: 0.1 + slP(c) * 0.5, birds: 3}),
    (c) => ({kind: 'night', night: 0.75, charge: 0.6, moonY: 0.15 + 0.45 * slP(c), stars: 2, mist: 0.6}),
  ],
  rest: [
    (c) => ({kind: 'sunrise', sun: 0.3, mist: 1, birds: 2}),
    (c) => ({kind: 'cairn', stones: 3, sun: 0.45, mist: 1}),
    (c) => ({kind: 'lake', sun: 0.5, mist: 0.9, ripples: c.D.week}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.4, mist: 1.2, peak: 0.6, birds: 2}),
    (c) => ({kind: 'path', trail: 0, sun: 0.5, beacon: 0.15}),
    (c) => ({kind: 'beach', sun: 0.4, birds: 2}),
    (c) => ({kind: 'night', night: 1, charge: 0.7, stars: 7, starLines: 0.6, mist: 0.5}),
  ],
  paused: [
    (c) => ({kind: 'sunrise', sun: 0.2, snow: 0.6}),
    (c) => ({kind: 'ridge', sun: 0.3, mist: 0.9, snow: 1}),
    (c) => ({kind: 'lake', sun: 0.35, mist: 0.8, frozen: true, snow: 0.4}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.25, mist: 0.9, snow: 1}),
    (c) => ({kind: 'path', trail: 0.4, sun: 0.3, snow: 0.8}),
    (c) => ({kind: 'beach', sun: 0.3, birds: 2}),
    (c) => ({kind: 'night', night: 1, charge: 0.5, stars: 3, snow: 0.5, mist: 0.5}),
  ],
  freshstart: [
    (c) => ({kind: 'sunrise', sun: 0.15 + 0.2 * ease(c.T / 3), birds: 3}),
    (c) => ({kind: 'cairn', stones: 0, sun: 0.3, mist: 0.8}),
    (c) => ({kind: 'lake', sun: 0.3, mist: 1.1}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.3, mist: 1.4 - 0.7 * ease(c.T / 3)}),
    (c) => ({kind: 'path', trail: 0.02, sun: 0.35, birds: 3}),
    (c) => ({kind: 'beach', sun: 0.35, birds: 2}),
    (c) => ({kind: 'night', night: 0.75, charge: 0.3, stars: 0, shoot: c.at + 1.2, mist: 0.5}),
  ],
  missed: [
    (c) => ({kind: 'sunrise', sun: 0.1, night: 0.25, rain: 0.4, mist: 1.2}),
    (c) => ({kind: 'ridge', sun: 0.2, mist: 1.1, peak: 0.5, rain: 0.7}),
    (c) => ({kind: 'lake', sun: 0.2, mist: 1.2, rain: 0.5}),
    (c) => ({kind: 'fog', mist: 1.3, peak: 0.3}),
    (c) => ({kind: 'path', trail: 0.5, sun: 0.2, mist: 1.3, peak: 0.3, rain: 0.4}),
    (c) => ({kind: 'beach', sun: 0.15, rain: 0.5}),
    (c) => ({kind: 'night', night: 1, charge: 0.3, stars: 2, mist: 1.2}),
  ],
  weekkept: [
    (c) => ({kind: 'sunrise', sun: 0.55, birds: 6, flash: c.at + 0.3}),
    (c) => ({kind: 'cairn', stones: 4 + ease((c.T - 0.4) / 0.8), sun: 0.5}),
    (c) => ({kind: 'lake', sun: 0.5, mist: 0.8, ripples: 5}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.5, mist: 0.7, burst: c.at + 0.5, burstAt: 'tree'}),
    (c) => ({kind: 'path', trail: 1, beacon: ease(c.T / 1.5), sun: 0.45}),
    (c) => ({kind: 'sunset', sun: 0.2, night: 0.25, lanterns: times(c.at + 0.3, 5, 0.35)}),
    (c) => ({kind: 'night', night: 1, charge: 0.98, stars: 7, starLines: ease((c.T - 0.5) / 1), mist: 0.5}),
  ],
  comeback: [
    (c) => ({kind: 'sunrise', sun: 0.15, night: 0.25, birds: 2}),
    (c) => ({kind: 'ridge', sun: 0.35, mist: 0.9, rockIn: ease((c.T - 0.3) / 0.9)}),
    (c) => ({kind: 'lake', boatX: 0.55 + 0.06 * ease(c.T / 3), sun: 0.3, mist: 0.9}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.2, night: 0.25, mist: 0.9, fireflies: 6}),
    (c) => ({kind: 'path', trail: 0.02, sun: 0.2, night: 0.25}),
    (c) => ({kind: 'beach', steps: 0.2, sun: 0.3}),
    (c) => ({kind: 'night', night: 1, charge: 0.2, stars: 1, shoot: c.at + 1, mist: 0.5}),
  ],
  drift: [
    (c) => ({kind: 'sunrise', sun: 0.2, mist: 1.4, peak: 0.2}),
    (c) => ({kind: 'ridge', sun: 0.3, mist: 1.5, peak: 0.15}),
    (c) => ({kind: 'lake', sun: 0.25, mist: 1.5, peak: 0.2}),
    (c) => ({kind: 'fog', mist: 1.4, peak: 0.2}),
    (c) => ({kind: 'path', trail: 0.4, sun: 0.3, mist: 1.4, peak: 0.25}),
    (c) => ({kind: 'beach', sun: 0.2, rain: 0.2}),
    (c) => ({kind: 'night', night: 1, charge: 0.4, stars: 3, mist: 1.3}),
  ],
  halfway: [
    (c) => ({kind: 'sunrise', sun: 0.3, birds: 3}),
    (c) => ({kind: 'cairn', stones: 2, sun: 0.45}),
    (c) => ({kind: 'lake', boatX: 0.71, sun: 0.45, mist: 0.8}),
    (c) => ({kind: 'ridge', noRock: true, sun: 0.45, mist: 0.8}),
    (c) => ({kind: 'path', trail: 0.9, sun: 0.5, birds: 3}),
    (c) => ({kind: 'beach', tide: 0.5, sun: 0.4}),
    (c) => ({kind: 'night', night: 1, charge: 0.5, stars: 3.5, mist: 0.5}),
  ],
  automatic: [
    (c) => ({kind: 'sunrise', sun: 0.6, birds: 5}),
    (c) => ({kind: 'ridge', sun: 0.6, mist: 0.7, rubble: 7, birds: 3}),
    (c) => ({kind: 'lake', boatX: 0.9, sun: 0.55, mist: 0.6}),
    (c) => ({kind: 'ridge', noRock: true, tree: 1, sun: 0.55, mist: 0.7, birds: 4}),
    (c) => ({kind: 'path', trail: 1, beacon: 1, sun: 0.5}),
    (c) => ({kind: 'sunset', sun: 0.3, lanterns: times(c.at + 0.3, 7, 0.3)}),
    (c) => ({kind: 'night', night: 1, charge: 0.98, stars: 7, starLines: 1, mist: 0.5}),
  ],
};

export const sceneFor12 = (s: S4, d: D4, f: number, t: number, day: Day, pos: Pos): Scene3 => {
  const D = dataFor12(s, pos);
  const T = f / 30;
  const n = s === 'setup' ? d.setupDone.filter(Boolean).length : 0;
  const p = V[s][day]({d, T, t, at: t - T, pos, D, n});
  const base: Scene3 = {kind: p.kind, seed: WSEED[day], tree: grow(D.day), cracks: 0, broken: 0, rubble: Math.min(7, Math.floor(D.sessions / 3)), sun: 0.4, night: 0, mist: 0.8, rain: 0, peak: 1, birds: 0};
  if (s === 'setup') {
    base.tree = grow(0) * (0.5 + (0.5 * n) / 3);
    base.rubble = 0;
  }
  return {...base, ...p};
};
