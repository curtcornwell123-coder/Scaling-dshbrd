"""Square 512x512 experience icon from a 3D render: post-processed crop + big stacked title.

Usage: python3 make_icon.py golf  ->  marketing/golf/icon.png
"""
import os
import sys

from PIL import Image

import overlay as ov

g, rgb, S = ov.g, ov.rgb, ov.S

ICONS = {
    # game: (render, crop centre x in the 1920x1080 render, title lines (text, style, size, y) on a 2048 canvas)
    "golf": ("hero", 1040, [("ULTIMATE", "golf", 300, 300), ("GOLF", "golf2", 470, 640)]),
}


def make(game):
    scene, cx, lines = ICONS[game]
    img = ov.post(Image.open(os.path.join(ov.MARKETING, game, "renders", f"{scene}.png")))
    x0 = max(0, min(1920 - 1080, int(cx - 540)))
    sq = img.crop((x0, 0, x0 + 1080, 1080)).resize((S, S), Image.LANCZOS)
    cv = g.Canvas(color=g.NAVY)
    cv.paste_image(sq, 0, 0)
    ov.legibility(cv, 470, 620, rgb("#05030F"), 0.45)
    for text, style, size, y in lines:
        top, bottom, outline, glow = ov.STYLE[style]
        core = g.m_text(text, S / 2, y, size, 0, "blackitalic", 0.0)
        g.glow(cv, core, size * 0.35, glow, 0.55)
        g.draw_text(cv, text, S / 2, y, size, top=top, bottom=bottom, outline=outline, ow=size * 0.13,
                    rotate=3, extrude=size * 0.1, shadow=(0, int(size * 0.14), int(size * 0.18), 0.6),
                    kind="blackitalic")
    out = os.path.join(ov.MARKETING, game, "icon.png")
    cv.to_image().resize((512, 512), Image.LANCZOS).convert("RGB").save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    for gm in sys.argv[1:] or list(ICONS):
        make(gm)
