# Characters: Quaternius packs (CC0)

Models and textures by **Quaternius** (https://quaternius.com), released under
**CC0 1.0 Universal** (public domain). Attribution is not required; it is given anyway.

| Pack | Used for |
|---|---|
| Universal Base Characters | the heads (`Regular_*_OnlyHead`), the skin textures (light and dark), the hairstyles and eyebrows "Rigged to Head Bone" |
| Modular Character Outfits – Fantasy (Source) | the Peasant, Ranger, Noble and Wizard outfits as modular parts, male and female, with their colourways |

## How they got here

`tools/characters/import_quaternius_characters.py` copies what the game wears out of the
extracted packs (default `~/Downloads/04_GameAssets/Quaternius_Assets/`):

- `models/` — glTF + .bin, image URIs rewritten to `../textures/`, because the packs keep
  textures in folders of their own and a glTF finds images only relative to itself;
- `textures/` — downscaled to 1024 px (the packs ship 2048). Re-run with `--size=2048` for
  the originals. The Knight outfit is left out; the script's header says how to add it.

`tools/characters/make_looks.py` writes `game/characters/looks/*.tscn` — each look a
`ModularCharacter` (head, pieces, colours) — from the table at its top. Edit the table and re-run;
edits made to a look in the editor are overwritten.

Every piece is skinned to the same 65-bone skeleton as the animation libraries in `game/anim/`
(see its ATTRIBUTION.md), which is why the clips play on these characters with no retargeting.
