#!/usr/bin/env bash
# Runs the Godot headless suite and the architecture lint.
#   GODOT=/path/to/godot ./tests/run_tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# The player's own settings (fullscreen, sensitivity, key bindings) stay out of the tests: every
# process here runs on the defaults and saves nothing (DECISIONS #165).
export UMF_SETTINGS=none

# Match PATTERN against CODE only. Everything from the first '#' on a line is stripped before
# matching, so a doc comment may name the SDK (net_config.gd explains the alias convention)
# while an actual reference still fails the build.
lint_code() {
  local pattern="$1"; shift
  grep -rnE "$pattern" "$@" 2>/dev/null \
    | awk -v pat="$pattern" '
        { rest = $0
          sub(/^[^:]*:[0-9]+:/, "", rest)   # drop the file:line prefix grep added
          sub(/#.*/, "", rest)              # drop the comment
          if (rest ~ pat) print $0 }'
}

echo "== architecture lint: SDK references outside spacetime_sync.gd =="
# Any script other than the adapter that names an SDK type or the SDK autoload is a violation.
if lint_code 'SpacetimeDB[A-Za-z]*|/root/SpacetimeDB|addons/SpacetimeDB|spacetime_bindings' \
     foundation sidecar game tests --include='*.gd' | grep -v 'foundation/net/spacetime_sync.gd'; then
  echo "VIOLATION: SDK referenced outside the adapter." >&2
  exit 1
fi
echo "ok"

echo "== architecture lint: no @rpc / MultiplayerSynchronizer =="
if lint_code '@rpc|MultiplayerSynchronizer|MultiplayerSpawner|rpc[(]' foundation --include='*.gd'; then
  echo "VIOLATION: Godot high-level multiplayer is not used in this project." >&2
  exit 1
fi
echo "ok"

echo "== architecture lint: every quit goes through AppExit =="
# A process that quits the moment a sound stops leaves the audio server's mixer holding it: about
# half the time the run ends "1 resources still in use" (DECISIONS #151). AppExit stops the
# sounds and waits for the mixer first, so it is the only thing that may call SceneTree.quit().
if lint_code '[.]quit[(]' foundation game sidecar tests --include='*.gd'      | grep -v '^foundation/core/app_exit.gd' | grep -v 'AppExit[.]quit[(]'; then
  echo "VIOLATION: quit() called directly; use AppExit.quit(get_tree(), code)." >&2
  exit 1
fi
echo "ok"

echo "== lint: test suites keep off the database people play in =="
# Every server suite republishes its database with --delete-data. On `umf` that wiped the world
# its owner was playing in (DECISIONS #154): suites source tests/lib/db.sh ("$DB", the game's
# database + "-test", exported as UMF_DB to every Godot process) and never name the play database.
PLAY_DB="$(python -c "import json; print(json.load(open('shared/game.json')).get('database', 'umf'))" | tr -d '\r')"
bad=""
for f in tests/*.sh; do
  if grep -qE 'spacetime (publish|call|sql|logs|delete)' "$f"; then
    grep -q '^\. tests/lib/db\.sh' "$f" || bad="$bad $f"
    if grep -nE "spacetime (publish|call|sql|logs|delete)( --[a-z]+)* $PLAY_DB(\$|[^-_a-z0-9])" "$f"; then bad="$bad $f"; fi
  fi
done
if [ -n "$bad" ]; then
  echo "VIOLATION: these suites can reach the play database:$bad (source tests/lib/db.sh and use \"\$DB\")." >&2
  exit 1
fi
echo "ok"

echo "== architecture lint: authority code stays under sidecar/ =="
if lint_code 'res://sidecar' foundation game tests --include='*.gd' --include='*.tscn' \
     | grep -v '^foundation/boot.gd' | grep -v '^foundation/net/referee_launcher.gd:[0-9]*:const SIDECAR_SCENE'; then
  # Excepted: boot.gd's dedicated-server branch, and the one constant RefereeLauncher starts as a
  # separate process in an editor run (DECISIONS #226): neither uses the sidecar's code.
  echo "VIOLATION: res://sidecar referenced outside sidecar/ (boot.gd branch and RefereeLauncher.SIDECAR_SCENE excepted)." >&2
  exit 1
fi
echo "ok"

# The foundation reads generated rows through MovementState.from_row(), which assumes the
# module's wire struct maps onto Godot's built-in Vector3. It only does so because the Rust
# struct is literally named `Vector3` (DECISIONS #40) — rename it and codegen silently emits a
# bespoke Resource instead, breaking every positional read at runtime. This check lives here
# rather than in a .gd test because naming the bindings path from tests/ trips the SDK lint.
# EVERY TABLE A SHIPPED NetConfig SUBSCRIBES TO EXISTS IN THE MODULE. A table dropped from the
# module but left in a config is refused at the server as "no such table", and the whole core
# subscription with it: the sidecar ran blind for a day on `fish_def`, and nothing but the one
# suite that runs a sidecar noticed. The generated bindings are the module's table list.
if [ -d spacetime_bindings/schema/tables ]; then
  echo "== binding contract: every subscribed table exists in the module =="
  missing=""
  for cfg in $(grep -rl 'script_class="NetConfig"' --include='*.tres' foundation game sidecar tests 2>/dev/null); do
    for t in $(grep -oE 'core_tables = Array\[StringName\]\(\[[^]]*\]' "$cfg" | grep -oE '&"[a-z_]+"' | tr -d '&"'); do
      [ -f "spacetime_bindings/schema/tables/umf_${t}_table.gd" ] || missing="$missing $cfg:$t"
    done
  done
  # A genre's own tables (its genre.tres, DECISIONS #173) are subscribed too.
  for mod in $(grep -rl 'script_class="GenreModule"' --include='*.tres' game 2>/dev/null); do
    for t in $(grep -oE '^tables = Array\[StringName\]\(\[[^]]*\]' "$mod" | grep -oE '&"[a-z_]+"' | tr -d '&"'); do
      [ -f "spacetime_bindings/schema/tables/umf_${t}_table.gd" ] || missing="$missing $mod:$t"
    done
  done
  if [ -n "$missing" ]; then
    echo "VIOLATION: subscribed to tables the module does not have:$missing" >&2
    exit 1
  fi
  echo "ok"
fi

BINDINGS="spacetime_bindings/schema/types/umf_movement_state_row.gd"
if [ -f "$BINDINGS" ]; then
  echo "== binding contract: movement_state pos/vel are native Vector3 =="
  for field in pos vel; do
    if ! grep -q "@export var ${field}: Vector3" "$BINDINGS"; then
      echo "VIOLATION: generated ${field} is not a Godot Vector3. Is the Rust struct still named Vector3?" >&2
      grep -E "@export var (pos|vel):" "$BINDINGS" >&2
      exit 1
    fi
  done
  grep -q "&\"server_ts\": &\"i64\"" "$BINDINGS" || {
    echo "VIOLATION: server_ts is no longer i64 microseconds; interpolation timing depends on it." >&2
    exit 1
  }
  echo "ok"
fi

echo "== godot headless tests =="
# Capture the run: a GDScript runtime error prints to stderr and does NOT fail a _check, so
# without this a script error could silently truncate a suite and still exit 0. That happened
# once already (a fake entity missing `body` cut 19 checks out of the movement suite).
out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT
set +e
"$GODOT" --headless --path . res://tests/test_runner.tscn 2>&1 | tee "$out_file"
godot_status=${PIPESTATUS[0]}
set -e
[ "$godot_status" -eq 0 ] || { echo "VIOLATION: test runner exited $godot_status." >&2; exit 1; }

# Errors the suites raise ON PURPOSE. Each entry must name the test that provokes it.
#   - unknown entity.kind : EntitySpawner test asserts an unregistered kind is refused
#   - AnimationSet is missing : the animation suite asserts an incomplete set is refused
#   - InterestManager: subscription : the interest suite asserts a refused subscription is loud
#   - Genres: ... no_such_genre : the genres suite asserts a genre with no genre.tres is reported
expected_errors='no EntityDefinition registered for entity.kind 77|AnimationTreeBuilder: AnimationSet is missing|InterestManager: subscription|Genres: shared/game.json names .no_such_genre.'

echo "== unexpected engine/script errors =="
if grep -E "SCRIPT ERROR|^ERROR:" "$out_file" | grep -vE "$expected_errors"; then
  echo "VIOLATION: the run produced errors that no test expects (listed above)." >&2
  exit 1
fi
echo "ok"
