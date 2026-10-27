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
assert_eq "$(row_count 'SELECT * FROM gather_node WHERE world_id = 0')" "29" "its 29 nodes are placed (17 trees, 5 copper, 4 iron and 3 coal rocks)"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 100')" "29" "each an entity of the node kind (100)"
assert_eq "$(row_count 'SELECT * FROM station WHERE world_id = 0')" "4" "and its four stations: a furnace, an anvil, a workbench, the order board"
assert_eq "$(row_count 'SELECT * FROM gather_node WHERE def_id = 40005')" "4" "four of the nodes iron rocks, by the points' tags"
TREE="$(node_at tree_1)"; TREE2="$(node_at tree_2)"; TREE3="$(node_at tree_3)"    # at (-9,0,-6), (-3,0,-11), (5,0,-8)
COPPER="$(node_at copper_1)"; IRON="$(node_at iron_1)"                            # at (14,0,16), (-18,0,18)
FURNACE="$(station_at furnace)"; ANVIL="$(station_at anvil)"; BENCH="$(station_at workbench)"   # at (-6,0,14), (-2,0,16.5), (4,0,15)
BOARD="$(station_at orders)"                                                                  # at (1,0,19)
# the newest work_result's XP at a target (the SQL has no ORDER BY: the highest id)
wr_xp() { sql_rows "SELECT id, xp FROM work_result WHERE entity_id = $MYENT AND target_id = $1" | tr -d ' ' | sort -t'|' -k1,1n | tail -1 | cut -d'|' -f2; }
log_of() { sql_first "SELECT $2 FROM recipe_log WHERE entity_id = $MYENT AND recipe_id = $1" 1; }
assert_eq "$(qty_of 40001) $(qty_of 40006)" "1 1" "the player was given a Copper axe and a Copper pickaxe"

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
assert_eq "$(round_field "$CID" payload)" "\"$TREE 40001 100\"" "its payload: the tree, its NodeDef, the copper axe's speed (100 %)"
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
# CHOOSING PARTS AND TRAITS (owner, 2026-10-23, MATERIALS.md step 3): craft_choosing takes the item in each part slot and
# the traits wanted, in order; each must be offered by a part picked, none twice. Steady is 40001 (oak), Springy 40002 (yew).
assert_rejected "craft_choosing $BENCH 40006 false [40010] []" "takes a handle there" "craft_choosing: a copper bar is no handle"
assert_rejected "craft_choosing $BENCH 40006 false [40013] [40001]" "offers no trait 40001" "a plain handle offers no Steady"
assert_rejected "craft_choosing $BENCH 40006 false [40016] [40002]" "offers no trait 40002" "an oak handle offers no Springy (the yew's)"
assert_rejected "craft_choosing $BENCH 40006 false [40016] [40001,40001]" "wanted twice" "Steady twice: refused"
assert_rejected "craft_choosing $BENCH 40006 false [40016,40012,40013] [40001]" "takes 2 part(s), not 3" "three parts for two slots (a handle, a binding): refused"
assert_rejected "craft_choosing $BENCH 40006 false [40016,40013] [40001]" "takes a binding there" "a handle in the binding's slot: refused"
assert_rejected "craft_choosing $BENCH 40005 false [40016] []" "takes no part" "a plain handle's recipe has no part slot"
assert_rejected "craft_choosing $BENCH 40006 false [40016] [40001]" "needs 1 Oak handle" "an oak handle chosen: the bag must have one"
assert_ok "grant_item $MYENT 40016 1" "(an oak handle for it)"
assert_ok "grant_item $MYENT 40012 2" "(and two rivets)"
assert_ok "craft_choosing $BENCH 40006 false [40016] [40001]" "craft_choosing: an iron axe with the oak handle, Steady wanted"
# (The SQL prints an array bare, its numbers run together: [40016,40012] is "4001640012"; none: blank. The AFK work ends at once: the
# CLI's player is offline.)
assert_eq "$(sql_first "SELECT recipe_id FROM craft_choice WHERE entity_id = $MYENT" 1)" "40006" "the choice is kept for its batches: the iron axe's"
assert_eq "$(sql_rows "SELECT parts, traits FROM craft_choice WHERE entity_id = $MYENT" | sed -e 's/ *| */|/' -e 's/^ *//' -e 's/ *$//' )" "4001640012|40001" "kept as chosen: the oak handle and copper rivets (the binding's own), Steady"
assert_ok "craft_choosing $BENCH 40006 false [40016] []" "craft_choosing again, no trait wanted (none is a choice too)"
assert_eq "$(sql_rows "SELECT parts, traits FROM craft_choice WHERE entity_id = $MYENT" | sed -e 's/ *| */|/' -e 's/^ *//' -e 's/ *$//' )" "4001640012|" "kept: the parts, no trait"
assert_ok "work_stop" "stop (the playtest makes the axe for real)"
# AFTER LUKE'S PLAYTEST (2026-10-23): rivets offer traits (copper: Gentle 40009 on a tool, Thirsting 40006 on a weapon);
# a part's trait counts only where it fits; the head picked BY GRADE; a made item REFITTED at a cost.
assert_ok "craft_choosing $BENCH 40006 false [40016,40012] [40001,40009]" "an iron axe with oak and copper rivets: Steady and Gentle"
assert_rejected "craft_choosing $BENCH 40006 false [40016,40012] [40006]" "offers no trait 40006" "Thirsting is the rivets' for a WEAPON: an axe (a tool) is offered Gentle"
assert_rejected "craft_choosing $BENCH 40010 false [40016,40012] [40001]" "offers no trait 40001" "and a sword is offered no Steady (a tool's): the oak gives it Heavy"
assert_rejected "set_craft_grade 4" "grades are 0 to 2" "grade 4: refused"
# The heads in the bag first go (the one shaped in a round above may be any grade, even Masterwork), then exactly one Fine.
for row in $(sql_rows "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40014" | tr -d ' '); do
  assert_ok "consume_item $row 1" "(an iron axe head put away)"
