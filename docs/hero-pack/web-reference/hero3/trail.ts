/**
 * The trail: one ridge climbing to a summit, a dotted path along its crest and a marker that moves
 * up it. Used for "at the gym" (marker = minutes toward the 20 minute proof), "drift zone" (marker in
 * the fog band of weeks 3 to 6) and "halfway" (marker at day 33 of 66).
 */
import {springFast} from '../../src/springFast';
import {ridgeY} from '../../src/done/geom';
import {H, W, birds, blit, clamp01, eo, glow, mist, paintRange, rgba, sky} from '../hero2/paint';
import {Ctx, R, Scene, camera, enter} from '../hero2/scenes';

export type TrailData = {p: number; fog: number; band?: [number, number]; live?: boolean};

const X0 = 470, X1 = 868;

export const trailScene = ({look, px, mode}: Ctx, getTrail: () => TrailData): Scene => {
  const sunX = 930;
  const ranges = [
    R(91, {depth: 0.1, base: 262, amp: 26, wave: 260, detail: 3}),
    R(92, {depth: 0.4, base: 318, amp: 30, wave: 190, detail: 6, lit: 0.5, rim: 1.1, peaks: [{x: 560, y: 236, sl: 0.7, sr: 0.8}]}),
    R(93, {depth: 0.92, base: 700, amp: 0, wave: 100, detail: 6, lit: 0.9, rim: 2.2, fog: 0.35, peaks: [{x: X1, y: 128, sl: 0.62, sr: 0.9, flat: 6}]}),
  ];
  const L = ranges.map((r) => paintRange(r, look, sunX, px));
  const spec = ranges[2].spec;
  // path points along the crest, slightly below it so they sit on the rock
  const path: [number, number][] = [];
  for (let x = X0; x <= X1; x += 2) path.push([x, ridgeY(spec, x) + 7]);
  const len: number[] = [0];
  for (let i = 1; i < path.length; i++) len.push(len[i - 1] + Math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]));
  const total = len[len.length - 1];
  const at = (u: number) => {
    const s = clamp01(u) * total;
    let i = 1;
    while (i < len.length - 1 && len[i] < s) i++;
    const k = (s - len[i - 1]) / Math.max(1e-6, len[i] - len[i - 1]);
    return [path[i - 1][0] + (path[i][0] - path[i - 1][0]) * k, path[i - 1][1] + (path[i][1] - path[i - 1][1]) * k] as const;
  };
  let shown = 0;
  return {
    draw(ctx, f, g) {
      const T = getTrail();
      sky(ctx, look, 0, 320);
      ctx.save();
      camera(ctx, mode, f, g);
      glow(ctx, sunX, 120, 260, look.sun, look.dark ? 0.16 : 0.95);
      L.forEach((l, i) => {
        const e = enter(mode, f, i, l.depth, g);
        blit(ctx, l, e.dx, e.dy, e.a);
        if (i === 0) mist(ctx, look.fog, 300, W, 300, 60, g, 93, 0.25, 0.7);
        if (i === 1) mist(ctx, look.fog, 300, W, 372, 70, g, 95, 0.35, 0.65);
      });
      const e = enter(mode, f, 2, 0.92, g);
      ctx.translate(e.dx, e.dy);
      // the drift band: fog sits on that stretch of the climb
      if (T.band) {
        const [a, b] = T.band;
        const pa = at(a), pb = at(b);
        const fa = eo((f - 10) / 20) * T.fog;
        mist(ctx, look.fog, pa[0] - 60, pb[0] + 60, (pa[1] + pb[1]) / 2, 120, g, 97, 0.5, fa, 6);
        mist(ctx, look.fog, pa[0] - 60, pb[0] + 60, (pa[1] + pb[1]) / 2 - 30, 90, g, 99, 0.8, fa * 0.8, 5);
      }
      // dotted path: walked part solid, the rest faint
      const intro = eo((f - 8) / 18);
      const target = T.p;
      shown = T.live ? target : (springFast(f - 12, 30, mode === 'bold' ? {damping: 13, stiffness: 120} : {damping: 22, stiffness: 90})) * target;
      const n = 46;
      for (let k = 0; k <= n; k++) {
        const u = k / n;
        if (u > intro) break;
        const [x, y] = at(u);
        const walked = u <= shown;
        ctx.beginPath();
        ctx.arc(x, y, walked ? 3.4 : 2.4, 0, Math.PI * 2);
        ctx.fillStyle = walked ? rgba(look.dark ? '#FFFFFF' : '#FFFFFF', 0.95) : rgba(look.dark ? '#FFFFFF' : '#FFFFFF', 0.45);
        ctx.fill();
      }
      // summit flag
      const fl = springFast(f - 18, 30, {damping: 10, stiffness: 200});
      const [sx, sy] = at(1);
      ctx.save();
      ctx.translate(sx, sy - 4);
      ctx.scale(1, clamp01(fl));
      ctx.strokeStyle = look.dark ? '#EDEDE8' : '#FFFFFF';
      ctx.lineWidth = 2.4;
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, -44);
      ctx.stroke();
      ctx.beginPath();
      const wv = Math.sin(g * 0.25) * 3;
      ctx.moveTo(0, -44);
      ctx.quadraticCurveTo(12, -40 + wv, 26, -38 + wv * 0.6);
      ctx.quadraticCurveTo(12, -32 - wv * 0.4, 0, -28);
      ctx.closePath();
      ctx.fillStyle = shown >= 0.999 ? '#E85D4E' : look.dark ? '#EDEDE8' : '#FFFFFF';
      ctx.fill();
      ctx.restore();
      // the marker: you, on the climb
      if (intro > 0.3) {
        const [mx, my] = at(shown);
        const pulse = 0.5 + 0.5 * Math.sin(g * 0.18);
        glow(ctx, mx, my, 44 + pulse * 14, '#FFFFFF', look.dark ? 0.35 : 0.9);
        ctx.beginPath();
        ctx.arc(mx, my, 16 + pulse * 6, 0, Math.PI * 2);
        ctx.strokeStyle = rgba('#FFFFFF', 0.5 * (1 - pulse));
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(mx, my, 11, 0, Math.PI * 2);
        ctx.fillStyle = '#FFFFFF';
        ctx.fill();
        ctx.beginPath();
        ctx.arc(mx, my, 5.5, 0, Math.PI * 2);
        ctx.fillStyle = '#E85D4E';
        ctx.fill();
      }
      ctx.translate(-e.dx, -e.dy);
      mist(ctx, look.fog, 300, W, 455, 80, g, 101, mode === 'bold' ? 0.6 : 0.3, 0.8);
      birds(ctx, look.ink, 640, 120, 3, g, 0.9, look.dark ? 0.45 : 0.5, 21);
      ctx.restore();
    },
  };
};
export {H};
