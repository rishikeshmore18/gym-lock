/**
 * The words for every moment, one version per day of the week, shared by Ridge and Matrix. Each day
 * has its own voice: Monday starts things, Tuesday stacks, Wednesday looks back from the middle,
 * Thursday holds on where most people let go, Friday finishes the most skipped weekday, Saturday is
 * pure choice, Sunday is the quiet day almost nobody trains.
 *
 * The note on each line is the brush note Ridge paints in the sky; it names the day's world.
 * Everything else names only things both modes show.
 */
import type {S4} from '../hero4/card4';
import type {C11, Pos} from '../hero11/copy11';
import {Day, MonthCal, MonthPos} from './days12';

type W7 = [C11, C11, C11, C11, C11, C11, C11];

export const STATE12: Record<S4, W7> = {
  setup: [
    {eyebrow: 'START ON A MONDAY', title: '#SETUP', sub: '', note: 'Fresh start.'},
    {eyebrow: 'FINISH YOUR SYSTEM', title: '#SETUP', sub: '', note: 'Lay the stone.'},
    {eyebrow: 'ALMOST SET', title: '#SETUP', sub: '', note: 'Still water first.'},
    {eyebrow: 'PLANT IT', title: '#SETUP', sub: '', note: 'Roots first.'},
    {eyebrow: 'BASE CAMP', title: '#SETUP', sub: '', note: 'Map the climb.'},
    {eyebrow: 'NO RUSH TODAY', title: '#SETUP', sub: '', note: 'Set it once.'},
    {eyebrow: 'SET UP THE WEEK', title: '#SETUP', sub: '', note: 'By starlight.'},
  ],
  firstnight: [
    {eyebrow: 'DAY ONE TOMORROW', title: 'Charge up.', sub: 'Tuesday, **07:00** at **Iron Works.** Sleep is step one.'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Lights low.', sub: 'Wednesday, **07:00.** A plan with a time and place **gets kept.**'},
    {eyebrow: 'THE NIGHT BEFORE', title: 'Bag packed?', sub: 'Shoes by the door. **Thursday, 07:00.**'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Rest easy.', sub: 'Friday starts it. All you do is **show up.**'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Sleep first.', sub: 'A Saturday start: **quiet floor, free racks.**'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Early night.', sub: 'Sunday is the **quietest gym day** of the week. Yours to own.'},
    {eyebrow: 'DAY ONE TOMORROW', title: 'Monday, day one.', sub: 'More people start on a Monday **than any other day.** Join them.'},
  ],
  bedtime: [
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Recharging.', sub: 'Apps **locked** until 06:30. Muscle **rebuilds** while you sleep.'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Lights out.', sub: 'Tomorrow is planned. **Nothing to decide** in the morning.'},
    {eyebrow: 'SLEEP MODE', title: 'Power down.', sub: 'Halfway through the week. **Sleep carries you through the rest.**'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Off duty.', sub: 'Tomorrow is the day most people skip. **Sleep well and you won’t.**'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Rest up.', sub: 'A Saturday session tomorrow. **Apps back at 06:30.**'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Wind down.', sub: 'Your phone sleeps too. **Nothing to scroll till morning.**'},
    {eyebrow: 'LOCKED FOR SLEEP', title: 'Refuel.', sub: 'New week at **07:00.** Good sleep is **part of the workout.**'},
  ],
  wake: [
    {eyebrow: 'ALARM · 06:30', title: 'Rise.', sub: 'Monday is **the busiest gym day** of the week. Be part of it.'},
    {eyebrow: 'ALARM · 06:30', title: 'Feet down.', sub: 'Apps stay locked until you’re **at the gym.**'},
    {eyebrow: 'GOOD MORNING', title: 'Up.', sub: 'Midweek. **First win of the day:** out of bed.'},
    {eyebrow: 'ALARM · 06:30', title: 'New day.', sub: 'Thirty minutes from now you’ll be **glad you went.**'},
    {eyebrow: 'ALARM · 06:30', title: 'Last push.', sub: 'Friday is **the most skipped weekday.** Not by you.'},
    {eyebrow: '06:30', title: 'Morning.', sub: 'No commute, no meetings. **Just the gym.**'},
    {eyebrow: 'ALARM · 06:30', title: 'Quiet start.', sub: 'The gym is at its **emptiest** on a Sunday. All yours.'},
  ],
  countdown: [
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'Bag ready? The week **starts with this one.**'},
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'Same time, same place. **That’s how it sticks.**'},
    {eyebrow: 'UNTIL 07:00', title: '#CLOCK', sub: 'People who plan **when and where** follow through 91% of the time.'},
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'Planned, so it **happens.** No decision to make.'},
    {eyebrow: 'COUNTING DOWN', title: '#CLOCK', sub: 'Iron Works at 07:00. **Finish what Monday started.**'},
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'A Saturday session is **pure choice.** Make it.'},
    {eyebrow: 'GYM TIME IN', title: '#CLOCK', sub: 'Train today and Monday starts **with momentum.**'},
  ],
  ready: [
    {eyebrow: 'ALARM BEATEN', title: 'Get ready.', sub: 'Shoes on. **Out by 06:45.**', note: 'Go.'},
    {eyebrow: 'ALARM BEATEN', title: 'Shoes on.', sub: 'The hardest rep is **the front door.**', note: 'Move.'},
    {eyebrow: 'UP AND MOVING', title: 'Out the door.', sub: 'Fifteen minutes to **Iron Works.**', note: 'Push off.'},
    {eyebrow: 'ALARM BEATEN', title: 'You’re up.', sub: 'That was the hard part. **Now just go.**', note: 'Onward.'},
    {eyebrow: 'GET READY', title: 'Grab the bag.', sub: 'Out by **06:45.** Done by 07:30.', note: 'Climb.'},
    {eyebrow: 'GET READY', title: 'Easy pace.', sub: 'No traffic on a Saturday. **Out by 06:45.**', note: 'Low tide.'},
    {eyebrow: 'UP EARLY', title: 'Out you go.', sub: 'An empty gym is the best gym. **Out by 06:45.**', note: 'Go.'},
  ],
  commute: [
    {eyebrow: 'ON YOUR WAY', title: '6 min out.', sub: 'The hard part **is behind you.**'},
    {eyebrow: 'ON YOUR WAY', title: 'Almost there.', sub: 'You’re out the door. **That was the win.**'},
    {eyebrow: 'EN ROUTE', title: '6 min out.', sub: 'Apps unlock **when you walk in.**'},
    {eyebrow: 'ON YOUR WAY', title: 'Moving.', sub: 'Showing up is **most of it.**'},
    {eyebrow: 'HEADING IN', title: 'Nearly there.', sub: 'Iron Works in **6 minutes.**'},
    {eyebrow: 'ON YOUR WAY', title: 'Rolling in.', sub: 'Weekend roads. **Six minutes out.**'},
    {eyebrow: 'EN ROUTE', title: 'Six minutes.', sub: 'Most people are still asleep. **You’re on your way.**'},
  ],
  atgym: [
    {eyebrow: 'AT THE GYM', title: '#LIVE', sub: ''},
    {eyebrow: 'ON THE FLOOR', title: '#LIVE', sub: ''},
    {eyebrow: 'CHECKED IN', title: '#LIVE', sub: ''},
    {eyebrow: 'AT IRON WORKS', title: '#LIVE', sub: ''},
    {eyebrow: 'IN SESSION', title: '#LIVE', sub: ''},
    {eyebrow: 'ON THE FLOOR', title: '#LIVE', sub: ''},
    {eyebrow: 'CHECKED IN', title: '#LIVE', sub: ''},
  ],
  verified: [
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: ''},
  ],
  stilltime: [
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: '**20 minutes** tonight and Monday counts.'},
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: 'Today is a planned day. **Twenty minutes counts.**'},
    {eyebrow: 'BEFORE THE DAY ENDS', title: '#LEFT', sub: 'A short session **beats a skipped one.**'},
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: 'The gym is open **until 22:00.**'},
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: 'Go tonight and **the weekend starts earned.**'},
    {eyebrow: 'TODAY’S STILL OPEN', title: '#LEFT', sub: 'Saturday evenings are quiet. **Twenty minutes is enough.**'},
    {eyebrow: 'STILL TIME TODAY', title: '#LEFT', sub: 'Go now and **Monday starts on a win.**'},
  ],
  rest: [
    {eyebrow: 'REST DAY', title: 'Recover.', sub: 'Muscle is built **between** sessions.', note: 'Stronger tomorrow.'},
    {eyebrow: 'REST DAY', title: 'Rest is training.', sub: 'Planned rest **protects the streak.**', note: 'Easy does it.'},
    {eyebrow: 'DAY OFF', title: 'Still water.', sub: 'Walk, stretch, sleep. **Back tomorrow.**', note: 'Settle.'},
    {eyebrow: 'REST DAY', title: 'Breathe.', sub: 'Nothing to do today **but recover.**', note: 'Roots grow quiet.'},
    {eyebrow: 'RECOVERY', title: 'Off day.', sub: 'Your streak is safe. **Rest is in the plan.**', note: 'Take in the view.'},
    {eyebrow: 'REST DAY', title: 'Weekend.', sub: 'You earned it. **Nothing to unlock today.**', note: 'Low tide.'},
    {eyebrow: 'REST DAY', title: 'Recharge.', sub: 'Rest now, **new week tomorrow.** Sleep early.', note: 'Count the stars.'},
  ],
  paused: [
    {eyebrow: 'STREAK FROZEN', title: 'Off the clock.', sub: 'Sick or travelling? Frozen days **don’t count against you.**', note: 'Frozen, not lost.'},
    {eyebrow: 'STREAK FROZEN', title: 'On hold.', sub: 'Your streak waits **right here.**', note: 'Under snow.'},
    {eyebrow: 'PAUSED', title: 'Take the break.', sub: 'Come back when you’re ready. **Nothing is lost.**', note: 'Iced over.'},
    {eyebrow: 'STREAK FROZEN', title: 'Rest up.', sub: 'Get well first. **The plan waits.**', note: 'Winter.'},
    {eyebrow: 'STREAK FROZEN', title: 'Hold position.', sub: 'The summit isn’t going anywhere. **Neither is your streak.**', note: 'Snowed in.'},
    {eyebrow: 'AWAY', title: 'Enjoy it.', sub: 'Frozen days **don’t break the chain.**', note: 'Back soon.'},
    {eyebrow: 'STREAK FROZEN', title: 'Paused.', sub: 'The count stays where you left it. **Come back to it.**', note: 'It’ll keep.'},
  ],
  freshstart: [
    {eyebrow: 'NEW WEEK', title: 'New week.', sub: 'Last week: **4 sessions, 3h 12m.** Gym visits jump **33%** at the start of a week.', note: 'Again.'},
    {eyebrow: 'NEW WEEK', title: 'Clean slate.', sub: 'Last week is banked. **First session today.**', note: 'New cairn.'},
    {eyebrow: 'NEW WEEK', title: 'Zero of five.', sub: 'One session and the week **is moving.**', note: 'Calm water.'},
    {eyebrow: 'NEW WEEK', title: 'Go again.', sub: 'Last week, **4 for 5.** This week, start strong.', note: 'New growth.'},
    {eyebrow: 'NEW WEEK', title: 'Week 8.', sub: 'A new week is **a fresh start.** People train more on them. Ride it.', note: 'Back to base.'},
    {eyebrow: 'NEW WEEK', title: 'Begin.', sub: 'Nothing on the board yet. **Today puts one there.**', note: 'Fresh sand.'},
    {eyebrow: 'NEW WEEK', title: 'Day one.', sub: 'Seven days, **five sessions.** The first is today.', note: 'First star.'},
  ],
  missed: [
    {eyebrow: 'MISSED YESTERDAY', title: 'Never twice.', sub: 'One miss doesn’t undo a habit. **Today keeps it.**'},
    {eyebrow: 'MISSED YESTERDAY', title: 'Back today.', sub: 'Missing once has **no real effect** on habit forming.'},
    {eyebrow: 'YESTERDAY SLIPPED', title: 'Today counts.', sub: 'One day is a blip. **Two is a pattern.**'},
    {eyebrow: 'MISSED YESTERDAY', title: 'Reset.', sub: 'Twenty minutes today and **the week is back.**'},
    {eyebrow: 'ONE MISS', title: 'Not two.', sub: 'Go today and **yesterday won’t matter.**'},
    {eyebrow: 'MISSED YESTERDAY', title: 'Make it up.', sub: 'The weekend is **the perfect catch-up.** Go today.'},
    {eyebrow: 'MISSED YESTERDAY', title: 'Still time.', sub: 'The week isn’t over **until tonight.**'},
  ],
  weekkept: [
    {eyebrow: 'WEEK KEPT', title: '5 of 5.', sub: 'Every planned session, **stacked.**', note: 'Week built.'},
    {eyebrow: 'WEEK KEPT', title: 'Full week.', sub: 'Five planned, **five done.**', note: 'Stacked.'},
    {eyebrow: 'WEEK KEPT', title: 'Perfect week.', sub: 'Week streak: **5.** Keep the run going.', note: 'Full circle.'},
    {eyebrow: 'WEEK DONE', title: 'All five.', sub: 'You kept **every promise** this week.', note: 'Grown.'},
    {eyebrow: 'WEEK KEPT', title: 'Closed out.', sub: 'Five for five. **Rest well this weekend.**', note: 'Lit.'},
    {eyebrow: 'WEEK KEPT', title: 'Kept.', sub: 'Five sessions, **zero excuses.** Enjoy the weekend.', note: 'Lanterns up.'},
    {eyebrow: 'WEEK KEPT', title: 'Every one.', sub: 'A full week, **start to finish.** Tomorrow, go again.', note: 'All lit.'},
  ],
  comeback: [
    {eyebrow: 'WELCOME BACK', title: 'Start again.', sub: 'A Monday comeback rides **the fresh-start wave.**', note: 'Back at it.'},
    {eyebrow: 'WELCOME BACK', title: 'Good to see you.', sub: 'Just 20 minutes **restarts the run.**', note: 'New stone.'},
    {eyebrow: 'BACK', title: 'Day one, again.', sub: 'Everyone restarts. **The ones who win do it fast.**', note: 'Push off.'},
    {eyebrow: 'WELCOME BACK', title: 'Pick it up.', sub: 'A return after a break is **the habit working.**', note: 'Still rooted.'},
    {eyebrow: 'WELCOME BACK', title: 'Fresh start.', sub: 'Bonus waiting **when you check in.**', note: 'Climb again.'},
    {eyebrow: 'WELCOME BACK', title: 'Back on it.', sub: 'No better day to restart than **one with no alarm.**', note: 'Tide’s in.'},
    {eyebrow: 'WELCOME BACK', title: 'Here again.', sub: 'Start today and **next week starts strong.**', note: 'First light.'},
  ],
  drift: [
    {eyebrow: 'WEEK 4', title: 'Drift zone.', sub: 'Most slip to **once a week** by week 6. **Not you.**', note: 'Keep going.'},
    {eyebrow: 'WEEK 4', title: 'Stay sharp.', sub: 'This is where **most people fade.**', note: 'Push through.'},
    {eyebrow: 'THE MIDDLE', title: 'Keep going.', sub: 'The middle is **the hardest part.** It passes.', note: 'Through it.'},
    {eyebrow: 'WEEK 4', title: 'Hold the line.', sub: 'New members plan 3 a week. **By week 6, 1.** Not you.', note: 'Steady.'},
    {eyebrow: 'WEEK 4', title: 'Stay the course.', sub: 'The fog lifts **if you keep walking.**', note: 'Onward.'},
    {eyebrow: 'WEEK 4', title: 'Don’t drift.', sub: 'The novelty is gone. **Routine is what’s left.** Lean on it.', note: 'Hold course.'},
    {eyebrow: 'WEEK 4', title: 'Stay on it.', sub: 'Motivation fades by design. **The plan doesn’t.**', note: 'Find north.'},
  ],
  halfway: [
    {eyebrow: 'HABIT FORMING', title: 'Day 33.', sub: 'Halfway up. **13 sessions** in.', note: 'Halfway up.'},
    {eyebrow: 'HALFWAY', title: 'Halfway.', sub: 'Habits take **66 days** on average. You’re at 33.', note: 'Keep climbing.'},
    {eyebrow: 'DAY 33 OF 66', title: 'Half there.', sub: 'From here, **the end is closer** than the start.', note: 'Mid-lake.'},
    {eyebrow: 'HABIT FORMING', title: 'Day 33.', sub: 'It’s getting **easier** than it was.', note: 'Halfway grown.'},
    {eyebrow: 'DAY 33', title: 'Midpoint.', sub: '33 days behind you. **33 to automatic.**', note: 'Look up.'},
    {eyebrow: 'HALFWAY', title: 'Day 33.', sub: 'Halfway to automatic. **The hard half is done.**', note: 'Half tide.'},
    {eyebrow: 'DAY 33 OF 66', title: 'Halfway.', sub: 'Half the shape is there. **33 days to the rest.**', note: 'Half lit.'},
  ],
  automatic: [
    {eyebrow: 'DAY 66', title: 'Automatic.', sub: '66 days is the median. **It’s yours now.**', note: 'Risen.'},
    {eyebrow: 'DAY 66', title: 'Habit made.', sub: 'It runs **on its own** now.', note: 'Unbreakable.'},
    {eyebrow: 'DAY 66', title: 'Who you are.', sub: 'You’re someone who **trains.**', note: 'Far shore.'},
    {eyebrow: 'HABIT BUILT', title: '66 days.', sub: 'The median time to automatic. **Done.**', note: 'Rooted.'},
    {eyebrow: 'DAY 66', title: 'Locked in.', sub: 'No more deciding. **You just go.**', note: 'Summit.'},
    {eyebrow: 'DAY 66', title: 'Second nature.', sub: 'What took effort **now takes none.**', note: 'Set sail.'},
    {eyebrow: 'DAY 66', title: 'Automatic.', sub: 'Every piece in place. **This is who you are now.**', note: 'All lit.'},
  ],
};

