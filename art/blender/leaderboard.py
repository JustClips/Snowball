"""Leaderboard stand for the summit plaza (LeaderboardService places 4 of them, Config/
Leaderboards Spots). A chunky stud-style board: log posts, a dark slate screen inside a
plank frame, a snow cap with icicles and a gold trophy on top, snow piles at the feet.

The screen is plain dark here: the game lays a SurfaceGui over it (rows, header, icon), on
an invisible part at Config/Leaderboards Screen (centre + size in model studs). Keep the
SCREEN numbers below in sync with that config.

Origin = footprint centre at ground level, front = -Z (Roblox).

  python leaderboard.py            # build, bake, export art/out/Leaderboard.glb + preview
"""
import math
import random
import sys

import kit
from kit import box, cyl, cone, sphere

# Screen rectangle on the front face (Roblox model studs): centre y and size. The front
# face of the panel is at z = 0.
SCREEN_Y = 12.6
SCREEN_W = 13.8
SCREEN_H = 17.2


def rb(x, y, z):
    return (-x, z, y)


def rsize(sx, sy, sz):
    return (sx, sz, sy)


def stand(p):
    rng = random.Random(7)
    # Stone step the whole thing stands on.
    p.append(box("Step", rsize(19, 1.0, 5), rb(0, 0.5, 0.4), "StoneDark", bevel=0.25))
    p.append(box("StepTop", rsize(18.2, 0.4, 4.4), rb(0, 1.1, 0.4), "Stone", bevel=0.15, studs=True))
    # Two thick log posts with darker rings.
    for s in (-1, 1):
        x = s * 8.3
        p.append(box(f"Post{s}", rsize(1.9, 23, 1.9), rb(x, 12.6, 0.4), "Log", bevel=0.25))
        for k, y in enumerate((4.0, 12.6, 21.0)):
            p.append(box(f"Ring{s}{k}", rsize(2.15, 0.45, 2.15), rb(x, y, 0.4), "LogDark", bevel=0.1))
        p.append(sphere(f"PostCap{s}", 1.35, rb(x, 24.3, 0.4), "Snow", subdiv=2, scale=(1.0, 1.0, 0.55)))
    # The dark screen panel, its front face at z = 0.
    p.append(box("Panel", rsize(SCREEN_W + 0.8, SCREEN_H + 0.8, 0.8), rb(0, SCREEN_Y, 0.4), "Black", bevel=0.08))
    # Plank frame around the screen.
    top = SCREEN_Y + SCREEN_H / 2
    bottom = SCREEN_Y - SCREEN_H / 2
    p.append(box("FrameTop", rsize(17.4, 1.5, 1.7), rb(0, top + 0.95, 0.3), "Plank", bevel=0.18))
    p.append(box("FrameBottom", rsize(17.4, 1.1, 1.7), rb(0, bottom - 0.75, 0.3), "Plank", bevel=0.15))
    for s in (-1, 1):
        p.append(box(f"FrameSide{s}", rsize(0.7, SCREEN_H + 1.0, 1.5), rb(s * (SCREEN_W / 2 + 0.55), SCREEN_Y, 0.25), "Plank", bevel=0.12))
    # Snow cap on the top beam, a little lumpy, overhanging the front.
    p.append(box("Cap", rsize(18.2, 0.7, 2.4), rb(0, top + 2.0, 0.2), "Snow", bevel=0.3))
    for k in range(7):
        x = -7.5 + k * 2.5 + rng.uniform(-0.4, 0.4)
        p.append(sphere(f"Lump{k}", rng.uniform(0.9, 1.3), rb(x, top + 2.35, 0.1), "Snow", subdiv=2, scale=(1.3, 1.0, 0.5)))
    # Icicles hanging off the front edge of the top beam.
    for k in range(9):
        x = -7.0 + k * 1.75 + rng.uniform(-0.25, 0.25)
        h = rng.uniform(0.7, 1.2)
        p.append(cone(f"Icicle{k}", 0.26, 0.0, h, rb(x, top + 1.7 - h / 2, -0.75), "Ice", verts=6,
                      rot=(math.radians(180), 0, 0)))
    # Gold trophy on top, on a small stone block (big enough to read from across the plaza).
    ty = top + 2.6
    k = 1.7
    p.append(box("TrophyBase", rsize(3.6, 0.8, 2.4), rb(0, ty + 0.4, 0.3), "StoneDark", bevel=0.15))
    p.append(box("TrophyFoot", rsize(1.8 * k, 0.45 * k, 1.4 * k), rb(0, ty + 0.8 + 0.22 * k, 0.3), "Gold", bevel=0.12))
    p.append(cyl("TrophyStem", 0.32 * k, 1.0 * k, rb(0, ty + 0.8 + 0.95 * k, 0.3), "Gold", verts=10, bevel=0.0))
    p.append(cone("TrophyCup", 0.75 * k, 1.45 * k, 1.9 * k, rb(0, ty + 0.8 + 2.4 * k, 0.3), "Gold", verts=16))
    p.append(cyl("TrophyRim", 1.5 * k, 0.25 * k, rb(0, ty + 0.8 + 3.35 * k, 0.3), "Gold", verts=16, bevel=0.05))
    for s in (-1, 1):
        p.append(box(f"Handle{s}", rsize(0.35 * k, 1.1 * k, 0.35 * k), rb(s * 1.6 * k, ty + 0.8 + 2.45 * k, 0.3), "Gold", bevel=0.05))
        p.append(box(f"HandleTop{s}", rsize(0.7 * k, 0.3 * k, 0.35 * k), rb(s * 1.35 * k, ty + 0.8 + 2.95 * k, 0.3), "Gold", bevel=0.05))
    p.append(sphere("TrophyStar", 0.5 * k, rb(0, ty + 0.8 + 3.85 * k, 0.3), "Window", subdiv=1))
    # Snow piles at the feet and against the posts.
    for s in (-1, 1):
        p.append(sphere(f"Pile{s}", 2.0, rb(s * 8.6, 1.2, -0.6), "Snow", subdiv=2, scale=(1.4, 1.2, 0.5)))
    p.append(sphere("PileMid", 1.6, rb(3.5, 1.2, -1.6), "SnowShade", subdiv=2, scale=(1.5, 1.0, 0.35)))
    # Two small lanterns on the posts so the board reads at dusk.
    for s in (-1, 1):
        p.append(box(f"Lantern{s}", rsize(0.9, 1.2, 0.9), rb(s * 8.3, 17.0, -1.25), "Window", bevel=0.12))
        p.append(box(f"LanternHat{s}", rsize(1.2, 0.3, 1.2), rb(s * 8.3, 17.75, -1.25), "Black", bevel=0.06))


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    parts = []
    stand(parts)
    return [kit.join(parts, "Leaderboard")]


if __name__ == "__main__":
    objs = build()
    print("tris", sum(len(p.vertices) - 2 for p in objs[0].data.polygons))
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "Leaderboard", size=1024, samples=24)
        print(kit.export_glb(objs, "Leaderboard"))
    print(kit.preview("Leaderboard", target=(0, 0, 13), dist=48, elev=12, azim=-28, res=(640, 720), samples=24))
