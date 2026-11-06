/**
 * Rush hero card: painted scene + copy (same shell as the app's hero card) and, under it, the
 * habit band: where the user is on the road to automatic (Lally et al. 2010, median 66 days).
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, H, LOOKS, Look, Mode, Theme, W, clamp01, eo, rgba} from '../hero2/paint';
import {DemoData, Scene, StateId, buildScene} from '../hero2/scenes';
import {CheckDot, Clock, SETUP_ITEMS, SF, SF_ROUNDED, clock} from '../hero2/card';
import {TrailData, trailScene} from './trail';

export type S3 = 'setup' | 'firstnight' | 'countdown' | 'ready' | 'atgym' | 'verified' | 'rest' | 'freshstart' | 'missed' | 'weekkept' | 'drift' | 'comeback' | 'halfway';

export const BAND_H = 214;
export const CARD_H = H + BAND_H;
export const PROOF = 20 * 60;
export const HABIT_DAYS = 66;

export type D3 = {setupDone: boolean[]; countdown: number; atgym: number; weekGoal: number};

type Def = {
  base: StateId | 'trail';
  night?: boolean;
  day: number; // habit day shown in the band
  from?: number; // band dot starts here
  pill: number;
  week: number; // momentum: sessions this week
  week2?: Partial<DemoData>;
  trail?: (d: D3) => TrailData;
  missed?: number[];
  band?: [number, number];
  caption: string;
};

export const DEFS: Record<S3, Def> = {
  setup: {base: 'setup', day: 0, pill: 0, week: 0, caption: 'Begins with your first session'},
  firstnight: {base: 'night', night: true, day: 0, pill: 0, week: 0, caption: 'Day 1 is tomorrow morning'},
  countdown: {base: 'countdown', day: 0, pill: 0, week: 0, caption: 'Today becomes day 1'},
  ready: {base: 'ready', day: 0, pill: 0, week: 0, caption: 'Today becomes day 1'},
  atgym: {base: 'trail', day: 0, pill: 0, week: 0, trail: (d) => ({p: clamp01(d.atgym / PROOF), fog: 0, live: true}), caption: 'Day 1 locks in at 20:00'},
  verified: {base: 'verified', day: 1, from: 0, pill: 1, week: 1, caption: 'Day 1 of about 66'},
  rest: {base: 'rest', day: 2, from: 1, pill: 1, week: 1, caption: 'Planned rest keeps the streak'},
  freshstart: {base: 'week', day: 7, from: 6, pill: 4, week: 0, week2: {weekDone: 0}, caption: 'Week 2 starts today'},
  missed: {base: 'setup', day: 10, from: 9, pill: 0, week: 2, missed: [7], week2: {setupDone: [true, true, false]}, caption: 'One gap. The curve keeps rising.'},
  weekkept: {base: 'week', day: 13, from: 12, pill: 9, week: 5, week2: {weekDone: 5}, caption: 'Every planned session, done'},
  drift: {base: 'trail', day: 24, from: 23, pill: 16, week: 2, band: [14, 42], trail: () => ({p: 0.42, fog: 1, band: [0.22, 0.62]}), caption: 'Where most new members stall'},
  comeback: {base: 'ready', day: 30, from: 30, pill: 0, week: 0, missed: [26, 27], caption: 'Pick it up where you left it'},
  halfway: {base: 'trail', day: 33, from: 32, pill: 21, week: 3, trail: () => ({p: 0.5, fog: 0}), caption: 'Halfway to automatic'},
};

export const lookFor3 = (s: S3, theme: Theme): Look => (DEFS[s].night ? LOOKS.night : LOOKS[theme]);

/** scene data for the hero2 painters */
export const demoData = (s: S3, d: D3): DemoData => {
  const base: DemoData = {setupDone: d.setupDone, bedtime: '23:00', wake: '06:30', nextDay: 'Friday', nextTime: '07:00', weekDone: DEFS[s].week, weekGoal: d.weekGoal, streakWeeks: 1, lockIn: 3600, countdown: {remaining: d.countdown, window: 2 * 3600}};
  return {...base, ...(DEFS[s].week2 ?? {})};
};

