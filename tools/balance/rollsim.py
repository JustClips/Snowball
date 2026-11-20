"""Monte Carlo of one roll, mirroring src/shared/Roll.luau + RollService (hits, pickups, cash).
Used by sim.py to turn Power into distance, cash and eggs. Skill: 0 = never steers,
1 = steers to every pile/coin it can and dodges every obstacle it would bonk on."""
import math, random, re, os
import luau

ZONES, MIN_ROLL, WALL = luau.zones()
RC = luau.roll_consts()
KINDS, SPACING, FIRST_AT = luau.obstacles()
EVERY, PSRC = luau.pickups()
SNOW_PER_PILE = luau.field(PSRC, "SnowPerPile")
COINS_PER = luau.field(PSRC, "CoinsPerCluster")
HIT = luau.field(PSRC, "HitRadius")
ROLLSRC = open(os.path.join(luau.ROOT, "..", "Roll.luau")).read()
SURF = {}
for name, body in re.findall(r"(\w+) = \{ (TopSpeed[^}]*)\}", ROLLSRC):
    SURF[name] = {k: float(v) for k, v in re.findall(r"(\w+) = ([0-9.]+)", body)}
CRACK = 2.0
try:
    CRACK = luau.field(luau.text("Zones"), "CrackPerRadius")
except KeyError:
    pass
PRESENT_MULT = 8

# Track: straight-line arc length through the points (close enough to the Catmull-Rom).
PTS = []
for m in re.finditer(r"Vector3\.new\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\), Width = (\d+), Slope = [0-9.]+, Surface = \"(\w+)\"", luau.text("Track")):
    PTS.append((float(m.group(1)), float(m.group(2)), float(m.group(3)), float(m.group(4)), m.group(5)))
SEG = [0.0]
for a, b in zip(PTS, PTS[1:]):
    SEG.append(SEG[-1] + math.dist(a[:3], b[:3]))
LENGTH = SEG[-1]
END_AT = min(WALL, LENGTH - 5)


def seg_at(s):
    lo = 0
    for i, v in enumerate(SEG):
        if v <= s:
            lo = i
    return PTS[lo]


def width_at(s):
    return seg_at(s)[3]


def zone_at(s):
    z = ZONES[0]
    for zz in ZONES:
        if s >= zz["Start"]:
            z = zz
    return z


KNOTS = [(0.0, MIN_ROLL)] + [(math.log10(z["Power"]), z["Start"]) for z in ZONES if z["Power"] > 0]
m = re.search(r"math\.log10\(([0-9e.]+)\), ([0-9_]+) \}", open(os.path.join(luau.ROOT, "..", "PowerCurve.luau")).read())
KNOTS.append((math.log10(float(m.group(1))), float(m.group(2).replace("_", ""))))


