"""Finish 3D renders into thumbnails: bloom, grade, vignette, sharpen, then chunky game titles.

Usage: python3 overlay.py [--previews] [game[:scene] ...]   (default: every render that exists)
In:  marketing/<game>/renders/<scene>.png      Out: marketing/<game>/thumbnails_3d/<scene>.png
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
MARKETING = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(MARKETING, "..", "chaos-golf", "tools"))
import gen_icons as g  # noqa: E402

g.FONT_FILES["blackitalic"] = ["InterDisplay-BlackItalic.otf", "Inter-BlackItalic.otf"]
rgb = g.rgb
S = g.S
TOP, BOTTOM = 448, 1600           # 16:9 band of the square working canvas
W, H = S, BOTTOM - TOP

# Title styles per game: (fill top, fill bottom, outline, glow)
STYLE = {
    "golf": (rgb("#FFF36B"), rgb("#FF8A00"), rgb("#1A0636"), rgb("#FFB000")),
    "golf2": (g.WHITE, rgb("#7FEFFF"), rgb("#1A0636"), rgb("#00C8F0")),
    "brainrot": (rgb("#FFF36B"), rgb("#FF4A1C"), rgb("#1A0410"), rgb("#FF4A1C")),
    "brainrot2": (g.WHITE, rgb("#FFC83D"), rgb("#1A0410"), rgb("#FFC83D")),
    "merge": (rgb("#FFF5FB"), rgb("#FF4FA3"), rgb("#2A0838"), rgb("#FF4FA3")),
    "merge2": (rgb("#FFF8D6"), rgb("#FFC83D"), rgb("#2A0838"), rgb("#FFC83D")),
    "cyber": (rgb("#E9FFFF"), rgb("#00D4FF"), rgb("#07021A"), rgb("#00E5FF")),
    "cyber2": (rgb("#FFE9FB"), rgb("#FF2BD6"), rgb("#07021A"), rgb("#FF2BD6")),
}

# (game, scene): list of title lines (text, style, size, y in band px, x in band px or None=centre), band
TITLES = {
    ("golf", "hero"): [("ULTIMATE", "golf", 150, 150, None), ("GOLF", "golf2", 230, 330, None)],
    ("golf", "ranked"): [("RANKED 1V1", "golf", 190, 190, None), ("VS", "golf2", 170, 700, None)],
    ("golf", "race"): [("8-PLAYER RACE", "golf2", 185, 185, None)],
    ("golf", "skins"): [("56+ BALL SKINS", "golf", 185, 190, None)],
    ("golf", "daily"): [("DAILY REWARDS", "golf", 185, 175, None)],
    ("brainrot", "hero"): [("BRAINROT", "brainrot", 170, 160, 700), ("HEIST", "brainrot2", 240, 360, 700)],
    ("brainrot", "mutations"): [("RARE MUTATIONS", "brainrot2", 180, 180, None)],
    ("brainrot", "night"): [("NIGHT LUCK", "brainrot2", 200, 190, 820)],
    ("merge", "hero"): [("MERGE A EGG", "merge", 210, 960, None)],
    ("merge", "steal"): [("STEAL EGGS", "merge2", 210, 190, None)],
    ("merge", "speed"): [("TRAIN YOUR SPEED", "merge2", 175, 175, None)],
    ("merge", "tiers"): [("MERGE TO EVOLVE", "merge", 180, 170, None)],
    ("cyber", "hero"): [("CYBER", "cyber", 190, 175, None), ("SWARM", "cyber2", 230, 380, None)],
    ("cyber", "breach"): [("BREAK THE DEFENSE", "cyber", 160, 170, None)],
    ("cyber", "army"): [("UNLEASH THE SWARM", "cyber2", 160, 170, None)],
}


def post(img):
    """Bloom + filmic-ish grade + vignette + sharpen on the raw render (float 0..1)."""
    a = np.asarray(img.convert("RGB"), np.float32) / 255.0
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    bright = a * np.clip((lum - 0.62) / 0.38, 0, 1)[..., None]
    bloom = np.zeros_like(a)
    for sigma, w in ((6, 0.45), (22, 0.35), (64, 0.3)):
        bloom += w * np.stack([ndimage.gaussian_filter(bright[..., c], sigma) for c in range(3)], -1)
    a = a + bloom * 0.55
    a = 1 - np.exp(-a * 1.35)                       # soft shoulder so bloom never clips harshly
    a = a / (1 - math.exp(-1.35))
    grey = (a @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
    a = grey + (a - grey) * 1.12                    # +12% saturation
    a = 0.5 + (a - 0.5) * 1.06                      # touch of contrast
    h, w = a.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.hypot((xs - w / 2) / (w / 2), (ys - h / 2) / (h / 2)) / math.sqrt(2)
    a *= (1 - 0.32 * r ** 2.4)[..., None]
    out = Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
    return out.filter(ImageFilter.UnsharpMask(radius=1.6, percent=55, threshold=2))


def legibility(cv, y, height, col, op):
    """Soft darkening behind a title so it reads on any background."""
    m = g.new_mask()
    arr = np.zeros((S, S), np.float32)
    ys = np.arange(S, dtype=np.float32)
    prof = np.clip(1 - np.abs(ys - y) / height, 0, 1) ** 1.6
    arr[:] = prof[:, None]
    m = Image.fromarray((arr * 255).astype(np.uint8), "L")
    cv.over(col, m, op)


def title(cv, text, style, size, y, x):
    top, bottom, outline, glow = STYLE[style]
    cx = S / 2 if x is None else x * S / 1920
    cy = TOP + y * H / 1080
    size = size * S / 1920
    core = g.m_text(text, cx, cy, size, 0, "blackitalic", 0.0)
    g.glow(cv, core, size * 0.35, glow, 0.55)
    g.draw_text(cv, text, cx, cy, size, top=top, bottom=bottom, outline=outline, ow=size * 0.13,
                rotate=2, extrude=size * 0.1, shadow=(0, int(size * 0.14), int(size * 0.18), 0.6),
                kind="blackitalic")


def finish(game, scene, src_dir="renders", out_dir="thumbnails_3d"):
    src = os.path.join(MARKETING, game, src_dir, f"{scene}.png")
    if not os.path.exists(src):
        return None
    img = post(Image.open(src)).resize((W, H), Image.LANCZOS)
    cv = g.Canvas(color=g.NAVY)
    cv.paste_image(img, 0, TOP)
    lines = TITLES.get((game, scene), [])
    if lines:
        ys = [ln[3] for ln in lines]
        mid = TOP + (min(ys) + max(ys)) / 2 * H / 1080
        span = (max(ys) - min(ys)) * H / 1080 / 2 + 260
        legibility(cv, mid, span, rgb("#05030F"), 0.38)
    for text, style, size, y, x in lines:
        title(cv, text, style, size, y, x)
    out_dir = os.path.join(MARKETING, game, out_dir)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{scene}.png")
    cv.to_image().crop((0, TOP, S, BOTTOM)).resize((1920, 1080), Image.LANCZOS).convert("RGB").save(out, optimize=True)
    return out


def main(args):
    src_dir, out_dir = "renders", "thumbnails_3d"
    if args[:1] == ["--previews"]:                 # quick look-dev on the low-res previews
        args, src_dir, out_dir = args[1:], "previews", "previews_titled"
    targets = []
    for a in args or [f"{gm}:{sc}" for gm, sc in TITLES]:
        gm, _, sc = a.partition(":")
        targets += [(gm, sc)] if sc else [k for k in TITLES if k[0] == gm]
    for gm, sc in targets:
        out = finish(gm, sc, src_dir, out_dir)
        print(out or f"skip {gm}:{sc} (no render yet)")


if __name__ == "__main__":
    main(sys.argv[1:])
