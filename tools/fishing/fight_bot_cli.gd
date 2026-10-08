extends SceneTree
## Play a fight for a cast from the command line, the way a client would, and print what the
## client would submit: the integration suite's way of landing (or snapping) a real catch against
## the real module from a shell.
##
##   godot --headless --path . --script res://tools/fishing/fight_bot_cli.gd -- \
##       --payload='<the challenge payload JSON>' [--reaction=0.2] [--bot=ace|good|sloppy|masher]
##       [--cut]    submit only the first half of the log (a fight that never finished)
##
## Prints:
##   RESULT [reaction, n, ticks, flags, crank, ...]   submit_challenge_result's argument
##   OUTCOME landed|snapped|fighting ticks=<n> seconds=<s>


func _init() -> void:
	var payload: Dictionary = {}
	var reaction: float = 0.2
	var bot: String = "ace"
	var cut: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--payload="):
			var text: String = arg.substr(10)
			if text.begins_with("\"") and text.ends_with("\""):
				text = text.substr(1, text.length() - 2)   # as `spacetime sql` prints a string
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				payload = parsed as Dictionary
		elif arg.begins_with("--reaction="):
			reaction = float(arg.substr(11))
		elif arg.begins_with("--bot="):
			bot = arg.substr(6)
		elif arg == "--cut":
			cut = true
	if payload.is_empty():
		printerr("fight_bot_cli: no readable --payload")
		quit(1)
		return
	var grade: FishingData.HookSet = FishingData.grade_hookset(reaction, float(payload.get("window_mult", 1.0)))
	var params: FightSim.Params = FightSim.params_for(int(payload.get("rod", 0)), int(payload.get("reel", 0)),
		int(payload.get("line", 0)), grade, bool(payload.get("deadlift", false)))
	var prof: FightSim.Profile = FightSim.profile_of(str(payload.get("catch", "")))
	if prof == null:
		printerr("fight_bot_cli: no fight profile for %s" % payload.get("catch", "?"))
		quit(1)
		return
	var f := FightSim.new(params, prof, int(payload.get("fight_seed", 0)),
		float(payload.get("range_cm", 1000)) / 100.0, true)
	var runs: Array[PackedInt32Array] = FightBot.play(FightBot.kind_named(bot), f)
	if cut:
		runs = runs.slice(0, maxi(1, runs.size() / 2))
		f = FightSim.replay(params, prof, int(payload.get("fight_seed", 0)),
			float(payload.get("range_cm", 1000)) / 100.0, runs)
	var result: Array[float] = [reaction]
	result.append_array(FightSim.encode_log(runs))
	print("RESULT ", JSON.stringify(result))
	var names: PackedStringArray = ["fighting", "landed", "snapped"]
	print("OUTCOME %s ticks=%d seconds=%.2f combo=%d" % [names[f.state], f.ticks,
		float(f.ticks) / float(FightSim.tick_hz()), f.best_combo])
	quit()
