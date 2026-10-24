#!/usr/bin/env bash
# Server integration tests: drives the PUBLISHED module through the spacetime CLI and asserts
# on real rows. `cargo test` cannot reach this code — module.rs is wasm-gated (DECISIONS #27),
# so reducer logic has no native unit tests and this script is its only automated coverage.
#
#   ./tests/integration_test.sh
#
# Requires: a local server (`spacetime start`) and the wasm32 target.
# Republishes the TEST database (umf-test) with --delete-data, and only ever on the `local` server;
# `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/genre_hooks.sh

# THE TEST DATABASE (DECISIONS #154): suites publish and play on `<database>-test` (shared/game.json), never on the
# database a person plays in. UMF_DB reaches every Godot process started from here.
. tests/lib/db.sh
SERVER=local
passes=0
failures=0

pass() { passes=$((passes + 1)); }
fail() { failures=$((failures + 1)); echo "  FAIL: $1" >&2; }
check() { if [ "$1" = "true" ]; then pass; else fail "$2"; fi }

# On stdout `spacetime sql` prints: header, dashes, then rows (the UNSTABLE warning goes to
# stderr, which is why the row data starts at line 3 and not 4).
sql_rows() { spacetime sql "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d'; }
sql_rows_anon() { spacetime sql --anonymous "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d'; }
row_count() { sql_rows "$1" | wc -l | tr -d ' '; }
# Column N of the first row, trimmed.
sql_first() {
  sql_rows "$1" | head -1 | awk -F'|' -v c="${2:-1}" '{gsub(/^[ \t]+|[ \t]+$/,"",$c); print $c}'
}
assert_eq() { if [ "$1" = "$2" ]; then pass; else fail "$3 (expected '$2', got '$1')"; fi }
# A reducer that must be refused, with a message containing $2.
assert_rejected() {
  local out; out="$(spacetime call "$DB" $1 2>&1)"
  if echo "$out" | grep -qi "$2"; then pass; else fail "$3 (output: $(echo "$out" | head -1))"; fi
}
assert_ok() {
  local out; out="$(spacetime call "$DB" $1 2>&1)"
  if echo "$out" | grep -qiE "^error|error:"; then fail "$2 ($(echo "$out" | head -1))"; else pass; fi
}

echo "== preflight =="
if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "ok"

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server "$SERVER" --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
sleep 3
echo "ok"

ADMIN=$(sql_first "SELECT identity FROM authority" 1)
echo "admin identity: $ADMIN"

echo "== init seeding =="
assert_eq "$(row_count 'SELECT * FROM world_config')" "1" "init creates exactly one world"
assert_eq "$(sql_first 'SELECT sim_authority FROM world_config' 1)" "0" "default world is MODULE"
assert_eq "$(sql_first 'SELECT authority_online FROM world_config' 1)" "true" "MODULE world is online"
assert_eq "$(row_count 'SELECT * FROM authority')" "1" "publisher seeded as the only authority"
assert_eq "$(sql_first 'SELECT role FROM authority' 1)" "0" "publisher has the admin role"
assert_eq "$(row_count 'SELECT * FROM session')" "1" "init creates the default session"
assert_eq "$(sql_first 'SELECT phase FROM session' 1)" "0" "default session starts in LOBBY"
run_genre_hooks integration_init   # what a genre's on_init sets up (fishing: the lakeside, its conditions, the rival)

echo "== client_connected =="
# The CLI's own sql connections count as clients, so a player row already exists.
MYENT=$(sql_first "SELECT entity_id FROM player WHERE identity = $ADMIN" 1)
check "$([ -n "$MYENT" ] && echo true || echo false)" "connecting created a player row"
assert_eq "$(row_count "SELECT * FROM movement_state WHERE entity_id = $MYENT")" "1" "player got movement_state"
assert_eq "$(row_count "SELECT * FROM health_state WHERE entity_id = $MYENT")" "1" "player got health_state"
# A NEW PLAYER'S HEALTH IS A HOT RULE (DECISIONS #201): the server's live `hot_rule` row, which
# starts at the rule set's value (foundation/content/rules/), not a number in module.rs.
RULE_HP="$(sql_first "SELECT number FROM hot_rule WHERE key = 'foundation.new_player_health'" 1)"
check "$([ -n "$RULE_HP" ] && echo true || echo false)" "the rule has its row"
assert_eq "$(sql_first "SELECT max FROM health_state WHERE entity_id = $MYENT" 1)" "$RULE_HP" \
  "a new player's health is the hot rule's ($RULE_HP)"
assert_eq "$(row_count "SELECT * FROM session_member WHERE entity_id = $MYENT")" "1" "player auto-joined the default session"
assert_eq "$(sql_first "SELECT world_id FROM entity WHERE entity_id = $MYENT" 1)" "0" "player is in the default world"
assert_eq "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $MYENT" 1)" \
  "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "a new player appears at its world's spawn"

echo "== levels: a world runs a baked level =="
run_genre_hooks integration_levels   # a genre's own level switching (fishing: use_level, its ponds)
# WHICH LEVEL A WORLD RUNS IS THE FOUNDATION'S (DECISIONS #175): any baked level, by its number. The
# foundation's example level is 200 (foundation/level/example/, baked into shared/world/).
out="$(spacetime call --anonymous "$DB" set_world_level 0 200 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" "only an admin switches a world's level"
assert_ok "set_world_level 0 200" "an admin switches world 0 to level 200, the example level (built in the editor)"
assert_eq "$(sql_first 'SELECT level_id FROM world_level WHERE world_id = 0' 1)" "200" "world_level says so"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 0, y = 0, z = 14)" "the spawn is the example bake's"
assert_rejected "set_world_level 0 9" "unknown level" "a level nobody baked is refused"
assert_eq "$(sql_first 'SELECT level_id FROM world_level WHERE world_id = 0' 1)" "200" "a refused switch changes nothing"
assert_ok "set_world_level 0 0" "switch the default world to the greybox"
assert_eq "$(sql_first 'SELECT level_id FROM world_level WHERE world_id = 0' 1)" "0" "the world now runs the greybox"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 0, y = 0, z = 0)" \
  "the greybox spawns at the origin"
assert_ok 'set_world_spawn 0 {"x":5.0,"y":1.0,"z":-3.0}' "an admin may move a world's spawn"
assert_eq "$(sql_first 'SELECT spawn FROM world_config WHERE world_id = 0' 1)" "(x = 5, y = 1, z = -3)" \
  "the spawn moved"
assert_rejected 'set_world_spawn 7 {"x":0.0,"y":0.0,"z":0.0}' "no world 7" "a spawn for a world that does not exist is refused"
out="$(spacetime call --anonymous "$DB" set_world_spawn 0 '{"x":1.0,"y":1.0,"z":1.0}' 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" \
  "a non-admin cannot move a spawn (output: $(echo "$out" | head -1))"
# Everything below was written against the greybox, with the admin's player at the origin.
assert_ok "set_world_level 0 0" "the rest of this suite runs on the greybox"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "bring the admin's player home"

echo "== worlds and authority =="
assert_ok "create_world 1 1" "admin can create a SIDECAR world"
assert_eq "$(sql_first 'SELECT authority_online FROM world_config WHERE world_id = 1' 1)" "false"   "a new SIDECAR world starts offline (no sidecar has heartbeated)"
assert_rejected "create_world 1 0" "already exists" "duplicate world_id is refused"
assert_rejected "create_world 2 9" "unknown sim_authority" "invalid sim_authority is refused"
assert_rejected "set_sim_authority 0 9" "unknown sim_authority" "invalid mode is refused on set"
assert_rejected "register_authority $ADMIN 1 1" "own admin role" "self-demotion is refused"
assert_rejected "register_authority 0x00 1 0" "specific world" "sidecar with wildcard world is refused"
assert_ok "register_authority 0x00 1 1" "sidecar for a specific world is accepted"
assert_eq "$(row_count 'SELECT * FROM authority')" "2" "authority table has admin + sidecar"

echo "== per-world ticking =="
T0_W0=$(sql_first "SELECT server_tick FROM world_config WHERE world_id = 0" 1)
sleep 2
T1_W0=$(sql_first "SELECT server_tick FROM world_config WHERE world_id = 0" 1)
check "$([ "$T1_W0" -gt "$T0_W0" ] && echo true || echo false)" "world 0 tick advances"
T1_W1=$(sql_first "SELECT server_tick FROM world_config WHERE world_id = 1" 1)
check "$([ "${T1_W1:-0}" -gt 0 ] && echo true || echo false)" "world 1 ticks independently of world 0"

# Registering the sidecar stamped last_seen, so check_authorities currently sees it as live.
# Once that window lapses with no heartbeat the 1 Hz watchdog must take the world back
# offline — that flag is what lets clients freeze interpolation instead of extrapolating.
echo "== authority heartbeat watchdog =="
sleep 8
assert_eq "$(sql_first 'SELECT authority_online FROM world_config WHERE world_id = 1' 1)" "false" \
  "watchdog marks the world offline once the heartbeat timeout lapses"
assert_ok "heartbeat 1" "an authority may heartbeat"
assert_eq "$(sql_first 'SELECT authority_online FROM world_config WHERE world_id = 1' 1)" "false" \
  "an ADMIN heartbeat does not bring a sidecar world online (DECISIONS #31)"

echo "== items and inventory =="
assert_ok 'seed_item_defs [{"item_def_id":1,"kind":0,"max_stack":20,"data":""},{"item_def_id":2,"kind":1,"max_stack":1,"data":""}]' \
  "catalogue seeds"
# Counted by id: a genre may seed items of its own at init (Regent's Rule's axe and logs).
assert_eq "$(row_count 'SELECT * FROM item_def WHERE item_def_id = 1 OR item_def_id = 2')" "2" "two item defs"
assert_ok 'seed_item_defs [{"item_def_id":1,"kind":0,"max_stack":20,"data":"v2"}]' "seeding is idempotent"
assert_eq "$(row_count 'SELECT * FROM item_def WHERE item_def_id = 1 OR item_def_id = 2')" "2" "re-seeding updates rather than duplicates"
assert_rejected 'seed_item_defs [{"item_def_id":3,"kind":0,"max_stack":0,"data":""}]' "max_stack must" \
  "max_stack 0 is refused"

assert_ok "grant_item $MYENT 1 25" "grant 25 of a max-20 stack"
assert_eq "$(row_count "SELECT * FROM inventory_item WHERE item_def_id = 1")" "2" "25 splits into two stacks"
assert_ok "grant_item $MYENT 1 10" "grant 10 more"
assert_eq "$(row_count "SELECT * FROM inventory_item WHERE item_def_id = 1")" "2" "top-up fills the partial stack, no new row"
assert_ok "grant_item $MYENT 2 3" "grant 3 unstackables"
assert_eq "$(row_count "SELECT * FROM inventory_item WHERE item_def_id = 2")" "3" "unstackables get a row each"
assert_rejected "grant_item $MYENT 99 1" "unknown item_def" "unknown item_def is refused"

ITEM=$(sql_first "SELECT id FROM inventory_item WHERE item_def_id = 2" 1)
assert_rejected "consume_item $ITEM 99" "cannot consume" "over-consume is refused"
assert_ok "consume_item $ITEM 1" "consume the whole stack"
assert_eq "$(row_count "SELECT * FROM inventory_item WHERE id = $ITEM")" "0" "fully consumed stack is deleted"

echo "== items on the ground: yours, then anyone's, then gone (DECISIONS #269) =="
GI=$(sql_first "SELECT id FROM inventory_item WHERE item_def_id = 1 AND qty = 20" 1)
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "stand at home"
assert_rejected "drop_item $GI 99" "cannot drop" "dropping more than the stack is refused"
assert_ok "drop_item $GI 5" "drop five at your feet"
assert_eq "$(sql_first "SELECT qty FROM inventory_item WHERE id = $GI" 1)" "15" "the stack is five lighter"
GR=$(sql_first "SELECT id FROM ground_item WHERE owner_id = $MYENT" 1)
assert_eq "$(sql_first "SELECT qty FROM ground_item WHERE id = $GR" 1)" "5" "five lie on the ground, yours"
GPOS="$(sql_first "SELECT pos FROM ground_item WHERE id = $GR" 1)"
check "$(python -c "
import re, sys
v = [float(x) for x in re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.argv[1])][:3]
print('true' if len(v) == 3 and abs((v[0] ** 2 + v[2] ** 2) ** 0.5 - 1.4) < 0.05 else 'false')
" "$GPOS")" "a step (1.4 m) in front of you, not at your feet ($GPOS)"
assert_eq "$(sql_first "SELECT anyone FROM ground_item WHERE id = $GR" 1)" "false" "yours alone for now"
assert_eq "$(sql_rows_anon "SELECT * FROM ground_item" | wc -l | tr -d ' ')" "0" "nobody else is even sent it (row-level security)"
out="$(spacetime call --anonymous "$DB" pick_up "$GR" 2>&1)"
if echo "$out" | grep -qiE "not yours|no player row"; then pass; else fail "someone else cannot take it while it is yours ($(echo "$out" | head -1))"; fi
assert_ok 'teleport {"x":10.0,"y":0.0,"z":0.0}' "walk ten metres off"
assert_rejected "pick_up $GR" "too far" "too far to pick up"
assert_ok 'teleport {"x":1.0,"y":0.0,"z":0.5}' "back beside it"
assert_ok "pick_up $GR" "pick it up"
assert_eq "$(sql_first "SELECT qty FROM inventory_item WHERE id = $GI" 1)" "20" "back in the bag"
assert_eq "$(row_count "SELECT * FROM ground_item WHERE id = $GR")" "0" "and gone from the ground"
assert_rejected "pick_up $GR" "it is gone" "what is gone cannot be picked up"
assert_ok "set_rule foundation.ground_owner_s 1 \"\"" "(test) yours for a second"
assert_ok "set_rule foundation.ground_public_s 6 \"\"" "(test) then anyone's for six (long enough for the queries below)"
assert_ok "drop_item $GI 1" "drop one"
GR2=$(sql_first "SELECT id FROM ground_item WHERE owner_id = $MYENT" 1)
sleep 2.2
assert_eq "$(sql_first "SELECT anyone FROM ground_item WHERE id = $GR2" 1)" "true" "a second on: anyone's"
assert_eq "$(sql_rows_anon "SELECT * FROM ground_item" | wc -l | tr -d ' ')" "1" "and everyone is sent it"
for _ in $(seq 1 40); do [ "$(row_count "SELECT * FROM ground_item WHERE id = $GR2")" = "0" ] && break; sleep 0.25; done
assert_eq "$(row_count "SELECT * FROM ground_item WHERE id = $GR2")" "0" "its time up: gone"
assert_ok "reset_rule foundation.ground_owner_s" "(test) rules back"
assert_ok "reset_rule foundation.ground_public_s" "(test) rules back"

echo "== chat: a line to the world you are in (DECISIONS #273) =="
# (Called directly: assert_ok splits its argument at spaces, and a line has them.)
out="$(spacetime call "$DB" send_chat '"  hello     there  "' 2>&1)"
if echo "$out" | grep -qiE "^error|error:"; then fail "say a line ($(echo "$out" | head -1))"; else pass; fi
CM=$(sql_first "SELECT id FROM chat_message WHERE entity_id = $MYENT" 1)
assert_eq "$(sql_first "SELECT text FROM chat_message WHERE id = $CM" 1)" '"hello there"' "kept as one line, its spaces tidied"
assert_eq "$(sql_first "SELECT world_id FROM chat_message WHERE id = $CM" 1)" "0" "in the world you are in"
assert_eq "$(sql_first "SELECT name FROM chat_message WHERE id = $CM" 1)" "$(sql_first "SELECT name FROM player WHERE entity_id = $MYENT" 1)" "with your name"
assert_eq "$(sql_rows_anon "SELECT * FROM chat_message WHERE id = $CM" | wc -l | tr -d ' ')" "1" "everyone is sent it"
out="$(spacetime call "$DB" send_chat '"   "' 2>&1)"
if echo "$out" | grep -qi "nothing to say"; then pass; else fail "nothing to say is not a line ($(echo "$out" | head -1))"; fi
CH_DIR="$(mktemp -d)"
for i in $(seq 1 12); do
  ( spacetime call "$DB" send_chat "\"flood $i\"" > "$CH_DIR/$i" 2>&1 ) &
