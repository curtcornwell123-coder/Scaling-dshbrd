"""512x512 game-pass / developer-product icons for Merge A Egg and Cyber Swarm.

Run: python3 marketing/gen_pass_icons.py [name ...]  ->  marketing/<game>/passes/<name>.png
"""
import math
import os
import sys

import numpy as np

import gen_thumbs as t

g, rgb, S, C = t.g, t.rgb, t.S, t.C
HERE = os.path.dirname(os.path.abspath(__file__))
ICONS = {}
INK = rgb("#14051F")


def icon(game, name):
    def deco(fn):
        ICONS[name] = (game, fn)
        return fn
    return deco


def base(inner, outer, rays):
    cv = g.Canvas(color=g.NAVY)
    g.background(cv, inner, outer, rays=(16, rays, 0.12))
    return cv


def label(cv, text, y, size, top=g.WHITE, bottom=rgb("#FFE36B"), outline=INK, rotate=4):
    g.draw_text(cv, text, C, y, size, top=top, bottom=bottom, outline=outline, ow=size * 0.11,
                rotate=rotate, extrude=size * 0.065)


def bolt(cv, cx, cy, h, col=rgb("#FFD000")):
    w = h * 0.55
    pts = [(cx + w * 0.10, cy - h / 2), (cx - w * 0.45, cy + h * 0.06), (cx - w * 0.02, cy + h * 0.06),
           (cx - w * 0.12, cy + h / 2), (cx + w * 0.45, cy - h * 0.08), (cx + w * 0.02, cy - h * 0.08)]
    m = g.m_poly(pts, 10)
    g.glow(cv, m, h * 0.12, col, 0.6)
    g.sticker(cv, m, g.vgrad(rgb("#FFF6A8"), col, cy - h / 2, cy + h / 2), outline=INK, ow=h * 0.04,
              shadow=(0, h * 0.04, h * 0.04, 0.5), top_light=0.35)


def clover(cv, cx, cy, r, col=rgb("#2EDB6A")):
    leaves = [g.m_circle(cx + dx * r * 0.52, cy + dy * r * 0.52, r * 0.55)
              for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1))]
    stem = g.m_line([(cx, cy), (cx + r * 0.35, cy + r * 1.25)], r * 0.16)
    m = g.m_union(*leaves, stem)
    g.sticker(cv, m, g.rad(g.light(col, 0.45), g.dark(col, 0.2), (cx - r * 0.4, cy - r * 0.5), r * 1.6),
              outline=INK, ow=r * 0.08, shadow=(0, r * 0.08, r * 0.08, 0.5), top_light=0.3)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        cv.over(g.light(col, 0.6), g.m_line([(cx, cy), (cx + dx * r * 0.62, cy + dy * r * 0.62)], r * 0.05), 0.7)


def clock_badge(cv, x, y, r, text="15M"):
    g.draw_badge(cv, x, y, r, text, rgb("#3D8BFF"), text_size=r * 0.62)


def ff_arrows(cv, cx, cy, h, col):
    w = h * 0.62
    tri = lambda x0: g.m_poly([(x0, cy - h / 2), (x0 + w, cy), (x0, cy + h / 2)], 18)  # noqa: E731
    m = g.m_union(tri(cx - w * 0.95), tri(cx - w * 0.05))
    g.glow(cv, m, h * 0.12, col, 0.55)
    g.sticker(cv, m, g.vgrad(g.light(col, 0.5), col, cy - h / 2, cy + h / 2), outline=INK, ow=h * 0.04,
              shadow=(0, h * 0.04, h * 0.04, 0.5), top_light=0.35)


# Merge A Egg ------------------------------------------------------------------------------------

@icon("merge", "merge_vip")
def merge_vip():
    cv = base(rgb("#7B2CFF"), rgb("#14052E"), g.GOLD)
    g.glow(cv, g.m_circle(C, C * 1.0, S * 0.26), S * 0.10, g.GOLD, 0.45)
    t.egg(cv, C, C * 1.0, 560, 720, rgb("#FFC23D"), spots=rgb("#FF8A00"), glow_col=rgb("#FFE07A"))
    g.draw_crown(cv, C - 10, C * 0.50, 600, 380, angle=-8)
    label(cv, "VIP", S * 0.76, 400, bottom=rgb("#FFE38A"), outline=rgb("#2A0A5C"))
    t.g.sparkles(cv, [(430, 640, 64), (1630, 760, 54), (1600, 1300, 38)], glow_col=g.GOLD)
    return cv


