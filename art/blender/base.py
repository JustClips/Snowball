"""Player base: a stud-style snowy yard with a log cabin, fence, gate, egg pedestals, pet pads,
lanterns and little pines. Footprint = World.BaseSize (64 x 56 studs).

Coordinates below are written in ROBLOX base-local space (x right, y up, z back; the base's
front / gate faces -Z toward the plaza) and converted with rb(). Keep these numbers in sync
with World.eggSpot / World.petSpot in src/shared/Config/World.luau.
"""
import math
import random

import kit
from kit import box, cyl, cone, sphere

W, D = 64, 56          # footprint (Roblox x, z)
FLOOR = 0.5            # floor top height (base pad top = base centre + 0.5)
GATE_HALF = 6

EGGS = [(-24, -20), (-15, -20), (-24, -11), (-15, -11)]
PETS = [(10, -20), (18, -20), (26, -20), (10, -11), (18, -11), (26, -11), (-24, 2), (-15, 2), (15, 2), (24, 2)]


def rb(x, y, z):
    """Roblox base-local (x, y, z) -> Blender (x, y, z)."""
    return (-x, z, y)


def rsize(sx, sy, sz):
    return (sx, sz, sy)


def floor(parts):
    parts.append(box("Floor", rsize(W, 2, D), rb(0, FLOOR - 1, 0), "Snow", bevel=0.4, studs=True))
    # Chunky stone rim under the snow so the base reads as a raised platform.
    parts.append(box("Rim", rsize(W + 1.2, 1.6, D + 1.2), rb(0, FLOOR - 2.2, 0), "StoneDark", bevel=0.3))


def fence(parts):
    rng = random.Random(3)
    hx, hz = W / 2 - 1, D / 2 - 1
    posts = []
    # Posts every ~8 studs around the edge, leaving the gate gap at the front centre.
    for x in range(-int(hx), int(hx) + 1, 8):
        posts.append((x, hz))
        if abs(x) > GATE_HALF:
            posts.append((x, -hz))
    for z in range(-int(hz) + 8, int(hz), 8):
        posts.append((hx, z))
        posts.append((-hx, z))
    for c in [(hx, hz), (-hx, hz), (hx, -hz), (-hx, -hz), (GATE_HALF + 1, -hz), (-GATE_HALF - 1, -hz)]:
        posts.append(c)
    for i, (x, z) in enumerate(set(posts)):
        h = 4.2 + rng.uniform(-0.2, 0.2)
        parts.append(box(f"Post{i}", rsize(1.2, h, 1.2), rb(x, FLOOR + h / 2, z), "Log", bevel=0.18))
        parts.append(box(f"PostCap{i}", rsize(1.6, 0.6, 1.6), rb(x, FLOOR + h + 0.2, z), "Snow", bevel=0.25))

    def rail(name, a, b, y):
        (x1, z1), (x2, z2) = a, b
        L = math.hypot(x2 - x1, z2 - z1)
        cx, cz = (x1 + x2) / 2, (z1 + z2) / 2
        along_x = abs(x2 - x1) > abs(z2 - z1)
        size = rsize(L, 0.6, 0.5) if along_x else rsize(0.5, 0.6, L)
        parts.append(box(name, size, rb(cx, y, cz), "Plank", bevel=0.12))

    for y in (FLOOR + 1.6, FLOOR + 3.2):
        rail(f"RailBack{y}", (-hx, hz), (hx, hz), y)
        rail(f"RailL{y}", (-hx, -hz), (-hx, hz), y)
        rail(f"RailR{y}", (hx, -hz), (hx, hz), y)
        rail(f"RailFL{y}", (-hx, -hz), (-GATE_HALF - 1, -hz), y)
        rail(f"RailFR{y}", (GATE_HALF + 1, -hz), (hx, -hz), y)

    # Gate: two tall posts, an arch beam with a snow cap and a big snowball emblem.
    for s in (-1, 1):
        x = s * (GATE_HALF + 1)
        parts.append(box(f"GatePost{s}", rsize(2, 9, 2), rb(x, FLOOR + 4.5, -hz), "LogDark", bevel=0.25))
        parts.append(box(f"GateCap{s}", rsize(2.6, 0.8, 2.6), rb(x, FLOOR + 9.3, -hz), "Snow", bevel=0.3))
        # Lantern hanging on the inner face of each gate post.
        parts.append(box(f"GateLamp{s}", rsize(1, 1.4, 1), rb(x - s * 1.5, FLOOR + 6.5, -hz - 0.2), "Glow", bevel=0.15))
        parts.append(box(f"GateLampTop{s}", rsize(1.3, 0.3, 1.3), rb(x - s * 1.5, FLOOR + 7.35, -hz - 0.2), "Black", bevel=0.08))
    parts.append(box("GateBeam", rsize(2 * GATE_HALF + 5, 1.6, 1.8), rb(0, FLOOR + 8.2, -hz), "Log", bevel=0.25))
    parts.append(box("GateBeamSnow", rsize(2 * GATE_HALF + 5.4, 0.6, 2.2), rb(0, FLOOR + 9.2, -hz), "Snow", bevel=0.28))
    parts.append(cyl("GateBadge", 2.1, 0.6, rb(0, FLOOR + 8.4, -hz - 1.0), "RoofBlue", verts=20, rot=(math.radians(90), 0, 0), bevel=0.15))
    parts.append(sphere("GateBall", 1.5, rb(0, FLOOR + 8.4, -hz - 1.6), "Snow", subdiv=2))


