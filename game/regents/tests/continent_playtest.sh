#!/usr/bin/env bash
# THE CONTINENT, WALKED (PROGRESS step 23): a real client on ring interest in the continent (level 21), a
# world bigger than one ring. Only the cells round it are loaded and sent; far away (a teleport) both follow
# and the camp's are let go; a cell over, what both rings share is kept, never spawned again; it stands on
# the ground; back at the camp the ring follows at once, and the CLI's player (online, a tool) is never seen.
# The checks are the client's (game/regents/tests/playtest/continent_playtest.gd).
#
#   GODOT=/path/to/godot ./game/regents/tests/continent_playtest.sh     # 150 ms round trip, 20 ms jitter
#   WINDOWED=1 GODOT=... ./game/regents/tests/continent_playtest.sh     # in a window: the minimap pictured round you too
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/continent_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data), world 0 on the continent =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the client teleports
spacetime call "$DB" set_world_level 0 21 >/dev/null 2>&1 || { echo "set_world_level failed" >&2; exit 1; }
sleep 2
LEVEL=$(spacetime sql "$DB" "SELECT level_id FROM world_level WHERE world_id = 0" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | head -1 | tr -d ' ')
NODES=$(spacetime sql "$DB" "SELECT entity_id FROM gather_node WHERE world_id = 0" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | wc -l)
echo "   world 0 runs level ${LEVEL:-none} (the continent is 21), with $NODES nodes"

log="$(mktemp)"; pid=""; cli_pid=""
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; [ -n "$cli_pid" ] && kill "$cli_pid" 2>/dev/null; wait 2>/dev/null; rm -f "$log"; }
trap cleanup EXIT
# The database's CLI comes back every few seconds throughout, as the host's feedback watcher does (Luke's
# playtest, 2026-10-24: its nameless "Player 39" was drawn at the spawn): its player stays at the camp (never
# parked), a tool, never seen.
( while true; do spacetime sql "$DB" "SELECT * FROM world_level" >/dev/null 2>&1; sleep 3; done ) &
cli_pid=$!
sleep 2
HL="--headless"; [ -n "${WINDOWED:-}" ] && HL=""   # WINDOWED=1: in a window, so the minimap's pictures are taken too
echo "== a client at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
"$GODOT" $HL --path . "$SCENE" -- --token=walker --latency="$LATENCY" --jitter="$JITTER" --autoconnect >"$log" 2>&1 &
pid=$!
wait "$pid"; status=$?; pid=""
grep -E "^   |FAIL|passed,|LevelStreamer" "$log"
if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
  echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$log" | head -12 >&2; status=1
fi
exit "$status"
