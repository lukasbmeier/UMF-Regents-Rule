#!/usr/bin/env bash
# Two real clients, no explicit identity, against one live module.
#
# This is the layer that catches the worst failure in local multiplayer: two clients that share
# one SpacetimeDB identity are handed the SAME entity by the server, so the session looks like it
# works — one avatar moves, no errors, every other suite green — while there is really only one
# player. Nothing below the client process can see that, because it is a property of how the two
# processes were launched, not of any single one of them.
#
#   GODOT=/path/to/godot ./tests/multiclient_test.sh
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
GODOT="${GODOT:-godot}"
SCENE="res://game/fishing/fishing_game.tscn"
RUN_SECONDS="${RUN_SECONDS:-16}"

pass=0; fail=0
check() {   # check <actual> <expected> <label>
  if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "  ok   $3";
  else fail=$((fail+1)); echo "  FAIL $3 (got '$1', want '$2')"; fi
}
check_ne() {
  if [ "$1" != "$2" ]; then pass=$((pass+1)); echo "  ok   $3";
  else fail=$((fail+1)); echo "  FAIL $3 (both were '$1')"; fi
}

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
# Every scripted route in this suite is on the greybox; the module's default level is the
# lakeside (the game). Selecting it moves the spawn to the origin and stocks the ponds.
spacetime call "$DB" use_level 0 0 >/dev/null 2>&1 \
  || { echo "use_level failed" >&2; exit 1; }
sleep 3
# Casting is PLAYING-gated and a fresh session starts in LOBBY; this suite is about identity and
# visibility, not the fishing loop, but the phase is set so the clients run the same path players do.
spacetime call "$DB" set_session_phase 1 1 >/dev/null 2>&1

log_a="$(mktemp)"; log_b="$(mktemp)"
trap 'rm -f "$log_a" "$log_b"; kill -9 ${pid_a:-} ${pid_b:-} 2>/dev/null' EXIT

echo "== two clients, NEITHER passing --token =="
# Deliberately no --token: the point is that boot.gd hands each editor-binary instance its own
# identity by itself. Passing one here would test the launcher instead of the mechanism.
# B starts second on purpose: it must find A's slot held and move to the next one.
"$GODOT" --headless --path . "$SCENE" -- --name=Ailsa >"$log_a" 2>&1 & pid_a=$!
sleep 2
"$GODOT" --headless --path . "$SCENE" -- --name="  Bram  the   Bold  " >"$log_b" 2>&1 & pid_b=$!
# Halfway through, score for B from out here, as an authority would for a catch. Each client's
# leaderboard then has to show the OTHER player's score under the OTHER player's name — the part
# of a scoreboard no single process can check.
half=$((RUN_SECONDS / 2))
sleep "$half"
ent_bram="$(spacetime sql "$DB" "SELECT entity_id FROM player WHERE name = 'Bram the Bold'" 2>/dev/null \
  | tail -n +3 | head -1 | tr -d ' ')"
[ -n "$ent_bram" ] && spacetime call "$DB" add_score "$ent_bram" 30 0 >/dev/null 2>&1
sleep $((RUN_SECONDS - half))
# Make sure both clients are really gone. A survivor keeps its identity slot bound and its
# connection open, which silently shifts the next run's slots and leaves a stale player row.
for pid in $pid_a $pid_b; do
  kill "$pid" 2>/dev/null
done
sleep 2
for pid in $pid_a $pid_b; do
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
done
wait $pid_a $pid_b 2>/dev/null

slot_a=$(grep -o 'dev identity slot [0-9]*' "$log_a" | head -1 | awk '{print $NF}')
slot_b=$(grep -o 'dev identity slot [0-9]*' "$log_b" | head -1 | awk '{print $NF}')
ent_a=$(grep -o '\[Boot\] local entity: [0-9]*' "$log_a" | head -1 | awk '{print $NF}')
ent_b=$(grep -o '\[Boot\] local entity: [0-9]*' "$log_b" | head -1 | awk '{print $NF}')

echo "  client A: slot=${slot_a:-none} entity=${ent_a:-none}"
echo "  client B: slot=${slot_b:-none} entity=${ent_b:-none}"

echo "== identity =="
check "$([ -n "$slot_a" ] && echo yes || echo no)" "yes" "client A claimed a dev identity slot"
check "$([ -n "$slot_b" ] && echo yes || echo no)" "yes" "client B claimed a dev identity slot"
check_ne "$slot_a" "$slot_b" "the two clients claimed different slots"
check "$([ -n "$ent_a" ] && echo yes || echo no)" "yes" "client A was assigned a local entity"
check "$([ -n "$ent_b" ] && echo yes || echo no)" "yes" "client B was assigned a local entity"
check_ne "$ent_a" "$ent_b" "the server handed them DIFFERENT entities"