def path(parts):
    rng = random.Random(7)
    z = -D / 2 + 1
    i = 0
    while z < 15:
        for x in (-2, 0, 2):
            h = 0.35 + rng.uniform(0, 0.15)
            c = "Stone" if (i + x // 2) % 2 == 0 else "StoneDark"
            parts.append(box(f"Cobble{i}_{x}", rsize(1.8, h, 1.8), rb(x + rng.uniform(-0.1, 0.1), FLOOR + h / 2 - 0.1, z), c, bevel=0.15))
        z += 2
        i += 1


def logwall(parts, name, a, b, rows, r=0.62):
    """Stacked horizontal logs from a to b (Roblox xz)."""
    (x1, z1), (x2, z2) = a, b
    L = math.hypot(x2 - x1, z2 - z1)
    along_x = abs(x2 - x1) > abs(z2 - z1)
    for k in range(rows):
        y = FLOOR + r + k * r * 1.85
        c = "Log" if k % 2 == 0 else "LogDark"
        rot = (0, math.radians(90), 0) if along_x else (math.radians(90), 0, 0)
        parts.append(cyl(f"{name}{k}", r, L + 1.4, rb((x1 + x2) / 2, y, (z1 + z2) / 2), c, verts=10, rot=rot, bevel=0.0))


def cabin(parts):
    x0, x1, z0, z1 = -11, 11, 15, 27
    rows = 7
    top = FLOOR + 0.62 + rows * 0.62 * 1.85
    # Solid inner block so there are no gaps between logs.
    parts.append(box("CabinCore", rsize(x1 - x0 - 0.6, top - FLOOR, z1 - z0 - 0.6), rb(0, (top + FLOOR) / 2, (z0 + z1) / 2), "LogDark", bevel=0.0))
    logwall(parts, "WallF", (x0, z0), (x1, z0), rows)
    logwall(parts, "WallB", (x0, z1), (x1, z1), rows)
    logwall(parts, "WallL", (x0, z0), (x0, z1), rows)
    logwall(parts, "WallR", (x1, z0), (x1, z1), rows)
    # Gable roof: ridge along x. Two slabs + snow layer on each.
    span = (z1 - z0) / 2 + 2.2
    rise = 6.0
    ang = math.atan2(rise, span)
    slab = math.hypot(span, rise)
    zc = (z0 + z1) / 2
    for s in (-1, 1):
        cz = zc + s * span / 2
        cy = top + rise / 2
        # Blender: rotation about X tilts along Y (= Roblox z).
        rot = (-s * ang, 0, 0)
        parts.append(box(f"Roof{s}", rsize(x1 - x0 + 3.6, 0.9, slab), rb(0, cy, cz), "RoofRed", bevel=0.2, rot=rot))
        parts.append(box(f"RoofSnow{s}", rsize(x1 - x0 + 3.9, 0.7, slab * 0.92), rb(0, cy + 0.75, cz - s * 0.25), "Snow", bevel=0.3, rot=rot))
    # Gable triangles (front and back) as wedge-ish prisms: a scaled cone with 3 verts would
    # read badly, so stack shrinking log rows instead.
    # Gable triangles on the side walls (ridge runs along x): shrinking log rows.
    for xx, nm in ((x0, "GableL"), (x1, "GableR")):
        for k in range(3):
            w = (z1 - z0) * (1 - (k + 0.6) / 3.3)
            parts.append(box(f"{nm}{k}", rsize(1.0, 1.4, w), rb(xx, top + 0.7 + k * 1.4, zc), "Log" if k % 2 == 0 else "LogDark", bevel=0.2))
    # Ridge beam.
    parts.append(box("Ridge", rsize(x1 - x0 + 4, 0.9, 0.9), rb(0, top + rise + 0.5, zc), "Snow", bevel=0.3))
    # Chimney.
    parts.append(box("Chimney", rsize(3, 9, 3), rb(-6, top + 3.5, zc + 3), "Stone", bevel=0.25))
    parts.append(box("ChimneyTop", rsize(3.8, 0.8, 3.8), rb(-6, top + 8.2, zc + 3), "StoneDark", bevel=0.2))
    parts.append(box("ChimneySnow", rsize(3.6, 0.6, 3.6), rb(-6, top + 8.8, zc + 3), "Snow", bevel=0.25))
    # Door with frame + porch step + awning.
    parts.append(box("DoorFrame", rsize(5.2, 7.4, 0.8), rb(0, FLOOR + 3.7, z0 - 0.6), "LogDark", bevel=0.15))
    parts.append(box("Door", rsize(4, 6.6, 0.6), rb(0, FLOOR + 3.3, z0 - 0.9), "Door", bevel=0.15))
    parts.append(sphere("DoorKnob", 0.3, rb(1.3, FLOOR + 3.2, z0 - 1.3), "Gold", subdiv=1))
    parts.append(box("DoorWindow", rsize(1.8, 1.4, 0.3), rb(0, FLOOR + 5.2, z0 - 1.25), "Window", bevel=0.08))
    parts.append(box("Porch", rsize(9, 0.7, 3), rb(0, FLOOR + 0.35, z0 - 2), "Plank", bevel=0.15))
    parts.append(box("Awning", rsize(7.5, 0.5, 3), rb(0, FLOOR + 8.0, z0 - 1.6), "RoofRed", bevel=0.15, rot=(math.radians(-14), 0, 0)))
    parts.append(box("AwningSnow", rsize(7.8, 0.4, 2.8), rb(0, FLOOR + 8.45, z0 - 1.7), "Snow", bevel=0.18, rot=(math.radians(-14), 0, 0)))
    # Glowing windows with shutters + flower(snow) boxes on the front.
    for wx in (-6.5, 6.5):
        parts.append(box(f"WinFrame{wx}", rsize(3.8, 3.8, 0.6), rb(wx, FLOOR + 4.6, z0 - 0.75), "LogDark", bevel=0.12))
        parts.append(box(f"Win{wx}", rsize(3, 3, 0.4), rb(wx, FLOOR + 4.6, z0 - 1.0), "Window", bevel=0.06))
        parts.append(box(f"WinBarV{wx}", rsize(0.3, 3, 0.3), rb(wx, FLOOR + 4.6, z0 - 1.25), "LogDark", bevel=0.0))
        parts.append(box(f"WinBarH{wx}", rsize(3, 0.3, 0.3), rb(wx, FLOOR + 4.6, z0 - 1.25), "LogDark", bevel=0.0))
        for s in (-1, 1):
            parts.append(box(f"Shutter{wx}{s}", rsize(1.4, 3.8, 0.4), rb(wx + s * 2.7, FLOOR + 4.6, z0 - 0.9), "RoofBlue", bevel=0.1))
        parts.append(box(f"SillBox{wx}", rsize(4.2, 0.9, 1.2), rb(wx, FLOOR + 2.4, z0 - 1.1), "Plank", bevel=0.12))
        parts.append(box(f"SillSnow{wx}", rsize(4.0, 0.4, 1.0), rb(wx, FLOOR + 3.0, z0 - 1.1), "Snow", bevel=0.15))
    # Side windows.
    for sx in (x0, x1):
        s = 1 if sx > 0 else -1
        parts.append(box(f"SideWin{sx}", rsize(0.4, 3, 3), rb(sx + s * 0.75, FLOOR + 4.6, (z0 + z1) / 2), "Window", bevel=0.06))
        parts.append(box(f"SideWinFrame{sx}", rsize(0.4, 3.8, 3.8), rb(sx + s * 0.55, FLOOR + 4.6, (z0 + z1) / 2), "LogDark", bevel=0.1))
    # Firewood stack by the side wall.
    for k in range(3):
        for j in range(4 - k):
            parts.append(cyl(f"Wood{k}{j}", 0.45, 2.6, rb(x1 + 1.9 + j * 0.95 + k * 0.45, FLOOR + 0.45 + k * 0.82, z0 + 3), "Plank", verts=8, rot=(math.radians(90), 0, 0), bevel=0.0))


def pedestal(parts, i, x, z):
    parts.append(cyl(f"Ped{i}", 3.0, 0.8, rb(x, FLOOR + 0.4, z), "StoneDark", verts=16, bevel=0.15))
    parts.append(cyl(f"PedTop{i}", 2.5, 0.5, rb(x, FLOOR + 1.0, z), "Stone", verts=16, bevel=0.12))
    parts.append(cyl(f"PedRing{i}", 2.7, 0.25, rb(x, FLOOR + 0.9, z), "Gold", verts=16, bevel=0.06))
    # Four little ice crystals around the pedestal.
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        parts.append(cone(f"PedIce{i}{k}", 0.45, 0.0, 1.4, rb(x + math.cos(a) * 2.9, FLOOR + 0.7, z + math.sin(a) * 2.9), "Ice", verts=5))


def petpad(parts, i, x, z):
    parts.append(cyl(f"Pad{i}", 2.6, 0.3, rb(x, FLOOR + 0.15, z), "Ice", verts=16, bevel=0.1))
    parts.append(cyl(f"PadIn{i}", 1.9, 0.32, rb(x, FLOOR + 0.17, z), "SnowShade", verts=16, bevel=0.08))


def pine(parts, name, x, z, h=10):
    parts.append(cyl(f"{name}Trunk", 0.6, h * 0.25, rb(x, FLOOR + h * 0.125, z), "LogDark", verts=8, bevel=0.0))
    for k, (r, f) in enumerate(((h * 0.32, 0.25), (h * 0.25, 0.48), (h * 0.17, 0.68))):
        y = FLOOR + h * f + h * 0.14
        parts.append(cone(f"{name}L{k}", r, 0.0, h * 0.36, rb(x, y, z), "Pine" if k % 2 == 0 else "PineDark", verts=8))
        parts.append(cone(f"{name}S{k}", r * 0.55, 0.0, h * 0.2, rb(x, y + h * 0.1, z), "Snow", verts=8))


def lantern(parts, name, x, z):
    parts.append(cyl(f"{name}Pole", 0.3, 4, rb(x, FLOOR + 2, z), "Black", verts=8, bevel=0.0))
    parts.append(box(f"{name}Lamp", rsize(1.1, 1.3, 1.1), rb(x, FLOOR + 4.6, z), "Glow", bevel=0.15))
    parts.append(cone(f"{name}Hat", 0.95, 0.15, 0.7, rb(x, FLOOR + 5.6, z), "Black", verts=4, rot=(0, 0, math.radians(45))))


def piles(parts):
    rng = random.Random(11)
    for i, (x, z) in enumerate([(-28, 24), (28, 24), (-28, -6), (29, 10), (-6, 24), (-20, 14), (20, 14)]):
        r = rng.uniform(1.4, 2.4)
        parts.append(sphere(f"Pile{i}", r, rb(x, FLOOR + r * 0.15, z), "Snow", subdiv=2, scale=(1.3, 1.1, 0.6)))


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    ground, fences, house, props = [], [], [], []
    floor(ground)
    path(ground)
    fence(fences)
    cabin(house)
    for i, (x, z) in enumerate(EGGS):
        pedestal(props, i, x, z)
    for i, (x, z) in enumerate(PETS):
        petpad(props, i, x, z)
    pine(props, "PineA", -26, 22, 11)
    pine(props, "PineB", 26, 22, 12)
    pine(props, "PineC", -18, 24, 8)
    pine(props, "PineD", 18, 24, 8)
    for i, (x, z) in enumerate([(-4.5, -14), (4.5, -14), (-4.5, 4), (4.5, 4)]):
        lantern(props, f"Lantern{i}", x, z)
    piles(props)
    objs = [kit.join(ground, "Ground"), kit.join(fences, "Fence"), kit.join(house, "Cabin"), kit.join(props, "Props")]
    return objs


if __name__ == "__main__":
    import sys
    objs = build()
    for o in objs:
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        print(o.name, "tris", tris)
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "Base", size=2048)
        print(kit.export_glb(objs, "Base"))
    print(kit.preview("Base", target=(0, 4, 3), dist=95, elev=34, azim=-30))
