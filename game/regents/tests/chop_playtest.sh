#!/usr/bin/env bash
# WOODCUTTING, PLAYED: two real clients at a simulated round trip in the frontier glade. The chopper taps
# E by a tree (AFK: logs come; walking away stops it), then holds E (a round, played with A and D while
# held still; the server replays it and pays). The buddy chops the same tree AFK at the same time.
#
#   GODOT=/path/to/godot ./game/regents/tests/chop_playtest.sh     # 150 ms round trip, 20 ms jitter
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/chop_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the clients step to the trees
sleep 2
LEVEL=$(spacetime sql "$DB" "SELECT level_id FROM world_level WHERE world_id = 0" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | head -1 | tr -d ' ')
echo "   world 0 runs level ${LEVEL:-none} (the frontier is 20)"

chop_log="$(mktemp)"; buddy_log="$(mktemp)"; buddy_pid=""
cleanup() { [ -n "$buddy_pid" ] && kill "$buddy_pid" 2>/dev/null; wait 2>/dev/null; rm -f "$chop_log" "$buddy_log"; }
trap cleanup EXIT

echo "== two clients at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
"$GODOT" --headless --path . "$SCENE" -- --token=buddy --role=buddy --latency="$LATENCY" --jitter="$JITTER" >"$buddy_log" 2>&1 &
buddy_pid=$!
"$GODOT" --headless --path . "$SCENE" -- --token=chopper --role=chopper --latency="$LATENCY" --jitter="$JITTER" >"$chop_log" 2>&1
status=$?
wait "$buddy_pid"; bstatus=$?; buddy_pid=""
for log in "$chop_log" "$buddy_log"; do
  grep -E "^   |FAIL|passed,|binding after" "$log"
  if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
    echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$log" | head -12 >&2; status=1
  fi
done
[ "$bstatus" -eq 0 ] || status=1
echo "-- the server's log"
spacetime logs "$DB" 2>/dev/null | grep -E "regents:" | tail -8
exit "$status"
