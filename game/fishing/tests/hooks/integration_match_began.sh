# FISHING'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, sql_first...). Moved verbatim (the template split).

assert_eq "$(sql_first 'SELECT time_of_day FROM fishing_conditions WHERE world_id = 0' 1)" "0" "a new match starts at dawn"