done
assert_ok "admin_give_item $MYENT 40014 1 600" "(one Fine iron axe head, and no other)"
assert_ok "set_craft_grade 2" "make with Masterwork heads"
assert_rejected "craft_choosing $BENCH 40006 false [40016,40012] [40001]" "of grade 2" "no Masterwork head in the bag: refused, by grade"
assert_ok "set_craft_grade 1" "make with Fine heads"
assert_ok "craft_choosing $BENCH 40006 false [40016,40012] [40001]" "a Fine head in the bag: begun"
assert_eq "$(sql_first "SELECT grade FROM craft_grade WHERE entity_id = $MYENT" 1)" "1" "the grade is kept for its batches"
assert_ok "craft_with $BENCH 40006 false 40016" "an older build's craft (any grade)"
assert_eq "$(row_count "SELECT * FROM craft_grade WHERE entity_id = $MYENT")" "0" "takes the best of any grade: the grade picked is forgotten"
assert_ok "work_stop" "stop"
# REFIT: a Fine iron axe made before parts were noted (plain handle, copper rivets), an oak handle swapped in.
for row in $(sql_rows "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40011" | tr -d ' '); do
  assert_ok "consume_item $row $(sql_first "SELECT qty FROM inventory_item WHERE id = $row" 1)" "(no iron bars yet)"
done
assert_ok "admin_give_item $MYENT 40015 1 650" "(a Fine iron axe, quality 650)"
AXE_R="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40015 AND instance_data = '{\"q\":650}'" 1)"
OAK0="$(qty_of 40016)"
assert_rejected "refit $BENCH $AXE_R [40016,40012] [40001]" "it takes 2 Iron bar" "no iron bars: refused (a refit costs bars of the head's metal)"
assert_ok "grant_item $MYENT 40011 2" "(two iron bars)"
assert_rejected "refit $BENCH $AXE_R [40016,40012] [40006]" "offers no trait 40006" "a refit's traits: only what the parts offer an axe"
assert_rejected "refit $BENCH $(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40012" 1) [] []" "is not made of parts" "rivets are not made of parts: no refit"
assert_rejected "refit $BENCH 999999 [] []" "not in your bag" "a row that is not yours: refused"
assert_ok "refit $BENCH $AXE_R [40016,40012] [40001,40009]" "refit: the oak handle swapped in, Steady and Gentle"
assert_eq "$(sql_first "SELECT instance_data FROM inventory_item WHERE id = $AXE_R" 1)" "\"{\"q\":650,\"h\":40016,\"p\":[40016,40012],\"t\":[40001,40009]}\""   "the same row: its quality kept, its parts and its two traits (Fine holds two)"
assert_eq "$(qty_of 40016) $(qty_of 40011)" "$((OAK0 - 1)) 0" "the oak handle used up, the two iron bars paid"
assert_rejected "refit $BENCH $AXE_R [40016,40012] [40001,40009]" "how it is already" "the same again: nothing to change"

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
# What "the same again" gave goes: an order may want a tool (a steel axe since the material table), which would
# be the best axe below (found 2026-10-23: the round at the steel axe's 75 %, and "no axe" with one in the bag).
for row in $(sql_rows "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = $O_ITEM" | tr -d ' '); do
  assert_ok "consume_item $row $(sql_first "SELECT qty FROM inventory_item WHERE id = $row" 1)" "(the order's item again, put away)"
