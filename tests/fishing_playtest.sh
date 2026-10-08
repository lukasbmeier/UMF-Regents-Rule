#!/usr/bin/env bash
# Fishing playtest: the real scene, a real module, and the game played with the real keys —
# walk from the spawn to the end of the dock, aim, hold and release the cast button, wait for
# the bite, set the hook, land the catch; then reel in early, get refused, and shop.
#
#   GODOT=/path/to/godot ./tests/fishing_playtest.sh              # 0 and 150 ms
#   GODOT=... LATENCIES="0" ./tests/fishing_playtest.sh           # pick your own
#   GODOT=... JITTER=40 ./tests/fishing_playtest.sh               # plus jitter each way
#   GODOT=... SHOTS=grip_pictures/play ./tests/fishing_playtest.sh
#                         # in a WINDOW, at 0 ms, pictures of every moment in that folder (and a
#                         # line left out when the round ends): look at them
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
GODOT="${GODOT:-godot}"
SHOTS="${SHOTS:-}"
LATENCIES="${LATENCIES:-0 150}"
[ -n "$SHOTS" ] && LATENCIES="0"
JITTER="${JITTER:-0}"
SCENE="res://tests/playtest/fishing_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

overall=0
for ms in $LATENCIES; do
  echo "== publish (fresh data) =="
  (cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
    || { echo "publish failed" >&2; exit 1; }
  # The game's own level: the module's default is the lakeside, which is what this plays.
  sleep 3
  # Skip the 30 s lobby: fishing is gated to the PLAYING phase.
  # The rival angler (DECISIONS #169) fishes this world too, and would win the round this suite
  # expects its one player to win: benched. tests/integration_test.sh plays him.
  spacetime call "$DB" set_rival 0 false >/dev/null 2>&1
  spacetime call "$DB" set_session_phase 1 1 >/dev/null 2>&1

  out_file="$(mktemp)"
  obs_file="$(mktemp)"
  # A SECOND CLIENT at the village: what it sees of this cast is checked in its own process
  # (tests/playtest/fishing_observer.gd). Started first, so it is in the world before the cast.
  "$GODOT" --headless --path . res://tests/playtest/fishing_observer.tscn -- --token=fishwatch \
    --name=Watcher >"$obs_file" 2>&1 &
  observer=$!
  sleep 4
  j=0; [ "$ms" -gt 0 ] && j="$JITTER"
  # ROUNDS END AND THE SHOP OPENS ON A TIMER, and waiting out a real round takes minutes. The
  # client is an ordinary player and may not move the phase itself, so watch for it reaching
  # each step and move the phase from out here, as admin — the same hook the integration suite
  # uses. First the results, then the shop.
  ( for _ in $(seq 1 400); do
      if grep -q -- "-- show the results --" "$out_file" 2>/dev/null; then
        spacetime call "$DB" set_session_phase 1 2 >/dev/null 2>&1
        break
      fi
      sleep 0.25
    done
    for _ in $(seq 1 400); do
      if grep -q -- "-- open the shop --" "$out_file" 2>/dev/null; then
        # One fish does not pay for a rod, and the point of this step is the purchase, not the
        # grind. Credit the angler as an authority would, then open the shop.
        # Every player row: the module keeps one per identity that has ever connected, and this
        # run's client is not necessarily the first of them.
        for ent in $(spacetime sql "$DB" "SELECT entity_id FROM player" 2>/dev/null | tail -n +3 | tr -d ' '); do
          [ -n "$ent" ] && spacetime call "$DB" add_score "$ent" 0 500 >/dev/null 2>&1
        done
        spacetime call "$DB" set_session_phase 1 3 >/dev/null 2>&1
        exit 0
      fi
      sleep 0.25
    done ) &
  watcher=$!
  if [ -n "$SHOTS" ]; then
    mkdir -p "$SHOTS"
    shots_abs="$(cd "$SHOTS" && pwd -W 2>/dev/null || pwd)"
    "$GODOT" --path . --resolution 1280x720 "$SCENE" -- --token=fishtest --name=Playtester \
      --latency="$ms" --jitter="$j" --autoconnect --shots="$shots_abs" 2>&1 | tee "$out_file"
  else
    "$GODOT" --headless --path . "$SCENE" -- --token=fishtest --name=Playtester --latency="$ms" \
      --jitter="$j" 2>&1 | tee "$out_file"
  fi
  status=${PIPESTATUS[0]}
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  # The observer exits by itself once it has seen the catch (or on its own timeout). One that never
  # starts its script (a parse error) never exits either: it is given 240 s, then stopped and failed.
  for _ in $(seq 1 480); do kill -0 "$observer" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$observer" 2>/dev/null; then
    kill "$observer" 2>/dev/null
    echo "  FAIL: the observer was still running after 240 s (did its script fail to load?)"
    wait "$observer" 2>/dev/null
    obs_status=1
  else
    wait "$observer"; obs_status=$?
  fi
  echo "== what the other client saw =="
  grep -E "^==|^   |FAIL|observer:" "$obs_file"
  if grep -E "SCRIPT ERROR" "$obs_file" >/dev/null; then
    echo "VIOLATION: the observer produced script errors:" >&2
    grep -E "SCRIPT ERROR" "$obs_file" | head -5 >&2
    obs_status=1
  fi
  rm -f "$obs_file"
  [ "$obs_status" -eq 0 ] || status=1
  if grep -E "SCRIPT ERROR" "$out_file" >/dev/null; then
    echo "VIOLATION: the client produced script errors:" >&2
    grep -E "SCRIPT ERROR" "$out_file" | head -5 >&2
    status=1
  fi
  rm -f "$out_file"
  [ "$status" -eq 0 ] || overall=1
  echo
done
exit "$overall"
