"""Preview the pet bone animations (art/anim/pets.py) on the real StudAnimalPack meshes in
Blender: builds every pet as a skinned mesh + armature from its Roblox mesh and plays the
same Bone.Transform values the game will play.

  python art/blender/pet_preview.py --clip Walk --frames 12 --out art/out/preview/walk
  python art/blender/pet_preview.py --pets Fox,Duck --clip Idle --frames 8 --out DIR
  python art/blender/pet_preview.py --pets Fox --save art/out/Fox_anims.blend   # open in Blender

Run with the pip `bpy` venv (or `blender --background --python ... -- <args>`). Meshes and
textures are fetched by asset id (needs ROBLOXAPIKEY) into art/out/petmesh/.
With --save, the .blend gets one action per clip (Idle/Walk/Happy) on each armature so the
clips can be scrubbed in Blender's own timeline.

Roblox -> Blender axes: (x, y, z) -> (x, -z, y). Pets face Roblox -Z = Blender +Y.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "art", "anim"))
import pets as petanim  # noqa: E402
import robloxmesh  # noqa: E402

CACHE = os.path.join(ROOT, "art", "out", "petmesh")
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Roblox -> Blender
SHOW_HEIGHT = 3.0


def to_bl(v):
    return C @ Vector(v)


def frame_matrix(rot, pos):
    r = C @ Matrix(rot)
    m = r.to_4x4()
    m.translation = to_bl(pos)
    return m


def local_matrix(pos, rot):
    m = Matrix(rot).to_4x4()
    m.translation = Vector(pos)
    return m


def build_pet(rig, at):
    data = petanim.json.load(open(petanim.RIGS))[rig.name]
    mesh_path = robloxmesh.fetch(data["mesh"], os.path.join(CACHE, f"{rig.name}.mesh"))
    m = robloxmesh.load(mesh_path)

    arm_data = bpy.data.armatures.new(rig.name + "_Rig")
    arm = bpy.data.objects.new(rig.name + "_Rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for n in rig.order:
        b = rig.bones[n]
        eb = arm_data.edit_bones.new(n)
        eb.head = (0, 0, 0)
        eb.tail = (0, 0.25 * rig.h / 6, 0)
        eb.matrix = frame_matrix(b["wrot"], b["wpos"])
        if b["parent"] in rig.bones:
            eb.parent = arm_data.edit_bones[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")

    me = bpy.data.meshes.new(rig.name)
    verts = [tuple(to_bl(p)) for p in m["pos"]]
    me.from_pydata(verts, [], [tuple(int(i) for i in f) for f in m["faces"]])
    me.update()
    if m.get("uv") is not None:
        uvl = me.uv_layers.new(name="UV")
        for loop in me.loops:
            u, v = m["uv"][loop.vertex_index]
            uvl.data[loop.index].uv = (u, 1 - v)
    obj = bpy.data.objects.new(rig.name, me)
    bpy.context.scene.collection.objects.link(obj)
    for poly in me.polygons:
        poly.use_smooth = False
    groups = {n: obj.vertex_groups.new(name=n) for n in m["bone_names"]}
    for vi in range(len(verts)):
        for k in range(4):
            w = float(m["skin_w"][vi][k])
            if w > 0:
                groups[m["bone_names"][m["skin_idx"][vi][k]]].add([vi], w, "ADD")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.parent = arm

    mat = bpy.data.materials.new(rig.name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    if data.get("tex"):
        tex_path = robloxmesh.fetch(data["tex"], os.path.join(CACHE, f"{rig.name}.png"))
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(tex_path)
        node.interpolation = "Closest"
        mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)

    scale = SHOW_HEIGHT / rig.h
    arm.scale = (scale, scale, scale)
    # Pivot: the pack's pivot is the part's bottom centre.
    arm.location = Vector(at) + Vector((0, 0, rig.h / 2 * scale))
    return arm


def pose(arm, rig, clip, t):
    vals = petanim.sample(rig, clip, t)
    for n, (pos, rot) in vals.items():
        arm.pose.bones[n].matrix_basis = local_matrix(pos, rot)


def bake_actions(arm, rig):
    for clip in petanim.CLIPS:
        act = bpy.data.actions.new(f"{rig.name}_{clip}")
        arm.animation_data_create()
        arm.animation_data.action = act
        n = round(petanim.LEN[clip] * 24)
        for i in range(n + 1):
            pose(arm, rig, clip, petanim.LEN[clip] * i / n)
            for pb in arm.pose.bones:
                pb.keyframe_insert("location", frame=i + 1)
                pb.keyframe_insert("rotation_quaternion", frame=i + 1)
        act.use_fake_user = True


def setup_scene(cols, rows, gap, res):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 12
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.85, 1.0, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    sc.world = world
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0))
    ground = bpy.context.active_object
    gm = bpy.data.materials.new("Snow")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.93, 0.96, 1, 1)
    gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    ground.data.materials.append(gm)
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    w = cols * gap
    hgt = rows * gap * 0.75 + 1.5
    cam.data.ortho_scale = max(w, hgt * res[0] / res[1]) * 1.05
    cx, cy = -(cols - 1) * gap / 2, -(rows - 1) * gap / 2
    # 3/4 front view, a bit from above and from the pet's right side.
    d = Vector((-1.0, 0.8, 0.55)).normalized()
    cam.location = Vector((cx, cy, 1.6)) + d * 80
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(cam)
    sc.camera = cam


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--pets", default="")
    ap.add_argument("--clip", default="Walk")
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--out", default=os.path.join(ROOT, "art", "out", "preview"))
    ap.add_argument("--cols", type=int, default=7)
    ap.add_argument("--save", default="")
    ap.add_argument("--res", default="1400x1000")
    a = ap.parse_args(argv)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rigs = petanim.load_rigs()
    names = [n for n in a.pets.split(",") if n] or [n for n in petanim.game_models() if n in rigs]
    cols = min(a.cols, len(names))
    rows = math.ceil(len(names) / cols)
    gap = 6.5
    arms = []
    for i, n in enumerate(names):
        at = (-(i % cols) * gap, -(i // cols) * gap, 0)
        arms.append((build_pet(rigs[n], at), rigs[n]))
    if a.save:
        for arm, rig in arms:
            for pb in arm.pose.bones:
                pb.rotation_mode = "QUATERNION"
            bake_actions(arm, rig)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.save))
        print("saved", a.save)
        return
    res = tuple(int(x) for x in a.res.split("x"))
    setup_scene(cols, rows, gap, res)
    os.makedirs(a.out, exist_ok=True)
    for f in range(a.frames):
        t = petanim.LEN[a.clip] * f / a.frames
        for arm, rig in arms:
            pose(arm, rig, a.clip, t)
        bpy.context.view_layer.update()
        bpy.context.scene.render.filepath = os.path.join(a.out, f"{a.clip}_{f:02d}.png")
        bpy.ops.render.render(write_still=True)
        print("frame", f, flush=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args)
