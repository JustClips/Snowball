"""Tutorial ground arrow (Steal an Egg's red chevrons on the ground, reference-study.md):
one chunky red chevron with a white rim, flat on the ground, pointing to the model's FRONT
(Roblox -Z), so CFrame.lookAt(pos, target) aims it. WorldService puts it in
ReplicatedStorage.Assets; TutorialController lays a trail of them to the goal.

  python marker.py
"""
import math
import sys

import kit
from kit import box

import bmesh
import bpy

# Chevron outline (Blender x, y; front = -Y), clockwise from the tip.
OUTLINE = [(0, -2.0), (2.0, 0.4), (1.25, 1.15), (0, -0.45), (-1.25, 1.15), (-2.0, 0.4)]


def slab(name, pts, z0, z1, color):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bottom = [bm.verts.new((x, y, z0)) for x, y in pts]
    top = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    n = len(pts)
    for k in range(n):
        bm.faces.new((bottom[k], bottom[(k + 1) % n], top[(k + 1) % n], top[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(kit.mat(color))
    kit._bevel(o, 0.08)
    return o


def grow(pts, d):
    """Offset a polygon outward by about d (scale about its centroid, good enough here)."""
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    out = []
    for x, y in pts:
        vx, vy = x - cx, y - cy
        l = math.hypot(vx, vy) or 1
        out.append((x + vx / l * d, y + vy / l * d))
    return out


def chevron(p):
    p.append(slab("Rim", grow(OUTLINE, 0.32), 0.0, 0.2, "Snow"))
    p.append(slab("Arrow", OUTLINE, 0.12, 0.5, "Red"))


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    parts = []
    chevron(parts)
    return [kit.join(parts, "Chevron")]


if __name__ == "__main__":
    objs = build()
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "Chevron", size=512, samples=16)
        print(kit.export_glb(objs, "Chevron"))
    print(kit.preview("Chevron", target=(0, 0, 0), dist=9, elev=55, azim=-20, res=(400, 400), samples=12))
