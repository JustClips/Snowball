"""Roll the Snowball progression sim (docs/BALANCE.md). Reads the real Luau configs.

A simulated player loops: train on the roller (auto reps + claimed Snow Pops), roll, carry the
eggs home, hatch them on the base, keep the best pets placed, buy the next roller / core /
egg slot / pet slot when it can, and rebirth once it has reached the Village and has the cash.

    python3 tools/balance/sim.py            # free player, 3 seeds, milestone table
    python3 tools/balance/sim.py --hours 12 --verbose
"""
import argparse, math, random, statistics as S, re
import luau, rollsim

ZONES, _, _ = luau.zones()
ZID = [z["Id"] for z in ZONES]
ROLLERS = luau.rollers()
CORES = luau.cores()
PETS, ZMULT, TZMULT = luau.pets()
POOLS, HATCH = luau.pools()
ECO = luau.economy()
UPG = luau.text("Upgrades")
EGG_SLOT_PRICES = luau.list_after(UPG, "Upgrades.EggSlotPrices")
PET_SLOT_PRICES = luau.list_after(UPG, "Upgrades.PetSlotPrices")
RARITY = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
REPS = luau.field(ECO, "TrainRepsPerSecond")
REB_FIRST = luau.field(ECO, "RebirthFirstCost")
REB_GROWTH = luau.field(ECO, "RebirthCostGrowth")
REB_TRAIN = luau.field(ECO, "RebirthTrainBonus")
REB_CASH = luau.field(ECO, "RebirthCashBonus")
REB_LUCK = luau.field(ECO, "RebirthLuckBonus")
CASH_GEOMETRIC = "rebirthCashMult(rebirths: number): number\n\treturn (1 +" in ECO
LUCKY_EVERY = luau.field(ECO, "LuckyEvery")
LUCKY_MULT = luau.field(ECO, "LuckyEveryMult")
START_SLOTS = luau.field(ECO, "StartPetSlots")
HATCH_SPOTS = 4
LUCK_POWER = luau.field(luau.text("Eggs"), "LuckPower")
EQUIP = 3
TRAIN_CAP = None
try:
    TRAIN_CAP = luau.field(ECO, "PetTrainBonusCap")
except KeyError:
    pass

# Snow Pops while training: average Power reps per second they add, if the player claims
# CLAIM of them (Pops.luau weights; a Train pop pays Mult x Seconds x reps/s).
POPSRC = luau.text("Pops")
_free = [(float(m.group(1)), float(m.group(2)), float(m.group(3)), k) for k, m in
         ((k, re.search(r'Kind = "' + k + r'",\s*Mult = ([0-9.]+),\s*Seconds = ([0-9.]+),\s*Weight = ([0-9.]+)', b))
          for b in luau.blocks(POPSRC.split("local Rainbow")[0], "Kind =") for k in ["Train", "Coin", "Present", "Luck"]) if m]
_w = sum(w for _, _, w, _ in _free)
POP_GAP = luau.field(POPSRC, "LifeSeconds") + (luau.field(POPSRC, "MinGap") + luau.field(POPSRC, "MaxGap")) / 2
POP_REPS = sum(m * s * REPS * w for m, s, w, k in _free if k == "Train") / _w / POP_GAP
POP_CASH_S = sum(m * w for m, s, w, k in _free if k in ("Coin", "Present")) / _w / POP_GAP  # income-seconds per second


def roll_rarity(rng, zone, luck):
    pool = POOLS[zone]
    ws = []
    for i, r in enumerate(RARITY):
        w = pool.get(r, 0)
        if w > 0:
            w *= max(1, luck) ** (i * LUCK_POWER)
        ws.append(w)
    x = rng.random() * sum(ws)
    for r, w in zip(RARITY, ws):
        x -= w
        if x <= 0 and w > 0:
            return r
    return "Common"


def pet_value(rng, rarity, zone, luck):
    inc, tr = PETS[rarity]
    mut = 1
    for chance, mult in ((500, 5), (100, 3), (20, 2)):
        if rng.random() < min(0.5, luck / chance):
            mut = mult
            break
    weight = 0.8 + 0.5 * rng.random() ** 2
    if rng.random() < 0.05:
        weight = rng.uniform(1.4, 2.2)
    return inc * ZMULT[zone] * mut * weight, tr * TZMULT[zone] * math.sqrt(mut)


