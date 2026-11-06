/**
 * Kinetic type for Dynamic. Each moment's headline arrives with a motion that matches what it says:
 * the alarm slams, the night before types itself out, bedtime blurs in, the commute wipes across,
 * the week kept drops letter by letter, a paused streak stamps down and stays.
 */
import React from 'react';
import type {TypeStyle} from './props13';

const cl = (x: number) => Math.min(1, Math.max(0, x));
const ez = (x: number) => 1 - Math.pow(1 - cl(x), 3);
const back = (x: number, k = 1.7) => {
  const t = cl(x) - 1;
  return 1 + (k + 1) * t * t * t + k * t * t;
};
const spr = (x: number, w = 13, z = 6) => (x <= 0 ? 0 : 1 - Math.exp(-x * z) * Math.cos(x * w));

type Props = {text: string; style: TypeStyle; f: number; size: number; color: string; family: string; weight: number; tracking?: number; reduce?: boolean};

export const Kinetic: React.FC<Props> = ({text, style, f, size, color, family, weight, tracking = -0.03, reduce}) => {
  const base: React.CSSProperties = {fontFamily: family, fontWeight: weight, fontSize: size, lineHeight: 1.02, color, letterSpacing: `${tracking}em`, whiteSpace: 'nowrap', display: 'inline-block', fontVariantNumeric: 'tabular-nums'};
  const x = (f - 3) / 30;
  if (reduce) return <span style={{...base, opacity: cl((f - 3) / 6)}}>{text}</span>;
  const chars = [...text];
  switch (style) {
    case 'slam': {
      const s = 1.6 - 0.6 * spr(x * 1.2);
      return <span style={{...base, opacity: cl((f - 3) / 2.5), transform: `scale(${s.toFixed(4)})`, transformOrigin: '0% 80%', letterSpacing: `${(tracking + 0.12 * (1 - ez(x * 3))).toFixed(4)}em`}}>{text}</span>;
    }
    case 'stamp': {
      const p = ez((f - 3) / 6);
      return <span style={{...base, opacity: cl((f - 3) / 2), transform: `scale(${(1.28 - 0.28 * p).toFixed(4)}) rotate(${(-3 * (1 - p)).toFixed(3)}deg)`, transformOrigin: '0% 60%'}}>{text}</span>;
    }
    case 'blur': {
      const p = ez((f - 3) / 20);
      return <span style={{...base, opacity: p, filter: `blur(${((1 - p) * 14).toFixed(2)}px)`, transform: `scale(${(1.06 - 0.06 * p).toFixed(4)})`, transformOrigin: '0% 60%'}}>{text}</span>;
    }
    case 'wipe': {
      const p = ez((f - 3) / 14);
      return (
        <span style={{position: 'relative', display: 'inline-block'}}>
          <span style={{...base, clipPath: `inset(0 ${((1 - p) * 100).toFixed(2)}% 0 0)`}}>{text}</span>
          {p < 1 && <span style={{position: 'absolute', top: '8%', bottom: '8%', left: `calc(${(p * 100).toFixed(2)}% - 3px)`, width: 6, borderRadius: 3, background: '#E85D4E', opacity: 1 - p * 0.6}} />}
        </span>
      );
    }
    case 'type': {
      const n = Math.max(0, Math.floor((f - 3) / 1.6));
      const done = n >= chars.length;
      return (
        <span style={base}>
          {chars.slice(0, n).join('')}
          <span style={{display: 'inline-block', width: '0.08em', height: '0.82em', marginLeft: '0.04em', verticalAlign: '-0.06em', background: color, opacity: done ? (Math.floor(f / 15) % 2 ? 0 : 1) : 1}} />
          <span style={{opacity: 0}}>{chars.slice(n).join('')}</span>
        </span>
      );
    }
    case 'jolt': {
      const k = Math.max(0, f - 3);
      const dx = Math.sin(k * 1.9) * 22 * Math.exp(-k / 6);
      return (
        <span style={{position: 'relative', display: 'inline-block'}}>
          {k < 10 && <span style={{...base, position: 'absolute', left: 0, top: 0, opacity: 0.25 * (1 - k / 10), transform: `translateX(${(-dx * 0.6).toFixed(2)}px)`}}>{text}</span>}
          <span style={{...base, opacity: cl(k / 2), transform: `translateX(${dx.toFixed(2)}px)`}}>{text}</span>
        </span>
      );
    }
    case 'rise': {
      const words = text.split(' ');
      return (
        <span style={{...base, display: 'inline-flex', gap: '0.24em'}}>
          {words.map((w, i) => {
            const p = back((f - 3 - i * 3) / 11, 1.3);
            return (
              <span key={i} style={{display: 'inline-block', overflow: 'hidden', paddingBottom: '0.12em', marginBottom: '-0.12em'}}>
                <span style={{display: 'inline-block', transform: `translateY(${((1 - p) * 110).toFixed(2)}%)`}}>{w}</span>
              </span>
            );
          })}
        </span>
      );
    }
    case 'drop':
      return (
        <span style={base}>
          {chars.map((ch, i) => {
            const p = back((f - 3 - i * 1.3) / 11, 2.2);
            return (
              <span key={i} style={{display: 'inline-block', whiteSpace: 'pre', opacity: cl((f - 3 - i * 1.3) / 2), transform: `translateY(${(-(1 - p) * size * 0.7).toFixed(2)}px)`}}>
                {ch}
              </span>
            );
          })}
        </span>
      );
    case 'track':
    default: {
      const sp = tracking + 0.55 * (1 - ez((f - 3) / 18));
      return (
        <span style={{...base, letterSpacing: `${sp.toFixed(4)}em`}}>
          {chars.map((ch, i) => (
            <span key={i} style={{opacity: cl((f - 3 - i * 0.9) / 6), whiteSpace: 'pre'}}>
              {ch}
            </span>
          ))}
        </span>
      );
    }
  }
};

