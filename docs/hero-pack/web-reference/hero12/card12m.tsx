/**
 * Matrix hero card: the app's hero card size (1000 × 488 design units). Copy on the left; on the right
 * a dot-matrix panel showing the day's world in moving dots. Touch the panel and the dots part under
 * the finger.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, H, Look, LOOKS, Theme, W, clamp01, eo, rgba} from '../hero2/paint';
import {CheckDot, Clock, SETUP_ITEMS, SF, SF_ROUNDED} from '../hero2/card';
import {Dots, Opts, Tgt, gridBitmap} from '../hero4/dots';
import * as G from '../hero4/glyphs';
import * as Z from './glyphs12';
import {D4, DEFS, PROOF, S4, copyFor4} from '../hero4/card4';
import type {Pos} from '../hero11/copy11';
import {cardCopy} from './copy12';
import {Day, MonthCal, MonthPos, WORLDS, tapsFor12} from './days12';
import {charge, dataFor12, ease} from './scenes12';
import {grow} from '../hero11/scenes11';

const OX = 492, OY = 26, PITCH = 12.5, COLS = 38, ROWS = 35;
const FR: G.Frame = {cols: COLS, rows: ROWS, cx: 19, cy: 17.5, u: 8};

const hm = (sec: number) => `${Math.floor(sec / 3600)}h ${String(Math.floor(sec / 60) % 60).padStart(2, '0')}m`;
const times = (at: number, n: number, gap: number) => Array.from({length: n}, (_, i) => at + i * gap);
const every = (t: number, k: number) => Math.floor(t / k) * k;

type GS = {hg: {drained: number[]}};
type Gl = {key?: string; T: Tgt[]; o?: Opts};
type C = {t: number; lt: number; at: number; d: D4; gs: GS; pos: Pos; g: number; n: number; week: number; N: number};
type Row = [(c: C) => Gl, (c: C) => Gl, (c: C) => Gl, (c: C) => Gl, (c: C) => Gl, (c: C) => Gl, (c: C) => Gl];

const cdP = (c: C) => 1 - clamp01(c.d.countdown / 7200);
const slP = (c: C) => clamp01(c.d.stillLeft / (6 * 3600));
const liveP = (c: C) => clamp01(c.d.atgym / PROOF);
const hit = (c: C) => c.d.atgym >= PROOF;
const proofAt = (c: C) => c.t - (c.d.atgym - PROOF);
const Y: Opts = {order: 'y', oy: 5, stagger: 0.35};

/** the glyph for each moment, one per day: Mon sun, Tue stone, Wed water, Thu pine, Fri summit, Sat sea, Sun stars */
const M: Record<S4, Row> = {
  setup: [
    (c) => ({T: Z.sun(FR, c.t, -0.3 + 0.3 * c.n, {rays: c.n / 3})}),
    (c) => ({key: 'lock' + c.d.setupDone.join(), T: G.lock(FR, c.t, [c.d.setupDone[0] ? 1 : 0, c.d.setupDone[1] ? 1 : 0, c.d.setupDone[2] ? 1 : 0]), o: {stagger: 0.25}}),
    (c) => ({T: Z.water(FR, c.t, {ripples: c.n})}),
    (c) => ({T: Z.pine(FR, c.t, 0.15 + 0.12 * c.n)}),
    (c) => ({T: Z.summit(FR, c.t, 0.12 * c.n, 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.15 + 0.12 * c.n})}),
    (c) => ({T: Z.stars(FR, c.t, c.n, 0)}),
  ],
  firstnight: [
    (c) => ({T: Z.sun(FR, c.t, -0.15, {rays: 0, dim: 0.5})}),
    (c) => ({T: Z.stone(FR, c.t, 0, 0, {dim: 0.5})}),
    (c) => ({T: Z.water(FR, c.t, {moon: true, dim: 0.75})}),
    (c) => ({T: Z.pine(FR, c.t, 0.15, {fireflies: 6, dim: 0.6})}),
    (c) => ({T: Z.summit(FR, c.t, 0, 0, {dim: 0.6})}),
    (c) => ({T: Z.sea(FR, c.t, {night: true, dim: 0.8})}),
    (c) => ({T: Z.stars(FR, c.t, 0, 0, {shoot: every(c.t, 6), moon: {x: FR.cx + 13, y: FR.cy - 12, phase: 0.2}})}),
  ],
  bedtime: [
    (c) => ({T: G.phoneLock(FR, c.t, c.lt)}),
    (c) => ({T: G.moon(FR, c.t)}),
    (c) => ({T: Z.water(FR, c.t, {moon: true, ripples: 1, dim: 0.8})}),
    (c) => ({T: Z.pine(FR, c.t, c.g, {fireflies: 10, dim: 0.55})}),
    (c) => ({T: Z.summit(FR, c.t, 0, 0.1, {dim: 0.6})}),
    (c) => ({T: Z.sea(FR, c.t, {night: true, dim: 0.8})}),
    (c) => ({T: Z.stars(FR, c.t, charge(c.t) * 7, 0, {moon: {x: FR.cx + 13, y: FR.cy - 12, phase: charge(c.t)}})}),
  ],
  wake: [
    (c) => ({T: Z.sun(FR, c.t, -0.3 + 0.9 * ease(c.lt / 2.5), {birds: 3})}),
    (c) => ({T: G.alarm(FR, c.t, c.lt)}),
    (c) => ({T: Z.water(FR, c.t, {boat: 0.2})}),
    (c) => ({T: Z.pine(FR, c.t, c.g, {burst: c.at + 1})}),
    (c) => ({T: Z.summit(FR, c.t, 0.02, 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: -0.1 + 0.5 * ease(c.lt / 3)})}),
    (c) => ({T: Z.stars(FR, c.t, 7, 0, {shoot: c.at + 0.8, moon: {x: FR.cx + 13, y: FR.cy - 12, phase: 0.98}})}),
  ],
  countdown: [
    (c) => ({T: Z.sun(FR, c.t, -0.3 + 0.9 * cdP(c), {rays: cdP(c)})}),
    (c) => ({T: G.hourglass(FR, c.t, 1 - c.d.countdown / 7200, c.gs.hg)}),
    (c) => ({T: Z.water(FR, c.t, {drip: true})}),
    (c) => ({T: Z.candle(FR, c.t, c.d.countdown / 7200)}),
    (c) => ({T: Z.summit(FR, c.t, 0.6 * cdP(c), 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.35, tide: cdP(c)})}),
    (c) => ({T: Z.stars(FR, c.t, 7, 0, {moon: {x: FR.cx + 10 + 4 * cdP(c), y: FR.cy - 14 + 22 * cdP(c), phase: 0.98}})}),
  ],
  ready: [
    (c) => ({T: Z.sun(FR, c.t, 0.6, {birds: 4})}),
    (c) => ({T: Z.stone(FR, c.t, 0, 0)}),
    (c) => ({T: Z.water(FR, c.t, {boat: 0.25})}),
    (c) => ({T: Z.pine(FR, c.t, c.g)}),
    (c) => ({T: Z.summit(FR, c.t, 0.05, 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.5})}),
    (c) => ({T: G.sunrise(FR, c.t, c.lt)}),
  ],
  commute: [
    (c) => ({T: Z.sun(FR, c.t, 0.45, {birds: 7})}),
    (c) => ({T: G.route(FR, c.t, Math.min(0.92, 0.55 + c.lt * 0.012))}),
    (c) => ({T: Z.water(FR, c.t, {boat: (c.lt * 0.04) % 1})}),
    (c) => ({T: Z.fog(Z.pine(FR, c.t, c.g), FR, c.t, 0.5)}),
    (c) => ({T: Z.summit(FR, c.t, 0.3 + ((c.lt * 0.02) % 0.4), 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.45})}),
    (c) => ({T: Z.stars(FR, c.t, 4, 0, {shoot: every(c.t, 4)})}),
  ],
  atgym: [
    (c) => ({T: Z.sun(FR, c.t, -0.3 + 1.2 * liveP(c), {rays: hit(c) ? 1 : liveP(c) * 0.6})}),
    (c) => ({T: Z.stone(FR, c.t, liveP(c) * 5, hit(c) ? ease((c.d.atgym - PROOF) / 0.8) : 0)}),
    (c) => ({T: Z.water(FR, c.t, {boat: liveP(c), ripples: hit(c) ? 3 : 0})}),
    (c) => ({T: Z.pine(FR, c.t, c.g * (0.8 + 0.2 * liveP(c)), {burst: hit(c) ? proofAt(c) : null})}),
    (c) => ({T: Z.summit(FR, c.t, 0.5 + 0.5 * liveP(c), hit(c) ? ease((c.d.atgym - PROOF) / 1.2) : 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.6 - 0.5 * liveP(c), lanterns: hit(c) ? times(proofAt(c), 5, 0.3) : []})}),
    (c) => ({T: Z.stars(FR, c.t, liveP(c) * 7, hit(c) ? ease((c.d.atgym - PROOF) / 1) : 0, {shoot: hit(c) ? proofAt(c) + 0.6 : null})}),
  ],
  verified: [
    (c) => ({T: Z.sun(FR, c.t, 0.85, {rays: 1, birds: 4}), o: {burst: 40, stagger: 0.1}}),
    (c) => ({T: Z.stone(FR, c.t, 5, ease((c.lt - 0.2) / 0.8))}),
    (c) => ({T: Z.water(FR, c.t, {skipN: c.N, skips: times(c.at + 0.3, c.N, 0.32), skipDone: c.at + 0.3 + c.N * 0.32})}),
    (c) => ({T: Z.pine(FR, c.t, c.g, {burst: c.at + 0.4})}),
    (c) => ({T: Z.summit(FR, c.t, 1, ease((c.lt - 0.2) / 1.2))}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.15, lanterns: times(c.at + 0.3, c.N, 0.3)})}),
    (c) => ({T: Z.stars(FR, c.t, 7, ease((c.lt - 0.3) / 1), {shoot: c.at + 0.9})}),
  ],
  stilltime: [
    (c) => ({T: Z.sun(FR, c.t, -0.2 + 0.7 * slP(c), {rays: 0.3})}),
    (c) => ({T: G.hourglass(FR, c.t, 1 - slP(c), c.gs.hg)}),
    (c) => {
      const T = G.flame(FR, c.t, {h: 16, dim: 0.35});
      for (let k = 0; k < 7; k++) {
        const p = (c.t * 0.45 + k / 7) % 1;
        T.push({x: FR.cx + Math.sin(p * 7 + k) * 2.2, y: FR.cy - 6 - p * 12, b: (1 - p) * 0.9, c: p < 0.3 ? 1 : 0});
      }
      return {T};
    },
    (c) => ({T: Z.candle(FR, c.t, slP(c))}),
    (c) => ({T: Z.summit(FR, c.t, 0.6, 0, {dim: 0.8})}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.1 + 0.5 * slP(c)})}),
    (c) => ({T: Z.stars(FR, c.t, 2, 0, {moon: {x: FR.cx + 12, y: FR.cy + 6 - 18 * (1 - slP(c)), phase: 0.6}})}),
  ],
  rest: [
    (c) => ({T: Z.sun(FR, c.t, 0.4, {dim: 0.7})}),
    (c) => ({T: G.wave(FR, c.t), o: {stagger: 0.4}}),
    (c) => ({T: Z.water(FR, c.t, {ripples: c.week})}),
    (c) => ({T: Z.fog(Z.pine(FR, c.t, c.g), FR, c.t, 0.55)}),
    (c) => ({T: Z.summit(FR, c.t, 0, 0.15)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.3})}),
    (c) => ({T: Z.stars(FR, c.t, 7, 0.6, {moon: {x: FR.cx + 13, y: FR.cy - 12, phase: 0.7}})}),
  ],
  paused: [
    (c) => ({T: [...Z.sun(FR, c.t, 0.2, {dim: 0.6}), ...Z.snow(FR, c.t)]}),
    (c) => ({T: [...Z.stone(FR, c.t, 0, 0, {snow: true}), ...Z.snow(FR, c.t)]}),
    (c) => ({T: [...Z.water(FR, c.t, {frozen: true}), ...Z.snow(FR, c.t, 14)]}),
    (c) => ({T: [...Z.pine(FR, c.t, c.g, {snow: true}), ...Z.snow(FR, c.t)]}),
    (c) => ({T: [...Z.summit(FR, c.t, 0.4, 0, {snow: true}), ...Z.snow(FR, c.t)]}),
    (c) => ({T: G.pause(FR, c.t)}),
    (c) => ({T: [...Z.stars(FR, c.t, 3, 0), ...Z.snow(FR, c.t, 16)]}),
  ],
  freshstart: [
    (c) => ({T: Z.sun(FR, c.t, -0.2 + 0.6 * ease(c.lt / 2), {birds: 3})}),
    (c) => ({T: G.weekGrid(FR, c.t, c.lt, 0, 0), o: Y}),
    (c) => ({T: Z.water(FR, c.t, {})}),
    (c) => ({T: Z.fog(Z.pine(FR, c.t, c.g), FR, c.t, 0.4 + 0.6 * ease(c.lt / 3))}),
    (c) => ({T: Z.summit(FR, c.t, 0.02, 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.35})}),
    (c) => ({T: Z.stars(FR, c.t, 0, 0, {shoot: c.at + 1.2})}),
  ],
  missed: [
    (c) => ({T: [...Z.sun(FR, c.t, 0.1, {dim: 0.6, rays: 0}), ...Z.rain(FR, c.t)]}),
    (c) => ({T: [...Z.stone(FR, c.t, 0, 0, {dim: 0.7}), ...Z.rain(FR, c.t)]}),
    (c) => ({T: [...Z.water(FR, c.t, {dim: 0.7}), ...Z.rain(FR, c.t)]}),
    (c) => ({T: Z.fog(Z.pine(FR, c.t, c.g), FR, c.t, 0.4)}),
    (c) => ({T: [...Z.summit(FR, c.t, 0.5, 0, {dim: 0.6}), ...Z.rain(FR, c.t)]}),
    (c) => ({T: G.dayRow(FR, c.t, ['done', 'done', 'done', 'done', 'missed', 'today', 'future'])}),
    (c) => ({T: Z.stars(FR, c.t, 2, 0, {dim: 0.6})}),
  ],
  weekkept: [
    (c) => ({T: Z.sun(FR, c.t, 0.85, {rays: 1, birds: 6}), o: {burst: 40, stagger: 0.1}}),
    (c) => ({T: G.weekGrid(FR, c.t, c.lt, 5, -1), o: {order: 'y', oy: 5, stagger: 0.3}}),
    (c) => ({T: Z.water(FR, c.t, {ripples: 5})}),
    (c) => ({T: Z.pine(FR, c.t, c.g, {burst: c.at + 0.5})}),
    (c) => ({T: Z.summit(FR, c.t, 1, ease(c.lt / 1.5))}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.2, lanterns: times(c.at + 0.3, 5, 0.35)})}),
    (c) => ({T: Z.stars(FR, c.t, 7, ease((c.lt - 0.5) / 1))}),
  ],
  comeback: [
    (c) => ({T: Z.sun(FR, c.t, 0.15, {birds: 2})}),
    (c) => ({T: G.flame(FR, c.t, {h: 15, ignite: Math.min(1, c.lt * 0.7)}), o: {scatter: 46, stagger: 0.5}}),
    (c) => ({T: Z.water(FR, c.t, {boat: 0.1 + 0.15 * ease(c.lt / 3)})}),
    (c) => ({T: Z.pine(FR, c.t, c.g, {fireflies: 6, dim: 0.7})}),
    (c) => ({T: Z.summit(FR, c.t, 0.02, 0, {dim: 0.85})}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.25})}),
    (c) => ({T: Z.stars(FR, c.t, 1, 0, {shoot: c.at + 1})}),
  ],
  drift: [
    (c) => ({T: Z.fog(Z.sun(FR, c.t, 0.2), FR, c.t)}),
    (c) => ({T: G.flame(FR, c.t, {h: 19, drift: 0.55})}),
    (c) => ({T: Z.fog(Z.water(FR, c.t, {}), FR, c.t)}),
    (c) => ({T: Z.fog(Z.pine(FR, c.t, c.g), FR, c.t, 0.35)}),
    (c) => ({T: Z.fog(Z.summit(FR, c.t, 0.4, 0), FR, c.t)}),
    (c) => ({T: Z.fog(Z.sea(FR, c.t, {sun: 0.2}), FR, c.t)}),
    (c) => ({T: Z.fog(Z.stars(FR, c.t, 3, 0), FR, c.t)}),
  ],
  halfway: [
    (c) => ({T: Z.sun(FR, c.t, 0.35)}),
    (c) => ({T: G.grid66(FR, c.t, c.lt, 33)}),
    (c) => ({T: Z.water(FR, c.t, {boat: 0.5})}),
    (c) => ({T: Z.pine(FR, c.t, 0.5)}),
    (c) => ({T: Z.summit(FR, c.t, 0.5, 0)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.3, tide: 0.5})}),
    (c) => ({T: Z.stars(FR, c.t, 3.5, 0, {moon: {x: FR.cx + 13, y: FR.cy - 12, phase: 0.5}})}),
  ],
  automatic: [
    (c) => ({T: Z.sun(FR, c.t, 0.9, {rays: 1, birds: 5})}),
    (c) => ({T: G.infinity(FR, c.t), o: {stagger: 0.3}}),
    (c) => ({T: Z.water(FR, c.t, {boat: 0.95})}),
    (c) => ({T: Z.pine(FR, c.t, 1, {burst: c.at + 0.6})}),
    (c) => ({T: Z.summit(FR, c.t, 1, 1)}),
    (c) => ({T: Z.sea(FR, c.t, {sun: 0.3, lanterns: times(c.at + 0.3, 7, 0.3)})}),
    (c) => ({T: Z.stars(FR, c.t, 7, 1, {moon: {x: FR.cx + 13, y: FR.cy - 12, phase: 0.98}})}),
  ],
};

