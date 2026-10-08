#!/usr/bin/env bash
# Connect playtest: the connect screen and the Escape menu, driven like a player drives them —
# typed addresses, Enter, real clicks — against a live module. See
# tests/playtest/connect_playtest.gd for what each step proves.
#
#   GODOT=/path/to/godot ./tests/connect_playtest.sh
#
# Requires a local server (`spacetime start`). Republishes the TEST database (umf-test) with --delete-data; `umf`, the one you play in, is not touched.
# Starts from a FRESH INSTALL: the test identity's saved settings and token are deleted first,
# because the first thing checked is what a new player sees.
set -uo pipefail
cd "$(dirname "$0")/.."
# THE TEST DATABASE (DECISIONS #154): suites publish and play on `umf-test`, never on `umf`, the
# database a person plays in. UMF_DB reaches every Godot process started from here.
DB="${DB:-umf-test}"
export UMF_DB="$DB"
GODOT="${GODOT:-godot}"
SCENE="res://tests/playtest/connect_playtest.tscn"
TAG="connecttest"

if ! curl -s -m 3 -o /dev/null http://127.0.0.1:3000/v1/ping; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
# The test dials 3999 expecting NOBODY to answer, and 3998 expecting the plain HTTP server this
# script starts there. Anything else already on either port would be testing a different failure.
for port in 3999 3998; do
  if curl -s -m 2 -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null; then
    echo "Something is listening on 127.0.0.1:$port; the playtest needs it free." >&2
    exit 1
  fi
done
PYTHON="${PYTHON:-python}"
"$PYTHON" -m http.server 3998 --bind 127.0.0.1 >/dev/null 2>&1 &
wrong_server=$!
trap 'kill "$wrong_server" 2>/dev/null' EXIT
for _ in $(seq 1 40); do
  curl -s -m 1 -o /dev/null http://127.0.0.1:3998/ 2>/dev/null && break
  sleep 0.25
done

echo "== publish (fresh data) =="
# Fresh data because every run is a new identity (see the token below), and a module kept
# across runs would collect one abandoned player per run.
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 \
  || { echo "publish failed" >&2; exit 1; }
# Every scripted route in this suite is on the greybox; the module's default level is the
# lakeside (the game). Selecting it moves the spawn to the origin and stocks the ponds.
spacetime call "$DB" use_level 0 0 >/dev/null 2>&1 \
  || { echo "use_level failed" >&2; exit 1; }
sleep 3

# user:// for this project, where ConnectSettings keeps one file per identity.
userdir="$("$GODOT" --headless --path . --quit-after 1 -s res://tools/print_user_dir.gd 2>/dev/null \
  | sed -n 's/^USER_DIR=//p' | tr -d '\r')"
if [ -z "$userdir" ]; then
  echo "could not find the project's user:// directory" >&2
  exit 1
fi
# A FRESH INSTALL has neither file. The identity token matters as much as the settings: with no
# token the SDK first fetches one over HTTP, and that fetch is where a mistyped address used to
# poison every later attempt (spacetime_sync.gd, _sdk_reset_token_fetch). Keep the token from a
# previous run and that path is never exercised — which is how this harness once passed with the
# fix removed.
# The profile carries the database's name under a suite (ConnectSettings, DECISIONS #179).
rm -f "$userdir/connect_$TAG.$DB.cfg" "$userdir/spacetime_token_$TAG.txt"

out_file="$(mktemp)"
"$GODOT" --headless --path . "$SCENE" -- --connect-screen --lobby-screen --token="$TAG" --connect-timeout=4 \
  2>&1 | tee "$out_file"
status=${PIPESTATUS[0]}
if grep -E "SCRIPT ERROR" "$out_file" >/dev/null; then
  echo "VIOLATION: the client produced script errors:" >&2
  grep -E "SCRIPT ERROR" "$out_file" | head -5 >&2
  status=1
fi
rm -f "$out_file"
exit "$status"
