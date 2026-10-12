"""3D thumbnail scenes for all Corny Games experiences.

Run: <blender-python> scenes.py <game> <scene> [--preview]
Writes marketing/<game>/renders/<scene>.png (no text; titles are added by overlay.py).
Composition rule: the top ~35% of the frame stays clean for the title.
"""
import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import hexrgb  # noqa: E402

R = math.radians


def cone(loc, r1, r2, depth, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    for p in o.data.polygons:
        p.use_smooth = True
    return kit.assign(o, mat)


def egg(loc, size, color, spots=None, glow=0.0):
    m = kit.mat_plastic("egg", color, 0.3, 0.8)
    if glow:
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Emission Color"].default_value = hexrgb(color)
        b.inputs["Emission Strength"].default_value = glow
    o = kit.sphere(loc, size, m, scale=(1, 1, 1.3))
    taper = o.modifiers.new("Taper", "SIMPLE_DEFORM")
    taper.deform_method = "TAPER"
    taper.factor = -0.28
    taper.deform_axis = "Z"
    if spots:
        sm = kit.mat_plastic("spot", spots, 0.35, 0.6)
        rnd = random.Random(int(loc[0] * 10 + loc[1] * 7))
        for _ in range(6):
            th = rnd.uniform(-1.2, 1.2) - math.pi / 2
            ph = rnd.uniform(-0.6, 0.7)
            r = size * 1.0
            x = loc[0] + r * math.cos(th) * math.cos(ph) * 0.97
            y = loc[1] + r * math.sin(th) * math.cos(ph) * 0.97
            z = loc[2] + size * 1.3 * math.sin(ph) * 0.95
            kit.sphere((x, y, z), size * rnd.uniform(0.12, 0.2), sm, scale=(1, 0.35, 1))
    return o


def crate(loc, size, color, trim="#FFC83D", seam="#FFD1E0"):
    x, y, z = loc
    kit.box(loc, (size, size, size * 0.86), kit.mat_plastic("crate", color, 0.25, 0.9), bevel=size * 0.09)
    gold = kit.mat_metal("trim", trim, 0.25)
    for dz in (-0.3, 0.3):
        kit.box((x, y, z + dz * size * 0.86), (size * 1.03, size * 1.03, size * 0.09), gold, bevel=size * 0.02)
    kit.box((x, y, z + 0.15 * size), (size * 1.035, size * 1.035, size * 0.035), kit.mat_emit("seam", seam, 8), bevel=0)
    kit.ball((x, y - size * 0.52, z), size * 0.2, kit.mat_golfball("emblem", "#F7F9FF"))
    kit.torus((x, y - size * 0.51, z), size * 0.23, size * 0.035, gold, rot=(R(90), 0, 0))


def flag(loc, height, color):
    x, y, z = loc
    kit.cyl((x, y, z + height / 2), 0.07, height, kit.mat_plastic("pole", "#F4F6FA", 0.3, 0.6), bevel=0.0)
    kit.sphere((x, y, z + height + 0.08), 0.13, kit.mat_metal("knob", "#FFC83D"))
    kit.box((x + 0.75, y, z + height - 0.45), (1.5, 0.04, 0.85), kit.mat_plastic("flag", color, 0.35, 0.5),
            bevel=0.01, rot=(0, 0, R(-8)))


def cup(loc, r=0.55):
    x, y, z = loc
    kit.cyl((x, y, z + 0.006), r, 0.012, kit.mat_plastic("hole", "#05050A", 0.9, 0.0), bevel=0)
    kit.torus((x, y, z + 0.012), r, 0.035, kit.mat_plastic("rim", "#FFFFFF", 0.3, 0.6))


def standard_lights(key=1400, rim_a="#FF4FD8", rim_b="#00E5FF", rim=1800):
    kit.light_area((-5, -8, 9), (0, 0, 1), key, size=6)
    kit.light_area((8, 6, 5), (0, 0, 1.5), rim, rim_a, size=4)
    kit.light_area((-8, 6, 5), (0, 0, 1.5), rim, rim_b, size=4)
    kit.light_area((0, 2, 12), (0, 0, 0), key * 0.5, size=8)


# Ultimate Golf -------------------------------------------------------------------------------------

def golf_hero():
    kit.world_gradient("#2A0D5E", "#12052E")
    kit.backdrop("#3A1A7A", "#A23BFF", glow=0.9)
    kit.cyl((1.5, 2.2, 0.25), 6.0, 0.5, kit.mat_plastic("green", "#3BD16F", 0.4, 0.5), bevel=0.12, verts=128)
    cup((4.0, 1.6, 0.5))
    flag((4.0, 1.6, 0.5), 4.2, "#FFD000")
    crate((-6.2, 2.6, 1.1), 2.2, "#FF2D55")
    crate((-3.9, 3.6, 0.72), 1.45, "#00C8F0", trim="#E9EEF8", seam="#C8FBFF")
    ball_pos = (0.4, -1.8, 2.2)
    kit.ball(ball_pos, 1.1, kit.mat_golfball("ball", "#F7F9FF"))
    bounce = (-1.6, -1.6, 0.55)
    path = [(-6.5, -0.6, 0.8), (-4.6, -1.0, 2.6), (-2.6, -1.5, 1.6), bounce, (-0.9, -1.7, 1.6), ball_pos]
    kit.tube(path, 0.07, kit.mat_emit("trail1", "#00E5FF", 12))
    kit.tube([(p[0], p[1] + 0.05, p[2] - 0.22) for p in path], 0.045, kit.mat_emit("trail2", "#FF00A0", 12))
    kit.tube([(p[0], p[1] - 0.05, p[2] + 0.2) for p in path], 0.035, kit.mat_emit("trail3", "#FFD000", 12))
    kit.torus((bounce[0], bounce[1], 0.52), 0.6, 0.04, kit.mat_emit("ring", "#BFF3FF", 10))
    kit.confetti((4.2, 1.2, 4.2), (1.1, 0.8, 0.9), 70, ["#FF4FA3", "#7FEFFF", "#FFE07A", "#6BE37A"], seed=3)
    standard_lights()
    kit.camera((0.0, -12.5, 2.6), (0.0, 0.5, 2.1), lens=36, dof_target=ball_pos, fstop=5)


def golf_ranked():
    kit.world_gradient("#1A0D3E", "#05030F")
    kit.backdrop("#1E1A33", "#3A2A6A", glow=0.7)
    kit.cyl((0, 1, 0.15), 7.5, 0.3, kit.mat_plastic("arena", "#2A2F48", 0.35, 0.8), bevel=0.08, verts=128)
    kit.torus((0, 1, 0.3), 7.45, 0.07, kit.mat_emit("arenaRing", "#FFC83D", 8))
    left, right = (-2.8, 0, 2.1), (2.8, 0, 2.1)
    kit.ball(left, 1.85, kit.mat_golfball("gold", "#FFB000", color2="#FF4A00", emissive=0.35, dimples=6.5))
    kit.ball(right, 1.85, kit.mat_golfball("plasma", "#00E5FF", color2="#7A00FF", emissive=0.35, dimples=6.5))
    gold = kit.mat_metal("crown", "#FFC83D", 0.2)
    cx, cy, cz = left[0], left[1], left[2] + 2.05
    kit.cyl((cx, cy, cz), 0.85, 0.5, gold, bevel=0.05)
    gem = kit.mat_glass("gem", "#FF3355", 0.05)
    for k in range(5):
        a = k / 5 * 2 * math.pi + 0.3
        cone((cx + math.cos(a) * 0.72, cy + math.sin(a) * 0.72, cz + 0.55), 0.24, 0.0, 0.7, gold)
        kit.sphere((cx + math.cos(a) * 0.72, cy + math.sin(a) * 0.72, cz + 0.95), 0.11, gold)
    kit.sphere((cx, cy - 0.86, cz), 0.16, gem)
    kit.light_area((-9, -4, 5), left, 5000, "#FF3D2E", size=5)
    kit.light_area((9, -4, 5), right, 5000, "#2E5BFF", size=5)
    kit.light_area((0, -9, 8), (0, 0, 2), 1200, size=6)
    kit.light_area((0, 6, 9), (0, 0, 2), 2500, "#FFE0A0", size=6)
    kit.camera((0, -17, 3.0), (0, 0, 3.6), lens=40)


def golf_race():
    kit.world_gradient("#0A3A6A", "#04101F")
    kit.backdrop("#0B1E3A", "#00A6E8", glow=0.9)
    pts = [(-11, -5, 0.05), (-5, -2.5, 0.05), (1, 0.5, 0.05), (6, 2.0, 0.05), (11, 2.5, 0.05)]
    import bmesh
    me = bpy.data.meshes.new("Track")
    bm = bmesh.new()
    left = [bm.verts.new((x, y - 1.6, 0.03)) for x, y, z in pts]
    right = [bm.verts.new((x, y + 1.6, 0.03)) for x, y, z in pts]
    for i in range(len(pts) - 1):
        bm.faces.new((left[i], left[i + 1], right[i + 1], right[i]))
    bm.to_mesh(me)
    bm.free()
    tr = bpy.data.objects.new("Track", me)
    bpy.context.scene.collection.objects.link(tr)
    tr.data.materials.append(kit.mat_plastic("trackMat", "#121A33", 0.25, 0.9))
    kit.tube([(x, y - 1.6, z + 0.1) for x, y, z in pts], 0.08, kit.mat_emit("railA", "#00E5FF", 10))
    kit.tube([(x, y + 1.6, z + 0.1) for x, y, z in pts], 0.08, kit.mat_emit("railB", "#FF00A0", 10))
    kit.cyl((8.2, 2.5, 0.12), 1.8, 0.24, kit.mat_plastic("green", "#3BD16F", 0.4, 0.5), bevel=0.06)
    cup((8.2, 2.5, 0.24), 0.42)
    flag((8.2, 2.5, 0.24), 3.0, "#FFD000")
    racers = [(0.80, -0.6, "#FFD000", "#FF8A00", 0.75), (0.70, 0.7, "#FF2D55", None, 0.72),
              (0.63, -0.3, "#6BE37A", None, 0.7), (0.55, 0.8, "#B04DFF", "#00E5FF", 0.68),
              (0.47, -0.8, "#F7F9FF", None, 0.66), (0.39, 0.4, "#FF8BD1", None, 0.64),
              (0.31, -0.5, "#3D8BFF", None, 0.62), (0.23, 0.7, "#FF7A00", None, 0.6)]

    def along(t, off):
        n = len(pts) - 1
        f = t * n
        i = min(int(f), n - 1)
        u = f - i
        a, b = pts[i], pts[i + 1]
        return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u + off)

    for t, off, c1, c2, r in racers:
        x, y = along(t, off)
        kit.ball((x, y, r), r, kit.mat_golfball(f"r{t}", c1, color2=c2, emissive=0.25 if c2 else 0.0, dimples=7))
        tail = [(*along(max(t - 0.12, 0), off), r), (*along(max(t - 0.06, 0), off), r), (x - 0.5, y, r)]
        kit.tube(tail, r * 0.12, kit.mat_emit(f"t{t}", c1, 9))
    bx, by = along(0.70, 0.2)
    spark = kit.mat_emit("spark", "#FFE07A", 25)
    rnd = random.Random(7)
    for _ in range(40):
        a, e = rnd.uniform(0, 6.28), rnd.uniform(-0.3, 1.2)
        d = rnd.uniform(0.4, 1.6)
        kit.sphere((bx + math.cos(a) * d, by + math.sin(a) * d * 0.5, 0.6 + e), rnd.uniform(0.03, 0.08), spark)
    kit.light_point((bx, by - 0.5, 1.0), 900, "#FFC060", radius=0.5)
    standard_lights(rim_a="#FF00A0", rim_b="#00E5FF")
    kit.camera((-1.0, -9.5, 2.4), (1.6, 0.6, 0.9), lens=32, dof_target=(along(0.66, 0)[0], along(0.66, 0)[1], 0.7), fstop=7)


