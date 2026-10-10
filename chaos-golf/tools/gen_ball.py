#!/usr/bin/env python3
"""Chaos Golf - dimpled golf-ball mesh generator.

Writes
  assets/mesh/golfball.obj          the mesh (Y-up, units = studs, CCW outward faces)
  assets/mesh/golfball_preview.png  512x512 software-rendered preview

Construction
  * 108 dimple centres with octahedral (24-fold rotational) symmetry: four generic
    orbits of 24 plus the 12 two-fold-axis directions, relaxed by repulsion and then
    Lloyd (centroidal Voronoi) iterations so every dimple has almost the same area.
    The symmetry forces the six +-X/+-Y/+-Z directions to be Voronoi corners, which
    become land vertices exactly on the sphere -> the bounding box is exactly 1.5^3.
  * Land = the spherical-Voronoi corners of those centres, all exactly on the
    sphere (radius 0.75), so neighbouring dimples meet in thin land ridges along
    the Voronoi edges (hex-dimple look). The longest ridges (whole symmetry orbits,
    longest first) also get a midpoint on the sphere until TARGET_TRIS is reached.
  * Each dimple is a fan from its centre vertex (sunk by DEPTH) to its rim.
  * Normals (per face corner, positions stay shared -> watertight): dimple centre =
    radial; rim corners = spherical-cap normals tilted toward the dimple centre, so
    each fan shades like a soft round cup and the ridges catch a thin highlight.
  * UVs: equirectangular, split at the seam per face corner.

Requires: numpy, scipy, Pillow.   Run:  python3 tools/gen_ball.py
"""
from __future__ import annotations

import itertools
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy.spatial import SphericalVoronoi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "mesh")
OBJ_PATH = os.path.join(OUT_DIR, "golfball.obj")
PREVIEW_PATH = os.path.join(OUT_DIR, "golfball_preview.png")

RADIUS = 0.75          # studs -> diameter 1.5 == Config.Ball.Diameter
N_DIMPLES = 108
DEPTH = 0.042          # dimple depth below the sphere (studs)
CUP_TILT_DEG = 24.0    # normal tilt at an average dimple rim (soft spherical cup)
TARGET_TRIS = 960      # soft target; HARD_MAX_TRIS is never exceeded
HARD_MAX_TRIS = 1100
SEED = 7


# --------------------------------------------------------------------------------------
# Dimple layout
# --------------------------------------------------------------------------------------

def octahedral_rotations() -> np.ndarray:
    """The 24 proper rotations of the cube as signed permutation matrices (exact in FP)."""
    mats = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1.0, -1.0), repeat=3):
            m = np.zeros((3, 3))
            for row, (col, s) in enumerate(zip(perm, signs)):
                m[row, col] = s
            if np.linalg.det(m) > 0:
                mats.append(m)
    assert len(mats) == 24
    return np.array(mats)


ROTS = octahedral_rotations()


def two_fold_axes() -> np.ndarray:
    pts = set()
    for a, b in itertools.product((1, -1), repeat=2):
        pts.add((a, b, 0))
        pts.add((a, 0, b))
        pts.add((0, a, b))
    arr = np.array(sorted(pts), dtype=float)
    return arr / np.linalg.norm(arr, axis=1, keepdims=True)


FIXED = two_fold_axes()  # 12 points, invariant under the group as a set
N_ORBITS = (N_DIMPLES - len(FIXED)) // len(ROTS)
assert N_ORBITS * len(ROTS) + len(FIXED) == N_DIMPLES


def expand(reps: np.ndarray) -> np.ndarray:
    """reps (N_ORBITS,3) -> all 108 points; orbit o, rotation g at index o*24+g."""
    orbit_pts = np.einsum("gij,oj->ogi", ROTS, reps).reshape(-1, 3)
    return np.vstack([orbit_pts, FIXED])


def symmetrize(points: np.ndarray) -> np.ndarray:
    """Average each orbit back onto its representative (keeps exact symmetry)."""
    orbit_pts = points[: N_ORBITS * 24].reshape(N_ORBITS, 24, 3)
    back = np.einsum("gji,ogj->ogi", ROTS, orbit_pts)  # R^T p
    reps = back.mean(axis=1)
    return reps / np.linalg.norm(reps, axis=1, keepdims=True)


