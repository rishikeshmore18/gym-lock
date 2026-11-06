/**
 * Matrix card, Dynamic: its own instrument. Scenes are designed for the dot board (pixel icons, LED
 * numerals, dials, bars, waveforms, particles that fly between shapes), not Ridge's landscape in dots.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, H, Look, LOOKS, Theme, W, clamp01, eo, rgba} from '../hero2/paint';
import {CheckDot, SETUP_ITEMS, SF, SF_ROUNDED, clock} from '../hero2/card';
import {gridBitmap} from '../hero4/dots';
import {MDots} from './mdots';
import {D4, DEFS, PROOF, S4, copyFor4} from '../hero4/card4';
import type {Pos} from '../hero11/copy11';
import {cardCopy} from '../hero12/copy12';
import {Day, MonthCal, MonthPos, WORLDS, tapsFor12} from '../hero12/days12';
import {dataFor12} from '../hero12/scenes12';
import {typeFor} from './props13';
import {mxScene} from './mx13';
import {MX_LIVE} from './mx/atgym';
import {G} from './mxlib';
import {Eyebrow, FlipClock, Kinetic} from './kin13';
import {reduceMotion} from './card13';

const OX = 492, OY = 26, PITCH = 12.5, COLS = 38, ROWS = 35;

const hm = (sec: number) => `${Math.floor(sec / 3600)}h ${String(Math.floor(sec / 60) % 60).padStart(2, '0')}m`;

let mctx: CanvasRenderingContext2D | null = null;
const measure = (txt: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `700 ${size}px ${SF_ROUNDED}`;
  return mctx!.measureText(txt).width * 0.98 + 1;
};
const lookFor = (s: S4, theme: Theme): Look => (DEFS[s].night ? LOOKS.night : LOOKS[theme]);

type Props = {state: S4; theme: Theme; f: number; t: number; d: D4; pxScale: number; day: Day; pos: Pos; mp: MonthPos; cal: MonthCal; onToggleItem?: (i: number) => void; onTouchTick?: () => void};

export const HeroCard13M: React.FC<Props> = ({state, theme, f, t, d, pxScale, day, pos, mp, cal, onToggleItem, onTouchTick}) => {
  const look = lookFor(state, theme);
  const cv = useRef<HTMLCanvasElement>(null);
  const root = useRef<HTMLDivElement>(null);
  const eng = useMemo(() => new MDots(720, COLS, ROWS), []);
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
  const reduce = reduceMotion();

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
    const g = new G();
    const sc = mxScene(state, day);
    const o = sc.draw(g, {t, T: lt, d, day, pos, N: tapsFor12(day, pos), D}) || {};
    eng.update(`${state}:${day}:${pos}:${o.ph ?? 0}`, g.out(), t, o.o ?? {stagger: 0.25});
    const sh = reduce ? 0 : (o.shake ?? 0) * PITCH;
    const dx = sh ? Math.sin(t * 97) * sh : 0, dy = sh ? Math.cos(t * 83) * sh * 0.6 : 0;
    eng.draw(ctx, OX + dx, OY + dy, PITCH, look.ink, CORAL, 4.6, (x) => clamp01((x - OX + 40) / 120));
    // a flash of light, when the scene calls for one
    const fa = reduce ? 0 : o.flash ?? 0;
    if (fa > 0.01) {
      ctx.fillStyle = rgba(look.ink, Math.min(0.3, fa * 0.6));
      ctx.fillRect(OX, OY, COLS * PITCH, ROWS * PITCH);
    }
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
  const liveSub = left > 0 ? `**${String(Math.floor(left / 60)).padStart(2, '0')}:${String(Math.floor(left) % 60).padStart(2, '0')}** ${MX_LIVE[day].live}.` : `**${MX_LIVE[day].liveDone}**`;
  const c = {eyebrow: state === 'atgym' && d.atgym >= PROOF ? base0.eyebrow : W7.eyebrow, headline: keepHead ? (state === 'stilltime' ? `${hm(d.stillLeft)} left` : base0.headline) : W7.title, support: state === 'atgym' ? liveSub : W7.sub};
  const setup = state === 'setup';
  const isClock = state === 'countdown';
  const live = state === 'atgym';
  const base = 88;
  const hSize = Math.min(base, (base * (setup ? 430 : 440)) / measure(isClock ? '00:00:00' : live ? '00:00' : c.headline, base));
  const eSize = Math.min(30, (30 * 450) / Math.max(1, measure(c.eyebrow, 30) * 1.25));
  const lab = eo((f - 2) / 7);
  const sub = eo((f - 9) / 12);
  const typeOf = typeFor(state, day);
  const proofHit = live && d.atgym >= PROOF;

  return (
    <div ref={root} onPointerMove={onMove} onPointerDown={onMove} onPointerUp={onLeave} onPointerLeave={onLeave} onPointerCancel={onLeave} style={{position: 'absolute', inset: 0, background: look.card, transition: 'background .35s', touchAction: 'pan-y'}}>
      <canvas ref={cv} style={{position: 'absolute', left: 0, top: 0, width: W, height: H, display: 'block'}} />
      <div style={{position: 'absolute', left: 52, top: 0, height: H, width: 470, display: 'flex', flexDirection: 'column', justifyContent: 'center', fontFamily: SF, color: look.ink, pointerEvents: setup ? 'auto' : 'none'}}>
        <Eyebrow text={c.eyebrow} f={f} color={look.ink2} reduce={reduce} style={{fontSize: eSize, fontWeight: 700, color: look.ink2, opacity: lab}}>
          {(live || state === 'stilltime') && <span style={{width: 14, height: 14, borderRadius: 7, background: CORAL, opacity: proofHit ? 1 : 0.5 + 0.5 * Math.sin(t * 9), flex: 'none'}} />}
        </Eyebrow>
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
          }}
        >
          {isClock ? (
            <FlipClock text={clock(d.countdown)} frac={1 - (d.countdown - Math.floor(d.countdown))} size={hSize} color={look.ink} family={SF_ROUNDED} weight={700} up={false} />
          ) : live ? (
            <span style={{opacity: clamp01((f - 4) / 3)}}>{c.headline}</span>
          ) : (
            <Kinetic text={c.headline} style={typeOf} f={f} size={hSize} color={look.ink} family={SF_ROUNDED} weight={700} tracking={-0.02} reduce={reduce} />
          )}
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
