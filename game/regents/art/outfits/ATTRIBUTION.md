# Outfits: Quaternius, Modular Character Outfits - Fantasy (CC0)

`knight/` holds the pack's Knight outfit (male and female: armor body, cloth body, arms, legs, feet, the armet
and horned helms, round and spiked pauldrons, the scarf) by **Quaternius** (https://quaternius.com), released
under **CC0 1.0 Universal**. Attribution is not required; it is given anyway.

The other four outfits (Peasant, Ranger, Noble, Wizard) are the foundation's, in `game/characters/quaternius/`.
The Knight is the genre's, brought in by `python game/regents/tools/wardrobe_assets.py knight` from the extracted
pack (textures downscaled to 1024 px; image URIs rewritten to `../textures/`; no LODs).

The dye zones (`game/regents/wardrobe/zones/`) are made from these textures by the same script (`zones`): the
pack's own pixels sorted and averaged, nothing generated.
