"""Square 3D icon renders: one big hero subject per game, readable at 100 px.

Run: <blender-python> icons3d.py <game> [--preview]   ->  marketing/<game>/icon_render.png
Games: brainrot, cyber, merge. Titles are added afterwards by make_icon.py.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
import scenes as sc  # noqa: E402

R = math.radians
MARKETING = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rim_lights(a, b, key=1600, rim=2600, target=(0, 0, 0)):
    kit.light_area((0, -9, 6), target, key, size=6)
    kit.light_area((-7, 3, 4), target, rim, a, size=3)
    kit.light_area((7, 3, 4), target, rim, b, size=3)


# Brainrot Heist: masked thief grinning beside a stolen glowing brainrot capsule ---------------------

def brainrot():
    kit.world_gradient("#4A0B24", "#0A020C")
    kit.backdrop("#16050E", "#6A0C2A", glow=0.7)
    sc.vault((0, 4.5, 3.6), 3.3)                                   # round vault door framing the head
    red = kit.mat_emit("laserRed", "#FF1E3C", 9)
    for a, b in (((-8, 2.6, 0.8), (8, 2.6, 6.6)), ((-8, 2.6, 6.4), (8, 2.6, 1.2))):
        kit.tube([a, b], 0.03, red)

    skin = kit.mat_plastic("skin", "#FFC98F", 0.45, 0.25)
    mask = kit.mat_plastic("mask", "#121019", 0.4, 0.5)
    beanie = kit.mat_plastic("beanie", "#1E2030", 0.75, 0.1)
    white = kit.mat_plastic("eyeWhite", "#FFFFFF", 0.25, 0.5)
    dark = kit.mat_plastic("pupil", "#0B0A10", 0.2, 0.8)
    hx, hy, hz = 0.0, 0.0, 3.0
    kit.box((hx, hy, hz), (2.6, 2.4, 2.5), skin, bevel=0.7)
    kit.box((hx, hy, hz + 0.22), (2.66, 2.46, 0.85), mask, bevel=0.3)
    kit.cyl((hx, hy, hz + 1.22), 1.36, 0.7, beanie, bevel=0.25)
    kit.torus((hx, hy, hz + 0.96), 1.33, 0.17, beanie)
    for ex in (-0.52, 0.52):                                       # sly glance toward the loot
        kit.sphere((hx + ex, hy - 1.24, hz + 0.24), 0.31, white, scale=(1, 0.3, 0.95))
        kit.sphere((hx + ex + 0.13, hy - 1.32, hz + 0.21), 0.14, dark, scale=(1, 0.35, 1))
        kit.sphere((hx + ex + 0.18, hy - 1.37, hz + 0.29), 0.045, kit.mat_emit("glint", "#FFFFFF", 3))
    brow = kit.mat_plastic("brow", "#0B0A10", 0.5, 0.2)
    for ex, tilt in ((-0.55, -14), (0.55, 20)):
        kit.box((hx + ex, hy - 1.27, hz + 0.8), (0.58, 0.08, 0.13), brow, bevel=0.04, rot=(0, R(tilt), 0))
    smirk = [(hx - 0.5, hy - 1.24, hz - 0.6), (hx - 0.02, hy - 1.27, hz - 0.76), (hx + 0.42, hy - 1.24, hz - 0.62),
             (hx + 0.66, hy - 1.18, hz - 0.42)]
    kit.tube(smirk, 0.07, dark)

    # Loot, close to the camera: money bag (left) and a glowing brainrot capsule (right).
    sack = kit.mat_plastic("sack", "#C98A4B", 0.7, 0.0)
    kit.sphere((-2.35, -1.6, 1.35), 0.95, sack, scale=(1, 0.9, 1.0))
    kit.cyl((-2.35, -1.6, 2.33), 0.24, 0.32, kit.mat_plastic("tie", "#E8B021", 0.4, 0.3), bevel=0.03)
    kit.text3d("$", (-2.35, -2.48, 1.3), 0.95, kit.mat_metal("dollar", "#FFC83D", 0.2), extrude=0.08)
    sc.capsule((2.35, -1.6, 1.95), "#39FF88", h=1.9, r=0.6, mark="?")
    kit.light_point((2.35, -2.5, 2.1), 200, "#39FF88", radius=0.6)
    rim_lights("#FF2440", "#39FF88", key=1400, target=(0, 0, 2.8))
    kit.camera((0, -12.5, 3.3), (0, 0, 4.0), lens=62, dof_target=(0, -1.25, 3.0), fstop=4)


# Cyber Swarm: hero robot charging forward, swarm behind, tower laser ---------------------------------

def cyber():
    kit.world_gradient("#2A0A5E", "#06021A")
    kit.backdrop("#0A0420", "#3A0F7A", glow=0.8)
    sc.neon_grid()
    kit.sphere((0, 22, 9.5), 6.0, kit.mat_emit("sun", "#FF4FD8", 2.2))
    for i, (x, y, s, col) in enumerate(((-4.2, 5.5, 0.75, "#39FF88"), (4.0, 6.0, 0.8, "#FFE07A"),
                                         (-2.2, 9.0, 0.6, "#00E5FF"), (2.4, 10.0, 0.6, "#FF8A00"),
                                         (-5.6, 10.5, 0.55, "#B266FF"), (5.8, 11.0, 0.55, "#00E5FF"))):
        sc.robot((x, y, 0), s, col, "scout" if i % 3 else "tank", facing=R(180 + (x * -4)))
    tip = sc.tower((6.2, 3.0, 0), 0.9, aim=(-1, -0.6, 0.15))
    sc.laser(tip, (1.6, -0.6, 3.6), "#FF3B3B")
    sc.boom((1.9, -0.4, 3.5), 0.45)

    metal = kit.mat_plastic("heroMetal", "#EEF2FA", 0.22, 0.9)
    dark = kit.mat_plastic("heroDark", "#1C2036", 0.35, 0.6)
    cyan = kit.mat_emit("heroGlow", "#00D8FF", 3.2)
    pink = kit.mat_emit("heroPink", "#FF2BD6", 10)
    kit.box((0, 0, 1.0), (3.0, 2.2, 1.4), dark, bevel=0.35)                       # shoulders / body
    kit.box((0, 0, 1.55), (3.05, 2.25, 0.12), pink, bevel=0.04)
    kit.box((0, -0.1, 3.2), (3.2, 2.6, 2.6), metal, bevel=1.0)                    # head
    kit.box((0, -1.3, 3.25), (2.5, 0.14, 1.25), kit.mat_plastic("visor", "#020207", 0.65, 0.0), bevel=0.3)
    for ex in (-0.66, 0.66):                                                      # angry slanted eyes
        kit.box((ex, -1.43, 3.3), (0.86, 0.06, 0.46), cyan, bevel=0.14, rot=(0, R(16 if ex < 0 else -16), 0))
    for sx in (-1, 1):                                                            # ear discs
        kit.cyl((sx * 1.66, -0.1, 3.2), 0.5, 0.25, dark, bevel=0.06, rot=(0, R(90), 0))
        kit.torus((sx * 1.8, -0.1, 3.2), 0.38, 0.05, cyan, rot=(0, R(90), 0))
    kit.cyl((0.7, -0.1, 4.85), 0.06, 0.8, dark, bevel=0.0)
    kit.sphere((0.7, -0.1, 5.35), 0.2, pink)
    kit.box((0, -1.36, 2.42), (1.1, 0.06, 0.12), cyan, bevel=0.03)              # grille
    kit.light_point((0, -3.0, 5.2), 60, "#BFF8FF", radius=0.8)
    rim_lights("#FF2BD6", "#00E5FF", target=(0, 0, 3.0))
    kit.camera((0, -12.5, 2.0), (0, 0, 4.7), lens=48, dof_target=(0, -1.4, 3.2), fstop=7)


# Merge A Egg: two eggs fusing into a cracked, glowing golden egg --------------------------------------

def merge():
    kit.world_gradient("#1C8FD8", "#061E44")
    kit.backdrop("#0A2E5C", "#2E9BE0", glow=0.8)
    kit.cyl((0, 0.4, 0.2), 2.4, 0.4, kit.mat_plastic("pad", "#E9EEF8", 0.25, 0.9), bevel=0.12, verts=96)
    kit.torus((0, 0.4, 0.42), 2.35, 0.08, kit.mat_emit("padRing", "#FFE07A", 10))
    gold = kit.mat_plastic("eggGold", "#FFB000", 0.28, 0.8)
    gb = gold.node_tree.nodes["Principled BSDF"]
    gb.inputs["Metallic"].default_value = 0.75
    gb.inputs["Emission Color"].default_value = kit.hexrgb("#FF9000")
    gb.inputs["Emission Strength"].default_value = 0.08
    big = kit.sphere((0, 0.4, 2.65), 1.6, gold, scale=(1, 1, 1.3))
    taper = big.modifiers.new("Taper", "SIMPLE_DEFORM")
    taper.deform_method = "TAPER"
    taper.factor = -0.28
    taper.deform_axis = "Z"
    crack = kit.mat_emit("crack", "#FFF6C2", 18)
    pts = [(-1.15, -0.62, 3.05), (-0.78, -1.12, 3.45), (-0.42, -1.36, 2.95), (-0.02, -1.45, 3.5), (0.38, -1.38, 2.98),
           (0.78, -1.12, 3.42), (1.15, -0.62, 3.0)]
    for a, b in zip(pts, pts[1:]):
        kit.tube([a, b], 0.075, crack)
    kit.light_point((0, -0.9, 3.1), 120, "#FFE07A", radius=0.5)
    for i, (x, col, spot) in enumerate(((-3.3, "#7FD6FF", "#2F7BD8"), (3.3, "#7AE582", "#2E9C55"))):
        x = x * 0.85
        sc.egg((x, -0.6, 1.25), 0.78, col, spots=spot, glow=0.15)
        sx = -1 if x < 0 else 1
        swirl = [(x - sx * 0.2, -0.9, 2.3), (x * 0.66, -1.5, 3.6), (x * 0.33, -1.2, 3.9), (sx * 0.6, -0.9, 3.3)]
        kit.tube(swirl, 0.07, kit.mat_emit(f"swirl{i}", col, 12))
    spark = kit.mat_emit("spark", "#FFFFFF", 14)
    rnd = random.Random(8)
    for _ in range(26):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(2.0, 3.6)
        kit.sphere((math.cos(a) * r, -0.6 + rnd.uniform(-0.4, 0.4), 3.0 + math.sin(a) * r * 0.75),
                   rnd.uniform(0.03, 0.08), spark)
    rim_lights("#FFE07A", "#FF8BD1", key=1100, target=(0, 0, 2.5))
    kit.camera((0, -12.5, 2.0), (0, 0, 3.9), lens=48, dof_target=(0, -1.2, 2.8), fstop=7)


SCENES = {"brainrot": brainrot, "cyber": cyber, "merge": merge}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = "--preview" in sys.argv
    game = args[0]
    kit.reset(384, 384, samples=10) if preview else kit.reset(1024, 1024, samples=48)
    SCENES[game]()
    out = os.path.join(MARKETING, game, "icon_preview.png" if preview else "icon_render.png")
    kit.render(out)
    print("WROTE", out)


if __name__ == "__main__":
    main()
