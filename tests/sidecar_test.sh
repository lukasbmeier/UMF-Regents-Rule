#!/usr/bin/env bash
# THE SIDECAR, RUNNING. Publishes a fresh module, creates a world the module deliberately does
# NOT simulate, starts a real headless sidecar against it, registers it as that world's
# authority, and drops an entity into the air.
#
# If the entity falls, every link in the chain worked: the world-filtered subscription, the
# `input_queue` RLS filter that only an authority can see through, SERVER_AUTHORITY simulation,
# `write_movement_batch` (including the BSATN hint shape, which no GDScript test can check), and
# the heartbeat that keeps `authority_online` true. If any one of them is wrong the entity hangs
# in the air and nothing else reports it.
#
#   GODOT=/path/to/godot ./tests/sidecar_test.sh
#   SIDECAR_BIN=build/server/umf_server.console.exe SIDECAR_ARGS=--headless ./tests/sidecar_test.sh
#
# SIDECAR_BIN / SIDECAR_ARGS replace how the sidecar is launched — tests/export_test.sh points them
# at the EXPORTED server, so the same checks prove the build a host would actually run.
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
WORLD=1

passes=0
failures=0
pass() { passes=$((passes + 1)); }
fail() { failures=$((failures + 1)); echo "  FAIL: $1" >&2; }
check() { if [ "$1" = "true" ]; then pass; else fail "$2"; fi }
sql_rows() { spacetime sql "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d'; }
# `spacetime call` prints an UNSTABLE warning on every invocation, so "produced output" is not a
# failure; only an actual error line is. Same rule as tests/integration_test.sh.
assert_ok() {
  local out; out="$(spacetime call "$DB" $1 2>&1)"
  if echo "$out" | grep -qiE "^error|error:"; then fail "$2 ($(echo "$out" | head -2 | tail -1))"
  else pass; fi
}

sidecar_pid=""
log="$(mktemp)"
log2="$(mktemp)"
cleanup() {
  if [ -n "$sidecar_pid" ]; then kill "$sidecar_pid" 2>/dev/null; wait "$sidecar_pid" 2>/dev/null; fi
  rm -f "$log" "$log2"
}
trap cleanup EXIT

# From source unless told otherwise. The binary is quoted (Godot often lives under a path with
# spaces in it); its arguments are word-split on purpose.
SIDECAR_BIN="${SIDECAR_BIN:-$GODOT}"
SIDECAR_ARGS="${SIDECAR_ARGS:---headless --path . res://sidecar/sidecar_main.tscn}"
start_sidecar() {   # start_sidecar LOGFILE
  # shellcheck disable=SC2086
  "$SIDECAR_BIN" $SIDECAR_ARGS -- --world=$WORLD > "$1" 2>&1 &
  sidecar_pid=$!
}

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
sleep 3
echo "ok"

echo "== a world the module does not simulate =="
# sim_authority = SIM_SIDECAR (1). `tick_movement` skips this world entirely, so anything that
# moves in it moved because the sidecar moved it.
assert_ok "create_world $WORLD 1" "create_world $WORLD as a SIDECAR world"

echo "== start the sidecar =="
echo "   $SIDECAR_BIN $SIDECAR_ARGS"
start_sidecar "$log"
ident=""
for _ in $(seq 1 60); do
  ident="$(grep -o 'identity 0x[0-9a-f]*' "$log" | head -1 | sed 's/.*0x//')"
  [ -n "$ident" ] && break
  sleep 0.5
done
check "$([ -n "$ident" ] && echo true || echo false)" "the sidecar connected and announced an identity"
if [ -z "$ident" ]; then
  echo "--- sidecar log ---" >&2; tail -30 "$log" >&2
  echo "sidecar: $passes passed, $((failures)) failed" >&2
  exit 1
fi
echo "   identity 0x$ident"

echo "== drop an entity into the air =="
# `spawn_npc` writes `grounded: true` whatever height it is given. That claim is a lie here, and
# an authority that believed it would leave the entity hanging.
assert_ok "spawn_npc $WORLD 0 {\"x\":0.0,\"y\":8.0,\"z\":0.0}" "spawn_npc into world $WORLD at y=8"

world_y() {
  sql_rows "SELECT pos FROM movement_state WHERE world_id = $WORLD" | head -1 \
    | grep -oE 'y = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/y = //'
}

echo "== CONTROL: nothing is authoritative for this world yet =="
# The sidecar is connected and is already simulating the fall in its own process, but it has not
# been registered, so every write it sends is refused. If the row moves anyway, something other
# than an authority is simulating this world and the whole trust model is wrong.
sleep 4
before_y="$(world_y)"
echo "   after 4 unregistered seconds, y = ${before_y:-?}"
check "$([ -n "$before_y" ] && awk -v v="$before_y" 'BEGIN { exit !(v > 7.5) }' && echo true || echo false)" \
  "an unregistered sidecar cannot move anything: the entity is still at y=8 (y=${before_y:-none})"

echo "== register it as that world's authority =="
# Until this lands the sidecar is nobody: writes are refused and `input_queue` is invisible to
# it, because that table's RLS filter joins on the `authority` table.
assert_ok "register_authority 0x$ident 1 $WORLD" "register_authority ROLE_SIDECAR world $WORLD"

landed=""
for _ in $(seq 1 60); do
  y="$(world_y)"
  if [ -n "$y" ] && awk -v v="$y" 'BEGIN { exit !(v < 1.0) }'; then landed="$y"; break; fi
  sleep 0.5
done
echo "   y went from ${before_y:-?} to ${landed:-?}"
check "$([ -n "$landed" ] && echo true || echo false)" \
  "THE SIDECAR SIMULATED IT: registering it is what made the entity fall (y=${landed:-$(world_y)})"

echo "== an NPC it drives itself =="
# Kind 1 is the rival angler, whose definition names a brain. Nobody sends it input: if it moves,
# the sidecar decided to move it and then moved it through the ordinary movement path.
assert_ok "spawn_npc $WORLD 1 {\"x\":-4.0,\"y\":0.0,\"z\":-4.0}" "spawn the rival angler"
npc_from=""
npc_moved=""
for _ in $(seq 1 40); do
  row="$(sql_rows "SELECT pos FROM movement_state WHERE world_id = $WORLD" | sed -n '2p')"
  x="$(printf '%s' "$row" | grep -oE 'x = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/x = //')"
  z="$(printf '%s' "$row" | grep -oE 'z = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/z = //')"
  [ -z "$x" ] && { sleep 0.5; continue; }
  if [ -z "$npc_from" ]; then npc_from="$x,$z"; fi
  d="$(awk -v x="$x" -v z="$z" 'BEGIN { split("'"$npc_from"'", a, ","); dx=x-a[1]; dz=z-a[2]; print sqrt(dx*dx+dz*dz) }')"
  if awk -v v="$d" 'BEGIN { exit !(v > 1.0) }'; then npc_moved="$d"; break; fi
  sleep 0.5
done
echo "   the rival wandered ${npc_moved:-0} m from ${npc_from:-?}"
check "$([ -n "$npc_moved" ] && echo true || echo false)"   "AN NPC THE SIDECAR DRIVES: nobody sent it input and it walked (${npc_moved:-0} m)"

echo "== and it is holding the world =="
online="$(sql_rows "SELECT authority_online FROM world_config WHERE world_id = $WORLD" | head -1 \
  | grep -oE 'true|false' | head -1)"
check "$([ "$online" = "true" ] && echo true || echo false)" \
  "the heartbeat keeps authority_online true (got '${online:-none}')"

echo "== its brain survives a restart =="
# The first sidecar started the rival's brain FRESH, homing it where it was spawned. It has been
# persisting since (write_npc_brain, on change, at most once a second). Kill it, and the rival is
# left standing wherever it wandered to — which is exactly where a brain that forgot would make
# its new home. A sidecar that REMEMBERS resumes the old one.
fresh_line="$(grep -o "entity [0-9]* starts brain 'wander' fresh ([^)]*))" "$log" | tail -1)"
npc_id="$(printf '%s' "$fresh_line" | grep -oE 'entity [0-9]+' | grep -oE '[0-9]+')"
home1="$(printf '%s' "$fresh_line" | grep -oE 'home \([^)]*\)')"
echo "   first run: entity ${npc_id:-?} started fresh with ${home1:-no home}"
check "$([ -n "$npc_id" ] && [ -n "$home1" ] && echo true || echo false)" \
  "the first sidecar started the rival's brain fresh and said where its home was"
