#!/usr/bin/env bash
# A STALE BAKE STOPS THE BUILD (DECISIONS #199). Content is edited as .tres resources and baked to
# shared/content/ (tools/bake_content.gd); server/build.rs checks the bake's manifest. This builds
# the server (native cargo check: build.rs runs for any target) against a COPY of the content
# (UMF_CONTENT_ROOT), unchanged and then broken each way a person can break it: a .tres edited and
# not baked, a new .tres never baked, a baked file edited by hand. Each must stop the build and name
# the file. The repo's own files are never touched. Needs no server and no Godot.
#
#   ./tests/content_test.sh
set -uo pipefail
cd "$(dirname "$0")/.."
passes=0; failures=0
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
check() { if [ "$1" = "true" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $2" >&2; fi }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fresh_copy() {
  rm -rf "$work/root"
  mkdir -p "$work/root/shared"
  cp -r foundation "$work/root/foundation"
  cp -r shared/content "$work/root/shared/content"
  cp shared/movement_config.json "$work/root/shared/"   # the default movement: build.rs bounds each kind from it
  "$PYTHON" -c "import json; g=json.load(open('shared/game.json'))['genres']; print('\n'.join(g))" | tr -d '\r' | while read -r g; do
    [ -n "$g" ] && [ -d "game/$g/content" ] && mkdir -p "$work/root/game/$g" && cp -r "game/$g/content" "$work/root/game/$g/content"
  done
}
# A Windows path where there is one (pwd -W): build.rs is a native program.
build() { (cd server && UMF_CONTENT_ROOT="$(cd "$work/root" && (pwd -W 2>/dev/null || pwd))" cargo check 2>&1); }
first_tres() { find "$work/root/foundation/content" -name '*.tres' | sort | head -1; }

echo "== the bake as committed =="
fresh_copy
out="$(build)"
check "$(echo "$out" | grep -q 'Finished' && echo true || echo false)" "the server builds against the content as baked"

echo "== a .tres edited, not baked =="
fresh_copy
t="$(first_tres)"
printf '\n' >> "$t"
out="$(build)"
check "$(echo "$out" | grep -q 'changed since the last bake' && echo "$out" | grep -q "$(basename "$t")" && echo true || echo false)" \
  "the build stops, naming $(basename "$t")"

echo "== a new .tres, never baked =="
fresh_copy
cp "$(first_tres)" "$work/root/foundation/content/brand_new.tres"
out="$(build)"
check "$(echo "$out" | grep -q 'brand_new.tres is content that was never baked' && echo true || echo false)" \
  "the build stops, naming brand_new.tres"

echo "== a baked file edited by hand =="
fresh_copy
j="$(find "$work/root/shared/content" -name '*.json' ! -name manifest.json | sort | head -1)"
# Any change at all (a space at the end): the first baked file is a genre's in a game with one, and
# the number this used to change (an ability's damage) is not in every file.
printf ' ' >> "$j"
out="$(build)"
check "$(echo "$out" | grep -q 'was edited by hand' && echo true || echo false)" \
  "the build stops, naming $(basename "$j")"

echo "== a character with a movement profile: its kind's bound (DECISIONS #205) =="
# The humanoid (kind 0) links a profile sprinting at 15 m/s; the copy is baked by hand (the files and
# the manifest's hashes as tools/bake_content.gd would write them), and the server built against it.
fresh_copy
"$PYTHON" - "$work/root" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
def fnv(b):
    h = 2166136261
    for x in b:
        h = ((h ^ x) * 16777619) & 0xFFFFFFFF
    return "%08x" % h
prof_tres = root / "foundation/content/movement/fast.tres"
prof_tres.parent.mkdir(parents=True, exist_ok=True)
prof_tres.write_bytes(b"[gd_resource type=\"Resource\" format=3]\n[resource]\n")
fields = {"walk_speed": 1.2, "run_speed": 5.0, "sprint_speed": 15.0, "strafe_speed_mult": 0.7, "back_speed_mult": 0.65,
          "acceleration": 70.0, "friction": 60.0, "air_control": 0.3, "jump_velocity": 8.0, "gravity": 20.0,
          "max_slope_deg": 45.0, "coyote_time_sec": 0.0, "flap_charges": 0, "flap_velocity": 6.0, "dash_impulse": 0.0,
          "dash_cooldown_ticks": 45, "dash_ticks": 10}
fields.update({"id": 0, "name": "Fast"})
mov = root / "shared/content/foundation/movement.json"
mov.write_bytes((json.dumps({"_comment": "test", "format": 1, "owner": "foundation", "type": "movement", "items": [fields]}, indent="\t", sort_keys=True) + "\n").encode())
chars = root / "shared/content/foundation/character.json"
doc = json.loads(chars.read_text(encoding="utf-8"))
for c in doc["items"]:
    if c["name"] == "Humanoid" and c["id"] == 2:
        c["movement"] = 0
chars.write_bytes((json.dumps(doc, indent="\t", sort_keys=True) + "\n").encode())
m = root / "shared/content/manifest.json"
man = json.loads(m.read_text(encoding="utf-8"))
man["outputs"]["shared/content/foundation/movement.json"] = {"count": 1, "hash": fnv(mov.read_bytes()), "owner": "foundation",
    "sources": {"foundation/content/movement/fast.tres": fnv(prof_tres.read_bytes())}, "type": "movement"}
man["outputs"]["shared/content/foundation/character.json"]["hash"] = fnv(chars.read_bytes())
m.write_bytes((json.dumps(man, indent="\t", sort_keys=True) + "\n").encode())
PY
out="$(cd server && UMF_CONTENT_ROOT="$(cd "$work/root" && (pwd -W 2>/dev/null || pwd))" UMF_EXPECT_KIND0_SPRINT=15 cargo test --test movement_limits 2>&1)"
check "$(echo "$out" | grep -q 'test result: ok. 3 passed' && echo true || echo false)" \
  "kind 0's Tier A bound is its humanoid's profile (sprint 15); a kind without one keeps the default"
out="$(cd server && UMF_EXPECT_KIND0_SPRINT=15 cargo test --test movement_limits 2>&1)"
check "$(echo "$out" | grep -q 'test result: FAILED' && echo true || echo false)" \
  "(and the repo's own content, with no profile, does not give kind 0 that bound)"

echo "== a character's abilities: only those, for its kind (DECISIONS #207) =="
# The humanoid (kind 0) lists ability 0 (melee) only: the server built against it lets kind 0 use
# 0 and not 7; a character listing an ability that is not baked stops the build.
rechars() {   # rechars PYTHON_ON_items
  "$PYTHON" - "$work/root" "$1" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
def fnv(b):
    h = 2166136261
    for x in b:
        h = ((h ^ x) * 16777619) & 0xFFFFFFFF
    return "%08x" % h
f = root / "shared/content/foundation/character.json"
doc = json.loads(f.read_text(encoding="utf-8"))
items = doc["items"]
exec(sys.argv[2])
f.write_bytes((json.dumps(doc, indent="\t", sort_keys=True) + "\n").encode())
m = root / "shared/content/manifest.json"
man = json.loads(m.read_text(encoding="utf-8"))
man["outputs"]["shared/content/foundation/character.json"]["hash"] = fnv(f.read_bytes())
m.write_bytes((json.dumps(man, indent="\t", sort_keys=True) + "\n").encode())
PY
}
fresh_copy
rechars 'for c in items:
    if c["id"] == 2: c["abilities"] = [0]'
out="$(cd server && UMF_CONTENT_ROOT="$(cd "$work/root" && (pwd -W 2>/dev/null || pwd))" UMF_EXPECT_KIND0_ONLY_ABILITY_0=1 cargo test --test kind_abilities 2>&1)"
check "$(echo "$out" | grep -q 'test result: ok. 2 passed' && echo true || echo false)" \
  "kind 0, whose humanoid lists melee only, may use melee and nothing else; another kind is not limited"
out="$(cd server && UMF_EXPECT_KIND0_ONLY_ABILITY_0=1 cargo test --test kind_abilities 2>&1)"
check "$(echo "$out" | grep -q 'test result: FAILED' && echo true || echo false)" \
  "(and the repo's own content, listing none, does not limit kind 0)"
fresh_copy
rechars 'for c in items:
    if c["id"] == 2: c["abilities"] = [999]'
out="$(build)"
check "$(echo "$out" | grep -q "lists ability 999, which is not baked content" && echo true || echo false)" \
  "a character listing an ability that is not content stops the build"

echo "== statuses: the build holds their numbers (DECISIONS #206) =="
# The baked status file edited as the bake would write it (the manifest's hash recomputed): a
# foundation status numbered 150 stops the build, naming it; so does a game with no status 0. (The
# rules for a genre's statuses, which the template has none of, are tests/status_rules.rs.)
restatus() {   # restatus PYTHON_EXPR_ON_items
  "$PYTHON" - "$work/root" "$1" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
def fnv(b):
    h = 2166136261
    for x in b:
        h = ((h ^ x) * 16777619) & 0xFFFFFFFF
    return "%08x" % h
f = root / "shared/content/foundation/status.json"
doc = json.loads(f.read_text(encoding="utf-8"))
items = doc["items"]
exec(sys.argv[2])
doc["items"] = items
f.write_bytes((json.dumps(doc, indent="\t", sort_keys=True) + "\n").encode())
m = root / "shared/content/manifest.json"
man = json.loads(m.read_text(encoding="utf-8"))
man["outputs"]["shared/content/foundation/status.json"]["hash"] = fnv(f.read_bytes())
m.write_bytes((json.dumps(man, indent="\t", sort_keys=True) + "\n").encode())
PY
}
fresh_copy
restatus 'items[1]["status"] = 150'
out="$(build)"
check "$(echo "$out" | grep -q "the foundation's status 'Injured' is number 150" && echo true || echo false)" \
  "a foundation status numbered 150 stops the build, naming it"
fresh_copy
restatus 'items = [i for i in items if i["status"] != 0]'
out="$(build)"
check "$(echo "$out" | grep -q "there is no status 0" && echo true || echo false)" "a game without status 0 (normal) does not build"
fresh_copy
restatus 'items[2]["then"] = 999'
out="$(build)"
check "$(echo "$out" | grep -q "becomes content 999 when it ends, which is not a status" && echo true || echo false)" \
  "a status that becomes something that is not a status stops the build"

echo "== holds: one press, one hold (DECISIONS #209) =="
# The baked hold file edited as the bake would write it: a press two holds could start, a hold done to
# nothing, a status link that is not a status, no times. (A genre's holds over the foundation's, which
# the template has none of: tests/hold_rules.rs.)
rehold() {   # rehold PYTHON_EXPR_ON_items
  "$PYTHON" - "$work/root" "$1" <<'PY'
import json, sys, pathlib, copy
root = pathlib.Path(sys.argv[1])
def fnv(b):
    h = 2166136261
    for x in b:
        h = ((h ^ x) * 16777619) & 0xFFFFFFFF
    return "%08x" % h
f = root / "shared/content/foundation/hold.json"
doc = json.loads(f.read_text(encoding="utf-8"))
items = doc["items"]
exec(sys.argv[2])
doc["items"] = items
f.write_bytes((json.dumps(doc, indent="\t", sort_keys=True) + "\n").encode())
m = root / "shared/content/manifest.json"
man = json.loads(m.read_text(encoding="utf-8"))
man["outputs"]["shared/content/foundation/hold.json"]["hash"] = fnv(f.read_bytes())
m.write_bytes((json.dumps(man, indent="\t", sort_keys=True) + "\n").encode())
PY
}
fresh_copy
rehold 'twin = copy.deepcopy(items[0]); twin["id"] = 5; twin["name"] = "Revive"; twin["targets"] = [1]; items.append(twin)'
out="$(build)"
check "$(echo "$out" | grep -q "foundation has two holds one press could start: 'Help up' and 'Revive'" && echo true || echo false)" \
  "two holds one press could start (a downed NPC) stop the build, naming both"
fresh_copy
rehold 'twin = copy.deepcopy(items[0]); twin["id"] = 5; twin["name"] = "Search"; twin["when"] = 5; items.append(twin)'
out="$(build)"
check "$(echo "$out" | grep -q 'Finished' && echo true || echo false)" "two told apart by the target's status (downed, hidden) build"
fresh_copy
rehold 'items[0]["targets"] = []'
out="$(build)"
check "$(echo "$out" | grep -q "hold 'Help up' is done to nothing" && echo true || echo false)" "a hold done to nothing stops the build"
fresh_copy
rehold 'items[0]["when"] = 999'
out="$(build)"
check "$(echo "$out" | grep -q "links when to content 999, which is not a status" && echo true || echo false)" \
  "a hold for a status that is not one stops the build"
fresh_copy
rehold 'items[0]["seconds_with"] = []'
out="$(build)"
check "$(echo "$out" | grep -q "needs seconds_with" && echo true || echo false)" "a hold that takes no time stops the build"

echo "== the real tree again =="
out="$(cd server && cargo check 2>&1)"
check "$(echo "$out" | grep -q 'Finished' && echo true || echo false)" "the server builds from the repo's own content"

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
