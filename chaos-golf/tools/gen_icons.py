#!/usr/bin/env python3
"""Chaos Golf - icon generator (game passes, dev products, crates, game icon).

All art is procedural and original. Every icon is drawn at 2048x2048 and downsampled
to 512x512 with LANCZOS. Important content stays inside the central circle with an
8% margin (radius 0.42*S), because Roblox crops game-pass icons to a circle.

Requires: numpy, scipy, Pillow, and the Inter font family (Inter Black / Inter Display Black).
Run:      python3 tools/gen_icons.py              # all icons + contact sheet
          python3 tools/gen_icons.py pass_vip     # only the named icon(s)
"""
from __future__ import annotations

import math
import os
import sys
from functools import lru_cache

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "icons")

S = 2048                # working resolution
FINAL = 512             # output resolution
C = S / 2
SAFE_R = S * 0.42       # keep important content inside this circle

FONT_DIRS = ["/usr/share/fonts/opentype/inter", "/usr/share/fonts/truetype/inter",
             os.path.expanduser("~/.fonts"), "/usr/local/share/fonts"]
FONT_FILES = {
    "black": ["InterDisplay-Black.otf", "Inter-Black.otf", "Inter-Black.ttf"],
    "xbold": ["InterDisplay-ExtraBold.otf", "Inter-ExtraBold.otf", "Inter-ExtraBold.ttf"],
    "semibold": ["Inter-SemiBold.otf", "Inter-SemiBold.ttf"],
}

# ======================================================================================
# Colour helpers
# ======================================================================================


def rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def mix(a, b, t):
    return np.asarray(a, np.float32) * (1 - t) + np.asarray(b, np.float32) * t


def light(c, t):
    return mix(c, (1, 1, 1), t)


def dark(c, t):
    return mix(c, (0, 0, 0), t)


def ink(c, t=0.72):
    """Very dark, slightly saturated outline colour derived from c."""
    return mix(dark(c, t), (0.03, 0.02, 0.10), 0.35)


WHITE = np.array([1, 1, 1], np.float32)
BLACK = np.array([0, 0, 0], np.float32)
SHADOW = rgb("#05030f")
GOLD = rgb("#FFC83D")
GOLD_L = rgb("#FFF0B0")
GOLD_D = rgb("#D9890B")
GOLD_INK = rgb("#5A2A00")
STEEL = rgb("#C9D3E6")
STEEL_D = rgb("#6D7A96")
NAVY = rgb("#0B1030")

# ======================================================================================
# Masks (PIL "L" images, S x S)
# ======================================================================================


def new_mask(size=S):
    return Image.new("L", (size, size), 0)


def round_poly(pts, r, n=10):
    """Polygon with filleted corners (works for convex and concave corners)."""
    pts = np.asarray(pts, np.float64)
    out = []
    N = len(pts)
    for i in range(N):
        p, a, b = pts[i], pts[i - 1], pts[(i + 1) % N]
        u, v = a - p, b - p
        lu, lv = np.linalg.norm(u), np.linalg.norm(v)
        if lu < 1e-6 or lv < 1e-6:
            continue
        u, v = u / lu, v / lv
        ang = math.acos(float(np.clip(u @ v, -1, 1)))
        if r <= 0 or ang < 1e-3 or ang > math.pi - 1e-3:
            out.append(tuple(p))
            continue
        t = min(r / math.tan(ang / 2), lu * 0.5, lv * 0.5)
        rr = t * math.tan(ang / 2)
        bis = (u + v) / np.linalg.norm(u + v)
        cen = p + bis * (rr / math.sin(ang / 2))
        p1, p2 = p + u * t, p + v * t
        a1 = math.atan2(p1[1] - cen[1], p1[0] - cen[0])
        a2 = math.atan2(p2[1] - cen[1], p2[0] - cen[0])
        da = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
        for k in range(n + 1):
            ak = a1 + da * k / n
            out.append((cen[0] + rr * math.cos(ak), cen[1] + rr * math.sin(ak)))
    return out


def m_poly(pts, r=0.0, size=S):
    m = new_mask(size)
    pts = round_poly(pts, r) if r > 0 else [tuple(p) for p in pts]
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def m_ellipse(cx, cy, rx, ry, size=S):
    m = new_mask(size)
    ImageDraw.Draw(m).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    return m


def m_circle(cx, cy, r, size=S):
    return m_ellipse(cx, cy, r, r, size)


def m_rrect(x0, y0, x1, y1, r, size=S):
    m = new_mask(size)
    ImageDraw.Draw(m).rounded_rectangle((x0, y0, x1, y1), radius=r, fill=255)
    return m


def m_line(pts, width, size=S):
    m = new_mask(size)
    d = ImageDraw.Draw(m)
    d.line([tuple(p) for p in pts], fill=255, width=int(width), joint="curve")
    r = width / 2
    for p in (pts[0], pts[-1]):
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=255)
    return m


def m_union(*ms):
    out = ms[0]
    for m in ms[1:]:
        out = ImageChops.lighter(out, m)
    return out


def m_inter(a, b):
    return ImageChops.multiply(a, b)


def m_sub(a, b):
    return ImageChops.subtract(a, b)


def m_blur(m, r):
    return m.filter(ImageFilter.GaussianBlur(r)) if r > 0 else m


def m_shift(m, dx, dy):
    out = Image.new("L", m.size, 0)
    out.paste(m, (int(round(dx)), int(round(dy))))
    return out


def m_rotate(m, deg, cx=C, cy=C):
    return m.rotate(deg, resample=Image.BICUBIC, center=(cx, cy))


def m_scale(m, k):
    return m.point(lambda v: int(v * k))


def m_dilate(m, r):
    """Grow a mask by r pixels (Euclidean, rounded corners)."""
    if r <= 0:
        return m
    bb = m.getbbox()
    if not bb:
        return m
    pad = int(r) + 3
    x0, y0 = max(bb[0] - pad, 0), max(bb[1] - pad, 0)
    x1, y1 = min(bb[2] + pad, m.size[0]), min(bb[3] + pad, m.size[1])
    a = np.asarray(m.crop((x0, y0, x1, y1))) >= 128
    dist = ndimage.distance_transform_edt(~a)
    g = np.clip(r - dist + 0.5, 0, 1)
    out = new_mask(m.size[0])
    out.paste(Image.fromarray((g * 255).astype(np.uint8)), (x0, y0))
    return out


def m_erode(m, r):
    if r <= 0:
        return m
    inv = ImageChops.invert(m)
    a = np.asarray(inv) >= 128
    dist = ndimage.distance_transform_edt(~a)
    g = np.clip(dist - r + 0.5, 0, 1)
    return Image.fromarray((g * 255).astype(np.uint8))


def m_from_array(a, x0=0, y0=0, size=S):
    out = new_mask(size)
    out.paste(Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)), (int(x0), int(y0)))
    return out


# ======================================================================================
# Gradients (callables evaluated on the masked region only)
# ======================================================================================


def lin(c0, c1, p0, p1, gamma=1.0):
    c0, c1 = np.asarray(c0, np.float32), np.asarray(c1, np.float32)
    d = np.array(p1, np.float32) - np.array(p0, np.float32)
    L2 = float(d @ d) or 1.0

    def f(xs, ys):
        t = np.clip(((xs - p0[0]) * d[0] + (ys - p0[1]) * d[1]) / L2, 0, 1) ** gamma
        return c0 + (c1 - c0) * t[..., None]
    return f


def rad(c0, c1, center, r, gamma=1.0):
    c0, c1 = np.asarray(c0, np.float32), np.asarray(c1, np.float32)

    def f(xs, ys):
        t = np.clip(np.hypot(xs - center[0], ys - center[1]) / r, 0, 1) ** gamma
        return c0 + (c1 - c0) * t[..., None]
    return f


def vgrad(c0, c1, y0, y1, gamma=1.0):
    return lin(c0, c1, (0, y0), (0, y1), gamma)


# ======================================================================================
# Canvas: premultiplied float RGB + alpha
# ======================================================================================


class Canvas:
    def __init__(self, size=S, color=None):
        self.size = size
        self.rgb = np.zeros((size, size, 3), np.float32)
        self.a = np.zeros((size, size), np.float32)
        if color is not None:
            self.rgb[:] = np.asarray(color, np.float32)
            self.a[:] = 1.0

    # -- internal -------------------------------------------------------------------
    @staticmethod
    def _col(col, x0, y0, x1, y1):
        if callable(col):
            ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
            return col(xs + 0.5, ys + 0.5).astype(np.float32)
        return np.asarray(col, np.float32)[None, None, :]

    def _region(self, mask):
        bb = mask.getbbox()
        if not bb:
            return None
        x0, y0, x1, y1 = bb
        return np.asarray(mask.crop(bb), np.float32) / 255.0, x0, y0, x1, y1

    # -- painting -------------------------------------------------------------------
    def over(self, col, mask, opacity=1.0):
        r = self._region(mask)
        if r is None:
            return
        m, x0, y0, x1, y1 = r
        self.over_arr(col, m * opacity, x0, y0)

    def over_arr(self, col, a, x0=0, y0=0):
        h, w = a.shape
        c = self._col(col, x0, y0, x0 + w, y0 + h)
        reg = self.rgb[y0:y0 + h, x0:x0 + w]
        reg *= (1 - a[..., None])
        reg += c * a[..., None]
        ra = self.a[y0:y0 + h, x0:x0 + w]
        ra *= (1 - a)
        ra += a

    def add(self, col, mask, opacity=1.0):
        r = self._region(mask)
        if r is None:
            return
        m, x0, y0, x1, y1 = r
        self.add_arr(col, m * opacity, x0, y0)

    def add_arr(self, col, a, x0=0, y0=0):
        h, w = a.shape
        c = self._col(col, x0, y0, x0 + w, y0 + h)
        self.rgb[y0:y0 + h, x0:x0 + w] += c * a[..., None]
        ra = self.a[y0:y0 + h, x0:x0 + w]
        ra += a * (1 - ra)

    def paste(self, rgb_premul, alpha, x0, y0):
        """Composite a premultiplied patch (clipped to the canvas)."""
        h, w = alpha.shape
        cx0, cy0 = max(x0, 0), max(y0, 0)
        cx1, cy1 = min(x0 + w, self.size), min(y0 + h, self.size)
        if cx1 <= cx0 or cy1 <= cy0:
            return
        sl = (slice(cy0 - y0, cy1 - y0), slice(cx0 - x0, cx1 - x0))
        a = alpha[sl]
        reg = self.rgb[cy0:cy1, cx0:cx1]
        reg *= (1 - a[..., None])
        reg += rgb_premul[sl]
        ra = self.a[cy0:cy1, cx0:cx1]
        ra *= (1 - a)
        ra += a

    def paste_canvas(self, other, x0=0, y0=0):
        self.paste(other.rgb, other.a, x0, y0)

    def paste_image(self, img: Image.Image, x0=0, y0=0):
        arr = np.asarray(img.convert("RGBA"), np.float32) / 255.0
        a = arr[..., 3]
        self.paste(arr[..., :3] * a[..., None], a, x0, y0)

    def to_image(self) -> Image.Image:
        a = np.clip(self.a, 0, 1)
        col = np.where(a[..., None] > 1e-6, self.rgb / np.maximum(a[..., None], 1e-6), 0)
        col = np.clip(col, 0, 1)
        arr = np.dstack([col, a])
        return Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")

    def save(self, path, size=FINAL):
        img = self.to_image()
        if size != self.size:
            img = img.resize((size, size), Image.LANCZOS)
        if img.getextrema()[3][0] == 255:
            img = img.convert("RGB")
        img.save(path, optimize=True)
        return img


# ======================================================================================
# Generic styling helpers
# ======================================================================================


def drop_shadow(cv, mask, dx=0, dy=28, blur=26, opacity=0.55, color=SHADOW):
    cv.over(color, m_shift(m_blur(mask, blur), dx, dy), opacity)


def sticker(cv, mask, fill, outline=None, ow=0, shadow=(0, 30, 28, 0.5), top_light=0.0,
            bottom_dark=0.0, bevel=0, gloss=0.0, gloss_mask=None):
    """Bold rounded shape: soft drop shadow, thick outline, gradient fill, bevel light."""
    outer = m_dilate(mask, ow) if ow else mask
    if shadow:
        drop_shadow(cv, outer, *shadow)
    if outline is not None and ow:
        cv.over(outline, outer)
    cv.over(fill, mask)
    if bevel:
        if bottom_dark:
            band = m_blur(m_sub(mask, m_shift(mask, -bevel * 0.4, -bevel)), bevel * 0.35)
            cv.over(BLACK, m_inter(band, mask), bottom_dark)
        if top_light:
            band = m_blur(m_sub(mask, m_shift(mask, bevel * 0.3, bevel)), bevel * 0.35)
            cv.over(WHITE, m_inter(band, mask), top_light)
    if gloss and gloss_mask is not None:
        cv.over(WHITE, m_inter(gloss_mask, mask), gloss)


def rays_alpha(cx, cy, n, rot=0.0, width=0.35, r0=0.0, r1=S * 0.75, size=S):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    ang = np.arctan2(ys - cy, xs - cx) + rot
    s = np.cos(ang * n)
    edge = math.cos(math.pi * width)
    a = np.clip((s - edge) / 0.06, 0, 1)
    d = np.hypot(xs - cx, ys - cy)
    fade = np.clip((d - r0) / max(r0, 1.0) if r0 else 1.0, 0, 1) * np.clip(1 - d / r1, 0, 1) ** 1.2
    return a * fade


