/**
 * The done screens, in order. Five normally; six in the first and last weeks of a month, which add
 * the month screen before "How far": set the month (first week) or see it whole (last week).
 */
import type {MonthPos} from './days12';

export type ScrId = 'verified' | 'today' | 'week' | 'month' | 'far' | 'climax';
type HK = 'light' | 'medium' | 'heavy' | 'success';
export type ScrCfg = {settle: number; haptics: {t: number; kind: HK}[]};

export const screens12 = (mp: MonthPos): ScrId[] => (mp === 'middle' ? ['verified', 'today', 'week', 'far', 'climax'] : ['verified', 'today', 'week', 'month', 'far', 'climax']);

export const CFG_R: Record<ScrId, ScrCfg> = {
  verified: {settle: 2.0, haptics: [{t: 0.05, kind: 'light'}, {t: 0.5, kind: 'medium'}, {t: 0.9, kind: 'heavy'}, {t: 0.95, kind: 'success'}, ...[0, 1, 2].map((k) => ({t: 1.3 + k * 0.12, kind: 'light' as HK}))]},
  today: {settle: 1.8, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 8}, (_, k) => ({t: 0.25 + k * 0.12, kind: 'light' as HK})), {t: 1.3, kind: 'medium'}]},
  week: {settle: 1.8, haptics: [{t: 0.05, kind: 'medium'}, ...[0, 1, 2].map((k) => ({t: 0.5 + k * 0.18, kind: 'medium' as HK})), {t: 1.3, kind: 'light'}]},
  month: {settle: 1.6, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 6}, (_, k) => ({t: 0.25 + k * 0.1, kind: 'light' as HK})), {t: 1.1, kind: 'heavy'}]},
  far: {settle: 2.0, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 7}, (_, k) => ({t: 0.3 + k * 0.13, kind: 'light' as HK})), {t: 1.4, kind: 'heavy'}]},
  climax: {settle: 1.0, haptics: [{t: 0.05, kind: 'medium'}]},
};
export const CFG_M: Record<ScrId, ScrCfg> = {
  verified: {settle: 1.5, haptics: [{t: 0.05, kind: 'medium'}, {t: 0.75, kind: 'heavy'}, {t: 0.8, kind: 'success'}]},
  today: {settle: 2.3, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 13}, (_, k) => ({t: 0.3 + k * 0.14, kind: 'light' as HK})), {t: 2.12, kind: 'heavy'}]},
  week: {settle: 2.4, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 8}, (_, k) => ({t: 0.2 + k * 0.18, kind: 'light' as HK})), {t: 1.9, kind: 'medium'}, {t: 2.15, kind: 'medium'}]},
  month: {settle: 1.8, haptics: [{t: 0.05, kind: 'medium'}, ...Array.from({length: 8}, (_, k) => ({t: 0.25 + k * 0.1, kind: 'light' as HK})), {t: 1.3, kind: 'heavy'}]},
  far: {settle: 1.9, haptics: [{t: 0.05, kind: 'medium'}, {t: 0.7, kind: 'heavy'}, {t: 0.75, kind: 'success'}, {t: 1.5, kind: 'light'}]},
  climax: {settle: 1.0, haptics: [{t: 0.05, kind: 'medium'}]},
};

/** stat label for the "How far" screen: what today's finish has added up to so far */
export const TALLY = ['SUNRISES', 'ROCKS BROKEN', 'CROSSINGS', 'RINGS GROWN', 'SUMMITS LIT', 'LANTERNS SENT', 'STARS LIT'];
