#!/usr/bin/env bash
# THE LOAD TEST (DECISIONS #284): steps of bot players (50, then 100, then 300: shared/load.json) on the
# TEST database, each a real connection playing as a guest, walking from cell to cell under ring interest
# with the world's referee running, measured step by step until a limit breaks. What it measures and why:
# tools/load/load_test.py; the bots: tools/load/bots.py; how to read it: docs/HANDBOOK.md, "The load test".
#
#   tools\run.cmd tests\load_test.sh            (Windows; about 20 minutes)
#   GODOT=<path> ./tests/load_test.sh
#   STEPS=50,100 MEASURE=30 ./tests/load_test.sh     other steps, a shorter window
#   NEGATIVE=0 ./tests/load_test.sh                  without the two negative runs at the end
#   LOAD=big ./tests/load_test.sh                    a game's other load config: shared/<genre>/load_big.json
#   REFEREES=3x2 ./tests/load_test.sh                that many region referees (columns x rows)
#   WATCH=0 PLAYER=1 STEPS=300 ./tests/load_test.sh  then keep the bots playing (0: until Ctrl+C; or seconds)
#                                                    and open a game window on the test database to join them
#
# Exit 0: the harness worked and every step held. 2: the harness worked and a step broke (where, and the
# numbers, are in build/load/ring/report.md). 1: the harness itself failed, or a negative run did not.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
OUT=build/load
mkdir -p "$OUT"
ref_pids=""
cleanup() {
  for p in $ref_pids; do kill "$p" 2>/dev/null; done
  wait 2>/dev/null
}
trap cleanup EXIT

echo "== the load test's own parts (no server) =="
unit="$("$PYTHON" -m unittest tests/load/test_load.py 2>&1)" || { echo "$unit" | tail -30 >&2; exit 1; }
echo "$unit" | tail -1

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

# The level world 0 plays on: shared/load.json "level", a game's own shared/<genre>/load.json over it.
LEVEL="$("$PYTHON" -c "import sys; sys.path.insert(0, 'tools/load'); import load_test; print(int(load_test.load_config().get('level', 0)))")"   || { echo "could not read the level from shared/load.json" >&2; exit 1; }

fresh() {
  (cd server && spacetime publish "$DB" --server local --delete-data --yes) >"$OUT/publish.log" 2>&1 \
    || { echo "publish failed ($OUT/publish.log)" >&2; tail -20 "$OUT/publish.log" >&2; exit 1; }
  spacetime call "$DB" set_world_level 0 "$LEVEL" >/dev/null 2>&1 || { echo "set_world_level 0 $LEVEL failed" >&2; exit 1; }
  # The bots spread across the area with the dev tools' teleport (as players who logged out there would be).
  spacetime call "$DB" set_dev_tools true >/dev/null 2>&1
  # The referee reports how it ran every 10 s instead of 30, so a step's window holds several reports.
  spacetime call "$DB" set_rule '"foundation.telemetry_window_s"' 10 '""' >/dev/null 2>&1
}

echo "== $DB, fresh, world 0 on level $LEVEL =="
fresh
echo "== what a real client of this game asks for =="
for mode in ring world; do
  "$GODOT" --headless --path . res://tools/load/interest_dump.tscn -- "--out=$OUT/interest_$mode.json" "--interest=$mode" \
    >"$OUT/interest_$mode.log" 2>&1
  grep "interest_dump:" "$OUT/interest_$mode.log" || { echo "the interest dump failed:" >&2; tail -20 "$OUT/interest_$mode.log" >&2; exit 1; }
done

# REGION REFEREES (DECISIONS #288): shared/load.json "referees" [columns, rows] (or REFEREES=2x2) cuts the bots'
# square into that many regions, a referee each; [1, 1] is one referee for the whole world. Bots spread over a
# whole level ("spread": "level", template 1.5) are cut where they live, an equal share of them to each.
REGIONS="$("$PYTHON" -c "import sys; sys.path.insert(0, 'tools/load'); import load_test as L; c = L.load_config(); s = sys.argv[1].split('x') if sys.argv[1] else c.get('referees', [1, 1]); n = max(int(x) for x in (sys.argv[2] or ','.join(str(v) for v in c['steps'])).split(',') if x.strip()); print(' '.join(L.region_args(c, s, n)))" "${REFEREES:-}" "${STEPS:-}")" \
  || { echo "could not read the referees from shared/load.json" >&2; exit 1; }
