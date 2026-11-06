/**
 * Ridge done screens, set in the day's world. Paper at the top for the words and numbers, the painted
 * world below.
 *   Verified    the world as you arrive; today's session in three numbers
 *   Today       the session in detail
 *   This week   the week counted in the world's own terms (stones, rings, lanterns, stars...)
 *   Month       first week: pick the month's target; last week: the month so far (first/last weeks only)
 *   How far     the long run, in the world
 *   Finish      a few taps that complete today's world: raise the sun, break the rock, skip the stone,
 *               grow the pine, light the beacon, send the lanterns, connect the stars
 */
import React, {useLayoutEffect, useRef} from 'react';
import {CORAL, Theme, clamp01, eo, eo5} from '../hero2/paint';
import {SF} from '../hero2/card';
import {AVG_HR, PEAK_HR, SESSION} from '../hero4/story4';
import {DISPLAY, Icon, Swoosh, Words} from '../hero8/card8';
import {MARKER, Pebble, Rich10} from './card12';
import {grow} from '../hero11/scenes11';
import {DAYS, DONE_DATA, MINS, POS_WEEK, Pos} from '../hero11/copy11';
import {boulderGeom, drawChips} from '../hero10/wash';
import {Painter3, Scene3} from './wash3';
import {DONE12, monthScreen} from './copy12';
import {Day, MONTH_TARGETS, MonthCal, MonthPos, POS_TAIL, WORLDS, endFor, tapsFor12} from './days12';
import {WSEED, ease} from './scenes12';
import {CFG_R, ScrId, TALLY} from './screens12';

export const BOX_W = 1080, BOX_H = 1920;
let mctx: CanvasRenderingContext2D | null = null;
const measure900 = (txt: string, size: number) => {
  if (!mctx) mctx = document.createElement('canvas').getContext('2d');
  mctx!.font = `900 ${size}px ${DISPLAY}`;
  return mctx!.measureText(txt).width;
};

const WEEKS = [38, 81, 129, 140, 95, 152, 158];
const HRS = Array.from({length: 60}, (_, i) => {
  const u = i / 59;
  const warm = Math.min(1, u / 0.12);
  const sets = Math.sin(u * Math.PI * 9) * 9 * (u > 0.1 ? 1 : 0);
  const fin = u > 0.82 ? Math.sin(((u - 0.82) / 0.18) * Math.PI) * 22 : 0;
  return 92 + warm * 36 + sets + fin + Math.sin(i * 1.7) * 2;
});
const q = (x: number, k: number) => Math.round(x * k) / k;

type SC = {id: ScrId; day: Day; lt: number; t: number; pos: Pos; taps: number; tapTimes: number[]; tapAt: number | null; sealT: number | null; N: number; mp: MonthPos};

/** how far the finish has got: taps so far, the newest one easing in */
const hv = (c: SC) => (c.sealT != null ? 1 : c.taps === 0 ? 0 : (c.taps - 1 + ease((c.t - (c.tapAt ?? c.t)) / 0.35)) / c.N);

