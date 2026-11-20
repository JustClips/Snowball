"""Shared Blender helpers for Roll the Snowball models (stud-style "toy-box" kit).

Units: 1 Blender unit = 1 Roblox stud (GLB 1 m = 1 stud). Axes: Blender (x, y, z) ->
Roblox (-x, z, y), so Blender -Y is the model's FRONT (Roblox -Z / LookVector) and +Z is up.
Every model's origin is the centre of its footprint at floor level.

Look (vault: "Voxel Art - Studs Outlines and Style Kits", outlined studded toy-box kit):
saturated mid colours, chunky bevelled blocks, raised studs on top faces, snow caps, one
glow colour. Colours are flat materials; `bake()` bakes lighting + studs into one texture
atlas per model, because Roblox ignores glTF base colours (palette texture rule).

Run inside Blender (Blender MCP / Dev's PC) or headless with the `bpy` wheel:
  python art/blender/build.py base       # builds, bakes, exports art/out/<Name>.glb + preview
"""
import math
import os

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "out")

# Palette (sRGB 0-255). Saturated mid tones, readable on phones.
PALETTE = {
    "Snow": (244, 248, 255),
    "SnowShade": (206, 222, 242),
    "Ice": (150, 215, 255),
    "Log": (150, 92, 52),
    "LogDark": (110, 64, 36),
    "Plank": (196, 132, 74),
    "Stone": (140, 148, 160),
    "StoneDark": (98, 104, 118),
    "RoofRed": (214, 58, 64),
    "RoofBlue": (60, 120, 220),
    "Door": (120, 70, 40),
    "Window": (255, 214, 120),
    "Gold": (255, 196, 40),
    "Pine": (40, 150, 90),
    "PineDark": (26, 110, 66),
    "Glow": (120, 230, 255),
    "Iron": (120, 128, 140),
    "Red": (230, 60, 60),
    "Green": (70, 200, 90),
    "Purple": (150, 90, 230),
    "Diamond": (120, 240, 255),
    "Aurora": (110, 255, 190),
    "Black": (30, 34, 44),
}

GLOW = {"Window", "Glow", "Aurora", "Diamond"}


def srgb(c):
    def lin(v):
        v = v / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (lin(c[0]), lin(c[1]), lin(c[2]), 1.0)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    return scene


_mats = {}


