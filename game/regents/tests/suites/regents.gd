extends "res://tests/suite_base.gd"
## REGENT'S RULE'S `regents` suite (`-- --only=regents` runs it alone), with no server:
##   - woodcutting's branch dodge (`ChopModel`): the trees; the trunk from a seed (the same every time,
##     the challenge's own generator, safe pieces at the bottom, as branchy as the tree says); a branch
##     at your head on your side hits you and staggers you; the swing and the round bound every press;
##     a perfect player scores in full; a replay of the inputs scores what was played
##   - the minigame (`ChopMinigame`): keeps every press, plays through the model, and its end says the
##     replay agrees; the lab opens it

const L: int = ChopModel.SIDE_LEFT
const R: int = ChopModel.SIDE_RIGHT


func run() -> void:
	_run_trees()
	_run_trunk()
	_run_golden()
	_run_chops()
	_run_perfect_and_replay()
	await _run_minigame()


func _params(permille: int = 450) -> ChopParams:
	var p: ChopParams = ChopParams.new()
	p.duration_ms = 10000
	p.swing_ms = 300
	p.stagger_ms = 800
	p.branch_permille = permille
	p.safe_segments = 2
	p.target_chops = 22
	return p


## A model on `p` whose trunk is `trunk` (bottom first), padded with bare pieces.
func _model_with(p: ChopParams, trunk: Array[int]) -> ChopModel:
	var m: ChopModel = ChopModel.start(1, p)
	var segs: PackedInt32Array = m.segments
	for i: int in segs.size():
		segs[i] = trunk[i] if i < trunk.size() else ChopModel.BRANCH_NONE
	m.segments = segs
	return m


func _run_trees() -> void:
	print("== regents: the trees ==")
	var defs: Array[TreeDef] = TreeDef.all_by_tier()
	_check(defs.size() == 3 and defs[0].display_name == "Tree" and defs[1].display_name == "Oak" and defs[2].display_name == "Yew",
		"three trees, lowest tier first: Tree, Oak, Yew")
	var prev: ChopParams = null
	for d: TreeDef in defs:
		_check(d.validate().is_empty(), "%s is valid (%s)" % [d.display_name, str(d.validate())])
		var t: ChopParams = d.chop
		if t == null:
			continue
		_check(t.target_chops <= ChopModel.max_chops(t), "%s: a full score is reachable (%d of at most %d)" % [t.display_name, t.target_chops, ChopModel.max_chops(t)])
		if prev != null:
			_check(t.branch_permille > prev.branch_permille and t.target_chops > prev.target_chops,
				"%s is harder than %s: branchier, more logs for a full score" % [t.display_name, prev.display_name])
		prev = t


func _run_trunk() -> void:
	print("== regents: the trunk from a seed ==")
	# The challenge's own generator (pinned against Rust by shared/golden/challenge), so the twin agrees.
	var same_gen: bool = true
	for x: int in [1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 123456789]:
		same_gen = same_gen and ChopModel._next_u32(x) == ChallengeModel._next_u32(x)
	for s: int in [0, 1, -1, 0x1234567890ABCDEF, -0x7000000000000000]:
		same_gen = same_gen and ChopModel._seed_state(s) == ChallengeModel._seed_state(s)
	_check(same_gen, "the trunk's generator and seed fold are the challenge's (xorshift32), high bits included")
	var p: ChopParams = _params()
	var a: PackedInt32Array = ChopModel.branches(42, p, 200)
	_check(a == ChopModel.branches(42, p, 200), "a seed makes the same trunk every time")
	_check(ChopModel.branches(42, p, 20) == a.slice(0, 20), "and its bottom does not depend on how much is made")
	_check(a != ChopModel.branches(43, p, 200), "another seed, another trunk")
	_check(a[0] == ChopModel.BRANCH_NONE and a[1] == ChopModel.BRANCH_NONE, "the bottom pieces are safe (safe_segments 2)")
	var n: int = 20000
	var big: PackedInt32Array = ChopModel.branches(7, p, n)
	var left: int = big.count(ChopModel.BRANCH_LEFT)
	var right: int = big.count(ChopModel.BRANCH_RIGHT)
	var rate: float = float(left + right) / float(n - 2)
	_check(rate > 0.43 and rate < 0.47, "45 %% of pieces carry a branch (%.3f over %d)" % [rate, n])
	_check(absf(float(left) / float(left + right) - 0.5) < 0.03, "left and right alike (%d / %d)" % [left, right])
	_check(ChopModel.branches(7, _params(0), 500).count(ChopModel.BRANCH_NONE) == 500, "0 ‰: no branches")
	_check(ChopModel.branches(7, _params(1000), 500).count(ChopModel.BRANCH_NONE) == 2, "1000 ‰: every piece above the safe ones")