ref_logs=()
start_referee() {   # start_referee LOG OFFER_REDUCER [REGION NAME]
  local code="load$(date +%s)$RANDOM"
  spacetime call "$DB" "$2" 0 "\"$code\"" >/dev/null 2>&1 || { echo "$2 failed" >&2; exit 1; }
  local extra=""
  [ -n "${3:-}" ] && extra="--region=$3 --name=$4"
  # shellcheck disable=SC2086
  "$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --claim="$code" --no-record $extra \
    >"$1" 2>&1 &
  ref_pids="$ref_pids $!"
  ref_logs+=(--referee-log "$1")
  for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$1" && break; sleep 0.5; done
  grep -q "claim_referee: registered" "$1" || { echo "the referee did not register:" >&2; tail -20 "$1" >&2; exit 1; }
}
if [ -z "$REGIONS" ]; then
  echo "== the world's referee =="
  start_referee "$OUT/referee.log" offer_referee
else
  echo "== the world's referees, a region each: $REGIONS =="
  i=0
  for r in $REGIONS; do
    start_referee "$OUT/referee_$i.log" "$([ "$i" = 0 ] && echo offer_referee || echo offer_region_referee)" "$r" "load_r$i"
    i=$((i + 1))
  done
fi
echo "ok"

# A PERSON JOINS THE BOTS (template 1.5): PLAYER=1 opens this game in a window on the test database (its own
# identity, `--token=watch`), to walk among them while WATCH keeps them playing. Close it when done.
if [ "${PLAYER:-0}" = "1" ]; then
  echo "== a game window for you on $DB (press Play, walk among the bots) =="
  "$GODOT" --path . -- --db="$DB" --token=watch >"$OUT/player.log" 2>&1 &
  ref_pids="$ref_pids $!"
fi

LABEL="${LABEL:-ring}"
echo "== the steps =="
"$PYTHON" tools/load/load_test.py --db "$DB" --interest "$OUT/interest_ring.json" --label "$LABEL" \
  ${STEPS:+--steps "$STEPS"} ${MEASURE:+--measure "$MEASURE"} ${WATCH:+--watch "$WATCH"} ${ref_logs[@]+"${ref_logs[@]}"}
status=$?
for p in $ref_pids; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
ref_pids=""
[ "$status" = "1" ] && { echo "THE HARNESS FAILED: build/load/$LABEL/report.md" >&2; exit 1; }

if [ "${NEGATIVE:-1}" != "0" ]; then
  neg_fail=0
  echo "== negative: a limit nothing can meet is reported broken =="
  fresh
  "$PYTHON" tools/load/load_test.py --db "$DB" --interest "$OUT/interest_ring.json" --label negative_limit \
    --steps 20 --settle 5 --measure 15 --no-referee --limit input_ack_p95_ms=0.001 >"$OUT/negative_limit.log" 2>&1
  neg=$?
  if [ "$neg" = "2" ] && grep -q "RESULT BREAKS_AT 20" "$OUT/negative_limit.log"; then echo "ok: it breaks at 20 bots"
  else echo "FAIL: a limit of 0.001 ms was not reported broken (exit $neg, $OUT/negative_limit.log)" >&2; neg_fail=1; fi

  echo "== negative: bots asking for the whole world are sent far more than a ring =="
  for mode in ring world; do
    fresh
    "$PYTHON" tools/load/load_test.py --db "$DB" --interest "$OUT/interest_$mode.json" --label "compare_$mode" \
      --steps 50 --settle 10 --measure 20 --no-referee >"$OUT/compare_$mode.log" 2>&1
  done
  if "$PYTHON" - "$OUT" <<'EOF'
import json, sys
out = sys.argv[1]
r = json.load(open(out + "/compare_ring/report.json"))["steps"][0]["bots"]
w = json.load(open(out + "/compare_world/report.json"))["steps"][0]["bots"]
rr, wr = r["client_rows_per_s"]["mean"], w["client_rows_per_s"]["mean"]
rs, ws = r["neighbours_seen"]["mean"], w["neighbours_seen"]["mean"]
print("   rows a second a client: ring %.0f, world %.0f; others seen: ring %.1f, world %.1f" % (rr, wr, rs, ws))
sys.exit(0 if rr < 0.5 * wr and rs < ws else 1)
EOF
  then echo "ok"; else echo "FAIL: the ring's bots were not sent clearly less than the world's" >&2; neg_fail=1; fi
  [ "$neg_fail" = "0" ] || exit 1
fi

echo
grep "^\*\*Verdict" "build/load/$LABEL/report.md"
exit "$status"
