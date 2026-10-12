"""Corny Games studio logo (high-res, transparent) - an upgraded take on the flat logo.

Run: python3 studio-loading-screen/gen_logo.py  ->  studio-loading-screen/corny_games_logo.png (+ _preview.png)
"""
import math
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SS = 4                      # supersampling
W, H = 1024, 1024           # final size
CW, CH = W * SS, H * SS
FONT_DIR = "/usr/share/fonts/opentype/inter"


def font(name, px):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), int(px * SS))


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def vgrad(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, np.float32)[None, None, :]
    b = np.array(bottom, np.float32)[None, None, :]
    arr = a + (b - a) * t
    arr = np.repeat(arr, w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def fill(mask, paint):
    """Paint (an RGBA image the size of the canvas) clipped to mask (L)."""
    out = paint.copy()
    out.putalpha(ImageChops.multiply(paint.getchannel("A"), mask))
    return out


def bezier(p0, p1, p2, p3, n=40):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0]
        y = u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]
        pts.append((x * SS, y * SS))
    return pts


def mask_poly(pts):
    m = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def mask_rrect(x0, y0, x1, y1, r):
    m = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(m).rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=r * SS, fill=255)
    return m


def blur(m, r):
    return m.filter(ImageFilter.GaussianBlur(r * SS))


def solid(color):
    return Image.new("RGBA", (CW, CH), color)


def text_mask(txt, f, cx, cy, tracking=0.0):
    m = Image.new("L", (CW, CH), 0)
    d = ImageDraw.Draw(m)
    widths = [d.textlength(ch, font=f) for ch in txt]
    total = sum(widths) + tracking * SS * (len(txt) - 1)
    x = cx * SS - total / 2
    asc, desc = f.getmetrics()
    y = cy * SS - (asc + desc) / 2
    for ch, w in zip(txt, widths):
        d.text((x, y), ch, font=f, fill=255)
        x += w + tracking * SS
    return m, total / SS


