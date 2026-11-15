#!/usr/bin/env bash
# THE SHOWCASE'S PICTURES AND FILMS (2026-11-15): what goes to the composers (and a trailer's first cut). Windowed, no
# server. Writes, under export/showcase/<date>/ (ignored by git):
#   stills/login.png, stills/vista_NN_<shot>.png, stills/battle_NN_<shot>.png    1920x1080
#   films/login.ogv (the front door, 40 s), films/vista_NN_<shot>.ogv, films/battle_NN_<shot>.ogv    1080p, 30 fps
#   index.txt                                                                    every file and the mood it plays in
# Godot's movie writer (Theora .ogv: VLC, Chrome and Firefox play it; Windows' own player does not). It records at
# the PROJECT's window size, never --resolution, so this writes a 1920x1080 override.cfg for the run and removes it
# after (and refuses to start if one is already there). A file written to the project stops a running playtest's
# referee: don't run this beside one.
#   GODOT=<path> ./game/regents/tests/showcase_render.sh [stills|films|all]   (Windows: tools\run.cmd game\regents\tests\showcase_render.sh)
# About 15 minutes for all; stills alone about 3.
set -uo pipefail
cd "$(dirname "$0")/../../.."
GODOT="${GODOT:-godot}"
WHAT="${1:-all}"
OUT="export/showcase/$(date +%Y-%m-%d)"
mkdir -p "$OUT/stills" "$OUT/films"
if [ -e override.cfg ]; then
	echo "override.cfg is already in the project: not touching it. Move it aside and run again." >&2
	exit 1
fi
cleanup() { rm -f override.cfg; }
trap cleanup EXIT INT TERM
printf '[display]\n\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\n' > override.cfg

quiet() { grep -v "godot_ai\|^Godot Engine\|^Vulkan\|^$\|Unreferenced static"; }

# Each lab's shots, in order: "<n> <title>" from its scene (the scene is the list a designer edits).
titles() {
	grep '^title = ' "game/regents/showcase/$1.tscn" | sed 's/^title = "\(.*\)"$/\1/'
}
slug() { echo "$1" | tr 'A-Z' 'a-z' | sed "s/[^a-z0-9]\+/_/g; s/^_//; s/_$//"; }

if [ "$WHAT" = "stills" ] || [ "$WHAT" = "all" ]; then
	echo "== stills"
	"$GODOT" --path . res://game/regents/tests/login_shot.tscn -- "$OUT/stills" 4 2>&1 | quiet
	for lab in vista battle; do
		tmp="$OUT/stills/.tmp_$lab"
		rm -rf "$tmp"
		"$GODOT" --path . "res://game/regents/showcase/${lab}_lab.tscn" -- stills "$tmp" 2>&1 | quiet
		for f in "$tmp"/*.png; do
			[ -e "$f" ] && mv "$f" "$OUT/stills/${lab}_$(basename "$f")"
		done
		rm -rf "$tmp"
	done
fi

if [ "$WHAT" = "films" ] || [ "$WHAT" = "all" ]; then
	echo "== films"
	"$GODOT" --path . --fixed-fps 30 --write-movie "$OUT/films/login.ogv" \
		res://game/regents/tests/login_shot.tscn -- "$OUT/films" 40 2>&1 | quiet
	rm -f "$OUT/films/login.png"
	for lab in vista battle; do
		n=0
		while IFS= read -r title; do
			n=$((n + 1))
			file="$OUT/films/${lab}_$(printf '%02d' "$n")_$(slug "$title").ogv"
			"$GODOT" --path . --fixed-fps 30 --write-movie "$file" \
				"res://game/regents/showcase/${lab}_lab.tscn" -- clip $((n - 1)) 2>&1 | quiet
		done < <(titles "${lab}_lab")
	done
fi

{
	echo "Regent's Rule: pictures and films for the music ($(date +%Y-%m-%d))."
	echo "Made in the game's engine with its own models and effects; no sound."
	echo
	echo "login        the title screen: the valley at dusk behind the sign-in form (main theme)"
	for lab in vista battle; do
		n=0
		while IFS= read -r title; do
			n=$((n + 1))
			mood=$(awk -v t="title = \"$title\"" '$0 == t {f=1} f && /^mood = / {print; exit}' "game/regents/showcase/${lab}_lab.tscn" \
				| sed 's/.*moods\/\(.*\)\.tres.*/\1/; s/.*mood_\([a-z]*\).*/\1/')
			printf '%-12s %s (%s)\n' "${lab}_$(printf '%02d' "$n")" "$title" "${mood:-?}"
		done < <(titles "${lab}_lab")
	done
} > "$OUT/index.txt"
echo "== done: $OUT"
ls -la "$OUT/stills" "$OUT/films" 2>/dev/null | grep -v "^total"
