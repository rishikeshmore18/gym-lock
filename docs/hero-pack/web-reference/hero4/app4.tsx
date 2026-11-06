/**
 * GymLock home with the "Matrix" hero card. Everything except the hero card mirrors the live app's
 * home screen; only the card (and the done screens it opens) is new.
 */
import React, {useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {LOOKS, Theme, W, clamp01, eio} from '../hero2/paint';
import {SF, SF_ROUNDED} from '../hero2/card';
import {FLAME_INNER, FLAME_OUTER} from '../hero2/strip';
import {CARD_H, D4 as D3, DEFS, HeroCard4, PROOF, S4 as S3, lookFor4 as lookFor3, stateHaptics4 as stateHaptics3} from './card4';
import {BOX_H, FOCUS_Y, SCREENS, Story4, fitComposition} from './story4';
import {LOGO_H, LOGO_PATH, LOGO_W} from '../../src/badges/logoPath';

const DPR = Math.min(3, window.devicePixelRatio || 2);

// ---------- haptics: native bridge when embedded, otherwise the iOS 18 switch trick ----------
declare global {
  interface Window {
    webkit?: {messageHandlers?: {gymlock?: {postMessage: (m: unknown) => void}}};
  }
}
let hapticLabel: HTMLLabelElement | null = null;
const tick = () => {
  if (!hapticLabel) {
    hapticLabel = document.createElement('label');
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.setAttribute('switch', '');
    hapticLabel.appendChild(input);
    hapticLabel.style.cssText = 'position:fixed;left:-99px;top:0;opacity:0;pointer-events:none';
    document.body.appendChild(hapticLabel);
  }
  hapticLabel.click();
};
type HK = 'light' | 'medium' | 'heavy' | 'success';
const haptic = (kind: HK) => {
  const bridge = window.webkit?.messageHandlers?.gymlock;
  if (bridge) return bridge.postMessage({haptic: kind});
  const pattern = {light: [0], medium: [0, 40], heavy: [0, 35, 70], success: [0, 60, 180]}[kind];
  if (navigator.vibrate) navigator.vibrate(kind === 'heavy' ? 45 : kind === 'success' ? [30, 60, 50] : kind === 'medium' ? 25 : 12);
  pattern.forEach((d) => setTimeout(tick, d));
};

const useSimClock = (rate: number) => {
  const [t, setT] = useState(0);
  const r = useRef(rate);
  r.current = rate;
  useEffect(() => {
    let raf = 0, last = performance.now(), sim = 0;
    const loop = (now: number) => {
      sim += (Math.min(64, now - last) / 1000) * r.current;
      last = now;
      setT(sim);
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, []);
  return t;
};
const F = (s: number) => s * 30;

type ThemePref = 'auto' | 'light' | 'dark';
const useSystemDark = () => {
  const mq = useMemo(() => window.matchMedia('(prefers-color-scheme: dark)'), []);
  const [d, setD] = useState(mq.matches);
  useEffect(() => {
    const h = () => setD(mq.matches);
    mq.addEventListener('change', h);
    return () => mq.removeEventListener('change', h);
  }, [mq]);
  return d;
};

const GROUPS: {title: string; items: {id: S3; label: string}[]}[] = [
  {title: 'Day 0 · before the first session', items: [{id: 'setup', label: 'Setup checklist'}, {id: 'firstnight', label: 'Night before day 1'}]},
  {title: 'A session day, in order', items: [{id: 'bedtime', label: 'Locked for sleep'}, {id: 'wake', label: 'Alarm'}, {id: 'countdown', label: 'Countdown'}, {id: 'ready', label: 'Get ready'}, {id: 'commute', label: 'On the way'}, {id: 'atgym', label: 'At the gym'}, {id: 'verified', label: 'Done card'}, {id: 'stilltime', label: 'Not gone yet (evening)'}]},
  {title: 'Days off', items: [{id: 'rest', label: 'Rest day'}, {id: 'paused', label: 'Paused (sick / travel)'}]},
  {title: 'The week', items: [{id: 'freshstart', label: 'New week'}, {id: 'missed', label: 'Missed yesterday'}, {id: 'weekkept', label: 'Week kept'}, {id: 'comeback', label: 'Comeback after a lapse'}]},
  {title: 'The long run', items: [{id: 'drift', label: 'Week 4 drift zone'}, {id: 'halfway', label: 'Day 33 of 66'}, {id: 'automatic', label: 'Day 66'}]},
];

const COUNTDOWN_START = 1 * 3600 + 24 * 60 + 36;
const ATGYM_START = 12 * 60 + 48;

// ---------- the parts of the home screen that stay exactly as they are ----------
const P = (t: Theme) =>
  t === 'dark'
    ? {page: '#0B0B0C', card: '#151517', ink: '#F2F2F0', ink2: '#A3A3A3', ink3: '#6E6E6E', border: 'rgba(255,255,255,.08)', chip: '#232326', dash: '#3A3A3E', off: '#2C2C30', offIn: '#3A3A3F'}
    : {page: '#FAF9F6', card: '#FFFFFF', ink: '#1A1A1A', ink2: '#6B6B6B', ink3: '#9A9A9A', border: '#E8E8E8', chip: '#F1F0ED', dash: '#DCDBD7', off: '#E4E3DF', offIn: '#F3F2EF'};
type Pal = ReturnType<typeof P>;

const Logo: React.FC<{size: number; bg: string; fg: string}> = ({size, bg, fg}) => (
  <div style={{width: size, height: size, borderRadius: size * 0.24, background: bg, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none'}}>
    <svg width={size * 0.66} height={(size * 0.66 * LOGO_H) / LOGO_W} viewBox={`0 0 ${LOGO_W} ${LOGO_H}`}>
      <path d={LOGO_PATH} fill={fg} fillRule="evenodd" />
    </svg>
  </div>
);

const StaticFlame: React.FC<{h: number; lit: boolean; pal: Pal; id: string}> = ({h, lit, pal, id}) => (
  <svg width={(h * 100) / 120} height={h} viewBox="0 0 100 120" style={{display: 'block'}}>
    <defs>
      <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#FFB067" />
        <stop offset="0.55" stopColor="#F27A45" />
        <stop offset="1" stopColor="#E5463A" />
      </linearGradient>
    </defs>
    <path d={FLAME_OUTER} fill={lit ? `url(#${id})` : pal.off} />
    <path d={FLAME_INNER} fill={lit ? '#FFF6EC' : pal.offIn} opacity={lit ? 0.9 : 1} />
  </svg>
);

const IconCircle: React.FC<{pal: Pal; children: React.ReactNode}> = ({pal, children}) => (
  <div style={{width: 34, height: 34, borderRadius: 17, background: pal.chip, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>{children}</div>
);
const ICONS = {
  apps: (c: string) => (
    <svg width={18} height={18} viewBox="0 0 24 24" fill="none">
      <rect x={6} y={10} width={12} height={10} rx={2.5} fill={c} />
      <path d="M8.5 10V7.5a3.5 3.5 0 0 1 7 0V10" stroke={c} strokeWidth={2.2} />
      <path d="M4 3l16 18" stroke={c} strokeWidth={2.2} strokeLinecap="round" />
    </svg>
  ),
  next: (c: string) => (
    <svg width={18} height={18} viewBox="0 0 24 24" fill="none">
      <circle cx={12} cy={13} r={7.5} stroke={c} strokeWidth={2.4} />
      <path d="M12 9.5V13l2.5 1.6M4 5l3-2.5M20 5l-3-2.5" stroke={c} strokeWidth={2.2} strokeLinecap="round" />
    </svg>
  ),
  path: (c: string) => (
    <svg width={18} height={18} viewBox="0 0 24 24" fill="none">
      <circle cx={12} cy={12} r={7} stroke={c} strokeWidth={2.2} />
      <circle cx={12} cy={12} r={2.2} fill={c} />
      <path d="M12 2v4M12 18v4M2 12h4M18 12h4" stroke={c} strokeWidth={2.2} strokeLinecap="round" />
    </svg>
  ),
  bars: (c: string) => (
    <svg width={20} height={16} viewBox="0 0 20 16">
      <rect x={0} y={7} width={5} height={9} rx={1.5} fill={c} />
      <rect x={7.5} y={3.5} width={5} height={12.5} rx={1.5} fill={c} />
      <rect x={15} y={0} width={5} height={16} rx={1.5} fill={c} />
    </svg>
  ),
};

const DAYS = [
  ['Fri', 9], ['Sat', 10], ['Sun', 11], ['Mon', 12], ['Tue', 13], ['Wed', 14], ['Thu', 15], ['Fri', 16], ['Sat', 17], ['Sun', 18], ['Mon', 19], ['Tue', 20], ['Wed', 21], ['Thu', 22],
] as const;
const CalendarStrip: React.FC<{pal: Pal}> = ({pal}) => {
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    if (ref.current) ref.current.scrollLeft = ref.current.scrollWidth;
  }, []);
  return (
    <div ref={ref} style={{display: 'flex', gap: 10, overflowX: 'auto', margin: '22px -16px 26px', padding: '0 16px', scrollbarWidth: 'none'}}>
      {DAYS.map(([d, n], i) => (
        <div key={i} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10, flex: 'none', width: 37}}>
          <div style={{fontSize: 14, fontWeight: 700, color: pal.ink2}}>{d}</div>
          <div style={{width: 37, height: 37, borderRadius: 19, border: `1.5px dashed ${pal.dash}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: SF_ROUNDED, fontSize: 16, fontWeight: 700, color: pal.ink2}}>{n}</div>
        </div>
      ))}
    </div>
  );
};

const mini = (s: S3, d: D3) => {
  const unlocked = s === 'verified' || s === 'rest' || s === 'paused';
  const sleep = s === 'firstnight' || s === 'bedtime';
  const apps = s === 'setup' ? {value: '—', detail: 'choose apps\nin setup'} : sleep ? {value: '6 locked', detail: 'for sleep'} : unlocked ? {value: 'Unlocked', detail: s === 'verified' ? 'earned today' : 'day off'} : {value: '6 locked', detail: 'until you verify'};
  const today = ['wake', 'countdown', 'ready', 'commute', 'atgym', 'stilltime', 'missed', 'comeback', 'freshstart'].includes(s);
  const next = s === 'setup' || sleep ? {value: '07:00', detail: 'Tomorrow'} : s === 'stilltime' ? {value: 'Now', detail: 'still open'} : today ? {value: '07:00', detail: 'Today'} : {value: '07:00', detail: 'Friday'};
  const steps: Partial<Record<S3, [string, string]>> = {
    setup: ['Ready', 'Finish setup\nto begin'], wake: ['1 / 4', 'awake'], countdown: ['1 / 4', 'wake up done'], ready: ['2 / 4', 'leave next'], commute: ['3 / 4', 'arrive next'],
    atgym: [d.atgym >= PROOF ? '4 / 4' : '3 / 4', d.atgym >= PROOF ? 'day won' : 'stay 20 min'], verified: ['4 / 4', 'day won'], rest: ['Rest', 'no steps today'], paused: ['Paused', 'resume anytime'], stilltime: ['0 / 4', 'still open'],
  };
  const st = steps[s] ?? ['Ready', '4 steps today'];
  return [
    {key: 'apps' as const, label: 'APPS', ...apps},
    {key: 'next' as const, label: 'NEXT', ...next, arrow: true},
    {key: 'path' as const, label: 'PATH', value: st[0], detail: st[1]},
  ];
};

const TabBar: React.FC<{pal: Pal; dark: boolean}> = ({pal, dark}) => (
  <div style={{position: 'fixed', left: 0, right: 0, bottom: 0, padding: '0 16px calc(env(safe-area-inset-bottom) + 8px)', display: 'flex', gap: 12, alignItems: 'center', justifyContent: 'center', zIndex: 20, pointerEvents: 'none'}}>
    <div style={{display: 'flex', alignItems: 'center', flex: 1, maxWidth: 420, height: 62, borderRadius: 31, background: dark ? 'rgba(30,30,33,.9)' : 'rgba(255,255,255,.88)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)', boxShadow: `0 0 0 1px ${pal.border}, 0 8px 24px rgba(0,0,0,.06)`, padding: 4, pointerEvents: 'auto'}}>
      {[
        {l: 'Home', on: true, icon: <path d="M3 11.5L12 4l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z" />},
        {l: 'Progress', icon: <><rect x={3} y={11} width={5} height={10} rx={1.5} /><rect x={9.5} y={7} width={5} height={14} rx={1.5} /><rect x={16} y={3} width={5} height={18} rx={1.5} /></>},
        {l: 'Community', icon: <><circle cx={8} cy={8} r={3.5} /><circle cx={17} cy={8} r={3} /><path d="M1.5 20c0-4 3-6.5 6.5-6.5s6.5 2.5 6.5 6.5zM14.5 13.6c3.6-.6 7.5 1.4 7.5 6.4h-6" /></>},
      ].map((t) => (
        <div key={t.l} style={{flex: 1, height: 54, borderRadius: 27, background: t.on ? pal.chip : 'transparent', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2, color: t.on ? pal.ink : pal.ink3}}>
          <svg width={24} height={22} viewBox="0 0 24 24" fill="currentColor">
            {t.icon}
          </svg>
          <div style={{fontSize: 12, fontWeight: 700}}>{t.l}</div>
        </div>
      ))}
    </div>
    <div style={{width: 62, height: 62, borderRadius: 31, background: dark ? 'rgba(30,30,33,.9)' : 'rgba(255,255,255,.88)', boxShadow: `0 0 0 1px ${pal.border}, 0 8px 24px rgba(0,0,0,.06)`, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'auto'}}>
      <svg width={24} height={24} viewBox="0 0 24 24" fill="none" stroke={pal.ink} strokeWidth={2.2}>
        <circle cx={12} cy={8} r={4} />
        <path d="M4 21c0-4.5 3.6-7 8-7s8 2.5 8 7z" strokeLinejoin="round" />
      </svg>
    </div>
  </div>
);

const App: React.FC = () => {
  const [themePref, setThemePref] = useState<ThemePref>('auto');
  const sysDark = useSystemDark();
  const theme: Theme = themePref === 'auto' ? (sysDark ? 'dark' : 'light') : themePref;
  const pal = P(theme);
  const [slow, setSlow] = useState(false);
  const t = useSimClock(slow ? 0.35 : 1);
  const tRef = useRef(t);
  tRef.current = t;

  const [state, setState] = useState<S3>('setup');
  const [start, setStart] = useState(0);
  const [prev, setPrev] = useState<{state: S3; start: number; at: number; d: D3} | null>(null);
  const [setupDone, setSetupDone] = useState([false, true, false]);
  const [cdStart, setCdStart] = useState(COUNTDOWN_START);
  const [gymStart, setGymStart] = useState(ATGYM_START);
  const [overlay, setOverlay] = useState<{idx: number; start: number; tapAt: number | null} | null>(null);
  const cardRef = useRef<HTMLDivElement | null>(null);
  const [vp, setVp] = useState({w: innerWidth, h: innerHeight});
  useEffect(() => {
    const r = () => setVp({w: innerWidth, h: innerHeight});
    addEventListener('resize', r);
    return () => removeEventListener('resize', r);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.body.style.background = pal.page;
  }, [theme, pal.page]);

  const f = F(t - start);
  const remaining = state === 'countdown' ? cdStart - (t - start) : cdStart;
  const atgym = state === 'atgym' ? gymStart + (t - start) : gymStart;
  const stillLeft = 4 * 3600 + 12 * 60 - (state === 'stilltime' ? t - start : 0);
  const d: D3 = {setupDone, countdown: Math.max(0, remaining), atgym, stillLeft};

  const stateRef = useRef(state), startRef = useRef(start), dRef = useRef(d);
  stateRef.current = state;
  startRef.current = start;
  dRef.current = d;
  const go = useCallback((s: S3, opts?: {cd?: number; gym?: number}) => {
    const now = tRef.current;
    setPrev({state: stateRef.current, start: startRef.current, at: now, d: dRef.current});
    setCdStart(opts?.cd ?? COUNTDOWN_START);
    setGymStart(opts?.gym ?? ATGYM_START);
    setState(s);
    setStart(now);
    window.scrollTo({top: 0, behavior: 'smooth'});
  }, []);

  // ---------- lifecycle hand-offs ----------
  useEffect(() => {
    if (state === 'countdown' && remaining <= 0) {
      haptic('heavy');
      go('ready');
    }
  }, [state, remaining, go]);
  const lastSec = useRef(-1);
  useEffect(() => {
    if (state !== 'countdown') return;
    const s = Math.ceil(remaining);
    if (s !== lastSec.current) {
      if (lastSec.current !== -1 && s <= 10 && s > 0) haptic(s <= 3 ? 'heavy' : 'medium');
      lastSec.current = s;
    }
  }, [remaining, state]);
  // at the gym: last ten seconds tick, 20:00 earns it and opens the done screen
  const lastGymSec = useRef(-1);
  const proofFired = useRef(false);
  useEffect(() => {
    if (state !== 'atgym') {
      proofFired.current = false;
      return;
    }
    const s = Math.floor(atgym);
    if (s !== lastGymSec.current) {
      if (lastGymSec.current !== -1 && s >= PROOF - 10 && s < PROOF) haptic(s >= PROOF - 3 ? 'heavy' : 'medium');
      lastGymSec.current = s;
    }
    if (!proofFired.current && atgym >= PROOF) {
      proofFired.current = true;
      haptic('success');
      setTimeout(() => haptic('heavy'), 140);
      setTimeout(() => play(), 1300);
    }
  }, [atgym, state]); // eslint-disable-line

  // entrance haptics for the card
  const lastF = useRef(-1);
  const hapList = useMemo(() => stateHaptics3(state), [state, start]); // eslint-disable-line
  useEffect(() => {
    if (overlay) return;
    for (const h of hapList) if (lastF.current < h.f && f >= h.f) haptic(h.kind);
    lastF.current = f;
  }, [f, hapList, overlay]);
  useEffect(() => {
    lastF.current = -1;
  }, [state, start]);

  // ---------- the done screens: tap to advance, nothing moves on by itself ----------
  const play = useCallback(() => {
    window.scrollTo({top: 0});
    setOverlay({idx: 0, start: tRef.current, tapAt: null});
  }, []);
  useEffect(() => {
    if (location.search.includes('noplay')) return;
    const id = setTimeout(() => play(), 700);
    return () => clearTimeout(id);
  }, [play]);
  const lt = overlay ? t - overlay.start : 0;
  const lastLT = useRef(-1);
  const lastIdx = useRef(-1);
  useEffect(() => {
    if (!overlay || overlay.tapAt != null) {
      lastLT.current = -1;
      return;
    }
    if (lastIdx.current !== overlay.idx) {
      lastIdx.current = overlay.idx;
      lastLT.current = -1;
    }
    for (const h of SCREENS[overlay.idx].haptics) if (lastLT.current < h.t && lt >= h.t) haptic(h.kind);
    lastLT.current = lt;
  }, [lt, overlay]);
  const COLLAPSE = 0.55;
  const cp = overlay?.tapAt != null ? clamp01((t - overlay.tapAt) / COLLAPSE) : 0;
  const landed = useRef(false);
  useEffect(() => {
    if (!overlay || overlay.tapAt == null) {
      landed.current = false;
      return;
    }
    if (!landed.current && cp >= 0.7) {
      landed.current = true;
      setPrev(null);
      setState('verified');
      setStart(tRef.current);
    }
    if (cp >= 1) setOverlay(null);
  }, [cp, overlay]);
  const settled = overlay ? lt >= SCREENS[overlay.idx].settle : false;
  const onOverlayTap = (e: React.MouseEvent) => {
    if (!overlay || overlay.tapAt != null) return;
    const back = e.clientX < vp.w * 0.22 && overlay.idx > 0;
    if (back) {
      haptic('light');
      setOverlay({idx: overlay.idx - 1, start: tRef.current - SCREENS[overlay.idx - 1].settle, tapAt: null});
      return;
    }
    if (!settled) {
      // first tap finishes this screen's animation
      haptic('light');
      setOverlay({...overlay, start: tRef.current - SCREENS[overlay.idx].settle});
      return;
    }
    if (overlay.idx < SCREENS.length - 1) {
      haptic('medium');
      setOverlay({idx: overlay.idx + 1, start: tRef.current, tapAt: null});
      return;
    }
    haptic('heavy');
    setOverlay({...overlay, tapAt: tRef.current});
  };

  const comp = fitComposition(vp.w, vp.h);
  const s0 = vp.w / comp.w;
  let ovStyle: React.CSSProperties = {};
  let ovOpacity = 1;
  if (overlay && overlay.tapAt != null && cardRef.current) {
    const r = cardRef.current.getBoundingClientRect();
    const p = eio(cp);
    const k = r.width / vp.w;
    const focusY = ((comp.h - BOX_H) / 2 + FOCUS_Y) * s0;
    const sc = 1 + (k - 1) * p;
    const cx = vp.w / 2 + (r.left + r.width / 2 - vp.w / 2) * p;
    const cy = focusY + (r.top + r.height / 2 - focusY) * p;
    const hh = r.height / k / 2;
    ovStyle = {
      transform: `translate(${(cx - (vp.w / 2) * sc).toFixed(2)}px, ${(cy - focusY * sc).toFixed(2)}px) scale(${sc.toFixed(4)})`,
      clipPath: `inset(${(p * Math.max(0, focusY - hh)).toFixed(1)}px 0px ${(p * Math.max(0, vp.h - focusY - hh)).toFixed(1)}px 0px round ${((p * 24) / k).toFixed(1)}px)`,
    };
    ovOpacity = 1 - clamp01((cp - 0.72) / 0.28);
  }

  // ---------- card host ----------
  const hostRef = useRef<HTMLDivElement | null>(null);
  const [cw, setCw] = useState(360);
  useLayoutEffect(() => {
    const el = hostRef.current!;
    const ro = new ResizeObserver(() => setCw(el.clientWidth));
    ro.observe(el);
    setCw(el.clientWidth);
    return () => ro.disconnect();
  }, []);
  const scale = cw / W;
  const [pressed, setPressed] = useState(false);
  const def = DEFS[state];
  const cards = mini(state, d);

  return (
    <div style={{fontFamily: SF, color: pal.ink}}>
      <div className="wrap" style={{paddingBottom: 'calc(env(safe-area-inset-bottom) + 110px)'}}>
        <header style={{display: 'flex', alignItems: 'center', gap: 12, padding: '10px 2px 0'}}>
          <Logo size={42} bg={theme === 'dark' ? '#FFFFFF' : '#121213'} fg={theme === 'dark' ? '#121213' : '#FFFFFF'} />
          <div style={{fontSize: 30, fontWeight: 800, letterSpacing: '-0.01em', flex: 1}}>GymLock</div>
          <div style={{display: 'flex', alignItems: 'center', gap: 8, padding: '9px 16px 9px 14px', borderRadius: 22, background: pal.card, boxShadow: `0 0 0 1px ${pal.border}, 0 4px 12px rgba(0,0,0,.05)`}}>
            <StaticFlame h={20} lit pal={pal} id="pill" />
            <span style={{fontFamily: SF_ROUNDED, fontSize: 18, fontWeight: 800}}>{def.pill}</span>
          </div>
        </header>
        <CalendarStrip pal={pal} />
        <div
          ref={(el) => {
            hostRef.current = el;
            cardRef.current = el;
          }}
          onPointerDown={() => setPressed(true)}
          onPointerUp={() => setPressed(false)}
          onPointerLeave={() => setPressed(false)}
          onClick={() => {
            if (state === 'verified') return play();
          }}
          style={{
            position: 'relative',
            width: '100%',
            height: cw * (CARD_H / W),
            borderRadius: 24,
            overflow: 'hidden',
            background: lookFor3(state, theme).card,
            boxShadow: `0 6px 14px rgba(0,0,0,.04), 0 0 0 1px ${pal.border}`,
            transform: `scale(${pressed ? 0.975 : 1})`,
            transition: 'transform .12s cubic-bezier(.2,.9,.25,1), background .3s',
            cursor: 'pointer',
            isolation: 'isolate',
          }}
        >
          <div style={{position: 'absolute', left: 0, top: 0, width: W, height: CARD_H, transform: `scale(${scale})`, transformOrigin: '0 0'}}>
            <HeroCard4
              state={state}
              theme={theme}
              pxScale={scale * DPR}
              f={f}
              t={t}
              d={d}
              onTouchTick={() => haptic('light')}
              onToggleItem={(i) => {
                const next = setupDone.map((x, k) => (k === i ? !x : x));
                setSetupDone(next);
                const all = next.every(Boolean);
                haptic(all && next[i] ? 'heavy' : next[i] ? 'medium' : 'light');
                if (all && next[i]) setTimeout(() => haptic('success'), 120);
              }}
            />
          </div>
        </div>

        <div style={{display: 'flex', gap: 11, marginTop: 16}}>
          {cards.map((m) => (
            <div key={m.label} style={{flex: 1, background: pal.card, borderRadius: 22, padding: '14px 12px 14px 14px', boxShadow: `0 0 0 1px ${pal.border}`, minHeight: 132, display: 'flex', flexDirection: 'column'}}>
              <IconCircle pal={pal}>{ICONS[m.key](pal.ink)}</IconCircle>
              <div style={{fontSize: 11.5, fontWeight: 800, letterSpacing: '0.1em', color: pal.ink2, marginTop: 10}}>{m.label}</div>
              <div style={{fontFamily: SF_ROUNDED, fontSize: 22, fontWeight: 800, color: pal.ink, marginTop: 2, fontVariantNumeric: 'tabular-nums', letterSpacing: '0.01em'}}>{m.value}</div>
              <div style={{fontSize: 11.5, fontWeight: 600, color: pal.ink3, marginTop: 2, whiteSpace: 'pre-line', lineHeight: 1.25, letterSpacing: '0.02em'}}>{m.detail}</div>
              {'arrow' in m && m.arrow && (
                <svg width={16} height={14} viewBox="0 0 16 14" style={{marginTop: 'auto'}}>
                  <path d="M1 7h13M9 1.5L14.5 7 9 12.5" fill="none" stroke={pal.ink} strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </div>
          ))}
        </div>

        <div style={{marginTop: 34, background: pal.card, borderRadius: 26, boxShadow: `0 0 0 1px ${pal.border}, 0 6px 18px rgba(0,0,0,.04)`, display: 'flex', alignItems: 'stretch', padding: '18px 16px'}}>
          <div style={{paddingRight: 14, borderRight: `1px solid ${pal.border}`}}>
            <div style={{display: 'flex', alignItems: 'center', gap: 8}}>
              <IconCircle pal={pal}>{ICONS.bars(pal.ink)}</IconCircle>
              <div style={{fontSize: 12.5, fontWeight: 800, letterSpacing: '0.14em'}}>MOMENTUM</div>
            </div>
            <div style={{fontFamily: SF_ROUNDED, fontSize: 46, fontWeight: 800, marginTop: 12, lineHeight: 1}}>
              {def.week}/5
            </div>
            <div style={{fontSize: 12, fontWeight: 800, letterSpacing: '0.14em', marginTop: 6}}>THIS WEEK</div>
          </div>
          <div style={{flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'space-between', paddingLeft: 14}}>
            {Array.from({length: 5}, (_, i) => (
              <React.Fragment key={i}>
                {i > 0 && <div style={{flex: 1, height: 0, borderTop: `2.5px dotted ${pal.dash}`, margin: '0 3px 14px'}} />}
                <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6}}>
                  <StaticFlame h={30} lit={i < def.week} pal={pal} id={'m' + i} />
                  <div style={{width: 22, height: 3, borderRadius: 2, background: i < def.week ? '#F27A45' : pal.off}} />
                </div>
              </React.Fragment>
            ))}
          </div>
        </div>

        <section className="panel">
          <div className="ptitle">Matrix version · test controls</div>
          <div className="row">
            <button className="chip primary" onClick={() => play(1)}>
              ▶ Play the done screens
            </button>
            <button className={`chip ${slow ? 'sel' : ''}`} onClick={() => setSlow(!slow)}>
              Slow-mo
            </button>
            <div className="seg">
              {(['auto', 'light', 'dark'] as const).map((m) => (
                <button key={m} className={themePref === m ? 'sel' : ''} onClick={() => setThemePref(m)}>
                  {m[0].toUpperCase() + m.slice(1)}
                </button>
              ))}
            </div>
          </div>
          {GROUPS.map((g) => (
            <div key={g.title} style={{marginTop: 14}}>
              <div className="ptitle">{g.title}</div>
              <div className="row">
                {g.items.map((it) => (
                  <button key={it.id} className={`chip ${state === it.id ? 'sel' : ''}`} onClick={() => go(it.id)}>
                    {it.label}
                  </button>
                ))}
                {g.title.startsWith('A session day') && (
                  <>
                    <button className="chip" onClick={() => go('countdown', {cd: 10})}>
                      Countdown · last 10 s
                    </button>
                    <button className="chip" onClick={() => go('atgym', {gym: PROOF - 12})}>
                      Gym · last 12 s → done
                    </button>
                  </>
                )}
                {g.title.startsWith('Day 0') && (
                  <button
                    className="chip"
                    onClick={() => {
                      setSetupDone([false, false, false]);
                      go('setup');
                    }}
                  >
                    Reset checklist
                  </button>
                )}
              </div>
            </div>
          ))}
          <p className="hint">
            Run the day: Countdown · last 10 s rolls into Get ready; Gym · last 12 s hits 20:00 and opens the done screens. Done screens never move on by themselves: tap to finish a screen, tap again for the next, tap the left edge to go back. Drag a finger across the dots on the card. Tap the Done card to replay. Haptics are exact in the native app; Safari gives a light tick (iOS 18+).
          </p>
        </section>
      </div>
      <TabBar pal={pal} dark={theme === 'dark'} />

      {overlay && (
        <div onClick={onOverlayTap} style={{position: 'fixed', inset: 0, zIndex: 50, opacity: ovOpacity, touchAction: 'none'}}>
          <div style={{position: 'absolute', left: 0, top: 0, width: vp.w, height: vp.h, transformOrigin: '0 0', ...ovStyle}}>
            <div style={{width: comp.w, height: comp.h, transform: `scale(${s0})`, transformOrigin: '0 0'}}>
              <Story4 f={0} idx={overlay.idx} lt={lt} w={comp.w} h={comp.h} pxScale={s0 * DPR} showHint={settled} leaving={overlay.tapAt != null} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

createRoot(document.getElementById('root')!).render(<App />);
void LOOKS;