done
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
# The order board's orders are random: one that wanted a copper pickaxe took ours above (2026-10-24).
if [ -z "$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40006" 1)" ]; then
  assert_ok "grant_item $MYENT 40006 1" "(a copper pickaxe again: an order took ours)"
fi
PICK_ROW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40006" 1)"
assert_rejected "use_ability_seen 40006 0 $C_AIM 901 100" "wield an axe first" "nothing wielded: an axe's chop is refused"
assert_rejected "wield $PICK_ROW" "is no weapon" "a pickaxe is no weapon"
assert_rejected "wield 999999" "not in your bag" "nor is what is not in the bag"
assert_ok "wield $AXE_ROW" "wield the copper axe"
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
assert_eq "$(python -c "print(round($HP0 - $HP1, 2))")" "18.2" "11 + 15 damage at the copper axe's 70 %: 18.2 off the dummy"
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
# THE RING (template 1.0, this game's half): a ring client is sent only the cells round it, so every row of
# ours that draws a player (the weapon, the block) follows them over a cell's edge, in the same step
# (`follow_place`), and a placed thing's (the dummy's) is cut in the cell it stands in.
rcell() { python -c "import math; s = lambda v: max(-512, min(511, math.floor(v / 64.0))); print((s($1) + 512) * 1024 + s($2) + 512)"; }
R_HOME=$(rcell 7.0 21.5)
for t in wielded combat_state; do
  assert_eq "$(sql_first "SELECT chunk FROM $t WHERE entity_id = $MYENT" 1)" "$R_HOME" "$t is in the camp's cell"
done
assert_eq "$(sql_first "SELECT chunk FROM dummy WHERE entity_id = $DUMMY" 1)" "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $DUMMY" 1)" \
  "the dummy's row is in the cell it stands in"
assert_ok 'teleport {"x":200.5,"y":0.0,"z":-130.0}' "three cells east, three north"
R_FAR=$(rcell 200.5 -130.0)
for t in wielded combat_state; do
  assert_eq "$(sql_first "SELECT chunk FROM $t WHERE entity_id = $MYENT" 1)" "$R_FAR" "$t follows the player into their new cell"
done
assert_eq "$(row_count "SELECT * FROM wielded WHERE world_id = 0 AND chunk = $R_HOME AND entity_id = $MYENT")" "0" "and is no longer in the camp's"
assert_ok 'teleport {"x":7.0,"y":0.0,"z":21.5}' "back by the dummy"
assert_eq "$(sql_first "SELECT chunk FROM wielded WHERE entity_id = $MYENT" 1)" "$R_HOME" "the weapon comes back with them"
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
# --- TRAITS (template DECISIONS #275): what changes how a weapon plays, never its Power. A dev reducer
# gives them here (a designer trying one); the playtest makes a tool with a handle's. Ids: the content's
# (game/regents/content/trait/). ---
T_BALANCED=40003; T_HEAVY=40004; T_BRUTAL=40005; T_SWIFT=40007
assert_rejected "set_item_traits $AXE_ROW [99999]" "no trait 99999" "a trait that is not one: refused"
assert_rejected "set_item_traits $AXE_ROW [$T_SWIFT]" "is not on a copper axe" "Swift Draw is a bow's: refused on an axe"
C_CODE_T='"regentstraitsrefereecode"'
assert_ok "offer_referee 0 $C_CODE_T" "a referee for the traits"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE_T" >/dev/null 2>&1
sleep 1.0
HPT0="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_ok "use_ability_seen 40006 0 $C_AIM 931 100" "a plain chop"
W0="$(sql_first "SELECT wind_up_ms FROM swing WHERE entity_id = $MYENT" 1)"; L0="$(sql_first "SELECT lock_ms FROM swing WHERE entity_id = $MYENT" 1)"
assert_ok "resolve_action $(sql_first "SELECT id FROM action_request WHERE predicted_id = 931" 1) $DUMMY" "it hits the dummy"
HPT1="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_eq "$(python -c "print(round($HPT0 - $HPT1, 2))")" "7.7" "11 at the copper axe's 70 %: 7.7 (no traits)"
assert_ok "set_item_traits $AXE_ROW [$T_BALANCED,$T_BRUTAL]" "(dev) the axe made Balanced and Brutal"
check "$(sql_first "SELECT instance_data FROM inventory_item WHERE id = $AXE_ROW" 1 | grep -q "\"t\":\[$T_BALANCED,$T_BRUTAL\]" && echo true || echo false)" "its row carries them"
sleep 1.2
# A referee is online 5 s after it was last seen, and the CLI's never calls again: the calls above can take
# that long (failed twice on 2026-10-24), so a fresh one judges this chop.
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "(the first traits referee unregistered)"
done
# The dummy is whole again `regents.dummy_reset_s` after its last hit: wait for it, so the traited hit is
# measured from full health whatever the calls above took (a reset between the two hits read -0.77).
for _ in $(seq 1 20); do
  [ "$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)" = "500" ] && break
  sleep 0.5