def background(cv, inner, outer, center=(C, C * 0.92), radius=S * 0.78, rays=None,
               vignette=0.45, gamma=1.0):
    cv.over_arr(rad(inner, outer, center, radius, gamma), np.ones((S, S), np.float32))
    if rays:
        n, col, op = rays[:3]
        rot = rays[3] if len(rays) > 3 else 0.0
        cv.add_arr(col, rays_alpha(center[0], center[1], n, rot) * op)
    if vignette:
        ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
        d = np.hypot(xs - C, ys - C) / (S * 0.72)
        cv.over_arr(SHADOW, np.clip(d - 0.55, 0, 1) ** 1.6 * vignette)


def glow(cv, mask, blur, col, opacity=1.0):
    cv.add(col, m_blur(mask, blur), opacity)


def sparkle(cv, x, y, r, col=WHITE, glow_col=None, rot=0.0, glow_op=0.7):
    """Four-point star (astroid) with a soft glow."""
    if glow_col is not None:
        glow(cv, m_circle(x, y, r * 0.55), r * 0.55, glow_col, glow_op)
    t = np.linspace(0, 2 * math.pi, 80, endpoint=False)
    px = np.sign(np.cos(t)) * np.abs(np.cos(t)) ** 3.2
    py = np.sign(np.sin(t)) * np.abs(np.sin(t)) ** 3.2
    ca, sa = math.cos(rot), math.sin(rot)
    pts = [(x + r * (a * ca - b * sa), y + r * (a * sa + b * ca)) for a, b in zip(px, py)]
    cv.over(col, m_poly(pts))
    cv.over(WHITE, m_circle(x, y, r * 0.12))


# ======================================================================================
# Fonts & text
# ======================================================================================


@lru_cache(maxsize=None)
def font_path(kind="black"):
    for d in FONT_DIRS:
        for f in FONT_FILES[kind]:
            p = os.path.join(d, f)
            if os.path.exists(p):
                return p
    raise SystemExit(f"Inter font ({kind}) not found; install fonts-inter")


@lru_cache(maxsize=None)
def get_font(size, kind="black"):
    return ImageFont.truetype(font_path(kind), int(size))


def m_text(text, cx, cy, size, stroke=0, kind="black", tracking=0.0, size_px=S):
    """Text mask centred (by ink bounds) on (cx, cy). tracking in em."""
    f = get_font(size, kind)
    m = new_mask(size_px)
    d = ImageDraw.Draw(m)
    if not tracking:
        l, t, r, b = d.textbbox((0, 0), text, font=f, anchor="ls", stroke_width=stroke)
        d.text((cx - (l + r) / 2, cy - (t + b) / 2), text, font=f, fill=255, anchor="ls",
               stroke_width=stroke, stroke_fill=255)
        return m
    adv = [f.getlength(ch) + tracking * size for ch in text]
    total = sum(adv) - tracking * size
    l, t, r, b = d.textbbox((0, 0), text, font=f, anchor="ls", stroke_width=stroke)
    x = cx - total / 2
    y = cy - (t + b) / 2
    for ch, a in zip(text, adv):
        d.text((x, y), ch, font=f, fill=255, anchor="ls", stroke_width=stroke, stroke_fill=255)
        x += a
    return m


def draw_text(cv, text, cx, cy, size, top=WHITE, bottom=None, outline=NAVY, ow=None,
              rotate=0.0, extrude=None, shadow=(0, 30, 26, 0.55), tracking=0.0, gloss=0.22,
              kind="black"):
    """Chunky game-UI title: drop shadow, extruded outline, gradient fill, top gloss."""
    ow = size * 0.11 if ow is None else ow
    bottom = top if bottom is None else bottom
    core = m_text(text, cx, cy, size, 0, kind, tracking)
    outer = m_text(text, cx, cy, size, int(ow), kind, tracking)
    if rotate:
        core, outer = m_rotate(core, rotate, cx, cy), m_rotate(outer, rotate, cx, cy)
    ext = extrude if extrude is not None else size * 0.06
    solid = outer
    if ext:
        steps = max(1, int(ext / 4))
        solid = m_union(*[m_shift(outer, 0, ext * k / steps) for k in range(steps + 1)])
    if shadow:
        drop_shadow(cv, solid, *shadow)
    cv.over(outline, solid)
    bb = core.getbbox() or (0, 0, S, S)
    cv.over(vgrad(top, bottom, bb[1], bb[3]), core)
    if gloss:
        mid = bb[1] + (bb[3] - bb[1]) * 0.46
        upper = m_poly([(0, 0), (S, 0), (S, mid - (S / 2) * math.tan(math.radians(rotate)) * 0),
                        (0, mid)])
        if rotate:
            upper = m_rotate(upper, rotate, cx, cy)
        cv.over(WHITE, m_inter(core, upper), gloss)
    return outer


def m_arc_text(text, cx, cy, radius, size, stroke=0, kind="black", tracking=0.02):
    """Text along an arc (centre of curvature (cx, cy + radius), letters upright to the arc)."""
    f = get_font(size, kind)
    out = new_mask()
    adv = [f.getlength(ch) + tracking * size for ch in text]
    total = sum(adv) - tracking * size
    ang = -total / 2 / radius
    tmp_size = int(size * 2)
    for ch, a in zip(text, adv):
        mid = ang + (a - tracking * size) / 2 / radius
        tile = Image.new("L", (tmp_size, tmp_size), 0)
        d = ImageDraw.Draw(tile)
        l, t, r, b = d.textbbox((0, 0), ch, font=f, anchor="ls", stroke_width=stroke)
        d.text((tmp_size / 2 - (l + r) / 2, tmp_size / 2 - (t + b) / 2), ch, font=f, fill=255,
               anchor="ls", stroke_width=stroke, stroke_fill=255)
        tile = tile.rotate(-math.degrees(mid), resample=Image.BICUBIC)
        px = cx + radius * math.sin(mid)
        py = cy + radius - radius * math.cos(mid)
        out.paste(tile, (int(px - tmp_size / 2), int(py - tmp_size / 2)), tile)
        ang += a / radius
    return out


# ======================================================================================
# Signature golf ball
# ======================================================================================


def _fib_sphere(n, seed_rot=(0.35, 0.8, 0.2)):
    i = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * i / n)
    th = math.pi * (1 + 5 ** 0.5) * i
    p = np.stack([np.cos(th) * np.sin(phi), np.cos(phi), np.sin(th) * np.sin(phi)], 1)
    a, b, c = seed_rot
    rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    rz = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    return (p @ (rz @ ry @ rx).T).astype(np.float32)


def draw_golf_ball(img, center, radius, base_color, *, dimples=84, outline=True, ow=None,
                   outline_color=None, shadow=True, rim_color=(0.35, 0.85, 1.0), gloss=True,
                   metal=False, tilt_deg=34.0, light_dir=(-0.5, 0.62, 0.62), spin=(0.35, 0.8, 0.2),
                   base_color2=None, emissive=0.0):
    """Shaded, dimpled golf ball onto Canvas `img`.

    Every pixel gets a sphere normal; the nearest of `dimples` evenly spread dimple
    centres bends it into a soft cup (smooth land, no crease), which gives the
    classic dark/light dimple pairs foreshortened toward the rim. Lambert + wrap,
    Blinn specular, neon fresnel rim, a stylised gloss and a sticker outline.
    base_color2 = optional bottom colour (vertical gradient); emissive = 0..1 Neon glow.
    """
    cx, cy = center
    r = float(radius)
    base = np.asarray(base_color, np.float32)
    ow = r * 0.065 if ow is None else ow
    oc = ink(base, 0.78) if outline_color is None else np.asarray(outline_color, np.float32)

    if shadow:
        drop_shadow(img, m_circle(cx, cy, r + ow), 0, r * 0.07, r * 0.09, 0.5)
    if outline and ow:
        img.over(oc, m_circle(cx, cy, r + ow))

    pad = 2
    x0, y0 = int(math.floor(cx - r - pad)), int(math.floor(cy - r - pad))
    x1, y1 = int(math.ceil(cx + r + pad)), int(math.ceil(cy + r + pad))
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    px, py = (xs + 0.5 - cx) / r, (ys + 0.5 - cy) / r
    d2 = px * px + py * py
    cover = np.clip((1 - np.sqrt(d2)) * r + 0.5, 0, 1)
    inside = d2 < 1.0
    nz = np.sqrt(np.clip(1 - d2, 0, 1))
    N = np.stack([px[inside], -py[inside], nz[inside]], 1)

    D = _fib_sphere(dimples, spin)
    D = D[D[:, 2] > -0.25]
    spacing = math.sqrt(8 * math.pi / (math.sqrt(3) * dimples))
    a_rad = spacing * 0.47
    best = np.full(len(N), -2.0, np.float32)
    idx = np.zeros(len(N), np.int64)
    for k0 in range(0, len(D), 24):
        dots = N @ D[k0:k0 + 24].T
        j = dots.argmax(1)
        v = dots[np.arange(len(N)), j]
        upd = v > best
        best[upd] = v[upd]
        idx[upd] = j[upd] + k0
    phi = np.arccos(np.clip(best, -1, 1))
    u = np.clip(phi / a_rad, 0, 1)
    cen = D[idx]
    t = cen - N * best[:, None]
    t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-6)
    prof = np.where(u < 1, 2.6 * u * (1 - u * u), 0.0)
    # fade dimples near the silhouette so the outline stays clean
    prof *= np.clip(N[:, 2] * 4.0, 0, 1)
    N2 = N + (math.tan(math.radians(tilt_deg)) * prof)[:, None] * t
    N2 /= np.linalg.norm(N2, axis=1, keepdims=True)
    ao = 1 - np.where(u < 1, 0.16 * (1 - u * u) ** 2, 0.0)
    if base_color2 is not None:
        tb = np.clip((py[inside] + 0.85) / 1.7, 0, 1)[:, None]
        base = base[None, :] * (1 - tb) + np.asarray(base_color2, np.float32)[None, :] * tb

    L = np.array(light_dir, np.float32)
    L /= np.linalg.norm(L)
    H = L + np.array([0, 0, 1], np.float32)
    H /= np.linalg.norm(H)
    ndl = N2 @ L
    wrap = np.clip(ndl * 0.62 + 0.38, 0, 1)
    hemi = 0.5 + 0.5 * N2[:, 1]
    sky = np.array([0.30, 0.33, 0.45], np.float32)
    gnd = np.array([0.16, 0.14, 0.24], np.float32)
    amb = gnd * (1 - hemi[:, None]) + sky * hemi[:, None]
    if metal:
        diff = base * (amb * 0.8 + wrap[:, None] ** 1.6 * 0.95)
        nh = np.clip(N2 @ H, 0, 1)
        spec = (nh ** 45 * 0.9 + nh ** 6 * 0.25)[:, None] * light(base, 0.55)
    else:
        diff = base * (amb * 1.1 + wrap[:, None] * 0.9)
        nh = np.clip(N2 @ H, 0, 1)
        spec = (nh ** 55 * 0.55 + nh ** 7 * 0.08)[:, None] * WHITE
    col = diff * ao[:, None] + spec
    if emissive:
        col = col * (1 - emissive * 0.45) + base * emissive * (0.75 + 0.25 * ao[:, None])
    if rim_color is not None:
        fres = (1 - N[:, 2]) ** 2.6
        side = np.clip(0.55 + 0.45 * (N[:, 0] * 0.8 - N[:, 1] * 0.6), 0, 1)
        col += (fres * side * 0.75)[:, None] * np.asarray(rim_color, np.float32)

    rgbp = np.zeros(xs.shape + (3,), np.float32)
    rgbp[inside] = col
    a = cover * inside
    img.paste(np.clip(rgbp, 0, 1.6) * a[..., None], a, x0, y0)

    if gloss:
        g = m_ellipse(cx - r * 0.34, cy - r * 0.50, r * 0.42, r * 0.22)
        g = m_rotate(g, 32, cx - r * 0.34, cy - r * 0.50)
        g = m_blur(g, r * 0.06)
        img.over(vgrad(WHITE, WHITE, 0, 1), m_inter(g, m_circle(cx, cy, r * 0.97)), 0.42 if not metal else 0.5)
        img.over(WHITE, m_blur(m_circle(cx - r * 0.45, cy - r * 0.44, r * 0.07), r * 0.02), 0.85)


# ======================================================================================
# Coins
# ======================================================================================


@lru_cache(maxsize=None)
def stamp_array(kind="flag", res=512):
    """Flat emblem art in unit-disc coordinates ([-1,1]^2 -> res x res), as float array."""
    m = Image.new("L", (res, res), 0)
    d = ImageDraw.Draw(m)
    k = res / 2.0

    def P(x, y):
        return (k + x * k, k + y * k)

    if kind == "flag":
        d.rounded_rectangle((*P(-0.24, -0.66), *P(-0.10, 0.42)), radius=int(0.06 * k), fill=255)
        flag = [P(-0.14, -0.70), P(0.56, -0.42), P(-0.14, -0.12)]
        d.polygon(round_poly(flag, 0.05 * k), fill=255)
        d.ellipse((*P(-0.62, 0.30), *P(0.46, 0.62)), fill=255)
    elif kind == "ball":
        d.ellipse((*P(-0.48, -0.48), *P(0.48, 0.48)), fill=255)
        for ang in range(0, 360, 60):
            x, y = 0.24 * math.cos(math.radians(ang)), 0.24 * math.sin(math.radians(ang))
            d.ellipse((*P(x - 0.08, y - 0.08), *P(x + 0.08, y + 0.08)), fill=90)
        d.ellipse((*P(-0.08, -0.08), *P(0.08, 0.08)), fill=90)
    return np.asarray(m, np.float32) / 255.0


