"""Launch deck (World.Deck: 140 x 44 studs, top at y = 0, centre = World.Deck.Center).
Authored in Roblox world axes relative to the deck centre: the balls launch toward +Z
(down the track), the plaza is at -Z. Lanes follow World.laneX (8 lanes, 13 apart), the
roller stands at z = -10 (World.DeckStand). Objects: "Deck" (floor, lane rails, lane pads)
and "Arch" (the start gate over the launch edge with start lights and bunting).

  python deck.py
"""
import math
import sys

import kit
from kit import box, cyl, cone, sphere

W, D = 140, 44
LANES, SPACING = 8, 13
LANE_COLORS = ["Red", "RoofBlue", "Green", "Gold", "Purple", "Ice", "Plank", "Aurora"]


def rb(x, y, z):
    return (-x, z, y)


def rsize(sx, sy, sz):
    return (sx, sz, sy)


def lane_x(i):
    return (i - (LANES + 1) / 2) * SPACING


def deck(p):
    # Plank floor (planks run along the launch direction) over a log frame.
    n = int(W // 2.5)
    for k in range(n):
        x = -W / 2 + 1.25 + k * 2.5
        c = "Plank" if k % 2 == 0 else "Log"
        p.append(box(f"Plank{k}", rsize(2.35, 1.2, D - 1), rb(x, -0.6, -0.5), c, bevel=0.12))
    for s in (-1, 1):
        p.append(box(f"Beam{s}", rsize(1.6, 2.4, D + 1), rb(s * (W / 2 + 0.3), -0.4, 0), "LogDark", bevel=0.2))
    p.append(box("BackBeam", rsize(W + 2.6, 2.4, 1.6), rb(0, -0.4, -D / 2 - 0.3), "LogDark", bevel=0.2))
    p.append(box("BackSnow", rsize(W + 3, 0.6, 2.0), rb(0, 1.0, -D / 2 - 0.3), "Snow", bevel=0.25))
    # Lane rails: low log rails between lanes, only on the front half so walking across
    # the back of the deck (where you step on) stays free.
    for k in range(LANES + 1):
        x = lane_x(k + 0.5)
        if abs(x) > W / 2:
            continue
        p.append(cyl(f"Rail{k}", 0.5, 26, rb(x, 0.5, 8), "Log" if k % 2 == 0 else "LogDark", verts=8, rot=(math.radians(90), 0, 0), bevel=0.0))
        p.append(box(f"RailCap{k}", rsize(0.9, 0.35, 25), rb(x, 1.0, 8), "Snow", bevel=0.12))
    # Lane start pads: a coloured ring where each lane's roller stands, and a chevron
    # arrow pointing down the lane.
    for i in range(1, LANES + 1):
        x = lane_x(i)
        c = LANE_COLORS[i - 1]
        p.append(cyl(f"Pad{i}", 3.6, 0.3, rb(x, 0.15, -10), c, verts=20, bevel=0.08))
        p.append(cyl(f"PadIn{i}", 2.8, 0.34, rb(x, 0.17, -10), "Snow", verts=20, bevel=0.06))
        for j in range(3):
            z = 2 + j * 5
            for s in (-1, 1):
                p.append(box(f"Chev{i}{j}{s}", rsize(2.6, 0.2, 0.9), rb(x + s * 0.9, 0.1, z), c, bevel=0.05,
                             rot=(0, 0, math.radians(35 * s))))


def arch(p):
    z = D / 2 - 1.5
    top = 24
    for s in (-1, 1):
        x = s * (W / 2 - 1)
        # Tower: stacked stone blocks with a pointed snowy roof and a flag.
        p.append(box(f"Tower{s}", rsize(6, top, 6), rb(x, top / 2, z), "Stone", bevel=0.3))
        for k in range(4):
            p.append(box(f"TowerBand{s}{k}", rsize(6.4, 0.8, 6.4), rb(x, 3 + k * 6, z), "StoneDark", bevel=0.2))
        p.append(cone(f"TowerRoof{s}", 5.2, 0.2, 7, rb(x, top + 3.5, z), "RoofBlue", verts=4, rot=(0, 0, math.radians(45))))
        p.append(cone(f"TowerRoofSnow{s}", 3.6, 0.2, 3.4, rb(x, top + 5.3, z), "Snow", verts=4, rot=(0, 0, math.radians(45))))
        p.append(cyl(f"FlagPole{s}", 0.25, 6, rb(x, top + 9, z), "Black", verts=8, bevel=0.0))
        p.append(box(f"Flag{s}", rsize(3.2, 2.0, 0.2), rb(x - s * 1.7, top + 10.6, z), "Red", bevel=0.05))
        # Lantern on the inner face.
        p.append(box(f"TowerLamp{s}", rsize(1.4, 1.8, 1.4), rb(x - s * 3.8, 10, z), "Glow", bevel=0.15))
    # Banner beam across the top.
    p.append(box("Banner", rsize(W - 6, 4, 2), rb(0, top - 2.5, z), "RoofBlue", bevel=0.3))
    p.append(box("BannerTrim", rsize(W - 5.4, 0.8, 2.4), rb(0, top - 0.3, z), "Gold", bevel=0.2))
    p.append(box("BannerTrimLow", rsize(W - 5.4, 0.8, 2.4), rb(0, top - 4.7, z), "Gold", bevel=0.2))
    p.append(box("BannerSnow", rsize(W - 5, 0.7, 2.6), rb(0, top + 0.5, z), "Snow", bevel=0.3))
    # Start lights in the middle: three big lamps (red, yellow, green) on a black board.
    p.append(box("LightBoard", rsize(13, 5, 1.2), rb(0, top - 2.5, z - 1.4), "Black", bevel=0.2))
    for k, c in enumerate(("Red", "Gold", "Green")):
        p.append(cyl(f"Light{k}", 1.6, 0.8, rb(-4 + k * 4, top - 2.5, z - 2.1), c, verts=16, rot=(math.radians(90), 0, 0), bevel=0.1))
    # Snowflake emblems along the banner.
    for k, x in enumerate((-45, -25, 25, 45)):
        p.append(cyl(f"Emb{k}", 1.6, 0.4, rb(x, top - 2.5, z - 1.1), "Snow", verts=6, rot=(math.radians(90), 0, 0), bevel=0.08))
    # Bunting: little triangle flags hanging under the banner.
    n = 34
    for k in range(n):
        x = -W / 2 + 6 + k * (W - 12) / (n - 1)
        sag = math.sin(math.pi * ((k % 17) / 16)) * 1.4
        c = ["Red", "Gold", "Green", "RoofBlue"][k % 4]
        p.append(cone(f"Bunt{k}", 0.9, 0.0, 1.8, rb(x, top - 6.1 - sag, z), c, verts=3, rot=(math.radians(180), 0, 0)))


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    a, b = [], []
    deck(a)
    arch(b)
    return [kit.join(a, "Deck"), kit.join(b, "Arch")]


if __name__ == "__main__":
    objs = build()
    for o in objs:
        print(o.name, sum(len(p.vertices) - 2 for p in o.data.polygons))
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "Deck", size=2048, samples=16)
        print(kit.export_glb(objs, "Deck"))
    print(kit.preview("Deck", target=(0, 0, 6), dist=150, elev=28, azim=-25, res=(960, 600), samples=16))
