#!/usr/bin/env bash
# Launch a local multiplayer fishing session: a fresh module, the lakeside, and N clients.
#
#   GODOT=/path/to/godot ./game/fishing/play_local.sh          # 2 players, third person
#   GODOT=... ./game/fishing/play_local.sh 3                   # 3 players
#   GODOT=... VIEW=--first-person ./game/fishing/play_local.sh # swap the camera rig
#   GODOT=... LEVEL=greybox ./game/fishing/play_local.sh       # the greybox (movement only: no water)
#
# Each client gets its OWN identity file. Two clients sharing one would be handed the same
# entity by the server and would look like a single player.
#
# You do not need this script to play: with a published module, Godot's
# Debug > Customize Run Instances (set the count to 2) runs the same thing from the editor,
# and boot.gd hands each editor instance its own identity automatically. This script exists to
# republish from scratch and to skip the 30 s lobby.
#
# Controls: WASD move · Shift sprint · Ctrl walk · Space jump · mouse to look.
#   Fishing: hold the LEFT mouse button to aim (the ring shows where it lands, green over water
#   the server will take) and let go to cast. When the float goes under, click. A click before
#   then reels the line back in; right-click puts the rod down without casting.
#   Between rounds the shop opens: 1 rod (reach), 2 reel (hook-set window), 3 line (load).
set -uo pipefail
cd "$(dirname "$0")/../.."
# The database to play in: the game's (shared/game.json) unless DB says otherwise. UMF_DB reaches
# every client started here.
DB="${DB:-$(python -c "import json; print(json.load(open('shared/game.json')).get('database', 'umf'))" | tr -d '\r')}"
export UMF_DB="$DB"

GODOT="${GODOT:-godot}"
PLAYERS="${1:-2}"
VIEW="${VIEW:-}"
LEVEL="${LEVEL:-lakeside}"
case "$LEVEL" in
  lakeside) SCENE="res://game/fishing/lakeside_game.tscn"; LEVEL_ID=1 ;;
  greybox)  SCENE="res://game/fishing/fishing_game.tscn";  LEVEL_ID=0 ;;
  *) echo "LEVEL must be lakeside or greybox" >&2; exit 1 ;;
esac

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publishing a fresh module =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
sleep 3

# The module's default world runs the lakeside; the greybox is a switch away (admin only, and
# the publisher is the admin). It moves the spawn and, on the greybox, stocks its ponds.
if [ "$LEVEL_ID" != "1" ]; then
  spacetime call "$DB" use_level 0 "$LEVEL_ID" >/dev/null 2>&1 || { echo "use_level failed" >&2; exit 1; }
fi
echo "   world 0 runs the $LEVEL"

# Casting is gated to the PLAYING phase; a fresh session starts in LOBBY, so skip the wait.
spacetime call "$DB" set_session_phase 1 1 >/dev/null 2>&1
echo "   session set to PLAYING"

echo "== launching $PLAYERS client(s) =="
pids=()
for i in $(seq 1 "$PLAYERS"); do
  # --autoconnect: this script is the quick way in, so it skips the connect screen.
  "$GODOT" --path . "$SCENE" -- --token="player$i" --name="Player $i" --autoconnect $VIEW &
  pids+=($!)
  echo "   player$i (pid ${pids[-1]})"
  sleep 1   # stagger so each client's connect is distinguishable in the server log
done

echo
echo "Running. Ctrl-C here closes every client."
trap 'kill "${pids[@]}" 2>/dev/null' EXIT INT TERM
wait
