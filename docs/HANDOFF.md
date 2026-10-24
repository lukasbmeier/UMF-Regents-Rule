# Handoff — Regent's Rule, 2026-10-23 (materials steps 1-3, the Tester page, Luke's crafting feedback)

## Where it stands
Steps 17-21 built, NOT committed (last commit: the template merge `ded24b3`); Luke commits. Published to the
play database `regents-rule` with `--codegen`, data kept: a friend's build needs a NEW EXPORT (new reducers:
the four `admin_*`, `craft_choosing`, `set_craft_grade`, `refit`; new tables `craft_choice`, `craft_grade`).
Suites green: regents unit 2469/0, native `cargo test` all (regents 35/0), integration 1051/0,
skilling playtest 63/0 + 7/0, combat playtest 50/0, content 18/0, `cargo check` (wasm) clean.
The internal wiki is its own project, `UMF ALL\Regents Wiki` (another session; `wiki.cmd` rebuilds it from
this repo's bake; not committed).

## This session
- The materials deep-dive (`docs/regents_rule/MATERIALS.md`) and steps 17-20 (the material table; copper,
  iron, steel; the Tester page; the crafting rework): PROGRESS has each.
- Step 21, after Luke's first look: the head picked by grade, plainer traits, rivets as a pattern with
  traits, every part a tool trait and a weapon trait, Refit (swap a made item's parts at a cost), tooltips.
- The order of work, Luke's answers and his confirmed defaults: `GAME.md`.

## Next, in order (Luke, 2026-10-23)
1. Done: Luke signed crafting off (2026-10-23). Later: the minigames harder, so the grades take skill.
2. NOW (a session started 2026-10-23 in `../UMF Template`): THE TEMPLATE 1.0 WITH ACCOUNTS, in `../UMF Template` (its own session): `chunk` on the positional tables,
   chunked subscriptions and streaming (M18, M19), SpacetimeAuth accounts and characters that outlive a
   machine (M23, #13). One wipe of every game's database; then pulled here (and into the other games).
3. THE COMBAT DEEP-DIVE with Luke: equipment and armour (five slots, stats), the server-side cast queue,
   crits (then Keen on steel rivets), NPC tiers; movement feel (orbit a still character; diagonal strafes).
4. THE IN-GAME LOOKUP (Luke, 2026-10-24; `GAME.md`, "The in-game lookup"): look into it with Luke first,
   then build the glance line, the detail card (`???` until found: a new add-only "found" table) and the
   skill guides. No in-game handbook (the wiki covers it). Open: chances as numbers or words; what `???`
   hides; the key (Q is taken).
5. Herbalism (fibre bindings, tier 4-6 / fibre / hide names) and the economy (marks, vendors).
- Small, any time: the minimap's north-up / turning choice.

## Waiting on Luke
- His look at step 21. Open: trait ranks (both paths liked; harder minigames first, AFK must still pay);
  #12 day/night; how the minimap grows; the ore nuggets' placement; gear XP numbers (MATERIALS step 5).

## Watch out
- SpacetimeDB renames a reducer with a digit after `_` (`craft_v2` -> `craft_v_2`): avoid it.
- A list argument's type hint to the SDK is its element's (`"u32"`), never `"vec_u32"`.
- The CLI's SQL prints an array's numbers run together (`[40016,40012]` is `4001640012`).
- The unit suite cannot see what a call sends on the wire (offline it fails first): the playtests do.
- A crafted head's grade in the integration suite is whatever its round scored: tests clear heads first.
- Python on this machine reads files as Windows-1252 unless told UTF-8 (the wiki's ‰ "bake bug" was this).
- The ability bench's cooldown check (template suite) is timing-sensitive: it failed once in five runs.
- Setting an untyped Array on a typed exported array through `Object.set` silently does nothing.
- A headless `-s` script that NAMES a content class compiles before the autoloads: load it by path.
- `frontier.tscn` gained coal markers: reload the level in an open editor before saving there.