class Player:
    def __init__(self, seed, skill=0.5, claim=0.6, train_cap_s=90, robux=None):
        self.rng = random.Random(seed)
        self.skill, self.claim, self.train_cap_s = skill, claim, train_cap_s
        self.t = 0.0
        self.cash = 0.0
        self.earned = {"pets": 0.0, "runs": 0.0, "pops": 0.0}
        self.power = 0.0
        self.roller = 0  # index
        self.core = 0
        self.egg_slots = 1
        self.pet_slots = START_SLOTS
        self.pets = []  # (income, train)
        self.hatching = []  # (ends_at, rarity, zone)
        self.bag = []
        self.reb = 0
        self.village = False
        self.runs = 0
        self.best_zone = 1
        self.log = []
        self.milestones = {}
        self.robux_mult = 1
        self.last_run = None

    # --- rates
    def placed(self):
        return sorted(self.pets, key=lambda p: -p[0])[: int(self.pet_slots)]

    def income(self):
        return sum(p[0] for p in self.placed()) * self.cash_mult()

    def cash_mult(self):
        if CASH_GEOMETRIC:
            return (1 + REB_CASH) ** self.reb
        return 1 + REB_CASH * self.reb

    def train_mult(self):
        bonus = sum(sorted((p[1] for p in self.placed()), reverse=True)[:EQUIP])
        if TRAIN_CAP is not None:
            bonus = min(bonus, TRAIN_CAP)
        return self.robux_mult * (1 + bonus) * (1 + REB_TRAIN) ** self.reb

    def luck(self):
        return CORES[self.core]["Luck"] * (1 + REB_LUCK * self.reb)

    # --- time passes: pets earn, eggs hatch
    def advance(self, dt):
        inc = self.income()
        self.cash += inc * dt
        self.earned["pets"] += inc * dt
        self.t += dt
        done = [h for h in self.hatching if h[0] <= self.t]
        for h in done:
            self.hatching.remove(h)
            self.pets.append(pet_value(self.rng, h[1], h[2], self.luck()))
            self.rarest = max(getattr(self, "rarest", 0), RARITY.index(h[1]))
            self.mark(f"First {h[1]}")
        while self.bag and len(self.hatching) < HATCH_SPOTS:
            # rarest egg first
            self.bag.sort(key=lambda e: RARITY.index(e[0]) * 10 + ZID.index(e[1]))
            r, z = self.bag.pop()
            secs = 3 if not self.pets and not self.hatching else HATCH[r]
            self.hatching.append((self.t + secs, r, z))
        if len(self.pets) > 60:  # players delete junk
            self.pets = sorted(self.pets, key=lambda p: -p[0])[:40]

    def mark(self, key):
        if key not in self.milestones:
            self.milestones[key] = self.t

    # --- spending (greedy, cheapest useful first, like a kid)
    def shop(self):
        cost = REB_FIRST * REB_GROWTH ** self.reb
        if self.village and self.cash >= cost:
            self.cash = 0
            self.power = 0
            self.roller = 0
            self.core = 0
            self.village = False
            self.reb += 1
            self.mark(f"Rebirth {self.reb}")

        bought = True
        while bought:
            bought = False
            opts = []
            if self.roller + 1 < len(ROLLERS) and ROLLERS[self.roller + 1]["Reb"] <= self.reb:
                price = ROLLERS[self.roller + 1]["Price"]
                if self.roller == 0 and self.runs >= 1:
                    price = 0  # Stone Roller is free in the tutorial
                opts.append((price, "roller"))
            if self.core + 1 < len(CORES):
                opts.append((CORES[self.core + 1]["Price"], "core"))
            if self.egg_slots <= len(EGG_SLOT_PRICES):
                opts.append((EGG_SLOT_PRICES[self.egg_slots - 1], "egg"))
            if self.pet_slots - START_SLOTS < len(PET_SLOT_PRICES) and len(self.pets) > self.pet_slots:
                opts.append((PET_SLOT_PRICES[int(self.pet_slots - START_SLOTS)], "pet"))
            opts.sort()
            if self.village:  # the game says REBIRTH now: save for it, buy only cheap things
                opts = [o for o in opts if o[0] < 0.05 * cost]
            for price, kind in opts:
                if self.cash >= price:
                    self.cash -= price
                    if kind == "roller":
                        self.roller += 1
                        self.mark(f"Roller {ROLLERS[self.roller]['Id']}" + (f" R{self.reb}" if self.reb else ""))
                    elif kind == "core":
                        self.core += 1
                        self.mark(f"Core {self.core + 1}" + (f" R{self.reb}" if self.reb else ""))
                    elif kind == "egg":
                        self.egg_slots += 1
                        self.mark(f"Egg slot {self.egg_slots}")
                    else:
                        self.pet_slots += 1
                        self.mark(f"Pet slot {int(self.pet_slots)}")
                    bought = True
                    break
    # --- one train + roll cycle
    def cycle(self):
        # Train: until the next zone's Power (x1.3 slack) or train_cap_s, at least 15 s.
        target_zone = min(len(ZONES), self.best_zone + 1)
        goal = ZONES[target_zone - 1]["Power"] * 1.6 if target_zone > self.best_zone else self.power * 1.5
        per = ROLLERS[self.roller]["Power"] * self.train_mult()
        rate = per * (REPS + POP_REPS * self.claim)
        need = max(0, goal - self.power) / rate if rate > 0 else 1e9
        dur = max(15, min(self.train_cap_s, need))
        if self.runs == 0:
            dur = 20
        self.power += rate * dur
        pop_cash = POP_CASH_S * self.claim * dur * max(self.income(), 5)
        self.cash += pop_cash
        self.earned["pops"] += pop_cash
        self.advance(dur)
        # Roll
        perfect = self.rng.random() < 0.5
        res = rollsim.roll(self.power, CORES[self.core]["Growth"], self.egg_slots, self.skill,
                           1.0 if perfect else 0.85, self.rng)
        self.runs += 1
        luck = self.luck() * (LUCKY_MULT if self.runs % LUCKY_EVERY == 0 else 1) * (1.5 if perfect else 1.2)
        rescue = 0
        for z in res["eggs"]:
            back = min(190, 50 + res["s"] * 0.03)
            rescue += back / 14 + back / 16 + 2
        self.advance(res["t"] + 6 + rescue + 8)  # pack + crack card + carry eggs + walk/teleport home
        cash = res["cash"] * self.cash_mult() + res["crack_s"] * self.income()
        self.cash += cash
        self.earned["runs"] += cash
        for z in res["eggs"]:
            self.bag.append((roll_rarity(self.rng, z, luck), z))
        if res["zone"] > self.best_zone:
            self.best_zone = res["zone"]
        self.mark(f"Zone {ZID[res['zone'] - 1]}" + (f" R{self.reb}" if self.reb else ""))
        if res["village"]:
            self.village = True
        self.last_run = (res, cash, self.income(), self.power)
        self.shop()


