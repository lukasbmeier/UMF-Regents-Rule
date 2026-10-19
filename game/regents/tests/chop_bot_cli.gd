extends SceneTree
## A WOODCUTTING ROUND PLAYED FROM A SHELL (the integration hook's): what a client would submit for a
## round of tree `--tree` (a TreeDef id) dealt with seed `--seed_hi`/`--seed_lo` (the u64's halves), by a
## bot: `perfect` never stands under a branch and swings on every swing; `blind` always chops from the
## left. Prints `RESULT [t, side, ...]` (the inputs, as the challenge takes them) and `PLAYED <result>`.
##   godot --headless --path . --script res://game/regents/tests/chop_bot_cli.gd -- --seed_hi=1 --seed_lo=2 --tree=40001 --bot=perfect


func _initialize() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var seed_value: int = (int(args.get("seed_hi", "0")) << 32) | int(args.get("seed_lo", "0"))
	var tree: TreeDef = TreeDef.by_id(int(args.get("tree", "0")))
	if tree == null:
		printerr("chop_bot_cli: no tree %s" % args.get("tree", "?"))
		quit(1)
		return
	var p: ChopParams = tree.chop
	var m: ChopModel = ChopModel.start(seed_value, p)
	var inputs: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t <= p.duration_ms:
		var side: int = ChopModel.SIDE_LEFT
		if String(args.get("bot", "perfect")) == "perfect":
			side = ChopModel.SIDE_RIGHT if m.head_branch() == ChopModel.BRANCH_LEFT else (ChopModel.SIDE_LEFT if m.head_branch() == ChopModel.BRANCH_RIGHT else m.side)
		inputs.append_array(PackedInt32Array([t, side]))
		m.chop(t, side)
		t += p.swing_ms
	var parts: PackedStringArray = PackedStringArray()
	for v: int in inputs:
		parts.append(str(v))
	print("RESULT [%s]" % ",".join(parts))
	print("PLAYED %s" % str(m.result()))
	quit(0)