const mmss = (sec: number) => {
  const t = Math.max(0, Math.floor(sec));
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};

export const copyFor3 = (s: S3, d: D3) => {
  const n = d.setupDone.filter(Boolean).length;
  switch (s) {
    case 'setup':
      return {eyebrow: 'FINISH YOUR SYSTEM', headline: [`${n} of ${d.setupDone.length} ready`], support: ''};
    case 'firstnight':
      return {eyebrow: 'DAY ONE TOMORROW', headline: ['Sleep first.'], support: 'Lay out your gym clothes tonight. Apps lock at 23:00.'};
    case 'countdown':
      return {eyebrow: 'GYM TIME IN', headline: [clock(d.countdown)], support: "Same time, same place. That's what makes it stick."};
    case 'ready':
      return {eyebrow: 'ALARM BEATEN', headline: ['Get ready'], support: 'Shoes on. Out the door by 06:45.'};
    case 'atgym': {
      const left = PROOF - d.atgym;
      return {eyebrow: left > 0 ? 'AT THE GYM' : 'PROOF EARNED', headline: [mmss(Math.min(d.atgym, PROOF + 59 * 60))], support: left > 0 ? `${mmss(left)} to go. Twenty minutes makes it count.` : 'Twenty minutes. It counts.'};
    }
    case 'verified':
      return {eyebrow: 'WORKOUT VERIFIED', headline: ['Done.'], support: 'That post-workout lift can last up to 12 hours.'};
    case 'rest':
      return {eyebrow: 'REST DAY', headline: ['Recover today.'], support: 'Rest is part of the plan. Next session Fri 07:00.'};
    case 'freshstart':
      return {eyebrow: 'NEW WEEK', headline: ['Clean slate.'], support: 'Gym visits jump at the start of a week. Ride that.'};
    case 'missed':
      return {eyebrow: 'MISSED YESTERDAY', headline: ['Never twice.'], support: "One missed day doesn't undo a habit. Today keeps it that way."};
    case 'weekkept':
      return {eyebrow: 'WEEK KEPT', headline: [`${d.weekGoal} of ${d.weekGoal}.`], support: 'Every session you planned, done. Week streak: 2.'};
    case 'drift':
      return {eyebrow: 'WEEK 4', headline: ['Drift zone.'], support: 'New members plan 3 a week. By week 6 the average is 1. Not you.'};
    case 'comeback':
      return {eyebrow: 'WELCOME BACK', headline: ['Start again.'], support: 'No catching up. Just 20 minutes today.'};
    case 'halfway':
      return {eyebrow: 'HABIT FORMING', headline: ['Day 33.'], support: "Habits took 66 days on average to feel automatic. You're halfway."};
  }
};

let mctx: CanvasRenderingContext2D | null = null;
const measure = (text: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `700 ${size}px ${SF_ROUNDED}`;
  return mctx!.measureText(text).width * 0.98 + 1;
};

// ---------- the habit band ----------
const auto = (day: number) => 1 - Math.exp(-day / 22);
const DMAX = 72;

