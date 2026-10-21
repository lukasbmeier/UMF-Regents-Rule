#!/usr/bin/env bash
# THE TELEMETRY PAGE (DECISIONS #276): what happened in the game, kept by the chronicle, as charts in your
# browser (tools/telemetry/dashboard.py). Run it on the machine that hosts; it records too while it is open
# when nothing else does. tools\telemetry.cmd for a double-click.
set -uo pipefail
cd "$(dirname "$0")/.."
[ -f tools/local.env ] && . tools/local.env
PYTHON="${PYTHON:-python}"
exec "$PYTHON" tools/telemetry/dashboard.py "$@"
