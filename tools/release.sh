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
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-python}"

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