done
HPT1="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_eq "$HPT1" "500" "(the dummy whole again before the traited chop)"
assert_ok "offer_referee 0 $C_CODE_T" "(a fresh referee for the traited chop)"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE_T" >/dev/null 2>&1
assert_ok "use_ability_seen 40006 0 $C_AIM 932 100" "a chop with the Balanced, Brutal axe"
L1="$(sql_first "SELECT lock_ms FROM swing WHERE entity_id = $MYENT" 1)"
assert_eq "$L1" "$(python -c "import math; print($W0 + int(math.floor(($L0 - $W0) * 0.85 + 0.5)))")" "Balanced: its recovery 15% shorter ($L0 -> $L1 ms, the wind-up $W0 as it was)"
assert_ok "resolve_action $(sql_first "SELECT id FROM action_request WHERE predicted_id = 932" 1) $DUMMY" "it hits the dummy"
HPT2="$(sql_first "SELECT current FROM health_state WHERE entity_id = $DUMMY" 1)"
assert_eq "$(python -c "print(round($HPT1 - $HPT2, 2))")" "6.93" "Brutal, the dummy above 30 %: a tenth less (7.7 -> 6.93)"
assert_ok "set_item_traits $AXE_ROW [$T_HEAVY]" "(dev) now Heavy"
sleep 1.2
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "(the last referee unregistered first)"
done
C_CODE_T2='"regentstraitsrefereecode2"'
assert_ok "offer_referee 0 $C_CODE_T2" "a fresh referee (a claim lapses in seconds)"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE_T2" >/dev/null 2>&1
assert_ok "use_ability_seen 40008 0 $C_AIM 933 100" "the overhead (the heavy) with the Heavy axe"
assert_ok "resolve_action $(sql_first "SELECT id FROM action_request WHERE predicted_id = 933" 1) $DUMMY" "it hits the dummy"
check "$(logged "$MYENT's hit staggered $DUMMY")" "Heavy: its heavy Staggers what it hits"
assert_eq "$(sql_first "SELECT status FROM status_state WHERE entity_id = $DUMMY" 1)" "103" "the dummy is Staggered"
assert_ok "set_item_traits $AXE_ROW []" "(dev) the axe plain again (what follows counts on it)"
check "$(sql_first "SELECT instance_data FROM inventory_item WHERE id = $AXE_ROW" 1 | grep -q '"t"' && echo false || echo true)" "no traits left on it"
assert_ok 'set_rule "foundation.trait_strength_pct" 0.0 ""' "(test) traits off"
assert_ok "set_item_traits $AXE_ROW [$T_BALANCED]" "(dev) Balanced again"
sleep 1.2
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "(the last referee unregistered first)"
done
C_CODE_T3='"regentstraitsrefereecode3"'
assert_ok "offer_referee 0 $C_CODE_T3" "a fresh referee"
spacetime call --anonymous "$DB" claim_referee 0 "$C_CODE_T3" >/dev/null 2>&1
assert_ok "use_ability_seen 40006 0 $C_AIM 934 100" "a chop, traits off"
assert_eq "$(sql_first "SELECT lock_ms FROM swing WHERE entity_id = $MYENT" 1)" "$L0" "the dial at 0: the kit's own lock"
assert_ok "resolve_action $(sql_first "SELECT id FROM action_request WHERE predicted_id = 934" 1) $DUMMY" "(its hit, so nothing is left waiting)"
assert_ok 'reset_rule "foundation.trait_strength_pct"' "(test) traits back on"
assert_ok "set_item_traits $AXE_ROW []" "(dev) the axe plain again"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the traits' referee unregistered"
done
sleep 5
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
# THE META (PROGRESS step 16): an alarm for a single hit, so this kill's period closes into one.
assert_ok 'set_rule "regents.meta_alarm_min_hits" 1.0 ""' "(test) a single hit can be a meta alarm"
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
CHOP_DMG="$(sql_first "SELECT damage FROM meta_tally WHERE weapon = 'axe'" 1)"
assert_eq "$(sql_first "SELECT hits FROM meta_tally WHERE weapon = 'axe'" 1)" "1" "the meta: one axe hit on a foe this period (the dummy's never count)"
check "$(python -c "print('true' if 2.0 < float('${CHOP_DMG:-0}') < 50.0 else 'false')")" "its damage, the chop's whole hit as XP counts it, past the 2 health it had left (${CHOP_DMG})"
assert_ok 'set_rule "regents.meta_period_s" 10.0 ""' "(test) the meta's period made 10 s: this hour's tally ends now"
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
# The meta's period ended while the camp waited: closed into meta_share, the tally gone.
for i in $(seq 1 15); do [ "$(row_count "SELECT * FROM meta_tally")" = "0" ] && break; sleep 1; done
assert_eq "$(row_count "SELECT * FROM meta_tally")" "0" "the meta: the period over, its tally is closed"
MS="$(sql_rows "SELECT weapon, hits, share_pct, alarm, period_s FROM meta_share" | tr -d ' ' | paste -sd, -)"
assert_eq "$MS" "\"axe\"|1|100|true|3600" "into one share: the axe, 1 hit, 100 % of the damage, an alarm past 45 %, its hour"
assert_ok 'reset_rule "regents.meta_period_s"' "(test) the meta by the hour again"
assert_ok 'reset_rule "regents.meta_alarm_min_hits"' "(test) and an alarm needs a busy hour"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $SKEL2" 1)" "120" "whole"
# A PLAYER SLAIN gets up at the spawn, whole; what they were working at stops.
assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "back beside tree_1"
assert_ok "set_status $TREE 0 0 \"\"" "tree_1 grows back (an admin: it was worked out above)"
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