def golf_skins():
    kit.world_gradient("#2A0D5E", "#0B0420")
    kit.backdrop("#22103F", "#7A2BFF", glow=0.8)
    skins = [("#FF0033", "#FF7A00", 0.4, "plastic", "#FF2D55"), ("#3A1C71", "#D76D77", 0.25, "plastic", "#B04DFF"),
             ("#FFC83D", None, 0.0, "metal", "#FFC83D"), ("#7A00FF", "#00E5FF", 0.45, "plastic", "#B04DFF"),
             ("#FFFFFF", "#FFD000", 0.45, "plastic", "#FFC83D"), ("#00FFC6", "#7A5CFF", 0.35, "plastic", "#3D8BFF"),
             ("#E0115F", None, 0.05, "glass", "#3D8BFF")]
    n = len(skins)
    for k, (c1, c2, em, kind, glow) in enumerate(skins):
        a = (k - (n - 1) / 2) * 0.32
        x, y = math.sin(a) * 8.0, -math.cos(a) * 8.0 + 8.5
        mid = abs(k - (n - 1) / 2)
        r = 0.95 - mid * 0.06
        kit.cyl((x, y, 0.4), r * 1.1, 0.8, kit.mat_plastic(f"ped{k}", "#1E1A33", 0.3, 0.8), bevel=0.05)
        kit.torus((x, y, 0.8), r * 1.1, 0.05, kit.mat_emit(f"pr{k}", glow, 10))
        if kind == "metal":
            m = kit.mat_golfball(f"s{k}", c1, rough=0.15, dimples=7)
            m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 1.0
        elif kind == "glass":
            m = kit.mat_golfball(f"s{k}", c1, rough=0.05, dimples=7)
            m.node_tree.nodes["Principled BSDF"].inputs["Transmission Weight"].default_value = 0.85
        else:
            m = kit.mat_golfball(f"s{k}", c1, color2=c2, emissive=em, dimples=7)
        kit.ball((x, y, 0.8 + r), r, m)
        kit.spot((x, y - 3, 7), (x, y, 1.2), 900, glow, angle=28)
    kit.light_area((0, -9, 6), (0, 0, 1.2), 900, size=8)
    kit.camera((0, -11, 2.4), (0, 1, 1.5), lens=34)


