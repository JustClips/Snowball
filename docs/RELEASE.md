# Roll the Snowball: release readiness

Launch: Thu 10 Dec 2026. Dev's order (20 Nov): keep improving until it's ready. Each line is
checked by playing it as a 10-year-old on a phone: no reading needed, never stuck, always a
next goal, every tap feels good. `[x]` = done and seen working in Studio, `[~]` = built but not
yet confirmed in Studio, `[ ]` = to do. Owner = the thread that does it.

## P0: must work on launch day

### First 5 minutes (Build thread)
- [~] Spawn on a base, the tutorial arrow points at the roller, training starts by itself
- [~] ROLL is the only way to start a launch (walking on the pad does nothing)
- [~] Pack meter: tap in the green, PERFECT/GOOD/WEAK word, ball launches
- [~] Ball grows, smashes, bonks, cracks; first run always gives an egg
- [~] Egg run: eggs on top of the pile with rarity tags, carry to the flag, yeti chases with real animations
- [~] Result card shows AFTER the eggs are home, with the eggs actually saved
- [ ] Place egg on base, hatch show, pet earns, "+$X/s" under cash
- [ ] Tutorial never softlocks (leave mid-step, rejoin, die, reset)

### Core systems (Build thread)
- [~] Egg strip while rolling: eggs in the ball as tiles under STOP, tap one to drop it, red flash when full
- [~] Lucky roll every 10th roll (x5), rainbow ball; counter above ROLL (UI thread restyled it)
- [ ] Upgrades sign, rebirth, zones 1-6, Village bonus
- [ ] Avalanche event
- [ ] Daily / Gifts / Wheel / Codes give what they show
- [ ] Saves: rejoin keeps everything; two servers can't double-load a save

### Money (Shop thread)
- [ ] Every product and pass created on universe 10778042297, ids in ProductIds.luau, prices match Products.luau (YetiRepellent 9, SledHome 25)
- [x] Buying shows what you got ("+$424M CASH", "+9.6K POWER"), not the product name, top centre
- [x] "Not enough cash" 3rd time prompts the cash product that covers it
- [ ] Offer timing: Starter Pack, Keep Rolling, Sled Home, No Yeti never stack on screen (offers now never show while rolling or rescuing; check in a live session)
- [x] Offers at the right moments: rare hatch -> Lucky Rolls, 3 rolls without a best -> Power pack, stuck on the next roller -> the cash pack that buys it, 8 min in -> 2x Cash (OfferService rules 9-12)

### Look (UI thread, Pet thread)
- [ ] One UI style everywhere (HUD, windows, rescue buttons, results, hatch, bag)
- [ ] Phone layout: nothing overlaps at 667x375, buttons 44 px+
- [ ] Bag/inventory and "you hatched" screens redone; pets face the camera in the bag

### Tech (Build thread)
- [x] Every asset granted to the owner account (tools/grant_all.py after each upload)
- [ ] No errors or warnings in Studio output during a full session
- [ ] Phone performance: 60 fps on a mid phone with 8 players rolling
- [ ] Remote rate limits + server checks on every client call

### Store page (Dev + Build thread)
- [ ] Icon, 3+ thumbnails, title, description, maturity questionnaire
- [ ] Credits line for any CC-BY asset (none in Snowball so far)

## P1: first week
- [ ] Analytics funnels (tutorial steps, first roll, first hatch, first purchase) visible in the dashboard
- [ ] Global leaderboards (distance, eggs)
- [ ] Christmas Egg update ready for 13 Dec
