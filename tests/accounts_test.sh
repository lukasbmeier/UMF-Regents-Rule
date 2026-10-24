#!/usr/bin/env bash
# ACCOUNTS ON A REAL SERVER (template 1.0, DECISIONS #278). A sign-in makes an account the first time and
# comes back to it on another machine; a token from a service the game does not trust, or for another
# game, is a guest; one that ran out is refused by the server itself; a link code joins a guest's machine
# to an account and takes the character over; an account keeps several characters when its game allows,
# each put away where it stood while another is played; an offline character is parked and comes back
# where it stood; a game that takes no guests gives a guest nothing.
#
# The sign-in service is the suites' own (tests/lib/oidc_issuer.py, on 127.0.0.1), trusted by the TEST
# database only. Each sign-in is an HTTP caller with its token: every call connects and leaves, as the
# server sees it (client_connected, client_disconnected). A real SpacetimeAuth sign-in is checked by hand.
#
#   ./tests/accounts_test.sh     (the server is needed; Godot is not)
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib/db.sh
PYTHON="${PYTHON:-$(command -v python || command -v python3)}"
HOST=http://127.0.0.1:3000
PORT=8775
OTHER_PORT=8776
ISS="http://127.0.0.1:$PORT"
AUD="umf-test-client"
passes=0; failures=0
check() { if [ "$1" = "true" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $2" >&2; fi }
assert_eq() { if [ "$1" = "$2" ]; then passes=$((passes + 1)); else failures=$((failures + 1)); echo "  FAIL: $3 (expected '$2', got '$1')" >&2; fi }

if ! curl -s -m 3 -o /dev/null "$HOST/v1/ping"; then
  echo "No local SpacetimeDB on 127.0.0.1:3000. Start one with: spacetime start" >&2
  exit 1
fi
work="$(mktemp -d)"
# The issuers' keys are kept between runs: the server keeps an issuer's keys for minutes, so a new key
# under the same address would be refused (InvalidSignature) until it looks again.
KEYS=build/test_issuer
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$work"; }
trap cleanup EXIT

sql_rows() { spacetime sql "$DB" "$1" 2>/dev/null | tail -n +3 | sed '/^[[:space:]]*$/d'; }
row_count() { sql_rows "$1" | wc -l | tr -d ' '; }
sql_first() { sql_rows "$1" | head -1 | awk -F'|' -v c="${2:-1}" '{gsub(/^[ \t]+|[ \t]+$/,"",$c); print $c}'; }
mint() { "$PYTHON" tests/lib/oidc_issuer.py mint --dir "$KEYS/main" --port "$PORT" "$@"; }
# call_as TOKEN REDUCER JSON_ARGS -> the HTTP status (the body in $work/last)
call_as() {
  curl -s -o "$work/last" -w "%{http_code}" -X POST -H "Authorization: Bearer $1" -H "Content-Type: application/json" \
    "$HOST/v1/database/$DB/call/$2" -d "$3"
}
ok_as() { local code; code="$(call_as "$@")"; check "$([ "$code" = "200" ] && echo true || echo false)" "$2 as a sign-in ($code: $(head -c 200 "$work/last"))"; }
# The identity a token is, as the server works it out.
identity_of() {
  "$PYTHON" -c "import sys,json,base64; p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4); print(json.loads(base64.urlsafe_b64decode(p)).get('hex_identity',''))" \
    "$(curl -s -X POST -H "Authorization: Bearer $1" "$HOST/v1/identity/websocket-token" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['token'])")"
}
wait_up() { for _ in $(seq 1 90); do curl -s -m 1 -o /dev/null "$1/.well-known/openid-configuration" && return 0; sleep 1; done; return 1; }

echo "== a sign-in service of our own, and the test database =="
"$PYTHON" tests/lib/oidc_issuer.py serve --port "$PORT" --dir "$KEYS/main" 2>"$work/issuer.log" & pids+=($!)
"$PYTHON" tests/lib/oidc_issuer.py serve --port "$OTHER_PORT" --dir "$KEYS/other" 2>"$work/other.log" & pids+=($!)
wait_up "$ISS" && wait_up "http://127.0.0.1:$OTHER_PORT" || { echo "the test issuers did not start" >&2; cat "$work/issuer.log" >&2; exit 1; }
(cd server && spacetime publish "$DB" --server local --delete-data --yes) >/dev/null 2>&1 || { echo "publish failed" >&2; exit 1; }
sleep 2
spacetime call "$DB" trust_issuer "\"$ISS\"" "\"$AUD\"" '"the suites issuer"' >/dev/null 2>&1
check "$([ "$(row_count "SELECT * FROM login_issuer WHERE issuer = '$ISS'")" = "1" ] && echo true || echo false)" "the admin trusts the suites' issuer"
out="$(spacetime call --anonymous "$DB" trust_issuer '"http://evil.example"' '""' '"no"' 2>&1)"
check "$(echo "$out" | grep -qi "admin" && echo true || echo false)" "only an admin trusts an issuer"
check "$([ "$(row_count "SELECT * FROM login_issuer WHERE issuer = 'https://auth.spacetimedb.com/oidc'")" = "1" ] && echo true || echo false)" \
  "the game's own sign-in (SpacetimeAuth) is trusted from the start"

echo "== the first sign-in makes an account =="
ALICE="$(mint --sub alice --aud "$AUD")"
A_ID="$(identity_of "$ALICE")"
check "$([ -n "$A_ID" ] && echo true || echo false)" "the server takes the token ($A_ID)"
ok_as "$ALICE" set_player_name '["Alice"]'
A_ACC="$(sql_first "SELECT account_id FROM account_login WHERE identity = 0x$A_ID" 1)"
check "$([ -n "$A_ACC" ] && echo true || echo false)" "her sign-in is an account's ($A_ACC)"
assert_eq "$(sql_first "SELECT method FROM account_login WHERE identity = 0x$A_ID" 1)" "1" "by its own sign-in"
A_ENT="$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$A_ID" 1)"
assert_eq "$(sql_first "SELECT account_id FROM account_character WHERE entity_id = $A_ENT" 1)" "$A_ACC" "her player is the account's character"
assert_eq "$(sql_first "SELECT name FROM account_character WHERE entity_id = $A_ENT" 1)" "\"Alice\"" "and it keeps her name"
ACCOUNTS="$(row_count "SELECT * FROM account")"

