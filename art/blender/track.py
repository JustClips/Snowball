"""Track models (Dev 2026-11-20: "everything looks cheap"): the obstacles a ball smashes,
the pickups on the run, and the hatching eggs on the base pedestals. Each is ONE mesh,
built at its game size so nothing is rescaled in Roblox:

  Obs_<Kind>    Config/Obstacles kinds, footprint = Radius * 2, height = Height
  Pick_<Kind>   Snow pile, Coin, Egg (frozen run egg), Present, Ramp (rises toward -Z, the
                direction of travel)
  Egg_<Rarity>  hatching eggs (3.4 x 4.4 x 3.4), one colour scheme per rarity

Origin = footprint centre on the ground, front = Roblox -Z. WorldService shares the track
ones with clients through ReplicatedStorage.Assets.

  python track.py            # all
  python track.py Obs_Pine Pick_Coin
"""
import math
import random
import sys

import bpy
import bmesh

import kit
from kit import box, cyl, cone, sphere

kit.PALETTE.update({
    "EggCommon": (232, 236, 244), "EggUncommon": (110, 220, 120), "EggRare": (80, 160, 255),
    "EggEpic": (175, 100, 255), "EggLegendary": (255, 200, 50), "EggMythic": (255, 70, 100),
    "EggSecret": (40, 40, 56), "SpotCyan": (90, 240, 255), "FrostEgg": (170, 225, 255),
    "CoinGold": (255, 200, 40), "CoinDark": (220, 150, 20), "RibbonGold": (255, 215, 70),
    "HutRed": (200, 70, 60), "IceDeep": (110, 190, 245),
})
kit.GLOW.update({"SpotCyan"})


def rb(x, y, z):
    return (-x, z, y)


def rsize(sx, sy, sz):
    return (sx, sz, sy)


