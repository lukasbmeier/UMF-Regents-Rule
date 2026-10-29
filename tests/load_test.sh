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
ref_pid=""
cleanup() {
  [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null
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

fresh() {
  (cd server && spacetime publish "$DB" --server local --delete-data --yes) >"$OUT/publish.log" 2>&1 \
    || { echo "publish failed ($OUT/publish.log)" >&2; tail -20 "$OUT/publish.log" >&2; exit 1; }
  spacetime call "$DB" set_world_level 0 0 >/dev/null 2>&1
  # The bots spread across the area with the dev tools' teleport (as players who logged out there would be).
  spacetime call "$DB" set_dev_tools true >/dev/null 2>&1
  # The referee reports how it ran every 10 s instead of 30, so a step's window holds several reports.
  spacetime call "$DB" set_rule '"foundation.telemetry_window_s"' 10 '""' >/dev/null 2>&1
}

echo "== $DB, fresh =="
fresh
echo "== what a real client of this game asks for =="
for mode in ring world; do
  "$GODOT" --headless --path . res://tools/load/interest_dump.tscn -- "--out=$OUT/interest_$mode.json" "--interest=$mode" \
    >"$OUT/interest_$mode.log" 2>&1
  grep "interest_dump:" "$OUT/interest_$mode.log" || { echo "the interest dump failed:" >&2; tail -20 "$OUT/interest_$mode.log" >&2; exit 1; }
done

echo "== the world's referee =="
CODE="\"load$(date +%s)$RANDOM\""
spacetime call "$DB" offer_referee 0 "$CODE" >/dev/null 2>&1 || { echo "offer_referee failed" >&2; exit 1; }
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee --claim="${CODE//\"/}" --no-record \
  >"$OUT/referee.log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$OUT/referee.log" && break; sleep 0.5; done
grep -q "claim_referee: registered" "$OUT/referee.log" || { echo "the referee did not register:" >&2; tail -20 "$OUT/referee.log" >&2; exit 1; }
echo "ok"

echo "== the steps =="
"$PYTHON" tools/load/load_test.py --db "$DB" --interest "$OUT/interest_ring.json" --label ring \
  ${STEPS:+--steps "$STEPS"} ${MEASURE:+--measure "$MEASURE"}
status=$?
kill "$ref_pid" 2>/dev/null
wait "$ref_pid" 2>/dev/null
ref_pid=""
[ "$status" = "1" ] && { echo "THE HARNESS FAILED: build/load/ring/report.md" >&2; exit 1; }

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
grep "^\*\*Verdict" build/load/ring/report.md
exit "$status"
