# FISHING'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, sql_first...). Moved verbatim (the template split).

# The genre hook runs last inside init. A fresh publish must be playable with no setup script:
# pressing Play in the editor is the whole workflow, so the default world already runs the
# game's level — the lakeside — at its baked spawn, and without the greybox's pond entities.
assert_eq "$(sql_first 'SELECT level FROM fishing_world WHERE world_id = 0' 1)" "1" \
  "game::on_init points the default world at the lakeside"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 0, y = 2.25, z = 76)" \
  "the default world's spawn is the lakeside's baked spawn"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 2')" "0" \
  "the lakeside has no pond entities: its water is terrain"
# THE ROUND'S TIME OF DAY AND WEATHER (DECISIONS #168): rolled for round 1 when the level was set.
assert_eq "$(sql_first 'SELECT round FROM fishing_conditions WHERE world_id = 0' 1)" "1" "round 1 has its conditions"
assert_eq "$(sql_first 'SELECT time_of_day FROM fishing_conditions WHERE world_id = 0' 1)" "0" "round 1 is the first time of day (dawn)"
check "$(python -c "import json; w=len(json.load(open('shared/fishing/fishing.json'))['conditions']['weather']); print(str(0 <= int('$(sql_first 'SELECT weather FROM fishing_conditions WHERE world_id = 0' 1)') < w).lower())")" \
  "and a weather the data has"
assert_eq "$(sql_rows_anon 'SELECT * FROM fishing_conditions' | wc -l | tr -d ' ')" "1" "public: every client draws them"
# THE RIVAL (DECISIONS #169): the lakeside, run by the module, has him standing where fishing.json
# says, playing the round. The suites count every line and catch in the world, so he is benched
# here and tested on his own at the end.
RIVAL_ENT=$(sql_first "SELECT entity_id FROM entity WHERE kind = 1" 1)
check "$([ -n "$RIVAL_ENT" ] && echo true || echo false)" "the rival angler is in the default world ($RIVAL_ENT)"
assert_eq "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $RIVAL_ENT" 1)" "(x = -40, y = 1.02, z = 50)" \
  "standing where fishing.json puts him"
assert_eq "$(row_count "SELECT * FROM session_member WHERE entity_id = $RIVAL_ENT")" "1" "and in the round, for the standings"
out="$(spacetime call --anonymous "$DB" set_rival 0 false 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" "only an admin benches him"
assert_ok "set_rival 0 false" "an admin benches the rival"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 1')" "0" "and he is gone"
assert_eq "$(row_count "SELECT * FROM session_member WHERE entity_id = $RIVAL_ENT")" "0" "from the round too"
