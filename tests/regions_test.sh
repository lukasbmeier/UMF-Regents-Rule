#!/usr/bin/env bash
# REGION REFEREES on a real server (DECISIONS #288): two referees for one world, west and east of x = 0,
# and a bot that wanders round a home on that edge. The module gives it to one referee at a time
# (`npc_driver`); as it walks over the edge (and 0.5 m on, `--hand-on=0.5`) the one it leaves lets go and
# the other takes it. A second referee is offered with `offer_region_referee` (`offer_referee` refuses one
# while the world has a referee); a take from a referee that is still there is skipped, from one that has
# gone it is granted.
#
#   GODOT=<path> ./tests/regions_test.sh        (Windows: tools\run.cmd tests\regions_test.sh)
#
# Requires a local server (`spacetime start`). Publishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
. tests/lib/db.sh

passes=0
failures=0
pass() { passes=$((passes + 1)); }
fail() { failures=$((failures + 1)); echo "  FAIL: $1" >&2; }
check() { if [ "$1" = "true" ]; then pass; else fail "$2"; fi }
sql_rows() { spacetime sql "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d'; }
sql_first() { sql_rows "$1" | head -1 | awk -v c="$2" -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $c); print $c}'; }
call() { spacetime call "$DB" "$@" 2>&1; }
assert_ok() { local out; out="$(call $1)"; if echo "$out" | grep -qiE "^error|error:"; then fail "$2 ($(echo "$out" | tail -1))"; else pass; fi; }
assert_refused() { local out; out="$(call $1)"; if echo "$out" | grep -qi "$2"; then pass; else fail "$3 (got: $(echo "$out" | tail -1))"; fi; }

west_log="$(mktemp)"; east_log="$(mktemp)"; west_pid=""; east_pid=""
cleanup() {
  for p in "$west_pid" "$east_pid"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  wait 2>/dev/null
  rm -f "$west_log" "$east_log"
}
trap cleanup EXIT

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
sleep 3

echo "== a bot whose home is on the edge between two regions =="
SESS0="$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)"
assert_ok "add_bot $SESS0 1 \"wander\" {\"x\":0.0,\"y\":0.0,\"z\":4.0}" "a wandering bot at x = 0"
BOT="$(sql_rows "SELECT entity_id FROM npc_brain WHERE brain = 'wander'" | awk '{print $1}' | sort -n | tail -1)"
check "$([ -n "$BOT" ] && echo true || echo false)" "it is there ($BOT)"

start_referee() {   # start_referee NAME REGION LOG CODE
  "$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --no-record \
    --name="$1" --region="$2" --hand-on=0.5 --claim="$4" > "$3" 2>&1 &
}
identity_of() { grep -o 'identity 0x[0-9a-f]*' "$1" | head -1 | sed 's/.*0x//'; }

echo "== the west referee: cells x -8 to -1 =="
assert_ok "offer_referee 0 \"regionstestwestreferee\"" "a referee offered"
start_referee regions_west "-8,-8,-1,7" "$west_log" regionstestwestreferee; west_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$west_log" && break; sleep 0.5; done
check "$(grep -q "claim_referee: registered" "$west_log" && echo true || echo false)" "the west referee registered"
check "$(grep -q "a region referee: cells -8,-8 to -1,7" "$west_log" && echo true || echo false)" "it says its region"

echo "== a second referee for the same world =="
assert_refused "offer_referee 0 \"regionstesteastreferee\"" "already has a referee" "offer_referee: refused while the world has one"
assert_refused "offer_region_referee 0 \"short\"" "at least" "offer_region_referee: a short code refused"
assert_ok "offer_region_referee 0 \"regionstesteastreferee\"" "offer_region_referee: one more, for a region"
start_referee regions_east "0,-8,7,7" "$east_log" regionstesteastreferee; east_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$east_log" && break; sleep 0.5; done
check "$(grep -q "claim_referee: registered" "$east_log" && echo true || echo false)" "the east referee registered too"
WEST="$(identity_of "$west_log")"; EAST="$(identity_of "$east_log")"
check "$([ -n "$WEST" ] && [ -n "$EAST" ] && [ "$WEST" != "$EAST" ] && echo true || echo false)" "two identities (--name): ${WEST:0:8}, ${EAST:0:8}"

