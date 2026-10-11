"""Corny Games community (group) icon: the studio logo on an opaque, circle-crop-safe background.

Run after gen_logo.py:  python3 gen_community_icon.py  ->  corny_games_community_icon.png (1024x1024)
"""
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
N = 1024


def main():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    d = np.sqrt((xx - N / 2) ** 2 + (yy - N * 0.42) ** 2) / (N * 0.75)
    t = np.clip(d, 0, 1)[..., None]
    inner = np.array([34, 30, 52], np.float32)
    outer = np.array([7, 8, 13], np.float32)
    bg = Image.fromarray((inner + (outer - inner) * t).astype(np.uint8), "RGB").convert("RGBA")

    # faint gold ring just inside the circle crop
    ring = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([28, 28, N - 28, N - 28], outline=(255, 196, 61, 70), width=6)
    bg.alpha_composite(ring)

    logo = Image.open(os.path.join(HERE, "corny_games_logo.png")).convert("RGBA")
    k = 0.8
    logo = logo.resize((int(N * k), int(N * k)), Image.LANCZOS)
    off = ((N - logo.width) // 2, (N - logo.height) // 2 + 6)
    bg.alpha_composite(logo, off)

    out = os.path.join(HERE, "corny_games_community_icon.png")
    bg.convert("RGB").save(out, optimize=True)
    # preview with the circle crop Roblox applies in some places
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, N, N], fill=255)
    prev = Image.new("RGB", (N, N), (240, 242, 246))
    prev.paste(bg.convert("RGB"), (0, 0), mask)
    prev.save(os.path.join(HERE, "corny_games_community_icon_circle_preview.png"), optimize=True)
    print(out)


if __name__ == "__main__":
    main()
