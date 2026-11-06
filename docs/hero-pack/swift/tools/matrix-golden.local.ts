// Golden values for MatrixParity (MatrixScene.swift / MatrixStoryView.swift), computed from the TS sources.
// Paths point at the prototype (gymlock-intro/web). From the gymlock-intro folder:
//   npx esbuild <this file> --bundle --platform=node --format=cjs --jsx=automatic --outfile=/tmp/golden.js && node /tmp/golden.js

import {MDots} from '../../web-reference/hero13/mdots';
import {G, rnd, ringBeat, lastRing, ringIndex, iconPts, back, spr, eio, pulse} from '../../web-reference/hero13/mxlib';
import {SCENES as V} from '../../web-reference/hero13/mx/verified';
import {SCENES as WK} from '../../web-reference/hero13/mx/wake';
import {SCENES as CD} from '../../web-reference/hero13/mx/countdown';
import {mxStory} from '../../web-reference/hero13/mxstory';
const hash = (i: number, k: number) => {
  let h = (i * 374761393 + k * 668265263) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};
const f = (x: number) => +x.toPrecision(12);
console.log('HASH', [[0,1],[1,1],[5,2],[719,8],[1399,10],[-3,7]].map(([i,k]) => f(hash(i,k))));
console.log('RND', [0,1,123,-7,2.5,1e6].map((i) => f(rnd(i))));
console.log('EASE', f(back(0.5)), f(spr(0.3)), f(eio(0.3)), f(pulse(3.1, 2.5, 0.13, 0.35)));
console.log('RING', [0.3,0.4,2.7,2.86,5.4].map((T) => [f(ringBeat(T)), lastRing(T), ringIndex(T)]));
const sum = (o: any[]) => f(o.reduce((a, q) => a + q.x * 1.3 + q.y * 0.7 + q.b * 5 + (q.c ? 11 : 0) + (q.id % 9973) * 0.001, 0));
const mc = (T: number, t = 100 + T, countdown = 3725.3) => ({t, T, d: {setupDone: [true, true, true], countdown, atgym: 0, stillLeft: 0}, day: 2, pos: 'middle', N: 5, D: {day: 23, week: 3, sessions: 14}});
for (const [name, sc, Ts] of [['verifiedWed', V[2], [0.5, 1.0, 2.0]], ['wakeMon', WK[0], [0.4, 3.0, 6.0]], ['countdownWed', CD[2], [0.3, 2.0]]] as const) {
  for (const T of Ts) {
    const g = new G();
    const o = (sc as any).draw(g, mc(T));
    const out = g.out();
    console.log('SCENE', name, 'T', T, 'n', out.length, 'sum', sum(out), 'first', JSON.stringify(out.slice(0, 2).map((q: any) => ({...q, x: f(q.x), y: f(q.y), b: f(q.b)}))), 'out', JSON.stringify(o));
  }
}
// engine run: battery from t=0 at 60 fps for 1.5 s
const e = new MDots(720, 38, 35);
console.log('INIT', [0,1,2].map((i) => [e.x[i], e.y[i]]));
for (let k = 0; k <= 90; k++) {
  const t = k / 60, g = new G();
  const o: any = V[2].draw(g, mc(t, t)) || {};
  e.update(`verified:2:middle:${o.ph ?? 0}`, g.out(), t, o.o ?? {stagger: 0.25});
}
let bs = 0, xs = 0; for (let i = 0; i < 720; i++) { bs += e.b[i]; xs += e.x[i] * (i % 7 + 1); }
console.log('ENGINE60', f(bs), f(xs), [0,1,2].map((i) => [e.x[i], e.y[i], e.b[i]]));
// story: finWed climax with 3 taps
const W = 1179/3, H = 2556/3; // unused
const cols = 52, rows = Math.ceil(2336 / 21), cx = Math.floor(1080 / 2 / 21) + 0.5, cy = Math.floor(((2336 - 1920) / 2 + 900) / 21) + 0.5;
const s: any = {t: 50, lt: 3, cx, cy, cols, rows, N: 5, taps: 3, tapTimes: [48, 48.6, 49.4], tapAt: 49.4, sealT: null, since: -1, D: {day: 23, sessions: 14}, day: 2, pos: 'middle', PW: {done: 3, today: 1}};
const r = mxStory('climax', false, s)!;
console.log('STORY rows', rows, 'cx', cx, 'cy', cy, 'n', r.g.out().length, 'sum', sum(r.g.out()), JSON.stringify({ph: r.ph, o: r.o, flash: r.flash, glow: r.glow}));
const s2 = {...s, taps: 5, tapTimes: [48, 48.6, 49.4, 49.8, 50.2], tapAt: 50.2, sealT: 50.2, t: 50.9, since: 0.7};
const r2 = mxStory('climax', false, s2)!;
console.log('STORY sealed n', r2.g.out().length, 'sum', sum(r2.g.out()));
const s3 = {...s2, t: 52.6, since: 2.4};
const r3 = mxStory('climax', true, s3)!;
console.log('STORY count n', r3.g.out().length, 'sum', sum(r3.g.out()), JSON.stringify(r3.o));
const r4 = mxStory('verified', false, {...s, lt: 1.0, t: 10})!;
console.log('STORY verifiedWed n', r4.g.out().length, 'sum', sum(r4.g.out()));