/** the Done moment: by where the session falls in the week, then by the day */
export const DONE12: Record<Pos, W7> = {
  first: [
    {eyebrow: 'FIRST OF THE WEEK', title: 'Week started.', sub: 'Monday is the **busiest gym day** of the week. You were in it.', note: 'Sun’s up.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'One down.', sub: 'Monday slipped, Tuesday didn’t. **The week still counts.**', note: 'First stone.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'Off the mark.', sub: 'A midweek start is still **a start.** Four to go.', note: 'First skip.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'Started.', sub: 'Late in the week and **still in it.** That’s the habit.', note: 'New growth.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'Got one in.', sub: 'Friday is the most skipped weekday. **You started on it.**', note: 'First light.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'On the board.', sub: 'A weekend session **saves the week.**', note: 'First lantern.'},
    {eyebrow: 'FIRST OF THE WEEK', title: 'One down.', sub: 'Sunday is the **quietest gym day.** You came anyway.', note: 'First star.'},
  ],
  middle: [
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: '**3 of 5.** Look how much is already behind you.', note: 'Keep rising.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Stacking up.', sub: '**3 sessions** this week. Two more and it’s full.', note: 'Stacked.'},
    {eyebrow: 'HALFWAY THROUGH THE WEEK', title: 'Past halfway.', sub: 'Only **2 left.** The end is closer than the start.', note: 'Keep going.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Still going.', sub: 'Thursday to Friday is where most people **drop off.** Not you.', note: 'Taller.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'On pace.', sub: 'Friday done. **Two sessions** from a full week.', note: 'Higher.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Weekend work.', sub: '**3 this week,** one on a Saturday. That’s commitment.', note: 'Let it rise.'},
    {eyebrow: 'WORKOUT VERIFIED', title: 'Done.', sub: 'The quietest day, **the strongest habit.** 3 of 5.', note: 'Three lit.'},
  ],
  last: [
    {eyebrow: 'WEEK COMPLETE', title: 'Five for five.', sub: 'Every session you planned this week. **All of them.**', note: 'Week done.'},
    {eyebrow: 'WEEK COMPLETE', title: 'That’s the week.', sub: 'Five planned, **five done.** Week streak: **6.**', note: 'Closed out.'},
    {eyebrow: 'WEEK COMPLETE', title: 'Perfect week.', sub: 'Most people never finish one. **You just did.**', note: 'Far shore.'},
    {eyebrow: 'WEEK COMPLETE', title: 'Finished early.', sub: 'Five done **before the weekend.** It’s all yours now.', note: 'Full grown.'},
    {eyebrow: 'WEEK COMPLETE', title: 'Finished strong.', sub: 'Friday is the most skipped weekday. **You closed the week on it.**', note: 'Summit.'},
    {eyebrow: 'WEEK COMPLETE', title: 'All five.', sub: 'The last one is what you’ll remember. **You made it count.**', note: 'Let them go.'},
    {eyebrow: 'WEEK COMPLETE', title: 'Week, complete.', sub: 'Closed on a Sunday. **Monday starts with a full tank.**', note: 'All seven.'},
  ],
};

// ---------- the first and last weeks of a month ----------
const FIRST_FRESH = [
  'New week **and** new month. A double fresh start.',
  '**#M** starts clean. So does the week.',
  'A new month lifts gym visits **14%** on its own. Use it.',
  'First week of #M. **Set the tone.**',
  '#M is a blank page. **Write the first line today.**',
  'Nothing on the #M calendar yet. **Start it today.**',
  'Start #M the way you want to **finish it.**',
];

/** the copy a card shows: the day's version, with the month's first and last weeks layered on */
export const cardCopy = (s: S4, day: Day, pos: Pos, mp: MonthPos, cal: MonthCal): C11 => {
  const base = s === 'verified' ? DONE12[pos][day] : STATE12[s][day];
  const M = cal.name;
  const MU = M.toUpperCase();
  if (mp === 'first') {
    if (s === 'freshstart') return {...base, eyebrow: 'NEW WEEK · NEW MONTH', sub: FIRST_FRESH[day].replace(/#M/g, M)};
    if (s === 'verified')
      return pos === 'first'
        ? {...base, eyebrow: `FIRST OF ${MU}`, sub: `${M}’s first session. **${cal.sessions} of ${cal.target}** for the month.`}
        : {...base, eyebrow: `${cal.short} · ${cal.sessions} OF ${cal.target}`};
  }
  if (mp === 'last') {
    const before = cal.sessions - 1;
    if (s === 'freshstart') return {...base, eyebrow: `LAST WEEK OF ${MU}`, sub: `**${Math.max(0, cal.target - before)} sessions** to your ${M} target. Finish the month strong.`};
    if (s === 'weekkept') return {...base, eyebrow: `${cal.short} · ${cal.sessions} OF ${cal.target}`, sub: `A full week to close out ${M}. **Best way to end one.**`};
    if (s === 'verified')
      return cal.sessions >= cal.target
        ? {...base, eyebrow: `${MU} · TARGET HIT`, sub: `**${cal.sessions} sessions** in ${M}. Your best month yet.`}
        : {...base, eyebrow: `${cal.short} · ${cal.sessions} OF ${cal.target}`, sub: `**${cal.target - cal.sessions} more** and ${M} hits its target. **The finish is in sight.**`};
  }
  return base;
};

/** the month screen in the done flow (first and last weeks only) */
export const monthScreen = (mp: MonthPos, pos: Pos, cal: MonthCal) => {
  const M = cal.name;
  if (mp === 'first') {
    if (pos === 'first')
      return {
        eyebrow: 'NEW MONTH',
        title: `${M}.`,
        sub: 'A fresh month. **Pick your target** for it.',
        research: 'Gym visits rise **14%** at the start of a month. A new chapter makes last month’s misses feel like someone else’s, so goals set now **stick better.**',
        note: 'New month.',
        pick: true,
      };
    return {
      eyebrow: `${M.toUpperCase()} SO FAR`,
      title: `${cal.sessions} of ${cal.target}.`,
      sub: 'The first week sets **the pace for the month.**',
      research: 'The start of a month is a fresh start: people train more in it than in any other week. **Bank as much of it as you can.**',
      note: 'Strong start.',
      pick: false,
    };
  }
  const hit = cal.sessions >= cal.target;
  const h = Math.floor(cal.minutes / 60), mm = cal.minutes % 60;
  return {
    eyebrow: hit ? `${M.toUpperCase()}, DONE` : `${M.toUpperCase()}, SO FAR`,
    title: `${cal.sessions} sessions.`,
    sub: `**${h}h ${String(mm).padStart(2, '0')}m** on the floor. Best week: **week ${cal.bestWeek}, ${cal.bestWeekN} of 5.**`,
    research: hit
      ? 'Target hit. People remember a month by its high point and its end. **This is both.**'
      : `**${cal.target - cal.sessions} to go.** The closer the finish line, the faster people move toward it.`,
    note: hit ? 'Month done.' : 'Home stretch.',
    pick: false,
  };
};
