#!/usr/bin/env bash
# A FOE GOES ROUND A ROCK, ON A REAL REFEREE (Luke's play, 2026-11-03, #8196: "Sparring skeleton walks right
# through the copper mine ore"; template 1.7.2, DECISIONS #304). The world's referee with Regent's own say
# (`sidecar/genres/regents.gd`, loaded as every game's referee loads it) in the glade: a bot patrols to and
# fro along z = 14, east to west, straight through copper rock 20 at (23, 14) (the other rocks 3.6 m or more
# off its lane):
#   - standing, the rock is a wall in the referee's walk map: the bot crosses the rock's line (x = 23) well
#     off its lane, round the rock, both ways, and reaches each end
#   - worked out (Depleted: the node's Blocks In is Normal only), the wall is let down, the map baked again,
#     and the bot walks straight through where the rock stood: the negative (the same lane, nothing else in
#     its way)
#
#   GODOT=<path> ./game/regents/tests/walls_playtest.sh     (Windows: tools\run.cmd game\regents\tests\walls_playtest.sh)
#
# Requires a local server (`spacetime start`). Publishes the TEST database with --delete-data.
# WALLS_LOG=<file>: keep the referee's log there.
set -uo pipefail
cd "$(dirname "$0")/../../.."
GODOT="${GODOT:-godot}"
. tests/lib/db.sh

passes=0
failures=0
pass() { passes=$((passes + 1)); }
fail() { failures=$((failures + 1)); echo "  FAIL: $1" >&2; }
check() { if [ "$1" = "true" ]; then pass; else fail "$2"; fi }
sql_rows() { spacetime sql "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d'; }
sql_first() { sql_rows "$1" | head -1 | awk -v c="$2" -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $c); print $c}'; }
call() { spacetime call "$DB" "$@" 2>&1; }
assert_ok() { local out; out="$(call "$@")"; if echo "$out" | grep -qiE "^error|error:"; then fail "$1 ($(echo "$out" | tail -1))"; else pass; fi; }

log="${WALLS_LOG:-$(mktemp)}"; samples="$(mktemp)"; ref_pid=""
cleanup() {
  [ -n "$ref_pid" ] && kill "$ref_pid" 2>/dev/null
  wait 2>/dev/null
  [ -z "${WALLS_LOG:-}" ] && rm -f "$log"
  rm -f "$samples"
}
trap cleanup EXIT

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
sleep 3

# The glade (level 20): copper rock 20 at (23, 14). The lane: z = 14, from x = 31 (home) to x = 18 (far end).
ROCK=20; LANE_Z=14; ROCK_X=23; HOME_X=31; FAR_X=18
check "$([ "$(sql_first "SELECT def_id FROM gather_node WHERE entity_id = $ROCK" 1)" = "40004" ] && echo true || echo false)" \
  "entity $ROCK is a copper rock (the glade's layout this test is laid out in)"
rock_pos="$(sql_first "SELECT pos FROM movement_state WHERE entity_id = $ROCK" 1)"
check "$(echo "$rock_pos" | grep -qE "x = $ROCK_X, y = [-0-9.e]+, z = $LANE_Z\)" && echo true || echo false)" "and it stands at ($ROCK_X, $LANE_Z) ($rock_pos)"

echo "== a patrolling bot along the lane =="
SESS0="$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)"
assert_ok add_bot "$SESS0" 0 '"patrol"' "{\"x\":$HOME_X.0,\"y\":0.0,\"z\":$LANE_Z.0}"
BOT="$(sql_rows "SELECT entity_id FROM npc_brain WHERE brain = 'patrol'" | awk '{print $1}' | sort -n | tail -1)"
check "$([ -n "$BOT" ] && echo true || echo false)" "a bot ($BOT)"
assert_ok write_npc_brain "$BOT" '"patrol"' '"out"' 0 "\"{\\\"to\\\":[$FAR_X.0,0.0,$LANE_Z.0]}\""

echo "== the world's referee, with Regent's say =="
assert_ok offer_referee 0 '"regentswallsrefereecode"'
"$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee \
  --no-record --name=walls_playtest --claim=regentswallsrefereecode > "$log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 90); do grep -q "claim_referee: registered" "$log" && break; sleep 0.5; done
check "$(grep -q "claim_referee: registered" "$log" && echo true || echo false)" "the referee registered"
check "$(grep -q "a genre's say: res://sidecar/genres/regents.gd (its walls read gather_node, station)" "$log" && echo true || echo false)" \
  "it took Regent's say (sidecar/genres/regents.gd: nodes and stations)"
for _ in $(seq 1 30); do grep -q "is driven by brain 'patrol'" "$log" && break; sleep 0.5; done
check "$(grep -q "is driven by brain 'patrol'" "$log" && echo true || echo false)" "the bot patrols (its row's brain)"

