/**
 * The "Rush" done screen. Two acts:
 *   1. TODAY'S SESSION on black: time at the gym rolls up like a race clock, energy and heart rate
 *      count in, the heart-rate trace draws itself and passes the 20:00 proof line, apps unlock.
 *   2. SLAM: white flash, the trace becomes the mountain you just climbed, "Done." lands.
 * Design box 1080 × 1920, fitted (extra room goes to the edges).
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {hash} from '../../src/done/geom';
import {CORAL, LOOKS, Theme, blit, clamp01, eo, eo5, glow, mist, mix, paintRange, rgba, sky} from '../hero2/paint';
import {SF, SF_ROUNDED} from '../hero2/card';

export const BOX_W = 1080;
export const BOX_H = 1920;
export const fitComposition = (vw: number, vh: number) => {
  const a = vw / vh;
  if (a < BOX_W / BOX_H) return {w: BOX_W, h: Math.round(BOX_W / a / 2) * 2};
  return {w: Math.round((BOX_H * a) / 2) * 2, h: BOX_H};
};
/** the part of the screen that lands inside the card when it collapses */
export const FOCUS_Y = 760;

// ---------- the session ----------
export const SESSION = {minutes: 52 + 14 / 60, kcal: 418, start: '07:04', end: '07:56'};
const N = 314; // one sample per 10 s
const HR: number[] = (() => {
  const out: number[] = [];
  for (let i = 0; i < N; i++) {
    const m = (i / (N - 1)) * SESSION.minutes;
    let v: number;
    if (m < 7) v = 96 + (m / 7) * 34;
    else if (m > 46) v = 132 - ((m - 46) / 6.2) * 28;
    else {
      const c = (m - 7) % 5.2;
      const set = Math.floor((m - 7) / 5.2);
      const peak = 150 + [4, 8, 12, 18, 14, 10, 6, 4][set % 8];
      v = c < 1.7 ? 124 + (peak - 124) * Math.sin((c / 1.7) * Math.PI * 0.5) : peak - (peak - 122) * eo((c - 1.7) / 2.2);
    }
    out.push(v + (hash(i, 5) - 0.5) * 5 + Math.sin(i * 0.7) * 1.5);
  }
  return out;
})();
const SMOOTH = HR.map((_, i) => {
  let s = 0, n = 0;
  for (let k = -6; k <= 6; k++) {
    const j = i + k;
    if (j >= 0 && j < N) {
      s += HR[j];
      n++;
    }
  }
  return s / n;
});
const SM2 = HR.map((_, i) => {
  let s = 0, n = 0;
  for (let k = -16; k <= 16; k++) {
    const j = i + k;
    if (j >= 0 && j < N) {
      s += HR[j];
      n++;
    }
  }
  return s / n;
});
export const AVG_HR = Math.round(HR.reduce((a, b) => a + b, 0) / N);
export const PEAK_HR = Math.round(Math.max(...HR));
const PEAK_I = HR.indexOf(Math.max(...HR));
/** the session as a massif: one big shape around the hardest set, sets as shoulders, beats as rock */
const RIDGE = HR.map((v, i) => {
  const env = 0.12 + 0.88 * Math.exp(-Math.pow((i - PEAK_I) / (N * 0.24), 2)) + 0.3 * Math.exp(-Math.pow((i - N * 0.14) / (N * 0.09), 2));
  return 1690 - env * 470 - ((SM2[i] - 112) / 50) * 150 - (v - SMOOTH[i]) * 1.4;
});

// ---------- timeline (frames @ 30 fps) ----------
export const T = {ROLL0: 8, ROLL1: 70, UNLOCK: 76, SLAM: 92, READY: 124};
const STATS = [
  {at: 18, dur: 40},
  {at: 24, dur: 40},
  {at: 30, dur: 40},
];
/** 0 → 1 progress of the race clock: fast, then braking hard into the final number */
const rollP = (f: number) => eo5((f - T.ROLL0) / (T.ROLL1 - T.ROLL0));
const statP = (f: number, k: number) => eo5((f - STATS[k].at) / STATS[k].dur);

