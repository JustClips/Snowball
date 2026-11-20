# Balance (economy and progression)

Pass of 20 Nov 2026, after Dev's report: "I have 1B Power and still can't reach the Village, and a 3 km
roll pays 1-2K while my pets make millions in the same time."

Everything here comes from two scripts that read the real Luau configs, so rerun them after any change:

```
python3 tools/balance/rollsim.py 0.5     # Power -> distance, size, bonks, run cash (skill 0..1)
python3 tools/balance/sim.py --hours 20  # free player from join to rebirth 7, milestone table
python3 tools/balance/sim.py --verbose   # + run cash vs pet income over time
```

`rollsim.py` runs the same step as `src/shared/Roll.luau`, with the real track, obstacle layout,
pickups and hit rules. A simulated player steers toward snow and coins and dodges obstacles it
would bonk on, with a chance (`skill`) of noticing each one. `sim.py` loops: train (auto reps plus 60% of
Snow Pops claimed), roll, carry the eggs home, hatch on 4 spots, keep the best pets placed, buy
the cheapest useful upgrade, and rebirth once it has reached the Village. It also counts time for
the pack, the crack card, the egg rescue walk and the trip home.

## What we copied, and from where

- **Steal an Egg (vault teardown):** "speed is the gate, money is the fuel". Pets make the money.
  The trained stat opens the next biome. Our Power works like their speed, rolling into zones works
  like their biomes, and pets stay the main income. The roll still has to be worth doing on its own.
- **Throw Food For Animals (our reference study):** the throw is the fun part and it delivers the
  animals. Pull-up stands and treadmills come in named tiers bought one by one with cash, plus
  Robux tiers. We kept the roller ladder, and the next roller is always the main cash goal.
- **Tizzy playbook (robloxdev.academy):** zone 1 at 0:50 and zone 2 at about 5 minutes in his test
  logs. He logs these milestones for each update. Retention comes before revenue. Cheap,
  stackable consumables beat passes. Don't sell the economy (no 9 R$ pack that skips the game).
- **LihFolk vault, Progression and Pacing / Pricing Curves / Rarity Ladders / Simulators playbook:**
  - Players feel time per step, not prices.
  - Price things in minutes of income.
  - The rebirth multiplier should be geometric and grow slightly slower than the rebirth cost.
  - Cap each multiplier category.
  - Watch luck inflation: luck stacks multiply and push the rarity ladder up.

## The three bugs behind Dev's report

### 1. No amount of Power could reach the Village

A smash multiplied the distance still to go by 0.95² (x0.90) and a bonk by 0.65² (x0.42). A deep
roll smashes about 10 things and bonks 2, so the ball kept about 15% of its run. With the old
numbers (rollsim, skill 0.5):

| Power | target | real distance before | real distance now | Village before | Village now |
|---|---|---|---|---|---|
| 1M | 2,544 | 1,452 | 2,951 | 0% | 0% |
| 10M | 4,102 | 1,728 | 4,409 | 0% | 0% |
| 50M | 5,500 | 1,757 | 5,537 | 0% | 77% |
| 1B | 6,000 | 1,814 | 5,560 (wall) | 0% | 100% |

Fix (`Roll.luau`):
- A hit now takes a flat share of the roll's launch distance. A smash costs 0.05% (`SmashLoss`). A bonk costs 2.5%, at least 20 studs (`BonkLoss`, `BonkMin`).
- The speed drops after hits stay, so they still feel the same.
- The Power curve now ends at 5B = 7,000 studs (was 500M = 6,000), so Power past the Village
  buys forgiveness for bonks.

The ball also has to be big enough for the zone you reach, or every deep obstacle bonks:
- Snow piles now come every 18 studs (was 22).
- Lake, Cave and Aurora obstacles need 1-3 less size: 8/11, 14/17 and 21/25.
- A ball reaching a zone now smashes most of its obstacles and still has to dodge the big ones: about 1-2 bonks a roll at skill 0.5.

### 2. A roll paid nothing next to the pets

Run cash was coins + smashes + radius × CoinValue × 2. CoinValue only went 1 → 120 while pet zone income goes 1 → 250,
and run cash never followed your pets. In the old sim, pets made 99% of all cash and a roll was worth
1-20 seconds of pet income.

Fix (`Zones.luau`, `RollService.finish`):
- CoinValue is steeper: 1 / 3 / 10 / 40 / 150 / 500.
- New per-zone `CrackSeconds` (15 / 20 / 30 / 40 / 50 / 60): when the ball cracks, it also pays
  that many seconds of your pets' income. The Village x3 applies on top, so 180 s at the wall.
- Result: a roll pays 40-130 s of pet income (about 200 s at the Village). Runs make about 1/3 of
  all cash and pets about 2/3, the Steal an Egg split with a roll that always matters. A 3 km roll
  (Cave/Aurora) pays about $40K-180K where it paid about $1-2K.

### 3. Rebirths collapsed into minutes, then would have walled

- The cash multiplier was +50% per rebirth (linear) against a cost growing x1.6. The vault calls
  this the most common rebirth mistake.
- Pets are kept through a rebirth and their training boost had no cap. Three Village Mythics gave
  x75 training, so after Rebirth 1 the next ones took 15-25 minutes each.

Fix (`Economy.luau`, `PetService`):
- `rebirthCashMult` is now x1.5 per rebirth (geometric, like training), against a cost of $40M × 5^n.
- Pet training bonus is capped at +1,500% (`PetTrainBonusCap`, x16).

