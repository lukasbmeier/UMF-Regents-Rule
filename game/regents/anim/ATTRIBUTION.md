# Regent's Rule's own animation libraries

| File | Source | Clips | License |
|---|---|---|---|
| `regents_cuts.res` | cut from the Quaternius libraries (`game/anim/`) by `game/regents/tools/cut_clips.gd` | — | CC0 |
| `mixamo_great_sword.res` | Mixamo, *Great Sword Pack* | 51 | Mixamo (Adobe): royalty-free in a game |
| `mixamo_sword_shield.res` | Mixamo, *Pro Sword and Shield Pack* | 51 | Mixamo |
| `mixamo_magic.res` | Mixamo, *Pro Magic Pack* | 56 | Mixamo |
| `mixamo_locomotion.res` | Mixamo, *Locomotion Pack* | 12 | Mixamo |

## Mixamo (2026-11-18)
Human motion capture from [mixamo.com](https://www.mixamo.com), downloaded by Luke with his Adobe account as FBX
(the settings to use: `docs/regents_rule/ANIMATIONS.md` §1). Mixamo's animations may be used in a game royalty-free, but the RAW FILES may not be shared, so
they are never committed: only these retargeted libraries are, and the repository is private. The sources are in
Luke's `Downloads\04_GameAssets\Mixamo\` (the Locomotion Pack in `Downloads\04_GameAssets\Animations\`).

They are RETARGETED onto our Quaternius skeleton (both 65 bones, a T-pose, one bone for one) by
`game/regents/tools/retarget_mixamo.gd`, which also takes each clip's drift out (in place) and loops the idles, walks
and runs. To regenerate (or add a pack):

```bash
mkdir -p game/anim/_import/mixamo/<pack>                     # git-ignored; the folder name is the library's
cp "<pack folder>"/*.fbx game/anim/_import/mixamo/<pack>/
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script res://game/regents/tools/retarget_mixamo.gd [-- <pack> ...]
rm -r game/anim/_import/mixamo                               # never left in: an export would carry the raw files
```

A new library is named in `MotionClip.LIBRARIES` (`mx_<pack>`) and in `regents_motion`'s `MIXAMO`.