def draw_coin(cv, cx, cy, r, tilt=0.5, angle=0.0, thick=None, stamp="flag", base=GOLD,
              ow=None, outline_color=GOLD_INK, shadow=True):
    """Thick gold coin seen at an angle. tilt = minor/major axis of the face ellipse."""
    t = r * 0.17 if thick is None else thick
    k = max(tilt, 0.05)
    ow = r * 0.075 if ow is None else ow
    ext = r + t + ow + 4
    x0, y0 = int(cx - ext), int(cy - ext)
    x1, y1 = int(cx + ext), int(cy + ext)
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = xs + 0.5 - cx, ys + 0.5 - cy
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    u = dx * ca + dy * sa
    v = -dx * sa + dy * ca
    base = np.asarray(base, np.float32)

    def body(rr, kk, tt):
        h = rr * kk * np.sqrt(np.clip(1 - (u / rr) ** 2, 0, 1))
        inside = (np.abs(u) <= rr) & (v >= -tt / 2 - h) & (v <= tt / 2 + h)
        return inside

    full = body(r + ow, (r * k + ow) / (r + ow), t)
    coin = body(r, k, t)
    vf = v + t / 2
    p, q = u / r, vf / (r * k)
    rho2 = p * p + q * q
    face = rho2 <= 1.0
    side = coin & ~face

    out = np.zeros(xs.shape + (3,), np.float32)
    # side band: cylindrical shading + reeding
    cyl = 0.5 + 0.5 * np.cos(np.clip(u / r, -1, 1) * math.pi * 0.5 + 0.6)
    reed = (np.sin(u / r * 34) > 0.15).astype(np.float32)
    side_col = (mix(GOLD_D, base, 0.25)[None, None, :] * (0.55 + 0.5 * cyl[..., None])
                * (1 - 0.10 * reed[..., None]))
    out[side] = side_col[side]
    # face
    rho = np.sqrt(rho2)
    shade = np.clip(0.62 - 0.35 * (p * 0.7 + q * 0.9), 0, 1)
    face_rgb = mix(GOLD_D, GOLD_L, shade[..., None] ** 1.2)
    face_rgb = mix(face_rgb, base, 0.35)
    # raised rim band
    rim = (rho > 0.78) & face
    rim_shade = np.clip(0.5 - 0.6 * (p * 0.6 + q * 0.8) / np.maximum(rho, 1e-3), 0, 1)
    rim_rgb = mix(GOLD_D, GOLD_L, rim_shade[..., None])
    face_rgb = np.where(rim[..., None], rim_rgb, face_rgb)
    groove = np.exp(-((rho - 0.78) / 0.018) ** 2)
    face_rgb = face_rgb * (1 - 0.45 * groove[..., None])
    # embossed stamp
    if stamp:
        arr = stamp_array(stamp)
        res = arr.shape[0]

        def samp(pp, qq):
            return ndimage.map_coordinates(arr, [(qq + 1) * res / 2, (pp + 1) * res / 2],
                                           order=1, mode="constant")
        fp, fq = p[face] / 0.6, q[face] / 0.6
        s0 = samp(fp, fq)
        e = 0.035
        g = samp(fp + e, fq + e) - samp(fp - e, fq - e)
        fr = face_rgb[face]
        fr = mix(fr, mix(GOLD_D, base, 0.45), 0.55 * s0[:, None])
        fr = fr + mix(GOLD_L, WHITE, 0.4) * np.clip(-g, 0, 1)[:, None] * 1.1
        fr = fr * (1 - 0.6 * np.clip(g, 0, 1)[:, None])
        face_rgb[face] = fr
    # specular streak
    streak = np.exp(-((p * 0.8 + q * 0.6 + 0.25) / 0.16) ** 2) * (rho < 0.97)
    face_rgb = face_rgb + streak[..., None] * 0.28
    out[face] = face_rgb[face]

    alpha = full.astype(np.float32)
    out[full & ~coin] = np.asarray(outline_color, np.float32)
    if shadow:
        sh = m_from_array(alpha, x0, y0)
        drop_shadow(cv, sh, 0, r * 0.08, r * 0.08, 0.45)
    cv.paste(out * alpha[..., None], alpha, x0, y0)


# ======================================================================================
# Flat emblem art (drawn on an S canvas, then warped onto a crate face)
# ======================================================================================

METALS = {
    "steel": (rgb("#F2F6FF"), rgb("#8E9BB8"), rgb("#1B2238")),
    "gold": (rgb("#FFF2B8"), rgb("#D98E0B"), rgb("#4A2200")),
    "dark": (rgb("#5A6078"), rgb("#1E2233"), rgb("#07080F")),
}


def draw_rocket(cv, cx, cy, size, angle=40.0):
    """Cartoon rocket pointing up (rotated by angle, degrees clockwise) with flame."""
    def T(x, y):
        a = math.radians(angle)
        return (cx + size * (x * math.cos(a) - y * math.sin(a)),
                cy + size * (x * math.sin(a) + y * math.cos(a)))
    body = [T(0, -1.0), T(0.22, -0.78), T(0.34, -0.42), T(0.34, 0.42), T(0.22, 0.58),
            T(-0.22, 0.58), T(-0.34, 0.42), T(-0.34, -0.42), T(-0.22, -0.78)]
    fin_l = [T(-0.30, 0.05), T(-0.66, 0.50), T(-0.62, 0.78), T(-0.26, 0.56)]
    fin_r = [T(0.30, 0.05), T(0.66, 0.50), T(0.62, 0.78), T(0.26, 0.56)]
    flame_o = [T(-0.24, 0.56), T(0.24, 0.56), T(0.16, 0.95), T(0, 1.32), T(-0.16, 0.95)]
    flame_i = [T(-0.12, 0.56), T(0.12, 0.56), T(0.07, 0.85), T(0, 1.08), T(-0.07, 0.85)]
    outline = ink(rgb("#00B4FF"), 0.8)
    ow = size * 0.07
    glow(cv, m_poly(flame_o, size * 0.1), size * 0.18, rgb("#FF8A00"), 0.9)
    for poly, fill in ((flame_o, vgrad(rgb("#FFD000"), rgb("#FF4A00"), *_ys(flame_o))),
                       (flame_i, WHITE)):
        cv.over(fill, m_poly(poly, size * 0.08))
    fins = m_union(m_poly(fin_l, size * 0.08), m_poly(fin_r, size * 0.08))
    bodym = m_poly(body, size * 0.10)
    cv.over(outline, m_dilate(m_union(fins, bodym), ow))
    cv.over(lin(rgb("#FF5A5F"), rgb("#B3122E"), T(-0.6, 0), T(0.6, 0)), fins)
    cv.over(lin(WHITE, rgb("#AFC3E0"), T(-0.4, 0), T(0.4, 0)), bodym)
    nose = m_inter(bodym, m_poly([T(-1, -1.2), T(1, -1.2), T(1, -0.62), T(-1, -0.62)]))
    cv.over(lin(rgb("#FF5A5F"), rgb("#C21B3A"), T(-0.4, 0), T(0.4, 0)), nose)
    wx, wy = T(0, -0.18)
    cv.over(outline, m_circle(wx, wy, size * 0.19))
    cv.over(rad(rgb("#9AF4FF"), rgb("#0090D0"), (wx - size * 0.05, wy - size * 0.05), size * 0.2),
            m_circle(wx, wy, size * 0.14))
    cv.over(WHITE, m_circle(wx - size * 0.05, wy - size * 0.05, size * 0.045), 0.9)


def _ys(poly):
    ys = [p[1] for p in poly]
    return min(ys), max(ys)


def draw_hazard_triangle(cv, cx, cy, size):
    pts = [(cx, cy - size), (cx + size * 1.08, cy + size * 0.78), (cx - size * 1.08, cy + size * 0.78)]
    m = m_poly(pts, size * 0.2)
    cv.over(rgb("#14110A"), m_dilate(m, size * 0.10))
    cv.over(vgrad(rgb("#FFE066"), rgb("#FFB703"), cy - size, cy + size), m)
    t = m_text("!", cx, cy + size * 0.16, size * 1.05)
    cv.over(rgb("#14110A"), t)


def emblem_image(kind, accent, metal="steel", size=S):
    """Round medallion (metal ring + art) as an RGBA image cropped to its bounds."""
    hi, lo, inkc = METALS[metal]
    accent = np.asarray(accent, np.float32)
    cv = Canvas(size)
    c, R = size / 2, size * 0.44
    cv.over(inkc, m_circle(c, c, R))
    cv.over(lin(hi, lo, (c - R, c - R), (c + R * 0.7, c + R * 0.7)), m_circle(c, c, R * 0.93))
    cv.over(lin(lo, hi, (c - R, c - R), (c + R * 0.7, c + R * 0.7)), m_circle(c, c, R * 0.80))
    inner = m_circle(c, c, R * 0.74)
    cv.over(inkc, m_circle(c, c, R * 0.765))
    cv.over(rad(light(accent, 0.15), dark(accent, 0.55), (c, c - R * 0.2), R * 0.85), inner)
    if kind in ("ball", "ball_gold"):
        glow(cv, m_circle(c, c, R * 0.5), R * 0.12, light(accent, 0.4), 0.8)
        base = GOLD if kind == "ball_gold" else rgb("#F7F9FF")
        draw_golf_ball(cv, (c, c), R * 0.60, base, dimples=64, ow=R * 0.04, shadow=False,
                       metal=(kind == "ball_gold"), rim_color=light(accent, 0.3))
    elif kind == "bullseye":
        cols = [rgb("#F8F3E6"), rgb("#E63946")]
        for k, rr in enumerate([0.74, 0.60, 0.46, 0.32, 0.18]):
            cv.over(cols[k % 2] if k else cols[1], m_circle(c, c, R * rr))
        cv.over(rgb("#F8F3E6"), m_circle(c, c, R * 0.60))
        cv.over(rgb("#E63946"), m_circle(c, c, R * 0.46))
        cv.over(rgb("#F8F3E6"), m_circle(c, c, R * 0.32))
        cv.over(rgb("#E63946"), m_circle(c, c, R * 0.18))
        cv.over(WHITE, m_inter(m_ellipse(c - R * 0.2, c - R * 0.35, R * 0.45, R * 0.22), inner), 0.22)
        draw_golf_ball(cv, (c + R * 0.05, c + R * 0.03), R * 0.15, rgb("#F7F9FF"), dimples=40,
                       ow=R * 0.03, shadow=True, rim_color=None)
    elif kind == "rocket":
        for k, (ox, oy, w) in enumerate([(-0.50, 0.30, 0.11), (-0.22, 0.56, 0.09), (-0.64, 0.00, 0.07)]):
            a = (c + R * ox, c + R * oy)
            b = (a[0] - R * 0.35, a[1] + R * 0.35)
            cv.over(rgb("#BFF3FF"), m_inter(m_line([a, b], R * w), inner), 0.85)
        draw_rocket(cv, c + R * 0.04, c - R * 0.04, R * 0.60, angle=42)
    elif kind == "hazard":
        ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
        band = ((xs + ys) / (R * 0.26)) % 2.0
        stripes = np.clip((np.abs(band - 1.0) - 0.5) * 40 + 0.5, 0, 1)
        im = np.asarray(inner, np.float32) / 255.0
        cv.over_arr(rgb("#1A1712"), stripes * im)
        cv.over_arr(rgb("#FFB703"), (1 - stripes) * im)
        cv.over(SHADOW, m_inter(m_sub(inner, m_shift(inner, 0, R * 0.08)), inner), 0.0)
        draw_hazard_triangle(cv, c, c + R * 0.02, R * 0.40)
    elif kind == "skin":
        # two-tone ball: one ball, two paint jobs split on a diagonal
        bx, by, br = c, c, R * 0.60
        glow(cv, m_circle(bx, by, br), R * 0.12, light(accent, 0.4), 0.7)
        draw_golf_ball(cv, (bx, by), br, rgb("#FF4FA3"), dimples=64, ow=R * 0.04, shadow=False,
                       rim_color=rgb("#FFD1E8"))
        other = Canvas(size)
        draw_golf_ball(other, (bx, by), br, rgb("#00E5FF"), dimples=64, ow=R * 0.04, shadow=False,
                       rim_color=rgb("#E0FBFF"))
        half = np.asarray(m_rotate(m_poly([(0, c), (size, c), (size, size), (0, size)]), 35, c, c),
                          np.float32) / 255.0
        cv.paste(other.rgb * half[..., None], other.a * half, 0, 0)
        seam_m = m_inter(m_rotate(m_rrect(0, c - R * 0.025, size, c + R * 0.025, 4), 35, c, c),
                         m_circle(bx, by, br))
        cv.over(WHITE, seam_m, 0.95)
    elif kind == "trail":
        # ball trailing a tapered multi-colour ribbon
        def bez(t):
            p0, p1, p2 = np.array([c - R * 0.70, c + R * 0.42]), np.array([c - R * 0.05, c + R * 0.62]), \
                np.array([c + R * 0.30, c - R * 0.22])
            return p0 * (1 - t) ** 2 + 2 * p1 * t * (1 - t) + p2 * t * t
        ts = np.linspace(0, 1, 60)
        cols = [rgb("#B04DFF"), rgb("#0066FF"), rgb("#00E5FF"), WHITE]
        for k, col in enumerate(cols):
            wmax = R * (0.34 - 0.075 * k)
            left, right = [], []
            for t in ts:
                pnt = bez(t)
                tan = bez(min(t + 0.01, 1)) - bez(max(t - 0.01, 0))
                nrm = np.array([-tan[1], tan[0]]) / (np.linalg.norm(tan) + 1e-9)
                w = wmax * (0.08 + 0.92 * t ** 1.3)
                left.append(tuple(pnt + nrm * w))
                right.append(tuple(pnt - nrm * w))
            rm = m_inter(m_poly(left + right[::-1]), inner)
            if k == 0:
                cv.add(col, m_blur(rm, R * 0.05), 0.6)
            cv.over(col, rm, 0.95)
        for t, rr in ((0.22, 0.035), (0.45, 0.05), (0.62, 0.03)):
            pnt = bez(t) + np.array([R * 0.06, -R * 0.20])
            sparkle(cv, pnt[0], pnt[1], R * rr * 2.2)
        draw_golf_ball(cv, (c + R * 0.30, c - R * 0.22), R * 0.34, rgb("#F7F9FF"), dimples=56,
                       ow=R * 0.035, shadow=False, rim_color=rgb("#00E5FF"))
    elif kind == "burst":
        # comic impact burst with a ball smashing into it
        rng = np.random.default_rng(5)
        def burst(rr_out, rr_in, n, jitter):
            pts = []
            for k in range(2 * n):
                a = math.pi * k / n + 0.12
                rr = (rr_out if k % 2 == 0 else rr_in) * (1 + rng.uniform(-jitter, jitter))
                pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
            return pts
        outer_b = m_poly(burst(R * 0.70, R * 0.42, 11, 0.10), R * 0.02)
        cv.over(ink(accent, 0.8), m_dilate(outer_b, R * 0.035))
        cv.over(rad(rgb("#FFE14D"), rgb("#FF7A00"), (c, c), R * 0.7), outer_b)
        inner_b = m_poly(burst(R * 0.46, R * 0.28, 9, 0.12), R * 0.02)
        cv.over(rad(WHITE, rgb("#FFF27A"), (c, c), R * 0.46), inner_b)
        for k, (oy, L) in enumerate(((-0.16, 0.30), (0.04, 0.38), (0.24, 0.26))):
            a0 = (c - R * 0.70, c + R * oy - R * 0.02)
            cv.over(WHITE, m_inter(m_line([a0, (a0[0] + R * L, a0[1])], R * 0.06), inner), 0.9)
        draw_golf_ball(cv, (c - R * 0.04, c + R * 0.02), R * 0.27, rgb("#F7F9FF"), dimples=48,
                       ow=R * 0.035, shadow=False, rim_color=rgb("#FFB36B"))
        for a, rr in ((-0.6, 0.06), (0.9, 0.05), (2.5, 0.045), (3.6, 0.05)):
            x, y = c + math.cos(a) * R * 0.58, c + math.sin(a) * R * 0.58
            cv.over(ink(accent, 0.8), m_circle(x, y, R * rr * 1.3))
            cv.over(rgb("#FFE14D"), m_circle(x, y, R * rr))
    elif kind == "arrow":
        # chunky aim arrow launching from a ball, dotted aim line behind it
        ang = -45.0

        def T(x, y):
            a = math.radians(ang)
            return (c + R * (x * math.cos(a) - y * math.sin(a)), c + R * (x * math.sin(a) + y * math.cos(a)))
        shaft = [T(-0.04, -0.12), T(0.26, -0.12), T(0.26, 0.12), T(-0.04, 0.12)]
        head = [T(0.20, -0.33), T(0.60, 0.0), T(0.20, 0.33)]
        am = m_union(m_poly(shaft, R * 0.03), m_poly(head, R * 0.05))
        cv.over(ink(accent, 0.85), m_dilate(am, R * 0.05))
        cv.over(lin(WHITE, light(accent, 0.2), T(0, -0.3), T(0, 0.3)), am)
        cv.add(light(accent, 0.3), m_blur(am, R * 0.08), 0.35)
        cv.over(WHITE, m_inter(m_sub(am, m_shift(am, R * 0.02, R * 0.05)), am), 0.6)
        for t in (-0.13, -0.23):
            x, y = T(t, 0)
            cv.over(ink(accent, 0.85), m_circle(x, y, R * 0.055))
            cv.over(WHITE, m_circle(x, y, R * 0.038))
        bx, by = T(-0.46, 0)
        draw_golf_ball(cv, (bx, by), R * 0.20, rgb("#F7F9FF"), dimples=48, ow=R * 0.035, shadow=False,
                       rim_color=light(accent, 0.3))
    # glass gloss over the whole medallion
    gl = m_inter(m_ellipse(c - R * 0.15, c - R * 0.52, R * 0.62, R * 0.30), inner)
    cv.over(WHITE, m_blur(gl, R * 0.02), 0.16)
    img = cv.to_image()
    return img.crop(img.getbbox())