def distance(power):
    lp = max(0.0, math.log10(max(power, 1)))
    if lp <= KNOTS[0][0]:
        return KNOTS[0][1]
    for a, b in zip(KNOTS, KNOTS[1:]):
        if lp <= b[0]:
            t = (lp - a[0]) / (b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t
    return KNOTS[-1][1]


def layout(rng):
    out = []
    s = FIRST_AT
    byz = {}
    for k in KINDS:
        byz.setdefault(k["Zone"], []).append(k)
    while s < min(LENGTH, WALL - 40):
        z = zone_at(s)
        kinds = byz.get(z["Id"])
        if kinds and z["Id"] != "Village":
            n = 2 if rng.random() < 0.35 else 1
            half = width_at(s) / 2
            for _ in range(n):
                k = rng.choice(kinds)
                out.append(dict(s=s + rng.uniform(-10, 10), x=rng.uniform(-half + k["Radius"] + 4, half - k["Radius"] - 4), k=k))
        s += SPACING * rng.uniform(0.8, 1.25)
    out.sort(key=lambda o: o["s"])
    return out


OBS = layout(random.Random(12345))


def pickups(rng, limit):
    out = []
    for kind in ["Snow", "Coin", "Egg", "Present", "Ramp"]:
        every = EVERY[kind]
        s = 40 + rng.uniform(0, every)
        while s < limit:
            half = width_at(s) / 2 - 6
            out.append(dict(kind=kind, s=s, x=rng.uniform(-half, half)))
            s += every * rng.uniform(0.6, 1.4)
    out.sort(key=lambda p: p["s"])
    return out


def radius(snow, growth):
    return min(RC["MaxRadius"], RC["StartRadius"] + RC["GrowthScale"] * math.sqrt(max(0, snow * growth)))


def roll(power, growth=1.0, egg_slots=1, skill=0.6, pack=1.0, rng=None, golden=False):
    rng = rng or random.Random()
    D = distance(power) * pack
    total_D = D
    st = dict(s=0.0, x=rng.uniform(-30, 30), v=RC["PushSpeed"], vx=0.0, r=RC["StartRadius"], snow=0.0)
    picks = pickups(rng, min(LENGTH, D * 1.15 + 160))
    coins = smash_cash = 0.0
    eggs = []
    bonks = smashes = 0
    hit_obs = set()
    noticed = {}
    dt = 0.05
    t = 0.0
    pi = oi = 0

    def penalize(keep, flat_key):
        nonlocal D
        rem = max(0, D - st["s"])
        if flat_key in RC:  # new model: flat share of the roll's target distance
            loss = RC[flat_key] * total_D
            if flat_key == "BonkLoss":
                loss = max(loss, RC.get("BonkMin", 0))
            D = st["s"] + max(0, rem - loss)
            st["v"] *= keep
        else:
            D = st["s"] + rem * keep * keep
            st["v"] *= keep

    while True:
        smp = seg_at(st["s"])
        surf = SURF.get(smp[4], SURF["Snow"])
        # steering
        steer = 0.0
        ahead_obs = [o for o in OBS[oi:oi + 8] if 0 < o["s"] - st["s"] < 70 and id(o) not in hit_obs]
        threat = None
        size = st["r"] * (1.5 if golden else 1)
        for o in ahead_obs:
            if size < o["k"]["Size"] and abs(o["x"] - st["x"]) < st["r"] + o["k"]["Radius"] + 3:
                key = id(o)
                if key not in noticed:
                    noticed[key] = rng.random() < skill
                if noticed[key]:
                    threat = o
                    break
        if threat:
            steer = -1.0 if threat["x"] > st["x"] else 1.0
        elif skill > 0:
            best = None
            for p in picks[pi:pi + 30]:
                if p["kind"] in ("Snow", "Coin", "Egg", "Present") and 5 < p["s"] - st["s"] < 60:
                    key = id(p)
                    if key not in noticed:
                        noticed[key] = rng.random() < skill
                    if noticed[key]:
                        best = p
                        break
            if best:
                dx = best["x"] - st["x"]
                steer = max(-1, min(1, dx / 8))
        rem = max(0, D - st["s"])
        top = surf["TopSpeed"] + st["s"] * RC["TopSpeedPerStud"]
        target = min(top, math.sqrt(2 * surf["Decel"] * rem), RC["SettleGrip"] * rem + 0.5)
        st["v"] = min(target, st["v"] + RC["Accel"] * dt) if st["v"] < target else target
        st["s"] += st["v"] * dt
        sp = max(0.12, min(1, st["v"] / 30))
        want = steer * surf["SteerSpeed"] * sp
        grip = surf["Grip"] + (1 - sp) * 10
        st["vx"] += (want - st["vx"]) * min(1, grip * dt)
        st["x"] += st["vx"] * dt
        half = max(0, smp[3] / 2 - st["r"])
        if abs(st["x"]) > half:
            st["x"] = math.copysign(half, st["x"])
            st["vx"] = -st["vx"] * 0.45
        t += dt
        # pickups
        reach = st["r"] + HIT
        while pi < len(picks) and picks[pi]["s"] < st["s"] - reach:
            pi += 1
        j = pi
        while j < len(picks) and picks[j]["s"] <= st["s"] + reach:
            p = picks[j]
            if p["kind"] != "Taken" and abs(p["x"] - st["x"]) <= reach:
                z = zone_at(p["s"])
                if p["kind"] == "Snow":
                    st["snow"] += SNOW_PER_PILE * z["Index"]
                    st["r"] = radius(st["snow"], growth)
                elif p["kind"] == "Coin":
                    coins += COINS_PER * z["Coin"] * (2 if golden else 1)
                elif p["kind"] == "Present":
                    coins += COINS_PER * z["Coin"] * PRESENT_MULT
                elif p["kind"] == "Ramp":
                    D += RC["RampBoost"]
                    st["v"] *= 1.15
                elif p["kind"] == "Egg":
                    if len(eggs) < egg_slots:
                        eggs.append(z["Id"])
                p["kind"] = "Taken"
            j += 1
        while oi < len(OBS) and OBS[oi]["s"] < st["s"] - st["r"] - 10:
            oi += 1
        j = oi
        size = st["r"] * (1.5 if golden else 1)
        while j < len(OBS) and OBS[j]["s"] <= st["s"] + st["r"] + 10:
            o = OBS[j]
            if id(o) not in hit_obs:
                ds, dx = o["s"] - st["s"], o["x"] - st["x"]
                if ds * ds + dx * dx <= (st["r"] + o["k"]["Radius"]) ** 2:
                    hit_obs.add(id(o))
                    if size >= o["k"]["Size"]:
                        smashes += 1
                        smash_cash += o["k"]["Cash"] * zone_at(o["s"])["Coin"]
                        penalize(RC["SmashKeep"], "SmashLoss")
                    else:
                        bonks += 1
                        penalize(RC["BonkKeep"], "BonkLoss")
                        st["vx"] = math.copysign(26, -dx)
            j += 1
        if st["s"] >= END_AT:
            st["s"] = END_AT
            break
        rem = D - st["s"]
        if rem <= 0.5 or (st["v"] < 1.2 and rem < 3) or t > 400:
            break
    z = zone_at(st["s"])
    village = st["s"] >= END_AT - 1
    cash = coins + smash_cash + st["r"] * z["Coin"] * CRACK
    if village:
        cash *= 3
        eggs.append("Village")
    if not eggs:
        eggs.append(z["Id"])
    crack_s = z.get("Crack", 0) * (3 if village else 1)
    return dict(crack_s=crack_s, s=st["s"], target=total_D, zone=z["Index"], r=st["r"], cash=cash, coins=coins, smash=smash_cash,
                eggs=eggs, bonks=bonks, smashes=smashes, t=t, village=village)


if __name__ == "__main__":
    import sys, statistics as S
    skill = float(sys.argv[1]) if len(sys.argv) > 1 else 0.6
    rng = random.Random(1)
    print(f"track {LENGTH:.0f} studs, wall {END_AT}, obstacles {len(OBS)}")
    print(f"{'power':>10} {'target':>7} {'dist':>7} {'p10':>6} {'zone':>5} {'r':>5} {'bonks':>5} {'smash':>5} {'cash':>9} {'t':>5} village%")
    for p in [10, 100, 1e3, 1e4, 1e5, 1e6, 1e7, 5e7, 1e8, 1e9, 1e10]:
        rs = [roll(p, 1.2, 3, skill, 1.0, rng) for _ in range(30)]
        ds = sorted(r["s"] for r in rs)
        print(f"{p:>10.0e} {rs[0]['target']:>7.0f} {S.mean(ds):>7.0f} {ds[3]:>6.0f} {S.mean(r['zone'] for r in rs):>5.1f} {S.mean(r['r'] for r in rs):>5.1f} {S.mean(r['bonks'] for r in rs):>5.1f} {S.mean(r['smashes'] for r in rs):>5.1f} {S.mean(r['cash'] for r in rs):>9.0f} {S.mean(r['t'] for r in rs):>5.0f} {100*S.mean(r['village'] for r in rs):.0f}")
