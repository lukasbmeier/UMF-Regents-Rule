#!/usr/bin/env bash
# THE LOOK, RENDERED. Checks that need pixels, so they open a (small) window — every other layer
# is headless and the headless renderer draws nothing (DECISIONS #141).
#
#   GODOT=<path> ./tests/render_test.sh
#
# The foundation's: F11 really makes the game fullscreen and back (#148) — the window flashes to
# full screen for a moment while that runs. The renderer chosen with no command line, the game
# restarting itself onto Compatibility, and Low cheaper than High on both renderers (#282). A
# genre's own run after it (fishing's: the foliage lit from both sides #141 #146, the lake's depth
# #150, the grip pictures #157).
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
# THE RENDERER WITH NO COMMAND LINE, AND LOW REALLY CHEAPER (DECISIONS #282). Each step is its own
# process (a renderer is picked as a process starts): tests/render/renderer_steps.gd says what each
# checks. The player's own renderer files in the user folder are put aside first and back after.
steps_scene="res://tests/render/renderer_steps.tscn"
udir="$("$GODOT" --path . --resolution 320x240 "$steps_scene" -- --step=where 2>/dev/null | tr -d '\r' | sed -n 's/^RENDER USERDIR //p' | head -1)"
if [ -z "$udir" ] || [ ! -d "$udir" ]; then
  echo "render_test: renderer: no user folder ($udir)"
  failed=1
else
  aside="$(mktemp -d)"
  for f in renderer.cfg renderer_guard.cfg; do [ -f "$udir/$f" ] && mv "$udir/$f" "$aside/$f"; done
  rm -f "$udir/render_test_result.txt" "$udir/render_test_guard.cfg"
  for step in default compat restart; do
    out="$(mktemp)"
    "$GODOT" --path . --resolution 320x240 "$steps_scene" -- --step=$step 2>&1 | tee "$out"
    code=${PIPESTATUS[0]}
    if [ "$code" -ne 0 ] || grep -q "RENDER FAIL" "$out" || ! grep -q "RENDER PASS" "$out"; then
      echo "render_test: renderer step '$step' FAILED"
      failed=1
    fi
    rm -f "$out"
  done
  # The restarted game writes its verdict; it starts a moment after the first one quits.
  for i in $(seq 1 60); do [ -f "$udir/render_test_result.txt" ] && break; sleep 1; done
  verdict="$(cat "$udir/render_test_result.txt" 2>/dev/null)"
  echo "renderer restart: ${verdict:-no verdict}"
  case "$verdict" in
    PASS*) echo "RENDER PASS the game restarted itself onto Compatibility and said why" ;;
    *) echo "render_test: the restart onto Compatibility FAILED (${verdict:-the restarted game never reported})"; failed=1 ;;
  esac
  rm -f "$udir/render_test_result.txt" "$udir/render_test_guard.cfg" "$udir/render_test_settings.cfg" "$udir/renderer.cfg" "$udir/renderer_guard.cfg"
  for f in renderer.cfg renderer_guard.cfg; do [ -f "$aside/$f" ] && mv "$aside/$f" "$udir/$f"; done
  rmdir "$aside" 2>/dev/null
fi
# Low against High, on both renderers, in the made-up level with 60 walking characters (the bench):
# Low's GPU time must be under 60 % of High's (measured: 23 % on Forward+, 11 % on Compatibility),
# and Compatibility must not be asked for effects it cannot draw.
for method in forward_plus gl_compatibility; do
  out="$(mktemp)"
  json="$(mktemp)"
  "$GODOT" --path . --rendering-method $method --resolution 960x540 res://tools/perf/perf_bench.tscn -- \
    --only=presets --chars=60 --frames=90 --warmup=30 --out="$json" 2>&1 | tee "$out" | grep "^\[bench\] preset"
  if ! python -c "
import json, sys
r = {x['name']: x for x in json.load(open(sys.argv[1]))['results']}
low, high = r['preset_low']['gpu_ms'], r['preset_high']['gpu_ms']
ok = high > 0 and low < 0.6 * high
print('RENDER %s %s: Low %.2f ms of GPU against High %.2f (%.0f %%)' % ('PASS' if ok else 'FAIL', sys.argv[2], low, high, 100 * low / max(high, 1e-9)))
sys.exit(0 if ok else 1)
" "$json" "$method"; then
    failed=1
  fi
  # The one warning allowed: the project's TAA, read before Settings turns it off on Compatibility.
  if grep "only available" "$out" | grep -v "TAA is only available" | grep -q .; then
    echo "render_test: $method was asked for effects it cannot draw:"; grep "only available" "$out" | grep -v "TAA is only"
    failed=1
  fi
  rm -f "$out" "$json"
done
if [ "$failed" -ne 0 ]; then
  echo "render_test: FAILED"
  exit 1
fi
echo "render_test: ok"
