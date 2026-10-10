"""Corny Games marketing thumbnails for the other experiences (1920x1080).

Run: python3 marketing/gen_thumbs.py [brainrot|merge] [name ...]
Output: marketing/<game>/thumbnails/<name>.png
Uses the shared drawing kit from chaos-golf/tools/gen_icons.py.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "chaos-golf", "tools"))
import gen_icons as g  # noqa: E402

S, C = g.S, g.C
TOP, BOTTOM = 448, 1600
rgb = g.rgb


# Shared ----------------------------------------------------------------------------------------

def bokeh(cv, rng, n, colors, y0=TOP, y1=TOP + 750, rmin=18, rmax=70, op=0.2):
    for _ in range(n):
        x, y = rng.uniform(0, S), rng.uniform(y0, y1)
        r = rng.uniform(rmin, rmax)
        cv.add(colors[rng.integers(len(colors))], g.m_blur(g.m_circle(x, y, r), r * 0.35), op * rng.uniform(0.4, 1.0))


def title(cv, text, y, size, top, bottom, rotate=2):
    g.draw_text(cv, text, C, y, size, top=top, bottom=bottom, outline=rgb("#14051F"),
                ow=size * 0.15, rotate=rotate, extrude=size * 0.11)


def label(cv, text, x, y, size, col):
    g.draw_text(cv, text, x, y, size, top=g.light(col, 0.55), bottom=col, outline=rgb("#0B0820"),
                ow=size * 0.16, extrude=size * 0.1)


def shadow(cv, x, y, rx, ry, op=0.45):
    cv.over(g.SHADOW, g.m_blur(g.m_ellipse(x, y, rx, ry), ry * 0.9), op)


# Brainrot Heist pieces ---------------------------------------------------------------------------

def moon(cv, x, y, r):
    g.glow(cv, g.m_circle(x, y, r * 1.2), r * 0.6, rgb("#BFD4FF"), 0.5)
    crescent = g.m_sub(g.m_circle(x, y, r), g.m_circle(x + r * 0.42, y - r * 0.18, r * 0.86))
    cv.over(g.vgrad(rgb("#FFFBEA"), rgb("#D9E4FF"), y - r, y + r), crescent)


def lasers(cv, y0, y1, n, col=rgb("#FF2440"), op=0.9):
    for k in range(n):
        x0 = -200 + k * (S + 400) / max(n - 1, 1)
        pts = [(x0, y0), (x0 + 620, y1)]
        cv.add(col, g.m_blur(g.m_line(pts, 26), 22), op * 0.8)
        cv.over(rgb("#FFC2CB"), g.m_line(pts, 7), op)
        pts2 = [(x0 + 620, y0), (x0, y1)]
        cv.add(col, g.m_blur(g.m_line(pts2, 26), 22), op * 0.8)
        cv.over(rgb("#FFC2CB"), g.m_line(pts2, 7), op)


def capsule(cv, x, y, w, h, glow_col, mark="?"):
    """Glass containment capsule with a glowing mystery brainrot inside."""
    body = g.m_rrect(x - w / 2, y - h / 2, x + w / 2, y + h / 2, w * 0.48)
    shadow(cv, x, y + h / 2 + 20, w * 0.7, 28)
    g.glow(cv, body, w * 0.35, glow_col, 0.75)
    cv.over(g.vgrad(g.dark(glow_col, 0.55), g.dark(glow_col, 0.8), y - h / 2, y + h / 2), body, 0.85)
    blob = g.m_ellipse(x, y + h * 0.08, w * 0.3, h * 0.3)
    cv.add(glow_col, g.m_blur(blob, w * 0.12), 1.0)
    cv.over(g.light(glow_col, 0.35), blob, 0.75)
    g.draw_text(cv, mark, x, y + h * 0.06, w * 0.62, top=g.WHITE, bottom=g.light(glow_col, 0.6),
                outline=g.dark(glow_col, 0.75), ow=w * 0.06, extrude=w * 0.03, shadow=None)
    gloss = g.m_rrect(x - w * 0.36, y - h * 0.4, x - w * 0.2, y + h * 0.25, w * 0.1)
    cv.over(g.WHITE, g.m_blur(gloss, 6), 0.35)
    for cy_cap in (y - h / 2, y + h / 2):
        cap = g.m_rrect(x - w * 0.56, cy_cap - h * 0.07, x + w * 0.56, cy_cap + h * 0.07, w * 0.12)
        g.sticker(cv, cap, g.vgrad(rgb("#E9EEF8"), rgb("#58627C"), cy_cap - h * 0.07, cy_cap + h * 0.07),
                  outline=rgb("#14051F"), ow=10, shadow=None)
    ring = g.m_sub(g.m_dilate(body, 10), body)
    cv.over(rgb("#14051F"), ring)


def helix(cv, x, y, h, col1, col2, turns=2.2, amp=110):
    pts1, pts2 = [], []
    for i in range(121):
        t = i / 120
        yy = y - h / 2 + h * t
        a = t * turns * 2 * math.pi
        pts1.append((x + math.sin(a) * amp, yy))
        pts2.append((x - math.sin(a) * amp, yy))
    for i in range(0, 121, 8):
        cv.over(rgb("#FFFFFF"), g.m_line([pts1[i], pts2[i]], 10), 0.55)
    for pts, col in ((pts1, col1), (pts2, col2)):
        cv.add(col, g.m_blur(g.m_line(pts, 30), 18), 0.8)
        cv.over(g.light(col, 0.3), g.m_line(pts, 18))


def brainrot_hero():
    rng = np.random.default_rng(101)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#3B2A8C"), rgb("#07051A"), center=(C, 900), radius=S * 0.85, vignette=0.4)
    for _ in range(90):
        x, y = rng.uniform(0, S), rng.uniform(TOP, 1050)
        cv.add(g.WHITE, g.m_circle(x, y, rng.uniform(1.5, 4)), rng.uniform(0.3, 0.9))
    moon(cv, 1760, 620, 120)
    bokeh(cv, rng, 25, [rgb("#9B7BFF"), rgb("#FF5A8A")], op=0.15)
    floor = g.m_poly([(0, 1300), (S, 1300), (S, BOTTOM + 50), (0, BOTTOM + 50)])
    cv.over(g.vgrad(rgb("#1D1640"), rgb("#0A0818"), 1300, BOTTOM), floor)
    lasers(cv, 1080, 1600, 5, op=0.75)
    vx, vy, vr = 1330, 1215, 250
    g.glow(cv, g.m_circle(vx, vy, vr * 1.1), 110, rgb("#FFB347"), 0.6)
    g.draw_vault(cv, vx, vy, vr, rng)
    hub = g.m_circle(vx, vy, vr * 0.2)
    g.sticker(cv, hub, g.vgrad(rgb("#2B2440"), rgb("#120E22"), vy - vr * 0.2, vy + vr * 0.2),
              outline=rgb("#14051F"), ow=8, shadow=None)
    g.draw_text(cv, "$", vx, vy, vr * 0.3, top=rgb("#C6FF4D"), bottom=rgb("#2EDB6A"),
                outline=rgb("#0B2A14"), ow=8, extrude=4, shadow=None)
    capsule(cv, 660, 1235, 220, 330, rgb("#39FF88"))
    g.draw_sack(cv, 300, 1400, 140, rgb("#C98A4B"))
    g.coin_pile(cv, 1720, 1480, 400, 150, 12, rng)
    title(cv, "BRAINROT", 600, 210, rgb("#C6FF4D"), rgb("#2EDB6A"))
    title(cv, "HEIST", 790, 260, rgb("#FF6B6B"), rgb("#E00033"))
    g.draw_ribbon(cv, C, 1530, 1000, 116, "STEAL · MUTATE · DEFEND", rgb("#E00033"), arc_r=5200, text_size=60)
    g.sparkles(cv, [(260, 660, 50), (1500, 520, 36)], glow_col=rgb("#C6FF4D"))
    return cv


def brainrot_mutations():
    rng = np.random.default_rng(102)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#1F7A5A"), rgb("#04140F"), center=(C, 1050), radius=S * 0.85,
                 rays=(22, rgb("#9BFFCF"), 0.07), vignette=0.4)
    bokeh(cv, rng, 40, [rgb("#9BFFCF"), rgb("#FFE07A"), rgb("#C77DFF")])
    helix(cv, C, 1100, 760, rgb("#39FF88"), rgb("#C77DFF"))
    caps = [(330, rgb("#FFC83D"), "GOLD"), (760, rgb("#7FE9FF"), "DIAMOND"),
            (S - 760, rgb("#B266FF"), "GALAXY"), (S - 330, rgb("#FF4FA3"), "RAINBOW")]
    for x, col, name in caps:
        capsule(cv, x, 1120, 210, 330, col, mark="?")
    title(cv, "RARE MUTATIONS", 630, 210, rgb("#C6FF4D"), rgb("#2EDB6A"))
    g.draw_ribbon(cv, C, 1530, 1060, 110, "STEAL THE RAREST BRAINROTS", rgb("#18A35A"), arc_r=5200, text_size=56)
    return cv


def brainrot_night():
    rng = np.random.default_rng(103)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#2B3FA8"), rgb("#05061A"), center=(C, 950), radius=S * 0.85, vignette=0.45)
    for _ in range(140):
        x, y = rng.uniform(0, S), rng.uniform(TOP, BOTTOM)
        cv.add(g.WHITE, g.m_circle(x, y, rng.uniform(1.5, 4.5)), rng.uniform(0.3, 0.95))
    moon(cv, C, 1050, 300)
    for x, col in ((360, rgb("#FFC83D")), (S - 360, rgb("#7FE9FF")), (680, rgb("#39FF88")), (S - 680, rgb("#FF4FA3"))):
        capsule(cv, x, 1250 if x in (680, S - 680) else 1180, 170, 270, col)
    title(cv, "NIGHT LUCK", 630, 240, rgb("#FFF3B0"), rgb("#FFC83D"))
    g.draw_ribbon(cv, C, 1530, 1100, 110, "BOOSTED LUCK AT NIGHT", rgb("#3B4FD8"), arc_r=5200, text_size=54)
    g.sparkles(cv, [(240, 640, 54), (1820, 700, 44), (C + 420, 860, 34)], glow_col=rgb("#BFD4FF"))
    return cv


# Merge A Egg pieces ---------------------------------------------------------------------------

def m_egg(cx, cy, w, h):
    pts = []
    for i in range(160):
        t = i / 160 * 2 * math.pi
        y = -math.cos(t)
        x = math.sin(t) * (1 - 0.14 * math.cos(t))
        pts.append((cx + x * w / 2, cy + y * h / 2 + h * 0.04))
    return g.m_poly(pts)


def egg(cv, cx, cy, w, h, col, spots=None, glow_col=None, crack=False):
    m = m_egg(cx, cy, w, h)
    shadow(cv, cx, cy + h * 0.52, w * 0.45, h * 0.07)
    if glow_col is not None:
        g.glow(cv, m, w * 0.3, glow_col, 0.8)
    outline = g.m_sub(g.m_dilate(m, max(8, w * 0.04)), m)
    cv.over(rgb("#1A0F2E"), outline)
    cv.over(g.rad(g.light(col, 0.45), g.dark(col, 0.35), (cx - w * 0.18, cy - h * 0.22), max(w, h) * 0.75), m)
    if spots is not None:
        rng = np.random.default_rng(int(cx * 7 + cy))
        for _ in range(7):
            sx = cx + rng.uniform(-0.3, 0.3) * w
            sy = cy + rng.uniform(-0.3, 0.32) * h
            r = rng.uniform(0.05, 0.1) * w
            cv.over(spots, g.m_inter(g.m_ellipse(sx, sy, r, r * 0.8), m), 0.85)
    gloss = g.m_ellipse(cx - w * 0.17, cy - h * 0.2, w * 0.1, h * 0.17)
    cv.over(g.WHITE, g.m_blur(gloss, w * 0.03), 0.6)
    if crack:
        # a hairline crack running down from the top, glowing from inside
        pts = [(cx + w * 0.05, cy - h * 0.47), (cx - w * 0.03, cy - h * 0.36), (cx + w * 0.07, cy - h * 0.27),
               (cx - w * 0.02, cy - h * 0.17), (cx + w * 0.04, cy - h * 0.09)]
        branch = [(cx - w * 0.03, cy - h * 0.36), (cx - w * 0.14, cy - h * 0.31)]
        crack_m = g.m_inter(g.m_union(g.m_line(pts, max(5, w * 0.018)), g.m_line(branch, max(4, w * 0.014))), m)
        cv.add(rgb("#FFF3B0"), g.m_blur(g.m_dilate(crack_m, 6), 12), 1.0)
        cv.over(rgb("#FFFBEA"), crack_m)


def treadmill(cv, x, y, w):
    belt = g.m_rrect(x - w / 2, y - w * 0.07, x + w / 2, y + w * 0.07, w * 0.07)
    shadow(cv, x, y + w * 0.12, w * 0.55, w * 0.05)
    g.sticker(cv, belt, g.vgrad(rgb("#3A3F55"), rgb("#1B1E2B"), y - w * 0.07, y + w * 0.07), outline=rgb("#0B0820"), ow=12)
    for k in range(9):
        sx = x - w * 0.42 + k * w * 0.105
        cv.over(rgb("#5A6180"), g.m_inter(g.m_line([(sx, y - w * 0.05), (sx - w * 0.03, y + w * 0.05)], 8), belt), 0.9)
    post = g.m_rrect(x + w * 0.42, y - w * 0.55, x + w * 0.48, y, 12)
    g.sticker(cv, post, g.vgrad(rgb("#E9EEF8"), rgb("#8A93AD"), y - w * 0.55, y), outline=rgb("#0B0820"), ow=10, shadow=None)
    panel = g.m_rrect(x + w * 0.3, y - w * 0.66, x + w * 0.56, y - w * 0.52, 18)
    g.sticker(cv, panel, g.vgrad(rgb("#2B3150"), rgb("#141729"), y - w * 0.66, y - w * 0.52), outline=rgb("#0B0820"), ow=10, shadow=None)
    cv.add(rgb("#39FF88"), g.m_blur(g.m_rrect(x + w * 0.34, y - w * 0.63, x + w * 0.52, y - w * 0.55, 8), 6), 0.9)


def blocky_runner(cv, x, y, h, shirt=rgb("#FF4FA3"), pants=rgb("#2E3A8C"), skin=rgb("#FFD8A8")):
    """Simple blocky avatar mid-stride (feet at y)."""
    u = h / 6
    def part(cx, cy, w, hh, col, ang):
        m = g.m_rotate(g.m_rrect(cx - w / 2, cy - hh / 2, cx + w / 2, cy + hh / 2, u * 0.18), ang, cx, cy)
        g.sticker(cv, m, g.vgrad(g.light(col, 0.15), g.dark(col, 0.2), cy - hh / 2, cy + hh / 2),
                  outline=rgb("#0B0820"), ow=8, shadow=None)
    part(x - u * 0.55, y - u * 1.0, u * 0.9, u * 2.1, pants, 28)    # back leg
    part(x - u * 0.9, y - u * 3.2, u * 0.75, u * 2.0, skin, -40)     # back arm
    part(x, y - u * 3.1, u * 2.0, u * 2.1, shirt, 0)                 # torso
    part(x + u * 0.55, y - u * 1.0, u * 0.9, u * 2.1, pants, -28)   # front leg
    part(x + u * 0.95, y - u * 3.2, u * 0.75, u * 2.0, skin, 40)    # front arm
    part(x, y - u * 4.9, u * 1.35, u * 1.35, skin, 0)                # head
    for ex in (-0.28, 0.28):
        cv.over(rgb("#0B0820"), g.m_circle(x + ex * u, y - u * 4.95, u * 0.11))


def speed_lines(cv, x0, x1, y0, y1, n, rng, col=g.WHITE):
    for _ in range(n):
        y = rng.uniform(y0, y1)
        a = rng.uniform(x0, x1 - 200)
        cv.over(col, g.m_line([(a, y), (a + rng.uniform(120, 320), y)], rng.uniform(5, 10)), rng.uniform(0.4, 0.85))


def merger(cv, x, y, w):
    """Base merger machine: two input chutes, a glowing chamber."""
    body = g.m_rrect(x - w / 2, y - w * 0.45, x + w / 2, y + w * 0.35, w * 0.12)
    shadow(cv, x, y + w * 0.4, w * 0.6, w * 0.06)
    g.sticker(cv, body, g.vgrad(rgb("#E9EEF8"), rgb("#7D86A3"), y - w * 0.45, y + w * 0.35), outline=rgb("#0B0820"), ow=14)
    chamber = g.m_circle(x, y - w * 0.05, w * 0.26)
    g.glow(cv, chamber, w * 0.18, rgb("#FFE07A"), 0.9)
    cv.over(g.rad(rgb("#FFF8D6"), rgb("#FF9F1C"), (x, y - w * 0.05), w * 0.26), chamber)
    cv.over(rgb("#0B0820"), g.m_sub(g.m_dilate(chamber, 10), chamber))
    for sx in (-1, 1):
        chute = g.m_rrect(x + sx * w * 0.5 - w * 0.09, y - w * 0.7, x + sx * w * 0.5 + w * 0.09, y - w * 0.3, 16)
        g.sticker(cv, chute, g.vgrad(rgb("#C9D1E3"), rgb("#6A7391"), y - w * 0.7, y - w * 0.3), outline=rgb("#0B0820"), ow=10, shadow=None)


def merge_hero():
    rng = np.random.default_rng(201)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#3FD3FF"), rgb("#0B2A5A"), center=(C, 1000), radius=S * 0.85,
                 rays=(20, rgb("#E6FBFF"), 0.08), vignette=0.3)
    bokeh(cv, rng, 40, [rgb("#E6FBFF"), rgb("#FFE07A"), rgb("#FF9EDB")])
    ground = g.m_ellipse(C, 1580, 1250, 260)
    cv.over(g.vgrad(rgb("#6BE37A"), rgb("#2E9C55"), 1320, 1840), ground)
    merger(cv, C, 1230, 420)
    egg(cv, 470, 1150, 220, 290, rgb("#7FC8FF"), spots=rgb("#2F7BD8"))
    egg(cv, S - 470, 1150, 220, 290, rgb("#7FC8FF"), spots=rgb("#2F7BD8"))
    for sx in (-1, 1):  # arrows from each egg into the merger
        arrow = g.m_poly([(C + sx * 590, 1135), (C + sx * 480, 1135), (C + sx * 480, 1095), (C + sx * 390, 1170),
                          (C + sx * 480, 1245), (C + sx * 480, 1205), (C + sx * 590, 1205)], 12)
        g.sticker(cv, arrow, g.vgrad(rgb("#FFF3B0"), rgb("#FFB000"), 1095, 1245), outline=rgb("#14051F"), ow=12)
    egg(cv, C, 980, 230, 300, rgb("#FFC83D"), spots=rgb("#FF7A00"), glow_col=rgb("#FFE07A"), crack=True)
    title(cv, "MERGE A EGG", 640, 230, rgb("#FFF36B"), rgb("#FF8A00"))
    g.draw_ribbon(cv, C, 1530, 1040, 110, "STEAL · MERGE · UPGRADE", rgb("#2F7BD8"), arc_r=5200, text_size=60)
    g.sparkles(cv, [(1820, 760, 54), (C + 230, 830, 36), (240, 720, 44)], glow_col=rgb("#FFE07A"))
    return cv


def merge_steal():
    rng = np.random.default_rng(204)
    cv = g.Canvas(color=g.NAVY)
    biomes = [rgb("#4FBF5A"), rgb("#BFE6FF"), rgb("#F2C66B"), rgb("#FF5A2E")]
    w = S / 4
    for k, col in enumerate(biomes):
        x0 = k * w
        quad = g.m_poly([(x0 - 60, TOP), (x0 + w + 60, TOP), (x0 + w - 60, BOTTOM), (x0 - 180, BOTTOM)])
        cv.over(g.vgrad(g.light(col, 0.25), g.dark(col, 0.35), TOP, BOTTOM), quad)
    for k in range(1, 4):
        x0 = k * w
        cv.over(rgb("#14051F"), g.m_line([(x0 + 60, TOP), (x0 - 60, BOTTOM)], 14))
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.hypot(xs - C, ys - 1050) / (S * 0.72)
    cv.over_arr(g.SHADOW, np.clip(d - 0.5, 0, 1) ** 1.6 * 0.6)
    eggs = [(rgb("#7AE582"), rgb("#2E9C55")), (rgb("#E6F6FF"), rgb("#7FC8FF")), (rgb("#FFE29A"), rgb("#E8A33D")), (rgb("#FF8A5C"), rgb("#B3261E"))]
    for k, (col, spot) in enumerate(eggs):
        x = k * w + w / 2
        y = 1230 + (k % 2) * 40
        speed_lines(cv, x - 420, x - 120, y - 140, y + 120, 6, rng)
        egg(cv, x, y, 200, 260, col, spots=spot, glow_col=col if k == 3 else None)
    title(cv, "STEAL EGGS", 640, 250, rgb("#FFF36B"), rgb("#FF8A00"))
    g.sparkles(cv, [(1840, 640, 50), (220, 700, 42)], glow_col=rgb("#FFE07A"))
    return cv


def merge_speed():
    rng = np.random.default_rng(205)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#FF7A59"), rgb("#2A0A3A"), center=(C, 1050), radius=S * 0.85,
                 rays=(22, rgb("#FFE7A3"), 0.08), vignette=0.35)
    bokeh(cv, rng, 30, [rgb("#FFE7A3"), rgb("#FF9EDB")])
    speed_lines(cv, 0, 1000, 950, 1350, 22, rng)
    treadmill(cv, 900, 1420, 720)
    blocky_runner(cv, 880, 1380, 520)
    bolt = g.m_poly([(1560, 900), (1700, 900), (1620, 1090), (1730, 1090), (1520, 1400), (1580, 1160), (1470, 1160)])
    g.glow(cv, bolt, 60, rgb("#FFE07A"), 0.9)
    g.sticker(cv, bolt, g.vgrad(rgb("#FFF6C0"), rgb("#FFB000"), 900, 1400), outline=rgb("#14051F"), ow=14)
    label(cv, "SPEED +", 1600, 1500, 90, rgb("#FFC83D"))
    title(cv, "TRAIN YOUR SPEED", 630, 210, rgb("#FFF36B"), rgb("#FF8A00"))
    return cv


def merge_tiers():
    rng = np.random.default_rng(202)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#B04DFF"), rgb("#1A0636"), center=(C, 1100), radius=S * 0.85,
                 rays=(22, rgb("#FFD1F0"), 0.08), vignette=0.35)
    bokeh(cv, rng, 40, [rgb("#FFD1F0"), rgb("#FFE07A"), rgb("#9BE8FF")])
    tiers = [(rgb("#F4F6FA"), rgb("#C9D1E3")), (rgb("#7AE582"), rgb("#2E9C55")), (rgb("#7FC8FF"), rgb("#2F7BD8")),
             (rgb("#C77DFF"), rgb("#7A2BFF")), (rgb("#FFC83D"), rgb("#FF7A00")), (rgb("#FF4FA3"), rgb("#7A00FF"))]
    xs = np.linspace(230, S - 230, len(tiers))
    for k, (x, (col, spot)) in enumerate(zip(xs, tiers)):
        w = 170 + k * 26
        h = w * 1.3
        y = 1330 - h / 2
        egg(cv, x, y, w, h, col, spots=spot, glow_col=col if k >= 3 else None)
        g.draw_badge(cv, x + w * 0.38, y - h * 0.42, 52, str(k + 1), g.dark(spot, 0.1))
        if k < len(tiers) - 1:
            g.draw_text(cv, "›", (x + xs[k + 1]) / 2 + 10, 1220, 120, top=g.WHITE, bottom=rgb("#FFD1F0"),
                        outline=rgb("#14051F"), ow=14, extrude=8)
    title(cv, "MERGE TO EVOLVE", 640, 210, rgb("#FFF36B"), rgb("#FF8A00"))
    g.draw_ribbon(cv, C, 1530, 980, 110, "THE RAREST EGGS AWAIT", rgb("#7A2BFF"), arc_r=5200, text_size=58)
    return cv


# Cyber Swarm pieces ------------------------------------------------------------------------------

def synth_floor(cv, horizon, col=rgb("#FF2BD6"), col2=rgb("#00E5FF")):
    floor = g.m_poly([(0, horizon), (S, horizon), (S, BOTTOM + 60), (0, BOTTOM + 60)])
    cv.over(g.vgrad(rgb("#1A0636"), rgb("#05010F"), horizon, BOTTOM), floor)
    for k in range(-12, 13):
        x_far = C + k * 60
        x_near = C + k * 420
        cv.add(col, g.m_blur(g.m_line([(x_far, horizon), (x_near, BOTTOM + 60)], 10), 8), 0.55)
        cv.over(g.light(col, 0.4), g.m_line([(x_far, horizon), (x_near, BOTTOM + 60)], 3), 0.7)
    y, step = horizon + 12, 14.0
    while y < BOTTOM + 60:
        cv.add(col2, g.m_blur(g.m_line([(0, y), (S, y)], 8), 6), 0.45)
        cv.over(g.light(col2, 0.4), g.m_line([(0, y), (S, y)], 3), 0.6)
        y += step
        step *= 1.32
    cv.add(col, g.m_blur(g.m_line([(0, horizon), (S, horizon)], 24), 30), 0.9)


def robot(cv, x, y, size, col, kind="scout"):
    """Cute cyber robot. (x, y) = feet centre."""
    u = size
    shadow(cv, x, y + u * 0.04, u * 0.55, u * 0.1)
    dark = rgb("#0B0820")
    metal = g.vgrad(rgb("#F1F4FB"), rgb("#8E98B6"), y - u * 1.4, y)
    if kind == "drone":
        y -= u * 0.5
        body = g.m_circle(x, y - u * 0.55, u * 0.42)
        for sx in (-1, 1):
            ax0, ax1 = sorted((x + sx * u * 0.35, x + sx * u * 0.72))
            arm = g.m_rrect(ax0, y - u * 0.98, ax1, y - u * 0.9, 8)
            g.sticker(cv, arm, metal, outline=dark, ow=8, shadow=None)
            rotor = g.m_ellipse(x + sx * u * 0.72, y - u * 1.0, u * 0.28, u * 0.06)
            cv.over(g.light(col, 0.4), rotor, 0.8)
        g.sticker(cv, body, metal, outline=dark, ow=10, shadow=None)
        visor = g.m_rrect(x - u * 0.26, y - u * 0.68, x + u * 0.26, y - u * 0.46, u * 0.1)
    else:
        w = {"scout": 0.7, "tank": 1.05, "boss": 1.2}.get(kind, 0.8) * u
        h = {"scout": 0.8, "tank": 0.75, "boss": 1.15}.get(kind, 0.8) * u
        legs = g.m_rrect(x - w * 0.42, y - u * 0.28, x + w * 0.42, y, u * 0.1)
        g.sticker(cv, legs, g.vgrad(rgb("#3A3F55"), rgb("#14172A"), y - u * 0.28, y), outline=dark, ow=8, shadow=None)
        body = g.m_rrect(x - w / 2, y - u * 0.22 - h, x + w / 2, y - u * 0.22, u * 0.22)
        g.sticker(cv, body, metal, outline=dark, ow=10, shadow=None)
        stripe = g.m_inter(g.m_rrect(x - w / 2, y - u * 0.22 - h * 0.28, x + w / 2, y - u * 0.22 - h * 0.14, 6), body)
        cv.over(col, stripe)
        visor = g.m_rrect(x - w * 0.36, y - u * 0.22 - h * 0.86, x + w * 0.36, y - u * 0.22 - h * 0.5, u * 0.12)
        ant_top = (x + w * 0.2, y - u * 0.22 - h - u * 0.3)
        cv.over(dark, g.m_line([(x + w * 0.2, y - u * 0.22 - h), ant_top], 8))
        g.glow(cv, g.m_circle(*ant_top, u * 0.08), u * 0.1, col, 0.9)
        cv.over(g.light(col, 0.4), g.m_circle(*ant_top, u * 0.07))
        if kind == "boss":
            for sx in (-1, 1):
                horn = g.m_poly([(x + sx * w * 0.3, y - u * 0.22 - h + 6), (x + sx * w * 0.5, y - u * 0.22 - h - u * 0.35),
                                 (x + sx * w * 0.12, y - u * 0.22 - h + 6)])
                g.sticker(cv, horn, g.vgrad(g.light(col, 0.3), col, y - u * 1.6, y - u), outline=dark, ow=8, shadow=None)
    cv.over(rgb("#0D1024"), visor)
    vy = g.m_sub(visor, g.m_shift(visor, 0, -6))
    g.glow(cv, visor, u * 0.1, col, 0.6)
    bb = visor.getbbox()
    if bb:
        ex = (bb[0] + bb[2]) / 2
        ey = (bb[1] + bb[3]) / 2
        for sx in (-1, 1):
            eye = g.m_rrect(ex + sx * u * 0.13 - u * 0.06, ey - u * 0.05, ex + sx * u * 0.13 + u * 0.06, ey + u * 0.05, 6)
            cv.add(col, g.m_blur(eye, 6), 1.0)
            cv.over(g.light(col, 0.6), eye)
    cv.over(g.WHITE, vy, 0.25)


def tower(cv, x, y, size, col=rgb("#FF3B3B"), aim=(-1, 0.3)):
    u = size
    dark = rgb("#0B0820")
    shadow(cv, x, y + u * 0.05, u * 0.6, u * 0.12)
    base = g.m_rrect(x - u * 0.45, y - u * 0.7, x + u * 0.45, y, u * 0.12)
    g.sticker(cv, base, g.vgrad(rgb("#4A4F6A"), rgb("#1E2133"), y - u * 0.7, y), outline=dark, ow=10, shadow=None)
    cv.over(col, g.m_rrect(x - u * 0.45, y - u * 0.42, x + u * 0.45, y - u * 0.34, 4), 0.9)
    head = g.m_circle(x, y - u * 0.95, u * 0.36)
    ax, ay = aim
    n = math.hypot(ax, ay)
    ax, ay = ax / n, ay / n
    tip = (x + ax * u * 0.9, y - u * 0.95 + ay * u * 0.9)
    cv.over(dark, g.m_line([(x, y - u * 0.95), tip], u * 0.2))
    cv.over(rgb("#8E98B6"), g.m_line([(x, y - u * 0.95), tip], u * 0.13))
    g.sticker(cv, head, g.vgrad(rgb("#E9EEF8"), rgb("#6A7391"), y - u * 1.3, y - u * 0.6), outline=dark, ow=10, shadow=None)
    core = g.m_circle(x, y - u * 0.95, u * 0.13)
    g.glow(cv, core, u * 0.12, col, 0.9)
    cv.over(g.light(col, 0.5), core)
    return tip


def laser(cv, a, b, col, w=14):
    cv.add(col, g.m_blur(g.m_line([a, b], w * 2.5), w * 2), 0.9)
    cv.over(g.light(col, 0.7), g.m_line([a, b], w * 0.5))


def boom(cv, x, y, r, col=rgb("#FFB347")):
    g.draw_firework(cv, x, y, r, col, rays=14)
    g.glow(cv, g.m_circle(x, y, r * 0.45), r * 0.4, rgb("#FFF3B0"), 0.9)


def cyber_hero():
    rng = np.random.default_rng(301)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#5B1BB5"), rgb("#07021A"), center=(C, 1000), radius=S * 0.8, vignette=0.2)
    sun = g.m_circle(C, 1080, 300)
    cv.over(g.vgrad(rgb("#FFE07A"), rgb("#FF2BD6"), 780, 1080), g.m_inter(sun, g.m_poly([(0, 0), (S, 0), (S, 1080), (0, 1080)])), 0.85)
    synth_floor(cv, 1080)
    t1 = tower(cv, 1700, 1300, 210, aim=(-1, 0.35))
    t2 = tower(cv, 1880, 1080 + 90, 150, aim=(-1, 0.6))
    laser(cv, t1, (1180, 1370), rgb("#FF3B3B"))
    laser(cv, t2, (1380, 1300), rgb("#FF3B3B"), 10)
    boom(cv, 1180, 1320, 150)
    swarm = [(260, 1530, 150, "tank", rgb("#00E5FF")), (520, 1450, 130, "scout", rgb("#39FF88")),
             (760, 1500, 140, "boss", rgb("#FF2BD6")), (980, 1400, 110, "scout", rgb("#FFE07A")),
             (420, 1300, 100, "drone", rgb("#00E5FF")), (860, 1240, 90, "drone", rgb("#39FF88")),
             (1080, 1500, 120, "tank", rgb("#FF8A00"))]
    for x, y, sz, kind, col in sorted(swarm, key=lambda r: r[1]):
        robot(cv, x, y, sz, col, kind)
    title(cv, "CYBER", 600, 240, rgb("#7FFBFF"), rgb("#00B4FF"))
    title(cv, "SWARM", 820, 280, rgb("#FFB0F5"), rgb("#FF2BD6"))
    g.draw_ribbon(cv, C, 1535, 1080, 112, "REVERSE TOWER DEFENSE", rgb("#7A1BD8"), arc_r=5200, text_size=60)
    return cv


def cyber_breach():
    rng = np.random.default_rng(302)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#B5121B"), rgb("#14020A"), center=(C, 1050), radius=S * 0.85,
                 rays=(20, rgb("#FFB0B0"), 0.07), vignette=0.35)
    synth_floor(cv, 1120, col=rgb("#FF3B3B"), col2=rgb("#FF8A00"))
    tips = []
    for k, x in enumerate((1250, 1500, 1750)):
        tips.append(tower(cv, x, 1260 + k * 40, 190, aim=(-1, 0.4)))
    for tip, tgt in zip(tips, ((700, 1420), (900, 1350), (1050, 1460))):
        laser(cv, tip, tgt, rgb("#FFE07A"), 11)
    boom(cv, 1500, 1060, 220, rgb("#FF8A00"))
    for x, y, sz, kind, col in ((300, 1560, 170, "boss", rgb("#00E5FF")), (620, 1480, 140, "tank", rgb("#39FF88")),
                                (880, 1430, 120, "scout", rgb("#FF2BD6")), (1060, 1530, 120, "scout", rgb("#00E5FF")),
                                (560, 1250, 100, "drone", rgb("#FFE07A"))):
        robot(cv, x, y, sz, col, kind)
    title(cv, "BREAK THE DEFENSE", 630, 168, rgb("#FFF36B"), rgb("#FF8A00"))
    return cv


def cyber_army():
    rng = np.random.default_rng(303)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#00A3C4"), rgb("#03121F"), center=(C, 1050), radius=S * 0.85,
                 rays=(22, rgb("#9BFFF7"), 0.08), vignette=0.35)
    synth_floor(cv, 1250, col=rgb("#00E5FF"), col2=rgb("#7A5CFF"))
    lineup = [(330, "drone", rgb("#39FF88"), 150, "1"), (700, "scout", rgb("#00E5FF"), 170, "2"),
              (1120, "tank", rgb("#FFE07A"), 190, "3"), (1600, "boss", rgb("#FF2BD6"), 230, "4")]
    for x, kind, col, sz, lvl in lineup:
        cv.add(col, g.m_blur(g.m_ellipse(x, 1440, sz * 0.8, sz * 0.18), 30), 0.8)
        robot(cv, x, 1440, sz, col, kind)
        g.draw_badge(cv, x + sz * 0.55, 1440 - sz * 1.45, 48, lvl, g.dark(col, 0.2))
    title(cv, "UNLEASH THE SWARM", 630, 168, rgb("#7FFBFF"), rgb("#00B4FF"))
    g.draw_ribbon(cv, C, 1535, 1000, 110, "PUSH PAST THE TOWERS", rgb("#0E7FA8"), arc_r=5200, text_size=58)
    return cv


GAMES = {
    "brainrot": {"hero": brainrot_hero, "mutations": brainrot_mutations, "night": brainrot_night},
    "merge": {"hero": merge_hero, "steal": merge_steal, "speed": merge_speed, "tiers": merge_tiers},
    "cyber": {"hero": cyber_hero, "breach": cyber_breach, "army": cyber_army},
}


def main(argv):
    game = argv[0]
    wanted = argv[1:] or list(GAMES[game])
    out_dir = os.path.join(HERE, game, "thumbnails")
    os.makedirs(out_dir, exist_ok=True)
    for name in wanted:
        img = GAMES[game][name]().to_image().crop((0, TOP, S, BOTTOM)).resize((1920, 1080), Image.LANCZOS)
        path = os.path.join(out_dir, f"{name}.png")
        img.convert("RGB").save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main(sys.argv[1:])