echo "== the same sign-in on another machine is the same account =="
ALICE2="$(mint --sub alice --aud "$AUD")"
ok_as "$ALICE2" set_player_name '["Alice"]'
assert_eq "$(identity_of "$ALICE2")" "$A_ID" "another token for her is the same identity"
assert_eq "$(row_count "SELECT * FROM account")" "$ACCOUNTS" "no second account"
assert_eq "$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$A_ID" 1)" "$A_ENT" "and the same character"

echo "== what is not this game's sign-in is a guest, or refused =="
WRONG_AUD="$(mint --sub mallory --aud another-game)"
ok_as "$WRONG_AUD" set_player_name '["Mallory"]'
M_ID="$(identity_of "$WRONG_AUD")"
assert_eq "$(row_count "SELECT * FROM account_login WHERE identity = 0x$M_ID")" "0" "a token for another game makes no account"
assert_eq "$(row_count "SELECT * FROM player WHERE identity = 0x$M_ID")" "1" "but plays as a guest (guests allowed)"
FOREIGN="$("$PYTHON" tests/lib/oidc_issuer.py mint --dir "$KEYS/other" --port "$OTHER_PORT" --sub alice --aud "$AUD")"
ok_as "$FOREIGN" set_player_name '["Foreigner"]'
F_ID="$(identity_of "$FOREIGN")"
check "$([ "$F_ID" != "$A_ID" ] && echo true || echo false)" "the same name at another issuer is someone else"
assert_eq "$(row_count "SELECT * FROM account_login WHERE identity = 0x$F_ID")" "0" "and an issuer nobody trusted makes no account"
EXPIRED="$(mint --sub alice --aud "$AUD" --exp -300)"
code="$(call_as "$EXPIRED" set_player_name '["Alice"]')"
check "$([ "$code" = "401" ] || [ "$code" = "403" ] && echo true || echo false)" "a token that ran out is refused by the server itself ($code)"
check "$([ "$(row_count "SELECT * FROM account")" = "$ACCOUNTS" ] && echo true || echo false)" "(still one account)"