def prism_x(name, pts_zy, x0, x1, color):
    """Extrudes a Roblox (z, y) side profile along Roblox x from x0 to x1."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    a = [bm.verts.new(rb(x0, y, z)) for z, y in pts_zy]
    b = [bm.verts.new(rb(x1, y, z)) for z, y in pts_zy]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts_zy)
    for k in range(n):
        bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(kit.mat(color))
    kit._bevel(o, 0.12)
    return o


# ---------------------------------------------------------------- obstacles

def snowman(p, h=7.0, name="S"):
    k = h / 7.0
    p.append(sphere(f"{name}B", 1.9 * k, rb(0, 1.7 * k, 0), "Snow", subdiv=3))
    p.append(sphere(f"{name}M", 1.4 * k, rb(0, 4.1 * k, 0), "Snow", subdiv=3))
    p.append(sphere(f"{name}H", 1.0 * k, rb(0, 5.9 * k, 0), "Snow", subdiv=3))
    p.append(cone(f"{name}N", 0.2 * k, 0, 1.1 * k, rb(0, 5.9 * k, -1.35 * k), "Plank", verts=8, rot=(math.radians(90), 0, 0)))
    for s in (-1, 1):
        p.append(sphere(f"{name}E{s}", 0.14 * k, rb(s * 0.38 * k, 6.25 * k, -0.86 * k), "Black", subdiv=1))
        p.append(cyl(f"{name}A{s}", 0.1 * k, 2.4 * k, rb(s * 2.2 * k, 4.6 * k, 0), "LogDark", verts=6,
                     rot=(0, math.radians(90) * -s * 0.7, 0), bevel=0.0))
    p.append(cyl(f"{name}Sc", 1.08 * k, 0.45 * k, rb(0, 5.1 * k, 0), "Red", verts=16, bevel=0.06))
    p.append(cyl(f"{name}Br", 1.1 * k, 0.2 * k, rb(0, 6.8 * k, 0), "Black", verts=14, bevel=0.04))
    p.append(cyl(f"{name}Hat", 0.72 * k, 1.1 * k, rb(0, 7.4 * k, 0), "Black", verts=14, bevel=0.06))


def obs_snowman(p):
    snowman(p, 7.0)


def obs_fence(p):
    for s in (-1, 0, 1):
        p.append(box(f"Post{s}", rsize(0.7, 4.0, 0.7), rb(s * 2.6, 2.0, 0), "Log", bevel=0.1))
        p.append(box(f"PostCap{s}", rsize(0.9, 0.35, 0.9), rb(s * 2.6, 4.15, 0), "Snow", bevel=0.12))
    for k, y in enumerate((1.3, 2.9)):
        p.append(box(f"Rail{k}", rsize(6.0, 0.6, 0.35), rb(0, y, -0.45), "Plank", bevel=0.08))
    p.append(sphere("Drift", 2.2, rb(0, 0, 0), "Snow", subdiv=2, scale=(1.6, 0.8, 0.35)))


def pine(p, h, r, name="P"):
    p.append(cyl(f"{name}T", r * 0.16, h * 0.2, rb(0, h * 0.1, 0), "LogDark", verts=8, bevel=0.0))
    tiers = ((1.0, 0.16), (0.78, 0.38), (0.56, 0.58), (0.34, 0.76))
    for k, (f, at) in enumerate(tiers):
        y = h * at + h * 0.12
        p.append(cone(f"{name}L{k}", r * f, 0.0, h * 0.32, rb(0, y, 0), "Pine" if k % 2 == 0 else "PineDark", verts=9))
        p.append(cone(f"{name}S{k}", r * f * 0.6, 0.0, h * 0.18, rb(0, y + h * 0.09, 0), "Snow", verts=9))


def obs_pine(p):
    pine(p, 16, 3.0)


def obs_bigpine(p):
    pine(p, 34, 6.0)
    p.append(sphere("Pile", 4.0, rb(0, 0, 0), "Snow", subdiv=2, scale=(1.5, 1.5, 0.3)))


def obs_log(p):
    p.append(cyl("Log", 1.5, 8.0, rb(0, 1.5, 0), "Log", verts=14, rot=(0, math.radians(90), 0), bevel=0.15))
    for s in (-1, 1):
        p.append(cyl(f"End{s}", 1.25, 0.1, rb(s * 4.02, 1.5, 0), "Plank", verts=14, rot=(0, math.radians(90), 0), bevel=0.0))
    p.append(box("SnowTop", rsize(7.4, 0.5, 1.6), rb(0, 2.95, 0), "Snow", bevel=0.22))
    p.append(cyl("Branch", 0.35, 1.6, rb(1.4, 2.6, -0.6), "LogDark", verts=6, rot=(math.radians(-30), 0, 0), bevel=0.0))


def obs_iceblock(p):
    p.append(box("Ice", rsize(7.0, 6.2, 7.0), rb(0, 3.1, 0), "Ice", bevel=0.5))
    p.append(box("Core", rsize(4.6, 4.4, 7.2), rb(0, 3.1, 0), "IceDeep", bevel=0.4))
    p.append(box("Cap", rsize(7.3, 0.8, 7.3), rb(0, 6.6, 0), "Snow", bevel=0.35))


def obs_fishinghut(p):
    p.append(box("Floor", rsize(10, 0.6, 10), rb(0, 0.3, 0), "LogDark", bevel=0.1))
    p.append(box("Walls", rsize(8.6, 5.6, 8.0), rb(0, 3.4, 0), "HutRed", bevel=0.2))
    p.append(box("Door", rsize(2.0, 3.4, 0.3), rb(-1.6, 2.3, -4.05), "Door", bevel=0.08))
    p.append(box("Window", rsize(1.8, 1.4, 0.3), rb(2.0, 3.8, -4.05), "Window", bevel=0.08))
    for s in (-1, 1):
        p.append(box(f"Roof{s}", rsize(5.4, 0.5, 9.4), rb(s * 2.4, 7.4, 0), "LogDark", bevel=0.12,
                     rot=(0, math.radians(-28 * s), 0)))
        p.append(box(f"RoofSnow{s}", rsize(5.2, 0.4, 9.0), rb(s * 2.35, 7.85, 0), "Snow", bevel=0.15,
                     rot=(0, math.radians(-28 * s), 0)))
    p.append(box("Chimney", rsize(1.0, 2.4, 1.0), rb(2.6, 8.6, 2.0), "Stone", bevel=0.1))
    p.append(cyl("Hole", 1.2, 0.08, rb(3.5, 0.62, -5.6), "IceDeep", verts=16, bevel=0.0))


def crystals(p, h, r, rng, name="C"):
    p.append(sphere(f"{name}Base", r * 0.8, rb(0, 0, 0), "Snow", subdiv=2, scale=(1.3, 1.3, 0.35)))
    for k in range(7):
        a = k / 7 * math.tau + rng.uniform(-0.2, 0.2)
        rr = 0.0 if k == 0 else r * 0.55
        hh = h if k == 0 else rng.uniform(h * 0.35, h * 0.65)
        tilt = 0 if k == 0 else 0.4
        p.append(cone(f"{name}{k}", (r * 0.38 if k == 0 else r * 0.24), 0.0, hh,
                      rb(math.cos(a) * rr, hh / 2, math.sin(a) * rr), "Ice" if k % 2 == 0 else "Diamond", verts=6,
                      rot=(math.sin(a) * tilt, -math.cos(a) * tilt, 0)))


def obs_crystal(p):
    crystals(p, 14, 5, random.Random(3))


def obs_stalagmite(p):
    rng = random.Random(8)
    for k in range(4):
        a = k / 4 * math.tau
        rr = 0 if k == 0 else 3.2
        hh = 20 if k == 0 else rng.uniform(7, 11)
        p.append(cone(f"St{k}", 3.0 if k == 0 else 1.8, 0.2, hh, rb(math.cos(a) * rr, hh / 2, math.sin(a) * rr),
                      "Stone" if k % 2 == 0 else "StoneDark", verts=8))
        p.append(cone(f"Ic{k}", 1.4 if k == 0 else 0.9, 0.1, hh * 0.25, rb(math.cos(a) * rr, hh * 0.86, math.sin(a) * rr), "Ice", verts=8))


def obs_boulder(p):
    rng = random.Random(11)
    for k in range(5):
        r = rng.uniform(3.5, 6.0) if k else 7.0
        x, z = (0, 0) if k == 0 else (rng.uniform(-4, 4), rng.uniform(-4, 4))
        p.append(sphere(f"R{k}", r, rb(x, r * 0.75, z), "Stone" if k % 2 else "StoneDark", subdiv=2, scale=(1.15, 1.0, 0.95)))
    p.append(sphere("Cap", 5.6, rb(0, 10.4, 0), "Snow", subdiv=2, scale=(1.3, 1.3, 0.45)))


def obs_snowmanwall(p):
    # A giant snowman holding a wall of snow blocks: the last big thing before the village.
    snowman(p, 18.0, "G")
    for k in range(5):
        x = -10 + k * 5
        if abs(x) < 3:
            continue
        p.append(box(f"Blk{k}", rsize(4.6, 5.0, 3.6), rb(x, 2.5, 1.5), "Snow", bevel=0.5))
        p.append(box(f"BlkTop{k}", rsize(4.2, 2.4, 3.2), rb(x, 6.2, 1.5), "SnowShade", bevel=0.5))


# ---------------------------------------------------------------- pickups

def pick_snow(p):
    rng = random.Random(2)
    for k in range(7):
        r = 1.3 if k else 2.0
        x, z = (0, 0) if k == 0 else (rng.uniform(-1.8, 1.8), rng.uniform(-1.8, 1.8))
        p.append(sphere(f"Lump{k}", r, rb(x, r * 0.45, z), "Snow" if k % 3 else "SnowShade", subdiv=2, scale=(1.2, 1.2, 0.75)))


def pick_coin(p):
    # Upright gold coin facing -Z with a raised snowflake (six bars) on both faces.
    p.append(cyl("Coin", 1.5, 0.5, rb(0, 1.6, 0), "CoinGold", verts=24, rot=(math.radians(90), 0, 0), bevel=0.12))
    p.append(cyl("Rim", 1.18, 0.62, rb(0, 1.6, 0), "CoinDark", verts=24, rot=(math.radians(90), 0, 0), bevel=0.06))
    for s in (-1, 1):
        for k in range(3):
            a = k * math.pi / 3
            p.append(box(f"Flake{s}{k}", rsize(0.22, 1.7, 0.2), rb(0, 1.6, s * 0.36), "CoinGold", bevel=0.05,
                         rot=(0, a, 0)))


def egg_shape(p, base, spot, rng, name="E", r=1.7, k=1.3, spots=9, y0=0.0):
    p.append(sphere(f"{name}Shell", r, rb(0, y0 + r * k, 0), base, subdiv=4, scale=(1, 1, k)))
    for i in range(spots):
        th = rng.uniform(0.5, 2.5)
        ph = rng.uniform(0, math.tau)
        rr = r * 1.0
        x = rr * math.sin(th) * math.cos(ph)
        z = rr * math.sin(th) * math.sin(ph)
        y = y0 + r * k + r * k * math.cos(th)
        p.append(sphere(f"{name}Spot{i}", rng.uniform(0.28, 0.45), rb(x, y, z), spot, subdiv=2, scale=(1, 1, 0.6)))


def pick_egg(p):
    egg_shape(p, "FrostEgg", "Snow", random.Random(4), y0=0.1)
    p.append(sphere("Nest", 1.9, rb(0, 0, 0), "Snow", subdiv=2, scale=(1.3, 1.3, 0.35)))


def pick_present(p):
    p.append(box("Box", rsize(3.0, 2.6, 3.0), rb(0, 1.3, 0), "Red", bevel=0.15))
    p.append(box("Lid", rsize(3.25, 0.6, 3.25), rb(0, 2.85, 0), "Red", bevel=0.15))
    p.append(box("RibX", rsize(3.3, 3.25, 0.5), rb(0, 1.62, 0), "RibbonGold", bevel=0.06))
    p.append(box("RibZ", rsize(0.5, 3.25, 3.3), rb(0, 1.62, 0), "RibbonGold", bevel=0.06))
    for s in (-1, 1):
        p.append(sphere(f"Bow{s}", 0.55, rb(s * 0.5, 3.45, 0), "RibbonGold", subdiv=2, scale=(1.3, 0.7, 0.8)))


def pick_ramp(p):
    # A packed-snow kicker: low at +Z (where the ball comes from), lip at -Z.
    prof = [(5, 0), (-5, 0), (-5, 3.2), (-3, 2.6), (-1, 1.7), (1, 0.95), (3, 0.35)]
    p.append(prism_x("Kicker", prof, -7, 7, "Snow"))
    p.append(prism_x("Lip", [(-5, 2.6), (-5.6, 2.6), (-5.6, 3.6), (-5, 3.6)], -7, 7, "IceDeep"))
    for s in (-1, 1):
        p.append(box(f"Side{s}", rsize(0.8, 3.0, 10.4), rb(s * 7.3, 1.5, 0), "Ice", bevel=0.25))
        for k in range(3):
            p.append(cone(f"Flag{s}{k}", 0.5, 0, 1.2, rb(s * 7.3, 3.6, -4 + k * 4), ["Red", "Gold", "RoofBlue"][k], verts=4))


RARITIES = {
    "Common": ("EggCommon", "SnowShade"), "Uncommon": ("EggUncommon", "Snow"), "Rare": ("EggRare", "Snow"),
    "Epic": ("EggEpic", "Gold"), "Legendary": ("EggLegendary", "Snow"), "Mythic": ("EggMythic", "Gold"),
    "Secret": ("EggSecret", "SpotCyan"),
}


def make_egg(rarity):
    base, spot = RARITIES[rarity]

    def build(p):
        egg_shape(p, base, spot, random.Random(len(rarity)), name=rarity, spots=10)
    return build


MODELS = {
    "Obs_Snowman": obs_snowman, "Obs_Fence": obs_fence, "Obs_Pine": obs_pine, "Obs_Log": obs_log,
    "Obs_IceBlock": obs_iceblock, "Obs_FishingHut": obs_fishinghut, "Obs_Crystal": obs_crystal,
    "Obs_Stalagmite": obs_stalagmite, "Obs_Boulder": obs_boulder, "Obs_BigPine": obs_bigpine,
    "Obs_SnowmanWall": obs_snowmanwall,
    "Pick_Snow": pick_snow, "Pick_Coin": pick_coin, "Pick_Egg": pick_egg, "Pick_Present": pick_present,
    "Pick_Ramp": pick_ramp,
}
for _r in RARITIES:
    MODELS[f"Egg_{_r}"] = make_egg(_r)


def build(name):
    scene = kit.reset()
    kit.light_rig(scene)
    parts = []
    MODELS[name](parts)
    return [kit.join(parts, name)]


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(MODELS)
    for name in names:
        objs = build(name)
        o = objs[0]
        dims = [round(v, 1) for v in o.dimensions]
        size = 1024 if name.startswith("Obs_") else 512
        if "--nobake" not in sys.argv:
            kit.bake_many(objs, name, size=size, samples=12)
            kit.export_glb(objs, name)
        h = max(o.dimensions)
        print(name, dims, kit.preview(name, target=(0, 0, o.dimensions[2] / 2), dist=h * 2.2 + 4, elev=22, azim=-30,
                                      res=(300, 300), samples=8))
