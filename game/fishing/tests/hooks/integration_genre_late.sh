# FISHING'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, sql_first...). Moved verbatim (the template split).

echo "== gear and the shop =="

MYENT="$(sql_first "SELECT entity_id FROM player" 1)"
MYSESS="$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)"

# Give the angler something to spend without fishing for it: `add_score` is authority-only and
# the admin is an authority, which is exactly the hook a genre's economy is meant to use.
assert_ok "set_session_phase $MYSESS 1" "put the session in PLAYING"
assert_rejected "buy_upgrade 0" "only open between rounds" "the shop is shut while a round runs"

assert_ok "set_session_phase $MYSESS 3" "advance to the SHOP phase"
assert_rejected "buy_upgrade 9" "unknown gear kind" "an unknown gear kind is refused"

# The angler has been fishing earlier in this run, so empty the purse rather than assuming it is
# empty — otherwise this section asserts how many fish that section happened to land.
rod_now() { local t; t="$(sql_first "SELECT rod_tier FROM gear WHERE entity_id = $MYENT" 1)"; echo "${t:-0}"; }
coins_now() { sql_first "SELECT coins FROM session_member WHERE entity_id = $MYENT" 1; }
# `--` so the CLI does not read the leading minus as a flag, as the health section does.
spacetime call -- "$DB" add_score "$MYENT" 0 "-$(coins_now)" >/dev/null 2>&1
assert_eq "$(coins_now)" "0" "the angler is broke"
rod_before="$(rod_now)"
assert_rejected "buy_upgrade 0" "costs" "a rod you cannot afford is refused, with the price"
assert_eq "$(rod_now)" "$rod_before" "and a refused purchase does not raise the tier"

before="$(coins_now)"
assert_ok "add_score $MYENT 0 500" "credit the angler 500 coins"
assert_eq "$(( $(coins_now) - before ))" "500" "the coins arrived"

before="$(coins_now)"
assert_ok "buy_upgrade 0" "buy a rod"
assert_eq "$(sql_first "SELECT rod_tier FROM gear WHERE entity_id = $MYENT" 1)" "1" "rod is tier 1"
assert_eq "$(( before - $(coins_now) ))" "40" "and 40 coins were spent"
assert_eq "$(sql_first "SELECT line_tier FROM gear WHERE entity_id = $MYENT" 1)" "0" \
  "buying a rod does not raise the line"
assert_eq "$(sql_first "SELECT reel_tier FROM gear WHERE entity_id = $MYENT" 1)" "0" \
  "or the reel"

before="$(coins_now)"
assert_ok "buy_upgrade 1" "buy a reel"
assert_ok "buy_upgrade 2" "buy a line"
assert_eq "$(( before - $(coins_now) ))" "80" "each first tier costs 40"
assert_eq "$(sql_first "SELECT reel_tier FROM gear WHERE entity_id = $MYENT" 1) $(sql_first "SELECT line_tier FROM gear WHERE entity_id = $MYENT" 1)" \
  "1 1" "each on its own track"

# Prices climb, and the top tier is a wall.
before="$(coins_now)"
assert_ok "buy_upgrade 0" "rod tier 2"
assert_eq "$(( before - $(coins_now) ))" "110" "tier 2 costs 110, not another 40"
assert_ok "buy_upgrade 0" "rod tier 3"
assert_ok "add_score $MYENT 0 1000" "top the angler up"
assert_ok "buy_upgrade 0" "rod tier 4"
assert_eq "$(sql_first "SELECT rod_tier FROM gear WHERE entity_id = $MYENT" 1)" "4" "rod is maxed"
assert_rejected "buy_upgrade 0" "top tier" "a fifth rod is refused"

# And the gate closes again behind it.
assert_ok "set_session_phase $MYSESS 1" "back to PLAYING"
assert_rejected "buy_upgrade 1" "only open between rounds" "the shop shuts when the next round starts"

echo "== the abandoned cast expired =="
waited=0
while [ "$(row_count "SELECT * FROM challenge WHERE entity_id = $MYENT")" != "0" ] && [ "$waited" -lt 120 ]; do
  sleep 1; waited=$((waited + 1))
