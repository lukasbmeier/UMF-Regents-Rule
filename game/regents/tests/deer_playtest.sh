#!/usr/bin/env bash
# A DEER GRAZES AND FLEES, ON A REAL REFEREE (hunting, 2026-11-09, HERBALISM_HUNTING_PREP.md §7 step 3). The world's
# referee with Regent's own say runs the glade's deer (deer_1 at (-30, 5), its brain `regents/deer`):
#   - nobody near (this CLI's player at the spawn, 30 m off): it grazes, never far from home (the negative)
#   - the player 9 m off and in sight: it gallops away (well past a walk, its brain "flee"), farther than it was
#   - the player gone: it calms and walks back near home, at a walk
#
#   GODOT=<path> ./game/regents/tests/deer_playtest.sh     (Windows: tools\run.cmd game\regents\tests\deer_playtest.sh)
#
# Requires a local server (`spacetime start`). Publishes the TEST database with --delete-data.
# DEER_LOG=<file>: keep the referee's log there.
set -uo pipefail
cd "$(dirname "$0")/../../.."
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
assert_ok() { local out; out="$(call "$@")"; if echo "$out" | grep -qiE "^error|error:"; then fail "$1 ($(echo "$out" | tail -1))"; else pass; fi; }

log="${DEER_LOG:-$(mktemp)}"; ref_pid=""
cleanup() {
  [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null
  wait 2>/dev/null
  [ -z "${DEER_LOG:-}" ] && rm -f "$log"
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

HOME_X=-30; HOME_Z=5
DEER="$(sql_first "SELECT entity_id FROM foe WHERE point_id = 'deer_1'" 1)"
check "$([ -n "$DEER" ] && [ "$(sql_first "SELECT kind FROM entity WHERE entity_id = $DEER" 1)" = "106" ] && echo true || echo false)" "the glade's deer ($DEER)"
assert_ok teleport '{"x":0.0,"y":0.0,"z":8.0}'   # this CLI's player, at the spawn: 30 m from the deer
# THE PLAYER IT SEES is a standing bot of the player's kind (0): this CLI's own player is offline between calls.
SESS0="$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)"

echo "== the world's referee, with Regent's say =="
assert_ok offer_referee 0 '"regentsdeerrefereecode"'
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee \
  --no-record --name=deer_playtest --claim=regentsdeerrefereecode > "$log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 90); do grep -q "claim_referee: registered" "$log" && break; sleep 0.5; done
check "$(grep -q "claim_referee: registered" "$log" && echo true || echo false)" "the referee registered"
for _ in $(seq 1 30); do grep -q "is driven by brain 'regents/deer'" "$log" && break; sleep 0.5; done
check "$(grep -q "is driven by brain 'regents/deer'" "$log" && echo true || echo false)" "the deer is driven by its brain (regents/deer)"

# where: "x z" of the deer now; state: its brain's state.
where() { sql_first "SELECT pos FROM movement_state WHERE entity_id = $DEER" 1 | python -c "
import re, sys
s = sys.stdin.read(); x = re.search(r'x = ([-0-9.e]+)', s); z = re.search(r'z = ([-0-9.e]+)', s)
print(x.group(1) if x else 'nan', z.group(1) if z else 'nan')"; }
state() { sql_first "SELECT state FROM npc_brain WHERE entity_id = $DEER" 1 | tr -d '"'; }
dist() { python -c "import math,sys; print('%.2f' % math.hypot(float(sys.argv[1]) - float(sys.argv[3]), float(sys.argv[2]) - float(sys.argv[4])))" "$@"; }
# watch SECONDS: the deer's farthest from home and fastest (m/s between looks; a look through the CLI takes a second or
# two, so this is an average over that), and its first look ("$fx $fz" at $ft ms).
watch() {
  local until=$(( $(date +%s) + $1 )); far=0; fast=0; local px="" pz="" pt=""; fx=""; fz=""; ft=""
  while [ "$(date +%s)" -lt "$until" ]; do
    read -r x z <<< "$(where)"; local t; t="$(date +%s%3N)"
    far="$(python -c "print(max($far, $(dist "$x" "$z" $HOME_X $HOME_Z)))")"
    if [ -n "$px" ]; then
      fast="$(python -c "import math; dt=($t-$pt)/1000.0; print(max($fast, math.hypot($x-$px, $z-$pz)/dt if dt > 0.05 else 0))")"
    fi
    [ -n "${DEER_TRACE:-}" ] && echo "     t=$t x=$x z=$z"
    [ -z "$fx" ] && { fx="$x"; fz="$z"; ft="$t"; }
    px="$x"; pz="$z"; pt="$t"
    sleep 0.2
  done
}

echo "== nobody near: it grazes round home =="
watch 12
check "$(python -c "print('true' if $far <= 7.0 else 'false')")" "NEGATIVE: with nobody near it stays within its grazing range of home ($far m at the farthest)"
echo "   farthest from home $far m, fastest $fast m/s, state $(state)"

echo "== a player 9 m off, in sight: it bolts =="
read -r x0 z0 <<< "$(where)"
T0="$(date +%s%3N)"
assert_ok add_bot "$SESS0" 0 '"stand"' "{\"x\":$(python -c "print($x0 + 9.0)"),\"y\":0.0,\"z\":$z0}"
watch 6
# ITS PACE from the moment the player came to its first look after (the CLI's looks are too far apart to catch a 3 s
# gallop between two of them): a lower bound on its gallop, the bot's coming and the brain's seeing included.
PACE="$(python -c "print('%.2f' % ($(dist "$fx" "$fz" "$x0" "$z0") / max(0.1, ($ft - $T0) / 1000.0)))")"
read -r x1 z1 <<< "$(where)"
echo "   farthest from home $far m, fastest $fast m/s, now $(dist "$x1" "$z1" "$(python -c "print($x0 + 9.0)")" "$z0") m from the player"
check "$(python -c "print('true' if $PACE >= 3.0 else 'false')")" "it galloped: $PACE m/s from the player's coming to its first look after, at the least (a walk is 1.4)"
check "$(python -c "print('true' if $(dist "$x1" "$z1" "$(python -c "print($x0 + 9.0)")" "$z0") >= 18.0 else 'false')")" "and got well away from the player (from 9 m to $(dist "$x1" "$z1" "$(python -c "print($x0 + 9.0)")" "$z0") m)"
check "$(python -c "print('true' if $(dist "$x1" "$z1" "$x0" "$z0") >= 10.0 else 'false')")" "running away from them, not round them (it moved $(dist "$x1" "$z1" "$x0" "$z0") m)"

echo "== the player gone: it calms and walks home =="
assert_ok remove_bots "$SESS0"
back=false
for _ in $(seq 1 60); do
  read -r x z <<< "$(where)"
  if python -c "import sys; sys.exit(0 if $(dist "$x" "$z" $HOME_X $HOME_Z) <= 7.0 else 1)"; then back=true; break; fi
  sleep 1
done
check "$back" "it came back near home ($(dist "$x" "$z" $HOME_X $HOME_Z) m from it) once calm"
watch 4
check "$(python -c "print('true' if $fast <= 3.0 else 'false')")" "and back home it walks, never gallops (fastest $fast m/s)"

echo
echo "deer playtest: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
