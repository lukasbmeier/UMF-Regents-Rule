#!/usr/bin/env bash
# HOST A GAME FOR PLAYERS ON OTHER MACHINES, without the editor (Luke 2026-10-15: on his Mac across
# town, the bot hens stood still and the wolf never came: nothing was driving them). A game needs two
# things running on the host besides SpacetimeDB:
#   - SpacetimeDB listening for other machines (0.0.0.0:3000), started here if it is not running
#   - the world's REFEREE (DECISIONS #226, #230): the sidecar that judges attacks and drives every bot.
#     Pressing Play in the editor starts one for you (RefereeLauncher); without the editor nothing does,
#     and the bots stand where they spawned. This offers the farm a one-time code and starts it.
# Both run until this window is closed (Ctrl+C); the referee comes back if it stops.
#
#   tools\host.cmd                         (Windows: double-click it)
#   GODOT=<path> ./tools/host.sh [world]   (world 0 by default)
#
# Plays on the game's own database (shared/game.json `database`), the one you publish to (UMF_DB: a
# test's). Players
# connect to this PC's address (port 3000: the firewall rule and the router's forward, or Tailscale:
# docs/HANDBOOK.md, "Playing with a friend"). Logs: build/host/.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -f tools/local.env ] && . tools/local.env
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-python}"
WORLD="${1:-0}"
DB="${UMF_DB:-$("$PYTHON" -c "import json; print(json.load(open('shared/game.json')).get('database', 'umf'))" | tr -d '\r')}"
mkdir -p build/host
up() { curl -s -m 2 -o /dev/null http://127.0.0.1:3000/v1/ping; }

st_pid=""
ref_pid=""
watch_pid=""
alive_pid=""
cleanup() {
  [ -n "$alive_pid" ] && kill "$alive_pid" 2>/dev/null
  rm -f build/host/host.alive
  [ -n "$watch_pid" ] && kill "$watch_pid" 2>/dev/null
  [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null
  [ -n "$st_pid" ] && kill "$st_pid" 2>/dev/null
  echo "host: stopped"
}
trap cleanup EXIT
trap 'exit 0' INT TERM

if up; then
  if netstat -an 2>/dev/null | grep -E "(0\.0\.0\.0|\[::\]):3000 .*LISTEN" >/dev/null; then
    echo "host: SpacetimeDB is already running, for other machines too"
  else
    echo "host: SpacetimeDB is already running, but only for this PC: stop it and run this again (it starts it with --listen-addr 0.0.0.0:3000)" >&2
    exit 1
  fi
else
  echo "host: starting SpacetimeDB for other machines (0.0.0.0:3000)"
  spacetime start --listen-addr 0.0.0.0:3000 > build/host/spacetime.log 2>&1 &
  st_pid=$!
  for _ in $(seq 1 60); do up && break; sleep 1; done
  up || { echo "host: SpacetimeDB did not start (build/host/spacetime.log)" >&2; tail -20 build/host/spacetime.log >&2; exit 1; }
fi
spacetime sql "$DB" "SELECT * FROM world_config" >/dev/null 2>&1 \
  || { echo "host: there is no '$DB' database on this server: publish it first (tools\\publish.cmd)" >&2; exit 1; }

# FEEDBACK AS IT ARRIVES (DECISIONS #244): a player's F8 shows up here, with a bell, while you host.
"$PYTHON" tools/feedback.py --db "$DB" --watch &
watch_pid=$!

# THE CHRONICLE (DECISIONS #276): everything that happens, kept on this PC for looking back
# (tools	elemetry.cmd shows it). It stops a few seconds after this window does (the alive file).
( while true; do touch build/host/host.alive; sleep 1; done ) &
alive_pid=$!
touch build/host/host.alive
"$PYTHON" tools/telemetry/chronicle.py --db "$DB" --parent-alive "$PWD/build/host/host.alive" > build/host/chronicle.log 2>&1 &
echo "host: recording everything that happens for looking back (tools	elemetry.cmd; build/host/chronicle.log)"

# The referee: offered a code (the CLI is the database's owner, its admin), started with it, and started
# again whenever it stops (a crash, a sleep), until this window closes.
while true; do
  CODE="host${WORLD}x$(date +%s)$RANDOM"
  if ! out="$(spacetime call "$DB" offer_referee "$WORLD" "\"$CODE\"" 2>&1)"; then
    if printf '%s' "$out" | grep -q "already has a referee"; then
      echo "host: world $WORLD already has a referee (an editor run, or another host): waiting for it to go"
      sleep 15
      continue
    fi
    echo "host: could not offer a referee: $out" >&2
    exit 1
  fi
  "$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world="$WORLD" --referee --claim="$CODE" \
    > build/host/referee.log 2>&1 &
  ref_pid=$!
  echo "$ref_pid" > build/host/referee.pid
  for _ in $(seq 1 60); do grep -q "claim_referee: registered" build/host/referee.log 2>/dev/null && break; kill -0 "$ref_pid" 2>/dev/null || break; sleep 1; done
  if grep -q "claim_referee: registered" build/host/referee.log 2>/dev/null; then
    echo "host: the referee judges world $WORLD and drives its bots. Players connect to this PC on port 3000."
    echo "      Close this window (or Ctrl+C) to stop hosting."
  else
    echo "host: the referee did not register (build/host/referee.log):" >&2
    tail -15 build/host/referee.log >&2
  fi
  wait "$ref_pid"
  ref_pid=""
  echo "host: the referee stopped; starting it again in 5 s"
  sleep 5
done
