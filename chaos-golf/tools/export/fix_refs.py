"""Turn Rojo_Id / Rojo_Target_<Prop> string attributes in an .rbxmx into real Ref
properties (Rojo 7.4 keeps them as plain attributes when building), and drop the
helper attributes. Usage: fix_refs.py in.rbxmx out.rbxmx
"""
import base64
import struct
import sys
import xml.etree.ElementTree as ET


def read_attrs(blob):
    data = base64.b64decode(blob)
    (count,) = struct.unpack_from("<I", data, 0)
    off = 4
    out = {}
    for _ in range(count):
        (n,) = struct.unpack_from("<I", data, off)
        off += 4
        name = data[off:off + n].decode()
        off += n
        kind = data[off]
        off += 1
        if kind != 0x02:
            raise ValueError(f"unsupported attribute type {kind} for {name}")
        (n,) = struct.unpack_from("<I", data, off)
        off += 4
        out[name] = data[off:off + n].decode()
        off += n
    return out


def write_attrs(attrs):
    parts = [struct.pack("<I", len(attrs))]
    for k, v in attrs.items():
        kb, vb = k.encode(), v.encode()
        parts.append(struct.pack("<I", len(kb)) + kb + b"\x02" + struct.pack("<I", len(vb)) + vb)
    return base64.b64encode(b"".join(parts)).decode()


def main(src, dst):
    tree = ET.parse(src)
    items = list(tree.iter("Item"))
    ids, targets = {}, []
    for item in items:
        props = item.find("Properties")
        blob = props.find("BinaryString[@name='AttributesSerialize']") if props is not None else None
        if blob is None or not (blob.text or "").strip():
            continue
        attrs = read_attrs(blob.text.strip())
        if "Rojo_Id" in attrs:
            ids[attrs.pop("Rojo_Id")] = item.get("referent")
        for k in [k for k in attrs if k.startswith("Rojo_Target_")]:
            targets.append((props, k[len("Rojo_Target_"):], attrs.pop(k)))
        if attrs:
            blob.text = write_attrs(attrs)
        else:
            props.remove(blob)
    missing = 0
    for props, prop, rid in targets:
        ref = ids.get(rid)
        if ref is None:
            missing += 1
            continue
        el = ET.SubElement(props, "Ref", {"name": prop})
        el.text = ref
    tree.write(dst, encoding="utf-8", xml_declaration=False)
    print(f"refs: {len(targets) - missing} linked, {missing} missing")
    if missing:
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
