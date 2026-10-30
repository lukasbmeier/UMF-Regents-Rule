#!/usr/bin/env bash
# REGENT'S RULE'S LOAD TEST (RULE_DESIGN.md §15, `load_300.sh`; the foundation's tests/load_test.sh, DECISIONS
# #284): bot players in steps (50, 100, 200, 300: shared/regents/load.json) on the CONTINENT (level 21), each a
# real guest connection walking cell to cell with the world's referee running its skeletons, and playing as a
# player does besides (game/regents/load_bot.py): every bot wields its Copper axe; every third swings its
# combo (judged by the referee), the next gathers trees and copper rocks AFK, the next only walks.
# Then THIS GAME'S CHECKS on each step: the bots really played (swings, gathers, nodes seen, every second of
# the window), and the referee judged swings. A negative run at the end: a report with no gathering in it
# fails these checks.
#
#   tools\run.cmd game\regents\tests\load_300.sh                  (Windows; ~25 minutes)
#   STEPS=50,100 MEASURE=30 tools\run.cmd game\regents\tests\load_300.sh
#   MEASURE=600 STEPS=300 ...                                      the design's nightly: 300 bots for 10 minutes
#
# Exit 0: every step held. 2: the game broke at a step (where, and the numbers: build/load/ring/report.md).
# 1: the harness failed, the bots did not play, or the negative run did not fail.
set -uo pipefail
cd "$(dirname "$0")/../../.."
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
REPORT=build/load/ring/report.json

# The game's checks on a report: each step's bots swung, gathered and said what they saw, every step.
check_play() {
  "$PYTHON" - "$1" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
bad = []
for s in r["steps"]:
    n, calls = s["bots_n"], s["bots"]["calls_per_s"]
    fighters = n // 3 + (1 if n % 3 > 0 else 0)
    swings = calls.get("use_ability_seen", 0.0)
    # A fighter swings two lights every 2.25 to 3.75 s: about 0.5 to 0.9 a second each.
    if swings < 0.3 * fighters:
        bad.append("%d bots: %.1f swings a second from %d fighters (at least %.1f)" % (n, swings, fighters, 0.3 * fighters))
    if calls.get("gather", 0.0) <= 0.0:
        bad.append("%d bots: nobody gathered" % n)
    if calls.get("saw_nodes", 0.0) <= 0.0:
        bad.append("%d bots: no node was seen" % n)
    played = s["bots"].get("refused_in_play", {})
    print("   %d bots: %.1f swings/s, %.2f gathers/s, %.2f work_stop/s; refused in play: %s" % (
        n, swings, calls.get("gather", 0.0), calls.get("work_stop", 0.0),
        ", ".join("%s x%d" % kv for kv in played.items()) or "none"))
for b in bad:
    print("   NOT PLAYED: " + b)
sys.exit(1 if bad else 0)
EOF
}

./tests/load_test.sh
status=$?
[ "$status" = "1" ] && { echo "THE HARNESS FAILED (above)" >&2; exit 1; }
[ -f "$REPORT" ] || { echo "no report at $REPORT" >&2; exit 1; }

echo "== Regent's Rule: the bots played =="
check_play "$REPORT" || { echo "FAIL: the bots did not play as the hook says" >&2; exit 1; }
echo "ok"

if [ "${NEGATIVE:-1}" != "0" ]; then
  echo "== negative: a report with no gathering in it fails the game's checks =="
  "$PYTHON" - "$REPORT" build/load/no_gather.json <<'EOF'
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
for s in r["steps"]:
    s["bots"]["calls_per_s"].pop("gather", None)
json.dump(r, open(sys.argv[2], "w", encoding="utf-8"))
EOF
  if check_play build/load/no_gather.json >/dev/null; then
    echo "FAIL: a report with no gathering passed the game's checks" >&2; exit 1
  fi
  echo "ok: it fails"
fi
exit "$status"
