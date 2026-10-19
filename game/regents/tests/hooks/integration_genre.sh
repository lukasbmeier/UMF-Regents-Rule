# REGENT'S RULE'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, assert_rejected, sql_first, row_count, check...).
# WOODCUTTING on the server: the trees a level plants, the starter axe, what `chop` refuses, a round the
# server deals and REPLAYS from a bot's inputs (game/regents/tests/chop_bot_cli.gd, the client's own
# ChopModel), paid once, never early, never from far away; a stump; no axe. AFK needs a client that
# stays connected (each `spacetime call` leaves at once): tests/chop_playtest.sh plays it.

echo "== REGENTS: woodcutting =="
GODOT="${GODOT:-godot}"
qty_of() { local v; v="$(sql_first "SELECT qty FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = $1" 1)"; echo "${v:-0}"; }
# chop_bot SEED TREE_DEF BOT -> BOT_RESULT (the inputs, a JSON array) and BOT_PLAYED
chop_bot() {
  local halves out
  halves="$(python -c "s=int('$1'); print(s >> 32, s & 0xFFFFFFFF)")"
  out="$("$GODOT" --headless --path . --script res://game/regents/tests/chop_bot_cli.gd -- \
    --seed_hi="${halves% *}" --seed_lo="${halves#* }" --tree="$2" --bot="$3" 2>&1)"
  BOT_RESULT="$(printf '%s\n' "$out" | grep '^RESULT ' | sed 's/^RESULT //' | tr -d '\r')"
  BOT_PLAYED="$(printf '%s\n' "$out" | grep '^PLAYED ' | sed 's/^PLAYED //' | tr -d '\r')"
  [ -n "$BOT_RESULT" ] || echo "  chop_bot: no result: $(printf '%s' "$out" | tail -3)" >&2
}
chop_cid() { sql_first "SELECT id FROM challenge WHERE kind = 100 AND entity_id = $MYENT" 1; }

assert_eq "$(row_count 'SELECT * FROM item_def WHERE item_def_id >= 40001 AND item_def_id <= 40005')" "5" \
  "the five items (an axe, three logs, a bird's nest) are item_def rows, from the genre's content"
assert_ok "set_world_level 0 20" "world 0 to the frontier glade (level 20)"
assert_eq "$(row_count 'SELECT * FROM tree_node WHERE world_id = 0')" "17" "the glade's 17 tree points are planted (8 trees, 5 oaks, 4 yews)"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 100')" "17" "each an entity of the tree kind (100)"
assert_eq "$(row_count 'SELECT * FROM tree_node WHERE def_id = 40003')" "4" "four of them yews, by the points' tags"
TREE="$(sql_first "SELECT entity_id FROM tree_node WHERE point_id = 'tree_1'" 1)"   # a Tree, at (-9, 0, -6)
OAK="$(sql_first "SELECT entity_id FROM tree_node WHERE point_id = 'oak_1'" 1)"     # an Oak, at (20, 0, -10)
assert_eq "$(qty_of 40001)" "1" "the player was given a Bronze axe"

assert_ok 'teleport {"x":0.0,"y":0.0,"z":8.0}' "stand at the spawn, 16 m from tree_1"
assert_rejected "chop $TREE false" "too far" "chopping from 16 m is refused"
assert_rejected "chop $MYENT false" "not a tree" "a player is not a tree"
assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "stand 1.5 m from tree_1"
assert_ok "chop $TREE false" "tap E: chop it AFK"
sleep 0.7
assert_eq "$(row_count "SELECT * FROM afk_chop WHERE entity_id = $MYENT")" "0" \
  "AFK stops when its player is gone (the CLI left at once)"

LOGS0="$(qty_of 40002)"
assert_ok "chop $TREE true" "hold E: a round is dealt"
CID="$(chop_cid)"
assert_eq "$(sql_first "SELECT payload FROM challenge WHERE id = $CID" 1)" "\"$TREE 40001\"" "its payload names the tree and its TreeDef"
assert_ok "submit_challenge_result $CID [10000.0,1.0]" "a press at the round's last millisecond, sent the moment it was dealt..."
assert_eq "$(qty_of 40002)" "$LOGS0" "...pays nothing: by the server's clock that press had not happened yet"
assert_eq "$(row_count "SELECT * FROM challenge WHERE id = $CID")" "0" "and the round is used up"

assert_ok "chop $TREE true" "another round"
CID="$(chop_cid)"
assert_ok "submit_challenge_result $CID [0.0,1.0,300.0]" "inputs that are not pairs..."
assert_eq "$(qty_of 40002)" "$LOGS0" "...pay nothing"

# Each of the next two on a tree of its own: a round that pays may fell its tree.
TREE2="$(sql_first "SELECT entity_id FROM tree_node WHERE point_id = 'tree_2'" 1)"   # at (-3, 0, -11)
TREE3="$(sql_first "SELECT entity_id FROM tree_node WHERE point_id = 'tree_3'" 1)"   # at (5, 0, -8)
assert_ok 'teleport {"x":-3.0,"y":0.0,"z":-9.5}' "stand by tree_2"
assert_ok "chop $TREE2 true" "a round on tree_2, played for real"
CID="$(chop_cid)"
chop_bot "$(sql_first "SELECT seed FROM challenge WHERE id = $CID" 1)" 40001 perfect
check "$(echo "$BOT_PLAYED" | grep -q '"score_pm": 1000' && echo true || echo false)" "the bot plays it perfectly ($BOT_PLAYED)"
sleep 9
assert_ok "submit_challenge_result $CID $BOT_RESULT" "submitted when its ten seconds have passed"
GOT=$(( $(qty_of 40002) - LOGS0 ))
HARVEST="$(sql_rows "SELECT qty, active, score_pm, felled FROM harvest WHERE entity_id = $MYENT AND active = true" | tail -1 | tr -d ' ')"
check "$([ "$GOT" -ge 1 ] && [ "$GOT" -le 4 ] && echo true || echo false)"   "the server replayed it and paid: $GOT logs (3.125 at a full score, fewer if the tree fell first)"
check "$(echo "$HARVEST" | grep -q "^$GOT|true|1000|" && echo true || echo false)" "a harvest row says so: $HARVEST"
assert_rejected "submit_challenge_result $CID $BOT_RESULT" "no such challenge" "a round is paid once"

assert_ok 'teleport {"x":5.0,"y":0.0,"z":-6.5}' "stand by tree_3"
assert_ok "chop $TREE3 true" "a round on tree_3"
CID="$(chop_cid)"
chop_bot "$(sql_first "SELECT seed FROM challenge WHERE id = $CID" 1)" 40001 perfect
assert_ok 'teleport {"x":5.0,"y":0.0,"z":4.0}' "walk 10 m away while it is played"
sleep 9
LOGS1="$(qty_of 40002)"
assert_ok "submit_challenge_result $CID $BOT_RESULT" "submitted from 10 m away..."
assert_eq "$(qty_of 40002)" "$LOGS1" "...pays nothing: you have to be at the tree"

assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "back at tree_1"
assert_ok "set_status $TREE 100 60000 \"\"" "an admin fells tree_1 (status Felled, 60 s)"
assert_rejected "chop $TREE true" "stump" "a stump cannot be chopped"

AXE_ROW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40001" 1)"
assert_ok "consume_item $AXE_ROW 1" "the axe leaves the bag"
assert_ok 'teleport {"x":20.0,"y":0.0,"z":-8.5}' "stand by oak_1"
assert_rejected "chop $OAK false" "need an axe" "with no axe, nothing is chopped"
assert_eq "$(qty_of 40001)" "0" "and the starter axe is not handed out again (once per character)"
assert_ok "grant_item $MYENT 40001 1" "an admin gives the axe back"

assert_ok "set_world_level 0 0" "back to the greybox"
assert_eq "$(row_count 'SELECT * FROM tree_node')" "0" "a level change takes the glade's trees away"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 100')" "0" "and their entities"
