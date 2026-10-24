# Handoff — Regent's Rule, 2026-10-24 (the template 1.0 taken; next, this game's half of it)

## Where it stands
- **The template 1.0 is taken** (2026-10-24): cells (`chunk` on every placed row, one movement helper),
  ring interest, streamed levels, SpacetimeAuth accounts (`../UMF Template/docs/TEMPLATE_1_0.md`, template
  DECISIONS #278-#281; 1.0.1: the suites' sign-in keys one per machine). This game's database was WIPED once
  and republished `--fresh --codegen`, `compat` 2: older builds are refused, friends need a new export
  (`tools\release.cmd`). Guests play as before; signing in waits on the SpacetimeAuth client id in
  `shared/game.json` `sign_in`.
- **Committed and pushed** (`5c053d1`, up to date with origin). Steps 17-21 (materials, crafting, the Tester
  page) are in `221db3c`; PROGRESS has each.
- **Suites after the pull**: unit 2533/0, e2e 11, accounts 65, skilling playtest 63+7, combat playtest 50
  green; integration 0 failed on its third run (the first two failed one check each, different ones: the
  hook's random order and timing, not the 1.0). Its pickaxe check now survives an order that took the pickaxe.
- **Running alongside**: a template session on low-end GPU performance (shaders, quality presets, renderer);
  every game gets it on its next pull. Game work here can go on in parallel.
- The internal wiki is its own project, `UMF ALL\Regents Wiki` (`wiki.cmd` rebuilds it from this bake).

## Next, in order (Luke, 2026-10-23/24; `GAME.md` "The order of work")
1. **This game's half of the 1.0** (small, start here):
   - switch to ring interest: `NetConfig.interest = RING`;
   - the genre's overrides: `characters_per_account` 3, `park_offline_s` 30 (a character that goes offline
     stays parked where it was for 30 s);
   - decide which of Regent's own tables follow a cell (its placed things: `gather_node`, `station`, `foe`,
     `dummy`, ...; `ground_item` already has one) and make them cell tables as the 1.0 doc says.
   Then the suites (unit, integration, both playtests) and a publish.
2. **THE COMBAT DEEP-DIVE** with Luke (as the materials one was): equipment and armour (five slots, stats),
   the server-side cast queue, crits (then Keen on steel rivets), NPC tiers; movement feel (orbit a still
   character without turning it; diagonal strafes that blend).
3. **THE IN-GAME LOOKUP** (`GAME.md` "The in-game lookup"): look into it with Luke first; then the glance line,
   the detail card (`???` until found: a new add-only "found" table), the skill guides. No in-game handbook
   (the wiki covers it). Open: chances as numbers or words; what `???` hides; the key (Q is taken).
4. **Herbalism** (fibre bindings, tier 4-6 / fibre / hide names) **and the economy** (marks, vendors).
- After those: writs, potions, death and shrines; party, duels, the lair and the Undercroft; the 300-bot test.
- Small, any time: the minimap's north-up / turning choice.
- From the 1.0, later, each waiting on something: renewing a sign-in's token before a reconnect (needs
  SpacetimeAuth set up and its token lifetime); moving a returning character off a spot no longer standable
  (with death and shrines: the same "safe place to stand" rule); nine cell queries or one combined (the
  300-bot test decides; the code supports both).

## Waiting on Luke
- The SpacetimeAuth client id (`shared/game.json` `sign_in`) for signing in.
- Open: trait ranks (both paths liked; harder minigames first so the grades take skill, AFK must still pay);
  #12 day/night; how the minimap grows; the ore nuggets' placement; gear XP numbers (MATERIALS step 5).

## Watch out
- The integration hook's checks run in a random order with real timing: one check can fail on a run and pass
  the next. Rerun before chasing; a check that fails twice is real.
- SpacetimeDB renames a reducer with a digit after `_` (`craft_v2` -> `craft_v_2`): avoid it.
- A list argument's type hint to the SDK is its element's (`"u32"`), never `"vec_u32"`.
- The CLI's SQL prints an array's numbers run together (`[40016,40012]` is `4001640012`).
- The unit suite cannot see what a call sends on the wire (offline it fails first): the playtests do.
- Python on this machine reads files as Windows-1252 unless told UTF-8.
- Setting an untyped Array on a typed exported array through `Object.set` silently does nothing.
- A headless `-s` script that NAMES a content class compiles before the autoloads: load it by path.
- `frontier.tscn` has coal markers and `SolidProps`: reload the level in an open editor before saving there.
- `NodeDef` and `RuleOverride` are `@tool` scripts: never rewrite one while Luke's editor is open.