/** every haptic of the screen, precomputed: ticks get sparser as the clock brakes */
export const momentHaptics = (() => {
  const out: {f: number; kind: 'light' | 'medium' | 'heavy' | 'success'}[] = [{f: 2, kind: 'light'}];
  let lastBucket = 0;
  let passed20 = false;
  for (let f = T.ROLL0; f <= T.ROLL1; f++) {
    const mins = rollP(f) * SESSION.minutes;
    const b = Math.floor(mins / 3);
    if (b > lastBucket) {
      out.push({f, kind: 'light'});
      lastBucket = b;
    }
    if (!passed20 && mins >= 20) {
      out.push({f, kind: 'heavy'});
      passed20 = true;
    }
  }
  STATS.forEach((s) => out.push({f: s.at + s.dur - 6, kind: 'medium'}));
  out.push({f: T.ROLL1, kind: 'medium'}, {f: T.UNLOCK, kind: 'medium'}, {f: T.SLAM, kind: 'heavy'}, {f: T.SLAM + 1, kind: 'success'}, {f: T.SLAM + 4, kind: 'heavy'}, {f: T.SLAM + 16, kind: 'light'}, {f: T.READY, kind: 'light'});
  return out.sort((a, b) => a.f - b.f);
})();

const mmss = (mins: number) => {
  const s = Math.floor(mins * 60);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
};

type Props = {theme: Theme; f: number; w: number; h: number; showButton: boolean; pxScale: number; habitDay: number};

const BLACK = '#0A0A0B';
const TX0 = 70, TX1 = 1010; // trace x range

