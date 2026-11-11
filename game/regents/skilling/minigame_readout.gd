class_name MinigameReadout extends RefCounted
## THE DIFFICULTY READOUT (`MINIGAMES_PREP.md` §6; Luke's M4, 2026-11-05: quality = the score, the difficulty tuned
## so the grades come out at target shares): simulated players of set skill (`SimPlayer`) play many seeds of a
## round through its own model, and the readout says how the scores fall: the mean, and the share that would be
## Fine and Masterwork (a part made at the anvil) or beat AFK (a gathering or smelting round). The skilling lab
## shows it for the round on show (T); the unit suite pins what it must stay. A guide for tuning, never the last
## word: Luke's own play is.
##
## Every simulated round is a real one: its inputs are what a client would send, and each is replayed through
## `SkillMinigames.play` and checked against what the bot saw (`agree`). Deterministic: the same params, player
## and seeds give the same readout.

const ROUNDS: int = 200


## One round of `p` from `seed_value`, played by `sim`: {inputs (flat, as a client sends them), live (the round's
## result as the bot saw it played, on its own model)}.
static func play_round(seed_value: int, p: Resource, sim: SimPlayer) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, sim.display_name, sim.react_ms, sim.jitter_ms, sim.aim_pm, sim.slip_pct])
	match SkillMinigames.kind_of(p):
		SkillMinigames.CHOP:
			return _chop(seed_value, p as ChopParams, sim, rng)
		SkillMinigames.CRACK:
			return _crack(seed_value, p as CrackParams, sim, rng)
		SkillMinigames.SMELT:
			return _smelt(seed_value, p as SmeltParams, sim, rng)
		SkillMinigames.SHAPE:
			return _shape(seed_value, p as ShapeParams, sim, rng)
		SkillMinigames.BEAT:
			return _beat(seed_value, p as BeatParams, sim, rng)
		SkillMinigames.CARVE:
			return _carve(seed_value, p as CarveParams, sim, rng)
		SkillMinigames.PULL:
			return _pull(seed_value, p as PullParams, sim, rng)
		SkillMinigames.SKIN:
			return _skin(seed_value, p as SkinParams, sim, rng)
	return {"inputs": PackedInt32Array(), "live": {}}


## `rounds` rounds of `p` by `sim` (seeds `first_seed` on): {mean (‰), fine_pct, masterwork_pct, beats_afk_pct,
## scores, agree (every replay matched what was played)}.
static func measure(p: Resource, sim: SimPlayer, rounds: int = ROUNDS, first_seed: int = 1) -> Dictionary:
	var scores: PackedInt32Array = PackedInt32Array()
	var agree: bool = true
	var cuts: Vector2i = grade_cuts()
	var afk: int = afk_break_even_pm()
	var fine: int = 0
	var mw: int = 0
	var beats: int = 0
	var total: int = 0
	for i: int in rounds:
		var s: int = first_seed + i * 7919
		var played: Dictionary = play_round(s, p, sim)
		var r: Dictionary = SkillMinigames.play(s, p, played["inputs"])
		var sc: int = int(r.get("score_pm", 0))
		agree = agree and r == played["live"]
		scores.append(sc)
		total += sc
		fine += int(sc >= cuts.x)
		mw += int(sc >= cuts.y)
		beats += int(sc >= afk)
	var n: int = maxi(1, rounds)
	return {"player": sim.display_name, "mean": total / n, "fine_pct": fine * 100 / n, "masterwork_pct": mw * 100 / n,
		"beats_afk_pct": beats * 100 / n, "scores": scores, "agree": agree}