def unit(v: np.ndarray) -> np.ndarray:
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def relax_points() -> np.ndarray:
    rng = np.random.default_rng(SEED)
    reps = unit(rng.normal(size=(N_ORBITS, 3)))

    # 1) Riesz repulsion to spread the orbits out.
    for it in range(600):
        pts = expand(reps)
        d = pts[:, None, :] - pts[None, :, :]
        r2 = (d ** 2).sum(-1) + np.eye(len(pts))
        force = (d / r2[..., None] ** 2).sum(1)  # ~1/r^3
        force -= (force * pts).sum(1, keepdims=True) * pts
        step = 0.0025 * (1.0 - it / 600) + 0.0003
        fmax = np.linalg.norm(force, axis=1).max()
        pts = unit(pts + step * force / fmax)
        reps = symmetrize(pts)

    # 2) Lloyd iterations: move every centre to its Voronoi-cell centroid.
    for _ in range(150):
        pts = expand(reps)
        sv = SphericalVoronoi(pts, radius=1.0, center=np.zeros(3))
        sv.sort_vertices_of_regions()
        cents = np.zeros_like(pts)
        for i, reg in enumerate(sv.regions):
            poly = sv.vertices[reg]
            a, b = poly, np.roll(poly, -1, axis=0)
            c = pts[i]
            areas = 0.5 * np.linalg.norm(np.cross(a - c, b - c), axis=1)
            cents[i] = ((a + b + c) / 3 * areas[:, None]).sum(0)
        reps = symmetrize(unit(cents))
    return expand(reps)


# --------------------------------------------------------------------------------------
# Topology
# --------------------------------------------------------------------------------------

def voronoi_cells(pts: np.ndarray):
    sv = SphericalVoronoi(pts, radius=1.0, center=np.zeros(3))
    sv.sort_vertices_of_regions()
    # Merge coincident corners (4-valent corners on the axes come out duplicated).
    canon: list[np.ndarray] = []
    remap = {}
    for i, v in enumerate(sv.vertices):
        for j, w in enumerate(canon):
            if np.linalg.norm(v - w) < 1e-6:
                remap[i] = j
                break
        else:
            remap[i] = len(canon)
            canon.append(v)
    corners = unit(np.array(canon))
    cells = []
    for i, reg in enumerate(sv.regions):
        loop = [remap[k] for k in reg]
        loop = [v for k, v in enumerate(loop) if v != loop[k - 1]]
        # orient CCW seen from outside (normal = dimple centre)
        poly = corners[loop]
        n = np.cross(poly[1] - poly[0], poly[2] - poly[0])
        if np.dot(n, pts[i]) < 0:
            loop = loop[::-1]
        cells.append(loop)
    return corners, cells


def build_mesh(pts: np.ndarray):
    corners, cells = voronoi_cells(pts)

    # --- land ridges (Voronoi edges) ------------------------------------------------
    ridges = {}
    for loop in cells:
        for a, b in zip(loop, loop[1:] + loop[:1]):
            key = (min(a, b), max(a, b))
            ridges.setdefault(key, math.acos(float(np.clip(corners[a] @ corners[b], -1, 1))))

    # Spend the triangle budget on the longest ridges (whole symmetry orbits at a
    # time): a midpoint vertex on the sphere keeps long ridges round and gives the
    # rim one more sample of the cup profile. Each midpoint adds two triangles.
    tris = sum(len(loop) for loop in cells)
    groups = {}
    for key, length in ridges.items():
        groups.setdefault(round(length, 7), []).append(key)
    split = set()
    for length in sorted(groups, reverse=True):
        if tris + 2 * len(groups[length]) > TARGET_TRIS:
            break
        split.update(groups[length])
        tris += 2 * len(groups[length])

    # --- vertex table: land corners, ridge midpoints, dimple centres ---------------
    pos = [c * RADIUS for c in corners]
    mid_idx = {}
    for key in sorted(split):
        mid_idx[key] = len(pos)
        pos.append(unit(corners[key[0]] + corners[key[1]]) * RADIUS)
    center_idx = []
    for c in pts:
        center_idx.append(len(pos))
        pos.append(c * (RADIUS - DEPTH))
    pos = np.array(pos)

    rims = []
    for loop in cells:
        rim = []
        for a, b in zip(loop, loop[1:] + loop[:1]):
            rim.append(a)
            key = (min(a, b), max(a, b))
            if key in mid_idx:
                rim.append(mid_idx[key])
        rims.append(rim)

    # --- normals --------------------------------------------------------------------
    # Spherical-cap normals tilt toward the dimple centre in proportion to the
    # distance from it; blending in a constant rim tilt makes hexagonal rims shade
    # like round cups. Centre normal = radial (cup bottom).
    rim_angles = [math.acos(float(np.clip(unit(pos[v]) @ pts[i], -1, 1)))
                  for i, rim in enumerate(rims) for v in rim]
    rim_mean = float(np.mean(rim_angles))

    def cup_normal(p, centre):
        p = unit(p)
        phi = math.acos(float(np.clip(p @ centre, -1, 1)))
        toward = unit(centre - p * (p @ centre))
        beta = math.radians(CUP_TILT_DEG) * (0.5 + 0.5 * phi / rim_mean)
        return unit(p * math.cos(beta) + toward * math.sin(beta))

    faces = []
    for i, rim in enumerate(rims):
        c = center_idx[i]
        for a, b in zip(rim, rim[1:] + rim[:1]):
            faces.append(((c, pts[i]), (a, cup_normal(pos[a], pts[i])), (b, cup_normal(pos[b], pts[i]))))
    return pos, faces, {"rim_mean_deg": math.degrees(rim_mean), "voronoi_corners": len(corners),
                        "ridges": len(ridges), "split_ridges": len(split)}


