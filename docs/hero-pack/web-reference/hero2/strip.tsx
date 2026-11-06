/**
 * The bottom band of the hero card: this week's flames (the streak, made visible) and one live
 * "what matters next" module. Built around how people who *intend* to train actually slip:
 *   • the week is never a blank slate — earned flames stay lit (endowed progress)
 *   • today's flame is visibly waiting to be lit, with a time on it (loss aversion + a deadline)
 *   • the next step is phrased as a concrete if-then (implementation intention)
 *   • the next milestone is always close and countable (goal gradient)
 *   • the locked apps are shown, not hidden — the stake is felt (commitment device)
 */
import React from 'react';
import {springFast} from '../../src/springFast';
import {hash} from '../../src/done/geom';
import {CORAL, Look, Mode, clamp01, eo, rgba} from './paint';
import {DemoData, StateId} from './scenes';
import {SF, SF_ROUNDED, clock} from './card';

export const FLAME_OUTER = 'M50 4C58 22 86 40 86 72C86 98 70 116 50 116C30 116 14 98 14 74C14 58 22 46 30 40C30 52 36 60 42 62C40 40 44 20 50 4Z';
export const FLAME_INNER = 'M50 70C56 80 64 86 64 98C64 106 58 112 50 112C42 112 36 106 36 98C36 88 44 82 50 70Z';
export const PLAN_DAYS = ['Mon', 'Wed', 'Fri'];

type FlameState = 'lit' | 'igniting' | 'today' | 'next' | 'off';

