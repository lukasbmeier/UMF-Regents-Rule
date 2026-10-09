#!/usr/bin/env bash
# HOT RULES ON A REAL SERVER (DECISIONS #201). An admin changes a rule while the game runs and the
# server uses the new value at once; nobody else may, and nothing outside the rule's bounds is
# taken. A republish with a new default reaches the database without a wipe, while a value an admin
# set is kept; reset puts a rule back. The republish builds against a COPY of the content
# (UMF_CONTENT_ROOT) with one default changed, so the repo's files are never touched.
#
#   GODOT=<path> ./tests/hot_rules_test.sh     (the server is needed; Godot is not)
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
passes=0; failures=0
check() { if [ "$1" = "true" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $2" >&2; fi }

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
# One rule's row: "<number>|<overridden>".
rule() { spacetime sql "$DB" "SELECT number, overridden FROM hot_rule WHERE key = '$1'" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ' | head -1; }
touch_server() { spacetime call --anonymous "$DB" set_player_name '"Tester"' >/dev/null 2>&1 || true; }   # a connect: syncs the rules

echo "== publish (fresh data) =="
(cd server && spacetime publish "$DB" --server local --delete-data --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "the module publishes"
check "$([ "$(rule foundation.interact_range_m)" = "3|false" ] && [ "$(rule foundation.new_player_health)" = "100|false" ] && echo true || echo false)" \
  "every rule has its row, at this build's default ($(rule foundation.interact_range_m), $(rule foundation.new_player_health))"

echo "== who may change a rule, and to what =="
out="$(spacetime call --anonymous "$DB" set_rule foundation.interact_range_m 5.0 '""' 2>&1)"
check "$(echo "$out" | grep -q 'admin only' && [ "$(rule foundation.interact_range_m)" = "3|false" ] && echo true || echo false)" \
  "a player cannot (output: $(echo "$out" | grep -o 'admin only' | head -1))"
out="$(spacetime call "$DB" set_rule foundation.interact_range_m 99.0 '""' 2>&1)"
check "$(echo "$out" | grep -q 'outside 0.5..20' && echo true || echo false)" "an admin cannot go outside its bounds"
out="$(spacetime call "$DB" set_rule foundation.no_such_rule 1.0 '""' 2>&1)"
check "$(echo "$out" | grep -q "no hot rule" && echo true || echo false)" "nor set a rule that does not exist"
spacetime call "$DB" set_rule foundation.interact_range_m 5.0 '""' >/dev/null 2>&1
check "$([ "$(rule foundation.interact_range_m)" = "5|true" ] && echo true || echo false)" \
  "an admin can, and the row says so ($(rule foundation.interact_range_m))"

echo "== the server uses the live value =="
# The admin (this CLI) is moved 40 m away from a fresh player, then tries to use them: the refusal
# names the range it judged by.
spacetime call "$DB" set_dev_tools true >/dev/null 2>&1
touch_server
target="$(spacetime sql "$DB" "SELECT entity_id FROM player WHERE name = 'Tester'" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d' | tr -d ' ' | head -1)"
spacetime call "$DB" teleport '{"x":40.0,"y":1.0,"z":40.0}' >/dev/null 2>&1
sleep 1
out="$(spacetime call "$DB" interact "$target" 0 2>&1)"
check "$(echo "$out" | grep -q '> 5.00 m' && echo true || echo false)" \
  "interact is judged by the live range, 5 m (output: $(echo "$out" | grep -o 'out of range[^"]*' | head -1))"

echo "== a republish with a new default =="
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/shared"
cp -r foundation "$work/foundation"
cp -r shared/content "$work/shared/content"
sed -i 's/^number = 100.0$/number = 150.0/' "$work/foundation/content/rules/foundation.tres"
"$PYTHON" - "$work" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
def fnv(b):
    h = 2166136261
    for x in b:
        h = ((h ^ x) * 16777619) & 0xFFFFFFFF
    return "%08x" % h
baked = root / "shared/content/foundation/rules.json"
doc = json.loads(baked.read_text(encoding="utf-8"))
for s in doc["items"]:
    for r in s["rules"]:
        if r["key"] == "foundation.new_player_health":
            r["number"] = 150.0
text = baked.read_text(encoding="utf-8").replace('"number": 100.0', '"number": 150.0')
baked.write_bytes(text.encode())
m = root / "shared/content/manifest.json"
man = json.loads(m.read_text(encoding="utf-8"))
out = man["outputs"]["shared/content/foundation/rules.json"]
out["hash"] = fnv(baked.read_bytes())
out["sources"]["foundation/content/rules/foundation.tres"] = fnv((root / "foundation/content/rules/foundation.tres").read_bytes())
m.write_bytes((json.dumps(man, indent="\t", sort_keys=True) + "\n").encode())
PY
root_w="$(cd "$work" && (pwd -W 2>/dev/null || pwd))"
(cd server && UMF_CONTENT_ROOT="$root_w" spacetime publish "$DB" --server local --yes >/dev/null 2>&1)
check "$([ $? -eq 0 ] && echo true || echo false)" "a build whose default for new players' health is 150 publishes over it, keeping the data"
touch_server
check "$([ "$(rule foundation.new_player_health)" = "150|false" ] && echo true || echo false)" \
  "the rule nobody set follows the new default ($(rule foundation.new_player_health))"
check "$([ "$(rule foundation.interact_range_m)" = "5|true" ] && echo true || echo false)" \
  "the rule the admin set keeps its value ($(rule foundation.interact_range_m))"

echo "== reset, and the real build again =="
spacetime call "$DB" reset_rule foundation.interact_range_m >/dev/null 2>&1
check "$([ "$(rule foundation.interact_range_m)" = "3|false" ] && echo true || echo false)" \
  "reset puts a rule back to this build's default ($(rule foundation.interact_range_m))"
(cd server && spacetime publish "$DB" --server local --yes >/dev/null 2>&1)
touch_server
check "$([ "$(rule foundation.new_player_health)" = "100|false" ] && echo true || echo false)" \
  "republishing the real build brings its default back ($(rule foundation.new_player_health))"
spacetime call "$DB" set_dev_tools false >/dev/null 2>&1

echo
echo "hot rules: $passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