echo "== each client sees the other =="
# The decisive assertion: A must spawn B's entity as a remote, and vice versa. Same-identity
# clients would each report exactly one entity and still look healthy.
check "$(grep -c "entity spawned: $ent_b kind 0 local=false" "$log_a")" "1" "A sees B's player as remote"
check "$(grep -c "entity spawned: $ent_a kind 0 local=false" "$log_b")" "1" "B sees A's player as remote"
check "$(grep -c "entity spawned: $ent_a kind 0 local=true" "$log_a")" "1" "A owns exactly one player"
check "$(grep -c "entity spawned: $ent_b kind 0 local=true" "$log_b")" "1" "B owns exactly one player"

echo "== names reach the other player =="
# A name is the one piece of untrusted text in the database and every client draws it over
# somebody's head, so the module cleans it: control characters gone, runs of whitespace
# collapsed. B is launched with a deliberately ragged one.
name_a="$(spacetime sql "$DB" "SELECT name FROM player WHERE entity_id = ${ent_a:-0}" 2>/dev/null | tail -n +3 | head -1 | sed 's/^ *//; s/ *$//; s/^"//; s/"$//')"
name_b="$(spacetime sql "$DB" "SELECT name FROM player WHERE entity_id = ${ent_b:-0}" 2>/dev/null | tail -n +3 | head -1 | sed 's/^ *//; s/ *$//; s/^"//; s/"$//')"
echo "  stored names: A='${name_a}' B='${name_b}'"
check "$name_a" "Ailsa" "A's name reached the server"
check "$name_b" "Bram the Bold" "B's ragged name was collapsed, not stored as typed"
# The nameplate is only built for entities that are NOT ours — you do not label yourself.
check "$(grep -c "nameplate: $ent_b = Bram the Bold" "$log_a")" "1" "A draws B's name over B"
check "$(grep -c "nameplate: $ent_a = Ailsa" "$log_b")" "1" "B draws A's name over A"
check "$(grep -c "nameplate: $ent_a =" "$log_a")" "0" "A does not draw a nameplate over itself"

echo "== the leaderboard =="
# The board prints each time it changes; the LAST line is what each player was looking at. B's
# score came from the server, so A can only show it if B's session row reached A's copy of B.
# The CLI connections above are players too (offline, no score) and must not be on it.
board_a="$(grep -o '\[Board\] .*' "$log_a" | tail -1 | tr -d '\r')"
board_b="$(grep -o '\[Board\] .*' "$log_b" | tail -1 | tr -d '\r')"
echo "  A shows: ${board_a:-nothing}"
echo "  B shows: ${board_b:-nothing}"
check "$board_a" "[Board] 1. Bram the Bold 30  2. Ailsa 0" "A ranks B first on B's server-side score, by name"
check "$board_b" "[Board] 1. Bram the Bold 30  2. Ailsa 0" "B's board agrees with A's"

echo "== both clients are actually rendering =="
# A client with no current camera draws nothing but its CanvasLayer HUD, reports no error, and
# passes every other suite. This runs the REAL genre scene, which is what a player launches.
check "$(grep -c 'view: looking through' "$log_a")" "1" "A is looking through a camera"
check "$(grep -c 'view: looking through' "$log_b")" "1" "B is looking through a camera"
check "$(grep -c 'no camera is current' "$log_a")" "0" "A never reported a missing camera"
check "$(grep -c 'no camera is current' "$log_b")" "0" "B never reported a missing camera"

echo "== the seeded pond reaches the clients =="
check "$(grep -c 'entity spawned: [0-9]* kind 2' "$log_a")" "3" "A spawned the three seeded fishing spots"
check "$(grep -c 'entity spawned: [0-9]* kind 2' "$log_b")" "3" "B spawned the three seeded fishing spots"

echo "== the server agrees =="
# One player row per client, plus one for the CLI connection that published/queried.
players=$(spacetime sql "$DB" 'SELECT entity_id FROM player' 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
check "$([ "$players" -ge 2 ] && echo yes || echo no)" "yes" "the module has at least two player rows ($players)"

echo "== no script errors =="
for f in "$log_a" "$log_b"; do
  if grep -E "SCRIPT ERROR" "$f" >/dev/null; then
    fail=$((fail+1)); echo "  FAIL script errors in $(basename "$f"):"; grep -E "SCRIPT ERROR" "$f" | head -3
  else
    pass=$((pass+1)); echo "  ok   clean run"
  fi
done

echo
echo "multiclient: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