# KILL IT WHILE IT IS AWAY FROM HOME. A wander brain roams AROUND its home and comes back, so a
# fixed wait sometimes caught it half a metre from where it started — and then "it resumed the
# old home" cannot be told apart from "it homed where it stood". So wait (3 s at least, for a
# persisted decision) until it is well away, and only then pull the plug.
hx="$(printf '%s' "$home1" | grep -oE -- '-?[0-9]+\.[0-9]+' | sed -n '1p')"
hz="$(printf '%s' "$home1" | grep -oE -- '-?[0-9]+\.[0-9]+' | sed -n '3p')"
away_since=$(date +%s)
for _ in $(seq 1 60); do
  sleep 0.5
  row="$(sql_rows "SELECT pos FROM movement_state WHERE entity_id = ${npc_id:-0}" | head -1)"
  px="$(printf '%s' "$row" | grep -oE 'x = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/x = //')"
  pz="$(printf '%s' "$row" | grep -oE 'z = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/z = //')"
  [ -z "$px" ] && continue
  far="$(awk -v a="${hx:-0}" -v b="${hz:-0}" -v x="$px" -v z="$pz" \
    'BEGIN { dx=a-x; dz=b-z; print (sqrt(dx*dx+dz*dz) > 1.5) ? "yes" : "no" }')"
  if [ "$far" = "yes" ] && [ $(( $(date +%s) - away_since )) -ge 3 ]; then break; fi
