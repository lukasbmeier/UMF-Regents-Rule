# FISHING'S CHECKS IN tests/multiclient_test.sh (sourced there by run_genre_hooks: $log_a, $log_b,
# check). The board is fishing's standings; the ponds are the greybox's fishing spots.

echo "== the leaderboard =="
# The board prints each time it changes; the LAST line is what each player was looking at. B's
# score came from the server, so A can only show it if B's session row reached A's copy of B.
# The CLI connections above are players too (offline, no score) and must not be on it.
board_a="$(grep -o '\[Board\] .*' "$log_a" | tail -1 | tr -d '\r')"
board_b="$(grep -o '\[Board\] .*' "$log_b" | tail -1 | tr -d '\r')"
echo "  A shows: ${board_a:-nothing}"
echo "  B shows: ${board_b:-nothing}"
check "$board_a" "[Board] 1. Bram the Bold 30  2. Ailsa 0" "A ranks B first on B's server-side score, by name"
check "$board_b" "[Board] 1. Bram the Bold 30  2. Ailsa 0" "B's board agrees with A's"

echo "== the seeded pond reaches the clients =="
check "$(grep -c 'entity spawned: [0-9]* kind 2' "$log_a")" "3" "A spawned the three seeded fishing spots"
check "$(grep -c 'entity spawned: [0-9]* kind 2' "$log_b")" "3" "B spawned the three seeded fishing spots"

