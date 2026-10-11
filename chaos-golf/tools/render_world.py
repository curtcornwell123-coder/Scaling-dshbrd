"""Render the code-built Roblox world (lobby + courses) headlessly with Blender/Cycles.

Input is a world dump from tests/boot/dump.sh:

    tests/boot/dump.sh <luau> <globalTypes.d.luau> world.txt [all|lobby|courses]

Run with a Python that has `bpy` (Blender as a module) or with `blender -b -P`:

    python tools/render_world.py world.txt                      # every default view
    python tools/render_world.py world.txt --views lobby        # all lobby views
    python tools/render_world.py world.txt --views spawn,fountain --quick
    python tools/render_world.py world.txt --list               # list view names
    python tools/render_world.py world.txt --views "lobby:peek=10,8,-40>0,4,0@60"

A custom view is `scene:name=x,y,z>tx,ty,tz[@fov]` in Roblox coordinates (Y up).

Conventions
  * Roblox is right-handed Y-up; Blender is right-handed Z-up. A Roblox point
    (x, y, z) maps to Blender (x, -z, y) (a +90 degree rotation about X), applied to
    positions and to the part's Right/Up/Back axes alike, so winding is preserved.
  * Part shapes: Block, Ball, Cylinder (axis = local X), WedgePart (slope faces
    Front/-Z and Top, tall side at the Back), CornerWedgePart, Truss/Mesh as boxes.
  * The look is an approximation of Roblox Future lighting: sun + sky, an
    "Ambient" term on every surface (Lighting.Ambient lights interiors evenly),
    neon that glows but does not light its surroundings, PointLight/SurfaceLight
    as Cycles point/spot lights, SurfaceGui text and gradients drawn on their faces.
"""
import argparse
import math
import os
import sys
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
DEFAULT_OUT = os.path.join(ROOT, "docs", "renders")

# Look tuning ----------------------------------------------------------------------