## Luck inflation

The egg roll multiplied tier n's weight by luck^((n-1) × 0.5). The free Aurora Core alone (x12)
made 33% of Aurora eggs Mythic. A 9 R$ Super Lucky Roll (x100) at the Village was a near-certain
Secret, a pet worth 150K/s.

- `Eggs.LuckPower` is now 0.3.
- Core luck is now 1 / 1.3 / 1.7 / 2.2 / 3 / 4 (was up to 12).

Village egg with the new numbers:

| luck | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|
| 1 | 30% | 30% | 22% | 12% | 5.9% | 0.1% |
| 4 (Aurora Core) | 15% | 23% | 25% | 21% | 16% | 0.4% |
| 12 | 7% | 15% | 23% | 27% | 28% | 1.0% |
| 100 (Super Lucky) | 1% | 4% | 12% | 27% | 52% | 3.5% |
| 500 | 0.2% | 1% | 6% | 21% | 65% | 7% |

First hatch of each rarity in the sim:
- Uncommon 8 min, Rare 12 min, Epic 29 min, Legendary 1.1 h, Mythic 3.9 h, Secret about 18 h.
- So the next tier you don't have is usually one or two sessions away (vault rule).

## Pacing: free player, phone pace (sim.py, 6 seeds, median)

| Milestone | Now | Plan (GAME_PLAN 5.2) / Tizzy |
|---|---|---|
| Pine Forest, Stone Roller | 2 min | 2 min / zone 1 at 0:50 |
| Frozen Lake, Iron Roller | 8-9 min | 12-15 min / zone 2 at ~5 min |
| Gold Roller | 22 min | |
| Ice Cave | 29 min | 35-40 min |
| Crystal Roller | 44 min | |
| Aurora Valley | 1.0 h | 1.25 h |
| Diamond Roller | 1.4 h | |
| The Village | 2.2 h | |
| Rebirth 1 | 2.6 h | 2-2.5 h |
| Rebirth 2 / 3 / 4 / 5 | 4.1 / 5.5 / 7.2 / 9.6 h | |
| Rebirth 6 / 7 | 15 / 19 h | |

- The first hour is a bit faster than the plan, because the playbook says first-session retention decides everything.
- The time between rebirths rises gently (1.5, 1.4, 1.7, 2.4 h), then steeply after Rebirth 5.
  That is where mountain 2 (18 Dec) has to take over. Before then, add a Glacier+ roller or a
  second Village goal.

Prices that changed:
- **Rollers:** Iron 1.5K (was 5K), Gold 25K (60K), Crystal 300K (800K), Diamond 4M (10M), Aurora 60M (150M), Glacier 1B (2.5B, still Rebirth 2).
- **Zone Power:** Lake 12K (was 25K), Cave 200K (400K), Aurora 3M (5M). Village is still 50M: it's reached about 3 in 4 times there, every time from about 100M+.
- **Pet zone income:** Village is now x250 (was x120), so the Village egg is a real jump over Aurora (x80).

## Robux value check

Unit: minutes of free play the product is worth. A free player trains at about 3.4 reps/s
(0.8 auto + claimed pops) and pets make about 2/3 of their cash.

| Product | R$ | Worth before | Worth now |
|---|---|---|---|
| Power Pack I / II / III / IV | 3 / 9 / 39 / 99 | 0.2 / 0.9 / 4.7 / 14 min | 0.5 / 2 / 10 / 29 min |
| 5 / 15 / 30 min of Training | 39 / 99 / 179 | 1.2 / 3.5 / 7 min (!) | 9 / 26 / 52 min |
| Rainbow Pop x25 / x50 / x100 | 19 / 39 / 79 | 12 / 23 / 46 min | same |
| 2x Power 10 min | 13 | 10 min | same |
| Cash packs | 25 / 59 / 149 / 399 | 6.5 / 20 / 59 / 195 min | same |
| Huge Penguin / Wolf / Polar Bear / Dragon | 99 - 4,999 | Meadow income (5K/s Dragon < one free Aurora Legendary) | income from your best zone, like bought eggs |

- Training Time used the 0.8 reps/s auto rate, so "30 min" was worth 7 real minutes. It was a
  worse deal than Power Pack III at a quarter of the price. It now pays at
  `Economy.TrainTimeRepsPerSecond` = 6 (Fast Train + every pop claimed). Pops still use
  `AutoTrainTapsPerSecond`.
- Value per Robux now rises with price (bigger pack = better deal), and Rainbow Pops stay the
  best value, as planned (the top earner in DIRECTION.md).
- No product skips the game. The biggest Power Pack is about 30 minutes, and Power needs about
  x15 per zone.

## Saves

No save fields were added, renamed or removed:
- Old Power, Cash, rollers, cores and pets keep their meaning.
- Players with rebirths get more cash than before (1.5^n instead of 1 + 0.5n).
- Owned Huge pets keep their old zone. Only new purchases use the best zone.

## When you tune

- Change one base at a time and rerun both scripts (vault: compounding sensitivity).
- Check the end of the ladder, not only the first 10 steps (the late rebirths), and watch the
  "run = secs of pets" column stays roughly between 40 and 200.
- After launch, compare with real saves: Stats.Runs, BestZone, Rebirths and Playtime per player.
  Playbook: wait about 3 days before you judge, and ship one hypothesis per update.