/** One streak flame. `t` = frames since it ignited (igniting only). */
export const Flame: React.FC<{state: FlameState; h: number; look: Look; g: number; t?: number; mode: Mode; id: string; seed?: number}> = ({state, h, look, g, t = 99, mode, id, seed = 0}) => {
  const lit = state === 'lit' || state === 'igniting';
  const ign = state === 'igniting' ? springFast(t, 30, mode === 'bold' ? {damping: 8, stiffness: 260} : {damping: 12, stiffness: 240}) : 1;
  const litA = state === 'igniting' ? clamp01(t / 4) : lit ? 1 : 0;
  const flick = lit ? Math.sin(g * 0.35 + seed * 2.1) * 0.025 + Math.sin(g * 0.9 + seed) * 0.012 : 0;
  const off = look.dark ? '#2C2C30' : '#E7E6E2';
  const offInner = look.dark ? '#3A3A3F' : '#F4F3F0';
  const breathe = 0.5 + 0.5 * Math.sin(g * 0.11 + seed);
  const s = state === 'igniting' ? 0.55 + 0.45 * ign : 1;
  return (
    <svg width={(h * 100) / 120} height={h} viewBox="0 0 100 120" style={{overflow: 'visible', display: 'block'}}>
      <defs>
        <linearGradient id={`${id}-g`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#FFB067" />
          <stop offset="0.55" stopColor="#F27A45" />
          <stop offset="1" stopColor="#E5463A" />
        </linearGradient>
        <radialGradient id={`${id}-r`}>
          <stop offset="0" stopColor="#FF8A4C" stopOpacity="0.55" />
          <stop offset="1" stopColor="#FF8A4C" stopOpacity="0" />
        </radialGradient>
      </defs>
      {/* halo when lit / igniting */}
      {lit && <circle cx={50} cy={86} r={state === 'igniting' ? 40 + (1 - clamp01(t / 18)) * 50 : 44} fill={`url(#${id}-r)`} opacity={state === 'igniting' ? 1 - clamp01((t - 10) / 30) * 0.6 : 0.4} />}
      {state === 'igniting' && t < 20 && <circle cx={50} cy={80} r={30 + (t / 20) * 50} fill="none" stroke="#F27A45" strokeWidth={3 * (1 - t / 20)} opacity={1 - t / 20} />}
      <g transform={`translate(50 116) scale(${(s * (1 + flick)).toFixed(4)} ${(s * (1 - flick * 0.6)).toFixed(4)}) translate(-50 -116)`}>
        <path d={FLAME_OUTER} fill={off} stroke={state === 'next' ? rgba(look.ink, 0.35) : 'none'} strokeWidth={state === 'next' ? 3 : 0} strokeDasharray={state === 'next' ? '5 6' : undefined} />
        <path d={FLAME_INNER} fill={offInner} />
        {/* today: a pilot light, waiting */}
        {state === 'today' && (
          <>
            <circle cx={50} cy={96} r={26 + breathe * 6} fill={`url(#${id}-r)`} opacity={0.6 + breathe * 0.4} />
            <path d={FLAME_INNER} fill="#F27A45" opacity={0.35 + breathe * 0.3} transform={`translate(50 112) scale(${0.62 + breathe * 0.06}) translate(-50 -112)`} />
          </>
        )}
        <g opacity={litA}>
          <path d={FLAME_OUTER} fill={`url(#${id}-g)`} />
          <path d={FLAME_INNER} fill="#FFF6EC" opacity={0.92} />
        </g>
      </g>
      {/* embers drifting up from a lit flame */}
      {lit &&
        Array.from({length: mode === 'bold' ? 4 : 2}, (_, i) => {
          const life = 70 + hash(i, seed) * 50;
          const k = (((g + hash(i, seed + 1) * life) % life) + life) % life / life;
          return <circle key={i} cx={50 + (hash(i, seed + 2) - 0.5) * 40 + Math.sin(k * 6 + i) * 6} cy={30 - k * 60} r={2.2 * (1 - k)} fill="#FF9A55" opacity={(1 - k) * 0.8 * litA} />;
        })}
      {state === 'igniting' &&
        t < 26 &&
        Array.from({length: mode === 'bold' ? 12 : 7}, (_, i) => {
          const a = -Math.PI / 2 + (hash(i, 7) - 0.5) * 2.4;
          const d = (40 + hash(i, 8) * 60) * eo(t / 22);
          return <circle key={'b' + i} cx={50 + Math.cos(a) * d} cy={70 + Math.sin(a) * d} r={2.6 * (1 - t / 26)} fill="#FF9A55" />;
        })}
    </svg>
  );
};

/** which flame is which, for the demo week (Mon / Wed / Fri plan) */
export const flameStates = (s: StateId, d: DemoData, f: number, igniteAt: number): FlameState[] =>
  PLAN_DAYS.slice(0, d.weekGoal).map((_, i) => {
    if (s === 'setup') return 'off';
    if (i < d.weekDone) {
      if (s === 'verified' && i === d.weekDone - 1) return f >= igniteAt ? 'igniting' : 'today';
      return 'lit';
    }
    if (i === d.weekDone) return s === 'countdown' || s === 'ready' ? 'today' : 'next';
    return 'off';
  });

const Bar: React.FC<{p: number; look: Look; accent?: boolean; w?: number}> = ({p, look, accent, w = 300}) => (
  <div style={{width: w, height: 8, borderRadius: 4, background: rgba(look.ink, look.dark ? 0.14 : 0.08), overflow: 'hidden'}}>
    <div style={{width: `${(clamp01(p) * 100).toFixed(2)}%`, height: '100%', borderRadius: 4, background: accent ? CORAL : look.ink}} />
  </div>
);

const LockGlyph: React.FC<{open: number; color: string; s?: number}> = ({open, color, s = 1}) => (
  <svg width={26 * s} height={30 * s} viewBox="0 0 26 30" style={{overflow: 'visible', flex: 'none'}}>
    <path d={`M6 13 V9 A7 7 0 0 1 20 9 V${13 - open * 6}`} fill="none" stroke={color} strokeWidth={3.2} strokeLinecap="round" transform={`translate(0 ${-open * 4})`} />
    <rect x={2} y={13} width={22} height={16} rx={4} fill={color} />
  </svg>
);

type Props = {state: StateId; look: Look; mode: Mode; f: number; g: number; data: DemoData; night: {remaining: number}};

export const StatusStrip: React.FC<Props> = ({state, look, mode, f, g, data, night}) => {
  const bold = mode === 'bold';
  const igniteAt = 16;
  const fs = flameStates(state, data, f, igniteAt);
  const lit = fs.filter((x) => x === 'lit' || x === 'igniting').length;
  const shownLit = state === 'verified' && f < igniteAt ? lit - 1 : lit;
  const inA = eo((f - 10) / 14);
  const enterY = (k: number) => {
    const p = springFast(f - 10 - k * 3, 30, bold ? {damping: 11, stiffness: 260} : {damping: 20, stiffness: 240});
    return {opacity: clamp01((f - 10 - k * 3) / 6), transform: `translateY(${((1 - p) * (bold ? 26 : 12)).toFixed(1)}px)`};
  };
  const todayIdx = fs.indexOf('today');
  const label = (t: string) => <div style={{fontSize: 26, fontWeight: 700, letterSpacing: '0.14em', color: look.ink3, whiteSpace: 'nowrap'}}>{t}</div>;

  // ---- right module, per state ----
  const right = (() => {
    switch (state) {
      case 'setup': {
        const n = data.setupDone.filter(Boolean).length;
        return (
          <>
            {label('FIRST FLAME')}
            <div style={{fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 50, marginTop: 4}}>{n === 3 ? 'Ready to light' : `${3 - n} step${3 - n > 1 ? 's' : ''} away`}</div>
            <div style={{display: 'flex', gap: 8, marginTop: 14}}>
              {[0, 1, 2].map((i) => (
                <div key={i} style={{flex: 1, height: 8, borderRadius: 4, background: data.setupDone[i] ? look.ink : rgba(look.ink, 0.1), transition: 'background .25s'}} />
              ))}
            </div>
          </>
        );
      }
      case 'night': {
        const r = night.remaining;
        return (
          <>
            {label('PHONE LOCKS IN')}
            <div style={{fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 50, marginTop: 4, fontVariantNumeric: 'tabular-nums'}}>{clock(r).replace(/^00:/, '')}</div>
            <div style={{fontSize: 29, fontWeight: 500, color: look.ink2, marginTop: 6}}>Calls and maps stay on.</div>
          </>
        );
      }
      case 'rest':
        return (
          <>
            {label('NEXT FLAME')}
            <div style={{fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 50, marginTop: 4}}>
              {PLAN_DAYS[Math.min(data.weekDone, data.weekGoal - 1)]} {data.nextTime}
            </div>
            <div style={{fontSize: 29, fontWeight: 500, color: look.ink2, marginTop: 6}}>Rest never breaks a streak.</div>
          </>
        );
      case 'week':
      case 'verified': {
        const left = data.weekGoal - data.weekDone;
        const p = eo((f - 18) / 20) * (data.weekDone / data.weekGoal);
        return (
          <>
            {label('WEEK STREAK')}
            <div style={{display: 'flex', alignItems: 'baseline', gap: 12, marginTop: 4, fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 50}}>
              <span>{data.streakWeeks}</span>
              <span style={{fontSize: 30, color: look.ink3}}>→</span>
              <span style={{color: left === 0 ? CORAL : look.ink}}>{data.streakWeeks + 1}</span>
            </div>
            <div style={{fontSize: 29, fontWeight: 500, color: look.ink2, marginTop: 6, marginBottom: 12}}>{left > 0 ? `${left} more locks in week ${data.streakWeeks + 1}.` : `Week ${data.streakWeeks + 1} is yours.`}</div>
            <Bar p={p} look={look} w={340} />
          </>
        );
      }
      case 'countdown': {
        const leaveIn = Math.max(0, data.countdown.remaining - 15 * 60);
        return (
          <>
            {label('LEAVE BY')}
            <div style={{fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 50, marginTop: 4}}>06:45</div>
            <div style={{display: 'flex', alignItems: 'center', gap: 12, marginTop: 10}}>
              <LockGlyph open={0} color={look.ink} s={1} />
              <span style={{fontSize: 29, fontWeight: 500, color: look.ink2}}>6 apps stay locked</span>
            </div>
            <span style={{display: 'none'}}>{leaveIn}</span>
          </>
        );
      }
      case 'ready': {
        const steps = ['Wake', 'Leave', 'Arrive', 'Train'];
        const done = 1;
        return (
          <>
            {label("TODAY'S PATH")}
            <div style={{display: 'flex', alignItems: 'center', marginTop: 18, width: 340}}>
              {steps.map((s, i) => {
                const pop = springFast(f - 14 - i * 3, 30, bold ? {damping: 9, stiffness: 300} : {damping: 15, stiffness: 300});
                const active = i === done;
                const pulse = active ? 0.5 + 0.5 * Math.sin(g * 0.15) : 0;
                return (
                  <React.Fragment key={s}>
                    {i > 0 && <div style={{flex: 1, height: 3, background: i <= done ? look.ink : rgba(look.ink, 0.12)}} />}
                    <div style={{position: 'relative', width: 26, height: 26, borderRadius: 13, flex: 'none', background: i < done ? look.ink : look.card, border: `3px solid ${i <= done ? look.ink : rgba(look.ink, 0.18)}`, boxSizing: 'border-box', transform: `scale(${(0.6 + 0.4 * pop).toFixed(3)})`, boxShadow: active ? `0 0 0 ${(4 + pulse * 6).toFixed(1)}px ${rgba(CORAL, 0.18 + pulse * 0.12)}` : 'none'}}>
                      {i < done && (
                        <svg viewBox="-10 -10 20 20" width={20} height={20} style={{position: 'absolute', left: 0, top: 0}}>
                          <path d="M-4.5 0 L-1.2 3.4 L4.6 -3" fill="none" stroke={look.card} strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round" />
                        </svg>
                      )}
                    </div>
                  </React.Fragment>
                );
              })}
            </div>
            <div style={{display: 'flex', justifyContent: 'space-between', width: 370, marginLeft: -10, marginTop: 8}}>
              {steps.map((s, i) => (
                <span key={s} style={{fontSize: 24, fontWeight: i === done ? 700 : 500, color: i === done ? look.ink : look.ink3, width: 70, textAlign: 'center'}}>
                  {s}
                </span>
              ))}
            </div>
          </>
        );
      }
    }
  })();

  return (
    <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 240, fontFamily: SF, color: look.ink}}>
      <div style={{position: 'absolute', left: 52, right: 52, top: 0, height: 1.5, background: rgba(look.ink, look.dark ? 0.12 : 0.08), transform: `scaleX(${inA.toFixed(3)})`, transformOrigin: '0 50%'}} />
      {/* left: this week, as flames */}
      <div style={{position: 'absolute', left: 52, top: 30, width: 450, ...enterY(0)}}>
        <div style={{display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', width: 400}}>
          {label('THIS WEEK')}
          <span style={{fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 34, fontVariantNumeric: 'tabular-nums'}}>
            {state === 'setup' ? '' : `${Math.max(0, shownLit)} of ${data.weekGoal}`}
          </span>
        </div>
        <div style={{display: 'flex', gap: 34, marginTop: 14, alignItems: 'flex-end'}}>
          {fs.map((st, i) => (
            <div key={i} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8}}>
              <Flame state={st} h={80} look={look} g={g} t={f - igniteAt} mode={mode} id={`fl-${state}-${i}`} seed={i} />
              <span style={{fontSize: 25, fontWeight: i === todayIdx || (st === 'igniting') ? 700 : 500, color: i === todayIdx || st === 'igniting' ? look.ink : look.ink3}}>
                {i === todayIdx ? 'Today' : st === 'next' && state === 'night' ? 'Tmrw' : PLAN_DAYS[i]}
              </span>
            </div>
          ))}
          {state === 'setup' && <span style={{fontSize: 29, fontWeight: 500, color: look.ink2, alignSelf: 'center', maxWidth: 170, lineHeight: 1.2}}>Lit by showing up.</span>}
        </div>
      </div>
      <div style={{position: 'absolute', left: 548, top: 30, bottom: 30, width: 1.5, background: rgba(look.ink, look.dark ? 0.12 : 0.08), opacity: inA}} />
      <div style={{position: 'absolute', left: 584, top: 30, right: 40, ...enterY(1)}}>{right}</div>
    </div>
  );
};
