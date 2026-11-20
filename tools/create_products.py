#!/usr/bin/env python3
"""Creates every gamepass and developer product in src/shared/Config/Products.luau for the
Snowball universe through Roblox Open Cloud and writes their ids to Config/ProductIds.luau.

    python3 tools/create_products.py --dry-run   # list what would be created
    python3 tools/create_products.py             # create missing ones, write ids

Safe to run again: ids already in ProductIds.luau are kept, and items that already exist on
Roblox with the same name are reused. Icons come from art/ui/Shop_*.png (art/icons_shop).

Needs an Open Cloud key OWNED BY THE ACCOUNT THAT OWNS THE GAME, with game-pass and
developer-product read+write for it: env ROBLOXAPIKEY_SNOWBALL (falls back to ROBLOXAPIKEY).
The key is never printed. Universe: env SNOWBALL_UNIVERSE, default 10778042297
(place 130604909447489).
"""
import json, os, re, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src", "shared", "Config", "Products.luau")
IDS = os.path.join(ROOT, "src", "shared", "Config", "ProductIds.luau")
UI = os.path.join(ROOT, "art", "ui")
UNIVERSE = os.environ.get("SNOWBALL_UNIVERSE", "10778042297")
API = "https://apis.roblox.com"
KEY = os.environ.get("ROBLOXAPIKEY_SNOWBALL") or os.environ.get("ROBLOXAPIKEY")

PIC = {"Cash2x": "Pass2xCash", "Train2x": "Pass2xPower", "AutoTrain": "PassFastTrain", "Lucky": "PassLucky",
       "GoldenSnowball": "PassGoldBall", "VIP": "PassVIP", "Train2xBoost": "Pass2xPower", "SuperLuckyRoll": "SuperLucky",
       "StarterPack": "StarterRoller", "KeepRolling1": "PassGoldBall", "KeepRolling2": "PassGoldBall"}
for i in range(1, 5):
    PIC[f"PowerPack{i}"] = f"Power{i}"
    PIC[f"Cash{i}"] = f"Cash{i}"
for n in (3, 10, 35, 100):
    PIC[f"LuckyRoll{n}"] = f"Lucky{n}"
for n in (2, 4, 8, 16):
    PIC[f"ServerLuck{n}"] = "ServerLuck"
KIND_TEXT = {
    "StarterPack": "Iron Roller, an Epic egg, 3 Lucky Rolls and 15 minutes of 2x Power. Once only!",
    "KeepRolling": "Push your snowball further when it stops just short.",
    "RainbowPop": "Rainbow training boost for 2 minutes.",
    "RobuxRoller": "A Robux Snow Roller: trains much faster, forever.",
    "TrainTime": "Instantly adds training time at your best speed.",
    "PowerPack": "Instant Power for your next roll.",
    "Boost": "A timed boost.",
    "LuckyRoll": "Rolls with x10 luck and +50% distance.",
    "SuperLuckyRoll": "One roll with x100 luck.",
    "ServerLuck": "15 minutes of luck for everyone in the server.",
    "GoldenRuns": "Golden Snowball runs: x2 coins, smashes bigger obstacles.",
    "EggPack": "Frozen eggs straight to your bag.",
    "HugePet": "A Huge pet, yours forever.",
    "SkipHatch": "Hatches one egg instantly.",
    "CashPack": "Cash that grows with your progress.",
    "Avalanche": "Starts an Avalanche for the whole server.",
    "WheelSpins": "Lucky Wheel spins.",
    "SkipRebirth": "Rebirth now.",
    "DoubleOffline": "Doubles your offline cash.",
}
FULL_PRICE = {"ServerLuck", "Avalanche"}


def items():
    src = open(SRC, encoding="utf-8").read()
    passes_src, products_src = src.split("local function p(", 1)
    passes = []
    for m in re.finditer(r'Key = "(\w+)",\s*Id = \d+,\s*Price = (\d+),\s*Name = "([^"]*)",(?:\s*Description = "([^"]*)")?', passes_src):
        passes.append({"key": m[1], "price": int(m[2]), "name": m[3], "desc": m[4] or m[3]})
    products = []
    for m in re.finditer(r'\bp\(\s*"(\w+)",\s*(\d+),\s*"([^"]*)",\s*"(\w+)"', products_src):
        products.append({"key": m[1], "price": int(m[2]), "name": m[3], "kind": m[4]})
    return passes, products


