#!/usr/bin/env python3
"""Ultimate Golf - premium dimpled golf-ball mesh generator (v2).

Writes
  assets/mesh/golfball.obj          the mesh (Y-up, units = studs, CCW outward faces)
  assets/mesh/golfball_preview.png  512x512 software-rendered preview

Construction
  * 252 dimples on an icosahedral geodesic layout (frequency 5: 12 five-neighbour and
    240 six-neighbour dimples), the even spacing real tour balls use.
  * Every dimple is ROUND: a spherical-cup profile (depth = DEPTH * (1 - (rho/rho_d)^2))
    sampled on two rings of SEGMENTS points, then a flat land band out to the dimple's
    spherical-Voronoi cell edge. Land is exactly on the sphere, so neighbouring dimples
    are separated by narrow ridges and small triangular land patches at the cell corners,
    like a real ball.
  * Cell edges are subdivided once and shared between neighbours -> watertight.
  * Normals are analytic: the cup's true surface normal inside the dimple, radial on the
    land, split at the rim so each dimple has a crisp edge that catches the light.
  * UVs: cube projection per dimple cell (no pole pinching), so part materials (Foil,
    Glass, ...) read evenly over the whole ball.

Requires: numpy, scipy, Pillow.   Run:  python3 tools/gen_ball.py
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image
from scipy.spatial import SphericalVoronoi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "mesh")
OBJ_PATH = os.path.join(OUT_DIR, "golfball.obj")
PREVIEW_PATH = os.path.join(OUT_DIR, "golfball_preview.png")

RADIUS = 0.75        # studs -> diameter 1.5 == Config.Ball.Diameter
FREQ = 5             # geodesic frequency: 10 * FREQ^2 + 2 dimples (252)
DIMPLE_FILL = 0.86   # dimple radius as a share of the cell's inradius (rest = land)
DEPTH = 0.024        # dimple depth at its centre (studs)
INNER_RING = 0.58    # middle ring of the cup, as a share of the dimple radius
MAX_TRIS = 20000     # Roblox mesh import limit


def icosahedron():
    p = (1 + 5 ** 0.5) / 2
    v = np.array([
        (-1, p, 0), (1, p, 0), (-1, -p, 0), (1, -p, 0),
        (0, -1, p), (0, 1, p), (0, -1, -p), (0, 1, -p),
        (p, 0, -1), (p, 0, 1), (-p, 0, -1), (-p, 0, 1),
    ], dtype=float)
    f = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1),
    ]
    return v / np.linalg.norm(v, axis=1, keepdims=True), f


def geodesic_points(freq):
    verts, faces = icosahedron()
    pts = {}
    for a, b, c in faces:
        A, B, C = verts[a], verts[b], verts[c]
        for i in range(freq + 1):
            for j in range(freq + 1 - i):
                k = freq - i - j
                p = (A * i + B * j + C * k) / freq
                p /= np.linalg.norm(p)
                pts[tuple(np.round(p, 9))] = p
    out = np.array(list(pts.values()))
    assert len(out) == 10 * freq * freq + 2, len(out)
    return out


def slerp_dir(c, t, rho):
    return c * math.cos(rho) + t * math.sin(rho)


def build():
    centres = geodesic_points(FREQ)
    sv = SphericalVoronoi(centres, radius=1.0)
    sv.sort_vertices_of_regions()

    positions: list[np.ndarray] = []
    pos_index: dict[tuple, int] = {}

    def vid(p):
        key = tuple(np.round(p, 9))
        i = pos_index.get(key)
        if i is None:
            i = len(positions)
            pos_index[key] = i
            positions.append(p)
        return i

    normals: list[np.ndarray] = []

    def nid(n):
        normals.append(n / np.linalg.norm(n))
        return len(normals)  # OBJ indices are 1-based

    uvs: list[tuple] = []

    def uvid(p, axis):
        a, b = [(1, 2), (0, 2), (0, 1)][axis]
        uvs.append((0.5 + p[a] / (2 * RADIUS), 0.5 + p[b] / (2 * RADIUS)))
        return len(uvs)

    faces = []  # each face: [(v, vt, vn) * 3], 1-based
    min_land = math.inf
    depth_profile = lambda u: DEPTH * (1 - u * u)

    for ci, region in enumerate(sv.regions):
        c = centres[ci]
        corners = [sv.vertices[k] for k in region]
        m = len(corners)
        # Make the corner order CCW seen from outside (right-handed about c).
        if np.dot(np.cross(corners[0] - c, corners[1] - c), c) < 0:
            corners = corners[::-1]
        boundary = []
        for k in range(m):
            a, b = corners[k], corners[(k + 1) % m]
            mid = a + b
            boundary.append(a / np.linalg.norm(a))
            boundary.append(mid / np.linalg.norm(mid))
        S = len(boundary)
        # Inradius: angular distance from the centre to the nearest cell edge (great circle).
        inr = math.inf
        for k in range(m):
            a, b = corners[k], corners[(k + 1) % m]
            nrm = np.cross(a, b)
            nrm /= np.linalg.norm(nrm)
            inr = min(inr, abs(math.asin(np.clip(np.dot(c, nrm), -1, 1))))
        rho_d = DIMPLE_FILL * inr
        min_land = min(min_land, (inr - rho_d) * RADIUS)
        axis = int(np.argmax(np.abs(c)))

        def cup_vertex(t, rho):
            u = rho / rho_d
            d = slerp_dir(c, t, rho)
            r = RADIUS - depth_profile(u)
            # Analytic normal of r(rho): radial minus (dr/drho / r) along the outward tangent.
            drdrho = 2 * DEPTH * rho / (rho_d * rho_d)
            tang = -c * math.sin(rho) + t * math.cos(rho)  # d(dir)/d(rho)
            n = d - (drdrho / r) * tang
            return d * r, n

        tangents = []
        for bp in boundary:
            t = bp - np.dot(bp, c) * c
            tangents.append(t / np.linalg.norm(t))

        centre_v = vid(c * (RADIUS - DEPTH))
        centre_n = nid(c)
        centre_uv = uvid(c * RADIUS, axis)
        ring1, ring2, rim_land, edge = [], [], [], []
        for j in range(S):
            t = tangents[j]
            p1, n1 = cup_vertex(t, INNER_RING * rho_d)
            p2, n2 = cup_vertex(t, rho_d)
            ring1.append((vid(p1), uvid(p1, axis), nid(n1)))
            ring2.append((vid(p2), uvid(p2, axis), nid(n2)))
            rim_land.append((ring2[-1][0], ring2[-1][1], nid(p2)))  # same point, land normal
            bp = boundary[j] * RADIUS
            edge.append((vid(bp), uvid(bp, axis), nid(bp)))
        for j in range(S):
            k = (j + 1) % S
            faces.append([(centre_v, centre_uv, centre_n), ring1[j], ring1[k]])
            faces.append([ring1[j], ring2[j], ring2[k]])
            faces.append([ring1[j], ring2[k], ring1[k]])
            faces.append([rim_land[j], edge[j], edge[k]])
            faces.append([rim_land[j], edge[k], rim_land[k]])

    P = np.array(positions)
    return P, normals, uvs, faces, len(centres), min_land


def write_obj(P, normals, uvs, faces, n_dimples):
    with open(OBJ_PATH, "w") as f:
        f.write(f"# Ultimate Golf ball: {n_dimples} round dimples, {len(P)} vertices, {len(faces)} triangles\n")
        f.write("o GolfBall\n")
        for p in P:
            f.write(f"v {p[0]:.6f} {p[1]:.6f} {p[2]:.6f}\n")
        for u in uvs:
            f.write(f"vt {u[0]:.6f} {u[1]:.6f}\n")
        for n in normals:
            f.write(f"vn {n[0]:.6f} {n[1]:.6f} {n[2]:.6f}\n")
        f.write("s 1\n")
        for face in faces:
            f.write("f " + " ".join(f"{v + 1}/{t}/{n}" for v, t, n in face) + "\n")


def check(P, faces):
    # Watertight: every undirected edge is used exactly twice, once in each direction.
    seen = {}
    for face in faces:
        idx = [v for v, _, _ in face]
        for a, b in ((idx[0], idx[1]), (idx[1], idx[2]), (idx[2], idx[0])):
            seen[(a, b)] = seen.get((a, b), 0) + 1
    bad = [e for e, n in seen.items() if n != 1 or seen.get((e[1], e[0])) != 1]
    assert not bad, f"{len(bad)} non-manifold edges"
    # Outward winding.
    for face in faces[:: max(1, len(faces) // 500)]:
        a, b, c = (P[v] for v, _, _ in face)
        assert np.dot(np.cross(b - a, c - a), a + b + c) > 0, "inward face"
    assert len(faces) <= MAX_TRIS, len(faces)


def preview(P, normals, faces):
    size = 512
    img = np.zeros((size, size, 3), dtype=np.float32)
    yy, xx = np.mgrid[0:size, 0:size]
    bg = np.stack([0.06 + 0.04 * (1 - yy / size), 0.07 + 0.04 * (1 - yy / size), 0.10 + 0.06 * (1 - yy / size)], -1)
    img[:] = bg
    zbuf = np.full((size, size), -np.inf)
    N = np.array(normals)
    # View: tilt the ball so a pentagonal dimple sits off-centre.
    ang_x, ang_y = math.radians(-24), math.radians(30)
    Rx = np.array([[1, 0, 0], [0, math.cos(ang_x), -math.sin(ang_x)], [0, math.sin(ang_x), math.cos(ang_x)]])
    Ry = np.array([[math.cos(ang_y), 0, math.sin(ang_y)], [0, 1, 0], [-math.sin(ang_y), 0, math.cos(ang_y)]])
    R = Rx @ Ry
    V = P @ R.T
    NN = N @ R.T
    scale = size * 0.42 / RADIUS
    sx = size / 2 + V[:, 0] * scale
    sy = size / 2 - V[:, 1] * scale
    light = np.array([-0.45, 0.6, 0.66]); light /= np.linalg.norm(light)
    rim_l = np.array([0.7, -0.1, -0.2]); rim_l /= np.linalg.norm(rim_l)
    half = light + np.array([0, 0, 1.0]); half /= np.linalg.norm(half)
    base = np.array([0.93, 0.94, 0.96])
    for face in faces:
        vi = [v for v, _, _ in face]
        ni = [n - 1 for _, _, n in face]
        if V[vi, 2].mean() < -0.05:
            continue
        x = sx[vi]; y = sy[vi]
        x0, x1 = int(max(0, math.floor(x.min()))), int(min(size - 1, math.ceil(x.max())))
        y0, y1 = int(max(0, math.floor(y.min()))), int(min(size - 1, math.ceil(y.max())))
        if x1 < x0 or y1 < y0:
            continue
        den = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((y[1] - y[2]) * (gx - x[2]) + (x[2] - x[1]) * (gy - y[2])) / den
        w1 = ((y[2] - y[0]) * (gx - x[2]) + (x[0] - x[2]) * (gy - y[2])) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -1e-4) & (w1 >= -1e-4) & (w2 >= -1e-4)
        if not inside.any():
            continue
        z = w0 * V[vi[0], 2] + w1 * V[vi[1], 2] + w2 * V[vi[2], 2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        mask = inside & (z > sub)
        if not mask.any():
            continue
        n = (w0[..., None] * NN[ni[0]] + w1[..., None] * NN[ni[1]] + w2[..., None] * NN[ni[2]])
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        diff = np.clip(n @ light, 0, 1)
        spec = np.clip(n @ half, 0, 1) ** 60
        rim = np.clip(n @ rim_l, 0, 1) * 0.25
        col = base * (0.22 + 0.78 * diff[..., None]) + spec[..., None] * 0.55 + rim[..., None] * np.array([0.55, 0.75, 1.0])
        sub[mask] = z[mask]
        img[y0:y1 + 1, x0:x1 + 1][mask] = col[mask]
    img = np.clip(img, 0, 1) ** (1 / 1.15)
    Image.fromarray((img * 255).astype(np.uint8)).save(PREVIEW_PATH)


def main():
    P, normals, uvs, faces, n_dimples, min_land = build()
    check(P, faces)
    write_obj(P, normals, uvs, faces, n_dimples)
    preview(P, normals, faces)
    ext = P.max(axis=0) - P.min(axis=0)
    print(f"{n_dimples} dimples, {len(P)} vertices, {len(faces)} triangles, bbox {ext.round(4)}, narrowest land {min_land:.4f} studs")


if __name__ == "__main__":
    main()
