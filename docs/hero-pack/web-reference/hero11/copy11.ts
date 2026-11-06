/**
 * The words for every moment, shared by both modes (Ridge and Matrix), five versions of each so the
 * same moment never reads the same two days running (variety slows hedonic adaptation: Sheldon &
 * Lyubomirsky 2012).
 *
 * The Done moment also depends on where the session falls in the week:
 *   first   the fresh start: gym visits jump 33% at the start of a week (Dai, Milkman & Riis 2014).
 *           Make the first step feel small and already won.
 *   middle  motivation sags halfway to a goal (Bonezzi, Brendl & De Angelis 2011). Early in the week
 *           look back at what’s done; later, look ahead at how little is left.
 *   last    people remember an experience by its peak and its end (Kahneman et al. 1993).
 *           Close the week on the loudest moment.
 */
import type {S4} from '../hero4/card4';

export type Pos = 'first' | 'middle' | 'last';
export type C11 = {eyebrow: string; title: string; sub: string; note?: string};

export const STATE_COPY: Record<S4, C11[]> = {
  setup: [
    {eyebrow: 'FINISH YOUR SYSTEM', title: '#SETUP', sub: '', note: 'Plant it.'},
    {eyebrow: 'ALMOST THERE', title: '#SETUP', sub: '', note: 'Roots first.'},
    {eyebrow: 'BUILD THE SYSTEM', title: '#SETUP', sub: '', note: 'Set it once.'},
    {eyebrow: 'THREE STEPS', title: '#SETUP', sub: '', note: 'Start small.'},
    {eyebrow: 'GET SET', title: '#SETUP', sub: '', note: 'Ground work.'},
  ],
  firstnight: [
    {eyebrow: 'DAY ONE TOMORROW', title: 'Charge up.', sub: 'Tomorrow, **07:00** at **Iron Works.** Sleep first.'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Sleep first.', sub: 'A plan with a **time and place** gets kept. Yours is 07:00.'},
    {eyebrow: 'THE NIGHT BEFORE', title: 'Bag packed?', sub: 'Shoes by the door. **07:00** at Iron Works.'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Rest easy.', sub: 'Everything is set. All you do tomorrow is **show up.**'},
    {eyebrow: 'TOMORROW, 07:00', title: 'Lights low.', sub: 'The first session starts **tonight,** with sleep.'},
  ],
  bedtime: [
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Recharging.', sub: 'Apps **locked** until 06:30. Muscle **rebuilds** while you sleep.'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Lights out.', sub: 'Apps stay **locked** until morning. Gym at 07:00.'},
    {eyebrow: 'SLEEP MODE', title: 'Power down.', sub: 'Nothing to scroll. **Tomorrow is planned.**'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Off duty.', sub: 'Your phone rests too. **Back at 06:30.**'},
    {eyebrow: 'NIGHT', title: 'Refuel.', sub: 'Good sleep is **part of the workout.**'},
  ],
  wake: [
    {eyebrow: 'ALARM · 06:30', title: 'Rise.', sub: 'Fully charged. Apps unlock when you **check in.**'},
    {eyebrow: 'ALARM · 06:30', title: 'Feet down.', sub: 'Apps stay locked until you’re **at the gym.**'},
    {eyebrow: 'GOOD MORNING', title: 'Up.', sub: 'First win of the day: **out of bed.**'},
    {eyebrow: 'ALARM · 06:30', title: 'New day.', sub: 'Thirty minutes from now you’ll be **glad you went.**'},
    {eyebrow: '06:30', title: 'Morning.', sub: 'Water, shoes, door. **That’s the whole plan.**'},
  ],
  countdown: [
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'Same time, same place. **That’s how it sticks.**'},
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'The sand is running. **Bag ready?**'},
    {eyebrow: 'UNTIL 07:00', title: '#CLOCK', sub: 'Planned, so it **happens.**'},
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'People who plan **when and where** follow through 91% of the time.'},
    {eyebrow: 'COUNTING DOWN', title: '#CLOCK', sub: 'Iron Works at 07:00. **No decision to make.**'},
  ],
  ready: [
    {eyebrow: 'ALARM BEATEN', title: 'Get ready.', sub: 'Shoes on. **Out by 06:45.**', note: 'Go.'},
    {eyebrow: 'ALARM BEATEN', title: 'Shoes on.', sub: 'The hardest rep is **the front door.**', note: 'Move.'},
    {eyebrow: 'UP AND MOVING', title: 'Out the door.', sub: 'Fifteen minutes to **Iron Works.**', note: 'Go.'},
    {eyebrow: 'ALARM BEATEN', title: 'You’re up.', sub: 'That was the hard part. **Now just go.**', note: 'Onward.'},
    {eyebrow: 'GET READY', title: 'Grab the bag.', sub: 'Out by **06:45.** Done by 07:30.', note: 'Go.'},
  ],
  commute: [
    {eyebrow: 'ON YOUR WAY', title: '6 min out.', sub: 'The hard part **is behind you.**'},
    {eyebrow: 'ON YOUR WAY', title: 'Almost there.', sub: 'You’re out the door. **That was the win.**'},
    {eyebrow: 'EN ROUTE', title: '6 min out.', sub: 'Apps unlock **when you walk in.**'},
    {eyebrow: 'ON YOUR WAY', title: 'Moving.', sub: 'Showing up is **most of it.**'},
    {eyebrow: 'HEADING IN', title: 'Nearly there.', sub: 'Iron Works in **6 minutes.**'},
  ],
  atgym: [
    {eyebrow: 'AT THE GYM', title: '#LIVE', sub: ''},
    {eyebrow: 'ON THE FLOOR', title: '#LIVE', sub: ''},
    {eyebrow: 'CHECKED IN', title: '#LIVE', sub: ''},
    {eyebrow: 'AT IRON WORKS', title: '#LIVE', sub: ''},
    {eyebrow: 'IN SESSION', title: '#LIVE', sub: ''},
  ],
  verified: [
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
  ],
  stilltime: [
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: '**20 minutes** before sundown keeps the week.'},
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: 'Today is a planned day. **Twenty minutes counts.**'},
    {eyebrow: 'BEFORE THE DAY ENDS', title: '#LEFT', sub: 'A short session **beats a skipped one.**'},
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: 'The gym is open **until 22:00.**'},
    {eyebrow: 'TODAY’S STILL OPEN', title: '#LEFT', sub: 'Go now and tonight **you’ll sleep on a win.**'},
  ],
  rest: [
    {eyebrow: 'REST DAY', title: 'Recover.', sub: 'Muscle is built **between** sessions.', note: 'Rest today. Stronger tomorrow.'},
    {eyebrow: 'REST DAY', title: 'Rest is training.', sub: 'Planned rest **protects the streak.**', note: 'Easy does it.'},
    {eyebrow: 'DAY OFF', title: 'Recharge.', sub: 'Walk, stretch, sleep. **Back tomorrow.**', note: 'Still water.'},
    {eyebrow: 'REST DAY', title: 'Breathe.', sub: 'Nothing to do today **but recover.**', note: 'Slow down.'},
    {eyebrow: 'RECOVERY', title: 'Off day.', sub: 'Your streak is safe. **Rest is in the plan.**', note: 'Let it settle.'},
  ],
  paused: [
    {eyebrow: 'STREAK FROZEN', title: 'Off the clock.', sub: 'Sick or travelling? Frozen days **don’t count against you.**', note: 'Frozen, not lost.'},
    {eyebrow: 'STREAK FROZEN', title: 'On hold.', sub: 'Your streak waits **right here.**', note: 'Paused.'},
    {eyebrow: 'PAUSED', title: 'Take the break.', sub: 'Come back when you’re ready. **Nothing is lost.**', note: 'It’ll keep.'},
    {eyebrow: 'STREAK FROZEN', title: 'Rest up.', sub: 'Get well first. **The plan waits.**', note: 'Frozen.'},
    {eyebrow: 'AWAY', title: 'Enjoy it.', sub: 'Frozen days **don’t break the chain.**', note: 'Back soon.'},
  ],
  freshstart: [
    {eyebrow: 'NEW WEEK', title: 'New week.', sub: 'Last week: **4 sessions, 3h 12m.** Gym visits jump **33%** at the start of a week.', note: 'Stack it again.'},
    {eyebrow: 'NEW WEEK', title: 'Clean slate.', sub: 'Last week is banked. **First session today.**', note: 'Fresh start.'},
    {eyebrow: 'MONDAY', title: 'Week 8.', sub: 'Mondays are when people **start fresh.** Ride it.', note: 'Day one.'},
    {eyebrow: 'NEW WEEK', title: 'Zero of five.', sub: 'One session and the week **is moving.**', note: 'Begin.'},
    {eyebrow: 'NEW WEEK', title: 'Go again.', sub: 'Last week, **4 for 5.** This week, start strong.', note: 'Again.'},
  ],
  missed: [
    {eyebrow: 'MISSED YESTERDAY', title: 'Never twice.', sub: 'One miss doesn’t undo a habit. **Today keeps it.**'},
    {eyebrow: 'MISSED YESTERDAY', title: 'Back today.', sub: 'Missing once has **no real effect** on habit forming.'},
    {eyebrow: 'YESTERDAY SLIPPED', title: 'Today counts.', sub: 'One day is a blip. **Two is a pattern.**'},
    {eyebrow: 'MISSED YESTERDAY', title: 'Reset.', sub: 'Twenty minutes today and **the week is back.**'},
    {eyebrow: 'ONE MISS', title: 'Not two.', sub: 'Go today and **yesterday won’t matter.**'},
  ],
  weekkept: [
    {eyebrow: 'WEEK KEPT', title: '5 of 5.', sub: 'Every planned session, **stacked.**', note: 'Week built.'},
    {eyebrow: 'WEEK KEPT', title: 'Full week.', sub: 'Five planned, **five done.**', note: 'Complete.'},
    {eyebrow: 'WEEK KEPT', title: 'Perfect week.', sub: 'Week streak: **5.** Keep the run going.', note: 'Stacked.'},
    {eyebrow: 'WEEK DONE', title: 'All five.', sub: 'You kept **every promise** this week.', note: 'Built.'},
    {eyebrow: 'WEEK KEPT', title: 'Closed out.', sub: 'Five for five. **Rest well this weekend.**', note: 'Earned.'},
  ],
  comeback: [
    {eyebrow: 'WELCOME BACK', title: 'Start again.', sub: 'Coming back **earns a bonus** today.', note: 'Back at it.'},
    {eyebrow: 'WELCOME BACK', title: 'Good to see you.', sub: 'Just 20 minutes **restarts the run.**', note: 'Again.'},
    {eyebrow: 'BACK', title: 'Day one, again.', sub: 'Everyone restarts. **The ones who win do it fast.**', note: 'Go.'},
    {eyebrow: 'WELCOME BACK', title: 'Pick it up.', sub: 'A return after a break is **the habit working.**', note: 'Onward.'},
    {eyebrow: 'WELCOME BACK', title: 'Fresh start.', sub: 'Bonus waiting **when you check in.**', note: 'Rise.'},
  ],
  drift: [
    {eyebrow: 'WEEK 4', title: 'Drift zone.', sub: 'Most slip to **once a week** by week 6. **Not you.**', note: 'Keep going.'},
    {eyebrow: 'WEEK 4', title: 'Stay sharp.', sub: 'This is where **most people fade.**', note: 'Push through.'},
    {eyebrow: 'THE MIDDLE', title: 'Keep going.', sub: 'The middle is **the hardest part.** It passes.', note: 'Through it.'},
    {eyebrow: 'WEEK 4', title: 'Hold the line.', sub: 'New members plan 3 a week. **By week 6, 1.** Not you.', note: 'Steady.'},
    {eyebrow: 'WEEK 4', title: 'Stay the course.', sub: 'The fog lifts **if you keep walking.**', note: 'Onward.'},
  ],
  halfway: [
    {eyebrow: 'HABIT FORMING', title: 'Day 33.', sub: 'Halfway up. **13 sessions** in.', note: 'Halfway up.'},
    {eyebrow: 'HALFWAY', title: 'Halfway.', sub: 'Habits take **66 days** on average. You’re at 33.', note: 'Keep climbing.'},
    {eyebrow: 'DAY 33 OF 66', title: 'Half there.', sub: 'From here, **the summit is closer** than the start.', note: 'Over the hump.'},
    {eyebrow: 'HABIT FORMING', title: 'Day 33.', sub: 'It’s getting **easier** than it was.', note: 'Halfway.'},
    {eyebrow: 'DAY 33', title: 'Midpoint.', sub: '33 days behind you. **33 to automatic.**', note: 'Look up.'},
  ],
  automatic: [
    {eyebrow: 'DAY 66', title: 'Automatic.', sub: '66 days is the median. **It’s yours now.**', note: 'Rooted.'},
    {eyebrow: 'DAY 66', title: 'Habit made.', sub: 'It runs **on its own** now.', note: 'Summit.'},
    {eyebrow: 'DAY 66', title: 'Who you are.', sub: 'You’re someone who **trains.**', note: 'Rooted.'},
    {eyebrow: 'HABIT BUILT', title: '66 days.', sub: 'The median time to automatic. **Done.**', note: 'Made it.'},
    {eyebrow: 'DAY 66', title: 'Locked in.', sub: 'No more deciding. **You just go.**', note: 'Second nature.'},
  ],
};

