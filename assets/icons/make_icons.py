# Draws the developer product icons (512x512) in the game's style:
# bright rounded tile, glossy cartoon object, chunky outlined title.
import math, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
OUT = sys.argv[1]
FONT = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
INK = (25, 20, 30)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def tile(top, bottom):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(grad)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S) + (255,))
    # sun-burst rays
    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    cx, cy = S / 2, S * 0.44
    for k in range(16):
        a0 = k * math.pi / 8
        a1 = a0 + math.pi / 16
        rd.polygon([(cx, cy), (cx + math.cos(a0) * 900, cy + math.sin(a0) * 900), (cx + math.cos(a1) * 900, cy + math.sin(a1) * 900)], fill=(255, 255, 255, 38))
    grad = Image.alpha_composite(grad, rays)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - 330, cy - 330, cx + 330, cy + 330], fill=(255, 255, 255, 70))
    grad = Image.alpha_composite(grad, glow.filter(ImageFilter.GaussianBlur(70)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([20, 20, S - 20, S - 20], radius=170, fill=255)
    img.paste(grad, (0, 0), mask)
    border = ImageDraw.Draw(img)
    border.rounded_rectangle([20, 20, S - 20, S - 20], radius=170, outline=INK + (255,), width=26)
    border.rounded_rectangle([46, 46, S - 46, S - 46], radius=146, outline=(255, 255, 255, 90), width=10)
    return img

def title(img, text, color):
    d = ImageDraw.Draw(img)
    size = 150
    while True:
        f = ImageFont.truetype(FONT, size)
        w = d.textlength(text, font=f)
        if w < S - 150 or size < 60:
            break
        size -= 6
    x = (S - w) / 2
    y = S - 250
    d.text((x + 8, y + 12), text, font=f, fill=(0, 0, 0, 120), stroke_width=22, stroke_fill=(0, 0, 0, 120))
    d.text((x, y), text, font=f, fill=color, stroke_width=22, stroke_fill=INK)

def shadow(img, box):
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse(box, fill=(0, 0, 0, 110))
    return Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(18)))

def shine(d, box, alpha=110):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=(255, 255, 255, alpha))
    d._image.alpha_composite(layer.filter(ImageFilter.GaussianBlur(6)))

def outlined_ellipse(d, box, fill, w=22):
    d.ellipse(box, fill=fill, outline=INK, width=w)

def save(img, name):
    img.resize((512, 512), Image.LANCZOS).save(f"{OUT}/{name}.png")

