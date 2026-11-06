/**
 * Ridge: a different painted place for each moment of the GymLock lifecycle, one watercolour language.
 *   night      the moon fills like a battery while you sleep
 *   sunrise    the alarm: a sun climbing out of a sea of clouds
 *   hourglass  the countdown, sand running out
 *   path       on your way, and later, how far up the mountain you are
 *   ridge      the session's rock: it cracks while you train and breaks when you're verified
 *   sunset     time left today, the sun going down
 *   lake       a rest day, still water
 *   beach      a frozen streak: two palms, an empty hammock
 *   cairn      the week, stacked one stone per session
 *   fog        the drift zone
 * The seed changes with the day, so the mountains, clouds and shores are never quite the same twice.
 */
import type {D4, S4} from '../hero4/card4';
import {PROOF} from '../hero4/card4';
import {Kind, Scene2} from './wash2';

export type Icon10 = 'check' | 'moon' | 'lock' | 'alarm' | 'clock' | 'pin' | 'flame' | 'pause' | 'sun' | 'path' | 'dot';
export type R10 = {kind: Kind; day: number; week: number; sessions: number; eyebrow: string; icon: Icon10; title: string; sub: string; note?: string; live?: boolean};

export const grow = (day: number) => 0.1 + 0.9 * Math.pow(Math.min(66, day) / 66, 0.75);

export const COPY10: Record<S4, R10> = {
  setup: {kind: 'ridge', day: 0, week: 0, sessions: 0, eyebrow: 'FINISH YOUR SYSTEM', icon: 'dot', title: '#SETUP', sub: '', note: 'Plant it.'},
  firstnight: {kind: 'night', day: 0, week: 0, sessions: 0, eyebrow: 'DAY ONE TOMORROW', icon: 'moon', title: 'Charge up.', sub: 'Tomorrow, **07:00** at **Iron Works.** Sleep first.'},
  bedtime: {kind: 'night', day: 44, week: 2, sessions: 16, eyebrow: 'LOCKED FOR SLEEP', icon: 'lock', title: 'Recharging.', sub: 'Apps **locked** until 06:30. Muscle **rebuilds** while you sleep.', live: true},
  wake: {kind: 'sunrise', day: 44, week: 2, sessions: 16, eyebrow: 'ALARM · 06:30', icon: 'alarm', title: 'Rise.', sub: 'Fully charged. Apps unlock when you **check in.**'},
  countdown: {kind: 'hourglass', day: 44, week: 2, sessions: 16, eyebrow: 'GYM TIME IN', icon: 'clock', title: '#CLOCK', sub: 'Same time, same place. **That’s how it sticks.**'},
  ready: {kind: 'sunrise', day: 44, week: 2, sessions: 16, eyebrow: 'ALARM BEATEN', icon: 'sun', title: 'Get ready.', sub: 'Shoes on. **Out by 06:45.**', note: 'Go.'},
  commute: {kind: 'path', day: 44, week: 2, sessions: 16, eyebrow: 'ON YOUR WAY', icon: 'pin', title: '6 min out.', sub: 'The hard part **is behind you.**'},
  atgym: {kind: 'ridge', day: 44, week: 2, sessions: 16, eyebrow: 'AT THE GYM', icon: 'pin', title: '#LIVE', sub: '', live: true},
  verified: {kind: 'ridge', day: 45, week: 3, sessions: 17, eyebrow: 'WORKOUT VERIFIED', icon: 'check', title: 'Done.', sub: '**52:14** at Iron Works. Session **17.**', note: 'Broken.'},
  stilltime: {kind: 'sunset', day: 44, week: 2, sessions: 16, eyebrow: 'STILL TIME TODAY', icon: 'clock', title: '4h 11m left.', sub: '**20 minutes** before sundown keeps the week.', live: true},
  rest: {kind: 'lake', day: 46, week: 3, sessions: 17, eyebrow: 'REST DAY', icon: 'dot', title: 'Recover.', sub: 'Muscle is built **between** sessions.', note: 'Rest today. Stronger tomorrow.'},
  paused: {kind: 'beach', day: 47, week: 3, sessions: 17, eyebrow: 'STREAK FROZEN', icon: 'pause', title: 'Off the clock.', sub: 'Sick or travelling? Frozen days **don’t count against you.**', note: 'Frozen, not lost.'},
  freshstart: {kind: 'cairn', day: 50, week: 0, sessions: 21, eyebrow: 'NEW WEEK', icon: 'sun', title: 'New week.', sub: 'Last week: **4 sessions, 3h 12m.** Gym visits jump **33%** at the start of a week.', note: 'Stack it again.'},
  missed: {kind: 'ridge', day: 52, week: 1, sessions: 22, eyebrow: 'MISSED YESTERDAY', icon: 'path', title: 'Never twice.', sub: 'One miss doesn’t undo a habit. **Today keeps it.**'},
  weekkept: {kind: 'cairn', day: 56, week: 5, sessions: 26, eyebrow: 'WEEK KEPT', icon: 'flame', title: '5 of 5.', sub: 'Every planned session, **stacked.**', note: 'Week built.'},
  comeback: {kind: 'sunrise', day: 30, week: 0, sessions: 12, eyebrow: 'WELCOME BACK', icon: 'sun', title: 'Start again.', sub: 'Coming back **earns a bonus** today.', note: 'Back at it.'},
  drift: {kind: 'fog', day: 24, week: 1, sessions: 9, eyebrow: 'WEEK 4', icon: 'path', title: 'Drift zone.', sub: 'Most slip to **once a week** by week 6. **Not you.**', note: 'Keep going.'},
  halfway: {kind: 'path', day: 33, week: 2, sessions: 13, eyebrow: 'HABIT FORMING', icon: 'flame', title: 'Day 33.', sub: 'Halfway up. **13 rocks broken.**', note: 'Halfway up.'},
  automatic: {kind: 'ridge', day: 66, week: 3, sessions: 34, eyebrow: 'DAY 66', icon: 'flame', title: 'Automatic.', sub: '66 days is the median. **It’s yours now.**', note: 'Rooted.'},
};

