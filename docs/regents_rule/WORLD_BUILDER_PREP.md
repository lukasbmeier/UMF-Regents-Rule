# World Builder & Lore Tooling prep (2026-11-16): "Hypixel Creative Mode" for Regent's Rule

**ANSWERED (Luke, 2026-11-16): "Accept all proposed and start building".** WB1–WB12 as proposed, in full in `GAME.md`
("THE WORLD BUILDER AND LORE STUDIO, ANSWERED"); §10 below is the order of work.

Luke, 2026-11-16: "make a really advanced world building addon on top of our repo for world building and lore. I'm
thinking functionality ranges from using Terrain3D built-in terrain and texture painting, to adding mesh instances
(with Terrain3D and without since there are some limitations with Terrain3D mesh placer), foliage and grass usage like
scatter tool does, making preset houses and/or placing already built ones (from the kit demo or even the town lab),
placing NPCs and working on their dialogue options, props and stations, enemies, harvestable nodes, mobs, etc.
Basically Hypixel creative mode for our game with tools adapted to what we need to place in the world. Can start on a
procedural base or create it all from scratch. I want as mature and advanced features as possible."

Like the other prep sheets, every decision (§9, **WB1–WB12**) carries a proposed answer; nothing in the game or
foundation is changed until Luke locks them in; his answers go to `GAME.md` and §10 becomes the order of work.

---

## 1. Three findings from the read-only pass (why this fits the repo so cleanly)

1. **About 70 % of the underlying machinery is already built and tested.**
   - **Terrain:** `Terrain3D` (`addons/terrain_3d/`) + procedural height/control/color map import (`build_continent.gd`,
     `continent_shape.gd`) + automatic wading-depth sea barriers.
   - **Towns & kits:** `KitHouse` (parametric houses from the 305-piece Medieval Village kit), `CastleWall` (procedural
     curtain walls, round/square towers, 5 roof styles, gatehouses, keeps), `houses/demo_*.tscn` (the kit's own demo
     buildings), `PropGroup` + `TownFurnish` (212 Fantasy Props kit items), `VillageDressing` (vines, fenced yards,
     crates, wagons), and `Settlement` + `SettlementStyle` + `TownKit` (the 11-slot town dye shader, per-building
     instance seed nudge, mesh merging, and Jolt single-body collision gathering).
   - **Foliage & ground wear:** `RegentsGroundClutter` (MultiMesh grass/flowers/pebbles with distance shrink and wind
     sway), `RegentsGroundPaint` (trodden dirt under stations and along `Path3D` trails, bare soil under trees/rocks),
     and `RegentsSolidProps` (automatic convex hulls on solid rocks, passable bushes).
   - **Server & streaming bake:** `LevelInfo`, `LevelBaker`, `LevelCells`, and `LevelStreamer`. Any `LevelPoint` placed
     under `LevelInfo/Cells` is automatically sliced into `64 m × 64 m` client streaming cells and compiled into
     `shared/world/<level>.json` for the server (`regents.rs` `populate`).
   - **Dialogue & outfits:** `CinemaDialogue` + `CinemaBalloon` (Dialogue Manager 3-compatible `.dialogue` runner with
     branching choices, state flags, camera/pose tags, and voice cadence synthesis) and `RegentsFigure` + `Wardrobe`
     (modular peasant/ranger/wizard/knight/noble outfits with dye palettes).
2. **Staying 100 % in Godot beats a web-page exporter by an order of magnitude.**
   - `Terrain3D` region storage, the custom town/foliage/wardrobe shaders, Jolt convex-hull generation (`RegentsSolid`),
     model-edge work-reach raycasts (`NodeComponent.surface_along`), and the physics-driven server bake (`LevelBaker`)
     all run natively in Godot. Rebuilding those in a browser would duplicate the engine and still look different.
   - Instead, we can run the World Builder **as an interactive in-engine "Hypixel Creative Mode" (`world_builder.tscn`,
     F6)** where you fly with WASD or drop into your walking character at any second, with a clean hotbar, radial/dock
     palette, and live inspector—and every save writes directly to the real Godot level `.tscn`, `Terrain3D` data
     folder, and `.tres` content files so the standard Godot editor can open them too.