/** the Done moment, by where the session falls in the week */
export const DONE_COPY: Record<Pos, C11[]> = {
  first: [
    {eyebrow: 'FIRST OF THE WEEK', title: 'Week started.', sub: 'The first step is the hardest one. **Done.**', note: 'First step.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'One down.', sub: 'People are most likely to train **at the start of a week.** You did.', note: 'Begun.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'Off the mark.', sub: 'The week is **moving.** Four to go.', note: 'Moving.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'Momentum.', sub: 'Monday done. **The rest gets easier.**', note: 'Rolling.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'Here we go.', sub: 'Session one is down. **The week is yours.**', note: 'Day one.'},
  ],
  middle: [
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: '**3 of 5** done. Look how much is already behind you.', note: 'Keep pushing.'},
    {eyebrow: 'HALFWAY THROUGH THE WEEK', title: 'Past halfway.', sub: 'Only **2 left.** The end is closer than the start.', note: 'Push on.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Still going.', sub: 'The middle is where most people stop. **You didn’t.**', note: 'Onward.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Stacking up.', sub: '**3 sessions** this week. Two more and it’s full.', note: 'Higher.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'On pace.', sub: 'Right on plan. **Two sessions** from a full week.', note: 'Steady.'},
  ],
  last: [
    {eyebrow: 'WEEK COMPLETE', title: 'Five for five.', sub: 'Every session you planned this week. **All of them.**', note: 'Week done.'},
    {eyebrow: 'WEEK COMPLETE', title: 'That’s the week.', sub: 'Five planned, **five done.** Week streak: **6.**', note: 'Closed out.'},
    {eyebrow: 'WEEK COMPLETE', title: 'Perfect week.', sub: 'Most people never finish one. **You just did.**', note: 'Peak.'},
    {eyebrow: 'WEEK COMPLETE', title: 'Finished strong.', sub: 'The last one is what you’ll remember. **You made it count.**', note: 'Summit.'},
    {eyebrow: 'WEEK COMPLETE', title: 'All five.', sub: 'Rest this weekend. **You earned it.**', note: 'Earned.'},
  ],
};

