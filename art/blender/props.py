"""Summit props, one small model each, placed many times by WorldService (Config/World
PlazaProps). Origin = footprint centre at ground level, front = -Z (Roblox).

  python props.py            # all
  python props.py Pine Lamp
"""
import math
import random
import sys

import kit
from kit import box, cyl, cone, sphere


def rb(x, y, z):
    return (-x, z, y)


def rsize(sx, sy, sz):
    return (sx, sz, sy)


def pine(p):
    h = 18
    p.append(cyl("Trunk", 1.0, 4, rb(0, 2, 0), "LogDark", verts=8, bevel=0.0))
    for k, (r, f) in enumerate(((6.2, 0.2), (4.8, 0.42), (3.4, 0.62), (2.0, 0.8))):
        y = h * f + 2.5
        p.append(cone(f"L{k}", r, 0.0, h * 0.34, rb(0, y, 0), "Pine" if k % 2 == 0 else "PineDark", verts=8))
        p.append(cone(f"S{k}", r * 0.62, 0.0, h * 0.2, rb(0, y + h * 0.09, 0), "Snow", verts=8))
    p.append(sphere("Pile", 3.2, rb(0, 0, 0), "Snow", subdiv=2, scale=(1.4, 1.4, 0.35)))


def lamp(p):
    p.append(box("Foot", rsize(2.2, 0.8, 2.2), rb(0, 0.4, 0), "StoneDark", bevel=0.2))
    p.append(cyl("Pole", 0.35, 9, rb(0, 4.8, 0), "Black", verts=10, bevel=0.0))
    p.append(box("Arm", rsize(3.2, 0.35, 0.35), rb(0.9, 9.0, 0), "Black", bevel=0.05))
    for s in (-1, 1):
        x = s * 1.6 + 0.9 - 0.9
        p.append(box(f"Lamp{s}", rsize(1.2, 1.5, 1.2), rb(x, 8.0, 0), "Glow", bevel=0.15))
        p.append(cone(f"Hat{s}", 1.05, 0.15, 0.7, rb(x, 9.1, 0), "Black", verts=4, rot=(0, 0, math.radians(45))))
        p.append(box(f"HatSnow{s}", rsize(0.9, 0.25, 0.9), rb(x, 9.5, 0), "Snow", bevel=0.1))
    p.append(sphere("Top", 0.5, rb(0, 10.1, 0), "Gold", subdiv=1))


def snowman(p):
    p.append(sphere("Bottom", 2.6, rb(0, 2.3, 0), "Snow", subdiv=3))
    p.append(sphere("Middle", 1.9, rb(0, 5.6, 0), "Snow", subdiv=3))
    p.append(sphere("Head", 1.35, rb(0, 8.1, 0), "Snow", subdiv=3))
    p.append(cone("Nose", 0.28, 0.0, 1.4, rb(0, 8.1, -1.9), "Plank", verts=8, rot=(math.radians(90), 0, 0)))
    for s in (-1, 1):
        p.append(sphere(f"Eye{s}", 0.18, rb(s * 0.5, 8.5, -1.2), "Black", subdiv=1))
        p.append(cyl(f"Arm{s}", 0.13, 3.2, rb(s * 2.9, 6.2, 0), "LogDark", verts=6, rot=(0, math.radians(90) * -s * 0.7, 0), bevel=0.0))
    for k in range(3):
        p.append(sphere(f"Button{k}", 0.2, rb(0, 4.9 + k * 0.7, -1.85 + k * 0.05), "Black", subdiv=1))
    p.append(cyl("Scarf", 1.45, 0.6, rb(0, 7.15, 0), "Red", verts=16, bevel=0.08))
    p.append(box("ScarfTail", rsize(0.7, 1.8, 0.3), rb(0.7, 6.3, -1.3), "Red", bevel=0.08))
    p.append(cyl("HatBrim", 1.5, 0.25, rb(0, 9.25, 0), "Black", verts=14, bevel=0.05))
    p.append(cyl("Hat", 1.0, 1.6, rb(0, 10.1, 0), "Black", verts=14, bevel=0.08))
    p.append(cyl("HatBand", 1.03, 0.35, rb(0, 9.6, 0), "Red", verts=14, bevel=0.0))


