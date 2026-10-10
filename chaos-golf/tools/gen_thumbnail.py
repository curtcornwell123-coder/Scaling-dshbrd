"""Ultimate Golf - 1920x1080 experience thumbnail, in the same style as the icons.

Run: python3 tools/gen_thumbnail.py  ->  assets/icons/thumbnail_1920x1080.png
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_icons as g  # noqa: E402
from PIL import Image  # noqa: E402

S, C = g.S, g.C
BAND_TOP, BAND_BOTTOM = 448, 1600  # 16:9 band of the square working canvas


def thumbnail():
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, g.rgb("#8A2BE2"), g.rgb("#12062E"), center=(C, 1000), radius=S * 0.8,
                 rays=(22, g.rgb("#FF8BD1"), 0.07), vignette=0.3)
    gy = 1395
    g.draw_green(cv, C + 120, gy, 1020, 190, 130)

    # crates on the left: the four category crates' hero
    red, cyan = g.rgb("#FF2D55"), g.rgb("#00E5FF")
    g.draw_crate(cv, 330, 1235, 330, red, metal="gold", emblem=g.emblem_image("ball", red, "gold"),
                 aura=g.rgb("#FFB0C0"))
    g.draw_crate(cv, 610, 1330, 210, cyan, metal="steel", emblem=g.emblem_image("ball", cyan, "steel"))

    # cup, flag, ball and its neon bounce trail
    g.draw_cup(cv, 1640, gy + 20, 125, 40)
    g.draw_flag(cv, 1690, gy + 22, 560, g.rgb("#FFD000"), flag_w=300)
    ball = (1190, 1205)
    br = 150
    cv.over(g.SHADOW, g.m_blur(g.m_ellipse(ball[0] + 30, gy + 10, br * 0.9, br * 0.2), 20), 0.45)
    l1 = (930, gy - 10)
    paths = [g._qbez((720, 1150), (820, 1000), l1), g._qbez(l1, (1050, 1040), ball)]
    for dx, dy, col, w in ((0, 0, g.rgb("#00E5FF"), 40), (-10, 24, g.rgb("#FF00A0"), 24), (8, -20, g.rgb("#FFD000"), 16)):
        for pts in paths:
            pts2 = [(x + dx, y + dy) for x, y in pts]
            line = g.m_line(pts2, w)
            cv.add(col, g.m_blur(line, w * 1.3), 0.85)
            cv.over(g.light(col, 0.45), line)
    ring = g.m_sub(g.m_ellipse(l1[0], l1[1], 110, 30), g.m_ellipse(l1[0], l1[1], 88, 21))
    cv.add(g.rgb("#BFF3FF"), g.m_blur(ring, 6), 0.7)
    g.glow(cv, g.m_circle(*ball, br * 1.1), 70, g.rgb("#00E5FF"), 0.5)
    g.draw_golf_ball(cv, ball, br, g.rgb("#F7F9FF"), dimples=72, rim_color=(0.2, 0.95, 1.0))

    # title
    g.draw_text(cv, "ULTIMATE", C, 640, 230, top=g.rgb("#FFF36B"), bottom=g.rgb("#FF8A00"),
                outline=g.rgb("#1A0636"), ow=36, rotate=3, extrude=26)
    g.draw_text(cv, "GOLF", C, 850, 300, top=g.WHITE, bottom=g.rgb("#7FEFFF"),
                outline=g.rgb("#1A0636"), ow=44, rotate=3, extrude=32)
    g.sparkles(cv, [(1820, 620, 54), (230, 700, 44), (1480, 560, 30), (560, 980, 26)], glow_col=g.rgb("#FF8BD1"))
    return cv


def main():
    img = thumbnail().to_image().crop((0, BAND_TOP, S, BAND_BOTTOM)).resize((1920, 1080), Image.LANCZOS)
    out = os.path.join(g.OUT_DIR, "thumbnail_1920x1080.png")
    img.convert("RGB").save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    main()
