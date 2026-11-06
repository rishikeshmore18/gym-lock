/**
 * The week as seven worlds. Every day of the week has its own place, painted (Ridge) or drawn in dots
 * (Matrix), and the whole day happens there: the night before, the alarm, the countdown, the gym, the
 * done screens. Monday is dawn, Tuesday stone, Wednesday water, Thursday pine, Friday the summit,
 * Saturday the sea, Sunday the stars. Each world has its own countdown and its own finish, so the
 * same moment never looks the same two days running and the done screens never end the same way
 * twice in a week.
 *
 * Why this shape:
 *   - Variety slows hedonic adaptation: a reward that changes keeps feeling like a reward
 *     (Sheldon & Lyubomirsky 2012).
 *   - Effort makes people value what they made, but only when they finish it (Norton, Mochon &
 *     Ariely 2012, the IKEA effect). So every finish is a few taps the user completes themselves.
 *   - Gym attendance falls through the week: Monday is the busiest day, Friday the least attended
 *     weekday and Sunday the least attended day (Wodify; Itensity, 2.4M check-ins: Friday 58% of
 *     Monday, Sunday 21%). Friday's and Sunday's words lean into that.
 *   - Fresh starts: gym visits rise 33% at the start of a week and 14% at the start of a month
 *     (Dai, Milkman & Riis 2014). The first week of a month gets its own screen: set the month.
 *   - People judge a stretch of time by its peak and its end (Kahneman et al. 1993). The last week of a
 *     month gets a recap screen and a closing flourish.
 */
import type {Pos} from '../hero11/copy11';
import {POS_WEEK} from '../hero11/copy11';

export type Day = 0 | 1 | 2 | 3 | 4 | 5 | 6;
export type MonthPos = 'first' | 'middle' | 'last';
export type WorldId = 'dawn' | 'stone' | 'water' | 'pine' | 'summit' | 'sea' | 'stars';

export const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
export const DAY_SHORT = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export type Climax = {
  eyebrow: string;
  lastEyebrow: string;
  title: string;
  sub: (n: number) => string;
  idle: string;
  mid: string;
  end: string;
};

export const WORLDS: {id: WorldId; name: string; blurb: string; countdown: string; live: string; liveDone: string; climax: Climax}[] = [
  {
    id: 'dawn',
    name: 'Dawn',
    blurb: 'a sea of clouds at sunrise',
    countdown: 'the sun rises as gym time gets closer',
    live: 'until the sun is up',
    liveDone: '20:00. Sun up. Verified.',
    climax: {eyebrow: 'TODAY’S SUN', lastEyebrow: 'THE WEEK’S LAST SUNRISE', title: 'Raise it.', sub: (n) => `Tap **${n} times** to lift the sun clear of the clouds.`, idle: 'Tap to raise the sun', mid: 'Higher', end: 'The sun is up, and so is the count.'},
  },
  {
    id: 'stone',
    name: 'Stone',
    blurb: 'a ridge and this week’s rock',
    countdown: 'an hourglass on the ledge',
    live: 'until today’s rock breaks',
    liveDone: '20:00. Rock broken. Verified.',
    climax: {eyebrow: 'TODAY’S ROCK', lastEyebrow: 'THE WEEK’S LAST ROCK', title: 'Break it.', sub: (n) => `Tap the rock **${n} times** to put today on the count.`, idle: 'Tap the rock to break it', mid: 'Keep going', end: 'Another one in pieces. Every session breaks one.'},
  },
  {
    id: 'water',
    name: 'Water',
    blurb: 'a mountain lake and a rowboat',
    countdown: 'a drip from a bough, one drop a second',
    live: 'until the boat reaches the far shore',
    liveDone: '20:00. Across. Verified.',
    climax: {eyebrow: 'THE LAKE', lastEyebrow: 'THE WEEK’S LAST THROW', title: 'Skip it.', sub: (n) => `Every tap is a skip. **${n}** gets it to the far shore.`, idle: 'Tap to skip the stone', mid: 'Again', end: 'All the way across. Today made it to the other side.'},
  },
  {
    id: 'pine',
    name: 'Pine',
    blurb: 'a pine on the ledge, fireflies, fog',
    countdown: 'a candle burning down in a lantern',
    live: 'until the pine grows',
    liveDone: '20:00. Grown. Verified.',
    climax: {eyebrow: 'THE PINE', lastEyebrow: 'THE WEEK’S LAST GROWTH', title: 'Grow it.', sub: (n) => `Tap **${n} times.** Today goes into the pine.`, idle: 'Tap to grow the pine', mid: 'Taller', end: 'Taller than this morning. That’s what a session does.'},
  },
  {
    id: 'summit',
    name: 'Summit',
    blurb: 'a trail up the mountain and a beacon at the top',
    countdown: 'a light walking the trail',
    live: 'until the beacon is lit',
    liveDone: '20:00. Beacon lit. Verified.',
    climax: {eyebrow: 'THE SUMMIT', lastEyebrow: 'THE WEEK’S LAST CLIMB', title: 'Light it.', sub: (n) => `Climb with **${n} taps,** then the beacon at the top is yours.`, idle: 'Tap to climb', mid: 'Keep climbing', end: 'Lit from the top. Everyone below can see it.'},
  },
  {
    id: 'sea',
    name: 'Sea',
    blurb: 'a shore at sunset, the tide, paper lanterns',
    countdown: 'the tide creeping up to a stick in the sand',
    live: 'until the lanterns go up',
    liveDone: '20:00. Lanterns up. Verified.',
    climax: {eyebrow: 'THE SHORE', lastEyebrow: 'THE WEEK’S LAST LIGHTS', title: 'Let them go.', sub: (n) => `One lantern for every tap. **${n}** to send up.`, idle: 'Tap to light a lantern', mid: 'Another', end: 'Up and away. Today is done and drifting.'},
  },
  {
    id: 'stars',
    name: 'Stars',
    blurb: 'a night sky and a constellation of the week',
    countdown: 'the moon setting behind the ridge',
    live: 'until the stars connect',
    liveDone: '20:00. Stars joined. Verified.',
    climax: {eyebrow: 'TONIGHT’S SKY', lastEyebrow: 'THE WEEK, IN STARS', title: 'Connect it.', sub: (n) => `**${n} stars,** one for every day of the week. Light them all.`, idle: 'Tap to light a star', mid: 'Next star', end: 'Seven days, one shape. The week is written in the sky.'},
  },
];