def golf_daily():
    kit.world_gradient("#FF7A59", "#2A0A3A")
    kit.backdrop("#3A1240", "#FF8A5C", glow=1.1)
    kit.ball((0, 0.5, 2.5), 1.9, kit.mat_golfball("dawn", "#FFB547", color2="#FF5E7E", emissive=0.9, dimples=6.5))
    kit.torus((0, 0.5, 2.5), 2.8, 0.05, kit.mat_emit("orbit", "#FFE7A3", 10), rot=(R(30), 0, R(22)))
    kit.torus((0, 0.5, 2.5), 3.2, 0.035, kit.mat_emit("orbit2", "#FF9EC0", 8), rot=(R(-26), 0, R(-30)))
    coin = kit.mat_metal("coin", "#FFC83D", 0.2)
    rnd = random.Random(9)
    for side in (-1, 1):
        for _ in range(26):
            x = side * rnd.uniform(3.0, 6.0)
            y = rnd.uniform(-1.5, 1.5)
            heap = max(0.0, 1 - abs(abs(x) - 4.5) / 1.6) * max(0.0, 1 - abs(y) / 1.6)
            z = 0.07 + heap * rnd.uniform(0.2, 0.75)
            kit.cyl((x, y, z), 0.42, 0.1, coin, bevel=0.02,
                    rot=(rnd.uniform(-0.45, 0.45), rnd.uniform(-0.45, 0.45), 0))
    kit.light_area((0, -9, 7), (0, 0, 2), 1200, size=8)
    kit.light_area((7, 4, 5), (0, 0, 2), 2200, "#FFB0C0", size=4)
    kit.light_area((-7, 4, 5), (0, 0, 2), 2200, "#FFE0A0", size=4)
    kit.camera((0, -14.0, 2.8), (0, 0.5, 3.2), lens=40)


# Brainrot Heist ------------------------------------------------------------------------------------

def capsule(loc, glow, h=2.0, r=0.62, mark="?"):
    x, y, z = loc
    steel = kit.mat_metal("cap", "#C9D1E3", 0.25)
    kit.cyl((x, y, z - h / 2 - 0.12), r * 1.15, 0.25, steel, bevel=0.06)
    kit.cyl((x, y, z + h / 2 + 0.12), r * 1.15, 0.25, steel, bevel=0.06)
    kit.cyl((x, y, z), r, h, kit.mat_glass("glass", "#E8FFF4", 0.02), bevel=0.02)
    kit.sphere((x, y, z - 0.1), r * 0.62, kit.mat_emit("blob", glow, 5), scale=(1, 1, 1.15))
    kit.text3d(mark, (x, y - r * 0.68, z), r * 1.1, kit.mat_emit("mark", "#FFFFFF", 6), extrude=0.04)
    kit.light_point((x, y - 0.5, z), 120, glow, radius=0.4)


