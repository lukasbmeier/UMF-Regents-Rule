#!/usr/bin/env bash
# Remote smoothness: one real client walks, another real client watches, both through the
# client latency simulator. Asserts the watcher draws the walker continuously and snaps once on
# a teleport (PHASE4_SPEC section 5: "the remote player is smooth").
#
#   GODOT=/path/to/godot ./tests/remote_playtest.sh                 # 100 ms, 20 ms jitter
#   GODOT=... LATENCY=200 JITTER=40 ./tests/remote_playtest.sh
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-100}"
JITTER="${JITTER:-20}"
SCENE="res://tests/playtest/remote_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
# Every scripted route in this suite is on the greybox; the module's default level is the
# lakeside (the game). Selecting it moves the spawn to the origin and stocks the ponds.
spacetime call "$DB" use_level 0 0 >/dev/null 2>&1 \
  || { echo "use_level failed" >&2; exit 1; }
# Its clients teleport (and nudge) themselves: dev tools, off on any other database (REVIEW B1).
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 \
  || { echo "set_dev_tools failed" >&2; exit 1; }
sleep 3
spacetime call "$DB" set_session_phase 1 1 >/dev/null 2>&1

walker_log="$(mktemp)"; observer_log="$(mktemp)"
trap 'rm -f "$walker_log" "$observer_log"; kill -9 ${walker_pid:-} 2>/dev/null' EXIT

echo "== walker + observer at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
"$GODOT" --headless --path . "$SCENE" -- --token=walker --role=walker \
  --latency="$LATENCY" --jitter="$JITTER" >"$walker_log" 2>&1 &
walker_pid=$!
sleep 1
"$GODOT" --headless --path . "$SCENE" -- --token=observer --role=observer \
  --latency="$LATENCY" --jitter="$JITTER" 2>&1 | tee "$observer_log" \
  | grep -E "^==|^   |FAIL|passed,"
status=${PIPESTATUS[0]}
wait "$walker_pid" 2>/dev/null
walker_status=$?

for f in "$walker_log" "$observer_log"; do
  if grep -E "SCRIPT ERROR" "$f" >/dev/null; then
    echo "VIOLATION: script errors in $( [ "$f" = "$walker_log" ] && echo walker || echo observer ):" >&2
    grep -E "SCRIPT ERROR" "$f" | head -5 >&2
    status=1
  fi
done
grep -E "walker: .* passed" "$walker_log" || { echo "walker did not finish" >&2; status=1; }
[ "$walker_status" -eq 0 ] || status=1
exit "$status"