def curl(method, path, form=None):
    if not KEY:
        sys.exit("No ROBLOXAPIKEY_SNOWBALL / ROBLOXAPIKEY in the environment")
    cmd = ["curl", "-sS", "-X", method, "-H", "x-api-key: " + KEY, "-w", "\n%{http_code}", API + path]
    for k, v in (form or {}).items():
        cmd += ["--form-string" if not str(v).startswith("@") else "-F", f"{k}={v}"]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    body, _, code = out.rpartition("\n")
    if not code.startswith("2"):
        raise RuntimeError(f"{method} {path} -> {code}: {body[:300]}")
    return json.loads(body) if body.strip() else {}


def list_all(path, field):
    out, token = [], ""
    while True:
        page = curl("GET", f"{path}?pageSize=50" + (f"&pageToken={token}" if token else ""))
        out += page.get(field) or []
        token = page.get("nextPageToken") or ""
        if not token:
            return out


def icon(key):
    path = os.path.join(UI, f"Shop_{PIC.get(key, 'PassGoldBall')}.png")
    return {"imageFile": f"@{path};type=image/png"} if os.path.exists(path) else {}


def read_ids():
    if not os.path.exists(IDS):
        return {}
    return {k: int(v) for k, v in re.findall(r'(\w+) = (\d+),', open(IDS).read())}


def write_ids(ids):
    lines = ["--!strict", "-- Product and gamepass ids for the Snowball universe, by Key (Products.luau).",
             f"-- Generated by tools/create_products.py (universe {UNIVERSE}). Keys missing here stay Id 0.", "return {"]
    lines += [f"\t{k} = {ids[k]}," for k in sorted(ids)]
    lines.append("} :: { [string]: number }")
    open(IDS, "w").write("\n".join(lines) + "\n")


def main():
    dry = "--dry-run" in sys.argv
    passes, products = items()
    ids = read_ids()
    print(f"{len(passes)} passes, {len(products)} products in Products.luau; {len(ids)} ids already known")
    gbase = f"/game-passes/v1/universes/{UNIVERSE}/game-passes"
    pbase = f"/developer-products/v2/universes/{UNIVERSE}/developer-products"
    have_p = {} if dry else {p["name"]: p for p in list_all(gbase + "/creator", "gamePasses")}
    have_d = {} if dry else {p["name"]: p for p in list_all(pbase + "/creator", "developerProducts")}
    for it in passes:
        if it["key"] in ids:
            continue
        found = have_p.get(it["name"])
        if found:
            ids[it["key"]] = int(found.get("gamePassId") or found.get("id"))
            print("pass reuse", it["key"], ids[it["key"]])
            continue
        print(f"pass create {it['key']} '{it['name']}' R${it['price']}")
        if dry:
            continue
        form = {"name": it["name"], "description": it["desc"], "price": it["price"], "isForSale": "true"}
        form.update(icon(it["key"]))
        made = curl("POST", gbase, form)
        ids[it["key"]] = int(made.get("gamePassId") or made.get("id"))
        write_ids(ids)
        time.sleep(0.4)
    for it in products:
        if it["key"] in ids:
            continue
        found = have_d.get(it["name"])
        if found:
            ids[it["key"]] = int(found["productId"])
            print("product reuse", it["key"], ids[it["key"]])
            continue
        print(f"product create {it['key']} '{it['name']}' R${it['price']}")
        if dry:
            continue
        form = {"name": it["name"], "description": KIND_TEXT.get(it["kind"], it["name"]), "price": it["price"],
                "isForSale": "true"}
        form.update(icon(it["key"]))
        made = curl("POST", pbase, form)
        ids[it["key"]] = int(made["productId"])
        if it["kind"] in FULL_PRICE:
            curl("PATCH", f"{pbase}/{ids[it['key']]}", {"isManagedPricingEnabled": "false"})
        write_ids(ids)
        time.sleep(0.4)
    if not dry:
        write_ids(ids)
        print(f"{len(ids)} ids in {os.path.relpath(IDS, ROOT)}")


if __name__ == "__main__":
    main()
