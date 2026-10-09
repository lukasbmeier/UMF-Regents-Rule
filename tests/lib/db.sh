# THE TEST DATABASE (DECISIONS #154, #195): every suite publishes and plays on "<game's database>-test",
# never on the database a person plays in (shared/game.json `database`; Fishing's is `umf`). Source
# this from a suite after it has cd'd to the repo root: it sets $DB (unless DB is already set) and
# exports UMF_DB, which every Godot process started from the suite joins.
GAME_DB="$(python -c "import json; print(json.load(open('shared/game.json')).get('database', 'umf'))" | tr -d '\r')"
DB="${DB:-$GAME_DB-test}"
export UMF_DB="$DB"
