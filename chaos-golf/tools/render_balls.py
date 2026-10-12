"""Render the ball collection (real dimpled mesh + every print plate) with Blender/Cycles.

Input is a dump from tests/boot/dump_balls.sh (one ball per skin, printed by BallPrints):

    tests/boot/dump_balls.sh <luau> <globalTypes.d.luau> balls.txt
    python tools/render_balls.py balls.txt                       # lineup sheets + close-ups
    python tools/render_balls.py balls.txt --only corny_studio --views front,back,left,right

Plates are rasterised from their dumped GUI (TextLabels, Frames with corners, strokes and
gradients) into alpha textures and placed exactly where the game welds them. Materials are
approximations of Roblox Future lighting (SmoothPlastic gloss, Foil, Glass shell, neon core).
"""
import argparse
import math
import os
import tempfile

import bpy
import numpy as np
from mathutils import Matrix, Vector
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
MESH = os.path.join(ROOT, "assets", "mesh", "golfball.obj")
OUT = os.path.join(ROOT, "docs", "renders", "balls")

FONTS = {
    "GothamBlack": "/usr/share/fonts/opentype/inter/Inter-Black.otf",
    "GothamBold": "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "GothamMedium": "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
    "Michroma": "/usr/share/fonts/opentype/inter/InterDisplay-ExtraBold.otf",
}
SYMBOL_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SS = 6  # supersampling for plate textures


def v3(s):
    return [float(x) for x in s.split(",")]


