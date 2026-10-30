#!/usr/bin/env bash
# 300 BOTS ON A SKYRIM-SIZE WORLD, AND YOU AMONG THEM (PROGRESS step 25): the load test on the expanse (level 22,
# shared/regents/load_expanse.json) on the TEST database, measured once, then the bots keep playing and a game
# window opens on that database for you: press Play (as a guest) and walk among them. You start at the camp,
# where a fifth of them live; the rest are spread over the world's 37 km2, the region referees running the
# skeletons near them. A line every 10 s says how the server and each referee are doing.
#
#   tools\run.cmd game\regents\tests\expanse_watch.sh                 (Windows; Ctrl+C in this window to stop)
#   REFEREES=3x2 tools\run.cmd game\regents\tests\expanse_watch.sh    with six referees instead of four
#   STEPS=150 WATCH=900 tools\run.cmd game\regents\tests\expanse_watch.sh   150 bots, for 15 minutes
#   PLAYER=0 ...                                                       no game window (watch the numbers only)
#
# The measured step is build/load/expanse/report.md. Nothing touches the database you play in (regents-rule).
set -uo pipefail
cd "$(dirname "$0")/../../.."
export LOAD=expanse
export LABEL="${LABEL:-expanse}"
export WATCH="${WATCH:-0}"
export PLAYER="${PLAYER:-1}"
export NEGATIVE=0
exec ./tests/load_test.sh
