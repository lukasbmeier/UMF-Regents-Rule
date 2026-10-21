class_name ProjectStamp
## WHEN THE PROJECT LAST CHANGED, as a sidecar sees it (DECISIONS #272): the newest modification time of
## what a sidecar runs or reads: its scripts and scenes (`sidecar/`, `foundation/`, `game/`), the baked
## content (`shared/content/manifest.json`) and the bindings' fingerprint.
## A referee started yesterday kept running yesterday's code after a publish (Luke, 2026-10-20: the
## skeletons never attacked; it had no definition for their kinds): one whose project is newer than it
## stops, and whatever started it (Play, `tools/host.sh`) starts a fresh one. SERVER-ONLY (rule 7b).

## The folders whose code a sidecar runs.
const CODE_DIRS: PackedStringArray = ["res://sidecar", "res://foundation", "res://game"]
## Single files it reads: the bake's manifest, and the bindings' fingerprint (the adapter's path).
static func files() -> PackedStringArray:
	return PackedStringArray(["res://shared/content/manifest.json", SpaceTimeSync.BINDINGS_FINGERPRINT_PATH])
## What counts as code or content in those folders.
const EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres", "json"]


## Whether the project changed after `stamp` (a sidecar's at its start): it is stale then.
static func newer_than(stamp: int) -> bool:
	return now() > stamp


## The newest modification time (unix seconds) of everything above that exists.
static func now() -> int:
	var newest: int = 0
	for f: String in files():
		if FileAccess.file_exists(f):
			newest = maxi(newest, FileAccess.get_modified_time(f))
	for d: String in CODE_DIRS:
		newest = maxi(newest, _newest_in(d))
	return newest


static func _newest_in(dir: String) -> int:
	var newest: int = 0
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return 0
	da.include_hidden = false
	for f: String in da.get_files():
		if EXTENSIONS.has(f.get_extension()):
			newest = maxi(newest, FileAccess.get_modified_time(dir.path_join(f)))
	for sub: String in da.get_directories():
		if not sub.begins_with("."):
			newest = maxi(newest, _newest_in(dir.path_join(sub)))
	return newest
