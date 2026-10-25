# Handoff — Regent's Rule, 2026-10-24 (this game's half of the 1.0 done; next, the combat deep-dive)

## Where it stands
- **PROGRESS step 22 built, green, committed and pushed** (`c6ce3e9`). Ring interest on, the two
  overrides in, `chunk` on Regent's own placed tables. A reshape, so (Luke's call) the play database
  `regents-rule` was WIPED a second time today (`--fresh --codegen`, then republished keeping data), and
  `shared/game.json` `compat` is 3. No compat-2 build had gone to friends; they need a new export
  (`tools\release.cmd`) before they play.
- **Template 1.1.0 taken** (shipped to all four games the same evening, Luke's say: runs well on weak
  computers, template #282, and the accounts suite's pinned defaults). No schema change, nothing republished.
  Restart the editor once (project.godot gained a line).
- **Suites**: step 22: `cargo test` green, integration 1096/0, skilling playtest 63+7, combat 50. After the
  1.1.0 pull: unit 2628/0, accounts 65/0, render_test.sh all passes (and in Fishing, Fowl Play, DiscGolf:
  unit and render green there too).

## This session
- `game/regents/regents_net_config.tres` (new, on the game's Boot): `interest` RING, Regent's `cell_tables`
  and `follow_tables`. No foundation change was needed (NetConfig already takes a game's cell tables).
- `game/regents/content/rules/regents.tres`: overrides `characters_per_account` 3, `park_offline_s` 30.
- `server/src/game/regents.rs`: `chunk` on gather_node, station, dummy, foe, afk_work, work_result, casting,
  spell_area, burning, wielded, combat_state (the last two gained `world_id`); `place_of`; `follow_place`
  (the `on_place_changed` hook). `genre.tres` world_tables gained foe, wielded, combat_state.
- Tests: the regents suite checks the ring config against the bindings' contract; the integration hook walks
  a player three cells over (weapon and block follow); two timing traps in its traits block fixed (a fresh
  referee, a whole dummy). Negatives: each new check fails when its thing is broken.
- `.claude/rules/regents-genre.md`: how a new table of ours joins the ring. `GAME.md` order of work updated.

## Next, in order
1. **THE COMBAT DEEP-DIVE** with Luke (`GAME.md` order of work (3)): equipment and armour (five slots, stats),
   the server-side cast queue, crits (then Keen on steel rivets), NPC tiers; movement feel (orbit a still
   character, blended diagonal strafes).
2. The in-game lookup (`GAME.md` "The in-game lookup"): look into it with Luke first.
3. Herbalism and the economy.
- Later, from step 22: a player's own records (`skill_xp`, `recipe_log`, `spell_cooldown`, `order_filled`,
  `foe_kill`) still go to everyone; "your own only" needs a template query (the 1.0 doc's `inventory_item`
  item). The 300-bot test decides whether it matters.

## Waiting on Luke
- The SpacetimeAuth client id (`shared/game.json` `sign_in`): the 3 characters per account need a sign-in.
- Open: trait ranks; #12 day/night; how the minimap grows; the ore nuggets' placement; gear XP numbers.

## Watch out
- The integration hook's CLI referee is online only 5 s after its claim: a block of checks that takes longer
  needs a fresh referee (revoke, offer, claim), as the later trait blocks do.
- `TaskStop` on a background suite stops the shell, not its children: the suite kept running and shared the
  test database with the next one. Let a suite finish, or kill its processes too.
- The skilling playtest's count moves (61 or 63) with how its rounds went (Make all, Stop): not a failure.
- `session_member` bind warnings for entities 36-39 in the playtests are the CLI's own players, in both modes.
- Older traps still hold: a digit after `_` in a reducer name; list hints are the element's type; the CLI
  runs array numbers together; Python reads files as Windows-1252 unless told UTF-8; `NodeDef` and
  `RuleOverride` are `@tool` scripts (never rewrite one under Luke's open editor).
