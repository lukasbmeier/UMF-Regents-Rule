# Settlements prep (2026-11-15): villages, towns, a capital, a castle

Before any town art goes into the world. Luke asked: explore the Medieval Village and Fantasy Props kits for what
we can build; every asset with a shader whose parameters give nearly endless variety so no two villages look alike
(like the clothes); and whether the kits have a castle or a bigger city or capital. The world's regions, roads and
towns are still Luke's to design (`GAME.md`, the 2026-10-24 load-test line): this doc is the kit and the look, not
where anything goes. His open decisions are §7 (S1-S8).

## 1. What is on disk (all Quaternius, CC0, human-made: fine under the No AI disclosure rule)

| Kit | Where | What it is |
|---|---|---|
| **Medieval Village MegaKit** [Source] | `Downloads/01_Archive_Pairs/Medieval Village MegaKit[Source]/` (glTF, `glTF (Godot)` with `-convcolonly` collisions, `Textures/`); also the kit's own Godot project under `04_GameAssets/Quaternius_Assets/Medieval Village/` | ~305 grid-snapping pieces: walls in 4 finishes (plaster with timber, uneven brick, wood-and-brick, worn wood) × straight/door/window, corners, floors, overhangs, balconies, 8 doors × 2 frames, ~20 windows and shutters, stairs inside and out, ~90 roof pieces (flat or round tiles, 4/6/8 wide, modular left/mid/right, dormers, a round **tower roof**, spikes, wooden roofs), and props: chimneys, crates, wagon, fences, vines, kerbs, iron fences |
| **Fantasy Props MegaKit** [Source] | `04_GameAssets/Quaternius_Assets/Fantasy Props/` (`Blends/` has the textures) | ~212 props: market stalls (blacksmith, potions, vegetables, cart), shop signs (armory, blacksmith, food, potions, pub), banners and bunting, barrels, crates, farm crates of produce, sacks, beds, tables, chairs, benches, shelves, bookcases, books, candles, chandeliers, lanterns, torches, cauldron, anvil, bellows, workbenches, tools, weapons, pots, potions, rugs, ropes, chains, cages. 22 are already in `game/regents/art/props/` |
| **All in One by Quaternius** (zip) | `04_GameAssets/All in One by Quaternius.zip` | the older packs; the ones that matter here are in §5 |

## 2. How the kits are built (what makes a variety shader easy)

- **The whole village kit uses about ten surfaces**: Plaster, Brick, RedBrick, UnevenBrick, RoundRocks, RockTrim,
  RoundTiles, FlatTiles, WoodTrim, MetalOrnaments, plus WindowGlass and Vine. Every wall, roof and floor piece is a
  few of these, tiled.
- **Their color textures are nearly flat.** Measured on the 2048 px base colors: the spread is 3-16 of 255 per
  channel (plaster 3-6, round tiles 8-16); the look comes from the normal maps. So a color can be swapped without
  losing anything: keep the texture's light and dark, put any color under it.
- **WoodTrim is a trim sheet in bands**: light planks, dark planks, light and dark end grain, a stone strip. A band
  is a range of the texture's height, so each band can take its own color (timber one shade, beams another).
- **Wear is already masked.** The walls carry a second UV set for the kit's top, middle and bottom wear masks
  (`T_TopWear`, `T_MidWear`, `T_BottomWear`): plaster wears through to brick at the eaves and the footing. The kit's
  own shader (`M_Plaster`) has only on/off switches; we would make them amounts.
- **The props are 4 trim sheets** (Props, Furniture, Metal, Cloth, each with a worn version), and 137 of the 212
  props carry **vertex colors** marking their parts. Parts (cloth, wood, metal) can be told apart and recolored.

## 3. The proposed shader: one look per settlement, a little different per building

The clothes today are NOT a shader: a look swaps the outfit pack's colorway textures and tints skin and hair
(`game/characters/modular_character.gd`, `_dressed`). Buildings would go further, and the same idea could later
give the clothes free dyes instead of the pack's 2-3 colorways (S6).

- **One shader per surface family** (walls, roofs, wood, stone, metal, glass, props), written in code
  (`game/regents/art/town/`), replacing the kit's visual shaders. Color = the texture's light and dark × a color
  from the settlement.
