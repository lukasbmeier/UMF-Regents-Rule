# Props

Quaternius **Fantasy Props MegaKit** (glTF), CC0 1.0 (public domain) by [@Quaternius](https://quaternius.com).
No attribution is required. `Axe_Bronze` is the Bronze axe woodcutting holds; its trim textures are the
pack's `Blends/T_Trim_Props_*` (the Godot/OpenGL normal map, not the Unreal one).
The order board (`Stall_Empty`, `Parchment`, `Scroll_1`) and the combat slice's `Dummy`, `Sword_Bronze`,
`Sword_Steel`, `Shield_Wooden` and `WeaponStand` come from the same pack (glTF exports; the cloth trim's
normal map is the pack's `Blends/` one, like the props').

## The rest of the kit (2026-11-15, the towns: `docs/regents_rule/SETTLEMENTS_PREP.md` §9)

Every other prop from the kit's Godot project (`Fantasy Props/Engine Projects/Godot/.../fantasypropsmegakit/Meshes/`,
its `-convcolonly` nodes import as collisions), 212 in all, and `T_Runes` from `Blends/`
(`LICENSE_Quaternius_Fantasy_Props.txt`: CC0 1.0). The ones above were already here and are kept as they were (no
collisions: the order board and the combat dummies must not change). The towns draw them all with the town dye
(`game/regents/town/`), the props' vertex colors kept.