def warp_onto(cv, img, P0, P1, P2):
    """Affine-map img so its corners (0,0),(w,0),(0,h) land on screen points P0,P1,P2."""
    w, h = img.size
    A = np.array([[(P1[0] - P0[0]) / w, (P2[0] - P0[0]) / h, P0[0]],
                  [(P1[1] - P0[1]) / w, (P2[1] - P0[1]) / h, P0[1]],
                  [0, 0, 1]], np.float64)
    P3 = (P1[0] + P2[0] - P0[0], P1[1] + P2[1] - P0[1])
    xs = [P0[0], P1[0], P2[0], P3[0]]
    ys = [P0[1], P1[1], P2[1], P3[1]]
    bx0, by0 = int(math.floor(min(xs))) - 2, int(math.floor(min(ys))) - 2
    bx1, by1 = int(math.ceil(max(xs))) + 2, int(math.ceil(max(ys))) + 2
    inv = np.linalg.inv(A) @ np.array([[1, 0, bx0], [0, 1, by0], [0, 0, 1]], np.float64)
    out = img.transform((bx1 - bx0, by1 - by0), Image.AFFINE, data=tuple(inv[:2].flatten()),
                        resample=Image.BICUBIC)
    cv.paste_image(out, bx0, by0)


# ======================================================================================
# Crate (3/4 view, chunky bevelled box with lid)
# ======================================================================================


class Proj:
    """Orthographic 3/4 projection: yaw about Y, then pitch down. y is up, z toward viewer."""

    def __init__(self, cx, cy, scale, yaw=-36.0, pitch=24.0):
        self.cx, self.cy, self.s = cx, cy, scale
        y, p = math.radians(yaw), math.radians(pitch)
        self.cyw, self.syw, self.cp, self.sp = math.cos(y), math.sin(y), math.cos(p), math.sin(p)

    def __call__(self, x, y, z):
        x1 = x * self.cyw + z * self.syw
        z1 = -x * self.syw + z * self.cyw
        yv = y * self.cp - z1 * self.sp
        return (self.cx + x1 * self.s, self.cy - yv * self.s)


