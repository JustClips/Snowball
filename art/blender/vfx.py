"""Particle textures for Roblox ParticleEmitters, rendered in Blender (transparent PNGs,
no text). Written to art/ui/Fx_<Name>.png so tools/upload_images.py uploads them into
Config/Images (Images.Fx_SnowPuff, ...).

  Fx_SnowPuff   4x4 flipbook (1024): a soft snow cloud puffing out and thinning.
  Fx_Sparkle    4-point star glint with a soft glow.
  Fx_Flake      chunky six-armed snowflake.
  Fx_Shard      a faceted ice shard.
  Fx_Ring       soft shockwave ring.

  python vfx.py
"""
import math
import os
import random

import bpy

import kit

UI = os.path.join(kit.ROOT, "art", "ui")


def scene_base(res):
    scene = kit.reset()
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = res
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.85, 0.92, 1, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.6
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 3.5
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(35), math.radians(-25), 0)
    scene.collection.objects.link(so)
    cam = bpy.data.cameras.new("Cam")
    cam.type = "ORTHO"
    cam.ortho_scale = 2.0
    co = bpy.data.objects.new("Cam", cam)
    co.location = (0, -10, 0)
    co.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(co)
    scene.camera = co
    return scene


def emissive(name, color, strength, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    if alpha < 1:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs["Fac"].default_value = alpha
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
    else:
        nt.links.new(em.outputs[0], out.inputs[0])
    return m


def snow_mat():
    m = bpy.data.materials.new("Snow")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.62, 0.7, 0.8, 1)
    b.inputs["Roughness"].default_value = 0.9
    b.inputs["Subsurface Weight"].default_value = 0.3
    return m


def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def snow_puff():
    """16 frames of a puff (lumpy sphere cluster growing and thinning), tiled 4x4."""
    from PIL import Image
    rng = random.Random(5)
    blobs = [(rng.uniform(-0.45, 0.45), rng.uniform(-0.2, 0.2), rng.uniform(-0.4, 0.4), rng.uniform(0.25, 0.45)) for _ in range(14)]
    frames = []
    for f in range(16):
        t = f / 15
        scene_base(256)
        m = snow_mat()
        grow = 0.55 + 0.6 * (1 - (1 - t) ** 2)
        keep = int(len(blobs) * (1 - 0.75 * t ** 1.5)) + 1
        for i, (x, y, z, r) in enumerate(blobs[:keep]):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r * grow * (1 - 0.35 * t), location=(x * grow, y, z * grow), segments=24, ring_count=12)
            o = bpy.context.active_object
            bpy.ops.object.shade_smooth()
            o.data.materials.append(m)
        p = render(os.path.join("/tmp", f"puff_{f}.png"))
        frames.append(Image.open(p).convert("RGBA"))
    sheet = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    for f, im in enumerate(frames):
        # Fade the last frames so the puff dissolves.
        t = f / 15
        if t > 0.5:
            a = im.split()[3].point(lambda v, k=(1 - (t - 0.5) * 2): int(v * k))
            im.putalpha(a)
        sheet.paste(im, ((f % 4) * 256, (f // 4) * 256))
    out = os.path.join(UI, "Fx_SnowPuff.png")
    sheet.save(out)
    return out


def flat(name, build, res=256):
    scene_base(res)
    build()
    return render(os.path.join(UI, f"Fx_{name}.png"))


def star_mesh(name, points, outer, inner, mat):
    """A flat star in the camera plane (XZ)."""
    import bmesh
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    centre = bm.verts.new((0, 0, 0))
    ring = []
    for k in range(points * 2):
        a = math.pi * k / points
        r = outer[k // 2 % len(outer)] if k % 2 == 0 else inner
        ring.append(bm.verts.new((math.sin(a) * r, 0, math.cos(a) * r)))
    for k in range(len(ring)):
        bm.faces.new((centre, ring[k], ring[(k + 1) % len(ring)]))
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def sparkle():
    glow = emissive("Glow", (1, 0.97, 0.85, 1), 6)
    soft = emissive("Soft", (0.7, 0.9, 1, 1), 1.5, alpha=0.35)
    star_mesh("Star", 4, [0.95, 0.95], 0.1, glow)
    s2 = star_mesh("Star2", 4, [0.45, 0.45], 0.06, glow)
    s2.rotation_euler = (0, math.radians(45), 0)
    bpy.ops.mesh.primitive_circle_add(vertices=48, radius=0.35, fill_type="NGON", location=(0, 0.5, 0), rotation=(math.radians(90), 0, 0))
    bpy.context.active_object.data.materials.append(soft)


def flake():
    m = emissive("Flake", (0.92, 0.97, 1, 1), 1.4)
    for k in range(6):
        a = k * math.pi / 3
        bpy.ops.mesh.primitive_cube_add(size=1, location=(math.sin(a) * 0.4, 0, math.cos(a) * 0.4), rotation=(0, a, 0))
        o = bpy.context.active_object
        o.scale = (0.11, 0.05, 0.8)
        o.data.materials.append(m)
        for s in (-1, 1):
            bpy.ops.mesh.primitive_cube_add(size=1, location=(math.sin(a) * 0.55 + math.sin(a + s * 0.9) * 0.12, 0, math.cos(a) * 0.55 + math.cos(a + s * 0.9) * 0.12), rotation=(0, a + s * 0.9, 0))
            b = bpy.context.active_object
            b.scale = (0.08, 0.05, 0.28)
            b.data.materials.append(m)
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.16, depth=0.1, location=(0, 0, 0), rotation=(math.radians(90), 0, 0))
    bpy.context.active_object.data.materials.append(m)


def shard():
    m = bpy.data.materials.new("Ice")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.55, 0.85, 1.0, 1)
    b.inputs["Roughness"].default_value = 0.15
    b.inputs["Emission Color"].default_value = (0.5, 0.85, 1, 1)
    b.inputs["Emission Strength"].default_value = 0.4
    bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.35, radius2=0, depth=1.7, rotation=(0, math.radians(20), math.radians(30)))
    o = bpy.context.active_object
    o.data.materials.append(m)
    bpy.ops.object.shade_flat()


def ring():
    m = emissive("Ring", (0.9, 0.96, 1, 1), 2.0, alpha=0.8)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.78, minor_radius=0.12, major_segments=64, minor_segments=12, rotation=(math.radians(90), 0, 0))
    bpy.context.active_object.data.materials.append(m)


if __name__ == "__main__":
    print(snow_puff())
    for name, fn in (("Sparkle", sparkle), ("Flake", flake), ("Shard", shard), ("Ring", ring)):
        print(flat(name, fn))
