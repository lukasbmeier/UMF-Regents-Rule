extends Node
## A WORKBENCH'S PICTURE, for real (DECISIONS #203): the Catalog's thumbnails are each piece rendered
## in its own workbench off screen, which needs a renderer, so this opens a window
## (tests/render_test.sh). Each bench's piece (melee in the ability bench, the humanoid in the character
## bench) rendered off screen: a picture
## of the right size, with something in it (not one flat colour), stored where the Catalog looks.
##
## Prints `RENDER PASS`/`RENDER FAIL` per check and exits 1 on any failure.

## Each bench, and a piece to picture in it.
const SHOTS: Array[Array] = [
	["res://tools/workbench/ability_workbench.tscn", "res://foundation/content/ability/melee.tres"],
	["res://tools/workbench/character_workbench.tscn", "res://foundation/content/character/humanoid.tres"],
]

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for shot: Array in SHOTS:
		await _shoot(String(shot[0]), load(String(shot[1])) as ContentDef)
	print("RENDER %s: %d failed" % ["PASS" if _failures == 0 else "FAIL", _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)


func _shoot(bench: String, def: ContentDef) -> void:
	var path: String = Workbench.thumbnail_path(def)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var img: Image = await Workbench.render_offscreen(bench, def, self)
	_expect(img != null and img.get_size() == Workbench.THUMB_SIZE,
		"the bench renders the piece off screen (%s)" % (img.get_size() if img != null else "nothing"))
	var distinct: Dictionary = {}
	if img != null:
		for y: int in range(0, img.get_height(), 8):
			for x: int in range(0, img.get_width(), 8):
				distinct[img.get_pixel(x, y).to_html(false)] = true
	_expect(distinct.size() > 20, "and the picture has something in it (%d distinct colours sampled)" % distinct.size())
	_expect(FileAccess.file_exists(path) and Workbench.thumbnail_of(def) != null,
		"stored where the Catalog looks (%s)" % path.get_file())


func _expect(ok: bool, what: String) -> void:
	print("RENDER %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failures += 1