done
wait
CH_REFUSED=$(grep -li "too many calls" "$CH_DIR"/* | wc -l | tr -d ' ')
rm -rf "$CH_DIR"
check "$([ "$CH_REFUSED" -ge 5 ] && echo true || echo false)" "twelve lines at once: the rest refused, too often ($CH_REFUSED refused)"
assert_ok "set_rule foundation.chat_keep_s 1 \"\"" "(test) a world keeps its lines a second"
for _ in $(seq 1 20); do [ "$(row_count "SELECT * FROM chat_message")" = "0" ] && break; sleep 0.25; done
assert_eq "$(row_count "SELECT * FROM chat_message")" "0" "then they are gone"
assert_ok "reset_rule foundation.chat_keep_s" "(test) rules back"

echo "== equip state: in hand or put away, reported by the owner (DECISIONS #160) =="
assert_eq "$(row_count "SELECT * FROM equip_state WHERE entity_id = $MYENT")" "0"   "nothing reported yet: no row (the client reads that as away)"
assert_ok "set_equip_state 1" "the owner reports a draw"
assert_eq "$(sql_first "SELECT state FROM equip_state WHERE entity_id = $MYENT" 1)" "1" "the row says drawing"
assert_eq "$(sql_first "SELECT world_id FROM equip_state WHERE entity_id = $MYENT" 1)" "0" "on the entity's own world"
assert_ok "set_equip_state 2" "then in hand"
assert_eq "$(row_count "SELECT * FROM equip_state WHERE entity_id = $MYENT")" "1" "one row per entity, updated in place"
assert_eq "$(sql_first "SELECT state FROM equip_state WHERE entity_id = $MYENT" 1)" "2" "the row says in hand"
assert_rejected "set_equip_state 4" "not a state" "a state there is not is refused"
assert_eq "$(sql_first "SELECT state FROM equip_state WHERE entity_id = $MYENT" 1)" "2" "and the refusal changes nothing"
assert_eq "$(sql_rows_anon "SELECT * FROM equip_state WHERE entity_id = $MYENT" | wc -l | tr -d ' ')" "1"   "public: another client sees it (that is the point: they play the draw)"
# The row goes with its entity between worlds, as every entity row does (the client subscribes
# to equip_state by world).
assert_ok "create_session 1 0 0" "an admin opens a session in world 1"
SESS1=$(sql_first "SELECT id FROM session WHERE world_id = 1" 1)
SESS0=$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)
assert_ok "join_session $SESS1" "the player joins it"
assert_eq "$(sql_first "SELECT world_id FROM equip_state WHERE entity_id = $MYENT" 1)" "1"   "and their equip state moves to world 1 with them"
assert_ok "leave_session" "they leave it"
assert_ok "join_session $SESS0" "and join the default session again"
assert_eq "$(sql_first "SELECT world_id FROM equip_state WHERE entity_id = $MYENT" 1)" "0" "and it is back on world 0"
assert_eq "$(sql_first "SELECT world_id FROM entity WHERE entity_id = $MYENT" 1)" "0" "with the entity"

echo "== the look a player chose (DECISIONS #166) =="
assert_eq "$(row_count "SELECT * FROM appearance WHERE entity_id = $MYENT")" "0" "no look chosen: no row (the look comes from the id)"
assert_ok 'set_appearance "ranger_f;hair=2;skin=4"' "a player chooses a look"
assert_eq "$(sql_first "SELECT look FROM appearance WHERE entity_id = $MYENT" 1)" '"ranger_f;hair=2;skin=4"' "the row says it"
assert_eq "$(sql_rows_anon "SELECT * FROM appearance WHERE entity_id = $MYENT" | wc -l | tr -d ' ')" "1" "public: every client dresses them by it"
assert_rejected 'set_appearance "Ranger_F"' "is not used in a look" "capitals are not how a look is spelled"
# A look with every piece swapped and dyed (DECISIONS #178) is well past the old 64 characters.
LONG_LOOK="wizard_f;arms=4;arms_dye=2;feet=4;feet_dye=2;hair=10;hairstyle=5;head=3;legs=4;legs_dye=2;neck=2;shoulders=4;skin=6;torso=4;torso_dye=2"
assert_ok "set_appearance \"$LONG_LOOK\"" "a look with every piece swapped is taken (${#LONG_LOOK} characters)"
assert_eq "$(sql_first "SELECT look FROM appearance WHERE entity_id = $MYENT" 1)" "\"$LONG_LOOK\"" "and the row holds all of it"
assert_ok 'set_appearance "ranger_f;hair=2;skin=4"' "back to the short one"
assert_rejected "set_appearance \"$(python -c "print('a' * 257)")\"" "at most 256" "nothing longer than 256"
assert_eq "$(sql_first "SELECT look FROM appearance WHERE entity_id = $MYENT" 1)" '"ranger_f;hair=2;skin=4"' "and a refusal changes nothing"
assert_ok 'set_appearance "ranger_f;hair=2;skin=4"' "the same look again (every connect sends it)"
assert_eq "$(row_count "SELECT * FROM appearance WHERE entity_id = $MYENT")" "1" "is still one row"
assert_ok 'set_appearance ""' "an empty look clears the choice"
assert_eq "$(row_count "SELECT * FROM appearance WHERE entity_id = $MYENT")" "0" "and the row goes"
assert_ok 'set_appearance "noble_m"' "choose again"
assert_ok "join_session $SESS1" "join world 1's session"
assert_eq "$(sql_first "SELECT world_id FROM appearance WHERE entity_id = $MYENT" 1)" "1" "the look moves to world 1 with them"
assert_eq "$(sql_first "SELECT session_id FROM lobby_member WHERE entity_id = $MYENT" 1)" "$SESS1" "and their lobby row is world 1's session's"
assert_ok "leave_session" "leave it"
assert_ok "join_session $SESS0" "back to the default session"
assert_eq "$(sql_first "SELECT world_id FROM appearance WHERE entity_id = $MYENT" 1)" "0" "and the look is back on world 0"

echo "== the lobby: ready and teams (DECISIONS #174) =="
assert_eq "$(row_count "SELECT * FROM lobby_member WHERE entity_id = $MYENT")" "1" "a member of a session has a lobby row"
assert_eq "$(sql_first "SELECT ready FROM lobby_member WHERE entity_id = $MYENT" 1)" "false" "not ready to begin with"
assert_rejected "set_team 1" "has no teams" "a game with no teams has none to pick"
assert_ok "set_session_phase 1 1" "a round under way"
assert_rejected "set_ready true" "already started" "ready is said in the lobby, not during a round"
assert_ok "set_session_phase 1 0" "back to the lobby"
assert_ok "set_ready true" "the only player here says ready"
assert_eq "$(sql_first 'SELECT phase FROM session WHERE id = 1' 1)" "1" \
  "and the round starts at once: everyone here is ready (rules.json: ready_up, min_players 1)"
assert_ok "set_session_phase 1 0" "a lobby again"
assert_eq "$(sql_first "SELECT ready FROM lobby_member WHERE entity_id = $MYENT" 1)" "true" \
  "an admin's phase change keeps the flags (only a new round clears them)"
assert_ok "set_ready false" "say not ready"
assert_eq "$(sql_first 'SELECT phase FROM session WHERE id = 1' 1)" "0" "and the lobby waits"

echo "== health =="
assert_ok "apply_damage $MYENT 30.0 999" "apply_damage lands"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $MYENT" 1)" "70" "100 - 30 = 70"
assert_eq "$(sql_first "SELECT last_damage_source FROM health_state WHERE entity_id = $MYENT" 1)" "999" "damage source recorded"
assert_ok "apply_damage $MYENT 9999.0 999" "lethal damage"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $MYENT" 1)" "0" "health clamps at 0"
assert_eq "$(sql_first "SELECT is_dead FROM health_state WHERE entity_id = $MYENT" 1)" "true" "is_dead flips"
# Who hurt it, for its loot (DECISIONS #268): a private tally per attacker.
assert_eq "$(sql_first "SELECT amount FROM damage_share WHERE target_id = $MYENT AND source_id = 999" 1)" "10029" "the tally: 999 dealt 30 + 9999"
# A negative amount heals — `current - amount` with amount < 0. `--` is needed because the CLI
# would otherwise read the leading minus as a flag.
out="$(spacetime call -- "$DB" apply_damage "$MYENT" -100.0 0 2>&1)"
if echo "$out" | grep -qiE "^error|error:"; then fail "negative damage heals ($(echo "$out" | head -1))"; else pass; fi
assert_eq "$(sql_first "SELECT is_dead FROM health_state WHERE entity_id = $MYENT" 1)" "false" "healing clears is_dead"

echo "== npc spawn / despawn =="
assert_ok 'spawn_npc 1 1 {"x":5.0,"y":0.0,"z":5.0}' "spawn an NPC into world 1"
NPC=$(sql_first "SELECT entity_id FROM entity WHERE kind = 1" 1)
assert_eq "$(sql_first "SELECT world_id FROM entity WHERE entity_id = $NPC" 1)" "1" "NPC is in world 1"
assert_rejected "despawn_entity $MYENT" "refusing to despawn a player" "despawn refuses player entities"
assert_ok "apply_damage $NPC 5.0 $MYENT" "the player hurts the NPC"
assert_eq "$(row_count "SELECT * FROM damage_share WHERE target_id = $NPC AND source_id = $MYENT")" "1" "a tally of who hurt it"
assert_ok "despawn_entity $NPC" "despawn the NPC"
assert_eq "$(row_count "SELECT * FROM entity WHERE entity_id = $NPC")" "0" "entity row gone"
assert_eq "$(row_count "SELECT * FROM damage_share WHERE target_id = $NPC")" "0" "and the tally of who hurt it"
assert_eq "$(row_count "SELECT * FROM movement_state WHERE entity_id = $NPC")" "0" "movement_state cascaded"
assert_eq "$(row_count "SELECT * FROM health_state WHERE entity_id = $NPC")" "0" "health_state cascaded"

echo "== row-level security =="
# Controls first: an anonymous identity must be able to read UNfiltered public tables, or a
# zero-row result below would prove nothing.
check "$([ "$(sql_rows_anon 'SELECT * FROM entity' | wc -l | tr -d ' ')" -gt 0 ] && echo true || echo false)" \
  "control: anonymous can read the unfiltered entity table"
assert_ok "issue_challenge $MYENT 0 0.5" "issue a challenge"
assert_eq "$(row_count 'SELECT * FROM challenge')" "1" "owner sees its own challenge"
assert_eq "$(sql_rows_anon 'SELECT * FROM challenge' | wc -l | tr -d ' ')" "0" "non-owner sees NO challenge rows"
assert_eq "$(sql_rows_anon 'SELECT * FROM input_queue' | wc -l | tr -d ' ')" "0" "non-authority sees NO input_queue rows"

echo "== challenge loop =="
CID=$(sql_first "SELECT id FROM challenge" 1)
SEED=$(sql_first "SELECT seed FROM challenge" 1)
SCORE_BEFORE=$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)
# Recompute the hit centres exactly as server/src/challenge.rs does. struct gives real float32
# rounding, so no numpy dependency.
CENTERS=$(python -c "
import struct, sys
f = lambda x: struct.unpack('<f', struct.pack('<f', x))[0]
M32 = 0xFFFFFFFF
def nxt(x):
    x &= M32
    x = (x ^ ((x << 13) & M32)) & M32
    x ^= (x >> 17)
    x = (x ^ ((x << 5) & M32)) & M32
    return x
seed = int('$SEED')
st = ((seed & M32) ^ ((seed >> 32) & M32)) & M32 or 1
out = []
for _ in range(3):
    st = nxt(st)
    out.append(f(f(0.15) + f(f(st >> 8) / f(16777216.0)) * f(0.7)))
print('[%.9f,%.9f,%.9f]' % tuple(out))
")
assert_ok "submit_challenge_result $CID $CENTERS" "submit a perfect play"
SCORE_AFTER=$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)
assert_eq "$((SCORE_AFTER - SCORE_BEFORE))" "100" "perfect play scores 100"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "challenge is consumed"

assert_ok "issue_challenge $MYENT 0 0.5" "issue a second challenge"
CID2=$(sql_first "SELECT id FROM challenge" 1)
SCORE_B2=$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)
assert_ok "submit_challenge_result $CID2 [0.5,0.5]" "malformed submission still returns Ok"
assert_eq "$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)" "$SCORE_B2" \
  "malformed submission awards nothing"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" \
  "malformed submission still consumes the challenge (no retry-probing)"

echo "== timed press: judged by the server's clock (DECISIONS #210) =="
# A skill check where the client sends only "pressed". The server works out where the marker was:
# the press's arrival, less half the player's quickest round trip it measured itself (the client
# acknowledges each one the moment it arrives), at most foundation.press_credit_cap_ms.
centers_of() {   # centers_of SEED -> "c0 c1 c2", as server/src/challenge.rs computes them (f32)
  python -c "
import struct
f = lambda x: struct.unpack('<f', struct.pack('<f', x))[0]
M32 = 0xFFFFFFFF
def nxt(x):
    x &= M32
    x = (x ^ ((x << 13) & M32)) & M32
    x ^= (x >> 17)
    x = (x ^ ((x << 5) & M32)) & M32
    return x
seed = int('$1')
st = ((seed & M32) ^ ((seed >> 32) & M32)) & M32 or 1
out = []
for _ in range(3):
    st = nxt(st)
    out.append(f(f(0.15) + f(f(st >> 8) / f(16777216.0)) * f(0.7)))
print(' '.join('%.6f' % c for c in out))
"
}
SCORE_P0=$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)
# The game acknowledges it straight after the issue, with only the read of its id between: the server
# keeps a round trip only under 5 s (RTT_SANE_MS), and on a busy machine the reads below, a CLI call
# each, took longer than that, so no round trip was kept and the presses were judged with no credit.
assert_ok "issue_challenge $MYENT 1 0.5" "issue a timed press (kind 1)"
TP=$(sql_first "SELECT id FROM challenge" 1)
assert_ok "challenge_seen $TP" "the player's game acknowledges it"
TP_SEED=$(sql_first "SELECT seed FROM challenge WHERE id = $TP" 1)
assert_eq "$(sql_first "SELECT kind FROM challenge WHERE id = $TP" 1)" "1" "it is a timed press"
assert_eq "$(sql_first "SELECT period_ms FROM timed_press WHERE challenge_id = $TP" 1)" "1800" \
  "its sweep frozen on its row: 1.8 s at difficulty 0.5 (between the rules' 2.4 s easy and 1.2 s hard)"
assert_eq "$(sql_first "SELECT rounds FROM timed_press WHERE challenge_id = $TP" 1)" "3" "three presses"
assert_eq "$(sql_rows_anon "SELECT * FROM timed_press" | wc -l | tr -d ' ')" "0" "private to its player (row-level security)"
SEEN=$(sql_first "SELECT seen_ms FROM timed_press WHERE challenge_id = $TP" 1)
check "$([ "$SEEN" -gt 0 ] && echo true || echo false)" "the server timed that round trip itself ($SEEN ms)"
assert_ok "challenge_seen $TP" "a second acknowledgement"
assert_eq "$(sql_first "SELECT seen_ms FROM timed_press WHERE challenge_id = $TP" 1)" "$SEEN" "changes nothing"
MINRTT=$(sql_first "SELECT min_ms FROM client_rtt WHERE entity_id = $MYENT" 1)
check "$([ -n "$MINRTT" ] && [ "$MINRTT" -le "$SEEN" ] && echo true || echo false)" "the player's quickest round trip is kept ($MINRTT ms)"
sleep 1
for i in 1 2 3; do assert_ok "challenge_press $TP" "press $i (no payload: only that it was pressed)"; sleep 0.2; done
assert_eq "$(row_count "SELECT * FROM challenge WHERE id = $TP")" "0" "three presses: scored and closed"
assert_eq "$(sql_first "SELECT done FROM timed_press WHERE challenge_id = $TP" 1)" "true" \
  "its sweep stays a moment, every press judged, so the player's game sees the last"
assert_rejected "challenge_press $TP" "no such challenge" "a fourth press is refused"
# The judgement, from the server's own record of it: each press judged at its arrival less the credit
# (half the quickest round trip, at most 120 ms), the marker where the sweep had it then, and the
# quality its distance from that press's target (the seed's).
JUDGED="$(spacetime logs "$DB" 2>/dev/null | grep "challenge $TP: press" | tail -3)"
SCORE_P1=$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)
TP_START=$(sql_first "SELECT starts_at FROM timed_press WHERE challenge_id = $TP" 1)
VERDICT=$(python - "$JUDGED" "$(centers_of "$TP_SEED")" "$MINRTT" "$((SCORE_P1 - SCORE_P0))" "$TP_START" <<'PY'
import re, sys
from datetime import datetime
lines = sys.argv[1].strip().splitlines()
centers = [float(c) for c in sys.argv[2].split()]
credit_want = min(int(sys.argv[3]) // 2, 120)
gained = int(sys.argv[4])
def when(t):   # an RFC 3339 time, to microseconds since the epoch
    t = t.strip().replace("Z", "+00:00")
    d, frac = (t.split("+")[0] + ".0").split(".")[:2]
    base = datetime.fromisoformat(d + "+00:00").timestamp()
    return int(base * 1_000_000) + int((frac + "000000")[:6])
start = when(sys.argv[5])
def sweep(t, p):
    if t <= 0: return 0.0
    ph = (t / p) % 1.0
    up = ph * 2
    return up if up <= 1 else 2 - up
qs = []
bad = []
for i, l in enumerate(lines):
    m = re.search(r"press (\d) at (-?\d+) ms \(credit (\d+) ms\): marker ([\d.]+), target ([\d.]+), quality ([\d.]+)", l)
    if not m: bad.append("unreadable: " + l); continue
    n, at, credit, marker, target, q = int(m[1]), int(m[2]), int(m[3]), float(m[4]), float(m[5]), float(m[6])
    if credit != credit_want: bad.append("press %d credit %d, want %d" % (n, credit, credit_want))
    arrived_ms = (when(l.split()[0]) - start) // 1000   # the log line's time is the press's arrival
    if abs(at - (arrived_ms - credit)) > 2: bad.append("press %d judged at %d ms, but it arrived at %d ms less %d" % (n, at, arrived_ms, credit))
    if abs(marker - sweep(at / 1000.0, 1.8)) > 0.002: bad.append("press %d marker %.3f, the sweep says %.3f" % (n, marker, sweep(at / 1000.0, 1.8)))
    if abs(target - centers[n - 1]) > 0.002: bad.append("press %d target %.3f, the seed says %.3f" % (n, target, centers[n - 1]))
    want_q = max(0.0, min(1.0, 1 - abs(marker - target) / 0.1))
    # The log prints the marker and target to 3 places; over a 0.1 half-width each rounding moves the
    # quality by up to 0.005, so 0.002 failed now and then on a correct judgement.
    if abs(q - want_q) > 0.011: bad.append("press %d quality %.3f, want %.3f" % (n, q, want_q))
    qs.append(q)
if len(qs) != 3: bad.append("%d presses judged" % len(qs))
elif abs(gained - round(sum(qs) / 3 * 100)) > 1: bad.append("scored %d, the presses say %d" % (gained, round(sum(qs) / 3 * 100)))   # 3-place qualities: the mean can round either way
print("ok" if not bad else "; ".join(bad))
PY
)
assert_eq "$VERDICT" "ok" "each press judged where the sweep had the marker at its arrival less the credit, against the seed's target, and scored their mean"

# CHOOSING A CHARACTER (DECISIONS #217): only a character marked playable; the template marks none
# (a game marks its own: Fowl Play's suite makes a hen a wolf and back).
assert_rejected "choose_character 1" "not a character you can play" "an NPC's kind is not a character a player may choose"
assert_rejected "choose_character 0" "not a character you can play" "nor, in the bare template, anything: it offers no characters"
assert_eq "$(sql_first "SELECT kind FROM entity WHERE entity_id = $MYENT" 1)" "0" "a refused choice changes nothing"
assert_ok "set_character_of $MYENT 1" "an authority may make any entity any kind (a bot a wolf; here, an NPC's)"
assert_eq "$(sql_first "SELECT kind FROM entity WHERE entity_id = $MYENT" 1)" "1" "and it is"
assert_ok "set_character_of $MYENT 0" "and back"

# A press is for a timed press; a timed press is never submitted.
assert_ok "issue_challenge $MYENT 0 0.5" "a timing bar (kind 0)"
BAR=$(sql_first "SELECT id FROM challenge" 1)
assert_rejected "challenge_press $BAR" "not a timed press" "is not pressed"
assert_ok "submit_challenge_result $BAR [0.5,0.5,0.5]" "(consumed)"
SCORE_P2=$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)
assert_ok "issue_challenge $MYENT 1 0.5" "a timed press"
TP2=$(sql_first "SELECT id FROM challenge" 1)
assert_ok "submit_challenge_result $TP2 [$(centers_of "$(sql_first "SELECT seed FROM challenge WHERE id = $TP2" 1)" | tr ' ' ',')]" \
  "submitted as if a bar, with the perfect answer"
assert_eq "$(sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1)" "$SCORE_P2" "nothing awarded: no outcome a client reports is accepted"
assert_eq "$(row_count "SELECT * FROM challenge")$(row_count "SELECT * FROM timed_press WHERE challenge_id = $TP2")" "00" "and it is consumed, its sweep with it"

# The credit is a rule: 0, and a press is judged on arrival.
assert_ok "set_rule foundation.press_credit_cap_ms 0 \"\"" "no credit for the trip"
assert_ok "issue_challenge $MYENT 1 0.5" "another"
TP3=$(sql_first "SELECT id FROM challenge" 1)
assert_ok "challenge_seen $TP3" "acknowledged"
assert_ok "challenge_press $TP3" "pressed"
assert_eq "$(sql_first "SELECT credit_ms FROM timed_press WHERE challenge_id = $TP3" 1)" "0" "judged on arrival"
assert_ok "reset_rule foundation.press_credit_cap_ms" "the cap back"
assert_ok "challenge_press $TP3" "finish it"
assert_ok "challenge_press $TP3" "(the last press)"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "no challenges outstanding"

echo "== interact: the SERVER decides range, not the client raycast =="
# Put a resource node far away, then next to the player, and check both answers.
assert_ok 'spawn_resource_node 0 {"x":100.0,"y":0.0,"z":100.0}' "spawn a distant resource node"
# The newest kind-2 entity (the highest id) is the one just inserted: not the last row, whose order
# the server does not promise (in Fowl Play, with its nests, it gave the far node). Taking the FIRST
# would pick a seeded pond spot, and this assertion would pass for the wrong reason.
FAR=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 2" | awk '{print $1}' | sort -n | tail -1)
assert_rejected "interact $FAR 0" "out of range" "interacting at 100 m is refused"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "a refused interact issues no challenge"

# Now one within reach. The player sits at the origin, so 1 m away is inside the 3 m check.
assert_ok 'spawn_resource_node 0 {"x":1.0,"y":0.0,"z":0.0}' "spawn a nearby resource node"
NEAR=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 2" | awk '{print $1}' | sort -n | tail -1)
assert_ok "interact $NEAR 0" "interacting in range is accepted"
assert_eq "$(row_count 'SELECT * FROM challenge')" "1" "a successful interact issues a challenge"
assert_eq "$(sql_first 'SELECT kind FROM challenge' 1)" "1" "the issued challenge is a timed press (judged by the server's clock, DECISIONS #210)"
assert_eq "$(sql_first 'SELECT difficulty FROM challenge' 1)" "0.35" "verb 0 issues the easier variant"

# Interacting with a player is refused: dispatch is by entity kind, not a catch-all.
assert_rejected "interact $MYENT 0" "nothing to do" "interacting with a player entity is refused"
assert_rejected "interact 999999 0" "no such entity" "interacting with a missing entity is refused"
# A GENRE'S OWN KIND (>= 100) goes to the genre's hook (game::on_interact, DECISIONS #154) instead
# of an arm in module.rs. Fishing claims no kind of its own, so the hook answers "nobody".
assert_ok 'spawn_npc 0 150 {"x":1.0,"y":0.0,"z":0.0}' "spawn an entity of a kind only a genre could own (150)"
GENRE_ENT=$(sql_first "SELECT entity_id FROM entity WHERE kind = 150" 1)
assert_rejected "interact $GENRE_ENT 0" "no game handles entity kind 150" \
  "using it reaches the genre's hook, which (fishing) claims no such kind"
assert_ok "despawn_entity $GENRE_ENT" "and it goes again"

# Consume the challenge this section raised. Leaving it outstanding would make the next
# section pick the wrong row — each section must hand back a clean slate.
INTERACT_CID=$(sql_first "SELECT id FROM challenge" 1)
assert_ok "submit_challenge_result $INTERACT_CID [0.5,0.5,0.5]" "consume the interact challenge"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "no challenges outstanding before the genre tests"

run_genre_hooks integration_genre   # a genre's own loop, on the greybox (fishing: cast, the fight, the catch, the bell)

echo "== rate limits: a flood of calls is refused (REVIEW 0.23.1 B3) =="
# Twenty renames at once, all from this player: set_player_name's budget (shared/rules.json
# rate_limits: 4 at once, half a call a second back) takes the first few and refuses the rest,
# each refusal saying why and changing nothing. Run in parallel so they land inside a second.
RL_DIR="$(mktemp -d)"
for i in $(seq 1 20); do
  ( spacetime call "$DB" set_player_name "\"Flood$i\"" > "$RL_DIR/$i" 2>&1 ) &
done
wait
RL_OK=0; RL_REFUSED=0
for i in $(seq 1 20); do
  if grep -qi "too many calls" "$RL_DIR/$i"; then RL_REFUSED=$((RL_REFUSED + 1));
  elif ! grep -qiE "^error|error:" "$RL_DIR/$i"; then RL_OK=$((RL_OK + 1)); fi
done
rm -rf "$RL_DIR"
check "$([ "$RL_OK" -ge 4 ] && [ "$RL_OK" -le 8 ] && echo true || echo false)" "the burst is taken ($RL_OK of 20 renames went through)"
check "$([ "$RL_REFUSED" -ge 12 ] && [ $((RL_OK + RL_REFUSED)) -eq 20 ] && echo true || echo false)" \
  "and the rest refused as too many calls ($RL_REFUSED refused)"
sleep 2.5
assert_ok 'set_player_name "Admin"' "after a pause the allowance has come back"
assert_eq "$(sql_first "SELECT name FROM player WHERE identity = $ADMIN" 1)" '"Admin"' "and the name is the last one taken"

echo "== names are unique; a player who is not here cannot be used (DECISIONS #202) =="
out="$(spacetime call --anonymous "$DB" set_player_name '" aDMIN "' 2>&1)"
check "$(echo "$out" | grep -q "is taken" && echo true || echo false)" \
  "another player cannot take a name someone holds, whatever its case and spacing (output: $(echo "$out" | grep -o "the name[^(]*is taken" | head -1))"
spacetime call --anonymous "$DB" set_player_name '"Gone Soon"' >/dev/null 2>&1
GONE="$(sql_first "SELECT entity_id FROM player WHERE name = 'Gone Soon'" 1)"
assert_eq "$(sql_first "SELECT online FROM player WHERE name = 'Gone Soon'" 1)" "false" \
  "a player whose client has gone is marked offline"
out="$(spacetime call "$DB" interact "$GONE" 0 2>&1)"
check "$(echo "$out" | grep -q "they are not here" && echo true || echo false)" \
  "and cannot be interacted with (output: $(echo "$out" | grep -o "they are not here" | head -1))"

echo "== Tier A trust: the envelope, correction epochs and the replay budget =="
# Runs LAST: it moves the CLI's own player, and every section above assumes it sits at the
# origin. The CLI disconnects after each call, so between calls this player is OFFLINE, which
# is exactly the "entity nobody is driving" path the idle tick exists for.
frame() {   # frame SEQ X Y Z EPOCH [MOVE_STATE] [LOOK_YAW] [FACE] [DASH]  -> one InputFrame as JSON
  printf '{"seq":%s,"client_tick":%s,"move_x":0.0,"move_y":0.0,"look_yaw":%s,"look_pitch":0.0,"jump":false,"sprint":false,"client_pos":{"x":%s,"y":%s,"z":%s},"epoch":%s,"move_state":%s,"dash":%s,"slow":false,"face":%s}' \
    "$1" "$1" "${7:-0.0}" "$2" "$3" "$4" "$5" "${6:-0}" "${9:-false}" "${8:-false}"
}
send_frames() {   # send_frames JSON_ARRAY
  local out; out="$(spacetime call "$DB" submit_input "$1" 2>&1)"
  if echo "$out" | grep -qiE "^error|error:"; then echo "  submit_input failed: $out" >&2; return 1; fi
  sleep 0.25   # a few 20 Hz ticks
}
pos_of() {   # -> "x y z" for MYENT
  sql_first "SELECT pos FROM movement_state WHERE entity_id = $MYENT" 1 \
    | python -c "import re,sys; v=re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.stdin.read()); print(' '.join(v[:3]))"
}
field() { sql_first "SELECT $1 FROM movement_state WHERE entity_id = $MYENT" 1; }
close_to() {   # close_to "x y z" X Y Z TOL -> true/false
  python -c "
a=[float(v) for v in '$1'.split()]; b=[$2,$3,$4]
print('true' if all(abs(p-q) <= $5 for p,q in zip(a,b)) else 'false')"
}

assert_eq "$(sql_first "SELECT world_id FROM entity WHERE entity_id = $MYENT" 1)" "0" \
  "the CLI player is in the MODULE-authority default world for this section"
SEQ=$(field last_processed_seq)
EPOCH=$(field correction_epoch)
read -r X0 Y0 Z0 <<< "$(pos_of)"

# 1. Inside the envelope the claim is taken EXACTLY. Bit-for-bit is what lets the owning
#    client's reconciliation see zero error in normal play.
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($X0 + 0.1)")" "$Y0" "$Z0" "$EPOCH")]"
read -r X1 Y1 Z1 <<< "$(pos_of)"
assert_eq "$(close_to "$X1 $Y1 $Z1" "$X0 + 0.1" "$Y0" "$Z0" 1e-6)" "true" "a claim inside the envelope is taken exactly"
assert_eq "$(field last_processed_seq)" "$SEQ" "the frame is acknowledged"
assert_eq "$(field correction_epoch)" "$EPOCH" "an honest frame does not start a correction"
assert_eq "$(field grounded)" "true" "no vertical motion reads as resting on something"

# FACING (DECISIONS #100, #136). Standing still and looking around does not turn the body, for
# everyone watching; a frame that is AIMING does, and the heading it aimed on then stays.
YAW0=$(field yaw)
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$X1" "$Y1" "$Z1" "$EPOCH" 0 1.25 false)]"
assert_eq "$(python -c "print('true' if abs($(field yaw) - $YAW0) < 1e-6 else 'false')")" "true" \
  "looking around standing still does not turn the body on the server"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$X1" "$Y1" "$Z1" "$EPOCH" 0 1.25 true)]"
assert_eq "$(python -c "print('true' if abs($(field yaw) - 1.25) < 1e-6 else 'false')")" "true" \
  "an AIMING frame turns the standing body to face the look (yaw $(field yaw))"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$X1" "$Y1" "$Z1" "$EPOCH" 0 -0.5 false)]"
assert_eq "$(python -c "print('true' if abs($(field yaw) - 1.25) < 1e-6 else 'false')")" "true" \
  "and when it stops aiming, the heading it aimed on stays"

# 2. STANDING ON SOMETHING the module cannot see. The old policy ran gravity against a client
#    standing on a box and dropped it through within ~1.5 s. Climb to 1.75 m (the greybox
#    platform top) like stairs: six frames up, then two at rest. Each CLI call disconnects, so
#    between calls this player is undriven — ending a call mid-air would hand it to the
#    gravity twin, which (correctly) throws it ballistically. A real client never pauses there.
climb_step() {   # climb_step FROM_Y TO_Y  -> six frames up, two at rest, one call
  local b="" y="$1" i
  for i in 1 2 3 4 5 6; do
    SEQ=$((SEQ + 1)); y=$(python -c "print(min($2, $y + 0.15))")
    b="$b$( [ -n "$b" ] && echo , )$(frame $SEQ "$X1" "$y" "$Z1" "$EPOCH")"
  done
  for i in 1 2; do
    SEQ=$((SEQ + 1)); b="$b,$(frame $SEQ "$X1" "$2" "$Z1" "$EPOCH")"
  done
  send_frames "[$b]"
}
climb_step "$Y0" 0.9
assert_eq "$(close_to "$(pos_of)" "$X1" 0.9 "$Z1" 1e-6)" "true" "first flight of stairs accepted"
climb_step 0.9 1.75
assert_eq "$(close_to "$(pos_of)" "$X1" 1.75 "$Z1" 1e-6)" "true" "the claimed climb onto raised geometry is accepted"
assert_eq "$(field grounded)" "true" "standing still on it reads as grounded"
sleep 1.5   # thirty ticks with nobody driving: long enough for any gravity to win
assert_eq "$(close_to "$(pos_of)" "$X1" 1.75 "$Z1" 1e-6)" "true"   "an undriven entity resting on raised geometry is NOT pulled through it by the module"

# 3. A SPEED HACK is clamped to the envelope and starts a correction epoch. THE ENVELOPE IS THE
#    PLAYER'S KIND'S (DECISIONS #205, #255): a frame's worth of its fastest character's sprint (x1.5
#    slack), worked out here as build.rs works it out from the game's content; its dash counts only in
#    a dash's window (#256). The foundation's humanoid: 8 m/s, no dash, 0.2 m; a game whose player rolls
#    (Regent's Rule) allows its dash on a dash press, and only then.
KIND0=$(sql_first "SELECT kind FROM entity WHERE entity_id = $MYENT" 1)
read -r STEP DSTEP <<< "$(python - "$KIND0" <<'PYEOF'
import glob, json, sys
kind = int(sys.argv[1])
cfg = json.load(open("shared/movement_config.json"))
default = (cfg["sprint_speed"], max(cfg.get("dash_impulse", 0.0), 0.0))
profiles = {}
for f in glob.glob("shared/content/*/movement.json"):
    for p in json.load(open(f))["items"]:
        profiles[p["id"]] = (p["sprint_speed"], max(p.get("dash_impulse", 0.0), 0.0))
best, profiled = None, False
for f in glob.glob("shared/content/*/character.json"):
    for c in json.load(open(f))["items"]:
        if c.get("kind", 0) != kind:
            continue
        lim = profiles.get(c.get("movement", -1), default)
        profiled = profiled or c.get("movement", -1) in profiles
        best = lim if best is None else (max(best[0], lim[0]), max(best[1], lim[1]))
if best is None or not profiled:
    best = default
print(round(best[0] * 1.5 / 60.0, 6), round((best[0] + best[1]) * 1.5 / 60.0, 6))
PYEOF
)"
if python -c "import sys; sys.exit(0 if $DSTEP > $STEP else 1)"; then
  # A DASH PRESS opens its window: that frame and the next may claim the dash's speed, unclamped. First a
  # frame standing still: the first frame after a correction stands for many (a replay, #258), not one.
  read -r XA YA ZA <<< "$(pos_of)"
  SEQ=$((SEQ + 1))
  send_frames "[$(frame $SEQ "$XA" "$YA" "$ZA" "$EPOCH")]"
  DX=$(python -c "print(round($DSTEP * 0.9, 4))")
  SEQ=$((SEQ + 1)); S2=$((SEQ + 1))
  send_frames "[$(frame $SEQ "$(python -c "print($XA + $DX)")" "$YA" "$ZA" "$EPOCH" 0 0.0 false true),$(frame $S2 "$(python -c "print($XA + 2 * $DX)")" "$YA" "$ZA" "$EPOCH")]"
  SEQ=$S2
  read -r XB YB ZB <<< "$(pos_of)"
  assert_eq "$(python -c "print('true' if abs(($XB - $XA) - 2 * $DX) < 1e-3 else 'false')")" "true"     "a dash press lets its frame and the next claim the dash's speed ($DX m a frame, past the sprint's $STEP; moved $(python -c "print(round($XB - $XA, 4))"))"
  assert_eq "$(field correction_epoch)" "$EPOCH" "unclamped: no correction"
  # Its window shuts (stand still a while); the speed hack below has no dash press, so only the sprint.
  for b in 1 2 3 4; do   # 20 frames, in batches the module takes (8 at most)
    F=""; for i in $(seq 1 5); do SEQ=$((SEQ + 1)); F="$F${F:+,}$(frame $SEQ "$XB" "$YB" "$ZB" "$EPOCH")"; done
    send_frames "[$F]"
  done
