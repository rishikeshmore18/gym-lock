/**
 * Ridge scenes, five per moment. Each version is a different painted place or light (a different
 * shore, a different hour, a different weather), so a moment that comes back every day still looks new.
 */
import type {D4, S4} from '../hero4/card4';
import {PROOF} from '../hero4/card4';
import {Kind, Scene2} from '../hero10/wash2';
import {DONE_DATA, Pos} from './copy11';

export type Icon10 = 'check' | 'moon' | 'lock' | 'alarm' | 'clock' | 'pin' | 'flame' | 'pause' | 'sun' | 'path' | 'dot';
export type Data11 = {day: number; week: number; sessions: number; icon: Icon10; live?: boolean};

export const grow = (day: number) => 0.1 + 0.9 * Math.pow(Math.min(66, day) / 66, 0.75);

export const DATA11: Record<S4, Data11> = {
  setup: {day: 0, week: 0, sessions: 0, icon: 'dot'},
  firstnight: {day: 0, week: 0, sessions: 0, icon: 'moon'},
  bedtime: {day: 44, week: 2, sessions: 16, icon: 'lock', live: true},
  wake: {day: 44, week: 2, sessions: 16, icon: 'alarm'},
  countdown: {day: 44, week: 2, sessions: 16, icon: 'clock'},
  ready: {day: 44, week: 2, sessions: 16, icon: 'sun'},
  commute: {day: 44, week: 2, sessions: 16, icon: 'pin'},
  atgym: {day: 44, week: 2, sessions: 16, icon: 'pin', live: true},
  verified: {day: 45, week: 3, sessions: 17, icon: 'check'},
  stilltime: {day: 44, week: 2, sessions: 16, icon: 'clock', live: true},
  rest: {day: 46, week: 3, sessions: 17, icon: 'dot'},
  paused: {day: 47, week: 3, sessions: 17, icon: 'pause'},
  freshstart: {day: 50, week: 0, sessions: 21, icon: 'sun'},
  missed: {day: 52, week: 1, sessions: 22, icon: 'path'},
  weekkept: {day: 56, week: 5, sessions: 26, icon: 'flame'},
  comeback: {day: 30, week: 0, sessions: 12, icon: 'sun'},
  drift: {day: 24, week: 1, sessions: 9, icon: 'path'},
  halfway: {day: 33, week: 2, sessions: 13, icon: 'flame'},
  automatic: {day: 66, week: 3, sessions: 34, icon: 'flame'},
};
export const dataFor = (s: S4, pos: Pos): Data11 => (s === 'verified' ? {...DATA11.verified, ...DONE_DATA[pos]} : DATA11[s]);

const ease = (x: number) => {
  const t = Math.min(1, Math.max(0, x));
  return 1 - Math.pow(1 - t, 3);
};
export const charge = (t: number) => Math.min(0.98, 0.18 + ((t * 0.02) % 0.8));

type P = Partial<Scene2> & {kind: Kind};
type Ctx = {d: D4; T: number; t: number; pos: Pos};

