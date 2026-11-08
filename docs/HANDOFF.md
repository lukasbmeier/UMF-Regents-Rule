# Handoff — Regent's Rule, 2026-11-07 late (the minigame overhaul's steps 45-49; herbalism step 1; the crash fixed)

## Where it stands
- Committed and pushed (the crash-hunt session): template 1.7.5 and 1.7.6 merged (`7c157b36`, tools and docs only),
  then 1.7.7, THE CRASH FIX (`b5734b98`, client only: no publish, no codegen; DECISIONS #308: the next chat line from
  someone whose bubble had gone cast its freed label, a silent crash in a release export). THE FIXED RELEASE IS MADE
  (2026-11-08, from a clean worktree of `b5734b98`, export 34/0): `build/releases/Regent's_Rule-331b21db0518-1.7.7.zip`
  and `-1.7.7-mac.zip` (the same fingerprint as the 2026-11-06 zips, which still crash: send the 1.7.7 ones). The
  checked-in compat snapshot already covers it (only its "saved" time differed). The fixed DEBUG build is beside them.
- NOT committed (Luke commits): this session's steps 45-50 (the minigames, then herbalism step 1). Published to the play
  database `regents-rule` (no wipe, no codegen), last after step 50.
- Left uncommitted ON PURPOSE: Luke's editor (13 `.png.import`, `game/regents/anim/adventurer.tres`); `shared/compat/`
  untracked (the 2026-11-06 release snapshot: Luke commits it).
- The test database is free (2026-11-08): the combat-check session (`local_f713a566`, branch
  `claude/compassionate-panini-246b25`) and the crash session's release are done, then this work's reruns.
- Suites on this tree: cargo green; unit 3237/1 (the 1: the content dock's "project task" check, Git Bash taking 8 s
  to start a script while the machine was loaded; it passes on a quiet machine). Integration 1315/10 (2026-11-08):
  every step 45-50 check passes; the 10 are the referee-paced combat checks and the foundation's referee and hold
  checks (they fail on `54c1973b` too: the combat-check session's task). Skilling playtest 94/0 + 8/0.

## This session
- 45: smelting is a rhythm track (kind `beat`, 104). 46: rounds back to back; pay 0.75-1.25 of AFK; rares by score.
- 47: rank eases a round (4 % x 3 ranks). 48: band 2's tests (knots, brittle notches, slag).
- 49: WOODWORKING'S CARVE, its own game (kind `carve`, 105): a vertical stave, wood off either side; the yew bow an
  UNSTRUNG C bending left or right by the seed; the staff.
- 50: HERBALISM STEP 1 (Luke answered H1-H11 of `HERBALISM_HUNTING_PREP.md`, `GAME.md`): flax pulled AFK with a
  TROWEL (no round yet), the trowel in the material table (a copper one in the starter kit), the spinning wheel (a
  placeholder block), the bowstring, STRINGING the carved stave into the yew bow; flax in the glade and 64 patches on
  the continent from their own random stream (every point before unmoved).
- Woodcutting's difficulty stays (Luke: "takes skill and precision").

## Next, in order
1. Herbalism step 2: PULL THE ROOT (`HERBALISM_HUNTING_PREP.md` §3, H3): a Tension model, its twin, goldens, a stage.
2. Then the deer (§7 step 3: the animal pack's rig, a flee brain), skinning, the wolf and the fang charm (H9).
3. Luke plays steps 45-50; tuning to M4's shares after his play. Send friends the 1.7.7 zips.

## Waiting on Luke
- His play of 45-50 (the carve, the rhythm smelt, runs and pay, band 2's tests, flax and stringing).
- A trowel model and a spinning wheel model (none in the packs); a pulling clip (needs `adventurer.tres`, his editor's).
- Whether his existing character gets a copper trowel by an admin grant (new characters get one; old ones smith it).

## Watch out
- CHECK THE TEST DATABASE IS FREE BEFORE A SERVER SUITE: the session list showed the combat session "idle" while its
  integration runs were on the database (its stopped task's children kept running). Ask the other session first.
- Publish the play database as soon as a playable change lands (Luke tries things mid-session).
- `export_test.sh` (so `release.sh`) used to run its client on whatever `regents-rule-test` held and fail on another
  session's leftover entities: template 1.7.8 (merged) publishes its own server fresh first.
- `integration_test.sh` / `skilling_playtest.sh` republish the test database from the source at their start, and the
  hook's bot loads scripts live: never edit code while one runs.
- The hook's `logged` helper is defined part-way down `integration_genre.sh`: a check above it cannot use it.
- A negative test on a NEW file: back it up first. Nearby small seeds draw alike: step seeds `1 + i * 7919`.
- `-s` script mode loads no autoloads: a windowed shot that needs them is a scene in `build/` (ignored).
- `ease`, `sign` are GDScript globals. Heredocs with Python patch strings break: write them with the Write tool.
