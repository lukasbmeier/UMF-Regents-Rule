"""Copy the parts of Quaternius' character packs the game wears into the project.

    python tools/characters/import_quaternius_characters.py [--src=<Quaternius_Assets>] [--size=1024]

Packs (all CC0, https://quaternius.com):
  - Universal Base Characters: the heads (a clothed character needs only the head, per the
    outfit pack's readme: a full body under clothes clips and costs draw time) and the skin
    textures, plus the hairstyles "Rigged to Head Bone".
  - Modular Character Outfits - Fantasy: the Peasant, Ranger, Noble and Wizard outfits, as
    modular parts (arms, body, legs, feet, accessories), male and female.

Every file here is skinned to the same 65-bone Unreal-style skeleton as the animation libraries
(`game/anim/`), which is what lets `CharacterLook` put a head, an outfit and a haircut on ONE
skeleton and play the existing clips on it with no retargeting.

What this does to the files, and nothing else:
  - glTF + .bin are copied into game/characters/quaternius/models/, with every image URI
    rewritten to ../textures/<name>, because the packs keep their textures in folders of their
    own and a glTF only finds images relative to itself;
  - textures go to game/characters/quaternius/textures/, downscaled to --size (2048 in the
    packs; a character is a few hundred pixels tall on screen, and the full set at 2048 would add
    ~120 MB to the repository). Re-run with --size=2048 for the originals.

  - each model's import is set to generate NO LODs (`meshes/generate_lods=false`): the pieces are
    worn in layers a millimetre apart, and an LOD simplifies each piece on its own, so at a
    distance the hair sank into the scalp and the skin showed through it in spots. An existing
    .import keeps its other settings; a new one is written with only this, and Godot fills in
    the rest on import.

The Knight outfit is left out: 80 MB of textures for armour nobody fishes in. Add its parts to
OUTFIT_PARTS and its textures to OUTFIT_TEXTURES to bring it in.
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "game" / "characters" / "quaternius"
SRC = Path.home() / "Downloads" / "04_GameAssets" / "Quaternius_Assets"

HEADS = ["Regular_Male_OnlyHead", "Regular_Female_OnlyHead"]
OUTFITS = ["Peasant", "Ranger", "Noble", "Wizard"]
HAIR_MALE = ["Eyebrows_Regular", "Eyebrows_Thick", "Hair_Balding", "Hair_Beard", "Hair_Buzzed",
             "Hair_Moustache", "Hair_MuttonChops", "Hair_Ponytail"]
HAIR_FEMALE = ["Eyebrows_Female", "Hair_Bob", "Hair_Buns", "Hair_Long", "Hair_Ponytail_2"]
# Beyond what the glTFs reference: the light skin (the packs export the dark one) and each
# outfit's alternative colourways, which a look swaps in.
EXTRA_TEXTURES = [
    ("Character Models/Base Characters/Textures", "T_Regular_Male_Light_BaseColor.png"),
    ("Character Models/Base Characters/Textures", "T_Regular_Female_Light_BaseColor.png"),
    ("Character Outfits/Textures/Peasant", "T_Peasant_2_BaseColor.png"),
    ("Character Outfits/Textures/Peasant", "T_Peasant_3_BaseColor.png"),
    ("Character Outfits/Textures/Ranger", "T_Ranger_2_BaseColor.png"),
    ("Character Outfits/Textures/Noble", "T_Noble_2_BaseColor.png"),
    ("Character Outfits/Textures/Wizard", "T_Wizard_2_BaseColor.png"),
]
# Where each referenced image lives in the packs, searched in order.
TEXTURE_DIRS = [
    "Character Outfits/Textures/Base",
    "Character Outfits/Textures/Peasant",
    "Character Outfits/Textures/Ranger",
    "Character Outfits/Textures/Noble",
    "Character Outfits/Textures/Wizard",
    "Character Models/Base Characters/Textures",
    "Character Models/Hairstyles/Textures",
    "Character Models/Base Characters/Exports/Godot - UE",
]


def model_sources(src: Path) -> list:
    parts = src / "Character Outfits" / "Exports" / "glTF (Godot-Unreal)" / "Modular Parts"
    heads = src / "Character Models" / "Base Characters" / "Exports" / "Godot - UE"
    hair = src / "Character Models" / "Hairstyles" / "Rigged to Head Bone" / "glTF (Godot -Unreal)"
    out = [heads / (h + ".gltf") for h in HEADS]
    for gltf in sorted(parts.glob("*.gltf")):
        if any("_%s_" % o in gltf.name for o in OUTFITS):
            out.append(gltf)
    out += [hair / "Male" / (h + ".gltf") for h in HAIR_MALE]
    out += [hair / "Female" / (h + ".gltf") for h in HAIR_FEMALE]
    return out


def find_texture(src: Path, name: str) -> Path:
    for d in TEXTURE_DIRS:
        p = src / d / name
        if p.exists():
            return p
    raise FileNotFoundError(name)


def copy_texture(p: Path, size: int) -> None:
    out = DEST / "textures" / p.name
    im = Image.open(p)
    if max(im.size) > size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(out, optimize=True)


NO_LODS = "meshes/generate_lods=false"


def no_lods(model: Path) -> None:
    imp = model.with_name(model.name + ".import")
    if not imp.exists():
        text = '[remap]\n\nimporter="scene"\ntype="PackedScene"\n\n[params]\n\n%s\n' % NO_LODS
        imp.write_bytes(text.encode("utf-8"))
        return
    s = imp.read_bytes().decode("utf-8")
    if "meshes/generate_lods=" in s:
        s = s.replace("meshes/generate_lods=true", NO_LODS)
    else:
        s = s.replace("[params]\n\n", "[params]\n\n%s\n" % NO_LODS, 1)
    imp.write_bytes(s.encode("utf-8"))


def main() -> None:
    src = SRC
    size = 1024
    for a in sys.argv[1:]:
        if a.startswith("--src="):
            src = Path(a[6:])
        elif a.startswith("--size="):
            size = int(a[7:])
    (DEST / "models").mkdir(parents=True, exist_ok=True)
    (DEST / "textures").mkdir(parents=True, exist_ok=True)
    wanted: set = set()
    for gltf in model_sources(src):
        doc = json.loads(gltf.read_text(encoding="utf-8"))
        for im in doc.get("images", []):
            uri = im["uri"]
            wanted.add(uri)
            im["uri"] = "../textures/" + uri
        for buf in doc.get("buffers", []):
            shutil.copyfile(gltf.parent / buf["uri"], DEST / "models" / buf["uri"])
        (DEST / "models" / gltf.name).write_bytes(json.dumps(doc, indent=1).encode("utf-8"))
        no_lods(DEST / "models" / gltf.name)
        print("model", gltf.name)
    for name in sorted(wanted):
        copy_texture(find_texture(src, name), size)
        print("texture", name)
    for folder, name in EXTRA_TEXTURES:
        copy_texture(src / folder / name, size)
        print("texture", name)


if __name__ == "__main__":
    main()
