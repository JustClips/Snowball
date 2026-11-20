"""The yeti that chases you while you carry an egg home (Dev 2026-11-20; v2 after Dev's
"tf is that yeti model, no animations whatsoever?"). A shaggy, long-armed snow ape cut into
12 separate objects so the game can pose a real skeleton (RescueController + YetiAnim):

  Hips (root) > Torso > Head > Jaw
               Torso > UpperArmL > LowerArmL,  Torso > UpperArmR > LowerArmR
  Hips > ThighL > ShinL,  Hips > ThighR > ShinR

About 11 studs tall, origin = between the feet on the ground, front = Roblox -Z. All
coordinates below are Roblox model-local (x right, y up, -z front); rb() maps them to
Blender. The joint points (JOINTS) are copied into src/shared/YetiAnim.luau.

  python yeti.py            # build, bake, export art/out/Yeti.glb + preview
  python yeti.py --nobake   # preview only
"""
import math
import sys

import bpy
from mathutils import Vector

import kit
from kit import box, cone, sphere

kit.PALETTE.update({
    "Fur": (238, 244, 252), "FurShade": (196, 212, 236), "FurDeep": (160, 182, 218),
    "YetiSkin": (104, 136, 196), "YetiSkinDark": (70, 96, 150), "YetiMouth": (52, 28, 60),
    "Tongue": (230, 90, 120), "Tooth": (255, 252, 240), "Claw": (230, 236, 250),
    "EyeBlue": (90, 225, 255), "Horn": (214, 226, 246),
})
kit.GLOW.update({"EyeBlue"})

# Joint pivots (Roblox model-local). Keep in sync with src/shared/YetiAnim.luau.
JOINTS = {
    "Torso": (0, 4.4, 0.1),
    "Head": (0, 8.0, -0.2),
    "Jaw": (0, 8.7, -0.9),
    "UpperArmL": (-3.0, 7.3, 0.2), "LowerArmL": (-3.5, 5.0, 0.0),
    "UpperArmR": (3.0, 7.3, 0.2), "LowerArmR": (3.5, 5.0, 0.0),
    "ThighL": (-1.35, 3.6, 0.1), "ShinL": (-1.45, 1.9, -0.1),
    "ThighR": (1.35, 3.6, 0.1), "ShinR": (1.45, 1.9, -0.1),
}


def rb(x, y, z):
    return (-x, z, y)


def aim(o, direction):
    """Points the object's local +Z (Blender) along direction (Roblox coords)."""
    d = Vector(rb(*direction))
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = d.normalized().to_track_quat("Z", "Y")


def capsule(p, name, a, b, r, color, squash=1.0):
    """A stretched ball from Roblox point a to b."""
    a, b = Vector(a), Vector(b)
    mid = (a + b) / 2
    length = (b - a).length
    o = sphere(name, 1.0, rb(*mid), color, subdiv=2, scale=(r, r * squash, length / 2 + r * 0.55))
    aim(o, tuple(b - a))
    p.append(o)
    return o


def spike(p, name, base, direction, r, length, color, verts=6):
    """A cone standing on base, pointing along direction (Roblox coords)."""
    d = Vector(direction).normalized()
    centre = Vector(base) + d * (length / 2)
    o = cone(name, r, 0.0, length, rb(*centre), color, verts=verts)
    aim(o, tuple(d))
    p.append(o)
    return o


def shag(p, name, centre, radii, n, color, r=0.42, length=0.9, droop=0.6, keep=None, seed=1):
    """Fur clumps over an ellipsoid: n cones on its surface pointing out and drooping down.
    keep(direction) -> bool limits them to part of the surface."""
    cx, cy, cz = centre
    k = 0
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(n * 3):
        if k >= n:
            break
        y = 1 - (i + 0.5) / (n * 3) * 2
        rad = math.sqrt(max(0, 1 - y * y))
        th = golden * (i + seed * 7)
        d = Vector((math.cos(th) * rad, y, math.sin(th) * rad))
        if keep and not keep(d):
            continue
        base = Vector((cx + d.x * radii[0] * 0.92, cy + d.y * radii[1] * 0.92, cz + d.z * radii[2] * 0.92))
        out = (d + Vector((0, -droop, 0))).normalized()
        jitter = 0.8 + 0.4 * ((i * 37) % 11) / 10
        spike(p, f"{name}{k}", tuple(base), tuple(out), r * jitter, length * jitter, color)
        k += 1


# ------------------------------------------------------------------- parts
def hips(p):
    p.append(sphere("Pelvis", 1.0, rb(0, 3.9, 0.15), "Fur", subdiv=3, scale=(2.2, 1.9, 1.6)))
    # Shaggy skirt of fur round the waist (hides the hip joints when the legs swing).
    shag(p, "Skirt", (0, 3.6, 0.15), (2.2, 1.0, 1.9), 16, "Fur", r=0.6, length=1.3, droop=2.2,
         keep=lambda d: d.y < 0.35)


