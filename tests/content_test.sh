#!/usr/bin/env bash
# A STALE BAKE STOPS THE BUILD (DECISIONS #199). Content is edited as .tres resources and baked to
# shared/content/ (tools/bake_content.gd); server/build.rs checks the bake's manifest. This builds
# the server (native cargo check: build.rs runs for any target) against a COPY of the content
# (UMF_CONTENT_ROOT), unchanged and then broken each way a person can break it: a .tres edited and
# not baked, a new .tres never baked, a baked file edited by hand. Each must stop the build and name
# the file. The repo's own files are never touched. Needs no server and no Godot.
#
#   ./tests/content_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
passes=0; failures=0
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
check() { if [ "$1" = "true" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $2" >&2; fi }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fresh_copy() {
  rm -rf "$work/root"
  mkdir -p "$work/root/shared"
  cp -r foundation "$work/root/foundation"
  cp -r shared/content "$work/root/shared/content"
  "$PYTHON" -c "import json; g=json.load(open('shared/game.json'))['genres']; print('\n'.join(g))" | tr -d '\r' | while read -r g; do
    [ -n "$g" ] && [ -d "game/$g/content" ] && mkdir -p "$work/root/game/$g" && cp -r "game/$g/content" "$work/root/game/$g/content"
  done
}
# A Windows path where there is one (pwd -W): build.rs is a native program.
build() { (cd server && UMF_CONTENT_ROOT="$(cd "$work/root" && (pwd -W 2>/dev/null || pwd))" cargo check 2>&1); }
first_tres() { find "$work/root/foundation/content" -name '*.tres' | sort | head -1; }

echo "== the bake as committed =="
fresh_copy
out="$(build)"
check "$(echo "$out" | grep -q 'Finished' && echo true || echo false)" "the server builds against the content as baked"

echo "== a .tres edited, not baked =="
fresh_copy
t="$(first_tres)"
printf '\n' >> "$t"
out="$(build)"
check "$(echo "$out" | grep -q 'changed since the last bake' && echo "$out" | grep -q "$(basename "$t")" && echo true || echo false)" \
  "the build stops, naming $(basename "$t")"

echo "== a new .tres, never baked =="
fresh_copy
cp "$(first_tres)" "$work/root/foundation/content/brand_new.tres"
out="$(build)"
check "$(echo "$out" | grep -q 'brand_new.tres is content that was never baked' && echo true || echo false)" \
  "the build stops, naming brand_new.tres"

echo "== a baked file edited by hand =="
fresh_copy
j="$(find "$work/root/shared/content" -name '*.json' ! -name manifest.json | sort | head -1)"
sed -i 's/"damage": [0-9.]*/"damage": 9999.0/' "$j"
out="$(build)"
check "$(echo "$out" | grep -q 'was edited by hand' && echo true || echo false)" \
  "the build stops, naming $(basename "$j")"

echo "== the real tree again =="
out="$(cd server && cargo check 2>&1)"
check "$(echo "$out" | grep -q 'Finished' && echo true || echo false)" "the server builds from the repo's own content"

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
