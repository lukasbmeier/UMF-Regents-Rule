#!/usr/bin/env bash
# EVERY ENTITY BINDS AT ONCE (armor run E2, 2026-11-15): one real client at a simulated round trip in the frontier
# camp. Every entity in its ring (the guide, the foes, the dummy, the nodes) must bind as soon as its rows are in:
# none waits out the foundation's 2 s bind timeout, and the log holds no "binding after ... without rows" warning.
# The foes and the guide stood frozen 2 s for a session_member row an NPC never has, until their scenes' Session
# component took it as optional (game/regents/regents_session_component.gd).
#
#   GODOT=/path/to/godot ./game/regents/tests/bind_playtest.sh     # 150 ms round trip, 20 ms jitter (~40 s)
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/bind_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the client steps to the camp
sleep 2

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
echo "== one client at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
timeout 90 "$GODOT" --headless --path . "$SCENE" -- --token=bindprobe --latency="$LATENCY" --jitter="$JITTER" >"$log" 2>&1
status=$?
grep -E "^BIND |^   |FAIL|passed," "$log"
if grep -q "binding after" "$log"; then
  echo "  FAIL: the client waited out the bind timeout:" >&2
  grep -E "binding after" "$log" | sed 's/^/    /' >&2
  status=1
else
  echo "   ok: no \"binding after ... without rows\" warning in the client's log"
fi
if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
  echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$log" | head -12 >&2; status=1
fi
# Which kinds warned, from the server's own entity rows (empty when none did).
for id in $(grep -oE 'SpaceTimeEntity [0-9]+: binding after' "$log" | awk '{print $2}' | tr -d ':'); do
  kind="$(spacetime sql "$DB" "SELECT kind FROM entity WHERE entity_id = $id" 2>/dev/null | tail -n +3 | head -1 | tr -d ' \r')"
  echo "    warned: entity $id kind ${kind:-?}" >&2
done
exit "$status"
