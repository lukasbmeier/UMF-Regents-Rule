#!/usr/bin/env bash
# THE RULES AN ADMIN SET ON THIS GAME'S SERVER (DECISIONS #201): every `hot_rule` row with
# `overridden`, as `spacetime sql` prints it. The Content dock's "Keep live tuning" runs this and
# writes the values into the rule sets; run it by hand to see what is live.
#
#   ./tools/rules_live.sh            (DB=<name> for another database)
set -uo pipefail
cd "$(dirname "$0")/.."
GAME_DB="$(python -c "import json; print(json.load(open('shared/game.json')).get('database', 'umf'))" | tr -d '\r')"
DB="${DB:-$GAME_DB}"
echo "database: $DB"
spacetime sql "$DB" "SELECT key, number, text FROM hot_rule WHERE overridden = true" 2>&1 | grep -v "UNSTABLE"
