"""Snow Roller training stations, one model per tier (Config/Rollers: 8 cash + 5 Robux).
Upgrading swaps the model in place (TrainService:RefreshRoller), so every tier keeps the
same footprint: a 16 x 16 stud deck, a big snowball (radius 4.5) resting on two log drums
at Roblox-local (0, 5, 4.5) relative to the deck top, and an arch over it with the tier
emblem. Two objects per model: "Station" (static) and "Ball" (spun by TrainController).

Coordinates are Roblox roller-local (x right, y up, z back; -Z = front) via rb().
  python roller.py            # every tier
  python roller.py Wooden Gold
"""
import math
import sys

import kit
from kit import box, cyl, cone, sphere

DECK = 0.6  # deck top height above the pad top


def rb(x, y, z):
    return (-x, z, y)


def rsize(sx, sy, sz):
    return (sx, sz, sy)


# Per-tier look: frame colour, trim, ball tint, emblem colour, extras.
TIERS = {
    "Wooden": dict(frame="Log", trim="Plank", ball="Snow", emblem="Plank", extras=[]),
    "Stone": dict(frame="Stone", trim="StoneDark", ball="Snow", emblem="StoneDark", extras=["boulders"]),
    "Iron": dict(frame="Iron", trim="Black", ball="Snow", emblem="Iron", extras=["rivets"]),
    "Gold": dict(frame="Gold", trim="Log", ball="Snow", emblem="Gold", extras=["rivets", "lamps"]),
    "Crystal": dict(frame="Ice", trim="Snow", ball="Ice", emblem="Ice", extras=["crystals"]),
    "Diamond": dict(frame="Diamond", trim="Snow", ball="Diamond", emblem="Diamond", extras=["crystals", "lamps"]),
    "Aurora": dict(frame="Aurora", trim="Purple", ball="Snow", emblem="Aurora", extras=["crystals", "arcs"]),
    "Glacier": dict(frame="RoofBlue", trim="Ice", ball="Ice", emblem="RoofBlue", extras=["crystals", "spikes", "lamps"]),
    "CandyCane": dict(frame="Red", trim="Snow", ball="Snow", emblem="Red", extras=["stripes", "lamps"]),
    "Golden": dict(frame="Gold", trim="Gold", ball="Gold", emblem="Gold", extras=["rivets", "lamps", "spikes"]),
    "NorthernLights": dict(frame="Aurora", trim="RoofBlue", ball="Aurora", emblem="Aurora", extras=["arcs", "crystals"]),
    "Galaxy": dict(frame="Purple", trim="Black", ball="Purple", emblem="Purple", extras=["stars", "arcs"]),
    "Divine": dict(frame="Snow", trim="Gold", ball="Snow", emblem="Gold", extras=["wings", "lamps", "stars"]),
}


def station(t, parts):
    f, trim = t["frame"], t["trim"]
    # Deck: planks with a trim border.
    parts.append(box("Deck", rsize(16, DECK, 16), rb(0, DECK / 2, 0), trim, bevel=0.15))
    for k in range(7):
        parts.append(box(f"Plank{k}", rsize(14.6, 0.25, 1.9), rb(0, DECK + 0.1, -6 + k * 2), f if f in ("Log", "Plank") else "Plank", bevel=0.08))
    # Log drums the ball rests on (front and back of the ball).
    for dz in (-2.6, 2.6):
        parts.append(cyl(f"Drum{dz}", 1.1, 11, rb(0, DECK + 1.1, 4.5 + dz), f, verts=14, rot=(0, math.radians(90), 0), bevel=0.1))
        for sx in (-1, 1):
            parts.append(box(f"DrumStand{dz}{sx}", rsize(1, 2.2, 1.6), rb(sx * 5.8, DECK + 1.1, 4.5 + dz), trim, bevel=0.12))
    # Arch over the ball: two posts and a beam with a snow cap.
    for sx in (-1, 1):
        parts.append(box(f"Post{sx}", rsize(1.6, 13, 1.6), rb(sx * 7, DECK + 6.5, 4.5), f, bevel=0.2))
        parts.append(box(f"PostFoot{sx}", rsize(2.4, 1, 2.4), rb(sx * 7, DECK + 0.5, 4.5), trim, bevel=0.15))
    parts.append(box("Beam", rsize(16.4, 1.8, 2), rb(0, DECK + 13.2, 4.5), f, bevel=0.22))
    parts.append(box("BeamSnow", rsize(16.8, 0.6, 2.4), rb(0, DECK + 14.3, 4.5), "Snow", bevel=0.25))
    # Emblem: a disc with a snowflake on the front of the beam.
    parts.append(cyl("Emblem", 2.2, 0.5, rb(0, DECK + 13.2, 4.5 - 1.2), t["emblem"], verts=20, rot=(math.radians(90), 0, 0), bevel=0.12))
    parts.append(cyl("EmblemRim", 2.5, 0.35, rb(0, DECK + 13.2, 4.5 - 1.0), trim, verts=20, rot=(math.radians(90), 0, 0), bevel=0.08))
    for k in range(3):
        a = k * math.pi / 3
        parts.append(box(f"Flake{k}", rsize(2.8, 0.35, 0.3), rb(0, DECK + 13.2, 4.5 - 1.5), "Snow", bevel=0.0, rot=(0, a, 0)))
    # Push bar at the front where the player stands.
    parts.append(box("Rail", rsize(8, 0.5, 0.5), rb(0, DECK + 3.4, -1.0), trim, bevel=0.1))
    for sx in (-1, 1):
        parts.append(box(f"RailPost{sx}", rsize(0.5, 3.4, 0.5), rb(sx * 3.8, DECK + 1.7, -1.0), trim, bevel=0.08))
    extras(t, parts)