/** five versions per moment */
const V: Record<S4, ((c: Ctx) => P)[]> = {
  setup: [
    (c) => ({kind: 'ridge', sun: 0.5, mist: 0.6}),
    (c) => ({kind: 'ridge', sun: 0.15, mist: 1, night: 0.25}),
    (c) => ({kind: 'ridge', sun: 0.6, mist: 0.5, birds: 3}),
    (c) => ({kind: 'ridge', sun: 0.3, mist: 1.2, peak: 0.5}),
    (c) => ({kind: 'ridge', sun: 0.05, mist: 0.8, night: 0.5}),
  ],
  firstnight: [
    (c) => ({kind: 'night', night: 1, charge: 0.12, mist: 0.6}),
    (c) => ({kind: 'night', night: 1, charge: 0.25, mist: 0.9}),
    (c) => ({kind: 'sunset', night: 0.5, sun: -0.02}),
    (c) => ({kind: 'night', night: 0.75, charge: 0.4, mist: 0.5}),
    (c) => ({kind: 'lake', night: 0.75, sun: 0.1, mist: 0.7}),
  ],
  bedtime: [
    (c) => ({kind: 'night', night: 1, charge: charge(c.t), mist: 0.7}),
    (c) => ({kind: 'night', night: 1, charge: charge(c.t + 9), mist: 1}),
    (c) => ({kind: 'night', night: 0.75, charge: charge(c.t + 17), mist: 0.5}),
    (c) => ({kind: 'lake', night: 1, sun: 0.2, mist: 0.6}),
    (c) => ({kind: 'night', night: 1, charge: charge(c.t + 26), mist: 0.8}),
  ],
  wake: [
    (c) => ({kind: 'sunrise', sun: -0.35 + 0.6 * ease(c.T / 3.2), night: 0.5 * (1 - ease(c.T / 3.2)), birds: 4}),
    (c) => ({kind: 'lake', sun: -0.1 + 0.3 * ease(c.T / 3), night: 0.25, mist: 1}),
    (c) => ({kind: 'sunrise', sun: -0.2 + 0.4 * ease(c.T / 2.6), birds: 2}),
    (c) => ({kind: 'path', trail: 0.02, sun: 0.15, night: 0.25, birds: 3}),
    (c) => ({kind: 'beach', sun: 0.05 + 0.2 * ease(c.T / 3), birds: 3}),
  ],
  countdown: [
    (c) => ({kind: 'hourglass', sand: c.d.countdown / 7200, sun: 0.45, mist: 0.9}),
    (c) => ({kind: 'hourglass', hgBg: 'lake', sand: c.d.countdown / 7200, sun: 0.25, mist: 0.9}),
    (c) => ({kind: 'hourglass', sand: c.d.countdown / 7200, sun: 0.55, mist: 0.6, peak: 0.6}),
    (c) => ({kind: 'hourglass', hgBg: 'sunrise', sand: c.d.countdown / 7200, sun: -0.1 + 0.3 * (1 - c.d.countdown / 7200), birds: 2}),
    (c) => ({kind: 'hourglass', hgBg: 'night', sand: c.d.countdown / 7200, night: 0.75, charge: 0.9, mist: 0.6}),
  ],
  ready: [
    (c) => ({kind: 'sunrise', sun: 0.45, birds: 5}),
    (c) => ({kind: 'path', trail: 0.03, sun: 0.4, birds: 3}),
    (c) => ({kind: 'lake', sun: 0.35, mist: 0.9}),
    (c) => ({kind: 'sunrise', sun: 0.3, birds: 3}),
    (c) => ({kind: 'ridge', sun: 0.4, mist: 0.9, birds: 3}),
  ],
  commute: [
    (c) => ({kind: 'path', trail: 0.05 + ((c.T * 0.04) % 0.3), sun: 0.45, birds: 3}),
    (c) => ({kind: 'path', trail: 0.1 + ((c.T * 0.04) % 0.3), sun: 0.25, night: 0.25}),
    (c) => ({kind: 'path', trail: 0.05 + ((c.T * 0.05) % 0.35), sun: 0.5, mist: 1.1}),
    (c) => ({kind: 'path', trail: 0.15 + ((c.T * 0.03) % 0.25), sun: 0.55, birds: 4}),
    (c) => ({kind: 'path', trail: 0.08 + ((c.T * 0.04) % 0.3), sun: 0.35, mist: 1.3, peak: 0.5}),
  ],
  atgym: [0.45, 0.25, 0.55, 0.35, 0.6].map((sun, i) => (c: Ctx) => {
    const p = Math.min(1, c.d.atgym / PROOF);
    return {kind: 'ridge' as Kind, cracks: p * 5, broken: c.d.atgym >= PROOF ? ease((c.d.atgym - PROOF) / 0.8) : 0, sun, mist: [0.8, 1.1, 0.6, 1.2, 0.7][i], night: i === 1 ? 0.25 : 0};
  }),
  verified: [
    (c) => (c.pos === 'last' ? {kind: 'cairn', stones: 5, sun: 0.55, birds: 4} : c.pos === 'first' ? {kind: 'sunrise', sun: 0.35, birds: 4} : {kind: 'ridge', cracks: 5, broken: 1, sun: 0.55, mist: 0.7}),
    (c) => (c.pos === 'last' ? {kind: 'sunrise', sun: 0.55, birds: 6} : c.pos === 'first' ? {kind: 'path', trail: 0.1, sun: 0.4} : {kind: 'ridge', cracks: 5, broken: 1, sun: 0.35, mist: 1}),
    (c) => (c.pos === 'last' ? {kind: 'cairn', stones: 5, sun: 0.2, night: 0.25} : c.pos === 'first' ? {kind: 'ridge', cracks: 5, broken: 1, sun: 0.3} : {kind: 'cairn', stones: 3, sun: 0.5}),
    (c) => (c.pos === 'last' ? {kind: 'ridge', cracks: 5, broken: 1, sun: 0.6, rubble: 7} : c.pos === 'first' ? {kind: 'lake', sun: 0.35} : {kind: 'path', trail: 0.6, sun: 0.5}),
    (c) => (c.pos === 'last' ? {kind: 'cairn', stones: 5, sun: 0.45, mist: 1.1} : c.pos === 'first' ? {kind: 'sunrise', sun: 0.2, night: 0.25, birds: 2} : {kind: 'ridge', cracks: 5, broken: 1, sun: 0.45, mist: 0.6}),
  ],
  stilltime: [
    (c) => ({kind: 'sunset', sun: 0.1 + (c.d.stillLeft / (6 * 3600)) * 0.5, night: 0.25, birds: 3}),
    (c) => ({kind: 'sunset', sun: 0.05 + (c.d.stillLeft / (6 * 3600)) * 0.45, night: 0.25}),
    (c) => ({kind: 'hourglass', hgBg: 'sunset', sand: c.d.stillLeft / (6 * 3600), sun: 0.1, night: 0.25}),
    (c) => ({kind: 'sunset', sun: 0.15 + (c.d.stillLeft / (6 * 3600)) * 0.4, birds: 4}),
    (c) => ({kind: 'lake', sun: 0.05, night: 0.5, mist: 0.8}),
  ],
  rest: [
    (c) => ({kind: 'lake', sun: 0.5, mist: 0.9}),
    (c) => ({kind: 'sunset', sun: 0.35, birds: 2}),
    (c) => ({kind: 'beach', sun: 0.4, birds: 2}),
    (c) => ({kind: 'cairn', stones: 3, sun: 0.45, mist: 1}),
    (c) => ({kind: 'ridge', sun: 0.4, mist: 1.3, peak: 0.6}),
  ],
  paused: [
    (c) => ({kind: 'beach', sun: 0.25, birds: 3}),
    (c) => ({kind: 'beach', sun: 0.45, birds: 2}),
    (c) => ({kind: 'beach', sun: 0.05, night: 0.25}),
    (c) => ({kind: 'lake', sun: 0.4, mist: 1}),
    (c) => ({kind: 'beach', sun: 0.35, birds: 4}),
  ],
  freshstart: [
    (c) => ({kind: 'cairn', stones: 0, sun: 0.3, mist: 0.8}),
    (c) => ({kind: 'sunrise', sun: 0.15 + 0.2 * ease(c.T / 3), birds: 3}),
    (c) => ({kind: 'cairn', stones: 0, sun: 0.15, night: 0.25, mist: 1}),
    (c) => ({kind: 'path', trail: 0.02, sun: 0.35, birds: 3}),
    (c) => ({kind: 'cairn', stones: 0, sun: 0.5, mist: 0.6}),
  ],
  missed: [
    (c) => ({kind: 'ridge', sun: 0.2, mist: 1.1, peak: 0.5, rain: 0.7}),
    (c) => ({kind: 'ridge', sun: 0.3, mist: 1.3, peak: 0.4, rain: 0.4}),
    (c) => ({kind: 'fog', mist: 1.2, peak: 0.3}),
    (c) => ({kind: 'sunrise', sun: 0.1, night: 0.25, birds: 1}),
    (c) => ({kind: 'ridge', sun: 0.1, mist: 0.9, night: 0.25, rain: 0.5}),
  ],
  weekkept: [
    (c) => ({kind: 'cairn', stones: 4 + ease((c.T - 0.4) / 0.8), sun: 0.5}),
    (c) => ({kind: 'cairn', stones: 4 + ease((c.T - 0.4) / 0.8), sun: 0.2, night: 0.25}),
    (c) => ({kind: 'sunrise', sun: 0.55, birds: 6}),
    (c) => ({kind: 'cairn', stones: 4 + ease((c.T - 0.4) / 0.8), sun: 0.6, mist: 1.1}),
    (c) => ({kind: 'ridge', cracks: 5, broken: ease((c.T - 0.4) / 1), sun: 0.55}),
  ],
  comeback: [
    (c) => ({kind: 'sunrise', sun: 0.15, night: 0.25, birds: 2}),
    (c) => ({kind: 'path', trail: 0.02, sun: 0.3, birds: 2}),
    (c) => ({kind: 'ridge', sun: 0.35, mist: 0.9, rockIn: ease((c.T - 0.3) / 0.9)}),
    (c) => ({kind: 'sunrise', sun: 0.3, birds: 4}),
    (c) => ({kind: 'lake', sun: 0.2, night: 0.25, mist: 0.9}),
  ],
  drift: [
    (c) => ({kind: 'fog', mist: 1.4, peak: 0.2}),
    (c) => ({kind: 'fog', mist: 1.1, peak: 0.2, night: 0.25}),
    (c) => ({kind: 'ridge', sun: 0.3, mist: 1.5, peak: 0.15}),
    (c) => ({kind: 'path', trail: 0.4, sun: 0.3, mist: 1.4, peak: 0.25}),
    (c) => ({kind: 'fog', mist: 1.5, peak: 0.2}),
  ],
  halfway: [
    (c) => ({kind: 'path', trail: 0.9, sun: 0.5, birds: 3}),
    (c) => ({kind: 'path', trail: 0.9, sun: 0.3, night: 0.25}),
    (c) => ({kind: 'ridge', sun: 0.45, mist: 0.8}),
    (c) => ({kind: 'path', trail: 0.9, sun: 0.55, mist: 1.1}),
    (c) => ({kind: 'cairn', stones: 2, sun: 0.45}),
  ],
  automatic: [
    (c) => ({kind: 'ridge', sun: 0.6, mist: 0.7, rubble: 7, birds: 3}),
    (c) => ({kind: 'sunrise', sun: 0.6, birds: 5}),
    (c) => ({kind: 'ridge', sun: 0.3, mist: 1, rubble: 7, night: 0.25}),
    (c) => ({kind: 'path', trail: 1, sun: 0.55, birds: 3}),
    (c) => ({kind: 'lake', sun: 0.55, mist: 0.6, birds: 3}),
  ],
};

const STATES = Object.keys(DATA11) as S4[];
export const sceneFor11 = (s: S4, d: D4, f: number, t: number, v: number, pos: Pos): Scene2 => {
  const D = dataFor(s, pos);
  const p = V[s][v % 5]({d, T: f / 30, t, pos});
  const base: Scene2 = {kind: p.kind, seed: 3 + ((v * 7 + STATES.indexOf(s) * 13 + (s === 'verified' ? ['first', 'middle', 'last'].indexOf(pos) * 5 : 0)) % 23), tree: grow(D.day), cracks: 0, broken: 0, rubble: Math.min(7, Math.floor(D.sessions / 3)), sun: 0.4, night: 0, mist: 0.8, rain: 0, peak: 1, birds: 0};
  if (s === 'setup') base.tree = grow(0) * (0.5 + (0.5 * d.setupDone.filter(Boolean).length) / 3);
  if (s === 'setup') base.rubble = 0;
  return {...base, ...p};
};