def _hull(pts):
    pts = sorted(set((round(p[0], 3), round(p[1], 3)) for p in pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


class Box:
    def __init__(self, P, w, d, y0, y1):
        self.P, self.w, self.d, self.y0, self.y1 = P, w, d, y0, y1
        hw, hd = w / 2, d / 2
        self.faces = {
            "front": ((-hw, y1, hd), (1, 0, 0), (0, -1, 0), w, y1 - y0),
            "right": ((hw, y1, hd), (0, 0, -1), (0, -1, 0), d, y1 - y0),
            "top": ((-hw, y1, -hd), (1, 0, 0), (0, 0, 1), w, d),
        }
        corners = [(x, y, z) for x in (-hw, hw) for y in (y0, y1) for z in (-hd, hd)]
        self.hull = _hull([P(*c) for c in corners])

    def pt(self, face, u, v):
        O, U, V, _, _ = self.faces[face]
        return self.P(O[0] + u * U[0] + v * V[0], O[1] + u * U[1] + v * V[1], O[2] + u * U[2] + v * V[2])

    def quad(self, face, u0, v0, u1, v1):
        return [self.pt(face, u0, v0), self.pt(face, u1, v0), self.pt(face, u1, v1), self.pt(face, u0, v1)]

    def size(self, face):
        return self.faces[face][3], self.faces[face][4]


def draw_box(cv, box, col, *, bevel=0.045, round_px=60, face_round=40, ow=26, outline=None,
             metal="steel", caps=("front", "right", "top"), cap=0.15, cap_rows=("top", "bottom"),
             shade=1.0, shadow=True):
    col = np.asarray(col, np.float32)
    outline = ink(col, 0.8) if outline is None else outline
    hi, lo, minkc = METALS[metal]
    hull = m_poly(box.hull, round_px)
    ys = [p[1] for p in box.hull]
    ytop, ybot = min(ys), max(ys)
    if shadow:
        drop_shadow(cv, m_dilate(hull, ow), 0, 34, 30, 0.5)
    cv.over(outline, m_dilate(hull, ow))
    # bevel colour: bright on top edges, deep at the bottom
    cv.over(vgrad(light(col, 0.55), dark(col, 0.45), ytop, ybot), hull)
    fills = {
        "top": lambda q: lin(light(col, 0.30), light(col, 0.10), q[0], q[3]),
        "front": lambda q: vgrad(light(col, 0.04), dark(col, 0.16 * shade), q[0][1], q[3][1]),
        "right": lambda q: vgrad(dark(col, 0.24 * shade), dark(col, 0.40 * shade), q[0][1], q[3][1]),
    }
    face_masks = {}
    for f in ("top", "front", "right"):
        W, H = box.size(f)
        q = box.quad(f, bevel, bevel, W - bevel, H - bevel)
        fm = m_poly(q, face_round)
        face_masks[f] = fm
        cv.over(fills[f](q), fm)
    # caps on the requested face corners
    capm = new_mask()
    for f in caps:
        W, H = box.size(f)
        cw, ch = min(cap, W * 0.45), min(cap, H * 0.45)
        if f != "top" and "full" in cap_rows:
            rows = [("full", 0, H)]
        else:
            rows = [("top", 0, ch), ("bottom", H - ch, H)]
        for row, v0, v1 in rows:
            if f != "top" and row not in cap_rows:
                continue
            for u0, u1 in ((0, cw), (W - cw, W)):
                capm = m_union(capm, m_poly(box.quad(f, u0, v0, u1, v1), 18))
    capm = m_inter(capm, m_erode(hull, 2))
    if capm.getbbox():
        cv.over(minkc, m_inter(m_dilate(capm, 9), hull))
        bb = capm.getbbox()
        cv.over(lin(hi, lo, (bb[0], bb[1]), (bb[2], bb[3])), capm)
        # per-cap highlight: lighter top-left bevel
        band = m_blur(m_sub(capm, m_shift(capm, 8, 10)), 3)
        cv.over(WHITE, band, 0.55)
        # rivets
        for f in caps:
            W, H = box.size(f)
            cw, ch = min(cap, W * 0.45), min(cap, H * 0.45)
            rivet_rows = (("full", H * 0.5),) if (f != "top" and "full" in cap_rows) else \
                (("top", ch * 0.5), ("bottom", H - ch * 0.5))
            for row, vv in rivet_rows:
                if f != "top" and row not in cap_rows:
                    continue
                for uu in (cw * 0.5, W - cw * 0.5):
                    x, y = box.pt(f, uu, vv)
                    rr = box.P.s * cap * 0.13
                    cv.over(minkc, m_circle(x, y + 3, rr * 1.15), 0.7)
                    cv.over(rad(WHITE, lo, (x - rr * 0.4, y - rr * 0.4), rr * 1.3), m_circle(x, y, rr))
    return hull, face_masks


def draw_crate(cv, cx, cy, scale, col, *, metal="steel", emblem=None, seam=None,
               aura=None, panel=True):
    """Chunky stylised crate: body + overhanging lid, metal caps, glowing seam, medallion."""
    col = np.asarray(col, np.float32)
    seam = light(col, 0.6) if seam is None else np.asarray(seam, np.float32)
    W = D = 1.0
    HB, HL, O = 0.60, 0.30, 0.05
    # (cx, cy) is the visual centre of the crate
    P = Proj(cx, cy, scale)
    mx, my = P(0, (HB + HL) / 2, 0)
    P = Proj(cx, cy + (cy - my), scale)
    body = Box(P, W, D, 0.0, HB)
    lid = Box(P, W + 2 * O, D + 2 * O, HB, HB + HL)

    # ground contact shadow
    gx, gy = P(0, 0, 0)
    cv.over(SHADOW, m_blur(m_ellipse(gx, gy + scale * 0.06, scale * 0.78, scale * 0.20), scale * 0.06), 0.6)
    if aura is not None:
        glow(cv, m_union(m_poly(body.hull), m_poly(lid.hull)), scale * 0.22, aura, 0.9)

    hull_b, faces_b = draw_box(cv, body, col, metal=metal, cap_rows=("bottom",), caps=("front", "right"))
    # recessed panels on the body
    if panel:
        for f in ("front", "right"):
            Wf, Hf = body.size(f)
            q = body.quad(f, 0.17, 0.16, Wf - 0.17, Hf - 0.12)
            pm = m_poly(q, 26)
            cv.over(dark(col, 0.30), pm, 0.55)
            cv.over(BLACK, m_inter(m_blur(m_sub(pm, m_shift(pm, 0, 16)), 5), pm), 0.35)
            cv.over(WHITE, m_inter(m_blur(m_sub(pm, m_shift(pm, 0, -12)), 4), pm), 0.18)
    # neon seam right under the lid
    seam_m = m_union(m_poly(body.quad("front", 0.02, 0.0, W - 0.02, 0.085)),
                     m_poly(body.quad("right", 0.0, 0.0, D - 0.02, 0.085)))
    cv.over(seam, seam_m)
    hull_l, faces_l = draw_box(cv, lid, col, metal=metal, ow=24, cap=0.15,
                               cap_rows=("full",), caps=("front", "right", "top"), shade=0.9,
                               shadow=False)
    # lid shadow onto the seam + glow
    cv.add(seam, m_blur(seam_m, 26), 0.75)
    cv.add(seam, m_blur(m_inter(seam_m, m_sub(m_poly(body.hull), hull_l)), 6), 0.6)
    # top gloss
    tq = lid.quad("top", 0.10, 0.10, lid.size("top")[0] - 0.45, 0.42)
    cv.over(WHITE, m_blur(m_poly(tq, 30), 12), 0.18)
    # medallion lock straddling the seam on the front
    if emblem is not None:
        zf = D / 2 + O + 0.012
        mr, my_ = 0.31, HB - 0.04
        P0 = P(-mr, my_ + mr, zf)
        P1 = P(mr, my_ + mr, zf)
        P2 = P(-mr, my_ - mr, zf)
        sh = m_poly([P0, P1, (P1[0] + P2[0] - P0[0], P1[1] + P2[1] - P0[1]), P2])
        e_c = ((P1[0] + P2[0]) / 2, (P1[1] + P2[1]) / 2)
        rx = math.hypot(P1[0] - P0[0], P1[1] - P0[1]) / 2
        ry = math.hypot(P2[0] - P0[0], P2[1] - P0[1]) / 2
        cv.over(SHADOW, m_blur(m_shift(m_ellipse(e_c[0], e_c[1], rx * 0.95, ry * 0.95), 10, 26), 18), 0.55)
        cv.add(seam, m_blur(m_ellipse(e_c[0], e_c[1], rx * 1.05, ry * 1.05), 40), 0.55)
        warp_onto(cv, emblem, P0, P1, P2)
    return body, lid


# ======================================================================================
# Props
# ======================================================================================


def draw_ribbon(cv, cx, cy, width, height, text, col, *, arc_r=2600.0, text_size=None,
                trim=GOLD, text_top=WHITE, text_bot=None, tail=None, drop=None):
    """Curved banner with folded, notched tails and arc text."""
    col = np.asarray(col, np.float32)
    R = arc_r
    tail = height * 0.95 if tail is None else tail
    drop = height * 0.42 if drop is None else drop
    oc = ink(col, 0.8)

    def mp(sv, tv):
        th = sv / R
        rr = R - tv
        return (cx + rr * math.sin(th), cy + R - rr * math.cos(th))

    def band(s0, s1, t0, t1, n=40):
        top = [mp(s0 + (s1 - s0) * k / n, t0) for k in range(n + 1)]
        bot = [mp(s1 - (s1 - s0) * k / n, t1) for k in range(n + 1)]
        return top + bot

    hw, hh = width / 2, height / 2
    tails = []
    for sgn in (-1, 1):
        s_in, s_out = sgn * (hw - height * 0.6), sgn * (hw + tail)
        tt0, tt1 = -hh + drop, hh + drop
        n = 12
        top = [mp(s_in + (s_out - s_in) * k / n, tt0) for k in range(n + 1)]
        notch = mp(s_out - sgn * height * 0.38, (tt0 + tt1) / 2)
        bot = [mp(s_out + (s_in - s_out) * k / n, tt1) for k in range(n + 1)]
        tails.append((top + [notch] + bot, sgn))
    main = band(-hw, hw, -hh, hh)
    allm = m_union(m_poly(main), *[m_poly(t, 10) for t, _ in tails])
    drop_shadow(cv, m_dilate(allm, height * 0.08), 0, height * 0.16, height * 0.14, 0.55)
    cv.over(oc, m_dilate(allm, height * 0.08))
    for poly, sgn in tails:
        tm = m_poly(poly, 10)
        cv.over(vgrad(dark(col, 0.25), dark(col, 0.5), cy - hh, cy + hh + drop), tm)
        # fold
        f0 = mp(sgn * (hw - height * 0.6), hh)
        f1 = mp(sgn * hw, hh)
        f2 = mp(sgn * (hw - height * 0.6), hh + drop)
        cv.over(dark(col, 0.65), m_poly([f0, f1, f2]))
    mm = m_poly(main)
    cv.over(vgrad(light(col, 0.18), dark(col, 0.22), cy - hh, cy + hh), mm)
    # trims
    trim_t = m_poly(band(-hw, hw, -hh, -hh + height * 0.11))
    trim_b = m_poly(band(-hw, hw, hh - height * 0.11, hh))
    cv.over(np.asarray(trim, np.float32), trim_t)
    cv.over(dark(np.asarray(trim, np.float32), 0.25), trim_b)
    cv.over(WHITE, m_poly(band(-hw, hw, -hh + height * 0.11, -hh + height * 0.30)), 0.13)
    ts = height * 0.62 if text_size is None else text_size
    tcore = m_arc_text(text, cx, cy + ts * 0.02, R, ts, 0)
    touter = m_arc_text(text, cx, cy + ts * 0.02, R, ts, int(ts * 0.12))
    cv.over(SHADOW, m_shift(touter, 0, ts * 0.07), 0.5)
    cv.over(oc, touter)
    bb = tcore.getbbox()
    cv.over(vgrad(text_top, text_bot if text_bot is not None else text_top, bb[1], bb[3]), tcore)


def crown_mask(cx, cy, w, h, angle=0.0):
    pts = [(-0.44, 1.0), (-0.5, 0.20), (-0.34, 0.52), (-0.24, 0.06), (-0.11, 0.46), (0, -0.04),
           (0.11, 0.46), (0.24, 0.06), (0.34, 0.52), (0.5, 0.20), (0.44, 1.0)]
    P = [(cx + x * w, cy - h / 2 + y * h) for x, y in pts]
    body = m_poly(P, w * 0.035)
    tips = [(-0.5, 0.20), (-0.24, 0.06), (0, -0.04), (0.24, 0.06), (0.5, 0.20)]
    balls = [(cx + x * w, cy - h / 2 + y * h) for x, y in tips]
    m = m_union(body, *[m_circle(x, y, w * 0.062) for x, y in balls])
    return (m_rotate(m, angle, cx, cy) if angle else m), balls


def draw_crown(cv, cx, cy, w, h, angle=0.0):
    m, balls = crown_mask(cx, cy, w, h, angle)
    band = m_rrect(cx - w * 0.47, cy - h / 2 + h * 0.70, cx + w * 0.47, cy + h / 2 + h * 0.04, w * 0.05)
    if angle:
        band = m_rotate(band, angle, cx, cy)
    full = m_union(m, band)
    sticker(cv, full, lin(GOLD_L, GOLD_D, (cx - w * 0.3, cy - h * 0.6), (cx + w * 0.3, cy + h * 0.5)),
            outline=GOLD_INK, ow=w * 0.035, shadow=(0, h * 0.06, h * 0.06, 0.5), bevel=w * 0.03,
            top_light=0.45, bottom_dark=0.35)
    cv.over(lin(GOLD, GOLD_D, (0, cy + h * 0.2), (0, cy + h * 0.55)), band)
    cv.over(WHITE, m_inter(m_blur(m_sub(band, m_shift(band, 0, w * 0.02)), 4), band), 0.5)
    # gems
    a = math.radians(angle)

    def R(x, y):
        dx, dy = x - cx, y - cy
        return (cx + dx * math.cos(-a) - dy * math.sin(-a), cy + dx * math.sin(-a) + dy * math.cos(-a))
    gy = cy - h / 2 + h * 0.86
    for gx, gr, gc in ((cx, w * 0.075, rgb("#FF2D55")), (cx - w * 0.27, w * 0.05, rgb("#00E5FF")),
                       (cx + w * 0.27, w * 0.05, rgb("#00E5FF"))):
        x, y = R(gx, gy)
        cv.over(GOLD_INK, m_circle(x, y, gr * 1.25))
        cv.over(rad(light(gc, 0.6), dark(gc, 0.35), (x - gr * 0.3, y - gr * 0.3), gr * 1.3), m_circle(x, y, gr))
        cv.over(WHITE, m_circle(x - gr * 0.3, y - gr * 0.35, gr * 0.28), 0.9)
    for x, y in balls:
        x, y = R(x, y)
        cv.over(WHITE, m_circle(x - w * 0.018, y - w * 0.02, w * 0.02), 0.9)


def draw_flag(cv, bx, by, height, flag_col, *, pole_w=None, flag_w=None, wave=1.0, angle=0.0,
              outline=None):
    """Golf flag: steel pole with ball cap and a waving pennant. (bx, by) = pole base."""
    pole_w = height * 0.045 if pole_w is None else pole_w
    flag_w = height * 0.55 if flag_w is None else flag_w
    flag_col = np.asarray(flag_col, np.float32)
    oc = ink(flag_col, 0.85) if outline is None else outline
    top = by - height
    fh = height * 0.30
    n = 30
    tops, bots = [], []
    for k in range(n + 1):
        t = k / n
        x = bx + pole_w * 0.3 + flag_w * t
        yw = math.sin(t * math.pi * 1.6) * height * 0.035 * wave * t
        tops.append((x, top + height * 0.03 + yw + fh * 0.5 * t * t * 0.0 + (fh * 0.5) * t))
        bots.append((x, top + height * 0.03 + fh + yw - (fh * 0.5) * t))
    flag = m_poly(tops + bots[::-1], height * 0.012)
    pole = m_rrect(bx - pole_w / 2, top, bx + pole_w / 2, by, pole_w / 2)
    if angle:
        flag, pole = m_rotate(flag, angle, bx, by), m_rotate(pole, angle, bx, by)
    both = m_union(flag, pole)
    drop_shadow(cv, m_dilate(both, height * 0.02), height * 0.01, height * 0.03, height * 0.03, 0.45)
    cv.over(oc, m_dilate(both, height * 0.02))
    cv.over(lin(WHITE, rgb("#9AA5B8"), (bx - pole_w / 2, 0), (bx + pole_w / 2, 0)), pole)
    cv.over(vgrad(light(flag_col, 0.25), dark(flag_col, 0.2), top, top + fh * 1.1), flag)
    cv.over(WHITE, m_inter(m_blur(m_sub(flag, m_shift(flag, 0, height * 0.02)), 3), flag), 0.4)
    ca = math.radians(angle)
    cx_, cy_ = bx + math.sin(-ca) * -height, by - math.cos(ca) * height
    cx_, cy_ = bx - math.sin(ca) * height, by - math.cos(ca) * height
    cv.over(oc, m_circle(cx_, cy_, pole_w * 1.25))
    cv.over(rad(GOLD_L, GOLD_D, (cx_ - pole_w * 0.3, cy_ - pole_w * 0.3), pole_w * 1.2), m_circle(cx_, cy_, pole_w * 0.95))


def draw_green(cv, cx, cy, rx, ry, thick, col=rgb("#3BD16F"), side=rgb("#1E8A4A")):
    """Floating putting-green island (top ellipse + rounded side band)."""
    oc = ink(side, 0.75)
    top = m_ellipse(cx, cy, rx, ry)
    bot = m_ellipse(cx, cy + thick, rx, ry)
    mid = m_poly([(cx - rx, cy), (cx + rx, cy), (cx + rx, cy + thick), (cx - rx, cy + thick)])
    allm = m_union(top, bot, mid)
    drop_shadow(cv, m_dilate(allm, rx * 0.03), 0, thick * 0.5, thick * 0.5, 0.5)
    cv.over(oc, m_dilate(allm, rx * 0.03))
    cv.over(vgrad(side, dark(side, 0.45), cy, cy + thick + ry), m_union(bot, mid))
    cv.over(rad(light(col, 0.25), dark(col, 0.15), (cx - rx * 0.2, cy - ry * 0.4), rx * 1.1), top)
    # mowing stripes
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    stripes = ((np.floor((xs - cx + ys * 0.6) / (rx * 0.22)) % 2) == 0).astype(np.float32)
    tm = np.asarray(top, np.float32) / 255
    cv.over_arr(WHITE, stripes * tm * 0.06)
    cv.over(WHITE, m_inter(m_blur(m_sub(top, m_shift(top, 0, ry * 0.08)), 6), top), 0.35)


def draw_cup(cv, cx, cy, rx, ry):
    cv.over(WHITE, m_ellipse(cx, cy, rx * 1.12, ry * 1.18), 0.95)
    cv.over(vgrad(rgb("#05060c"), rgb("#2a2f45"), cy - ry, cy + ry), m_ellipse(cx, cy, rx, ry))
    cv.over(BLACK, m_ellipse(cx, cy - ry * 0.25, rx * 0.92, ry * 0.7), 0.6)


def draw_confetti(cv, rng, n, cx, cy, spread_x, spread_y, size, colors, bias_up=0.0, mask=None):
    for _ in range(n):
        x = cx + rng.normal() * spread_x
        y = cy + rng.normal() * spread_y - abs(rng.normal()) * bias_up
        col = colors[rng.integers(len(colors))]
        w, h = size * rng.uniform(0.6, 1.2), size * rng.uniform(0.25, 0.45)
        a = rng.uniform(0, math.pi)
        kind = rng.integers(3)
        if kind == 2:
            m = m_circle(x, y, h * 0.8)
        else:
            pts = [(x + dx * math.cos(a) - dy * math.sin(a), y + dx * math.sin(a) + dy * math.cos(a))
                   for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2))]
            m = m_poly(pts, h * 0.35)
        if mask is not None:
            m = m_inter(m, mask)
        cv.over(dark(col, 0.55), m_shift(m, 0, size * 0.12), 0.5)
        cv.over(col, m)
        cv.over(WHITE, m_inter(m, m_shift(m, -size * 0.06, -size * 0.06)), 0.0)


def draw_firework(cv, x, y, r, col, rays=14, dots=True, rot=0.0):
    col = np.asarray(col, np.float32)
    glow(cv, m_circle(x, y, r * 0.5), r * 0.4, col, 0.55)
    for k in range(rays):
        a = rot + 2 * math.pi * k / rays
        p0 = (x + math.cos(a) * r * 0.30, y + math.sin(a) * r * 0.30)
        p1 = (x + math.cos(a) * r * 0.86, y + math.sin(a) * r * 0.86)
        line = m_line([p0, p1], r * 0.055)
        cv.add(col, m_blur(line, r * 0.04), 0.8)
        cv.over(light(col, 0.55), line)
        if dots:
            px, py = x + math.cos(a) * r, y + math.sin(a) * r
            cv.over(WHITE, m_circle(px, py, r * 0.045))
            cv.add(col, m_blur(m_circle(px, py, r * 0.06), r * 0.05), 0.9)
    cv.over(WHITE, m_circle(x, y, r * 0.07))


