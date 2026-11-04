#!/usr/bin/env bash
# WALLS A GENRE SIZES, ON A REAL REFEREE (DECISIONS #304; Regent's Rule's feedback #8196: "Sparring skeleton
# walks right through the copper mine ore"). Two resource nodes, ONE KIND, in the greybox. A test genre
# (tests/e2e/walls_genre.gd, handed to the referee with --referee-genre) gives the first a wall 4 m wide
# across a bot's way, and the second none. Two bots patrol to and fro across them (the `patrol` brain, its
# far end written into its memory):
#   - the first never passes through the wall's line where the wall is: it goes round its end and reaches
#     the far side, both ways (the wall is in the referee's space and in its walk map)
#   - the second walks straight through where its node stands (the negative: no wall given, none there)
#   - the first node worked out (status Out): its wall is let down, its walk map is baked again, and the
#     first bot then walks straight through where the wall was
#
#   GODOT=<path> ./tests/walls_test.sh        (Windows: tools\run.cmd tests\walls_test.sh)
#
# Requires a local server (`spacetime start`). Publishes the TEST database with --delete-data.
set -uo pipefail
cd "$(dirname "$0")/.."
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

# WALLS_LOG=<file>: keep the referee's log there.
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

# The greybox: a 40 m floor, walls at x = +-10. Lane A at x = -6, lane B at x = -2, both from z = 8 to z = -4;
# each node stands on its lane at z = 2.
LANE_A=-6; LANE_B=-2; NODE_Z=2
echo "== two resource nodes (one kind), two patrolling bots =="
assert_ok spawn_resource_node 0 "{\"x\":$LANE_A.0,\"y\":0.0,\"z\":$NODE_Z.0}"
assert_ok spawn_resource_node 0 "{\"x\":$LANE_B.0,\"y\":0.0,\"z\":$NODE_Z.0}"
NODES="$(sql_rows "SELECT entity_id FROM entity WHERE kind = 2" | awk '{print $1}' | sort -n)"
NODE_A="$(echo "$NODES" | head -1)"; NODE_B="$(echo "$NODES" | tail -1)"
check "$([ -n "$NODE_A" ] && [ -n "$NODE_B" ] && [ "$NODE_A" != "$NODE_B" ] && echo true || echo false)" "two nodes ($NODE_A, $NODE_B)"
SESS0="$(sql_first "SELECT id FROM session WHERE world_id = 0" 1)"
assert_ok add_bot "$SESS0" 0 '"patrol"' "{\"x\":$LANE_A.0,\"y\":0.0,\"z\":8.0}"
assert_ok add_bot "$SESS0" 0 '"patrol"' "{\"x\":$LANE_B.0,\"y\":0.0,\"z\":8.0}"
BOTS="$(sql_rows "SELECT entity_id FROM npc_brain WHERE brain = 'patrol'" | awk '{print $1}' | sort -n)"
BOT_A="$(echo "$BOTS" | head -1)"; BOT_B="$(echo "$BOTS" | tail -1)"
check "$([ -n "$BOT_A" ] && [ -n "$BOT_B" ] && [ "$BOT_A" != "$BOT_B" ] && echo true || echo false)" "two bots ($BOT_A, $BOT_B)"
# (Bots of the player's kind: a kind whose character names a brain (the NPC's `wander`) drives its bots by
# that one, whatever their row names.)
# Each one's far end: its memory, as a genre (or an admin) would set it.
# (A String argument is a JSON string: the memory's own JSON, quoted.)
assert_ok write_npc_brain "$BOT_A" '"patrol"' '"out"' 0 "\"{\\\"to\\\":[$LANE_A.0,0.0,-4.0]}\""
assert_ok write_npc_brain "$BOT_B" '"patrol"' '"out"' 0 "\"{\\\"to\\\":[$LANE_B.0,0.0,-4.0]}\""

echo "== a referee with the test genre: node $NODE_A walled 4 m wide, node $NODE_B not =="
assert_ok offer_referee 0 '"wallstestrefereecode"' 
UMF_TEST_WALLS="$NODE_A=4,2,0.6" "$GODOT" --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee \
  --no-record --name=walls_test --claim=wallstestrefereecode --referee-genre=res://tests/e2e/walls_genre.gd > "$log" 2>&1 &