echo "== the bot changes hands as it wanders over the edge =="
driver() { sql_first "SELECT driver FROM npc_driver WHERE entity_id = $BOT" 1 | sed 's/^0x//' | tr 'A-F' 'a-f'; }
bot_x() { sql_rows "SELECT pos FROM movement_state WHERE entity_id = $BOT" | head -1 | grep -oE 'x = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/x = //'; }
west_n=0; east_n=0; none_n=0; wrong=0; changes=0; last=""; xs=""
for _ in $(seq 1 90); do
  d="$(driver)"; x="$(bot_x)"
  case "$d" in
    "$WEST") west_n=$((west_n + 1));;
    "$EAST") east_n=$((east_n + 1));;
    *) none_n=$((none_n + 1));;
  esac
  if [ -n "$x" ] && [ -n "$d" ]; then
    # Deep on one side (2 m past the edge), it must be that side's: 0.5 m of hand-on, and the poll.
    if awk -v v="$x" 'BEGIN { exit !(v < -2.0) }' && [ "$d" = "$EAST" ]; then wrong=$((wrong + 1)); fi
    if awk -v v="$x" 'BEGIN { exit !(v > 2.0) }' && [ "$d" = "$WEST" ]; then wrong=$((wrong + 1)); fi
  fi
  [ -n "$last" ] && [ "$d" != "$last" ] && changes=$((changes + 1))
  last="$d"; xs="$xs ${x%%.*}"
  [ "$changes" -ge 4 ] && [ "$west_n" -ge 3 ] && [ "$east_n" -ge 3 ] && break
  sleep 1
done
echo "   samples: west $west_n, east $east_n, nobody $none_n; changes $changes; x:$xs"
check "$([ "$west_n" -gt 0 ] && [ "$east_n" -gt 0 ] && echo true || echo false)" "driven by the west referee and by the east one, in turn"
check "$([ "$changes" -ge 2 ] && echo true || echo false)" "handed on and back ($changes changes)"
check "$([ "$wrong" -eq 0 ] && echo true || echo false)" "never driven from the wrong side ($wrong samples)"
check "$(grep -q "entity $BOT leaves this region: handed on" "$west_log" && grep -q "entity $BOT leaves this region: handed on" "$east_log" && echo true || echo false)" \
  "each referee let it go as it left (its log)"
moved="$(echo "$xs" | tr ' ' '\n' | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
check "$([ "$moved" -ge 3 ] && echo true || echo false)" "and it kept walking through the hand-offs ($moved places)"

echo "== the module: one driver at a time =="
# The CLI is the admin (an authority for every world): a take of the bot while a live referee drives it is
# skipped; the bot's driver stays that referee.
held="$(driver)"
assert_ok "drive_npcs 0 [$BOT] []" "the admin asks to take it"
check "$([ "$(driver)" = "$held" ] && echo true || echo false)" "skipped: a referee that is there keeps it"
ME="$(sql_first "SELECT entity_id FROM player" 1)"
assert_refused "drive_npcs 0 [$ME] []" "player" "a player is never taken (the CLI's own, $ME)"
out="$(spacetime call --anonymous "$DB" drive_npcs 0 "[$BOT]" "[]" 2>&1)"
check "$(echo "$out" | grep -qi "not an authority" && echo true || echo false)" "nobody else may take one"
echo "== a referee that has gone loses what it drove =="
held="$(driver)"
if [ "$held" = "$WEST" ]; then kill "$west_pid"; west_pid=""; else kill "$east_pid"; east_pid=""; fi
sleep 7   # its heartbeat lapses (5 s)
assert_ok "drive_npcs 0 [$BOT] []" "the admin asks again"
check "$([ -n "$(driver)" ] && [ "$(driver)" != "$held" ] && echo true || echo false)" "granted: taken from a referee that has gone"
assert_ok "despawn_entity $BOT" "the bot goes"
check "$([ -z "$(sql_rows "SELECT * FROM npc_driver WHERE entity_id = $BOT")" ] && echo true || echo false)" "and so does who drove it"
check "$(! grep -q "this referee read" "$west_log" "$east_log" && echo true || echo false)" "neither referee read a table it does not subscribe"
check "$(! grep -qE "SCRIPT ERROR|subscription .* failed" "$west_log" "$east_log" && echo true || echo false)" "no script errors, every subscription taken (the column ranges)"

echo
echo "regions: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
