#!/usr/bin/env bash
# THE DIFFICULTY READOUT (MINIGAMES_PREP.md §6): every node's and recipe's minigame round played by four simulated
# players (flawless, skilled, average, careless) on many seeds, and how their scores fall: the mean, the share of
# Fine and Masterwork parts (the anvil), the share that beats AFK (gathering, smelting). No server; about a minute.
# The same as T in the skilling lab, for every round at once.
#   GODOT=<path> ./game/regents/tests/minigame_readout.sh [ROUNDS]     (Windows: tools\run.cmd game\regents\tests\minigame_readout.sh)
set -uo pipefail
cd "$(dirname "$0")/../../.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . res://game/regents/tests/minigame_readout_cli.tscn -- --rounds="${1:-200}" 2>&1 \
	| grep -v "godot_ai\|^Godot Engine"