const HabitBand: React.FC<{s: S3; look: Look; f: number; g: number}> = ({s, look, f, g}) => {
  const D = DEFS[s];
  const x0 = 520, x1 = 948, yb = 168, yt = 46;
  const X = (d: number) => x0 + (d / DMAX) * (x1 - x0);
  const Y = (d: number) => yb - (auto(d) / auto(DMAX)) * (yb - yt);
  const pts = (a: number, b: number) => {
    const out: string[] = [];
    for (let d = a; d <= b + 1e-6; d += 0.5) out.push(`${X(d).toFixed(1)},${Y(d).toFixed(1)}`);
    return out.join(' ');
  };
  const mv = springFast(f - 14, 30, {damping: 12, stiffness: 160});
  const from = D.from ?? D.day;
  const day = from + (D.day - from) * mv;
  const draw = eo((f - 6) / 16);
  const pulse = 0.5 + 0.5 * Math.sin(g * 0.16);
  const lab = eo((f - 4) / 10);
  const num = Math.round(day);
  return (
    <div style={{position: 'absolute', left: 0, top: H, width: W, height: BAND_H}}>
      <div style={{position: 'absolute', left: 52, right: 52, top: 0, height: 2, background: look.border}} />
      <div style={{position: 'absolute', left: 52, top: 38, opacity: lab, transform: `translateY(${((1 - lab) * 8).toFixed(1)}px)`}}>
        <div style={{fontFamily: SF, fontSize: 26, fontWeight: 700, letterSpacing: '0.14em', color: look.ink2}}>HABIT STRENGTH</div>
        <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 58, color: look.ink, marginTop: 6, fontVariantNumeric: 'tabular-nums', letterSpacing: '-0.01em'}}>
          Day {num}
          <span style={{fontSize: 34, color: look.ink3, fontWeight: 700}}> of {HABIT_DAYS}</span>
        </div>
        <div style={{fontFamily: SF, fontSize: 28, fontWeight: 500, color: look.ink3, marginTop: 4, whiteSpace: 'nowrap'}}>{D.caption}</div>
      </div>
      <svg width={W} height={BAND_H} style={{position: 'absolute', left: 0, top: 0, overflow: 'visible'}}>
        {D.band && (
          <g opacity={eo((f - 10) / 14)}>
            <rect x={X(D.band[0])} y={yt - 4} width={X(D.band[1]) - X(D.band[0])} height={yb - yt + 10} rx={10} fill={rgba(look.ink, look.dark ? 0.1 : 0.06)} />
            <text x={(X(D.band[0]) + X(D.band[1])) / 2} y={yb + 34} textAnchor="middle" fontFamily={SF} fontSize={20} fontWeight={700} letterSpacing="2.5" fill={look.ink2}>
              WEEKS 3 TO 6
            </text>
          </g>
        )}
        {/* 66 marker */}
        <line x1={X(HABIT_DAYS)} x2={X(HABIT_DAYS)} y1={yt - 14} y2={yb + 6} stroke={look.ink3} strokeWidth={2} strokeDasharray="4 6" opacity={draw} />
        <text x={X(HABIT_DAYS)} y={yb + 34} textAnchor="middle" fontFamily={SF_ROUNDED} fontSize={22} fontWeight={700} fill={look.ink3} opacity={draw}>
          66
        </text>
        <line x1={x0} x2={x1} y1={yb + 6} y2={yb + 6} stroke={look.border} strokeWidth={2} />
        {/* the road ahead */}
        <polyline points={pts(0, DMAX)} fill="none" stroke={look.ink3} strokeWidth={2.5} strokeDasharray="2 9" strokeLinecap="round" opacity={draw * 0.9} />
        {/* the road walked */}
        {day > 0.05 && <polyline points={pts(0, day * draw)} fill="none" stroke={look.ink} strokeWidth={5} strokeLinecap="round" strokeLinejoin="round" />}
        {D.missed?.map((m, i) => (
          <g key={i} opacity={eo((f - 16 - i * 3) / 8)}>
            <circle cx={X(m)} cy={Y(m)} r={8} fill={look.card} stroke={look.ink2} strokeWidth={2.5} />
          </g>
        ))}
        {s === 'halfway' && (
          <text x={X(33)} y={Y(33) + 46} textAnchor="middle" fontFamily={SF} fontSize={20} fontWeight={700} letterSpacing="2.5" fill={look.ink2} opacity={eo((f - 24) / 10)}>
            HALFWAY
          </text>
        )}
        {/* you */}
        <g transform={`translate(${X(day * draw).toFixed(1)} ${Y(day * draw).toFixed(1)})`} opacity={draw}>
          <circle r={18 + pulse * 10} fill={CORAL} opacity={0.16 * (1 - pulse * 0.6)} />
          <circle r={10} fill={CORAL} stroke={look.card} strokeWidth={4} />
        </g>
      </svg>
    </div>
  );
};

