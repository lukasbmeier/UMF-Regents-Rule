#!/usr/bin/env bash
# THE SKILLING CHAIN, PLAYED: two real clients at a simulated round trip in the frontier glade. The
# chopper chops (AFK and a round), mines a round, smelts a round, makes rivets AFK, carves a handle, shapes
# an iron axe head in a round, assembles an Iron axe and chops with it; the buddy chops tree_1 beside them.
# When the chopper prints GRANT_ORE <entity>, this gives it two copper ore (two to a bar); at GRANT_ME, two
# iron bars, two logs and two oak logs (a fresh character's iron and oak need ranks, more than a test's minutes); at
# GRANT_SWORD, two copper bars and two rivets (the tutorial's sword, made last).
#
#   GODOT=/path/to/godot ./game/regents/tests/skilling_playtest.sh     # 150 ms round trip, 20 ms jitter
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/skilling_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the clients step to the work
sleep 2
LEVEL=$(spacetime sql "$DB" "SELECT level_id FROM world_level WHERE world_id = 0" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | head -1 | tr -d ' ')
echo "   world 0 runs level ${LEVEL:-none} (the frontier is 20)"

chop_log="$(mktemp)"; buddy_log="$(mktemp)"; buddy_pid=""; chop_pid=""
cleanup() { [ -n "$buddy_pid" ] && kill "$buddy_pid" 2>/dev/null; [ -n "$chop_pid" ] && kill "$chop_pid" 2>/dev/null; wait 2>/dev/null; rm -f "$chop_log" "$buddy_log"
  spacetime call "$DB" reset_rule '"regents.foe_respawn_s"' >/dev/null 2>&1; }
# Skinning slays the glade's deer twice: it comes back in 3 s for this run (reset as it ends).
spacetime call "$DB" set_rule '"regents.foe_respawn_s"' 3.0 '""' >/dev/null 2>&1
trap cleanup EXIT

echo "== two clients at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
"$GODOT" --headless --path . "$SCENE" -- --token=buddy --role=buddy --latency="$LATENCY" --jitter="$JITTER" >"$buddy_log" 2>&1 &
buddy_pid=$!
# SHOTS=<dir>: the chopper plays in a window and saves pictures of the windows it opens (the station's, the
# bag, the skills) to <dir>.
CHOP_HEADLESS="--headless"; [ -n "${SHOTS:-}" ] && CHOP_HEADLESS="--resolution 1280x720"
"$GODOT" $CHOP_HEADLESS --path . "$SCENE" -- --token=chopper --role=chopper --latency="$LATENCY" --jitter="$JITTER" --autoconnect --shots="${SHOTS:-}" >"$chop_log" 2>&1 &
chop_pid=$!
granted=""; ore_given=""; sword_given=""; stave_given=""; slain=0; last_deer=""
while kill -0 "$chop_pid" 2>/dev/null; do
  if [ -z "$ore_given" ]; then
    ent="$(grep -oE '^GRANT_ORE [0-9]+' "$chop_log" | head -1 | awk '{print $2}')"
    if [ -n "$ent" ]; then
      spacetime call "$DB" grant_item "$ent" 40007 2 >/dev/null 2>&1
      ore_given="yes"
      echo "   gave entity $ent two copper ore"
    fi
  fi
  if [ -z "$granted" ]; then
    ent="$(grep -oE '^GRANT_ME [0-9]+' "$chop_log" | head -1 | awk '{print $2}')"
    if [ -n "$ent" ]; then
      spacetime call "$DB" grant_item "$ent" 40011 2 >/dev/null 2>&1
      spacetime call "$DB" grant_item "$ent" 40002 2 >/dev/null 2>&1
      spacetime call "$DB" grant_item "$ent" 40003 2 >/dev/null 2>&1
      granted="yes"
      echo "   gave entity $ent two iron bars, two logs and two oak logs"
    fi
  fi
  if [ -z "$stave_given" ]; then
    ent="$(grep -oE '^GRANT_STAVE [0-9]+' "$chop_log" | head -1 | awk '{print $2}')"
    if [ -n "$ent" ]; then
      spacetime call "$DB" admin_give_item "$ent" 40049 1 650 >/dev/null 2>&1
      stave_given="yes"
      echo "   gave entity $ent an unstrung yew bow of quality 650 (herbalism's stringing)"
    fi
  fi
  # SKINNING asks for a deer each time (SLAY_DEER <entity> <n>): the glade's deer, once it is back (a fresh entity on
  # deer_1: foes come back in 3 s for this run), slain as that player's kill.
  asked="$(grep -cE '^SLAY_DEER [0-9]+' "$chop_log")"
  if [ "$asked" -gt "$slain" ]; then
    ent="$(grep -oE '^SLAY_DEER [0-9]+' "$chop_log" | tail -1 | awk '{print $2}')"
    deer="$(spacetime sql "$DB" "SELECT entity_id FROM foe WHERE point_id = 'deer_1' AND gone = false" 2>/dev/null | tail -n +3 | head -1 | tr -d ' ')"
    if [ -n "$deer" ] && [ "$deer" != "$last_deer" ]; then
      spacetime call "$DB" admin_slay "$deer" "$ent" >/dev/null 2>&1
      slain=$((slain + 1)); last_deer="$deer"
      echo "   slew the glade's deer ($deer) as entity $ent's kill (skinning, $slain)"
    fi
  fi
  if [ -z "$sword_given" ]; then
    ent="$(grep -oE '^GRANT_SWORD [0-9]+' "$chop_log" | head -1 | awk '{print $2}')"
    if [ -n "$ent" ]; then
      spacetime call "$DB" grant_item "$ent" 40010 2 >/dev/null 2>&1
      spacetime call "$DB" grant_item "$ent" 40012 2 >/dev/null 2>&1
      sword_given="yes"
      echo "   gave entity $ent two copper bars and two copper rivets (the tutorial's sword)"
    fi
  fi
  sleep 0.5
done
wait "$chop_pid"; status=$?; chop_pid=""
wait "$buddy_pid"; bstatus=$?; buddy_pid=""
for log in "$chop_log" "$buddy_log"; do
  grep -E "^   |FAIL|passed,|binding after" "$log"
  if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
    echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$log" | head -12 >&2; status=1
  fi
done
[ "$bstatus" -eq 0 ] || status=1
echo "-- the server's log"
spacetime logs "$DB" 2>/dev/null | grep -E "regents:" | tail -14
exit "$status"
