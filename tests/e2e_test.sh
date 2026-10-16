#!/usr/bin/env bash
# End-to-end: publishes a fresh module, then runs a REAL Godot client against it and asserts
# on what the client observes. This is the only layer that exercises BSATN encoding, the SDK
# adapter and the generated bindings together — see tests/e2e/e2e_runner.gd for why that
# matters (DECISIONS #40 was invisible to every other suite).
#
#   GODOT=/path/to/godot ./tests/e2e_test.sh
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `<database>-test` (shared/game.json), never on the
# database a person plays in. UMF_DB reaches every Godot process started from here.
. tests/lib/db.sh
GODOT="${GODOT:-godot}"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
# Every scripted route in this suite is on the greybox (level 0); a game's default world may run
# another. The foundation's switch moves the spawn to the origin; a genre's hook sets up its part.
spacetime call "$DB" set_world_level 0 0 >/dev/null 2>&1 \
  || { echo "set_world_level failed" >&2; exit 1; }
# Its clients teleport (and nudge) themselves: dev tools, off on any other database (REVIEW B1).
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 \
  || { echo "set_dev_tools failed" >&2; exit 1; }
# Its game reports how it ran every 2 s, not 30 (DECISIONS #244), so a run this short sends some.
spacetime call "$DB" set_rule foundation.telemetry_window_s 2 '""' >/dev/null 2>&1 \
  || { echo "set_rule telemetry_window_s failed" >&2; exit 1; }
sleep 3
echo "ok"

echo "== real client against the live module =="
out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT
"$GODOT" --headless --path . res://tests/e2e/e2e_test.tscn 2>&1 | tee "$out_file"
status=${PIPESTATUS[0]}

# A client that silently fails to decode a row still "passes" if nothing asserts on it, so
# treat script errors as failures here exactly as run_tests.sh does.
if grep -E "SCRIPT ERROR" "$out_file" >/dev/null; then
  echo "VIOLATION: the client produced script errors:" >&2
  grep -E "SCRIPT ERROR" "$out_file" | head -5 >&2
  exit 1
fi
[ "$status" -eq 0 ] || exit "$status"

# HOW IT RAN, REPORTED (DECISIONS #244): the real client's own windows reached the host, its own (an
# entity that is a player's, not the CLI's), with frames counted and a frame rate.
REPORTS=$(spacetime sql "$DB" --format json "SELECT entity_id, role, frames, fps, build FROM perf_report" 2>/dev/null \
  | python -c "import json,sys; t=sys.stdin.read(); rows=json.loads(t[t.find('['):])[0]['rows'] if '[' in t else []; ok=[r for r in rows if r[0] > 0 and r[1] == 0 and r[2] > 0 and r[3] > 0 and len(r[4]) > 0]; print(len(ok))")
if [ "${REPORTS:-0}" -ge 1 ]; then
  echo "  telemetry: the real client reported $REPORTS window(s) of how it ran"
else
  echo "  FAIL: the real client sent no performance report (perf_report: ${REPORTS:-none})" >&2
  exit 1
fi

# THE SAME PLAYER, RESTARTED (DECISIONS #149): a second client with the first one's identity
# (its token persisted in user://). The server still holds the first run's input count for the
# entity; this run's own sampled inputs must be heard at once, not dropped until they catch up.
echo "== the same identity, restarted =="
"$GODOT" --headless --path . res://tests/e2e/e2e_test.tscn -- --restart-check 2>&1 | tee "$out_file"
status=${PIPESTATUS[0]}
if grep -E "SCRIPT ERROR" "$out_file" >/dev/null; then
  echo "VIOLATION: the restarted client produced script errors:" >&2
  grep -E "SCRIPT ERROR" "$out_file" | head -5 >&2
  exit 1
fi
exit "$status"