/** the tail of the finish note, by where the session falls in the week */
export const POS_TAIL: Record<Pos, string> = {
  first: 'The first of the week is the hardest to start.',
  middle: 'The middle is where most people stop. **You didn’t.**',
  last: 'A full week, finished on a high. **That’s how it will be remembered.**',
};

/** the closing line and button: the next session is the next weekday */
export const endFor = (pos: Pos, day: Day) => {
  const next = day >= 4 ? 'Monday' : DAY_NAMES[day + 1];
  if (pos === 'last') return {sub: 'Week **5 of 5.** Week streak **6.** Rest up.', button: 'Week done. See you Monday'};
  return {sub: pos === 'first' ? `Next: **${next}, 07:00.** Keep it rolling.` : `Next: **${next}, 07:00.** Only 2 left.`, button: `See you ${next}`};
};

/** taps for today's finish: five, seven for the week's last session; Sunday's sky always has seven stars */
export const tapsFor12 = (day: Day, pos: Pos) => (day === 6 || pos === 'last' ? 7 : 5);

// ---------- dates ----------
export const autoDay = (): Day => (((new Date().getDay() + 6) % 7) as Day);
const dim = (y: number, m: number) => new Date(y, m + 1, 0).getDate();
export const autoMonthPos = (): MonthPos => {
  const d = new Date();
  const n = dim(d.getFullYear(), d.getMonth());
  return d.getDate() <= 7 ? 'first' : d.getDate() > n - 7 ? 'last' : 'middle';
};
/** Monday starts the week; Friday through Sunday close it */
export const autoPos = (day: Day): Pos => (day === 0 ? 'first' : day >= 4 ? 'last' : 'middle');
export const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

export type CalCell = 'off' | 'done' | 'miss' | 'today' | 'future' | 'blank';
export type MonthCal = {name: string; short: string; lead: number; cells: CalCell[]; date: number; sessions: number; target: number; lastMonth: number; minutes: number; bestWeek: number; bestWeekN: number; leftDays: number};

/**
 * This month's calendar, believable and consistent: Monday to Friday sessions with the odd miss,
 * today placed in the first, middle or last full week of the month on the chosen weekday, and
 * this week's sessions so far matching the Done card's count.
 */
export const monthCal = (monthPos: MonthPos, day: Day, pos: Pos, target = 18): MonthCal => {
  const now = new Date();
  const y = now.getFullYear(), m = now.getMonth();
  const n = dim(y, m);
  const wd = (d: number) => (new Date(y, m, d).getDay() + 6) % 7; // 0 Monday
  const mondays: number[] = [];
  for (let d = 1; d <= n; d++) if (wd(d) === 0) mondays.push(d);
  const full = mondays.filter((d) => d + 6 <= n);
  const start = monthPos === 'first' ? full[0] : monthPos === 'last' ? full[full.length - 1] : full[Math.floor(full.length / 2)];
  const date = start + day;
  const before = POS_WEEK[pos].done - 1; // this week's sessions before today
  const thisWeek: number[] = [];
  for (let d = date - 1; d >= start && thisWeek.length < before; d--) thisWeek.push(d);
  const cells: CalCell[] = [];
  for (let d = 1; d <= n; d++) {
    if (d > date) cells.push('future');
    else if (d === date) cells.push('today');
    else if (d >= start) cells.push(thisWeek.includes(d) ? 'done' : 'off');
    else if (wd(d) >= 5) cells.push('off');
    else cells.push((d * 7 + m) % 11 === 3 ? 'miss' : 'done');
  }
  const sessions = cells.filter((c) => c === 'done').length + 1;
  // best full week so far
  let bestWeek = 1, bestWeekN = 0;
  full.forEach((mo, k) => {
    if (mo >= start) return;
    let c = 0;
    for (let d = mo; d < mo + 7; d++) if (cells[d - 1] === 'done') c++;
    if (c > bestWeekN) {
      bestWeekN = c;
      bestWeek = k + 1;
    }
  });
  return {name: MONTH_NAMES[m], short: MONTH_NAMES[m].slice(0, 3).toUpperCase(), lead: wd(1), cells, date, sessions, target, lastMonth: 14, minutes: sessions * 52, bestWeek, bestWeekN, leftDays: n - date};
};
export const MONTH_TARGETS: {n: number; label: string}[] = [
  {n: 14, label: 'Steady'},
  {n: 18, label: 'Your pace'},
  {n: 22, label: 'Push'},
];
