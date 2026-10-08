#!/usr/bin/env bash
# Movement playtest: the real fishing scene, a real module, scripted keys, and measured feel.
# Runs twice: once at localhost speed and once through the client's latency simulator, because
# prediction that only works at 0 ms is not prediction.
#
#   GODOT=/path/to/godot ./tests/playtest_test.sh            # 0, 100, 200 ms
#   GODOT=... JITTER=50 ./tests/playtest_test.sh            # plus up to 50 ms jitter each way
#   GODOT=... LATENCIES="0 50 150" ./tests/playtest_test.sh   # pick your own
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
GODOT="${GODOT:-godot}"
LATENCIES="${LATENCIES:-0 100 200}"
# Jitter per direction, applied at every latency above 0. Real networks are never steady.
JITTER="${JITTER:-0}"
SCENE="res://tests/playtest/movement_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

overall=0
for ms in $LATENCIES; do
  echo "== publish (fresh data) =="
  (cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
    || { echo "publish failed" >&2; exit 1; }
  # Every scripted route in this suite is on the greybox; the module's default level is the
  # lakeside (the game). Selecting it moves the spawn to the origin and stocks the ponds.
  spacetime call "$DB" use_level 0 0 >/dev/null 2>&1 \
    || { echo "use_level failed" >&2; exit 1; }
  sleep 3
  spacetime call "$DB" set_session_phase 1 1 >/dev/null 2>&1

  out_file="$(mktemp)"
  j=0; [ "$ms" -gt 0 ] && j="$JITTER"
  "$GODOT" --headless --path . "$SCENE" -- --token=playtest --latency="$ms" --jitter="$j" 2>&1 | tee "$out_file"
  status=${PIPESTATUS[0]}
  if grep -E "SCRIPT ERROR" "$out_file" >/dev/null; then
    echo "VIOLATION: the client produced script errors:" >&2
    grep -E "SCRIPT ERROR" "$out_file" | head -5 >&2
    status=1
  fi
  rm -f "$out_file"
  [ "$status" -eq 0 ] || overall=1
  echo
done
exit "$overall"