## Every preset on `p`: one line each.
static func report(p: Resource, rounds: int = ROUNDS) -> String:
	var making: bool = SkillMinigames.kind_of(p) == SkillMinigames.SHAPE or SkillMinigames.kind_of(p) == SkillMinigames.CARVE
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s: %d rounds each%s" % [String(p.get(&"display_name")), rounds,
		"  (Fine at %d%%, Masterwork at %d%%)" % [grade_cuts().x / 10, grade_cuts().y / 10] if making
		else "  (AFK pays the same at a %d%% score)" % [afk_break_even_pm() / 10]])
	for sim: SimPlayer in SimPlayer.presets():
		var m: Dictionary = measure(p, sim, rounds)
		if making:
			lines.append("%-9s  mean %3d%%   Common %3d%%   Fine %3d%%   Masterwork %3d%%%s" % [sim.display_name, int(m["mean"]) / 10,
				100 - int(m["fine_pct"]), int(m["fine_pct"]) - int(m["masterwork_pct"]), m["masterwork_pct"], "" if m["agree"] else "   REPLAY DISAGREES"])
		else:
			lines.append("%-9s  mean %3d%%   beats AFK %3d%%%s" % [sim.display_name, int(m["mean"]) / 10, m["beats_afk_pct"],
				"" if m["agree"] else "   REPLAY DISAGREES"])
	# Luke's M3 and M4 (2026-11-05): rank eases the round; the targets are a fresh band Fine ~50 %, Masterwork ~10 %,
	# and three ranks on Masterwork ~33 %. The same players on the round as eased at the most ranks count for.
	var most: int = most_ease_pct()
	if making and most > 0:
		var eased: Resource = SkillMinigames.eased(p, most)
		lines.append("  %d ranks on (%d %% easier):" % [int(HotRules.number(&"regents.rank_ease_ranks")), most])
		for sim: SimPlayer in SimPlayer.presets():
			var m2: Dictionary = measure(eased, sim, rounds)
			lines.append("%-9s  mean %3d%%   Common %3d%%   Fine %3d%%   Masterwork %3d%%%s" % [sim.display_name, int(m2["mean"]) / 10,
				100 - int(m2["fine_pct"]), int(m2["fine_pct"]) - int(m2["masterwork_pct"]), m2["masterwork_pct"], "" if m2["agree"] else "   REPLAY DISAGREES"])
	return "\n".join(lines)


## The most rank eases a round (`regents.rank_ease_pct` x `regents.rank_ease_ranks`, as the server works it out).
static func most_ease_pct() -> int:
	return mini(50, roundi(maxf(0.0, HotRules.number(&"regents.rank_ease_pct")) * maxf(0.0, HotRules.number(&"regents.rank_ease_ranks"))))


## The grade cut points now (`regents.grade_fine_q`, `regents.grade_masterwork_q`), as qualities (‰).
static func grade_cuts() -> Vector2i:
	var fine: int = int(HotRules.number(&"regents.grade_fine_q"))
	return Vector2i(fine, maxi(fine, int(HotRules.number(&"regents.grade_masterwork_q"))))


## The score at which a played gathering or smelting round pays what AFK would in its time (`SkillingRules`: pay runs
## from `regents.active_yield_floor` at 0 to `regents.active_yield_mult` at a full score; Luke's M11 put it near half).
static func afk_break_even_pm() -> int:
	return SkillingRules.break_even_pm(HotRules.number(&"regents.active_yield_mult"), HotRules.number(&"regents.active_yield_floor"))


## A time `mean` ms from now give or take the player's spread, never before `floor_ms`.
static func _at(mean: int, sim: SimPlayer, rng: RandomNumberGenerator, floor_ms: int) -> int:
	return maxi(floor_ms, mean + roundi(rng.randfn(0.0, float(sim.jitter_ms))))


static func _slips(sim: SimPlayer, rng: RandomNumberGenerator) -> bool:
	return sim.slip_pct > 0 and rng.randi_range(1, 100) <= sim.slip_pct


