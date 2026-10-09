# FISHING'S PART OF tests/integration_test.sh, sourced there by run_genre_hooks (it sees the suite's
# helpers and variables: $DB, $MYENT, assert_ok, sql_first...). Moved verbatim (the template split).

echo "== FISHING GENRE: the full loop =="
# Fishing needs water, so this section runs on the lakeside, from where a player would fish: the
# end of the dock (dry deck at y = 0.9; the lake starts at z = 22). The catalogue, the spots and
# the gear are compiled into the module from shared/fishing/fishing.json — there is no table to
# seed. Every cast is a POINT on the water; the server decides what is there.
assert_ok "use_level 0 1" "fishing runs on the lakeside"
assert_ok 'teleport {"x":0.0,"y":0.9,"z":24.0}' "stand at the end of the dock"
cast_at() { printf '{"x":%s,"y":0.0,"z":%s}' "$1" "$2"; }
# THE FIGHT, played from a shell: a bot plays the cast's fight in the client's own simulation
# (tools/fishing/fight_bot_cli.gd, FightSim) and prints what a client would submit — the
# reaction and the fight's input log — which the module then REPLAYS through genre::fight.
# fight_for PAYLOAD REACTION BOT [--cut]  -> FIGHT_RESULT, FIGHT_OUTCOME, FIGHT_S, FIGHT_COMBO
GODOT="${GODOT:-godot}"
fight_for() {
  local out
  out="$("$GODOT" --headless --path . --script res://tools/fishing/fight_bot_cli.gd -- \
    --payload="$1" --reaction="$2" --bot="$3" ${4:-} 2>&1)"
  FIGHT_RESULT="$(printf '%s\n' "$out" | grep '^RESULT ' | sed 's/^RESULT //' | tr -d '\r')"
  FIGHT_OUTCOME="$(printf '%s\n' "$out" | grep -oE '^OUTCOME [a-z]+' | awk '{print $2}')"
  FIGHT_S="$(printf '%s\n' "$out" | grep -oE 'seconds=[0-9.]+' | cut -d= -f2)"
  FIGHT_COMBO="$(printf '%s\n' "$out" | grep -oE 'combo=[0-9]+' | cut -d= -f2)"
  [ -n "$FIGHT_RESULT" ] || echo "  fight_for: the bot printed no result: $(printf '%s' "$out" | tail -3)" >&2
}
# Wait out a bite, a reaction and a fight, as a player would have: the module refuses a fight
# that finished faster than the clock allows.
wait_out() { sleep "$(python -c "print(float('$1') + float('$2') + float('${3:-0}') + 0.6)")"; }
fish_payload() { sql_first 'SELECT payload FROM challenge WHERE kind = 100' 1; }
# One field of a cast's payload (the owner's private copy of what the server rolled).
pfield() { python -c 'import json,sys; print(str(json.loads(sys.argv[1][1:-1])[sys.argv[2]]).lower())' "$1" "$2"; }
coins_of() { sql_first "SELECT coins FROM session_member WHERE entity_id = $MYENT" 1; }
score_of() { sql_first "SELECT score FROM session_member WHERE entity_id = $MYENT" 1; }

# Force LOBBY rather than assuming the suite got here inside the session's first 30 s.
assert_ok "set_session_phase 1 0" "force the session back to LOBBY for the phase-gate check"
assert_rejected "cast $(cast_at 0.0 10.0)" "PLAYING phase" "casting outside the PLAYING phase is refused"
assert_ok "set_session_phase 1 1" "admin can force a session phase for testing"
assert_eq "$(sql_first 'SELECT phase FROM session' 1)" "1" "session is in PLAYING"
# ...for as long as shared/rules.json plans PLAYING to last (DECISIONS #154).
PLAY_ENDS="$(sql_first 'SELECT phase_ends_at FROM session WHERE id = 1' 1)"
PLAY_LEFT="$(python - "$PLAY_ENDS" <<'PY'
import sys, re, datetime
raw = sys.argv[1].strip()
m = re.match(r"(\d{4}-\d\d-\d\d)[T ](\d\d:\d\d:\d\d)(\.\d+)?\s*(Z|[+-]\d\d:?\d\d)?", raw)
if not m:
    print("unparsed:" + raw); sys.exit()
