/**
 * Ridge card: the day's painted world on the right, fading to paper on the left where the words sit.
 * A brush note in the sky, river stones for the week.
 */
import React, {useLayoutEffect, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {H, Theme, W, clamp01, eo} from '../hero2/paint';
import {SETUP_ITEMS, SF} from '../hero2/card';
import {D4, PROOF, S4} from '../hero4/card4';
import {DISPLAY, Icon, Swoosh, Words} from '../hero8/card8';
import {charge, dataFor12, sceneFor12} from './scenes12';
import type {Pos} from '../hero11/copy11';
import {cardCopy} from './copy12';
import {Day, MonthCal, MonthPos, WORLDS} from './days12';
import {boulderGeom, drawChips} from '../hero10/wash';
import {Painter3} from './wash3';

export const MARKER = 'GLMarker, "Marker Felt", "Bradley Hand", cursive';

/** a small river stone: filled for a session done, outlined for one to come */
const PEB = ['M6 14C3 13 2 10 4 7C6 4 11 3 15 4C19 5 22 8 21 11C20 14 16 16 11 16C9 16 7 15 6 14Z', 'M5 13C2 11 3 7 6 5C9 3 14 3 17 5C20 7 21 11 18 13C15 15 9 15 5 13Z', 'M4 11C3 8 6 5 10 4C14 3 19 5 20 8C21 12 17 15 12 15C8 15 5 14 4 11Z'];
export const Pebble: React.FC<{s: number; on: boolean; ink: string; k: number}> = ({s, on, ink, k}) => (
  <svg width={s} height={(s * 18) / 24} viewBox="0 0 24 18" style={{display: 'block', overflow: 'visible'}}>
    <path d={PEB[k % 3]} fill={on ? ink : 'none'} stroke={ink} strokeWidth={on ? 0 : 1.6} strokeDasharray={on ? undefined : '2.2 2'} opacity={on ? 1 : 0.5} />
    {on && <path d="M8 7C10 6 13 6 15 7" stroke="rgba(255,255,255,.35)" strokeWidth={1.4} fill="none" strokeLinecap="round" />}
  </svg>
);

export const Rich10: React.FC<{text: string; ink: string; ink2: string}> = ({text, ink, ink2}) => (
  <>
    {text.split('**').map((part, i) => (
      <span key={i} style={{fontWeight: i % 2 ? 800 : 500, color: i % 2 ? ink : ink2}}>
        {part}
      </span>
    ))}
  </>
);

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

export const HeroCard12: React.FC<Props> = ({state, theme, f, t, d, pxScale, day, pos, mp, cal, onToggleItem}) => {
  const cv = useRef<HTMLCanvasElement>(null);
  const painter = useRef<Painter3 | null>(null);
  const chip = useRef<{key: string; at: number} | null>(null);
  const dark = theme === 'dark';
  const D = dataFor12(state, pos);
  const W5 = cardCopy(state, day, pos, mp, cal);
  const world = WORLDS[day];
  const c = {...D, ...W5, title: W5.title === '#LEFT' ? `${Math.floor(d.stillLeft / 3600)}h ${String(Math.floor(d.stillLeft / 60) % 60).padStart(2, '0')}m left.` : W5.title};
  // chips fly when the rock breaks (stone days): on the Done card, and the moment the 20 minutes complete
  const chipKey = day !== 1 ? '' : state === 'verified' ? 'v' + pos : state === 'atgym' && d.atgym >= PROOF ? 'g' : '';
  if (chipKey && chip.current?.key !== chipKey) chip.current = {key: chipKey, at: t + (state === 'verified' ? 0.3 : 0)};
  if (!chipKey) chip.current = null;
  useLayoutEffect(() => {
    if (!painter.current) painter.current = new Painter3();
    const cw = Math.round(W * pxScale), ch = Math.round(H * pxScale);
    const el = cv.current!;
    if (el.width !== cw || el.height !== ch) {
      el.width = cw;
      el.height = ch;
    }
    const ctx = el.getContext('2d')!;
    const S = sceneFor12(state, d, f, t, day, pos);
    painter.current.render3(ctx, cw, ch, S, theme, t);
    if (chip.current) {
      const B = boulderGeom(cw, ch, S.seed);
      drawChips(ctx, cw, ch, S.seed, [B.cx, B.by - B.bh * 0.6], t - chip.current.at, theme);
      drawChips(ctx, cw, ch, S.seed + 5, [B.cx + B.bw * 0.2, B.by - B.bh * 0.3], t - chip.current.at - 0.08, theme);
    }
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
  const sub = eo((f - 12) / 12);
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
        <div style={{display: 'flex', alignItems: 'center', gap: 12, fontFamily: SF, fontSize: c.eyebrow.length > 22 ? 21 : 24, fontWeight: 800, letterSpacing: `${0.06 + (1 - lab) * 0.2}em`, opacity: lab, whiteSpace: 'nowrap'}}>
          <Icon k={c.icon} color={ink} bg={`rgb(${paper})`} s={32} />
          {c.eyebrow}
          {(live || c.live) && <span style={{width: 11, height: 11, borderRadius: 6, background: '#E85D4E', opacity: proofHit ? 1 : 0.5 + 0.5 * Math.sin(t * 8)}} />}
        </div>
        <div style={{marginTop: 8, fontFamily: DISPLAY, fontWeight: 900, fontSize: tSize, lineHeight: 1.0, letterSpacing: '-0.03em', fontVariantNumeric: 'tabular-nums'}}>
          {c.title === '#CLOCK' ? (
            <span style={{opacity: clamp01((f - 4) / 4)}}>{hms(d.countdown)}</span>
          ) : c.title === '#LIVE' ? (
            <span style={{opacity: clamp01((f - 4) / 4)}}>{mmss(d.atgym)}</span>
          ) : (
            <Words text={title} f={f} at={4} size={tSize} color={ink} maxW={490} />
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
