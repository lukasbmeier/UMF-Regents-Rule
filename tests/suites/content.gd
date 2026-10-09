extends "res://tests/suite_base.gd"
## The `content` suite (tests/test_runner.gd runs it; `-- --only=content` runs it alone).
## CONTENT IS RESOURCES, BAKED (docs/CONTENT_TOOLING_SPEC.md §1, DECISIONS #199): the bake on disk is
## the one the .tres files make now, every piece of content is valid, and a type says what is wrong
## with bad content in words. (That the server refuses a stale bake is tests/content_test.sh.)

const BAKE: GDScript = preload("res://tools/bake_content.gd")


func run() -> void:
	_run_content_tests()
	await get_tree().process_frame


func _run_content_tests() -> void:
	print("== content ==")
	var result: Dictionary = BAKE.call(&"bake", false)
	_check((result["errors"] as Array).is_empty(), "every piece of content is valid %s" % str(result["errors"]))
	_check((result["stale"] as Array).is_empty(),
		"the bake on disk is current (Bake, or tools/bake_content.gd) %s" % str(result["stale"]))
	var melee: AbilityDef = load("res://foundation/content/abilities/melee.tres") as AbilityDef
	_check(melee != null and melee.validate().is_empty(), "the foundation's ability, melee, is content")
	var baked: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/content/foundation/ability.json"))
	var item: Dictionary = ((baked as Dictionary)["items"] as Array)[0] if baked is Dictionary else {}
	_check(melee != null and int(item.get("ability_id", -1)) == melee.id and int(item.get("wind_up_ms", -1)) == melee.wind_up_ms
		and String(item.get("name", "")) == melee.display_name and not item.has("designer_notes"),
		"its baked row is its Inspector values, without the designer's notes")
	var bad := AbilityDef.new()
	bad.display_name = ""
	bad.wind_up_ms = 50
	var why: Array[String] = bad.validate()
	_check(why.size() == 2 and why[1].contains("50 ms") and why[0].contains("no display name"),
		"bad content is refused in words: %s" % str(why))
	_check(BAKE.call(&"hash_bytes", "a".to_utf8_buffer()) == "e40c292c"
		and BAKE.call(&"hash_bytes", PackedByteArray()) == "811c9dc5",
		"the manifest's hash is FNV-1a 32 (build.rs computes the same)")