3. **Three gaps currently stop a designer from hand-building a real world:**
   - **Re-running `build_continent.tscn` wipes hand edits** (`build_continent.gd` overwrites `continent.tscn` and
     `terrain/data/`). We need non-destructive scene layers and procedural exclusion masks (§3).
   - **`RegentsGroundClutter` and `RegentsGroundPaint` are flat-ground only (`y = 0`)** (`frontier.tscn`). They need to
     read `Terrain3D` height, slope, and texture control maps across `64 m` cells (§5).
   - **`LevelPoint` markers are invisible crosses in the editor** (`frontier.tscn`), and only the tutorial `guide`
     exists as a friendly NPC. Placing nodes, stations, foes, and lore NPCs needs live 3D preview meshes, radius/leash
     rings, and a general `NpcDef` content type (§7, §8).

---

## 2. Mode of operation: In-Game "Creative Mode" (F6) + Editor Plugin Sync

Rather than forcing you to click through Godot's deep scene tree and type raw strings into `Marker3D` arrays, the World
Builder is a **dedicated Creative Mode studio (`game/regents/builder/world_builder.tscn`, F6)** that also works as an
`@tool` overlay in the editor:

- **Instant Fly / Walk Toggle (`Tab` or `V`):**
  - **Fly Mode (Creative):** WASD + Q/E free-flight (scroll wheel adjusts speed from 3 m/s to 400 m/s, Shift to boost,
    same feel as `town_world.gd`), with a 3D ground/surface cursor, grid/angle snap toggles, and a bottom hotbar (`1–9`)
    + collapsible side palette.
  - **Walk Mode (Play-in-Place):** Drops your real `Adventurer` body onto the cursor's spot using the game's real
    `MovementModel`, camera rig, and interaction ray. You can walk through doors, check jump clearances, test sightlines,
    and press `E` on any placed NPC to test their dialogue tree live—then press `Tab` to pop right back into Fly Mode.
- **Undo / Redo (`Ctrl+Z` / `Ctrl+Y`):**
  - Every brush stroke, terrain sculpt, placed building, moved marker, or deleted prop goes through a command history stack.
- **Direct Save + One-Click Server Bake:**
  - **Save (`Ctrl+S`):** Saves the `Terrain3D` storage directory (`terrain/data/`), the level `.tscn`, and any edited
    `NpcDef` / `SettlementStyle` resources.
  - **Bake & Publish (`Bake World` button):** Runs `LevelBaker` + `LevelCells` (cutting the `64 m` streamed cells and
    writing `shared/world/<level>.json` + `_depth.bin` + `_ground.bin`) and shows a **"What the Server Sees" overlay**
    (water depth grid, wading barrier, cell grid, and point radii).

---

## 3. Pillar 1 — Starting Base (Procedural vs. Scratch) & Non-Destructive Layers

You asked to **start on a procedural base or create it all from scratch** without losing hand-built work when tweaking
procedural scatter.

### 3.1 Starting a new or existing world
When opening the World Builder, you pick (or create) a level:
1. **Start from Scratch (Blank Canvas):** Creates a new `LevelInfo` scene + empty `Terrain3D` region grid at your chosen
   vertex spacing (`1 m` or `2 m`), sea level (`water_y`), and default grass texture.
2. **Start from Procedural Generator:** Runs a parameterized base generator (noise/ridge/coast parameters like
   `ContinentShape`, or a heightmap image you supply—human-made or procedural code, keeping the No AI Disclosure rule) to
   populate the initial `Terrain3D` height/control/color maps.
3. **Open Existing Level:** Opens `frontier.tscn` (level 20), `continent.tscn` (level 21), `expanse.tscn` (level 22), or
   any new level scene.

### 3.2 Non-destructive layer hierarchy under `LevelInfo/Cells`
To prevent procedural regeneration from wiping hand-placed towns, roads, or quest camps, everything under `Cells` is
organized into explicit sub-layers (and `LevelCells.cut` is updated to walk one level deeper or flatten layer children
into their `64 m` cell scenes at bake time):
- `Cells/Hand_Settlements` — hand-placed `Settlement`s, `KitHouse`s, `CastleWall`s, `PropGroup`s.
- `Cells/Hand_Props` — hand-placed rocks, ruins, bridges, docks, landmarks.
- `Cells/Hand_Gameplay` — hand-placed `LevelPoint`s (nodes, stations, foes, bosses, NPCs, POIs).
- `Cells/Proc_Scatter` — procedurally scattered trees, rocks, wildlife, and camps.

