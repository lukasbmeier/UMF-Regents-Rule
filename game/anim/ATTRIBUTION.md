# Animation assets

## Where they came from

| File | Source | Clips |
|---|---|---|
| `humanoid_core.res` | Quaternius **Universal Animation Library**, `Unreal Engine/AL.fbx` | 127 |
| `humanoid_extra.res` | Quaternius **Universal Animation Library 2**, `Unreal-Godot/UAL2.glb` | 135 |
| `../characters/mannequin_f.glb` | Quaternius **Universal Animation Library 2**, `Female Mannequin/Unreal-Godot/Mannequin_F.glb` | — |

All three are **CC0 1.0** (public domain dedication) by [@Quaternius](https://quaternius.com).
No attribution is required; this file is here because a template should say where its content
came from, and because regenerating these artifacts needs the source packs:

- https://quaternius.com/packs/universalanimationlibrary.html
- https://quaternius.com/packs/universalanimationlibrary2.html
- https://quaternius.com/packs/universalbasecharacters.html

## One skeleton, no retargeting

Both libraries and every character in the Universal Base Characters pack are rigged to the same
**65-bone Unreal-style skeleton** (`root`, `pelvis`, `spine_01`, `clavicle_l`, …). Bone names and
rest poses match, so a clip from either library plays on any of those characters directly — none
of the `SkeletonProfileHumanoid` retargeting `docs/ANIMATION_SPEC.md` §1 allows for is needed
here. A rig from somewhere else would need it.

The **base characters are not committed**: one of them plus its textures is ~18 MB, and the
mannequin above is the model those animations were authored on. Dropping in a real character is
one field: `EntityDefinition.visual_scene`, plus `visual_yaw_deg` if the new rig faces the other
way (these Quaternius rigs face +Z, so the fisher's definition carries 180).

## Why `.res` and not the source files

The sources are 68 MB (FBX) and 20 MB (GLB) because each carries a mannequin mesh and its
textures. The animation data alone is 3.7 MB per library, so only that is committed — the same
bargain as the vendored SDK: a fresh clone works offline, and the tool that produced the
artifact sits next to it.

## Regenerating

```bash
mkdir -p game/anim/_import
cp "<pack>/Unreal Engine/AL.fbx"          game/anim/_import/humanoid_core.fbx
cp "<pack>/Unreal-Godot/UAL2.glb"         game/anim/_import/humanoid_extra.glb
godot --headless --path . --import
godot --headless --path . --script res://tools/extract_animation_library.gd
rm -r game/anim/_import
godot --headless --path . --script res://tools/animation_set_builder.gd
```

The extractor renames FBX takes (`Rig|Jump_Start` → `Jump_Start`), re-addresses every bone
track onto `Skeleton3D:<bone>` so a library does not depend on the node names of the file it came
out of, and composes what those nodes CONTRIBUTED into the tracks: the FBX source carries a -90°
X rotation and a ×100 scale (Z-up, centimetres) on the node above the skeleton, and dropping
either one gives a character that animates perfectly while lying on its back or standing 100×
too small (DECISIONS #99). The set builder then fuzzy-matches clip names onto the semantic names the game
uses and prints what it matched — read that report; it is the point of generating the set
rather than writing it.

Last run:

```
library '': 127 clips        library 'extra': 135 clips
locomotion.idle        Idle
locomotion.walk        Walk
locomotion.run         Sprint
jump.start             Jump_Start   (x4.17 to fit the jump)
jump.loop              Jump
jump.land              Jump_Land   (x2.64 to fit the jump)
jump.land_heavy        MISSING -> falls back to [jump.land]
react.hit              Hit_Chest
react.death            Death01
react.revive           extra/KipUp
interact               Interact          (fisher: extra/Fish_Cast)
ability.0              —                 (fisher: extra/Melee_Hook)
```
