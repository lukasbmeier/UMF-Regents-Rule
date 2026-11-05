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
	var making: bool = SkillMinigames.kind_of(p) == SkillMinigames.SHAPE
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
	return "\n".join(lines)


## The grade cut points now (`regents.grade_fine_q`, `regents.grade_masterwork_q`), as qualities (‰).
static func grade_cuts() -> Vector2i:
	var fine: int = int(HotRules.number(&"regents.grade_fine_q"))
	return Vector2i(fine, maxi(fine, int(HotRules.number(&"regents.grade_masterwork_q"))))


## The score at which a played gathering or smelting round pays what AFK would in its time: yield is AFK x
## `regents.active_yield_mult` x the score (owner #23), so 1 / the multiplier. (Luke's M11, 2026-11-05, moves it
## down to about half; change it here with the formula.)
static func afk_break_even_pm() -> int:
	var mult: float = maxf(1.0, HotRules.number(&"regents.active_yield_mult"))
	return ceili(1000.0 / mult)


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
		var t: int = _at(aim, sim, rng, last)
		if t > p.duration_ms:
			break
		var at: Vector2i = m.notch(m.k + (1 if _slips(sim, rng) else 0))
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


## SHAPE TO THE OUTLINE: once the last strike has landed, strike the column that brings the bar nearest the
## outline (a planner) or the one that bulges most; back in the fire when it is nearly too cold; stop when no
## strike would help.
static func _shape(seed_value: int, p: ShapeParams, sim: SimPlayer, rng: RandomNumberGenerator) -> Dictionary:
	var m: ShapeModel = ShapeModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var seen: int = 0
	var last: int = 0
	var margin: int = sim.react_ms + 2 * sim.jitter_ms   # how near cold they reheat
	for _guard: int in 2000:
		var t: int = _at(seen + sim.react_ms, sim, rng, last)
		if t > p.duration_ms:
			break
		var c: int = _shape_column(m, p, sim.plans)
		if c < 0:
			break   # no strike would bring it closer: done
		var lands: int = maxi(t, m.next_ok_ms)   # a strike mid-swing lands when the swing ends
		var slip: bool = _slips(sim, rng)
		if m.hot_until_ms - lands < maxi(margin, 1):
			if not slip:
				c = ShapeModel.REHEAT_COLUMN   # a slip here: struck anyway, maybe cold
		elif slip:
			c = clampi(c + (1 if rng.randi_range(0, 1) == 1 else -1), 0, m.heights.size() - 1)
		out.append_array(PackedInt32Array([t, c]))
		var did: int = m.strike(t, c)
		if did == ShapeModel.HELD:
			m.settle(m.held_at_ms)
		last = maxi(t, m.last_act_ms)
		seen = m.last_act_ms if did != ShapeModel.IGNORED else t
	m.finish()
	return {"inputs": out, "live": m.result()}


## The column to strike next (-1: none would help).
static func _shape_column(m: ShapeModel, p: ShapeParams, plans: bool) -> int:
	var best: int = -1
	if plans:
		var now: int = m.error()
		var best_err: int = now
		for i: int in m.heights.size():
			var e: int = _error_after(m, p, i)
			if e < best_err:
				best_err = e
				best = i
		return best
	var most: int = 0
	for i: int in m.heights.size():
		var over: int = m.heights[i] - p.outline[i]
		if over > most:
			most = over
			best = i
	return best


## The bar's error if column `i` were struck now (hot).
static func _error_after(m: ShapeModel, p: ShapeParams, i: int) -> int:
	var h: PackedInt32Array = m.heights.duplicate()
	var d: int = mini(h[i], p.hammer_drop)
	h[i] -= d
	var side: int = d * p.spread_pct / 100
	if i > 0:
		h[i - 1] += side
	if i < h.size() - 1:
		h[i + 1] += side
	var e: int = 0
	for j: int in h.size():
		e += absi(h[j] - p.outline[j])
	return e
