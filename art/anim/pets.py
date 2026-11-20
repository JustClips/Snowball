"""Bone animations for the StudAnimalPack pets: Idle, Walk and Happy for every animal.

  python3 art/anim/pets.py                 # every pet in src/shared/Config/Pets.luau
  python3 art/anim/pets.py Fox Duck        # just these pack models
  python3 art/anim/pets.py --all           # all 100 pack animals

Writes art/out/anims/Pet_<Model>_<Clip>.rbxmx (KeyframeSequences). Upload them with
tools/upload_anims.py, which also writes the ids into src/shared/Config/Anims.luau.

How it works
- art/anim/pet_rigs.json holds each pack model's bones (name, parent, rest CFrame relative to
  the parent, exactly as in the .rbxm) and the MeshPart size. art/anim/extract_rigs.luau
  rebuilds it from the pack file.
- A clip is written as motion in MODEL space (pitch about X = nose/leg forward and up,
  yaw about Y, roll about Z; offsets in studs), then converted into each bone's own frame,
  because Roblox plays Bone.Transform in bone space and every animal's bones point
  differently. That's why each animal gets its own clips (no shared "Quad" clip).
- Gaits are picked from the bone names, with a few per-animal styles (hoppers, fish).
- Model space: the pack faces -Z, so +pitch on a leg swings the foot forward.

art/blender/pet_preview.py loads the real pack meshes into Blender and plays these same
clips to render preview sheets.
"""
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "art", "out", "anims")
RIGS = os.path.join(HERE, "pet_rigs.json")

sys.path.insert(0, HERE)
from push import cframe_xml, Ref  # noqa: E402

