/**
 * Ridge card, Dynamic: the day's painted world with the moment's own scene played over it, a camera
 * move, and the headline arriving with its own motion.
 */
import React, {useLayoutEffect, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {H, Theme, W, clamp01, eo} from '../hero2/paint';
import {SETUP_ITEMS, SF} from '../hero2/card';
import {D4, PROOF, S4} from '../hero4/card4';
import {DISPLAY, Icon, Swoosh} from '../hero8/card8';
import {charge, dataFor12} from '../hero12/scenes12';
import type {Pos} from '../hero11/copy11';
import {cardCopy} from '../hero12/copy12';
import {Day, MonthCal, MonthPos, WORLDS, tapsFor12} from '../hero12/days12';
import {palette} from '../hero10/wash';
import {Painter3} from '../hero12/wash3';
import {build} from './props13';
import {CAM0, Cam, camMatrix, paintShapes} from './stage13';
import {Eyebrow, FlipClock, Kinetic} from './kin13';
import {MARKER, Pebble, Rich10} from '../hero12/card12';

/** keep the painted backdrop covering the card while the camera moves */
export const clampCam = (c: Cam): Cam => {
  const s = Math.max(1, c.s, 1 + Math.abs(c.r) * 0.9);
  const pxs = 492 + (c.px ?? 55) * 4.75, pys = 26 + (c.py ?? 46) * 4.75;
  const lo = (-(1000 - pxs) * (s - 1)) / 4.75, hi = (pxs * (s - 1)) / 4.75;
  const loY = (-(488 - pys) * (s - 1)) / 4.75, hiY = (pys * (s - 1)) / 4.75;
  return {...c, s, x: Math.min(hi, Math.max(lo, c.x)), y: Math.min(hiY, Math.max(loY, c.y))};
};
export const reduceMotion = () => typeof window !== 'undefined' && !!window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

let mctx: CanvasRenderingContext2D | null = null;
const measure900 = (txt: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `900 ${size}px ${DISPLAY}`;
  return mctx!.measureText(txt).width * 1.0;
};
const mmss = (sec: number) => {
  const t = Math.max(0, Math.floor(sec));
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};
const hms = (sec: number) => {
  const t = Math.max(0, Math.floor(sec));
  return `${String(Math.floor(t / 3600)).padStart(2, '0')}:${String(Math.floor(t / 60) % 60).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};

type Props = {state: S4; theme: Theme; f: number; t: number; d: D4; pxScale: number; day: Day; pos: Pos; mp: MonthPos; cal: MonthCal; onToggleItem?: (i: number) => void};

export const HeroCard13: React.FC<Props> = ({state, theme, f, t, d, pxScale, day, pos, mp, cal, onToggleItem}) => {
  const cv = useRef<HTMLCanvasElement>(null);
  const painter = useRef<Painter3 | null>(null);
  const dark = theme === 'dark';
  const D = dataFor12(state, pos);
  const W5 = cardCopy(state, day, pos, mp, cal);
  const world = WORLDS[day];
  const c = {...D, ...W5, title: W5.title === '#LEFT' ? `${Math.floor(d.stillLeft / 3600)}h ${String(Math.floor(d.stillLeft / 60) % 60).padStart(2, '0')}m left.` : W5.title};
  const reduce = reduceMotion();
  const T = f / 30;
  const B = build(state, day, {t, T, at: t - T, d, day, pos, n: d.setupDone.filter(Boolean).length, D, N: tapsFor12(day, pos), matrix: false});
  useLayoutEffect(() => {
    if (!painter.current) painter.current = new Painter3();
    const cw = Math.round(W * pxScale), ch = Math.round(H * pxScale);
    const el = cv.current!;
    if (el.width !== cw || el.height !== ch) {
      el.width = cw;
      el.height = ch;
    }
    const ctx = el.getContext('2d')!;
    const P = painter.current;
    const S = B.scene;
    const cam = reduce ? CAM0 : clampCam(B.cam);
    P.xf = camMatrix(cam, pxScale);
    const pal = palette(theme, Math.round(S.night * 4) / 4);
    const shapes = reduce ? B.shapes.filter((q) => q.k !== 'flash') : B.shapes;
    P.render(ctx, cw, ch, S, theme, t, () => {
      P.overlay(ctx, cw, ch, S, theme, t);
      paintShapes(ctx, shapes, pxScale, pal, theme, cw, ch);
    });
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  });

  const paper = dark ? '14,14,16' : '246,246,244';
  const ink = dark ? '#F4F4F2' : '#0E0E10';
  const ink2 = dark ? 'rgba(244,244,242,.72)' : 'rgba(14,14,16,.72)';
  const setup = state === 'setup';
  const live = state === 'atgym';
  const proofHit = live && d.atgym >= PROOF;
  const done = d.setupDone.filter(Boolean).length;
  const title = setup ? `${done} of 3 ready.` : c.title;
  const tSize = Math.min(96, (96 * 470) / measure900(title === '#CLOCK' ? '00:00:00' : title === '#LIVE' ? '00:00' : title, 96));
  const lab = eo((f - 2) / 7);
  const sub = eo((f - 14) / 10);
  const foot = eo((f - 18) / 12);
  const note = eo((f - 22) / 14);
  const noteInk = dark ? 'rgba(244,244,242,.92)' : 'rgba(14,14,16,.88)';
  return (
    <div style={{position: 'absolute', inset: 0, background: `rgb(${paper})`, overflow: 'hidden'}}>
      <canvas ref={cv} style={{position: 'absolute', left: 0, top: 0, width: W, height: H, display: 'block'}} />
      {/* fade to paper on the left, like a print bleeding off the page */}
      <div style={{position: 'absolute', inset: 0, background: `linear-gradient(90deg, rgba(${paper},1) 0%, rgba(${paper},.96) 32%, rgba(${paper},.7) 44%, rgba(${paper},.3) 55%, rgba(${paper},0) 66%)`}} />
      {c.note && (
        <div style={{position: 'absolute', right: 250, top: 30, textAlign: 'right', transform: `rotate(-5deg) translateY(${((1 - note) * 8).toFixed(1)}px)`, transformOrigin: '100% 0', opacity: note}}>
          <div style={{fontFamily: MARKER, fontSize: c.note.length > 16 ? 34 : 42, lineHeight: 1.05, color: noteInk, maxWidth: 300, letterSpacing: '0.01em', textTransform: 'uppercase'}}>{c.note}</div>
          <div style={{display: 'flex', justifyContent: 'flex-end', marginTop: 4}}>
            <Swoosh p={eo((f - 30) / 14)} color={noteInk} w={160} />
          </div>
        </div>
      )}
      <div style={{position: 'absolute', left: 52, top: 0, height: H, width: 470, display: 'flex', flexDirection: 'column', justifyContent: 'center', color: ink, pointerEvents: setup ? 'auto' : 'none'}}>
        <Eyebrow text={c.eyebrow} f={f} color={ink} reduce={reduce} style={{fontFamily: SF, fontSize: c.eyebrow.length > 22 ? 21 : 24, fontWeight: 800, opacity: lab}}>
          <Icon k={c.icon} color={ink} bg={`rgb(${paper})`} s={32} />
          {(live || c.live) && <span style={{order: 9, width: 11, height: 11, borderRadius: 6, background: '#E85D4E', opacity: proofHit ? 1 : 0.5 + 0.5 * Math.sin(t * 8)}} />}
        </Eyebrow>
        <div style={{marginTop: 8, fontFamily: DISPLAY, fontWeight: 900, fontSize: tSize, lineHeight: 1.0, letterSpacing: '-0.03em', fontVariantNumeric: 'tabular-nums'}}>
          {c.title === '#CLOCK' ? (
            <span style={{opacity: clamp01((f - 4) / 4)}}><FlipClock text={hms(d.countdown)} frac={1 - (d.countdown - Math.floor(d.countdown))} size={tSize} color={ink} family={DISPLAY} weight={900} up={false} /></span>
          ) : c.title === '#LIVE' ? (
            <span style={{opacity: clamp01((f - 4) / 4)}}><FlipClock text={mmss(d.atgym)} frac={d.atgym - Math.floor(d.atgym)} size={tSize} color={ink} family={DISPLAY} weight={900} /></span>
          ) : (
            <Kinetic text={title} style={B.type} f={f} size={tSize} color={ink} family={DISPLAY} weight={900} reduce={reduce} />
          )}
        </div>
        {!setup && c.sub && (
          <div style={{marginTop: 12, fontFamily: SF, fontSize: 30, lineHeight: 1.24, maxWidth: 420, opacity: sub, transform: `translateY(${((1 - sub) * 10).toFixed(1)}px)`}}>
            <Rich10 text={c.sub} ink={ink} ink2={ink2} />
          </div>
        )}
        {live && (
          <div style={{marginTop: 14, opacity: sub}}>
            <div style={{width: 360, height: 8, borderRadius: 4, background: dark ? 'rgba(255,255,255,.14)' : 'rgba(0,0,0,.1)', overflow: 'hidden'}}>
              <div style={{width: `${(clamp01(d.atgym / PROOF) * 100).toFixed(2)}%`, height: '100%', borderRadius: 4, background: proofHit ? '#E85D4E' : ink}} />
            </div>
            <div style={{marginTop: 10, fontFamily: SF, fontSize: 26, color: ink2}}>
              {proofHit ? (
                <span style={{fontWeight: 800, color: ink}}>{world.liveDone}</span>
              ) : (
                <>
                  <span style={{fontWeight: 800, color: ink}}>{mmss(PROOF - d.atgym)}</span> {world.live}.
                </>
              )}
            </div>
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
                  style={{all: 'unset', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 14, fontFamily: SF, fontSize: 30, fontWeight: on ? 800 : 500, color: on ? ink : ink2, opacity: clamp01(row * 2), transform: `translateY(${((1 - row) * 16).toFixed(1)}px)`, WebkitTapHighlightColor: 'transparent'}}
                >
                  <span style={{width: 30, height: 30, borderRadius: 15, boxShadow: on ? 'none' : `inset 0 0 0 2.5px ${ink2}`, background: on ? ink : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
                    {on && (
                      <svg width={16} height={16} viewBox="0 0 16 16">
                        <path d="M3 8.5l3 3L13 4.5" fill="none" stroke={`rgb(${paper})`} strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                    )}
                  </span>
                  {label}
                </button>
              );
            })}
          </div>
        )}
        {!setup && !live && (
          <div style={{marginTop: 22, display: 'flex', alignItems: 'center', gap: 16, opacity: foot, transform: `translateY(${((1 - foot) * 10).toFixed(1)}px)`}}>
            {state === 'verified' ? (
              [
                ['52:14', 'TIME'],
                [`${c.week}/5`, 'THIS WEEK'],
                [String(c.sessions), 'SESSIONS'],
              ].map(([v, l], k) => (
                <div key={k} style={{paddingLeft: k ? 16 : 0, borderLeft: k ? `2px solid ${dark ? 'rgba(255,255,255,.16)' : 'rgba(0,0,0,.12)'}` : 'none'}}>
                  <div style={{fontFamily: DISPLAY, fontWeight: 800, fontSize: 34, lineHeight: 1, color: ink, fontVariantNumeric: 'tabular-nums'}}>{v}</div>
                  <div style={{fontFamily: SF, fontWeight: 700, fontSize: 15, letterSpacing: '0.12em', color: ink2, marginTop: 4}}>{l}</div>
                </div>
              ))
            ) : (
              <>
                {state === 'bedtime' || state === 'firstnight' ? (
                  <div style={{display: 'flex', alignItems: 'center', gap: 12}}>
                    <div style={{width: 64, height: 26, borderRadius: 7, boxShadow: `inset 0 0 0 2.5px ${ink}`, padding: 4, position: 'relative'}}>
                      <div style={{height: '100%', borderRadius: 3, background: ink, width: `${Math.round((state === 'bedtime' ? charge(t) : 0.12) * 100)}%`}} />
                      <div style={{position: 'absolute', right: -6, top: 8, width: 4, height: 10, borderRadius: 2, background: ink}} />
                    </div>
                    <div style={{fontFamily: SF, fontWeight: 800, fontSize: 17, letterSpacing: '0.1em', color: ink2}}>
                      <span style={{color: ink, fontVariantNumeric: 'tabular-nums'}}>{Math.round((state === 'bedtime' ? charge(t) : 0.12) * 100)}%</span> RECHARGED
                    </div>
                  </div>
                ) : (
                  <>
                    <div style={{display: 'flex', gap: 6, alignItems: 'center'}}>
                      {Array.from({length: 5}, (_, k) => (
                        <Pebble key={k} s={30} on={k < c.week} ink={ink} k={k} />
                      ))}
                    </div>
                    <div style={{fontFamily: SF, fontWeight: 800, fontSize: 17, letterSpacing: '0.1em', color: ink2, lineHeight: 1.25}}>
                      <span style={{color: ink}}>{c.week}/5</span> THIS WEEK
                      <br />
                      <span style={{color: ink}}>{c.sessions}</span> SESSIONS
                    </div>
                  </>
                )}
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
