#!/usr/bin/env python3
"""Ultimate Golf - icons for the cosmetic passes (Tour, Heritage, Members Club).

Composites transparent ball renders (tools/render_balls.py --transparent) onto a club-style
badge. Content stays inside the central circle (Roblox crops pass icons to a circle).

Usage:
  tests/boot/dump_balls.sh <luau> <defs> balls.txt
  python tools/render_balls.py balls.txt --only tour_black,tour_pearl,tour_graphite,heritage_cream,heritage_forest,heritage_oxblood \
      --views three --transparent --res 900x900 --out RENDERS
  python3 tools/gen_pass_icons.py RENDERS
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icons")
S = 1024
FINAL = 512
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
FONT_SEMI = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def badge(c0, c1, ring):
    """Radial-gradient disc with a fine ring, on transparent."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    px = img.load()
    cx = cy = S / 2
    R = S * 0.48
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - cx, y - cy * 0.9) / R
            if math.hypot(x - cx, y - cy) <= R:
                t = min(1, d)
                px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3)) + (255,)
    dr = ImageDraw.Draw(img)
    dr.ellipse((cx - R + 18, cy - R + 18, cx + R - 18, cy + R - 18), outline=ring + (255,), width=6)
    return img


def ball(renders, ball_id, size):
    im = Image.open(os.path.join(renders, f"{ball_id}_three.png")).convert("RGBA")
    bbox = im.getbbox()
    im = im.crop(bbox)
    k = size / max(im.size)
    return im.resize((int(im.size[0] * k), int(im.size[1] * k)), Image.LANCZOS)


def shadow(img, xy, size, alpha=110):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dr = ImageDraw.Draw(sh)
    x, y = xy
    dr.ellipse((x - size * 0.42, y - size * 0.06, x + size * 0.42, y + size * 0.06), fill=(0, 0, 0, alpha))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14)))


def trio(renders, ids, c0, c1, ring, title, title_color):
    img = badge(c0, c1, ring)
    big, small = 470, 360
    spots = [((S * 0.3, S * 0.5), small, ids[0]), ((S * 0.7, S * 0.5), small, ids[2]), ((S * 0.5, S * 0.55), big, ids[1])]
    for (x, y), size, bid in spots:
        b = ball(renders, bid, size)
        shadow(img, (x, y + size * 0.47), size)
        img.alpha_composite(b, (int(x - b.size[0] / 2), int(y - b.size[1] / 2)))
    dr = ImageDraw.Draw(img)
    f = font(FONT, 92)
    w = dr.textlength(title, font=f)
    dr.text(((S - w) / 2, S * 0.78), title, font=f, fill=title_color + (255,))
    return img


def members():
    green, cream, red, ink = (31, 107, 78), (243, 237, 221), (200, 40, 46), (24, 27, 30)
    img = badge((22, 64, 47), (10, 30, 22), cream)
    dr = ImageDraw.Draw(img)
    # Contrail: a soft cream arc sweeping behind the crest.
    trail = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(trail)
    td.arc((S * 0.1, S * 0.25, S * 1.15, S * 1.2), 200, 300, fill=cream + (150,), width=22)
    img.alpha_composite(trail.filter(ImageFilter.GaussianBlur(3)))
    # Diamond crest with a pin flag.
    cx, cy, r = S / 2, S * 0.43, S * 0.24
    dia = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    dr.polygon(dia, fill=green + (255,), outline=cream + (255,), width=10)
    dr.rectangle((cx - 8, cy - r * 0.6, cx + 4, cy + r * 0.62), fill=cream + (255,))
    dr.polygon([(cx + 4, cy - r * 0.6), (cx + r * 0.45, cy - r * 0.45), (cx + 4, cy - r * 0.3)], fill=red + (255,))
    # Ribbon.
    rw, rh, ry = S * 0.62, S * 0.12, S * 0.66
    dr.rounded_rectangle((cx - rw / 2, ry, cx + rw / 2, ry + rh), radius=10, fill=cream + (255,), outline=ink + (255,), width=5)
    f = font(FONT, 84)
    w = dr.textlength("MEMBERS", font=f)
    dr.text((cx - w / 2, ry + rh / 2 - 50), "MEMBERS", font=f, fill=ink + (255,))
    f2 = font(FONT_SEMI, 44)
    w2 = dr.textlength("CLUB", font=f2)
    dr.text((cx - w2 / 2, S * 0.8), "CLUB", font=f2, fill=cream + (255,))
    return img


def main():
    renders = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "renders", "balls")
    os.makedirs(OUT, exist_ok=True)
    icons = {
        "pass_tour.png": trio(renders, ["tour_black", "tour_pearl", "tour_graphite"], (40, 42, 47), (12, 13, 15), (226, 185, 91), "TOUR", (236, 238, 242)),
        "pass_heritage.png": trio(renders, ["heritage_cream", "heritage_forest", "heritage_oxblood"], (28, 74, 55), (11, 32, 24), (226, 185, 91), "HERITAGE", (239, 230, 207)),
        "pass_members.png": members(),
    }
    for name, img in icons.items():
        img.resize((FINAL, FINAL), Image.LANCZOS).save(os.path.join(OUT, name))
        print("wrote", os.path.join(OUT, name))


if __name__ == "__main__":
    main()