fi
read -r XA YA ZA <<< "$(pos_of)"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($XA + 5.0)")" "$YA" "$ZA" "$EPOCH")]"
read -r XB YB ZB <<< "$(pos_of)"
MOVED=$(python -c "print(round($XB - $XA, 4))")
assert_eq "$(python -c "print('true' if $STEP * 0.95 < $MOVED <= $STEP + 0.0001 else 'false')")" "true" \
  "a 5 m claim in one frame moves only the envelope's $STEP m (moved $MOVED)"
NEW_EPOCH=$((EPOCH + 1))
assert_eq "$(field correction_epoch)" "$NEW_EPOCH" "the clamp starts a new correction epoch"
assert_eq "$(row_count "SELECT * FROM correction WHERE entity_id = $MYENT AND from_seq = $SEQ")" "1" \
  "the module records where the correction started (private bookkeeping)"
CLAMP_SEQ=$SEQ

# 4. Frames from the OLD epoch were sent before the client could know. They are consumed and
#    move nothing — taking them is what made client and server chase each other forever.
SEQ=$((SEQ + 1)); S2=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($XA + 6.0)")" "$YA" "$ZA" "$EPOCH"),$(frame $S2 "$(python -c "print($XA + 7.0)")" "$YA" "$ZA" "$EPOCH")]"
SEQ=$S2
assert_eq "$(close_to "$(pos_of)" "$XB" "$YB" "$ZB" 1e-6)" "true" "old-epoch frames move nothing"
assert_eq "$(field last_processed_seq)" "$SEQ" "but they are consumed (acknowledged)"
assert_eq "$(field correction_epoch)" "$NEW_EPOCH" "and do not start yet another correction"

