/**
 * Matrix hero card: same size as the app's hero card (1000 × 488 design units). Copy on the left in
 * the app's type; on the right a dot-matrix panel whose lit dots fly from glyph to glyph as the
 * user's day moves on. Touch the panel and the dots part under the finger.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, H, Look, LOOKS, Theme, W, clamp01, eo, rgba} from '../hero2/paint';
import {CheckDot, Clock, SETUP_ITEMS, SF, SF_ROUNDED, clock} from '../hero2/card';
import {Dots, Opts, Tgt, gridBitmap} from './dots';
import * as G from './glyphs';

export type S4 =
  | 'setup' | 'firstnight' | 'bedtime' | 'wake' | 'countdown' | 'ready' | 'commute' | 'atgym' | 'verified' | 'stilltime'
  | 'rest' | 'paused' | 'freshstart' | 'missed' | 'weekkept' | 'comeback' | 'drift' | 'halfway' | 'automatic';

export const CARD_H = H; // unchanged: the app's hero card
export const PROOF = 20 * 60;
export type D4 = {setupDone: boolean[]; countdown: number; atgym: number; stillLeft: number};

// panel geometry (design units)
const OX = 492, OY = 26, PITCH = 12.5, COLS = 38, ROWS = 35;
const FR: G.Frame = {cols: COLS, rows: ROWS, cx: 19, cy: 17.5, u: 8};

type Def = {night?: boolean; pill: number; week: number};
export const DEFS: Record<S4, Def> = {
  setup: {pill: 0, week: 0},
  firstnight: {night: true, pill: 0, week: 0},
  bedtime: {night: true, pill: 3, week: 1},
  wake: {pill: 3, week: 1},
  countdown: {pill: 3, week: 1},
  ready: {pill: 3, week: 1},
  commute: {pill: 3, week: 1},
  atgym: {pill: 3, week: 1},
  verified: {pill: 4, week: 2},
  stilltime: {pill: 3, week: 1},
  rest: {pill: 4, week: 2},
  paused: {pill: 4, week: 2},
  freshstart: {pill: 5, week: 0},
  missed: {pill: 0, week: 2},
  weekkept: {pill: 9, week: 5},
  comeback: {pill: 0, week: 0},
  drift: {pill: 16, week: 2},
  halfway: {pill: 21, week: 3},
  automatic: {pill: 44, week: 4},
};

const mmss = (sec: number) => {
  const t = Math.max(0, Math.floor(sec));
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};
const hm = (sec: number) => {
  const t = Math.max(0, Math.floor(sec));
  return `${Math.floor(t / 3600)}h ${String(Math.floor((t % 3600) / 60)).padStart(2, '0')}m`;
};

export const copyFor4 = (s: S4, d: D4) => {
  const n = d.setupDone.filter(Boolean).length;
  const C = (eyebrow: string, headline: string, support: string) => ({eyebrow, headline, support});
  switch (s) {
    case 'setup': return C('FINISH YOUR SYSTEM', `${n} of 3 ready`, '');
    case 'firstnight': return C('DAY ONE TOMORROW', 'Sleep first.', 'Tomorrow, 07:00, Iron Works. A plan with a time and place gets kept.');
    case 'bedtime': return C('LOCKED FOR SLEEP', 'Lights out.', 'Apps stay locked until morning. Gym at 07:00.');
    case 'wake': return C('ALARM · 06:30', 'Feet down.', 'Apps stay locked until you check in at the gym.');
    case 'countdown': return C('GYM TIME IN', clock(d.countdown), "Same time, same place. That's what makes it stick.");
    case 'ready': return C('ALARM BEATEN', 'Get ready', 'Shoes on. Out the door by 06:45.');
    case 'commute': return C('ON YOUR WAY', '6 min out', "You're out the door. That was the hard part.");
    case 'atgym': {
      const left = PROOF - d.atgym;
      return C(left > 0 ? 'AT THE GYM' : 'PROOF EARNED', mmss(Math.min(d.atgym, 3599)), left > 0 ? `${mmss(left)} to go. Twenty minutes makes it count.` : 'Twenty minutes. It counts.');
    }
    case 'verified': return C('WORKOUT VERIFIED', 'Done.', 'That post-workout lift can last up to 12 hours.');
    case 'stilltime': return C('STILL TIME TODAY', hm(d.stillLeft), 'Today is a planned day. Twenty minutes keeps the flame lit.');
    case 'rest': return C('REST DAY', 'Recover.', 'Rest is part of the plan. Your streak is safe.');
    case 'paused': return C('STREAK PAUSED', 'Rest up.', "Sick or travelling? Paused days don't count against you.");
    case 'freshstart': return C('NEW WEEK', 'Clean slate.', 'Gym visits jump at the start of a week. Ride that.');
    case 'missed': return C('MISSED YESTERDAY', 'Never twice.', "One missed day doesn't undo a habit. Today keeps it that way.");
    case 'weekkept': return C('WEEK KEPT', '5 of 5.', 'Every session you planned, done. Week streak: 2.');
    case 'comeback': return C('WELCOME BACK', 'Start again.', 'Coming back after a miss earns a bonus today. Just 20 minutes.');
    case 'drift': return C('WEEK 4', 'Drift zone.', 'New members plan 3 a week. By week 6 the average is 1. Not you.');
    case 'halfway': return C('HABIT FORMING', 'Day 33.', "Habits took 66 days on average to feel automatic. You're halfway.");
    case 'automatic': return C('DAY 66', 'Automatic.', '66 days is the median for a habit to stick. You made it.');
  }
};

/** the glyph for each state: targets + how the dots should arrive */
type GlyphState = {hg: {drained: number[]}};
const glyphFor = (s: S4, t: number, lt: number, d: D4, gs: GlyphState): {key: string; T: Tgt[]; o?: Opts} => {
  switch (s) {
    case 'setup':
      return {key: s, T: G.lock(FR, t, [d.setupDone[0] ? 1 : 0, d.setupDone[1] ? 1 : 0, d.setupDone[2] ? 1 : 0]), o: {stagger: 0.25}};
    case 'firstnight':
      return {key: s, T: G.moon(FR, t)};
    case 'bedtime':
      return {key: s, T: G.phoneLock(FR, t, lt)};
    case 'wake':
      return {key: s, T: G.alarm(FR, t, lt)};
    case 'countdown':
      return {key: s, T: G.hourglass(FR, t, 1 - d.countdown / (2 * 3600), gs.hg)};
    case 'ready':
      return {key: s, T: G.sunrise(FR, t, lt)};
    case 'commute':
      return {key: s, T: G.route(FR, t, Math.min(0.92, 0.55 + lt * 0.012))};
    case 'atgym':
      return {key: s, T: G.ring20(FR, t, d.atgym)};
    case 'verified':
      return {key: s, T: G.flame(FR, t, {h: 19}), o: {burst: 40, stagger: 0.1}};
    case 'stilltime': {
      const T = G.flame(FR, t, {h: 16, dim: 0.35});
      for (let k = 0; k < 7; k++) {
        const p = (t * 0.45 + k / 7) % 1;
        T.push({x: FR.cx + Math.sin(p * 7 + k) * 2.2, y: FR.cy - 6 - p * 12, b: (1 - p) * 0.9, c: p < 0.3 ? 1 : 0});
      }
      return {key: s, T};
    }
    case 'rest':
      return {key: s, T: G.wave(FR, t), o: {stagger: 0.4}};
    case 'paused':
      return {key: s, T: G.pause(FR, t)};
    case 'freshstart':
      return {key: s, T: G.weekGrid(FR, t, lt, 0, 0), o: {order: 'y', oy: 5, stagger: 0.35}};
    case 'missed':
      return {key: s, T: G.dayRow(FR, t, ['done', 'done', 'missed', 'today', 'future', 'future', 'future'])};
    case 'weekkept':
      return {key: s, T: G.weekGrid(FR, t, lt, 5, -1), o: {order: 'y', oy: 5, stagger: 0.3}};
    case 'comeback':
      return {key: s, T: G.flame(FR, t, {h: 15, ignite: Math.min(1, lt * 0.7)}), o: {scatter: 46, stagger: 0.5}};
    case 'drift':
      return {key: s, T: G.flame(FR, t, {h: 19, drift: 0.55})};
    case 'halfway':
      return {key: s, T: G.grid66(FR, t, lt, 33)};
    case 'automatic':
      return {key: s, T: G.infinity(FR, t), o: {stagger: 0.3}};
  }
};

