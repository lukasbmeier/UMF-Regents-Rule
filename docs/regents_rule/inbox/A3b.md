# A3b: INTEGRATION'S CHECK COUNT MADE STEADY
Built (`game/regents/tests/hooks/integration_genre.sh`, the genre's; nothing in the foundation's files):
- FOUND, by reading every check in both files for a count that depends on the run (a check inside a loop over rows,
  a check in a branch only sometimes taken, `[ x ] && assert_ok`), the genre's:
  - EIGHT TIDY-UP LOOPS, one `assert_ok "consume_item ..."` per BAG ROW: iron axe heads (40014), iron axes (40011), the
    order's item (twice), flax (40046), deer hides (40056), wolf pelts (40064), yew logs. Rows of an item that carries a
    quality never stack, so how many rows there are follows a random yield, grade or loot: each loop counted 0 to many.
    Now `put_away ITEM LABEL`: every row consumed silently, then ONE check that none is left (a stronger check than
    "each consume was accepted": a row it missed now fails).
  - THE LOOT PICK-UP, one `pick_up` check per sack on the ground (the loot's roll): now every sack picked up, then ONE
    check that none of yours is left (the next check still compares the bag to the loot).
  - TWO BRANCHES checking only when taken: tree_2 regrown by an admin if it was worked out; a copper pickaxe given
    again if a random order took ours. Now the act is silent and ONE check of the state after runs every time.
  - FOUR XP GIVE-BACKS, `[ "$XP" -gt 0 ] && assert_ok "grant_xp ..."`: now `give_back SKILL XP LABEL`, one check every
    run (given back and accepted, or nothing to give back).
- `COUNT_BY_SECTION=1` prints, at each of the hook's legs (its `# ---` headings and the big ones inside foes and
  armor), how many checks that leg made: `[count] N checks: <leg>` (`tally`, silent otherwise).
- Not a gap: no loop stopped early, no section returned early; the helpers that loop inside (`hits`, `bot`,
  `play_round`, `standin_up`) check a fixed number of times. Every varying check above was a tidy-up or a give-back
  whose number of rows or branch depended on the run, not something the leg should have checked and skipped.
How to play it: nothing to play. `COUNT_BY_SECTION=1 tools\run.cmd tests\integration_test.sh` (the hook's legs; the
foundation's sections need the template change below).
Tested:
- `integration_test.sh` once, under the lock, with `COUNT_BY_SECTION=1` and a TEMPORARY, uncommitted copy of the
  foundation's script carrying the proposal below (deleted after): 1710 passed, 0 failed, exit 0. Per section, the
  foundation's: init seeding 7, client_connected 8, levels 15, worlds and authority 9, per-world ticking 2, heartbeat
  3, items 15, items on the ground 24, chat 10, equip state 17, the look 21, the lobby 12, health 9, npc spawn 10,
  row-level security 5, challenge loop 7, timed press 39, interact + the genre hook 1018, rate limits 4, names 3,
  Tier A 54, actions 26, statuses 35, effects 23, the dodge roll 16, the referee 74, bodies 35, carry 27, pings 11,
  telemetry 11, holds 60, NPC brains 14, bots 20, the match 33, cells 33. The genre's legs: setup 8, THE TUTORIAL 13,
  woodcutting 29, mining 13, the furnace 14, the anvil 16, the workbench 60, the order board 26, a node worked out 10,
  herbalism 32, combat 70, TRAITS 38, POISE 51, ROLES 62, FOES 21, ARMOR 29, THE ROLL 20, DEATH INTERRUPTS 15, YOU SLAY
  IT 27, THE DEER 20, SKINNING 51, THE WOLF 52, SKINNING 5 20, A FOE'S SHOT 8, A PLAYER SLAIN 37, THE YEW BOW 49, THE
  STAFF 171, THE WORLD MAP 11, NO ROLL IN THE AIR 5, THE TUTORIAL (end) 25. The next run's counts, compared with these
  leg by leg, show where any change came from.
- One run only (as asked), so steadiness itself is shown by the reading above, not by two equal totals. Expect a total
  different from 1703 (the old loops' rows): 1710 here.
- NEGATIVE: each new single check fails if a row or a sack is left (`put_away`'s and the sacks' `assert_eq ... "0"`),
  where the old per-row checks passed whatever was left behind; `give_back` fails on a refused grant as before.
Needs on merge: none.
Placeholders made: none.
For Luke: none.
For the rules/handbook: a line for regents-genre.md, if wanted: "AN INTEGRATION CHECK COUNTS ONCE A RUN: never a check
per row of a query or only in a branch sometimes taken; tidy silently, then one check of the state (`put_away`,
`give_back`); `COUNT_BY_SECTION=1` prints each leg's count."
Left for later, THE FOUNDATION'S (for the template, not edited here):
1. `COUNT_BY_SECTION` in `tests/integration_test.sh`: after `check()`, add
   ```
   SEC_AT=0; SEC_NAME=""
   section() {
     if [ "${COUNT_BY_SECTION:-}" = "1" ] && [ -n "$SEC_NAME" ]; then echo "  [count] $((passes + failures - SEC_AT)) checks: $SEC_NAME"; fi
     SEC_AT=$((passes + failures)); SEC_NAME="$1"; TALLY_AT=$SEC_AT
     [ -n "$1" ] && echo "== $1 =="
   }
   ```
   then each of the 37 `echo "== X =="` lines becomes `section "X"`, `section ""` goes just before the
   `echo "$passes passed, $failures failed"`, and `tests/lib/genre_hooks.sh` line 12 (`echo "== $g: $1 =="`) calls
   `section "$g: $1"` too, so a genre hook's checks are not counted inside the section before it (here "interact" showed
   1018: the genre hook's ~950 with it). (`TALLY_AT` lets a genre hook's own `tally` start from its section.) This is
   exactly what the run above used.
2. The same varying-count pattern in the foundation's file, one check per row: `revoke_authority` per registered
   referee (lines ~1194, 1219, 1291, 1598: usually 1 row, more if a referee is left over) and `despawn_entity` per ball
   (~1288). Proposed: the loop silent, then one `assert_eq "$(row_count "SELECT * FROM authority WHERE role = 1 AND
   world_id = 0")" "0" "..."` (and `body_state WHERE owner_id = $MYENT` for the balls).