# 5. The first NEW-epoch frame carries the client's replay of everything since the correction:
#    ten frames later it may be a metre away, and that is accepted exactly, not clamped.
SEQ=$((CLAMP_SEQ + 10))
send_frames "[$(frame $SEQ "$(python -c "print($XB + 1.0)")" "$YB" "$ZB" "$NEW_EPOCH")]"
assert_eq "$(close_to "$(pos_of)" "$XB + 1.0" "$YB" "$ZB" 1e-6)" "true" \
  "the first frame of the new epoch may carry the replayed motion (1 m over 10 frames)"
assert_eq "$(field correction_epoch)" "$NEW_EPOCH" "so no further correction: ONE settles it"
assert_eq "$(row_count "SELECT * FROM correction WHERE entity_id = $MYENT")" "0" \
  "the correction bookkeeping is cleared once acknowledged"

# 6. That budget is bounded by REAL time. A client that skips a thousand seqs does not buy a
#    thousand frames of distance.
read -r XC YC ZC <<< "$(pos_of)"
SEQ=$((SEQ + 1))
# Taken BEFORE the clamp, so it is never later than the correction the module records: the
# elapsed times below are then an upper bound on the module's, and the allowance derived from
# them can only be generous, never accidentally strict.
T_CORRECTION=$(python -c "import time; print(time.time())")
send_frames "[$(frame $SEQ "$(python -c "print($XC + 5.0)")" "$YC" "$ZC" "$NEW_EPOCH")]"   # clamp: new epoch
E3=$(field correction_epoch)
read -r XD YD ZD <<< "$(pos_of)"
SEQ=$((SEQ + 1000))
# The allowance IS elapsed real time (frames = elapsed/CLIENT_DT * 1.5 + 6, each worth the frame's
# envelope, $STEP m), so both the claim and the bound are computed from the clock rather
# than hardcoded. With a fixed 100 m claim and a fixed 20 m bound this assertion passed or
# failed on how quick the CLI felt that minute: a slow run spent 2.2 s here, which legitimately
# allows 40 m, and the test called that a violation.
E_LOW=$(python -c "import time; print(round(time.time() - $T_CORRECTION, 3))")
ALLOWED_LOW=$(python -c "print(round($STEP * 90.0 * $E_LOW + $STEP * 6.0, 2))")
CLAIM=$(python -c "print(round(max(100.0, $ALLOWED_LOW * 4.0), 2))")
send_frames "[$(frame $SEQ "$(python -c "print($XD + $CLAIM)")" "$YD" "$ZD" "$E3")]"
E_HIGH=$(python -c "import time; print(round(time.time() - $T_CORRECTION, 3))")
ALLOWED_HIGH=$(python -c "print(round($STEP * 90.0 * $E_HIGH + $STEP * 6.0, 2))")
JUMP=$(python -c "print(round($(pos_of | awk '{print $1}') - $XD, 2))")
assert_eq "$(python -c "print('true' if 0 < $JUMP < $CLAIM * 0.5 else 'false')")" "true" \
  "a thousand-seq gap does not buy a thousand frames: $CLAIM m claimed, $JUMP m taken"
assert_eq "$(python -c "print('true' if $JUMP <= $ALLOWED_HIGH + 1.0 else 'false')")" "true" \
  "and what it buys is the real-time allowance: <= $ALLOWED_HIGH m after ${E_HIGH}s, took $JUMP m"

# 7. Seq GAPS are accepted. A lost batch or a reconnect leaves one, and refusing gaps froze the
#    player forever: every later frame was too far ahead.
E4=$(field correction_epoch)
read -r XE YE ZE <<< "$(pos_of)"
SEQ=$((SEQ + 50))
send_frames "[$(frame $SEQ "$(python -c "print($XE + 0.05)")" "$YE" "$ZE" "$E4")]"
assert_eq "$(field last_processed_seq)" "$SEQ" "a frame after a 50-seq gap is still accepted"

# 8. move_state: Tier A has no simulation to decide it, so the module MIRRORS the client's —
#    that is how everyone else animates this player — but only a state someone defined.
read -r XF YF ZF <<< "$(pos_of)"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$XF" "$YF" "$ZF" "$E4" 2)]"
assert_eq "$(field move_state)" "2" "the client's SPRINT is mirrored onto the row for everyone to see"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$XF" "$YF" "$ZF" "$E4" 50)]"
assert_eq "$(field move_state)" "2" "an undefined move_state (50: between foundation 0-7 and genre 100+) is not mirrored"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$XF" "$YF" "$ZF" "$E4" 101)]"
assert_eq "$(field move_state)" "101" "a genre move_state (>= 100) is mirrored"

# 9a. THE DEV TOOLS ARE OFF FOR PLAYERS (REVIEW 0.23.1 B1). A fresh publish has them off: a player
#     who is not an admin cannot teleport (past the rod-reach gate) or nudge itself, and cannot turn
#     them on. The admin (this CLI) still may. The suites whose clients teleport turn them on.
for verb in teleport dev_nudge; do
  out="$(spacetime call --anonymous "$DB" $verb '{"x":0.0,"y":0.0,"z":0.0}' 2>&1)"
  check "$(echo "$out" | grep -qi "dev tool" && echo true || echo false)" "a player's $verb is refused while the dev tools are off ($(echo "$out" | tail -1))"
done
out="$(spacetime call --anonymous "$DB" dev_push "$MYENT" '{"x":0.0,"y":5.0,"z":0.0}' 2>&1)"
check "$(echo "$out" | grep -qi "dev tool" && echo true || echo false)" "a player's dev_push is refused while the dev tools are off ($(echo "$out" | tail -1))"
out="$(spacetime call --anonymous "$DB" set_dev_tools true 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" "only an admin turns the dev tools on"
assert_ok "set_dev_tools true" "an admin turns the dev tools on"
out="$(spacetime call --anonymous "$DB" teleport '{"x":0.0,"y":0.0,"z":0.0}' 2>&1)"
check "$(echo "$out" | grep -qiE "^error|error:" && echo false || echo true)" "with them on, a player may teleport ($(echo "$out" | tail -1))"
assert_ok "set_dev_tools false" "and off again"
out="$(spacetime call --anonymous "$DB" teleport '{"x":0.0,"y":0.0,"z":0.0}' 2>&1)"
check "$(echo "$out" | grep -qi "dev tool" && echo true || echo false)" "off means off again"

# 9b. THE SERVER PUSHES (DECISIONS #251): a push is a row the pushed player's client applies (its bound
#     widened meanwhile: server/tests/push.rs, and tests/bodies_playtest.sh flies one uncorrected).
assert_ok "dev_push $MYENT {\"x\":0.0,\"y\":6.0,\"z\":200.0}" "an admin pushes their own player"
assert_eq "$(sql_first "SELECT vel FROM push WHERE entity_id = $MYENT" 1 | grep -c "39.9")" "1" "a push as hard as 200 m/s is written at the most (40, along itself)"
out="$(spacetime call "$DB" dev_push 987654321 '{"x":0.0,"y":5.0,"z":0.0}' 2>&1)"
check "$(echo "$out" | grep -qi "no such entity" && echo true || echo false)" "a push for nobody is refused ($(echo "$out" | tail -1))"

# 9. Overrides from reducers bump the epoch too (the admin's own, with the dev tools off).
assert_ok 'dev_nudge {"x":0.4,"y":0.0,"z":0.0}' "dev_nudge applies a correction"
assert_eq "$(field correction_epoch)" "$((E4 + 1))" "dev_nudge starts a new correction epoch"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "teleport back to the origin"
assert_eq "$(field correction_epoch)" "$((E4 + 2))" "a teleport starts a new correction epoch"
# (teleport_flag is set for exactly ONE tick by design; by the time the CLI can read the row the
# next tick has cleared it. The playtests assert what it is for: remote clients snap once.)

# 10. A FAR claim that is also LOWER (DECISIONS #149) — a restarted client's prediction, a lag
#     burst — is clamped as a WHOLE: it takes the same share of the drop as of the distance.
#     Clamped apart, the height was taken nearly in full: a player by the village, claimed at the
#     end of the dock 53 m off, was dropped to the dock's height 1.35 m below the ground, stuck.
#     Measured from RAISED ground, standing, as test 2 climbs to it: between CLI calls this player
#     is undriven, and on the flat ground_y plane the gravity twin would lift a sunk body back up
#     and hide the bug; up here it can only let it fall.
E5=$(field correction_epoch)
read -r XG YG ZG <<< "$(pos_of)"
climb_here() {   # climb_here FROM_Y TO_Y -> six frames up, two at rest, at (XG, ZG)
  local b="" y="$1" i
  for i in 1 2 3 4 5 6; do
    SEQ=$((SEQ + 1)); y=$(python -c "print(min($2, $y + 0.15))")
    b="$b$( [ -n "$b" ] && echo , )$(frame $SEQ "$XG" "$y" "$ZG" "$E5")"
  done
  for i in 1 2; do
    SEQ=$((SEQ + 1)); b="$b,$(frame $SEQ "$XG" "$2" "$ZG" "$E5")"
  done
  send_frames "[$b]"
}
climb_here "$YG" 0.9
climb_here 0.9 1.75
read -r XG YG ZG <<< "$(pos_of)"
assert_eq "$(python -c "print('true' if abs($YG - 1.75) < 1e-6 else 'false')")$(field grounded)" "truetrue" \
  "standing on raised ground again (y $YG)"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($XG + 5000.0)")" "$(python -c "print($YG - 1.35)")" "$ZG" "$E5")]"
read -r XH YH ZH <<< "$(pos_of)"
MOVED_H=$(python -c "print(round($XH - $XG, 4))")
DROP=$(python -c "print(round($YG - $YH, 6))")
assert_eq "$(python -c "print('true' if 0 < $MOVED_H < $STEP * 5.0 else 'false')")" "true" \
  "a claim 5 km off and 1.35 m lower is clamped to a few frames' envelope (moved $MOVED_H m, under 5 frames' $STEP m)"
assert_eq "$(python -c "print('true' if 0 <= $DROP < 0.001 else 'false')")$(field grounded)" "truetrue" \
  "and takes only its share of the drop ($DROP m): the player keeps their footing instead of sinking"

# 11. THE LAKE IS NOT A ROAD (REVIEW 0.23.1 B2): the envelope bounds speed, not place. Into the
#     example level's pond in 25 cm steps — each well inside the envelope — the claim that leaves
#     ground a player may stand on is refused whole, and the one before it is taken exactly. The
#     edge comes from the probes (tools/world/gen_level_probes.py), not from a number here.
read -r Z_OK Z_NO <<< "$(python -c "
import json; p=[q for q in json.load(open('shared/golden/level/example_probes.json'))['probes'] if q['name'].startswith('into_example_pond_')]
k=next(i for i in range(len(p)-1) if p[i]['can_stand'] and not p[i+1]['can_stand']); print(p[k]['z'], p[k+1]['z'])")"
assert_ok "set_world_level 0 200" "to the example level, whose bake knows the water"
assert_ok "teleport {\"x\":0.0,\"y\":0.0,\"z\":$(python -c "print($Z_OK + 0.1)")}" "at the pond's edge"
# Offline between CLI calls and flagged airborne by the teleport, this player falls under the idle
# twin until it lands; a claim made mid-fall has a vertical step, stays airborne, and the twin
# then carries the claim's velocity on across ticks. Let it land first, as the climb above does.
sleep 1.5
read -r XL YL ZL <<< "$(pos_of)"
EL=$(field correction_epoch)
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$XL" "$YL" "$Z_OK" "$EL")]"
read -r XL YL ZL <<< "$(pos_of)"
assert_eq "$(python -c "print('true' if abs($ZL - $Z_OK) < 1e-5 else 'false')") $(field correction_epoch)" "true $EL" \
  "a step to the last ground a player may stand on is taken exactly (z $ZL)"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$XL" "$YL" "$Z_NO" "$EL")]"