let mctx: CanvasRenderingContext2D | null = null;
const measure = (txt: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `700 ${size}px ${SF_ROUNDED}`;
  return mctx!.measureText(txt).width * 0.98 + 1;
};

export const lookFor4 = (s: S4, theme: Theme): Look => (DEFS[s].night ? LOOKS.night : LOOKS[theme]);

type Props = {state: S4; theme: Theme; f: number; t: number; d: D4; pxScale: number; onToggleItem?: (i: number) => void; onTouchTick?: () => void};

export const HeroCard4: React.FC<Props> = ({state, theme, f, t, d, pxScale, onToggleItem, onTouchTick}) => {
  const look = lookFor4(state, theme);
  const cv = useRef<HTMLCanvasElement>(null);
  const root = useRef<HTMLDivElement>(null);
  const eng = useMemo(() => new Dots(520, COLS, ROWS), []);
  const gs = useRef<GlyphState>({hg: {drained: []}});
  const grid = useMemo(() => {
    const c = gridBitmap(COLS, ROWS, PITCH, 1.7, look.ink, look.dark ? 0.16 : 0.1, pxScale);
    const g = c.getContext('2d')!;
    // fade the unlit grid out toward the copy
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
    if (state !== 'countdown') gs.current.hg = {drained: []};
  }, [state]);

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
    const gl = glyphFor(state, t, lt, d, gs.current);
    eng.update(gl.key, gl.T, t, gl.o);
    eng.draw(ctx, OX, OY, PITCH, look.ink, CORAL, 4.6, (x) => clamp01((x - OX + 40) / 120));
  });

  // touch: the dots part under the finger, with a tick every few cells
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

  const c = copyFor4(state, d);
  const setup = state === 'setup';
  const isClock = state === 'countdown';
  const live = state === 'atgym';
  const base = 88;
  const hSize = Math.min(base, (base * (setup ? 430 : 440)) / measure(isClock ? '00:00:00' : live ? '00:00' : c.headline, base));
  const lab = eo((f - 2) / 7);
  const sub = eo((f - 9) / 12);
  const hp = springFast(f - 4, 30, {damping: 13, stiffness: 240});
  const proofHit = live && d.atgym >= PROOF;

  return (
    <div ref={root} onPointerMove={onMove} onPointerDown={onMove} onPointerUp={onLeave} onPointerLeave={onLeave} onPointerCancel={onLeave} style={{position: 'absolute', inset: 0, background: look.card, transition: 'background .35s', touchAction: 'pan-y'}}>
      <canvas ref={cv} style={{position: 'absolute', left: 0, top: 0, width: W, height: H, display: 'block'}} />
      <div style={{position: 'absolute', left: 52, top: 0, height: H, width: 470, display: 'flex', flexDirection: 'column', justifyContent: 'center', fontFamily: SF, color: look.ink, pointerEvents: setup ? 'auto' : 'none'}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 12, fontSize: 30, fontWeight: 700, letterSpacing: `${0.14 + (1 - lab) * 0.25}em`, color: look.ink2, opacity: lab, whiteSpace: 'nowrap'}}>
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
            {c.support}
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

type HK = 'light' | 'medium' | 'heavy' | 'success';
export const stateHaptics4 = (s: S4): {f: number; kind: HK}[] => {
  const out: {f: number; kind: HK}[] = [{f: 2, kind: 'light'}, {f: 6, kind: 'medium'}];
  if (s === 'verified' || s === 'weekkept' || s === 'automatic') out.push({f: 14, kind: 'success'}, {f: 18, kind: 'heavy'});
  if (s === 'weekkept') for (let i = 0; i < 5; i++) out.push({f: 10 + i * 5, kind: 'heavy'});
  if (s === 'wake') for (let i = 0; i < 6; i++) out.push({f: 4 + i * 4, kind: i % 2 ? 'medium' : 'heavy'});
  if (s === 'comeback') out.push({f: 16, kind: 'medium'}, {f: 26, kind: 'heavy'});
  if (s === 'missed' || s === 'drift') out.push({f: 10, kind: 'heavy'});
  if (s === 'halfway') for (let i = 0; i < 8; i++) out.push({f: 4 + i * 3, kind: 'light'});
  return out;
};