## BRANCH DODGE: chop from the side the branch at your head is not on, as soon as you have seen the trunk drop.
static func _chop(seed_value: int, p: ChopParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: ChopModel = ChopModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var seen: int = 0   # when the round last changed
	var last: int = 0
	for _guard: int in 2000:
		var aim: int = (m.next_ok_ms + sim.react_ms / 2) if m.staggered else (seen + sim.react_ms)
		var t: int = _at(aim, sim, rng, last)
		if t > p.duration_ms:
			break
		var side: int = m.side
		if m.head_branch() == ChopModel.BRANCH_LEFT:
			side = ChopModel.SIDE_RIGHT
		elif m.head_branch() == ChopModel.BRANCH_RIGHT:
			side = ChopModel.SIDE_LEFT
		if _slips(sim, rng):
			side = ChopModel.SIDE_LEFT if side == ChopModel.SIDE_RIGHT else ChopModel.SIDE_RIGHT
		out.append_array(PackedInt32Array([t, side]))
		var did: int = m.chop(t, side)
		if did == ChopModel.HELD:
			m.settle(m.held_at_ms)
		last = maxi(t, m.last_act_ms)
		seen = m.last_act_ms if did != ChopModel.IGNORED else t
	m.finish()
	return {"inputs": out, "live": m.result()}


## FOLLOW THE SEAM: strike the glowing notch once you have seen it, as near it as your hand lands.
static func _crack(seed_value: int, p: CrackParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: CrackModel = CrackModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var seen: int = 0
	var last: int = 0
	for _guard: int in 2000:
		var aim: int = (m.next_ok_ms + sim.react_ms / 2) if m.staggered else (seen + sim.react_ms)
		var slip: bool = _slips(sim, rng)
		# A brittle notch (band 2): they wait for the ring to fade, a little after it (a slip: they do not).
		if m.is_brittle(m.k) and m.last_hit_ms >= 0 and not slip:
			aim = maxi(aim, m.last_hit_ms + p.ring_ms + 2 * sim.jitter_ms)
		var t: int = _at(aim, sim, rng, last)
		if t > p.duration_ms:
			break
		var at: Vector2i = m.notch(m.k + (1 if slip and not m.is_brittle(m.k) else 0))
		var x: int = clampi(at.x + roundi(rng.randfn(0.0, float(sim.aim_pm))), 0, 1000)
		var y: int = clampi(at.y + roundi(rng.randfn(0.0, float(sim.aim_pm))), 0, 1000)
		out.append_array(PackedInt32Array([t, x, y]))
		var did: int = m.strike(t, x, y)
		if did == CrackModel.HELD:
			m.settle(m.held_at_ms)
		last = maxi(t, m.last_act_ms)
		seen = m.last_act_ms if did != CrackModel.IGNORED else t
	m.finish()
	return {"inputs": out, "live": m.result()}


## BELLOWS, THEN POUR: pump (as fast as the hand goes) while the heat, as read a moment ago, is under the band's
## middle; then tilt, and stop when the mold should be at the line.
static func _smelt(seed_value: int, p: SmeltParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: SmeltModel = SmeltModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var seen_heat: PackedInt32Array = PackedInt32Array()   # the heat after each tick, as the player saw it
	var gap: int = 1000 / maxi(1, sim.mash_hz)
	var next_pump: int = sim.react_ms
	var t: int = 0
	while t < p.heat_ms:
		m.advance_to(t)
		while seen_heat.size() <= m.tick:
			seen_heat.append(m.heat)
		if t >= next_pump:
			var read: int = seen_heat[maxi(0, m.tick - sim.react_ms / SmeltModel.TICK_MS)] + roundi(rng.randfn(0.0, float(sim.aim_pm)))
			var want: bool = read < m.band(m.tick).x
			if _slips(sim, rng):
				want = not want
			if want:
				out.append_array(PackedInt32Array([t, SmeltModel.PUMP]))
				m.press(t, SmeltModel.PUMP)
				next_pump = t + gap + absi(roundi(rng.randfn(0.0, float(sim.jitter_ms) / 4.0)))
		t += 10
	var tilt: int = _at(p.heat_ms + p.pour_ready_ms + sim.react_ms, sim, rng, p.heat_ms + p.pour_ready_ms)
	out.append_array(PackedInt32Array([tilt, SmeltModel.POUR]))
	m.press(tilt, SmeltModel.POUR)
	var ideal: int = tilt + m.target * SmeltModel.TICK_MS / maxi(1, p.pour_rate)
	var stop: int = _at(ideal + (300 if _slips(sim, rng) else 0), sim, rng, tilt + 10)
	out.append_array(PackedInt32Array([stop, SmeltModel.STOP]))
	m.press(stop, SmeltModel.STOP)
	m.finish()
	return {"inputs": out, "live": m.result()}


## SMELTING'S RHYTHM TRACK (Luke, 2026-11-07): a note is pressed on its time give or take the player's timing spread
## (a beat is felt ahead, not reacted to, so no reaction time); a tap let go a moment later, a long draw at its end
## (give or take). A slip loses the note: half the time it is not pressed at all, half the time pressed a beat
## wrong (a wasted press). Then the pour as in `_smelt`: tilt once it is ready and seen, stop at the line.
static func _beat(seed_value: int, p: BeatParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: BeatModel = BeatModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var last: int = 0
	for j: int in m.note_t.size():
		var t: int = m.note_t[j]
		if t < sim.react_ms:
			continue   # not yet with the beat (a real hand is, by the count-in's end; an absent one never)
		if _slips(sim, rng):
			if rng.randi_range(0, 1) == 0:
				continue   # missed it
			t += p.beat_ms / 4 * (1 if rng.randi_range(0, 1) == 0 else -1) + p.good_ms   # pressed off the beat
		var down: int = maxi(last + 1, t + roundi(rng.randfn(0.0, float(sim.jitter_ms))))
		if m.is_slag(j):   # slag (band 2's test): skimmed with the second button
			out.append_array(PackedInt32Array([down, BeatModel.SKIM]))
			m.press(down, BeatModel.SKIM)
			last = down
			continue
		var up: int = down + 60
		if m.note_end[j] > m.note_t[j]:
			up = maxi(down + 1, m.note_end[j] + roundi(rng.randfn(0.0, float(sim.jitter_ms))))
		out.append_array(PackedInt32Array([down, BeatModel.DOWN, up, BeatModel.UP]))
		m.press(down, BeatModel.DOWN)
		m.press(up, BeatModel.UP)
		last = up
	var end: int = BeatModel.track_end_ms(p)
	var tilt: int = _at(end + p.pour_ready_ms + sim.react_ms, sim, rng, maxi(last + 1, end + p.pour_ready_ms))
	out.append_array(PackedInt32Array([tilt, BeatModel.DOWN]))
	m.press(tilt, BeatModel.DOWN)
	var ideal: int = tilt + m.target * BeatModel.TICK_MS / maxi(1, p.pour_rate)
	var stop: int = _at(ideal + (300 if _slips(sim, rng) else 0), sim, rng, tilt + 10)
	out.append_array(PackedInt32Array([stop, BeatModel.UP]))
	m.press(stop, BeatModel.UP)
	m.finish()
	return {"inputs": out, "live": m.result()}


## WOODWORKING'S CARVE (Luke, 2026-11-07): they study the pattern and lift it, then cut the edge furthest past its
## profile as they remember it, a swing after the last: deep while a deep cut fits (with a unit to spare once the
## picture has blurred), then fine. Exact for `memory_strikes` cuts, then each profile a little off; one who
## `looks_again` lays the pattern on once more when every edge is within two of the line as remembered; a slip cuts the
## row beside the one meant. They set the piece down when nothing is past.
static func _carve(seed_value: int, p: CarveParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: CarveModel = CarveModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var mind_l: PackedInt32Array = m.target_left.duplicate()
	var mind_r: PackedInt32Array = m.target_right.duplicate()
	var since_look: int = 0
	var blurred: bool = false
	var looked_again: bool = false
	var t: int = sim.react_ms + 400
	if m.laid:
		_carve_send(m, out, t, CarveModel.LIFT)
	for _guard: int in 600:
		t = _at(maxi(t, m.next_ok_ms) + sim.react_ms / 3, sim, rng, t + 1)
		if t > p.duration_ms:
			break
		if p.hide_outline > 0 and since_look == sim.memory_strikes and not blurred:
			blurred = true
			for i: int in m.rows():
				mind_l[i] = m.target_left[i] + rng.randi_range(-1, 1)
				mind_r[i] = m.target_right[i] + rng.randi_range(-1, 1)
		var best: int = 0
		var code: int = -1
		for i: int in m.rows():
			for side: int in 2:
				var over: int = (m.left[i] - mind_l[i]) if side == 0 else (m.right[i] - mind_r[i])
				if over > best:
					best = over
					var deep: bool = over >= p.deep_cut + (1 if blurred else 0)
					code = (CarveModel.LEFT_DEEP if side == 0 else CarveModel.RIGHT_DEEP) + (0 if deep else 1000) + i
		if blurred and sim.looks_again and not looked_again and best <= 2:
			looked_again = true   # close to the line everywhere, and unsure: check the pattern
			_carve_send(m, out, t, CarveModel.LAY)
			t += sim.react_ms + 300
			_carve_send(m, out, t, CarveModel.LIFT)
			mind_l = m.target_left.duplicate()
			mind_r = m.target_right.duplicate()
			blurred = false
			since_look = -100000   # fresh from the pattern: it stays clear to the end
			continue
		if code < 0:
			break
		if _slips(sim, rng):
			var row: int = clampi(code % 1000 + (1 if rng.randi_range(0, 1) == 0 else -1), 0, m.rows() - 1)
			code = code / 1000 * 1000 + row
		_carve_send(m, out, t, code)
		since_look += 1
	_carve_send(m, out, mini(p.duration_ms, t + 50), CarveModel.DONE)
	m.finish()
	return {"inputs": out, "live": m.result()}


static func _carve_send(m: CarveModel, out: PackedInt32Array, t: int, code: int) -> void:
	out.append_array(PackedInt32Array([t, code]))
	m.press(t, code)


## SHAPE TO THE OUTLINE: once the last strike has landed, strike the column that brings the bar nearest the
## outline (planning) or the one that bulges most (a light tap once it is closer than a heavy strike's drop, when
## the round has taps); back in the fire when it is nearly too cold (before it goes red), while a heat is worth what
## it costs; stop when no strike would help. A player who plans plays the round both ways and keeps the better (on
## the pickaxe head the plain way scored a hair higher, 2026-11-05): the top lines are the round's ceiling, not one
## way of playing it.
## THE BANDS' RULES (2026-11-05): with a template they look, lift it, and work from MEMORY: exact for
## `memory_strikes`, then each column a little off; one who `looks_again` lays it on to check once the picture has
## blurred and only finishing is left (rough work needs no exact picture); with heats they set the
## part down when done, and with a quench they set it down in its window (a heat spent on it when the bar has gone
## too cold, if one is left).
static func _shape(seed_value: int, p: ShapeParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	if not sim.plans:
		return _shape_by(seed_value, p, sim, rng, false)
	var from: int = rng.state
	var planned: Dictionary = _shape_by(seed_value, p, sim, rng, true)
	rng.state = from
	var plain: Dictionary = _shape_by(seed_value, p, sim, rng, false)
	return planned if int(planned["live"]["score_pm"]) >= int(plain["live"]["score_pm"]) else plain


static func _shape_by(seed_value: int, p: ShapeParams, sim: SimPlayer, rng: RandomNumberGenerator, plans: bool) -> Dictionary:
	var m: ShapeModel = ShapeModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var seen: int = 0
	var last: int = 0
	var margin: int = sim.react_ms + 2 * sim.jitter_ms   # how near cold (or red) they reheat
	var since_look: int = 0
	var blurred: bool = false
	var mind: PackedInt32Array = m.outline.duplicate()   # the outline as they remember it
	var heat_worth: int = p.reheat_cost_pm * p.error_scale / 1000   # error a heat costs, in the outline's units
	for _guard: int in 3000:
		var t: int = _at(seen + sim.react_ms, sim, rng, last)
		if t > p.duration_ms or m.done_ms >= 0:
			break
		if m.laid:
			# Studying the pattern: as long as it takes to take in, then lift it and work from memory.
			t = maxi(t, last + sim.react_ms + 200)
			_send(m, out, t, ShapeModel.LIFT)
			since_look = 0
			blurred = false
			mind = m.outline.duplicate()
			seen = t
			last = t
			continue
		if p.hide_outline > 0 and since_look == sim.memory_strikes and not blurred:
			blurred = true
			for i: int in mind.size():
				mind[i] = m.outline[i] + rng.randi_range(-1, 1)   # the picture blurs
		var c: int = _shape_column(m, p, plans, mind)
		if blurred and sim.looks_again and (c < 0 or c >= ShapeModel.TAP):
			_send(m, out, t, ShapeModel.LAY)   # down to finishing, and unsure: check the pattern
			seen = t
			last = t
			continue
		var lands: int = maxi(t, m.next_ok_ms)   # a strike mid-swing lands when the swing ends
		var left: int = m.reheats_left()
		var going: bool = m.hot_until_ms - p.red_ms - lands < maxi(margin, 1)
		var worth: bool = left != 0 and (left < 0 or m.error() > heat_worth)
		if c < 0 or (going and not worth):
			if p.max_reheats <= 0:
				break   # no strike would bring it closer: done (a round on a clock)
			t = _quench_time(m, p, sim, rng, t, out)
			_send(m, out, t, ShapeModel.DONE)
			break
		var slip: bool = _slips(sim, rng)
		if going:
			if not slip:
				c = ShapeModel.REHEAT_COLUMN   # a slip here: struck anyway, maybe red or cold
		elif slip:
			var tap: int = ShapeModel.TAP if c >= ShapeModel.TAP else 0
			c = tap + clampi(c - tap + (1 if rng.randi_range(0, 1) == 1 else -1), 0, m.heights.size() - 1)
		var did: int = _send(m, out, t, c)
		if did == ShapeModel.HELD:
			m.settle(m.held_at_ms)
		if c != ShapeModel.REHEAT_COLUMN:
			since_look += 1
		last = maxi(t, m.last_act_ms)
		seen = m.last_act_ms if did != ShapeModel.IGNORED else t
	m.finish()
	return {"inputs": out, "live": m.result()}


## PULL THE ROOT (herbalism, 2026-11-08; the trowel's work after Luke's play): the puller looks every 50 ms. Each stem
## they DIG ROUND first, left then right until both sides are loose (a slip forgets the rest and starts pulling); a
## stroke a moment after the last is done (a third of their reaction, give or take their timing). Then they pull while
## the strain reads under PULL_HI (less their misreading, `aim_pm` x 5) and let go there, pulling again once it reads
## PULL_LO (they read it off the stem's stretch and creak, give or take their aim). When the soil CRACKS they stroke
## that side `react_ms` after it starts (a slip strokes the other side, which only digs); the stroke pauses the pull.
## Nobody sees where a side root is before its crack, nor how big its jump.
const PULL_HI: int = 880
const PULL_LO: int = 450


static func _pull(seed_value: int, p: PullParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: PullModel = PullModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var last: int = 0
	var crack_from: int = -1
	var crack_side: int = 0
	var plant: int = -1
	var dig_done: bool = false
	var t: int = 0
	while t <= p.duration_ms:
		m.advance_to(t)
		if m.plant != plant:
			plant = m.plant
			dig_done = false
		var show: int = m.showing()
		if show != crack_side:
			crack_side = show
			crack_from = t if show != 0 else -1
		var code: int = 0
		if not m.stroking(t):
			if show != 0 and t - crack_from >= sim.react_ms:
				code = show if not _slips(sim, rng) else (PullModel.RIGHT if show == PullModel.LEFT else PullModel.LEFT)
				crack_from = t + p.stroke_ms   # a missed one, seen again once the stroke is done
			elif not dig_done and m.up_by == 0 and m.pack_left + m.pack_right > 0:
				if _slips(sim, rng):
					dig_done = true
				else:
					code = PullModel.LEFT if m.pack_left >= m.pack_right and m.pack_left > 0 else PullModel.RIGHT
			else:
				dig_done = true
		if code != 0:
			var at: int = _at(maxi(t, m.stroke_until_ms) + sim.react_ms / 3, sim, rng, maxi(maxi(last, t), m.stroke_until_ms))
			if at > p.duration_ms:
				break
			out.append_array(PackedInt32Array([at, code]))
			m.press(at, code)
			last = at
		elif dig_done:
			var seen: int = m.strain + roundi(rng.randfn(0.0, float(sim.aim_pm * 5)))
			var want: bool = seen < PULL_HI - sim.aim_pm * 5 if m.down else seen <= PULL_LO
			if want != m.down:
				var at2: int = _at(t + sim.react_ms / 3, sim, rng, maxi(last, t))
				if at2 > p.duration_ms:
					break
				out.append_array(PackedInt32Array([at2, PullModel.DOWN if want else PullModel.UP]))
				m.press(at2, PullModel.DOWN if want else PullModel.UP)
				last = at2
		t = maxi(t + 50, last)
	m.finish()
	return {"inputs": out, "live": m.result()}


## THE CUT LINE (skinning): a hand on the knife, looking every 50 ms. A new line is pressed at its start `react_ms`
## after it shows (give or take their timing). Held, they aim at the cut's own pace along the line past the tip, and
## their hand DRIFTS across it (a smooth random walk: its spread `aim_pm` of the hide's 1000 a look, steadier for a
## better hand); torn for `react_ms` running they see it and pull back onto the line. A slip (`slip_pct` a line) jerks
## the knife well off the line for a look.
static func _skin(seed_value: int, p: SkinParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: SkinModel = SkinModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var line: int = -1
	var press_at: int = 0
	var drift: float = 0.0
	var torn_run: int = 0
	var seen_torn: int = 0
	var slip_at: int = -1
	var t: int = 0
	while t <= p.duration_ms:
		m.advance_to(t)
		torn_run = torn_run + 1 if m.down and m.torn > seen_torn else 0
		seen_torn = m.torn
		if m.line != line:
			line = m.line
			press_at = _at(t + sim.react_ms, sim, rng, t)
			drift = 0.0
			slip_at = rng.randi_range(5, 30) if _slips(sim, rng) else -1
		var x: int = -1
		var y: int = -1
		if not m.down:
			if t >= press_at:
				var tp: Vector2i = m.tip()
				x = tp.x
				y = tp.y
		else:
			drift = drift * 0.8 + rng.randfn(0.0, float(sim.aim_pm) * 0.6)
			if torn_run * 50 >= maxi(50, sim.react_ms):
				drift *= 0.2
				torn_run = 0
			var aim: Vector2 = m.ahead(float(p.cut_speed))
			var across: Vector2 = Vector2(0.0, drift)
			slip_at -= 1
			if slip_at == 0:
				across.y += 120.0 if rng.randf() < 0.5 else -120.0
			x = clampi(roundi(aim.x + across.x), 0, 1000)
			y = clampi(roundi(aim.y + across.y), 0, 1000)
		if x >= 0:
			out.append_array(PackedInt32Array([t, x, y]))
			m.press(t, x, y)
		t += 50
	m.finish()
	return {"inputs": out, "live": m.result()}


static func _send(m: ShapeModel, out: PackedInt32Array, t: int, c: int) -> int:
	out.append_array(PackedInt32Array([t, c]))
	return m.strike(t, c)


## When a smith done shaping sets the part down: now, or (a round with a quench) as the bar's heat passes the middle
## of the window, give or take their timing; a bar already too cold for it goes back in the fire first, if a heat
## is left.
static func _quench_time(m: ShapeModel, p: ShapeParams, sim: SimPlayer, rng: RandomNumberGenerator, t: int,
		out: PackedInt32Array) -> int:
	if p.quench_hi_pm <= 0:
		return t
	var lands: int = maxi(t, m.next_ok_ms)
	if m.heat_pm(lands) < p.quench_lo_pm and m.reheats_left() != 0:
		_send(m, out, t, ShapeModel.REHEAT_COLUMN)
		m.settle(m.next_ok_ms)
		t = m.next_ok_ms
	var mid: int = (p.quench_lo_pm + p.quench_hi_pm) / 2
	var at: int = m.hot_until_ms - mid * p.heat_ms / 1000   # when the heat is at the window's middle
	return maxi(t, at + roundi(rng.randfn(0.0, float(sim.jitter_ms))))


## The column to strike next, `ShapeModel.TAP` + it for a light tap (-1: none would help), by the outline as they
## remember it: planning, the strike that brings the bar nearest (a spread counted); else the column that bulges most.
static func _shape_column(m: ShapeModel, p: ShapeParams, plans: bool, mind: PackedInt32Array) -> int:
	var best: int = -1
	if plans:
		var best_delta: int = 0
		for i: int in m.heights.size():
			for mv: int in ([i, ShapeModel.TAP + i] if p.tap_drop > 0 else [i]):
				var d: int = _delta(m.heights, p, mv, mind)
				if d < best_delta:
					best_delta = d
					best = mv
		return best
	var most: int = 0
	for i: int in m.heights.size():
		var over: int = m.heights[i] - mind[i]
		if over > most:
			most = over
			best = i
	if best >= 0 and p.tap_drop > 0 and most < p.hammer_drop:
		best += ShapeModel.TAP
	return best


## How strike `mv` would change the bar's error against `line` (only its column and their neighbors move).
static func _delta(h: PackedInt32Array, p: ShapeParams, mv: int, line: PackedInt32Array) -> int:
	var tap: bool = mv >= ShapeModel.TAP
	var i: int = mv - ShapeModel.TAP if tap else mv
	var d: int = mini(h[i], p.tap_drop if tap else p.hammer_drop)
	var side: int = d * (p.tap_spread_pct if tap else p.spread_pct) / 100
	var out: int = absi(h[i] - d - line[i]) - absi(h[i] - line[i])
	if i > 0:
		out += absi(h[i - 1] + side - line[i - 1]) - absi(h[i - 1] - line[i - 1])
	if i < h.size() - 1:
		out += absi(h[i + 1] + side - line[i + 1]) - absi(h[i + 1] - line[i + 1])
	return out