ref_pid=$!
for _ in $(seq 1 60); do grep -q "claim_referee: registered" "$log" && break; sleep 0.5; done
check "$(grep -q "claim_referee: registered" "$log" && echo true || echo false)" "the referee registered"
check "$(grep -q "a genre's say: res://tests/e2e/walls_genre.gd (its walls read status_state)" "$log" && echo true || echo false)" \
  "it took the test genre's say (--referee-genre)"
check "$(grep -q "runs level" "$log" && echo false || echo true)" "it runs the greybox (this test's lanes are laid out in it)"
for _ in $(seq 1 20); do [ "$(grep -c "is driven by brain 'patrol'" "$log")" -ge 2 ] && break; sleep 0.5; done
check "$([ "$(grep -c "is driven by brain 'patrol'" "$log")" -ge 2 ] && echo true || echo false)" "both bots patrol (their rows' brain)"

# Samples: "<ms> <entity> <x> <z>", a few a second: one query, one awk (a subprocess a row was 5 s a look).
sample() {
  sql_rows "SELECT entity_id, pos FROM movement_state WHERE world_id = 0" | awk -F'|' -v t="$(date +%s%3N)" \
    -v a="$BOT_A" -v b="$BOT_B" '{ e = $1; gsub(/ /, "", e); if (e != a && e != b) next
      x = $2; sub(/.*x = /, "", x); sub(/,.*/, "", x); z = $2; sub(/.*z = /, "", z); sub(/[ )].*/, "", z)
      print t, e, x, z }' >> "$samples"
}
# crossings ENTITY SINCE_MS: "<n> <crossings> <min z> <max z> <last x> <last z>": each time it crossed
# z = NODE_Z after SINCE_MS, its x there (interpolated) and which way ("-6.00:S"), how far it got either way,
# and where it was last seen.
crossings() {
  python - "$samples" "$1" "$2" "$NODE_Z" <<'PY'
import sys
path, eid, since, line_z = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
pts = []
for row in open(path):
    w = row.split()
    if len(w) == 4 and w[1] == eid and int(w[0]) >= since:
        pts.append((float(w[2]), float(w[3])))
out = []
for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
    if (z0 - line_z) * (z1 - line_z) < 0:
        f = (line_z - z0) / (z1 - z0)
        out.append("%.2f:%s" % (x0 + (x1 - x0) * f, "S" if z1 < z0 else "N"))
zs = [z for _, z in pts]
last = pts[-1] if pts else (99.0, 99.0)
print(len(out), ",".join(out) if out else "-", "%.2f" % (min(zs) if zs else 99), "%.2f" % (max(zs) if zs else -99),
      "%.2f" % last[0], "%.2f" % last[1])
PY
}
# off LANE CROSSINGS: the nearest any crossing was to the lane, and the furthest (-1 -1: none).
off() {
  python - "$1" "$2" <<'PY'
import sys
lane = float(sys.argv[1]); xs = [float(c.split(":")[0]) for c in sys.argv[2].split(",") if ":" in c]
print("%.2f %.2f" % (min(abs(x - lane) for x in xs), max(abs(x - lane) for x in xs)) if xs else "-1 -1")
PY
}
# watch SECONDS ENTITY N [ENTITY2 N2]: sample until each has crossed N times (or the time is up); the last
# look at each is left in $look1 / $look2.
watch() {
  local until=$(( $(date +%s) + $1 )); local since; since="$(date +%s%3N)"; local polls=0
  look1=""; look2=""
  while [ "$(date +%s)" -lt "$until" ]; do
    sample; polls=$((polls + 1))
    if [ $((polls % 6)) -eq 0 ]; then
      look1="$(crossings "$2" "$since")"; [ -n "${4:-}" ] && look2="$(crossings "$4" "$since")"
      echo "   ... $2: $look1${4:+ | $4: $look2}"
      [ "$(echo "$look1" | awk '{print $1}')" -ge "$3" ] && { [ -z "${4:-}" ] || [ "$(echo "$look2" | awk '{print $1}')" -ge "$5" ]; } && return
    fi
    sleep 0.2
  done
  look1="$(crossings "$2" "$since")"; [ -n "${4:-}" ] && look2="$(crossings "$4" "$since")"
}

