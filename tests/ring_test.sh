#!/usr/bin/env bash
# RING INTEREST ON A REAL SERVER (template 1.0, DECISIONS #278): a client sent only the 3 x 3 cells round
# it sees its neighbours there and nobody beyond, keeps a neighbour that walks between two of its cells
# (never deleted and spawned again), and gains and loses neighbours as it moves. The checks are the
# client's (tests/ring/ring_runner.gd); this places the NPCs and runs it.
#
#   GODOT=<path> ./tests/ring_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data), three neighbours =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_world_level 0 0 >/dev/null 2>&1
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1
sql_ids() { spacetime sql "$DB" "SELECT entity_id FROM entity WHERE kind = 0" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ' | sort -n; }
before="$(sql_ids)"
spawn_at() { spacetime call "$DB" spawn_npc 0 0 "{\"x\":$1,\"y\":0.0,\"z\":$2}" >/dev/null 2>&1; comm -13 <(echo "$before") <(sql_ids) | tail -1; }
NEAR="$(spawn_at 10.0 10.0)"; before="$(sql_ids)"
EAST="$(spawn_at 150.0 10.0)"; before="$(sql_ids)"
WEST="$(spawn_at -100.0 10.0)"
echo "near $NEAR, east $EAST, west $WEST"
[ -n "$NEAR" ] && [ -n "$EAST" ] && [ -n "$WEST" ] || { echo "the NPCs were not placed" >&2; exit 1; }
sleep 2

echo "== the client =="
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
"$GODOT" --headless --path . res://tests/ring/ring_test.tscn -- --token=ring_client --name=Ringer \
  "--near=$NEAR" "--east=$EAST" "--west=$WEST" 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
if grep -q "SCRIPT ERROR" "$out"; then echo "VIOLATION: the client produced script errors" >&2; exit 1; fi
exit "$status"