def torso(p):
    p.append(sphere("Chest", 1.0, rb(0, 6.5, 0.35), "Fur", subdiv=3, scale=(3.2, 2.5, 2.3)))
    p.append(sphere("Belly", 1.0, rb(0, 5.2, 0.0), "Fur", subdiv=3, scale=(2.4, 1.6, 2.0)))
    p.append(sphere("Hump", 1.0, rb(0, 7.3, 1.2), "Fur", subdiv=2, scale=(2.6, 1.4, 1.5)))
    for s in (-1, 1):
        p.append(sphere(f"Shoulder{s}", 1.0, rb(s * 2.55, 7.45, 0.3), "Fur", subdiv=2, scale=(1.35, 1.15, 1.3)))
    shag(p, "Back", (0, 6.6, 0.6), (3.0, 2.3, 2.1), 30, "Fur", r=0.5, length=1.1, droop=0.7,
         keep=lambda d: d.z > -0.25 and d.y > -0.6)
    shag(p, "Collar", (0, 7.9, 0.0), (2.0, 0.6, 1.6), 14, "FurShade", r=0.45, length=1.0, droop=0.9,
         keep=lambda d: d.y > -0.2)
    shag(p, "Flank", (0, 5.4, 0.1), (2.5, 1.5, 2.0), 16, "FurShade", r=0.45, length=1.0, droop=1.0,
         keep=lambda d: abs(d.x) > 0.55)


def head(p):
    p.append(sphere("Skull", 1.0, rb(0, 9.35, -0.45), "Fur", subdiv=3, scale=(1.85, 1.75, 1.75)))
    p.append(sphere("Face", 1.0, rb(0, 9.2, -1.75), "YetiSkin", subdiv=3, scale=(1.4, 0.95, 0.6)))
    p.append(sphere("Muzzle", 1.0, rb(0, 8.75, -2.05), "YetiSkin", subdiv=2, scale=(0.95, 0.5, 0.45)))
    p.append(sphere("Nose", 1.0, rb(0, 9.05, -2.42), "YetiSkinDark", subdiv=2, scale=(0.36, 0.22, 0.2)))
    for s in (-1, 1):
        p.append(sphere(f"Socket{s}", 1.0, rb(s * 0.55, 9.55, -2.12), "YetiSkinDark", subdiv=2, scale=(0.5, 0.42, 0.18)))
        p.append(sphere(f"Eye{s}", 1.0, rb(s * 0.56, 9.52, -2.26), "EyeBlue", subdiv=2, scale=(0.36, 0.3, 0.2)))
        # Angry brow ridges: shaggy fur slanting down to the middle.
        p.append(box(f"Brow{s}", (0.95, 0.3, 0.4), rb(s * 0.62, 10.02, -2.1), "FurShade", bevel=0.12,
                     rot=(0, math.radians(-24 * s), 0)))
        # Curved horns: three tapering spikes bending outwards and up.
        base = Vector((s * 1.35, 10.4, -0.2))
        dirs = [(s * 0.8, 0.6, 0.1), (s * 0.35, 1.0, 0.25), (s * -0.1, 1.0, 0.35)]
        r = 0.55
        for i, d in enumerate(dirs):
            seg = 0.8
            spike(p, f"Horn{s}{i}", tuple(base), d, r, seg + 0.25, "Horn", verts=8)
            base = base + Vector(d).normalized() * seg
            r *= 0.68
        # Upper fangs.
        spike(p, f"Fang{s}", (s * 0.45, 8.6, -2.3), (0, -1, -0.15), 0.17, 0.62, "Tooth")
        # Furry cheeks.
        p.append(sphere(f"Cheek{s}", 1.0, rb(s * 1.45, 8.9, -1.25), "Fur", subdiv=2, scale=(0.75, 0.8, 0.7)))
    shag(p, "Mane", (0, 9.6, -0.2), (1.85, 1.7, 1.7), 20, "Fur", r=0.42, length=0.95, droop=0.4,
         keep=lambda d: d.z > -0.45 and d.y > -0.4)