done
kill "$sidecar_pid" 2>/dev/null; wait "$sidecar_pid" 2>/dev/null; sidecar_pid=""
sleep 1
row="$(sql_rows "SELECT pos FROM movement_state WHERE entity_id = ${npc_id:-0}" | head -1)"
nx="$(printf '%s' "$row" | grep -oE 'x = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/x = //')"
nz="$(printf '%s' "$row" | grep -oE 'z = -?[0-9]+\.?[0-9]*' | head -1 | sed 's/z = //')"
echo "   killed it; the rival stands at x=${nx:-?} z=${nz:-?}"

start_sidecar "$log2"
resumed=""
for _ in $(seq 1 60); do
  resumed="$(grep -o "entity ${npc_id:-0} resumes brain 'wander' in state '[a-z]*' ([^)]*))" "$log2" | tail -1)"
  [ -n "$resumed" ] && break
  grep -q "entity ${npc_id:-0} starts brain 'wander' fresh" "$log2" && break
  sleep 0.5
done
home2="$(printf '%s' "$resumed" | grep -oE 'home \([^)]*\)')"
echo "   second run: ${resumed:-it did not resume}"
check "$([ -n "$resumed" ] && echo true || echo false)" \
  "THE RESTARTED SIDECAR RESUMED THE BRAIN instead of starting it fresh"
check "$([ -n "$home2" ] && [ "$home2" = "$home1" ] && echo true || echo false)" \
  "with the home it had before (${home2:-none}, was ${home1:-none})"
# And that home is NOT simply where the rival stood, or this check could not tell the two apart.
hx="$(printf '%s' "$home1" | grep -oE -- '-?[0-9]+\.[0-9]+' | sed -n '1p')"
hz="$(printf '%s' "$home1" | grep -oE -- '-?[0-9]+\.[0-9]+' | sed -n '3p')"
apart="$(awk -v a="${hx:-0}" -v b="${hz:-0}" -v x="${nx:-0}" -v z="${nz:-0}" \
  'BEGIN { dx=a-x; dz=b-z; print sqrt(dx*dx+dz*dz) }')"
check "$(awk -v d="$apart" 'BEGIN { print (d > 1.0) ? "true" : "false" }')" \
  "and the rival had wandered ${apart} m from it, so a brain that forgot would have homed elsewhere"

for f in "$log" "$log2"; do
  if grep -E "SCRIPT ERROR" "$f" >/dev/null; then
    fail "the sidecar produced script errors"
    grep -E "SCRIPT ERROR" "$f" | head -5 >&2
  fi
done

echo
echo "sidecar: $passes passed, $failures failed"
[ "$failures" -eq 0 ] || { echo "--- sidecar log ---" >&2; tail -40 "$log" >&2; }
exit $([ "$failures" -eq 0 ] && echo 0 || echo 1)