def fmt_t(s):
    if s is None:
        return "-"
    if s < 3600:
        return f"{s / 60:.0f}m"
    return f"{s / 3600:.1f}h"


def big(n):
    for suf, v in (("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if n >= v:
            return f"{n / v:.1f}{suf}"
    return f"{n:.0f}"


def run(hours, seeds, verbose, skill, claim):
    players = []
    for seed in range(seeds):
        p = Player(seed, skill, claim)
        snaps = []
        next_snap = 60
        while p.t < hours * 3600:
            p.cycle()
            if p.t >= next_snap:
                res, cash, inc, power = p.last_run
                snaps.append((p.t, p.power, res["s"], ZID[res["zone"] - 1], cash, inc, p.reb, ROLLERS[p.roller]["Id"]))
                next_snap = next_snap * 1.5 if next_snap < 3600 else next_snap + 3600
        players.append((p, snaps))
    keys = []
    for p, _ in players:
        for k in sorted(p.milestones, key=lambda k: p.milestones[k]):
            if k not in keys:
                keys.append(k)
    print(f"free player, skill {skill}, pops claimed {claim:.0%}, {seeds} seeds, {hours} h")
    rows = []
    for k in keys:
        ts = [p.milestones.get(k) for p, _ in players]
        ok = [t for t in ts if t is not None]
        rows.append((S.median(ok) if ok else 9e9, k, ok, len(ts)))
    rows.sort()
    for med, k, ok, n in rows:
        print(f"  {k:<22} {fmt_t(med):>6}" + ("" if len(ok) == n else f"  ({len(ok)}/{n})"))
    p, snaps = players[0]
    if verbose:
        print("\n  time   power   last roll       run cash   pet $/s  run=secs of pets  reb roller")
        for t, pw, s, z, cash, inc, reb, rid in snaps:
            ratio = cash / inc if inc > 0 else float("inf")
            print(f"  {fmt_t(t):>5} {big(pw):>7} {s:>6.0f} {z:<8} {big(cash):>8} {big(inc):>9}   {ratio:>8.0f}s     {reb:>2} {rid}")
    tot = sum(p.earned.values())
    print(f"\n  cash earned by source (seed 0): " + ", ".join(f"{k} {v / tot:.0%}" for k, v in p.earned.items()))
    return players


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=float, default=6)
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--skill", type=float, default=0.5)
    ap.add_argument("--claim", type=float, default=0.6)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    print(f"pops add {POP_REPS:.2f} reps/s if all claimed (auto training is {REPS}/s); coin pops {POP_CASH_S:.2f} income-s per s")
    run(a.hours, a.seeds, a.verbose, a.skill, a.claim)