const ease = (x: number) => {
  const t = Math.min(1, Math.max(0, x));
  return 1 - Math.pow(1 - t, 3);
};
const STATES: S4[] = Object.keys(COPY10) as S4[];
/** a seed that shifts with the day, so each visit paints a slightly different place */
export const seedFor = (s: S4, day: number) => 3 + ((day * 7 + STATES.indexOf(s) * 13) % 23);

export const charge = (t: number) => Math.min(0.98, 0.18 + ((t * 0.02) % 0.8));

export const sceneFor = (s: S4, d: D4, f: number, t = 0): Scene2 => {
  const c = COPY10[s];
  const T = f / 30;
  const base: Scene2 = {kind: c.kind, seed: seedFor(s, c.day), tree: grow(c.day), cracks: 0, broken: 0, rubble: Math.min(7, Math.floor(c.sessions / 3)), sun: 0.4, night: 0, mist: 0.8, rain: 0, peak: 1, birds: 0};
  switch (s) {
    case 'setup':
      return {...base, tree: grow(0) * (0.5 + (0.5 * d.setupDone.filter(Boolean).length) / 3), sun: 0.5, mist: 0.6, rubble: 0};
    case 'firstnight':
      return {...base, night: 1, charge: 0.12, mist: 0.6};
    case 'bedtime':
      return {...base, night: 1, charge: charge(t), mist: 0.7};
    case 'wake': {
      const p = ease(T / 3.2);
      return {...base, sun: -0.35 + 0.6 * p, night: 0.5 * (1 - p), birds: 4};
    }
    case 'countdown':
      return {...base, sand: d.countdown / 7200, sun: 0.45, mist: 0.9};
    case 'ready':
      return {...base, sun: 0.45, birds: 5};
    case 'commute':
      return {...base, trail: 0.05 + ((T * 0.04) % 0.3), sun: 0.45, birds: 3};
    case 'atgym': {
      const p = Math.min(1, d.atgym / PROOF);
      return {...base, cracks: p * 5, broken: d.atgym >= PROOF ? ease((d.atgym - PROOF) / 0.8) : 0, sun: 0.45};
    }
    case 'verified':
      return {...base, cracks: 5, broken: 1, sun: 0.55, mist: 0.7};
    case 'stilltime':
      return {...base, sun: 0.1 + (d.stillLeft / (6 * 3600)) * 0.5, night: 0.25, birds: 3};
    case 'rest':
      return {...base, sun: 0.5, mist: 0.9};
    case 'paused':
      return {...base, sun: 0.25, birds: 3};
    case 'freshstart':
      return {...base, stones: 0, sun: 0.3, mist: 0.8};
    case 'missed':
      return {...base, sun: 0.2, mist: 1.1, peak: 0.5, rain: 0.7};
    case 'weekkept':
      return {...base, stones: 4 + ease((T - 0.4) / 0.8), sun: 0.5};
    case 'comeback':
      return {...base, sun: 0.15, night: 0.25, birds: 2};
    case 'drift':
      return {...base, mist: 1.4, peak: 0.2};
    case 'halfway':
      return {...base, trail: 0.9, sun: 0.5, birds: 3};
    case 'automatic':
      return {...base, sun: 0.6, mist: 0.7, rubble: 7, birds: 3};
  }
};