/** numbers for the Done moment, so both modes say the same thing */
export const DONE_DATA: Record<Pos, {week: number; sessions: number; day: number; weekStreak: number}> = {
  first: {week: 1, sessions: 15, day: 43, weekStreak: 5},
  middle: {week: 3, sessions: 17, day: 45, weekStreak: 5},
  last: {week: 5, sessions: 19, day: 47, weekStreak: 6},
};

export const DAYS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
export const MINS = [52, 48, 54, 61, 52, 0, 0];
/** taps it takes to break today's rock; the week's last rock is bigger */
export const tapsFor = (pos: Pos) => (pos === 'last' ? 7 : 5);
export const POS_WEEK: Record<Pos, {done: number; today: number; total: string; next: string; s2: {title: string; sub: string; note: string; research: string}; end: {sub: string; note: string; noteM: string; button: string}}> = {
  first: {
    done: 1, today: 0, total: '52m', next: 'Tuesday',
    s2: {title: '1 of 5.', sub: 'Session one is down. **The week has started.**', note: 'First stone.', research: 'Gym visits jump **33%** at the start of a week. You rode the wave instead of waiting for it.'},
    end: {sub: 'Next: **Tuesday, 07:00.** Keep it rolling.', note: 'Every session breaks a rock. The first one of the week is the hardest to lift.', noteM: 'The first session of the week is the hardest one to start. **Done.**', button: 'See you Tuesday'},
  },
  middle: {
    done: 3, today: 2, total: '2h 34m', next: 'Thursday',
    s2: {title: '3 of 5.', sub: 'More than half done. **Only 2 left.**', note: '2 to go.', research: 'Motivation dips halfway to a goal. The fix is to look ahead: **2 sessions** and the week stands.'},
    end: {sub: 'Next: **Thursday, 07:00.** Only 2 left.', note: 'The middle is where most people stop. You broke another one.', noteM: 'The middle is where most people stop. **You didn’t.**', button: 'See you Thursday'},
  },
  last: {
    done: 5, today: 4, total: '4h 27m', next: 'Monday',
    s2: {title: '5 of 5.', sub: 'Every session done. **The week is full.**', note: 'Week built.', research: 'People remember a stretch of time by its high point and its end. **This is both.**'},
    end: {sub: 'Week **5 of 5.** Week streak **6.** Rest up.', note: 'The last rock of the week, in pieces. That’s how this week will be remembered.', noteM: 'A full week, finished on a high. **That’s how it will be remembered.**', button: 'Week done. See you Monday'},
  },
};


export const strip = (s: string) => s.replace(/\*\*/g, '');
export const dayVariant = () => {
  const d = new Date();
  const start = new Date(d.getFullYear(), 0, 0);
  return Math.floor((d.getTime() - start.getTime()) / 86400000) % 5;
};
