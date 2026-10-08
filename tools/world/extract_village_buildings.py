"""Split the Medieval Village MegaKit's sample scene into one scene per building.

    python tools/world/extract_village_buildings.py

The kit ships its buildings only as groups inside `L_SampleScene_1.tscn`, each group a Node3D
full of wall, floor and roof pieces. A group's own transform places it in the sample; its
CHILDREN are in the building's frame, with the ground floor at y = 0. So a building is exactly
a group's children, re-parented to a new root with an identity transform, and nothing else
needs changing — no sub-resources are involved, only ext_resource instances.

Text-level on purpose: packing through the engine would expand every instanced piece into its
meshes and bodies and write a file forty times the size. This keeps each piece an instance of
the kit's own glTF, so a fix to a piece (or its material) reaches every building.

Deterministic: same input, same bytes. `House C2` is the same building as `House C` placed a
second time, so it is not written out; `lakeside` places `house_c` twice.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAMPLE = ROOT / "game/world/kits/village/medievalvillagemegakit/L_SampleScene_1.tscn"
OUT = ROOT / "game/world/buildings"
GROUPS = {"House C": "house_c", "Tower": "tower", "Houses A": "houses_a", "Houses D": "houses_d"}

text = SAMPLE.read_text(encoding="utf-8")
ext = {}
for m in re.finditer(r'^\[ext_resource ([^\]]*)\]$', text, re.M):
    attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
    ext[attrs["id"]] = attrs

blocks = re.split(r'\n(?=\[)', text)
nodes = {name: [] for name in GROUPS}
for b in blocks:
    m = re.match(r'\[node name="([^"]+)" parent="([^"]+)"', b)
    if m and m.group(2) in GROUPS:
        nodes[m.group(2)].append(b.strip("\n"))

OUT.mkdir(parents=True, exist_ok=True)
for group, stem in GROUPS.items():
    body = nodes[group]
    if not body:
        raise SystemExit(f"no pieces under '{group}' — has the sample scene changed?")
    used = []
    for b in body:
        rid = re.search(r'instance=ExtResource\("([^"]+)"\)', b).group(1)
        if rid not in used:
            used.append(rid)
    lines = [f"[gd_scene load_steps={len(used) + 1} format=3]", ""]
    for rid in used:
        a = ext[rid]
        uid = f' uid="{a["uid"]}"' if "uid" in a else ""
        lines.append(f'[ext_resource type="{a["type"]}"{uid} path="{a["path"]}" id="{rid}"]')
    root = "".join(w.capitalize() for w in stem.split("_"))
    lines += ["", f'[node name="{root}" type="Node3D"]', ""]
    for b in body:
        lines.append(b.replace(f'parent="{group}"', 'parent="."', 1))
        lines.append("")
    out = OUT / f"{stem}.tscn"
    out.write_bytes(("\n".join(lines).rstrip("\n") + "\n").encode("utf-8"))
    print(f"{stem}: {len(body)} pieces, {len(used)} distinct -> {out.relative_to(ROOT)}")