- **A settlement style is a `.tres`** (`SettlementStyle`, edited in the Inspector, no code): plaster, timber (light,
  dark), stone, brick, roof tile, metal and trim colors; how worn (eaves, middle, footing); how much moss and
  grime (on faces turned up, from world-space noise); dirt splashed up from the ground; soot by the chimneys; snow
  on surfaces facing up (a northern village); how faded by the sun; window glow at night (tied to day and night).
- **Per building, a seeded nudge**: each house moves its colors a little (hue, lightness, wear) from a number
  derived from where it stands, through Godot's `instance uniform`, so a street of the same house is not a row of
  clones and nothing needs a material per house. A style gives the range; the house picks inside it.
- **A culture is a set of styles**: a fishing village (weathered gray-blue timber, slate roofs, salt bleach), a
  hill town (warm stone, red tiles), the capital (clean plaster, dark timber, blue slate, gilded metal). Two
  villages of one culture differ by their seed.
- **Props take the same style** through their vertex-color parts: the village's cloth color on its stalls,
  banners and awnings, its metal on hinges and lanterns.
- **What it costs**: the per-building nudge is free (no extra materials). A house of 60 pieces is 60 draw calls
  if left as pieces; for 300 players, a finished house is baked to one mesh per surface family (a "bake this
  house" tool, as levels are baked now), and the shader works the same on the baked mesh.
- **Alive, beyond color** (code-made, the VFX lab's way): chimney smoke, banners and bunting moving in the wind
  (the foliage shader's sway), lit windows at dusk, shutters some open and some closed, vines and flower boxes by
  seed.

## 4. What the village kit builds on its own

- **Villages and hamlets**: cottages, longhouses, a tavern, a smithy (stall + anvil + bellows), a market square
  (stalls, carts, signs, bunting), farms (fences, wagons, farm crates).
- **A market town**: three- and four-storey townhouses with overhangs, balconies and dormers; stone ground floors
  with timber above; outside stairs and platforms; a round stone tower with its tiled roof (the kit's preview has
  one); iron fences, kerbs, paved floors.
- **Interiors**: the walls have both faces, the stairs and floors are in, and the props kit furnishes them.

## 5. Castle, capital, modern city: what exists

- **No castle in the village kit**: no curtain walls, battlements, gatehouse or keep. Quaternius has not released
  a castle MegaKit that we could find (a search, 2026-11-15; their site was not checked directly).
- **In the All in One zip** (all CC0):
  - *Ultimate Modular Ruins* (Aug 2021): textured, closest in style. Gothic and round arches, columns, walls
    (whole, broken, overgrown), arched doors, barred windows, stairs, bridge sections, wall flags, statues. Its
    whole pieces could be a keep's inner yard or a cathedral nave; its broken ones, a ruined castle.
  - *Modular Medieval Buildings* (Jul 2017): tall walls, wall gates, round and square towers, watchtowers, a bridge,
    a tunnel. A real castle set, but the older flat-color low-poly style; next to the MegaKit it would look like
    a different game unless retextured.
  - *Modular Dungeon* (2018, 2019): castle cellars, the Undercroft.
  - *Ultimate Fantasy RTS* (2022): walls, wall towers, town centers, a "Wonder"; built for a top-down camera at
    miniature scale. Not for walking up to.
  - *Modular Street Pack*, *Ultimate Textured Building Pack*: modern (air conditioners, casino signs). No.
- **So for a castle or a walled capital, three routes** (S3):
  1. **Make the walls in code**: a wall, tower and gatehouse generator (a path for the wall, heights, crenels,
     arrow slits, a round or square tower at each corner), textured with the kit's own tileable stone and brick
     and the same shader. It matches the kit exactly, any length and shape, and is code-made (no disclosure
     question). The most work; the most freedom.
  2. **The Ruins pack for the keep and the grand buildings**, the village kit for the town inside, a generator only
     for the curtain wall.
  3. **Buy a castle kit** that fits the style (third-party; licence and look to check), or wait for Quaternius.
- **The capital** is then: the market-town pieces at their tallest and cleanest, the Ruins pack's arches and
  columns for halls and a cathedral, a curtain wall and gate (route 1 or 2), and a richer style (§3).

## 6. Order of work

1. ~~Intake~~ (built, §8): the village kit in `game/regents/art/village/`. The props kit waits for Luke's okay of
   the test (he wants to see everything furnished after).
2. ~~The shader, `SettlementStyle`, the town lab~~ (built, §8).
3. ~~A house from pieces, merged~~ (built, §8: merged at run time; a saved bake is still to do).
4. ~~A test world~~ (built, §8: `town_world.tscn`, the castle by route 1). Next: Luke's look at both labs; then
   furnishing with the props kit; then his S1-S8 and a first real village where he puts it.

## 7. Luke's open decisions

- **S1** Settlements: how many, which sizes (hamlet, village, market town, the capital), and is there one castle
  (the Regent's seat?) or several (lords' keeps)?
- **S2** How far variety goes: a style per culture or region, with each village a seed inside it (proposed); or
  every village its own hand-picked style?
- **S3** The castle: walls made in code with the kit's textures (proposed), the Ruins pack, or buy a kit?
- **S4** Snow, salt, moss, soot: by region (the north has snow) or by the season, if the game has seasons?
- **S5** Who builds a house: placed by hand from pieces in the editor (proposed first), or a builder that makes a
  house from a footprint and a style?
- **S6** Clothes on the same idea later: free dye colors per part, instead of the pack's colorways?
- **S7** Interiors: can players walk into houses, or only some (the tavern, the smithy, the bank)?
- **S8** Do towns change with play (the market fuller when a province's writs are met, damage, banners of who
  holds it), or is the look fixed?

## 8. Built (2026-11-15): the town world and the town lab

Luke, 2026-11-15: "a small 3d scene (say 1km x 1km) that packs in a small village, middle market town and a castle
with code made walls and reusing the walls. and then another wardrobe like lab that shows some preset village sets
for colors to show how unique each can look using exact same models"; the kit's demo houses used; no props yet
("once i okay the test Ill want to see how eveything furnishes"). Presentation only: nothing is in the game.

**How to look at it** (F6 in the editor, no server):
- `game/regents/town/town_world.tscn`, THE TOWN WORLD: a kilometer square. The village (Riverside style: cottages in
  two rings round a green, the kit's House D as the inn, a few along the road out), the walled market town in the
  middle (Sunreach: two streets crossing at a cobbled market, two lanes, ~110 houses facing the streets, the kit's
  demo houses at the market, the kit's tower in its corner; a `CastleWall` with square towers and three gates), the
  castle on its mound (The capital: a pentagon curtain wall with round towers and a gatehouse toward the town, a keep
  that is a small roofed `CastleWall`, a hall, barracks, a stable and the kit's tower). Roads between them, woods
  (the nature kit's common trees, bushes, rocks; its red and blue trees left out). Keys: 1-7 views, right mouse to
  look, WASD QE to fly, Shift, wheel for speed, L day/dusk/night, S every place to the next preset style, H help.
- `game/regents/town/town_lab.tscn`, THE TOWN LAB: one little street (three `KitHouse`s, the kit's House D, a stretch
  of wall with towers and a gate) in every preset: 1 Presets (all eight side by side; Left/Right to step through them
  close), 2 One (the panel edits a style live: every slot's color and alpha, the weather, each building's spread,
  the night; Save style writes `styles/custom_<time>.tres`), 3 Seeds (one style, six streets: each building's own
  nudge), 4 Houses (one house in every preset in a row). L light, H panel.
- Shots (windowed): `"$GODOT" --path . res://game/regents/town/town_world.tscn -- <out dir>` and the same with
  `town_lab.tscn`.

**What it is** (`game/regents/town/`):
- `town_surface.gdshader` (+ `town_weather.gdshaderinc`, `town_leaves.gdshader`): THE TOWN DYE, the wardrobe's idea
  for buildings. A texel becomes its slot's color times how much lighter or darker the painting is than the texture's
  measured mean; alpha is how much. Modes per kit material: one slot; plaster over stone (the kit's wear masks show
  the stone, by `wear`); the wood trim sheet's bands (light planks, dark timber, end grain, its stone strip); roof
  tiles weathered by the kit's second UVs; glass (lit at night, window by window, `lit_share`); metal; vines. Then
  each building's nudge (hue, light, wear, from two instance uniforms: no material per building) and the weather
  (grime at the foot, moss up and low, the sun's fading, snow on what faces up).
- `settlement_style.gd` (`SettlementStyle`, a `.tres`): eleven slots (plaster, stone, masonry, brick, paving, roof,
  timber, planks, metal, glass, foliage), the weather, each building's spread, the night. `styles/`: eight presets
  (As painted, Riverside, Saltmarsh, Sunreach, Frostmark, The capital, Fenwick, Ashfall).
- `town_kit.gd` (`TownKit`): which kit material is which mode and slots (`SURFACES`, the means measured by
  `game/regents/tools/town_kit.py means`); the style's shared materials; DRESS (a building's surfaces, its seed and
  foot); MERGE (a building's pieces into one mesh, a surface per material: a 76-piece house draws as 13);
  `instance_building` and `gather_collisions` (a building's many piece bodies made one: the town alone passed Jolt's
  10240-body limit before this).
- `kit_house.gd` (`KitHouse`): a house from the kit's pieces by footprint (2 m cells), floors, the ground and upper
  finishes (plaster, uneven brick, wood and brick, worn wood), round or flat tiles, stone or boarded gables, the
  door's cell, arched or square openings, how many windows and shutters, a chimney, a seed. The kit's grid read from
  its own sample scene (walls 2 x 3 m, outside +z; the one-piece roofs `Roof_<tiles>_<depth>x<width>`, turned -90).
  A footprint the kit has no roof for is narrowed (`effective_width`). Builds in the editor too, never saved.
- `castle_wall.gd` (`CastleWall`): ROUTE 1 of §5: walls in code round any outline, open or closed; a plinth, a cap,
  merlons and an inner rail; round (16 sides) or square towers at the corners with tiled cones or pyramids; gates in
  any stretches (a frame, a half-raised portcullis, a gatehouse of two square towers); `roofed` makes a keep. The
  kit's own stone at the kit's scale; its surfaces named as the kit's materials, so a `Settlement` dresses it like a
  house. The town's wall, the curtain and the keep are all this one script.
- `settlement.gd` (`Settlement`): every building under it (a `KitHouse`, a `CastleWall`, any instanced scene; plain
  groups searched) dressed in its style and merged as the game runs; nothing changes in the editor. `restyle` swaps
  the style live.
- `houses/demo_*.tscn`: the kit's own demo buildings (its Godot sample scene: House C, Houses A, House D, the Tower;
  C2 is C again) rebuilt from our pieces by `town_kit.py demo`.
- `town_world.gd`, `town_ground.gdshader` (grass, dirt roads and cobbled squares from the layout, code-made but the
  cobbles), `town_lab.gd`.

**Tested**: `game/regents/tests/suites/regents_town.gd` (`-- --only=regents_town`), 39 checks: the presets; every
material the kit's 305 pieces wear is a known slot, every texture there (NEGATIVE: with `MI_Vine` taken out of
`SURFACES` three checks fail; restored); a house's roof, gables, corners, one door, one body, the same seed the same
house, the narrowing both ways; a settlement merges each building to one mesh, every surface dyed, materials shared,
seeds differ, a live edit reaches the material, an unknown surface is left and reported; the gate is open and the
wall beside it solid (NEGATIVE: no gate, the same spot is wall); the world's three places full and inside 1 km, no
two town houses overlapping (it caught the kit's tower counted inside the market); the lab's four modes. Looked at in
the shots of both scenes (day, dusk, night; every preset close).

**Left for later**:
- Furnishing: the Fantasy Props kit (stalls, carts, barrels, signs, banners, lanterns, furniture) in the market, the
  village and the castle yard, dressed by the same styles through its vertex-color parts. After Luke's okay.
- A saved bake of a merged building (today it merges as the game runs: ~17 s to build the whole world headless, and
  each piece's scene is loaded); and LODs or impostors for the farthest buildings.
- The village kit's own small props (`Prop_Wagon`, crates, fences, vines) placed by a settlement.
- The ground is a stand-in (value-noise grass, painted roads): the real world's terrain and paths are Luke's.
- Interiors, stairs and upper floors are left out of `KitHouse` (draw calls): S7.
- The nature kit's twisted and tall-thick trees have red and blue leaves; the woods here leave them out.
