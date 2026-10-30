#!/usr/bin/env bash
# HOW MANY REFEREES THE EXPANSE NEEDS FOR 300 PLAYERS (PROGRESS step 25): the template's referee sweep
# (tests/referee_sweep.sh) on the Skyrim-size world (LOAD=expanse): the load test once with each cut of the
# world into region referees, then one table, build/load/sweep.md: each cut's worst referee, the CPU cores and
# memory the referees took on this machine, and the fewest that held with room to spare. On the TEST database;
# about 4 to 5 minutes a cut.
#
#   tools\run.cmd game\regents\tests\expanse_referees.sh                         (1, 2, 4, 6 and 9 referees)
#   GRIDS="2x2 3x3 4x3" tools\run.cmd game\regents\tests\expanse_referees.sh     other cuts
#   STEPS=150 ...                                                                another crowd
set -uo pipefail
cd "$(dirname "$0")/../../.."
export LOAD=expanse
export GRIDS="${GRIDS:-1x1 2x1 2x2 3x2 3x3}"
exec ./tests/referee_sweep.sh
