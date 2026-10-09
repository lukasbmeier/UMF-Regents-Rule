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
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `<database>-test` (shared/game.json), never on the
# database a person plays in. UMF_DB reaches every Godot process started from here.
. tests/lib/db.sh
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
# One pass: publish fresh, then the playtest at `$1` ms; `$2`: extra client arguments. Leaves the
# client's output in $last_out.
run_pass() {
  local ms="$1" extra="${2:-}"
  echo "== publish (fresh data) =="
  (cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1     || { echo "publish failed" >&2; exit 1; }
  # Every scripted route in this suite is on the greybox (level 0); a game's default world may run
  # another. The foundation's switch moves the spawn to the origin; a genre's hook sets up its part.
  spacetime call "$DB" set_world_level 0 0 >/dev/null 2>&1     || { echo "set_world_level failed" >&2; exit 1; }
  # Its clients teleport (and nudge) themselves: dev tools, off on any other database (REVIEW B1).
  spacetime call "$DB" set_dev_tools true >/dev/null 2>&1     || { echo "set_dev_tools failed" >&2; exit 1; }
  sleep 3
  spacetime call "$DB" set_session_phase 1 1 >/dev/null 2>&1

  last_out="$(mktemp)"
  local j=0; [ "$ms" -gt 0 ] && j="$JITTER"
  "$GODOT" --headless --path . "$SCENE" -- --token=playtest --latency="$ms" --jitter="$j" $extra 2>&1 | tee "$last_out"
  local status=${PIPESTATUS[0]}
  if grep -E "SCRIPT ERROR" "$last_out" >/dev/null; then
    echo "VIOLATION: the client produced script errors:" >&2
    grep -E "SCRIPT ERROR" "$last_out" | head -5 >&2
    status=1
  fi
  [ "$status" -eq 0 ] || overall=1
  echo
}
for ms in $LATENCIES; do
  run_pass "$ms"
  rm -f "$last_out"
done

# A CHARACTER WITH ITS OWN MOVEMENT PROFILE (DECISIONS #205): the same playtest, played as a slow
# runner (tests/fixtures/slow_character.tres: run 3, sprint 4.5, everything else the default's).
# Its speed checks follow the character's numbers, so passing proves the client predicts with the
# profile and the server accepts what it predicted.
echo "== playing as a character with a slow movement profile =="
run_pass 100 "--character=res://tests/fixtures/slow_character.tres"
if grep -q "\[Boot\] playing as Slow runner" "$last_out" && grep -q "\[playtest\] moving by run 3.0 " "$last_out"; then
  echo "  ok   the player moved by the slow runner's profile (run 3 m/s)"
else
  echo "  FAIL the player did not move by the slow runner's profile" >&2
  overall=1
fi
rm -f "$last_out"
exit "$overall"