frac = (m.group(3) or ".0")[:7]
tz = m.group(4) or "+00:00"
tz = "+00:00" if tz == "Z" else (tz if ":" in tz else tz[:3] + ":" + tz[3:])
ends = datetime.datetime.fromisoformat(f"{m.group(1)}T{m.group(2)}{frac}{tz}")
print(round((ends - datetime.datetime.now(datetime.timezone.utc)).total_seconds()))
PY
)"
PLAY_PLAN="$(python -c "import json; d=json.load(open('shared/rules.json')); print([p['seconds'] for s in d['sessions'] if s['kind']==0 for p in s['phases'] if p['phase']==1][0])")"
check "$(python -c "print('true' if abs(float('$PLAY_LEFT') - float('$PLAY_PLAN')) <= 5 else 'false')" 2>/dev/null || echo false)" \
  "PLAYING lasts shared/rules.json's ${PLAY_PLAN} s (it ends in ${PLAY_LEFT} s)"

# WHERE A FLOAT MAY GO, each check at its own boundary.
assert_rejected "cast $(cast_at 0.0 21.0)" "at your feet" "a float dropped 3 m away is not a cast"
assert_rejected "cast $(cast_at 0.0 -30.0)" "further than" "54 m out is further than the starting rod reaches"
assert_rejected "cast $(cast_at 0.0 40.0)" "dry land" "the pier behind us is dry land"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "and none of those issued anything"

# A GOOD CAST, 14 m out, inside the Dock End spot.
assert_rejected "show_fight 1 0.5 5.0" "no line out" "a fight cannot be shown without a line out (DECISIONS #170)"
assert_ok "cast $(cast_at 0.0 10.0)" "a cast 14 m out over the lake is accepted"
assert_eq "$(row_count 'SELECT * FROM challenge WHERE kind = 100')" "1" "a cast issues exactly one fishing challenge"
assert_rejected "cast $(cast_at 2.0 10.0)" "already have a line out" "a second cast is refused while a line is out"
PAYLOAD="$(fish_payload)"
echo "  the roll: $PAYLOAD"
CATCH="$(pfield "$PAYLOAD" catch)"; KG="$(pfield "$PAYLOAD" kg)"; BITE="$(pfield "$PAYLOAD" bite)"
check "$(python -c "import json; d=json.load(open('shared/fishing/fishing.json')); print(str(any(c['id']=='$CATCH' for c in d['catches'])).lower())")" \
  "the roll is a catch the catalogue has ($CATCH)"
assert_eq "$(pfield "$PAYLOAD" spot)" "dock_end" "and it knows which spot the float is in"
assert_eq "$(pfield "$PAYLOAD" window_mult)" "1" "the starting reel's hook-set window (x1)"
# The fastest is the spot's AND the round's (DECISIONS #168): round 1 is dawn, and its weather
# speeds bites too, so the floor is read off the round's conditions, not the spot's alone.
TOD="$(sql_first 'SELECT time_of_day FROM fishing_conditions WHERE world_id = 0' 1)"
WX="$(sql_first 'SELECT weather FROM fishing_conditions WHERE world_id = 0' 1)"
check "$(python -c "
import json; d=json.load(open('shared/fishing/fishing.json')); t=d['timing']; c=d['conditions']
fast=t['bite_min_s']/(d['spots']['dock_end']['bite_speed']*c['times'][$TOD]['bite_speed']*c['weather'][$WX]['bite_speed'])
print(str(fast - 1e-3 <= float('$BITE') <= t['bite_cap_s']).lower())")" \
  "the bite is due between the Dock End's fastest under this round's sky and the cap ($BITE s)"
check "$(python -c "
import json; d=json.load(open('shared/fishing/fishing.json'))
print(str(('$(pfield "$PAYLOAD" deadlift)' == 'true') == (float('$KG') > d['gear']['line'][0]['max_load_kg'])).lower())")" \
  "a DEADLIFT is exactly a catch heavier than the line holds ($KG kg on the starting line)"

# THE PUBLIC HALF, AND THE PRIVATE HALF. Everyone may see where a float is; only the angler may
# know what is under it or when it will bite — the roll is in a private table, and in the owner's
# challenge (RLS).
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "1" "a cast puts one public line in the water"
assert_eq "$(sql_first "SELECT spot FROM fishing_line WHERE entity_id = $MYENT" 1)" '"dock_end"' "in the spot it went into"
assert_eq "$(sql_first "SELECT challenge_id FROM fishing_line WHERE entity_id = $MYENT" 1)" \
  "$(sql_first 'SELECT id FROM challenge WHERE kind = 100' 1)" "tied to the challenge it belongs to"