# THE TESTER PAGE (owner, 2026-10-23): the admin sets any player's ranks, resets their skills, gives them items
# and resets their bag; nobody else may. (The page itself: game/regents/ui/tester_page.gd, the unit suite.)
MINING=40002
# A stranger's calls change NOTHING (checked by what is in the database, not by the words printed: a probe of
# the page's reducers with the admin check taken out printed nothing either way, 2026-10-23).
before() { echo "$(xp_of $MINING) $(row_count "SELECT * FROM recipe_log WHERE entity_id = $MYENT") $(qty_of 40024) $(row_count "SELECT * FROM inventory_item WHERE owner_entity_id = $MYENT")"; }
WAS="$(before)"
for verb in "admin_set_rank $MYENT $MINING 3" "admin_reset_skills $MYENT" "admin_give_item $MYENT 40024 5 0" "admin_reset_bag $MYENT"; do
  # shellcheck disable=SC2086
  out="$(spacetime call --anonymous "$DB" $verb 2>&1)"
  check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" "a stranger's ${verb%% *}: refused, admin only"
  assert_eq "$(before)" "$WAS" "and after a stranger's ${verb%% *}, the player's mining XP, recipe records, coal and bag are as they were"
done
assert_ok "admin_set_rank $MYENT $MINING 3" "the admin sets mining to rank 3"
assert_eq "$(xp_of $MINING)" "150" "mining's XP is rank 3's start (150)"
assert_ok "admin_set_rank $MYENT $MINING 1" "and back down to rank 1"
assert_eq "$(xp_of $MINING)" "0" "rank 1 is no XP"
assert_rejected "admin_set_rank $MYENT $MINING 11" "ranks 1 to 10" "rank 11: refused (mining has ten)"
assert_rejected "admin_set_rank $MYENT $MINING 0" "ranks 1 to 10" "rank 0: refused"
assert_rejected "admin_set_rank $MYENT 1 3" "no such skill" "a skill that is not: refused"
assert_rejected "admin_set_rank $(node_at copper_1) $MINING 3" "is no player" "a rock is no player: refused"
COAL0="$(qty_of 40024)"
assert_ok "admin_give_item $MYENT 40024 25 0" "the admin gives 25 coal"
assert_eq "$(qty_of 40024)" "$((COAL0 + 25))" "25 more coal in the bag"
assert_ok "admin_give_item $MYENT 40034 2 850" "the admin gives two steel axes at quality 850"
assert_eq "$(row_count "SELECT * FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40034 AND instance_data = '{\"q\":850}'")" "2" "two rows, each a Masterwork steel axe (q 850)"
assert_rejected "admin_give_item $MYENT 40034 21 500" "1 to 20" "21 axes at once: refused (one row each)"
assert_rejected "admin_give_item $MYENT 40024 0 0" "1 to 10000" "none: refused"
assert_rejected "admin_give_item $MYENT 49999 1 0" "no such item" "an item that is not: refused"
assert_ok "grant_xp $MYENT $MINING 500" "(some mining XP to reset)"
check "$([ "$(row_count "SELECT * FROM recipe_log WHERE entity_id = $MYENT")" -gt 0 ] && echo true || echo false)" "(recipes made above, on record)"
assert_ok "admin_reset_skills $MYENT" "the admin resets every skill"
assert_eq "$(row_count "SELECT * FROM skill_xp WHERE entity_id = $MYENT")" "0" "no XP left in any skill"
assert_eq "$(row_count "SELECT * FROM recipe_log WHERE entity_id = $MYENT")" "0" "no recipe on record (the first-make bonus back)"
assert_eq "$(row_count "SELECT * FROM order_filled WHERE entity_id = $MYENT")" "0" "no order filled"
AXE_NOW="$(sql_first "SELECT id FROM inventory_item WHERE owner_entity_id = $MYENT AND item_def_id = 40034" 1)"
assert_ok "wield $AXE_NOW" "wield a steel axe"
assert_ok "admin_reset_bag $MYENT" "the admin resets the bag"
assert_eq "$(row_count "SELECT * FROM inventory_item WHERE owner_entity_id = $MYENT")" "2" "two rows left: the starter kit"
assert_eq "$(qty_of 40001) $(qty_of 40006) $(qty_of 40024) $(qty_of 40034)" "1 1 0 0" "a Copper axe and a Copper pickaxe; no coal, no steel axe"
assert_eq "$(row_count "SELECT * FROM wielded WHERE entity_id = $MYENT")" "0" "the steel axe it held is put away"