def rb(v):
    """Roblox (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def srgb_to_linear(c):
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


# Dump ---------------------------------------------------------------------------------

def parse(path):
    balls = {}
    order = []
    plate = None
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("|")
        tag = f[0]
        if tag == "@BALL":
            b = {
                "i": int(f[1]), "id": f[2], "name": f[3],
                "pos": v3(f[4]), "d": float(f[8]), "color": v3(f[9]), "mat": f[10],
                "tr": float(f[11]), "refl": float(f[12]),
                "core": None, "rings": [], "plates": [],
            }
            balls[b["i"]] = b
            order.append(b)
        elif tag == "@CORE":
            balls[int(f[1])]["core"] = {"pos": v3(f[2]), "d": float(f[3]), "color": v3(f[4])}
        elif tag == "@RING":
            balls[int(f[1])]["rings"].append({"cf": [v3(f[2]), v3(f[3]), v3(f[4]), v3(f[5])], "size": v3(f[6]), "color": v3(f[7]), "mat": f[8]})
        elif tag == "@PLATE":
            plate = {"cf": [v3(f[2]), v3(f[3]), v3(f[4]), v3(f[5])], "wh": v3(f[6]), "pps": float(f[7]), "items": []}
            balls[int(f[1])]["plates"].append(plate)
        elif tag == "@PT":
            plate["items"].append(("T", v3(f[1]), v3(f[2]), f[3], int(f[4]), "|".join(f[5:])))
        elif tag == "@PF":
            plate["items"].append(("F", v3(f[1]), v3(f[2]), float(f[3]), float(f[4]), f[5], f[6]))
    return order


# Plate textures ------------------------------------------------------------------------

_font_cache = {}


def font_for(name, size, ch):
    path = FONTS.get(name, FONTS["GothamBold"])
    if any(ord(c) > 0x24F for c in ch):
        path = SYMBOL_FONT
    key = (path, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


def grad_color(stops, t):
    for k in range(len(stops) - 1):
        t0, c0 = stops[k]
        t1, c1 = stops[k + 1]
        if t <= t1:
            u = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return [c0[j] + (c1[j] - c0[j]) * u for j in range(3)]
    return stops[-1][1]


def raster(plate):
    W = max(2, int(round(plate["wh"][0] * plate["pps"])))
    H = max(2, int(round(plate["wh"][1] * plate["pps"])))
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for it in plate["items"]:
        x, y, w, h = [v * SS for v in it[1]]
        if it[0] == "T":
            color = tuple(int(c * 255) for c in it[2]) + (255,)
            text, size = it[5], it[4] * SS
            fnt = font_for(it[3], int(size * 0.98), text)
            bbox = draw.textbbox((0, 0), text, font=fnt, anchor="ls")
            tw = bbox[2] - bbox[0]
            # Roblox centres the line box; Inter caps sit ~0.36 em above the box centre.
            draw.text((x + (w - tw) / 2 - bbox[0], y + h / 2 + size * 0.36), text, font=fnt, fill=color, anchor="ls")
        else:
            color, transp, corner, stroke, grad = it[2], it[3], it[4], it[5], it[6]
            box = [x, y, x + w, y + h]
            if transp < 1:
                rgb = tuple(int(c * 255) for c in color)
                alpha = int((1 - transp) * 255)
                if grad:
                    spec, rot = grad.split("@")
                    stops = []
                    for kv in spec.split(";"):
                        t, c = kv.split(":")
                        stops.append((float(t), v3(c)))
                    a = math.radians(float(rot))
                    dx, dy = math.cos(a), math.sin(a)
                    tile = Image.new("RGBA", (max(1, int(w)), max(1, int(h))))
                    px = tile.load()
                    tw_, th_ = tile.size
                    for yy in range(th_):
                        for xx in range(tw_):
                            u = ((xx / tw_ - 0.5) * dx + (yy / th_ - 0.5) * dy) / (abs(dx) + abs(dy)) + 0.5
                            c = grad_color(stops, min(1, max(0, u)))
                            px[xx, yy] = (int(c[0] * color[0] * 255), int(c[1] * color[1] * 255), int(c[2] * color[2] * 255), alpha)
                    img.alpha_composite(tile, (int(x), int(y)))
                elif float(corner) >= 0.5:
                    draw.ellipse(box, fill=rgb + (alpha,))
                else:
                    draw.rectangle(box, fill=rgb + (alpha,))
            if stroke:
                th, sc = stroke.split(":")
                rgb = tuple(int(c * 255) for c in v3(sc))
                t = float(th) * SS
                outer = [x - t, y - t, x + w + t, y + h + t]
                if float(corner) >= 0.5:
                    draw.ellipse(outer, outline=rgb + (255,), width=int(t))
                else:
                    draw.rectangle(outer, outline=rgb + (255,), width=int(t))
    return img.resize((W * 2, H * 2), Image.LANCZOS)


# Scene -----------------------------------------------------------------------------------

def principled(name, color, rough=0.4, metal=0.0, alpha=1.0, emit=None, strength=0.0, coat=0.0, ior=1.45, transmission=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = srgb_to_linear(color)
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Alpha"].default_value = alpha
    b.inputs["IOR"].default_value = ior
    if "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.05
    if transmission and "Transmission Weight" in b.inputs:
        b.inputs["Transmission Weight"].default_value = transmission
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*srgb_to_linear(emit), 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


def ball_material(b):
    mat, c, tr, refl = b["mat"], b["color"], b["tr"], b["refl"]
    if mat == "Foil":
        return principled("foil", c, rough=0.22, metal=0.9 if refl < 0.35 else 1.0, coat=0.3)
    if mat == "Glass":
        if b["core"]:
            return principled("shell", c, rough=0.06, alpha=1 - tr * 1.1, coat=1.0)
        return principled("gem", c, rough=0.05, alpha=1 - tr, coat=1.0, transmission=0.15)
    if mat == "ForceField":
        return principled("field", c, rough=0.2, alpha=0.45, emit=c, strength=1.5)
    if mat == "Ice":
        return principled("ice", c, rough=0.15, alpha=0.95, coat=0.6)
    return principled("gloss", c, rough=0.32, coat=0.25 + refl * 4)


def load_mesh():
    bpy.ops.wm.obj_import(filepath=MESH, forward_axis="NEGATIVE_Z", up_axis="Y")
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    obj.name = "BallMeshTemplate"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)  # mesh in Blender axes
    bpy.ops.object.shade_smooth()
    obj.hide_render = True
    obj.hide_viewport = True
    return obj.data


def roblox_to_blender_matrix():
    return Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def cf_matrix(cf):
    p, r, u, back = cf
    return Matrix((
        (r[0], u[0], back[0], p[0]),
        (r[1], u[1], back[1], p[1]),
        (r[2], u[2], back[2], p[2]),
        (0, 0, 0, 1),
    ))


def build_ball(b, mesh_data, base: Matrix, tmp):
    """`base` maps the ball's Roblox-local frame (centre at the origin) to Blender world."""
    R2B = roblox_to_blender_matrix()
    centre = Matrix.Translation(Vector(b["pos"]))
    to_local = centre.inverted()
    me = mesh_data.copy()
    me.materials.clear()
    me.materials.append(ball_material(b))
    o = bpy.data.objects.new("Ball_" + b["id"], me)
    bpy.context.collection.objects.link(o)
    s = b["d"] / 1.5
    o.matrix_world = base @ Matrix.Diagonal((s, s, s, 1))
    if b["core"]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=b["core"]["d"] / 2)
        c = bpy.context.active_object
        c.data.materials.append(principled("core", b["core"]["color"], emit=b["core"]["color"], strength=6.0))
        c.matrix_world = base @ R2B @ to_local @ Matrix.Translation(Vector(b["core"]["pos"]))
        bpy.ops.object.shade_smooth()
    for rg in b["rings"]:
        sx, sy, _ = rg["size"]
        bpy.ops.mesh.primitive_cylinder_add(vertices=96, radius=sy / 2, depth=sx)
        cyl = bpy.context.active_object
        # Roblox cylinder axis = local X; Blender primitive axis = Z.
        cyl.matrix_world = base @ R2B @ to_local @ cf_matrix(rg["cf"]) @ Matrix.Rotation(math.pi / 2, 4, "Y")
        metal = rg["mat"] == "Foil"
        cyl.data.materials.append(principled("ring", rg["color"], rough=0.25 if metal else 0.4, metal=0.9 if metal else 0))
        bpy.ops.object.shade_smooth()
    for k, pl in enumerate(b["plates"]):
        img = raster(pl)
        path = os.path.join(tmp, f"{b['id']}_{k}.png")
        img.save(path)
        w, h = pl["wh"]
        bpy.ops.mesh.primitive_plane_add(size=1)
        pq = bpy.context.active_object
        # Plane faces +Z; the plate's outward face is Roblox -Z (front). Image x runs along the
        # plate's -X (viewer's right), y down along -Y.
        m = bpy.data.materials.new("ink")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        bsdf.inputs["Roughness"].default_value = 0.45
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(path)
        tex.interpolation = "Cubic"
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if hasattr(m, "blend_method"):
            m.blend_method = "HASHED"
        pq.data.materials.append(m)
        front = Matrix.Translation(Vector((0, 0, -0.005 * b["d"] / 1.5))) @ Matrix.Rotation(math.pi, 4, "Y")
        pq.matrix_world = base @ R2B @ to_local @ cf_matrix(pl["cf"]) @ front @ Matrix.Diagonal((w, h, 1, 1))