@icon("merge", "merge_2x_speed")
def merge_2x_speed():
    cv = base(rgb("#FF7A2E"), rgb("#2A0A10"), rgb("#FFE0A0"))
    rng = np.random.default_rng(5)
    t.speed_lines(cv, 260, 760, 520, 1100, 9, rng)
    bolt(cv, C + 80, C * 0.80, 900)
    label(cv, "2X", S * 0.73, 520, outline=rgb("#3A0A00"))
    return cv


@icon("merge", "merge_2x_luck")
def merge_2x_luck():
    cv = base(rgb("#2BD46A"), rgb("#03251A"), rgb("#D7FFB0"))
    t.egg(cv, C + 300, C * 0.95, 380, 490, rgb("#E6F6FF"), spots=rgb("#7FC8FF"))
    clover(cv, C - 230, C * 0.78, 330)
    label(cv, "2X LUCK", S * 0.76, 300, outline=rgb("#06301F"))
    t.g.sparkles(cv, [(400, 420, 60), (1650, 520, 50), (1660, 1160, 36)], glow_col=rgb("#C6FF4D"))
    return cv


@icon("merge", "merge_auto_merge")
def merge_auto_merge():
    cv = base(rgb("#2F9BFF"), rgb("#061A40"), rgb("#BFE0FF"))
    t.merger(cv, C, C * 1.02, 760)
    for sx, col, spot in ((-1, rgb("#7AE582"), rgb("#2E9C55")), (1, rgb("#FF8BD1"), rgb("#C2367E"))):
        t.egg(cv, C + sx * 620, C * 0.62, 260, 330, col, spots=spot)
    label(cv, "AUTO", S * 0.80, 340, outline=rgb("#06204A"))
    return cv


@icon("merge", "merge_extra_merger")
def merge_extra_merger():
    cv = base(rgb("#22C3B5"), rgb("#04262A"), rgb("#C8FFF6"))
    t.merger(cv, C, C * 1.05, 900)
    g.draw_badge(cv, S * 0.74, S * 0.24, 200, "+1", rgb("#22D46B"))
    t.g.sparkles(cv, [(400, 460, 58), (1640, 1180, 44)], glow_col=rgb("#C8FFF6"))
    return cv


@icon("merge", "merge_server_luck")
def merge_server_luck():
    cv = base(rgb("#2BD46A"), rgb("#03251A"), rgb("#D7FFB0"))
    clover(cv, C, C * 0.78, 400)
    label(cv, "2X", S * 0.76, 430, outline=rgb("#06301F"))
    clock_badge(cv, S * 0.76, S * 0.24, 190)
    return cv


@icon("merge", "merge_speed_boost")
def merge_speed_boost():
    cv = base(rgb("#FF7A2E"), rgb("#2A0A10"), rgb("#FFE0A0"))
    bolt(cv, C, C * 0.82, 900)
    label(cv, "BOOST", S * 0.77, 330, outline=rgb("#3A0A00"))
    clock_badge(cv, S * 0.76, S * 0.24, 190)
    return cv


# Cyber Swarm ------------------------------------------------------------------------------------

CY_IN, CY_OUT = rgb("#7A1BD8"), rgb("#07021A")


@icon("cyber", "cyber_vip")
def cyber_vip():
    cv = base(CY_IN, CY_OUT, g.GOLD)
    g.glow(cv, g.m_circle(C, C * 1.05, S * 0.26), S * 0.10, rgb("#FF2BD6"), 0.4)
    t.robot(cv, C, C * 1.42, 560, rgb("#00E5FF"), "scout")
    g.draw_crown(cv, C, C * 0.40, 560, 360, angle=-6)
    label(cv, "VIP", S * 0.82, 360, bottom=rgb("#FFE38A"), outline=rgb("#2A0A5C"))
    return cv


