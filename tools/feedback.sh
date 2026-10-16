#!/usr/bin/env bash
# WHAT THE PLAYERS SAID, AND HOW THE GAME RAN FOR THEM (DECISIONS #244): tools/feedback.py on this
# machine's server (run it where you host). tools\feedback.cmd for a double-click.
#
#   ./tools/feedback.sh [--hours N] [--limit N] [--db NAME]
set -uo pipefail
cd "$(dirname "$0")/.."
PYTHON="${PYTHON:-python}"
"$PYTHON" tools/feedback.py "$@"