assert_eq "$(sql_rows_anon 'SELECT * FROM fishing_line' | wc -l | tr -d ' ')" "1" "ANOTHER client sees the line"
assert_eq "$(sql_rows_anon 'SELECT * FROM challenge' | wc -l | tr -d ' ')" "0" \
  "but not the challenge behind it, which carries the roll"
assert_eq "$(sql_rows_anon 'SELECT * FROM fishing_cast' | wc -l | tr -d ' ')" "0" \
  "nor the server's own record of it"
assert_eq "$(row_count 'SELECT * FROM fishing_cast')" "1" "which the server does keep"

# THE FIGHT, SHOWN (DECISIONS #170): the owner reports what it looks like; the module only bounds it.
assert_ok "show_fight 2 0.7 9.5" "the angler shows their fight"
assert_eq "$(sql_first "SELECT state FROM fight_show WHERE entity_id = $MYENT" 1)" "2" "the sweet spot, for everyone"
assert_eq "$(sql_rows_anon "SELECT * FROM fight_show WHERE entity_id = $MYENT" | wc -l | tr -d ' ')" "1" "public: another client sees it"
assert_rejected "show_fight 9 0.5 5.0" "not a fight state" "a state there is not is refused"
assert_ok "show_fight 3 7.0 999.0" "numbers out of range are taken..."
assert_eq "$(sql_first "SELECT load FROM fight_show WHERE entity_id = $MYENT" 1)" "1" "...the load at most 1"
assert_eq "$(sql_first "SELECT line_m FROM fight_show WHERE entity_id = $MYENT" 1)" "16" "...the line at most the cast's range and its slack (14 + 2 m)"
check "$([ "$(pfield "$PAYLOAD" range_cm)" = "1400" ] && echo true || echo false)" \
  "the fight's range is carried in whole centimetres, so both sides compute the same metres ($(pfield "$PAYLOAD" range_cm))"
check "$(python -c "print(str(int('$(pfield "$PAYLOAD" fight_seed)') > 0).lower())")" "and so is its random stream's seed"
assert_eq "$(pfield "$PAYLOAD" rod) $(pfield "$PAYLOAD" reel) $(pfield "$PAYLOAD" line)" "0 0 0" \
  "and the gear it is fought with, fixed at the cast"

# SET THE HOOK AND PLAY THE FIGHT, honestly: a 0.2 s reaction (PERFECT), then an ace's fight,
# submitted only once the bite, the reaction and the fight could all have happened.
CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
COINS_BEFORE="$(coins_of)"; SCORE_BEFORE="$(score_of)"
fight_for "$PAYLOAD" 0.2 ace
echo "  the fight: $FIGHT_OUTCOME in $FIGHT_S s, best combo $FIGHT_COMBO"
assert_eq "$FIGHT_OUTCOME" "landed" "the client's simulation lands it"
wait_out "$BITE" 0.2 "$FIGHT_S"
assert_ok "submit_challenge_result $CID $FIGHT_RESULT" "submit the hook-set and the fight's input log"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "the module's REPLAY lands it too: exactly one catch row"
assert_eq "$(sql_first 'SELECT best_combo FROM catch' 1)" "$FIGHT_COMBO" "with the combo the fight had"
check "$(python -c "print(str(abs(float('$(sql_first 'SELECT fight_s FROM catch' 1)') - float('$FIGHT_S')) < 0.02).lower())")" \
  "and the fight's length, off the module's own replay ($FIGHT_S s)"
assert_eq "$(sql_first 'SELECT clean FROM catch' 1)" "true" "a perfect set and an ace's rhythm is a clean catch"
assert_eq "$(sql_first 'SELECT owner_entity_id FROM catch' 1)" "$MYENT" "the catch belongs to the caster"
assert_eq "$(sql_first 'SELECT catch_key FROM catch' 1)" "\"$CATCH\"" "and it is what the roll put on the line"
check "$(python -c "print(str(abs(float('$(sql_first 'SELECT kg FROM catch' 1)') - float('$KG')) < 1e-4).lower())")" \
  "at the weight it was rolled at ($KG kg)"
