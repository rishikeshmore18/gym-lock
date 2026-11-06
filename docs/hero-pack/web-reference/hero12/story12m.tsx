/**
 * Matrix done screens on a full-screen dot matrix, set in the day's world. The same particles fly
 * from screen to screen. The last screen is the day's finish, done with taps: raise the sun, break
 * the rock, skip the stone, grow the pine, light the beacon, send the lanterns, connect the stars.
 * Then the dots become the session count.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {CORAL, clamp01, eo, eo5, rgba} from '../hero2/paint';
import {SF, SF_ROUNDED} from '../hero2/card';
import {Dots, Opts, Tgt, gridBitmap, text, textWidth} from '../hero4/dots';
import * as G from '../hero4/glyphs';
import * as Z from './glyphs12';
import {AVG_HR, PEAK_HR, SESSION} from '../hero4/story4';
import {DONE_DATA, POS_WEEK, Pos} from '../hero11/copy11';
import {grow} from '../hero11/scenes11';
import {DONE12, monthScreen} from './copy12';
import {Day, MONTH_TARGETS, MonthCal, MonthPos, POS_TAIL, WORLDS, endFor, tapsFor12} from './days12';
import {ease} from './scenes12';
import {CFG_M, ScrId, TALLY} from './screens12';

export const BOX_W = 1080, BOX_H = 1920;
const PITCH = 21;
const GY = 900;

const mmss = (mins: number) => {
  const s = Math.floor(mins * 60);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};
const B: React.FC<{text: string}> = ({text: tx}) => (
  <>
    {tx.split('**').map((p, i) => (
      <span key={i} style={i % 2 ? {color: '#FFFFFF', fontWeight: 700} : undefined}>
        {p}
      </span>
    ))}
  </>
);

type Props = {ids: ScrId[]; idx: number; lt: number; w: number; h: number; pxScale: number; showHint: boolean; leaving: boolean; tapTimes: number[]; sealT: number | null; t: number; pos: Pos; day: Day; mp: MonthPos; cal: MonthCal; picked: boolean; dyn?: boolean};

export const Story12M: React.FC<Props> = ({ids, idx, lt, w, h, pxScale, showHint, leaving, tapTimes, sealT, t, pos, day, mp, cal, picked, dyn}) => {
  const id = ids[idx];
  const V = DONE12[pos][day];
  const D = DONE_DATA[pos];
  const PW = POS_WEEK[pos];
  const world = WORLDS[day];
  const END = endFor(pos, day);
  const MS = monthScreen(mp, pos, cal);
  const N = tapsFor12(day, pos);
  const taps = tapTimes.length;
  const tapAt = taps ? tapTimes[taps - 1] : null;
  const cv = useRef<HTMLCanvasElement>(null);
  const ox = (w - BOX_W) / 2, oy = (h - BOX_H) / 2;
  const cols = Math.ceil(w / PITCH), rows = Math.ceil(h / PITCH);
  const eng = useMemo(() => new Dots(1400, cols, rows), [cols, rows]);
  const grid = useMemo(() => gridBitmap(cols, rows, PITCH, 1.6, '#FFFFFF', 0.07, pxScale), [cols, rows, pxScale]);
  const cx = Math.floor(w / 2 / PITCH) + 0.5, cy = Math.floor((oy + GY) / PITCH) + 0.5;
  const FR: G.Frame = {cols, rows, cx, cy, u: 12};
  const FW: G.Frame = {cols, rows, cx, cy, u: 10};
  const g = grow(D.day);
  const since = sealT != null ? t - sealT : -1;
  const counted = sealT != null && since > 1.6;

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
    const at = t - lt;
    let T: Tgt[] = [];
    let o: Opts = {};
    let key = id + day;
    if (id === 'verified') {
      T = [
        Z.sun(FW, t, -0.15 + 0.35 * ease(lt / 1.5), {birds: 3}),
        Z.stone(FW, t, 4, 0),
        Z.water(FW, t, {boat: 0.3, ripples: 1}),
        Z.pine(FW, t, Math.max(0.3, g - 0.2)),
        Z.summit(FW, t, 0.5 + 0.3 * ease((lt - 0.2) / 1.2), 0),
        Z.sea(FW, t, {sun: 0.35}),
        Z.stars(FW, t, 0, 0, {moon: {x: cx + 18, y: cy - 22, phase: 0.98}}),
      ][day];
      o = {stagger: 0.25};
    } else if (id === 'today') {
      const m = eo5((lt - 0.3) / 1.8) * SESSION.minutes;
      const s = mmss(m);
      const tw = textWidth(s, 2, 0.5);
      T = text(s, Math.round(cx - tw / 2), Math.round(cy - 7), {scale: 2, dim: 0.09, gap: 0.5});
      for (let k = 0; k < 52; k++) {
        const on = k < m;
        T.push({x: cx - 13 + (k % 26), y: cy + 11 + Math.floor(k / 26) * 1.5, b: on ? 0.9 : 0.12, c: k === 19 && on ? 1 : 0});
      }
      o = {stagger: 0.2};
    } else if (id === 'week') {
      T = G.weekGrid(FR, t, lt, lt > 0.6 ? PW.done : PW.done - 1, PW.today);
      o = {order: 'y', oy: 5, stagger: 0.3, ...(pos === 'last' && lt > 0.6 ? {burst: 50} : {})};
    } else if (id === 'month') {
      T = Z.monthGrid({...FR, cy: cy - 2}, t, lt, cal.lead, cal.cells, MS.pick && !picked ? null : cal.target);
      key += picked ? 'p' + cal.target : '';
      o = {order: 'y', oy: cy - 12, stagger: 0.4};
    } else if (id === 'far') {
      const p = ease((lt - 0.2) / 1.4);
      const k = D.day / 66;
      const FU: G.Frame = {...FW, cy: cy - 5};
      T = [
        Z.sun(FU, t, -0.3 + 1.1 * k * p, {rays: p}),
        Z.stone(FU, t, 0, 0),
        Z.water(FU, t, {boat: k * p}),
        Z.pine(FU, t, 0.1 + (g - 0.1) * p),
        Z.summit(FU, t, k * p, 0),
        Z.sea(FU, t, {sun: 0.3, tide: k * p}),
        Z.stars(FU, t, 7 * k * p, 0),
      ][day];
      for (let i = 0; i < 66; i++) {
        const c = i % 33, r = Math.floor(i / 33);
        const on = i < D.day;
        T.push({x: cx - 16 + c, y: cy + 17 + r * 1.5, b: on ? (lt > 0.3 + i * 0.02 ? 0.95 : 0.2) : 0.16, c: i === D.day - 1 && lt > 1.4 ? 1 : 0});
      }
      o = {stagger: 0.2};
    } else if (counted) {
      const word = String(D.sessions);
      const tw2 = textWidth(word, 3);
      T = text(word, Math.round(cx - tw2 / 2), Math.round(cy - 10), {scale: 3});
      T.push(...Z.stars({...FR, cy: cy + 26}, t, 0, 0, {ridge: false, dim: 0.5}).slice(0, 18));
      T.push(...G.scatterField(FR, t, 200));
      key = 'count';
      o = {burst: 70, stagger: 0.05};
    } else {
      const hv = sealT != null ? 1 : taps === 0 ? 0 : (taps - 1 + ease((t - (tapAt ?? t)) / 0.35)) / N;
      const s = sealT;
      const g0 = Math.max(0.3, g - 0.2), g1 = Math.min(1, g + 0.08);
      T = [
        () => Z.sun(FW, t, s != null ? 0.9 : -0.35 + 1.15 * hv, {rays: s != null ? 1 : hv, birds: s != null ? 6 : 0}),
        () => Z.stone(FW, t, s != null ? 5 : hv * 5, s != null ? ease(Math.min(1, since / 0.55)) : 0),
        () => Z.water(FW, t, {skipN: N, skips: tapTimes, skipDone: s != null ? s + 0.35 : null}),
        () => Z.pine(FW, t, g0 + (g1 - g0) * hv, {burst: s}),
        () => Z.summit(FW, t, 0.4 + 0.6 * hv, s != null ? ease(since / 1) : 0),
        () => Z.sea(FW, t, {sun: 0.15, lanterns: s != null ? [...tapTimes, s + 0.25, s + 0.5] : tapTimes}),
        () => Z.stars(FW, t, s != null ? 7 : Math.min(7, taps === 0 ? 0 : taps - 1 + ease((t - (tapAt ?? t)) / 0.3)), s != null ? ease(since / 1) : 0, {shoot: s != null ? s + 0.7 : null}),
      ][day]();
      if (s != null && day === 0) {
        key += 's';
        o = {burst: 40, stagger: 0.1};
      }
    }
    void at;
    eng.update(key, T, t, o);
    eng.draw(ctx, 0, 0, PITCH, '#FFFFFF', CORAL, 7.4);
    // a flash on the finish
    if (id === 'climax' && sealT != null && since < 0.45) {
      ctx.fillStyle = rgba('#FFFFFF', 0.35 * (1 - since / 0.45));
      ctx.fillRect(0, 0, w, h);
    }
    if (id === 'climax' && counted && since < 2) {
      ctx.fillStyle = rgba('#FFFFFF', 0.4 * (1 - (since - 1.6) / 0.4));
      ctx.fillRect(0, 0, w, h);
    }
  });

  const a = (at: number, d = 0.3) => eo((lt - at) / d);
  const white = '#FFFFFF';
  const lbl: React.CSSProperties = {fontFamily: SF, fontWeight: 700, letterSpacing: '0.16em', fontSize: 30, color: rgba(white, 0.55)};
  const titleS: React.CSSProperties = {fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 120, lineHeight: 1.02, letterSpacing: '-0.03em', marginTop: 12};
  const cap: React.CSSProperties = {fontFamily: SF, fontWeight: 500, fontSize: 40, lineHeight: 1.3, color: rgba(white, 0.62)};
  const roll = (to: number, at: number, d = 1.2) => Math.round(eo5((lt - at) / d) * to);
  const monthFlourish = mp === 'last' && pos === 'last';
  const hitM = cal.sessions >= cal.target;
  const heads: Record<ScrId, {eyebrow: string; title: string}> = {
    verified: {eyebrow: V.eyebrow, title: V.title},
    today: {eyebrow: 'TODAY’S SESSION', title: ''},
    week: {eyebrow: 'THIS WEEK', title: PW.s2.title},
    month: {eyebrow: MS.eyebrow, title: MS.title},
    far: {eyebrow: 'HOW FAR YOU’VE COME', title: 'Week 7.'},
    climax: sealT != null ? {eyebrow: pos === 'last' ? 'WEEK COMPLETE' : 'SESSIONS', title: ''} : {eyebrow: pos === 'last' ? world.climax.lastEyebrow : world.climax.eyebrow, title: world.climax.title},
  };
  const hd = heads[id];
  const lastScr = idx === ids.length - 1;
  const ca = (at: number, d = 0.4) => eo((since - at) / d);

  const reduceM = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  const dz = dyn && !reduceM;
  const camS = dz ? 1 + 0.08 * (1 - eo(lt / 0.8)) + (id === 'climax' && tapAt != null && sealT == null ? 0.04 * Math.exp(-(t - tapAt) * 7) : 0) + (id === 'climax' && sealT != null ? 0.06 * Math.exp(-(t - sealT) * 4) : 0) : 1;
  const shakeX = dz && id === 'climax' && tapAt != null && sealT == null ? Math.exp(-(t - tapAt) * 9) * Math.sin((t - tapAt) * 70) * 8 : 0;
  return (
    <div style={{position: 'relative', width: w, height: h, overflow: 'hidden', background: '#0A0A0B', color: white}}>
      <canvas ref={cv} style={{position: 'absolute', inset: 0, width: w, height: h, display: 'block', transform: `translateX(${shakeX.toFixed(2)}px) scale(${camS.toFixed(4)})`, transformOrigin: '50% 47%'}} />
      {dz && id === 'climax' && tapAt != null && t - tapAt < 0.7 && (
        <div style={{position: 'absolute', left: '50%', top: '47%', width: (t - tapAt) * 1500, height: (t - tapAt) * 1500, marginLeft: -(t - tapAt) * 750, marginTop: -(t - tapAt) * 750, borderRadius: '50%', boxShadow: `inset 0 0 0 ${Math.max(1, 5 * (1 - (t - tapAt) / 0.7)).toFixed(1)}px ${sealT != null && t - sealT < 0.7 ? CORAL : white}`, opacity: 0.45 * (1 - (t - tapAt) / 0.7), pointerEvents: 'none'}} />
      )}
      <div style={{position: 'absolute', top: Math.max(oy, 0) + 90, left: 60, right: 60, display: 'flex', gap: 12, opacity: leaving ? 0 : 1}}>
        {ids.map((sid, i) => (
          <div key={i} style={{flex: 1, height: 7, borderRadius: 4, background: rgba(white, 0.18), overflow: 'hidden'}}>
            <div style={{height: '100%', borderRadius: 4, background: white, width: `${(i < idx ? 1 : i > idx ? 0 : clamp01(lt / CFG_M[sid].settle)) * 100}%`}} />
          </div>
        ))}
      </div>
      <div style={{position: 'absolute', left: ox, top: oy, width: BOX_W, height: BOX_H, textAlign: 'center', pointerEvents: 'none'}}>
        <div key={'h' + id + (sealT != null ? 's' : '')} style={{position: 'absolute', top: 250, left: 60, right: 60, opacity: a(0.1)}}>
          {hd.eyebrow && <div style={{...lbl, letterSpacing: `${0.16 + (1 - a(0.1)) * 0.3}em`}}>{hd.eyebrow}</div>}
          {hd.title && <div style={{...titleS, transform: `translateY(${((1 - springFast(lt * 30 - 5, 30, {damping: 11, stiffness: 220})) * 50).toFixed(1)}px) scale(${(dz ? 1 + 0.25 * Math.exp(-lt * 6) * Math.cos(lt * 14) : 1).toFixed(4)})`}}>{hd.title}</div>}
        </div>
        {id === 'verified' && (
          <div style={{position: 'absolute', top: 1350, left: 110, right: 110, opacity: a(0.9, 0.4), transform: `translateY(${((1 - a(0.9, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={cap}><B text={V.sub} /></div>
            <div style={{display: 'inline-flex', alignItems: 'center', gap: 16, marginTop: 34, padding: '20px 34px', borderRadius: 60, background: rgba(white, 0.1), fontFamily: SF, fontSize: 32, fontWeight: 700, color: white}}>
              <span style={{width: 14, height: 14, borderRadius: 7, background: CORAL}} />6 apps unlocked
            </div>
          </div>
        )}
        {id === 'today' && (
          <div style={{position: 'absolute', top: 1250, left: 110, right: 110, opacity: a(2.1, 0.4)}}>
            <div style={{fontFamily: SF_ROUNDED, fontSize: 64, fontWeight: 800}}>
              {SESSION.start} <span style={{color: rgba(white, 0.4)}}>to</span> {SESSION.end}
            </div>
            <div style={{...cap, marginTop: 14}}><B text="Logged the moment you walked in. **+6:10** on your last session." /></div>
            <div style={{display: 'flex', marginTop: 50}}>
              {[
                {v: roll(AVG_HR, 2.2, 0.8), u: 'bpm', l: 'AVG', c: false},
                {v: roll(PEAK_HR, 2.3, 0.8), u: 'bpm', l: 'PEAK', c: true},
                {v: roll(SESSION.kcal, 2.4, 0.8), u: 'kcal', l: 'ENERGY', c: false},
              ].map((s, k) => (
                <div key={k} style={{flex: 1, borderLeft: k ? `1px solid ${rgba(white, 0.14)}` : 'none'}}>
                  <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 72, lineHeight: 1, fontVariantNumeric: 'tabular-nums', color: s.c ? CORAL : white}}>
                    {s.v}
                    <span style={{fontSize: 26, color: rgba(white, 0.5), marginLeft: 6}}>{s.u}</span>
                  </div>
                  <div style={{...lbl, fontSize: 20, marginTop: 10}}>{s.l}</div>
                </div>
              ))}
            </div>
          </div>
        )}
        {id === 'week' && (
          <div style={{position: 'absolute', top: 1280, left: 110, right: 110, opacity: a(0.8, 0.4), transform: `translateY(${((1 - a(0.8, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={cap}><B text={PW.s2.sub} /></div>
            <div style={{...cap, fontSize: 30, marginTop: 30, color: rgba(white, 0.42)}}><B text={PW.s2.research} /></div>
          </div>
        )}
        {id === 'month' && (
          <div style={{position: 'absolute', top: 1230, left: 90, right: 90, opacity: a(0.7, 0.4), transform: `translateY(${((1 - a(0.7, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={{...cap, fontSize: 36}}><B text={MS.sub} /></div>
            {MS.pick ? (
              <div style={{display: 'flex', gap: 18, marginTop: 34, pointerEvents: 'auto'}}>
                {MONTH_TARGETS.map((m) => {
                  const sel = picked && cal.target === m.n;
                  return (
                    <div key={m.n} data-pick={m.n} style={{flex: 1, padding: '20px 0 16px', borderRadius: 30, background: sel ? white : rgba(white, 0.08), color: sel ? '#111' : white, cursor: 'pointer'}}>
                      <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 64, lineHeight: 1}}>{m.n}</div>
                      <div style={{...lbl, fontSize: 18, marginTop: 8, color: sel ? 'rgba(0,0,0,.55)' : rgba(white, 0.5)}}>{m.label.toUpperCase()}</div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <div style={{display: 'flex', marginTop: 34}}>
                {(mp === 'last'
                  ? [
                      {v: String(roll(cal.sessions, 0.8, 0.8)), l: 'SESSIONS', c: false},
                      {v: `${Math.floor(cal.minutes / 60)}h`, l: 'ON THE FLOOR', c: false},
                      {v: `+${cal.sessions - cal.lastMonth}`, l: 'VS LAST MONTH', c: true},
                    ]
                  : [
                      {v: String(roll(cal.sessions, 0.8, 0.8)), l: 'SESSIONS', c: false},
                      {v: String(cal.target), l: 'TARGET', c: false},
                      {v: String(Math.max(0, cal.target - cal.sessions)), l: 'TO GO', c: true},
                    ]
                ).map((s, k) => (
                  <div key={k} style={{flex: 1, borderLeft: k ? `1px solid ${rgba(white, 0.14)}` : 'none'}}>
                    <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 72, lineHeight: 1, color: s.c ? CORAL : white}}>{s.v}</div>
                    <div style={{...lbl, fontSize: 20, marginTop: 10}}>{s.l}</div>
                  </div>
                ))}
              </div>
            )}
            <div style={{...cap, fontSize: 28, marginTop: 30, color: rgba(white, 0.42)}}><B text={MS.research} /></div>
          </div>
        )}
        {id === 'far' && (
          <div style={{position: 'absolute', top: 1340, left: 120, right: 120, opacity: a(1.4, 0.4), transform: `translateY(${((1 - a(1.4, 0.4)) * 20).toFixed(1)}px)`}}>
            <div style={cap}>
              <B text={`Day **${D.day}** of about 66. **${D.sessions}** sessions, **${D.sessions - 1}** ${TALLY[day].toLowerCase()}.`} />
              <br />
              <span style={{color: rgba(white, 0.42)}}>From 38 min in week 1 to {PW.total} this week.</span>
            </div>
          </div>
        )}
        {id === 'climax' && sealT == null && (
          <div style={{position: 'absolute', top: 1300, left: 110, right: 110, opacity: a(0.4, 0.4)}}>
            <div style={cap}><B text={world.climax.sub(N)} /></div>
            <div style={{display: 'flex', gap: 16, justifyContent: 'center', marginTop: 40}}>
              {Array.from({length: N}, (_, k) => (
                <div key={k} style={{width: 30, height: 30, borderRadius: 15, background: k < taps ? white : 'transparent', boxShadow: k < taps ? 'none' : `inset 0 0 0 3px ${rgba(white, 0.4)}`, transform: `scale(${k === taps - 1 && tapAt != null ? 1 + 0.4 * Math.max(0, 1 - (t - tapAt) * 4) : 1})`}} />
              ))}
            </div>
          </div>
        )}
        {id === 'climax' && sealT != null && (
          <div style={{position: 'absolute', top: 1300, left: 110, right: 110, opacity: ca(1.7), transform: `translateY(${((1 - ca(1.7)) * 20).toFixed(1)}px)`}}>
            <div style={{fontFamily: SF, fontSize: 46, fontWeight: 700, lineHeight: 1.25}}>
              <B text={world.climax.end} />
            </div>
            <div style={{...cap, marginTop: 24, fontSize: 36}}><B text={`${POS_TAIL[pos]} ${END.sub}`} /></div>
          </div>
        )}
        {id === 'climax' && monthFlourish && (
          <div style={{position: 'absolute', top: 560, left: 0, right: 0, opacity: ca(2.4, 0.5), transform: `scale(${1 + 0.25 * (1 - ca(2.4, 0.6))})`}}>
            <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 60, letterSpacing: '0.02em'}}>
              {hitM ? (
                <>
                  {cal.name}, <span style={{color: CORAL}}>done.</span>
                </>
              ) : (
                <>
                  {cal.name}: <span style={{color: CORAL}}>{cal.sessions}</span> of {cal.target}.
                </>
              )}
            </div>
          </div>
        )}
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 300, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', opacity: leaving ? 0 : 1}}>
        {!lastScr ? (
          <div style={{fontFamily: SF, fontSize: 30, fontWeight: 600, letterSpacing: '0.04em', color: rgba(white, showHint ? 0.45 + 0.25 * Math.sin(lt * 4) : 0), display: 'flex', alignItems: 'center', gap: 14}}>
            {id === 'month' && MS.pick && !picked ? 'Pick a target' : 'Tap to continue'}
            <svg width={22} height={22} viewBox="0 0 22 22" style={{opacity: showHint ? 1 : 0}}>
              <path d="M7 3l8 8-8 8" fill="none" stroke={rgba(white, 0.6)} strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </div>
        ) : (
          <div style={{position: 'relative', overflow: 'hidden', fontFamily: SF, fontWeight: 700, fontSize: 38, color: '#111', background: white, borderRadius: 60, padding: '30px 80px', opacity: a(0.4)}}>
            <div style={{position: 'absolute', left: 0, top: 0, bottom: 0, width: `${(sealT != null ? 1 : Math.min(1, taps / N)) * 100}%`, background: CORAL}} />
            <span style={{position: 'relative'}}>{sealT != null ? END.button : taps > 0 ? (taps >= N - 1 ? 'One more' : world.climax.mid) : world.climax.idle}</span>
          </div>
        )}
      </div>
    </div>
  );
};
