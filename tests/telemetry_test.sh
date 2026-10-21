#!/usr/bin/env bash
# THE CHRONICLE AND THE TELEMETRY PAGE ON A REAL SERVER (DECISIONS #276). The module notes where every
# online player is every `foundation.telemetry_where_s` seconds (and not when they are offline, and not
# at all at 0); the chronicle, subscribed as the owner, keeps every change (an insert, an update with what
# it was, the private tables too), each place at the server's time, and nothing of the tables it skips;
# a second chronicle stays out; a dropped subscription comes back as a new run; the page serves every
# panel, the chat said and an error for a panel that is not there. Its own rules without a server first
# (tests/telemetry/test_chronicle.py).
#
#   ./tests/telemetry_test.sh     (the server is needed; Godot is not)
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
passes=0; failures=0
check() { if [ "$1" = "true" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $2" >&2; fi }

echo "== the chronicle's own rules =="
if "$PYTHON" -m unittest tests/telemetry/test_chronicle.py >/dev/null 2>&1; then check true ""; else
  "$PYTHON" -m unittest tests/telemetry/test_chronicle.py 2>&1 | tail -20 >&2; check false "tests/telemetry/test_chronicle.py"; fi

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
work="$(mktemp -d)"
FILE="$work/chronicle.sqlite"
pids=()
cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  # The CLI's subscriptions are children of a launcher: end any this suite left.
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -c "Get-CimInstance Win32_Process | ? { \$_.CommandLine -like '*subscribe $DB *' } | % { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
  else
    pkill -f "subscribe $DB " 2>/dev/null
  fi
  rm -rf "$work"
}
trap cleanup EXIT
q() { "$PYTHON" -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); r=c.execute(sys.argv[2]).fetchone(); print('' if r is None or r[0] is None else r[0])" "$FILE" "$1"; }
sql_n() { spacetime sql "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ' | head -1; }
# The CLI's player is online only while a connection of its is open: hold one for $1 seconds.
hold_online() { spacetime subscribe "$DB" "SELECT * FROM world_level" -t "$1" -y >/dev/null 2>&1 || true; }

echo "== publish (fresh data), notes every 2 s =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "the module publishes"
spacetime call "$DB" set_rule foundation.telemetry_where_s 2.0 '""' >/dev/null 2>&1
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1
spacetime call "$DB" set_player_name '"Tess"' >/dev/null 2>&1

echo "== the chronicle records =="
UMF_DB="$DB" "$PYTHON" tools/telemetry/chronicle.py --file "$FILE" --for 90 > "$work/chronicle.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 30); do grep -q "recording" "$work/chronicle.log" 2>/dev/null && break; sleep 1; done
check "$(grep -q "recording $DB" "$work/chronicle.log" && echo true || echo false)" "it starts ($(head -c 300 "$work/chronicle.log"))"
UMF_DB="$DB" "$PYTHON" tools/telemetry/chronicle.py --file "$FILE" --for 5 > "$work/second.log" 2>&1
check "$(grep -q "already being recorded" "$work/second.log" && echo true || echo false)" "a second chronicle of the same file stays out"
sleep 2
check "$([ "$(q "SELECT COUNT(*) FROM change WHERE op = 'have' AND tbl = 'hot_rule'")" -ge 20 ] && echo true || echo false)" \
  "what there was when it connected is kept (hot rules: $(q "SELECT COUNT(*) FROM change WHERE op = 'have' AND tbl = 'hot_rule'"))"
check "$([ "$(q "SELECT tool FROM player_name WHERE name = 'Tess'")" = "0" ] && echo true || echo false)" "the CLI's player, named, is a player in the names"

spacetime call "$DB" teleport '{"x":12.0,"y":1.0,"z":-7.0}' >/dev/null 2>&1
spacetime call "$DB" send_chat '"kept for looking back"' >/dev/null 2>&1
spacetime call "$DB" set_player_name '"Tessa"' >/dev/null 2>&1
before_hold="$("$PYTHON" -c "import time; print(time.time())")"
hold_online 8
after_hold="$("$PYTHON" -c "import time; print(time.time())")"
sleep 5   # the next note finds them offline; the one after notes nothing
sleep 2
check "$([ "$(q "SELECT json_extract(row, '\$.text') FROM change WHERE tbl = 'chat_message' AND op = 'insert'")" = "kept for looking back" ] && echo true || echo false)" \
  "a line said is an insert, its words kept"
check "$([ "$(q "SELECT json_extract(old, '\$.name') || '>' || json_extract(row, '\$.name') FROM change WHERE tbl = 'player' AND op = 'update' AND json_extract(old, '\$.name') IS NOT NULL")" = "Tess>Tessa" ] && echo true || echo false)" \
  "a rename is an update that says what it was ($(q "SELECT old FROM change WHERE tbl = 'player' AND op = 'update' AND json_extract(old, '\$.name') IS NOT NULL"))"
check "$([ "$(q "SELECT COUNT(*) FROM change WHERE tbl = 'feedback' OR tbl = 'perf_report'")" = "0" ] && [ "$(q "SELECT COUNT(*) FROM change WHERE tbl IN ('movement_state', 'tick_schedule', 'input_queue')")" = "0" ] && echo true || echo false)" \
  "nothing of what it skips (steps, schedules)"
n_at="$(q "SELECT COUNT(*) FROM position WHERE ABS(x - 12.0) < 0.01 AND ABS(z + 7.0) < 0.01")"
check "$([ "$n_at" -ge 3 ] && [ "$n_at" -le 6 ] && echo true || echo false)" "while online, noted where they stood every 2 s ($n_at notes in 8 s)"
gap="$(q "SELECT MIN(b.at - a.at) FROM position a JOIN position b ON b.rowid = a.rowid + 1")"
check "$("$PYTHON" -c "print('true' if 1.4 <= float('${gap:-0}') <= 2.6 else 'false')")" "two notes are the rule's 2 s apart, by the server's clock ($gap)"
late="$(q "SELECT COUNT(*) FROM position WHERE at > $after_hold + 3")"
check "$([ "$late" = "0" ] && echo true || echo false)" "offline, not noted ($late after they left)"
check "$([ "$(sql_n "SELECT COUNT(*) AS n FROM where_sample")" = "0" ] && echo true || echo false)" "and their note is gone from the database"

echo "== a dropped subscription comes back as a new run =="
if command -v powershell >/dev/null 2>&1; then
  powershell -NoProfile -c "Get-CimInstance Win32_Process | ? { \$_.Name -like 'spacetimedb-cli*' -and \$_.CommandLine -like '*subscribe $DB *SELECT * FROM chat_message*' } | % { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
else
  pkill -f "subscribe $DB .*chat_message" 2>/dev/null
fi
for _ in $(seq 1 20); do [ "$(q "SELECT COUNT(*) FROM run")" -ge 2 ] && break; sleep 1; done
check "$([ "$(q "SELECT COUNT(*) FROM run")" -ge 2 ] && [ -n "$(q "SELECT ended FROM run WHERE id = 1")" ] && echo true || echo false)" \
  "a second run, the first ended ($(q "SELECT COUNT(*) FROM run") runs)"
spacetime call "$DB" send_chat '"after the gap"' >/dev/null 2>&1
sleep 2
check "$([ "$(q "SELECT COUNT(*) FROM change WHERE tbl = 'chat_message' AND op = 'insert' AND run = 2")" = "1" ] && echo true || echo false)" "and records on"

echo "== the hot rule at 0 notes nothing =="
spacetime call "$DB" set_rule foundation.telemetry_where_s 0.0 '""' >/dev/null 2>&1
hold_online 5
check "$([ "$(sql_n "SELECT COUNT(*) AS n FROM where_sample")" = "0" ] && echo true || echo false)" "online, but the rule is 0: no note"

echo "== the page =="
"$PYTHON" tools/telemetry/dashboard.py --file "$FILE" --port 8799 --no-open --no-record > "$work/page.log" 2>&1 &
pids+=($!)
for _ in $(seq 1 20); do curl -s -m 1 -o /dev/null http://127.0.0.1:8799/api/status && break; sleep 0.5; done
page="$(curl -s -m 5 http://127.0.0.1:8799/)"
check "$(echo "$page" | grep -q "<title>Telemetry</title>" && echo true || echo false)" "the page is served"
panels="$(curl -s -m 5 http://127.0.0.1:8799/api/panels)"
bad=""
for id in $(echo "$panels" | "$PYTHON" -c "import json,sys; print(' '.join(p['id'] for p in json.load(sys.stdin)))"); do
  out="$(curl -s -m 10 "http://127.0.0.1:8799/api/panel?id=$id&range=hour")"
  echo "$out" | grep -q '"error"' && bad="$bad $id"
done
check "$([ -n "$panels" ] && [ -z "$bad" ] && echo true || echo false)" "every panel answers for the last hour (failed:${bad:- none})"
chat="$(curl -s -m 5 "http://127.0.0.1:8799/api/panel?id=chat&range=hour")"
check "$(echo "$chat" | grep -q "kept for looking back" && echo "$chat" | grep -q "Tessa" && echo true || echo false)" "the chat panel shows what was said, and who by"
who="$(curl -s -m 5 "http://127.0.0.1:8799/api/panel?id=where&range=hour")"
check "$(echo "$who" | "$PYTHON" -c "import json,sys; r=json.load(sys.stdin)['rows']; print('true' if any(x == 12 and z == -8 for _, x, z, _ in r) else 'false')")"   "the heatmap has where they stood, in its 4 m square (x 12..16, z -8..-4: -7 floors to -8, not 0's way) ($(echo "$who" | head -c 160))"
none="$(curl -s -m 5 "http://127.0.0.1:8799/api/panel?id=no_such_panel")"
check "$(echo "$none" | grep -q '"error"' && echo true || echo false)" "a panel that is not there is an error, not a crash"

echo
echo "telemetry: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