# --------------------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------------------

def validate(pos: np.ndarray, faces) -> dict:
    tri = np.array([[c[0] for c in f] for f in faces])
    a, b, c = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    cross = np.cross(b - a, c - a)
    area = 0.5 * np.linalg.norm(cross, axis=1)
    outward = np.einsum("ij,ij->i", cross, (a + b + c) / 3)
    assert (outward > 0).all(), "inconsistent winding"
    assert area.min() > 1e-5, f"degenerate triangle (area {area.min()})"
    elen = np.linalg.norm(np.concatenate([b - a, c - b, a - c]), axis=1)
    assert elen.min() > 1e-3, "near-zero edge"
    directed = {}
    for t in tri:
        for u, v in ((t[0], t[1]), (t[1], t[2]), (t[2], t[0])):
            assert (u, v) not in directed, "duplicate directed edge (non-manifold)"
            directed[(u, v)] = True
    for (u, v) in directed:
        assert (v, u) in directed, "open edge (not watertight)"
    used = np.unique(tri)
    assert len(used) == len(pos), "unused vertices"
    nv, nf = len(pos), len(tri)
    assert nv - len(directed) // 2 + nf == 2, "Euler characteristic != 2"
    r = np.linalg.norm(pos, axis=1)
    return {
        "vertices": nv,
        "triangles": nf,
        "bbox_min": pos.min(0),
        "bbox_max": pos.max(0),
        "r_min": r.min(),
        "r_max": r.max(),
        "min_area": area.min(),
        "min_edge": elen.min(),
    }


# --------------------------------------------------------------------------------------
# OBJ
# --------------------------------------------------------------------------------------

def sphere_uv(p: np.ndarray) -> tuple[float, float]:
    p = p / np.linalg.norm(p)
    u = 0.5 + math.atan2(p[0], p[2]) / (2 * math.pi)
    v = 0.5 + math.asin(float(np.clip(p[1], -1, 1))) / math.pi
    return u, v


