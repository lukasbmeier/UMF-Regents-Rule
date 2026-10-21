# REGENT'S RULE'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, assert_rejected, sql_first, row_count, check...).
# THE SKILLING CHAIN on the server: the nodes and stations a level places, the starter kit, what `gather`
# and `craft` refuse, rounds of all four minigames dealt by the server and REPLAYED from a bot's inputs
# (game/regents/tests/skill_bot_cli.gd, the client's own models): paid once, never early, never from far
# away; XP and the ranks it gates; a better tool's speed in the round; the smith's quality on the part.
# AFK work needs a client that stays connected (each `spacetime call` leaves at once):
# game/regents/tests/chop_playtest.sh plays it, and the assembly.

echo "== REGENTS: the skilling chain =="
GODOT="${GODOT:-godot}"
qty_of() { local v; v="$(sql_rows "SELECT qty FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = $1" | awk -F'|' '{s+=$1} END {print s+0}')"; echo "${v:-0}"; }
xp_of() { local v; v="$(sql_first "SELECT xp FROM skill_xp WHERE entity_id = $MYENT AND skill_id = $1" 1)"; echo "${v:-0}"; }
node_at() { sql_first "SELECT entity_id FROM gather_node WHERE point_id = '$1'" 1; }
station_at() { sql_first "SELECT entity_id FROM station WHERE point_id = '$1'" 1; }
# bot KIND DEF SEED SPEED -> BOT_RESULT (the inputs, a JSON array) and BOT_PLAYED
bot() {
  local halves out
  halves="$(python -c "s=int('$3'); print(s >> 32, s & 0xFFFFFFFF)")"
  out="$("$GODOT" --headless --path . --script res://game/regents/tests/skill_bot_cli.gd -- \
    --kind="$1" --def="$2" --speed="$4" --seed_hi="${halves% *}" --seed_lo="${halves#* }" 2>&1)"
  BOT_RESULT="$(printf '%s\n' "$out" | grep '^RESULT ' | sed 's/^RESULT //' | tr -d '\r')"
  BOT_PLAYED="$(printf '%s\n' "$out" | grep '^PLAYED ' | sed 's/^PLAYED //' | tr -d '\r')"
  [ -n "$BOT_RESULT" ] || echo "  bot: no result: $(printf '%s' "$out" | tail -3)" >&2
}
round_cid() { sql_first "SELECT id FROM challenge WHERE kind >= 100 AND kind <= 103 AND entity_id = $MYENT" 1; }
round_field() { sql_first "SELECT $2 FROM challenge WHERE id = $1" 1; }
# play_round KIND DEF WAIT_S -> plays the round the server just dealt, after its time, and submits it
play_round() {
  local cid seed payload speed
  cid="$(round_cid)"
  seed="$(round_field "$cid" seed)"
  payload="$(round_field "$cid" payload | tr -d '"')"
  speed="${payload##* }"
  ROUND_PAYLOAD="$payload"
  bot "$1" "$2" "$seed" "$speed"
  sleep "$3"
  assert_ok "submit_challenge_result $cid $BOT_RESULT" "a round of $1 submitted once its time has passed"
  ROUND_CID="$cid"
}

assert_eq "$(row_count 'SELECT * FROM item_def WHERE item_def_id >= 40001 AND item_def_id <= 40015')" "15" \
  "the chain's fifteen items are item_def rows, from the genre's content"
assert_eq "$(row_count 'SELECT * FROM item_def WHERE item_def_id = 40016 OR item_def_id = 40017')" "2" "and the oak and yew handles"
assert_ok "set_world_level 0 20" "world 0 to the frontier glade (level 20)"
assert_eq "$(row_count 'SELECT * FROM gather_node WHERE world_id = 0')" "26" "its 26 nodes are placed (17 trees, 5 copper and 4 iron rocks)"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 100')" "26" "each an entity of the node kind (100)"
assert_eq "$(row_count 'SELECT * FROM station WHERE world_id = 0')" "4" "and its four stations: a furnace, an anvil, a workbench, the order board"
assert_eq "$(row_count 'SELECT * FROM gather_node WHERE def_id = 40005')" "4" "four of the nodes iron rocks, by the points' tags"
TREE="$(node_at tree_1)"; TREE2="$(node_at tree_2)"; TREE3="$(node_at tree_3)"    # at (-9,0,-6), (-3,0,-11), (5,0,-8)
COPPER="$(node_at copper_1)"; IRON="$(node_at iron_1)"                            # at (14,0,16), (-18,0,18)
FURNACE="$(station_at furnace)"; ANVIL="$(station_at anvil)"; BENCH="$(station_at workbench)"   # at (-6,0,14), (-2,0,16.5), (4,0,15)
BOARD="$(station_at orders)"                                                                  # at (1,0,19)
# the newest work_result's XP at a target (the SQL has no ORDER BY: the highest id)
wr_xp() { sql_rows "SELECT id, xp FROM work_result WHERE entity_id = $MYENT AND target_id = $1" | tr -d ' ' | sort -t'|' -k1,1n | tail -1 | cut -d'|' -f2; }
log_of() { sql_first "SELECT $2 FROM recipe_log WHERE entity_id = $MYENT AND recipe_id = $1" 1; }
assert_eq "$(qty_of 40001) $(qty_of 40006)" "1 1" "the player was given a Bronze axe and a Bronze pickaxe"

# --- woodcutting ---
assert_ok 'teleport {"x":0.0,"y":0.0,"z":8.0}' "stand at the spawn, 16 m from tree_1"
assert_rejected "gather $TREE false" "too far" "gathering from 16 m is refused"
assert_rejected "gather $MYENT false" "nothing to gather" "a player is nothing to gather"
assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "stand 1.5 m from tree_1"
assert_ok "gather $TREE false" "tap E: chop it AFK"
sleep 0.7
assert_eq "$(row_count "SELECT * FROM afk_work WHERE entity_id = $MYENT")" "0" "AFK stops when its player is gone (the CLI left at once)"
LOGS0="$(qty_of 40002)"
assert_ok "gather $TREE true" "hold E: a round is dealt"
CID="$(round_cid)"
assert_eq "$(round_field "$CID" payload)" "\"$TREE 40001 100\"" "its payload: the tree, its NodeDef, the bronze axe's speed (100 %)"
assert_eq "$(round_field "$CID" kind)" "100" "a round of branch dodge (challenge kind 100)"
assert_ok "submit_challenge_result $CID [10000.0,1.0]" "a press at the round's last millisecond, sent the moment it was dealt..."
assert_eq "$(qty_of 40002)" "$LOGS0" "...pays nothing: by the server's clock that press had not happened yet"
assert_eq "$(row_count "SELECT * FROM challenge WHERE id = $CID")" "0" "and the round is used up"
assert_ok "gather $TREE true" "another round"
assert_ok "submit_challenge_result $(round_cid) [0.0,1.0,300.0]" "inputs that are not pairs..."
assert_eq "$(qty_of 40002)" "$LOGS0" "...pay nothing"
assert_ok 'teleport {"x":-3.0,"y":0.0,"z":-9.5}' "stand by tree_2"
assert_ok "gather $TREE2 true" "a round on tree_2, played for real"
play_round chop 40001 9
GOT=$(( $(qty_of 40002) - LOGS0 ))
check "$(echo "$BOT_PLAYED" | grep -q '"score_pm": 1000' && echo true || echo false)" "the bot plays it perfectly ($BOT_PLAYED)"
check "$([ "$GOT" -ge 1 ] && [ "$GOT" -le 4 ] && echo true || echo false)" \
  "the server replayed it and paid: $GOT logs (3.125 at a full score, fewer if the tree fell first)"
check "$(sql_rows "SELECT qty, active, score_pm, xp FROM work_result WHERE entity_id = $MYENT AND active = true" | tail -1 | tr -d ' ' | grep -q "^$GOT|true|1000|$((GOT * 10))\$" && echo true || echo false)" \
  "a work_result row says so: $GOT logs, a round, a full score, $((GOT * 10)) XP"
assert_eq "$(xp_of 40001)" "$((GOT * 10))" "and woodcutting has the XP (10 a log)"
assert_rejected "submit_challenge_result $ROUND_CID $BOT_RESULT" "no such challenge" "a round is paid once"
assert_ok 'teleport {"x":5.0,"y":0.0,"z":-6.5}' "stand by tree_3"
assert_ok "gather $TREE3 true" "a round on tree_3"
CID="$(round_cid)"
bot chop 40001 "$(round_field "$CID" seed)" 100
assert_ok 'teleport {"x":5.0,"y":0.0,"z":4.0}' "walk 10 m away while it is played"
sleep 9
LOGS1="$(qty_of 40002)"
assert_ok "submit_challenge_result $CID $BOT_RESULT" "submitted from 10 m away..."
assert_eq "$(qty_of 40002)" "$LOGS1" "...pays nothing: you have to be where you work"

# --- mining, and the rank a node needs ---
assert_ok 'teleport {"x":-18.0,"y":0.0,"z":16.5}' "stand by iron_1"
assert_rejected "gather $IRON true" "needs Mining rank 2" "an iron rock needs mining rank 2 (a new miner has 1)"
assert_ok 'teleport {"x":14.0,"y":0.0,"z":14.5}' "stand by copper_1"
ORE0="$(qty_of 40007)"
assert_ok "gather $COPPER true" "hold E at the copper rock: a round of crack the rock"
assert_eq "$(round_field "$(round_cid)" kind)" "101" "challenge kind 101"
play_round crack 40004 9
ORE=$(( $(qty_of 40007) - ORE0 ))
check "$(echo "$BOT_PLAYED" | grep -q '"score_pm": 1000' && echo true || echo false)" "the bot follows the seam, every notch in order ($BOT_PLAYED)"
check "$([ "$ORE" -ge 1 ] && [ "$ORE" -le 3 ] && echo true || echo false)" "the server replayed the strikes and paid $ORE copper ore (2.78 at a full score, fewer if the rock gave out)"
assert_eq "$(xp_of 40002)" "$((ORE * 10))" "and mining has the XP"

# --- the furnace ---
assert_ok 'teleport {"x":-6.0,"y":0.0,"z":12.5}' "stand at the furnace"
assert_rejected "craft $FURNACE 40002 true" "needs 2 Iron ore" "no iron ore, no iron bar (two ores to a bar)"
assert_rejected "craft $FURNACE 40004 true" "not made at the furnace" "an axe head is not made at a furnace"
assert_rejected "craft $ANVIL 40003 true" "too far" "rivets at the anvil, asked from the furnace: too far"
assert_ok "grant_item $MYENT 40007 5" "an admin gives 5 copper ore"
ORE_HAVE="$(qty_of 40007)"; BARS0="$(qty_of 40010)"
assert_ok "craft $FURNACE 40001 true" "hold E at the furnace: a round of bellows then pour, for copper bars"
assert_eq "$(round_field "$(round_cid)" kind)" "102" "challenge kind 102"
play_round smelt 40001 11
BARS=$(( $(qty_of 40010) - BARS0 ))
check "$([ "$BARS" -ge 1 ] && [ "$BARS" -le $((ORE_HAVE / 2)) ] && echo true || echo false)" "smelted: $BARS copper bars from $ORE_HAVE ore ($BOT_PLAYED)"
assert_eq "$(( ORE_HAVE - $(qty_of 40007) ))" "$((BARS * 2))" "each bar took two ores"
SMELT_XP="$(xp_of 40003)"
assert_eq "$(wr_xp "$FURNACE")" "$SMELT_XP" "smelting has the XP the round's work_result says"
# a bar's own 6 XP, plus 60 % of its two ores' mining (12): 18 a batch, less as it wears; x5 more the first time
check "$([ "$SMELT_XP" -ge $((18 * 5 + 18 * BARS - BARS)) ] && [ "$SMELT_XP" -le $((18 * 5 + 18 * BARS)) ] && echo true || echo false)"   "it paid for the work in the ores and a first-make bonus: $SMELT_XP XP for $BARS bars (once 6 a bar)"
assert_eq "$(log_of 40001 made)" "$BARS" "the recipe log counts the bars made"
check "$([ "$(log_of 40001 fresh_pm)" -lt 1000 ] && echo true || echo false)" "and the recipe has worn a little stale ($(log_of 40001 fresh_pm) per mille)"

# --- the anvil: a part as good as the smith ---
assert_ok 'teleport {"x":-2.0,"y":0.0,"z":15.0}' "stand at the anvil"
assert_rejected "craft $ANVIL 40004 true" "needs 2 Iron bar" "no iron bars, no axe head"
assert_ok "grant_item $MYENT 40011 2" "an admin gives 2 iron bars"
assert_ok "craft $ANVIL 40004 true" "hold E at the anvil: a round of shape to the outline, for an iron axe head"
assert_eq "$(round_field "$(round_cid)" kind)" "103" "challenge kind 103"
play_round shape 40004 15
SCORE="$(echo "$BOT_PLAYED" | grep -oE '"score_pm": [0-9]+' | grep -oE '[0-9]+$')"
assert_eq "$(qty_of 40011)" "0" "the head took both bars"
assert_eq "$(sql_first "SELECT instance_data FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40014" 1)" "\"{\"q\":$SCORE}\"" \
  "an iron axe head, its quality the round's score ($SCORE)"
SMITH_XP="$(xp_of 40004)"
assert_eq "$(wr_xp "$ANVIL")" "$SMITH_XP" "smithing has the XP the round's work_result says"
check "$([ "$SMITH_XP" -ge 180 ] && echo true || echo false)" "a first axe head pays its own 30, its bars' work and the first-make bonus: $SMITH_XP XP"

# --- the workbench, and a better tool's speed ---
assert_ok 'teleport {"x":4.0,"y":0.0,"z":13.5}' "stand at the workbench"
assert_rejected "craft $BENCH 40006 false" "needs 1 Handle" "an iron axe needs a handle (and rivets): assembled by the playtest"
assert_rejected "craft_with $BENCH 40006 false 40010" "takes a handle there" "a copper bar is no handle"
assert_rejected "craft_with $BENCH 40006 false 40016" "needs 1 Oak handle" "an oak handle chosen: the bag must have one"
assert_rejected "craft_with $BENCH 40005 false 40016" "takes no part" "a plain handle's recipe has no part slot"
assert_rejected "craft $BENCH 40007 false" "needs Crafting rank 2" "an oak handle needs crafting rank 2"

# --- the order board ---
assert_eq "$(row_count 'SELECT * FROM work_order WHERE world_id = 0')" "3" "the board has three work orders"
ORDER="$(sql_first "SELECT id FROM work_order WHERE world_id = 0 AND slot = 0" 1)"
O_ITEM="$(sql_first "SELECT item_id FROM work_order WHERE id = $ORDER" 1)"; O_QTY="$(sql_first "SELECT qty FROM work_order WHERE id = $ORDER" 1)"
O_SKILL="$(sql_first "SELECT skill_id FROM work_order WHERE id = $ORDER" 1)"; O_XP="$(sql_first "SELECT xp FROM work_order WHERE id = $ORDER" 1)"
check "$([ "$O_QTY" -ge 1 ] && [ "$O_XP" -ge 1 ] && echo true || echo false)" "order 1 wants $O_QTY of item $O_ITEM for $O_XP XP in skill $O_SKILL"
assert_rejected "fill_order $BOARD $ORDER" "too far" "filled from the workbench: too far"
assert_ok 'teleport {"x":1.0,"y":0.0,"z":17.5}' "stand at the order board"
assert_rejected "fill_order $FURNACE $ORDER" "too far" "the furnace is no order board (and far)"
for row in $(sql_rows "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = $O_ITEM" | tr -d ' '); do
  assert_ok "consume_item $row $(sql_first "SELECT qty FROM inventory_item WHERE id = $row" 1)" "what the bag had of it goes"
done
assert_rejected "fill_order $BOARD $ORDER" "it wants $O_QTY" "an empty bag cannot fill it"
assert_ok "grant_item $MYENT $O_ITEM $O_QTY" "an admin gives what it wants"
XP0="$(xp_of "$O_SKILL")"
assert_ok "fill_order $BOARD $ORDER" "E at the board: the order is filled"
assert_eq "$(qty_of "$O_ITEM")" "0" "it took them all"
assert_eq "$(( $(xp_of "$O_SKILL") - XP0 ))" "$O_XP" "and paid its $O_XP XP"
assert_eq "$(row_count "SELECT * FROM order_filled WHERE order_id = $ORDER AND entity_id = $MYENT")" "1" "noted as filled"
assert_ok "grant_item $MYENT $O_ITEM $O_QTY" "the same again"
assert_rejected "fill_order $BOARD $ORDER" "you have filled that order" "an order is filled once per player"
assert_rejected "fill_order $BOARD 999999" "that order is gone" "an order that is not there"
assert_ok "grant_item $MYENT 40015 1" "an admin gives an iron axe (no quality)"
assert_ok 'teleport {"x":-25.0,"y":0.0,"z":-28.5}' "stand by yew_1"
assert_rejected "gather $(node_at yew_1) true" "needs Woodcutting rank 4" "a yew needs woodcutting rank 4"
assert_ok 'teleport {"x":-3.0,"y":0.0,"z":-9.5}' "back by tree_2"
if [ "$(sql_first "SELECT status FROM status_state WHERE entity_id = $TREE2" 1)" = "100" ]; then
  assert_ok "set_status $TREE2 0 0 \"\"" "tree_2 grows back (an admin)"
fi
assert_ok "gather $TREE2 true" "a round with the iron axe in the bag"
assert_eq "$(round_field "$(round_cid)" payload)" "\"$TREE2 40001 85\"" "the best axe is used: the round is at the iron axe's speed (85 %)"
CID="$(round_cid)"
assert_ok "submit_challenge_result $CID []" "nothing pressed"

# --- a node worked out ---
assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "back at tree_1"
assert_ok "set_status $TREE 100 60000 \"\"" "an admin works tree_1 out (status Depleted, 60 s)"
assert_rejected "gather $TREE true" "worked out" "a stump cannot be chopped"
AXE_ROWS="$(sql_rows "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND (item_def_id = 40001 OR item_def_id = 40015)" | tr -d ' ')"
for row in $AXE_ROWS; do assert_ok "consume_item $row 1" "an axe leaves the bag"; done
assert_ok 'teleport {"x":5.0,"y":0.0,"z":-6.5}' "stand by tree_3"
assert_rejected "gather $TREE3 false" "need an axe" "with no axe, nothing is chopped"
assert_eq "$(qty_of 40001)" "0" "and the starter kit is not handed out again (once per character)"
assert_ok "grant_item $MYENT 40001 1" "an admin gives the axe back"

# --- combat: the weapon is the kit; the training dummy ---
C_AIM='{"x":0.0,"y":0.0,"z":-1.0}'
assert_eq "$(row_count 'SELECT * FROM dummy WHERE world_id = 0')" "2" "two training dummies at camp"
DUMMY="$(sql_first "SELECT entity_id FROM dummy WHERE point_id = 'dummy_1'" 1)"
assert_eq "$(sql_first "SELECT max FROM health_state WHERE entity_id = $DUMMY" 1)" "500" "a dummy has 500 health (regents.dummy_hp)"
assert_eq "$(sql_first "SELECT brain FROM npc_brain WHERE entity_id = $DUMMY" 1)" "\"stand\"" "and a stand-still brain (so the referee counts it as someone to hit)"
assert_ok 'teleport {"x":7.0,"y":0.0,"z":21.5}' "stand by the dummy"
AXE_ROW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40001" 1)"
PICK_ROW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40006" 1)"
assert_rejected "use_ability_seen 40006 0 $C_AIM 901 100" "wield an axe first" "nothing wielded: an axe's chop is refused"
assert_rejected "wield $PICK_ROW" "is no weapon" "a pickaxe is no weapon"
assert_rejected "wield 999999" "not in your bag" "nor is what is not in the bag"
assert_ok "wield $AXE_ROW" "wield the bronze axe"
assert_eq "$(sql_first "SELECT kit FROM wielded WHERE entity_id = $MYENT" 1)" "\"axe\"" "it fights with the axe kit"
assert_rejected "use_ability_seen 40001 0 $C_AIM 902 100" "that is a sword move" "a sword's slash, with an axe: refused"
assert_rejected "use_ability_seen 40007 0 $C_AIM 903 100" "out of the combo's order" "the combo's second swing first: refused"
assert_rejected "use_ability_seen 40009 0 $C_AIM 904 100" "no referee" "Cleave (Q, rank 1) passes the game's checks; with nobody judging, the foundation refuses it"
C_CODE='"regentscombatrefereecode"'
assert_ok "offer_referee 0 $C_CODE" "a referee for world 0 (the admin judges here)"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE" >/dev/null 2>&1
HP0="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_ok "use_ability_seen 40006 0 $C_AIM 905 100" "a chop: queued for the referee"
assert_rejected "use_ability_seen 40008 0 $C_AIM 9050 100" "still swinging" "the overhead while the chop holds you (its clip's 578 ms): refused"
R905="$(sql_first "SELECT id FROM action_request WHERE predicted_id = 905" 1)"
assert_ok "use_ability_seen 40007 0 $C_AIM 906 100" "the combo's second, right after: allowed"
R906="$(sql_first "SELECT id FROM action_request WHERE predicted_id = 906" 1)"
assert_ok "resolve_action $R905 $DUMMY" "the referee: the chop hit the dummy"
assert_ok "resolve_action $R906 $DUMMY" "and the second"
HP1="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_eq "$(python -c "print(round($HP0 - $HP1, 2))")" "18.2" "11 + 15 damage at the bronze axe's 70 %: 18.2 off the dummy"
assert_eq "$(xp_of 40007)" "5" "axemanship XP: half a point a damage, half again on a dummy (2 + 3)"
assert_ok "use_ability_seen 40010 0 $C_AIM 907 100" "Ctrl: the dodge roll"
logged() { spacetime logs "$DB" 2>/dev/null | tail -60 | grep -qE "$1" && echo true || echo false; }
check "$(logged "entity $MYENT: status [0-9]+ -> 101 \(Rolling\) for 550 ms")" "rolling for regents.roll_ms: nothing hits you, and its burst carries you"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the test referee unregistered"
done
sleep 0.6
# A CLI call leaves at once, and leaving lowers a block: what it did is in the log; a block HELD by a
# connected player (and no swing behind it) is the playtest's.
assert_ok "block true" "hold the right button: block"
check "$(logged "block .*entity $MYENT: status 0 -> 102 \(Blocking\)")" "the block went up (Blocking: half speed, no sprint)"
check "$(logged "client_disconnected .*entity $MYENT: status 102 -> 0")" "and came down as the player left"
assert_eq "$(sql_first "SELECT blocking FROM combat_state WHERE entity_id = $MYENT" 1)" "false" "the server's record agrees"
sleep 5
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)" "500" "the dummy is whole again a few seconds after its last hit"
# A ROLL CANCELS A SWING: in the overhead's wind-up (600 ms) the roll; the referee finds the dummy, and
# the hit never lands.
C_CODE2='"regentscombatrefereecodetwo"'
assert_ok "offer_referee 0 $C_CODE2" "a referee again"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE2" >/dev/null 2>&1
HPC="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_ok "use_ability_seen 40008 0 $C_AIM 911 100" "the overhead: queued (its wind-up 600 ms)"
assert_ok "use_ability_seen 40010 0 $C_AIM 912 100" "Ctrl in its wind-up: the roll"
assert_eq "$(sql_first "SELECT cancelled FROM swing WHERE entity_id = $MYENT" 1)" "true" "the overhead is cancelled"
R911="$(sql_first "SELECT id FROM action_request WHERE predicted_id = 911" 1)"
assert_ok "resolve_action $R911 $DUMMY" "the referee: its sweep found the dummy"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)" "$HPC" "but a cancelled swing never lands: no damage"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the test referee unregistered"
done
# --- FOES (owner, 2026-10-19: the first enemies, a skeleton camp east of the spawn) ---
assert_eq "$(row_count 'SELECT * FROM foe WHERE world_id = 0')" "3" "three skeletons at the camp (the level's foe points)"
SKEL="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_1'" 1)"
assert_eq "$(sql_first "SELECT kind FROM entity WHERE entity_id = $SKEL" 1)" "103" "skeleton_1 is a skeleton warrior (kind 103)"
assert_eq "$(sql_first "SELECT max FROM health_state WHERE entity_id = $SKEL" 1)" "120" "with its FoeDef's health"
assert_eq "$(sql_first "SELECT brain FROM npc_brain WHERE entity_id = $SKEL" 1)" "\"regents/foe\"" "and the foe brain (the referee drives it)"
assert_eq "$(sql_first "SELECT kind FROM entity WHERE entity_id = $(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_2'" 1)" 1)" "104" "skeleton_2 is an axeman"
assert_ok 'set_rule "regents.foe_corpse_s" 1.0 ""' "(test) a body lies 1 s"
assert_ok 'set_rule "regents.foe_respawn_s" 15.0 ""' "(test) and its foe is back after 15"
assert_ok 'set_rule "regents.player_respawn_s" 1.0 ""' "(test) a slain player is up after 1"
assert_ok 'teleport {"x":33.0,"y":0.0,"z":0.4}' "stand by skeleton_1"
C_CODE3='"regentscombatrefereecodethree"'
assert_ok "offer_referee 0 $C_CODE3" "a referee for the fight"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE3" >/dev/null 2>&1
# ITS SWING ON YOU: as its brain asks (the authority's use_ability_as), at 50 % (its FoeDef's damage).
PHP0="$(sql_first "SELECT current FROM health_state WHERE entity_id = $MYENT" 1)"
assert_ok "use_ability_as $SKEL 40001 0 {\"x\":0.0,\"y\":0.0,\"z\":1.0} 0" "the skeleton slashes (the sword kit's first light)"
RS="$(sql_first "SELECT id FROM action_request WHERE actor_id = $SKEL" 1)"
assert_ok "resolve_action $RS $MYENT" "the referee: it hit you"
PHP1="$(sql_first "SELECT current FROM health_state WHERE entity_id = $MYENT" 1)"
SLASH="$(sql_first "SELECT damage FROM ability_def WHERE ability_id = 40001" 1)"
check "$(python -c "print('true' if abs(($PHP0 - $PHP1) - $SLASH * 0.5) < 1e-3 else 'false')")" "its slash at its 50 %: half the sword slash's $SLASH ($PHP0 -> $PHP1)"
# WHO MAY HURT WHOM (owner's playtest, 2026-10-20): its sweep catching the skeleton beside it does nothing.
SK_NEXT="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_2'" 1)"
NH0="$(sql_first "SELECT current FROM health_state WHERE entity_id = $SK_NEXT" 1)"
sleep 0.8
assert_ok "use_ability_as $SKEL 40001 0 {\"x\":0.0,\"y\":0.0,\"z\":1.0} 0" "it slashes again"
RS2="$(sql_rows "SELECT id FROM action_request WHERE actor_id = $SKEL" | tr -d ' ' | sort -n | tail -1)"
assert_ok "resolve_action $RS2 $SK_NEXT" "the referee: the sweep caught skeleton_2"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $SK_NEXT" 1)" "$NH0" "skeleton_2 is not hurt by its own kind"
# YOU SLAY IT: worn down by an authority, then a chop: Slain, its loot is yours, its body goes, it comes back.
QTY() { local v; v="$(sql_rows "SELECT qty FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = $1" | awk -F'|' '{s+=$1} END {print s+0}')"; echo "${v:-0}"; }
C0="$(QTY 40007)"; I0="$(QTY 40008)"; G0="$(QTY 40009)"; XP0="$(xp_of 40007)"
assert_ok "apply_damage $SKEL 118 0" "(test) worn down to 2"
sleep 1.2
# (A fresh stand-in referee: the last one lapses while the checks above run.)
for OLD_REF in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  spacetime call "$DB" revoke_authority "$OLD_REF" >/dev/null 2>&1
done
spacetime call "$DB" offer_referee 0 '"regentscombatrefereecodefour"' >/dev/null 2>&1
spacetime call --anonymous "$DB" claim_referee 0 '"regentscombatrefereecodefour"' >/dev/null 2>&1
assert_ok "use_ability_seen 40006 0 $C_AIM 921 100" "a chop at it"
RK="$(sql_first "SELECT id FROM action_request WHERE predicted_id = 921" 1)"
assert_ok "resolve_action $RK $SKEL" "the referee: the chop hit"
assert_eq "$(sql_first "SELECT is_dead FROM health_state WHERE entity_id = $SKEL" 1)" "true" "its health ran out"
assert_eq "$(sql_first "SELECT status FROM status_state WHERE entity_id = $SKEL" 1)" "106" "Slain: nothing moves, acts or is hit"
check "$(sql_first "SELECT fell_at FROM foe WHERE entity_id = $SKEL" 1 | grep -qv none && echo true || echo false)" "the camp knows it fell"
LOOT="$(sql_first "SELECT loot FROM foe_kill WHERE entity_id = $MYENT" 1 | tr -d '"')"
# It falls on the ground where it fell, yours alone for now (DECISIONS #269): sacks of what you rolled.
GROUND="$(sql_rows "SELECT item_def_id, qty FROM ground_item WHERE owner_id = $MYENT AND anyone = false" | tr -d ' ' | tr '|' ':' | paste -sd, -)"
check "$(python -c "
import collections
a = collections.Counter({int(i): int(q) for i, q in (p.split(':') for p in '$LOOT'.split(',') if p)})
b = collections.Counter()
for p in '$GROUND'.split(','):
    if p:
        i, q = p.split(':'); b[int(i)] += int(q)