def jaw(p):
    p.append(sphere("Chin", 1.0, rb(0, 8.25, -1.7), "YetiSkin", subdiv=2, scale=(1.15, 0.45, 0.85)))
    p.append(sphere("MouthIn", 1.0, rb(0, 8.5, -1.85), "YetiMouth", subdiv=2, scale=(0.95, 0.22, 0.7)))
    p.append(sphere("Tongue", 1.0, rb(0, 8.55, -1.95), "Tongue", subdiv=2, scale=(0.55, 0.14, 0.45)))
    for s in (-1, 1):
        spike(p, f"Tusk{s}", (s * 0.7, 8.45, -2.15), (s * 0.15, 1, -0.1), 0.15, 0.55, "Tooth")
    shag(p, "Beard", (0, 8.05, -1.5), (1.1, 0.5, 0.8), 10, "Fur", r=0.35, length=0.85, droop=1.6,
         keep=lambda d: d.y < 0.1)


def upper_arm(p, s):
    a, b = (s * 3.05, 7.3, 0.2), (s * 3.5, 5.0, 0.0)
    p.append(sphere(f"Ball{s}", 1.0, rb(*a), "Fur", subdiv=2, scale=(1.15, 1.15, 1.15)))
    capsule(p, f"Bicep{s}", a, b, 1.05, "Fur")
    shag(p, f"ArmFur{s}", (s * 3.3, 6.1, 0.1), (1.05, 1.3, 1.05), 12, "FurShade", r=0.38, length=0.85, droop=1.1,
         keep=lambda d: d.x * s > -0.2)


def lower_arm(p, s):
    a, b = (s * 3.5, 5.0, 0.0), (s * 3.7, 2.9, -0.2)
    p.append(sphere(f"Elbow{s}", 1.0, rb(*a), "Fur", subdiv=2, scale=(1.0, 1.0, 1.0)))
    capsule(p, f"Forearm{s}", a, b, 1.0, "Fur")
    # Big blue hands with three claws, knuckles forward.
    p.append(sphere(f"Hand{s}", 1.0, rb(s * 3.75, 2.25, -0.35), "YetiSkin", subdiv=2, scale=(0.95, 0.85, 1.1)))
    for i, dx in enumerate((-0.4, 0.0, 0.4)):
        spike(p, f"Claw{s}{i}", (s * 3.75 + dx, 1.75, -1.15), (0, -0.5, -1), 0.16, 0.6, "Claw")
    p.append(sphere(f"Thumb{s}", 1.0, rb(s * 3.25, 2.4, -0.9), "YetiSkin", subdiv=2, scale=(0.35, 0.35, 0.45)))
    shag(p, f"Cuff{s}", (s * 3.65, 3.2, -0.15), (1.0, 0.5, 1.0), 10, "Fur", r=0.36, length=0.75, droop=1.2)


def thigh(p, s):
    a, b = (s * 1.35, 3.7, 0.1), (s * 1.45, 1.9, -0.1)
    capsule(p, f"Thigh{s}", a, b, 1.15, "Fur")


def shin(p, s):
    a, b = (s * 1.45, 1.9, -0.1), (s * 1.45, 0.75, 0.1)
    p.append(sphere(f"Knee{s}", 1.0, rb(*a), "Fur", subdiv=2, scale=(1.0, 1.0, 1.0)))
    capsule(p, f"Calf{s}", a, b, 0.9, "Fur")
    p.append(sphere(f"Foot{s}", 1.0, rb(s * 1.45, 0.42, -0.4), "YetiSkin", subdiv=2, scale=(1.05, 0.45, 1.45)))
    for i, dx in enumerate((-0.45, 0.0, 0.45)):
        spike(p, f"Toe{s}{i}", (s * 1.45 + dx, 0.35, -1.75), (0, -0.15, -1), 0.17, 0.5, "Claw")
    shag(p, f"Ankle{s}", (s * 1.45, 1.0, 0.0), (0.95, 0.4, 0.95), 9, "Fur", r=0.36, length=0.7, droop=1.4)


PARTS = [
    ("Hips", hips), ("Torso", torso), ("Head", head), ("Jaw", jaw),
    ("UpperArmL", lambda p: upper_arm(p, -1)), ("LowerArmL", lambda p: lower_arm(p, -1)),
    ("UpperArmR", lambda p: upper_arm(p, 1)), ("LowerArmR", lambda p: lower_arm(p, 1)),
    ("ThighL", lambda p: thigh(p, -1)), ("ShinL", lambda p: shin(p, -1)),
    ("ThighR", lambda p: thigh(p, 1)), ("ShinR", lambda p: shin(p, 1)),
]


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    objs = []
    for name, fn in PARTS:
        parts = []
        fn(parts)
        objs.append(kit.join(parts, name))
    return objs


if __name__ == "__main__":
    objs = build()
    tris = sum(len(o.data.polygons) for o in objs)
    print("faces", tris)
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "Yeti", size=1024, samples=16, isolate=True)
        print(kit.export_glb(objs, "Yeti"))
    print(kit.preview("Yeti", target=(0, 0, 5.5), dist=17, elev=8, azim=-25, res=(600, 600), samples=12))
