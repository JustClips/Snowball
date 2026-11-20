"""The rescue flag (Dev 2026-11-20, egg rescue): where you carry an egg from the crack pile
to bank it. A snow mound with a blue ice ring, a wooden pole with a gold knob and a big wavy
green flag with a white egg sign. About 14 studs tall; origin = mound centre on the ground,
flag waves toward Roblox +X.

  python flag.py
"""
import math
import sys

import kit
from kit import cyl, sphere

import bmesh
import bpy

kit.PALETTE.update({"FlagGreen": (60, 205, 90), "FlagWhite": (250, 252, 255), "PoleWood": (140, 90, 50),
                    "Knob": (255, 200, 50), "IceRing": (110, 200, 255), "Mound": (240, 246, 255)})
kit.GLOW.update({"IceRing"})


def rb(x, y, z):
    return (-x, z, y)


def cloth(name, w, h, x0, y0, color, z=0.0, depth=0.12, wave=0.45):
    """A waving flag panel in the Roblox X/Y plane, starting at the pole (x0) going +X."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    nx, ny = 16, 6
    def p(i, j, side):
        u, v = i / nx, j / ny
        x = x0 + u * w
        y = y0 + v * h - u * 0.6
        zz = z + math.sin(u * math.pi * 1.6) * wave * u + side * depth / 2
        return rb(x, y, zz)
    front = [[bm.verts.new(p(i, j, -1)) for j in range(ny + 1)] for i in range(nx + 1)]
    back = [[bm.verts.new(p(i, j, 1)) for j in range(ny + 1)] for i in range(nx + 1)]
    for i in range(nx):
        for j in range(ny):
            bm.faces.new((front[i][j], front[i + 1][j], front[i + 1][j + 1], front[i][j + 1]))
            bm.faces.new((back[i][j + 1], back[i + 1][j + 1], back[i + 1][j], back[i][j]))
    for i in range(nx):
        bm.faces.new((front[i][0], back[i][0], back[i + 1][0], front[i + 1][0]))
        bm.faces.new((front[i + 1][ny], back[i + 1][ny], back[i][ny], front[i][ny]))
    for j in range(ny):
        bm.faces.new((front[nx][j], back[nx][j], back[nx][j + 1], front[nx][j + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(kit.mat(color))
    return o


def build():
    scene = kit.reset()
    kit.light_rig(scene)
    parts = []
    parts.append(sphere("Mound", 4.2, rb(0, -1.6, 0), "Mound", subdiv=3, scale=(1, 1, 0.55)))
    parts.append(cyl("Ring", 4.6, 0.35, rb(0, 0.15, 0), "IceRing", verts=32, rot=(0, 0, 0)))
    parts.append(cyl("RingHole", 3.9, 0.4, rb(0, 0.17, 0), "Mound", verts=32))
    parts.append(cyl("Pole", 0.28, 13.0, rb(0, 7.0, 0), "PoleWood", verts=10))
    parts.append(sphere("Knob", 0.55, rb(0, 13.6, 0), "Knob", subdiv=2))
    parts.append(cloth("Flag", 6.0, 3.8, 0.25, 9.0, "FlagGreen"))
    # White egg sign on both sides of the flag.
    for side in (-1, 1):
        parts.append(sphere(f"EggSign{side}", 0.95, rb(2.9, 10.65, side * 0.32), "FlagWhite", subdiv=3,
                            scale=(0.8, 0.25, 1.05)))
    return [kit.join(parts, "RescueFlag")]


if __name__ == "__main__":
    objs = build()
    if "--nobake" not in sys.argv:
        kit.bake_many(objs, "RescueFlag", size=1024, samples=16)
        print(kit.export_glb(objs, "RescueFlag"))
    print(kit.preview("RescueFlag", target=(0, 0, 6), dist=30, elev=15, azim=-35, res=(400, 400), samples=12))