done
echo "  pruned $(( $(date +%s) - ABANDONED_AT )) s after the cast"
assert_eq "$(row_count "SELECT * FROM challenge WHERE entity_id = $MYENT")" "0" \
  "the abandoned challenge expired and was pruned"
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "0" \
  "and its public line went with it (the prune path calls on_challenge_closed too)"
assert_eq "$(row_count 'SELECT * FROM fishing_cast')" "0" "and so did the server's record of it"

# =============================================================================
# GEAR CHANGES THE GAME (DECISIONS #118)
# =============================================================================
# Three tracks, three DIFFERENT things, each observable on a cast: the rod how far a float may
# go, the reel how long the hook-set window is, the line how heavy a catch it holds before it is
# a deadlift. The shop section above left the rod maxed; this buys the rest and casts.
echo "== gear changes the game =="
MYENT="$(sql_first "SELECT entity_id FROM player" 1)"
MYSESS="$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)"
assert_ok "use_level 0 1" "back to the lakeside"
assert_ok 'teleport {"x":0.0,"y":0.9,"z":24.0}' "at the end of the dock"
assert_ok "set_session_phase $MYSESS 3" "open the shop"
spacetime call -- "$DB" add_score "$MYENT" 0 5000 >/dev/null 2>&1
while [ "$(sql_first "SELECT reel_tier FROM gear WHERE entity_id = $MYENT" 1)" != "4" ]; do
  spacetime call "$DB" buy_upgrade 1 >/dev/null 2>&1 || break
done
while [ "$(sql_first "SELECT line_tier FROM gear WHERE entity_id = $MYENT" 1)" != "4" ]; do
  spacetime call "$DB" buy_upgrade 2 >/dev/null 2>&1 || break
done
assert_eq "$(sql_first "SELECT rod_tier FROM gear WHERE entity_id = $MYENT" 1) $(sql_first "SELECT reel_tier FROM gear WHERE entity_id = $MYENT" 1) $(sql_first "SELECT line_tier FROM gear WHERE entity_id = $MYENT" 1)" \
  "4 4 4" "everything maxed"
assert_ok "set_session_phase $MYSESS 1" "back to PLAYING"
# ROD: the 54 m cast refused on the starting rod is inside the best rod's reach.
assert_ok "cast $(cast_at 0.0 -30.0)" "a 54 m cast, refused on the starting rod, is accepted on the best"
PAYLOAD="$(fish_payload)"
echo "  the roll: $PAYLOAD"
# REEL: the hook-set window the server grades against is wider.
assert_eq "$(pfield "$PAYLOAD" window_mult)" "1.5" "the best reel's hook-set window (x1.5, the starting reel's x1)"
# LINE: a deadlift is a catch heavier than THIS line holds.
check "$(python -c "
import json; d=json.load(open('shared/fishing/fishing.json'))
print(str(('$(pfield "$PAYLOAD" deadlift)' == 'true') == (float('$(pfield "$PAYLOAD" kg)') > d['gear']['line'][4]['max_load_kg'])).lower())")" \
  "a deadlift is judged against the line being fished with ($(pfield "$PAYLOAD" kg) kg)"
# And the same slow hook-set that was too slow on the starting reel lands on the best one.
BITE="$(pfield "$PAYLOAD" bite)"
CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
CAUGHT_BEFORE="$(row_count 'SELECT * FROM catch')"
fight_for "$PAYLOAD" 1.2 ace
echo "  the fight on the best gear: $FIGHT_OUTCOME in $FIGHT_S s"
wait_out "$BITE" 1.2 "$FIGHT_S"
assert_ok "submit_challenge_result $CID $FIGHT_RESULT" "the same 1.2 s hook-set as before, and its fight"
assert_eq "$(( $(row_count 'SELECT * FROM catch') - CAUGHT_BEFORE ))" "1" \
  "lands with the best reel, where the starting reel lost it"
assert_eq "$(sql_rows 'SELECT id, hookset FROM catch' | sort -n | tail -1 | awk -F'|' '{gsub(/ /,"",$2); print $2}')" "2" \
  "graded LATE (2), not missed"
