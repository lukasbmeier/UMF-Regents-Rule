#!/usr/bin/env bash
# THE SKELETON ARCHER, PLAYED (Luke's F1-F6, 2026-11-12, FOES_PREP.md section 9 step 3): the world's real referee and
# a real client at a simulated round trip, against the archer by the glade's skeleton camp. The fighter is shot from 11 m (the tell,
# the pale glint, the arrow's damage, no stagger), blocks an arrow, rolls one, knocks one away with a timed parry
# (its shooter not staggered), then walks up: the archer steps back once, is caught, and shoves. Then the server's
# own word, from its log: the shot loosed at where we stood, knocked away, and a player's use of the shot refused.
#
#   GODOT=/path/to/godot ./game/regents/tests/archer_playtest.sh     # 150 ms round trip, 20 ms jitter (~3 min)
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/archer_playtest.tscn"
CODE='"regentsarcherplaytestcode"'

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the client steps about
sleep 2

ref_log="$(mktemp)"; fight_log="$(mktemp)"; ref_pid=""; fight_pid=""
cleanup() { [ -n "$fight_pid" ] && kill "$fight_pid" 2>/dev/null; [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null; wait 2>/dev/null; rm -f "$ref_log" "$fight_log"; }
trap cleanup EXIT

echo "== the world's referee =="
spacetime call "$DB" offer_referee 0 "$CODE" >/dev/null 2>&1 || { echo "offer_referee failed" >&2; exit 1; }
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --claim="${CODE//\"/}" --no-record >"$ref_log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$ref_log" && break; sleep 0.5; done
if ! grep -q "claim_referee: registered" "$ref_log"; then
  echo "the referee did not register:" >&2; tail -20 "$ref_log" >&2; exit 1
fi

echo "== a fighter at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
timeout 200 "$GODOT" --headless --path . "$SCENE" -- --token=archerfighter --latency="$LATENCY" --jitter="$JITTER" >"$fight_log" 2>&1 &
fight_pid=$!
heals=0
slain=""
while kill -0 "$fight_pid" 2>/dev/null; do
  # HEAL <entity>: the fighter whole again between legs (an authority's negative damage).
  asked="$(grep -cE '^HEAL [0-9]+' "$fight_log")"
  if [ "$asked" -gt "$heals" ]; then
    ent="$(grep -oE '^HEAL [0-9]+' "$fight_log" | tail -1 | awk '{print $2}')"
    spacetime call "$DB" apply_damage "$ent" -- -200.0 0 >/dev/null 2>&1
    heals="$asked"
  fi
  # CAMP_DOWN (and SLAY_CAMP, the close-up leg's): the melee skeletons beside the archer (warriors 40001, axemen 40002)
  # and the imp (40007) fall, and are slain again every ~20 s (they are back after 60): the archer's legs are the
  # archer's alone. Since foes wander at rest (F10, 2026-11-13) they can come within sight of the archer's spot.
  if grep -qE '^(CAMP_DOWN|SLAY_CAMP)' "$fight_log"; then
    camp_tick=$(( ${camp_tick:-66} + 1 ))
    if [ "$camp_tick" -ge 66 ] || { [ -z "$slain" ] && grep -q '^SLAY_CAMP' "$fight_log"; }; then
      for fid in 40001 40002 40007; do
        for ent in $(spacetime sql "$DB" "SELECT entity_id FROM foe WHERE foe_id = $fid" 2>/dev/null | grep -oE '^ *[0-9]+' | tr -d ' '); do
          spacetime call "$DB" admin_slay "$ent" 0 >/dev/null 2>&1
        done
      done
      camp_tick=0
      grep -q '^SLAY_CAMP' "$fight_log" && slain=1
    fi
  fi
  sleep 0.3
done
wait "$fight_pid"; status=$?; fight_pid=""
grep -E "^   |FAIL|passed," "$fight_log"
if grep -E "SCRIPT ERROR" "$fight_log" >/dev/null; then
  echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$fight_log" | head -12 >&2; status=1
fi
if grep -E "SCRIPT ERROR|no behavior tree" "$ref_log" >/dev/null; then
  echo "VIOLATION: the referee:" >&2; grep -E "SCRIPT ERROR|no behavior tree" -A3 "$ref_log" | head -12 >&2; status=1
fi

echo "-- the server's own word"
logs="$(spacetime logs "$DB" -n 4000 2>/dev/null)"
ok() { echo "   ok: $1"; }
bad() { echo "  FAIL: $1" >&2; status=1; }
loosed="$(echo "$logs" | grep -c "looses 40030 at where")"
[ "$loosed" -ge 4 ] && ok "the server loosed $loosed shots at where its target stood" || bad "the server loosed $loosed shots (4 or more wanted)"
parried_here="$(grep -oE '^PARRIED_SHOTS [0-9]+' "$fight_log" | awk '{print $2}')"
knocked="$(echo "$logs" | grep -c "knocked away")"
if [ "${parried_here:-0}" -ge 1 ]; then
  [ "$knocked" -ge 1 ] && ok "a timed parry knocked a shot away ($knocked), by the server's judging" || bad "the client took nothing, but the server knocked no shot away"
fi
echo "$logs" | grep -q "40030 on .* is dealt at once" && ok "a shot on a player is dealt at once, to be taken back" || bad "no shot was dealt at once"
if echo "$logs" | grep -E "40030 staggered|parried [0-9]+'s 40030" >/dev/null; then bad "a shot staggered someone, or was parried as a swing is"; else ok "NEGATIVE: no shot staggered anyone, and none was parried as a swing is (no stagger on its shooter)"; fi
# NEGATIVE: a player's own use of the foe's shot is refused (no weapon gives that kit).
refused="$(spacetime call "$DB" use_ability 40030 0 '{"x":0.0,"y":0.0,"z":-1.0}' 0 2>&1)"
if echo "$refused" | grep -qiE "wield|cannot use|error"; then ok "NEGATIVE: a player's use of the archer's shot is refused ($(echo "$refused" | grep -m1 -oiE "wield[^\"]*|cannot use[^\"]*" | head -1))"; else bad "a player used the archer's shot: $refused"; fi
exit "$status"
