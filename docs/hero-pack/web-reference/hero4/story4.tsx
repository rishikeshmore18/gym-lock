/**
 * Done screen as five tap-through screens on a full-screen dot matrix. The same particles fly from
 * screen to screen: lock → race clock → heart-rate equaliser → flame → DONE. Nothing advances on
 * its own: each screen plays, its bar fills, then "Tap to continue" appears.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, clamp01, eo, eo5, rgba} from '../hero2/paint';
import {SF, SF_ROUNDED} from '../hero2/card';
import {Dots, Tgt, gridBitmap, hash, text, textWidth} from './dots';
import * as G from './glyphs';

export const BOX_W = 1080;
export const BOX_H = 1920;
export const fitComposition = (vw: number, vh: number) => {
  const a = vw / vh;
  if (a < BOX_W / BOX_H) return {w: BOX_W, h: Math.round(BOX_W / a / 2) * 2};
  return {w: Math.round((BOX_H * a) / 2) * 2, h: BOX_H};
};
export const FOCUS_Y = 880;
const PITCH = 21;
const GY = 900; // glyph centre in the box

// ---------- the session ----------
export const SESSION = {minutes: 52 + 14 / 60, kcal: 418, start: '07:04', end: '07:56'};
const HR: number[] = (() => {
  const out: number[] = [];
  for (let i = 0; i < 40; i++) {
    const m = (i / 39) * SESSION.minutes;
    let v: number;
    if (m < 7) v = 96 + (m / 7) * 34;
    else if (m > 46) v = 132 - ((m - 46) / 6.2) * 28;
    else {
      const c = (m - 7) % 5.2;
      const peak = 150 + [4, 8, 12, 18, 14, 10, 6, 4][Math.floor((m - 7) / 5.2) % 8];
      v = c < 1.7 ? 124 + (peak - 124) * Math.sin((c / 1.7) * Math.PI * 0.5) : peak - (peak - 122) * eo((c - 1.7) / 2.2);
    }
    out.push(v + (hash(i, 5) - 0.5) * 6);
  }
  return out;
})();
export const AVG_HR = Math.round(HR.reduce((a, b) => a + b, 0) / HR.length);
export const PEAK_HR = Math.round(Math.max(...HR));
const PEAK_I = HR.indexOf(Math.max(...HR));
const HRN = HR.map((v) => (v - 80) / (PEAK_HR - 80));

type HK = 'light' | 'medium' | 'heavy' | 'success';
const minuteTicks = (() => {
  const out: {t: number; kind: HK}[] = [];
  let last = 0;
  for (let t = 0.3; t <= 2.1; t += 1 / 60) {
    const m = eo5((t - 0.3) / 1.8) * SESSION.minutes;
    if (Math.floor(m / 4) > last) {
      last = Math.floor(m / 4);
      out.push({t, kind: 'light'});
    }
  }
  return out;
})();

export const SCREENS: {settle: number; haptics: {t: number; kind: HK}[]}[] = [
  {settle: 1.5, haptics: [{t: 0.05, kind: 'medium'}, {t: 0.75, kind: 'heavy'}, {t: 0.8, kind: 'success'}]},
  {settle: 2.3, haptics: [{t: 0.05, kind: 'medium'}, ...minuteTicks, {t: 2.12, kind: 'heavy'}]},
  {settle: 2.4, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 8}, (_, k) => ({t: 0.2 + k * 0.18, kind: 'light' as HK})), {t: 1.9, kind: 'medium'}, {t: 2.15, kind: 'medium'}]},
  {settle: 1.9, haptics: [{t: 0.05, kind: 'medium'}, {t: 0.7, kind: 'heavy'}, {t: 0.75, kind: 'success'}, {t: 1.5, kind: 'light'}]},
  {settle: 1.3, haptics: [{t: 0.02, kind: 'heavy'}, {t: 0.08, kind: 'success'}, {t: 0.3, kind: 'heavy'}]},
];

const mmss = (mins: number) => {
  const s = Math.floor(mins * 60);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

type Props = {f: number; idx: number; lt: number; w: number; h: number; pxScale: number; showHint: boolean; leaving: boolean};

export const Story4: React.FC<Props> = ({idx, lt, w, h, pxScale, showHint, leaving}) => {
  const cv = useRef<HTMLCanvasElement>(null);
  const ox = (w - BOX_W) / 2, oy = (h - BOX_H) / 2;
  const cols = Math.ceil(w / PITCH), rows = Math.ceil(h / PITCH);
  const eng = useMemo(() => new Dots(1400, cols, rows), [cols, rows]);
  const grid = useMemo(() => gridBitmap(cols, rows, PITCH, 1.6, '#FFFFFF', 0.07, pxScale), [cols, rows, pxScale]);
  const t0 = useRef(performance.now());
  const cx = Math.floor(w / 2 / PITCH) + 0.5, cy = Math.floor((oy + GY) / PITCH) + 0.5;
  const FR: G.Frame = {cols, rows, cx, cy, u: 12};

  useLayoutEffect(() => {
    const c = cv.current!;
    const pw = Math.round(w * pxScale), ph = Math.round(h * pxScale);
    if (c.width !== pw || c.height !== ph) {
      c.width = pw;
      c.height = ph;
    }
    const ctx = c.getContext('2d')!;
    ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    ctx.fillStyle = '#0A0A0B';
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(grid, 0, 0, cols * PITCH, rows * PITCH);
    const t = (performance.now() - t0.current) / 1000;
    let T: Tgt[] = [];
    let o = {};
    if (idx === 0) {
      const open = springFast(lt * 30 - 22, 30, {damping: 9, stiffness: 180});
      T = G.lock(FR, t, [1, 1, 1], Math.max(0, open));
      o = {stagger: 0.25};
    } else if (idx === 1) {
      const m = eo5((lt - 0.3) / 1.8) * SESSION.minutes;
      const s = mmss(m);
      const tw = textWidth(s, 2, 0.5);
      T = text(s, Math.round(cx - tw / 2), Math.round(cy - 7), {scale: 2, dim: 0.09, gap: 0.5});
      // one dot per minute; minute 20, the proof, in coral
      for (let k = 0; k < 52; k++) {
        const on = k < m;
        T.push({x: cx - 13 + (k % 26), y: cy + 11 + Math.floor(k / 26) * 1.5, b: on ? 0.9 : 0.12, c: k === 19 && on ? 1 : 0});
      }
      o = {stagger: 0.2};
    } else if (idx === 2) {
      T = G.equalizer(FR, t, lt - 0.1, HRN, 18, PEAK_I);
      o = {stagger: 0.25};
    } else if (idx === 3) {
      const ig = clamp01((lt - 0.25) / 0.6);
      T = G.flame(FR, t, {h: 30, ignite: ig, dy: -5});
      // 66 days: two rows of 33, day one lit
      for (let i = 0; i < 66; i++) {
        const c = i % 33, r = Math.floor(i / 33);
        const on = i === 0;
        T.push({x: Math.round(cx - 16 + c) + 0.5 - 0.5, y: cy + 17 + r * 1.5, b: on ? (lt > 1.4 ? 1 : 0.2) : 0.16 + (lt > 1.4 ? 0.04 * Math.sin(t * 3 + i * 0.3) : 0), c: on && lt > 1.4 ? 1 : 0});
      }
      o = {stagger: 0.2};
    } else {
      const tw = textWidth('DONE', 2);
      T = text('DONE', Math.round(cx - tw / 2), Math.round(cy - 7), {scale: 2});
      T.push(...G.scatterField(FR, t, 260));
      o = {burst: 70, stagger: 0.05};
    }
    eng.update('s' + idx, T, t, o);
    eng.draw(ctx, 0, 0, PITCH, '#FFFFFF', CORAL, 7.4);
    // slam flash on DONE
    if (idx === 4 && lt < 0.4) {
      ctx.fillStyle = rgba('#FFFFFF', 0.5 * (1 - lt / 0.4));
      ctx.fillRect(0, 0, w, h);
    }
  });

  const a = (at: number, d = 0.3) => eo((lt - at) / d);
  const white = '#FFFFFF';
  const lbl: React.CSSProperties = {fontFamily: SF, fontWeight: 700, letterSpacing: '0.16em', fontSize: 30, color: rgba(white, 0.55)};
  const title: React.CSSProperties = {fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 120, lineHeight: 1.02, letterSpacing: '-0.03em', marginTop: 12};
  const cap: React.CSSProperties = {fontFamily: SF, fontWeight: 500, fontSize: 40, lineHeight: 1.3, color: rgba(white, 0.62)};
  const roll = (to: number, at: number, d = 1.2) => Math.round(eo5((lt - at) / d) * to);

  const heads: {eyebrow: string; title: string}[] = [
    {eyebrow: 'WORKOUT VERIFIED', title: 'It counts.'},
    {eyebrow: 'TIME AT THE GYM', title: ''},
    {eyebrow: 'EFFORT', title: ''},
    {eyebrow: 'STREAK', title: 'Day 1.'},
    {eyebrow: '', title: ''},
  ];
  const hd = heads[idx];

  return (
    <div style={{position: 'relative', width: w, height: h, overflow: 'hidden', background: '#0A0A0B', color: white}}>
      <canvas ref={cv} style={{position: 'absolute', inset: 0, width: w, height: h, display: 'block'}} />
      {/* story bars */}
      <div style={{position: 'absolute', top: Math.max(oy, 0) + 90, left: 60, right: 60, display: 'flex', gap: 12, opacity: leaving ? 0 : 1}}>
        {SCREENS.map((s, i) => (
          <div key={i} style={{flex: 1, height: 7, borderRadius: 4, background: rgba(white, 0.18), overflow: 'hidden'}}>
            <div style={{height: '100%', borderRadius: 4, background: white, width: `${(i < idx ? 1 : i > idx ? 0 : clamp01(lt / s.settle)) * 100}%`}} />
          </div>
        ))}
      </div>
      <div style={{position: 'absolute', left: ox, top: oy, width: BOX_W, height: BOX_H, textAlign: 'center', pointerEvents: 'none'}}>
        <div key={'h' + idx} style={{position: 'absolute', top: 250, left: 60, right: 60, opacity: a(0.1)}}>
          {hd.eyebrow && <div style={{...lbl, letterSpacing: `${0.16 + (1 - a(0.1)) * 0.3}em`}}>{hd.eyebrow}</div>}
          {hd.title && <div style={{...title, transform: `translateY(${((1 - springFast(lt * 30 - 5, 30, {damping: 11, stiffness: 220})) * 50).toFixed(1)}px)`}}>{hd.title}</div>}
        </div>
        {idx === 0 && (
          <div style={{position: 'absolute', top: 1350, left: 110, right: 110, opacity: a(0.9, 0.4), transform: `translateY(${((1 - a(0.9, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={cap}>Twenty minutes at the gym, confirmed.</div>
            <div style={{display: 'inline-flex', alignItems: 'center', gap: 16, marginTop: 34, padding: '20px 34px', borderRadius: 60, background: rgba(white, 0.1), fontFamily: SF, fontSize: 32, fontWeight: 700, color: white}}>
              <span style={{width: 14, height: 14, borderRadius: 7, background: CORAL}} />6 apps unlocked
            </div>
          </div>
        )}
        {idx === 1 && (
          <div style={{position: 'absolute', top: 1250, left: 110, right: 110, opacity: a(2.1, 0.4)}}>
            <div style={{fontFamily: SF_ROUNDED, fontSize: 64, fontWeight: 800}}>
              {SESSION.start} <span style={{color: rgba(white, 0.4)}}>to</span> {SESSION.end}
            </div>
            <div style={{...cap, marginTop: 14}}>Logged the moment you walked in.</div>
          </div>
        )}
        {idx === 2 && (
          <div style={{position: 'absolute', top: 1160, left: 70, right: 70}}>
            <div style={{display: 'flex'}}>
              {[
                {v: roll(SESSION.kcal, 0.5), u: 'kcal', l: 'ACTIVE ENERGY'},
                {v: roll(AVG_HR, 0.7), u: 'bpm', l: 'AVG HEART RATE'},
                {v: roll(PEAK_HR, 0.95), u: 'bpm', l: 'PEAK'},
              ].map((s, k) => (
                <div key={k} style={{flex: 1, opacity: a(0.4 + k * 0.2), transform: `translateY(${((1 - a(0.4 + k * 0.2)) * 24).toFixed(1)}px)`, borderLeft: k ? `1px solid ${rgba(white, 0.14)}` : 'none'}}>
                  <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 92, lineHeight: 1, fontVariantNumeric: 'tabular-nums', color: k === 2 ? CORAL : white}}>
                    {s.v}
                    <span style={{fontSize: 32, color: rgba(white, 0.5), marginLeft: 6}}>{s.u}</span>
                  </div>
                  <div style={{...lbl, fontSize: 22, marginTop: 14}}>{s.l}</div>
                </div>
              ))}
            </div>
            <div style={{...cap, fontSize: 28, marginTop: 50, color: rgba(white, 0.36)}}>Heart rate and energy from Apple Health</div>
          </div>
        )}
        {idx === 3 && (
          <div style={{position: 'absolute', top: 1340, left: 120, right: 120, opacity: a(1.4, 0.4), transform: `translateY(${((1 - a(1.4, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={cap}>
              Day 1 of about 66.
              <br />
              <span style={{color: rgba(white, 0.42)}}>Miss a day later and it won't undo this.</span>
            </div>
          </div>
        )}
        {idx === 4 && (
          <div style={{position: 'absolute', top: 1110, left: 110, right: 110, opacity: a(0.35, 0.4), transform: `translateY(${((1 - a(0.35, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={{fontFamily: SF, fontSize: 50, fontWeight: 700, lineHeight: 1.25}}>
              Almost half of people who plan to work out don't follow through.
              <span style={{color: CORAL}}> You did.</span>
            </div>
          </div>
        )}
      </div>
      {/* bottom: hint, or the way home */}
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 300, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', opacity: leaving ? 0 : 1}}>
        {idx < 4 ? (
          <div style={{fontFamily: SF, fontSize: 30, fontWeight: 600, letterSpacing: '0.04em', color: rgba(white, showHint ? 0.45 + 0.25 * Math.sin(lt * 4) : 0), display: 'flex', alignItems: 'center', gap: 14, transition: 'color .2s'}}>
            Tap to continue
            <svg width={22} height={22} viewBox="0 0 22 22" style={{opacity: showHint ? 1 : 0}}>
              <path d="M7 3l8 8-8 8" fill="none" stroke={rgba(white, 0.6)} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>
        ) : (
          <div style={{fontFamily: SF, fontWeight: 700, fontSize: 40, color: '#111', background: white, borderRadius: 60, padding: '30px 110px', opacity: showHint ? 1 : 0, transform: `translateY(${showHint ? 0 : 20}px)`, transition: 'all .3s cubic-bezier(.2,.9,.25,1)'}}>
            Back to home
          </div>
        )}
      </div>
    </div>
  );
};