echo "== the rival angler fishes the round (DECISIONS #169) =="
rival_line() { sql_first "SELECT spot FROM fishing_line WHERE entity_id = $RIVAL_ENT" 1; }
wait_for() {   # wait_for SECONDS COMMAND... : true once the command prints something non-empty
  local until=$(( $(date +%s) + $1 )); shift
  while [ "$(date +%s)" -lt "$until" ]; do
    [ -n "$("$@")" ] && return 0
    sleep 0.5
  done
  return 1
}
reel_in_mine() { spacetime call "$DB" reel_in >/dev/null 2>&1; }
reel_in_mine
assert_ok "set_rival 0 true" "an admin brings the rival back"
# Other suites leave NPCs about: his own private row says which entity he is (the publisher reads it).
RIVAL_ENT=$(sql_first "SELECT entity_id FROM fishing_rival WHERE world_id = 0" 1)
check "$([ -n "$RIVAL_ENT" ] && echo true || echo false)" "he is back ($RIVAL_ENT)"
assert_ok "set_session_phase 1 0" "a lobby"
assert_ok "set_session_phase 1 1" "and a round"
check "$(wait_for 15 rival_line && echo true || echo false)" "within his rest, he casts"
assert_eq "$(rival_line)" '"village_shallows"' "into the spot he fishes"
RX=$(sql_first "SELECT x FROM fishing_line WHERE entity_id = $RIVAL_ENT" 1); RZ=$(sql_first "SELECT z FROM fishing_line WHERE entity_id = $RIVAL_ENT" 1)
check "$(python -c "import math; d=math.hypot(float('$RX')+40, float('$RZ')-50); print(str(4.0 <= d <= 24.0).lower())")" \
  "within his rod's reach of where he stands ($RX, $RZ)"
assert_eq "$(sql_rows_anon "SELECT * FROM fishing_line WHERE entity_id = $RIVAL_ENT" | wc -l | tr -d ' ')" "1" "everyone sees his float"
if [ "$(row_count "SELECT * FROM fight_show WHERE entity_id = $RIVAL_ENT")" = "0" ]; then
  assert_ok "set_session_phase 1 2" "the bell, before anything bites"
  sleep 1.5
  assert_eq "$(row_count "SELECT * FROM fishing_line WHERE entity_id = $RIVAL_ENT")" "0" "brings his line in, like anyone's"
  assert_ok "set_session_phase 1 1" "another round"
  check "$(wait_for 15 rival_line && echo true || echo false)" "and he casts again"
else
  pass; pass; pass; pass   # it bit before the bell could ring: the same count either way
fi
rival_fighting() { sql_first "SELECT state FROM fight_show WHERE entity_id = $RIVAL_ENT" 1; }
check "$(wait_for 40 rival_fighting && echo true || echo false)" "something bites, and his fight is shown"
check "$(python -c "print(str(0.0 <= float('$(sql_first "SELECT load FROM fight_show WHERE entity_id = $RIVAL_ENT" 1)') <= 1.0).lower())")" \
  "with a load a watcher can draw"
rival_done() { [ -z "$(rival_line)" ] && echo done; }
check "$(wait_for 25 rival_done && echo true || echo false)" "the fight ends, and his line comes in"
assert_eq "$(row_count "SELECT * FROM fight_show WHERE entity_id = $RIVAL_ENT")" "0" "and so does its show"
RIVAL_CATCHES=$(row_count "SELECT * FROM catch WHERE owner_entity_id = $RIVAL_ENT")
RIVAL_SCORE=$(sql_first "SELECT score FROM session_member WHERE entity_id = $RIVAL_ENT" 1)
check "$( { [ "$RIVAL_CATCHES" = "0" ] && [ "${RIVAL_SCORE:-0}" = "0" ]; } || { [ "$RIVAL_CATCHES" = "1" ] && [ "${RIVAL_SCORE:-0}" -gt 0 ]; } && echo true || echo false)" \
  "he landed it and scored, or lost it and did not ($RIVAL_CATCHES catches, $RIVAL_SCORE points)"
assert_ok "use_level 0 0" "the greybox has no rival"
assert_eq "$(row_count "SELECT * FROM entity WHERE entity_id = $RIVAL_ENT")" "0" "he leaves with the lakeside"
assert_eq "$(row_count "SELECT * FROM session_member WHERE entity_id = $RIVAL_ENT")" "0" "and the round"

assert_ok "use_level 0 0" "back to the greybox for what follows"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "and home"
