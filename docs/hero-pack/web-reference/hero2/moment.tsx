/**
 * Full-screen "workout verified": the ranges slide in through the clouds, the sun climbs behind the
 * summit and breaks over it, then "Done." and this week's peaks. Design box 1080 × 1920, fitted.
 */
import React, {useLayoutEffect, useMemo, useRef} from 'react';
import {springFast} from '../../src/springFast';
import {hash, LayerSpec} from '../../src/done/geom';
import {LOOKS, Mode, Theme, blit, clamp01, eio, eo, glow, mist, mix, paintRange, rgba, sky} from './paint';
import {SF, SF_ROUNDED} from './card';
import {Flame, PLAN_DAYS} from './strip';

export const BOX_W = 1080;
export const BOX_H = 1920;
export const fitComposition = (vw: number, vh: number) => {
  const a = vw / vh;
  if (a < BOX_W / BOX_H) return {w: BOX_W, h: Math.round(BOX_W / a / 2) * 2};
  return {w: Math.round((BOX_H * a) / 2) * 2, h: BOX_H};
};
export const FOCUS_Y = 900;
const SUMMIT = {x: 560, y: 830};
const SUN = {x: 650};

let rays: HTMLCanvasElement | null = null;
/** the burst of light, drawn once (512 px) and rotated */
const rayCanvas = () => {
  if (rays) return rays;
  const c = document.createElement('canvas');
  c.width = c.height = 512;
  const g = c.getContext('2d')!;
  g.translate(256, 256);
  const rg = g.createRadialGradient(0, 0, 0, 0, 0, 256);
  rg.addColorStop(0, 'rgba(255,255,255,1)');
  rg.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = rg;
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2 + hash(i, 3) * 0.2;
    const wd = 0.04 + hash(i, 4) * 0.04;
    g.beginPath();
    g.moveTo(0, 0);
    g.lineTo(Math.cos(a - wd) * 256, Math.sin(a - wd) * 256);
    g.lineTo(Math.cos(a + wd) * 256, Math.sin(a + wd) * 256);
    g.closePath();
    g.fill();
  }
  rays = c;
  return c;
};

export const MOMENT = {
  calm: {BREAK: 44, READY: 92, haptics: [{f: 8, kind: 'light'}, {f: 44, kind: 'medium'}, {f: 74, kind: 'success'}, {f: 92, kind: 'light'}]},
  bold: {BREAK: 38, READY: 86, haptics: [{f: 4, kind: 'medium'}, {f: 10, kind: 'medium'}, {f: 16, kind: 'heavy'}, {f: 38, kind: 'heavy'}, {f: 40, kind: 'success'}, {f: 54, kind: 'heavy'}, {f: 74, kind: 'heavy'}, {f: 76, kind: 'success'}, {f: 86, kind: 'medium'}]},
} as const;

type Props = {mode: Mode; theme: Theme; f: number; w: number; h: number; weekBefore: number; weekAfter: number; goal: number; showButton: boolean; pxScale: number};