read -r XM YM ZM <<< "$(pos_of)"
assert_eq "$(python -c "print('true' if abs($ZM - $Z_OK) < 1e-5 else 'false')")" "true" \
  "the next 25 cm, into deep water, is refused: the player stays at z $Z_OK (z $ZM, claimed $Z_NO)"
assert_eq "$(field correction_epoch)" "$((EL + 1))" "and the client is told: a new correction epoch"
assert_ok "set_world_level 0 0" "back to the greybox"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "teleport back to the origin"


echo "== actions: use_ability (PHASE3_SPEC Task 12, PHASE4_SPEC §3) =="
# The CLI player was teleported back to the origin at the end of the trust section.
AIM='{"x":0.0,"y":0.0,"z":0.0}'
assert_eq "$(row_count 'SELECT * FROM ability_def WHERE ability_id = 0')" "1" "init ships the built-in ability 0 (melee, 2 m, 10 damage)"
assert_ok 'spawn_npc 0 1 {"x":1.0,"y":0.0,"z":0.0}' "a target NPC 1 m away"
NEAR=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok 'spawn_npc 0 1 {"x":5.0,"y":0.0,"z":0.0}' "another 5 m away"
FAR=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
HP0=$(sql_first "SELECT current FROM health_state WHERE entity_id = $NEAR" 1)

assert_ok "use_ability 0 $NEAR $AIM 41" "melee on a target in range is accepted"
assert_eq "$(sql_first "SELECT outcome FROM action_event WHERE actor_id = $MYENT AND predicted_id = 41" 1)" "0" \
  "it lands as a HIT event"
assert_eq "$(sql_first "SELECT target_id FROM action_event WHERE predicted_id = 41" 1)" "$NEAR" \
  "the event names the target, and echoes the client's predicted id so its prediction can be confirmed"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $NEAR" 1)" "$(python -c "print(int(float('$HP0') - 10))")" \
  "the target takes the ability's 10 damage, through the one path that changes health"
assert_eq "$(row_count "SELECT * FROM ability_state WHERE entity_id = $MYENT AND ability_id = 0")" "1" \
  "the actor's cooldown is recorded"
# Test the cooldown against one the CLI cannot outlast. Two `spacetime call`s can be more than
# a second apart here, so checking this against ability 0's 800 ms melee cooldown was a race —
# and losing it also broke the "no event" check below, which then saw a use that went through.
assert_ok 'define_ability 8 30000 10.0 0 0.0 {}' "admin defines a slow ability (30 s cooldown)"
assert_ok "use_ability 8 $NEAR $AIM 48" "its first use is accepted"
assert_rejected "use_ability 8 $NEAR $AIM 42" "on cooldown" "a second use inside the cooldown is refused"
assert_eq "$(row_count "SELECT * FROM action_event WHERE predicted_id = 42")" "0" "a refused use leaves no event: it did not happen"

sleep 1
assert_rejected "use_ability 0 $FAR $AIM 43" "out of range" "a target 5 m away is out of melee range"
assert_rejected "use_ability 99 $NEAR $AIM 44" "unknown ability" "an ability nobody defined is refused"
# A player who is not connected is not in the world (DECISIONS #202): "Gone Soon", from the names section.
assert_rejected "use_ability 0 $GONE $AIM 49" "they are not here" "an ability cannot target a player who is not connected"
assert_ok "use_ability 0 0 $AIM 45" "an untargeted use is accepted"
assert_eq "$(sql_first "SELECT outcome FROM action_event WHERE predicted_id = 45" 1)" "1" \
  "and resolves as a MISS: Tier A has no hit test, the sidecar will"

# A genre defines its own: long range, no damage, no cooldown.
assert_ok 'define_ability 7 0 10.0 100 0.0 {}' "admin defines ability 7"
assert_ok "use_ability 7 $FAR $AIM 46" "the genre's ability reaches the far target"
assert_eq "$(sql_first "SELECT outcome FROM action_event WHERE predicted_id = 46" 1)" "0" "and hits it"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $FAR" 1)" "$(sql_first "SELECT max FROM health_state WHERE entity_id = $FAR" 1)" \
  "with zero damage, health is untouched"

# The dead do not act.
assert_ok "apply_damage $MYENT 1000.0 0" "kill the actor"
assert_rejected "use_ability 7 $FAR $AIM 47" "dead cannot act" "a dead actor's ability is refused"
# `--` so the CLI does not read the leading minus as a flag (as in the health section).
out="$(spacetime call -- "$DB" apply_damage "$MYENT" -1000.0 0 2>&1)"
if echo "$out" | grep -qiE "^error|error:"; then fail "heal the actor again ($(echo "$out" | head -1))"; else pass; fi
assert_eq "$(sql_first "SELECT is_dead FROM health_state WHERE entity_id = $MYENT" 1)" "false" "the actor is alive again"

# Events are a few seconds of history, not a combat log.
sleep 6
assert_eq "$(row_count "SELECT * FROM action_event WHERE actor_id = $MYENT")" "0" "action events are pruned after 5 s"

# =============================================================================
# THE SHOP (GENRE_ADAPTERS §1)
# =============================================================================
# Gear is the progression the round loop exists for, and the phase gate is the whole of its
# integrity: a rod bought mid-cast would change the odds of a fish already on the line.
run_genre_hooks integration_genre_late   # a genre's sections that need everything above (fishing: the shop, gear, the rival)

echo "== statuses and their timers (DECISIONS #206) =="
# What a status LETS an entity do is content (foundation/content/status/); the module keeps who is
# in which (`status_state`), moves it on when its time is up, and holds every rule to it.
UNTIL_CHANGED=4294967295
status_of() { sql_first "SELECT status FROM status_state WHERE entity_id = $1" 1; }
# Normal is no row, or a row saying 0 (a genre's section before this one may have set and reset it:
# Fowl Play's wolf recovers from a missed pounce).
check "$(case "$(status_of $MYENT)" in ""|0) echo true;; *) echo false;; esac)" "a player in no status is normal ($(status_of $MYENT))"
out="$(spacetime call --anonymous "$DB" set_status "$NEAR" 2 0 '""' 2>&1)"
check "$(echo "$out" | grep -qi "only an authority" && echo true || echo false)" "a player cannot set someone else's status"
assert_rejected "set_status $NEAR 77 0 \"\"" "no status 77" "a status this game does not have is refused, naming the ones it has"
assert_rejected "set_status $NEAR 2 0 $(python -c "print('x' * 300)")" "at most 256 bytes" "a status's data is kept short"
assert_ok "set_status $NEAR 2 0 \"\"" "an authority downs the NPC, for the status's own length"
assert_eq "$(status_of $NEAR)" "2" "it is downed"
# Downed's own length in THIS game: a genre's Downed replaces the foundation's (Fowl Play's: 120 s).
OWN_DOWNED_MS=$(python -c "
import json, glob, os
own = None
for f in sorted(glob.glob('shared/content/*/status.json')):
    for i in json.load(open(f))['items']:
        if i['status'] == 2 and (own is None or os.path.basename(os.path.dirname(f)) != 'foundation'):
            own = i['lasts_ms']
print(own)")
assert_eq "$(sql_first "SELECT lasts_ms FROM status_state WHERE entity_id = $NEAR" 1)" "$OWN_DOWNED_MS" "for downed's own length, as this game has it ($OWN_DOWNED_MS ms: its StatusDef)"
assert_eq "$(sql_first "SELECT by_entity FROM status_state WHERE entity_id = $NEAR" 1)" "$MYENT" "and says who did it"
assert_eq "$(sql_rows_anon "SELECT * FROM status_state WHERE entity_id = $NEAR" | wc -l | tr -d ' ')" "1" "public: every client shows it"

# The timer: downed for 1.5 s becomes OUT (downed's `then`) on its own; a newer status cancels it.
assert_ok "set_status $NEAR 2 1500 \"\"" "downed for 1.5 s"
sleep 3
assert_eq "$(status_of $NEAR)" "4" "when its time is up it becomes out (downed's then), by the server's timer"
assert_eq "$(sql_first "SELECT prev_status FROM status_state WHERE entity_id = $NEAR" 1)" "2" "from downed"
assert_eq "$(sql_first "SELECT lasts_ms FROM status_state WHERE entity_id = $NEAR" 1)" "0" "and out lasts until something changes it"
assert_ok "set_status $NEAR 2 1500 \"\"" "downed for 1.5 s again"
assert_ok "set_status $NEAR 1 $UNTIL_CHANGED \"\"" "and injured before that is up"
sleep 3
assert_eq "$(status_of $NEAR)" "1" "the old timer does not move the newer status on (it is still injured)"
assert_eq "$(row_count "SELECT * FROM status_expiry")" "0" "and no timer is left behind"

# What a status allows: a downed actor cannot act; nobody can reach someone who is out.
assert_ok "set_status $MYENT 2 $UNTIL_CHANGED \"\"" "the CLI player is downed"
assert_rejected "use_ability 0 $NEAR $AIM 51" "cannot while downed" "a downed player cannot use an ability"
assert_rejected "interact $NEAR 0" "cannot while downed" "nor use anything"
assert_ok "set_status $MYENT 0 $UNTIL_CHANGED \"\"" "back to normal"
assert_ok "set_status $NEAR 4 $UNTIL_CHANGED \"\"" "the NPC is out"
assert_rejected "use_ability 0 $NEAR $AIM 52" "cannot be reached" "an ability cannot reach someone who is out"
assert_ok "set_status $NEAR 0 $UNTIL_CHANGED \"\"" "and back"
sleep 1
assert_ok "use_ability 0 $NEAR $AIM 53" "now it can"

# TIER A IN A STATUS: a downed player crawls (a quarter of its speed), so a claim a running player
# may make is clamped; after the grace (`foundation.status_grace_ms`), and not before it.
SEQ=$(field last_processed_seq)
EPOCH=$(field correction_epoch)
read -r SX SY SZ <<< "$(pos_of)"
assert_ok "set_status $MYENT 2 $UNTIL_CHANGED \"\"" "downed again"
sleep 1
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($SX + 0.1)")" "$SY" "$SZ" "$EPOCH")]"
check "$([ "$(field correction_epoch)" != "$EPOCH" ] && echo true || echo false)" "a running step (0.1 m in a frame) is clamped while downed"
read -r CX CY CZ <<< "$(pos_of)"
check "$(python -c "print('true' if 0.0 < $CX - $SX < 0.04 else 'false')")" "to a crawl's step ($(python -c "print(round($CX - $SX, 4))") m)"
assert_ok "set_rule foundation.status_grace_ms 3000 \"\"" "a long grace, so the CLI can beat it"
assert_ok "set_status $MYENT 0 $UNTIL_CHANGED \"\"" "back to normal"
# Everything the step needs is read BEFORE going down (going down changes none of it), so only the
# one call that sends it is inside the grace: CLI calls take a second each on some machines, and
# three reads after going down missed a 3 s grace.
EPOCH=$(field correction_epoch); SEQ=$(field last_processed_seq); read -r SX SY SZ <<< "$(pos_of)"
assert_ok "set_status $MYENT 2 $UNTIL_CHANGED \"\"" "and downed at once"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($SX + 0.1)")" "$SY" "$SZ" "$EPOCH")]"
assert_eq "$(field correction_epoch)" "$EPOCH" "inside the grace the step it could make a moment ago is still taken"
assert_ok "reset_rule foundation.status_grace_ms" "the grace back to its default"
assert_ok "set_status $MYENT 0 $UNTIL_CHANGED \"\"" "normal again"
EPOCH=$(field correction_epoch); SEQ=$(field last_processed_seq); read -r SX SY SZ <<< "$(pos_of)"
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ "$(python -c "print($SX + 0.1)")" "$SY" "$SZ" "$EPOCH")]"
assert_eq "$(field correction_epoch)" "$EPOCH" "and running, the same step is taken"

echo "== the referee: abilities a sidecar judges (DECISIONS #226) =="
# The module's side. A judged ability is queued for its world's referee, not resolved; with nobody
# judging it is refused; a referee is registered by presenting an admin's one-time code; its answer is
# a hit or a miss every client sees; a request nobody answers in time is a miss. The CLI's admin plays
# the referee here (`resolve_action` is an authority's, and an admin is one for every world); a real
# sidecar judging against a real level: tests/sidecar_test.sh.
JUDGED='"{\"name\":\"lunge\",\"judged\":true,\"reach\":1.4,\"radius\":0.35,\"height\":0.6}"'
assert_ok "define_ability 9 0 0.0 400 25.0 $JUDGED" "admin defines a judged ability (a lunge: 400 ms wind-up, 25 damage)"
assert_ok "define_ability 10 0 0.0 20000 25.0 $JUDGED" "and a slow one (20 s wind-up: each use waits for its referee while it is checked, a CLI call a second)"
# THE ABILITIES FOLLOW THE BUILD: content's abilities are brought up to date on every connection (they
# were seeded once, at init: a world from before an ability was added never had it).
assert_ok 'define_ability 0 5000 2.0 150 10.0 {}' "an admin changes the built-in melee by hand (a 5 s cooldown)"
assert_eq "$(sql_first 'SELECT cooldown_ms FROM ability_def WHERE ability_id = 0' 1)" "800" "the next connection puts content's back (800 ms)"
assert_eq "$(sql_first 'SELECT cooldown_ms FROM ability_def WHERE ability_id = 9' 1)" "0" "an ability content does not name is left as the admin made it"
assert_ok 'spawn_npc 0 1 {"x":1.0,"y":0.0,"z":-1.0}' "someone to hit"
VICTIM=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok 'spawn_npc 0 77 {"x":3.0,"y":0.0,"z":0.0}' "and a thing, not a person (a kind no character is)"
THING=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 77 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
REF_CODE='"refereecodeforthetestsuite"'
anon_call() { spacetime call --anonymous "$DB" "$@" 2>&1; }