def dollar(d, cx, cy, size, color):
    f = ImageFont.truetype(FONT, size)
    d.text((cx, cy), "$", font=f, fill=color, anchor="mm", stroke_width=max(8, size // 18), stroke_fill=INK)

# Cash Bag --------------------------------------------------------------
img = tile((120, 235, 120), (25, 140, 60))
img = shadow(img, [250, 640, 774, 740])
d = ImageDraw.Draw(img)
outlined_ellipse(d, [230, 260, 794, 720], (95, 190, 85))
d.polygon([(400, 300), (624, 300), (700, 160), (324, 160)], fill=(95, 190, 85), outline=INK)
d.line([(400, 300), (324, 160), (700, 160), (624, 300)], fill=INK, width=22, joint="curve")
d.rounded_rectangle([370, 270, 654, 330], radius=30, fill=(255, 205, 60), outline=INK, width=20)
shine(d, [300, 340, 420, 470], 90)
dollar(d, 512, 500, 300, (255, 220, 70))
for (x, y, r) in [(170, 610, 60), (850, 590, 52), (820, 700, 44)]:
    outlined_ellipse(d, [x - r, y - r * 0.55, x + r, y + r * 0.55], (255, 205, 60), 14)
title(img, "CASH BAG", (255, 255, 255))
save(img, "cash_bag")

# Cash Vault ------------------------------------------------------------
img = tile((110, 190, 255), (30, 70, 170))
img = shadow(img, [210, 640, 814, 750])
d = ImageDraw.Draw(img)
d.rounded_rectangle([200, 150, 824, 700], radius=70, fill=(150, 160, 185), outline=INK, width=24)
d.rounded_rectangle([240, 190, 784, 660], radius=50, fill=(120, 130, 155))
outlined_ellipse(d, [292, 205, 732, 645], (205, 210, 225))
outlined_ellipse(d, [362, 275, 662, 575], (255, 200, 60), 18)
cx, cy = 512, 425
for k in range(6):
    a = k * math.pi / 3
    d.line([(cx, cy), (cx + math.cos(a) * 150, cy + math.sin(a) * 150)], fill=INK, width=34)
    d.line([(cx, cy), (cx + math.cos(a) * 140, cy + math.sin(a) * 140)], fill=(255, 225, 110), width=18)
outlined_ellipse(d, [cx - 50, cy - 50, cx + 50, cy + 50], (255, 225, 110), 16)
for y in (260, 590):
    d.rounded_rectangle([772, y - 40, 820, y + 40], radius=12, fill=(90, 95, 110), outline=INK, width=14)
shine(d, [320, 230, 430, 300], 80)
# cash spilling out
for (x, y, ang) in [(250, 690, -12), (390, 720, 8), (650, 715, -6), (790, 690, 14)]:
    note = Image.new("RGBA", (220, 110), (0, 0, 0, 0))
    nd = ImageDraw.Draw(note)
    nd.rounded_rectangle([6, 6, 214, 104], radius=14, fill=(110, 205, 95), outline=INK, width=12)
    nd.ellipse([80, 25, 140, 85], outline=(40, 120, 50), width=8)
    note = note.rotate(ang, expand=True, resample=Image.BICUBIC)
    img.alpha_composite(note, (x - note.width // 2, y - note.height // 2))
title(img, "CASH VAULT", (255, 225, 90))
save(img, "cash_vault")

# Server Luck -----------------------------------------------------------
img = tile((150, 255, 170), (20, 150, 110))
img = shadow(img, [300, 650, 724, 740])
d = ImageDraw.Draw(img)
cx, cy = 512, 390
leaf = (70, 200, 80)
leaf_light = (150, 240, 140)
# Stem behind the leaves
d.line([(cx, cy + 40), (cx + 60, cy + 280)], fill=INK, width=48)
d.line([(cx, cy + 40), (cx + 60, cy + 280)], fill=(50, 160, 60), width=26)
# Four heart-shaped leaves, each its own outlined shape with a vein
def heart(a, r, color, grow):
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    tip = (cx + ux * 18, cy + uy * 18)
    pts = []
    for side in (-1, 1):
        bx = cx + ux * 150 + px * side * 62
        by = cy + uy * 150 + py * side * 62
        d.ellipse([bx - r - grow, by - r - grow, bx + r + grow, by + r + grow], fill=color)
        pts.append((bx + px * side * (r + grow) - ux * 20, by + py * side * (r + grow) - uy * 20))
    g = grow * 1.6
    d.polygon([(tip[0] - ux * g, tip[1] - uy * g), pts[0], pts[1]], fill=color)
for k in range(4):
    heart(k * math.pi / 2 + math.pi / 4, 78, INK, 20)
for k in range(4):
    a = k * math.pi / 2 + math.pi / 4
    heart(a, 78, leaf, 0)
    ux, uy = math.cos(a), math.sin(a)
    d.line([(cx + ux * 30, cy + uy * 30), (cx + ux * 175, cy + uy * 175)], fill=(40, 140, 55), width=12)
    px, py = -uy, ux
    hx = cx + ux * 165 - px * 70
    hy = cy + uy * 165 - py * 70
    d.ellipse([hx - 26, hy - 18, hx + 26, hy + 18], fill=leaf_light)
outlined_ellipse(d, [cx - 40, cy - 40, cx + 40, cy + 40], (255, 215, 70), 14)
def star(cx, cy, r, color):
    pts = []
    for k in range(10):
        rr = r if k % 2 == 0 else r * 0.45
        a = -math.pi / 2 + k * math.pi / 5
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color, outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=12, joint="curve")
star(190, 220, 70, (255, 230, 90))
star(830, 260, 56, (255, 255, 255))
star(800, 560, 44, (255, 230, 90))
f = ImageFont.truetype(FONT, 120)
d.text((215, 600), "x2", font=f, fill=(255, 230, 90), anchor="mm", stroke_width=16, stroke_fill=INK)
title(img, "SERVER LUCK", (255, 255, 255))
save(img, "server_luck")

print("done")
