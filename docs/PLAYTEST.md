# Roll the Snowball: playtest guide

## Sync

1. In Studio, open a new Baseplate place (or the Snowball place once it exists).
2. LiveSync panel: repo `JustClips/Snowball`, branch `main`, Connect.
3. To keep saves between tests: Game Settings > Security > Enable Studio Access to API Services. Without it saves use a mock store and reset each test.

## Test commands (chat, admins and anyone in Studio)

| Command | Does |
|---|---|
| `/power 50M` | set Power |
| `/cash 1M` | give cash |
| `/pop Golden` | next Snow Pop tier (stand on your roller) |
| `/egg Rare` | add an egg |
| `/avalanche` | start an Avalanche now |
| `/village` | mark the Village as reached (unlocks Rebirth) |
| `/nextday` | move the reward clock 24 h (daily streak, free wheel spin) |
| `/spins 5` | add Lucky Wheel spins |
| `/keeprolling` | toggle: KEEP ROLLING? shows after every roll, not only near misses |
| `/starter` | put the Starter Pack back on sale (it pops again a few seconds later) |
| `/reset` | wipe your save and kick |

## Checklist

1. Spawn on a base. Tutorial card says STEP 1/5. Walk up to the Snow Roller: it trains Power by itself and the ball spins. Tapping is only for Snow Pops.
2. First Snow Pop at about 5 s is x5. Tap it.
3. At 100 Power press ROLL (walking onto the pad does nothing), tap in the green, push. Steer by dragging (phone) or A/D.
4. The ball grows on snow piles, smashes small obstacles, bonks big ones, cracks and shows results. A Common egg is on the first run.
5. BASE, place the egg, it hatches, the pet starts earning and follows you.
6. Buy the Stone Roller (free in the tutorial). Reach Pine Forest. Tutorial done: free wheel spin toast.
7. DAILY, GIFTS, SPIN, CODES buttons on the left. Try code `SNOWBALL`. Wheel: first spin always lands on the Rare egg.
8. Avalanche meter top centre fills from finished runs (or `/avalanche`): 10 s warning, then 60 s with 2x luck and a bonus egg per run.
9. `/power 50M`, roll to the Village (x3 cash + bonus egg), then REBIRTH appears on the right.
10. SHOP: one scrolling list (Starter Pack banner, Rollers, Eggs, Passes, Boosts + Server Luck, Money, Codes box), section buttons right of the window, purple gift button on giftable cards.
11. Starter Pack: about 6 s after the tutorial ends a big window pops; the chest tile on the right rail shows the countdown and reopens it.
12. Keep Rolling: stop just short of the next zone (or use `/keeprolling`): KEEP ROLLING? card, 8 s timer, buy = the ball rolls on with new snow/coins/eggs; X or the timer cracks it.

**Shop / buying:** open the Shop: one list scrolling down (Featured, Passes, Boosts, Power, Rolls, Money, Codes), 3 cards per row, each with its own picture and what it gives (+$ / +Power). The buttons on the right jump to a section. Press a Buy: the Shop hides, Processing... shows, then BOUGHT! and the Shop comes back. Try to buy an upgrade you can't afford 3 times: Roblox's buy box opens for the cash pack that covers it.

**Studio test buys:** in Studio, any product or pass without an ID is granted for free when you press its Buy (the Output says STUDIO TEST BUY). Live servers show SOON instead. Note: with API access on, test buys save to your real data (`/reset` wipes it).
13. Phone emulator (Studio Device view): check every window fits and the buttons are reachable.

Report anything odd with what you pressed and what you saw (a screenshot helps).