assert_rejected "use_ability_seen 10 0 $AIM 60 100" "no referee" "with nobody judging the world, a judged ability is refused (said, not guessed at)"
assert_eq "$(row_count 'SELECT * FROM action_request')" "0" "and nothing is queued"
assert_rejected "offer_referee 0 \"short\"" "at least 16" "an offer's code is long enough not to be guessed"
assert_rejected "offer_referee 77 $REF_CODE" "no world 77" "an offer is for a world that exists"
assert_ok "offer_referee 0 $REF_CODE" "the admin offers a code for world 0 (as its client does before starting a referee)"
assert_rejected "offer_referee 0 $REF_CODE" "already being started" "a second offer while one stands is refused (two instances do not start two referees)"
out="$(anon_call claim_referee 0 '"notthecodethatwasoffered"')"
check "$(echo "$out" | grep -q "not the code offered" && echo true || echo false)" "another code is refused"
assert_rejected "claim_referee 0 $REF_CODE" "an admin cannot be a referee" "the admin cannot claim it (it would stop being an admin)"
out="$(anon_call claim_referee 0 "$REF_CODE")"
# Online for 5 s from its claim (its heartbeat would keep it so; the CLI's anonymous identity cannot
# beat): queue two at once, and check after.
assert_ok "use_ability_seen 10 0 $AIM 61 400" "a judged use, seen 400 ms behind: queued"
assert_ok "use_ability_seen 10 0 $AIM 63 20" "a slow one, seen 20 ms behind"
check "$(echo "$out" | grep -qiE "^error|error:" && echo false || echo true)" "a sidecar presenting the code is registered ($(echo "$out" | grep -i error | head -1))"
# Both run out 23 s after they were used (the 20 s wind-up, then REQUEST_GRACE_MICROS' 3 s), so what
# needs them waiting comes first, from ONE read of them: a CLI call takes about a second on a busy
# machine, and the two dozen this once made before 63's last refusal outlasted it ("no such request").
REQS=$(spacetime sql "$DB" --format json "SELECT id, predicted_id, rewind_ms, issued_at, due_at FROM action_request" 2>/dev/null | python -c "
import json, sys
t = sys.stdin.read()
rows = json.loads(t[t.find('['):])[0]['rows'] if '[' in t else []
by = {r[1]: r for r in rows}
r61, r63 = by.get(61), by.get(63)
print(r61[0] if r61 else '-', r63[0] if r63 else '-', len(rows), r61[2] if r61 else '-', r63[2] if r63 else '-',
      round((r61[4][0] - r61[3][0]) / 1000) if r61 else -1)")
read -r R61 R63 NREQ RW61 RW63 DUE_MS <<< "$REQS"
assert_eq "$NREQ" "2" "both wait for the referee"
assert_eq "$RW61" "150" "seen 400 ms behind, rewound the cap's 150 (favouring the attacker, no further)"
assert_eq "$RW63" "20" "under the cap, what it saw"
assert_eq "$DUE_MS" "20000" "it lands its wind-up after it was used: when the referee judges it"
check "$([ "$(spacetime sql --anonymous "$DB" 'SELECT * FROM action_request' 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')" = "0" ] && echo true || echo false)" \
  "a player cannot read them: only the world's authority (no early look at an attacker's aim)"
assert_eq "$(row_count 'SELECT * FROM action_event WHERE predicted_id = 61')" "0" "nothing has happened yet: no event"
assert_rejected "resolve_action $R63 $MYENT" "not itself" "a referee cannot have it hit its own user"
assert_ok "set_status $VICTIM 2 $UNTIL_CHANGED \"\"" "the one it would hit goes down"
assert_rejected "resolve_action $R63 $VICTIM" "cannot be hit" "a downed one is not hit again (downed: not hittable)"
assert_ok "set_status $VICTIM 0 $UNTIL_CHANGED \"\"" "(up again)"
assert_rejected "resolve_action $R63 $THING" "not someone" "a thing is not hit"

HPV=$(sql_first "SELECT current FROM health_state WHERE entity_id = $VICTIM" 1)
assert_ok "resolve_action $R61 $VICTIM" "the referee: request 61 hit"
assert_eq "$(sql_first "SELECT outcome FROM action_event WHERE predicted_id = 61" 1)" "0" "every client sees a HIT"
assert_eq "$(sql_first "SELECT target_id FROM action_event WHERE predicted_id = 61" 1)" "$VICTIM" "on whom the referee said"
assert_eq "$(sql_first "SELECT current FROM health_state WHERE entity_id = $VICTIM" 1)" "$(python -c "print(int(float('$HPV') - 25))")" \
  "with no genre to say otherwise, the ability's 25 damage"
assert_eq "$(row_count "SELECT * FROM action_request WHERE id = $R61")" "0" "answered: gone"
assert_rejected "resolve_action $R61 $VICTIM" "no such request" "and answered once"
# The referee's registration, now nothing is waiting on the clock (its row stays after it stops beating).
assert_eq "$(row_count 'SELECT * FROM authority WHERE role = 1 AND world_id = 0')" "1" "as world 0's authority: its referee"
REF_IDENT=$(sql_first 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' 1)
assert_eq "$(row_count "SELECT * FROM player WHERE identity = $REF_IDENT")" "0" "and not a player: the player its first connection made is taken away (0.41.1)"
out="$(anon_call claim_referee 0 "$REF_CODE")"
check "$(echo "$out" | grep -q "nothing was offered" && echo true || echo false)" "the code is used up"
assert_ok "despawn_entity $THING" "(gone)"
# Left unanswered, 63 runs out: the 1 Hz prune, its landing time (20 s) and 3 s on. Its miss is an
# action_event, pruned 5 s after it (ACTION_EVENT_TTL_MICROS), so the wait watches for that event and
# keeps its outcome as it appears, rather than reading it after the wait has looked twice more.
OUT63=""
deadline=$((SECONDS + 45))
while [ -z "$OUT63" ] && [ "$SECONDS" -lt "$deadline" ]; do
  OUT63=$(sql_first "SELECT outcome FROM action_event WHERE predicted_id = 63" 1)
  [ -z "$OUT63" ] && sleep 0.5
done
assert_eq "$(row_count "SELECT * FROM action_request WHERE id = $R63")" "0" "nobody answered it: it ran out"
assert_eq "$OUT63" "1" "as a miss (the referee went away; not the user's)"
assert_rejected "use_ability_seen 10 0 $AIM 64 100" "no referee" "a referee that stopped beating is not judging: refused again"
# The cap is a live rule: a second referee, the cap at 50 ms first.
assert_ok "set_rule foundation.rewind_max_ms 50 \"\"" "the rewind's cap at 50 ms"
assert_ok "offer_referee 0 $REF_CODE" "another offer, now nobody is judging"
out="$(anon_call claim_referee 0 "$REF_CODE")"
assert_ok "use_ability_seen 10 0 $AIM 62 400" "a use seen 400 ms behind"
assert_ok "reset_rule foundation.rewind_max_ms" "(the cap back to 150)"
R62=$(sql_first "SELECT id FROM action_request WHERE predicted_id = 62" 1)
assert_eq "$(sql_first "SELECT rewind_ms FROM action_request WHERE id = $R62" 1)" "50" "rewound the live cap's 50"
assert_ok "resolve_action $R62 0" "the referee: nothing in its way"
assert_eq "$(sql_first "SELECT outcome FROM action_event WHERE predicted_id = 62" 1)" "1" "a MISS"
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "a test referee unregistered"
done
assert_ok "despawn_entity $VICTIM" "(the one it hit gone)"

echo "== bodies: things the referee flies (DECISIONS #246) =="
# The module's half of milestone 13: a player's throw, bounded; nothing thrown without a referee; the
# thrower's oldest goes past the body's limit; the module never moves a body (the referee does); the
# referee's writes and contacts; a body's rows go with it. A real referee flying a real ball:
# tests/bodies_playtest.sh.
v3() { echo "{\"x\":$1,\"y\":$2,\"z\":$3}"; }
read BMX BMY BMZ <<< "$(pos_of)"
BODY_HAND="$(v3 "$BMX" "$(python -c "print($BMY + 1.4)")" "$BMZ")"
BODY_FAR="$(v3 "$(python -c "print($BMX + 10.0)")" "$BMY" "$BMZ")"
BODY_SOFT="$(v3 0.0 2.0 -10.0)"
BODY_NOSPIN="$(v3 0.0 0.0 0.0)"
body_count() { row_count "SELECT * FROM body_state WHERE owner_id = $MYENT"; }
assert_rejected "launch_body 1 7 $BODY_HAND $BODY_SOFT $BODY_NOSPIN $BODY_NOSPIN" "no referee" "with no referee nothing thrown would fly: refused (said)"
assert_eq "$(body_count)" "0" "and nothing was made"
assert_rejected "launch_body 9999 7 $BODY_HAND $BODY_SOFT $BODY_NOSPIN $BODY_NOSPIN" "no body 9999" "a body the game does not have"
assert_rejected "launch_body 1 7 $BODY_HAND $(v3 0.0 0.0 -30.0) $BODY_NOSPIN $BODY_NOSPIN" "faster than" "faster than the ball may be thrown (25 m/s)"
assert_rejected "launch_body 1 7 $BODY_HAND $BODY_SOFT $BODY_NOSPIN $(v3 0.0 50.0 0.0)" "spin" "spun harder than it may be"
assert_rejected "launch_body 1 7 $BODY_FAR $BODY_SOFT $BODY_NOSPIN $BODY_NOSPIN" "within" "from 10 m away: out of the thrower's reach"
# The bounds are checked before the referee is looked for; the throws below need one online.
assert_ok "offer_referee 0 $REF_CODE" "a referee for world 0 (online 5 s from its claim)"
out="$(anon_call claim_referee 0 "$REF_CODE")"
# Four throws at once: the anonymous referee is online for only 5 s from its claim, and a CLI call takes
# most of a second (more on a busy server). The ball's limit is three a thrower, so one goes.
BODY_DIR="$(mktemp -d)"
for L in 7 8 9 10; do
  ( spacetime call "$DB" launch_body 1 "$L" "$BODY_HAND" "$BODY_SOFT" "$BODY_NOSPIN" "$BODY_NOSPIN" > "$BODY_DIR/$L" 2>&1 ) &
done
wait
for L in 7 8 9 10; do
  check "$(grep -qiE "^error|error:" "$BODY_DIR/$L" && echo false || echo true)" "throw $L inside the bounds ($(grep -i error "$BODY_DIR/$L" | head -1))"
done
rm -rf "$BODY_DIR"
assert_eq "$(body_count)" "3" "three at most: the fourth took the oldest away"
B1=$(sql_first "SELECT entity_id FROM body_state WHERE owner_id = $MYENT" 1)
check "$([ -n "$B1" ] && echo true || echo false)" "a body, with the thrower's own number for it"
assert_eq "$(sql_first "SELECT kind FROM entity WHERE entity_id = ${B1:-0}" 1)" "3" "an entity of kind 3 (a body)"
assert_eq "$(sql_first "SELECT def_id FROM body_state WHERE entity_id = ${B1:-0}" 1)" "1" "which body: the ball"
assert_eq "$(sql_first "SELECT frames FROM body_state WHERE entity_id = ${B1:-0}" 1)" "0" "no frames flown yet"
check "$(close_to "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = ${B1:-0}" 1 | python -c "import re,sys; v=re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.stdin.read()); print(' '.join(v[:3]))")" "$BMX" "$(python -c "print($BMY + 1.4)")" "$BMZ" 0.01)" "its movement row: where it left the hand"
check "$([ "$(row_count "SELECT * FROM entity WHERE kind = 3")" = "3" ] && echo true || echo false)" "the one taken away went with all its rows (three bodies, three entities)"
B10="$B1"
BODY_P0="$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $B10" 1)"
sleep 1
assert_eq "$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $B10" 1)" "$BODY_P0" "a second of ticks: the module never moved it (no gravity of its own: the referee's)"
# The referee's write (the admin is an authority for every world).
BW="[{\"entity_id\":$B10,\"pos\":$(v3 1.5 0.11 -4.0),\"vel\":$(v3 0.0 0.0 0.0),\"rot\":$(v3 0.0 1.0 0.0),\"spin\":$(v3 0.0 0.0 0.0),\"at_rest\":true,\"frames\":95}]"
out="$(spacetime call "$DB" write_body_batch 0 "$BW" 2>&1)"
check "$(echo "$out" | grep -qiE "^error|error:" && echo false || echo true)" "the referee writes a body ($(echo "$out" | head -1))"
assert_eq "$(sql_first "SELECT last_processed_seq FROM movement_state WHERE entity_id = $B10" 1)" "95" "its movement row: the referee's frame, its timeline"
assert_eq "$(sql_first "SELECT grounded FROM movement_state WHERE entity_id = $B10" 1)" "true" "at rest: grounded"
assert_eq "$(sql_first "SELECT at_rest FROM body_state WHERE entity_id = $B10" 1)" "true" "its body row: at rest"
assert_eq "$(sql_first "SELECT frames FROM body_state WHERE entity_id = $B10" 1)" "95" "with its frames"
out="$(spacetime call "$DB" write_body_batch 1 "$BW" 2>&1)"
assert_eq "$(sql_first "SELECT frames FROM body_state WHERE entity_id = $B10" 1)" "95" "a write for it as if in world 1: passed over"
BC="[{\"body_id\":$B10,\"other_id\":$MYENT,\"pos\":$(v3 1.5 1.0 -4.0),\"normal\":$(v3 0.0 0.0 1.0),\"speed\":7.5}]"
out="$(spacetime call "$DB" report_body_contacts 0 "$BC" 2>&1)"
check "$(echo "$out" | grep -qiE "^error|error:" && echo false || echo true)" "the referee reports a hit ($(echo "$out" | head -1))"
assert_eq "$(sql_first "SELECT other_id FROM body_contact WHERE body_id = $B10" 1)" "$MYENT" "a row everyone in the world gets: what it hit"
assert_eq "$(row_count "SELECT * FROM body_contact WHERE body_id = $B10")" "1" "once"
check "$([ "$(sql_rows_anon "SELECT * FROM body_state WHERE entity_id = $B10" | wc -l | tr -d ' ')" = "1" ] && echo true || echo false)" "a body's row is public: any player draws it"
for _ in $(seq 1 12); do [ "$(row_count "SELECT * FROM body_contact WHERE body_id = $B10")" = "0" ] && break; sleep 1; done
assert_eq "$(row_count "SELECT * FROM body_contact WHERE body_id = $B10")" "0" "a few seconds on, the contact's row is gone (heard as it is made)"
assert_ok "despawn_entity $B10" "an authority takes a body away"
assert_eq "$(row_count "SELECT * FROM body_state WHERE entity_id = $B10")" "0" "its body row with it"
for B in $(sql_rows "SELECT entity_id FROM body_state WHERE owner_id = $MYENT" | awk '{print $1}'); do
  assert_ok "despawn_entity $B" "(a ball put away)"
done
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the test referee unregistered"
done

echo "== carry: one entity carried by another (DECISIONS #228) =="
# The module's half of milestone 6: who may carry whom; a carried entity is CARRIED, kept at its
# carrier every tick whatever its own client claims; put down at its carrier's feet in the status it
# had; a carrier that goes drops what it carried. A genre decides WHEN (Fowl Play's pick up and stash).
pos_e() {   # pos_e ID -> "x y z"
  sql_first "SELECT pos FROM movement_state WHERE entity_id = $1" 1 \
    | python -c "import re,sys; v=re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.stdin.read()); print(' '.join(v[:3]))"
}
move_e() {   # move_e ID X Z: the authority puts it there
  spacetime call "$DB" write_movement_batch 0 "[{\"entity_id\":$1,\"pos\":{\"x\":$2,\"y\":0.0,\"z\":$3},\"vel\":{\"x\":0.0,\"y\":0.0,\"z\":0.0},\"yaw\":0.0,\"grounded\":true,\"move_state\":0,\"last_processed_seq\":0,\"teleport_flag\":true}]" >/dev/null 2>&1
}
assert_ok 'spawn_npc 0 1 {"x":2.0,"y":0.0,"z":2.0}' "a carrier"
CARRIER=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok 'spawn_npc 0 1 {"x":4.0,"y":0.0,"z":4.0}' "and someone to carry"
LOAD=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok "set_status $LOAD 2 $UNTIL_CHANGED \"\"" "who is down"
assert_rejected "attach_as $LOAD $LOAD \"\"" "not itself" "nothing carries itself"
assert_ok "attach_as $LOAD $CARRIER \"\"" "the carrier picks it up"
assert_eq "$(sql_first "SELECT carrier_id FROM attachment WHERE entity_id = $LOAD" 1)" "$CARRIER" "the row says who carries it"
assert_eq "$(status_of $LOAD)" "3" "it is CARRIED (cannot move or act, nor be hit)"
assert_eq "$(sql_first "SELECT prev_status FROM attachment WHERE entity_id = $LOAD" 1)" "2" "and the row remembers it was down"
assert_rejected "attach_as $LOAD $CARRIER \"\"" "already carried" "it cannot be picked up twice"
assert_rejected "attach_as $CARRIER $LOAD \"\"" "carrying while carried" "nor carry its carrier"
sleep 0.3
check "$(close_to "$(pos_e $LOAD)" 2.0 0.0 2.0 0.01)" "from the next tick it is where its carrier is ($(pos_e $LOAD))"
move_e "$CARRIER" 9.0 -6.0
sleep 0.3
check "$(close_to "$(pos_e $LOAD)" 9.0 0.0 -6.0 0.01)" "the carrier moves: it comes along ($(pos_e $LOAD))"
# A carried PLAYER's own claims are dropped: the CLI's player, carried, says it ran off.
assert_ok 'spawn_npc 0 1 {"x":-3.0,"y":0.0,"z":-3.0}' "a second carrier"
CARRIER2=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok "attach_as $MYENT $CARRIER2 \"\"" "it picks up the CLI's player"
sleep 0.3
EPOCH=$(field correction_epoch); SEQ=$(field last_processed_seq)
SEQ=$((SEQ + 1))
send_frames "[$(frame $SEQ 30.0 0.0 30.0 "$EPOCH")]"
check "$(close_to "$(pos_of)" -3.0 0.0 -3.0 0.01)" "a carried player claiming it ran 33 m off stays where it is carried ($(pos_of))"
assert_eq "$(field last_processed_seq)" "$SEQ" "its frame consumed (its client is not left waiting for it)"
assert_ok "despawn_entity $CARRIER2" "its carrier is gone"
assert_eq "$(row_count "SELECT * FROM attachment WHERE entity_id = $MYENT")" "0" "so it is carried no more"
check "$(case "$(status_of $MYENT)" in ""|0) echo true;; *) echo false;; esac)" "put down in the status it had (normal)"
check "$(close_to "$(pos_of)" -3.0 0.0 -3.0 0.01)" "where its carrier was"
assert_ok "detach_as $LOAD" "the first carrier puts its load down"
assert_eq "$(row_count "SELECT * FROM attachment WHERE entity_id = $LOAD")" "0" "carried no more"
assert_eq "$(status_of $LOAD)" "2" "down again, as it was when picked up"
check "$(close_to "$(pos_e $LOAD)" 9.0 0.0 -6.0 0.01)" "at its carrier's feet"
assert_rejected "detach_as $LOAD" "not carried" "and it cannot be put down twice"
for e in "$CARRIER" "$LOAD"; do assert_ok "despawn_entity $e" "(gone)"; done
move_e "$MYENT" 0.0 0.0   # the CLI's player back at the origin

echo "== pings and noises: what a world hears (DECISIONS #233) =="
# A player pings where they look (`ping`): a noise of kind 1 there, about what they pointed at, for
# everyone in the world. Not further than 80 m from them, not about something that is not here, and
# no faster than shared/rules.json's `ping` (two at once, one about every three seconds after). A
# noise's row goes a few seconds after it was made (it is heard as it is made).
xyz() { python -c "import re,sys; v=re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', sys.stdin.read()); print(' '.join(v[:3]))"; }
sleep 6   # the ping allowance full again (the moves above did not spend it: each reducer has its own)
assert_ok 'ping {"x":3.0,"y":0.0,"z":4.0} 0' "the CLI's player pings a place 5 m off"
assert_eq "$(sql_first "SELECT kind FROM noise WHERE source_id = $MYENT" 1)" "1" "a noise of kind 1 (a ping), made by them"
check "$(close_to "$(sql_first "SELECT pos FROM noise WHERE source_id = $MYENT" 1 | xyz)" 3 0 4 0.01)" "where they pointed"
assert_rejected 'ping {"x":200.0,"y":0.0,"z":0.0} 0' "further than" "a place 200 m off: refused"
assert_rejected 'ping {"x":1.0,"y":0.0,"z":1.0} 999999' "nothing like that" "about something not here: refused"
assert_eq "$(row_count "SELECT * FROM noise WHERE source_id = $MYENT")" "1" "(neither made a noise)"
sleep 6
PG_DIR="$(mktemp -d)"
for i in $(seq 1 6); do
  ( spacetime call "$DB" ping '{"x":1.0,"y":0.0,"z":1.0}' 0 > "$PG_DIR/$i" 2>&1 ) &
done
wait
PG_OK=0; PG_REFUSED=0
for i in $(seq 1 6); do
  if grep -qi "too many calls" "$PG_DIR/$i"; then PG_REFUSED=$((PG_REFUSED + 1));
  elif ! grep -qiE "^error|error:" "$PG_DIR/$i"; then PG_OK=$((PG_OK + 1)); fi
done
rm -rf "$PG_DIR"
check "$([ "$PG_OK" -ge 2 ] && [ "$PG_OK" -le 3 ] && [ $((PG_OK + PG_REFUSED)) -eq 6 ] && echo true || echo false)"   "six pings at once: two or three taken, the rest too many ($PG_OK taken, $PG_REFUSED refused)"
sleep 12
assert_eq "$(row_count "SELECT * FROM noise WHERE source_id = $MYENT")" "0" "ten seconds on, the noises are gone"
assert_ok "set_status $MYENT 4 $UNTIL_CHANGED \"\"" "(the CLI's player out)"
assert_rejected 'ping {"x":1.0,"y":0.0,"z":1.0} 0' "watching" "out of the game: no ping"
assert_ok "set_status $MYENT 0 $UNTIL_CHANGED \"\"" "(the CLI's player back)"

echo "== telemetry: how a game ran, and what a player said (DECISIONS #244) =="
# A player's game reports each window (report_perf), at most at shared/rules.json's rate; the server
# says whose, in what world and level. Feedback (send_feedback) is stamped by the server with who,
# where, and in what part of the game, from its own rows; the moment they marked is theirs unless their
# clock is off. Neither table reaches a client: only the database's owner reads them.
tm_report() { spacetime call "$DB" report_perf '"itest"' '"Windows | itest"' 30.0 1800 6.9 8.1 12.5 70.2 2 35.0 80.0 1 512.5 12 '"{\"spikes\":[[1.5,70.2,\"frame\"]]}"' 2>&1; }
check "$(tm_report | grep -qiE "^error|error:" && echo false || echo true)" "a player's game reports a window"
TM_Q="SELECT entity_id, role, frames FROM perf_report WHERE build = 'itest'"
assert_eq "$(sql_first "$TM_Q" 1) $(sql_first "$TM_Q" 2) $(sql_first "$TM_Q" 3)" "$MYENT 0 1800" "kept: theirs (the server's word for whose), a game's, its frames"
check "$(python -c "print('true' if abs(float('$(sql_first "SELECT fps FROM perf_report WHERE build = 'itest'" 1)') - 60.0) < 0.01 else 'false')")" "its frame rate worked out by the server (1800 in 30 s: 60)"
sleep 8   # its allowance full again (three at once, one every 2 s)
TM_DIR="$(mktemp -d)"
for i in $(seq 1 6); do ( tm_report > "$TM_DIR/$i" 2>&1 ) & done
wait
TM_OK=0; TM_REFUSED=0
for i in $(seq 1 6); do
  if grep -qi "too many calls" "$TM_DIR/$i"; then TM_REFUSED=$((TM_REFUSED + 1)); elif ! grep -qiE "^error|error:" "$TM_DIR/$i"; then TM_OK=$((TM_OK + 1)); fi
done
rm -rf "$TM_DIR"
check "$([ "$TM_OK" -ge 3 ] && [ "$TM_OK" -le 4 ] && [ "$TM_REFUSED" -ge 2 ] && [ $((TM_OK + TM_REFUSED)) = 6 ] && echo true || echo false)" "six at once: three taken (its burst; a fourth if a second passed), the rest too many (report_perf: shared/rules.json; $TM_OK taken, $TM_REFUSED refused)"
sleep 11
spacetime call "$DB" report_perf '"itest3"' "\"$(python -c "print('x' * 900)")\"" 9999.0 10 1.0 1.0 1.0 1.0 0 1.0 1.0 0 1.0 1 '""' >/dev/null 2>&1
TM_W=$(sql_first "SELECT window_s FROM perf_report WHERE build = 'itest3'" 1)
TM_P=$(spacetime sql "$DB" --format json "SELECT platform FROM perf_report WHERE build = 'itest3'" 2>/dev/null | python -c "import json,sys; t=sys.stdin.read(); print(len(json.loads(t[t.find('['):])[0]['rows'][0][0]))")
assert_eq "$TM_W $TM_P" "600 200" "a window out of sense stored as its most (600 s), a 900-byte platform cut to 200"
NOW_US=$(python -c "import time; print(int(time.time() * 1e6))")
FB_OUT=$(spacetime call "$DB" send_feedback "$((NOW_US - 20000000))" 9 '"  the wolf went through the gate  "' '"itest"' '"Windows | itest"' '"{\"perf\":{}}"' 2>&1)
check "$(echo "$FB_OUT" | grep -qiE "^error|error:" && echo false || echo true)" "a player sends feedback ($(echo "$FB_OUT" | head -1))"
FB_Q="SELECT entity_id, category, text FROM feedback WHERE build = 'itest'"
assert_eq "$(sql_first "$FB_Q" 1)|$(sql_first "$FB_Q" 2)|$(sql_first "$FB_Q" 3)" "$MYENT|3|\"the wolf went through the gate\"" \
  "kept as theirs (the server's), an unknown category as Other, their words trimmed"
fb_gap() { spacetime sql "$DB" --format json "SELECT noticed_at, at FROM feedback WHERE build = '$1'" 2>/dev/null | python -c "import json,sys; t=sys.stdin.read(); r=json.loads(t[t.find('['):])[0]['rows'][0]; print(round((r[1][0]-r[0][0])/1e6))"; }
FB_GAP=$(fb_gap itest)
check "$([ "$FB_GAP" -ge 18 ] && [ "$FB_GAP" -le 30 ] && echo true || echo false)" "the moment they marked kept: 20 s before the server heard it ($FB_GAP s)"
spacetime call "$DB" send_feedback "$((NOW_US - 86400000000))" 0 '"clock off"' '"itest-off"' '"x"' '"{}"' >/dev/null 2>&1
assert_eq "$(fb_gap itest-off)" "0" "a moment a day before (a clock that is off): the server's own"
check "$([ -z "$(sql_rows_anon "SELECT * FROM feedback")" ] && [ -z "$(sql_rows_anon "SELECT * FROM perf_report")" ] && echo true || echo false)" \
  "and neither table reaches anyone but the database's owner (private)"
check "$(spacetime logs "$DB" 2>/dev/null | grep -q "FEEDBACK .*the wolf went through the gate" && echo true || echo false)" "feedback is in the server's log as it arrives"

echo "== holds: hold to interact (DECISIONS #209) =="
# What a hold IS is content (foundation/content/hold/: Help up, 4 s alone, 2.5 with two, 2 with three,
# on a downed player or NPC, back to normal when done); the module keeps who holds what and how far
# along it is, and a 10 Hz tick lets go of doers who wander, are hurt or cannot act. The CLI's player
# is offline between calls, so the lasting doers are NPCs, held through the authority's route (the
# sidecar's, for bots): begin_interact_as.
hold_rows() { row_count "SELECT * FROM hold_progress WHERE entity_id = $1"; }
hold_field() { sql_first "SELECT $2 FROM hold_progress WHERE entity_id = $1" 1; }
doer_count() { row_count "SELECT * FROM hold_member WHERE target_id = $1"; }
near() { python -c "print('true' if abs(float('$1') - $2) < 0.01 else 'false')"; }
near_rate() { python -c "print('true' if abs(float('${1:-nan}') - $2) <= abs($2) * 0.05 else 'false')"; }   # within 5 %
move_npc() {   # move_npc ID X Z: the authority puts an NPC there
  spacetime call "$DB" write_movement_batch 0 "[{\"entity_id\":$1,\"pos\":{\"x\":$2,\"y\":0.0,\"z\":$3},\"vel\":{\"x\":0.0,\"y\":0.0,\"z\":0.0},\"yaw\":0.0,\"grounded\":true,\"move_state\":0,\"last_processed_seq\":0,\"teleport_flag\":true}]" >/dev/null 2>&1
}
assert_ok 'spawn_npc 0 1 {"x":1.5,"y":0.0,"z":0.8}' "a helper NPC beside the target"
H1=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok 'spawn_npc 0 1 {"x":0.5,"y":0.0,"z":0.8}' "and another"
H2=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)
assert_ok 'spawn_npc 0 1 {"x":1.0,"y":0.0,"z":-0.8}' "and a third"
H3=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1 AND world_id = 0" | awk '{print $1}' | sort -n | tail -1)

