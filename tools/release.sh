#!/usr/bin/env bash
# MAKE A BUILD TO SEND TO FRIENDS (DECISIONS #198). Exports and tests the builds (Windows, and the Mac app)
# (tests/export_test.sh, which also plays this build against a newer server), saves this build's
# contract as a release snapshot (shared/compat/<database>/<fingerprint>.json: commit it), and zips
# the client to build/releases/<title>-<fingerprint>.zip, ready to send.
#
#   tools\release.cmd          (Windows: double-click it)
#   GODOT=<path> ./tools/release.sh
#
# From then on, the unit suite fails if a change would stop this build playing on the server:
# that is what keeps friends from having to re-download for every server fix.
#
# A DEBUG BUILD, for hunting a crash (DECISIONS #307):
#   tools\release.cmd --debug
# The Windows client on Godot's DEBUG export template, zipped to build/releases/<title>-<fingerprint>-debug.zip.
# The official RELEASE template has no crash handler: a native crash (a freed object read, say) ends the game
# with nothing in its log. The debug template checks those as it runs and turns them into a SCRIPT ERROR
# with the script, line and backtrace, and the game carries on; every warning names its line too. It runs
# slower (the script checks), so it is for play while a crash is being hunted, never the default build.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-python}"

if [ "${1:-}" = "--debug" ]; then
  echo "== export the Windows client on the debug template =="
  rm -rf build/client-debug
  mkdir -p build/client-debug
  "$GODOT" --headless --path . --export-debug "Windows Client" build/client-debug/umf.exe > build/client-debug-export.log 2>&1 \
    && [ -f build/client-debug/umf.exe ] \
    || { echo "release: the debug export failed (build/client-debug-export.log; the debug export template installed?)" >&2; exit 1; }
  # The debug template is the one with the crash handler and the script checks (the release one has neither).
  grep -a -q "Dumping the backtrace" build/client-debug/umf.exe \
    || { echo "release: build/client-debug/umf.exe is not Godot's debug template" >&2; exit 1; }
  # Every GDExtension's DEBUG library beside it (a debug export loads the `windows.debug` one).
  for ext in $(grep -rl "^windows.debug.x86_64" --include=*.gdextension addons 2>/dev/null | grep -v "addons/godot_ai/"); do
    lib="$(sed -n 's/^windows.debug.x86_64 *= *"\(.*\)".*/\1/p' "$ext" | head -1 | tr -d '\r')"; lib="${lib##*/}"
    [ -f "build/client-debug/$lib" ] || { echo "release: $ext's debug library ($lib) is not beside the build" >&2; exit 1; }
  done
  # It starts: the libraries load, every script compiles, the genres come up (no server needed: it is pointed
  # at a closed port and stopped).
  smoke="$(UMF_SETTINGS=none timeout 60 build/client-debug/umf.exe --headless --quit-after 600 -- \
    --host=127.0.0.1:1 --token=debugbuild --connect-timeout=3 2>&1 || true)"
  if ! printf '%s\n' "$smoke" | grep -q "\[Boot\] genres:" || printf '%s\n' "$smoke" | grep -qE "^(SCRIPT ERROR|ERROR)"; then
    printf '%s\n' "$smoke" | tail -20 >&2
    echo "release: the debug build did not start cleanly" >&2; exit 1
  fi
  echo "== record this build's contract =="
  "$GODOT" --headless --path . -s res://tools/compat_snapshot.gd | grep "compat snapshot"
  FP="$("$PYTHON" -c "import json; print(json.load(open('spacetime_bindings/schema_fingerprint.json'))['fingerprint'])" | tr -d '\r')"
  TITLE="$("$PYTHON" -c "import json; print(json.load(open('shared/game.json')).get('title', 'game'))" | tr -d '\r')"
  mkdir -p build/releases
  ZIP="build/releases/${TITLE// /_}-$FP-debug.zip"
  "$PYTHON" - "$ZIP" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk("build/client-debug"):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, "build/client-debug"))
PY
  echo
  echo "release: $ZIP (Windows, DEBUG: slower; a crash becomes a SCRIPT ERROR naming its line in godot.log)"
  echo "Send it to whoever is playing while the crash is hunted. Then commit shared/compat/ (the snapshot)."
  exit 0
fi

echo "== export and test both builds =="
GODOT="$GODOT" ./tests/export_test.sh

echo "== record this build's contract =="
"$GODOT" --headless --path . -s res://tools/compat_snapshot.gd | grep "compat snapshot"

FP="$("$PYTHON" -c "import json; print(json.load(open('spacetime_bindings/schema_fingerprint.json'))['fingerprint'])" | tr -d '\r')"
TITLE="$("$PYTHON" -c "import json; print(json.load(open('shared/game.json')).get('title', 'game'))" | tr -d '\r')"
mkdir -p build/releases
ZIP="build/releases/${TITLE// /_}-$FP.zip"
"$PYTHON" - "$ZIP" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk("build/client"):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, "build/client"))
PY
# The Mac app (tests/export_test.sh exported it: a universal app, signed ad hoc): its zip as Godot wrote it.
MACZIP="build/releases/${TITLE// /_}-$FP-mac.zip"
cp build/mac/umf.zip "$MACZIP"
echo
echo "release: $ZIP (Windows)"
echo "         $MACZIP (Mac: unzip; the first time, System Settings > Privacy & Security > Open Anyway: docs/HANDBOOK.md)"
echo "Send those. Then commit shared/compat/ (the snapshot), so later changes are held to this build."
