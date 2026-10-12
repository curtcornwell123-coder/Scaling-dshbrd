"""Convert export_model.luau records (@N / @Q) into a Rojo .model.json.

Beam attachment references become Rojo_Id / Rojo_Target_* attributes, which Rojo
resolves into Ref properties at build time.
"""
import json
import sys


def floats(s):
    return [float(x) for x in s.split(",")]


def convert(kind, s):
    if kind == "V3":
        return {"Vector3": floats(s)}
    if kind == "V2":
        return {"Vector2": floats(s)}
    if kind == "C3":
        return {"Color3": floats(s)}
    if kind == "CF":
        pos, right, up, back = (floats(p) for p in s.split(";"))
        # Rows of the rotation matrix whose columns are Right, Up, Back.
        rows = [[right[i], up[i], back[i]] for i in range(3)]
        return {"CFrame": {"position": pos, "orientation": rows}}
    if kind == "EN":
        return s
    if kind == "B":
        return s == "true"
    if kind == "F":
        return float(s)
    if kind == "S":
        return s
    if kind == "NR":
        return {"NumberRange": floats(s)}
    if kind == "CS":
        kps = []
        for k in s.split(";"):
            t, c = k.split(":")
            kps.append({"time": float(t), "color": floats(c)})
        return {"ColorSequence": {"keypoints": kps}}
    if kind == "NS":
        kps = []
        for k in s.split(";"):
            t, v, e = k.split(":")
            kps.append({"time": float(t), "value": float(v), "envelope": float(e)})
        return {"NumberSequence": {"keypoints": kps}}
    raise ValueError(kind)


INT_PROPS = {"Segments"}


def main(records, name, out):
    nodes, order, refs = {}, [], []
    for line in open(records, encoding="utf-8"):
        f = line.rstrip("\n").split("|")
        if f[0] == "@N":
            nid, parent = int(f[1]), int(f[2])
            nodes[nid] = {"className": f[3], "name": f[4], "properties": {}, "children": [], "parent": parent}
            order.append(nid)
        elif f[0] == "@Q":
            nid, prop, kind, val = int(f[1]), f[2], f[3], "|".join(f[4:])
            if kind == "REF":
                refs.append((nid, prop, int(val)))
                continue
            v = convert(kind, val)
            if prop in INT_PROPS:
                v = {"Int32": int(round(v))}
            elif kind == "F":
                v = {"Float32": v}
            nodes[nid]["properties"][prop] = v
    for nid, prop, target in refs:
        nodes[target].setdefault("attributes", {})["Rojo_Id"] = f"ref{target}"
        nodes[nid].setdefault("attributes", {})[f"Rojo_Target_{prop}"] = f"ref{target}"
    root = None
    for nid in order:
        n = nodes[nid]
        parent = n.pop("parent")
        if parent == 0:
            root = n
        else:
            nodes[parent]["children"].append(n)
    root["name"] = name
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(root, fh)


if __name__ == "__main__":
    main(*sys.argv[1:4])