const sceneAt = (c: SC): Scene3 => {
  const D = DONE_DATA[c.pos];
  const PW = POS_WEEK[c.pos];
  const {day, lt, t} = c;
  const g = grow(D.day);
  const base: Scene3 = {kind: 'ridge', seed: WSEED[day], tree: g, cracks: 0, broken: 0, rubble: Math.min(7, Math.floor(D.sessions / 3)), sun: 0.5, night: 0, mist: 0.8, rain: 0, peak: 1, birds: 0};
  const last = c.pos === 'last';
  const S = (p: Partial<Scene3>): Scene3 => ({...base, ...p});
  const done = PW.done - 1 + ease((lt - 0.4) / 0.7); // this week's count, today's arriving
  switch (c.id) {
    case 'verified':
      return [
        S({kind: 'sunrise', sun: -0.15 + 0.25 * ease(lt / 2), birds: 3}),
        S({kind: 'ridge', cracks: 4, sun: 0.5, mist: 0.7}),
        S({kind: 'lake', sun: 0.5, mist: 0.8, ripples: 1}),
        S({kind: 'ridge', noRock: true, tree: Math.max(0.3, g - 0.2), sun: 0.45, mist: 0.8}),
        S({kind: 'path', trail: 0.6 + 0.21 * ease((lt - 0.2) / 1.6), sun: 0.5, birds: 2}),
        S({kind: 'sunset', sun: 0.35, birds: 2}),
        S({kind: 'night', night: 1, charge: 0.98, stars: 0, mist: 0.5}),
      ][day];
    case 'today':
      return [
        S({kind: 'sunrise', sun: 0.4, mist: 1.1, birds: 2}),
        S({kind: 'cairn', stones: PW.done - 1, sun: 0.5}),
        S({kind: 'lake', drip: true, sun: 0.45, mist: 0.9}),
        S({kind: 'fog', mist: 1, peak: 0.5}),
        S({kind: 'path', trail: 0.5, sun: 0.5}),
        S({kind: 'beach', steps: 0.6, sun: 0.4}),
        S({kind: 'night', night: 1, charge: 0.6, stars: 3, mist: 0.5}),
      ][day];
    case 'week':
      return [
        S({kind: 'sunrise', sun: -0.25 + 0.17 * done, birds: Math.round(done)}),
        S({kind: 'cairn', stones: done, sun: last ? 0.6 : 0.5, birds: last ? 5 : 0}),
        S({kind: 'lake', sun: 0.5, mist: 0.8, ripples: Math.round(done)}),
        S({kind: 'ridge', noRock: true, night: 0.5, sun: 0.1, mist: 0.8, fireflies: Math.round(done * 2)}),
        S({kind: 'path', trail: 0.81 * (done / 5), sun: 0.5}),
        S({kind: 'sunset', sun: 0.15, night: 0.25, lanterns: Array.from({length: PW.done}, (_, i) => t - lt + 0.4 + i * 0.25)}),
        S({kind: 'night', night: 1, charge: 0.98, stars: done, mist: 0.5}),
      ][day];
    case 'month':
      return c.mp === 'first'
        ? [
            S({kind: 'sunrise', sun: 0.05, birds: 2}),
            S({kind: 'cairn', stones: 0, sun: 0.35, mist: 0.9}),
            S({kind: 'lake', sun: 0.25, mist: 1.1}),
            S({kind: 'ridge', noRock: true, sun: 0.3, mist: 1.2}),
            S({kind: 'path', trail: 0.02, sun: 0.35}),
            S({kind: 'beach', sun: 0.3, birds: 2}),
            S({kind: 'night', night: 1, charge: 0.1, stars: 0, shoot: t - lt + 1.2, mist: 0.5}),
          ][day]
        : [
            S({kind: 'sunrise', sun: 0.6, birds: 6}),
            S({kind: 'cairn', stones: 5, sun: 0.55}),
            S({kind: 'lake', sun: 0.55, mist: 0.7, ripples: 5}),
            S({kind: 'ridge', noRock: true, tree: Math.min(1, g + 0.1), sun: 0.5}),
            S({kind: 'path', trail: 1, beacon: 0.5, sun: 0.45}),
            S({kind: 'sunset', sun: 0.08, night: 0.25}),
            S({kind: 'night', night: 1, charge: 0.98, stars: 7, starLines: 1, mist: 0.5}),
          ][day];
    case 'far': {
      const p = ease((lt - 0.2) / 1.6);
      const k = D.day / 66;
      return [
        S({kind: 'sunrise', sun: -0.3 + 0.9 * k * p, birds: 3}),
        S({kind: 'ridge', sun: 0.55, mist: 0.7, rubble: Math.round(7 * p), cracks: 0}),
        S({kind: 'lake', boatX: 0.12 + 0.76 * k * p, sun: 0.5, mist: 0.7}),
        S({kind: 'ridge', noRock: true, tree: q(0.12 + (g - 0.12) * p, 20), sun: 0.5, mist: 0.7}),
        S({kind: 'path', trail: 0.81 * eo((lt - 0.2) / 1.6) + (lt > 1.8 ? 0.19 * k * eo((lt - 1.8) / 0.8) : 0), sun: 0.5, birds: 3}),
        S({kind: 'beach', steps: k * p, sun: 0.4}),
        S({kind: 'night', night: 1, charge: 0.98, stars: 7 * k * p, mist: 0.5}),
      ][day];
    }
    case 'climax': {
      const h = hv(c);
      const s = c.sealT;
      const since = s != null ? t - s : -1;
      switch (day) {
        case 0:
          return S({kind: 'sunrise', sun: s != null ? 0.45 + 0.25 * ease(since / 0.8) : -0.35 + 0.8 * h, birds: s != null ? 5 : 2, flash: s, burst: s, burstAt: 'sun'});
        case 1:
          return S({kind: 'ridge', cracks: s != null ? 5 : h * 5, broken: s != null ? ease(Math.min(1, since / 0.55)) : 0, sun: last ? 0.6 : 0.5, mist: 0.8});
        case 2:
          return S({kind: 'lake', sun: 0.5, mist: 0.8, skipN: c.N, skips: c.tapTimes, skipDone: s != null ? s + 0.35 : null});
        case 3: {
          const g0 = Math.max(0.3, g - 0.2), g1 = Math.min(1, g + 0.08);
          return S({kind: 'ridge', noRock: true, tree: q(g0 + (g1 - g0) * h, 50), sun: 0.5, mist: 0.75, burst: s, burstAt: 'tree', flash: s});
        }
        case 4:
          return S({kind: 'path', trail: 0.81 + 0.19 * h, sun: 0.45, beacon: s != null ? ease(since / 1) : 0, flash: s != null ? s + 0.1 : null});
        case 5:
          return S({kind: 'sunset', sun: 0.12, night: 0.25, lanterns: s != null ? [...c.tapTimes, s + 0.25, s + 0.5] : c.tapTimes, flash: s});
        default:
          return S({kind: 'night', night: 1, charge: 0.98, stars: s != null ? 7 : Math.min(7, c.taps === 0 ? 0 : c.taps - 1 + ease((t - (c.tapAt ?? t)) / 0.3)), starLines: s != null ? ease(since / 1) : 0, shoot: s != null ? s + 0.7 : null, mist: 0.5});
      }
    }
  }
};