def shield_pts(cx, top, w, h, n=24):
    def bez(p0, p1, p2, p3):
        out = []
        for k in range(n + 1):
            t = k / n
            out.append(tuple(np.array(p0) * (1 - t) ** 3 + 3 * np.array(p1) * t * (1 - t) ** 2 +
                             3 * np.array(p2) * t * t * (1 - t) + np.array(p3) * t ** 3))
        return out
    hw = w / 2
    right = bez((cx, top), (cx + hw * 0.45, top + h * 0.06), (cx + hw * 0.8, top - h * 0.02), (cx + hw, top + h * 0.06))
    right += bez((cx + hw, top + h * 0.06), (cx + hw * 1.02, top + h * 0.55), (cx + hw * 0.55, top + h * 0.82), (cx, top + h))
    left = [(2 * cx - x, y) for x, y in right[::-1]]
    return right + left


def coin_pile(cv, cx, cy, width, height, n, rng, r=None, tilt=(0.32, 0.5)):
    """Mound of coins (drawn back to front)."""
    r = width * 0.13 if r is None else r
    coins = []
    for _ in range(n):
        u = rng.uniform(-1, 1)
        v = rng.uniform(0, 1)
        hmax = (1 - u * u) ** 0.7
        y = cy - v * hmax * height
        x = cx + u * width / 2
        coins.append((y, x))
    coins.sort()
    for y, x in coins:
        draw_coin(cv, x, y, r * rng.uniform(0.85, 1.1), tilt=rng.uniform(*tilt),
                  angle=rng.uniform(-25, 25), shadow=True)


def draw_badge(cv, cx, cy, r, text, col, text_size=None):
    """Round sticker badge with a short label (e.g. "+1")."""
    col = np.asarray(col, np.float32)
    m = m_circle(cx, cy, r)
    sticker(cv, m, rad(light(col, 0.35), dark(col, 0.2), (cx - r * 0.3, cy - r * 0.4), r * 1.5),
            outline=ink(col, 0.8), ow=r * 0.10, shadow=(0, r * 0.12, r * 0.12, 0.55), bevel=r * 0.1,
            top_light=0.4, bottom_dark=0.3)
    cv.over(WHITE, m_inter(m_ellipse(cx - r * 0.1, cy - r * 0.5, r * 0.7, r * 0.35), m), 0.18)
    draw_text(cv, text, cx, cy, text_size or r * 1.05, top=WHITE, bottom=light(col, 0.75),
              outline=ink(col, 0.85), ow=r * 0.11, shadow=None, extrude=r * 0.06)


def draw_sack(cv, cx, cy, size, col, tie=rgb("#E8B021"), emblem=True, frill=True, lumpy=0.0):
    """Cloth coin bag. size ~ half width. (cx, cy) = bag centre."""
    col = np.asarray(col, np.float32)
    s = size
    n = 60
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        # base: squashed circle, wider at the bottom
        x = math.cos(t)
        y = math.sin(t)
        wide = 1.0 + 0.10 * y
        bump = 1 + lumpy * 0.04 * math.sin(5 * t)
        pts.append((cx + x * s * wide * bump, cy + s * 0.18 + y * s * 0.80 * bump))
    body = m_poly(pts)
    neck = m_poly([(cx - s * 0.30, cy - s * 0.80), (cx + s * 0.30, cy - s * 0.80),
                   (cx + s * 0.55, cy - s * 0.30), (cx - s * 0.55, cy - s * 0.30)], s * 0.1)
    shape = m_union(body, neck)
    fr = None
    if frill:
        fp = []
        for k in range(9):
            x = -0.48 + k * 0.12
            fp.append((cx + x * s, cy - s * (1.08 if k % 2 == 0 else 0.96)))
        fp += [(cx + s * 0.34, cy - s * 0.74), (cx - s * 0.34, cy - s * 0.74)]
        fr = m_poly(fp, s * 0.05)
        shape = m_union(shape, fr)
    oc = ink(col, 0.8)
    drop_shadow(cv, m_dilate(shape, s * 0.05), 0, s * 0.10, s * 0.08, 0.5)
    cv.over(oc, m_dilate(shape, s * 0.05))
    cv.over(rad(light(col, 0.38), dark(col, 0.28), (cx - s * 0.35, cy - s * 0.25), s * 1.5), shape)
    # side shading + highlight
    cv.over(BLACK, m_inter(m_blur(m_sub(shape, m_shift(shape, -s * 0.10, -s * 0.06)), s * 0.06), shape), 0.35)
    cv.over(WHITE, m_inter(m_blur(m_ellipse(cx - s * 0.42, cy - s * 0.05, s * 0.16, s * 0.34), s * 0.05), shape), 0.30)
    # folds
    for k, dx in enumerate((-0.18, 0.18)):
        fold = m_line([(cx + dx * s, cy - s * 0.72), (cx + dx * s * 1.6, cy - s * 0.40)], s * 0.035)
        cv.over(dark(col, 0.4), fold, 0.5)
    # tie
    tie_m = m_rrect(cx - s * 0.40, cy - s * 0.84, cx + s * 0.40, cy - s * 0.66, s * 0.09)
    cv.over(GOLD_INK, m_dilate(tie_m, s * 0.03))
    cv.over(vgrad(light(tie, 0.4), dark(tie, 0.3), cy - s * 0.84, cy - s * 0.66), tie_m)
    knot = m_circle(cx + s * 0.18, cy - s * 0.74, s * 0.10)
    cv.over(GOLD_INK, m_dilate(knot, s * 0.03))
    cv.over(rad(light(tie, 0.5), dark(tie, 0.2), (cx + s * 0.15, cy - s * 0.78), s * 0.14), knot)
    for ang in (25, 55):
        a = math.radians(ang)
        p1 = (cx + s * 0.18 + math.sin(a) * s * 0.28, cy - s * 0.74 + math.cos(a) * s * 0.30)
        string = m_line([(cx + s * 0.18, cy - s * 0.74), p1], s * 0.05)
        cv.over(GOLD_INK, m_dilate(string, s * 0.025))
        cv.over(tie, string)
    if emblem:
        ex, ey, er = cx, cy + s * 0.28, s * 0.36
        cv.over(dark(col, 0.45), m_circle(ex, ey + s * 0.02, er * 1.08), 0.6)
        draw_coin(cv, ex, ey, er, tilt=1.0, thick=0.0, shadow=False, ow=er * 0.06)
    return shape


def draw_chest(cv, cx, cy, w, rng, gold_heap=True):
    """Open treasure chest overflowing with coins. (cx, cy) = centre of the front."""
    wood, wood_d = rgb("#B5622E"), rgb("#6B3416")
    h = w * 0.52
    x0, x1 = cx - w / 2, cx + w / 2
    yt, yb = cy - h * 0.35, cy + h * 0.65
    # lid (open, behind)
    lid = m_poly([(x0 + w * 0.04, yt - h * 0.05), (x1 - w * 0.04, yt - h * 0.05), (x1 - w * 0.08, yt - h * 0.95),
                  (x0 + w * 0.08, yt - h * 0.95)], w * 0.05)
    cv.over(GOLD_INK, m_dilate(lid, w * 0.02))
    cv.over(vgrad(rgb("#7A3B18"), rgb("#4A220D"), yt - h, yt), lid)
    inner_lid = m_poly([(x0 + w * 0.10, yt - h * 0.12), (x1 - w * 0.10, yt - h * 0.12), (x1 - w * 0.13, yt - h * 0.86),
                        (x0 + w * 0.13, yt - h * 0.86)], w * 0.03)
    cv.over(rgb("#2E1408"), inner_lid)
    for fx in (0.17, 0.83):
        band = m_poly([(x0 + w * (fx - 0.04), yt - h * 0.05), (x0 + w * (fx + 0.04), yt - h * 0.05),
                       (x0 + w * (fx + 0.035), yt - h * 0.95), (x0 + w * (fx - 0.035), yt - h * 0.95)], 8)
        cv.over(lin(GOLD_L, GOLD_D, (x0, 0), (x1, 0)), band)
    # inner glow
    glow(cv, m_ellipse(cx, yt, w * 0.42, h * 0.35), w * 0.10, rgb("#FFD36B"), 1.0)
    # coins heap
    if gold_heap:
        coin_pile(cv, cx, yt + h * 0.12, w * 0.86, h * 0.55, 26, rng, r=w * 0.085)
    # body
    body = m_rrect(x0, yt, x1, yb, w * 0.06)
    sticker(cv, body, vgrad(wood, wood_d, yt, yb), outline=GOLD_INK, ow=w * 0.025,
            shadow=(0, w * 0.04, w * 0.04, 0.5), bevel=w * 0.02, top_light=0.25, bottom_dark=0.3)
    # planks
    for k in range(1, 3):
        yy = yt + (yb - yt) * k / 3
        cv.over(dark(wood, 0.45), m_rrect(x0 + w * 0.02, yy - 4, x1 - w * 0.02, yy + 4, 4), 0.7)
    # gold trims
    rim = m_rrect(x0 - w * 0.015, yt - h * 0.02, x1 + w * 0.015, yt + h * 0.13, w * 0.03)
    cv.over(GOLD_INK, m_dilate(rim, w * 0.015))
    cv.over(vgrad(GOLD_L, GOLD_D, yt, yt + h * 0.13), rim)
    for fx in (0.17, 0.83):
        band = m_rrect(x0 + w * (fx - 0.045), yt, x0 + w * (fx + 0.045), yb, w * 0.02)
        cv.over(GOLD_INK, m_dilate(band, w * 0.012))
        cv.over(lin(GOLD_L, GOLD_D, (x0 + w * (fx - 0.045), 0), (x0 + w * (fx + 0.045), 0)), band)
    # lock plate with golf-flag stamp
    lp = m_rrect(cx - w * 0.10, yt + h * 0.06, cx + w * 0.10, yt + h * 0.44, w * 0.04)
    cv.over(GOLD_INK, m_dilate(lp, w * 0.015))
    cv.over(vgrad(GOLD_L, GOLD_D, yt, yt + h * 0.44), lp)
    cv.over(GOLD_INK, m_circle(cx, yt + h * 0.24, w * 0.035))
    cv.over(GOLD_INK, m_rrect(cx - w * 0.012, yt + h * 0.24, cx + w * 0.012, yt + h * 0.36, 4))


def draw_vault(cv, cx, cy, r, rng):
    """Round vault door with gold trim, bolts and a spoked wheel."""
    st_hi, st_lo = rgb("#E9EEF8"), rgb("#58627C")
    oc = rgb("#141826")
    outer = m_circle(cx, cy, r)
    drop_shadow(cv, outer, 0, r * 0.06, r * 0.06, 0.55)
    cv.over(oc, m_circle(cx, cy, r * 1.05))
    cv.over(lin(GOLD_L, GOLD_D, (cx - r, cy - r), (cx + r, cy + r)), outer)
    cv.over(GOLD_INK, m_circle(cx, cy, r * 0.90))
    cv.over(lin(st_hi, st_lo, (cx - r, cy - r), (cx + r * 0.6, cy + r * 0.6)), m_circle(cx, cy, r * 0.87))
    cv.over(lin(st_lo, st_hi, (cx - r, cy - r), (cx + r * 0.6, cy + r * 0.6)), m_circle(cx, cy, r * 0.74))
    cv.over(lin(rgb("#C3CCE0"), rgb("#6A7590"), (cx - r, cy - r), (cx + r * 0.6, cy + r * 0.6)),
            m_circle(cx, cy, r * 0.69))
    # bolts on the ring
    for k in range(12):
        a = 2 * math.pi * k / 12 + 0.26
        x, y = cx + math.cos(a) * r * 0.805, cy + math.sin(a) * r * 0.805
        cv.over(oc, m_circle(x, y + r * 0.012, r * 0.045))
        cv.over(rad(WHITE, st_lo, (x - r * 0.015, y - r * 0.015), r * 0.05), m_circle(x, y, r * 0.037))
    # wheel
    for k in range(3):
        a = math.pi * k / 3 + 0.3
        p0 = (cx + math.cos(a) * r * 0.48, cy + math.sin(a) * r * 0.48)
        p1 = (cx - math.cos(a) * r * 0.48, cy - math.sin(a) * r * 0.48)
        spoke = m_line([p0, p1], r * 0.075)
        cv.over(oc, m_dilate(spoke, r * 0.02))
        cv.over(lin(GOLD_L, GOLD_D, (cx - r * 0.5, cy - r * 0.5), (cx + r * 0.5, cy + r * 0.5)), spoke)
        for pp in (p0, p1):
            cv.over(oc, m_circle(pp[0], pp[1], r * 0.085))
            cv.over(rad(GOLD_L, GOLD_D, (pp[0] - r * 0.02, pp[1] - r * 0.02), r * 0.08), m_circle(pp[0], pp[1], r * 0.065))
    ring = m_sub(m_circle(cx, cy, r * 0.40), m_circle(cx, cy, r * 0.32))
    cv.over(oc, m_dilate(ring, r * 0.015))
    cv.over(lin(GOLD_L, GOLD_D, (cx - r * 0.4, cy - r * 0.4), (cx + r * 0.4, cy + r * 0.4)), ring)
    draw_golf_ball(cv, (cx, cy), r * 0.22, GOLD, dimples=50, ow=r * 0.02, metal=True, shadow=False,
                   rim_color=(1.0, 0.75, 0.3))
    cv.over(WHITE, m_inter(m_ellipse(cx - r * 0.25, cy - r * 0.55, r * 0.55, r * 0.22), outer), 0.18)