def write_obj(path: str, pos: np.ndarray, faces, stats: dict) -> None:
    vt, vt_idx, vn, vn_idx = [], {}, [], {}

    def key_index(table, index, value):
        k = tuple(round(float(x), 6) for x in value)
        if k not in index:
            index[k] = len(table)
            table.append(k)
        return index[k] + 1

    lines_f = []
    for f in faces:
        uvs = [list(sphere_uv(pos[c[0]])) for c in f]
        pole = [abs(pos[c[0]][0]) < 1e-9 and abs(pos[c[0]][2]) < 1e-9 for c in f]
        # unwrap across the seam: keep every u within half a turn of the first
        # non-pole corner; a pole corner takes the mean u of the other two
        ref = next(uv[0] for uv, p in zip(uvs, pole) if not p)
        for uv, p in zip(uvs, pole):
            if not p:
                uv[0] += round(ref - uv[0])
        for k, p in enumerate(pole):
            if p:
                uvs[k][0] = sum(uvs[m][0] for m in range(3) if not pole[m]) / 2
        refs = []
        for c, uv in zip(f, uvs):
            ti = key_index(vt, vt_idx, uv)
            ni = key_index(vn, vn_idx, unit(np.asarray(c[1], dtype=float)))
            refs.append(f"{c[0] + 1}/{ti}/{ni}")
        lines_f.append("f " + " ".join(refs))

    with open(path, "w", newline="\n") as fh:
        fh.write("# Chaos Golf - dimpled golf ball (generated by tools/gen_ball.py)\n")
        fh.write(f"# {N_DIMPLES} dimples, depth {DEPTH} studs, radius {RADIUS} studs (diameter {2 * RADIUS})\n")
        fh.write(f"# vertices {stats['vertices']}  triangles {stats['triangles']}  Y-up, CCW = outward\n")
        fh.write("o GolfBall\n")
        for p in pos:
            fh.write(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n")
        for t in vt:
            fh.write(f"vt {t[0]:.6f} {t[1]:.6f}\n")
        for n in vn:
            fh.write(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n")
        fh.write("s off\n")
        fh.write("\n".join(lines_f) + "\n")


# --------------------------------------------------------------------------------------
# Preview: tiny software rasterizer (per-pixel normals, Lambert + spec + neon rim)
# --------------------------------------------------------------------------------------

def rot_matrix(yaw_deg: float, pitch_deg: float) -> np.ndarray:
    y, p = math.radians(yaw_deg), math.radians(pitch_deg)
    ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    rx = np.array([[1, 0, 0], [0, math.cos(p), -math.sin(p)], [0, math.sin(p), math.cos(p)]])
    return rx @ ry


def render_preview(path: str, pos: np.ndarray, faces, size: int = 512, ss: int = 3) -> None:
    W = size * ss
    rot = rot_matrix(28, 22)
    scale = W * 0.36 / RADIUS
    cx, cy = W / 2, W * 0.47
    zbuf = np.full((W, W), -np.inf, dtype=np.float32)
    nbuf = np.zeros((W, W, 3), dtype=np.float32)

    for f in faces:
        p3 = np.array([rot @ pos[c[0]] for c in f])
        n3 = np.array([rot @ unit(np.asarray(c[1], dtype=float)) for c in f])
        sx = cx + p3[:, 0] * scale
        sy = cy - p3[:, 1] * scale
        area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sx[2] - sx[0]) * (sy[1] - sy[0])
        if area >= 0:  # CCW in world -> CW in y-down screen space; back faces have area >= 0
            continue
        x0, x1 = int(max(0, math.floor(sx.min()))), int(min(W - 1, math.ceil(sx.max())))
        y0, y1 = int(max(0, math.floor(sy.min()))), int(min(W - 1, math.ceil(sy.max())))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((sx[1] - gx) * (sy[2] - gy) - (sx[2] - gx) * (sy[1] - gy)) / area
        w1 = ((sx[2] - gx) * (sy[0] - gy) - (sx[0] - gx) * (sy[2] - gy)) / area
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        z = w0 * p3[0, 2] + w1 * p3[1, 2] + w2 * p3[2, 2]
        sub_z = zbuf[y0:y1 + 1, x0:x1 + 1]
        upd = inside & (z > sub_z)
        sub_z[upd] = z[upd]
        n = w0[..., None] * n3[0] + w1[..., None] * n3[1] + w2[..., None] * n3[2]
        nbuf[y0:y1 + 1, x0:x1 + 1][upd] = n[upd]

    mask = np.isfinite(zbuf)
    n = nbuf / np.maximum(np.linalg.norm(nbuf, axis=-1, keepdims=True), 1e-6)
    view = np.array([0, 0, 1.0])

    # background: dark navy radial gradient + soft neon glow + contact shadow
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32) / W
    rr = np.sqrt((xx - 0.5) ** 2 + (yy - 0.45) ** 2)
    bg = np.empty((W, W, 3), np.float32)
    top, bottom = np.array([0.075, 0.085, 0.16]), np.array([0.03, 0.03, 0.07])
    bg[:] = top * (1 - yy[..., None]) + bottom * yy[..., None]
    glow = np.exp(-(rr / 0.30) ** 2)[..., None]
    bg += glow * np.array([0.10, 0.05, 0.22]) * 0.9
    sh = np.exp(-(((xx - 0.5) / 0.26) ** 2 + ((yy - 0.865) / 0.035) ** 2))[..., None]
    bg *= 1 - 0.65 * sh

    key = unit(np.array([-0.55, 0.65, 0.75]))
    fill = unit(np.array([0.7, -0.25, 0.55]))
    rim_c = unit(np.array([0.95, 0.15, -0.35]))   # cyan, back-right
    rim_m = unit(np.array([-0.95, -0.1, -0.35]))  # magenta, back-left
    base = np.array([0.95, 0.96, 0.99])

    ndl = np.clip((n @ key) * 0.85 + 0.15, 0, 1)            # slightly wrapped Lambert
    ndf = np.clip(n @ fill, 0, 1)
    hemi = 0.5 + 0.5 * n[..., 1]
    ambient = (np.array([0.20, 0.21, 0.30]) * (1 - hemi[..., None]) +
               np.array([0.30, 0.32, 0.40]) * hemi[..., None])
    col = base * (ambient + ndl[..., None] * np.array([1.0, 0.97, 0.92]) * 0.72 +
                  ndf[..., None] * np.array([0.35, 0.45, 0.75]) * 0.30)
    h = unit(key + view)
    spec = np.clip(n @ h, 0, 1) ** 60 * 0.5
    col += spec[..., None]
    fres = (1 - np.clip(n @ view, 0, 1)) ** 2.5
    # neon rim lights: direction from the mesh normal, falloff from the silhouette
    # (sphere) normal so the rim reads as a clean edge glow rather than per-dimple glints
    ys, xs = np.mgrid[0:W, 0:W].astype(np.float32)
    sxn = (xs + 0.5 - cx) / scale / RADIUS
    syn = -(ys + 0.5 - cy) / scale / RADIUS
    sz = np.sqrt(np.clip(1 - sxn ** 2 - syn ** 2, 0, 1))
    fres = 0.6 * fres + 0.4 * (1 - sz) ** 2.5
    col += (np.clip(n @ rim_c, 0, 1) * fres)[..., None] * np.array([0.0, 0.85, 1.0]) * 0.8
    col += (np.clip(n @ rim_m, 0, 1) * fres)[..., None] * np.array([1.0, 0.15, 0.65]) * 0.55

    img = np.where(mask[..., None], col, bg)
    img = np.clip(img, 0, 1) ** (1 / 1.1)
    out = Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGB")
    out = out.resize((size, size), Image.LANCZOS)
    out.save(path, optimize=True)


