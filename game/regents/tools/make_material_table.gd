@tool
extends SceneTree
## MAKE THE MATERIAL TABLE without the editor (`MaterialTable`, `docs/regents_rule/MATERIALS.md` §2): what
## the Make the table button on a material or a pattern does. Then bake (publish does).
##
##   godot --headless --path . -s res://game/regents/tools/make_material_table.gd             make it
##   godot --headless --path . -s res://game/regents/tools/make_material_table.gd -- --check  say what is out of date
##
## The table is loaded when it runs, not named here: naming it would compile the content scripts before the
## autoloads they read (`HotRules`) exist, as the bake (`tools/bake_content.gd`) avoids too.

const TABLE: String = "res://game/regents/content/material_table.gd"


func _initialize() -> void:
	var table: Script = load(TABLE) as Script
	if OS.get_cmdline_user_args().has("--check"):
		var problems: Array = table.call(&"problems")
		for p: String in problems:
			printerr("  ", p)
		if problems.is_empty():
			print("the material table is current (%d cell(s))" % (table.call(&"plan") as Array).size())
			quit()
		else:
			printerr("the material table is out of date: %d problem(s)" % problems.size())
			quit(1)
		return
	var result: Dictionary = table.call(&"generate")
	for line: String in result["lines"] as Array:
		print(line)
	for e: String in result["errors"] as Array:
		printerr("  ", e)
	quit(1 if not (result["errors"] as Array).is_empty() else 0)