type Props = {ids: ScrId[]; idx: number; lt: number; t: number; w: number; h: number; pxScale: number; theme: Theme; showHint: boolean; leaving: boolean; tapTimes: number[]; sealT: number | null; pos: Pos; day: Day; mp: MonthPos; cal: MonthCal; picked: boolean; dyn?: boolean};

export const Story12: React.FC<Props> = ({ids, idx, lt, t, w, h, pxScale, theme, showHint, leaving, tapTimes, sealT, pos, day, mp, cal, picked, dyn}) => {
  const id = ids[idx];
  const N = tapsFor12(day, pos);
  const taps = tapTimes.length;
  const tapAt = taps ? tapTimes[taps - 1] : null;
  const hits = Math.min(1, taps / N);
  const D = DONE_DATA[pos];
  const PW = POS_WEEK[pos];
  const V = DONE12[pos][day];
  const world = WORLDS[day];
  const END = endFor(pos, day);
  const MS = monthScreen(mp, pos, cal);
  const cv = useRef<HTMLCanvasElement>(null);
  const painter = useRef<Painter3 | null>(null);
  const dark = theme === 'dark';
  const ox = (w - BOX_W) / 2, oy = (h - BOX_H) / 2;
  const sc: SC = {id, day, lt, t, pos, taps, tapTimes, tapAt, sealT, N, mp};
  useLayoutEffect(() => {
    if (!painter.current) painter.current = new Painter3();
    const cw = Math.round(w * pxScale), ch = Math.round(h * pxScale);
    const el = cv.current!;
    if (el.width !== cw || el.height !== ch) {
      el.width = cw;
      el.height = ch;
    }
    const ctx = el.getContext('2d')!;
    const S = sceneAt(sc);
    painter.current.render3(ctx, cw, ch, S, theme, t);
    // the rock (stone days): chips on every hit, then the break
    if (id === 'climax' && day === 1) {
      const B = boulderGeom(cw, ch, S.seed);
      if (sealT == null && tapAt != null) drawChips(ctx, cw, ch, S.seed + taps * 3, [B.cx + (taps % 2 ? -1 : 1) * B.bw * 0.15, B.by - B.bh * 0.55], (t - tapAt) * 1.6, theme);
      if (sealT != null) {
        drawChips(ctx, cw, ch, S.seed, [B.cx, B.by - B.bh * 0.6], t - sealT, theme);
        drawChips(ctx, cw, ch, S.seed + 4, [B.cx - B.bw * 0.2, B.by - B.bh * 0.35], t - sealT - 0.06, theme);
        drawChips(ctx, cw, ch, S.seed + 9, [B.cx + B.bw * 0.22, B.by - B.bh * 0.3], t - sealT - 0.1, theme);
      }
    }
  });

  const paper = dark ? '14,14,16' : '246,246,244';
  const ink = dark ? '#F4F4F2' : '#0E0E10';
  const ink2 = dark ? 'rgba(244,244,242,.66)' : 'rgba(14,14,16,.66)';
  const line = dark ? 'rgba(255,255,255,.14)' : 'rgba(0,0,0,.1)';
  const a = (at: number, d = 0.35) => eo((lt - at) / d);
  const up = (at: number, d = 0.35) => ({opacity: a(at, d), transform: `translateY(${((1 - a(at, d)) * 16).toFixed(1)}px)`});
  const roll = (to: number, at: number, d = 1.1) => Math.round(eo5((lt - at) / d) * to);
  const lastScr = idx === ids.length - 1;
  const time = (() => {
    const s = Math.floor(eo5((lt - 0.15) / 1.2) * SESSION.minutes * 60);
    return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  })();
  const monthFlourish = mp === 'last' && pos === 'last';
  const flourish = cal.sessions >= cal.target ? `${cal.name}, done.` : `${cal.name}: ${cal.sessions} of ${cal.target}.`;
  const heads: Record<ScrId, {eyebrow: string; icon: 'check' | 'clock' | 'flame' | 'path' | 'dot' | 'sun'; title: string; sub: string; note: string}> = {
    verified: {eyebrow: V.eyebrow, icon: 'check', title: V.title, sub: V.sub, note: V.note ?? ''},
    today: {eyebrow: 'TODAY’S SESSION', icon: 'clock', title: '', sub: '**+6:10** on your last session.', note: ''},
    week: {eyebrow: 'THIS WEEK', icon: 'flame', title: PW.s2.title, sub: PW.s2.sub, note: PW.s2.note},
    month: {eyebrow: MS.eyebrow, icon: mp === 'first' ? 'sun' : 'flame', title: MS.title, sub: MS.sub, note: ''},
    far: {eyebrow: 'HOW FAR YOU’VE COME', icon: 'path', title: 'Week 7.', sub: 'From **38 min** in week 1 to **2h 38m** this week.', note: 'Look how far.'},
    climax:
      sealT != null
        ? {eyebrow: pos === 'last' ? 'WEEK COMPLETE' : 'SESSIONS', icon: 'check', title: '', sub: END.sub, note: monthFlourish ? flourish : ''}
        : {eyebrow: pos === 'last' ? world.climax.lastEyebrow : world.climax.eyebrow, icon: 'dot', title: world.climax.title, sub: world.climax.sub(N), note: ''},
  };
  const hd = heads[id];
  const tSize = Math.min(158, (158 * 900) / measure900(hd.title || 'x', 158));
  const statRow = (items: [string | number, string, boolean?][], at: number) => (
    <div style={{display: 'flex'}}>
      {items.map(([v, l, coral], k) => (
        <div key={k} style={{flex: 1, paddingLeft: k ? 26 : 0, borderLeft: k ? `2px solid ${line}` : 'none', ...up(at + k * 0.12)}}>
          <div style={{fontFamily: SF, fontWeight: 700, fontSize: 24, letterSpacing: '0.1em', color: ink2}}>{l}</div>
          <div style={{fontFamily: DISPLAY, fontWeight: 800, fontSize: 76, lineHeight: 1.05, color: coral ? CORAL : ink, fontVariantNumeric: 'tabular-nums'}}>{v}</div>
        </div>
      ))}
    </div>
  );
  const note = (txt: string, at: number) => (
    <div style={{fontFamily: SF, fontWeight: 500, fontSize: 31, lineHeight: 1.36, color: ink2, maxWidth: 900, borderLeft: `4px solid ${ink}`, paddingLeft: 24, ...up(at)}}>
      <Rich10 text={txt} ink={ink} ink2={ink2} />
    </div>
  );
  const sealAt = sealT != null ? sealT - (t - lt) : 0; // seal time in this screen's clock
  const shake = id === 'climax' && day === 1 && tapAt != null && sealT == null ? `translateX(${(Math.exp(-(t - tapAt) * 9) * Math.sin((t - tapAt) * 70) * (6 + taps * 2)).toFixed(2)}px)` : sealT != null && id === 'climax' && (day === 1 || day === 4) ? `translateY(${(Math.exp(-(t - sealT) * 6) * Math.sin((t - sealT) * 50) * (day === 1 ? 14 : 6)).toFixed(2)}px)` : undefined;
  // Dynamic: every screen opens on a pull-back; every tap on the finish punches in; the finish lands hard
  const reduceM = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  const dz = dyn && !reduceM;
  const camS = dz ? 1 + 0.1 * (1 - eo(lt / 0.9)) + (id === 'climax' && tapAt != null && sealT == null ? 0.035 * Math.exp(-(t - tapAt) * 7) : 0) + (id === 'climax' && sealT != null ? 0.07 * Math.exp(-(t - sealT) * 4) : 0) : 1;
  const titleS = dz ? 1 + 0.22 * Math.exp(-lt * 6) * Math.cos(lt * 14) : 1;
  return (
    <div style={{position: 'relative', width: w, height: h, overflow: 'hidden', background: `rgb(${paper})`, color: ink}}>
      <canvas ref={cv} style={{position: 'absolute', inset: 0, width: w, height: h, display: 'block', transform: `${shake ?? ''} scale(${camS.toFixed(4)})`, transformOrigin: '50% 75%'}} />
      {dz && id === 'climax' && tapAt != null && t - tapAt < 0.7 && (
        <div style={{position: 'absolute', left: '50%', top: '72%', width: (t - tapAt) * 1500, height: (t - tapAt) * 1500, marginLeft: -(t - tapAt) * 750, marginTop: -(t - tapAt) * 750, borderRadius: '50%', boxShadow: `inset 0 0 0 ${Math.max(1, 6 * (1 - (t - tapAt) / 0.7)).toFixed(1)}px ${sealT != null && t - sealT < 0.7 ? CORAL : ink}`, opacity: 0.5 * (1 - (t - tapAt) / 0.7), pointerEvents: 'none'}} />
      )}
      {dz && id === 'climax' && sealT != null && t - sealT < 0.6 && <div style={{position: 'absolute', inset: 0, background: dark ? '#FFFFFF' : '#FFFFFF', opacity: 0.55 * (1 - (t - sealT) / 0.6), pointerEvents: 'none'}} />}
      <div style={{position: 'absolute', left: 0, right: 0, top: 0, height: oy + (id === 'month' ? 1500 : 1240), background: `linear-gradient(180deg, rgba(${paper},1) 0%, rgba(${paper},1) 62%, rgba(${paper},.75) 80%, rgba(${paper},0) 100%)`}} />
      <div style={{position: 'absolute', top: Math.max(oy, 0) + 90, left: 60, right: 60, display: 'flex', gap: 12, opacity: leaving ? 0 : 1}}>
        {ids.map((sid, i) => (
          <div key={i} style={{flex: 1, height: 6, borderRadius: 3, background: line, overflow: 'hidden'}}>
            <div style={{height: '100%', background: ink, width: `${(i < idx ? 1 : i > idx ? 0 : clamp01(lt / CFG_R[sid].settle)) * 100}%`}} />
          </div>
        ))}
      </div>
      <div style={{position: 'absolute', left: ox, top: oy, width: BOX_W, height: BOX_H}}>
        <div key={'t' + id} style={{position: 'absolute', left: 80, right: 80, top: 210}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 16, fontFamily: SF, fontWeight: 800, fontSize: 30, letterSpacing: `${0.06 + (1 - a(0.05)) * 0.2}em`, opacity: a(0.05)}}>
            <Icon k={hd.icon} color={ink} bg={`rgb(${paper})`} s={40} />
            {hd.eyebrow}
          </div>
          <div style={{fontFamily: DISPLAY, fontWeight: 900, fontSize: id === 'today' ? 210 : tSize, lineHeight: 1.0, letterSpacing: '-0.035em', marginTop: 14, fontVariantNumeric: 'tabular-nums', transform: `scale(${titleS.toFixed(4)})`, transformOrigin: '0% 80%'}}>
            {id === 'climax' && sealT != null ? (
              <span style={{display: 'inline-flex', alignItems: 'baseline', gap: 24}}>
                <span style={{display: 'inline-block', height: '1em', overflow: 'hidden', lineHeight: 1, verticalAlign: 'bottom'}}>
                  <span style={{display: 'block', lineHeight: 1, transform: `translateY(${(-eo((t - sealT - 0.45) / 0.5) * 50).toFixed(2)}%)`}}>
                    <span style={{display: 'block'}}>{D.sessions - 1}</span>
                    <span style={{display: 'block'}}>{D.sessions}</span>
                  </span>
                </span>
                <span style={{fontSize: '0.3em', fontWeight: 800, letterSpacing: '0', opacity: eo((t - sealT - 0.8) / 0.4)}}>{pos === 'last' ? 'sessions. Week done.' : 'and counting.'}</span>
              </span>
            ) : id === 'today' ? (
              <span style={{opacity: clamp01(lt * 6)}}>{time}</span>
            ) : (
              <Words text={hd.title} f={lt * 30} at={3} size={tSize} color={ink} maxW={940} />
            )}
          </div>
          <div style={{fontFamily: SF, fontSize: 44, lineHeight: 1.22, marginTop: 14, ...up(0.45)}}>
            <Rich10 text={hd.sub} ink={ink} ink2={ink2} />
          </div>
        </div>
        <div key={'m' + id} style={{position: 'absolute', left: 80, right: 80, top: id === 'today' ? 700 : id === 'month' ? 560 : 660}}>
          {id === 'verified' && (
            <>
              {statRow(
                [
                  [time, 'TIME'],
                  [roll(AVG_HR, 0.6), 'AVG HEART RATE'],
                  [roll(SESSION.kcal, 0.75), 'CALORIES'],
                ],
                0.5,
              )}
              <div style={{marginTop: 34}}>{note('Small wins are the strongest daily motivator: **76%** of people’s best days involved visible progress.', 1.2)}</div>
            </>
          )}
          {id === 'today' && (
            <>
              <div style={{fontFamily: SF, fontWeight: 700, fontSize: 24, letterSpacing: '0.1em', color: ink2, ...up(0.2)}}>HEART RATE</div>
              <svg width={920} height={230} viewBox="0 0 920 230" style={{display: 'block', marginTop: 10, overflow: 'visible'}}>
                {(() => {
                  const p = eo((lt - 0.25) / 1.1);
                  const n = Math.max(2, Math.floor(HRS.length * p));
                  const pts = HRS.slice(0, n).map((v, i) => [(i / (HRS.length - 1)) * 920, 220 - ((v - 80) / 100) * 210] as [number, number]);
                  const dd = pts.map((qq, i) => `${i ? 'L' : 'M'}${qq[0].toFixed(1)} ${qq[1].toFixed(1)}`).join(' ');
                  const peakI = HRS.indexOf(Math.max(...HRS));
                  return (
                    <>
                      {[0, 1, 2].map((k) => (
                        <line key={k} x1={0} x2={920} y1={20 + k * 100} y2={20 + k * 100} stroke={line} strokeWidth={2} />
                      ))}
                      <path d={`${dd} L${pts[pts.length - 1][0]} 222 L0 222 Z`} fill={dark ? 'rgba(255,255,255,.1)' : 'rgba(0,0,0,.07)'} />
                      <path d={dd} fill="none" stroke={ink} strokeWidth={4} strokeLinejoin="round" />
                      {n > peakI && <circle cx={(peakI / (HRS.length - 1)) * 920} cy={220 - ((HRS[peakI] - 80) / 100) * 210} r={10} fill={CORAL} />}
                    </>
                  );
                })()}
              </svg>
              <div style={{marginTop: 24}}>
                {statRow(
                  [
                    [roll(AVG_HR, 0.6), 'AVG BPM'],
                    [roll(PEAK_HR, 0.7), 'PEAK BPM'],
                    [roll(SESSION.kcal, 0.8), 'CALORIES'],
                  ],
                  0.6,
                )}
              </div>
              <div style={{display: 'flex', gap: 14, marginTop: 30, flexWrap: 'wrap'}}>
                {['2nd longest this month', 'Best week since week 3'].map((txt, k) => (
                  <span key={k} style={{display: 'inline-flex', alignItems: 'center', gap: 10, padding: '14px 22px', borderRadius: 40, background: dark ? 'rgba(255,255,255,.08)' : 'rgba(0,0,0,.05)', fontFamily: SF, fontWeight: 700, fontSize: 28, ...up(1.1 + k * 0.15)}}>
                    <Icon k="check" color={ink} bg={`rgb(${paper})`} s={30} />
                    {txt}
                  </span>
                ))}
              </div>
            </>
          )}
          {id === 'week' && (
            <>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                {DAYS.map((dn, k) => {
                  const m = k < PW.done ? MINS[k] : 0;
                  const lit = m > 0 && a(0.5 + k * 0.08, 0.3) > 0.5;
                  return (
                    <div key={k} style={{width: 110, textAlign: 'center', ...up(0.3 + k * 0.06)}}>
                      <div style={{display: 'flex', justifyContent: 'center'}}>
                        <Pebble s={86} on={lit} ink={ink} k={k} />
                      </div>
                      <div style={{marginTop: 12, fontFamily: DISPLAY, fontWeight: 800, fontSize: 30, color: m ? ink : ink2}}>{m ? `${m}m` : '·'}</div>
                      <div style={{marginTop: 4, fontFamily: SF, fontWeight: 800, fontSize: 22, letterSpacing: '0.1em', color: k === PW.today ? ink : ink2, textDecoration: k === PW.today ? 'underline' : 'none', textUnderlineOffset: 6}}>{dn}</div>
                    </div>
                  );
                })}
              </div>
              <div style={{marginTop: 36}}>
                {statRow(
                  [
                    [PW.total, 'THIS WEEK'],
                    [String(PW.done), 'SESSIONS'],
                    [String(D.weekStreak), 'WEEK STREAK'],
                  ],
                  0.9,
                )}
              </div>
              <div style={{marginTop: 34}}>{note(PW.s2.research, 1.3)}</div>
            </>
          )}
          {id === 'month' && (
            <>
              <div style={{display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', rowGap: 4, ...up(0.15)}}>
                {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((dn, k) => (
                  <div key={'h' + k} style={{textAlign: 'center', fontFamily: SF, fontWeight: 800, fontSize: 20, letterSpacing: '0.1em', color: ink2}}>
                    {dn}
                  </div>
                ))}
                {Array.from({length: cal.lead}, (_, k) => (
                  <div key={'b' + k} />
                ))}
                {(() => {
                  let fut = 0;
                  return cal.cells.map((cc, i) => {
                    if (cc === 'future') fut++;
                    const planned = cc === 'future' && (picked || mp === 'last' || !MS.pick) && cal.sessions + fut <= cal.target;
                    const on = a(0.25 + i * 0.022, 0.25);
                    return (
                      <div key={i} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2, opacity: 0.25 + 0.75 * on}}>
                        {cc === 'today' ? (
                          <div style={{width: 46, height: 34, borderRadius: 17, background: CORAL, transform: `scale(${1 + 0.08 * Math.sin(lt * 4)})`}} />
                        ) : (
                          <Pebble s={46} on={cc === 'done'} ink={cc === 'miss' ? ink2 : ink} k={i} />
                        )}
                        <div style={{fontFamily: SF, fontWeight: 700, fontSize: 15, color: cc === 'today' ? ink : planned ? ink : ink2, opacity: cc === 'future' && !planned ? 0.5 : 1}}>{i + 1}</div>
                      </div>
                    );
                  });
                })()}
              </div>
              <div style={{marginTop: 26}}>
                {MS.pick ? (
                  <div style={{display: 'flex', gap: 16, pointerEvents: 'auto', ...up(0.9)}}>
                    {MONTH_TARGETS.map((m) => {
                      const sel = picked && cal.target === m.n;
                      return (
                        <div key={m.n} data-pick={m.n} style={{flex: 1, padding: '18px 0 16px', borderRadius: 28, textAlign: 'center', background: sel ? ink : 'transparent', color: sel ? `rgb(${paper})` : ink, boxShadow: sel ? 'none' : `inset 0 0 0 3px ${line}`, cursor: 'pointer'}}>
                          <div style={{fontFamily: DISPLAY, fontWeight: 900, fontSize: 64, lineHeight: 1}}>{m.n}</div>
                          <div style={{fontFamily: SF, fontWeight: 800, fontSize: 20, letterSpacing: '0.12em', marginTop: 6, opacity: 0.75}}>{m.label.toUpperCase()}</div>
                        </div>
                      );
                    })}
                  </div>
                ) : mp === 'last' ? (
                  statRow(
                    [
                      [roll(cal.sessions, 0.8), 'SESSIONS'],
                      [`${Math.floor(cal.minutes / 60)}h`, 'ON THE FLOOR'],
                      [`+${cal.sessions - cal.lastMonth}`, 'VS LAST MONTH', true],
                    ],
                    0.8,
                  )
                ) : (
                  statRow(
                    [
                      [roll(cal.sessions, 0.8), 'SESSIONS'],
                      [String(cal.target), 'TARGET'],
                      [String(Math.max(0, cal.target - cal.sessions)), 'TO GO'],
                    ],
                    0.8,
                  )
                )}
              </div>
              <div style={{marginTop: 26}}>{note(MS.research, 1.2)}</div>
            </>
          )}
          {id === 'far' && (
            <>
              <div style={{fontFamily: SF, fontWeight: 700, fontSize: 24, letterSpacing: '0.1em', color: ink2, ...up(0.2)}}>TIME EACH WEEK</div>
              <svg width={920} height={250} viewBox="0 0 920 250" style={{display: 'block', marginTop: 10, overflow: 'visible'}}>
                {(() => {
                  const p = eo((lt - 0.3) / 1.2);
                  const pts = WEEKS.map((m, i) => [30 + (i / (WEEKS.length - 1)) * 860, 210 - (m / 170) * 190] as [number, number]);
                  const n = Math.max(1, Math.ceil(WEEKS.length * p));
                  const dd = pts.slice(0, n).map((qq, i) => `${i ? 'L' : 'M'}${qq[0]} ${qq[1]}`).join(' ');
                  return (
                    <>
                      <line x1={0} x2={920} y1={212} y2={212} stroke={line} strokeWidth={2} />
                      <path d={dd} fill="none" stroke={ink} strokeWidth={4} strokeLinejoin="round" />
                      {pts.slice(0, n).map((qq, i) => (
                        <circle key={i} cx={qq[0]} cy={qq[1]} r={i === WEEKS.length - 1 ? 12 : 8} fill={i === WEEKS.length - 1 ? CORAL : ink} />
                      ))}
                      {pts.map((qq, i) => (
                        <text key={'l' + i} x={qq[0]} y={244} textAnchor="middle" fontFamily={SF} fontWeight={700} fontSize={22} fill={ink2}>
                          W{i + 1}
                        </text>
                      ))}
                    </>
                  );
                })()}
              </svg>
              <div style={{marginTop: 30}}>
                {statRow(
                  [
                    [roll(D.sessions, 0.8), 'SESSIONS'],
                    [roll(D.sessions - 1, 0.9), TALLY[day]],
                    [`${D.day}/66`, 'DAYS'],
                  ],
                  0.8,
                )}
              </div>
            </>
          )}
          {id === 'climax' && sealT == null && (
            <div style={{display: 'flex', gap: 16, ...up(0.5)}}>
              {Array.from({length: N}, (_, k) => (
                <div key={k} style={{width: 34, height: 34, borderRadius: 17, background: k < taps ? ink : 'transparent', boxShadow: k < taps ? 'none' : `inset 0 0 0 3px ${ink2}`, transform: `scale(${k === taps - 1 && tapAt != null ? 1 + 0.4 * Math.max(0, 1 - (t - tapAt) * 4) : 1})`}} />
              ))}
            </div>
          )}
          {id === 'climax' && sealT != null && note(`${world.climax.end} ${POS_TAIL[pos]}`, 0.9 + sealAt)}
        </div>
        {hd.note && (
          <div style={{position: 'absolute', left: 80, top: 1190, transform: 'rotate(-5deg)', transformOrigin: '0 0', textAlign: 'left'}}>
            <div style={id === 'climax' ? {opacity: eo((t - (sealT ?? t)) / 0.4 - 3), transform: `scale(${1 + 0.4 * (1 - eo((t - (sealT ?? t) - 1.2) / 0.5))})`, transformOrigin: '0 50%'} : up(1.0)}>
              <div style={{fontFamily: MARKER, fontSize: id === 'climax' ? 84 : 64, lineHeight: 1, color: ink, textTransform: 'uppercase'}}>{hd.note}</div>
              <div style={{display: 'flex', justifyContent: 'flex-start', marginTop: 6}}>
                <Swoosh p={id === 'climax' ? eo((t - (sealT ?? t) - 1.5) / 0.5) : eo((lt - 1.2) / 0.5)} color={id === 'climax' ? CORAL : ink} w={id === 'climax' ? 360 : 260} />
              </div>
            </div>
          </div>
        )}
      </div>
      <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 250, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', opacity: leaving ? 0 : 1}}>
        {!lastScr ? (
          <div style={{padding: '14px 28px', borderRadius: 40, background: 'rgba(0,0,0,.35)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)', fontFamily: SF, fontSize: 28, fontWeight: 700, color: `rgba(255,255,255,${showHint ? 0.75 + 0.2 * Math.sin(lt * 4) : 0})`, opacity: showHint ? 1 : 0}}>
            {id === 'month' && MS.pick && !picked ? 'Pick a target' : 'Tap to continue ›'}
          </div>
        ) : (
          <div style={{position: 'relative', overflow: 'hidden', padding: '28px 50px', borderRadius: 80, background: dark ? '#F4F4F2' : '#0E0E10', color: dark ? '#0E0E10' : '#F6F6F4', fontFamily: SF, fontWeight: 800, fontSize: 34, opacity: a(0.4)}}>
            <div style={{position: 'absolute', left: 0, top: 0, bottom: 0, width: `${(sealT != null ? 1 : hits) * 100}%`, background: CORAL}} />
            <span style={{position: 'relative'}}>{sealT != null ? END.button : taps > 0 ? (taps >= N - 1 ? 'One more' : world.climax.mid) : world.climax.idle}</span>
          </div>
        )}
      </div>
    </div>
  );
};
