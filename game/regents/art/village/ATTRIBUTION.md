# Medieval Village kit

Quaternius **Medieval Village MegaKit** [Source] (glTF), CC0 1.0 (public domain) by [@Quaternius](https://quaternius.com)
(`LICENSE_Quaternius_Medieval_Village.txt`). Human-made: nothing here needs Steam's AI disclosure. No attribution is
required.

Copied 2026-11-15 from Luke's download (`Downloads/01_Archive_Pairs/Medieval Village MegaKit[Source]/`):
- every piece from `glTF (Godot)/` (the Godot export: its `-convcolonly` nodes import as collisions), less the sample
  scene's ground;
- the color, normal and roughness textures from `glTF/`, and from `Textures/`: `T_WindowGradient`, `T_VineLeaf`,
  `T_Normal_Default`, and the wear masks and noise the town dye reads (`T_TopWear`, `T_MidWear`, `T_BottomWear`,
  `T_BrushedNoise`; these four scaled from 4096 to 1024 px, grayscale: they are soft masks).

The kit's demo buildings (its Godot sample scene, `Engine Projects/Godot`) are rebuilt from these pieces as
`game/regents/town/houses/demo_*.tscn` by `game/regents/tools/town_kit.py demo`.

The kit's own materials are not used: every surface is drawn by the town dye (`game/regents/town/`, code).
