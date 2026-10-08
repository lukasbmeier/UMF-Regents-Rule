#!/usr/bin/env bash
# What tools\run.cmd runs in Git Bash: this machine's settings (tools/local.env), then the script
# named first, with the rest of the arguments. Kept here because cmd cannot pass bash a command
# line with quotes or redirections in it.
cd "$(dirname "$0")/.."
if [ -f tools/local.env ]; then
  set -a
  eval "$(tr -d '\r' < tools/local.env)"
  set +a
fi
script="$1"
shift
exec bash "$script" "$@"
