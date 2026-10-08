#!/usr/bin/env bash
# GENRES ARE MODULES (DECISIONS #173): the server built from a game of NO genres (the foundation
# alone, tests/fixtures/game_no_genres.json) type-checks, builds, passes the native suites, and
# publishes a database with the foundation's tables and none of fishing's. Then the real game is
# built again, so nothing is left behind.
#
#   GODOT=<path> ./tests/genres_test.sh      (Godot is not needed; the server is)
set -uo pipefail
cd "$(dirname "$0")/.."
DB="${DB:-umf-test}"
export UMF_DB="$DB"
passes=0; failures=0
check() { if [ "$1" = "true" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $2" >&2; fi }

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== the foundation alone =="
# A Windows path where there is one (pwd -W): rustc and build.rs are native programs.
export UMF_GAME="$(pwd -W 2>/dev/null || pwd)/tests/fixtures/game_no_genres.json"
(cd server && cargo check --target wasm32-unknown-unknown >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "the module type-checks with no genres"
out="$(cd server && cargo test 2>&1)"
check "$(echo "$out" | grep -q 'test result: FAILED\|error\[' && echo false || echo true)" "the native suites pass with no genres"
check "$(echo "$out" | grep -q 'fishing_claims_only_its_own' && echo false || echo true)" "and fishing's own tests are not compiled in"
(cd server && spacetime build >/dev/null 2>&1 && spacetime publish "$DB" --server local --delete-data --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "it builds and publishes"
sleep 2
check "$(spacetime sql "$DB" "SELECT * FROM session" 2>/dev/null | grep -q '|' && echo true || echo false)" \
  "the foundation's tables are there (a session)"
# Captured first: under pipefail, the refusal's own exit status would sink the grep that found it.
no_table="$(spacetime sql "$DB" "SELECT * FROM catch" 2>&1)"
check "$(echo "$no_table" | grep -qi 'no such table' && echo true || echo false)" \
  "and fishing's are not (no catch table)"
no_reducer="$(spacetime call "$DB" cast '{"x":0.0,"y":0.0,"z":0.0}' 2>&1)"
check "$(echo "$no_reducer" | grep -qi 'no such reducer\|not found\|reducers not shown' && echo true || echo false)" \
  "nor its reducers (no cast: \"$(echo "$no_reducer" | grep -i error | head -1)\")"

echo "== the game again =="
unset UMF_GAME
(cd server && cargo check --target wasm32-unknown-unknown >/dev/null 2>&1 && spacetime build >/dev/null 2>&1 \
  && spacetime publish "$DB" --server local --delete-data --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "the real game builds and publishes again"
check "$(spacetime sql "$DB" "SELECT * FROM fishing_world" 2>/dev/null | grep -q '|' && echo true || echo false)" \
  "with fishing in it (the lakeside is set up)"

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