let mctx: CanvasRenderingContext2D | null = null;
const measure = (txt: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `700 ${size}px ${SF_ROUNDED}`;
  return mctx!.measureText(txt).width * 0.98 + 1;
};
const lookFor = (s: S4, theme: Theme): Look => (DEFS[s].night ? LOOKS.night : LOOKS[theme]);

type Props = {state: S4; theme: Theme; f: number; t: number; d: D4; pxScale: number; day: Day; pos: Pos; mp: MonthPos; cal: MonthCal; onToggleItem?: (i: number) => void; onTouchTick?: () => void};

export const HeroCard12M: React.FC<Props> = ({state, theme, f, t, d, pxScale, day, pos, mp, cal, onToggleItem, onTouchTick}) => {
  const look = lookFor(state, theme);
  const cv = useRef<HTMLCanvasElement>(null);
  const root = useRef<HTMLDivElement>(null);
  const eng = useMemo(() => new Dots(520, COLS, ROWS), []);
  const gs = useRef<GS>({hg: {drained: []}});
  const grid = useMemo(() => {
    const c = gridBitmap(COLS, ROWS, PITCH, 1.7, look.ink, look.dark ? 0.16 : 0.1, pxScale);
    const g = c.getContext('2d')!;
    g.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    g.globalCompositeOperation = 'destination-out';
    const fade = g.createLinearGradient(0, 0, 190, 0);
    fade.addColorStop(0, 'rgba(0,0,0,1)');
    fade.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = fade;
    g.fillRect(0, 0, 190, ROWS * PITCH);
    const v = g.createLinearGradient(0, 0, 0, ROWS * PITCH);
    v.addColorStop(0, 'rgba(0,0,0,.6)');
    v.addColorStop(0.15, 'rgba(0,0,0,0)');
    v.addColorStop(0.85, 'rgba(0,0,0,0)');
    v.addColorStop(1, 'rgba(0,0,0,.6)');
    g.fillStyle = v;
    g.fillRect(0, 0, COLS * PITCH, ROWS * PITCH);
    return c;
  }, [look, pxScale]);
  const lt = f / 30;
  useLayoutEffect(() => {
    gs.current.hg = {drained: []};
  }, [state, day]);

  const D = dataFor12(state, pos);
  const pw = Math.round(W * pxScale), ph = Math.round(H * pxScale);
  useLayoutEffect(() => {
    const c = cv.current!;
    if (c.width !== pw || c.height !== ph) {
      c.width = pw;
      c.height = ph;
    }
    const ctx = c.getContext('2d')!;
    ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    ctx.clearRect(0, 0, W, H);
    ctx.drawImage(grid, OX, OY, COLS * PITCH, ROWS * PITCH);
    const n = d.setupDone.filter(Boolean).length;
    const gl = M[state][day]({t, lt, at: t - lt, d, gs: gs.current, pos, g: grow(D.day), n, week: D.week, N: tapsFor12(day, pos)});
    eng.update(`${state}:${day}:${pos}:${gl.key ?? ''}`, gl.T, t, gl.o);
    eng.draw(ctx, OX, OY, PITCH, look.ink, CORAL, 4.6, (x) => clamp01((x - OX + 40) / 120));
  });

  const lastCell = useRef<{x: number; y: number} | null>(null);
  const onMove = (e: React.PointerEvent) => {
    const r = root.current!.getBoundingClientRect();
    const sc = r.width / W;
    const x = (e.clientX - r.left) / sc, y = (e.clientY - r.top) / sc;
    const cx = (x - OX) / PITCH, cy = (y - OY) / PITCH;
    if (cx < -2) {
      eng.pointer = null;
      return;
    }
    eng.pointer = {x: cx, y: cy};
    const l = lastCell.current;
    if (!l || Math.hypot(cx - l.x, cy - l.y) > 3.2) {
      if (l) onTouchTick?.();
      lastCell.current = {x: cx, y: cy};
    }
  };
  const onLeave = () => {
    eng.pointer = null;
    lastCell.current = null;
  };

  const base0 = copyFor4(state, d);
  const W7 = cardCopy(state, day, pos, mp, cal);
  const keepHead = state === 'setup' || state === 'countdown' || state === 'atgym' || state === 'stilltime';
  const left = PROOF - d.atgym;
  const liveSub = left > 0 ? `**${String(Math.floor(left / 60)).padStart(2, '0')}:${String(Math.floor(left) % 60).padStart(2, '0')}** ${WORLDS[day].live}.` : `**${WORLDS[day].liveDone}**`;
  const c = {eyebrow: state === 'atgym' && d.atgym >= PROOF ? base0.eyebrow : W7.eyebrow, headline: keepHead ? (state === 'stilltime' ? `${hm(d.stillLeft)} left` : base0.headline) : W7.title, support: state === 'atgym' ? liveSub : W7.sub};
  const setup = state === 'setup';
  const isClock = state === 'countdown';
  const live = state === 'atgym';
  const base = 88;
  const hSize = Math.min(base, (base * (setup ? 430 : 440)) / measure(isClock ? '00:00:00' : live ? '00:00' : c.headline, base));
  const eSize = Math.min(30, (30 * 450) / Math.max(1, measure(c.eyebrow, 30) * 1.25));
  const lab = eo((f - 2) / 7);
  const sub = eo((f - 9) / 12);
  const hp = springFast(f - 4, 30, {damping: 13, stiffness: 240});
  const proofHit = live && d.atgym >= PROOF;

  return (
    <div ref={root} onPointerMove={onMove} onPointerDown={onMove} onPointerUp={onLeave} onPointerLeave={onLeave} onPointerCancel={onLeave} style={{position: 'absolute', inset: 0, background: look.card, transition: 'background .35s', touchAction: 'pan-y'}}>
      <canvas ref={cv} style={{position: 'absolute', left: 0, top: 0, width: W, height: H, display: 'block'}} />
      <div style={{position: 'absolute', left: 52, top: 0, height: H, width: 470, display: 'flex', flexDirection: 'column', justifyContent: 'center', fontFamily: SF, color: look.ink, pointerEvents: setup ? 'auto' : 'none'}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 12, fontSize: eSize, fontWeight: 700, letterSpacing: `${0.14 + (1 - lab) * 0.25}em`, color: look.ink2, opacity: lab, whiteSpace: 'nowrap'}}>
          {(live || state === 'stilltime') && <span style={{width: 14, height: 14, borderRadius: 7, background: CORAL, opacity: proofHit ? 1 : 0.5 + 0.5 * Math.sin(t * 9), flex: 'none'}} />}
          {c.eyebrow}
        </div>
        <div
          style={{
            marginTop: 6,
            fontFamily: SF_ROUNDED,
            fontWeight: 700,
            fontSize: hSize,
            lineHeight: 1.02,
            letterSpacing: '-0.02em',
            whiteSpace: 'nowrap',
            fontVariantNumeric: 'tabular-nums',
            opacity: clamp01((f - 4) / 3),
            transform: `translateY(${((1 - hp) * 46).toFixed(2)}px) scale(${(1.08 - 0.08 * hp).toFixed(4)})`,
            transformOrigin: '0% 100%',
          }}
        >
          {isClock ? <Clock remaining={d.countdown} mode="bold" /> : c.headline}
        </div>
        {!setup && (
          <div style={{marginTop: 10, fontSize: 35, fontWeight: 500, color: look.ink2, lineHeight: 1.24, maxWidth: 430, opacity: sub, transform: `translateY(${((1 - sub) * 10).toFixed(1)}px)`}}>
            {c.support.split('**').map((part, i) => (
              <span key={i} style={{fontWeight: i % 2 ? 700 : 500, color: i % 2 ? look.ink : look.ink2}}>
                {part}
              </span>
            ))}
          </div>
        )}
        {live && (
          <div style={{marginTop: 16, width: 380, height: 10, borderRadius: 5, background: rgba(look.ink, look.dark ? 0.14 : 0.08), overflow: 'hidden', opacity: sub}}>
            <div style={{width: `${(clamp01(d.atgym / PROOF) * 100).toFixed(2)}%`, height: '100%', borderRadius: 5, background: proofHit ? CORAL : look.ink}} />
          </div>
        )}
        {setup && (
          <div style={{marginTop: 16, display: 'flex', flexDirection: 'column', gap: 10}}>
            {SETUP_ITEMS.map((label, i) => {
              const on = d.setupDone[i];
              const row = springFast(f - 9 - i * 3, 30, {damping: 13, stiffness: 300});
              return (
                <button
                  key={i}
                  onClick={(e) => {
                    e.stopPropagation();
                    onToggleItem?.(i);
                  }}
                  style={{all: 'unset', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 16, fontSize: 34, fontWeight: on ? 600 : 500, color: on ? look.ink : look.ink2, opacity: clamp01(row * 2), transform: `translateY(${((1 - row) * 18).toFixed(1)}px)`, WebkitTapHighlightColor: 'transparent'}}
                >
                  <CheckDot on={on} look={look} mode="bold" />
                  {label}
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
