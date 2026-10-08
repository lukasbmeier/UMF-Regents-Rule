#!/usr/bin/env bash
# THE LOOK, RENDERED. Checks that need pixels, so they open a (small) window — every other layer
# is headless and the headless renderer draws nothing (DECISIONS #141).
#
#   GODOT=<path> ./tests/render_test.sh
#
# Today: the Nature kit's leaves and blades are lit the same from behind as from the front, and
# the grass keeps its colour at a distance (DECISIONS #141, #146), each with a control that shows
# the bug; the lake shows its depth from a player's camera (#150); the grip preview's Save
# Pictures draws every animation (#157); and F11 really makes the game fullscreen and back
# (#148) — the window flashes to full screen for a moment while that runs.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# On the defaults, not the player's settings: a saved fullscreen would change every picture.
export UMF_SETTINGS=none
failed=0
for scene in res://tests/render/foliage_render_test.tscn res://tests/render/water_render_test.tscn \
    res://tests/render/grip_pictures_test.tscn res://tests/render/window_test.tscn; do
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
