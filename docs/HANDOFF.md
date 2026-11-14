# Handoff — UMF Template, 2026-11-14 (1.8.2: the referee reads effects; 1.8.1: windows scroll; 1.8.0: the roll, windows)

## Where it stands
- **1.8.2** (DECISIONS #312): the referee reads effects (a rolling player was reported hit and the module refused it,
  so Regent's never heard the miss), and `resolve_action` answers a hit on someone who cannot be hit as a MISS, not an
  error. Committed on main, not pushed; 1.8.0 and 1.8.1 were pushed by Luke and shipped to all four games.
- **1.8.1** (DECISIONS #311, client only): a window scrolls what it cannot show (Luke, via Regent's Rule: the bag's long
  descriptions). Pushed and shipped.
- **1.8.0** (DECISIONS #309, #310), started from a Regent's Rule session (Luke: "Lets do some template work on both the roll
  and resizable window"). Committed (1a03c2c), pushed by Luke and shipped to all four games
  with 1.8.1. `umf-template` republished with `--codegen` (a new PRIVATE table `roll_state`: add-only, old builds keep playing).
- Green: `tests/run_tests.sh` 2466/0 (the `content` project-task check passed this time too), `cargo check --target
  wasm32-unknown-unknown`, `cargo test` (new `server/tests/roll.rs` 8/8), `tests/integration_test.sh` 699/0 (its first run
  failed two of the new checks on CLI timing, a 550 ms roll gone before the next read and a referee still registered;
  both fixed, rerun green).
  Mutations checked: the roll's late window, the air hold's timestamp, a window's minimum, a remembered reopen.

## This session
- THE DODGE ROLL (#309): `AbilityDef` "A dodge roll" (`rolls`, `roll_status`, `roll_ms`, `roll_ms_rule`, `roll_in_air`; baked
  only on a roll), `EntityDefinition.dodge_roll` (baked only when set), `foundation/components/roll_component.gd` (given to
  every entity, `SpaceTimeEntity._ensure_status_component`), `server/src/roll.rs` (pure) + `server/src/module/rolls.rs`
  (`may_roll`, `begin_roll`, `rolled_clear`, `is_rolling`, `roll_state`), `Genre::on_roll`, `resolve_action` judging a
  referee's hit by when the roll was pressed. Content: Dodge roll (ability 1), Rolling (status 7); hot rules
  `foundation.roll_ms` (550), `roll_late_ms` (50), `roll_hold_ms` (1500). `HotRules.has_rule`. The humanoid is NOT given
  the roll (no game's dash key changes until it opts in).
- WINDOWS (#310): `foundation/ui/kit/ui_window.gd` resizes from edges/corners (min, on screen), remembers place and size per
  `place_id()` in `Settings` (`window_place` etc., `user://settings.cfg` `[windows]`), double-click the bar resets;
  Settings > Game > "Remember where windows are". `tests/render_test.sh` draws no UiWindow: not touched.
- Tests: `tests/suites/roll.gd`, `tests/suites/ui_window.gd` (both in `test_runner.gd`), the integration suite's "dodge roll"
  section and its referee section's roll checks. HANDBOOK (movement, windows, the character recipe), CHANGELOG 1.8.0.

- 1.8.1 SCROLLING (#311): `UiWindow.content` sits in `scroller` (a ScrollContainer); the window grows itself to what it
  holds (`_grow_to_content`, on `content.minimum_size_changed`) up to the screen less `SCREEN_MARGIN` and scrolls past;
  a player's size is kept and scrolls; the resize minimum is now `size_min`. A scroll restore of our own proved
  redundant (mutation: Godot keeps it on a one-frame refill) and was removed; the suite guards the behaviour.

## Next, in order
1. Push 1.8.2 (Luke), then ship it (`ship_template.sh`): every game republishes (module and referee).
2. Regent's Rule has moved its roll onto the foundation's (done in its own session, 2026-11-14); after 1.8.2 its
   combat_playtest's yard (the tutorial's "roll through") should pass again. The adoption list for any other game is
   in `docs/HANDBOOK.md` (the movement section and the character recipe).
3. From before: the SDK btree patch upstream (ask Luke); effects' own presentation; a region referee's load.

## Waiting on Luke
- From before: how many strips the expanse runs by default; the SDK fix upstream; the bandwidth budget.
- Whether the greybox humanoid should roll by default (left off so Fishing/DiscGolf/Fowl Play keep their dash key).

## Watch out
- `ConfigFile.get_value(section, key, null)` with a missing key is an ENGINE ERROR (null is "no default"): check
  `has_section_key` first (`Settings.window_place`).
- PowerShell `Start-Process bash -ArgumentList '-c', "<cmd with spaces>"` loses the quoting: run a script file.
- A suite's `SpaceTimeEntity` gets its `entity_id` AFTER `add_child` (hard rule 8's assert in `_ready`).
- From before: a freed node `as`-cast crashes a release build; `release.sh` packs what is on disk; `run_tests.sh` takes no
  arguments (`-- --only=x` on the runner scene runs one suite).
