# FISHING'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, sql_first...). Moved verbatim (the template split).

# WHICH LEVEL A WORLD RUNS IS THE FOUNDATION'S (DECISIONS #175): any baked level, by its number.
assert_eq "$(sql_first 'SELECT level_id FROM world_level WHERE world_id = 0' 1)" "1" "the foundation records that world 0 runs level 1, the lakeside"
out="$(spacetime call --anonymous "$DB" set_world_level 0 2 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" "only an admin switches a world's level"
assert_ok "set_world_level 0 2" "an admin switches world 0 to level 2, the meadow (built in the editor)"
assert_eq "$(sql_first 'SELECT level_id FROM world_level WHERE world_id = 0' 1)" "2" "world_level says so"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 0, y = 0, z = 14)" "the spawn is the meadow bake's"
assert_eq "$(sql_first 'SELECT level FROM fishing_world WHERE world_id = 0' 1)" "2" "and fishing set itself up for it (its hook)"
assert_rejected "set_world_level 0 9" "unknown level" "a level nobody baked is refused"
assert_ok "use_level 0 1" "and fishing's own switch takes it back to the lakeside"
assert_eq "$(sql_first 'SELECT level_id FROM world_level WHERE world_id = 0' 1)" "1" "through the same foundation record"
assert_rejected "use_level 0 9" "unknown level" "an unknown level is refused"
assert_eq "$(sql_first 'SELECT level FROM fishing_world WHERE world_id = 0' 1)" "1" "a refused switch changes nothing"
out="$(spacetime call --anonymous "$DB" use_level 0 0 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" \
  "a non-admin cannot switch a world's level (output: $(echo "$out" | head -1))"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 2')" "0" "and the refused switch stocked nothing"
assert_ok "use_level 0 0" "switch the default world to the greybox"
assert_eq "$(sql_first 'SELECT level FROM fishing_world WHERE world_id = 0' 1)" "0" "the world now runs the greybox"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 0, y = 0, z = 0)" \
  "the greybox spawns at the origin"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 2 AND world_id = 0')" "3" "the greybox's ponds are stocked"
assert_ok "use_level 0 0" "switching to the level a world already runs"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 2')" "3" "is idempotent: no second set of ponds"
assert_ok "use_level 0 1" "and back to the lakeside"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 2')" "0" "the lakeside clears the greybox's ponds"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 0, y = 2.25, z = 76)" \
  "and restores its own spawn"
assert_ok 'set_world_spawn 0 {"x":5.0,"y":1.0,"z":-3.0}' "an admin may move a world's spawn"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 5, y = 1, z = -3)" \
  "the spawn moved"
assert_rejected 'set_world_spawn 7 {"x":0.0,"y":0.0,"z":0.0}' "no world 7" "a spawn for a world that does not exist is refused"
out="$(spacetime call --anonymous "$DB" set_world_spawn 0 '{"x":1.0,"y":1.0,"z":1.0}' 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" \
  "a non-admin cannot move a spawn (output: $(echo "$out" | head -1))"
# Everything below was written against the greybox, with the admin's player at the origin.
assert_ok "use_level 0 0" "the rest of this suite runs on the greybox"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "the admin's player arrived at the lakeside spawn; bring it home"
