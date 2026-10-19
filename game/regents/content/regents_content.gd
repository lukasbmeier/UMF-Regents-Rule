class_name RegentsContent extends RefCounted
## THE GENRE'S CONTENT, LOOKED UP ONCE. `ContentLibrary.items(type)` lists the content folders and loads
## every piece each time it is asked (right for the editor and the bake, where content changes), and the
## HUD asks every frame: at the workbench its prompt asked dozens of times a frame and the game ran at
## 10 fps (owner's feedback, 2026-10-19). In a running game content does not change, so each type is
## listed once here; in the editor every ask goes to the library, so edits show at once.

static var _cache: Dictionary[StringName, Array] = {}


## Every piece of `type`, by id (the library's list).
static func items(type: StringName) -> Array[ContentDef]:
	if Engine.is_editor_hint():
		return ContentLibrary.items(type)
	if not _cache.has(type):
		_cache[type] = ContentLibrary.items(type)
	var out: Array[ContentDef] = []
	out.assign(_cache[type])
	return out


## Forget what was listed (a test that changes content).
static func clear() -> void:
	_cache.clear()