# --------------------------------------------------------------------------------------

def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    pts = relax_points()
    pos, faces, info = build_mesh(pts)
    stats = validate(pos, faces)
    if stats["triangles"] > HARD_MAX_TRIS:
        raise SystemExit(f"too many triangles: {stats['triangles']}")
    write_obj(OBJ_PATH, pos, faces, stats)
    render_preview(PREVIEW_PATH, pos, faces)

    # dimple evenness report
    sv = SphericalVoronoi(pts, radius=1.0, center=np.zeros(3))
    areas = sv.calculate_areas()
    nn = np.sort(np.arccos(np.clip(pts @ pts.T, -1, 1)), axis=1)[:, 1]
    bmin, bmax = stats["bbox_min"], stats["bbox_max"]
    print(f"golfball.obj   dimples {N_DIMPLES}  depth {DEPTH}  rim radius ~{info['rim_mean_deg']:.2f} deg")
    print(f"  vertices {stats['vertices']}   triangles {stats['triangles']}   "
          f"(land corners {info['voronoi_corners']}, ridges {info['ridges']}, "
          f"{info['split_ridges']} longest ridges with a midpoint)")
    print(f"  bbox min ({bmin[0]:.6f}, {bmin[1]:.6f}, {bmin[2]:.6f})  max ({bmax[0]:.6f}, {bmax[1]:.6f}, {bmax[2]:.6f})")
    print(f"  size {bmax[0] - bmin[0]:.6f} x {bmax[1] - bmin[1]:.6f} x {bmax[2] - bmin[2]:.6f}   "
          f"radius range {stats['r_min']:.4f}..{stats['r_max']:.6f}")
    print(f"  dimple cell area spread {areas.min() / areas.mean():.3f}..{areas.max() / areas.mean():.3f} of mean, "
          f"nearest-neighbour angle {math.degrees(nn.min()):.2f}..{math.degrees(nn.max()):.2f} deg")
    print(f"  watertight, consistently wound (CCW outward), min tri area {stats['min_area']:.2e}, "
          f"min edge {stats['min_edge']:.4f}")
    print(f"wrote {os.path.relpath(OBJ_PATH, ROOT)}, {os.path.relpath(PREVIEW_PATH, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