export const Moment: React.FC<Props> = ({mode, theme, f, w, h, weekBefore, weekAfter, goal, showButton, pxScale}) => {
  const look = LOOKS[theme];
  const bold = mode === 'bold';
  const T = MOMENT[mode];
  const cv = useRef<HTMLCanvasElement>(null);
  const ox = (w - BOX_W) / 2, oy = (h - BOX_H) / 2;

  const layers = useMemo(() => {
    const x0 = -ox - 760, x1 = BOX_W + ox + 80, y0 = 560, y1 = BOX_H + oy + 80;
    const mk = (seed: number, depth: number, o: Partial<LayerSpec>, lit?: number, rim?: number, fog?: number) =>
      paintRange({spec: {depth, base: o.base ?? 1000, amp: o.amp ?? 50, wave: o.wave ?? 300, detail: o.detail ?? 8, seed, peaks: o.peaks}, depth, lit, rim, fog}, look, SUN.x, pxScale, x0, x1, y0, y1);
    return [
      mk(101, 0.1, {base: 980, amp: 60, wave: 420, detail: 6}),
      mk(102, 0.4, {base: 1060, amp: 70, wave: 330, detail: 12, peaks: [{x: 200, y: 880, sl: 0.8, sr: 0.8}, {x: 930, y: 900, sl: 0.8, sr: 0.7}]}, 0.6, 2.2),
      mk(103, 0.88, {base: 2400, amp: 0, wave: 200, detail: 14, peaks: [{x: SUMMIT.x, y: SUMMIT.y, sl: 0.86, sr: 0.74, flat: 4}]}, 1, 3.2, 0.45),
    ];
  }, [look, pxScale, ox, oy]);

  useLayoutEffect(() => {
    const c = cv.current!;
    const pw = Math.round(w * pxScale), ph = Math.round(h * pxScale);
    if (c.width !== pw || c.height !== ph) {
      c.width = pw;
      c.height = ph;
    }
    const ctx = c.getContext('2d')!;
    ctx.setTransform(pxScale, 0, 0, pxScale, 0, 0);
    ctx.fillStyle = look.card;
    ctx.fillRect(0, 0, w, h);
    const brk = f - T.BREAK;
    const shake = bold && brk >= 0 && brk < 10 ? (1 - brk / 10) * 16 : 0;
    ctx.save();
    ctx.translate(ox + Math.sin(f * 3.4) * shake, oy + Math.cos(f * 2.6) * shake * 0.6);
    sky(ctx, look, -oy, 1100, -ox, BOX_W + ox, BOX_H + oy * 2);
    // camera: pushes back and settles down onto the summit
    const cam = springFast(f, 30, bold ? {damping: 16, stiffness: 60} : {damping: 26, stiffness: 40});
    const s = 1 + (bold ? 0.35 : 0.14) * (1 - cam);
    ctx.translate(SUMMIT.x, 1100);
    ctx.scale(s, s);
    ctx.translate(-SUMMIT.x, -1100 + (1 - cam) * (bold ? 160 : 90));
    // sun climbing behind the summit
    const rise = eio((f - 8) / (T.BREAK - 8));
    const sunY = 1040 - rise * 300;
    const brkGlow = brk >= 0 ? (bold ? 0.5 : 0.25) * Math.exp(-brk / 16) : 0;
    glow(ctx, SUN.x, sunY, 520 + brkGlow * 400, look.sun, (look.dark ? 0.22 : 1) * (0.4 + 0.6 * rise) + brkGlow);
    if (brk >= 0) {
      ctx.save();
      ctx.translate(SUN.x, sunY);
      ctx.rotate(f * (bold ? 0.004 : 0.0012) + (bold ? Math.max(0, 1 - brk / 20) * 0.6 : 0));
      ctx.globalAlpha = eo(brk / 18) * (look.dark ? 0.12 : 0.5);
      ctx.drawImage(rayCanvas(), -1400, -1400, 2800, 2800);
      ctx.restore();
    }
    ctx.beginPath();
    ctx.arc(SUN.x, sunY, 44, 0, Math.PI * 2);
    ctx.fillStyle = look.dark ? '#EDEDE8' : '#FFFFFF';
    ctx.fill();
    const travel = bold ? 760 : 420;
    layers.forEach((L, i) => {
      const local = f - i * (bold ? 2 : 3);
      const p = springFast(local, 30, bold ? {damping: 14, stiffness: 120} : {damping: 24, stiffness: 90});
      blit(ctx, L, (1 - p) * travel * (0.25 + 0.75 * L.depth), (1 - p) * 60 * L.depth, clamp01(local / 8));
      if (i === 0) mist(ctx, look.fog, -ox, BOX_W + ox, 1010, 140, f, 61, 0.5, 0.75);
      if (i === 1) mist(ctx, look.fog, -ox, BOX_W + ox, 1120, 180, f, 63, 0.8, 0.85, 8);
    });
    // the sea of clouds below the summit
    mist(ctx, look.fog, -ox, BOX_W + ox, 1250, 230, f, 67, bold ? 2 : 1, 1, 9);
    mist(ctx, look.fog, -ox, BOX_W + ox, 1420, 300, f, 71, bold ? 2.6 : 1.3, 1, 9);
    const fg = ctx.createLinearGradient(0, 1330, 0, 1600);
    fg.addColorStop(0, rgba(look.fog, 0));
    fg.addColorStop(1, rgba(look.fog, 1));
    ctx.fillStyle = fg;
    ctx.fillRect(-ox - 400, 1330, BOX_W + ox * 2 + 800, BOX_H + oy + 600);
    // bold: a cloud bank rushes past the camera on the way in
    if (bold && f < 34) {
      const t = f / 34;
      mist(ctx, look.fog, -ox - t * 1600, BOX_W + ox - t * 1600, 900, 900, 0, 81, 0, (1 - t) * 1, 6);
    }
    ctx.restore();
    const flash = brk >= 0 ? (bold ? 0.65 : 0.22) * (look.dark ? 0.35 : 1) * Math.max(0, 1 - brk / (bold ? 9 : 14)) : 0;
    if (flash > 0) {
      ctx.fillStyle = rgba('#FFFFFF', flash);
      ctx.fillRect(0, 0, w, h);
    }
  });

  const lab = eo((f - 50) / 12);
  const title = springFast(f - 54, 30, bold ? {damping: 9, stiffness: 260} : {damping: 18, stiffness: 240});
  const sub = eo((f - 62) / 12);
  const row = eo((f - 70) / 12);
  const btn = springFast(f - T.READY, 30, bold ? {damping: 11, stiffness: 260} : {damping: 20, stiffness: 240});
  const count = f >= 74 ? weekAfter : weekBefore;

  return (
    <div style={{position: 'absolute', inset: 0, overflow: 'hidden', background: look.card, fontFamily: SF}}>
      <canvas ref={cv} style={{position: 'absolute', inset: 0, width: w, height: h, display: 'block'}} />
      <div style={{position: 'absolute', left: ox, top: oy, width: BOX_W, height: BOX_H, color: look.ink, textAlign: 'center', pointerEvents: 'none'}}>
        <div style={{position: 'absolute', top: 1180, left: 0, right: 0, fontSize: 32, fontWeight: 700, letterSpacing: '0.16em', paddingLeft: '0.16em', color: look.ink2, opacity: lab}}>WORKOUT VERIFIED</div>
        <div style={{position: 'absolute', top: 1222, left: 0, right: 0, fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 170, letterSpacing: '-0.025em', lineHeight: 1.05, opacity: clamp01((f - 54) / (bold ? 2 : 5)), transform: bold ? `translateY(${((1 - title) * 80).toFixed(1)}px) scale(${(1.2 - 0.2 * title).toFixed(4)})` : `translateY(${((1 - title) * 40).toFixed(1)}px)`}}>
          Done.
        </div>
        <div style={{position: 'absolute', top: 1398, left: 0, right: 0, fontSize: 46, fontWeight: 500, color: look.ink2, opacity: sub, transform: `translateY(${((1 - sub) * 14).toFixed(1)}px)`}}>You showed up today.</div>
        <div style={{position: 'absolute', top: 1478, left: 0, right: 0, display: 'flex', justifyContent: 'center', alignItems: 'flex-end', gap: 40, opacity: row, transform: `translateY(${((1 - row) * 16).toFixed(1)}px)`}}>
          {Array.from({length: goal}, (_, i) => {
            const st = i < weekBefore ? 'lit' : i === weekBefore ? (f >= 74 ? 'igniting' : 'today') : 'off';
            return (
              <div key={i} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10}}>
                <Flame state={st} h={96} look={look} g={f} t={f - 74} mode={mode} id={`mf${i}`} seed={i} />
                <span style={{fontSize: 26, fontWeight: i === weekBefore ? 700 : 500, color: i === weekBefore ? look.ink : look.ink3}}>{i === weekBefore ? 'Today' : PLAN_DAYS[i]}</span>
              </div>
            );
          })}
          <div style={{textAlign: 'left', marginLeft: 16, alignSelf: 'center'}}>
            <div style={{fontFamily: SF_ROUNDED, fontWeight: 700, fontSize: 64, lineHeight: 1, fontVariantNumeric: 'tabular-nums'}}>
              {count} of {goal}
            </div>
            <div style={{fontSize: 24, fontWeight: 700, letterSpacing: '0.14em', color: look.ink3, marginTop: 8}}>THIS WEEK</div>
          </div>
        </div>
      </div>
      {showButton && (
        <div style={{position: 'absolute', left: w / 2 - 250, top: h - Math.max(130, oy + 110) - 116 + (1 - btn) * 40, width: 500, height: 116, borderRadius: 58, background: look.ink, color: look.card, fontSize: 40, fontWeight: 600, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: clamp01(btn * 1.6)}}>
          Continue
        </div>
      )}
    </div>
  );
};

export {mix};