// ---------- the card ----------
type Props = {state: S3; theme: Theme; mode: Mode; f: number; g: number; d: D3; pxScale: number; onToggleItem?: (i: number) => void; exit?: number};

export const HeroCard3: React.FC<Props> = ({state, theme, mode, f, g, d, pxScale, onToggleItem, exit = 0}) => {
  const look = lookFor3(state, theme);
  const def = DEFS[state];
  const cv = useRef<HTMLCanvasElement>(null);
  const dRef = useRef(d);
  dRef.current = d;
  const pw = Math.round(W * pxScale), ph = Math.round(H * pxScale);
  const scene: Scene = useMemo(
    () => (def.base === 'trail' ? trailScene({look, px: pxScale, mode}, () => def.trail!(dRef.current)) : buildScene(def.base, {look, px: pxScale, mode}, demoData(state, d))),
    [state, look, pxScale, mode], // eslint-disable-line
  );
  useLayoutEffect(() => {
    const c = cv.current!;
    if (c.width !== pw || c.height !== ph) {
      c.width = pw;
      c.height = ph;
    }
    const ctx = c.getContext('2d')!;
    ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    ctx.fillStyle = look.card;
    ctx.fillRect(0, 0, W, H);
    scene.draw(ctx, f, g, demoData(state, d));
    const bottom = ctx.createLinearGradient(0, H - 90, 0, H);
    bottom.addColorStop(0, rgba(look.card, 0));
    bottom.addColorStop(1, look.card);
    ctx.fillStyle = bottom;
    ctx.fillRect(0, H - 90, W, 90);
    const fade = ctx.createLinearGradient(0, 0, W, 0);
    fade.addColorStop(0, look.card);
    fade.addColorStop(0.3, look.card);
    fade.addColorStop(0.42, rgba(look.card, 0.82));
    fade.addColorStop(0.55, rgba(look.card, 0.4));
    fade.addColorStop(0.72, rgba(look.card, 0));
    ctx.fillStyle = fade;
    ctx.fillRect(0, 0, W, H);
  });

  const c = copyFor3(state, d);
  const bold = mode === 'bold';
  const isClock = state === 'countdown';
  const live = state === 'atgym';
  const setup = state === 'setup';
  const base = 88;
  const hSize = Math.min(base, ...c.headline.map((l) => (base * (setup ? 470 : 500)) / measure(isClock ? '00:00:00' : live ? '00:00' : l, base)));
  const lab = eo((f - 2) / (bold ? 6 : 10));
  const sub = eo((f - (bold ? 9 : 12)) / 12);
  const kick = bold && f >= 7 ? Math.max(0, 1 - (f - 7) / 8) : 0;
  const proofHit = live && d.atgym >= PROOF;

  return (
    <div style={{position: 'absolute', inset: 0, opacity: 1 - exit, background: look.card}}>
      <canvas ref={cv} style={{position: 'absolute', left: 0, top: 0, width: W, height: H, display: 'block'}} />
      <div
        style={{
          position: 'absolute',
          left: 52,
          top: 0,
          height: H,
          width: setup ? 480 : 520,
          display: 'flex',
          flexDirection: 'column',
          justifyContent: 'center',
          fontFamily: SF,
          color: look.ink,
          pointerEvents: setup ? 'auto' : 'none',
          transform: `translateY(${(Math.sin(f * 2.9) * kick * 5).toFixed(2)}px)`,
        }}
      >
        <div style={{display: 'flex', alignItems: 'center', gap: 12, fontSize: 30, fontWeight: 700, letterSpacing: `${bold ? 0.14 + (1 - lab) * 0.3 : 0.14}em`, color: look.ink2, opacity: lab, transform: `translateY(${((1 - lab) * 8).toFixed(1)}px)`, whiteSpace: 'nowrap'}}>
          {live && <span style={{width: 14, height: 14, borderRadius: 7, background: CORAL, opacity: proofHit ? 1 : 0.5 + 0.5 * Math.sin(g * 0.3), flex: 'none'}} />}
          {c.eyebrow}
        </div>
        <div style={{marginTop: 6}}>
          {c.headline.map((line, i) => {
            const at = 4 + i * 3;
            const p = springFast(f - at, 30, bold ? {damping: 10, stiffness: 260} : {damping: 18, stiffness: 260});
            return (
              <div
                key={i}
                style={{
                  fontFamily: SF_ROUNDED,
                  fontWeight: 700,
                  fontSize: hSize,
                  lineHeight: 1.02,
                  letterSpacing: '-0.02em',
                  whiteSpace: 'nowrap',
                  fontVariantNumeric: 'tabular-nums',
                  opacity: clamp01((f - at) / (bold ? 2 : 5)),
                  transform: bold ? `translateY(${((1 - p) * 60).toFixed(2)}px) scale(${(1.1 - 0.1 * p).toFixed(4)})` : `translateY(${((1 - p) * 26).toFixed(2)}px)`,
                  transformOrigin: '0% 100%',
                }}
              >
                {isClock ? <Clock remaining={d.countdown} mode={mode} /> : line}
              </div>
            );
          })}
        </div>
        {!setup && (
          <div style={{marginTop: 10, fontSize: 36, fontWeight: 500, color: look.ink2, lineHeight: 1.22, maxWidth: 440, opacity: sub, transform: `translateY(${((1 - sub) * 10).toFixed(1)}px)`}}>
            {c.support}
          </div>
        )}
        {live && (
          <div style={{marginTop: 18, width: 400, height: 10, borderRadius: 5, background: rgba(look.ink, look.dark ? 0.14 : 0.08), overflow: 'hidden', opacity: sub}}>
            <div style={{width: `${(clamp01(d.atgym / PROOF) * 100).toFixed(2)}%`, height: '100%', borderRadius: 5, background: proofHit ? CORAL : look.ink}} />
          </div>
        )}
        {setup && (
          <div style={{marginTop: 16, display: 'flex', flexDirection: 'column', gap: 10}}>
            {SETUP_ITEMS.map((label, i) => {
              const on = d.setupDone[i];
              const row = springFast(f - 9 - i * (bold ? 3 : 2.5), 30, bold ? {damping: 11, stiffness: 300} : {damping: 18, stiffness: 280});
              return (
                <button
                  key={i}
                  onClick={(e) => {
                    e.stopPropagation();
                    onToggleItem?.(i);
                  }}
                  style={{all: 'unset', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 16, fontSize: 34, fontWeight: on ? 600 : 500, color: on ? look.ink : look.ink2, opacity: clamp01(row * 2), transform: `translateY(${((1 - row) * (bold ? 24 : 12)).toFixed(1)}px)`, WebkitTapHighlightColor: 'transparent'}}
                >
                  <CheckDot on={on} look={look} mode={mode} />
                  {label}
                </button>
              );
            })}
          </div>
        )}
      </div>
      <HabitBand s={state} look={look} f={f} g={g} />
    </div>
  );
};

type HK = 'light' | 'medium' | 'heavy' | 'success';
export const stateHaptics3 = (s: S3): {f: number; kind: HK}[] => {
  const out: {f: number; kind: HK}[] = [{f: 6, kind: 'medium'}, {f: 14, kind: 'light'}];
  if (s === 'verified' || s === 'weekkept' || s === 'halfway') out.push({f: 18, kind: 'success'}, {f: 22, kind: 'heavy'});
  if (s === 'freshstart' || s === 'comeback') out.push({f: 12, kind: 'medium'});
  if (s === 'missed' || s === 'drift') out.push({f: 9, kind: 'heavy'});
  if (s === 'weekkept') for (let i = 0; i < 5; i++) out.push({f: 12 + i * 4, kind: 'heavy'});
  return out;
};
