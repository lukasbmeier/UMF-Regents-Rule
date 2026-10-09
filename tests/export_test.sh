#!/usr/bin/env bash
# THE BUILDS, EXPORTED AND RUN. Exports both presets in export_presets.cfg, checks what each pack
# actually contains, then runs them: the client against the live module, and the server as a real
# sidecar through the whole of tests/sidecar_test.sh.
#
#   GODOT=/path/to/godot ./tests/export_test.sh
#
# Needs the Windows export templates for this Godot version, a local server (`spacetime start`),
# and Python. sidecar_test.sh republishes the TEST database (umf-test) with --delete-data. Builds go to build/
# (gitignored).
#
# Why a layer of its own: an export is a different program from the project. Files are filtered
# in and out by patterns, resources are converted, a feature tag picks a different main scene —
# and every other suite runs from source, where none of that happens. The failures this catches
# are silent everywhere else: a server script in the client a player downloads (hard rule 7b),
# a JSON file the game reads at runtime left out because it is not a "resource", a server build
# that boots the fishing game instead of the sidecar.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/genre_hooks.sh
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `<database>-test` (shared/game.json), never on the
# database a person plays in. UMF_DB reaches every Godot process started from here.
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-python}"

passes=0
failures=0
pass() { passes=$((passes + 1)); }
fail() { failures=$((failures + 1)); echo "  FAIL: $1" >&2; }
check() { if [ "$1" = "true" ]; then pass; else fail "$2"; fi }

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

client_pid=""
client_log="$(mktemp)"
cleanup() {
  [ -n "$client_pid" ] && kill "$client_pid" 2>/dev/null
  rm -f "$client_log"
}
trap cleanup EXIT

echo "== export =="
rm -rf build/client build/server
mkdir -p build/client build/server
for preset in "Windows Client:build/client/umf.exe" "Windows Server:build/server/umf_server.exe"; do
  name="${preset%%:*}"; out="${preset#*:}"
  if "$GODOT" --headless --path . --export-release "$name" "$out" >/dev/null 2>&1 && [ -f "$out" ]; then
    pass; echo "   $name -> $out"
  else
    fail "the '$name' preset exports (is the export template for this Godot version installed?)"
  fi
done
[ "$failures" -eq 0 ] || { echo "export: $passes passed, $failures failed"; exit 1; }

files_of() { "$PYTHON" tools/pck_list.py "$1" 2>/dev/null; }
count() { files_of "$1" | grep -cE "$2"; }

echo "== what the CLIENT carries =="
# THE PACK IS IN THE EXE (DECISIONS #185): no umf.pck beside umf.exe (only Terrain3D's native library,
# which Godot loads from disk), and the pack is read out of the executable itself.
check "$([ ! -f build/client/umf.pck ] && echo true || echo false)" "the client's pack is inside umf.exe: no umf.pck beside it"
CPCK=build/client/umf.exe
# Hard rule 7b: authority logic ships only to the people who run a server. A brain or a hit rule
# in the client is readable by every player and is exactly what the rule exists to prevent.
check "$([ "$(count $CPCK '^sidecar/')" = "0" ] && echo true || echo false)" \
  "no sidecar/ file is in the client ($(count $CPCK '^sidecar/') found)"
check "$([ "$(count $CPCK '^(tests/(test_runner|suite_base|suites/|e2e/|playtest/|render/|fight_bot)|game/[a-z_]+/tests/|tools/)')" = "0" ] && echo true || echo false)" \
  "nor test code or tools"
# THE LEVEL LIVES UNDER tests/levels/ — the game and the sidecar both load it — so "leave the tests
# out" must not mean "leave the level out". The first version of these presets did exactly that,
# and both builds died loading their main scene. Only an export can show it: from source the file
# is always there.
check "$([ "$(count $CPCK '^tests/levels/greybox\.tscn')" -ge 1 ] && echo true || echo false)" \
  "but the level the game is played in IS"
check "$([ "$(count $CPCK '^shared/golden/')" = "0" ] && echo true || echo false)" \
  "nor the golden vectors"
# Read by the movement model at runtime. Godot 4 counts .json as a resource, so "all resources"
# carries it with no include filter; what this guards against is an exclude pattern (`shared/*`,
# `*.json` — both look like tidying) quietly taking it out of every client.
check "$([ "$(count $CPCK '^shared/movement_config\.json$')" = "1" ] && echo true || echo false)" \
  "the movement tunables the client reads at runtime ARE in it"