# ======================================================================================
# Icons
# ======================================================================================

ICONS = {}


def icon(name, use):
    def deco(fn):
        ICONS[name] = (fn, use)
        return fn
    return deco


def sparkles(cv, spots, col=WHITE, glow_col=None):
    for x, y, r in spots:
        sparkle(cv, x, y, r, col, glow_col=glow_col)


def crate_icon(col, *, metal="steel", emblem="ball", seam=None, bg_in=None, bg_out=None,
               rays_col=None, extra_bg=None, sparkle_spots=(), sparkle_glow=None, aura=None,
               scale=820, cy=C * 1.02):
    col = np.asarray(col, np.float32)
    cv = Canvas(color=NAVY)
    background(cv, bg_in if bg_in is not None else light(col, 0.05),
               bg_out if bg_out is not None else mix(dark(col, 0.75), NAVY, 0.4),
               rays=(14, rays_col if rays_col is not None else light(col, 0.5), 0.10))
    if extra_bg:
        extra_bg(cv)
    em = emblem_image(emblem, col, "gold" if metal == "gold" else ("dark" if metal == "dark" else "steel"))
    draw_crate(cv, C, cy, scale, col, metal=metal, emblem=em, seam=seam, aura=aura)
    sparkles(cv, sparkle_spots, glow_col=sparkle_glow if sparkle_glow is not None else light(col, 0.4))
    return cv


@icon("crate_skins", "Shop crate: Ball Skin Crate (Coins or Skin key)")
def crate_skins():
    def bg(cv):
        rng = np.random.default_rng(21)
        for col in (rgb("#FF4FA3"), rgb("#00E5FF"), rgb("#FFD93B"), rgb("#7CF2B8")) * 2:
            x, y = rng.uniform(200, 1850), rng.uniform(200, 1850)
            if math.hypot(x - C, y - C) < 700:
                continue
            cv.over(col, m_circle(x, y, rng.uniform(40, 80)), 0.16)
    return crate_icon(rgb("#3D8BFF"), metal="steel", emblem="skin", seam=rgb("#D8E8FF"), extra_bg=bg,
                      sparkle_spots=[(430, 470, 60), (1660, 560, 46)])


@icon("crate_trails", "Shop crate: Trail Crate (Coins or Trail key)")
def crate_trails():
    def bg(cv):
        for k, (y0, col) in enumerate(((1500, rgb("#B04DFF")), (1640, rgb("#00E5FF")), (1780, rgb("#FFFFFF")))):
            pts = [(x, y0 - 420 * math.sin(math.pi * x / S) + 60 * math.sin(x / 260.0)) for x in range(-50, S + 60, 40)]
            cv.add(col, m_blur(m_line(pts, 36 - k * 8), 6), 0.16)
    return crate_icon(rgb("#00E5FF"), metal="steel", emblem="trail", seam=rgb("#E0FBFF"),
                      bg_in=rgb("#27B9E8"), bg_out=rgb("#0A1240"), rays_col=rgb("#C9F6FF"), extra_bg=bg,
                      sparkle_spots=[(430, 470, 60), (1660, 560, 46)])


@icon("crate_knockouts", "Shop crate: Knockout Crate (Coins or Knockout key)")
def crate_knockouts():
    def bg(cv):
        pts = []
        for k in range(28):
            a = math.pi * k / 14
            rr = S * (0.62 if k % 2 == 0 else 0.44)
            pts.append((C + math.cos(a) * rr, C * 0.98 + math.sin(a) * rr))
        cv.over(rgb("#FFD0B0"), m_poly(pts), 0.08)
    return crate_icon(rgb("#FF5A36"), metal="steel", emblem="burst", seam=rgb("#FFE1C8"),
                      bg_in=rgb("#FF6F45"), bg_out=rgb("#2E0712"), rays_col=rgb("#FFD0B0"), extra_bg=bg,
                      sparkle_spots=[(430, 470, 60), (1660, 560, 46)])


@icon("crate_arrows", "Shop crate: Arrow Crate (Coins or Arrow key)")
def crate_arrows():
    def bg(cv):
        for k in range(3):
            x = 260 + k * 150
            ch = [(x, 1500), (x + 120, 1620), (x, 1740), (x - 60, 1740), (x + 60, 1620), (x - 60, 1500)]
            cv.over(rgb("#FFF3B0"), m_poly(ch, 10), 0.10 + 0.04 * k)
            x2 = S - 260 - (2 - k) * 150
            ch2 = [(x2, 360), (x2 + 120, 480), (x2, 600), (x2 - 60, 600), (x2 + 60, 480), (x2 - 60, 360)]
            cv.over(rgb("#FFF3B0"), m_poly(ch2, 10), 0.10 + 0.04 * k)
    return crate_icon(rgb("#FFC83D"), metal="steel", emblem="arrow", seam=rgb("#FFF6D0"),
                      bg_in=rgb("#F2A93B"), bg_out=rgb("#3A1400"), rays_col=rgb("#FFF3B0"), extra_bg=bg,
                      sparkle_spots=[(430, 470, 60), (1660, 560, 46)])


def mythic_crate(cv_extra=None):
    red = rgb("#FF2D55")

    def bg(cv):
        cv.add_arr(GOLD, rays_alpha(C, C * 0.95, 9, rot=0.17, width=0.18) * 0.22)
        glow(cv, m_circle(C, C * 0.98, S * 0.30), S * 0.12, rgb("#FF4D4D"), 0.75)
        glow(cv, m_circle(C, C * 0.98, S * 0.20), S * 0.08, rgb("#FFD36B"), 0.55)
    cv = crate_icon(red, metal="gold", emblem="ball_gold", seam=rgb("#FFE38A"),
                    bg_in=rgb("#FF4D6D"), bg_out=rgb("#2A0010"), rays_col=rgb("#FFD36B"),
                    extra_bg=bg, aura=rgb("#FFB347"), scale=760, cy=C * 0.97,
                    sparkle_spots=[(400, 430, 84), (1690, 470, 66), (1700, 1180, 44), (330, 1150, 40),
                                   (1240, 300, 34)], sparkle_glow=rgb("#FFD36B"))
    draw_ribbon(cv, C, S * 0.775, S * 0.66, S * 0.15, "MYTHIC", rgb("#E0103A"), arc_r=S * 1.25,
                trim=GOLD, text_top=rgb("#FFFFFF"), text_bot=rgb("#FFE38A"), tail=S * 0.08)
    return cv


@icon("crate_mythic_featured", "In-game reference / hero art: Mythic Featured Crate")
def crate_mythic_featured():
    return mythic_crate()


@icon("crate_target", "In-game reference: Bullseye Crate (Target practice tokens)")
def crate_target():
    def bg(cv):
        for k, rr in enumerate((0.47, 0.39, 0.31, 0.23)):
            ring = m_sub(m_circle(C, C * 0.98, S * rr), m_circle(C, C * 0.98, S * (rr - 0.035)))
            cv.over(rgb("#FFE3E5"), ring, 0.07)
    return crate_icon(rgb("#E63946"), metal="steel", emblem="bullseye", seam=rgb("#FFD6D9"),
                      bg_in=rgb("#F25563"), bg_out=rgb("#2B0610"), extra_bg=bg,
                      sparkle_spots=[(420, 480, 58), (1650, 560, 44)])


@icon("crate_drive", "In-game reference: Long-Drive Crate (Drive practice tokens)")
def crate_drive():
    def bg(cv):
        rng = np.random.default_rng(3)
        for _ in range(16):
            y = rng.uniform(250, 1800)
            x = rng.uniform(100, 1900)
            L = rng.uniform(220, 520)
            line = m_line([(x, y), (x + L * 0.82, y - L * 0.57)], rng.uniform(10, 22))
            cv.add(rgb("#BFF3FF"), line, rng.uniform(0.10, 0.22))
    return crate_icon(rgb("#00B4FF"), metal="steel", emblem="rocket", seam=rgb("#E0FBFF"),
                      bg_in=rgb("#2CC4FF"), bg_out=rgb("#04203F"), extra_bg=bg,
                      sparkle_spots=[(430, 470, 56), (1660, 540, 44)])


@icon("crate_hazard", "In-game reference: Hazard Crate (Hazard practice tokens)")
def crate_hazard():
    def bg(cv):
        ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
        band = ((xs + ys) / 150.0) % 2.0
        st = np.clip((np.abs(band - 1.0) - 0.5) * 20 + 0.5, 0, 1)
        fade = np.clip((ys - S * 0.78) / (S * 0.06), 0, 1)
        cv.over_arr(rgb("#14110A"), st * fade * 0.55)
    return crate_icon(rgb("#FFB703"), metal="dark", emblem="hazard", seam=rgb("#FFF1B8"),
                      bg_in=rgb("#C9741A"), bg_out=rgb("#1F1000"), rays_col=rgb("#FFE08A"), extra_bg=bg,
                      sparkle_spots=[(430, 470, 56), (1660, 540, 44)])


@icon("pass_vip", "Game pass: VIP")
def pass_vip():
    cv = Canvas(color=NAVY)
    background(cv, rgb("#7B2CFF"), rgb("#14052E"), rays=(16, GOLD, 0.13))
    glow(cv, m_circle(C, C * 1.02, S * 0.26), S * 0.10, rgb("#FFC83D"), 0.45)
    draw_golf_ball(cv, (C, C * 1.04), 400, GOLD, metal=True, rim_color=(1.0, 0.55, 0.9), dimples=80)
    draw_crown(cv, C - 20, C * 0.50, 640, 400, angle=-8)
    draw_text(cv, "VIP", C, S * 0.745, 400, top=WHITE, bottom=rgb("#FFE38A"), outline=rgb("#2A0A5C"),
              ow=46, extrude=26)
    sparkles(cv, [(420, 640, 70), (1640, 760, 58), (1600, 1300, 40), (470, 1260, 36)], glow_col=GOLD)
    return cv


@icon("pass_double_coins", "Game pass: 2x Coins")
def pass_double_coins():
    cv = Canvas(color=NAVY)
    background(cv, rgb("#1FD17A"), rgb("#032B1F"), rays=(16, rgb("#E9FFB0"), 0.12))
    glow(cv, m_circle(C, C * 0.80, S * 0.25), S * 0.10, GOLD, 0.5)
    draw_coin(cv, C + 50, C * 0.92, 390, tilt=0.42, angle=-6)
    draw_coin(cv, C - 40, C * 0.92 - 165, 390, tilt=0.42, angle=-13)
    draw_text(cv, "2X", C, S * 0.695, 540, top=WHITE, bottom=rgb("#FFE36B"), outline=rgb("#06301F"),
              ow=60, rotate=6, extrude=34)
    sparkles(cv, [(420, 520, 66), (1640, 560, 54), (430, 1380, 38), (1620, 1360, 34)], glow_col=GOLD)
    return cv


@icon("pass_celebrations", "Game pass: Celebration Pack")
def pass_celebrations():
    cv = Canvas(color=NAVY)
    background(cv, rgb("#9B2CFF"), rgb("#12052E"), rays=(18, rgb("#FF8BD1"), 0.10))
    draw_firework(cv, 560, 640, 330, rgb("#00E5FF"), rays=14, rot=0.1)
    draw_firework(cv, 1500, 560, 290, rgb("#FFD000"), rays=12, rot=0.25)
    draw_firework(cv, 1120, 330, 180, rgb("#FF4FD8"), rays=10, rot=0.0)
    draw_green(cv, C, S * 0.70, 640, 210, 120)
    # confetti burst from the cup
    rng = np.random.default_rng(11)
    cone = m_poly([(C - 90, S * 0.69), (C + 90, S * 0.69), (C + 640, S * 0.20), (C - 640, S * 0.20)])
    glow(cv, cone, 80, rgb("#FFD36B"), 0.18)
    draw_cup(cv, C, S * 0.69, 150, 52)
    draw_confetti(cv, rng, 46, C, S * 0.43, 330, 210, 66,
                  [rgb("#FF2D55"), rgb("#FFD000"), rgb("#00E5FF"), rgb("#7CF2B8"), rgb("#FF8BD1"), WHITE])
    draw_flag(cv, C + 270, S * 0.735, 900, rgb("#FF2D55"), angle=0)
    draw_golf_ball(cv, (C - 330, S * 0.665), 120, rgb("#F7F9FF"), dimples=60)
    sparkles(cv, [(380, 1060, 46), (1690, 1090, 40)], glow_col=rgb("#FF8BD1"))
    return cv