assert_rejected "begin_interact_as $H1 $NEAR 0" "nothing to hold there" "nothing to hold on someone standing (Help up is for the downed)"
assert_ok "set_status $NEAR 2 $UNTIL_CHANGED \"\"" "the target NPC is downed"
out="$(spacetime call --anonymous "$DB" begin_interact_as "$H1" "$NEAR" 0 2>&1)"
check "$(echo "$out" | grep -qi "authority" && echo true || echo false)" "a player cannot hold for an NPC"
assert_rejected "begin_interact_as $FAR $NEAR 0" "out of range" "an NPC 4 m away is out of reach"
assert_rejected "begin_interact_as $NEAR $NEAR 0" "not on yourself" "nobody helps themself up"
assert_rejected "begin_interact_as $H1 $NEAR 9" "nothing to hold there" "another verb starts nothing"

# Each CLI call takes about half a second, longer than Help up gives: the game's pace rule slows every
# hold to a tenth while the rates are read (40 s alone), which is also how a designer slows them live.
assert_ok "set_rule foundation.hold_speed 0.05 \"\"" "every hold at a twentieth of its speed, the rule's least (so a run of slow CLI calls cannot finish it)"
assert_ok "begin_interact_as $H1 $NEAR 0" "one helper holds Help up"
assert_eq "$(hold_rows $NEAR)" "1" "one thing held on the target"
assert_eq "$(hold_field $NEAR doers)" "1" "by one"
check "$(near_rate "$(hold_field $NEAR rate)" 0.0125)" "an eightieth a second: 4 s alone, at a twentieth of the pace ($(hold_field $NEAR rate))"
assert_eq "$(sql_first "SELECT target_id FROM hold_member WHERE entity_id = $H1" 1)" "$NEAR" "the helper holds it"
assert_eq "$(sql_rows_anon "SELECT * FROM hold_progress WHERE entity_id = $NEAR" | wc -l | tr -d ' ')" "1" "public: every client draws the bar"
assert_ok "begin_interact_as $H1 $NEAR 0" "holding it again changes nothing"
assert_eq "$(doer_count $NEAR)" "1" "(still one)"
assert_ok "begin_interact_as $H2 $NEAR 0" "a second joins"
check "$(near_rate "$(hold_field $NEAR rate)" 0.02)" "faster together: 2.5 s with two ($(hold_field $NEAR rate))"
assert_ok "begin_interact_as $H3 $NEAR 0" "a third"
check "$(near_rate "$(hold_field $NEAR rate)" 0.025)" "2 s with three ($(hold_field $NEAR rate))"
assert_ok "end_interact_as $H3" "the third lets go"
check "$([ "$(doer_count $NEAR)" = "2" ] && [ "$(near_rate "$(hold_field $NEAR rate)" 0.02)" = "true" ] && echo true || echo false)" "two again, at two's rate"
assert_ok "apply_damage $H2 1 0" "the second is hurt"
check "$([ "$(doer_count $NEAR)" = "1" ] && [ "$(near_rate "$(hold_field $NEAR rate)" 0.0125)" = "true" ] && echo true || echo false)" "and lets go (Help up stops when its doer is hurt)"
assert_ok "set_rule foundation.hold_speed 0.1 \"\"" "the pace changed while it is held (doubled)"
sleep 0.5
check "$(near_rate "$(hold_field $NEAR rate)" 0.025)" "takes effect at once ($(hold_field $NEAR rate))"
move_npc "$H1" 0.5 0.3
sleep 0.5
assert_eq "$(doer_count $NEAR)" "0" "the last helper moved 1.1 m from where it began, still in reach (Help up lets go past 0.75 m): let go by the tick"
assert_eq "$(hold_rows $NEAR)" "0" "nobody holding Help up: the help is lost (it keeps nothing)"
assert_eq "$(status_of $NEAR)" "2" "the target still downed"

# Done: three together, 2 s. The target is back to normal, the rows go, the tick stops.
assert_ok "reset_rule foundation.hold_speed" "holds at their own speed again"
move_npc "$H1" 1.5 0.8; move_npc "$H2" 0.5 0.8; move_npc "$H3" 1.0 -0.8
assert_ok "begin_interact_as $H1 $NEAR 0" "three help"
assert_ok "begin_interact_as $H2 $NEAR 0" "together"
assert_ok "begin_interact_as $H3 $NEAR 0" "again"
assert_eq "$(row_count "SELECT * FROM hold_tick")" "1" "the hold tick runs while something is held"
sleep 3
assert_eq "$(status_of $NEAR)" "0" "done: the target is back on its feet (Help up's then: normal)"
assert_eq "$(sql_first "SELECT by_entity FROM status_state WHERE entity_id = $NEAR" 1)" "$H1" "helped up by the first to begin"
assert_eq "$(hold_rows $NEAR)" "0" "the bar is gone"
assert_eq "$(row_count "SELECT * FROM hold_member")" "0" "everyone let go"
assert_eq "$(row_count "SELECT * FROM hold_tick")" "0" "and nothing held: the tick stopped itself"

# A doer who cannot act lets go; a target that is no longer downed ends it; a player offline lets go.
assert_ok "set_rule foundation.hold_speed 0.05 \"\"" "slow again, so nothing finishes while it is checked"
assert_ok "set_status $NEAR 2 $UNTIL_CHANGED \"\"" "downed again"
assert_ok "begin_interact_as $H1 $NEAR 0" "a helper"
assert_ok "begin_interact_as $H2 $NEAR 0" "and another"
assert_ok "set_status $H2 2 $UNTIL_CHANGED \"\"" "the second is downed itself"
sleep 0.5
assert_eq "$(doer_count $NEAR)" "1" "a doer who cannot act lets go"
assert_ok "set_status $H2 0 $UNTIL_CHANGED \"\"" "(back up)"
assert_ok "set_status $NEAR 0 $UNTIL_CHANGED \"\"" "the target gets up some other way"
sleep 0.5
assert_eq "$(hold_rows $NEAR)" "0" "nothing left to help up: the hold ends"
assert_eq "$(row_count "SELECT * FROM hold_member")" "0" "and its helper lets go"
assert_ok "set_status $NEAR 2 $UNTIL_CHANGED \"\"" "downed once more"
read -r SX SY SZ <<< "$(pos_of)"
assert_ok "begin_interact $NEAR 0" "the CLI's own player holds it ($(python -c "print(round((($SX - 1.0) ** 2 + ($SZ) ** 2) ** 0.5, 2))") m away)"
sleep 0.5
assert_eq "$(row_count "SELECT * FROM hold_member WHERE entity_id = $MYENT")" "0" "and, offline between CLI calls, lets go"
assert_ok "end_interact" "letting go of nothing is fine (a release after the hold ended)"