# Samples "<ms> <entity> <x> <z>", a few a second.
sample() {
  sql_rows "SELECT entity_id, pos FROM movement_state WHERE entity_id = $BOT" | awk -F'|' -v t="$(date +%s%3N)" '{
      e = $1; gsub(/ /, "", e)
      x = $2; sub(/.*x = /, "", x); sub(/,.*/, "", x); z = $2; sub(/.*z = /, "", z); sub(/[ )].*/, "", z)
      print t, e, x, z }' >> "$samples"
}
# crossings SINCE_MS: "<n> <crossings> <min x> <max x>": each time the bot crossed the rock's line x = ROCK_X
# after SINCE_MS, how far off the lane it was there ("1.93:W"), and how far it got either way.
crossings() {
  python - "$samples" "$1" "$ROCK_X" "$LANE_Z" <<'PY'
import sys
path, since, line_x, lane = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
pts = []
for row in open(path):
    w = row.split()
    if len(w) == 4 and int(w[0]) >= since:
        pts.append((float(w[2]), float(w[3])))
out = []
for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
    if (x0 - line_x) * (x1 - line_x) < 0:
        f = (line_x - x0) / (x1 - x0)
        out.append("%.2f:%s" % (abs(z0 + (z1 - z0) * f - lane), "W" if x1 < x0 else "E"))
xs = [x for x, _ in pts]
print(len(out), ",".join(out) if out else "-", "%.2f" % (min(xs) if xs else 99), "%.2f" % (max(xs) if xs else -99))
PY
}
# watch SECONDS N: sample until the bot has crossed N times (or the time is up); the last look in $look.
watch() {
  local until=$(( $(date +%s) + $1 )); local since; since="$(date +%s%3N)"; local polls=0
  look=""
  while [ "$(date +%s)" -lt "$until" ]; do
    sample; polls=$((polls + 1))
    if [ $((polls % 6)) -eq 0 ]; then
      look="$(crossings "$since")"
      echo "   ... $look"
      [ "$(echo "$look" | awk '{print $1}')" -ge "$2" ] && return
    fi
    sleep 0.2
  done
  look="$(crossings "$since")"
}
# nearest CROSSINGS / furthest CROSSINGS: how far off the lane (-1: none).
nearest() { python -c "import sys; v=[float(c.split(':')[0]) for c in sys.argv[1].split(',') if ':' in c]; print('%.2f' % min(v) if v else -1)" "$1"; }
furthest() { python -c "import sys; v=[float(c.split(':')[0]) for c in sys.argv[1].split(',') if ':' in c]; print('%.2f' % max(v) if v else -1)" "$1"; }

for _ in $(seq 1 60); do grep -qE "a walk map for bodies .* [1-9][0-9]* wall boxes" "$log" && break; sleep 0.5; done
check "$(grep -qE "a walk map for bodies .* [1-9][0-9]* wall boxes" "$log" && echo true || echo false)" \
  "the referee's walk map was baked with the glade's walls in it ($(grep -oE "[0-9]+ wall boxes" "$log" | head -1))"

echo "== standing: the bot goes round the rock, both ways =="
watch 150 2
cross="$(echo "$look" | awk '{print $2}')"; minx="$(echo "$look" | awk '{print $3}')"; maxx="$(echo "$look" | awk '{print $4}')"
echo "   it crossed x = $ROCK_X this far off its lane: $cross (it reached x $minx to $maxx)"
check "$(echo "$cross" | grep -q 'W' && echo "$cross" | grep -q 'E' && echo true || echo false)" "it crossed the rock's line both ways ($cross)"
near="$(nearest "$cross")"
# The rock is 2.5 m or more across: a body going round passes 1.2 m or more off the rock's middle.
check "$(python -c "print('true' if $near >= 1.2 else 'false')")" "every time round the rock, never through it ($near m off the lane at the nearest)"
for _ in $(seq 1 60); do grep -q "entity $BOT's patrol reached its home end" "$log" && break; sleep 0.5; done
check "$(grep -q "entity $BOT's patrol reached its far end" "$log" && grep -q "entity $BOT's patrol reached its home end" "$log" && echo true || echo false)" \
  "and it reached the far side each way (its far end and home again)"

echo "== worked out: the rock's wall is let down, and the bot walks straight through =="
assert_ok set_status "$ROCK" 100 4294967295 '""'
for _ in $(seq 1 60); do grep -q "again (its walls changed)" "$log" && break; sleep 0.5; done
check "$(grep -q "again (its walls changed)" "$log" && echo true || echo false)" "its walk map was baked again (the wall let down)"
sleep 2
watch 120 2
cross2="$(echo "$look" | awk '{print $2}')"
far2="$(furthest "$cross2")"
echo "   it then crossed x = $ROCK_X this far off its lane: $cross2"
check "$(python -c "print('true' if 0 <= $far2 < 0.6 else 'false')")" \
  "down, it walks straight through where the rock stood ($far2 m off its lane at most): the negative"

if [ "$failures" -gt 0 ]; then
  echo "--- the referee's log (walls, walk maps, the bot) ---" >&2
  grep -E "walk map|genre|patrol|level|ERROR|SCRIPT|entity $BOT" "$log" | head -60 >&2
fi
echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