assert_eq "$(sql_first 'SELECT hookset FROM catch' 1)" "0" "graded PERFECT (0)"
assert_eq "$(sql_first 'SELECT round FROM catch' 1)" "1" "stamped with the session round"
PAID="$(sql_first 'SELECT coins FROM catch' 1)"
check "$([ "${PAID:-0}" -gt 0 ] && echo true || echo false)" "it is worth something ($PAID coins)"
assert_eq "$(( $(coins_of) - COINS_BEFORE ))" "$PAID" "and exactly that was paid"
check "$([ "$(score_of)" -gt "$SCORE_BEFORE" ] && echo true || echo false)" "and scored ($SCORE_BEFORE -> $(score_of))"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "the challenge was consumed"
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "0" "the line came in"
assert_eq "$(row_count 'SELECT * FROM fight_show')" "0" "and the fight's show with it"
assert_eq "$(row_count 'SELECT * FROM fishing_cast')" "0" "and the server's record of the cast went with it"
RICH="$(sql_first "SELECT richness FROM fishing_spot WHERE key = 'lakeside:dock_end'" 1)"
check "$(python -c "print(str(abs(float('${RICH:-1}') - (1.0 - 0.08)) < 0.01).lower())")" \
  "the Dock End is a little fished out: richness $RICH (1 - one catch's 0.08)"

# A FIGHT THE CLOCK SAYS IS IMPOSSIBLE: a perfectly good fight, submitted before the bite and the
# fight could have happened. The server does not believe it, and the cast is spent. "Before" is
# measured, not assumed: the bot takes seconds to start, and a short fight (a tankard) can be over
# by then — so a cast whose claim could no longer be early is reeled in and another one made.
early=""
for _ in 1 2 3 4; do
  assert_ok "cast $(cast_at 0.0 10.0)" "cast again"
  T0="$(python -c "import time; print(time.time())")"
  PAYLOAD="$(fish_payload)"; CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
  fight_for "$PAYLOAD" 0.2 ace
  if python -c "import sys, time; sys.exit(0 if time.time() - $T0 + 1.5 < float('$(pfield "$PAYLOAD" bite)') + 0.2 + float('${FIGHT_S:-0}') else 1)"; then
    assert_ok "submit_challenge_result $CID $FIGHT_RESULT" "submit a winning fight before it could have been fought"
    early="yes"
    break
  fi
  spacetime call "$DB" reel_in >/dev/null 2>&1
done
check "$([ -n "$early" ] && echo true || echo false)" "a fight was submitted provably early (in 4 casts)"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "a fight faster than time lands nothing"
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "0" "and costs the cast: the line is gone"

# A FIGHT THAT SNAPPED: a masher never lets go. The module replays the same snap.
assert_ok "cast $(cast_at 0.0 10.0)" "cast again"
PAYLOAD="$(fish_payload)"; CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
fight_for "$PAYLOAD" 0.2 masher
assert_eq "$FIGHT_OUTCOME" "snapped" "a masher snaps the line in the client's simulation"
wait_out "$(pfield "$PAYLOAD" bite)" 0.2 "$FIGHT_S"
assert_ok "submit_challenge_result $CID $FIGHT_RESULT" "submit the snapped fight"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "and in the module's: nothing landed"

# A FIGHT CUT SHORT: half a winning fight's log is an undecided fight, not a catch.
assert_ok "cast $(cast_at 0.0 10.0)" "cast again"
PAYLOAD="$(fish_payload)"; CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
fight_for "$PAYLOAD" 0.2 ace --cut
assert_eq "$FIGHT_OUTCOME" "fighting" "half the log leaves the fight undecided"
wait_out "$(pfield "$PAYLOAD" bite)" 0.2 "$FIGHT_S"
assert_ok "submit_challenge_result $CID $FIGHT_RESULT" "submit half a fight"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "lands nothing"

# A FORGED LOG: half a tick is not an input anyone pressed.
assert_ok "cast $(cast_at 0.0 10.0)" "cast again"
BITE="$(pfield "$(fish_payload)" bite)"; CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
wait_out "$BITE" 0.2 5
assert_ok "submit_challenge_result $CID [0.2,1,90.5,1,0]" "submit a log with half a tick in it"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "a forged log lands nothing"

