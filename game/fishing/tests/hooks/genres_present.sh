# FISHING'S PART OF tests/genres_test.sh, sourced there by run_genre_hooks (it sees the suite's helpers).

check "$(spacetime sql "$DB" "SELECT * FROM fishing_world" 2>/dev/null | grep -q '|' && echo true || echo false)" \
  "with fishing in it (the lakeside is set up)"
