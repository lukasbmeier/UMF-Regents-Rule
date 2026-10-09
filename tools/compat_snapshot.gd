extends SceneTree
## SAVES THIS BUILD'S CONTRACT as a release snapshot (docs/rules/compatibility.md, DECISIONS #198):
## `shared/compat/<database>/<fingerprint>.json`. The export plugin (`addons/umf_export`) does this
## on every export from the editor, the builds that reach players; the `version` unit suite then
## fails while any snapshot of the current compatibility generation cannot play on the current
## schema, so a change that would strand a friend's build is caught before it is published.
## By hand (headless exports by the test suites take none):
##   godot --headless --path . -s res://tools/compat_snapshot.gd

const BINDINGS_CONTRACT: String = "res://spacetime_bindings/schema_contract.json"
const BINDINGS_FINGERPRINT: String = "res://spacetime_bindings/schema_fingerprint.json"
const DIR: String = "res://shared/compat/%s"


func _initialize() -> void:
	var path: String = save()
	if path.is_empty():
		printerr("no contract beside the bindings: run tools/publish.sh --codegen first")
		quit(1)
		return
	print("compat snapshot: ", path)
	quit()


## Save the snapshot (once per schema: an existing one is left as it is). Returns its path, or ""
## when the bindings have no contract.
static func save() -> String:
	var contract: Variant = _json(BINDINGS_CONTRACT)
	var fp: Variant = _json(BINDINGS_FINGERPRINT)
	if not contract is Dictionary or not fp is Dictionary:
		return ""
	var fingerprint: String = String((fp as Dictionary).get("fingerprint", ""))
	if fingerprint.is_empty():
		return ""
	var dir: String = DIR % _database()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path: String = "%s/%s.json" % [dir, fingerprint]
	if FileAccess.file_exists(path):
		return path
	var snap: Dictionary = (contract as Dictionary).duplicate(true)
	snap["note"] = "A RELEASE SNAPSHOT (tools/compat_snapshot.gd, DECISIONS #198): a build with this contract went out. Every later server of the same generation must still satisfy it (tests: version suite). Never edit; to break on purpose, bump shared/game.json compat."
	snap["saved"] = Time.get_datetime_string_from_system(true)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(snap, "\t", true) + "\n")
	f.close()
	return path


static func _database() -> String:
	var game: Variant = _json("res://shared/game.json")
	return String((game as Dictionary).get("database", "umf")) if game is Dictionary else "umf"


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
