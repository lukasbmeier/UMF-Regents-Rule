#!/usr/bin/env bash
# THE LOOK, RENDERED. Checks that need pixels, so they open a (small) window — every other layer
# is headless and the headless renderer draws nothing (DECISIONS #141).
#
#   GODOT=<path> ./tests/render_test.sh
#
# The foundation's: F11 really makes the game fullscreen and back (#148) — the window flashes to
# full screen for a moment while that runs. A genre's own run after it (fishing's: the foliage lit
# from both sides #141 #146, the lake's depth #150, the grip pictures #157).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# On the defaults, not the player's settings: a saved fullscreen would change every picture.
export UMF_SETTINGS=none
failed=0
. tests/lib/genre_hooks.sh
# The foundation's (tests/render/) and each listed genre's (game/<genre>/tests/render/).
scenes=""
for f in tests/render/*_test.tscn; do scenes="$scenes res://$f"; done
for g in $(genres_listed); do
  for f in game/$g/tests/render/*_test.tscn; do [ -f "$f" ] && scenes="$scenes res://$f"; done
done
for scene in $scenes; do
  out="$(mktemp)"
  "$GODOT" --path . --resolution 320x240 "$scene" 2>&1 | tee "$out"
  code=${PIPESTATUS[0]}
  if [ "$code" -ne 0 ] || grep -q "RENDER FAIL" "$out" || ! grep -q "RENDER PASS:" "$out"; then
    echo "render_test: $scene FAILED"
    failed=1
  fi
  rm -f "$out"
done
if [ "$failed" -ne 0 ]; then
  echo "render_test: FAILED"
  exit 1
fi
echo "render_test: ok"
