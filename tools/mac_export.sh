#!/usr/bin/env bash
# EXPORT THE MAC CLIENT (the "macOS Client" preset: a universal app, Intel and Apple Silicon, signed
# ad hoc), as this game's own app: its bundle identifier, `com.umf.` and shared/game.json's title
# (`com.umf.fowl-play`), is put in the shared preset for the length of the export and taken out again,
# so the preset stays the template's. Godot writes an app's Info.plist before any export plugin runs,
# and changing it after would break its signature: this is the one place to say it.
#
#   GODOT=<path> ./tools/mac_export.sh [out.zip]        (default build/mac/umf.zip)
#
# Needs the macOS export template for this Godot version (Editor > Manage Export Templates).
# Opening it on the Mac the first time (it is signed ad hoc, not by a developer ID): System Settings >
# Privacy & Security > Open Anyway, or `xattr -dr com.apple.quarantine "<the app>"` (docs/HANDBOOK.md).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-python}"
OUT="${1:-build/mac/umf.zip}"
BUNDLE="$("$PYTHON" tools/mac_bundle.py --bundle-id shared/game.json | tr -d '\r')"
cp export_presets.cfg export_presets.cfg.mac_export_hold
trap 'mv -f export_presets.cfg.mac_export_hold export_presets.cfg' EXIT
"$PYTHON" - "$BUNDLE" <<'PY'
import re, sys
p = "export_presets.cfg"
s = open(p, encoding="utf-8", newline="").read()
head, sep, rest = s.partition('name="macOS Client"')
if not sep:
    sys.exit("no 'macOS Client' preset in export_presets.cfg")
rest = re.sub(r'application/bundle_identifier="[^"]*"', 'application/bundle_identifier="%s"' % sys.argv[1], rest, count=1)
open(p, "w", encoding="utf-8", newline="").write(head + sep + rest)
PY
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
"$GODOT" --headless --path . --export-release "macOS Client" "$OUT" >/dev/null 2>&1 || true
[ -f "$OUT" ] || { echo "the macOS export made nothing (is the macOS export template for this Godot version installed?)" >&2; exit 1; }
echo "mac: $OUT ($BUNDLE)"