# A target that is gone takes its holds with it.
assert_ok "begin_interact_as $H1 $NEAR 0" "a helper on the downed NPC"
assert_ok "despawn_entity $NEAR" "and the target despawned"
assert_eq "$(row_count "SELECT * FROM hold_progress")" "0" "its holds gone with it"
assert_eq "$(row_count "SELECT * FROM hold_member")" "0" "every helper let go"
for e in $H1 $H2 $H3; do spacetime call "$DB" despawn_entity "$e" >/dev/null 2>&1; done
assert_ok "reset_rule foundation.hold_speed" "holds at their own speed"

echo "== NPC brains persist, for their authority only =="
# `write_npc_brain` keeps what a brain needs to resume after its sidecar restarts. Called here as
# the publisher, who is an authority for every world (world_id 0) — and whose row in `authority`
# is ALSO for world 0, which is why this NPC is spawned there: the table's filter joins on the
# world, so world 0 is the one the publisher can read back.
# Arguments are JSON; they are passed as an array so quoting survives the shell.
call() { spacetime call "$DB" "$@" 2>&1; }
ok_call() {   # ok_call LABEL ARGS...
  local label="$1"; shift
  local out; out="$(call "$@")"
  if echo "$out" | grep -qiE "^error|error:"; then fail "$label ($(echo "$out" | head -2 | tail -1))"; else pass; fi
}
refused_call() {   # refused_call PATTERN LABEL ARGS...
  local pattern="$1" label="$2"; shift 2
  local out; out="$(call "$@")"
  if echo "$out" | grep -qi "$pattern"; then pass; else fail "$label (output: $(echo "$out" | head -2 | tail -1))"; fi
}
ok_call "spawn an NPC to have a brain" spawn_npc 0 1 '{"x":8.0,"y":0.0,"z":8.0}'
NPC="$(sql_rows "SELECT entity_id FROM entity WHERE kind = 1" | tail -1 | tr -d ' ')"
check "$([ -n "$NPC" ] && echo true || echo false)" "the NPC exists ($NPC)"
ok_call "write a brain" write_npc_brain "$NPC" '"wander"' '"rest"' 0 '"{\"home\":[8.0,0.0,8.0]}"'
assert_eq "$(sql_first "SELECT brain FROM npc_brain WHERE entity_id = $NPC" 1 | tr -d '"')" "wander" \
  "the brain is stored under its entity"
check "$(sql_first "SELECT data FROM npc_brain WHERE entity_id = $NPC" 1 | grep -q 'home' && echo true || echo false)" \
  "with the brain's own data, which the module never parses"
ok_call "write it again" write_npc_brain "$NPC" '"wander"' '"wander"' 0 '"{\"home\":[8.0,0.0,8.0]}"'
assert_eq "$(row_count "SELECT * FROM npc_brain WHERE entity_id = $NPC")" "1" \
  "a second write replaces the row rather than adding one"
assert_eq "$(sql_first "SELECT state FROM npc_brain WHERE entity_id = $NPC" 1 | tr -d '"')" "wander" \
  "and carries the new state"
assert_eq "$(sql_rows_anon 'SELECT * FROM npc_brain' | wc -l | tr -d ' ')" "0" \
  "a client that is not the world's authority sees no brain at all"
refused_call "no brain" "a player entity has no brain to write" \
  write_npc_brain "$MYENT" '"wander"' '"rest"' 0 '"{}"'
refused_call "no such entity" "a brain for nothing is refused" \
  write_npc_brain 999999 '"wander"' '"rest"' 0 '"{}"'
big="$(python -c "print('x' * 5000)")"
refused_call "limit" "a brain bigger than MAX_BRAIN_DATA is refused" \
  write_npc_brain "$NPC" '"wander"' '"rest"' 0 "\"$big\""
ok_call "despawn the NPC" despawn_entity "$NPC"
assert_eq "$(row_count "SELECT * FROM npc_brain WHERE entity_id = $NPC")" "0" \
  "and its brain goes with it"

echo "== bots: a member with a brain, driven by the world's referee (DECISIONS #230) =="
# Milestone 7. A bot is an NPC that is a session member and has an `npc_brain` row; the world's referee
# (a MODULE world: its players move themselves) builds and drives only its bots, through the same
# movement model and the level's walls, and writes where they went.
out="$(anon_call add_bot "$SESS0" 1 '"wander"' '{"x":6.0,"y":0.0,"z":6.0}')"
check "$(echo "$out" | grep -qi "admin" && echo true || echo false)" "a player cannot add a bot"
refused_call "a brain's name" "a bot needs a brain" add_bot "$SESS0" 1 '""' '{"x":6.0,"y":0.0,"z":6.0}'
refused_call "no such session" "nor to a session that is not there" add_bot 999999 1 '"wander"' '{"x":6.0,"y":0.0,"z":6.0}'
ok_call "a bot that wanders, in world 0's session (open ground: not under the greybox's platform)" add_bot "$SESS0" 1 '"wander"' '{"x":-4.0,"y":0.0,"z":4.0}'
BOT="$(sql_rows "SELECT entity_id FROM npc_brain WHERE brain = 'wander'" | awk '{print $1}' | sort -n | tail -1)"
check "$([ -n "$BOT" ] && echo true || echo false)" "it has a brain row ($BOT)"
assert_eq "$(row_count "SELECT * FROM session_member WHERE entity_id = $BOT AND session_id = $SESS0")" "1" "and is a member of the session"
assert_eq "$(row_count "SELECT * FROM player WHERE entity_id = $BOT")" "0" "and is nobody's player"
BOT_AT="$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $BOT" 1)"
BOT_CODE='"refereeforthebotsinthesuite"'
assert_ok "offer_referee 0 $BOT_CODE" "a referee for world 0 is offered"
BOT_LOG="$(mktemp)"
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --claim=refereeforthebotsinthesuite > "$BOT_LOG" 2>&1 &
BOT_PID=$!
for _ in $(seq 1 60); do grep -q "is driven by brain 'wander'" "$BOT_LOG" && break; sleep 1; done
check "$(grep -q "claim_referee: registered" "$BOT_LOG" && echo true || echo false)" "a real referee claimed the world"
check "$(grep -q "entity $BOT is driven by brain 'wander'" "$BOT_LOG" && echo true || echo false)" "it builds the bot and drives it by its row's brain"
check "$(grep -q "simulating entity $MYENT " "$BOT_LOG" && echo false || echo true)" "and not the CLI's player (players move themselves)"
sleep 6
BOT_NOW="$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $BOT" 1)"
check "$(python -c "
import re
a=[float(x) for x in re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', '''$BOT_AT''')][:3]
b=[float(x) for x in re.findall(r'-?[0-9.]+(?:e-?[0-9]+)?', '''$BOT_NOW''')][:3]
print('true' if ((a[0]-b[0])**2+(a[2]-b[2])**2) ** 0.5 > 0.5 else 'false')")" "it wanders: the server has it somewhere else ($BOT_AT -> $BOT_NOW)"
check "$(sql_first "SELECT state FROM npc_brain WHERE entity_id = $BOT" 1 | grep -qE "wander|rest" && echo true || echo false)" "and its brain keeps its row ($(sql_first "SELECT state FROM npc_brain WHERE entity_id = $BOT" 1))"
ok_call "every bot leaves the session" remove_bots "$SESS0"
assert_eq "$(row_count "SELECT * FROM entity WHERE entity_id = $BOT")" "0" "the bot is gone, every row of it"
assert_eq "$(row_count "SELECT * FROM npc_brain WHERE entity_id = $BOT")" "0" "its brain too"
sleep 1.5
check "$(grep -q "released entity $BOT" "$BOT_LOG" && echo true || echo false)" "and the referee let it go"
kill "$BOT_PID" 2>/dev/null; wait "$BOT_PID" 2>/dev/null
for REF_ID in $(sql_rows 'SELECT identity FROM authority WHERE role = 1 AND world_id = 0' | awk '{print $1}'); do
  assert_ok "revoke_authority $REF_ID" "the bots' referee unregistered"
done
rm -f "$BOT_LOG"

# =============================================================================
# THE MATCH (DECISIONS #182): rounds count from 1 per match; a world nobody is in stops
# =============================================================================
echo "== the match =="
assert_eq "$(row_count 'SELECT * FROM session_match WHERE session_id = 1')" "1" "the default session has a match"
out="$(spacetime call --anonymous "$DB" new_match 1 2>&1)"
check "$(echo "$out" | grep -qi "admin only" && echo true || echo false)" "only an admin ends a match by hand"
assert_ok "set_session_phase 1 1" "a round under way"
assert_eq "$(sql_first 'SELECT started FROM session_match WHERE session_id = 1' 1)" "true" "so the match has started"
MATCH_N="$(sql_first 'SELECT number FROM session_match WHERE session_id = 1' 1)"
ROUND_BEFORE="$(sql_first 'SELECT round FROM session WHERE id = 1' 1)"
assert_ok "new_match 1" "end the match"
assert_eq "$(sql_first 'SELECT phase FROM session WHERE id = 1' 1)" "0" "back in the lobby"
ROUND_NOW="$(sql_first 'SELECT round FROM session WHERE id = 1' 1)"
assert_eq "$ROUND_NOW" "$((ROUND_BEFORE + 1))" "the round that was under way ended: the session's count goes on (catches are filed under it)"
assert_eq "$(sql_first 'SELECT first_round FROM session_match WHERE session_id = 1' 1)" "$ROUND_NOW" \
  "and the new match counts from here: its next round is round 1"
assert_eq "$(sql_first 'SELECT started FROM session_match WHERE session_id = 1' 1)" "false" "it has not started"
assert_eq "$(sql_first 'SELECT number FROM session_match WHERE session_id = 1' 1)" "$((MATCH_N + 1))" "and it is the next match"
ENDS="$(sql_first 'SELECT phase_ends_at FROM session WHERE id = 1' 1)"
check "$(python -c "import sys; print('true' if int('$ENDS'[:4]) > $(date -u +%Y) else 'false')" 2>/dev/null || echo false)" \
  "its lobby waits for its players rather than running out (ends $ENDS)"
run_genre_hooks integration_match_began   # what a genre resets per match (fishing: dawn)
assert_ok "set_ready true" "the one player here says ready"
assert_eq "$(sql_first 'SELECT phase FROM session WHERE id = 1' 1)" "1" "and the match's first round starts"
assert_eq "$(sql_first 'SELECT started FROM session_match WHERE session_id = 1' 1)" "true" "the match has started"
# Nobody here: after end_after_empty_s the world's match ends, and nothing is played or counted.
EMPTY_S="$(python -c "import json; d=json.load(open('shared/rules.json')); print(int([s for s in d['sessions'] if s['kind']==0][0]['match']['end_after_empty_s']))")"
echo "  nobody online for $((EMPTY_S + 4)) s..."
sleep $((EMPTY_S + 4))
assert_eq "$(sql_first 'SELECT phase FROM session WHERE id = 1' 1)" "0" "an empty world's match ends: back to the lobby"
assert_eq "$(sql_first 'SELECT started FROM session_match WHERE session_id = 1' 1)" "false" "where the next match waits"
assert_eq "$(sql_first 'SELECT number FROM session_match WHERE session_id = 1' 1)" "$((MATCH_N + 2))" "a new one"
assert_eq "$(sql_first 'SELECT first_round FROM session_match WHERE session_id = 1' 1)" \
  "$(sql_first 'SELECT round FROM session WHERE id = 1' 1)" "counting its rounds from 1 again"

# A MEMBER FROM BEFORE THE LOBBY (DECISIONS #184): Luke's world was republished without a wipe, and
# his membership is older than lobby rows, so Ready said "you are not in a session". Made here by
# deleting our row as the database's owner.
spacetime sql "$DB" "DELETE FROM lobby_member WHERE entity_id = $MYENT" >/dev/null 2>&1
assert_ok "set_ready true" "a member with no lobby row can still say ready (the row is made)"
assert_eq "$(sql_first "SELECT ready FROM lobby_member WHERE entity_id = $MYENT" 1)" "true" "and it says ready"
assert_eq "$(sql_first 'SELECT phase FROM session WHERE id = 1' 1)" "1" "and, everyone here ready, the match starts"

# A NEW MATCH, NEW STATUSES (DECISIONS #206): everyone in the world back to normal, unless the
# game's rule says statuses last across matches.
assert_ok "set_status $MYENT 1 4294967295 \"\"" "the player is injured"
assert_ok 'spawn_resource_node 0 {"x":30.0,"y":0.0,"z":30.0}' "a thing in the world"
THING=$(sql_rows "SELECT entity_id FROM entity WHERE kind = 2" | awk '{print $1}' | sort -n | tail -1)
assert_ok "set_status $THING 5 4294967295 \"\"" "in a status of its own (a nest's stage, a gate's state)"
assert_ok "new_match 1" "a new match"
assert_eq "$(sql_first "SELECT status FROM status_state WHERE entity_id = $MYENT" 1)" "0" "and they begin it normal"
assert_eq "$(sql_first "SELECT status FROM status_state WHERE entity_id = $THING" 1)" "5" \
  "a thing keeps its status: only people are reset (DECISIONS #222; its game resets it if it means to)"
assert_ok "despawn_entity $THING" "(the thing gone)"
assert_ok "set_rule foundation.statuses_reset_each_match 0 \"\"" "a game whose statuses last"
assert_ok "set_status $MYENT 1 4294967295 \"\"" "injured again"
assert_ok "new_match 1" "another match"
assert_eq "$(sql_first "SELECT status FROM status_state WHERE entity_id = $MYENT" 1)" "1" "keeps them injured"
assert_ok "reset_rule foundation.statuses_reset_each_match" "the rule back"

# EVERY ROW OF A PLACED THING KNOWS ITS CELL (template 1.0, DECISIONS #278): a ring client is sent only
# the cells round it, so when someone crosses a cell's edge every row it is drawn from must follow
# (module/place.rs `follow`), in the same step. An EVENT (a push) is cut where it happened.
echo "== cells: every row of a placed thing follows it =="
cell_of() { python -c "import math; s = lambda v: max(-512, min(511, math.floor(v / 64.0))); print((s($1) + 512) * 1024 + s($2) + 512)"; }
assert_ok "set_status $MYENT 1 4294967295 \"\"" "the player in a status (a row of its own)"
assert_ok 'set_appearance "cells_test"' "with a look"
assert_ok "set_equip_state 2" "something in hand"
HOME=$(cell_of 0.0 0.0)
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "at the origin"
for t in entity movement_state health_state status_state appearance equip_state; do
  assert_eq "$(sql_first "SELECT chunk FROM $t WHERE entity_id = $MYENT" 1)" "$HOME" "$t is in the origin's cell"
done
assert_ok 'teleport {"x":200.5,"y":0.0,"z":-130.0}' "three cells east, three north"
FAR=$(cell_of 200.5 -130.0)
check "$([ "$FAR" != "$HOME" ] && echo true || echo false)" "(another cell: $FAR)"
for t in entity movement_state health_state status_state appearance equip_state; do
  assert_eq "$(sql_first "SELECT chunk FROM $t WHERE entity_id = $MYENT" 1)" "$FAR" "$t follows the player into its new cell"
done
assert_eq "$(sql_rows "SELECT entity_id FROM movement_state WHERE world_id = 0 AND (chunk = $FAR OR chunk = $HOME)" | grep -cw "$MYENT")" "1" \
  "a query by cells finds them in theirs"
assert_eq "$(row_count "SELECT * FROM health_state WHERE world_id = 0 AND chunk = $HOME AND entity_id = $MYENT")" "0" \
  "and no longer in the cell they left"
assert_ok "set_dev_tools true" "(dev tools on, for a push)"
assert_ok "dev_push $MYENT {\"x\":0.0,\"y\":3.0,\"z\":0.0}" "a push where they stand"
assert_eq "$(sql_first "SELECT chunk FROM push WHERE entity_id = $MYENT" 1)" "$FAR" "an event is cut in the cell it happened in"
assert_ok "set_dev_tools false" "(dev tools off)"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "home again"
for t in entity movement_state health_state status_state appearance equip_state; do
  assert_eq "$(sql_first "SELECT chunk FROM $t WHERE entity_id = $MYENT" 1)" "$HOME" "$t comes home with them"
done
assert_eq "$(sql_first "SELECT chunk FROM push WHERE entity_id = $MYENT" 1)" "$FAR" "the push stays where it happened"
assert_ok "set_status $MYENT 0 4294967295 \"\"" "(normal again)"

run_genre_hooks integration_end   # a genre's checks that end a match or change what follows (Fowl Play: a new match is a new night)

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
