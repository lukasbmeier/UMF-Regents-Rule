#!/usr/bin/env bash
# ANOTHER PLAYER'S SPELL, SEEN (Luke, 2026-11-15: "yes, add it", PROGRESS 83): two real clients at a simulated round
# trip in the frontier glade. The caster casts Gale alone; the watcher comes in after (that row is history: nothing
# shows); the caster casts again (the watcher sees the gust where the caster stood, the way they aimed) and once more
# while it cools (refused: nothing). No referee: Gale needs none.
#   GRANT_STAFF <entity>  the caster asks: a yew staff, at level 5, Sorcery 10 (a fresh character's is 1), then
#                          STAFF_READY in the signal file
#   GALE_1                the caster's first Gale: the watcher starts a few seconds later
#   WATCHING, GALE_REFUSED, WATCHER_DONE  passed on to the other client through the signal file
#
#   GODOT=/path/to/godot ./game/regents/tests/spells_seen_playtest.sh     # 150 ms round trip, 20 ms jitter (~2 min)
#
# Requires a local server (`spacetime start`). Republishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/../../.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
LATENCY="${LATENCY:-150}"
JITTER="${JITTER:-20}"
SCENE="res://game/regents/tests/playtest/spells_seen_playtest.tscn"
SORCERY=40009
STAFF=40023

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1 || { echo "set_dev_tools failed" >&2; exit 1; }   # the clients step about
sleep 2

cast_log="$(mktemp)"; watch_log="$(mktemp)"; signal="$(mktemp)"; cast_pid=""; watch_pid=""
cleanup() { [ -n "$cast_pid" ] && kill "$cast_pid" 2>/dev/null; [ -n "$watch_pid" ] && kill "$watch_pid" 2>/dev/null; wait 2>/dev/null
  rm -f "$cast_log" "$watch_log" "$signal"; }
trap cleanup EXIT
: > "$signal"
# The signal file as Godot reads it (a Windows path under Git Bash).
signal_path="$(cygpath -m "$signal" 2>/dev/null || echo "$signal")"

echo "== the caster at ${LATENCY} ms round trip, ${JITTER} ms jitter =="
timeout 160 "$GODOT" --headless --path . "$SCENE" -- --token=spellcaster --role=caster --signal="$signal_path" \
  --latency="$LATENCY" --jitter="$JITTER" >"$cast_log" 2>&1 &
cast_pid=$!
staffed=""; watching=""; refused=""; done_w=""; caster_ent=""
while kill -0 "$cast_pid" 2>/dev/null || { [ -n "$watch_pid" ] && kill -0 "$watch_pid" 2>/dev/null; }; do
  if [ -z "$staffed" ]; then
    caster_ent="$(grep -oE '^GRANT_STAFF [0-9]+' "$cast_log" | head -1 | awk '{print $2}')"
    if [ -n "$caster_ent" ]; then
      spacetime call "$DB" grant_item "$caster_ent" "$STAFF" 1 >/dev/null 2>&1
      row="$(spacetime sql "$DB" "SELECT id FROM inventory_item WHERE owner_entity_id = $caster_ent AND item_def_id = $STAFF" 2>/dev/null | tail -n +3 | head -1 | tr -d ' \r')"
      spacetime call "$DB" admin_set_item_level "$caster_ent" "$row" 5 >/dev/null 2>&1
      spacetime call "$DB" admin_set_rank "$caster_ent" "$SORCERY" 10 >/dev/null 2>&1
      echo "STAFF_READY" >> "$signal"
      staffed="yes"
      echo "   gave entity $caster_ent a yew staff (row $row) at level 5, Sorcery 10"
    fi
  fi
  if [ -z "$watch_pid" ] && grep -q '^GALE_1' "$cast_log"; then
    sleep 3   # the first Gale's row is history by the time the watcher sees it
    echo "== the watcher, after the caster's first Gale =="
    timeout 140 "$GODOT" --headless --path . "$SCENE" -- --token=spellwatcher --role=watcher --caster="$caster_ent" \
      --signal="$signal_path" --latency="$LATENCY" --jitter="$JITTER" >"$watch_log" 2>&1 &
    watch_pid=$!
  fi
  if [ -z "$watching" ] && grep -q '^WATCHING' "$watch_log"; then echo "WATCHING" >> "$signal"; watching="yes"; fi
  if [ -z "$refused" ] && grep -q '^GALE_REFUSED' "$cast_log"; then
    landed_then="$(spacetime sql "$DB" "SELECT ability FROM spell_landed WHERE entity_id = $caster_ent" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ')"
    echo "GALE_REFUSED" >> "$signal"; refused="yes"
  fi
  if [ -z "$done_w" ] && grep -q '^WATCHER_DONE' "$watch_log"; then echo "WATCHER_DONE" >> "$signal"; done_w="yes"; fi
  sleep 0.3
done
wait "$cast_pid"; status=$?; cast_pid=""
wstatus=1
if [ -n "$watch_pid" ]; then wait "$watch_pid"; wstatus=$?; watch_pid=""; else echo "  FAIL: the watcher never started (no GALE_1)" >&2; fi
[ "$wstatus" -eq 0 ] || status=1
for log in "$cast_log" "$watch_log"; do
  grep -E "^   |FAIL|passed," "$log"
  if grep -E "SCRIPT ERROR" "$log" >/dev/null; then
    echo "VIOLATION: script errors:" >&2; grep -E "SCRIPT ERROR" -A3 "$log" | head -12 >&2; status=1
  fi
done
echo "-- the server's own word"
# While they played (read as the refused Gale was answered) the row said Gale; once the caster left it is gone.
if [ "${landed_then:-}" = "40016" ]; then echo "   ok: while they played, the caster's spell_landed row was their Gale (40016)"; else echo "  FAIL: the caster's spell_landed row while they played: '${landed_then:-}'" >&2; status=1; fi
gone="$(spacetime sql "$DB" "SELECT ability FROM spell_landed WHERE entity_id = ${caster_ent:-0}" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ')"
if [ -z "$gone" ]; then echo "   ok: the caster left: their spell_landed row went with them"; else echo "  FAIL: the caster left, their spell_landed row stayed: '$gone'" >&2; status=1; fi
exit "$status"
