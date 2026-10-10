"""Ultimate Golf - polished 1920x1080 experience thumbnails (feature set).

Run: python3 tools/gen_thumbnails.py [name ...]  ->  assets/thumbnails/<name>.png
Names: hero, ranked, race, skins, daily
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_icons as g  # noqa: E402
from PIL import Image  # noqa: E402

S, C = g.S, g.C
TOP, BOTTOM = 448, 1600          # the 16:9 band of the square working canvas
OUT = os.path.join(os.path.dirname(g.OUT_DIR), "thumbnails")
rgb = g.rgb


# Shared polish ---------------------------------------------------------------------------------

def bokeh(cv, rng, n, colors, y0=TOP, y1=TOP + 700, rmin=18, rmax=70, op=0.22):
    for _ in range(n):
        x, y = rng.uniform(0, S), rng.uniform(y0, y1)
        r = rng.uniform(rmin, rmax)
        col = colors[rng.integers(len(colors))]
        cv.add(col, g.m_blur(g.m_circle(x, y, r), r * 0.35), op * rng.uniform(0.4, 1.0))


def beams(cv, x, y, col, n=5, spread=0.9, length=1400, width=0.05, op=0.18, rot=-math.pi / 2):
    for k in range(n):
        a = rot + (k - (n - 1) / 2) * spread / max(n - 1, 1)
        p1 = (x + math.cos(a) * length, y + math.sin(a) * length)
        cv.add(col, g.m_blur(g.m_line([(x, y), p1], length * width), 40), op)


def headline(cv, text, y, size, top=rgb("#FFF36B"), bottom=rgb("#FF8A00"), rotate=2):
    g.draw_text(cv, text, C, y, size, top=top, bottom=bottom, outline=rgb("#1A0636"),
                ow=size * 0.15, rotate=rotate, extrude=size * 0.11)


def brand(cv):
    """Small ULTIMATE GOLF lockup, top-left."""
    g.draw_text(cv, "ULTIMATE", 300, TOP + 92, 74, top=rgb("#FFF36B"), bottom=rgb("#FF8A00"),
                outline=rgb("#1A0636"), ow=12, extrude=8, rotate=2)
    g.draw_text(cv, "GOLF", 300, TOP + 172, 96, top=g.WHITE, bottom=rgb("#7FEFFF"),
                outline=rgb("#1A0636"), ow=14, extrude=10, rotate=2)


def trail(cv, pts, col, w):
    line = g.m_line(pts, w)
    cv.add(col, g.m_blur(line, w * 1.4), 0.8)
    cv.over(g.light(col, 0.45), line, 0.9)


def ball(cv, x, y, r, col, col2=None, emissive=0.0, metal=False, glow_col=None, rim=(0.35, 0.85, 1.0)):
    if glow_col is not None:
        g.glow(cv, g.m_circle(x, y, r * 1.15), r * 0.45, glow_col, 0.6)
    g.draw_golf_ball(cv, (x, y), r, col, base_color2=col2, emissive=emissive, metal=metal,
                     rim_color=rim, dimples=72 if r > 150 else 60)


def ground_shadow(cv, x, y, rx, ry, op=0.45):
    cv.over(g.SHADOW, g.m_blur(g.m_ellipse(x, y, rx, ry), ry * 0.9), op)


# Thumbnails ---------------------------------------------------------------------------------------

def hero():
    rng = np.random.default_rng(11)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#9B3BFF"), rgb("#12062E"), center=(C, 980), radius=S * 0.8,
                 rays=(22, rgb("#FF8BD1"), 0.07), vignette=0.3)
    beams(cv, 260, TOP - 60, rgb("#7FEFFF"), n=3, rot=math.pi * 0.32, op=0.12)
    beams(cv, S - 260, TOP - 60, rgb("#FFB0F0"), n=3, rot=math.pi * 0.68, op=0.12)
    bokeh(cv, rng, 40, [rgb("#FF8BD1"), rgb("#7FEFFF"), rgb("#FFE07A")])

    gy = 1400
    g.draw_green(cv, C + 120, gy, 1040, 190, 130)
    red, cyan = rgb("#FF2D55"), rgb("#00E5FF")
    g.draw_crate(cv, 320, 1240, 330, red, metal="gold", emblem=g.emblem_image("ball", red, "gold"),
                 aura=rgb("#FFB0C0"))
    g.draw_crate(cv, 600, 1335, 205, cyan, metal="steel", emblem=g.emblem_image("ball", cyan, "steel"))

    g.draw_cup(cv, 1650, gy + 20, 125, 40)
    g.draw_flag(cv, 1700, gy + 22, 560, rgb("#FFD000"), flag_w=300)
    g.draw_confetti(cv, rng, 70, 1650, gy - 220, 170, 120, 22,
                    [rgb("#FF4FA3"), rgb("#7FEFFF"), rgb("#FFE07A"), rgb("#6BE37A")], bias_up=160)

    bx, by, br = 1190, 1210, 150
    ground_shadow(cv, bx + 30, gy + 8, br * 0.9, br * 0.2)
    l1 = (930, gy - 10)
    for dx, dy, col, w in ((0, 0, cyan, 40), (-10, 24, rgb("#FF00A0"), 24), (8, -20, rgb("#FFD000"), 16)):
        for pts in (g._qbez((720, 1150), (820, 1000), l1), g._qbez(l1, (1050, 1040), (bx, by))):
            trail(cv, [(x + dx, y + dy) for x, y in pts], col, w)
    ring = g.m_sub(g.m_ellipse(l1[0], l1[1], 110, 30), g.m_ellipse(l1[0], l1[1], 88, 21))
    cv.add(rgb("#BFF3FF"), g.m_blur(ring, 6), 0.7)
    ball(cv, bx, by, br, rgb("#F7F9FF"), glow_col=cyan, rim=(0.2, 0.95, 1.0))

    headline(cv, "ULTIMATE", 640, 230)
    headline(cv, "GOLF", 850, 300, top=g.WHITE, bottom=rgb("#7FEFFF"))
    g.sparkles(cv, [(1820, 620, 54), (230, 700, 44), (1480, 560, 30), (560, 990, 26)], glow_col=rgb("#FF8BD1"))
    g.draw_ribbon(cv, C, 1535, 1180, 120, "MULTIPLAYER CHAOS MINI-GOLF", rgb("#FF2D8A"), arc_r=5200, text_size=58)
    return cv


def ranked():
    rng = np.random.default_rng(22)
    cv = g.Canvas(color=g.NAVY)
    cv.over_arr(g.lin(rgb("#FF3D2E"), rgb("#2E5BFF"), (C - 520, C), (C + 520, C)), np.ones((S, S), np.float32))
    cv.add_arr(rgb("#FFFFFF"), g.rays_alpha(C, 1120, 26, 0.05, width=0.3, r1=S) * 0.07)
    bokeh(cv, rng, 30, [rgb("#FFD0C0"), rgb("#C0D4FF")], op=0.18)
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.hypot(xs - C, ys - 1050) / (S * 0.72)
    cv.over_arr(g.SHADOW, np.clip(d - 0.45, 0, 1) ** 1.5 * 0.6)

    # arena floor
    floor = g.m_ellipse(C, 1480, 1150, 210)
    cv.over(g.vgrad(rgb("#2A2F48"), rgb("#12141F"), 1280, 1690), floor)
    cv.add(rgb("#FFC83D"), g.m_blur(g.m_sub(floor, g.m_shift(floor, 0, 12)), 8), 0.8)

    lx, rx, by, br = 560, 1490, 1180, 250
    for x, c1, c2, glow_c in ((lx, rgb("#FF4A00"), rgb("#FFB000"), rgb("#FF7A3C")),
                              (rx, rgb("#7A00FF"), rgb("#00E5FF"), rgb("#6FA8FF"))):
        ground_shadow(cv, x, 1440, br * 0.9, br * 0.2, 0.55)
        ball(cv, x, by, br, c1, c2, emissive=0.3, glow_col=glow_c, rim=(1.0, 0.9, 0.6))
    g.draw_crown(cv, lx, by - br - 70, 230, 150, angle=-12)

    # VS bolt
    bolt = g.m_poly([(C - 40, 920), (C + 90, 920), (C + 10, 1110), (C + 110, 1110),
                     (C - 70, 1390), (C - 10, 1170), (C - 110, 1170)])
    g.glow(cv, bolt, 60, rgb("#FFE07A"), 0.9)
    g.sticker(cv, bolt, rgb("#FFF3A0"), outline=rgb("#1A0636"), ow=14)
    g.draw_text(cv, "VS", C, 1180, 210, top=g.WHITE, bottom=rgb("#FFE07A"), outline=rgb("#1A0636"),
                ow=30, extrude=22, rotate=-4)

    headline(cv, "RANKED 1V1", 620, 220)
    for x, label, col in ((lx, "GOLD III", rgb("#FFC83D")), (rx, "DIAMOND I", rgb("#7FD8FF"))):
        g.draw_text(cv, label, x, 1525, 78, top=g.light(col, 0.5), bottom=col, outline=rgb("#0B0820"),
                    ow=12, extrude=8)
    # (no corner lockup: these sit on the game page next to the title)
    g.sparkles(cv, [(1840, 600, 50), (210, 760, 40), (C + 360, 860, 30)], glow_col=rgb("#FFE07A"))
    return cv


def race():
    rng = np.random.default_rng(33)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#00B4FF"), rgb("#071330"), center=(C, 900), radius=S * 0.85,
                 rays=(20, rgb("#9BE8FF"), 0.07), vignette=0.35)
    bokeh(cv, rng, 40, [rgb("#9BE8FF"), rgb("#FF8BD1"), rgb("#FFE07A")])

    # neon track sweeping toward the cup
    track_pts = g._qbez((-120, 1560), (900, 980), (2150, 1240), n=80)
    cv.over(rgb("#141A33"), g.m_line(track_pts, 330))
    cv.add(rgb("#00E5FF"), g.m_blur(g.m_line([(x, y - 165) for x, y in track_pts], 14), 10), 0.9)
    cv.over(rgb("#BFF6FF"), g.m_line([(x, y - 165) for x, y in track_pts], 8))
    cv.add(rgb("#FF00A0"), g.m_blur(g.m_line([(x, y + 165) for x, y in track_pts], 14), 10), 0.9)
    cv.over(rgb("#FFC4E8"), g.m_line([(x, y + 165) for x, y in track_pts], 8))

    g.draw_green(cv, 1830, 1270, 230, 70, 50)
    g.draw_cup(cv, 1830, 1270, 70, 24)
    g.draw_flag(cv, 1860, 1272, 380, rgb("#FFD000"), flag_w=200)

    racers = [  # (t along track, lane offset, colour, colour2, radius)
        (0.80, -60, rgb("#FFD000"), rgb("#FF8A00"), 112),
        (0.70, 70, rgb("#FF2D55"), None, 104),
        (0.60, -10, rgb("#6BE37A"), None, 96),
        (0.50, 95, rgb("#B04DFF"), rgb("#00E5FF"), 90),
        (0.41, -85, rgb("#F7F9FF"), None, 84),
        (0.32, 40, rgb("#FF8BD1"), None, 78),
        (0.23, -40, rgb("#3D8BFF"), None, 72),
        (0.15, 80, rgb("#FF7A00"), None, 66),
    ]
    n = len(track_pts) - 1
    for t, off, c1, c2, r in reversed(racers):
        i = int(t * n)
        x, y = track_pts[i]
        y += off * 0.6
        tail = [(px, py + off * 0.6) for px, py in track_pts[max(0, i - 14):i + 1]]
        trail(cv, tail, c1, r * 0.55)
        ground_shadow(cv, x + 10, y + r * 0.85, r * 0.8, r * 0.18, 0.4)
        ball(cv, x, y - r * 0.2, r, c1, c2, emissive=0.15 if c2 is not None else 0.0)

    # knockout burst between two racers
    kx, ky = track_pts[int(0.655 * n)]
    g.draw_firework(cv, kx, ky - 40, 210, rgb("#FFE07A"), rays=16)
    g.draw_text(cv, "KNOCKOUT!", kx + 40, ky - 300, 120, top=g.WHITE, bottom=rgb("#FFE07A"),
                outline=rgb("#1A0636"), ow=18, extrude=12, rotate=-8)

    headline(cv, "8-PLAYER RACE", 640, 200, top=g.WHITE, bottom=rgb("#7FEFFF"))
    # (no corner lockup: these sit on the game page next to the title)
    g.sparkles(cv, [(1830, 580, 50), (650, 880, 30)], glow_col=rgb("#9BE8FF"))
    return cv


def skins():
    rng = np.random.default_rng(44)
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, rgb("#B04DFF"), rgb("#140628"), center=(C, 1050), radius=S * 0.8,
                 rays=(24, rgb("#FFD1F0"), 0.08), vignette=0.35)
    bokeh(cv, rng, 45, [rgb("#FFD1F0"), rgb("#FFE07A"), rgb("#9BE8FF")])

    # fan of skins on pedestals of light
    lineup = [
        (rgb("#FF0033"), rgb("#FF7A00"), 0.35, False, rgb("#FF2D55")),   # Chaos Core (Mythic)
        (rgb("#3A1C71"), rgb("#D76D77"), 0.20, False, rgb("#B04DFF")),   # Galaxy (Epic)
        (rgb("#FFC83D"), None, 0.0, True, rgb("#FFC83D")),               # Golden Ace (Legendary)
        (rgb("#7A00FF"), rgb("#00E5FF"), 0.35, False, rgb("#B04DFF")),   # Plasma
        (rgb("#FFFFFF"), rgb("#FFD000"), 0.40, False, rgb("#FFC83D")),   # Supernova
        (rgb("#00FFC6"), rgb("#7A5CFF"), 0.30, False, rgb("#3D8BFF")),   # Aurora
        (rgb("#E0115F"), None, 0.05, False, rgb("#3D8BFF")),             # Ruby
    ]
    xs = np.linspace(230, S - 230, len(lineup))
    for k, (x, (c1, c2, em, metal, glow_c)) in enumerate(zip(xs, lineup)):
        mid = (len(lineup) - 1) / 2
        dist = abs(k - mid)
        r = 165 - dist * 18
        y = 1150 + dist * 30
        cv.add(glow_c, g.m_blur(g.m_ellipse(x, y + r + 40, r * 1.1, r * 0.28), 30), 0.7)
        ball(cv, x, y, r, c1, c2, emissive=em, metal=metal, glow_col=glow_c, rim=(1.0, 0.9, 0.7))

    headline(cv, "56+ BALL SKINS", 640, 200)
    g.draw_ribbon(cv, C, 1520, 1300, 116, "TRAILS  ·  KNOCKOUT FX  ·  ARROWS  ·  AURAS", rgb("#7A2BFF"),
                  arc_r=6000, text_size=52)
    # (no corner lockup: these sit on the game page next to the title)
    g.sparkles(cv, [(1830, 600, 52), (C, 880, 34), (480, 860, 30)], glow_col=rgb("#FFD1F0"))
    return cv


def daily():
    rng = np.random.default_rng(55)
    warm, pink = rgb("#FFB547"), rgb("#FF5E7E")
    cv = g.Canvas(color=g.NAVY)
    bc = (C, 1120)
    g.background(cv, rgb("#FF7A59"), rgb("#1E0830"), center=bc, radius=S * 0.8, vignette=0.4)
    cv.add_arr(rgb("#FFD36B"), g.rays_alpha(bc[0], bc[1], 18, rot=0.1, width=0.22, r1=S) * 0.3)
    bokeh(cv, rng, 35, [rgb("#FFE7A3"), rgb("#FF8BA0")])
    hz = g.m_ellipse(C, 2150, S * 1.1, 760)
    cv.over(g.vgrad(rgb("#4A1452"), rgb("#14051F"), 1390, 1700), hz)
    cv.add(warm, g.m_blur(g.m_sub(hz, g.m_shift(hz, 0, 14)), 30), 1.0)

    g.glow(cv, g.m_circle(*bc, 300), 140, warm, 0.8)
    g.draw_golf_ball(cv, bc, 260, warm, base_color2=pink, emissive=0.45, rim_color=(1.0, 0.9, 0.55),
                     outline_color=rgb("#4A1030"), dimples=80)
    g.coin_pile(cv, 430, 1450, 520, 230, 16, rng)
    g.coin_pile(cv, S - 430, 1450, 520, 230, 16, rng)

    headline(cv, "DAILY REWARDS", 620, 200)
    g.draw_ribbon(cv, C, 1520, 1050, 116, "DAY 14: EXCLUSIVE ETERNAL DAWN", rgb("#E2365B"), arc_r=5200, text_size=56)
    # (no corner lockup: these sit on the game page next to the title)
    g.sparkles(cv, [(1820, 640, 54), (C + 330, 900, 40), (C - 360, 960, 34)], glow_col=rgb("#FFD36B"))
    return cv


THUMBS = {"hero": hero, "ranked": ranked, "race": race, "skins": skins, "daily": daily}


def main(argv):
    os.makedirs(OUT, exist_ok=True)
    names = [a for a in argv if a in THUMBS] or list(THUMBS)
    for name in names:
        img = THUMBS[name]().to_image().crop((0, TOP, S, BOTTOM)).resize((1920, 1080), Image.LANCZOS)
        path = os.path.join(OUT, f"{name}.png")
        img.convert("RGB").save(path, optimize=True)
        print(path)


if __name__ == "__main__":
    main(sys.argv[1:])
