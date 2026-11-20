"""Player training animation for the Snow Roller: a leaning push-walk with a shove on
every rep (Economy.TrainRepsPerSecond 0.8 -> one cycle = 1.25 s; TrainController sets the
track speed from the real rep rate). Writes art/out/anims/Player_Push.rbxmx, a
KeyframeSequence; upload with tools/upload_anims.py.

R15 joint rotations (Motor6D Transform, CFrame.Angles order):
  +X on a shoulder / hip swings the limb FORWARD (toward -Z), +X on an elbow bends it up,
  -X on a knee bends it back; -X on the torso leans forward.
"""
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "anims")

R15_TREE = {
    "HumanoidRootPart": {
        "LowerTorso": {
            "UpperTorso": {
                "Head": {},
                "RightUpperArm": {"RightLowerArm": {"RightHand": {}}},
                "LeftUpperArm": {"LeftLowerArm": {"LeftHand": {}}},
            },
            "RightUpperLeg": {"RightLowerLeg": {"RightFoot": {}}},
            "LeftUpperLeg": {"LeftLowerLeg": {"LeftFoot": {}}},
        }
    }
}


def mat(rx, ry, rz):
    """CFrame.Angles(rx, ry, rz) rotation matrix (R = Rx * Ry * Rz)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    Rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mm(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mm(mm(Rx, Ry), Rz)


def cframe_xml(pos, rot):
    m = rot if isinstance(rot, list) else mat(*rot)
    vals = {"X": pos[0], "Y": pos[1], "Z": pos[2]}
    for i in range(3):
        for j in range(3):
            vals[f"R{i}{j}"] = m[i][j]
    inner = "".join(f"<{k}>{v:.5f}</{k}>" for k, v in vals.items())
    return f'<CoordinateFrame name="CFrame">{inner}</CoordinateFrame>'


class Ref:
    n = 0

    @classmethod
    def next(cls):
        cls.n += 1
        return f"RBX{cls.n}"


def pose_xml(name, tree, poses):
    pos, rot = poses.get(name, ((0, 0, 0), (0, 0, 0)))
    kids = "".join(pose_xml(k, sub, poses) for k, sub in tree.items())
    return (f'<Item class="Pose" referent="{Ref.next()}"><Properties>'
            f'<string name="Name">{name}</string>{cframe_xml(pos, rot)}'
            f'<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
            f'<float name="Weight">1</float></Properties>{kids}</Item>')


def sequence(name, frames, loop, priority, tree):
    """frames: list of (time, {joint: ((x,y,z),(rx,ry,rz))})."""
    Ref.n = 0
    kfs = []
    for t, poses in frames:
        root, sub = next(iter(tree.items()))
        kfs.append(f'<Item class="Keyframe" referent="{Ref.next()}"><Properties>'
                   f'<string name="Name">Keyframe</string><float name="Time">{t:.4f}</float></Properties>'
                   f'{pose_xml(root, sub, poses)}</Item>')
    return ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">'
            f'<Item class="KeyframeSequence" referent="RBX0"><Properties>'
            f'<string name="Name">{name}</string><bool name="Loop">{"true" if loop else "false"}</bool>'
            f'<token name="Priority">{priority}</token></Properties>{"".join(kfs)}</Item></roblox>')



D = math.radians
CYCLE = 1.25


def push(t):
    """Pose at time t (0..CYCLE). Two steps per cycle; the shove peaks at t = 0.4 s."""
    w = 2 * math.pi * t / CYCLE
    step = math.sin(2 * w)            # two steps per rep
    shove = math.exp(-((t - 0.4) / 0.16) ** 2)  # quick arm extension
    bob = abs(math.sin(2 * w))
    lean = -26 - 6 * shove
    return {
        "LowerTorso": ((0, -0.15 * bob, 0), (D(-10), 0, D(2 * step))),
        "UpperTorso": ((0, 0, 0), (D(lean + 10), D(4 * step), 0)),
        "Head": ((0, 0, 0), (D(24 + 4 * shove), 0, 0)),
        # Both arms forward onto the ball, elbows bent, straightening on the shove.
        "RightUpperArm": ((0, 0, 0), (D(100 + 10 * shove + 4 * step), 0, D(8))),
        "RightLowerArm": ((0, 0, 0), (D(38 - 30 * shove), 0, 0)),
        "LeftUpperArm": ((0, 0, 0), (D(100 + 10 * shove - 4 * step), 0, D(-8))),
        "LeftLowerArm": ((0, 0, 0), (D(38 - 30 * shove), 0, 0)),
        "RightHand": ((0, 0, 0), (D(-20), 0, 0)),
        "LeftHand": ((0, 0, 0), (D(-20), 0, 0)),
        # Legs: digging-in walk, hips compensate the lower-torso lean.
        "RightUpperLeg": ((0, 0, 0), (D(10 + 30 * step), 0, 0)),
        "RightLowerLeg": ((0, 0, 0), (D(-20 - 25 * max(0, -step)), 0, 0)),
        "RightFoot": ((0, 0, 0), (D(10 * step), 0, 0)),
        "LeftUpperLeg": ((0, 0, 0), (D(10 - 30 * step), 0, 0)),
        "LeftLowerLeg": ((0, 0, 0), (D(-20 - 25 * max(0, step)), 0, 0)),
        "LeftFoot": ((0, 0, 0), (D(-10 * step), 0, 0)),
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    steps = 20
    frames = [(CYCLE * i / steps, push(CYCLE * i / steps)) for i in range(steps + 1)]
    xml = sequence("Player_Push", frames, True, 3, R15_TREE)
    path = os.path.join(OUT, "Player_Push.rbxmx")
    open(path, "w").write(xml)
    print("wrote", path, len(xml))


if __name__ == "__main__":
    main()
