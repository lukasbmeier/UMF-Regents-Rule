# Handoff — Regent's Rule, 2026-10-21 (end of the second session)

## Where it stands
Step 16 (telemetry, the polish round, and the fixes after Luke's first play of it) is built. The SERVER
part is published to the play database `regents-rule` (`--codegen`, data kept: a friend needs a NEW
EXPORT). The fixes since (hit loop, collisions, ore layouts, skeleton facing) are client only: Play picks
them up, no republish. NOTHING of step 16 is committed yet. Luke's call (2026-10-21): once he has confirmed
the fixes in play, commit and push ALL of it, his own grip edits, adventurer AnimationSet and texture
imports included, and ship the template to the other games. The template merges are committed (`9e6a166`).
Suites green: unit 2391/0, native all, integration 931/0, telemetry 21/0, skilling playtest 62/0 + 7/0,
combat playtest 50/0, content 18/0.

## This session
- Telemetry: the chronicle (template #276) keeps every change and a place every 5 s in
  `build/telemetry/regents-rule.sqlite`; `tools\telemetry.cmd` shows it; Regent's panels in
  `shared/regents/telemetry.json`; the meta in the database (`meta_tally`, `meta_share`, the 45 % alarm).
- Polish: vitals, work bar, Make 1 / X / all, the minimap, hit flashes (`regents_hud.gd`, `ui/`,
  `combat/hit_feedback_component.gd`).
- After Luke's play: the hit reaction looping (template #277); every rock, station and level prop solid
  (`solid.gd`, `levels/solid_props.gd`); ore layouts per rock model to place by hand
  (`skilling/mining/ore/`); skeletons turned to face forward. PROGRESS step 16 has all of it.

## Next, in order
1. Luke confirms the fixes in play, then: commit everything (his files too), push; `ship_template.sh`
   for Fishing, Fowl Play and DiscGolf (it needs every game clean: this one will be, after the commit).
2. **THE MATERIALS AND TINKERS' DEEP-DIVE** (Luke's next session). Read first: `RULE_DESIGN.md` §7.4
   (gear is modular: a core sets base stats and tier, a handle or hilt its trait; gear XP; durability and
   repair as the material sink), `LOOT_AND_STYLES.md` §0 (Tier = the material level, sets the power band;
   Grade; Power; Trait), its §2 and §6 (traits; handles give theirs always), §9 (all standard gear is
   crafted; drops give materials and components; salvage), and `GAME.md`'s Traits call (oak Steady, yew
   Springy are toned to the early game UNTIL this deep-dive).
   What exists now: woods (logs, oak, yew), ores (copper, iron) and bars, one handle per wood (plain,
   oak 40016 Steady, yew 40017 Springy), cores (iron axe head, iron sword blade), assembled tools and
   weapons (bronze axe and pickaxe from the starter kit; iron axe, iron sword; yew bow, yew staff); an
   item's instance data holds its quality, handle and traits (`{"q","h","t"}`). Recipes:
   `game/regents/content/recipe/`; items: `content/item/`; tiers and Power: `server/src/genre/regents/`.
   Questions for Luke, not to default: which materials per tier and how many tiers in v1; what a material
   changes (only Power through tier, or traits too, as handles); whether cores take a material trait;
   gear XP and durability now or later; where rarer materials come from (nodes, drops, salvage).
3. Then `LOOT_AND_STYLES.md` §10's list: salvage and components, the reagent cost hook, the teleport spell.

## Waiting on Luke
- His play of the fixes (hit loop, collisions, the ore, skeletons); placing the nuggets in the layouts.
- The materials deep-dive's questions (above). Open items: #10 hosting, #12 day/night, the other skills'
  minigames, the bow's draw scaling, how the minimap grows.

## Watch out
- `frontier.tscn` gained a `SolidProps` node: if the editor has the level open from before, reload it
  before saving there, or the editor's copy drops the node.
- `NodeDef` and `RuleOverride` are `@tool` scripts: never rewrite one while Luke's editor is open.
- A windowed Godot run strips one blank line from `project.godot` `[rendering]`: put it back.
- The editor's Play starts `chronicle.py` (Python on PATH); it stops a few seconds after the game.
- The minimap zooms with the wheel only while the cursor is free (a window open, Alt).
