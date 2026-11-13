#!/usr/bin/env bash
# THE IMP CASTER, PLAYED (Luke's F1, 2026-11-12, FOES_PREP.md section 9 step 4): the world's real referee and a real
# client at a simulated round trip, against the imp by the glade's skeleton camp. The fighter stands in its range and
# takes what it casts, each of six ways once: a bolt taken, a bolt stepped out of after the aim locks, a bolt walked
# into (led: hit), a bolt turned from after the lock (missed), a ring stood in, a ring walked out of. Then it stands on the imp and swings: staggered, its cast is lost. Then the server's own word,
# from its log: bolts flown, rings laid under where we stood, a cast stopped, a player's use of the ring refused.
#
#   GODOT=/path/to/godot ./game/regents/tests/caster_playtest.sh     # 150 ms round trip, 20 ms jitter (~4 min)
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/caster_playtest.tscn"
CODE='"regentscasterplaytestcode"'

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
timeout 280 "$GODOT" --headless --path . "$SCENE" -- --token=casterfighter --latency="$LATENCY" --jitter="$JITTER" >"$fight_log" 2>&1 &
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
  # SLAY_CAMP: the melee skeletons beside the archer (warriors 40001, axemen 40002) and the archer (40006) fall, for the close-up leg.
  if [ -z "$slain" ] && grep -q '^SLAY_CAMP' "$fight_log"; then
    for fid in 40001 40002 40006; do
      for ent in $(spacetime sql "$DB" "SELECT entity_id FROM foe WHERE foe_id = $fid" 2>/dev/null | grep -oE '^ *[0-9]+' | tr -d ' '); do
        spacetime call "$DB" admin_slay "$ent" 0 >/dev/null 2>&1
      done
    done
    slain=1
  fi
  # ARCHER_DOWN: the camp's archer kept down while the imp's own legs run (2026-11-13: at rest foes wander, F10, and
  # the archer came within sight of the imp's spot and shot too). Slain again every ~20 s (it is back after 60).
  if grep -q '^ARCHER_DOWN' "$fight_log"; then
    archer_tick=$(( ${archer_tick:-66} + 1 ))
    if [ "$archer_tick" -ge 66 ]; then
      for ent in $(spacetime sql "$DB" "SELECT entity_id FROM foe WHERE foe_id = 40006" 2>/dev/null | grep -oE '^ *[0-9]+' | tr -d ' '); do
        spacetime call "$DB" admin_slay "$ent" 0 >/dev/null 2>&1
      done
      archer_tick=0
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
logs="$(spacetime logs "$DB" -n 6000 2>/dev/null)"
ok() { echo "   ok: $1"; }
bad() { echo "  FAIL: $1" >&2; status=1; }
bolts="$(echo "$logs" | grep -c "looses 40032 at where")"
rings="$(echo "$logs" | grep -c "lays 40033 under where")"
[ "$bolts" -ge 2 ] && ok "the server flew $bolts bolts at where its target stood" || bad "the server flew $bolts bolts (2 or more wanted)"
led="$(echo "$logs" | grep -cE "aims 40032 [0-9.]+ m ahead of")"
[ "$led" -ge 2 ] && ok "the server led $led bolts at a walker ($(echo "$logs" | grep -oE "aims 40032 [0-9.]+ m ahead" | head -2 | grep -oE "[0-9.]+ m" | paste -sd ' '))" || bad "the server led $led bolts (2 or more wanted: the walked and turned legs)"
[ "$rings" -ge 2 ] && ok "the server laid $rings rings under where its target stood" || bad "the server laid $rings rings (2 or more wanted)"
stopped="$(echo "$logs" | grep -cE "'s shot 4003[23] was stopped before it flew")"
[ "$stopped" -ge 1 ] && ok "a cast was stopped before it flew ($stopped): the imp staggered mid-cast" || bad "no cast was stopped by our swings"
if echo "$logs" | grep -E "4003[23] staggered|parried [0-9]+'s 4003[23]" >/dev/null; then bad "a cast staggered someone, or was parried as a swing is"; else ok "NEGATIVE: no cast staggered anyone"; fi
# NEGATIVE: a player's own use of the imp's ring is refused (no weapon gives that kit).
refused="$(spacetime call "$DB" use_ability 40033 0 '{"x":0.0,"y":0.0,"z":-1.0}' 0 2>&1)"
if echo "$refused" | grep -qiE "wield|cannot use|error"; then ok "NEGATIVE: a player's use of the imp's ring is refused ($(echo "$refused" | grep -m1 -oiE "wield[^\"]*|cannot use[^\"]*" | head -1))"; else bad "a player used the imp's ring: $refused"; fi
exit "$status"