**Exclusion Volumes (`BuilderZone`):** Every `Settlement`, road spline, or hand-placed `BuilderZone` carries a
`clear_procedural_radius` (or polygon). You can click **"Re-Scatter Procedural Layer"** at any time: it only regenerates
`Cells/Proc_Scatter` and automatically skips any spot inside a hand-built town, road, or exclusion zone.

---

## 4. Pillar 2 — Terrain3D Sculpting, Painting & Auto-Leveling Foundations

`Terrain3D` already ships `Terrain3DEditor` C++ operations for sculpting and painting (`addons/terrain_3d/`). In the
World Builder, we wrap those directly into the Creative Mode hotbar and add **structure-aware terrain tools**:

- **Sculpt Brushes:**
  - **Raise / Lower** (LMB raise, Shift+LMB lower; adjustable radius, strength, falloff).
  - **Smooth** (blends rough vertices).
  - **Flatten to Height** (picks height on click, levels ground to that Y).
  - **Ramp / Slope** (click Point A, click Point B: carves a walkable ramp or mountain pass between two heights,
    checking against the movement model's max walkable slope).
  - **Terrace / Plateau** (steps heights in configurable meter bands for cliffside camps or castle mounds).
- **Surface & Texture Brushes:**
  - **Texture Paint:** Paints `Terrain3D` base/overlay texture IDs and blend weights (grass, dirt, cobble, rock, sand,
    snow, forest floor).
  - **Auto-Slope/Height Material Rule:** One-click or brush-applied rule that automatically paints steep faces (`slope >
    0.85`) as Rock and low shore (`y < water_y + 1.6`) as Sand, while leaving hand-painted roads untouched.
  - **Vertex Color / Wetness Tint:** Paints subtle dark/warm/cool ground variation into `Terrain3D`'s color map.
  - **Holes / Caves Cutout:** Cuts `Terrain3D` hole masks where a dungeon entrance (`Undercroft`) or cave mesh sits.
- **Auto-Level Under Buildings & Stations (Toggleable):**
  - When you stamp a `KitHouse`, `demo_house_*`, `CastleWall`, or `Station` onto hilly terrain, the builder automatically
    flattens the `Terrain3D` vertices under the building's oriented bounding box (`footprint + margin`) and cosine-blends
    a skirt (`blend_m`, default `4 m`) into the surrounding hill—so no house ever floats or clips half-buried into a
    slope.

---

## 5. Pillar 3 — Mesh Instances (Terrain3D Instancer vs. Scene Nodes)

You noted that `Terrain3D`'s built-in mesh placer (`Terrain3DInstancer`) has limitations, so you want **both**. Here is
how the tool handles both seamlessly from the same asset browser:

| Mode | How it stores & renders | Best for | Limitations handled |
|---|---|---|---|
| **Mode A: Scene Node (`Cells/Hand_Props`)** | Instantiates the `.gltf` / `.tscn` under `LevelInfo/Cells`; cut into `64 m` streamed scenes by `LevelCells`; wrapped in Jolt convex hulls by `RegentsSolidProps` if solid | Rocks that block players and foe sight, bridges, docks, ruins, custom landmarks, anything needing per-instance scripts or exact Jolt collision | Automatically sets `visibility_range_end` so distant cells cull cleanly |
| **Mode B: `PropGroup` Batch (`Settlement`)** | Places props into a `PropGroup` (`prop_group.gd`); `TownKit.merge` combines all meshes by material into **1 draw call** and `TownKit.gather_collisions` combines all colliders into **1 `StaticBody3D`** | Cluttered areas: market stalls, barrel stacks, camp furniture, fences, walls, smithies (avoids Jolt's 10,240 body limit) | Supports "Unpack to Edit" in the builder and "Merge" for runtime |
| **Mode C: `Terrain3D` MultiMesh Instancer** | Writes transforms into `Terrain3D`'s region-baked `MultiMesh` cells (`Terrain3DInstancer`); moves automatically when terrain height is sculpted | Thousands of background visual meshes (distant pine forests, cliff boulders outside walkable play space, dense undergrowth) | No per-instance script or `RegentsSolid` wrapper; used strictly where hardware-instanced visuals are wanted |

**Placement ergonomics for all three modes:**
- **Ghost preview** at the 3D cursor before clicking.
- **Scroll wheel:** Rotate yaw (`15°` snap, or smooth with `Shift`, or `R` for random yaw).
- **`[` / `]`:** Scale up/down (or toggle random scale range `0.8–1.3`).
- **Align to Surface Normal toggle (`N`):** Tilts rocks and ferns with the hill slope, while keeping trees and buildings
  plumb (`Vector3.UP`).
- **Paint-Drag Stroke:** Hold LMB and drag to scatter props at a minimum spacing (`min_spacing_m`).

---

## 6. Pillar 4 — Foliage, Grass & Ground Wear (Scatter Tool + Road Splines)

Upgrades `RegentsGroundClutter` (`ground_clutter.gd`) and `RegentsGroundPaint` (`ground_paint.gd`) from flat-ground glade
scripts into a full **Terrain-Aware Scatter & Path System**:

1. **Terrain3D Height & Slope Integration:**
   - Each clutter tuft queries `Terrain3D` height (or raycasts static ground) at `(wx, wz)` and aligns to the surface
     normal.
   - Steep slopes (`slope > max_slope`, e.g. cliff faces) and underwater cells (`y < water_y`) automatically reject grass.
2. **Spline Roads & Trails (`Path3D` Tool):**
   - Click points on the terrain to draw a `Path3D` road or trail.
   - Choose its surface style: **Trodden Dirt** (stamps `RegentsGroundPaint` red channel / `Terrain3D` dirt texture),
     **Cobblestone**, or **Stone Setts** (`town_paving.gdshaderinc`).
   - Optionally **flatten the cross-slope** of the terrain along the road spline so carts and players walk on a level
     roadbed cutting across hills.
   - Grass (`RegentsGroundClutter`) automatically stays off the road and clusters along its verges (`at_edges`).
3. **Scatter Zones & Erase Brush (ProtonScatter-style):**
   - Define **Biome Scatter Presets** (e.g., *Meadow Grass & Flax Flowers*, *Deep Forest Fern & Mushroom*, *Rocky Scree &
     Pebbles*, *Autumn Timberline*).
   - Apply a preset either **world-wide by texture/altitude** or inside a **drawn Polygon / Brush Mask**, and use an
     **Erase Clutter** brush to clear grass inside specific campfires or yards.

---

## 7. Pillar 5 — Settlements, Preset Houses, Demo Kits & Castle Walls

Brings everything built in `town_lab.gd` and `town_world.gd` (`SETTLEMENTS_PREP.md`) into an interactive builder tool:

1. **Settlement Container & Style Live-Switcher:**
   - Click **"New Settlement"** on the map (e.g., *Riverside Hamlet*, *Sunreach Market Town*, *Northern Keep*).
   - Pick any of the 8 `SettlementStyle` presets (`01_as_painted` through `08_ashfall`) or tweak the 11 dye slots,
     weathering (moss, grime, snow, sun fade), and paving pattern live—every building inside that settlement updates its
     shader parameters immediately.
2. **Three Ways to Place Buildings:**
   - **Parametric `KitHouse` Stamper:** Move the cursor, adjust width (`1–7` cells), depth (`2–4` cells), floors (`1–4`),
     ground/upper wall finishes (`Plaster`, `UnevenBrick`, `WoodBrick`, `WoodWear`), roof tiles (`Round`, `Flat`),
     gables, door cell, and `house_seed` (press `R` to roll a new window/shutter/door/dressing layout on the spot).
   - **Pre-Built Demo & Lab Prefabs:** One-click stamp of the kit's complex authored buildings (`demo_house_c`,
     `demo_house_d` inn, `demo_houses_a` row, `demo_tower`) or **any custom house you save as a preset**.
   - **Piece-by-Piece Custom Builder ("Kit Piece Mode"):** When you want a unique landmark building (a guildhall, a
     bridge-house, an L-shaped tavern, or an interior), switch to **2 m Grid-Snap Kit Mode** to snap individual walls,
     arches, stairs, balconies, roofs, and props from the 305 Medieval Village pieces and 212 Fantasy Props pieces, then
     click **"Save as Building Preset"**.
3. **Interactive `CastleWall` & Keep Drawer:**
   - Click corner points on the terrain to draw a `CastleWall` polygon or open wall stretch.
   - Click any wall segment to toggle a **Gatehouse & Portcullis** (`gates`).
   - Adjust wall height, thickness, round vs. square corner towers, roof style (`Cone`, `Bell`, `Stepped`, `Kit`,
     `Turret`, `Open`), slate vs. round tiles, or toggle `roofed = true` to turn a closed wall into a **Keep**.
4. **One-Click Furnishing Stampers (`TownFurnish` + `VillageDressing`):**
   - Stamp complete functional arrangements—**Market Square Stalls**, **Village Green Campfire**, **Inn Outdoor Tables**,
     **Training Yard**, **Smithy Corner**, or **House Door Lanterns/Signs/Crates**—which automatically populate a
     `PropGroup` and inherit the settlement's cloth/wood/metal colors.

---

## 8. Pillar 6 & 7 — Gameplay Objects, Friendly NPCs, Dialogue & Lore

### 8.1 Live 3D Previews & Gizmos for Every `LevelPoint`
Today, `LevelPoint` is a bare `Marker3D`. We extend `LevelPoint` (or attach an `@tool` `LevelPointPreview` helper) so
that in the editor and World Builder:
- **`kind = "node"`:** Shows the actual `NodeDef` 3D tree/rock/flax model (with ore nuggets if a rock), its trunk/rock
  footprint ring (`radii_cm`), and its `3 m` work-reach ring (`regents.work_reach_m`).
- **`kind = "station"`:** Shows the `StationDef` 3D station pieces (`furnace`, `anvil`, `workbench`, `spinning_wheel`,
  `tanning_rack`, `orders`) and its interaction radius.
- **`kind = "<foe_key>"` (`skeleton_warrior`, `skeleton_archer`, `imp`, `wolf`, `deer`, `sparring_skeleton`):** Shows the
  dressed `Mannequin` / `FoeLook` (with bow/blade/albedo), plus 3 color-coded ground rings:
  - **Wander radius** (`FoeDef.wander_m`, green)
  - **Sight / Notice cone & hearing ring** (`FoeDef.notice_m`, `notice_arc_deg`, `hear_m`, amber)
  - **Leash radius** (`FoeDef.leash_m`, red) and **Pack call radius** (`FoeDef.pack_m`, blue, showing lines to nearby
    packmates!).
- **`kind = "poi"`:** Floating banner/icon gizmo showing the World Map label (e.g. `"Copper mining zone"`, `"Sunreach
  Market"`), immediately previewable on the `M` World Map.
- **No bloat in saved scenes:** The preview meshes are created with `Node.INTERNAL_MODE_BACK` and never saved into the
  `.tscn`, so the server bake and client runtime stay identical to today.

### 8.2 Friendly NPCs, Lore & Dialogue Workbench (`NpcDef`)
Right now, only `guide` (the Drillmaster) exists on the server (`regents.rs` `populate_guides`). To support full world
lore, townsfolk, quest-givers, guards, and chroniclers:
1. **New `NpcDef extends ContentDef` (`game/regents/content/npc_def.gd`):**
   - `key: StringName` (what `LevelPoint` `kind = "npc"` `tags[0]` references, e.g., `"chronicler"`, `"blacksmith_hal"`).
   - `display_name: String` and `title: String` (e.g., `"Master Smith Hal"`, `"The Chronicler"`).
   - **Appearance & Outfit:** Body (`Male` / `Female`), outfit family (`Peasant`, `Ranger`, `Wizard`, `Knight`, `Noble` —
     remember `GAME.md`: Noble and Knight tabard are reserved for NPCs!), hair/beard/skin, and `DyePalette` / armor
     pieces, plus optional held item (`hammer`, `staff`, `sword`, `mug`) and idle pose (`AnimationSet` clip).
   - **Dialogue & Lore Script:** Inline `@export_multiline var dialogue_script: String` (or path to a `.dialogue` file)
     using `CinemaDialogue`'s syntax (`~ start`, speaker lines, `[#cam=...]`, `[#pose=...]`, branching `- Choice [if
     flag]`, `set flag`, `do action`), plus `designer_notes` / lore codex entry.
2. **In-Builder Dialogue & Lore Editor + Live Test:**
   - Click any placed NPC in the World Builder to open the **NPC & Lore Inspector** on the right:
     - Tweak their outfit, colors, held prop, and facing yaw live in 3D.
     - Edit their `.dialogue` branches with live syntax checking (catches missing `=> target` sections or bad tags).
     - Click **"Test Dialogue Here"**: immediately runs `CinemaDialogue` + `CinemaBalloon` (using the camera cuts and
       poses right where the NPC stands in your town/camp!) so you can click through every dialogue branch and hear the
       voice cadence without starting a server.
3. **Server Integration (Add-Only, Rule 17 Compliant):**
   - `LevelPoint` with `kind = "npc"` and `tags = ["<npc_key>"]` is read by `populate_npcs(ctx, world_id)` in
     `regents.rs`, spawning an unhurtable NPC entity (`ENTITY_NPC` / `ENTITY_GUIDE`) with a `"stand"` (or `"wander"`)
     brain and a public `world_npc` side-table row (`entity_id, world_id, chunk, npc_id, point_id`) so every client
     dresses the NPC from `NpcDef` and opens their dialogue on `E`.

---

## 9. The Decisions That Are Yours (WB1–WB12)

Every item has a recommended default so you can reply **"Accept all proposed"** or adjust any specific one:

| # | Decision | Proposed |
|---|---|---|
| **WB1** | **Where the tool runs** | **100 % in Godot** as a playable **"Hypixel Creative Mode" scene (`game/regents/builder/world_builder.tscn`, F6)** that writes directly to the real level `.tscn`, `Terrain3D` data folder, and `.tres` content files—plus `@tool` gizmos so the standard Godot editor shows the same previews. (No external web app needed.) |
| **WB2** | **Camera & testing controls** | **Dual-mode (`Tab` to swap):** Free-Fly camera (`WASD/QE`, scroll speed, 3D surface cursor) for fast building, and instant **Drop-In Walk Mode** (spawns your real `Adventurer` at the cursor to test scale, jumps, collisions, work spots, and NPC dialogue in place). |
| **WB3** | **Procedural vs. hand-built workflow** | **Both, non-destructively:** Start a world either **From Scratch** (blank `Terrain3D`) or **From Procedural Base** (`ContinentShape` / noise). Separate scene children under `Cells` into `Hand_*` and `Proc_Scatter` layers, with **Exclusion Zones** around towns/roads so re-running procedural scatter never touches hand-built areas. |
| **WB4** | **Terrain sculpting & building foundations** | Wrap `Terrain3DEditor` brushes (Raise, Lower, Smooth, Flatten, Ramp, Terrace, Texture Paint, Auto-Slope Rock/Sand) in the Creative Mode bar, **plus Auto-Flatten Under Footprint** (with a smooth blend skirt) whenever a house, wall, or station is stamped on a hill. |
| **WB5** | **Mesh placement modes** | Support **all three** from one palette: (1) **Cell Scene Nodes** (`Cells/Hand_Props`, wrapped by `RegentsSolidProps` for solid rock collision), (2) **`PropGroup` Batches** (auto-merged mesh + single Jolt body for dense town/camp clutter), and (3) **`Terrain3D` Instancer** (for thousands of visual-only background trees/rocks). |
| **WB6** | **Foliage, grass & roads on hills** | Upgrade `RegentsGroundClutter` and `RegentsGroundPaint` to work **per `64 m` cell on `Terrain3D` heights and slopes** (rejecting cliffs and underwater), add a **`Path3D` Road/Trail drawer** (dirt, cobbles, or setts, with optional roadbed leveling), and a **Scatter/Erase Brush**. |
| **WB7** | **Houses, walls & kit building** | Support **3 building tiers**: (1) Parametric `KitHouse` stamper (width, depth, floors, finishes, seed), (2) Preset/Demo stamper (`demo_house_*` + any saved custom house), and (3) **2 m Grid-Snap Piece Mode** for assembling custom landmarks from the 305 village + 212 prop pieces and saving them as new presets. Include the click-to-draw `CastleWall` & Keep tool. |
| **WB8** | **Live 3D previews on `LevelPoint`s** | Give `LevelPoint` an `@tool` preview visualizer (never saved into the `.tscn` file) that renders the actual tree/rock/station/foe/NPC 3D model and draws **work-reach, wander, sight-cone, hearing, leash, and pack-link rings** in the builder. |
| **WB9** | **Friendly NPCs & Lore (`NpcDef`)** | Add `NpcDef extends ContentDef` (`game/regents/content/npc/`): display name, title, `RegentsFigure` outfit (including NPC-only **Noble** and **Knight tabard** looks), dye palette, held item, idle pose, lore notes, and `.dialogue` script. Add a `world_npc` cell table (add-only, rule 17) so `E` talks to any placed NPC. |
| **WB10** | **Dialogue authoring & presentation** | Built-in **Dialogue Editor & Live Tester** in the World Builder side panel using `CinemaDialogue` + `CinemaBalloon` (`cinema_lab.gd`). Include both **3D Speech Bubble** and **Bottom Cinematic Box** styles (matching your `GAME.md` B11 note) so you can preview conversations in place. |
| **WB11** | **World Map POI integration** | Any `LevelPoint` with `kind = "poi"` (or a `Settlement` with a map title) can be placed/edited in the builder and previewed immediately on the `M` World Map overlay. |
| **WB12** | **Where it lives (Rule 16)** | Everything genre-specific (TownKit, RegentsGroundClutter, NodeDef/FoeDef/StationDef/NpcDef previews, `world_builder.tscn`) lives under `game/regents/builder/` (listed in `regents.paths`). Any generic level-gizmo hook on `LevelInfo` / `LevelPoint` stays foundation-clean. |

---

## 10. Order of Work (Once Locked In)

Each slice is self-contained, verified by headless unit checks (`regents` suite), and ends with a playable F6 build:

1. **Slice 1 — The Creative Mode Shell, Fly/Walk Controller & Non-Destructive Layer Saver:**
   - `game/regents/builder/world_builder.tscn` + `world_builder.gd`: load any level (or create from scratch / procedural
     base), WASD fly camera + `Tab` drop-in `Adventurer` walk test, 3D raycast cursor, Undo/Redo stack, `Hand_*` vs.
     `Proc_Scatter` layer preservation, and one-click **Save & Bake (`LevelBaker` + `LevelCells`)** with a server-view
     overlay.
2. **Slice 2 — Live `LevelPoint` 3D Visualizers & Gameplay Palette (Nodes, Stations, Foes, Wildlife, POIs):**
   - `@tool` preview models + radius/sight/leash/pack gizmo rings on `LevelPoint`; hotbar palette to stamp and configure
     gathering nodes (`Tree`, `Oak`, `Yew`, `Copper`, `Iron`, `Coal`, `Flax`), stations, dummies, foes (`Skeleton
     Warrior/Axeman/Archer`, `Imp`, `Wolf` packs, `Deer`), and World Map POIs from dropdowns.
3. **Slice 3 — Settlements, Houses (`KitHouse` / Demo / Piece Snap), `CastleWall` Drawer & Auto-Leveling:**
   - Interactive `Settlement` manager (live `SettlementStyle` & `VillageDressing` picker), `KitHouse` + `demo_house_*`
     stamper with **automatic `Terrain3D` footprint leveling**, click-to-draw `CastleWall` & Keep tool, `TownFurnish`
     group stampers, and 2 m grid-snap piece mode for custom buildings.
4. **Slice 4 — Terrain3D Sculpt/Paint Brushes, Road Splines & Terrain-Aware Clutter Scatter:**
   - In-builder `Terrain3D` sculpt/paint brushes (Raise, Lower, Smooth, Flatten, Ramp, Texture Paint, Auto-Slope),
     `Path3D` road/trail drawer, and upgrading `RegentsGroundClutter` + `RegentsGroundPaint` to sample `Terrain3D`
     heights/slopes across cells with paintable scatter/exclusion zones.
5. **Slice 5 — Friendly NPCs (`NpcDef`), Wardrobe Picker & In-Builder Dialogue/Lore Studio:**
   - `NpcDef` content type + workbench, `world_npc` server table & `populate_npcs`, in-builder NPC outfit/dye configurator
     (Peasant, Ranger, Wizard, Knight, Noble), `.dialogue` script editor with syntax validation, and one-click **"Test
     Conversation"** in-place preview.