run_genre_hooks export_client   # what a genre's client must carry (fishing: its sounds, lakeside, content)

# EDITOR TOOLING STAYS IN THE EDITOR (REVIEW 0.23.1 B4): the MCP bridge (it can run code it is
# sent), the export plugin that keeps its autoload out, and Terrain3D's demo scene, in neither build.
for PK in build/client/umf.exe build/server/umf_server.pck; do
  check "$([ "$(count $PK '^addons/(godot_ai|umf_export)/')" = "0" ] && [ "$(count $PK '^demo/')" = "0" ] && echo true || echo false)" \
    "no editor tooling in $PK (godot_ai $(count $PK '^addons/godot_ai/'), umf_export $(count $PK '^addons/umf_export/'), demo $(count $PK '^demo/'))"
done

echo "== what the SERVER carries =="
SPCK=build/server/umf_server.pck
check "$([ "$(count $SPCK '^sidecar/sidecar_main\.tscn')" -ge 1 ] && echo true || echo false)" \
  "the sidecar is in the server build"
check "$([ "$(count $SPCK '^sidecar/npc/')" -ge 1 ] && echo true || echo false)" \
  "with its NPC brains"
check "$([ "$(count $SPCK '^tests/levels/greybox\.tscn')" -ge 1 ] && echo true || echo false)" \
  "and the level it resolves movement against — the same one its players load"
check "$([ "$(count $SPCK '^shared/movement_config\.json$')" = "1" ] && echo true || echo false)" \
  "and the same movement tunables, or it would simulate different physics from its players"
check "$([ -f build/server/umf_server.console.exe ] && echo true || echo false)" \
  "a console wrapper exists, so a host can see its log"

echo "== run the exported CLIENT =="
# Headless: no connect screen (nobody to ask), so it connects to the shipped default server —
# the local one. A token of its own keeps it from sharing an identity with anyone.
build/client/umf.exe --headless -- --token=exporttest --name=Exported >"$client_log" 2>&1 &
client_pid=$!
ready=""
for _ in $(seq 1 60); do
  if grep -q "\[Boot\] world ready" "$client_log" && grep -q "\[Boot\] local entity:" "$client_log"; then
    ready=yes; break
  fi
  sleep 0.5
done
# Judge the log as it stood WHILE RUNNING. Godot 4.7.1's shutdown path prints a batch of
# "BUG: Unreferenced static string" engine reports when the process is asked to exit, which have
# nothing to do with this game; taking the log before the kill keeps every real error in scope
# without filtering out any message.
sleep 3
running_log="$(cat "$client_log")"
kill "$client_pid" 2>/dev/null; wait "$client_pid" 2>/dev/null; client_pid=""
check "$([ -n "$ready" ] && echo true || echo false)" \
  "the exported client connects, subscribes and is handed its player"
check "$(grep -q 'view: looking through' "$client_log" && echo true || echo false)" \
  "and is looking through a camera: its scenes, scripts and bindings all loaded"
# ANY error, not just script errors. A build missing a runtime file does not crash: the movement
# model reports "cannot read" and carries on with its defaults — a client that plays, with nothing
# but this line to say it is not playing the server's numbers.
if printf '%s\n' "$running_log" | grep -E "^(ERROR|SCRIPT ERROR)" >/dev/null; then
  fail "the exported client logged errors while running"
  printf '%s\n' "$running_log" | grep -E "^(ERROR|SCRIPT ERROR)" | head -5 >&2
else
  pass
fi
[ -n "$ready" ] || { echo "--- client log ---" >&2; tail -30 "$client_log" >&2; }

echo "== run the exported SERVER as a sidecar =="
# The whole sidecar suite, pointed at the exported binary: it must boot the sidecar (the
# `dedicated_server` feature picks its main scene), simulate, drive an NPC, and resume that NPC's
# brain after a restart.
if SIDECAR_BIN=build/server/umf_server.console.exe SIDECAR_ARGS=--headless GODOT="$GODOT" \
    ./tests/sidecar_test.sh > build/server_run.log 2>&1; then
  pass
else
  fail "the exported server passes tests/sidecar_test.sh (see build/server_run.log)"
fi
grep -E "^==|sidecar:|FAIL|run:" build/server_run.log | sed 's/^/   /'

echo
echo "export: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
