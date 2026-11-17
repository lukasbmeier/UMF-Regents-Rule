# M9FIX: THE FOUR INTEGRATION FAILURES
Branch `claude/m9-integration-fixes` (from `main` 1feb2d3d). Not pushed. All four were TESTS (stale numbers, or a leg that
depended on what ran before it); no code changed. One file: `game/regents/tests/hooks/integration_genre.sh`.

1. "12 at the copper axe's 70 %: 8.4 (no traits)": got 8.47.
   CAUSE: Axemanship rank 2 (x1.0084, `mastery_bp(2)` = 84). The leg's numbers are at rank 1; S1's new Cleave leg (Cleave on
   two dummies, earlier in the same section) paid enough axemanship XP to reach rank 2 on the 1-33 curve.
   FIX (test, its own state): the traits leg sets Axemanship 1 (`admin_set_rank`) before its first chop, and afterwards puts
   back the XP from before the leg plus what the leg itself earned (`admin_set_rank 1` + `grant_xp`), so every later leg
   sees the same XP as before the fix. The checks (8.4, 7.56) are unchanged.
2. "Brutal ... a tenth less (8.4 -> 7.56)": got 7.62. CAUSE: the same rank 2 (7.56 x 1.0084). FIX: the same.
3. "its 7 (14 at the skeleton's 50 %) x 67 / (67 + 20 + 12) ...": got 2.707. NOT A CODE BUG.
   CAUSE: my S2 leg's expectation was wrong. The integration's skeleton swings ability 40001, the SWORD kit's Slash (8
   damage), so it lands at 8 x 50 % = 4, not the 14-damage cut in ARMOR_PREP's table (another foe's). 2.707 is exactly
   4 x 67 / 99: the cuirass (20) and the helm at quality 1000 (12) added up to 32, as built. The combat playtest's armor leg
   reads each foe's hit from content (`FoeDef` x its kit), which is why it always measured right.
   FIX (test): the leg compares against the SAME slash measured unarmored earlier in that section (PHP0 -> PHP1; checked to be
   4.0), times 67 / (67 + 20 + 12): no number copied from a sheet.
4. "the Bolt's 9 (150 -> 138)": CAUSE: P1 raised the Bolt to 12 (step 91) and did not move this expectation (138 = 150 - 12).
   FIX (test): the expected damage is the server's own `ability_def` row for 40012 (at the yew staff's 100 %, no quality,
   Sorcery 1), checked to be above 0, instead of a constant.

Tested: `tests/integration_test.sh` (the whole suite: the genre hook cannot run alone, it needs the suite's earlier set-up),
once, under the lock: **1761 passed, 0 failed**, every section ran (the same section headers as the M9 run). The total differs
from the M9 run's 1770 (1766 + 4): the suite counts checks inside loops over bag rows (heads put away, an order's items, a
round's results) whose lengths vary from run to run; nothing was skipped. Log:
`C:\Users\Luke\AppData\Local\Temp\claude\9f8cd82389d3f1b5\59ed792e-4669-46cd-8faf-cd0c77f150f2\m9fix_integration.log`
(the session's TEMP; it prints failures only).
Needs on merge: none (a test file only; no re-bake, no codegen).
Placeholders made: none. For Luke: none.
For the rules/handbook: an integration leg that measures a number sets its own state (ranks, rules) or reads its expectation
from the server's rows; never a number that an earlier leg or a content change can move.
