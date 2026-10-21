#!/usr/bin/env bash
# PUBLISH THE SERVER, AND BRING THE CLIENT IN STEP — one command for "I changed the server or its
# data" (DECISIONS #154). Run it after editing anything under server/, or a file the server
# compiles in: shared/rules.json, shared/movement_config.json, shared/fishing/*.json,
# shared/world/*.json.
#
#   ./tools/publish.sh                     build and publish to the game's database (shared/game.json
#                                          `database`; Fishing's is umf), keeping its data
#   ./tools/publish.sh --fresh             ...wiping its data first: needed when a table changed
#                                          shape (a column added, renamed or retyped)
#   GODOT=<path> ./tools/publish.sh --codegen
#                                          ...and regenerate the client's bindings, for when a
#                                          table or a reducer's arguments changed. Without it the
#                                          client silently ignores the new table. Close the editor
#                                          first, or let it reload the generated scripts.
#   DB=umf-test ./tools/publish.sh         another database (the test suites use umf-test). Not
#                                          with --codegen: the bindings are generated from the
#                                          schema of `umf` (the module's name), whatever DB says
#
# Needs `spacetime start` running (127.0.0.1:3000) and the wasm32 target (`rustup target add
# wasm32-unknown-unknown`). Then restart the game: a running client keeps the old rules.
set -uo pipefail
cd "$(dirname "$0")/.."
# This machine's settings, when not run through tools\run.cmd (tools/local.env.example).
if [ -z "${GODOT:-}" ] && [ -f tools/local.env ]; then set -a; eval "$(tr -d '\r' < tools/local.env)"; set +a; fi
GAME_DB="$(python -c "import json; print(json.load(open('shared/game.json')).get('database', 'umf'))" | tr -d '\r')"
DB="${DB:-$GAME_DB}"
GODOT="${GODOT:-godot}"
fresh=0
codegen=0
for arg in "$@"; do
  case "$arg" in
    --fresh) fresh=1 ;;
    --codegen) codegen=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

if [ $codegen -eq 1 ] && [ "$DB" != "$GAME_DB" ]; then
  echo "--codegen reads the schema from the game's database ($GAME_DB, shared/game.json), not $DB: the" >&2
  echo "bindings would come out of whatever $GAME_DB has. Publish $GAME_DB with --codegen instead." >&2
  exit 2
fi

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== bake the content =="
# The .tres content to shared/content/ (DECISIONS #199): build.rs refuses a stale bake, so publishing
# bakes first. Without Godot, the build still says whether the bake is current.
if command -v "$GODOT" >/dev/null 2>&1 || [ -x "$GODOT" ]; then
  bake_out="$("$GODOT" --headless --path . -s res://tools/bake_content.gd 2>&1)"
  bake_status=$?
  printf '%s\n' "$bake_out" | grep -E "^ |baked|refused" || true
  [ $bake_status -eq 0 ] || { echo "the bake refused the content above: fix what it names, then publish" >&2; exit 1; }
else
  echo "(Godot not found, so the content is not baked here; the build checks the bake is current)"
fi

echo "== build =="
(cd server && spacetime build) || { echo "the build failed: see the errors above" >&2; exit 1; }

echo "== publish to $DB$([ $fresh -eq 1 ] && echo ', wiping its data') =="
if [ $fresh -eq 1 ]; then
  (cd server && spacetime publish "$DB" --server local --delete-data --yes)
else
  (cd server && spacetime publish "$DB" --server local --yes)
fi
status=$?
if [ $status -ne 0 ]; then
  echo "publish failed. If it says the schema changed in a way that needs a migration, a table" >&2
  echo "changed shape: run again with --fresh (it wipes $DB's data)." >&2
  exit 1
fi

if [ $codegen -eq 1 ]; then
  echo "== regenerate the client's bindings =="
  # The config step replaces the editor dock; the second --import registers the generated
  # class_names, without which the SpacetimeDB autoload fails to parse (AGENTS.md, Verify loop).
  "$GODOT" --headless --path . -s tools/codegen_config.gd >/dev/null 2>&1 &&
  "$GODOT" --headless --path . --import >/dev/null 2>&1 &&
  "$GODOT" --headless --path . --script res://addons/SpacetimeDB/cli.gd &&
  "$GODOT" --headless --path . --import >/dev/null 2>&1 &&
  "$GODOT" --headless --path . -s res://tools/write_schema_fingerprint.gd \
    || { echo "codegen failed (is GODOT set to the Godot 4.7 executable?)" >&2; exit 1; }
  # The fingerprint is what a client compares with a server's before connecting (DECISIONS #164):
  # export the game again after this, or friends' builds are refused by this server.
  echo "bindings regenerated in spacetime_bindings/ (export again: older builds will be refused)"
else
  echo "(bindings not regenerated: add --codegen if a table or a reducer's arguments changed)"
fi
# THE EDITOR IS AN ADMIN of the game's own database on this machine (DECISIONS #272): each identity an
# editor instance plays as, so pressing Play starts the world's referee (RefereeLauncher).
if [ "$DB" = "$GAME_DB" ]; then
  for ident in $(python tools/editor_admins.py 2>/dev/null | tr -d ''); do
    if spacetime call "$DB" register_authority "$ident" 0 0 >/dev/null 2>&1; then
      echo "the editor's identity ${ident:0:12}... is an admin of $DB (Play starts its referee)"
    fi
  done
fi
echo "done: $DB is up to date. Restart the game to pick it up."
