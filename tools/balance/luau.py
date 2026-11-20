"""Tiny readers for the Snowball Luau configs, so the balance sim always uses the real numbers."""
import re, os

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "src", "shared", "Config")


def text(name):
    with open(os.path.join(ROOT, name + ".luau"), encoding="utf-8") as f:
        return f.read()


def num(s):
    s = s.replace("_", "").strip()
    if "*" in s:
        out = 1.0
        for part in s.split("*"):
            out *= float(part)
        return out
    return float(s)


def field(src, key):
    m = re.search(r"\b" + key + r"\s*=\s*([-0-9_.\s*]+)(?:[,\n}]|$)", src)
    if not m:
        raise KeyError(key)
    return num(m.group(1))


def blocks(src, must):
    """Every { ... } block (one level) that contains `must`."""
    out = []
    for m in re.finditer(r"\{([^{}]*)\}", src):
        b = m.group(1)
        if must in b:
            out.append(b)
    return out


def sfield(block, key):
    m = re.search(r"\b" + key + r'\s*=\s*"([^"]*)"', block)
    return m.group(1) if m else None


def zones():
    src = text("Zones")
    z = []
    for b in blocks(src, "IncomeMult ="):
        z.append(dict(Id=sfield(b, "Id"), Start=field(b, "Start"), Power=field(b, "Power"),
                      Coin=field(b, "CoinValue"), Index=int(field(b, "Index")),
                      Crack=field(b, "CrackSeconds") if "CrackSeconds" in b else 0))
    return z, field(src, "MinRoll"), field(src, "VillageWall")


def rollers():
    src = text("Rollers")
    cash = src.split("local Robux")[0]
    return [dict(Id=sfield(b, "Id"), Power=field(b, "Power"), Price=field(b, "Price"),
                 Reb=field(b, "RebirthsNeeded")) for b in blocks(cash, "RebirthsNeeded =")]


def cores():
    src = text("Upgrades")
    return [dict(Luck=field(b, "Luck"), Growth=field(b, "Growth"), Price=field(b, "Price"))
            for b in blocks(src, "Growth =")]


def list_after(src, key):
    m = re.search(key + r"\s*=\s*\{([^}]*)\}", src)
    return [num(x) for x in m.group(1).split(",") if x.strip()]


def pets():
    src = text("Pets")
    by = {}
    for m in re.finditer(r'pet\("(\w+)",\s*"(\w+)",\s*([0-9.]+),\s*([0-9.]+),\s*"\w+"\)', src):
        by.setdefault(m.group(2), (float(m.group(3)), float(m.group(4))))
    zm = dict((k, num(v)) for k, v in re.findall(r"(\w+) = ([0-9_.]+)", re.search(r"ZoneMult = \{([^}]*)\}", src).group(1)))
    tzm = dict((k, num(v)) for k, v in re.findall(r"(\w+) = ([0-9_.]+)", re.search(r"TrainZoneMult = \{([^}]*)\}", src).group(1)))
    return by, zm, tzm


def pools():
    src = text("Eggs")
    p = {}
    for m in re.finditer(r"(\w+) = \{ ((?:\w+ = [0-9.]+,? ?)+)\}", src.split("local Eggs =")[0]):
        if m.group(1) in ("Meadow", "Pine", "Lake", "Cave", "Aurora", "Village"):
            p[m.group(1)] = {k: float(v) for k, v in re.findall(r"(\w+) = ([0-9.]+)", m.group(2))}
    hatch = {sfield(b, "Name"): field(b, "HatchSeconds") for b in blocks(src, "HatchSeconds =")}
    return p, hatch


def obstacles():
    src = text("Obstacles")
    kinds = [dict(Id=sfield(b, "Id"), Zone=sfield(b, "Zone"), Size=field(b, "SizeNeeded"),
                  Radius=field(b, "Radius"), Cash=field(b, "Cash")) for b in blocks(src, "SizeNeeded =") if "kind." not in b]
    return kinds, field(src, "Spacing"), field(src, "FirstAt")


def roll_consts():
    src = open(os.path.join(ROOT, "..", "Roll.luau"), encoding="utf-8").read()
    keys = ["PushSpeed", "Accel", "TopSpeedPerStud", "StartRadius", "MaxRadius", "GrowthScale",
            "SmashKeep", "BonkKeep", "RampBoost", "SettleGrip"]
    out = {}
    for k in keys:
        try:
            out[k] = field(src, k)
        except KeyError:
            pass
    for k in ["SmashLoss", "BonkLoss", "BonkMin"]:
        try:
            out[k] = field(src, k)
        except KeyError:
            pass
    return out


def economy():
    return text("Economy")


def pickups():
    src = text("Pickups")
    every = {k: num(v) for k, v in re.findall(r"(\w+) = ([0-9_.]+)", re.search(r"Every = \{([^}]*)\}", src).group(1))}
    return every, src