echo "== a link code joins a guest's machine to the account =="
GUEST="$(curl -s -X POST "$HOST/v1/identity" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['token'])")"
ok_as "$GUEST" set_player_name '["Guesty"]'
G_ID="$(identity_of "$GUEST")"
G_ENT="$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$G_ID" 1)"
code="$(call_as "$GUEST" make_link_code '["ABCDEFGH"]')"
check "$(grep -qi "sign in first" "$work/last" && echo true || echo false)" "a guest cannot make a code ($code)"
ok_as "$ALICE" make_link_code '["abcdefgh"]'
assert_eq "$(sql_first "SELECT code FROM link_code WHERE maker = 0x$A_ID" 1)" "\"ABCDEFGH\"" "her code, as typed (any case)"
code="$(call_as "$ALICE" make_link_code '["ABCDEFG0"]')"
check "$(grep -qi "a code is" "$work/last" && echo true || echo false)" "a code has its own letters (no 0)"
code="$(call_as "$GUEST" use_link_code '["ZZZZZZZZ"]')"
check "$(grep -qi "no such code" "$work/last" && echo true || echo false)" "a wrong code is refused"
ok_as "$GUEST" use_link_code '["ABCDEFGH"]'
assert_eq "$(sql_first "SELECT account_id FROM account_login WHERE identity = 0x$G_ID" 1)" "$A_ACC" "the guest's machine is a way in to her account"
assert_eq "$(sql_first "SELECT method FROM account_login WHERE identity = 0x$G_ID" 1)" "2" "by a link"
assert_eq "$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$G_ID" 1)" "$A_ENT" "and plays her character there"
assert_eq "$(row_count "SELECT * FROM player WHERE identity = 0x$A_ID")" "0" "which her other sign-in let go"
assert_eq "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $G_ENT" 1)" "4294967295" "the guest's own character is put away"
assert_eq "$(row_count "SELECT * FROM link_code")" "0" "a code is used once"
code="$(call_as "$GUEST" use_link_code '["ABCDEFGH"]')"
check "$([ "$code" != "200" ] && echo true || echo false)" "and not again ($code)"

echo "== characters: several, each put away while another is played =="
spacetime call "$DB" set_rule foundation.characters_per_account 2 '""' >/dev/null 2>&1
ok_as "$GUEST" new_character '[]'
NEW_ENT="$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$G_ID" 1)"
check "$([ -n "$NEW_ENT" ] && [ "$NEW_ENT" != "$A_ENT" ] && echo true || echo false)" "a second character, played at once ($NEW_ENT)"
assert_eq "$(row_count "SELECT * FROM account_character WHERE account_id = $A_ACC")" "2" "the account lists two"
assert_eq "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $A_ENT" 1)" "4294967295" "the first is put away"
for t in entity health_state; do
  assert_eq "$(sql_first "SELECT chunk FROM $t WHERE entity_id = $A_ENT" 1)" "4294967295" "with its $t"
done
code="$(call_as "$GUEST" new_character '[]')"
check "$(grep -qi "at most 2" "$work/last" && echo true || echo false)" "no third past the rule"
ok_as "$GUEST" play_character "[$A_ENT]"
assert_eq "$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$G_ID" 1)" "$A_ENT" "back to the first"
check "$([ "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $A_ENT" 1)" != "4294967295" ] && echo true || echo false)" \
  "where it stood"
assert_eq "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $NEW_ENT" 1)" "4294967295" "and the second put away"
code="$(call_as "$WRONG_AUD" play_character "[$A_ENT]")"
check "$([ "$code" != "200" ] && echo true || echo false)" "nobody else plays her character ($code)"
ok_as "$ALICE" set_player_name '["Alice"]'
assert_eq "$(sql_first "SELECT entity_id FROM player WHERE identity = 0x$A_ID" 1)" "$A_ENT" "her own sign-in takes it back (the last played)"
assert_eq "$(row_count "SELECT * FROM player WHERE identity = 0x$G_ID")" "0" "from the machine that had it"
code="$(call_as "$WRONG_AUD" set_player_name '["Alice"]')"
check "$(grep -qi "taken" "$work/last" && echo true || echo false)" "her name is hers"

echo "== an offline character is parked, and comes back where it stood =="
spacetime call "$DB" set_rule foundation.park_offline_s 2 '""' >/dev/null 2>&1
HOME_CHUNK="$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $A_ENT" 1)"
sleep 5
assert_eq "$(sql_first "SELECT online FROM player WHERE identity = 0x$A_ID" 1)" "false" "(she is offline)"
assert_eq "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $A_ENT" 1)" "4294967295" "after the rule's time she is put away"
assert_eq "$(row_count "SELECT * FROM movement_state WHERE world_id = 0 AND chunk = $HOME_CHUNK AND entity_id = $A_ENT")" "0" \
  "in no cell anyone is sent"