def main():
    img = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))

    cx = W / 2
    cob = (cx - 112, 110, cx + 112, 640)          # x0, y0, x1, y1
    cob_r = 112

    # Halo behind the cob
    halo = blur(mask_rrect(cob[0] - 40, cob[1] - 20, cob[2] + 40, cob[3] - 40, 160), 60)
    img.alpha_composite(fill(halo, solid(hexc("#FFC83D", 120))))

    # Cob body: warm vertical gradient + rim shading
    body = mask_rrect(*cob, cob_r)
    img.alpha_composite(fill(body, vgrad((CW, CH), hexc("#FFE27A"), hexc("#F2A900"))))

    # Kernels: 5 columns, staggered rows, each a glossy rounded square
    cols, rows = 5, 10
    kw = (cob[2] - cob[0] - 36) / cols
    kh = (cob[3] - cob[1] - 40) / rows
    kernels = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    for r in range(rows):
        for c in range(cols):
            x0 = cob[0] + 18 + c * kw + (kw * 0.5 if r % 2 else 0) - kw * 0.25
            y0 = cob[1] + 20 + r * kh
            if x0 < cob[0] + 6 or x0 + kw > cob[2] - 6:
                continue
            k = mask_rrect(x0 + 4, y0 + 4, x0 + kw - 4, y0 + kh - 4, 12)
            k = ImageChops.multiply(k, body)
            shade = vgrad((CW, CH), hexc("#FFF1A8"), hexc("#F5B400"))
            kernels.alpha_composite(fill(k, shade))
            # kernel highlight (top-left gloss)
            hl = ImageChops.multiply(blur(mask_rrect(x0 + 10, y0 + 9, x0 + kw * 0.55, y0 + kh * 0.38, 8), 2), body)
            kernels.alpha_composite(fill(hl, solid(hexc("#FFFFFF", 150))))
            # contact shadow under each kernel
            sh = ImageChops.subtract(mask_rrect(x0 + 4, y0 + 8, x0 + kw - 4, y0 + kh, 12), k)
            sh = ImageChops.multiply(blur(sh, 2), body)
            kernels.alpha_composite(fill(sh, solid(hexc("#B87400", 140))))
    img.alpha_composite(kernels)

    # Cylindrical shading: darker edges, bright specular stripe on the left
    xs = np.linspace(0, 1, CW)[None, :]
    edge = np.clip((np.abs((xs * W - cx) / ((cob[2] - cob[0]) / 2))) ** 3, 0, 1)
    edge_img = Image.fromarray((np.repeat(edge, CH, 0) * 150).astype(np.uint8), "L")
    img.alpha_composite(fill(ImageChops.multiply(edge_img, body), solid(hexc("#7A3E00"))))
    spec = blur(mask_rrect(cob[0] + 26, cob[1] + 70, cob[0] + 40, cob[3] - 200, 7), 5)
    img.alpha_composite(fill(ImageChops.multiply(spec, body), solid(hexc("#FFFFFF", 90))))

    # Leaves (left and right), wrapping the base of the cob
    def leaf(side):
        # A cupped husk leaf on one side of the cob: wide at the base, tip curling outward.
        s = side
        base = (cx - s * 40, 772)
        tip = (cx + s * 150, 400)
        outer = bezier(base, (cx + s * 250, 740), (cx + s * 230, 520), tip)
        inner = bezier(tip, (cx + s * 70, 520), (cx + s * 20, 640), (cx - s * 70, 700))
        return outer + inner

    for s in (-1, 1):
        pts = leaf(s)
        m = mask_poly(pts)
        # shadow cast onto the cob
        img.alpha_composite(fill(blur(m, 14), solid(hexc("#000000", 110))))
        top, bottom = (hexc("#72E883"), hexc("#1B7A3E")) if s == 1 else (hexc("#55D068"), hexc("#156A34"))
        img.alpha_composite(fill(m, vgrad((CW, CH), top, bottom)))
        # midrib highlight
        rib = Image.new("L", (CW, CH), 0)
        rib_pts = bezier((cx + s * 10, 745), (cx + s * 150, 690), (cx + s * 170, 540), (cx + s * 145, 420))
        ImageDraw.Draw(rib).line(rib_pts, fill=255, width=int(7 * SS), joint="curve")
        img.alpha_composite(fill(ImageChops.multiply(blur(rib, 1.5), m), solid(hexc("#C9FFB5", 150))))
        # rim light on the outer edge
        rim = ImageChops.subtract(m, ImageChops.offset(m, int(-s * 6 * SS), int(6 * SS)))
        img.alpha_composite(fill(blur(rim, 1), solid(hexc("#D8FFD0", 120))))

    # Wordmark
    f_big = font("Inter-Black.otf", 150)
    f_small = font("Inter-Bold.otf", 44)
    corny, _ = text_mask("CORNY", f_big, cx, 840, tracking=4)
    img.alpha_composite(fill(blur(ImageChops.offset(corny, 0, int(10 * SS)), 6), solid(hexc("#000000", 150))))
    img.alpha_composite(fill(corny, vgrad((CW, CH), hexc("#FFFFFF"), hexc("#DCE3F0"))))
    gloss = ImageChops.multiply(corny, mask_rrect(0, 760, W, 838, 0))
    img.alpha_composite(fill(gloss, solid(hexc("#FFFFFF", 60))))

    games, gw = text_mask("GAMES", f_small, cx, 945, tracking=14)
    gold = vgrad((CW, CH), hexc("#FFE07A"), hexc("#FF9F1C"))
    img.alpha_composite(fill(blur(ImageChops.offset(games, 0, int(4 * SS)), 3), solid(hexc("#000000", 120))))
    img.alpha_composite(fill(games, gold))
    for side in (-1, 1):
        x_in = cx + side * (gw / 2 + 26)
        x_out = cx + side * (gw / 2 + 170)
        line = Image.new("L", (CW, CH), 0)
        n = 60
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            a = int(255 * (1 - t0) ** 1.4)
            xa = x_in + (x_out - x_in) * t0
            xb = x_in + (x_out - x_in) * t1
            ImageDraw.Draw(line).rectangle([min(xa, xb) * SS, (945 - 3) * SS, max(xa, xb) * SS, (945 + 3) * SS], fill=a)
        img.alpha_composite(fill(line, gold))

    out = img.resize((W, H), Image.LANCZOS)
    out.save(os.path.join(HERE, "corny_games_logo.png"), optimize=True)
    preview = Image.new("RGBA", (W, H), hexc("#0A0C12"))
    preview.alpha_composite(out)
    preview.convert("RGB").save(os.path.join(HERE, "corny_games_logo_preview.png"), optimize=True)
    print("ok")


if __name__ == "__main__":
    main()