/** the eyebrow: a short rule draws out, then the words slide in after it */
export const Eyebrow: React.FC<{text: string; f: number; color: string; children?: React.ReactNode; style?: React.CSSProperties; reduce?: boolean}> = ({text, f, color, children, style, reduce}) => {
  const line = reduce ? 1 : ez((f - 1) / 6);
  const tx = reduce ? 1 : ez((f - 4) / 8);
  return (
    <div style={{display: 'flex', alignItems: 'center', gap: 12, whiteSpace: 'nowrap', ...style}}>
      {children}
      <span style={{display: 'inline-block', width: 26 * line, height: 3, borderRadius: 2, background: color, opacity: 0.85, marginRight: 2 - 14 * (1 - line)}} />
      <span style={{opacity: tx, transform: `translateX(${((1 - tx) * -10).toFixed(2)}px)`, letterSpacing: `${(0.06 + (1 - tx) * 0.22).toFixed(3)}em`}}>{text}</span>
    </div>
  );
};

/** digits that flip in when they change (the countdown and the gym clock) */
export const FlipClock: React.FC<{text: string; frac: number; size: number; color: string; family: string; weight: number; up?: boolean}> = ({text, frac, size, color, family, weight, up = true}) => {
  // frac: 0 right after the last digit changed, 1 just before the next change
  const p = ez(frac / 0.22);
  return (
    <span style={{fontFamily: family, fontWeight: weight, fontSize: size, lineHeight: 1.02, color, letterSpacing: '-0.03em', fontVariantNumeric: 'tabular-nums', display: 'inline-flex'}}>
      {[...text].map((ch, i) => {
        const last = i === text.length - 1;
        return (
          <span key={i} style={{display: 'inline-block', overflow: 'hidden', height: '1.02em'}}>
            <span style={{display: 'inline-block', transform: last ? `translateY(${((1 - p) * (up ? 60 : -60)).toFixed(2)}%)` : undefined, opacity: last ? 0.3 + 0.7 * p : 1}}>{ch}</span>
          </span>
        );
      })}
    </span>
  );
};
