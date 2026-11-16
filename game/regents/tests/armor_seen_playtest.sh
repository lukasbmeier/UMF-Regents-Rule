#!/usr/bin/env bash
# ANOTHER PLAYER'S ARMOR, SEEN (W2): two real clients at a simulated round trip in the frontier glade. The wearer is
# given three pieces and wears them through the server; the watcher comes in after and must see them on the
# wearer's body (and not on its own); the wearer takes the chest off and the watcher sees the Peasant shirt again.
# No referee: wearing needs none.
#   GRANT_ARMOR <entity> <item> <item> <item>   the wearer asks: one of each, quality 0
#   WORN                                        the wearer wears them: the watcher starts
#   SEEN, WATCHER_DONE                          passed on to the wearer through the signal file
#
#   GODOT=/path/to/godot ./game/regents/tests/armor_seen_playtest.sh     # 150 ms round trip, 20 ms jitter (~2 min)
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/armor_seen_playtest.tscn"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the clients step about
sleep 2

wear_log="$(mktemp)"; watch_log="$(mktemp)"; signal="$(mktemp)"; wear_pid=""; watch_pid=""
cleanup() { [ -n "$wear_pid" ] && kill "$wear_pid" 2>/dev/null; [ -n "$watch_pid" ] && kill "$watch_pid" 2>/dev/null; wait 2>/dev/null
  rm -f "$wear_log" "$watch_log" "$signal"; }
trap cleanup EXIT
: > "$signal"
signal_path="$(cygpath -m "$signal" 2>/dev/null || echo "$signal")"

echo "== the wearer at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
timeout 160 "$GODOT" --headless --path . "$SCENE" -- --token=armorwearer --role=wearer --signal="$signal_path" \
  --latency="$LATENCY" --jitter="$JITTER" >"$wear_log" 2>&1 &
wear_pid=$!
given=""; seen=""; done_w=""; wearer_ent=""
while kill -0 "$wear_pid" 2>/dev/null || { [ -n "$watch_pid" ] && kill -0 "$watch_pid" 2>/dev/null; }; do
  if [ -z "$given" ]; then
    line="$(grep -oE '^GRANT_ARMOR [0-9]+ [0-9]+ [0-9]+ [0-9]+' "$wear_log" | head -1)"
    if [ -n "$line" ]; then
      wearer_ent="$(echo "$line" | awk '{print $2}')"
      for i in 3 4 5; do
        spacetime call "$DB" admin_give_item "$wearer_ent" "$(echo "$line" | awk -v n=$i '{print $n}')" 1 0 >/dev/null 2>&1
      done
      given="yes"
      echo "   gave entity $wearer_ent three pieces of armor"
    fi
  fi
  if [ -z "$watch_pid" ] && grep -q '^WORN' "$wear_log"; then
    echo "== the watcher, after the wearer put them on =="
    timeout 140 "$GODOT" --headless --path . "$SCENE" -- --token=armorwatcher --role=watcher --wearer="$wearer_ent" \
      --signal="$signal_path" --latency="$LATENCY" --jitter="$JITTER" >"$watch_log" 2>&1 &
    watch_pid=$!
  fi
  if [ -z "$seen" ] && grep -q '^SEEN' "$watch_log"; then echo "SEEN" >> "$signal"; seen="yes"; fi
  if [ -z "$done_w" ] && grep -q '^WATCHER_DONE' "$watch_log"; then echo "WATCHER_DONE" >> "$signal"; done_w="yes"; fi
  sleep 0.3
done
wait "$wear_pid"; status=$?; wear_pid=""
wstatus=1
if [ -n "$watch_pid" ]; then wait "$watch_pid"; wstatus=$?; watch_pid=""; else echo "  FAIL: the watcher never started (no WORN)" >&2; fi
[ "$wstatus" -eq 0 ] || status=1
for log in "$wear_log" "$watch_log"; do
  grep -E "^   |FAIL|passed," "$log"
  if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
    echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$log" | head -12 >&2; status=1
  fi
done
echo "-- the server's own word"
worn="$(spacetime sql "$DB" "SELECT head_item, chest_item, legs_item FROM worn WHERE entity_id = ${wearer_ent:-0}" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ')"
if [ "$worn" = "40078|0|40083" ]; then echo "   ok: the wearer's worn row: the armet and the trousers, the chest off"; else echo "  FAIL: the wearer's worn row: '$worn'" >&2; status=1; fi
exit "$status"