def rock(p):
    rng = random.Random(4)
    for k in range(4):
        r = rng.uniform(1.4, 2.6)
        x, z = rng.uniform(-2, 2), rng.uniform(-2, 2)
        p.append(sphere(f"Rock{k}", r, rb(x, r * 0.5, z), "Stone" if k % 2 else "StoneDark", subdiv=1, scale=(1.2, 1.0, 0.8)))
        p.append(sphere(f"Cap{k}", r * 0.75, rb(x, r * 0.95, z), "Snow", subdiv=1, scale=(1.2, 1.0, 0.35)))


def crystal(p):
    rng = random.Random(9)
    p.append(sphere("Base", 2.2, rb(0, 0, 0), "Snow", subdiv=2, scale=(1.3, 1.3, 0.4)))
    for k in range(6):
        a = k / 6 * math.tau
        r = 0.0 if k == 0 else 1.3
        h = 6.5 if k == 0 else rng.uniform(2.5, 4.2)
        tilt = 0 if k == 0 else 0.35
        p.append(cone(f"C{k}", 0.75 if k else 1.0, 0.0, h, rb(math.cos(a) * r, h / 2, math.sin(a) * r), "Ice", verts=6,
                      rot=(math.sin(a) * tilt, -math.cos(a) * tilt, 0)))


def bench(p):
    p.append(box("Seat", rsize(7, 0.5, 2.2), rb(0, 2.1, 0), "Plank", bevel=0.12))
    p.append(box("Back", rsize(7, 1.6, 0.4), rb(0, 3.6, 1.0), "Plank", bevel=0.12, rot=(math.radians(-10), 0, 0)))
    for s in (-1, 1):
        p.append(box(f"Leg{s}", rsize(0.5, 2.1, 2.0), rb(s * 3, 1.05, 0), "Black", bevel=0.06))
    p.append(box("Snow", rsize(6.6, 0.35, 1.9), rb(0, 2.5, 0), "Snow", bevel=0.15))


def flagpole(p):
    p.append(box("Foot", rsize(2, 0.8, 2), rb(0, 0.4, 0), "StoneDark", bevel=0.2))
    p.append(cyl("Pole", 0.3, 14, rb(0, 7.4, 0), "Iron", verts=10, bevel=0.0))
    p.append(sphere("Ball", 0.55, rb(0, 14.6, 0), "Gold", subdiv=1))
    # A wavy pennant (three tilted slabs) in game blue with a white snowflake block.
    for k in range(3):
        p.append(box(f"Flag{k}", rsize(1.6, 3.2 - k * 0.6, 0.2), rb(1.1 + k * 1.5, 12.4 - k * 0.2, (k % 2) * 0.25), "RoofBlue", bevel=0.05,
                     rot=(0, math.radians(8 if k % 2 else -8), 0)))
    p.append(box("FlagMark", rsize(1.0, 1.0, 0.3), rb(2.0, 12.4, 0), "Snow", bevel=0.05, rot=(0, math.radians(45), 0)))


PROPS = {"Pine": pine, "Lamp": lamp, "Snowman": snowman, "Rock": rock, "Crystal": crystal, "Bench": bench, "Flagpole": flagpole}


def build(name):
    scene = kit.reset()
    kit.light_rig(scene)
    parts = []
    PROPS[name](parts)
    return [kit.join(parts, name)]


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(PROPS)
    for name in names:
        objs = build(name)
        print(name, sum(len(p.vertices) - 2 for p in objs[0].data.polygons))
        if "--nobake" not in sys.argv:
            kit.bake_many(objs, f"Prop_{name}", size=512, samples=16)
            print(kit.export_glb(objs, f"Prop_{name}"))
        print(kit.preview(f"Prop_{name}", target=(0, 0, 5), dist=30, elev=20, azim=-30, res=(400, 400), samples=12))
