/**
 * GymLock hero card demo (open on iPhone). Built twice from this file:
 *   __VERSION__ = 'refined' → the app's own design language, smooth + snappy
 *   __VERSION__ = 'bold'    → heavy, kinetic, loud haptics
 */
import React, {useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {CORAL, H, LOOKS, Mode, Theme, W, clamp01, eio} from './paint';
import {DemoData, StateId} from './scenes';
import {CARD_H, HeroCardArt, SF, SF_ROUNDED, stateHaptics} from './card';
import {Flame} from './strip';
import {FOCUS_Y, BOX_H, MOMENT, Moment, fitComposition} from './moment';
const DPR = Math.min(3, window.devicePixelRatio || 2);
const palette = (_m: Mode, t: Theme) => {
  const L = LOOKS[t];
  return {page: t === 'dark' ? '#0B0B0C' : '#FAF9F6', card: L.card, ink: L.ink, ink2: L.ink2, ink3: L.ink3, border: L.border};
};
import {LOGO_H, LOGO_PATH, LOGO_W} from '../../src/badges/logoPath';

declare const __VERSION__: Mode;
const V: Mode = __VERSION__;

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

// ---------- clock ----------
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

const GROUPS: {title: string; items: {id: StateId; label: string}[]}[] = [
  {title: 'Rest · night · progress', items: [{id: 'night', label: 'Night'}, {id: 'rest', label: 'Rest day'}, {id: 'week', label: 'Week progress'}]},
  {title: 'Workout completed', items: [{id: 'verified', label: 'Verified card'}]},
  {title: 'Getting ready', items: [{id: 'countdown', label: 'Countdown'}, {id: 'ready', label: 'Get ready'}]},
  {title: 'Setup incomplete', items: [{id: 'setup', label: 'Checklist'}]},
];

const COUNTDOWN_START = 1 * 3600 + 24 * 60 + 36;

const Logo: React.FC<{size: number; bg: string; fg: string}> = ({size, bg, fg}) => (
  <div style={{width: size, height: size, borderRadius: size * 0.26, background: bg, display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 'none'}}>
    <svg width={size * 0.66} height={(size * 0.66 * LOGO_H) / LOGO_W} viewBox={`0 0 ${LOGO_W} ${LOGO_H}`}>
      <path d={LOGO_PATH} fill={fg} fillRule="evenodd" />
    </svg>
  </div>
);

const App: React.FC = () => {
  const [themePref, setThemePref] = useState<ThemePref>('auto');
  const sysDark = useSystemDark();
  const theme: Theme = themePref === 'auto' ? (sysDark ? 'dark' : 'light') : themePref;
  const P = palette(V, theme);
  const PR = P; // the page itself is always the app's own chrome
  const [slow, setSlow] = useState(false);
  const t = useSimClock(slow ? 0.35 : 1);
  const tRef = useRef(t);
  tRef.current = t;

  const [state, setState] = useState<StateId>('setup');
  const [start, setStart] = useState(0);
  const [prev, setPrev] = useState<{state: StateId; start: number; at: number; data: DemoData} | null>(null);
  const [setupDone, setSetupDone] = useState([true, true, false]);
  const [weekDone, setWeekDone] = useState(1);
  const [cdStart, setCdStart] = useState(COUNTDOWN_START);
  const [overlay, setOverlay] = useState<{start: number; tapAt: number | null; before: number} | null>(null);
  const cardRef = useRef<HTMLDivElement | null>(null);
  const [vp, setVp] = useState({w: innerWidth, h: innerHeight});
  useEffect(() => {
    const r = () => setVp({w: innerWidth, h: innerHeight});
    addEventListener('resize', r);
    return () => removeEventListener('resize', r);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    document.body.style.background = PR.page;
  }, [theme, PR.page]);

  const f = F(t - start);
  const remaining = state === 'countdown' ? cdStart - (t - start) : cdStart;
  const lockIn = Math.max(0, 76 * 60 - (state === 'night' ? t - start : 0));
  const data: DemoData = {setupDone, bedtime: '23:00', wake: '06:30', nextDay: 'Friday', nextTime: '07:00', weekDone, weekGoal: 3, streakWeeks: 1, lockIn, countdown: {remaining: Math.max(0, remaining), window: 2 * 3600}};

  const go = useCallback((s: StateId, opts?: {cd?: number}) => {
    const now = tRef.current;
    setPrev((p) => ({state: stateRef.current, start: startRef.current, at: now, data: dataRef.current}));
    if (opts?.cd != null) setCdStart(opts.cd);
    else if (s === 'countdown') setCdStart(COUNTDOWN_START);
    setState(s);
    setStart(now);
  }, []);
  const stateRef = useRef(state), startRef = useRef(start), dataRef = useRef(data);
  stateRef.current = state;
  startRef.current = start;
  dataRef.current = data;

  // countdown reaching zero hands over to "get ready"
  useEffect(() => {
    if (state === 'countdown' && remaining <= 0) {
      haptic(V === 'bold' ? 'heavy' : 'medium');
      go('ready');
    }
  }, [state, remaining, go]);
  // bold: last ten seconds tick
  const lastSec = useRef(-1);
  useEffect(() => {
    if (state !== 'countdown') return;
    const s = Math.ceil(remaining);
    if (s !== lastSec.current) {
      if (lastSec.current !== -1 && s <= 10 && s > 0) haptic(V === 'bold' ? (s <= 3 ? 'heavy' : 'medium') : 'light');
      lastSec.current = s;
    }
  }, [remaining, state]);

  // entrance haptics for the card
  const lastF = useRef(-1);
  const hapList = useMemo(() => stateHaptics(state, V, data), [state, start]); // eslint-disable-line
  useEffect(() => {
    if (overlay) return;
    for (const h of hapList) if (lastF.current < h.f && f >= h.f) haptic(h.kind);
    lastF.current = f;
  }, [f, hapList, overlay]);
  useEffect(() => {
    lastF.current = -1;
  }, [state, start]);

  // ---------- the verified moment ----------
  const play = useCallback(() => {
    window.scrollTo({top: 0});
    setOverlay({start: tRef.current, tapAt: null, before: Math.min(weekDoneRef.current, 2)});
  }, []);
  const weekDoneRef = useRef(weekDone);
  weekDoneRef.current = weekDone;
  useEffect(() => {
    const id = setTimeout(play, 700);
    return () => clearTimeout(id);
  }, [play]);

  const of = overlay ? F(t - overlay.start) : 0;
  const READY = MOMENT[V].READY;
  const lastOF = useRef(-1);
  useEffect(() => {
    if (!overlay) {
      lastOF.current = -1;
      return;
    }
    for (const h of MOMENT[V].haptics) if (lastOF.current < h.f && of >= h.f) haptic(h.kind as HK);
    lastOF.current = of;
  }, [of, overlay]);
  const COLLAPSE = V === 'bold' ? 0.5 : 0.62;
  const cp = overlay?.tapAt != null ? clamp01((t - overlay.tapAt) / COLLAPSE) : 0;
  const landed = useRef(false);
  useEffect(() => {
    if (!overlay || overlay.tapAt == null) {
      landed.current = false;
      return;
    }
    if (!landed.current && cp >= 0.7) {
      landed.current = true;
      setWeekDone(overlay.before + 1);
      setPrev(null);
      setState('verified');
      setStart(tRef.current);
    }
    if (cp >= 1) setOverlay(null);
  }, [cp, overlay]);
  const onOverlayTap = () => {
    if (!overlay || overlay.tapAt != null || of < READY) return;
    haptic(V === 'bold' ? 'heavy' : 'light');
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
  const prevExit = prev ? clamp01((t - prev.at) / (V === 'bold' ? 0.14 : 0.22)) : 1;

  // press feedback on the card (touch-down)
  const [pressed, setPressed] = useState(false);

  const mini = miniCards(state, data);

  return (
    <div style={{fontFamily: SF, color: PR.ink}}>
      <div className="wrap">
        <header style={{display: 'flex', alignItems: 'center', gap: 12, padding: '6px 2px 0'}}>
          <Logo size={44} bg={theme === 'dark' ? '#fff' : '#121213'} fg={theme === 'dark' ? '#121213' : '#fff'} />
          <div style={{fontSize: 30, fontWeight: 800, letterSpacing: '-0.02em', flex: 1}}>GymLock</div>
          <div style={{display: 'flex', alignItems: 'center', gap: 6, padding: '8px 14px 8px 12px', borderRadius: 22, background: PR.card, boxShadow: `0 0 0 1px ${PR.border}`}}>
            <Flame state="lit" h={24} look={LOOKS[theme]} g={F(t)} mode={V} id="pill" />
            <span style={{fontFamily: SF_ROUNDED, fontSize: 19, fontWeight: 800}}>1</span>
          </div>
        </header>
        <Week P={PR} today={state === 'verified'} />
        <div
          ref={(el) => {
            hostRef.current = el;
            cardRef.current = el;
          }}
          onPointerDown={() => {
            setPressed(true);
            haptic('light');
          }}
          onPointerUp={() => setPressed(false)}
          onPointerLeave={() => setPressed(false)}
          onClick={() => {
            setPrev(null);
            setStart(tRef.current);
          }}
          style={{
            position: 'relative',
            width: '100%',
            height: cw * (CARD_H / W),
            borderRadius: 24,
            overflow: 'hidden',
            background: state === 'night' ? LOOKS.night.card : P.card,
            boxShadow: `0 6px 14px rgba(0,0,0,.05), 0 0 0 1px ${P.border}`,
            transform: `scale(${pressed ? 0.97 : 1})`,
            transition: 'transform .12s cubic-bezier(.2,.9,.25,1)',
            cursor: 'pointer',
            WebkitTapHighlightColor: 'transparent',
            isolation: 'isolate',
          }}
        >
          <div style={{position: 'absolute', left: 0, top: 0, width: W, height: CARD_H, transform: `scale(${scale})`, transformOrigin: '0 0'}}>
            <HeroCardArt
              key={state + start}
              state={state}
              theme={theme}
              mode={V}
              pxScale={scale * DPR}
              f={f}
              g={F(t)}
              data={data}
              onToggleItem={(i) => {
                const next = setupDone.map((x, k) => (k === i ? !x : x));
                setSetupDone(next);
                const all = next.every(Boolean);
                haptic(all && next[i] ? (V === 'bold' ? 'heavy' : 'success') : next[i] ? (V === 'bold' ? 'medium' : 'light') : 'light');
                if (all && next[i] && V === 'bold') setTimeout(() => haptic('success'), 120);
              }}
            />
            {prev && prevExit < 1 && <HeroCardArt key={'p' + prev.state + prev.start} state={prev.state} theme={theme} mode={V} pxScale={scale * DPR} f={F(prev.at - prev.start) + 200} g={F(t)} data={prev.data} exit={prevExit} />}
          </div>
        </div>
        <div style={{display: 'flex', gap: 10, marginTop: 12}}>
          {mini.map((m) => (
            <div key={m.label} style={{flex: 1, background: PR.card, borderRadius: 18, padding: '14px 12px', boxShadow: `0 0 0 1px ${PR.border}`, minHeight: 112}}>
              <div style={{fontSize: 11, fontWeight: 700, letterSpacing: '0.12em', color: PR.ink2}}>{m.label}</div>
              <div style={{fontFamily: SF_ROUNDED, fontSize: 22, fontWeight: 700, color: PR.ink, marginTop: 10, fontVariantNumeric: 'tabular-nums'}}>{m.value}</div>
              <div style={{fontSize: 12, fontWeight: 500, color: PR.ink3, marginTop: 2}}>{m.detail}</div>
            </div>
          ))}
        </div>

        <section className="panel">
          <div className="ptitle">{V === 'bold' ? 'Bold version' : 'Calm version'} · test controls</div>
          <div className="row">
            <button className="chip primary" onClick={play}>
              ▶ Play “Workout verified”
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
                {g.title === 'Getting ready' && (
                  <button className="chip" onClick={() => go('countdown', {cd: 10})}>
                    Countdown · last 10 s
                  </button>
                )}
                {g.title === 'Setup incomplete' && (
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
          <p className="hint">Tap a checklist row on the card to tick it; ticking the last one snaps the lock shut. “Countdown · last 10 s” runs into “Get ready”. Tap the card to replay its entrance. Haptics are exact in the native app; Safari gives a light tick (iOS 18+).</p>
        </section>
      </div>

      {overlay && (
        <div onClick={onOverlayTap} style={{position: 'fixed', inset: 0, zIndex: 50, opacity: ovOpacity, touchAction: 'none'}}>
          <div style={{position: 'absolute', left: 0, top: 0, width: vp.w, height: vp.h, transformOrigin: '0 0', ...ovStyle}}>
            <div style={{width: comp.w, height: comp.h, transform: `scale(${s0})`, transformOrigin: '0 0'}}>
              <Moment mode={V} theme={theme} f={of} w={comp.w} h={comp.h} weekBefore={overlay.before} weekAfter={overlay.before + 1} goal={3} showButton={overlay.tapAt == null} pxScale={s0 * DPR} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const Week: React.FC<{P: ReturnType<typeof palette>; today: boolean}> = ({P, today}) => (
  <div style={{display: 'flex', justifyContent: 'space-between', margin: '14px 0 18px'}}>
    {DAYS.map((d, i) => {
      const isToday = i === 0;
      return (
        <div key={d} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, padding: '10px 6px 8px', borderRadius: 26, background: isToday ? P.card : 'transparent', boxShadow: isToday ? `0 2px 10px rgba(0,0,0,.05), 0 0 0 1px ${P.border}` : 'none'}}>
          <div style={{fontSize: 14, fontWeight: 700, color: isToday ? P.ink : P.ink3}}>{d}</div>
          <div style={{width: 34, height: 34, borderRadius: 17, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 15, fontWeight: 800, color: isToday ? P.card : P.ink3, background: isToday ? P.ink : 'transparent', border: isToday ? 'none' : `2px dashed ${P.border}`, transition: 'background .25s'}}>
            {isToday && today ? '✓' : i + 2}
          </div>
        </div>
      );
    })}
  </div>
);

const miniCards = (s: StateId, d: DemoData) => {
  const apps = s === 'verified' || s === 'ready' ? {value: 'Unlocked', detail: 'earned back'} : s === 'night' ? {value: '6 apps', detail: 'locked for sleep'} : s === 'setup' && !d.setupDone[0] ? {value: 'None yet', detail: 'pick in setup'} : {value: '6 apps', detail: 'until verification'};
  const next = s === 'night' ? {value: '06:30', detail: 'wake'} : s === 'rest' ? {value: 'Wed', detail: '07:00'} : s === 'countdown' ? {value: '07:00', detail: 'today'} : s === 'verified' ? {value: 'Wed', detail: '07:00'} : {value: '07:00', detail: 'Wednesday'};
  const path = s === 'verified' ? {value: '4 / 4', detail: 'day won'} : s === 'ready' ? {value: '1 / 4', detail: 'steps today'} : s === 'rest' || s === 'night' ? {value: 'Rest', detail: 'no steps today'} : {value: '4 steps', detail: 'to win today'};
  return [
    {label: 'APPS', ...apps},
    {label: 'NEXT', ...next},
    {label: 'PATH', ...path},
  ];
};

createRoot(document.getElementById('root')!).render(<App />);