AMBIENT = 0.16  # Lighting.Ambient stand-in (fraction of albedo added on camera/glossy rays)
NEON_STRENGTH = 2.2
NEON_GI = 0.08  # how much neon lights its surroundings (Roblox: none)
SUN_STRENGTH = 2.1
SUN_DIR = (-0.35, 0.85, 0.40)  # Roblox coords, toward the sun (ClockTime 13.5)
SKY_LIGHT = 0.45
LIGHT_K = 4.0  # Cycles watts per (Brightness * Range^2)
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
]


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def rb(v):
    """Roblox (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def rb_np(a):
    return np.stack([a[..., 0], -a[..., 2], a[..., 1]], axis=-1)


# Dump parsing ----------------------------------------------------------------------

def _v3(s):
    return tuple(float(x) for x in s.split(","))


class Scene:
    def __init__(self, name):
        self.name = name
        self.parts = []
        self.lights = []
        self.texts = []
        self.grads = []
        self.holes = []
        self.origin = None
        self.by_id = {}


def parse_dump(path):
    scenes = {}
    cur = None
    last = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.startswith("@"):
                continue
            f = line.split("|")
            tag = f[0]
            if tag == "@SCENE":
                cur = Scene(f[1])
                scenes[cur.name] = cur
            elif cur is None:
                continue
            elif tag == "@P":
                last = {
                    "cls": f[1], "shape": f[2], "pos": _v3(f[3]), "right": _v3(f[4]), "up": _v3(f[5]),
                    "back": _v3(f[6]), "size": _v3(f[7]), "rgb": _v3(f[8]), "mat": f[9],
                    "t": float(f[10]), "shadow": f[11] == "true", "name": f[12] if len(f) > 12 else "",
                }
                cur.parts.append(last)
            elif tag == "@I":
                if last is not None:
                    cur.by_id[int(f[1])] = last
            elif tag == "@L":
                cur.lights.append({
                    "cls": f[1], "pos": _v3(f[2]), "rgb": _v3(f[3]), "brightness": float(f[4]),
                    "range": float(f[5]), "face": f[6], "up": _v3(f[7]), "back": _v3(f[8]),
                })
            elif tag == "@T":
                cur.texts.append({"id": int(f[1]), "face": f[2], "rgb": _v3(f[3]), "font": f[4],
                                  "text": "|".join(f[5:]).replace("\\n", "\n")})
            elif tag == "@G":
                cur.grads.append({"id": int(f[1]), "face": f[2], "c0": _v3(f[3]), "c1": _v3(f[4]),
                                  "rot": float(f[5])})
            elif tag == "@ORIGIN":
                cur.origin = _v3(f[1])
            elif tag == "@HOLE":
                cur.holes.append({"i": int(f[1]), "tee": _v3(f[2]), "cup": _v3(f[3]), "pos": _v3(f[4]),
                                  "right": _v3(f[5]), "up": _v3(f[6]), "back": _v3(f[7])})
    return scenes


# Unit shape templates (Roblox local coords, extents +-0.5) --------------------------

def _orient(verts, faces):
    """Make every face wind counter-clockwise seen from outside (templates are convex)."""
    centre = verts.mean(axis=0)
    out = []
    for f in faces:
        p = verts[list(f)]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        if np.linalg.norm(n) < 1e-9 and len(f) > 3:
            n = np.cross(p[2] - p[0], p[3] - p[0])
        if np.dot(n, p.mean(axis=0) - centre) < 0:
            f = list(reversed(f))
        out.append(list(f))
    return out


def _template(verts, faces, smooth):
    verts = np.asarray(verts, dtype=np.float32)
    faces = _orient(verts, faces)
    return {"v": verts, "f": faces, "smooth": np.asarray(smooth, dtype=bool)}


def tmpl_box():
    h = 0.5
    quads = [
        [(h, -h, -h), (h, h, -h), (h, h, h), (h, -h, h)],
        [(-h, -h, -h), (-h, -h, h), (-h, h, h), (-h, h, -h)],
        [(-h, h, -h), (-h, h, h), (h, h, h), (h, h, -h)],
        [(-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)],
        [(-h, -h, h), (h, -h, h), (h, h, h), (-h, h, h)],
        [(-h, -h, -h), (-h, h, -h), (h, h, -h), (h, -h, -h)],
    ]
    verts, faces = [], []
    for q in quads:
        faces.append(list(range(len(verts), len(verts) + 4)))
        verts.extend(q)
    return _template(verts, faces, [False] * 6)


def tmpl_wedge():
    h = 0.5
    b0, b1, b2, b3 = (-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)
    t0, t1 = (-h, h, h), (h, h, h)
    polys = [[b0, b1, b2, b3], [b3, b2, t1, t0], [b0, t0, t1, b1], [b0, b3, t0], [b1, t1, b2]]
    verts, faces = [], []
    for p in polys:
        faces.append(list(range(len(verts), len(verts) + len(p))))
        verts.extend(p)
    return _template(verts, faces, [False] * len(faces))


def tmpl_cornerwedge():
    # Bottom square plus one apex above the (+X, -Z) corner.
    h = 0.5
    b0, b1, b2, b3 = (-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h)
    a = (h, h, -h)
    polys = [[b0, b1, b2, b3], [b1, a, b2], [b0, a, b1], [b2, a, b3], [b3, a, b0]]
    verts, faces = [], []
    for p in polys:
        faces.append(list(range(len(verts), len(verts) + len(p))))
        verts.extend(p)
    return _template(verts, faces, [False] * len(faces))


def tmpl_cylinder(n=28):
    th = np.linspace(0, 2 * math.pi, n, endpoint=False)
    c, s = 0.5 * np.cos(th), 0.5 * np.sin(th)
    verts = []
    for x in (-0.5, 0.5):  # side ring (smooth)
        verts.extend([(x, c[k], s[k]) for k in range(n)])
    for x in (-0.5, 0.5):  # caps (flat, separate verts)
        verts.extend([(x, c[k], s[k]) for k in range(n)])
    faces, smooth = [], []
    for k in range(n):
        k1 = (k + 1) % n
        faces.append([k, k1, n + k1, n + k])
        smooth.append(True)
    faces.append([2 * n + k for k in range(n)])
    faces.append([3 * n + k for k in range(n)])
    smooth += [False, False]
    return _template(verts, faces, smooth)


def tmpl_ball(nseg=24, nring=12):
    verts = [(0, 0.5, 0)]
    for r in range(1, nring):
        phi = math.pi * r / nring
        for k in range(nseg):
            th = 2 * math.pi * k / nseg
            verts.append((0.5 * math.sin(phi) * math.cos(th), 0.5 * math.cos(phi), 0.5 * math.sin(phi) * math.sin(th)))
    verts.append((0, -0.5, 0))
    bottom = len(verts) - 1
    faces = []
    for k in range(nseg):
        faces.append([0, 1 + k, 1 + (k + 1) % nseg])
    for r in range(nring - 2):
        a, b = 1 + r * nseg, 1 + (r + 1) * nseg
        for k in range(nseg):
            k1 = (k + 1) % nseg
            faces.append([a + k, b + k, b + k1, a + k1])
    last = 1 + (nring - 2) * nseg
    for k in range(nseg):
        faces.append([last + k, bottom, last + (k + 1) % nseg])
    return _template(verts, faces, [True] * len(faces))


TEMPLATES = {}


def template_for(part):
    cls, shape = part["cls"], part["shape"]
    if cls == "WedgePart":
        key = "wedge"
    elif cls == "CornerWedgePart":
        key = "cornerwedge"
    elif shape == "Ball":
        key = "ball"
    elif shape == "Cylinder":
        key = "cylinder"
    else:
        key = "box"
    if key not in TEMPLATES:
        TEMPLATES[key] = {"box": tmpl_box, "wedge": tmpl_wedge, "cornerwedge": tmpl_cornerwedge,
                          "cylinder": tmpl_cylinder, "ball": tmpl_ball}[key]()
    return key, TEMPLATES[key]


# Materials ----------------------------------------------------------------------------

def mat_class(name):
    if name == "Neon":
        return "neon"
    if name == "Glass":
        return "glass"
    if name == "ForceField":
        return "forcefield"
    if name in ("Metal", "DiamondPlate", "Foil", "CorrodedMetal"):
        return "metal"
    if name in ("Ice", "Glacier"):
        return "ice"
    if name == "SmoothPlastic":
        return "smooth"
    if name == "Plastic":
        return "plastic"
    return "rough"


def _gate(nt, extra=0.0):
    """1 on camera/glossy/transmission rays, `extra` on diffuse/shadow rays."""
    lp = nt.nodes.new("ShaderNodeLightPath")
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MAXIMUM"
    nt.links.new(lp.outputs["Is Camera Ray"], m1.inputs[0])
    nt.links.new(lp.outputs["Is Glossy Ray"], m1.inputs[1])
    m2 = nt.nodes.new("ShaderNodeMath")
    m2.operation = "MAXIMUM"
    nt.links.new(m1.outputs[0], m2.inputs[0])
    nt.links.new(lp.outputs["Is Transmission Ray"], m2.inputs[1])
    if extra <= 0:
        return m2.outputs[0]
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = extra
    mr.inputs["To Max"].default_value = 1.0
    nt.links.new(m2.outputs[0], mr.inputs["Value"])
    return mr.outputs["Result"]


def _mul(nt, a, b):
    m = nt.nodes.new("ShaderNodeMath")
    m.operation = "MULTIPLY"
    for i, x in enumerate((a, b)):
        if isinstance(x, (int, float)):
            m.inputs[i].default_value = x
        else:
            nt.links.new(x, m.inputs[i])
    return m.outputs[0]


def _alpha_mix(nt, shader, alpha):
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha, mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(shader, mix.inputs[2])
    return mix.outputs[0]


def make_material(cls, attr="col"):
    m = bpy.data.materials.new("rbx_" + cls)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = attr
    col, alpha = at.outputs["Color"], at.outputs["Alpha"]
    m.cycles.emission_sampling = "NONE"
    if cls == "neon":
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(col, em.inputs["Color"])
        nt.links.new(_mul(nt, _gate(nt, NEON_GI), NEON_STRENGTH), em.inputs["Strength"])
        shader = em.outputs[0]
    elif cls == "glass":
        bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(col, bs.inputs["Base Color"])
        bs.inputs["Roughness"].default_value = 0.04
        bs.inputs["Specular IOR Level"].default_value = 1.0
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        tint = nt.nodes.new("ShaderNodeMix")
        tint.data_type = "RGBA"
        tint.inputs["Factor"].default_value = 0.35
        tint.inputs["A"].default_value = (1, 1, 1, 1)
        nt.links.new(col, tint.inputs["B"])
        nt.links.new(tint.outputs["Result"], tr.inputs["Color"])
        mix = nt.nodes.new("ShaderNodeMixShader")
        # Roblox glass reads more opaque than its Transparency suggests.
        fac = _mul(nt, alpha, 0.55)
        nt.links.new(fac, mix.inputs["Fac"])
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(bs.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])
        return m
    elif cls == "forcefield":
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.35
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(col, em.inputs["Color"])
        em.inputs["Strength"].default_value = 1.6
        fac = nt.nodes.new("ShaderNodeMapRange")
        fac.inputs["To Min"].default_value = 0.15
        fac.inputs["To Max"].default_value = 0.9
        nt.links.new(lw.outputs["Facing"], fac.inputs["Value"])
        a = _mul(nt, fac.outputs["Result"], alpha)
        nt.links.new(_alpha_mix(nt, em.outputs[0], a), out.inputs["Surface"])
        return m
    else:
        bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(col, bs.inputs["Base Color"])
        rough = {"smooth": 0.42, "plastic": 0.6, "metal": 0.3, "ice": 0.12, "rough": 0.8}[cls]
        bs.inputs["Roughness"].default_value = rough
        bs.inputs["Specular IOR Level"].default_value = 0.45 if cls != "rough" else 0.25
        if cls == "metal":
            bs.inputs["Metallic"].default_value = 0.85
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(col, em.inputs["Color"])
        nt.links.new(_mul(nt, _gate(nt), AMBIENT), em.inputs["Strength"])
        add = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(bs.outputs[0], add.inputs[0])
        nt.links.new(em.outputs[0], add.inputs[1])
        shader = add.outputs[0]
    nt.links.new(_alpha_mix(nt, shader, alpha), out.inputs["Surface"])
    return m


# Geometry ------------------------------------------------------------------------------

def build_parts(parts, hide):
    """Merge parts into one mesh per (material class, casts shadow)."""
    groups = {}
    skipped = 0
    for p in parts:
        if p["t"] >= 0.98 or any(h in p["name"] for h in hide):
            skipped += 1
            continue
        key = (mat_class(p["mat"]), p["shadow"])
        groups.setdefault(key, []).append(p)
    mats = {}
    for (cls, shadow), plist in groups.items():
        by_shape = {}
        for p in plist:
            k, _ = template_for(p)
            by_shape.setdefault(k, []).append(p)
        co_all, loops_all, starts_all, cols_all, smooth_all = [], [], [], [], []
        vbase = lbase = 0
        for k, ps in by_shape.items():
            t = TEMPLATES[k]
            P = len(ps)
            pos = np.array([p["pos"] for p in ps], dtype=np.float64)
            R = np.array([p["right"] for p in ps])
            U = np.array([p["up"] for p in ps])
            B = np.array([p["back"] for p in ps])
            S = np.array([p["size"] for p in ps])
            if k == "ball":
                S = np.repeat(S.min(axis=1, keepdims=True), 3, axis=1)
            elif k == "cylinder":
                d = np.minimum(S[:, 1], S[:, 2])
                S = np.stack([S[:, 0], d, d], axis=1)
            tv = t["v"].astype(np.float64)
            w = (pos[:, None, :]
                 + (tv[None, :, 0:1] * S[:, None, 0:1]) * R[:, None, :]
                 + (tv[None, :, 1:2] * S[:, None, 1:2]) * U[:, None, :]
                 + (tv[None, :, 2:3] * S[:, None, 2:3]) * B[:, None, :])
            co_all.append(rb_np(w).reshape(-1, 3))
            nv = len(tv)
            flat = np.concatenate([np.asarray(f) for f in t["f"]])
            lens = np.array([len(f) for f in t["f"]])
            fstarts = np.concatenate([[0], np.cumsum(lens)[:-1]])
            nl = len(flat)
            loops_all.append((flat[None, :] + (np.arange(P) * nv + vbase)[:, None]).ravel())
            starts_all.append((fstarts[None, :] + (np.arange(P) * nl + lbase)[:, None]).ravel())
            rgb = srgb_to_linear(np.array([p["rgb"] for p in ps]))
            a = 1.0 - np.array([p["t"] for p in ps], dtype=np.float32)
            rgba = np.concatenate([rgb, a[:, None]], axis=1)
            cols_all.append(np.repeat(rgba, len(t["f"]), axis=0))
            smooth_all.append(np.tile(t["smooth"], P))
            vbase += P * nv
            lbase += P * nl
        co = np.concatenate(co_all).astype(np.float32)
        loops = np.concatenate(loops_all).astype(np.int32)
        starts = np.concatenate(starts_all).astype(np.int32)
        me = bpy.data.meshes.new(f"{cls}_{'s' if shadow else 'n'}")
        me.vertices.add(len(co))
        me.vertices.foreach_set("co", co.ravel())
        me.loops.add(len(loops))
        me.loops.foreach_set("vertex_index", loops)
        me.polygons.add(len(starts))
        me.polygons.foreach_set("loop_start", starts)
        me.update(calc_edges=True)
        ca = me.attributes.new("col", "FLOAT_COLOR", "FACE")
        ca.data.foreach_set("color", np.concatenate(cols_all).astype(np.float32).ravel())
        sh = me.attributes.new("sharp_face", "BOOLEAN", "FACE")
        sh.data.foreach_set("value", ~np.concatenate(smooth_all))
        if cls not in mats:
            mats[cls] = make_material(cls)
        me.materials.append(mats[cls])
        ob = bpy.data.objects.new(me.name, me)
        ob.visible_shadow = shadow and cls not in ("neon", "glass", "forcefield")
        bpy.context.scene.collection.objects.link(ob)
    return sum(len(v) for v in groups.values()), skipped


def face_frame(part, face):
    """(centre, text-right, text-up, normal, width, height) of a part face, Roblox coords."""
    pos = np.array(part["pos"])
    R, U, B = (np.array(part[k]) for k in ("right", "up", "back"))
    sx, sy, sz = part["size"]
    if face == "Front":
        return pos - B * sz / 2, -R, U, -B, sx, sy
    if face == "Back":
        return pos + B * sz / 2, R, U, B, sx, sy
    if face == "Top":
        return pos + U * sy / 2, -R, B, U, sx, sz
    if face == "Bottom":
        return pos - U * sy / 2, -R, -B, -U, sx, sz
    if face == "Right":
        return pos + R * sx / 2, -B, U, R, sz, sy
    return pos - R * sx / 2, B, U, -R, sz, sy  # Left


def build_gradients(scene):
    if not scene.grads:
        return
    co, faces, cols = [], [], []
    for g in scene.grads:
        part = scene.by_id.get(g["id"])
        if not part:
            continue
        c, r, u, n, w, h = face_frame(part, g["face"])
        c = c + n * 0.02
        c0 = list(srgb_to_linear(g["c0"])) + [1.0]
        c1 = list(srgb_to_linear(g["c1"])) + [1.0]
        # rotation 90: colour 0 at the top, colour 1 at the bottom; 0: left -> right.
        top, bot = (c0, c1) if abs(g["rot"] - 90) < 45 else (c1, c0)
        corners = [c - r * w / 2 - u * h / 2, c + r * w / 2 - u * h / 2, c + r * w / 2 + u * h / 2, c - r * w / 2 + u * h / 2]
        if abs(g["rot"] - 90) < 45 or abs(g["rot"] - 270) < 45:
            cc = [bot, bot, top, top]
        else:
            cc = [top, bot, bot, top]
        base = len(co)
        co.extend(rb(x) for x in corners)
        faces.append([base, base + 1, base + 2, base + 3])
        cols.extend(cc)
    me = bpy.data.meshes.new("gradients")
    me.from_pydata([tuple(v) for v in co], [], faces)
    ca = me.attributes.new("gcol", "FLOAT_COLOR", "POINT")
    ca.data.foreach_set("color", np.array(cols, dtype=np.float32).ravel())
    me.materials.append(make_material("smooth", attr="gcol"))
    ob = bpy.data.objects.new("gradients", me)
    ob.visible_shadow = False
    bpy.context.scene.collection.objects.link(ob)


_FONT = None
_TEXT_MATS = {}


def build_texts(scene):
    global _FONT
    if _FONT is None or _FONT.name not in bpy.data.fonts:
        _FONT = None
        for path in FONT_CANDIDATES:
            if os.path.exists(path):
                _FONT = bpy.data.fonts.load(path)
                break
    _TEXT_MATS.clear()
    objs = []
    for t in scene.texts:
        part = scene.by_id.get(t["id"])
        if not part:
            continue
        c, r, u, n, w, h = face_frame(part, t["face"])
        cu = bpy.data.curves.new("txt", "FONT")
        cu.body = t["text"]
        if _FONT:
            cu.font = _FONT
        cu.align_x = "CENTER"
        cu.align_y = "CENTER"
        cu.size = 1.0
        key = tuple(round(x, 3) for x in t["rgb"])
        if key not in _TEXT_MATS:
            m = bpy.data.materials.new("text")
            m.use_nodes = True
            nt = m.node_tree
            nt.nodes.clear()
            em = nt.nodes.new("ShaderNodeEmission")
            em.inputs["Color"].default_value = (*srgb_to_linear(t["rgb"]), 1)
            em.inputs["Strength"].default_value = 1.0
            o = nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(em.outputs[0], o.inputs["Surface"])
            m.cycles.emission_sampling = "NONE"
            _TEXT_MATS[key] = m
        cu.materials.append(_TEXT_MATS[key])
        ob = bpy.data.objects.new("txt", cu)
        ob.visible_shadow = False
        bpy.context.scene.collection.objects.link(ob)
        objs.append((ob, c, r, u, n, w, h))
    bpy.context.view_layer.update()
    for ob, c, r, u, n, w, h in objs:
        dx, dy = max(ob.dimensions.x, 1e-3), max(ob.dimensions.y, 1e-3)
        # TextScaled inside 4%/8% padding, capped at ~100 px glyphs.
        cap = 5.0 if w > 20 else 3.4
        s = min(w * 0.92 / dx, h * 0.84 / dy, cap)
        rr, uu, nn = rb(r), rb(u), rb(n)
        m = Matrix((rr, uu, nn)).transposed().to_4x4()
        m.translation = rb(c + n * 0.03)
        ob.matrix_world = m @ Matrix.Scale(s, 4)


def build_lights(scene, scale=1.0):
    for L in scene.lights:
        rgb = tuple(srgb_to_linear(L["rgb"]))
        rng = max(L["range"], 1.0)
        power = LIGHT_K * L["brightness"] * rng * rng * scale
        if L["cls"] == "PointLight":
            ld = bpy.data.lights.new("pl", "POINT")
            ld.shadow_soft_size = min(1.5, 0.1 * rng)
        else:
            ld = bpy.data.lights.new("sl", "SPOT")
            ld.spot_size = math.radians(150)
            ld.spot_blend = 0.6
            ld.shadow_soft_size = min(2.0, 0.1 * rng)
        ld.energy = power
        ld.color = rgb
        ld.use_shadow = True
        # Soften the inverse-square hot spot right next to the light.
        ld.use_nodes = True
        nt = ld.node_tree
        fo = nt.nodes.new("ShaderNodeLightFalloff")
        fo.inputs["Strength"].default_value = 1.0
        fo.inputs["Smooth"].default_value = (rng * 0.2) ** 2
        em = nt.nodes.get("Emission")
        if em:
            nt.links.new(fo.outputs["Quadratic"], em.inputs["Strength"])
        ob = bpy.data.objects.new(ld.name, ld)
        ob.location = rb(L["pos"])
        if L["cls"] != "PointLight":
            up, back = np.array(L["up"]), np.array(L["back"])
            right = np.cross(up, back)
            d = {"Bottom": -up, "Top": up, "Front": -back, "Back": back, "Right": right, "Left": -right}.get(L["face"], -up)
            dz = rb(d).normalized()
            ob.rotation_euler = (-dz).to_track_quat("Z", "Y").to_euler()
        bpy.context.scene.collection.objects.link(ob)


# Scene setup -------------------------------------------------------------------------------

def setup_render(args):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.threads_mode = "FIXED"
    sc.render.threads = args.threads
    sc.cycles.samples = args.samples
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.03
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 4
    sc.cycles.transparent_max_bounces = 24
    sc.cycles.caustics_reflective = False
    sc.cycles.caustics_refractive = False
    sc.cycles.sample_clamp_indirect = 4.0
    sc.render.resolution_x, sc.render.resolution_y = args.res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.exposure = 0.0
    world = bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    # Sky: horizon -> zenith gradient on camera rays, a flat soft sky for lighting.
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*srgb_to_linear((0.80, 0.88, 0.97)), 1)
    ramp.color_ramp.elements[1].position = 0.6
    ramp.color_ramp.elements[1].color = (*srgb_to_linear((0.36, 0.58, 0.92)), 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    bg_cam = nt.nodes.new("ShaderNodeBackground")
    nt.links.new(ramp.outputs["Color"], bg_cam.inputs["Color"])
    bg_cam.inputs["Strength"].default_value = 1.0
    bg_amb = nt.nodes.new("ShaderNodeBackground")
    bg_amb.inputs["Color"].default_value = (*srgb_to_linear((0.70, 0.78, 0.92)), 1)
    bg_amb.inputs["Strength"].default_value = SKY_LIGHT
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(bg_amb.outputs[0], mix.inputs[1])
    nt.links.new(bg_cam.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = SUN_STRENGTH
    sun.angle = math.radians(1.5)
    sun.color = (1.0, 0.97, 0.92)
    so = bpy.data.objects.new("Sun", sun)
    d = rb(SUN_DIR).normalized()
    so.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    sc.collection.objects.link(so)
    return sc


def set_camera(view):
    sc = bpy.context.scene
    cd = bpy.data.cameras.new("Cam")
    cd.sensor_fit = "VERTICAL"
    cd.angle_y = math.radians(view["fov"])
    cd.clip_start = 0.3
    cd.clip_end = 6000
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    pos = rb(view["pos"])
    look = rb(view["look"]).normalized()
    up_hint = Vector((0, 0, 1)) if abs(look.z) < 0.99 else Vector((0, 1, 0))
    right = look.cross(up_hint).normalized()
    up = right.cross(look).normalized()
    m = Matrix((right, up, -look)).transposed().to_4x4()
    m.translation = pos
    cam.matrix_world = m
    sc.camera = cam
    return cam


def bloom(path, strength=0.35, threshold=0.78):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    rgb = px[..., :3]
    lum = rgb.max(axis=2)
    wgt = np.clip((lum - threshold) / (1 - threshold), 0, 1)[..., None]
    bright = rgb * wgt
    f = 4
    hh, ww = h // f, w // f
    small = bright[: hh * f, : ww * f].reshape(hh, f, ww, f, 3).mean(axis=(1, 3))

    def box(a, r, axis):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        n = a.shape[axis]
        return (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) / (2 * r + 1)

    acc = np.zeros_like(small)
    for r, wt in ((2, 0.5), (6, 0.35), (14, 0.25)):
        b = small
        for _ in range(2):
            b = box(box(b, r, 0), r, 1)
        acc += b * wt
    big = np.repeat(np.repeat(acc, f, axis=0), f, axis=1)
    out = rgb.copy()
    out[: hh * f, : ww * f] += strength * big
    px[..., :3] = np.clip(out, 0, 1)
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# Views ------------------------------------------------------------------------------------

def _cam(pos, target, fov=70.0, hide=()):
    p, t = np.array(pos, float), np.array(target, float)
    return {"pos": tuple(p), "look": tuple(t - p), "fov": fov, "hide": tuple(hide)}


LOBBY_VIEWS = {
    # Inside the dome, high over the north wall, looking across the whole hub.
    "lobby_overview": _cam((0, 82, -58), (0, 0, 12), 78),
    # Outside, high aerial of the whole complex (dome, rooms, roofs).
    "lobby_aerial": _cam((150, 230, 210), (0, 10, 0), 50),
    # Spawn POV: standing on the spawn pad (0,3,-25), facing south toward the fountain.
    "spawn": _cam((0, 8, -25), (0, 5, 10), 70),
    # Default third-person camera just after spawning (behind and above the character).
    "spawn_3p": _cam((0, 9.5, -38), (0, 5, -10), 70),
    "fountain": _cam((19, 9, -21), (0, 4.5, 0), 60),
    "arch_north": _cam((0, 10, -40), (0, 14, -88), 70),
    "room_north": _cam((0, 9, -90), (0, 8, -150), 80),
    "room_east": _cam((90, 9, 0), (150, 8, 0), 80),
    "room_south": _cam((0, 9, 90), (0, 8, 150), 80),
    "room_west": _cam((-90, 9, 0), (-150, 8, 0), 80),
    "room_north_back": _cam((0, 15, -148), (0, 7, -92), 80),
    "room_east_back": _cam((148, 15, 0), (92, 7, 0), 80),
    "room_south_back": _cam((0, 15, 148), (0, 7, 92), 80),
    "room_west_back": _cam((-148, 15, 0), (-92, 7, 0), 80),
}

DEFAULT_LOBBY = ["lobby_overview", "lobby_aerial", "spawn", "spawn_3p", "fountain", "room_north", "room_east",
                 "room_south", "room_west", "room_east_back", "room_north_back"]


def course_views(scene):
    """Gameplay hole camera for hole 1 + a wide hall shot (and every hole on request)."""
    views = {}
    tag = scene.name.replace("course_", "")
    for h in scene.holes:
        look = -np.array(h["back"])
        views[f"hole_{tag}_{h['i']}"] = {"pos": h["pos"], "look": tuple(look), "fov": 70.0, "hide": ()}
    if scene.origin and scene.holes:
        ox, oy, oz = scene.origin
        n = len(scene.holes)
        x0 = ox - 65 - 26
        views[f"hall_{tag}"] = _cam((x0 + 6, oy + 40, oz + 86), (ox + 130 * min(2, n - 1), oy - 8, oz - 10), 75)
    return views


def all_views(scenes):
    out = {}
    if "lobby" in scenes:
        for k, v in LOBBY_VIEWS.items():
            out[k] = ("lobby", v)
    for name, s in scenes.items():
        if name == "lobby":
            continue
        for k, v in course_views(s).items():
            out[k] = (name, v)
    return out


def default_views(scenes):
    names = [v for v in DEFAULT_LOBBY if "lobby" in scenes]
    for name, s in scenes.items():
        if name.startswith("course_") or name == "tutorial":
            tag = name.replace("course_", "")
            names.append(f"hole_{tag}_1")
            if name != "tutorial":
                names.append(f"hall_{tag}")
    return names


def parse_custom(spec):
    # scene:name=x,y,z>tx,ty,tz[@fov]
    scene, rest = spec.split(":", 1)
    name, geo = rest.split("=", 1)
    fov = 70.0
    if "@" in geo:
        geo, f = geo.split("@")
        fov = float(f)
    a, b = geo.split(">")
    return name, (scene, _cam(_v3(a), _v3(b), fov))


# Main ---------------------------------------------------------------------------------------

def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dump")
    ap.add_argument("--views", default="default", help="comma list: view names, 'default', 'all', 'lobby', 'courses', or custom specs")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--quick", action="store_true", help="480x270, 6 samples")
    ap.add_argument("--samples", type=int, default=None)
    ap.add_argument("--res", default=None, help="WxH (default 960x540)")
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--hide", default="", help="comma list of name substrings to leave out")
    ap.add_argument("--no-bloom", action="store_true")
    ap.add_argument("--no-text", action="store_true")
    ap.add_argument("--suffix", default="", help="appended to output file names")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)
    args.samples = args.samples or (6 if args.quick else 16)
    args.res = tuple(int(x) for x in (args.res or ("480x270" if args.quick else "960x540")).split("x"))

    scenes = parse_dump(args.dump)
    views = all_views(scenes)
    if args.list:
        for k, (s, v) in views.items():
            print(f"{k:28s} {s}")
        return
    wanted = []
    for tok in [t for t in args.views.split(",") if t]:
        if ":" in tok and "=" in tok:
            name, sv = parse_custom(tok)
            views[name] = sv
            wanted.append(name)
        elif tok == "default":
            wanted += default_views(scenes)
        elif tok == "all":
            wanted += list(views)
        elif tok == "lobby":
            wanted += [k for k in DEFAULT_LOBBY if k in views] + [k for k in LOBBY_VIEWS if k not in DEFAULT_LOBBY]
        elif tok == "courses":
            wanted += [k for k in default_views(scenes) if views[k][0] != "lobby"]
        elif tok in views:
            wanted.append(tok)
        else:
            sys.exit(f"unknown view {tok!r} (use --list)")
    wanted = list(dict.fromkeys(wanted))
    os.makedirs(args.out, exist_ok=True)
    hide = [h for h in args.hide.split(",") if h]

    by_scene = {}
    for k in wanted:
        by_scene.setdefault(views[k][0], []).append(k)
    for sname, names in by_scene.items():
        s = scenes[sname]
        t0 = time.time()
        setup_render(args)
        TEMPLATES.clear()
        n, skipped = build_parts(s.parts, hide)
        build_gradients(s)
        if not args.no_text:
            build_texts(s)
        build_lights(s)
        print(f"[{sname}] {n} parts ({skipped} hidden), {len(s.lights)} lights, {len(s.texts)} texts, built in {time.time() - t0:.1f}s", flush=True)
        for k in names:
            v = views[k][1]
            hidden = []
            if v.get("hide"):
                for ob in bpy.context.scene.objects:
                    if any(h in ob.name for h in v["hide"]):
                        ob.hide_render = True
                        hidden.append(ob)
            cam = set_camera(v)
            path = os.path.join(args.out, f"{k}{args.suffix}.png")
            t1 = time.time()
            bpy.context.scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            if not args.no_bloom:
                bloom(path)
            print(f"  {k}: {path} ({time.time() - t1:.1f}s)", flush=True)
            bpy.data.objects.remove(cam)
            for ob in hidden:
                ob.hide_render = False


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    main(argv)
