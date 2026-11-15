"""THE MEDIEVAL VILLAGE KIT, BROUGHT IN (2026-11-15, docs/regents_rule/SETTLEMENTS_PREP.md). Two jobs:

    python game/regents/tools/town_kit.py demo  "<the kit's L_SampleScene_1.tscn>"
        The kit's own demo buildings (its Godot sample scene: House C, Houses A, Houses D, the Tower) as scenes of their
        own in game/regents/town/houses/demo_*.tscn, each centered on its footprint, its foot at y 0, its pieces our
        imported ones (game/regents/art/village/). Quaternius built them by hand from the kit: they show what the kit
        can do and they are dressed by a Settlement like any house. House C2 is House C again and is left out.

    python game/regents/tools/town_kit.py means
        The mean linear brightness of each color texture in game/regents/art/village/ (what TownKit.SURFACES' "mean"
        holds, which the town dye scales from), and the wood trim sheet's band means (TownKit.TRIM_BANDS).

The kit is CC0 (Quaternius); the sample scene is in the kit's [Source] download under Engine Projects/Godot.
"""

import math
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
VILLAGE = "res://game/regents/art/village/"
HOUSES = os.path.join(ROOT, "game", "regents", "town", "houses")
GROUPS = {"House C": "demo_house_c", "Houses A": "demo_houses_a", "Houses D": "demo_house_d", "Tower": "demo_tower"}


def demo(sample):
    text = open(sample, encoding="utf-8").read()
    ext = {m.group(2): m.group(1).split("/")[-1][:-5] for m in re.finditer(r'path="([^"]+)" id="([^"]+)"', text)}
    pat = re.compile(r'\[node name="([^"]+)" parent="([^"]*)" instance=ExtResource\("([^"]+)"\)\]\s*\n(transform = Transform3D\(([^)]*)\))?')
    os.makedirs(HOUSES, exist_ok=True)
    for group, out in GROUPS.items():
        nodes = []
        for m in pat.finditer(text):
            if m.group(2) != group:
                continue
            xf = [float(x) for x in m.group(5).split(",")] if m.group(5) else [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
            nodes.append((m.group(1), ext[m.group(3)], xf))
        walls = [n for n in nodes if n[1].startswith(("Wall_", "Corner_"))] or nodes
        xs = [n[2][9] for n in walls]
        zs = [n[2][11] for n in walls]
        cx = (min(xs) + max(xs)) * 0.5
        cz = (min(zs) + max(zs)) * 0.5
        cx, cz = round(cx), round(cz)
        pieces = sorted({n[1] for n in nodes})
        ids = {p: f"{i + 1}_p" for i, p in enumerate(pieces)}
        title = out.replace("demo_", "Demo_").title().replace("_", "")
        lines = [f"[gd_scene load_steps={len(pieces) + 1} format=3]", ""]
        for p in pieces:
            lines.append(f'[ext_resource type="PackedScene" path="{VILLAGE}{p}.gltf" id="{ids[p]}"]')
        lines += ["", f'[node name="{title}" type="Node3D"]', ""]
        used = set()
        for name, p, xf in nodes:
            n = name
            k = 2
            while n in used:
                n = f"{name}_{k}"
                k += 1
            used.add(n)
            xf = list(xf)
            xf[9] = round(xf[9] - cx, 4)
            xf[11] = round(xf[11] - cz, 4)
            nums = ", ".join(f"{v:g}" for v in xf)
            lines.append(f'[node name="{n}" parent="." instance=ExtResource("{ids[p]}")]')
            lines.append(f"transform = Transform3D({nums})")
            lines.append("")
        path = os.path.join(HOUSES, out + ".tscn")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))
        print(f"{out}.tscn: {len(nodes)} pieces, footprint x {min(xs) - cx:.0f}..{max(xs) - cx:.0f} z {min(zs) - cz:.0f}..{max(zs) - cz:.0f}")


def means():
    import numpy as np
    from PIL import Image

    d = os.path.join(ROOT, "game", "regents", "art", "village")

    def luma(path):
        a = np.asarray(Image.open(path).convert("RGB").resize((256, 256)), dtype=np.float64) / 255.0
        a = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
        return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722

    for f in sorted(os.listdir(d)):
        if f.endswith("_BaseColor.png"):
            print(f"{f}: {luma(os.path.join(d, f)).mean():.4f}")
    t = luma(os.path.join(d, "T_WoodTrim_BaseColor.png"))
    h = t.shape[0]
    bands = [(0.0, 0.312), (0.312, 0.62), (0.62, 0.785), (0.785, 0.955)]
    print("wood trim bands:", ", ".join(f"{t[int(a * h) + 3:int(b * h) - 3].mean():.3f}" for a, b in bands))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "demo":
        demo(sys.argv[2])
    elif len(sys.argv) >= 2 and sys.argv[1] == "means":
        means()
    else:
        print(__doc__)
