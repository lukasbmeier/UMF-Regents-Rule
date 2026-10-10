#!/usr/bin/env bash
# THE SERVER-TIMED PRESS, PLAYED (DECISIONS #210): a real client, at a simulated round trip, uses a
# resource node and plays the timed press it starts, pressing the interact key the frame ITS bar shows
# the marker on each target. Run twice:
#   credited    the server credits each press with half the player's quickest measured round trip:
#               judged where it was seen, it scores well
#   uncredited  `foundation.press_credit_cap_ms` 0: the first press judged on arrival scores clearly
#               worse; the bar calibrates from that judgement and the next presses recover
# Together: the credit makes the first press fair at a distance, the bar's calibration keeps what
# the player sees in step with what the server judges, and the client sent only "pressed".
#
#   GODOT=/path/to/godot ./tests/press_playtest.sh              # 150 ms round trip, 20 ms jitter
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://tests/playtest/press_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_world_level 0 0 >/dev/null 2>&1 || { echo "set_world_level failed" >&2; exit 1; }
spacetime call "$DB" spawn_resource_node 0 '{"x":1.0,"y":0.0,"z":0.0}' >/dev/null 2>&1 || { echo "spawn_resource_node failed" >&2; exit 1; }
NODE=$(spacetime sql "$DB" "SELECT entity_id FROM entity WHERE kind = 2" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tail -1 | awk '{print $1}')
sleep 2

status=0
play() {   # play EXPECT
  local log; log="$(mktemp)"
  "$GODOT" --headless --path . "$SCENE" -- --token=presser --expect="$1" --node="$NODE" \
    --latency="$LATENCY" --jitter="$JITTER" >"$log" 2>&1
  local s=$?
  grep -E "^   |FAIL|passed,|\[Press\]" "$log"
  if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
    echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" "$log" | head -5 >&2; s=1
  fi
  rm -f "$log"
  [ "$s" -eq 0 ] || status=1
}
echo "== at ${LATENCY} ms round trip, ${JITTER} ms jitter: credited for the trip =="
play credited
echo "== the same, judged on arrival (foundation.press_credit_cap_ms 0) =="
spacetime call "$DB" set_rule foundation.press_credit_cap_ms 0 '""' >/dev/null 2>&1 || { echo "set_rule failed" >&2; exit 1; }
play uncredited
spacetime call "$DB" reset_rule foundation.press_credit_cap_ms >/dev/null 2>&1
exit "$status"