def extras(t, parts):
    ex = t["extras"]
    corners = [(-7.2, -7.2), (7.2, -7.2)]
    if "boulders" in ex:
        for i, (x, z) in enumerate(corners + [(-7.4, 7.6), (7.4, 7.6)]):
            parts.append(sphere(f"Boulder{i}", 1.1, rb(x, DECK + 0.6, z), "StoneDark", subdiv=1, scale=(1.2, 1, 0.8)))
    if "rivets" in ex:
        for sx in (-1, 1):
            for y in (3, 6, 9, 12):
                parts.append(sphere(f"Rivet{sx}{y}", 0.3, rb(sx * 7, DECK + y, 4.5 - 0.85), "Black" if t["frame"] != "Iron" else "Gold", subdiv=1))
    if "lamps" in ex:
        for i, (x, z) in enumerate(corners):
            parts.append(cyl(f"LampPole{i}", 0.25, 3.4, rb(x, DECK + 1.7, z), "Black", verts=8, bevel=0.0))
            parts.append(box(f"Lamp{i}", rsize(1, 1.2, 1), rb(x, DECK + 3.9, z), "Glow", bevel=0.12))
    if "crystals" in ex:
        for i, (x, z, h) in enumerate([(-7.3, -7.0, 3.2), (-6.2, -7.4, 2.0), (7.3, -7.0, 3.0), (6.4, 7.6, 2.4), (-6.8, 7.4, 2.8)]):
            parts.append(cone(f"Crystal{i}", 0.7, 0.0, h, rb(x, DECK + h / 2, z), t["emblem"] if t["emblem"] != "Gold" else "Diamond", verts=6))
    if "spikes" in ex:
        for sx in (-1, 1):
            parts.append(cone(f"Spike{sx}", 0.9, 0.0, 2.4, rb(sx * 7, DECK + 15.6, 4.5), t["trim"], verts=6))
    if "arcs" in ex:
        # Glowing ribbon arcs behind the arch.
        for k in range(14):
            a = math.pi * (k + 0.5) / 14
            parts.append(box(f"Arc{k}", rsize(2.2, 0.7, 0.5), rb(-math.cos(a) * 9.5, DECK + 7 + math.sin(a) * 9, 6.4), "Aurora" if k % 2 == 0 else "Glow", bevel=0.1, rot=(0, -(a - math.pi / 2), 0)))
    if "stripes" in ex:
        for sx in (-1, 1):
            for y in range(1, 13, 2):
                parts.append(box(f"Stripe{sx}{y}", rsize(1.75, 0.8, 1.75), rb(sx * 7, DECK + y + 0.5, 4.5), "Snow", bevel=0.1, rot=(0, 0, 0)))
    if "stars" in ex:
        for i, (x, y, z) in enumerate([(-5, 16.5, 4.5), (5, 17.2, 4.5), (0, 17.8, 5), (-8.5, 11, 3), (8.5, 12, 3)]):
            parts.append(sphere(f"Star{i}", 0.6, rb(x, DECK + y, z), "Window", subdiv=1))
    if "wings" in ex:
        for sx in (-1, 1):
            for k in range(4):
                parts.append(box(f"Wing{sx}{k}", rsize(3.4 - k * 0.5, 0.9, 0.5), rb(sx * (8.6 + k * 0.4), DECK + 12.6 - k * 1.2, 4.5), "Snow", bevel=0.15, rot=(0, sx * math.radians(25 + k * 8), 0)))


def ball(t):
    parts = []
    parts.append(sphere("BallCore", 4.5, rb(0, DECK + 5.0, 4.5), t["ball"], subdiv=3))
    # Lumps of packed snow so the spin reads.
    for k, (a, b) in enumerate([(0.3, 0.2), (1.9, -0.5), (3.6, 0.9), (4.8, -1.1), (5.9, 0.4), (2.7, 1.3), (1.1, -1.3)]):
        x = math.cos(a) * math.cos(b) * 4.25
        y = math.sin(b) * 4.25
        z = math.sin(a) * math.cos(b) * 4.25
        parts.append(sphere(f"Lump{k}", 0.85, rb(x, DECK + 5.0 + y, 4.5 + z), "SnowShade" if t["ball"] == "Snow" else "Snow", subdiv=1, scale=(1, 1, 0.8)))
    return parts


def build(name):
    t = TIERS[name]
    scene = kit.reset()
    kit.light_rig(scene)
    st = []
    station(t, st)
    s = kit.join(st, "Station")
    b = kit.join(ball(t), "Ball")
    return [s, b]


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(TIERS)
    for name in names:
        objs = build(name)
        print(name, [(o.name, sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in objs])
        if "--nobake" not in sys.argv:
            kit.bake_many(objs, f"Roller_{name}", size=1024, samples=16)
            print(kit.export_glb(objs, f"Roller_{name}"))
        print(kit.preview(f"Roller_{name}", target=(0, 2, 7), dist=40, elev=22, azim=-35, res=(640, 640), samples=16))
