/**
 * Hero card: the app's own card (white, hairline, 24 radius, SF Rounded numbers) with a painted
 * landscape on the right that fades into the card behind the copy. 1000 × 488 design space.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, H, LOOKS, Look, Mode, Theme, W, clamp01, eo, eo5, rgba} from './paint';
import {DemoData, StateId, buildScene} from './scenes';
import {StatusStrip} from './strip';

/** card = painted hero (1000 × 488) + the status band below it */
export const STRIP_H = 240;
export const CARD_H = H + STRIP_H;

export const SF = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif';
export const SF_ROUNDED = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif';
export const SETUP_ITEMS = ['Apps locked', 'Alarm ready', 'Gym selected'];

export const lookFor = (s: StateId, theme: Theme): Look => (s === 'night' ? LOOKS.night : LOOKS[theme]);

export const clock = (s: number) => {
  const t = Math.max(0, Math.ceil(s));
  return [Math.floor(t / 3600), Math.floor((t % 3600) / 60), t % 60].map((x) => String(x).padStart(2, '0')).join(':');
};

export const copyFor = (s: StateId, d: DemoData) => {
  const n = d.setupDone.filter(Boolean).length;
  switch (s) {
    case 'setup':
      return {eyebrow: 'FINISH YOUR SYSTEM', headline: [`${n} of ${d.setupDone.length} ready`], support: ''};
    case 'night':
      return {eyebrow: 'REST NOW', headline: [d.bedtime], support: `Apps lock for the night. Up at ${d.wake}.`};
    case 'rest':
      return {eyebrow: 'REST DAY', headline: ['Recover', 'today.'], support: `Next session ${d.nextDay} ${d.nextTime}`};
    case 'week': {
      const left = d.weekGoal - d.weekDone;
      return {eyebrow: 'YOUR PROGRESS', headline: [`${d.weekDone} of ${d.weekGoal}`], support: left > 0 ? `${left} more to finish the week.` : 'Week complete.'};
    }
    case 'countdown':
      return {eyebrow: 'GYM TIME IN', headline: [clock(d.countdown.remaining)], support: 'Leave when the ring closes.'};
    case 'ready':
      return {eyebrow: 'FIRST STEP WON', headline: ['Get ready'], support: 'The mist is lifting. Time to go.'};
    case 'verified':
      return {eyebrow: 'WORKOUT VERIFIED', headline: ['Done.'], support: 'You showed up today.'};
  }
};

export const Clock: React.FC<{remaining: number; mode: Mode}> = ({remaining, mode}) => {
  const now = clock(remaining), prev = clock(remaining + 1);
  const since = Math.ceil(remaining) - remaining;
  const t = eo5(1 - since / (mode === 'bold' ? 0.22 : 0.32));
  return (
    <span style={{display: 'inline-flex', fontVariantNumeric: 'tabular-nums'}}>
      {Array.from(now).map((ch, i) =>
        ch === prev[i] || ch === ':' ? (
          <span key={i} style={{display: 'inline-block', width: ch === ':' ? '0.3em' : '0.6em', textAlign: 'center'}}>
            {ch}
          </span>
        ) : (
          <span key={i} style={{position: 'relative', display: 'inline-block', width: '0.6em', height: '1.08em', overflow: 'hidden', verticalAlign: 'top'}}>
            <span style={{position: 'absolute', left: 0, right: 0, textAlign: 'center', transform: `translateY(${(-t * 100).toFixed(1)}%)`, opacity: 1 - t}}>{prev[i]}</span>
            <span style={{position: 'absolute', left: 0, right: 0, textAlign: 'center', transform: `translateY(${((1 - t) * 100).toFixed(1)}%)`}}>{ch}</span>
          </span>
        ),
      )}
    </span>
  );
};

export const CheckDot: React.FC<{on: boolean; look: Look; mode: Mode}> = ({on, look, mode}) => {
  const ref = useRef<{on: boolean; t0: number}>({on, t0: 0});
  if (ref.current.on !== on) ref.current = {on, t0: performance.now()};
  const fr = ((performance.now() - ref.current.t0) / 1000) * 30;
  const p = ref.current.t0 ? springFast(fr, 30, mode === 'bold' ? {damping: 8, stiffness: 340} : {damping: 14, stiffness: 320}) : 1;
  return (
    <svg width={34} height={34} viewBox="-17 -17 34 34" style={{flex: 'none', overflow: 'visible', transform: `scale(${on ? 0.6 + 0.4 * p : 1})`}}>
      {on ? (
        <>
          <circle r={15.5} fill={look.ink} />
          <path d="M-6.6 0.4 L-2 5 L7 -4.6" fill="none" stroke={look.card} strokeWidth={3.2} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray="1" strokeDashoffset={1 - clamp01(p * 1.2)} />
        </>
      ) : (
        <circle r={14.5} fill="none" stroke={look.ink3} strokeWidth={2.4} />
      )}
    </svg>
  );
};

let mctx: CanvasRenderingContext2D | null = null;
const measure = (text: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `700 ${size}px ${SF_ROUNDED}`;
  return mctx!.measureText(text).width * 0.98 + 1;
};

type Props = {state: StateId; theme: Theme; mode: Mode; f: number; g: number; data: DemoData; pxScale: number; onToggleItem?: (i: number) => void; exit?: number};

