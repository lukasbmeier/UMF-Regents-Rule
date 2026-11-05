extends Node
## THE DIFFICULTY READOUT FROM A SHELL (`MINIGAMES_PREP.md` §6): every node's and recipe's round, played by the
## four simulated players (`SimPlayer.presets()`), and how their scores fall: the same as T in the skilling lab,
## for every round at once. A scene, not a `--script`, so the hot rules (an autoload) are there.
##   tools\run.cmd game\regents\tests\minigame_readout.sh            (or: godot --headless --path .
##   res://game/regents/tests/minigame_readout_cli.tscn -- --rounds=200)


func _ready() -> void:
	var rounds: int = MinigameReadout.ROUNDS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = maxi(1, int(a.trim_prefix("--rounds=")))
	var started: int = Time.get_ticks_msec()
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame != null:
			print(MinigameReadout.report(n.minigame, rounds), "\n")
	for r: RecipeDef in RecipeDef.all():
		if r.minigame != null:
			print(MinigameReadout.report(r.minigame, rounds), "\n")
	print("READOUT DONE in %d ms" % (Time.get_ticks_msec() - started))
	AppExit.quit(get_tree(), 0)
