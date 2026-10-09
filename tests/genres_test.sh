#!/usr/bin/env bash
# GENRES ARE MODULES (DECISIONS #173): the server built from a game of NO genres (the foundation
# alone, tests/fixtures/game_no_genres.json) type-checks, builds, passes the native suites, and
# publishes a database with the foundation's tables and none of a genre's (each genre checks its own
# absence: game/<genre>/tests/hooks/genres_absent.sh). Then the real game is built again.
#
#   GODOT=<path> ./tests/genres_test.sh      (Godot is not needed; the server is)
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
passes=0; failures=0
. tests/lib/genre_hooks.sh
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
(cd server && spacetime build >/dev/null 2>&1 && spacetime publish "$DB" --server local --delete-data --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "it builds and publishes"
sleep 2
check "$(spacetime sql "$DB" "SELECT * FROM session" 2>/dev/null | grep -q '|' && echo true || echo false)" \
  "the foundation's tables are there (a session)"
run_genre_hooks genres_absent   # each of the game's genres: none of its tables or reducers

echo "== the game again =="
unset UMF_GAME
(cd server && cargo check --target wasm32-unknown-unknown >/dev/null 2>&1 && spacetime build >/dev/null 2>&1 \
  && spacetime publish "$DB" --server local --delete-data --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "the real game builds and publishes again"
run_genre_hooks genres_present   # and each genre is back

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
