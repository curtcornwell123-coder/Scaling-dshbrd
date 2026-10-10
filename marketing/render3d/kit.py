"""Blender (bpy) toolkit for Corny Games 3D marketing renders.

Scenes are built from code: glossy plastic, neon emission, metal and glass materials, bevelled
primitives, the real dimpled golf-ball mesh, blocky R6-style avatars. Cycles + denoise, AgX.
"""
import math
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BALL_OBJ = os.path.join(ROOT, "chaos-golf", "assets", "mesh", "golfball.obj")


def hexrgb(h, a=1.0):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    # sRGB -> linear
    lin = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (*lin, a)


# Scene -----------------------------------------------------------------------------------------

def reset(width=1920, height=1080, samples=64):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.max_bounces = 6
    sc.cycles.glossy_bounces = 3
    sc.cycles.transmission_bounces = 4
    sc.render.resolution_x = width
    sc.render.resolution_y = height
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX"
    try:
        sc.view_settings.look = "AgX - Punchy"
    except TypeError:
        pass
    sc.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    return sc


def world_gradient(top, bottom, strength=1.0):
    """Vertical gradient sky (visible background + soft ambient)."""
    w = bpy.context.scene.world
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mp = nt.nodes.new("ShaderNodeMapRange")
    mp.inputs["From Min"].default_value = -0.3
    mp.inputs["From Max"].default_value = 0.8
    ramp.color_ramp.elements[0].color = hexrgb(bottom)
    ramp.color_ramp.elements[1].color = hexrgb(top)
    nt.links.new(tex.outputs["Generated"], sep.inputs[0])
    nt.links.new(tex.outputs["Window"], sep.inputs[0])
    nt.links.new(sep.outputs["Y"], mp.inputs["Value"])
    nt.links.new(mp.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def camera(loc, target, lens=50, dof_target=None, fstop=2.8):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(loc)
    look_at(cam, target)
    bpy.context.scene.camera = cam
    if dof_target is not None:
        cam_data.dof.use_dof = True
        cam_data.dof.focus_distance = (Vector(loc) - Vector(dof_target)).length
        cam_data.dof.aperture_fstop = fstop
    return cam


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def light_area(loc, target, power, color="#FFFFFF", size=4.0):
    ld = bpy.data.lights.new("Area", "AREA")
    ld.energy = power
    ld.size = size
    ld.color = hexrgb(color)[:3]
    lo = bpy.data.objects.new("Area", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = Vector(loc)
    look_at(lo, target)
    return lo


def light_point(loc, power, color="#FFFFFF", radius=0.3):
    ld = bpy.data.lights.new("Point", "POINT")
    ld.energy = power
    ld.shadow_soft_size = radius
    ld.color = hexrgb(color)[:3]
    lo = bpy.data.objects.new("Point", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = Vector(loc)
    return lo


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# Materials ------------------------------------------------------------------------------------

def mat_plastic(name, color, rough=0.28, coat=0.6, sheen=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexrgb(color)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.08
    if sheen:
        b.inputs["Sheen Weight"].default_value = sheen
    return m


def mat_metal(name, color, rough=0.22):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexrgb(color)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    return m


def mat_emit(name, color, strength=6.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexrgb(color)
    b.inputs["Emission Color"].default_value = hexrgb(color)
    b.inputs["Emission Strength"].default_value = strength
    return m


def mat_glass(name, color, rough=0.02, ior=1.45):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexrgb(color)
    b.inputs["Transmission Weight"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    b.inputs["IOR"].default_value = ior
    return m


def assign(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    return obj


# Primitives ------------------------------------------------------------------------------------

def _finish(obj, mat, bevel=0.0, segments=4, smooth=True):
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth = True
        try:
            obj.data.set_sharp_from_angle(angle=math.radians(40))
        except Exception:
            pass
    if mat is not None:
        assign(obj, mat)
    return obj


def box(loc, size, mat, bevel=0.08, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(o, mat, bevel, 5)


def cyl(loc, radius, depth, mat, bevel=0.03, rot=(0, 0, 0), verts=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, mat, bevel, 4)


def sphere(loc, radius, mat, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=radius, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    return _finish(o, mat, 0, smooth=True)


def torus(loc, major, minor, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc, rotation=rot,
                                     major_segments=96, minor_segments=24)
    return _finish(bpy.context.active_object, mat, 0)


def plane(loc, size, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = (size[0], size[1], 1)
    return _finish(o, mat, 0, smooth=False)


def mat_golfball(name, color, rough=0.22, coat=0.9, dimples=7.5, emissive=0.0, color2=None):
    """Glossy plastic with real round dimples (Voronoi bump) for marketing balls."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    if color2:
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = -1
        mr.inputs["From Max"].default_value = 1
        ramp.color_ramp.elements[0].color = hexrgb(color2)
        ramp.color_ramp.elements[1].color = hexrgb(color)
        nt.links.new(tc.outputs["Object"], sep.inputs[0])
        nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
        nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
        if emissive:
            nt.links.new(ramp.outputs["Color"], b.inputs["Emission Color"])
    else:
        b.inputs["Base Color"].default_value = hexrgb(color)
        b.inputs["Emission Color"].default_value = hexrgb(color)
    b.inputs["Emission Strength"].default_value = emissive
    b.inputs["Roughness"].default_value = rough
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.05
    tc = nt.nodes.new("ShaderNodeTexCoord")
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "F1"
    vor.inputs["Scale"].default_value = dimples
    vor.inputs["Randomness"].default_value = 0.35
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = 0.5
    mr.inputs["To Min"].default_value = 0.0
    mr.inputs["To Max"].default_value = 1.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.55
    bump.inputs["Distance"].default_value = 0.05
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    nt.links.new(vor.outputs["Distance"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Coat Normal"])
    return m


def ball(loc, radius, mat):
    """Perfect sphere for marketing balls (use with mat_golfball)."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = (radius, radius, radius)
    for p in o.data.polygons:
        p.use_smooth = True
    return assign(o, mat)


def backdrop(color_floor, color_wall, size=80, curve=12, y=18, glow=0.6):
    """Seamless studio sweep: floor that curves up into a back wall (no horizon line)."""
    import bmesh
    me = bpy.data.meshes.new("Sweep")
    bm = bmesh.new()
    prof = []
    for i in range(0, 41):
        t = i / 40
        if t < 0.6:
            prof.append((-size + (y + size) * (t / 0.6), 0.0))
        else:
            a = (t - 0.6) / 0.4 * (math.pi / 2)
            prof.append((y + math.sin(a) * curve, curve - math.cos(a) * curve))
    prof.append((y + curve, size))
    rows = []
    for x in (-size, size):
        rows.append([bm.verts.new((x, py, pz)) for py, pz in prof])
    for i in range(len(prof) - 1):
        bm.faces.new((rows[0][i], rows[1][i], rows[1][i + 1], rows[0][i + 1]))
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("Sweep", me)
    bpy.context.scene.collection.objects.link(o)
    for p in o.data.polygons:
        p.use_smooth = True
    m = bpy.data.materials.new("SweepMat")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = curve * 1.2
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = hexrgb(color_floor)
    ramp.color_ramp.elements[1].color = hexrgb(color_wall)
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Emission Color"])
    # the wall glows softly so the gradient reads even where lights don't reach
    gl = nt.nodes.new("ShaderNodeMath")
    gl.operation = "MULTIPLY"
    gl.inputs[1].default_value = glow
    nt.links.new(mr.outputs["Result"], gl.inputs[0])
    nt.links.new(gl.outputs["Value"], b.inputs["Emission Strength"])
    b.inputs["Roughness"].default_value = 0.55
    o.data.materials.append(m)
    return o


_ball_mesh = None


def golf_ball(loc, radius, mat, rot=(0.3, 0.5, 0.2)):
    """The game's real 108-dimple mesh (assets/mesh/golfball.obj), radius in metres."""
    global _ball_mesh
    if _ball_mesh is None:
        bpy.ops.wm.obj_import(filepath=BALL_OBJ)
        src = bpy.context.selected_objects[0]
        _ball_mesh = src.data
        bpy.data.objects.remove(src)
    o = bpy.data.objects.new("GolfBall", _ball_mesh.copy())
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(loc)
    o.rotation_euler = rot
    s = radius / 0.75
    o.scale = (s, s, s)
    mod = o.modifiers.new("Sub", "SUBSURF")
    mod.levels = 1
    mod.render_levels = 2
    for p in o.data.polygons:
        p.use_smooth = True
    return assign(o, mat)


def avatar(loc, rot_z, shirt, pants, skin="#FFD8A8", pose="stand", scale=1.0, face=True):
    """Blocky R6-style avatar (feet at loc). pose: stand | run | cheer."""
    S = scale
    x, y, z = loc
    parts = []
    m_skin = mat_plastic("skin", skin, 0.45, 0.2)
    m_shirt = mat_plastic("shirt", shirt, 0.5, 0.3)
    m_pants = mat_plastic("pants", pants, 0.55, 0.2)
    leg_swing = {"run": 35, "stand": 0, "cheer": 0}[pose]
    arm_swing = {"run": 45, "stand": 0, "cheer": 160}[pose]

    def limb(px, pz, sx, sz, mat, swing):
        o = box((0, 0, 0), (0.5 * S, 0.5 * S, sz * S), mat, bevel=0.06 * S)
        # pivot at the top of the limb
        o.location = Vector((px * S, 0, pz * S - sz * S / 2))
        bpy.ops.object.empty_add(location=(px * S, 0, pz * S))
        piv = bpy.context.active_object
        o.parent = piv
        o.location = Vector((0, 0, -sz * S / 2))
        piv.rotation_euler = (math.radians(swing), 0, 0)
        return piv

    root = bpy.data.objects.new("Avatar", None)
    bpy.context.scene.collection.objects.link(root)
    torso = box((0, 0, 3.0 * S), (1.5 * S, 0.75 * S, 2.0 * S), m_shirt, bevel=0.08 * S)
    head = box((0, 0, 4.6 * S), (1.15 * S, 1.15 * S, 1.15 * S), m_skin, bevel=0.32 * S)
    parts += [torso, head]
    pivs = [limb(-0.375, 2.0, 0.5, 2.0, m_pants, leg_swing), limb(0.375, 2.0, 0.5, 2.0, m_pants, -leg_swing),
            limb(-1.0, 4.0, 0.5, 2.0, m_skin, -arm_swing if pose != "cheer" else arm_swing),
            limb(1.0, 4.0, 0.5, 2.0, m_skin, arm_swing)]
    if face:
        m_eye = mat_plastic("eye", "#14121C", 0.3, 0.2)
        for ex in (-0.22, 0.22):
            e = sphere((ex * S, -0.58 * S, 4.72 * S), 0.11 * S, m_eye, scale=(1, 0.5, 1.5))
            parts.append(e)
        mouth = torus((0, -0.57 * S, 4.42 * S), 0.18 * S, 0.035 * S, m_eye, rot=(math.radians(90), 0, 0))
        # keep the lower half of the torus as a smile
        bpy.ops.object.select_all(action="DESELECT")
        parts.append(mouth)
    for o in parts + pivs:
        o.parent = root
    root.location = Vector(loc)
    root.rotation_euler = (0, 0, rot_z)
    return root


def tube(points, radius, mat, resolution=24):
    """Smooth tube through 3D points (neon trails, lasers, rails)."""
    cu = bpy.data.curves.new("Tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 6
    cu.resolution_u = resolution
    sp = cu.splines.new("NURBS" if len(points) > 2 else "POLY")
    sp.points.add(len(points) - 1)
    for p, co in zip(sp.points, points):
        p.co = (co[0], co[1], co[2], 1.0)
    if len(points) > 2:
        sp.use_endpoint_u = True
        sp.order_u = min(4, len(points))
    o = bpy.data.objects.new("Tube", cu)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    return o


def text3d(body, loc, size, mat, extrude=0.08, rot=(math.radians(90), 0, 0), font_path=None):
    cu = bpy.data.curves.new("Txt", "FONT")
    cu.body = body
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = extrude * 0.35
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    fp = font_path or "/usr/share/fonts/opentype/inter/Inter-Black.otf"
    if os.path.exists(fp):
        cu.font = bpy.data.fonts.load(fp)
    o = bpy.data.objects.new("Txt", cu)
    bpy.context.scene.collection.objects.link(o)
    o.location = Vector(loc)
    o.rotation_euler = rot
    o.data.materials.append(mat)
    return o


def confetti(center, spread, n, colors, seed=1, size=0.12):
    import random
    rnd = random.Random(seed)
    mats = [mat_plastic(f"conf{i}", c, 0.35, 0.4) for i, c in enumerate(colors)]
    for _ in range(n):
        loc = (center[0] + rnd.gauss(0, spread[0]), center[1] + rnd.gauss(0, spread[1]), center[2] + rnd.gauss(0, spread[2]))
        rot = (rnd.uniform(0, 6.3), rnd.uniform(0, 6.3), rnd.uniform(0, 6.3))
        box(loc, (size, size * 0.45, 0.02), mats[rnd.randrange(len(mats))], bevel=0.0, rot=rot)


def spot(loc, target, power, color="#FFFFFF", angle=35, blend=0.4, radius=0.4):
    ld = bpy.data.lights.new("Spot", "SPOT")
    ld.energy = power
    ld.spot_size = math.radians(angle)
    ld.spot_blend = blend
    ld.shadow_soft_size = radius
    ld.color = hexrgb(color)[:3]
    lo = bpy.data.objects.new("Spot", ld)
    bpy.context.scene.collection.objects.link(lo)
    lo.location = Vector(loc)
    look_at(lo, target)
    return lo