print('true' if a == b else 'false')
")" "its loot ('$LOOT') lies on the ground, yours ('$GROUND')"
for GID in $(sql_rows "SELECT id FROM ground_item WHERE owner_id = $MYENT" | tr -d ' '); do
  assert_ok "pick_up $GID" "pick up a sack beside it"
done
check "$(python -c "
import sys
got = {int(a): int(b) for a, b in (p.split(':') for p in '$LOOT'.split(',') if p)}
d = {40007: $(QTY 40007) - $C0, 40008: $(QTY 40008) - $I0, 40009: $(QTY 40009) - $G0}
print('true' if all(d[k] == got.get(k, 0) for k in d) and all(k in d for k in got) else 'false')
")" "picked up, its loot ('$LOOT') is in your bag, and nothing else"
# A personal roll of the camp's table (DECISIONS #268): the chop was all the players' damage, so the roll
# was yours; the gem's pity keeps your run of misses (0 if it dropped); the tally of who hurt it is gone.
check "$(sql_first "SELECT rolls_since FROM drop_pity WHERE table_id = 40001 AND line = 2" 1 | grep -qE '^ *[01] *$' && echo true || echo false)" "the gem's pity: your run of misses is kept (0 or 1)"
assert_eq "$(row_count "SELECT * FROM damage_share WHERE target_id = $SKEL")" "0" "and the tally of who hurt it is forgotten"
check "$(python -c "print('true' if $(xp_of 40007) > $XP0 else 'false')")" "and axemanship XP for the hit (at the foe's full rate)"
sleep 1
assert_eq "$(row_count "SELECT * FROM entity WHERE entity_id = $SKEL")" "0" "a second on, its body is gone"
assert_eq "$(sql_first "SELECT gone FROM foe WHERE entity_id = $SKEL" 1)" "true" "and the camp waits for it"
SKEL2=""
for i in $(seq 1 30); do
  SKEL2="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_1'" 1)"
  [ -n "$SKEL2" ] && [ "$SKEL2" != "$SKEL" ] && break
  sleep 1
