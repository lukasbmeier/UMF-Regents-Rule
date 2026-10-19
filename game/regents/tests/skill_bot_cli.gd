extends SceneTree
## A SKILLING ROUND PLAYED FROM A SHELL (the integration hook's): what a client would submit for a round
## the server dealt, played well by a bot through the client's own models. `--kind` is chop, crack, smelt or
## shape; `--def` the NodeDef (chop, crack) or RecipeDef (smelt, shape) id; `--speed` the payload's tool
## speed; the seed's halves `--seed_hi`/`--seed_lo`. Prints `RESULT [values...]` (the inputs, as the
## challenge takes them) and `PLAYED <result>`.
##   godot --headless --path . --script res://game/regents/tests/skill_bot_cli.gd -- --kind=crack --def=40004 --speed=100 --seed_hi=0 --seed_lo=5


func _initialize() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var seed_value: int = (int(args.get("seed_hi", "0")) << 32) | int(args.get("seed_lo", "0"))
	var kind: StringName = StringName(String(args.get("kind", "")))
	var def_id: int = int(args.get("def", "0"))
	var content: ContentDef = NodeDef.by_id(def_id) if kind == SkillMinigames.CHOP or kind == SkillMinigames.CRACK else RecipeDef.by_id(def_id)
	var minigame: Resource = (content as NodeDef).minigame if content is NodeDef else ((content as RecipeDef).minigame if content is RecipeDef else null)
	if minigame == null or SkillMinigames.kind_of(minigame) != kind:
		printerr("skill_bot_cli: no %s round for %d" % [kind, def_id])
		quit(1)
		return
	var p: Resource = SkillMinigames.with_speed(minigame, int(args.get("speed", "100")))
	var inputs: PackedInt32Array = PackedInt32Array()
	match kind:
		SkillMinigames.CHOP:
			inputs = _chop(seed_value, p as ChopParams)
		SkillMinigames.CRACK:
			inputs = _crack(seed_value, p as CrackParams)
		SkillMinigames.SMELT:
			inputs = _smelt(seed_value, p as SmeltParams)
		SkillMinigames.SHAPE:
			inputs = _shape(seed_value, p as ShapeParams)
	var parts: PackedStringArray = PackedStringArray()
	for v: int in inputs:
		parts.append(str(v))
	print("RESULT [%s]" % ",".join(parts))
	print("PLAYED %s" % str(SkillMinigames.play(seed_value, p, inputs)))
	quit(0)


## Never under a branch, a swing every swing.
func _chop(seed_value: int, p: ChopParams) -> PackedInt32Array:
	var m: ChopModel = ChopModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t <= p.duration_ms:
		var side: int = ChopModel.SIDE_RIGHT if m.head_branch() == ChopModel.BRANCH_LEFT else (ChopModel.SIDE_LEFT if m.head_branch() == ChopModel.BRANCH_RIGHT else m.side)
		out.append_array(PackedInt32Array([t, side]))
		m.chop(t, side)
		t += p.swing_ms
	return out


## The seam followed, every notch struck dead on, a fifth of a second after the pick is free.
func _crack(seed_value: int, p: CrackParams) -> PackedInt32Array:
	var m: CrackModel = CrackModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 200
	while t <= p.duration_ms:
		if t >= m.next_ok_ms + 200:
			var g: Vector2i = m.notch(m.k)
			out.append_array(PackedInt32Array([t, g.x, g.y]))
			m.strike(t, g.x, g.y)
		t += 10
	return out


## Pumps under the band's middle; pours, and stops at the line.
func _smelt(seed_value: int, p: SmeltParams) -> PackedInt32Array:
	var m: SmeltModel = SmeltModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t < p.heat_ms:
		m.advance_to(t)
		if m.heat < m.band(m.tick).x and m.press(t, SmeltModel.PUMP) == SmeltModel.DONE:
			out.append_array(PackedInt32Array([t, SmeltModel.PUMP]))
		t += 10
	t = p.heat_ms + p.pour_ready_ms + 100
	out.append_array(PackedInt32Array([t, SmeltModel.POUR]))
	m.press(t, SmeltModel.POUR)
	while m.fill < m.target and t < p.heat_ms + p.pour_ms - 100:
		t += 10
		m.advance_to(t)
	out.append_array(PackedInt32Array([t, SmeltModel.STOP]))
	return out


## The column furthest over the outline, each swing; back in the fire when nearly cold.
func _shape(seed_value: int, p: ShapeParams) -> PackedInt32Array:
	var m: ShapeModel = ShapeModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t <= p.duration_ms:
		if t >= m.next_ok_ms:
			var c: int = ShapeModel.REHEAT_COLUMN
			if m.hot_until_ms - t >= 400:
				c = 0
				for i: int in m.heights.size():
					if m.heights[i] - p.outline[i] > m.heights[c] - p.outline[c]:
						c = i
				if m.heights[c] - p.outline[c] <= 0:
					break
			out.append_array(PackedInt32Array([t, c]))
			m.strike(t, c)
		t += 10
	return out