# TOO SLOW: past the reel's window the fish spits the hook, whatever the fight would have been.
assert_ok "cast $(cast_at 0.0 10.0)" "cast again"
PAYLOAD="$(fish_payload)"; BITE="$(pfield "$PAYLOAD" bite)"
CID=$(sql_first "SELECT id FROM challenge WHERE kind = 100" 1)
fight_for "$PAYLOAD" 1.2 ace
wait_out "$BITE" 1.2 "$FIGHT_S"
assert_ok "submit_challenge_result $CID $FIGHT_RESULT" "a hook-set 1.2 s after the bite"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "is too slow on the starting reel: nothing landed"

# REEL IN: a line with nothing on it yet comes back out, and takes its private roll with it.
assert_ok "cast $(cast_at 0.0 10.0)" "cast again"
assert_ok "reel_in" "reel in before the bite"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "the cast is over"
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "0" "the float is out of the water for everyone"
assert_eq "$(row_count 'SELECT * FROM fishing_cast')" "0" "and the roll is gone"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "with nothing caught"
assert_rejected "reel_in" "no line out" "reeling in with no line out is refused"

# A non-fishing challenge must NOT produce a catch: the hook checks the challenge's kind.
assert_ok "issue_challenge $MYENT 0 0.5" "issue a plain (non-fishing) challenge"
CID2=$(sql_first "SELECT id FROM challenge" 1)
assert_ok "submit_challenge_result $CID2 [0.5,0.5,0.5]" "submit the plain challenge"
assert_eq "$(row_count 'SELECT * FROM catch')" "1" "a non-fishing challenge produces no catch"

# THE BELL CLOSES THE WATER (DECISIONS #161): when the round's PLAYING ends, a line nothing has
# bitten comes in; one that has bitten plays out through the results (you finish what you hooked).
# Left out, a waiting line got its bite during the results, under the results panel.
BITE=0
# Twenty tries: at the dock a bite comes 1.4-5 s out, so six missed about one run in 150 (seen).
for _ in $(seq 1 20); do   # a roll that bites soon could bite before the bell: roll again
  spacetime call "$DB" cast "$(cast_at 0.0 10.0)" >/dev/null 2>&1
  BITE=$(sql_first "SELECT bite_s FROM fishing_cast" 1)
  [ -n "$BITE" ] && python -c "import sys; sys.exit(0 if float('$BITE') >= 3.0 else 1)" && break
  spacetime call "$DB" reel_in >/dev/null 2>&1
done
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "1" "a line is out, biting after ${BITE} s"
assert_ok "set_session_phase 1 2" "the round ends before the bite"
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "0" "the bell brings in the line nothing had bitten"
assert_eq "$(row_count 'SELECT * FROM fishing_cast')" "0" "and its roll goes with it"
assert_eq "$(row_count 'SELECT * FROM challenge')" "0" "and its challenge"
assert_ok "set_session_phase 1 1" "PLAYING again"
assert_ok "cast $(cast_at 0.0 10.0)" "cast, and let it bite"
BITE=$(sql_first "SELECT bite_s FROM fishing_cast" 1)
sleep "$(python -c "import math; print(math.ceil(float('$BITE')) + 1)")"
assert_ok "set_session_phase 1 2" "the round ends after the bite"
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "1" \
  "CONTROL: a line that has bitten (after ${BITE} s) stays out through the results, to be fought"
assert_ok "reel_in" "reel that one in"
assert_ok "set_session_phase 1 1" "and back to PLAYING for the rest"

# AN ABANDONED CAST: the player walks off and never sets the hook. The challenge expires after
# the line's life (line_life_s) and is pruned; its public line has to go with it, through the
# same hook, or everyone else watches this angler fish a lake they left long ago. Checked much
# later ("the abandoned cast expired"), so the sections in between pay for the wait.
assert_ok "cast $(cast_at 0.0 10.0)" "cast, then walk away without setting the hook"
ABANDONED_AT=$(date +%s)
assert_eq "$(row_count 'SELECT * FROM fishing_line')" "1" "the abandoned cast's line is in the water"
# The sections below were written against the greybox, with the admin's player at the origin.
assert_ok "use_level 0 0" "back to the greybox"
assert_ok 'teleport {"x":0.0,"y":0.0,"z":0.0}' "and home"