# ---------------------------------------------------------------- tiny 3x3 math
def mm(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mv(a, v):
    return [sum(a[i][k] * v[k] for k in range(3)) for i in range(3)]


def tr(a):
    return [[a[j][i] for j in range(3)] for i in range(3)]


def rx(a):
    c, s = math.cos(a), math.sin(a)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def ry(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def rz(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


I3 = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
D = math.pi / 180
TAU = 2 * math.pi


def euler(p=0.0, y=0.0, r=0.0):
    """Model-space rotation from degrees: yaw (Y) * pitch (X) * roll (Z)."""
    return mm(mm(ry(y * D), rx(p * D)), rz(r * D))


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def keys(phase, pts):
    """Smoothly interpolated value over a looping [0,1) phase. pts = [(phase, value), ...]."""
    phase %= 1.0
    pts = sorted(pts)
    if pts[0][0] > 0:
        pts = [(pts[-1][0] - 1, pts[-1][1])] + pts
    if pts[-1][0] < 1:
        pts = pts + [(pts[0][0] + 1, pts[0][1])]
    for (a, va), (b, vb) in zip(pts, pts[1:]):
        if a <= phase <= b:
            return va + (vb - va) * smooth((phase - a) / max(b - a, 1e-6))
    return pts[0][1]


def s(x):
    return math.sin(TAU * x)


def c(x):
    return math.cos(TAU * x)


# ---------------------------------------------------------------- rigs
class Rig:
    def __init__(self, name, data):
        self.name = name
        self.part = data["part"]
        self.size = data["size"]
        self.h = data["size"][1]
        self.bones = {}
        self.order = []
        for b in data["bones"]:
            cf = b["cf"]
            pos = cf[0:3]
            rot = [cf[3:6], cf[6:9], cf[9:12]]
            self.bones[b["name"]] = {"parent": b["parent"], "pos": pos, "rot": rot}
            self.order.append(b["name"])
        # Rest frames in part space.
        for n in self.order:
            b = self.bones[n]
            p = self.bones.get(b["parent"])
            if p:
                b["wrot"] = mm(p["wrot"], b["rot"])
                b["wpos"] = [p["wpos"][i] + mv(p["wrot"], b["pos"])[i] for i in range(3)]
            else:
                b["wrot"] = b["rot"]
                b["wpos"] = list(b["pos"])
        self.children = {}
        for n in self.order:
            self.children.setdefault(self.bones[n]["parent"], []).append(n)
        names = set(self.order)
        self.has = lambda *ns: all(x in names for x in ns)
        self.style = style_of(name, names)

    def side(self, bone):
        """+1 / -1: which side of the body the bone is on (model X)."""
        x = self.bones[bone]["wpos"][0]
        if abs(x) < 1e-3:
            return 1 if bone.endswith(".L") else -1
        return 1 if x > 0 else -1

    def local(self, bone, rot, off):
        """Model-space rotation about the bone's pivot + model-space offset -> Bone.Transform."""
        w = self.bones[bone]["wrot"]
        wt = tr(w)
        return mv(wt, off), mm(mm(wt, rot), w)


HOPPERS = {"Rabbit", "Frog", "Kangaroo", "GuineaPig"}
FISH = {"Goldfish", "Clownfish", "Shark", "Pufferfish", "Stingray", "Seahorse"}


def style_of(name, names):
    if name in HOPPERS:
        return "hop"
    if name in FISH:
        return "fish"
    if "fin.L" in names:
        return "sea"
    if "flipper.L" in names:
        return "penguin"
    if "leg_front.L" in names:
        return "quad"
    if "leg1.L" in names:
        return "crawler"
    if "arm1" in names or "arm1.L" in names:
        return "tentacle"
    if "wing.L" in names and ("leg.L" in names or "foot.L" in names):
        return "bird"
    if "wing.L" in names:
        return "flyer"
    if "leg.L" in names:
        return "biped"
    return "worm"


# ---------------------------------------------------------------- the motion
class Pose:
    """Collects model-space motion per bone for one moment."""

    def __init__(self):
        self.rot = {}
        self.off = {}

    def turn(self, bone, p=0.0, y=0.0, r=0.0):
        cur = self.rot.get(bone, I3)
        self.rot[bone] = mm(euler(p, y, r), cur)

    def move(self, bone, x=0.0, y=0.0, z=0.0):
        cur = self.off.get(bone, [0, 0, 0])
        self.off[bone] = [cur[0] + x, cur[1] + y, cur[2] + z]


def chain(rig, start):
    """Bones from start down its single child line (tail -> tail2 -> tail3)."""
    out = []
    n = start
    while n in rig.bones:
        out.append(n)
        kids = rig.children.get(n, [])
        n = kids[0] if len(kids) == 1 else None
    return out


def legs_quad(rig, P, ph, amp, lift):
    for side in (".L", ".R"):
        for end, off in (("front", 0.0), ("back", 0.5)):
            leg = f"leg_{end}{side}"
            foot = f"foot_{end}{side}"
            if leg not in rig.bones:
                continue
            o = off + (0.0 if side == ".L" else 0.5)  # diagonal pairs: front.L with back.R
            a = amp * s(ph + o)
            up = max(0.0, c(ph + o))
            P.turn(leg, p=a)
            P.move(leg, y=lift * up)
            if foot in rig.bones:
                P.turn(foot, p=-a - 25 * up)


def legs_pair(rig, P, ph, amp, lift, names=("leg", "foot")):
    upper, lower = names
    for side, o in ((".L", 0.0), (".R", 0.5)):
        a = amp * s(ph + o)
        up = max(0.0, c(ph + o))
        if upper + side in rig.bones:
            P.turn(upper + side, p=a)
            P.move(upper + side, y=lift * up)
            if lower + side in rig.bones:
                P.turn(lower + side, p=-a - 20 * up)
        elif lower + side in rig.bones:
            P.turn(lower + side, p=a)
            P.move(lower + side, y=lift * up)


def tail_wag(rig, P, ph, yaw, pitch=0.0, axis="yaw", lag=0.12):
    for i, b in enumerate(chain(rig, "tail")):
        k = 1 + 0.4 * i
        if axis == "yaw":
            P.turn(b, y=yaw * k * s(ph - lag * i), p=pitch)
        else:
            P.turn(b, p=yaw * k * s(ph - lag * i))


def wings(rig, P, flap, fold=0.0):
    for side in (".L", ".R"):
        for w, k in (("wing", 1.0), ("wing_tip", 0.6), ("flipper", 1.0)):
            b = w + side
            if b in rig.bones:
                sg = rig.side(b)
                P.turn(b, r=sg * (flap * k + fold))


def head_look(rig, P, yaw, pitch, roll=0.0):
    if "neck" in rig.bones:
        P.turn("neck", y=yaw * 0.4, p=pitch * 0.4)
        P.turn("head", y=yaw * 0.6, p=pitch * 0.6, r=roll)
    elif "head" in rig.bones:
        P.turn("head", y=yaw, p=pitch, r=roll)
    if "trunk" in rig.bones:
        P.turn("trunk", p=-pitch * 0.5)


def misc_idle(rig, P, ph):
    # Trunk swing, jaw, wings at rest, worm segments.
    if "trunk" in rig.bones:
        P.turn("trunk", p=6 * s(ph * 2), y=8 * s(ph))
        if "trunk2" in rig.bones:
            P.turn("trunk2", p=10 * s(ph * 2 - 0.15))


# Clip lengths (seconds) and sample rates.
LEN = {"Idle": 4.0, "Walk": 0.8, "Happy": 0.9}
FPS = {"Idle": 8, "Walk": 20, "Happy": 20}
# Walk cycle is authored for about 10 studs/s at the in-game pet height; the game sets
# AdjustSpeed(speed / 10).
WALK_SPEED = 10


def idle(rig, ph):
    P = Pose()
    h = rig.h
    st = rig.style
    breath = s(ph * 2)
    look_y = keys(ph, [(0.0, 0), (0.12, 0), (0.22, 22), (0.42, 22), (0.52, 0), (0.62, -16), (0.8, -16), (0.9, 0)])
    look_p = keys(ph, [(0.0, 0), (0.45, 0), (0.5, -10), (0.56, -10), (0.6, 0)])
    if st in ("quad", "hop", "biped", "crawler"):
        P.move("body", y=0.006 * h * breath)
        P.turn("body", p=0.8 * breath)
        head_look(rig, P, look_y, look_p + 2 * breath)
        tail_wag(rig, P, ph * 3, 10)
        misc_idle(rig, P, ph)
        if "wing.L" in rig.bones:  # dragon: wings breathe and stretch once
            stretch = keys(ph, [(0.0, 0), (0.68, 0), (0.75, 30), (0.82, 30), (0.9, 0)])
            wings(rig, P, 4 * breath + stretch)
        if "jaw" in rig.bones:
            P.turn("jaw", p=-keys(ph, [(0.0, 0), (0.7, 0), (0.75, 18), (0.82, 18), (0.88, 0)]))
        for i in (1, 2, 3, 4):
            for side in (".L", ".R"):
                if f"leg{i}{side}" in rig.bones:
                    P.turn(f"leg{i}{side}", y=3 * s(ph * 2 + i * 0.2))
        for side in (".L", ".R"):
            if "arm" + side in rig.bones:
                P.turn("arm" + side, p=6 * breath)
    elif st in ("bird", "penguin"):
        P.move("body", y=0.006 * h * breath)
        tilt = keys(ph, [(0.0, 0), (0.25, 0), (0.3, 18), (0.4, 18), (0.45, 0)])
        head_look(rig, P, look_y, look_p * 1.4, roll=tilt)
        ruffle = keys(ph, [(0.0, 0), (0.78, 0), (0.82, 14), (0.86, 0), (0.9, 10), (0.94, 0)])
        wings(rig, P, ruffle + 2 * breath)
        tail_wag(rig, P, ph * 2, 8)
        P.turn("body", r=1.5 * s(ph))
    elif st in ("sea", "fish"):
        P.move("body", y=0.008 * h * breath)
        P.turn("body", p=1.2 * breath)
        head_look(rig, P, look_y * 0.7, 4 * s(ph * 2 + 0.1))
        tail_wag(rig, P, ph * 2, 10, axis="yaw" if st == "fish" else "pitch")
        for side in (".L", ".R"):
            if "fin" + side in rig.bones:
                P.turn("fin" + side, p=8 * s(ph * 2 + 0.25), r=rig.side("fin" + side) * 5 * breath)
        if "fin" in rig.bones:
            P.turn("fin", y=20 * s(ph * 8))
    elif st == "flyer":
        P.move("root", y=0.08 * h * s(ph * 2))
        wings(rig, P, 40 * s(ph * 16), 10)
        head_look(rig, P, look_y * 0.5, 0)
        tail_wag(rig, P, ph * 2, 6, axis="pitch")
    elif st == "tentacle":
        P.move("body", y=0.02 * h * breath)
        arms = [b for b in rig.order if re.match(r"arm\d", b) and "_tip" not in b]
        for i, a in enumerate(arms):
            P.turn(a, p=8 * s(ph * 2 + i / max(len(arms), 1)))
            tip = a.replace(".", "_tip.") if "." in a else a + "_tip"
            if tip in rig.bones:
                P.turn(tip, p=12 * s(ph * 2 + i / max(len(arms), 1) - 0.1))
    else:  # worm: snake, caterpillar, snail
        segs = [b for b in rig.order if b in ("neck", "seg2", "seg3", "seg4", "seg5", "tail", "shell")]
        for i, b in enumerate(segs):
            P.turn(b, y=6 * s(ph * 2 - i * 0.12))
        head_look(rig, P, look_y * 0.6, 4 * breath)
    return P


def walk(rig, ph):
    P = Pose()
    h = rig.h
    st = rig.style
    if st == "quad":
        legs_quad(rig, P, ph, 26, 0.06 * h)
        P.move("body", y=0.02 * h * (1 - c(ph * 2)) / 2)
        P.turn("body", p=1.5 * s(ph * 2), r=2.5 * s(ph))
        head_look(rig, P, 3 * s(ph), -3 * s(ph * 2 + 0.1))
        tail_wag(rig, P, ph, 16)
        if "trunk" in rig.bones:
            P.turn("trunk", p=8 * s(ph * 2 - 0.1), y=6 * s(ph))
            if "trunk2" in rig.bones:
                P.turn("trunk2", p=10 * s(ph * 2 - 0.25))
        if "wing.L" in rig.bones:
            wings(rig, P, 6 * s(ph * 2))
    elif st == "hop":
        # Bounding hop: lift off at 0, land at 0.55, squash, push off.
        air = math.sin(math.pi * min(ph / 0.55, 1.0)) if ph < 0.55 else 0.0
        land = math.sin(math.pi * (ph - 0.55) / 0.45) if ph >= 0.55 else 0.0
        P.move("root", y=0.16 * h * air - 0.03 * h * land)
        P.turn("body", p=10 * (air if ph < 0.25 else air * 0.2) - 6 * land)
        for side in (".L", ".R"):
            if f"leg_front{side}" in rig.bones:
                P.turn(f"leg_front{side}", p=30 * air - 10 * land)
                P.turn(f"foot_front{side}", p=-20 * air)
            if f"leg_back{side}" in rig.bones:
                P.turn(f"leg_back{side}", p=-35 * air + 15 * land)
                P.turn(f"foot_back{side}", p=-25 * air)
            if "arm" + side in rig.bones:
                P.turn("arm" + side, p=20 * air)
        head_look(rig, P, 0, -8 * air + 6 * land)
        tail_wag(rig, P, ph, 0, pitch=0)
        for b in chain(rig, "tail"):
            P.turn(b, p=-15 * air + 10 * land)
    elif st in ("bird", "penguin", "biped"):
        waddle = 10 if st == "penguin" else 6
        legs_pair(rig, P, ph, 30 if st != "penguin" else 18, 0.05 * h)
        P.turn("body", r=waddle * s(ph), y=4 * s(ph))
        P.move("body", y=0.02 * h * (1 - c(ph * 2)) / 2)
        if "neck" in rig.bones:  # pigeon-style head bob
            P.turn("neck", p=-8 * s(ph * 2))
            P.turn("head", p=8 * s(ph * 2))
        else:
            head_look(rig, P, 0, 4 * s(ph * 2 + 0.2), roll=-waddle * 0.6 * s(ph))
        wings(rig, P, 8 * s(ph * 2) + (12 if st == "penguin" else 4))
        for side in (".L", ".R"):
            if "arm" + side in rig.bones:
                P.turn("arm" + side, p=-25 * s(ph + (0 if side == ".L" else 0.5)))
        tail_wag(rig, P, ph, 14)
        if "jaw" in rig.bones:
            P.turn("jaw", p=-4 * s(ph * 2))
    elif st in ("sea", "fish"):
        # Seal flop: body rocks, chest pushes off, tail lifts, fins paddle together.
        push = max(0.0, s(ph))
        P.move("body", y=0.06 * h * push)
        P.turn("body", p=7 * s(ph))
        head_look(rig, P, 0, -9 * s(ph - 0.1))
        tail_wag(rig, P, ph + 0.25, 16 if st == "fish" else 20, axis="yaw" if st == "fish" else "pitch")
        for side in (".L", ".R"):
            if "fin" + side in rig.bones:
                P.turn("fin" + side, p=-28 * s(ph + 0.1))
        if "fin" in rig.bones:
            P.turn("fin", y=25 * s(ph * 4))
    elif st == "crawler":
        for i in (1, 2, 3, 4):
            for side in (".L", ".R"):
                b = f"leg{i}{side}"
                if b in rig.bones:
                    o = (i + (0 if side == ".L" else 1)) % 2 * 0.5
                    P.turn(b, y=rig.side(b) * 22 * s(ph + o))
                    P.move(b, y=0.04 * h * max(0.0, c(ph + o)))
        for side in (".L", ".R"):
            if "arm" + side in rig.bones:
                P.turn("arm" + side, y=rig.side("arm" + side) * 8 * s(ph))
        P.move("body", y=0.015 * h * (1 - c(ph * 2)) / 2)
        P.turn("body", r=2 * s(ph))
        tail_wag(rig, P, ph, 10, axis="pitch")
    elif st == "flyer":
        P.move("root", y=0.06 * h * s(ph))
        P.turn("body", p=-8)
        wings(rig, P, 45 * s(ph * 6), 10)
        tail_wag(rig, P, ph, 8, axis="pitch")
    elif st == "tentacle":
        arms = [b for b in rig.order if re.match(r"arm\d", b) and "_tip" not in b]
        for i, a in enumerate(arms):
            P.turn(a, p=18 * s(ph + i / max(len(arms), 1)))
            tip = a.replace(".", "_tip.") if "." in a else a + "_tip"
            if tip in rig.bones:
                P.turn(tip, p=22 * s(ph + i / max(len(arms), 1) - 0.12))
        P.move("body", y=0.05 * h * max(0.0, s(ph * 2)))
    else:
        segs = [b for b in rig.order if b in ("neck", "seg2", "seg3", "seg4", "seg5", "tail")]
        for i, b in enumerate(segs):
            P.turn(b, y=16 * s(ph - i * 0.18), p=(8 * s(ph * 2 - i * 0.18) if "seg2" in rig.bones else 0))
        if "shell" in rig.bones:
            P.turn("shell", r=3 * s(ph))
        head_look(rig, P, 6 * s(ph + 0.2), 0)
    return P


def happy(rig, ph):
    """A cheerful hop in place, looped (cheering at the roller, after a hatch, on placing)."""
    P = Pose()
    h = rig.h
    st = rig.style
    air = math.sin(math.pi * min(ph / 0.6, 1.0)) if ph < 0.6 else 0.0
    land = math.sin(math.pi * (ph - 0.6) / 0.4) if ph >= 0.6 else 0.0
    jump = 0.3 if h < 8 else 0.18
    if st == "flyer":
        P.move("root", y=0.2 * h * s(ph))
        P.turn("root", y=360 * ph)
        wings(rig, P, 50 * s(ph * 8), 10)
        return P
    P.move("root", y=jump * h * air - 0.04 * h * land)
    P.turn("body", p=12 * air - 6 * land)
    head_look(rig, P, 0, 14 * air - 8 * land)
    for side in (".L", ".R"):
        for b, p in ((f"leg_front{side}", 35), (f"leg_back{side}", -30), (f"leg{side}", 20), (f"foot{side}", 10)):
            if b in rig.bones and (b.startswith("leg") or f"leg{side}" not in rig.bones):
                P.turn(b, p=p * air)
        if "arm" + side in rig.bones:
            P.turn("arm" + side, r=rig.side("arm" + side) * 50 * air)
        if "fin" + side in rig.bones:
            P.turn("fin" + side, r=rig.side("fin" + side) * 30 * air, p=-15 * air)
    if "jaw" in rig.bones:
        P.turn("jaw", p=-20 * air)
    if "trunk" in rig.bones:
        P.turn("trunk", p=35 * air)
        if "trunk2" in rig.bones:
            P.turn("trunk2", p=25 * air)
    if st in ("bird", "penguin") or "wing.L" in rig.bones:
        wings(rig, P, 45 * abs(s(ph * 3)) + (10 if st == "penguin" else 0))
    if st in ("sea",):
        tail_wag(rig, P, ph * 2, 25, axis="pitch")
    else:
        tail_wag(rig, P, ph * 3, 25)
    for i in (1, 2, 3, 4):
        for side in (".L", ".R"):
            b = f"leg{i}{side}"
            if b in rig.bones:
                P.turn(b, r=rig.side(b) * 20 * air)
    arms = [b for b in rig.order if re.match(r"arm\d", b) and "_tip" not in b]
    for i, a in enumerate(arms):
        P.turn(a, p=25 * air)
    for i, b in enumerate([x for x in rig.order if x.startswith("seg")]):
        P.turn(b, p=-10 * air)
    return P


CLIPS = {"Idle": idle, "Walk": walk, "Happy": happy}
PRIORITY = {"Idle": 0, "Walk": 1, "Happy": 2}  # Enum.AnimationPriority Idle/Movement/Action


def sample(rig, clip, t):
    """Bone.Transform (pos, rot) for every bone at time t of the clip."""
    P = CLIPS[clip](rig, (t / LEN[clip]) % 1.0)
    out = {}
    for b in rig.order:
        rot = P.rot.get(b, I3)
        off = P.off.get(b, [0, 0, 0])
        out[b] = rig.local(b, rot, off)
    return out


def pose_tree_xml(rig, name, poses):
    if name == rig.part:
        pos, rot = (0, 0, 0), I3
    else:
        pos, rot = poses[name]
    kids = "".join(pose_tree_xml(rig, k, poses) for k in rig.children.get(name, []))
    return (f'<Item class="Pose" referent="{Ref.next()}"><Properties>'
            f'<string name="Name">{name}</string>{cframe_xml(pos, rot)}'
            f'<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
            f'<float name="Weight">1</float></Properties>{kids}</Item>')


def write_clip(rig, clip):
    Ref.n = 0
    n = round(LEN[clip] * FPS[clip])
    kfs = []
    for i in range(n + 1):
        t = LEN[clip] * i / n
        poses = sample(rig, clip, t)
        kfs.append(f'<Item class="Keyframe" referent="{Ref.next()}"><Properties>'
                   f'<string name="Name">Keyframe</string><float name="Time">{t:.4f}</float></Properties>'
                   f'{pose_tree_xml(rig, rig.part, poses)}</Item>')
    name = f"Pet_{rig.name}_{clip}"
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">'
           f'<Item class="KeyframeSequence" referent="{Ref.next()}"><Properties>'
           f'<string name="Name">{name}</string><bool name="Loop">true</bool>'
           f'<token name="Priority">{PRIORITY[clip]}</token></Properties>{"".join(kfs)}</Item></roblox>')
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name + ".rbxmx"), "w") as f:
        f.write(xml)
    return name


def load_rigs():
    with open(RIGS) as f:
        data = json.load(f)
    return {k: Rig(k, v) for k, v in data.items()}


def game_models():
    src = open(os.path.join(ROOT, "src", "shared", "Config", "Pets.luau")).read()
    models = set()
    for m in re.finditer(r'pet\(\s*"(\w+)"', src):
        models.add(m.group(1))
    for m in re.finditer(r'Model\s*=\s*"(\w+)"', src):
        models.add(m.group(1))
    return sorted(models)


def main(argv):
    rigs = load_rigs()
    if "--all" in argv:
        names = sorted(rigs)
    elif argv:
        names = argv
    else:
        names = [n for n in game_models() if n in rigs]
    for n in names:
        for clip in CLIPS:
            write_clip(rigs[n], clip)
        print(f"{n}: {rigs[n].style}")


if __name__ == "__main__":
    main(sys.argv[1:])