ok_as "$ALICE" set_player_name '["Alice"]'
assert_eq "$(sql_first "SELECT chunk FROM movement_state WHERE entity_id = $A_ENT" 1)" "$HOME_CHUNK" "signing in brings her back where she stood"
assert_eq "$(sql_first "SELECT chunk FROM health_state WHERE entity_id = $A_ENT" 1)" "$HOME_CHUNK" "with everything of hers"
spacetime call "$DB" set_rule foundation.park_offline_s 0 '""' >/dev/null 2>&1

echo "== a real client signs in, and comes back silently =="
# Boot's own sign-in (SignIn): PKCE, the answer heard on 127.0.0.1, the ID token connected with, the
# refresh token kept beside the identity's token file. The browser's part is played in-process.
if [ -z "${GODOT:-}" ]; then
  echo "  (skipped: GODOT is not set)"
else
  userdir="$("$GODOT" --headless --path . --quit-after 1 -s res://tools/print_user_dir.gd 2>/dev/null | sed -n 's/^USER_DIR=//p' | tr -d '\r')"
  kept="$userdir/spacetime_token_accounts_carol.sign_in.cfg"
  rm -f "$kept" "$userdir/spacetime_token_accounts_carol.txt"
  flags=(--token=accounts_carol "--sign-in-issuer=$ISS" "--sign-in-client=$AUD" --sign-in-port=53699)
  client() { "$GODOT" --headless --path . res://tests/accounts/sign_in_client.tscn -- "${flags[@]}" "$@" 2>&1 | tee -a "$work/client.log" | sed -n 's/^SIGNED_IN //p' | tr -d '\r'; }
  run1="$(client --sign-in-as=carol)"
  C_ENT="$(echo "$run1" | sed -n 's/.*entity=\([0-9]*\).*/\1/p')"
  check "$(echo "$run1" | grep -q "signed=true" && [ -n "$C_ENT" ] && echo true || echo false)" "a client signs in through the service and plays ($run1)"
  C_IDENT="$(sql_first "SELECT identity FROM player WHERE entity_id = ${C_ENT:-0}" 1)"
  assert_eq "$(sql_first "SELECT method FROM account_login WHERE identity = ${C_IDENT:-0x00}" 1)" "1" "as a new account's character"
  check "$([ -f "$kept" ] && echo true || echo false)" "the sign-in is kept for next time"
  run2="$(client)"
  assert_eq "$(echo "$run2" | sed -n 's/.*entity=\([0-9]*\).*/\1/p')" "$C_ENT" "the next launch signs in silently, as the same character ($run2)"
  rm -f "$kept"
  run3="$(client)"
  G2="$(echo "$run3" | sed -n 's/.*entity=\([0-9]*\).*/\1/p')"
  check "$(echo "$run3" | grep -q "signed=false" && [ -n "$G2" ] && [ "$G2" != "$C_ENT" ] && echo true || echo false)" \
    "signed out, the machine plays as a guest of its own ($run3)"
  if grep -q "SCRIPT ERROR" "$work/client.log"; then check false "the client ran without script errors"; grep "SCRIPT ERROR" "$work/client.log" | head -3 >&2; fi
  rm -f "$kept" "$userdir/spacetime_token_accounts_carol.txt"
fi

echo "== a game that takes no guests =="
spacetime call "$DB" set_rule foundation.guests_allowed 0 '""' >/dev/null 2>&1
STRANGER="$(curl -s -X POST "$HOST/v1/identity" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['token'])")"
call_as "$STRANGER" set_player_name '["Stranger"]' >/dev/null
S_ID="$(identity_of "$STRANGER")"
assert_eq "$(row_count "SELECT * FROM player WHERE identity = 0x$S_ID")" "0" "gives someone who has not signed in no character"
BOB="$(mint --sub bob --aud "$AUD")"
ok_as "$BOB" set_player_name '["Bob"]'
B_ID="$(identity_of "$BOB")"
assert_eq "$(row_count "SELECT * FROM player WHERE identity = 0x$B_ID")" "1" "while a sign-in still gets one"
spacetime call "$DB" set_rule foundation.guests_allowed 1 '""' >/dev/null 2>&1
spacetime call "$DB" set_rule foundation.characters_per_account 1 '""' >/dev/null 2>&1

echo
echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ] || exit 1