@icon("pass_founder", "Game pass: Founder")
def pass_founder():
    dark_c, red = rgb("#2B2D42"), rgb("#EF233C")
    cv = Canvas(color=NAVY)
    background(cv, rgb("#4A4E6E"), rgb("#0E0F18"), rays=(12, red, 0.10))
    glow(cv, m_circle(C, C, S * 0.28), S * 0.10, red, 0.35)
    top, w, h = S * 0.185, S * 0.56, S * 0.64
    outer = m_poly(shield_pts(C, top, w, h))
    sticker(cv, outer, lin(light(red, 0.15), dark(red, 0.25), (C - w / 2, top), (C + w / 2, top + h)),
            outline=rgb("#0B0C14"), ow=34, shadow=(0, 40, 36, 0.6), bevel=24, top_light=0.4, bottom_dark=0.35)
    inner = m_poly(shield_pts(C, top + 64, w - 136, h - 118))
    cv.over(rgb("#0B0C14"), m_dilate(inner, 14))
    cv.over(rad(light(dark_c, 0.12), dark(dark_c, 0.35), (C, top + 260), w * 0.6), inner)
    cv.over(WHITE, m_inter(m_poly(shield_pts(C, top + 70, w - 150, h * 0.36)), inner), 0.06)
    draw_golf_ball(cv, (C, top + h * 0.44), 225, rgb("#F7F9FF"), rim_color=light(red, 0.2), dimples=72)
    # star above the ball
    star = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = 96 if k % 2 == 0 else 42
        star.append((C + rr * math.cos(a), top + 128 + rr * math.sin(a)))
    sticker(cv, m_poly(star, 8), vgrad(GOLD_L, GOLD_D, top + 30, top + 240), outline=GOLD_INK, ow=14,
            shadow=(0, 10, 10, 0.5))
    draw_ribbon(cv, C, top + h * 0.79, S * 0.62, S * 0.12, "FOUNDER", red, arc_r=S * 1.4, trim=dark_c,
                text_top=WHITE, text_bot=rgb("#FFD6DA"), tail=S * 0.045, text_size=S * 0.078)
    return cv


def coins_icon(bg_in, bg_out, rays_col, draw_fn, sparkle_spots, glow_col=GOLD, rays_n=16, rays_op=0.12):
    cv = Canvas(color=NAVY)
    background(cv, bg_in, bg_out, rays=(rays_n, rays_col, rays_op))
    glow(cv, m_circle(C, C, S * 0.25), S * 0.10, glow_col, 0.35)
    draw_fn(cv)
    sparkles(cv, sparkle_spots, glow_col=glow_col)
    return cv


@icon("product_coins_1", "Dev product: Coin Pouch (1,000 Coins)")
def product_coins_1():
    def art(cv):
        rng = np.random.default_rng(1)
        draw_sack(cv, C, C * 0.98, 420, rgb("#E39A4F"), emblem=True)
        draw_coin(cv, C - 380, C * 1.48, 170, tilt=0.45, angle=12)
        draw_coin(cv, C + 360, C * 1.50, 190, tilt=0.40, angle=-16)
        draw_coin(cv, C + 120, C * 1.62, 150, tilt=0.35, angle=8)
    return coins_icon(rgb("#2BD46A"), rgb("#05301A"), rgb("#D7FFB0"), art, [(440, 520, 54), (1600, 600, 44)])


@icon("product_coins_2", "Dev product: Coin Sack (3,500 Coins)")
def product_coins_2():
    def art(cv):
        rng = np.random.default_rng(2)
        draw_sack(cv, C, C * 0.90, 500, rgb("#E8A85E"), emblem=True, lumpy=1.0)
        coin_pile(cv, C, C * 1.70, 1300, 300, 13, rng, r=160)
    return coins_icon(rgb("#3D8BFF"), rgb("#071A40"), rgb("#BFE0FF"), art,
                      [(420, 500, 62), (1640, 560, 52), (1690, 1100, 36)])


@icon("product_coins_3", "Dev product: Coin Chest (10,000 Coins)")
def product_coins_3():
    def art(cv):
        rng = np.random.default_rng(3)
        glow(cv, m_ellipse(C, C * 0.82, S * 0.28, S * 0.16), S * 0.08, rgb("#FFD36B"), 0.6)
        cv.add_arr(rgb("#FFE9A8"), rays_alpha(C, C * 0.78, 10, rot=-0.3, width=0.22, r1=S * 0.6) * 0.25)
        draw_chest(cv, C, C * 1.08, 1180, rng)
        coin_pile(cv, C, C * 1.78, 1350, 200, 12, rng, r=140)
    return coins_icon(rgb("#B04DFF"), rgb("#1A0636"), rgb("#F0C8FF"), art,
                      [(390, 480, 72), (1660, 470, 60), (1700, 1060, 40), (340, 1080, 36)])


@icon("product_coins_4", "Dev product: Coin Vault (28,000 Coins)")
def product_coins_4():
    def art(cv):
        rng = np.random.default_rng(4)
        cv.add_arr(GOLD, rays_alpha(C, C * 0.9, 12, rot=0.13, width=0.2) * 0.25)
        glow(cv, m_circle(C, C * 0.86, S * 0.32), S * 0.10, rgb("#FFB347"), 0.7)
        draw_vault(cv, C, C * 0.86, 600, rng)
        coin_pile(cv, C, C * 1.78, 1500, 420, 26, rng, r=150)
    return coins_icon(rgb("#FF5A3C"), rgb("#2A0710"), rgb("#FFE38A"), art,
                      [(380, 420, 80), (1680, 430, 66), (1730, 1060, 46), (300, 1060, 44), (1250, 220, 34)],
                      glow_col=rgb("#FFD36B"))


@icon("product_mythic_crate", "Dev product: Mythic Featured Crate (+1)")
def product_mythic_crate():
    cv = mythic_crate()
    draw_badge(cv, S * 0.73, S * 0.25, 175, "+1", rgb("#22D46B"))
    return cv


def _qbez(p0, p1, p2, n=48):
    p0, p1, p2 = (np.array(p, np.float64) for p in (p0, p1, p2))
    return [tuple(p0 * (1 - t) ** 2 + 2 * p1 * t * (1 - t) + p2 * t * t) for t in np.linspace(0, 1, n)]


@icon("game_icon", "Experience icon (512x512)")
def game_icon():
    cv = Canvas(color=NAVY)
    background(cv, rgb("#8A2BE2"), rgb("#12062E"), center=(C, C * 1.25), radius=S * 0.85,
               rays=(18, rgb("#FF8BD1"), 0.08), vignette=0.35)
    gy = S * 0.80
    draw_green(cv, C, gy, 900, 225, 120)
    l1, l2 = (360, gy + 70), (720, gy + 10)
    ball = (1010, 1300)
    br = 230
    # ball shadow on the green
    cv.over(SHADOW, m_blur(m_ellipse(ball[0] + 40, gy + 20, br * 0.9, br * 0.22), 20), 0.45)
    draw_cup(cv, 1560, gy + 30, 125, 42)
    draw_flag(cv, 1610, gy + 32, 620, rgb("#FFD000"), flag_w=330)
    # impact marks where the ball bounced
    for (x, y), k in ((l1, 0.8), (l2, 1.0)):
        ring = m_sub(m_ellipse(x, y, 120 * k, 34 * k), m_ellipse(x, y, 96 * k, 24 * k))
        cv.add(rgb("#BFF3FF"), m_blur(ring, 6), 0.7)
        for a in (-150, -120, -60, -30):
            ar = math.radians(a)
            p0 = (x + math.cos(ar) * 70 * k, y + math.sin(ar) * 40 * k)
            p1 = (x + math.cos(ar) * 150 * k, y + math.sin(ar) * 110 * k)
            cv.over(WHITE, m_line([p0, p1], 16 * k), 0.9)
    # neon chaos streaks along the bounce path
    paths = [_qbez((-80, 1260), (150, 1200), l1), _qbez(l1, (540, gy - 640), l2),
             _qbez(l2, (840, 1240), ball)]
    for dx, dy, col, w in ((0, 0, rgb("#00E5FF"), 44), (-10, 26, rgb("#FF00A0"), 26), (8, -22, rgb("#FFD000"), 18)):
        for pts in paths:
            pts2 = [(x + dx, y + dy) for x, y in pts]
            line = m_line(pts2, w)
            cv.add(col, m_blur(line, w * 1.3), 0.85)
            cv.over(light(col, 0.45), line)
            if w > 30:
                cv.over(WHITE, m_line(pts2, w * 0.35), 0.85)
    glow(cv, m_circle(*ball, br * 1.1), 70, rgb("#00E5FF"), 0.5)
    draw_golf_ball(cv, ball, br, rgb("#F7F9FF"), dimples=72, rim_color=(0.2, 0.95, 1.0))
    # title
    draw_text(cv, "CHAOS", C, S * 0.155, 450, top=rgb("#FFF36B"), bottom=rgb("#FF8A00"),
              outline=rgb("#1A0636"), ow=56, rotate=4, extrude=38)
    draw_text(cv, "GOLF", C, S * 0.365, 450, top=WHITE, bottom=rgb("#7FEFFF"), outline=rgb("#1A0636"),
              ow=56, rotate=4, extrude=38)
    sparkles(cv, [(1850, 520, 58), (210, 640, 48), (1840, 1120, 36)], glow_col=rgb("#FF8BD1"))
    return cv


@icon("icon_daily_grand", "In-game reference: 14-day login grand prize - Eternal Dawn ball (exclusive)")
def icon_daily_grand():
    warm, pink = rgb("#FFB547"), rgb("#FF5E7E")
    bc = (C, S * 0.47)
    br = 420
    cv = Canvas(color=NAVY)
    background(cv, rgb("#FF7A59"), rgb("#1E0830"), center=bc, radius=S * 0.82, vignette=0.4)
    cv.add_arr(rgb("#FFD36B"), rays_alpha(bc[0], bc[1], 16, rot=0.1, width=0.22, r1=S * 0.9) * 0.32)
    cv.add_arr(rgb("#FFE7A3"), rays_alpha(bc[0], bc[1], 8, rot=0.3, width=0.07, r1=S * 0.8) * 0.30)
    glow(cv, m_circle(*bc, br * 1.15), 170, warm, 0.85)
    glow(cv, m_circle(*bc, br * 0.9), 90, pink, 0.35)
    # dawn horizon
    hz = m_ellipse(C, S * 1.66, S * 1.05, S * 0.76)
    cv.over(vgrad(rgb("#4A1452"), rgb("#14051F"), S * 0.88, S), hz)
    rim = m_inter(m_sub(hz, m_shift(hz, 0, 16)), hz)
    cv.add(warm, m_blur(rim, 34), 1.0)
    cv.over(rgb("#FFE7A3"), rim)
    # orbit ring (back half behind the ball, front half in front)
    tilt = -16
    ring = m_sub(m_ellipse(bc[0], bc[1], 640, 150), m_ellipse(bc[0], bc[1], 622, 136))
    ring = m_rotate(ring, tilt, *bc)
    upper = m_rotate(m_poly([(0, 0), (S, 0), (S, bc[1]), (0, bc[1])]), tilt, *bc)
    back, front = m_inter(ring, upper), m_sub(ring, upper)
    cv.add(rgb("#FFD36B"), m_blur(back, 10), 0.6)
    cv.over(rgb("#FFE7A3"), back, 0.55)
    draw_golf_ball(cv, bc, br, warm, base_color2=pink, emissive=0.45, rim_color=(1.0, 0.9, 0.55),
                   outline_color=rgb("#4A1030"), dimples=80)
    cv.add(rgb("#FFD36B"), m_blur(front, 12), 0.9)
    cv.over(rgb("#FFF6D8"), front)
    a = math.radians(tilt)
    for t, rr in ((0.30, 46), (2.45, 34), (1.25, 26)):
        x0, y0 = 640 * math.cos(t), 150 * math.sin(t)
        x, y = bc[0] + x0 * math.cos(a) - y0 * math.sin(a), bc[1] + x0 * math.sin(a) + y0 * math.cos(a)
        sparkle(cv, x, y, rr * 2.2, glow_col=rgb("#FFD36B"))
    sparkles(cv, [(430, 380, 70), (1650, 330, 58), (1720, 1180, 40), (330, 1120, 44)], glow_col=rgb("#FFD36B"))
    return cv


# ======================================================================================
# Contact sheet & main
# ======================================================================================

PASS_ICONS = {"pass_vip", "pass_double_coins", "pass_celebrations", "pass_founder"}


def contact_sheet(names, path, cell=300, cols=4):
    rows = math.ceil(len(names) / cols)
    pad, label_h, head = 24, 44, 90
    W = cols * cell + (cols + 1) * pad
    H = head + rows * (cell + label_h) + (rows + 1) * pad
    sheet = Image.new("RGB", (W, H), (14, 16, 30))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 28), "Chaos Golf - icon contact sheet", font=get_font(36, "black"), fill=(245, 247, 255))
    d.text((W - pad, 40), "game passes shown with Roblox circle crop", font=get_font(22, "semibold"),
           fill=(150, 158, 190), anchor="ra")
    for i, name in enumerate(names):
        r, c = divmod(i, cols)
        x = pad + c * (cell + pad)
        y = head + pad + r * (cell + label_h + pad)
        im = Image.open(os.path.join(OUT_DIR, name + ".png")).convert("RGB").resize((cell, cell), Image.LANCZOS)
        if name in PASS_ICONS:
            mask = Image.new("L", (cell * 4, cell * 4), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, cell * 4 - 1, cell * 4 - 1), fill=255)
            mask = mask.resize((cell, cell), Image.LANCZOS)
            bgc = Image.new("RGB", (cell, cell), (14, 16, 30))
            bgc.paste(im, (0, 0), mask)
            im = bgc
        sheet.paste(im, (x, y))
        d.text((x + cell / 2, y + cell + 10), name + ".png", font=get_font(20, "semibold"),
               fill=(220, 224, 240), anchor="ma")
    sheet.save(path, optimize=True)


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    wanted = [a for a in argv if not a.startswith("-")]
    names = [n for n in ICONS if not wanted or n in wanted]
    unknown = [w for w in wanted if w not in ICONS]
    if unknown:
        raise SystemExit(f"unknown icon(s): {unknown}; choose from {list(ICONS)}")
    for name in names:
        fn, use = ICONS[name]
        cv = fn()
        cv.save(os.path.join(OUT_DIR, name + ".png"))
        print(f"  {name}.png  ({use})")
    if "--no-sheet" not in argv:
        contact_sheet(list(ICONS), os.path.join(OUT_DIR, "contact_sheet.png"))
        print("  contact_sheet.png")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
