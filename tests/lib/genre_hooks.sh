# A GENRE'S CHECKS IN A FOUNDATION SUITE. Source this, then call `run_genre_hooks <point>` where a
# genre may add its own: for every genre shared/game.json lists, `game/<genre>/tests/hooks/<point>.sh`
# is SOURCED there, so it sees the suite's variables (its logs, $DB) and helpers (check, assert_ok...).
# The foundation's suites name no genre; the template, which has none, runs them as they are.
genres_listed() {
  python -c "import json; print(' '.join(json.load(open('shared/game.json')).get('genres', [])))" | tr -d '\r'
}
run_genre_hooks() {
  local g
  for g in $(genres_listed); do
    if [ -f "game/$g/tests/hooks/$1.sh" ]; then
      echo "== $g: $1 =="
      # shellcheck disable=SC1090
      . "game/$g/tests/hooks/$1.sh"
    fi
  done
}