export const HeroCardArt: React.FC<Props> = ({state, theme, mode, f, g, data, pxScale, onToggleItem, exit = 0}) => {
  const look = lookFor(state, theme);
  const cv = useRef<HTMLCanvasElement>(null);
  const pw = Math.round(W * pxScale), ph = Math.round(H * pxScale);
  const scene = useMemo(() => buildScene(state, {look, px: pxScale, mode}, data), [state, look, pxScale, mode, data.weekGoal]); // eslint-disable-line
  useLayoutEffect(() => {
    const c = cv.current!;
    if (c.width !== pw || c.height !== ph) {
      c.width = pw;
      c.height = ph;
    }
    const ctx = c.getContext('2d')!;
    ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = look.card;
    ctx.fillRect(0, 0, W, H);
    scene.draw(ctx, f, g, data);
    const bottom = ctx.createLinearGradient(0, H - 70, 0, H);
    bottom.addColorStop(0, rgba(look.card, 0));
    bottom.addColorStop(1, look.card);
    ctx.fillStyle = bottom;
    ctx.fillRect(0, H - 70, W, 70);
    const fade = ctx.createLinearGradient(0, 0, W, 0);
    fade.addColorStop(0, look.card);
    fade.addColorStop(0.3, look.card);
    fade.addColorStop(0.42, rgba(look.card, 0.82));
    fade.addColorStop(0.55, rgba(look.card, 0.4));
    fade.addColorStop(0.72, rgba(look.card, 0));
    ctx.fillStyle = fade;
    ctx.fillRect(0, 0, W, H);
  });

  const c = copyFor(state, data);
  const bold = mode === 'bold';
  const isClock = state === 'countdown';
  const setup = state === 'setup';
  const base = c.headline.length > 1 ? 80 : 88;
  const hSize = Math.min(base, ...c.headline.map((l) => (base * (setup ? 470 : 520)) / measure(isClock ? '00:00:00' : l, base)));
  const lab = eo((f - 2) / (bold ? 6 : 10));
  const sub = eo((f - (bold ? 9 : 12)) / 12);
  const kick = bold && f >= 7 ? Math.max(0, 1 - (f - 7) / 8) : 0;

  return (
    <div style={{position: 'absolute', inset: 0, opacity: 1 - exit, background: look.card}}>
      <canvas ref={cv} style={{position: 'absolute', inset: 0, width: W, height: H, display: 'block'}} />
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
        <div style={{fontSize: 30, fontWeight: 700, letterSpacing: `${bold ? 0.14 + (1 - lab) * 0.3 : 0.14}em`, color: look.ink2, opacity: lab, transform: `translateY(${((1 - lab) * 8).toFixed(1)}px)`, whiteSpace: 'nowrap'}}>
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
                  opacity: clamp01((f - at) / (bold ? 2 : 5)),
                  transform: bold ? `translateY(${((1 - p) * 60).toFixed(2)}px) scale(${(1.1 - 0.1 * p).toFixed(4)})` : `translateY(${((1 - p) * 26).toFixed(2)}px)`,
                  transformOrigin: '0% 100%',
                }}
              >
                {isClock ? <Clock remaining={data.countdown.remaining} mode={mode} /> : line}
              </div>
            );
          })}
        </div>
        {!setup && (
          <div style={{marginTop: 10, fontSize: 38, fontWeight: 500, color: look.ink2, lineHeight: 1.22, maxWidth: 430, opacity: sub, transform: `translateY(${((1 - sub) * 10).toFixed(1)}px)`}}>
            {c.support}
          </div>
        )}
        {setup && (
          <div style={{marginTop: 16, display: 'flex', flexDirection: 'column', gap: 10}}>
            {SETUP_ITEMS.map((label, i) => {
              const on = data.setupDone[i];
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
      <StatusStrip state={state} look={look} mode={mode} f={f} g={g} data={data} night={{remaining: data.lockIn}} />
    </div>
  );
};

export const stateHaptics = (s: StateId, mode: Mode, d: DemoData): {f: number; kind: 'light' | 'medium' | 'heavy' | 'success'}[] => {
  if (mode === 'calm') {
    const out: {f: number; kind: 'light' | 'medium' | 'heavy' | 'success'}[] = [{f: 6, kind: s === 'ready' ? 'medium' : 'light'}];
    if (s === 'verified') out.push({f: 16, kind: 'success'});
    if (s === 'week') for (let i = 0; i < d.weekDone; i++) out.push({f: 13 + i * 6, kind: 'light'});
    if (s === 'setup') d.setupDone.forEach((on, k) => on && out.push({f: 14 + k * 4, kind: 'light'}));
    return out;
  }
  const out: {f: number; kind: 'light' | 'medium' | 'heavy' | 'success'}[] = [{f: 6, kind: 'heavy'}];
  if (s === 'week') for (let i = 0; i < d.weekDone; i++) out.push({f: 13 + i * 4, kind: 'heavy'});
  if (s === 'setup') d.setupDone.forEach((on, k) => on && out.push({f: 14 + k * 4, kind: 'medium'}));
  if (s === 'verified') out.push({f: 16, kind: 'success'}, {f: 19, kind: 'heavy'});
  if (s === 'ready') out.push({f: 12, kind: 'medium'}, {f: 18, kind: 'light'});
  if (s === 'night') out.push({f: 12, kind: 'light'});
  return out;
};

export {CORAL};
