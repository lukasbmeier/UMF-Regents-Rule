# WAITING ON LUKE (the armor run's sheet, 2026-11-15; the master keeps it)

One line each: the question, today's value or the proposal, where it is written. Nothing here is defaulted.

## 1. Decisions only you can make
**Combat and foes**
- A foe's swing shown landing at the server's time, your own hits' spark at once? Today: neither (`GAME.md`, "hit at once").
- The archer's and the imp's numbers (F16: the sheet's as a start); the lead's share of a shot (`FOES_PREP.md` §6).
- `regents.string_chase_ms`, `regents.roll_late_ms` 50: the agent's numbers, yours to change (hot rules).
- The wolf pack's place; others' aim held a moment after a spell lands ("maybe").
- Others' effects: always the lighter version (half the particles, no light), or whole when few players are near? Today: always half (PROGRESS 88).
- The combat triangle as foe design; single against multi combat zones (`COMBAT_OVERHAUL.md` §8).

**Abilities**
- The bar: round or square (`bar_lab.tscn`; B11).
- Your rewrite of the sword's pools (`ABILITIES_PREP.md` §9); then the axe's, bow's and staff's real content (§2 below).
- CONFIRM: "Blink moves from the staff to cloth chests" (B8) is built: the staff has no Blink; a staff user with no robe has an empty F that says what fills it.
- A chest's ability costs no mana and trains no mastery (mana is the staff's alone): yours to change. The chest's level (B8) waits for a family with more than one ability.
- B13 as read (one free change a week, then the head's materials, escalating): confirm the reading.
- How a shove is worded on the bar: today "knocks it back at 10 m/s" (the content's number); a distance in meters reads better but depends on the movement's friction (PROGRESS 102).
- Which other abilities hit every foe in their sweep (only Cleave is marked; `hits_all` on the ability's .tres; PROGRESS 89).
- YOUR STAFF: the staff now has a placeholder ult (Meteor) on R, so a staff that took Gale or Frost Ring on R keeps the pick but it no longer fires: change the pick to Meteor (free once a week), or say the staff should have no ult until yours is designed.
- The second pick (~12) has nothing to take once E holds an option: upgrades are not built (B6).
- Per-role sets are in for the SWORD (step 100). The axe and the bow keep one set each: no shaped handle gives them a role yet (your "the axe has none yet").
- Picks taken from the old one sword pool that the handle's own set does not hold read as EMPTY and are free to choose again.
- A respec's cost once testing is over; the 99 curve and its hours (before the public demo, with a wipe).

**Armor** (`ARMOR_PREP.md` §0; this run builds it with placeholders, §2 below)
- The parts: plates + which secondary parts (three trait-bearing parts a piece).
- The traits: which, on which part (Padded and Warded to the lining?). The run leaves every armor trait pool EMPTY.
- What makes lighter armor worth wearing (the combat triangle).
- The materials' tiers and the numbers: slot shares, tier values, K (67 today, `regents.defense_k`).
- A second piece worn in a taken slot SWAPS, the old one staying in the bag (the agent's call, as weapons do): or should it refuse?
- Leather and cloth are as strong as metal of the same tier for now (what makes lighter armor worth wearing is yours); linen is made straight from flax (no spinning yet).
- Two pieces of one outfit in different materials (a steel armet with an iron cuirass) wear ONE palette, the chest's: fine, or should each piece keep its own bar (a material per piece)?
- A cloth hat's source (W5: by hand, CC0 or commissioned); a short Steadied after a player's stagger (duels: an idea).

**Towns** (`SETTLEMENTS_PREP.md` §7, §9)
- S1 how many settlements, which sizes, one castle or several. S2 a style per region, or per village.
- S3 the castle's walls: code-made (proposed), the Ruins pack, or a bought kit. S4 snow, moss, soot: by region or season.
- S5 houses placed by hand (proposed first) or a builder. S6 free dye on clothes (done for players: W8).
- S7 interiors: all, or only some. S8 do towns change with play.
- LODs or impostors for far buildings: allowed (the no-LOD rule is for worn pieces only), none built: wanted?
- A saved bake of merged buildings: measured, not built (~80 MB of binaries in git to save ~1 s; the cache took the world from 24 s to 4 s): say if you want it anyway.
- Which roof style where (today: the town hipped, the castle slate bells, the keep turrets); the streets' colors.

**Showcase and login**
- Your look at the re-rendered films; MP4 needs ffmpeg (a download: your yes). Deer have no graze clip; "The line" is wide.
- The forest's colors, the moods, the keep, the login's words: the agent's first pass.

**World**
- 300 bodies IN VIEW cost 22-28 ms a frame on this machine, most of it the body itself (27 draw calls each); merging a far body's pieces would be the lever, but "no LODs" is the foundation's rule: your call, and template work (PROGRESS 98).
- #12 day/night (Sky3D only if yes); how the minimap grows; the ore nuggets' placement (yours, by hand).
- Tree scale, volumetric fog, station lights, the continent's ground; the glade's grass and colors.
- The other skills' minigames; trait ranks: a better-made part, upgrades through use, or both (`MATERIALS.md` §11).
- Names for tiers 4-6, the fibers and the hides.

**The UI rebuild** (`GAME.md`, "THE UI, A REBUILD SOON AFTER ARMOR": each yours to shape first)
- The doll's empty slots show a letter (H, C, L, T), not a picture: a silhouette per slot with the rebuild?
- 1 the inventory (drag, drop, resize). 2 C, the character sheet. 3 one look for every window. 4 the bar's keys reordered.

**Art and the AI audit** (`AI_ASSET_AUDIT.md`)
- Replacing the AI-made continent map and its terrain: how (by hand, code-made, commissioned).
- The code-made gray area (generator scripts an AI wrote): disclose or not, read strictly.
- Herbalism dyes for armor's cloth and leather; hats.

## 2. Placeholders this run made (fill in; each says where)
- THE VILLAGE'S PROPS: how many houses get vines, a fenced yard, crates, a wagon, the yard's depth; which places wear them (only the town world's village now): `game/regents/town/dressing/village.tres`.
- THE WEAPON POOLS, all stand-ins (names, numbers, what each really does): sword E Flurry, Hamstring Cut, Shield Bash, R Execute; axe E Hamstring Chop, Skull Splitter, Shoulder Shove, R Whirlwind; bow Q Point-Blank Shot, E Pinning Shot, Kick Away, Quick Shot, R Arrow Volley; staff R Meteor: `game/regents/content/ability/{sword,axe,bow}_*.tres`, `staff_meteor.tres`, `content/spell/staff_meteor.tres`; their slows and shoves in `content/kit/*.tres` `hits`. Whirlwind and Arrow Volley hit every foe in the sweep (`hits_all`).
- The staff's Bolt at 12 damage (was 9), for your feel check: `content/ability/staff_bolt.tres`.
- THE PICKER'S SUGGESTED SWATCHES: the four `starter_*` palettes' colors per slot: `RegentsColors.swatches` in `game/regents/wardrobe/regents_colors.gd`. Keep them or choose your own row.
- ARMOR'S NUMBERS: the slot shares head 2, chest 5, legs 3 (`defense_share` in `game/regents/content/pattern/{armet,cuirass,legplates,hood,jerkin,leather_trousers,robe,cloth_trousers}.tres`); the new materials' tiers: soft leather 1, supple leather 2, linen 1 (`content/material/*.tres`); metal uses copper 1, iron 2, steel 3. Change a number, press Make the table.
- ARMOR'S TRAIT PARTS: every piece names lining, straps, fittings (`trait_parts`), with NO trait offered: which traits, on which part, is yours.
- ARMOR'S RECIPES: plates 2 bars; armet 1, cuirass 3, legplates 2 plates + copper rivets; leather 1 / 3 / 2; linen robe 4, trousers 3 flax; their XP (`content/recipe/`, made by the table).
- THE CLOTH UNDER METAL: the scarf and padding keep the Knight's first colorway (gray, a red scarf) at every bar: `game/regents/wardrobe/palettes/metal_1_copper|2_iron|3_steel.tres`. Pick it per tier, or one for all.
- METEOR'S RING LOOK: the imp's cinder-ring fire colors, so a player's Meteor reads like the imp's ring you must get out of; a color of its own, or keep it (and should a player's fire ring look different from a foe's?): `game/regents/vfx/effects/meteor_ring.tscn` (`color`, `light_color`).
- THE BOLT'S HAND FLASH: its size (0.45 m), sparks (10) and length (0.3 s): `game/regents/vfx/effects/bolt_cast.tscn`.
- THE CHEST ABILITIES: leather's Snare (placeholder) and metal's Shove (placeholder): what each does and its numbers: `game/regents/content/ability/chest_*.tres`, `content/spell/chest_*.tres`.
- THE SWORD'S HANDLE SETS, stand-ins: crossguard Q Shield Bash, options Charge, Hold the Line, ult Bulwark; banner Q Swipe, options Shoulder Check, Banner Sweep, ult Banner Storm; the plain grip keeps Lunge, Flurry, Hamstring Cut, Execute: `game/regents/content/ability/sword_*.tres` (40051-40057 new), claimed per role in `content/kit/sword.tres`. The draft's real mechanics (a mend by a share, a taunt, a guard window) are only imitated.

## 3. To play and look at
- The effects in play: staff, sword, axe, the imp, the skeletons; two instances for another player's Gale and its pose.
- The town lab: 5 Roofs, 6 Places; the town world: 8, 9, 0.
- The showcase films in `export/showcase/2026-11-15/`.
- Step 88, two instances: the other player's Frost Ring, fireball blast, Gale and Blink are thinner and cast no light; your own shake your camera a little when they land near you (`vfx_camera_shake.gd`: 0.25 m, 6-20 m). VFX lab: O shows "as another player sees it".
- Step 99, THE FIRST THING TO PLAY: `admin_give_item <you> 40075 1 500` (an iron cuirass), I: the doll at the top; pick the cuirass, read its words ("Wearing it, you'd take N% less, now M%"), Wear; click it on the doll to take it off; in a fight Wear is refused with its reason.
- Step 100: re-hilt a sword at the workbench (crossguard or banner grip): its Q is that handle's, its picks at 5, 12, 20 that handle's set only.
- Step 97: `admin_give_item <you> 40087 1 0` (a linen robe), `wear <row>` out of a fight, F: Blink. A soft leather jerkin (40082): Snare; an iron cuirass (40075): Shove. With a staff and no robe, F is empty.
- Step 96, two instances: wear an iron cuirass (40075), a copper armet, leather trousers: each sees the other's armor; steel's pauldrons are spiked; a helm hides the hair. `figure_shot.tscn` shows every tier on both bodies.
- Step 94: craft iron plates at the anvil (two iron bars, a shape round), the Iron cuirass at the workbench (three plates, two copper rivets), or `admin_give_item <you> 40075 1 0`; `wear <row>` out of a fight (no doll yet). The workbench lists them under Armor.
- Step 93: the picker (connect screen, or Escape > Character): Peasant M / F, hair, beard, brows, skin, and a color with swatches for main, accent, under, trim, leather. A character saved as Ranger, Wizard, Knight or Noble is now a Peasant. `figure_shot.tscn` shows four players together.
- Step 92 (wearing armor; the practice pieces are gone since step 105): `admin_give_item <you> 40075 1 0` (iron cuirass) and `40078 1 1000` (steel armet), worn from the bag's doll out of a fight; a skeleton's slash lands lower. A database that still holds a 40067 or 40068 counts it as Defense 0 and draws nothing; `take_off` frees the slot.
- Step 91: sword, axe or bow: Q from level 1; at 5 open the weapon's abilities and pick E from three; at 20 R is the ult. A staff at 20: R offers Meteor. `admin_set_item_level` jumps a weapon's level. A bow skill has never been pressed by a real client: tell me how it feels.
- Step 90: F6 on `game/regents/town/town_world.tscn` (up in ~4 s now); 2 or 3: the village's fenced yards, vines, crates, a wagon.
- Step 89: the copper axe at the frontier camp, stand on the line between the two training dummies, Q (Cleave): both lose 12.6.
- Step 87: walk into the frontier camp: the foes and the Drillmaster move at once.
(more as each item merges)