export const Moment3: React.FC<Props> = ({theme, f, w, h, showButton, pxScale, habitDay}) => {
  const look = LOOKS[theme];
  const cv = useRef<HTMLCanvasElement>(null);
  const ox = (w - BOX_W) / 2, oy = (h - BOX_H) / 2;
  const s = f - T.SLAM; // frames since the slam

  const layers = useMemo(() => {
    const x0 = -ox - 200, x1 = BOX_W + ox + 200, y0 = 900, y1 = BOX_H + oy + 60;
    const mk = (seed: number, depth: number, base: number, amp: number, peaks: {x: number; y: number; sl: number; sr: number}[], lit?: number, rim?: number) =>
      paintRange({spec: {depth, base, amp, wave: 320, detail: 9, seed, peaks}, depth, lit, rim}, look, 900, pxScale, x0, x1, y0, y1);
    return [mk(301, 0.1, 1250, 60, [{x: 240, y: 1130, sl: 0.6, sr: 0.7}]), mk(302, 0.42, 1360, 50, [{x: 900, y: 1170, sl: 0.7, sr: 0.6}, {x: 120, y: 1220, sl: 0.6, sr: 0.7}], 0.6, 1.8)];
  }, [look, pxScale, ox, oy]);

  const roll = rollP(f);
  const head = roll * (N - 1);
  const m = s >= 0 ? clamp01(springFast(s, 30, {damping: 13, stiffness: 120})) : 0; // trace → mountain morph
  const actA = s < 6 ? 1 - clamp01(s / 4) : 0; // act one fades under the flash

  useLayoutEffect(() => {
    const c = cv.current!;
    const pw = Math.round(w * pxScale), ph = Math.round(h * pxScale);
    if (c.width !== pw || c.height !== ph) {
      c.width = pw;
      c.height = ph;
    }
    const ctx = c.getContext('2d')!;
    ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    const shake = s >= 0 && s < 12 ? (1 - s / 12) * 20 : 0;
    // ---------- act one: black ----------
    if (actA > 0 || s < 0) {
      ctx.fillStyle = BLACK;
      ctx.fillRect(0, 0, w, h);
      ctx.save();
      ctx.translate(ox, oy);
      // heartbeat: a soft pulse behind the clock at the live heart rate
      const live = HR[Math.min(N - 1, Math.floor(head))];
      const beat = (f / 30) * (live / 60);
      const pulse = Math.pow(Math.max(0, Math.sin(beat * Math.PI * 2)), 8);
      glow(ctx, 540, 560, 520 + pulse * 60, '#FFFFFF', (0.05 + pulse * 0.06) * clamp01(f / 10));
      // grid
      ctx.strokeStyle = rgba('#FFFFFF', 0.06);
      ctx.lineWidth = 1;
      for (let k = 0; k <= 3; k++) {
        const y = 1120 + k * 100;
        ctx.beginPath();
        ctx.moveTo(TX0, y);
        ctx.lineTo(TX1, y);
        ctx.stroke();
      }
      // 20:00 proof line
      const x20 = TX0 + (20 / SESSION.minutes) * (TX1 - TX0);
      const passed = head / (N - 1) >= 20 / SESSION.minutes;
      ctx.setLineDash([6, 8]);
      ctx.strokeStyle = rgba(passed ? CORAL : '#FFFFFF', passed ? 0.9 : 0.25);
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(x20, 1100);
      ctx.lineTo(x20, 1440);
      ctx.stroke();
      ctx.setLineDash([]);
      // the trace
      const yA = (v: number) => 1420 - ((v - 90) / 85) * 300;
      const xA = (i: number) => TX0 + (i / (N - 1)) * (TX1 - TX0);
      const hi = Math.floor(head);
      if (hi > 0) {
        const area = ctx.createLinearGradient(0, 1100, 0, 1440);
        area.addColorStop(0, rgba('#FFFFFF', 0.22));
        area.addColorStop(1, rgba('#FFFFFF', 0));
        ctx.beginPath();
        ctx.moveTo(xA(0), 1440);
        for (let i = 0; i <= hi; i++) ctx.lineTo(xA(i), yA(HR[i]));
        ctx.lineTo(xA(hi), 1440);
        ctx.closePath();
        ctx.fillStyle = area;
        ctx.fill();
        ctx.beginPath();
        for (let i = 0; i <= hi; i++) i ? ctx.lineTo(xA(i), yA(HR[i])) : ctx.moveTo(xA(i), yA(HR[i]));
        ctx.strokeStyle = '#FFFFFF';
        ctx.lineWidth = 4;
        ctx.lineJoin = 'round';
        ctx.stroke();
        const hx = xA(hi), hy = yA(HR[hi]);
        glow(ctx, hx, hy, 70 + pulse * 30, '#FFFFFF', 0.6);
        ctx.beginPath();
        ctx.arc(hx, hy, 9, 0, Math.PI * 2);
        ctx.fillStyle = '#FFFFFF';
        ctx.fill();
      }
      ctx.restore();
    }
    // ---------- act two: the mountain ----------
    if (s >= 0) {
      ctx.save();
      ctx.globalAlpha = 1 - actA;
      ctx.fillStyle = look.card;
      ctx.fillRect(0, 0, w, h);
      ctx.translate(ox + Math.sin(f * 3.3) * shake, oy + Math.cos(f * 2.7) * shake * 0.6);
      sky(ctx, look, -oy, 1300, -ox, BOX_W + ox, BOX_H + oy * 2);
      const px = TX0 + (PEAK_I / (N - 1)) * (TX1 - TX0);
      const sunUp = eo(s / 40);
      glow(ctx, px + 140, 1180 - sunUp * 200, 560, look.sun, (look.dark ? 0.22 : 1) * (0.5 + 0.5 * sunUp));
      layers.forEach((L, i) => {
        const p = springFast(s - 2 - i * 2, 30, {damping: 15, stiffness: 110});
        blit(ctx, L, 0, (1 - p) * 260 * (0.4 + i * 0.4), clamp01((s - i * 2) / 6));
        if (i === 0) mist(ctx, look.fog, -ox, BOX_W + ox, 1290, 140, f, 311, 0.5, 0.8);
      });
      // the session, now a ridge: raw trace → smoothed, scaled up and pushed down to the bottom
      const YS = new Float32Array(N), XS = new Float32Array(N);
      for (let i = 0; i < N; i++) {
        const ya = 1420 - ((HR[i] - 90) / 85) * 300;
        YS[i] = ya + (RIDGE[i] - ya) * m;
        const xa = TX0 + (i / (N - 1)) * (TX1 - TX0);
        const xb = -ox - 40 + (i / (N - 1)) * (BOX_W + ox * 2 + 80);
        XS[i] = xa + (xb - xa) * m;
      }
      const yB = (i: number) => YS[i];
      const xB = (i: number) => XS[i];
      let top = Infinity;
      for (let i = 0; i < N; i++) top = Math.min(top, yB(i));
      const tone = mix(look.far, look.near, Math.pow(0.9, 1.35));
      const gr = ctx.createLinearGradient(0, top, 0, top + 620);
      gr.addColorStop(0, tone);
      gr.addColorStop(0.45, mix(tone, look.fog, 0.18));
      gr.addColorStop(1, mix(tone, look.fog, 0.42));
      ctx.beginPath();
      ctx.moveTo(xB(0), BOX_H + oy + 40);
      for (let i = 0; i < N; i++) ctx.lineTo(xB(i), yB(i));
      ctx.lineTo(xB(N - 1), BOX_H + oy + 40);
      ctx.closePath();
      ctx.fillStyle = gr;
      ctx.globalAlpha = (1 - actA) * clamp01(m * 1.4);
      ctx.fill();
      // sunlit left faces, a few strokes of light
      ctx.globalAlpha = (1 - actA) * clamp01(m * 1.4) * (look.dark ? 0.18 : 0.32);
      ctx.strokeStyle = look.lit;
      ctx.lineWidth = 3;
      for (let i = 2; i < N; i++) {
        if (yB(i) < yB(i - 2) - 0.8) {
          ctx.beginPath();
          ctx.moveTo(xB(i), yB(i) + 3);
          ctx.lineTo(xB(i) - 6, yB(i) + 26 + hash(i, 9) * 30);
          ctx.stroke();
        }
      }
      ctx.globalAlpha = 1 - actA;
      ctx.beginPath();
      for (let i = 0; i < N; i++) i ? ctx.lineTo(xB(i), yB(i)) : ctx.moveTo(xB(i), yB(i));
      ctx.strokeStyle = mix(look.near, look.dark ? '#000000' : '#000000', 0.3);
      ctx.lineWidth = 3;
      ctx.stroke();
      // the summit: your hardest minute
      const sx = xB(PEAK_I), sy = yB(PEAK_I);
      const flagP = springFast(s - 16, 30, {damping: 9, stiffness: 220});
      if (s > 16) {
        ctx.save();
        ctx.translate(sx, sy - 2);
        ctx.scale(1, clamp01(flagP));
        ctx.strokeStyle = look.dark ? '#EDEDE8' : '#1A1A1A';
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(0, -80);
        ctx.stroke();
        const wv = Math.sin(f * 0.25) * 5;
        ctx.beginPath();
        ctx.moveTo(0, -80);
        ctx.quadraticCurveTo(22, -74 + wv, 48, -70 + wv * 0.6);
        ctx.quadraticCurveTo(22, -60 - wv * 0.4, 0, -54);
        ctx.closePath();
        ctx.fillStyle = CORAL;
        ctx.fill();
        ctx.restore();
      }
      mist(ctx, look.fog, -ox, BOX_W + ox, BOX_H + oy - 60, 200, f, 313, 0.9, 0.5 * m, 8);
      ctx.restore();
      // flash
      const flash = Math.exp(-s / 5) * (look.dark ? 0.55 : 1);
      if (flash > 0.01) {
        ctx.fillStyle = rgba('#FFFFFF', flash);
        ctx.fillRect(0, 0, w, h);
      }
    }
  });

  // ---------- act one text ----------
  const a1 = (at: number, d = 8) => eo((f - at) / d) * actA;
  const clockMins = roll * SESSION.minutes;
  const landed = f >= T.ROLL1;
  const stat = (k: number, to: number) => Math.round(statP(f, k) * to);
  const statPop = (k: number) => {
    const end = STATS[k].at + STATS[k].dur - 6;
    return f >= end ? 1 + 0.12 * Math.exp(-(f - end) / 4) * Math.cos((f - end) * 0.9) : 1;
  };
  const liveHR = Math.round(HR[Math.min(N - 1, Math.floor(head))]);
  const passed20 = clockMins >= 20;
  const pass20At = useMemo(() => {
    for (let ff = T.ROLL0; ff < T.ROLL1; ff++) if (rollP(ff) * SESSION.minutes >= 20) return ff;
    return T.ROLL1;
  }, []);
  const x20 = TX0 + (20 / SESSION.minutes) * (TX1 - TX0);
  const unlock = eo((f - T.UNLOCK) / 8) * actA;

  // ---------- act two text ----------
  const doneP = s >= 0 ? springFast(s, 30, {damping: 9, stiffness: 260}) : 0;
  const b = (at: number, d = 10) => (s >= at ? eo((s - at) / d) : 0);
  const white = '#FFFFFF';
  const lbl: React.CSSProperties = {fontFamily: SF, fontWeight: 700, letterSpacing: '0.16em'};
  const statCols = [
    {label: 'ACTIVE ENERGY', value: stat(0, SESSION.kcal), unit: 'kcal'},
    {label: 'AVG HEART RATE', value: stat(1, AVG_HR), unit: 'bpm'},
    {label: 'PEAK HEART RATE', value: stat(2, PEAK_HR), unit: 'bpm'},
  ];

  return (
    <div style={{position: 'relative', width: w, height: h, overflow: 'hidden', background: BLACK}}>
      <canvas ref={cv} style={{position: 'absolute', inset: 0, width: w, height: h, display: 'block'}} />
      <div style={{position: 'absolute', left: ox, top: oy, width: BOX_W, height: BOX_H, color: white, textAlign: 'center', pointerEvents: 'none'}}>
        {actA > 0 && (
          <>
            <div style={{...lbl, position: 'absolute', top: 250, left: 0, right: 0, fontSize: 32, color: rgba(white, 0.6), opacity: a1(0), letterSpacing: `${0.16 + (1 - a1(0)) * 0.3}em`}}>TODAY'S SESSION</div>
            <div style={{position: 'absolute', top: 302, left: 0, right: 0, fontFamily: SF, fontSize: 30, fontWeight: 500, color: rgba(white, 0.42), opacity: a1(3)}}>
              {SESSION.start} to {SESSION.end} · verified at the gym
            </div>
            <div
              style={{
                position: 'absolute',
                top: 380,
                left: 0,
                right: 0,
                fontFamily: SF_ROUNDED,
                fontWeight: 800,
                fontSize: 260,
                lineHeight: 1,
                letterSpacing: '-0.03em',
                fontVariantNumeric: 'tabular-nums',
                opacity: a1(T.ROLL0 - 4, 5),
                transform: `scale(${(landed ? 1 + 0.07 * Math.exp(-(f - T.ROLL1) / 4) * Math.cos((f - T.ROLL1) * 0.8) : 1).toFixed(4)})`,
                filter: !landed && f > T.ROLL0 ? `blur(${(Math.max(0, 1 - roll * 1.15) * 3).toFixed(2)}px)` : 'none',
              }}
            >
              {mmss(clockMins)}
            </div>
            <div style={{...lbl, position: 'absolute', top: 660, left: 0, right: 0, fontSize: 26, color: rgba(white, 0.5), opacity: a1(T.ROLL0)}}>TIME AT THE GYM</div>
            <div style={{position: 'absolute', top: 770, left: 60, right: 60, display: 'flex'}}>
              {statCols.map((c, k) => (
                <div key={k} style={{flex: 1, opacity: a1(STATS[k].at - 4, 6), transform: `translateY(${((1 - eo((f - STATS[k].at + 4) / 10)) * 30).toFixed(1)}px)`, borderLeft: k ? `1px solid ${rgba(white, 0.12)}` : 'none'}}>
                  <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 86, lineHeight: 1, fontVariantNumeric: 'tabular-nums', transform: `scale(${statPop(k).toFixed(4)})`}}>
                    {c.value}
                    <span style={{fontSize: 30, fontWeight: 700, color: rgba(white, 0.5), marginLeft: 4}}>{c.unit}</span>
                  </div>
                  <div style={{...lbl, fontSize: 22, color: rgba(white, 0.45), marginTop: 14}}>{c.label}</div>
                </div>
              ))}
            </div>
            <div style={{...lbl, position: 'absolute', top: 1040, left: TX0, fontSize: 24, color: rgba(white, 0.45), opacity: a1(T.ROLL0)}}>HEART RATE</div>
            <div style={{position: 'absolute', top: 1032, right: BOX_W - TX1, fontFamily: SF_ROUNDED, fontSize: 34, fontWeight: 800, opacity: a1(T.ROLL0) * (landed ? 0.6 : 1), fontVariantNumeric: 'tabular-nums'}}>
              {liveHR} <span style={{fontSize: 22, color: rgba(white, 0.5)}}>BPM</span>
            </div>
            {passed20 && (
              <div
                style={{
                  position: 'absolute',
                  top: 1452,
                  left: x20 - 160,
                  width: 320,
                  fontFamily: SF,
                  fontSize: 26,
                  fontWeight: 700,
                  color: CORAL,
                  opacity: actA,
                  transform: `scale(${(1 + 0.4 * Math.exp(-(f - pass20At) / 4)).toFixed(3)})`,
                }}
              >
                20:00 · VERIFIED
              </div>
            )}
            <div style={{position: 'absolute', top: 1540, left: 0, right: 0, display: 'flex', justifyContent: 'center', opacity: unlock, transform: `translateY(${((1 - unlock) * 20).toFixed(1)}px) scale(${(0.9 + 0.1 * unlock).toFixed(3)})`}}>
              <div style={{display: 'flex', alignItems: 'center', gap: 16, padding: '20px 34px', borderRadius: 60, background: rgba(white, 0.1), fontFamily: SF, fontSize: 32, fontWeight: 700}}>
                <svg width={34} height={38} viewBox="0 0 34 38">
                  <rect x={3} y={16} width={28} height={20} rx={5} fill={white} />
                  <path d={`M9 16 V11 a8 8 0 0 1 16 0`} fill="none" stroke={white} strokeWidth={4} strokeLinecap="round" transform={`translate(${(eo((f - T.UNLOCK - 2) / 6) * 9).toFixed(1)} ${(-eo((f - T.UNLOCK - 2) / 6) * 5).toFixed(1)})`} />
                </svg>
                6 apps unlocked
              </div>
            </div>
            <div style={{position: 'absolute', top: 1680, left: 0, right: 0, fontFamily: SF, fontSize: 24, fontWeight: 500, color: rgba(white, 0.32), opacity: a1(T.ROLL1)}}>Heart rate and energy from Apple Health</div>
          </>
        )}
        {s >= 0 && (
          <div style={{color: look.ink}}>
            <div style={{...lbl, position: 'absolute', top: 300, left: 0, right: 0, fontSize: 32, color: look.ink2, opacity: b(5), letterSpacing: `${0.16 + (1 - b(5)) * 0.4}em`}}>WORKOUT VERIFIED · DAY {habitDay}</div>
            <div
              style={{
                position: 'absolute',
                top: 340,
                left: 0,
                right: 0,
                fontFamily: SF_ROUNDED,
                fontWeight: 800,
                fontSize: 300,
                lineHeight: 1,
                letterSpacing: '-0.04em',
                opacity: clamp01(s / 2),
                transform: `scale(${(2.4 - 1.4 * doneP).toFixed(4)})`,
                transformOrigin: '50% 60%',
              }}
            >
              Done.
            </div>
            <div style={{position: 'absolute', top: 700, left: 90, right: 90, display: 'flex'}}>
              {[
                {v: mmss(SESSION.minutes), l: 'TIME'},
                {v: String(SESSION.kcal), l: 'KCAL'},
                {v: String(AVG_HR), l: 'AVG BPM'},
              ].map((c, k) => (
                <div key={k} style={{flex: 1, opacity: b(8 + k * 2, 8), transform: `translateY(${((1 - b(8 + k * 2, 8)) * 24).toFixed(1)}px)`, borderLeft: k ? `1px solid ${look.border}` : 'none'}}>
                  <div style={{fontFamily: SF_ROUNDED, fontWeight: 800, fontSize: 72, lineHeight: 1, fontVariantNumeric: 'tabular-nums'}}>{c.v}</div>
                  <div style={{...lbl, fontSize: 22, color: look.ink2, marginTop: 10}}>{c.l}</div>
                </div>
              ))}
            </div>
            <div style={{position: 'absolute', top: 860, left: 120, right: 120, fontFamily: SF, fontSize: 44, fontWeight: 600, lineHeight: 1.25, color: look.ink, opacity: b(18, 12), transform: `translateY(${((1 - b(18, 12)) * 16).toFixed(1)}px)`}}>
              Almost half of people who plan to work out don't follow through.
              <span style={{color: look.ink2}}> You did.</span>
            </div>
          </div>
        )}
      </div>
      {s >= 0 && (
        <div style={{position: 'absolute', left: 0, right: 0, bottom: 0, height: 320, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none'}}>
          <div
            style={{
              fontFamily: SF,
              fontWeight: 700,
              fontSize: 40,
              color: '#1A1A1A',
              background: '#FFFFFF',
              borderRadius: 60,
              padding: '30px 120px',
              boxShadow: '0 10px 30px rgba(0,0,0,.25)',
              opacity: showButton ? eo((f - T.READY) / 10) : 0,
              transform: `translateY(${((1 - eo((f - T.READY) / 10)) * 30).toFixed(1)}px)`,
            }}
          >
            Continue
          </div>
        </div>
      )}
    </div>
  );
};
