#!/usr/bin/env bash
# COMBAT, PLAYED (owner, 2026-10-19: the first slice): the world's real referee and a real client at a
# simulated round trip, in the frontier glade's camp. The fighter wields the bronze axe from the bag panel,
# Tabs onto a training dummy (the ring, its health at the top), swings the light combo and a held heavy (the
# referee judges each along the way the body faces; the numbers float up; axemanship XP), rolls (Ctrl: the
# Rolling burst carries it further than a run), blocks (the right button: no swing behind it), and lets go
# of the target (Esc).
#
#   GODOT=/path/to/godot ./game/regents/tests/combat_playtest.sh     # 150 ms round trip, 20 ms jitter
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/combat_playtest.tscn"
CODE='"regentscombatplaytestcode"'

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the client steps to the dummy
sleep 2

ref_log="$(mktemp)"; fight_log="$(mktemp)"; ref_pid=""; fight_pid=""
cleanup() { [ -n "$fight_pid" ] && kill "$fight_pid" 2>/dev/null; [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null; wait 2>/dev/null; rm -f "$ref_log" "$fight_log"; }
trap cleanup EXIT

echo "== the world's referee =="
spacetime call "$DB" offer_referee 0 "$CODE" >/dev/null 2>&1 || { echo "offer_referee failed" >&2; exit 1; }
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --claim="${CODE//\"/}" --no-record >"$ref_log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$ref_log" && break; sleep 0.5; done
if ! grep -q "claim_referee: registered" "$ref_log"; then
  echo "the referee did not register:" >&2; tail -20 "$ref_log" >&2; exit 1
fi

echo "== a fighter at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
timeout 400 "$GODOT" --headless --path . "$SCENE" -- --token=fighter --latency="$LATENCY" --jitter="$JITTER" >"$fight_log" 2>&1 &
fight_pid=$!
bow_given=""
while kill -0 "$fight_pid" 2>/dev/null; do
  if [ -z "$bow_given" ]; then
    ent="$(grep -oE '^GRANT_BOW [0-9]+' "$fight_log" | head -1 | awk '{print $2}')"
    if [ -n "$ent" ]; then
      spacetime call "$DB" grant_item "$ent" 40020 1 >/dev/null 2>&1
      spacetime call "$DB" grant_item "$ent" 40022 10 >/dev/null 2>&1
      bow_given=1
    fi
  fi
  sleep 0.3
done
wait "$fight_pid"; status=$?; fight_pid=""
grep -E "^   |FAIL|passed," "$fight_log"
if grep -E "SCRIPT ERROR" "$fight_log" >/dev/null; then
  echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$fight_log" | head -12 >&2; status=1
fi
echo "-- the referee"; grep -E "judged|ERROR" "$ref_log" | head -8
echo "-- the server's log"
spacetime logs "$DB" 2>/dev/null | grep -E "regents: .* wields|Rolling|Blocking|parried" | tail -8
exit "$status"
