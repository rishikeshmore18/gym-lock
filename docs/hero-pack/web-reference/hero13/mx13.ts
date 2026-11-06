/** Matrix Dynamic: pick the scene for a moment and a day. Each moment lives in its own file under ./mx. */
import {SCENES as setup} from './mx/setup';
import {SCENES as firstnight} from './mx/firstnight';
import {SCENES as bedtime} from './mx/bedtime';
import {SCENES as wake} from './mx/wake';
import {SCENES as countdown} from './mx/countdown';
import {SCENES as ready} from './mx/ready';
import {SCENES as commute} from './mx/commute';
import {SCENES as atgym} from './mx/atgym';
import {SCENES as verified} from './mx/verified';
import {SCENES as stilltime} from './mx/stilltime';
import {SCENES as rest} from './mx/rest';
import {SCENES as paused} from './mx/paused';
import {SCENES as freshstart} from './mx/freshstart';
import {SCENES as missed} from './mx/missed';
import {SCENES as weekkept} from './mx/weekkept';
import {SCENES as comeback} from './mx/comeback';
import {SCENES as drift} from './mx/drift';
import {SCENES as halfway} from './mx/halfway';
import {SCENES as automatic} from './mx/automatic';
import type {MHap, MScn} from './mxlib';

const ALL: Record<string, MScn[]> = {setup, firstnight, bedtime, wake, countdown, ready, commute, atgym, verified, stilltime, rest, paused, freshstart, missed, weekkept, comeback, drift, halfway, automatic};
export const mxScene = (state: string, day: number): MScn => ALL[state][day];
export const mxHap = (state: string, day: number): MHap | undefined => ALL[state]?.[day]?.hap;
