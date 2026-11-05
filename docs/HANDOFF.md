# Handoff — Regent's Rule, 2026-11-05 (the minigame prep sheet, revision 2: PROGRESS 39)

## Where it stands
- Pushed through step 38 (`b0fac474`). Step 39's first version committed (`13d16e99`), not pushed.
- **NOT committed**: revision 2 of the sheet, docs only: `MINIGAMES_PREP.md`, `GAME.md`, `CLAUDE.md`, PROGRESS 39,
  this file.
- Play database `regents-rule`: as published after step 36. Step 38's rebaked manifest goes out with the next publish.
- Suites: unchanged since step 38 (unit 3138/0, `cargo test --test regents` 45/0; integration 1298/0 at step 37).
  Nothing run for 39 (no code or content changed).

## This session
- The minigame overhaul's prep sheet, `MINIGAMES_PREP.md`: §1 where the four built minigames stand (what each score
  pays, the tier ladder, cost, the look); §2 every coming skill in five model families, one minigame per craft;
  §3 tiers "harder but similar" (one game a skill, a new thing per band, rank easing the round); §4 what a score is
  worth; §5 the look (2D re-skin / in the world / a 3D stage in the panel) and assets (Gemini as mockups only);
  §6 a difficulty readout; §7 decisions M1-M10 with proposed answers; §8 the order of work.
- Revision 2 (2026-11-05): an outside review checked against the code and folded in (§9: taken and not); §3.1 two
  anvil strikes, rhythmic bellows, sound; §4.1 the core alone sets an assembled item's quality; §5.3 gathering's
  rounds back to back in a side panel (hands free once started, a second note); M11-M12.
- Found: a round scored 80 % pays exactly AFK; assembly takes the BEST input's quality; smithing's tiers are identical; bars, grips, bows and staves have no quality; rank never changes a round;
  the copper/steel heads' and the sword blades' rounds are titled "Iron ..." (params `display_name`).

## Next, in order
1. Luke answers M1-M12 (`MINIGAMES_PREP.md` §7); his answers go to `GAME.md`.
2. `MINIGAMES_PREP.md` §8 step 1: the difficulty readout (simulated players, grade shares per tier and rank, pinned in
   the unit suite, shown in the lab), the round titles fix, assembly's quality from the core only (M12).
3. §8 step 2: the look on smithing (M7's choice), for Luke to play; then smithing's ladder, the other three, carving.
4. Then herbalism and hunting; armor after (`ARMOR_PREP.md` §0).
5. Still owed: run `load_300.sh` once, watching for `[Sidecar] a walk map ... again` piling up.

## Waiting on Luke
- M1-M12 (`MINIGAMES_PREP.md` §7); in particular M11 (revisits his 1.25x edge), M12, M2 (does "copper, iron tier 1, steel+ tier 2" replace 2026-10-18's
  bands 1-3 / 4-5 / 6), M7 (the look) and M8 (paid packs, AI-generated art).
- From before: "Cancelled." on the connect screen (a template change); where combat steps 5-7 and the lookup go;
  the tutorial's words; PROGRESS 30's list; a loot table with swords; which foes are bosses.

## Watch out
- The minigame UIs only draw their models: a new look must not touch a model, a Rust twin or a golden. A new
  mechanic in a model is add-only params defaulting off (today's rounds replay unchanged), or a new challenge kind.
- New text and names in American spelling; never rename the kept British names (`.claude/rules/regents-genre.md`).
- Python here writes through Windows text mode: open with `newline=""` to keep LF.
- A heredoc through Git Bash can mangle backslashes in Python source: write patch scripts with the Write tool.
- `RegentsContent` caches in a running game: a test that writes content uses `ContentLibrary.root_override` or
  `RegentsContent.clear()`.
- Never run two server suites at once; never kill all Godot/Python processes, by PID only.