echo "== up: bot A goes round, both ways; bot B walks straight through node B =="
watch 120 "$BOT_A" 2 "$BOT_B" 1
a_cross="$(echo "$look1" | awk '{print $2}')"; a_minz="$(echo "$look1" | awk '{print $3}')"; a_maxz="$(echo "$look1" | awk '{print $4}')"
b_cross="$(echo "$look2" | awk '{print $2}')"
echo "   bot A crossed z = $NODE_Z at x: $a_cross (reached z $a_minz to $a_maxz); bot B at x: $b_cross"
read -r a_near a_far <<< "$(off "$LANE_A" "$a_cross")"
read -r b_near b_far <<< "$(off "$LANE_B" "$b_cross")"
check "$(echo "$a_cross" | grep -q 'S' && echo "$a_cross" | grep -q 'N' && echo true || echo false)" "bot A crossed the wall's line both ways ($a_cross)"
# The wall runs x = -8 to -4; a body 0.3-0.45 m round is at least 2.3 m off the lane going round either end.
check "$(python -c "print('true' if $a_near >= 2.25 else 'false')")" \
  "bot A never crossed where the wall stands: every crossing went round an end ($a_near m from its lane at the nearest)"
# Where it turned (its own log: a patrol turns only at an end, within 0.6 m of it). Samples miss a running
# bot's turn.
for _ in $(seq 1 60); do grep -q "entity $BOT_A's patrol reached its home end" "$log" && break; sleep 0.5; done
far_z="$(grep -oE "entity $BOT_A's patrol reached its far end \(-?[0-9.]+, -?[0-9.]+\)" "$log" | head -1 | sed -E 's/.*, (-?[0-9.]+)\)/\1/')"
home_z="$(grep -oE "entity $BOT_A's patrol reached its home end \(-?[0-9.]+, -?[0-9.]+\)" "$log" | head -1 | sed -E 's/.*, (-?[0-9.]+)\)/\1/')"
check "$(python -c "print('true' if '$far_z' and '$home_z' and float('$far_z' or 0) < -3.3 and float('$home_z' or 0) > 7.3 else 'false')")" \
  "and reached the far side each way: its far end (z ${far_z:-none}, 4 past the wall) and home again (z ${home_z:-none})"
check "$(python -c "print('true' if 0 <= $b_far < 0.8 else 'false')")" \
  "bot B, its node given no wall, walked straight through where it stands ($b_far m from its lane at most): the negative"
check "$(grep -qE "a walk map for bodies .* [1-9][0-9]* wall boxes" "$log" && echo true || echo false)" "the referee's walk map was baked with the wall in it"

echo "== node A worked out (Out): its wall is let down, and bot A walks straight through =="
assert_ok set_status "$NODE_A" 4 4294967295 "\"\""
for _ in $(seq 1 60); do grep -q "again (its walls changed)" "$log" && break; sleep 0.5; done
check "$(grep -q "again (its walls changed)" "$log" && echo true || echo false)" "its walk map was baked again (the wall let down)"
watch 90 "$BOT_A" 1
c_cross="$(echo "$look1" | awk '{print $2}')"
read -r c_near c_far <<< "$(off "$LANE_A" "$c_cross")"
echo "   bot A then crossed at x: $c_cross"
check "$(python -c "print('true' if 0 <= $c_near < 0.8 else 'false')")" \
  "down, bot A walks straight through where the wall was ($c_near m from its lane)"

if [ "$failures" -gt 0 ]; then
  echo "--- the referee's log (walls, walk maps, bots) ---" >&2
  grep -E "walk map|genre|WallsGenre|patrol|level|ERROR|SCRIPT|entity" "$log" | head -60 >&2
fi
echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
