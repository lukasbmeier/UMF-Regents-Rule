#!/usr/bin/env bash
# HOW MANY REFEREES DOES THIS WORLD NEED? (template 1.5): the load test (tests/load_test.sh) run once for each
# way of cutting the world into region referees, at one crowd, on the TEST database, then one table: each
# cut's worst referee, what the referees cost this machine (cores, memory), whether the step held, and the
# fewest referees that held with room to spare. Each run is a whole load test step: about 4 minutes each.
#
#   tools\run.cmd tests\referee_sweep.sh                                   (Windows)
#   GRIDS="1x1 2x2 3x3" STEPS=300 ./tests/referee_sweep.sh               other cuts (rows too: dearer for the server)
#   LOAD=expanse GRIDS="2x2 3x2 4x3" ./tests/referee_sweep.sh               a game's other load config
#
# "Holds": every limit of shared/load.json held. "With room": the worst referee's frame p95 is at most half its
# limit (a referee at 45 of 50 ms holds today and breaks with the next camp). Results: build/load/sweep.md.
# Exit 0: the sweep ran (whatever it found); 1: a run's harness failed.
set -uo pipefail
cd "$(dirname "$0")/.."
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
# Strips by default (1.6.3): a region as tall as the level asks the server for one range a table, a region cut
# across it a range a column, which the server checks every moved row against (DECISIONS #297).
GRIDS="${GRIDS:-1x1 2x1 3x1 4x1 6x1}"
STEPS="${STEPS:-$("$PYTHON" -c "import sys; sys.path.insert(0, 'tools/load'); import load_test as L; print(max(L.load_config()['steps']))")}"
labels=""
for g in $GRIDS; do
  echo "=================== $g referees, $STEPS bots ==================="
  LABEL="sweep_$g" REFEREES="$g" STEPS="$STEPS" NEGATIVE=0 ./tests/load_test.sh
  status=$?
  [ "$status" = "1" ] && { echo "the run with $g referees failed (build/load/sweep_$g/report.md)" >&2; exit 1; }
  labels="$labels sweep_$g"
done
"$PYTHON" tools/load/sweep_report.py $labels