done
check "$( [ -n "$SKEL2" ] && [ "$SKEL2" != "$SKEL" ] && echo true || echo false)" "once its time is up it is back on its point, a new entity ($SKEL2)"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $SKEL2" 1)" "120" "whole"
# A PLAYER SLAIN gets up at the spawn, whole; what they were working at stops.
assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "back beside tree_1"
assert_ok "gather $TREE true" "a round of branch dodge, then..."
assert_eq "$(row_count "SELECT * FROM challenge WHERE kind >= 100 AND kind <= 103 AND entity_id = $MYENT")" "1" "(the round is open)"
PHP2="$(sql_first "SELECT current FROM health_state WHERE entity_id = $MYENT" 1)"
assert_ok "apply_damage $MYENT $(python -c "print($PHP2 - 1)") 0" "(test) you are worn down to 1"
assert_ok "offer_referee 0 $C_CODE3" "a referee again"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE3" >/dev/null 2>&1
assert_ok "use_ability_as $SKEL2 40001 0 {\"x\":0.0,\"y\":0.0,\"z\":1.0} 0" "the new skeleton slashes"
RS2="$(sql_first "SELECT id FROM action_request WHERE actor_id = $SKEL2" 1)"
assert_ok "resolve_action $RS2 $MYENT" "and hits you"
check "$(logged "player $MYENT was slain by $SKEL2")" "you are slain"
assert_eq "$(row_count "SELECT * FROM challenge WHERE kind >= 100 AND kind <= 103 AND entity_id = $MYENT")" "0" "slain mid-round: the round is withdrawn (no chop pose over the death)"
sleep 2
assert_eq "$(sql_first "SELECT is_dead FROM health_state WHERE entity_id = $MYENT" 1)" "false" "a second on you are up"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $MYENT" 1)" "$(sql_first "SELECT max FROM health_state WHERE entity_id = $MYENT" 1)" "whole"
check "$(python -c "
import re
v = [float(x) for x in re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', '''$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $MYENT" 1)''')][:3]
print('true' if abs(v[0]) < 0.5 and abs(v[2] - 8.0) < 0.5 else 'false')
")" "at the spawn"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the test referee unregistered"
done
assert_ok 'reset_rule "regents.foe_corpse_s"' "(test) rules back"
assert_ok 'reset_rule "regents.foe_respawn_s"' "(test) rules back"
assert_ok 'reset_rule "regents.player_respawn_s"' "(test) rules back"

# --- THE YEW BOW (owner, 2026-10-20): draw, loose at a target (the server aims and rolls), what an arrow
# hits (the referee reports it), point blank, the arrows used and the share back from a kill ---
assert_ok "grant_item $MYENT 40020 1" "an admin gives a yew bow"
assert_ok "grant_item $MYENT 40022 3" "and three copper arrows"
BOW_ROW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40020" 1)"
assert_ok "wield $BOW_ROW" "wield the bow"
assert_rejected "loose_arrow 0 {\"x\":0.0,\"y\":0.0,\"z\":-1.0}" "draw first" "a loose with no draw is refused"
SKB="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_1'" 1)"
assert_ok 'teleport {"x":33.0,"y":0.0,"z":9.0}' "stand ten metres from skeleton_1"
C_CODE4='"regentsbowrefereecode"'
bow_referee() {   # the stand-in referee leaves with each CLI call: claimed again before a shot
  # (the last one revoked first: an offer is refused while it still counts as running, and then it lapses)
  for OLD_REF in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
    spacetime call "$DB" revoke_authority "$OLD_REF" >/dev/null 2>&1
  done
  spacetime call "$DB" offer_referee 0 "$C_CODE4" >/dev/null 2>&1
  spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE4" >/dev/null 2>&1
}
newest_arrow() { sql_rows "SELECT entity_id FROM body_state WHERE owner_id = $MYENT AND def_id = 40001" | tr -d ' ' | sort -n | tail -1; }
hit_report() {   # hit_report ARROW TARGET Z: the referee says the arrow hit TARGET at (33, 1, Z)
  assert_ok "report_body_contacts 0 [{\"body_id\":$1,\"other_id\":$2,\"pos\":{\"x\":33.0,\"y\":1.0,\"z\":$3},\"normal\":{\"x\":0.0,\"y\":0.0,\"z\":1.0},\"speed\":40.0}]" "$4"
}
bow_referee
assert_ok "draw_bow true" "draw"
check "$(logged "entity $MYENT: status [0-9]+ -> 107 \(Drawing\)")" "Drawing: a walk, no sprint or jump"
sleep 0.9
assert_ok "loose_arrow $SKB {\"x\":0.0,\"y\":0.0,\"z\":-1.0}" "a full draw loosed at the skeleton"
check "$(logged "$MYENT looses at $SKB \(10\.[0-9] m, [0-9]+ % to hit\)")" "the server aimed it at the skeleton and rolled the hit"
assert_eq "$(QTY 40022)" "2" "it took an arrow"
A1="$(newest_arrow)"
check "$( [ -n "$A1" ] && echo true || echo false)" "an arrow is in the world, flown by the referee ($A1)"
SH0="$(sql_first "SELECT current FROM health_state WHERE entity_id = $SKB" 1)"
AXP0="$(xp_of 40008)"
hit_report "$A1" "$SKB" -1.0 "the referee: it hit the skeleton"
SH1="$(sql_first "SELECT current FROM health_state WHERE entity_id = $SKB" 1)"
check "$(python -c "print('true' if abs(($SH0 - $SH1) - 30.0) < 1e-3 else 'false')")" "a full draw from ten metres: the shot's 30 ($SH0 -> $SH1)"
check "$(python -c "print('true' if $(xp_of 40008) > $AXP0 else 'false')")" "archery XP"
assert_eq "$(row_count "SELECT * FROM entity WHERE entity_id = $A1")" "0" "and the arrow is gone"
# Point blank: a quick draw, hitting two metres from where it left the bow.
bow_referee
assert_ok "draw_bow true" "draw again"
assert_ok "loose_arrow $SKB {\"x\":0.0,\"y\":0.0,\"z\":-1.0}" "loosed at once"
A2="$(newest_arrow)"
hit_report "$A2" "$SKB" 7.0 "it hit two metres out"
SH2="$(sql_first "SELECT current FROM health_state WHERE entity_id = $SKB" 1)"
check "$(python -c "d = $SH1 - $SH2; print('true' if 0 < d <= 30.0 * 0.6 + 1e-3 else 'false')")" "point blank: at most 60 % of a full 30 ($SH1 -> $SH2)"
# The last arrow kills it: three stuck in it, 40 % of them (one) back to the bag.
assert_ok "apply_damage $SKB $(python -c "print($SH2 - 1)") 0" "(test) worn down to 1"
bow_referee
assert_ok "draw_bow true" "draw the last arrow"
sleep 0.9
assert_ok "loose_arrow $SKB {\"x\":0.0,\"y\":0.0,\"z\":-1.0}" "loosed"
assert_eq "$(QTY 40022)" "0" "no arrows left in the bag"
A3="$(newest_arrow)"
hit_report "$A3" "$SKB" -1.0 "it hit"
assert_eq "$(sql_first "SELECT is_dead FROM health_state WHERE entity_id = $SKB" 1)" "true" "the skeleton falls to it"
assert_eq "$(QTY 40022)" "1" "and one of the three arrows in it comes back (40 %)"
# Free aim: no target, it flies the way you look.
bow_referee
assert_ok "draw_bow true" "draw"
assert_ok "loose_arrow 0 {\"x\":1.0,\"y\":0.0,\"z\":0.0}" "loosed with no target, aimed east"
A4="$(newest_arrow)"
A4_VEL="$(sql_first "SELECT vel FROM movement_state WHERE entity_id = ${A4:-0}" 1)"
check "$(python -c "
import re, sys
v = [float(x) for x in re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.argv[1])][:3]
print('true' if len(v) == 3 and v[0] > 15 and abs(v[2]) < 0.5 else 'false')
" "$A4_VEL")" "it flies east, as aimed ($A4_VEL)"
assert_rejected "draw_bow true" "no arrows" "out of arrows, no draw"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the test referee unregistered"
done
spacetime call "$DB" draw_bow false >/dev/null 2>&1   # never leave the section drawn (a walk's bound)
assert_ok "wield $AXE_ROW" "the axe again"