def laser(a, b, color="#FF2440"):
    kit.tube([a, b], 0.035, kit.mat_emit("laser", color, 30))


def vault(loc, r):
    x, y, z = loc
    steel = kit.mat_metal("steel", "#AEB6C8", 0.28)
    gold = kit.mat_metal("gold", "#FFC83D", 0.22)
    kit.cyl((x, y, z), r, 0.6, steel, bevel=0.08, rot=(R(90), 0, 0), verts=96)
    kit.torus((x, y - 0.32, z), r * 0.86, 0.09, gold, rot=(R(90), 0, 0))
    kit.torus((x, y - 0.42, z), r * 0.38, 0.08, steel, rot=(R(90), 0, 0))
    for k in range(3):
        a = k / 3 * math.pi
        kit.box((x, y - 0.42, z), (r * 0.8, 0.12, 0.12), steel, bevel=0.03, rot=(0, a, 0))
    kit.cyl((x, y - 0.45, z), r * 0.12, 0.2, gold, bevel=0.03, rot=(R(90), 0, 0))
    for k in range(16):
        a = k / 16 * 2 * math.pi
        kit.sphere((x + math.cos(a) * r * 0.93, y - 0.3, z + math.sin(a) * r * 0.93), 0.09, steel)


def brainrot_hero():
    kit.world_gradient("#1A1450", "#05040F")
    kit.backdrop("#141030", "#2B2080", glow=0.6)
    kit.box((3.5, 4.5, 3.2), (8, 0.8, 6.4), kit.mat_plastic("wall", "#2A2A3E", 0.6, 0.1), bevel=0.1)
    vault((3.3, 4.0, 2.8), 2.4)
    capsule((-0.8, 0.8, 1.35), "#39FF88")
    for a, b in (((-7, 2, 0.6), (7, -1, 3.6)), ((-7, -1, 3.2), (7, 2.5, 0.4)), ((-6, 3.5, 2.0), (6, -2, 1.2))):
        laser(a, b)
    kit.avatar((-4.2, -1.8, 0), R(62), "#1E1E28", "#2B2B3A", pose="run", scale=0.62)
    kit.box((-4.2, -2.2, 2.95), (0.85, 0.1, 0.22), kit.mat_plastic("mask", "#0B0B12", 0.4, 0.2), bevel=0.04,
            rot=(0, 0, R(62)))
    kit.sphere((-3.1, -2.5, 1.55), 0.55, kit.mat_plastic("sack", "#C98A4B", 0.7, 0.0), scale=(1, 1, 0.95))
    kit.cyl((-3.1, -2.5, 2.1), 0.14, 0.25, kit.mat_plastic("tie", "#E8B021", 0.4, 0.3), bevel=0.02)
    kit.text3d("$", (-3.1, -3.05, 1.5), 0.5, kit.mat_metal("dollar", "#FFC83D"), extrude=0.05)
    cash = kit.mat_plastic("cash", "#3BB273", 0.5, 0.2)
    for k in range(6):
        kit.box((5.8 + (k % 3) * 0.55, 1.0 + (k // 3) * 0.7, 0.18 + (k // 3) * 0.02), (0.5, 0.95, 0.32), cash, bevel=0.03)
    kit.sphere((7.5, 16, 9.5), 1.3, kit.mat_emit("moon", "#EEF3FF", 4))
    kit.light_area((-6, -8, 8), (0, 0, 1.5), 900, "#7A8CFF", size=6)
    kit.light_area((7, -3, 6), (0, 0, 1.5), 1600, "#FF2440", size=3)
    kit.light_area((0, 3, 10), (0, 0, 1), 900, "#9B7BFF", size=6)
    kit.camera((0.0, -12.0, 2.8), (0.2, 0.5, 2.0), lens=34, dof_target=(-0.8, 0.8, 1.35), fstop=7)


def brainrot_mutations():
    kit.world_gradient("#0D3A2A", "#020A07")
    kit.backdrop("#0E2A20", "#1F7A5A", glow=0.8)
    cols = ["#FFC83D", "#7FE9FF", "#B266FF", "#FF4FA3"]
    for k, c in enumerate(cols):
        x = -4.8 + k * 3.2
        kit.cyl((x, 0.5, 0.3), 1.0, 0.6, kit.mat_plastic("ped", "#1A2A24", 0.3, 0.8), bevel=0.05)
        kit.torus((x, 0.5, 0.6), 1.0, 0.05, kit.mat_emit("pr", c, 10))
        capsule((x, 0.5, 1.95), c, h=2.2, r=0.68)
    a_mat, b_mat = kit.mat_emit("dnaA", "#39FF88", 8), kit.mat_emit("dnaB", "#C77DFF", 8)
    for i in range(40):
        t = i / 39
        z = 0.5 + t * 4.4
        ang = t * 4.4 * math.pi
        p1 = (math.cos(ang) * 0.9, 8.0 + math.sin(ang) * 0.9, z)
        p2 = (-math.cos(ang) * 0.9, 8.0 - math.sin(ang) * 0.9, z)
        kit.sphere(p1, 0.16, a_mat)
        kit.sphere(p2, 0.16, b_mat)
        if i % 3 == 0:
            kit.tube([p1, p2], 0.04, kit.mat_emit("rung", "#E6FFF4", 4))
    kit.light_area((0, -9, 7), (0, 0, 1.5), 1000, size=8)
    kit.light_area((8, 2, 5), (0, 0, 1.5), 1500, "#39FF88", size=4)
    kit.light_area((-8, 2, 5), (0, 0, 1.5), 1500, "#C77DFF", size=4)
    kit.camera((0, -13, 3.0), (0, 0.6, 3.3), lens=38)


def brainrot_night():
    kit.world_gradient("#10184A", "#020310")
    kit.backdrop("#0C1238", "#26338A", glow=0.7)
    kit.sphere((7.2, 16, 7.4), 2.1, kit.mat_emit("moon", "#E8EEFF", 3.0))
    star = kit.mat_emit("star", "#FFFFFF", 12)
    rnd = random.Random(4)
    for _ in range(70):
        kit.sphere((rnd.uniform(-16, 16), 29.5, rnd.uniform(3, 16)), rnd.uniform(0.03, 0.09), star)
    for x, y, c in ((-4.6, 0.2, "#FFC83D"), (-1.6, 1.2, "#39FF88"), (1.6, 1.2, "#FF4FA3"), (4.6, 0.2, "#7FE9FF")):
        capsule((x, y, 1.3), c, h=1.9, r=0.6)
    kit.light_area((0, -9, 7), (0, 0, 1.5), 700, "#9BB0FF", size=8)
    kit.light_area((0, 8, 8), (0, 0, 1.0), 1600, "#BFD4FF", size=6)
    kit.camera((0, -13.5, 2.4), (0, 1, 3.0), lens=36)


# Merge A Egg -----------------------------------------------------------------------------------------

def merger(loc):
    x, y, z = loc
    body = kit.mat_plastic("machine", "#E9EEF8", 0.25, 0.8)
    kit.box((x, y, z + 1.3), (3.4, 2.2, 2.6), body, bevel=0.3)
    kit.box((x, y, z + 0.15), (3.8, 2.6, 0.3), kit.mat_plastic("base", "#2E3A8C", 0.3, 0.8), bevel=0.1)
    kit.sphere((x, y - 1.05, z + 1.4), 0.85, kit.mat_emit("core", "#FFD36B", 6), scale=(1, 0.35, 1))
    kit.torus((x, y - 1.1, z + 1.4), 0.9, 0.09, kit.mat_metal("coreRing", "#FFC83D"), rot=(R(90), 0, 0))
    for sx in (-1, 1):
        kit.cyl((x + sx * 1.25, y, z + 2.95), 0.42, 0.9, kit.mat_plastic("chute", "#B7C1D6", 0.3, 0.6), bevel=0.06)
        kit.torus((x + sx * 1.25, y, z + 3.4), 0.42, 0.07, kit.mat_emit("chuteRing", "#00E5FF", 8))
    kit.light_point((x, y - 2.0, z + 1.4), 400, "#FFC060", radius=0.6)


def arrow3d(a, b, color):
    m = kit.mat_plastic("arrow", color, 0.3, 0.8)
    ax, ay, az = a
    bx, by, bz = b
    ang = math.atan2(bz - az, bx - ax)
    length = math.hypot(bx - ax, bz - az)
    mid = ((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2)
    kit.box(mid, (length * 0.65, 0.3, 0.3), m, bevel=0.08, rot=(0, -ang, 0))
    tip = (bx - math.cos(ang) * 0.3, by, bz - math.sin(ang) * 0.3)
    cone(tip, 0.45, 0.0, 0.7, m, rot=(0, R(90) - ang, 0))


def merge_hero():
    kit.world_gradient("#3FD3FF", "#0B2A5A")
    kit.backdrop("#2E9C55", "#59C7FF", glow=0.9)
    kit.cyl((0, 1.0, 0.15), 8.5, 0.3, kit.mat_plastic("grass", "#6BE37A", 0.45, 0.3), bevel=0.1, verts=128)
    merger((0, 1.6, 0.3))
    egg((-4.6, 0.2, 1.4), 0.85, "#7FC8FF", spots="#2F7BD8")
    egg((4.6, 0.2, 1.4), 0.85, "#7FC8FF", spots="#2F7BD8")
    arrow3d((-3.4, 0.3, 1.6), (-1.9, 0.3, 2.2), "#FFC83D")
    arrow3d((3.4, 0.3, 1.6), (1.9, 0.3, 2.2), "#FFC83D")
    egg((0, 0.6, 4.6), 0.85, "#FFC83D", spots="#FF7A00", glow=0.6)
    kit.light_point((0, -0.5, 4.6), 300, "#FFE07A", radius=0.5)
    kit.confetti((0, 0.4, 5.0), (1.6, 0.6, 0.8), 50, ["#FFE07A", "#FF9EDB", "#7FEFFF"], seed=12)
    standard_lights(rim_a="#FFE07A", rim_b="#7FEFFF")
    kit.camera((0, -14, 3.6), (0, 0.6, 2.3), lens=40)


def merge_steal():
    kit.world_gradient("#7FD8FF", "#1A5A9A")
    kit.backdrop("#3A8CC0", "#9BE3FF", glow=1.0)
    islands = [((-5.5, 3.5, 0.6), "#6BE37A", "#3E8E46", "#7AE582", "#2E9C55"),
               ((-1.2, 5.5, 1.1), "#F4F8FF", "#A8C4DE", "#E6F6FF", "#7FC8FF"),
               ((3.2, 4.5, 0.8), "#F2C66B", "#B98A3C", "#FFE29A", "#E8A33D"),
               ((7.2, 2.8, 0.5), "#3A2A30", "#FF5A2E", "#FF8A5C", "#B3261E")]
    for (x, y, z), top, side, egg_c, spot_c in islands:
        kit.cyl((x, y, z), 2.0, 0.5, kit.mat_plastic("top", top, 0.5, 0.3), bevel=0.1)
        cone((x, y, z - 1.1), 1.9, 0.3, 1.7, kit.mat_plastic("rock", side, 0.7, 0.1), rot=(R(180), 0, 0))
        egg((x, y, z + 1.15), 0.62, egg_c, spots=spot_c)
    kit.avatar((-1.0, -1.6, 0), R(75), "#FF4FA3", "#2E3A8C", pose="run", scale=0.5)
    egg((-0.25, -2.25, 1.95), 0.46, "#FFC83D", spots="#FF7A00", glow=0.4)
    speed = kit.mat_emit("speed", "#FFFFFF", 4)
    rnd = random.Random(5)
    for _ in range(14):
        y = rnd.uniform(-2.6, -1.0)
        z = rnd.uniform(0.6, 3.0)
        x0 = rnd.uniform(-7.0, -4.2)
        kit.tube([(x0, y, z), (x0 + rnd.uniform(1.0, 2.0), y, z)], 0.025, speed)
    standard_lights(rim_a="#FFE07A", rim_b="#FFFFFF")
    kit.camera((0.5, -13.5, 3.2), (0.8, 1.2, 2.0), lens=36, dof_target=(-0.5, -1.8, 1.6), fstop=7)


def merge_speed():
    kit.world_gradient("#FF7A59", "#2A0A3A")
    kit.backdrop("#3A1450", "#FF8A5C", glow=1.0)
    belt = kit.mat_plastic("belt", "#22263A", 0.6, 0.2)
    kit.box((0, 0.5, 0.35), (2.6, 6.0, 0.4), belt, bevel=0.15)
    stripe = kit.mat_plastic("stripe", "#454C6E", 0.5, 0.2)
    for k in range(10):
        kit.box((0, -2.2 + k * 0.55, 0.56), (2.3, 0.08, 0.02), stripe, bevel=0)
    rail = kit.mat_metal("rail", "#D7DEEA", 0.25)
    for sx in (-1, 1):
        kit.cyl((sx * 1.45, -1.6, 1.6), 0.08, 2.6, rail, bevel=0.0)
        kit.tube([(sx * 1.45, -1.6, 2.9), (sx * 1.45, 1.8, 2.9)], 0.08, rail)
    kit.box((0, -1.8, 3.1), (2.4, 0.35, 0.9), kit.mat_plastic("console", "#2B3150", 0.3, 0.7), bevel=0.1)
    kit.box((0, -1.99, 3.15), (1.6, 0.02, 0.5), kit.mat_emit("screen", "#39FF88", 5), bevel=0.0)
    kit.avatar((0, 0.4, 0.55), R(0), "#FF4FA3", "#2E3A8C", pose="run", scale=0.52)
    speed = kit.mat_emit("speed", "#FFFFFF", 5)
    rnd = random.Random(6)
    for k in range(9):
        x = rnd.uniform(-0.7, 0.7)
        y = 1.5 + rnd.uniform(0.0, 0.8)
        z = 1.1 + k * 0.24
        kit.tube([(x, y, z), (x, y + rnd.uniform(1.3, 2.3), z)], 0.022, speed)
    standard_lights(rim_a="#FFE07A", rim_b="#FF9EDB")
    kit.camera((-6.5, -9.0, 3.6), (0.0, 0.4, 1.9), lens=36)


def merge_tiers():
    kit.world_gradient("#B04DFF", "#1A0636")
    kit.backdrop("#2A1050", "#9B3BFF", glow=0.9)
    tiers = [("#F4F6FA", "#C9D1E3"), ("#7AE582", "#2E9C55"), ("#7FC8FF", "#2F7BD8"),
             ("#C77DFF", "#7A2BFF"), ("#FFC83D", "#FF7A00"), ("#FF4FA3", "#7A00FF")]
    for k, (c, s) in enumerate(tiers):
        size = 0.5 + k * 0.1
        x = -6.2 + k * 2.5
        kit.cyl((x, 0.6, 0.2), size * 1.3, 0.4, kit.mat_plastic("ped", "#1E1A33", 0.3, 0.8), bevel=0.05)
        kit.torus((x, 0.6, 0.4), size * 1.3, 0.04, kit.mat_emit("pr", c, 8))
        egg((x, 0.6, 0.4 + size * 1.3), size, c, spots=s, glow=0.35 if k >= 3 else 0.0)
        kit.text3d(str(k + 1), (x, 0.6 - size - 0.1, 0.4 + size * 2.9 + 0.5), 0.7, kit.mat_emit("num", "#FFFFFF", 3),
                   extrude=0.06)
    kit.light_area((0, -9, 7), (0, 0, 1.5), 1100, size=8)
    kit.light_area((8, 3, 5), (0, 0, 1.5), 1400, "#FFE07A", size=4)
    kit.light_area((-8, 3, 5), (0, 0, 1.5), 1400, "#7FEFFF", size=4)
    kit.camera((0, -15.0, 3.0), (0, 0.6, 1.9), lens=36)


# Cyber Swarm ------------------------------------------------------------------------------------------

def neon_grid(color_a="#FF2BD6", color_b="#00E5FF", y0=-12, y1=20, half=24):
    a, b = kit.mat_emit("gridA", color_a, 6), kit.mat_emit("gridB", color_b, 5)
    for k in range(-12, 13):
        kit.box((k * 2.0, (y0 + y1) / 2, 0.01), (0.04, y1 - y0, 0.02), a, bevel=0)
    for k in range(0, 17):
        kit.box((0, y0 + k * 2.0, 0.01), (half * 2, 0.04, 0.02), b, bevel=0)


def robot(loc, size, color, kind="scout", facing=R(-60)):
    x, y, z = loc
    root = bpy.data.objects.new("Robot", None)
    bpy.context.scene.collection.objects.link(root)
    parts = []
    metal = kit.mat_plastic("robo", "#E9EEF8", 0.25, 0.9)
    dark = kit.mat_plastic("roboDark", "#20243A", 0.4, 0.5)
    glow = kit.mat_emit("visor", color, 9)
    accent = kit.mat_plastic("accent", color, 0.3, 0.7)
    s = size
    if kind == "drone":
        parts.append(kit.sphere((0, 0, 2.2 * s), 0.55 * s, metal))
        parts.append(kit.box((0, -0.45 * s, 2.25 * s), (0.6 * s, 0.1 * s, 0.22 * s), glow, bevel=0.04 * s))
        for sx in (-1, 1):
            parts.append(kit.box((sx * 0.75 * s, 0, 2.45 * s), (0.6 * s, 0.12 * s, 0.1 * s), dark, bevel=0.03 * s))
            parts.append(kit.cyl((sx * 1.05 * s, 0, 2.55 * s), 0.38 * s, 0.03 * s, accent, bevel=0.0))
    else:
        w = {"scout": 0.9, "tank": 1.4, "boss": 1.6}[kind] * s
        h = {"scout": 1.0, "tank": 0.9, "boss": 1.5}[kind] * s
        parts.append(kit.box((0, 0, 0.25 * s), (w * 0.9, w * 0.8, 0.45 * s), dark, bevel=0.12 * s))
        parts.append(kit.box((0, 0, 0.5 * s + h / 2), (w, w * 0.8, h), metal, bevel=0.2 * s))
        parts.append(kit.box((0, -w * 0.4, 0.5 * s + h * 0.62), (w * 0.72, 0.06 * s, h * 0.28), glow, bevel=0.04 * s))
        parts.append(kit.box((0, 0, 0.5 * s + h * 0.25), (w * 1.01, w * 0.81, h * 0.1), accent, bevel=0.02 * s))
        parts.append(kit.cyl((w * 0.25, 0, 0.5 * s + h + 0.25 * s), 0.04 * s, 0.5 * s, dark, bevel=0.0))
        parts.append(kit.sphere((w * 0.25, 0, 0.5 * s + h + 0.55 * s), 0.1 * s, glow))
        if kind == "boss":
            for sx in (-1, 1):
                parts.append(cone((sx * w * 0.35, 0, 0.5 * s + h + 0.3 * s), 0.18 * s, 0.0, 0.6 * s, accent))
    for p in parts:
        p.parent = root
    root.location = (x, y, z)
    root.rotation_euler = (0, 0, facing)
    return root


def tower(loc, size, color="#FF3B3B", aim=(-1, -0.4, -0.25)):
    x, y, z = loc
    s = size
    base = kit.mat_plastic("towerBase", "#3A3F5A", 0.3, 0.8)
    head = kit.mat_plastic("towerHead", "#E9EEF8", 0.25, 0.9)
    kit.cyl((x, y, z + 0.8 * s), 0.8 * s, 1.6 * s, base, bevel=0.1 * s)
    kit.torus((x, y, z + 1.2 * s), 0.81 * s, 0.05 * s, kit.mat_emit("tRing", color, 9))
    kit.sphere((x, y, z + 2.1 * s), 0.6 * s, head)
    ax, ay, az = aim
    n = math.sqrt(ax * ax + ay * ay + az * az)
    ax, ay, az = ax / n, ay / n, az / n
    tip = (x + ax * 1.4 * s, y + ay * 1.4 * s, z + 2.1 * s + az * 1.4 * s)
    kit.tube([(x, y, z + 2.1 * s), tip], 0.14 * s, base)
    kit.sphere((x + ax * 0.55 * s, y + ay * 0.55 * s, z + 2.1 * s + az * 0.55 * s), 0.18 * s, kit.mat_emit("tCore", color, 10))
    return tip


def boom(loc, r, color="#FFB347"):
    x, y, z = loc
    kit.sphere(loc, r * 0.45, kit.mat_emit("boomCore", "#FFF3B0", 20))
    kit.light_point(loc, 1500, color, radius=r * 0.5)
    m = kit.mat_emit("boomSpark", color, 18)
    rnd = random.Random(int(x * 13 + z))
    for _ in range(36):
        a, e = rnd.uniform(0, 6.28), rnd.uniform(-1, 1)
        d = rnd.uniform(0.5, 1.4) * r
        kit.sphere((x + math.cos(a) * d, y + math.sin(a) * d * 0.6, z + e * d * 0.6), rnd.uniform(0.04, 0.12) * r, m)


def cyber_hero():
    kit.world_gradient("#3A0F8A", "#05010F")
    kit.backdrop("#07021A", "#5B1BB5", glow=0.8)
    kit.sphere((0, 22, 7.0), 6.0, kit.mat_emit("sun", "#FF5AC8", 2.5))
    neon_grid()
    tips = [tower((5.2, 3.0, 0), 1.0, aim=(-1, -0.5, -0.3)), tower((7.5, 6.0, 0), 0.8, aim=(-1, -0.7, -0.35))]
    targets = [(0.8, -1.0, 1.0), (1.8, 0.5, 0.9)]
    for tip, tg in zip(tips, targets):
        kit.tube([tip, tg], 0.05, kit.mat_emit("laser", "#FF3B3B", 30))
    boom((1.3, -0.4, 1.2), 1.0)
    swarm = [(-5.4, -1.6, 1.0, "tank", "#00E5FF"), (-3.2, -2.8, 0.85, "scout", "#39FF88"),
             (-2.2, 0.0, 1.05, "boss", "#FF2BD6"), (-0.6, -2.2, 0.75, "scout", "#FFE07A"),
             (-4.2, 1.2, 0.7, "drone", "#00E5FF"), (-1.0, 1.8, 0.65, "drone", "#39FF88"),
             (-7.0, 0.4, 0.8, "scout", "#FF8A00"), (-5.8, 2.6, 0.7, "scout", "#B266FF"),
             (-3.0, 3.0, 0.75, "tank", "#FFE07A"), (-1.8, -3.6, 0.7, "scout", "#00E5FF"),
             (-6.6, -3.2, 0.72, "scout", "#FF2BD6"), (0.2, 0.6, 0.6, "drone", "#FF8A00")]
    for x, y, s, kind, col in swarm:
        robot((x, y, 0), s, col, kind, facing=R(-70))
    kit.light_area((-6, -9, 8), (0, 0, 1), 1500, "#B0C8FF", size=6)
    kit.light_area((8, 2, 5), (0, 0, 1), 1800, "#FF3B3B", size=4)
    kit.light_area((-8, 4, 5), (0, 0, 1), 1800, "#00E5FF", size=4)
    kit.camera((-1.5, -12.0, 3.2), (-0.5, 1.0, 1.5), lens=32, dof_target=(-2.2, 0.0, 1.2), fstop=8)


def cyber_breach():
    kit.world_gradient("#5A0610", "#0A0105")
    kit.backdrop("#14020A", "#B5121B", glow=0.8)
    neon_grid("#FF3B3B", "#FF8A00")
    for k, (x, y) in enumerate(((2.0, 3.2), (4.6, 2.2), (7.0, 3.6))):
        tip = tower((x, y, 0), 0.95, color="#FFE07A", aim=(-1, -0.6, -0.3))
        kit.tube([tip, (-2.0 + k * 1.2, -1.0 - k * 0.3, 0.9)], 0.045, kit.mat_emit("laser", "#FFE07A", 30))
    boom((4.6, 2.2, 2.2), 1.3, "#FF8A00")
    for x, y, s, kind, col in ((-4.6, -0.8, 0.95, "boss", "#00E5FF"), (-2.6, -2.4, 0.75, "tank", "#39FF88"),
                               (-1.2, -0.6, 0.62, "scout", "#FF2BD6"), (-3.6, 0.8, 0.55, "drone", "#FFE07A"),
                               (0.4, -2.2, 0.6, "scout", "#00E5FF")):
        robot((x, y, 0), s, col, kind, facing=R(-65))
    kit.light_area((-6, -9, 8), (0, 0, 1), 1300, "#FFD0C0", size=6)
    kit.light_area((8, 2, 5), (0, 0, 1), 2000, "#FF8A00", size=4)
    kit.camera((-1.0, -14.5, 3.6), (0.8, 0.8, 1.5), lens=34)


def cyber_army():
    kit.world_gradient("#004A66", "#020A12")
    kit.backdrop("#03121F", "#0090B5", glow=0.9)
    neon_grid("#00E5FF", "#7A5CFF")
    lineup = [(-5.4, "drone", "#39FF88", 0.9), (-2.1, "scout", "#00E5FF", 1.0), (1.5, "tank", "#FFE07A", 1.0),
              (5.4, "boss", "#FF2BD6", 1.15)]
    for x, kind, col, s in lineup:
        kit.cyl((x, 0.5, 0.12), 1.5, 0.24, kit.mat_plastic("ped", "#10182A", 0.3, 0.8), bevel=0.05)
        kit.torus((x, 0.5, 0.25), 1.5, 0.05, kit.mat_emit("pr", col, 10))
        robot((x, 0.5, 0.24), s, col, kind, facing=R(-20))
        kit.spot((x, -3, 7), (x, 0.5, 1.2), 800, col, angle=30)
    kit.light_area((0, -9, 6), (0, 0, 1.2), 1000, size=8)
    kit.camera((0, -14.5, 3.0), (0, 0.5, 1.7), lens=34)


SCENES = {
    "golf": {"hero": golf_hero, "ranked": golf_ranked, "race": golf_race, "skins": golf_skins, "daily": golf_daily},
    "brainrot": {"hero": brainrot_hero, "mutations": brainrot_mutations, "night": brainrot_night},
    "merge": {"hero": merge_hero, "steal": merge_steal, "speed": merge_speed, "tiers": merge_tiers},
    "cyber": {"hero": cyber_hero, "breach": cyber_breach, "army": cyber_army},
}


def main():
    args = [a for a in sys.argv[1:] if a != "--"]
    preview = "--preview" in args
    args = [a for a in args if not a.startswith("--")]
    game, name = args[0], args[1]
    if preview:
        kit.reset(640, 360, samples=12)
    else:
        kit.reset(1920, 1080, samples=32)
    SCENES[game][name]()
    sub = "previews" if preview else "renders"
    out = os.path.join(kit.ROOT, "marketing", game, sub, f"{name}.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    kit.render(out)
    print("WROTE", out)


if __name__ == "__main__":
    main()
