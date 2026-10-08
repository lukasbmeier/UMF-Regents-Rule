"""Write the fishing game's character looks: game/characters/looks/<name>.tscn.

    python tools/characters/make_looks.py

Each look is a `ModularCharacter` (game/characters/modular_character.gd): a head, the pieces it
wears, and its colours. The table below IS the design; this script only spells it as scenes, so
a look is changed here and regenerated rather than edited in the editor (an edit there is
overwritten the next time this runs).

`PLAYER_LOOKS` is what anglers wear, in order: `EntityDefinition.visual_variants` hands entity
N the (N mod count)th, so consecutive players never match. `RIVAL` is the rival angler's own.
Needs the models imported first (tools/characters/import_quaternius_characters.py).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "characters" / "looks"
MODELS = "res://game/characters/quaternius/models/"
TEXTURES = "res://game/characters/quaternius/textures/"
SCRIPT = "res://game/characters/modular_character.gd"

HEAD = {"m": "Regular_Male_OnlyHead", "f": "Regular_Female_OnlyHead"}
SKIN = {("m", "light"): "T_Regular_Male_Light_BaseColor", ("m", "dark"): "T_Regular_Male_Dark_BaseColor",
        ("f", "light"): "T_Regular_Female_Light_BaseColor", ("f", "dark"): "T_Regular_Female_Dark_BaseColor"}


def outfit(sex: str, name: str, pieces: list) -> list:
    who = "Male" if sex == "m" else "Female"
    return ["%s_%s_%s" % (who, name, p) for p in pieces]


# name: sex, pieces worn, skin (texture, tint), hair colour, outfit colourway (None = the first)
LOOKS = {
    "peasant_m": ("m", outfit("m", "Peasant", ["Arms", "Body", "Legs", "Feet"])
                  + ["Eyebrows_Regular", "Hair_Buzzed", "Hair_Beard"],
                  ("light", (1.0, 0.93, 0.86)), (0.30, 0.19, 0.10), None),
    "peasant_f": ("f", outfit("f", "Peasant", ["Arms", "Body", "Legs", "Feet"])
                  + ["Eyebrows_Female", "Hair_Buns"],
                  ("light", (0.95, 0.83, 0.74)), (0.46, 0.20, 0.08), "T_Peasant_2_BaseColor"),
    "ranger_m": ("m", outfit("m", "Ranger", ["Arms", "Body", "Legs", "Feet_Boots", "Acc_Pauldron"])
                 + ["Eyebrows_Thick", "Hair_Ponytail", "Hair_Moustache"],
                 ("dark", (1.0, 1.0, 1.0)), (0.06, 0.05, 0.05), None),
    "ranger_f": ("f", outfit("f", "Ranger", ["Arms", "Body", "Legs", "Feet", "Acc_Pauldrons", "Head_Hood"])
                 + ["Eyebrows_Female"],
                 ("light", (1.0, 0.95, 0.9)), (0.55, 0.38, 0.20), "T_Ranger_2_BaseColor"),
    "noble_m": ("m", outfit("m", "Noble", ["Arms", "Body", "Legs", "Feet", "Acc_Gorget"])
                + ["Eyebrows_Regular", "Hair_Buzzed", "Hair_MuttonChops"],
                ("light", (0.86, 0.70, 0.57)), (0.74, 0.60, 0.34), "T_Noble_2_BaseColor"),
    "noble_f": ("f", outfit("f", "Noble", ["Arms", "Body", "Legs", "Feet", "Acc_Gorget"])
                + ["Eyebrows_Female", "Hair_Long"],
                ("dark", (1.0, 1.0, 1.0)), (0.09, 0.06, 0.05), None),
    "wizard_m": ("m", outfit("m", "Wizard", ["Arms", "Body", "Legs", "Feet"])
                 + ["Eyebrows_Thick", "Hair_Balding", "Hair_Beard"],
                 ("light", (1.0, 0.9, 0.82)), (0.70, 0.70, 0.72), None),
    "wizard_f": ("f", outfit("f", "Wizard", ["Arms", "Body", "Legs", "Feet"])
                 + ["Eyebrows_Female", "Hair_Ponytail_2"],
                 ("dark", (0.92, 0.9, 0.9)), (0.86, 0.86, 0.9), "T_Wizard_2_BaseColor"),
}
PLAYER_LOOKS = ["peasant_m", "ranger_f", "wizard_m", "noble_f", "ranger_m", "peasant_f", "noble_m",
                "wizard_f"]
RIVAL = ("rival", ("m", outfit("m", "Noble", ["Arms", "Body", "Legs", "Feet", "Acc_Pauldron_Lion", "Head_Crown"])
                   + ["Eyebrows_Thick", "Hair_Moustache", "Hair_MuttonChops"],
                   ("light", (1.0, 0.88, 0.8)), (0.20, 0.12, 0.06), None))


def color(c: tuple) -> str:
    return "Color(%s, %s, %s, 1)" % tuple(round(v, 3) for v in c)


def scene(name: str, look: tuple) -> str:
    sex, pieces, (skin, tint), hair, colourway = look
    ext = [("Script", SCRIPT), ("PackedScene", MODELS + HEAD[sex] + ".gltf")]
    ext += [("PackedScene", MODELS + p + ".gltf") for p in pieces]
    ext.append(("Texture2D", TEXTURES + SKIN[(sex, skin)] + ".png"))
    if colourway:
        ext.append(("Texture2D", TEXTURES + colourway + ".png"))
    lines = ["[gd_scene load_steps=%d format=3]" % (len(ext) + 1), ""]
    for i, (kind, path) in enumerate(ext, 1):
        lines.append('[ext_resource type="%s" path="%s" id="%d"]' % (kind, path, i))
    parts = ", ".join('ExtResource("%d")' % i for i in range(3, 3 + len(pieces)))
    lines += ["", '[node name="%s" type="Node3D"]' % name.title().replace("_", ""),
              'script = ExtResource("1")',
              'head = ExtResource("2")',
              'body = &"%s"' % {"m": "male", "f": "female"}[sex],
              "parts = Array[PackedScene]([%s])" % parts,
              'skin_texture = ExtResource("%d")' % (3 + len(pieces)),
              "skin_tint = %s" % color(tint),
              "hair_color = %s" % color(hair)]
    if colourway:
        lines.append('outfit_texture = ExtResource("%d")' % (4 + len(pieces)))
    return "\n".join(lines) + "\n"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    models = ROOT / "game" / "characters" / "quaternius" / "models"
    for name, look in list(LOOKS.items()) + [RIVAL]:
        for p in [HEAD[look[0]]] + look[1]:
            assert (models / (p + ".gltf")).exists(), "%s wears %s, which is not imported" % (name, p)
        (OUT / (name + ".tscn")).write_bytes(scene(name, look).encode("utf-8"))
        print("look", name)
    print("player order:", ", ".join(PLAYER_LOOKS))


if __name__ == "__main__":
    main()