# --- THE STAFF (owner, 2026-10-20, LOOT_AND_STYLES §4): mana on wielding it; a Bolt; Fireball's cast, splash
# and burn; a cast let go costs nothing; Frost Ring's slow; Blink; too little mana; Gale's push ---
xyz() { python -c "
import re, sys
v = [float(x) for x in re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.argv[1])][:3]
print(' '.join('%.3f' % x for x in v))
" "$1"; }
vec() { printf '{"x":%s,"y":%s,"z":%s}' "$1" "$2" "$3"; }
newest_body() { sql_rows "SELECT entity_id FROM body_state WHERE owner_id = $MYENT AND def_id = $1" | tr -d ' ' | sort -n | tail -1; }
HP() { sql_first "SELECT current FROM health_state WHERE entity_id = $1" 1; }
MANA() { sql_first "SELECT stored FROM resource_state WHERE entity_id = $MYENT AND resource_id = 40001" 1; }
assert_ok "grant_item $MYENT 40023 1" "an admin gives a yew staff"
STAFF_ROW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40023" 1)"
assert_ok "wield $STAFF_ROW" "wield it"
assert_eq "$(MANA)" "100" "wielding it gives you mana, full"
SK2="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_2'" 1)"
SK3="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'skeleton_3'" 1)"
read -r X2 Y2 Z2 <<< "$(xyz "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $SK2" 1)")"
read -r X3 Y3 Z3 <<< "$(xyz "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $SK3" 1)")"
NORTH="$(vec 0.0 0.0 -1.0)"
NONE="$(vec 0.0 0.0 0.0)"
assert_ok "teleport $(vec "$X2" 0.0 "$(python -c "print($Z2 + 8)")")" "stand eight metres south of skeleton_2"
assert_rejected "cast_spell 40014 0 $NORTH $(vec "$X3" "$Y3" "$Z3")" "needs Sorcery rank 3" "Frost Ring needs Sorcery rank 3"
bow_referee
H0="$(HP "$SK2")"
assert_ok "cast_spell 40012 $SK2 $NORTH $NONE" "a Bolt at skeleton_2"
B1="$(newest_body 40002)"
check "$( [ -n "$B1" ] && echo true || echo false)" "a bolt flies, flown by the referee ($B1)"
assert_eq "$(row_count "SELECT * FROM spell_cooldown WHERE entity_id = $MYENT AND ability = 40012")" "1" "the Bolt's own cooldown begun"
SXP0="$(xp_of 40009)"
assert_ok "report_body_contacts 0 [{\"body_id\":$B1,\"other_id\":$SK2,\"pos\":$(vec "$X2" 1.0 "$Z2"),\"normal\":$NORTH,\"speed\":30.0}]" "the referee: it hit"
check "$(python -c "print('true' if abs(($H0 - $(HP "$SK2")) - 9.0) < 1e-3 else 'false')")" "the Bolt's 9 ($H0 -> $(HP "$SK2"))"
check "$(python -c "print('true' if $(xp_of 40009) > $SXP0 else 'false')")" "Sorcery XP"
sleep 0.7
assert_ok 'set_rule "regents.cast_time_pct" 500.0 ""' "(test) casts five times slower, so a CLI can see one going"
bow_referee
assert_ok "cast_spell 40013 $SK2 $NORTH $NONE" "Fireball: a 0.6 s cast (3 s at the test's pace)"
assert_eq "$(row_count "SELECT * FROM casting WHERE entity_id = $MYENT")" "1" "being cast"
assert_eq "$(MANA)" "100" "not paid until it lands"
assert_rejected "cast_spell 40012 $SK2 $NORTH $NONE" "already casting" "one cast at a time"
bow_referee
H2="$(HP "$SK2")"; H3="$(HP "$SK3")"
# (A missile lives 3 s: its hit is reported the moment it flies, before anything else is read.)
for _ in $(seq 1 30); do F1="$(newest_body 40003)"; [ -n "$F1" ] && break; sleep 0.1; done
assert_ok "report_body_contacts 0 [{\"body_id\":$F1,\"other_id\":$SK2,\"pos\":$(vec "$X3" 1.0 "$Z3"),\"normal\":$NORTH,\"speed\":20.0}]" "it hits skeleton_2 beside skeleton_3"
check "$( [ -n "$F1" ] && echo true || echo false)" "a fireball flew when the cast landed ($F1)"
assert_eq "$(row_count "SELECT * FROM casting WHERE entity_id = $MYENT")" "0" "landed"
assert_eq "$(MANA)" "75" "and paid: 25 mana"
check "$(logged "$MYENT's spell hit $SK2 for 20\.0")" "Fireball's 20 to skeleton_2 (the server's log of the hit)"
assert_rejected "cast_spell 40013 $SK2 $NORTH $NONE" "not ready" "Fireball again at once: its own 7 s cooldown"
assert_ok 'reset_rule "regents.cast_time_pct"' "(test) casts back to their pace"
check "$(python -c "print('true' if abs(($H3 - $(HP "$SK3")) - 8.0) < 1e-3 else 'false')")" "and 40 % (8) to skeleton_3 within 3 m ($H3 -> $(HP "$SK3"))"
assert_eq "$(sql_first "SELECT dps FROM burning WHERE entity_id = $SK2" 1)" "3" "skeleton_2 burns, 3 a second"
for _ in $(seq 1 25); do [ "$(row_count "SELECT * FROM burning WHERE entity_id = $SK2")" = "0" ] && break; sleep 0.2; done
check "$(python -c "d = $H2 - $(HP "$SK2"); print('true' if 28.0 <= d <= 29.1 else 'false')")" "its fire out after 3 s: the hit's 20 and about 9 of fire, 3 a second ($H2 -> $(HP "$SK2"))"
assert_ok "grant_xp $MYENT 40009 5000" "(test) Sorcery to rank 10"
FROST_AT="$(vec "$X3" "$Y3" "$Z3")"
assert_rejected "cast_spell 40014 0 $NORTH $(vec "$X2" 0.0 "$(python -c "print($Z2 - 40)")")" "too far" "Frost Ring past its 20 m"
M0="$(MANA)"
assert_ok "cast_spell 40014 0 $NORTH $FROST_AT" "Frost Ring on skeleton_3: a 1 s cast"
assert_ok "cancel_cast" "let go"
assert_eq "$(row_count "SELECT * FROM casting WHERE entity_id = $MYENT")" "0" "a cast let go: gone"
assert_eq "$(MANA)" "$M0" "and costs nothing"
assert_ok "cast_spell 40014 0 $NORTH $FROST_AT" "Frost Ring again"
sleep 1.15
assert_eq "$(sql_first "SELECT landed FROM spell_area WHERE owner = $MYENT" 1)" "false" "cast: its circle on the ground, landing in a second"
assert_ok "cast_spell 40015 0 $(vec 1.0 0.0 0.0) $NONE" "Blink east"
# The circle lands a second after it was cast; its Slowed lasts 3 s. Looked for at once (the CLI calls
# below can outlast it on a busy machine).
for _ in $(seq 1 10); do [ "$(sql_first "SELECT status FROM status_state WHERE entity_id = $SK3" 1)" = "108" ] && break; sleep 0.2; done
assert_eq "$(sql_first "SELECT status FROM status_state WHERE entity_id = $SK3" 1)" "108" "it landed: skeleton_3 is Slowed"
read -r BX BY BZ <<< "$(xyz "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $MYENT" 1)")"
check "$(python -c "print('true' if abs($BX - ($X2 + 8)) < 0.05 and abs($BZ - ($Z2 + 8)) < 0.05 else 'false')")" "eight metres east, at once ($BX, $BZ)"
assert_ok "teleport $(vec "$X2" 0.0 "$(python -c "print($Z2 + 5)")")" "five metres south of skeleton_2"
assert_ok 'set_rule "regents.mana_cost_pct" 300.0 ""' "(test) spells three times dearer: Gale 105, more than mana holds"
assert_rejected "cast_spell 40016 0 $NORTH $NONE" "not enough mana" "too little mana: refused, nothing spent"
assert_ok 'reset_rule "regents.mana_cost_pct"' "(test) costs back"
sleep 1.0
sleep 1.0
assert_eq "$(row_count "SELECT * FROM spell_area WHERE owner = $MYENT")" "0" "and the circle is gone after its moment"
sleep 1.0
H5="$(HP "$SK2")"
assert_ok "cast_spell 40016 0 $NORTH $NONE" "Gale, the mana back"
assert_eq "$(row_count "SELECT * FROM push WHERE entity_id = $SK2 AND by_id = $MYENT")" "1" "skeleton_2 is thrown back"
check "$(logged "$MYENT's spell hit $SK2 for 7\.6")" "and hurt: Gale's 6 at Sorcery 10 (+27 %: 7.6, the server's log)"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the test referee unregistered"
done
assert_ok "wield $AXE_ROW" "the axe again"
assert_eq "$(row_count "SELECT * FROM resource_state WHERE entity_id = $MYENT AND resource_id = 40001")" "1" "your mana stays yours, as it was"

assert_ok "unwield" "put the axe away"
assert_eq "$(row_count "SELECT * FROM wielded WHERE entity_id = $MYENT")" "0" "nothing wielded"
assert_rejected "block true" "wield a weapon" "and nothing to block with"

assert_ok "set_world_level 0 0" "back to the greybox"
assert_eq "$(row_count 'SELECT * FROM gather_node')" "0" "a level change takes the glade's nodes away"
assert_eq "$(row_count 'SELECT * FROM station')" "0" "and its stations"
assert_eq "$(row_count 'SELECT * FROM work_order')" "0" "and its board's orders"
assert_eq "$(row_count 'SELECT * FROM dummy')" "0" "and its dummies"
assert_eq "$(row_count 'SELECT * FROM foe')" "0" "and its foes"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 103 OR kind = 104')" "0" "and their bodies"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 100 OR kind = 101')" "0" "and their entities"
