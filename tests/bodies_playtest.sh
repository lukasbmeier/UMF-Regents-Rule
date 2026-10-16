#!/usr/bin/env bash
# BODIES THE REFEREE MOVES, PLAYED (DECISIONS #246): the world's real referee and two real clients at a
# simulated round trip. One throws the greybox's ball at the east wall; the other watches. The thrower's
# ball leaves the hand on the throw and stays with the referee's through the wall's bounce, without a
# snap; the watcher sees it fly smoothly from the referee's rows; both see it come to rest where the
# referee put it; the wall's hit is a contact everyone gets.
#
#   GODOT=/path/to/godot ./tests/bodies_playtest.sh           # 150 ms round trip, 20 ms jitter
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://tests/playtest/bodies_playtest.tscn"
CODE='"bodiesplaytestrefereecode"'

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_world_level 0 0 >/dev/null 2>&1 || { echo "set_world_level failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the watcher steps aside
sleep 2

ref_log="$(mktemp)"; watch_log="$(mktemp)"; throw_log="$(mktemp)"
ref_pid=""; watch_pid=""
cleanup() {
  [ -n "$watch_pid" ] && kill "$watch_pid" 2>/dev/null
  [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null
  wait 2>/dev/null
  rm -f "$ref_log" "$watch_log" "$throw_log"
}
trap cleanup EXIT

echo "== the world's referee =="
spacetime call "$DB" offer_referee 0 "$CODE" >/dev/null 2>&1 || { echo "offer_referee failed" >&2; exit 1; }
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --claim="${CODE//\"/}" --no-record >"$ref_log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$ref_log" && break; sleep 0.5; done
if ! grep -q "claim_referee: registered" "$ref_log"; then
  echo "the referee did not register:" >&2; tail -20 "$ref_log" >&2; exit 1
fi
echo "ok"

status=0
report() {   # report LOG
  grep -E "^   |FAIL|passed,|\[Bodies\]|binding after" "$1"
  if grep -E "SCRIPT ERROR" "$1" >/dev/null; then
    echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$1" | head -12 >&2; status=1
  fi
}
echo "== at ${LATENCY} ms round trip, ${JITTER} ms jitter: one throws, one watches =="
"$GODOT" --headless --path . "$SCENE" -- --token=watcher --role=watcher --latency="$LATENCY" --jitter="$JITTER" >"$watch_log" 2>&1 &
watch_pid=$!
"$GODOT" --headless --path . "$SCENE" -- --token=thrower --role=thrower --latency="$LATENCY" --jitter="$JITTER" >"$throw_log" 2>&1
[ $? -eq 0 ] || status=1
wait "$watch_pid"; [ $? -eq 0 ] || status=1
watch_pid=""
echo "-- thrower"; report "$throw_log"
echo "-- watcher"; report "$watch_log"
echo "-- the referee"; grep -E "\[Bodies\]|ERROR" "$ref_log" | head -10
REST=$(spacetime sql "$DB" "SELECT at_rest, frames FROM body_state" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | head -1)
echo "   the server's ball: $REST"
echo "$REST" | grep -q "true" || { echo "  FAIL: the server's ball is not at rest" >&2; status=1; }
exit "$status"
