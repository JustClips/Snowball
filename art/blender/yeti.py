"""The yeti that chases you while you carry an egg home (Dev 2026-11-20). Six separate
objects so the game can swing the limbs: Body, Head, ArmL, ArmR, LegL, LegR. About 9 studs
tall, origin = between the feet on the ground, front = Roblox -Z. Joint points (Roblox
model-local) used by RescueController: shoulders (+-2.7, 6.6, 0), hips (+-1.2, 3.2, 0),
neck (0, 7.4, 0).

  python yeti.py
"""
import math
import sys

import kit
from kit import box, cyl, cone, sphere

kit.PALETTE.update({
    "Fur": (236, 242, 252), "FurShade": (200, 214, 235), "YetiSkin": (120, 150, 200),
    "YetiMouth": (60, 40, 70), "Tooth": (255, 255, 255), "EyeBlue": (90, 220, 255),
})
kit.GLOW.update({"EyeBlue"})


def rb(x, y, z):
    return (-x, z, y)


def body(p):
    p.append(sphere("Belly", 2.6, rb(0, 5.0, 0), "Fur", subdiv=3, scale=(1.05, 0.9, 1.15)))
    p.append(sphere("Chest", 2.4, rb(0, 6.4, 0.2), "Fur", subdiv=3, scale=(1.2, 0.95, 0.85)))
    p.append(sphere("Tummy", 1.6, rb(0, 4.9, -1.7), "FurShade", subdiv=2, scale=(1.0, 0.45, 1.1)))
    for k in range(6):
        a = k / 6 * math.tau
        p.append(cone(f"Tuft{k}", 0.5, 0.0, 1.0, rb(math.cos(a) * 2.2, 3.5, math.sin(a) * 2.2), "Fur", verts=6,
                      rot=(math.radians(180), 0, 0)))


def head(p):
    p.append(sphere("Skull", 1.75, rb(0, 8.6, 0), "Fur", subdiv=3, scale=(1.05, 1.0, 1.0)))
    p.append(sphere("Face", 1.2, rb(0, 8.4, -1.15), "YetiSkin", subdiv=3, scale=(1.15, 0.6, 1.0)))
    for s in (-1, 1):
        p.append(sphere(f"Eye{s}", 0.28, rb(s * 0.5, 8.85, -1.75), "EyeBlue", subdiv=2))
        p.append(box(f"Brow{s}", (0.8, 0.25, 0.25), rb(s * 0.5, 9.3, -1.7), "FurShade", bevel=0.08,
                     rot=(0, math.radians(28 * s), 0)))
        p.append(cone(f"Horn{s}", 0.35, 0.0, 1.4, rb(s * 1.3, 10.1, 0), "Tooth", verts=8, rot=(0, math.radians(25 * s), 0)))
    p.append(box("Mouth", (1.5, 0.6, 0.4), rb(0, 7.95, -1.72), "YetiMouth", bevel=0.12))
    for i, x in enumerate((-0.5, -0.17, 0.17, 0.5)):
        p.append(cone(f"Fang{i}", 0.16, 0.0, 0.45, rb(x, 8.2, -1.86), "Tooth", verts=6, rot=(math.radians(180), 0, 0)))


def arm(p, s):
    # Hangs from the shoulder (s * 2.7, 6.6) down to a big fist at y ~ 2.4.
    x = s * 2.9
    p.append(sphere(f"Upper{s}", 1.0, rb(x, 5.6, 0), "Fur", subdiv=2, scale=(0.9, 0.9, 1.5)))
    p.append(sphere(f"Fore{s}", 0.95, rb(x + s * 0.15, 3.8, 0), "Fur", subdiv=2, scale=(0.9, 0.9, 1.4)))
    p.append(sphere(f"Fist{s}", 0.85, rb(x + s * 0.2, 2.4, -0.2), "YetiSkin", subdiv=2))


def leg(p, s):
    x = s * 1.2
    p.append(sphere(f"Thigh{s}", 1.05, rb(x, 2.3, 0), "Fur", subdiv=2, scale=(1.0, 1.0, 1.3)))
    p.append(sphere(f"Foot{s}", 0.9, rb(x, 0.5, -0.5), "YetiSkin", subdiv=2, scale=(1.0, 1.5, 0.55)))


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    objs = []
    for name, fn in (("Body", body), ("Head", head), ("ArmL", lambda p: arm(p, -1)), ("ArmR", lambda p: arm(p, 1)),
                     ("LegL", lambda p: leg(p, -1)), ("LegR", lambda p: leg(p, 1))):
        parts = []
        fn(parts)
        objs.append(kit.join(parts, name))
    return objs


if __name__ == "__main__":
    objs = build()
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "Yeti", size=1024, samples=16)
        print(kit.export_glb(objs, "Yeti"))
    print(kit.preview("Yeti", target=(0, 0, 5), dist=24, elev=12, azim=-30, res=(400, 400), samples=12))
