# Roll the Snowball: architecture

Design: `GAME_PLAN.md` in the project files (game-ideas/roll-the-snowball/). This file says where things live in code.

## Layout (Rojo style, synced by LiveSync)

| Folder | Becomes | What |
|---|---|---|
| `src/shared` | ReplicatedStorage.Shared | Net, BigNum, Format, Signal, Spline, Roll, RollMath, PowerCurve, PetLook, Types, `Config/*` |
| `src/server` | ServerScriptService.Server | `Main.server.luau`, `Services/*`, `Lib/*` (ProfileStore, MockDataStore, PetModels), `Config/Codes` |
| `src/client` | StarterPlayerScripts.Client | `Main.client.luau`, `State`, `Ui`, `Controllers/*` |

## Boot

Server `Main` requires every service in `ORDER`, calls all `Init(services)`, then all `Start()`. Services call each other through the shared `services` table (`S.X:Method()`), so there are no require cycles. The client does the same with controllers (`Init(controllers)` then `Start()`).

## Data and state

- `DataService`: session-locked profiles (ProfileStore rules from Sweep), `TEMPLATE` with reconcile for new keys, MockDataStore in Studio without API access.
- `StateService`: builds the player snapshot and sends it after `Mark(player)` (flush every 0.15 s). Pets/Eggs only travel when `InvVersion` changes. Server-wide values are attributes on `ReplicatedStorage.ServerState` (Server Luck, Avalanche meter, crown).
- Client `State.data` holds the last snapshot; controllers use `State.observe(fn)`.

## The roll

Server-authoritative 2D sim: a ball is `(s, x)` on the track spline (`Config/Track`, `Spline`). `PowerCurve.distance(power)` × pack quality sets the target distance; `Roll.step` brakes so it stops there. Smash/bonk/ramp change the remaining distance. Server sims at 20 Hz, sends 10 Hz buffer snapshots (`RunSnapshot`); the client predicts with the same `Roll.step`. Pickups come from a per-run seed, so server and client generate the same ones.

## Services (server)

| Service | Job |
|---|---|
| Data, Analytics, State | saves, funnels/custom events, snapshots |
| World, Base | graybox summit/track/wheel stand, base assignment and teleports |
| Cash, Boost | cash in/out, every multiplier (training, cash, luck) |
| Inventory, Pet, Hatch, Carry | egg bag; pets out in the park (income, training bonus from the best ones) or in the bag; carrying a pet/egg in your arms and putting it down anywhere in your park (Shared/EggSpots); hatching |
| Train, Pop | Snow Roller training, Snow Pops and the Rainbow Pop |
| Roll | pack meter, launch, sim, hits, results |
| Upgrade, Rebirth | cash upgrades, rebirth |
| Avalanche | server meter, warning, 60 s event, crown |
| Reward, Code | daily streak, playtime gifts, Lucky Wheel, tutorial reward, codes |
| Shop, Offer | receipts (idempotent, gifts, regional price check), contextual offers |
| Admin | chat test commands (see PLAYTEST.md) |

## Remotes

All in `Shared/Net.luau` (events and functions with per-player rate limits). Add a remote there first, then `Net.onEvent` / `Net.onInvoke` on the server.

## Products

`Config/Products.luau`. Every product and pass has `Id = 0` until they are created for the Snowball universe; buttons show SOON and the server refuses to prompt them, except in Studio, where `Products.StudioTestBuys` grants them for free so offers can be tested.

Money moments (DIRECTION.md in the project files): Starter Pack window after the tutorial (`OfferService` -> `StarterPackController`, HUD chest tile with the countdown), KEEP ROLLING? when a roll stops short (`RollService` phase `Stopped` -> `ContinueController`; a purchase calls `RollService:Continue`, which pushes the ball on and adds a new stretch of pickups), contextual offers (`OfferService`), the Shop (`ShopController`, Sweep layout) and the "BOUGHT!" stamp (`PurchaseController`).

## UI

Placeholder look from `Ui.luau` follows the house rules (Montserrat, solid buttons, no rounded corners, one window per feature, mobile first). ForgeUI art replaces it later without renaming frames.

## Pets and eggs (Steal an Egg / Sweep the World style, 2026-11-20)

- Bag = eggs + pets not out in the park. Client: `InventoryController` (hotbar bottom right + Bag window), `PlacementController` (carry, ghost + green/red ring, click/tap to put down, HOME button when far), `HoldPoseController` (arms), `PetWorldController` (pets wander in every park, Pick Up prompt, egg timers), `HoverController` (name in rarity colour, rarity, weight, $/s).
- Server: `CarryService` (welds HeldPet / HeldEgg, PlaceHeld), `PetService` (park = `base.Pets` folders with PetId/Weight/Income/X/Z; clients build the models), `HatchService` (eggs saved with X/Z in the park; the pet pops out where the egg was).
- Pet weight: `Config/Pets.Kg` + `rollWeight`; `Shared/PetStats` turns it into size and income. Pet clips: `Config/Anims` `Pet_<PackModel>_Idle/_Walk/_Happy` (procedural hop until a pet has them).