@icon("cyber", "cyber_2x_coins")
def cyber_2x_coins():
    g.stamp_array = _bolt_stamp
    cv = base(rgb("#00B4FF"), CY_OUT, rgb("#BFF8FF"))
    g.glow(cv, g.m_circle(C, C * 0.80, S * 0.25), S * 0.10, g.GOLD, 0.5)
    g.draw_coin(cv, C + 45, C * 0.90, 380, tilt=0.60, angle=-5)
    g.draw_coin(cv, C - 35, C * 0.90 - 175, 380, tilt=0.60, angle=-11)
    label(cv, "2X", S * 0.70, 540, outline=rgb("#04122A"))
    return cv


@icon("cyber", "cyber_extra_slot")
def cyber_extra_slot():
    cv = base(rgb("#FF2BD6"), CY_OUT, rgb("#FFC8F5"))
    t.robot(cv, C - 60, C * 1.45, 640, rgb("#39FF88"), "tank")
    g.draw_badge(cv, S * 0.74, S * 0.24, 200, "+1", rgb("#22D46B"))
    return cv


@icon("cyber", "cyber_2x_speed")
def cyber_2x_speed():
    cv = base(rgb("#FF8A00"), CY_OUT, rgb("#FFE0A0"))
    ff_arrows(cv, C + 40, C * 0.78, 640, rgb("#00E5FF"))
    label(cv, "2X", S * 0.75, 500, outline=rgb("#04122A"))
    return cv


def _bolt_stamp(kind="flag", res=512, _orig=g.stamp_array):
    return _orig("bolt" if kind == "flag" else kind, res)


def coins_bg(inner):
    g.stamp_array = _bolt_stamp          # Cyber Swarm coins carry a bolt, not the golf flag
    cv = base(inner, CY_OUT, rgb("#BFF8FF"))
    g.glow(cv, g.m_circle(C, C, S * 0.25), S * 0.10, g.GOLD, 0.35)
    return cv


@icon("cyber", "cyber_coins_1")
def cyber_coins_1():
    cv = coins_bg(rgb("#00B4FF"))
    for dx, dy, a in ((-260, 160, 12), (240, 120, -14), (0, -140, -6)):
        g.draw_coin(cv, C + dx, C + dy, 330, tilt=0.55, angle=a)
    g.sparkles(cv, [(430, 520, 56), (1620, 600, 46)], glow_col=g.GOLD)
    return cv


@icon("cyber", "cyber_coins_2")
def cyber_coins_2():
    cv = coins_bg(rgb("#7A1BD8"))
    rng = np.random.default_rng(2)
    g.draw_sack(cv, C, C * 0.90, 500, rgb("#E8A85E"), emblem=True, lumpy=1.0)
    g.coin_pile(cv, C, C * 1.70, 1300, 300, 13, rng, r=160)
    g.sparkles(cv, [(420, 500, 62), (1640, 560, 52)], glow_col=g.GOLD)
    return cv


@icon("cyber", "cyber_coins_3")
def cyber_coins_3():
    cv = coins_bg(rgb("#FF2BD6"))
    rng = np.random.default_rng(3)
    g.glow(cv, g.m_ellipse(C, C * 0.82, S * 0.28, S * 0.16), S * 0.08, rgb("#FFD36B"), 0.6)
    g.draw_chest(cv, C, C * 1.08, 1180, rng)
    g.coin_pile(cv, C, C * 1.78, 1350, 200, 12, rng, r=140)
    g.sparkles(cv, [(390, 480, 72), (1660, 470, 60)], glow_col=g.GOLD)
    return cv


def main(argv):
    names = argv or list(ICONS)
    for n in names:
        game, fn = ICONS[n]
        out_dir = os.path.join(HERE, game, "passes")
        os.makedirs(out_dir, exist_ok=True)
        fn().save(os.path.join(out_dir, n + ".png"), size=512)
        print(os.path.join(game, "passes", n + ".png"))


if __name__ == "__main__":
    main(sys.argv[1:])
