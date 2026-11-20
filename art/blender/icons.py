"""Game-specific icons rendered in Blender (transparent PNG, no text) into art/ui/Icon_<Name>.png:
  Snowball  a big shaded snowball with motion streaks (the ROLL button)
  python icons.py
"""
import math
import os

import bpy

import kit
from vfx import scene_base, emissive, render, UI


def outline_mat():
    m = bpy.data.materials.new("Outline")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.04, 0.09, 1)
    m.use_backface_culling = True
    return m


def snowball():
    scene = scene_base(512)
    bpy.context.scene.camera.data.ortho_scale = 2.6
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
    snow = bpy.data.materials.new("Snow")
    snow.use_nodes = True
    b = snow.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.8, 0.9, 1.0, 1)
    b.inputs["Roughness"].default_value = 0.7
    shade = bpy.data.materials.new("Shade")
    shade.use_nodes = True
    shade.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.45, 0.65, 0.95, 1)
    # Ball + lumps.
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.8, subdivisions=4, location=(0.15, 0, -0.05))
    ball = bpy.context.active_object
    ball.data.materials.append(snow)
    bpy.ops.object.shade_smooth()
    for k, (a, z) in enumerate([(0.6, 0.45), (2.2, -0.35), (3.9, 0.2), (5.0, -0.55), (1.4, -0.65)]):
        d = (math.cos(a) * 0.6, -0.55, z)
        n = math.sqrt(sum(c * c for c in d))
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.17, subdivisions=2, location=(0.15 + d[0] / n * 0.78, d[1] / n * 0.78, -0.05 + d[2] / n * 0.78))
        o = bpy.context.active_object
        o.data.materials.append(shade if k % 2 else snow)
        bpy.ops.object.shade_smooth()
    # Thick dark outline: inverted hull.
    bpy.ops.mesh.primitive_ico_sphere_add(radius=0.9, subdivisions=4, location=(0.15, 0.4, -0.05))
    hull = bpy.context.active_object
    hull.data.materials.append(outline_mat())
    # Motion streaks on the left.
    streak = emissive("Streak", (0.75, 0.9, 1, 1), 1.6)
    for k, (z, w) in enumerate([(0.35, 0.55), (0.0, 0.8), (-0.35, 0.5)]):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(-0.85 - w / 2 + 0.1, 0.2, z))
        o = bpy.context.active_object
        o.scale = (w, 0.05, 0.11)
        o.data.materials.append(streak)
    return render(os.path.join(UI, "Icon_Snowball.png"))


if __name__ == "__main__":
    print(snowball())