## The golden rounds (made by a third, Python version: `game/regents/tests/make_chop_golden.py`), which the
## server's Rust twin is held to as well (`server/tests/regents.rs`).
func _run_golden() -> void:
	print("== regents: the golden rounds ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/regents/chop.json", FileAccess.READ)
	_check(f != null, "shared/golden/regents/chop.json is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var cases: Array = doc.get("cases", []) as Array
	_check(cases.size() >= 10, "it has its cases (%d)" % cases.size())
	var bad: Array[String] = []
	for c: Dictionary in cases:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var pp: Dictionary = c["params"]
		var p: ChopParams = ChopParams.new()
		p.duration_ms = int(pp["duration_ms"])
		p.swing_ms = int(pp["swing_ms"])
		p.stagger_ms = int(pp["stagger_ms"])
		p.branch_permille = int(pp["branch_permille"])
		p.safe_segments = int(pp["safe_segments"])
		p.target_chops = int(pp["target_chops"])
		var want_seg: PackedInt32Array = PackedInt32Array()
		for v: Variant in c["segments"]:
			want_seg.append(int(v))
		var inputs: PackedInt32Array = PackedInt32Array()
		for pair: Array in c["inputs"]:
			inputs.append(int(pair[0]))
			inputs.append(int(pair[1]))
		var e: Dictionary = c["expected"]
		var want: Dictionary = {"clean": int(e["clean"]), "hits": int(e["hits"]), "best_combo": int(e["best_combo"]), "score_pm": int(e["score_pm"])}
		var got: Dictionary = ChopModel.play(seed_value, p, inputs)
		if ChopModel.branches(seed_value, p, want_seg.size()) != want_seg or got != want:
			bad.append("%s: %s, wanted %s" % [c["name"], str(got), str(want)])
	_check(bad.is_empty(), "the GDScript twin plays every golden round exactly%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))


func _run_chops() -> void:
	print("== regents: chopping ==")
	var p: ChopParams = _params()
	var m: ChopModel = _model_with(p, [0, L, 0, R])
	_check(m.head_branch() == L, "the branch at your head is the piece above the cut")
	_check(m.chop(0, L) == ChopModel.HIT and m.cut == 0 and m.hits == 1 and m.combo == 0, "chopping from the branch's side: hit, the trunk does not drop")
	_check(m.chop(799, R) == ChopModel.IGNORED and m.cut == 0, "staggered: a swing 799 ms after the hit is not swung")
	_check(m.chop(800, R) == ChopModel.CLEAN and m.cut == 1 and m.clean == 1, "at 800 ms (stagger_ms), from the other side: clean, the trunk drops")
	_check(m.head_branch() == ChopModel.BRANCH_NONE and m.chop(1099, R) == ChopModel.IGNORED, "mid-swing (299 ms after a chop): not swung")
	_check(m.chop(1100, R) == ChopModel.CLEAN and m.head_branch() == R, "a swing later: clean, and the next branch is on your side")
	_check(m.chop(1400, R) == ChopModel.HIT and m.chop(2200, L) == ChopModel.CLEAN, "stay under it and it hits; step across and chop")
	_check(m.best_combo == 2 and m.combo == 1, "a hit ends a combo (best 2, now 1)")
	var o: ChopModel = _model_with(p, [])
	_check(o.chop(-1, L) == ChopModel.IGNORED and o.chop(0, 0) == ChopModel.IGNORED and o.chop(0, 3) == ChopModel.IGNORED,
		"before the round, or no side: nothing")
	_check(o.chop(500, L) == ChopModel.CLEAN and o.chop(400, L) == ChopModel.IGNORED and o.chop(900, L) == ChopModel.CLEAN,
		"a press earlier than the last one is out of order: nothing")
	_check(o.chop(10000, R) == ChopModel.CLEAN and o.chop(10001, R) == ChopModel.IGNORED and o.clean == 3,
		"the round's last millisecond counts; after it, nothing")
	o.clean = 11
	_check(o.score_pm() == 500, "11 of a 22-log target scores half (%d)" % o.score_pm())
	o.clean = 40
	_check(o.score_pm() == 1000, "more than the target scores no more")


## A player who never misses: a swing every `swing_ms` from the side the next branch is not on.
func _perfect_inputs(seed_value: int, p: ChopParams) -> PackedInt32Array:
	var m: ChopModel = ChopModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t <= p.duration_ms:
		var side: int = R if m.head_branch() == L else (L if m.head_branch() == R else m.side)
		out.append_array(PackedInt32Array([t, side]))
		m.chop(t, side)
		t += p.swing_ms
	return out


func _run_perfect_and_replay() -> void:
	print("== regents: a perfect round, and a replay ==")
	for d: TreeDef in TreeDef.all_by_tier():
		var t: ChopParams = d.chop
		var r: Dictionary = ChopModel.play(99, t, _perfect_inputs(99, t))
		_check(r["hits"] == 0 and r["clean"] == ChopModel.max_chops(t) and r["score_pm"] == 1000,
			"%s: never under a branch, every swing on time: %d logs, no hits, a full score" % [t.display_name, r["clean"]])
	# Pressing blind (always left) on a branchy tree: hit, staggered, far short.
	var p: ChopParams = _params(600)
	var blind: PackedInt32Array = PackedInt32Array()
	for k: int in 34:
		blind.append_array(PackedInt32Array([k * 300, L]))
	var b: Dictionary = ChopModel.play(5, p, blind)
	_check(b["hits"] > 0 and b["score_pm"] < 1000, "always the left on a branchy tree: hit %d times, scores %d ‰" % [b["hits"], b["score_pm"]])
	# The replay is the inputs': change one side and a different round is scored.
	var perfect: PackedInt32Array = _perfect_inputs(5, p)
	var m: ChopModel = ChopModel.start(5, p)
	var flip: int = -1
	var i: int = 0
	while i + 1 < perfect.size():
		if m.head_branch() != ChopModel.BRANCH_NONE:
			flip = i
			break
		m.chop(perfect[i], perfect[i + 1])
		i += 2
	var tampered: PackedInt32Array = perfect.duplicate()
	tampered[flip + 1] = m.head_branch()
	var pr: Dictionary = ChopModel.play(5, p, perfect)
	var tr: Dictionary = ChopModel.play(5, p, tampered)
	# The stagger puts every later swing off the perfect player's timing, so the hits go on from there.
	_check(flip >= 0 and pr["hits"] == 0 and int(tr["hits"]) >= 1 and tr["clean"] < pr["clean"],
		"one swing moved under a branch: the replay scores the hit and what it cost (%s vs %s)" % [str(tr), str(pr)])


func _run_minigame() -> void:
	print("== regents: the minigame ==")
	var g: ChopMinigame = ChopMinigame.new()
	g.size = Vector2(1280, 720)
	add_child(g)
	var p: ChopParams = _params(500)
	var seen: Array[Dictionary] = []
	g.round_finished.connect(func(live: Dictionary, replayed: Dictionary) -> void:
		seen.append(live)
		seen.append(replayed))
	_check(g.press_at(0, L) == ChopModel.IGNORED and g.inputs.is_empty(), "before a round, a press is nothing and is not kept")
	g.begin(77, p)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var t: int = -50
	var events: Dictionary = {}
	var sides: Array[int] = [L, R, L, R, 0]
	for k: int in 120:
		var side: int = sides[rng.randi_range(0, 4)]
		var ev: int = g.press_at(t, side)
		events[ev] = int(events.get(ev, 0)) + 1
		t += rng.randi_range(-40, 220)
	_check(g.inputs.size() == 240, "every press is kept, the ignored ones too (%d values)" % g.inputs.size())
	_check(events.has(ChopModel.CLEAN) and events.has(ChopModel.HIT) and events.has(ChopModel.IGNORED),
		"a messy player chops, gets hit, and swings when it cannot (%s)" % str(events))
	await get_tree().process_frame
	g.finish()
	_check(seen.size() == 2 and seen[0] == seen[1] and seen[0] == ChopModel.play(77, p, g.inputs),
		"the round's end: what was played is what a replay of its inputs scores (%s)" % (str(seen[0]) if seen.size() > 0 else "none"))
	_check(g.press_at(t, L) == ChopModel.IGNORED and g.inputs.size() == 240, "after the round, presses are nothing")
	g.queue_free()
	var lab: Node = (load("res://game/regents/skilling/woodcutting/chop_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	await get_tree().process_frame
	var inner: ChopMinigame = null
	for c: Node in lab.get_children():
		if c is ChopMinigame:
			inner = c as ChopMinigame
	_check(inner != null and inner.tree != null and inner.tree.display_name == "Tree" and inner.model != null,
		"the lab opens on the first tree, its trunk showing, ready to play")
	var buttons: Array[Button] = []
	buttons.assign(lab.get("tree_buttons"))
	if inner != null and buttons.size() == 3:
		var tree_trunk: PackedInt32Array = inner.model.segments
		buttons[2].pressed.emit()
		_check(inner.tree.display_name == "Yew" and buttons[2].button_pressed and not buttons[0].button_pressed
			and inner.model.segments != tree_trunk and inner.state == ChopMinigame.State.READY,
			"the Yew button picks the yew, lit alone, and shows its trunk at once")
		inner.begin(1, inner.tree)
		buttons[0].pressed.emit()
		_check(inner.tree.display_name == "Yew" and inner.state == ChopMinigame.State.PLAYING,
			"mid-round, the tree stays as it is")
		inner.finish()
		buttons[1].pressed.emit()
		_check(inner.tree.display_name == "Oak", "after the round, the Oak button picks the oak")
	else:
		_check(false, "the lab has a button per tree (%d)" % buttons.size())
	lab.queue_free()
	await get_tree().process_frame
