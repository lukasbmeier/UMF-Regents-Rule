# FISHING'S PART OF tests/genres_test.sh, sourced there by run_genre_hooks (it sees the suite's helpers).

check "$(echo "$out" | grep -q 'fishing_claims_only_its_own' && echo false || echo true)" "fishing's own tests are not compiled in"
# Captured first: under pipefail, the refusal's own exit status would sink the grep that found it.
no_table="$(spacetime sql "$DB" "SELECT * FROM catch" 2>&1)"
check "$(echo "$no_table" | grep -qi 'no such table' && echo true || echo false)" \
  "and fishing's are not (no catch table)"
no_reducer="$(spacetime call "$DB" cast '{"x":0.0,"y":0.0,"z":0.0}' 2>&1)"
check "$(echo "$no_reducer" | grep -qi 'no such reducer\|not found\|reducers not shown' && echo true || echo false)" \
  "nor its reducers (no cast: \"$(echo "$no_reducer" | grep -i error | head -1)\")"