def setup_scene(res, samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.cycles.max_bounces = 6
    sc.cycles.transparent_max_bounces = 32
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "AgX" if "AgX" in [x.name for x in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    sc.view_settings.look = "None"
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    tc = world.node_tree.nodes.new("ShaderNodeTexCoord")
    sep = world.node_tree.nodes.new("ShaderNodeSeparateXYZ")
    ramp = world.node_tree.nodes.new("ShaderNodeValToRGB")
    world.node_tree.links.new(tc.outputs["Generated"], sep.inputs[0])
    world.node_tree.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    ramp.color_ramp.elements[0].color = (0.010, 0.011, 0.016, 1)
    ramp.color_ramp.elements[1].color = (0.30, 0.31, 0.34, 1)
    world.node_tree.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.9
    sc.world = world


def add_lights(target: Vector, span: float):
    def area(name, loc, power, size, color=(1, 1, 1)):
        d = bpy.data.lights.new(name, "AREA")
        d.energy = power
        d.size = size
        d.color = color
        o = bpy.data.objects.new(name, d)
        bpy.context.collection.objects.link(o)
        o.location = loc
        o.rotation_euler = (target - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    k = span
    area("Key", target + Vector((-1.2 * k, 2.2 * k, 1.8 * k)), 260 * k * k, 1.6 * k)
    area("Fill", target + Vector((1.6 * k, 1.8 * k, 0.4 * k)), 60 * k * k, 2.2 * k, (0.85, 0.9, 1.0))
    area("Rim", target + Vector((0.4 * k, -2.0 * k, 1.6 * k)), 220 * k * k, 1.0 * k, (1.0, 0.95, 0.88))


def floor(z):
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, z))
    f = bpy.context.active_object
    f.data.materials.append(principled("floor", [0.05, 0.055, 0.065], rough=0.25, coat=0.4))


def camera(loc, target, lens=85, ortho=None):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    o = bpy.data.objects.new("Cam", cd)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = o


def label_sheet(path, labels, ortho, res):
    """labels: (name, world x, world z of the label point)."""
    img = Image.open(path).convert("RGB")
    draw = ImageDraw.Draw(img)
    fnt = ImageFont.truetype(FONTS["GothamBold"], max(12, int(res[0] / ortho * 0.2)))
    k = res[0] / ortho
    for nm, x, z in labels:
        draw.text((res[0] / 2 + x * k, res[1] / 2 - z * k), nm, font=fnt, fill=(225, 220, 205), anchor="ms")
    img.save(path)


VIEW_YAW = {"front": 0.0, "three": -28.0, "back": 180.0, "left": 90.0, "right": -90.0}


def render_sheet(balls, out, cols, yaw_deg, res, samples):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene(res, samples)
    mesh = load_mesh()
    tmp = tempfile.mkdtemp()
    rows = math.ceil(len(balls) / cols)
    gap = 2.4
    for k, b in enumerate(balls):
        cx = (k % cols - (cols - 1) / 2) * gap
        cz = ((rows - 1) / 2 - k // cols) * gap
        # Blender: camera looks along +Y; the ball's front (Roblox -Z) maps to Blender +Y,
        # so turn the ball 180 degrees to face the camera, then the view yaw.
        base = Matrix.Translation(Vector((cx, 0, cz))) @ Matrix.Rotation(math.radians(180 + yaw_deg), 4, "Z") @ Matrix.Rotation(math.radians(14), 4, "X") @ Matrix.Diagonal((1.5 / b["d"],) * 3 + (1,))
        build_ball(b, mesh, base, tmp)
    span = max(cols, rows) * gap
    ortho = max(cols * gap, rows * gap * res[0] / res[1]) * 1.02
    camera((0, -60, 0), (0, 0, 0), ortho=ortho)
    add_lights(Vector((0, 0, 0)), span / 2)
    bpy.context.scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    labels = []
    for k, b in enumerate(balls):
        labels.append((b["name"], (k % cols - (cols - 1) / 2) * gap, ((rows - 1) / 2 - k // cols) * gap - 1.0))
    label_sheet(out, labels, ortho, res)
    print("wrote", out)


def render_closeups(b, views, res, samples, outdir, transparent=False):
    for view in views:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        setup_scene(res, samples)
        if transparent:
            bpy.context.scene.render.film_transparent = True
        mesh = load_mesh()
        tmp = tempfile.mkdtemp()
        base = Matrix.Rotation(math.radians(180 + VIEW_YAW[view]), 4, "Z") @ Matrix.Rotation(math.radians(10), 4, "X") @ Matrix.Diagonal((1.5 / b["d"],) * 3 + (1,))
        build_ball(b, mesh, base, tmp)
        if not transparent:
            floor(-0.76)
        camera((0, -6.2, 0.9), (0, 0, 0.02), lens=85)
        add_lights(Vector((0, 0, 0)), 1.2)
        out = os.path.join(outdir, f"{b['id']}_{view}.png")
        bpy.context.scene.render.filepath = out
        bpy.ops.render.render(write_still=True)
        print("wrote", out)


def main():
    import sys
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--only", default="")
    ap.add_argument("--views", default="three")
    ap.add_argument("--sheet", action="store_true", help="lineup sheets of every ball")
    ap.add_argument("--cols", type=int, default=8)
    ap.add_argument("--samples", type=int, default=48)
    ap.add_argument("--res", default="1600x1000")
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--transparent", action="store_true", help="no floor, transparent background (icons)")
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    balls = parse(args.dump)
    res = tuple(int(x) for x in args.res.split("x"))
    if args.sheet:
        per = args.cols * 4
        for s in range(0, len(balls), per):
            render_sheet(balls[s:s + per], os.path.join(args.out, f"collection_{s // per + 1}.png"), args.cols, -24, res, args.samples)
    if args.only:
        want = set(args.only.split(","))
        for b in balls:
            if b["id"] in want:
                render_closeups(b, args.views.split(","), res, args.samples, args.out, args.transparent)


if __name__ == "__main__":
    main()
