# Handoff — UMF Template, 2026-11-14 (1.8.0: the dodge roll; windows that resize and remember)

## Where it stands
- **1.8.0** (DECISIONS #309, #310), started from a Regent's Rule session (Luke: "Lets do some template work on both the roll
  and resizable window"). Committed on main (1a03c2c), NOT PUSHED (the session's
  push was refused by its permission check): `git push origin main` first, then the games can pull it. `umf-template` republished with `--codegen`
  (a new PRIVATE table `roll_state`: add-only, old builds keep playing). NOT shipped to the games yet (`ship_template.sh`).
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

## Next, in order
1. Ship 1.8.0 (and 1.7.5-1.7.8 for the others) with `ship_template.sh`; each game republishes `--codegen`.
2. REGENT'S RULE switches its own roll to the foundation's (its own step, after `git pull template main`):
   - content: `dodge.tres` (40010) ticks `rolls`, `roll_status` = its Rolling (101), `roll_ms` 550, `roll_ms_rule`
     `&"regents.roll_ms"`, `key` EMPTY (= the `dash` action its `bind_keys` puts on Ctrl); `adventurer.tres`
     `dodge_roll` = dodge.tres.
   - server `regents.rs`: drop `may_fight`'s dodge air check (the foundation's); move `fought`'s dodge branch to
     `fn on_roll` (block down, cast ended, swing canceled, combo reset, held/dealt hits taken back with the given
     `seen_us`/`roll_ms`) and REMOVE its `set_status_internal(STATUS_ROLLING)`: the roll's status is now an EFFECT;
     every `status_state.status == STATUS_ROLLING` check becomes `crate::module::is_rolling`; `rules::roll_clears` can
     call `crate::roll::clears`.
   - client `combat_component.gd`: delete `dodge()`, `roll_direction*`, `roll_cooldown`, the air hold, the Ctrl branch
     and `_began`'s dodge branch; connect `RollComponent.rolled` to what a roll cancels; read `roll_until_ms`/`rolling()`
     and the bar's `cooldown()` from the RollComponent; Rolling checks become `StatusComponent.has_effect(101)`.
   - its tests that name `dodge()`/`DODGE_ID`/`STATUS_ROLLING` follow; `combat_playtest.sh` is the proof.
   - windows need no code (its five windows are remembered by their scripts).
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
