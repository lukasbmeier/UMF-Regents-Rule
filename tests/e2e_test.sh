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
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
GODOT="${GODOT:-godot}"

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