def mat(name, studs=False):
    """Flat colour material. studs=True adds a stud bump grid (1 stud apart) for tops."""
    key = (name, studs)
    if key in _mats and _mats[key].name in bpy.data.materials:
        return _mats[key]
    m = bpy.data.materials.new(f"{name}{'_Studs' if studs else ''}")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(PALETTE[name])
    bsdf.inputs["Roughness"].default_value = 0.6
    if name in GLOW:
        bsdf.inputs["Emission Color"].default_value = srgb(PALETTE[name])
        bsdf.inputs["Emission Strength"].default_value = 0.6
    if studs:
        # Raised round studs every 1 stud in object XY: distance to cell centre -> bump.
        coord = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["Object"], sep.inputs[0])
        def frac(out):
            sub = nt.nodes.new("ShaderNodeMath"); sub.operation = "FRACT"
            nt.links.new(out, sub.inputs[0])
            off = nt.nodes.new("ShaderNodeMath"); off.operation = "SUBTRACT"
            nt.links.new(sub.outputs[0], off.inputs[0]); off.inputs[1].default_value = 0.5
            return off.outputs[0]
        fx, fy = frac(sep.outputs["X"]), frac(sep.outputs["Y"])
        comb = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(fx, comb.inputs[0]); nt.links.new(fy, comb.inputs[1])
        length = nt.nodes.new("ShaderNodeVectorMath"); length.operation = "LENGTH"
        nt.links.new(comb.outputs[0], length.inputs[0])
        ramp = nt.nodes.new("ShaderNodeMapRange")
        nt.links.new(length.outputs["Value"], ramp.inputs["Value"])
        ramp.inputs["From Min"].default_value = 0.26
        ramp.inputs["From Max"].default_value = 0.30
        ramp.inputs["To Min"].default_value = 1.0
        ramp.inputs["To Max"].default_value = 0.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = 0.9
        bump.inputs["Distance"].default_value = 0.08
        nt.links.new(ramp.outputs["Result"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _mats[key] = m
    return m


def _bevel(obj, width):
    if width <= 0:
        return
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = 2
    mod.limit_method = "ANGLE"


def box(name, size, loc, color, bevel=0.12, rot=(0, 0, 0), studs=False, parent_list=None):
    """Axis box: size (x, y, z), loc = centre."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(color))
    if studs:
        # Top face gets the stud material.
        o.data.materials.append(mat(color, studs=True))
        for poly in o.data.polygons:
            if poly.normal.z > 0.9:
                poly.material_index = 1
    _bevel(o, bevel)
    if parent_list is not None:
        parent_list.append(o)
    return o


def cyl(name, radius, depth, loc, color, verts=12, rot=(0, 0, 0), bevel=0.08):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat(color))
    _bevel(o, bevel)
    return o


def cone(name, r1, r2, depth, loc, color, verts=8, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot, vertices=verts)
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(mat(color))
    _bevel(o, 0.06)
    return o


def sphere(name, radius, loc, color, subdiv=2, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, location=loc, subdivisions=subdiv)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat(color))
    bpy.ops.object.shade_flat()
    return o


def snowcap(name, size, loc, drip=True):
    """A soft snow slab on top of something, slightly overhanging, with lumpy edge."""
    o = box(name, (size[0] + 0.3, size[1] + 0.3, size[2]), loc, "Snow", bevel=min(0.35, size[2] * 0.45))
    return o


def join(objs, name):
    """Applies modifiers and joins into one mesh object."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def all_meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def light_rig(scene, strength=3.0):
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = strength
    sun.angle = math.radians(12)
    so = bpy.data.objects.new("Sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(so)


def bake(obj, name, size=1024, samples=24):
    """Smart-UV the object and bake lit colour (diffuse + AO + studs) into one image,
    then swap its materials for one textured material. Returns the image path."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, area_weight=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(f"{name}_Atlas", size, size)
    for m in obj.data.materials:
        nt = m.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        nt.nodes.active = tex
    bake = scene.render.bake
    bake.use_pass_direct = True
    bake.use_pass_indirect = True
    bake.use_pass_diffuse = True
    bake.use_pass_glossy = False
    bake.use_pass_transmission = False
    bake.use_pass_emit = True
    bake.margin = 4
    bpy.ops.object.bake(type="COMBINED")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}_Atlas.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    # One textured, unlit-friendly material.
    out = bpy.data.materials.new(f"{name}_Mat")
    out.use_nodes = True
    nt = out.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(out)
    return path


def export_glb(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_image_format="AUTO")
    return path


def preview(name, target=(0, 0, 4), dist=70, elev=32, azim=-38, res=(960, 640), samples=24):
    """Renders art/out/<name>_preview.png from a 3/4 front view (front = -Y)."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.resolution_x, scene.render.resolution_y = res
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 40
    co = bpy.data.objects.new("Cam", cam)
    scene.collection.objects.link(co)
    a, e = math.radians(azim), math.radians(elev)
    co.location = (target[0] + dist * math.cos(e) * math.sin(a), target[1] - dist * math.cos(e) * math.cos(a), target[2] + dist * math.sin(e))
    direction = [target[i] - co.location[i] for i in range(3)]
    import mathutils
    co.rotation_euler = mathutils.Vector(direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = co
    path = os.path.join(OUT, f"{name}_preview.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(co)
    return path


def bake_many(objs, name, size=2048, samples=24):
    """Like bake(), but packs every object's UVs into ONE shared atlas (multi-object edit)
    so a model made of several MeshParts uses a single texture."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002, area_weight=0.0)
    bpy.ops.uv.pack_islands(margin=0.002)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(f"{name}_Atlas", size, size)
    seen = set()
    for o in objs:
        for m in o.data.materials:
            if m.name in seen:
                continue
            seen.add(m.name)
            tex = m.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = img
            m.node_tree.nodes.active = tex
    b = scene.render.bake
    b.use_pass_direct = True
    b.use_pass_indirect = True
    b.use_pass_diffuse = True
    b.use_pass_glossy = False
    b.use_pass_transmission = False
    b.use_pass_emit = True
    b.margin = 3
    bpy.ops.object.bake(type="COMBINED")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}_Atlas.png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    out = bpy.data.materials.new(f"{name}_Mat")
    out.use_nodes = True
    nt = out.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(out)
    return path