# --- THE WORLD MAP'S DISCOVERY (Luke, 2026-10-26): a node is named once you have been near it ---
SEEN_TREE="$(node_at tree_1)"
seen_n() { row_count "SELECT * FROM node_seen WHERE entity_id = $MYENT"; }
assert_eq "$(seen_n)" "0" "nothing seen yet"
assert_ok 'teleport {"x":200.0,"y":0.0,"z":200.0}' "stand 280 m from tree_1"
assert_ok "saw_nodes [$SEEN_TREE]" "say tree_1 is near, from far away"
assert_eq "$(seen_n)" "0" "too far: not seen (the server measures, not the client)"
sleep 1
assert_ok 'teleport {"x":-9.0,"y":0.0,"z":-4.5}' "stand 1.5 m from tree_1"
assert_ok "saw_nodes [$SEEN_TREE,999999]" "tree_1 is near (and a nonsense id)"
assert_eq "$(sql_first "SELECT point_id FROM node_seen WHERE entity_id = $MYENT" 1 | tr -d ' "')" "tree_1" "tree_1 seen, by its point; the nonsense skipped"
sleep 1
assert_ok "saw_nodes [$SEEN_TREE]" "tree_1 again"
assert_eq "$(seen_n)" "1" "seen once only"
assert_rejected "saw_nodes [$(seq -s, 1 33)]" "at most 32" "33 at once: refused"
assert_eq "$(spacetime sql --anonymous "$DB" "SELECT * FROM node_seen" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" "0" "another player is sent none of them"

assert_ok "set_world_level 0 0" "back to the greybox"
assert_eq "$(row_count 'SELECT * FROM gather_node')" "0" "a level change takes the glade's nodes away"
assert_eq "$(row_count 'SELECT * FROM station')" "0" "and its stations"
assert_eq "$(row_count 'SELECT * FROM work_order')" "0" "and its board's orders"
assert_eq "$(row_count 'SELECT * FROM dummy')" "0" "and its dummies"
assert_eq "$(row_count 'SELECT * FROM foe')" "0" "and its foes"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 103 OR kind = 104')" "0" "and their bodies"
assert_eq "$(row_count 'SELECT * FROM entity WHERE kind = 100 OR kind = 101')" "0" "and their entities"
