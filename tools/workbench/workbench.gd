@tool
@abstract
class_name Workbench extends Node3D
## WHERE A PIECE OF CONTENT IS MADE AND TESTED (docs/CONTENT_TOOLING_SPEC.md §3, DECISIONS #203):
## a `@tool` scene with the real character, the real animations and the real moment in the game,
## and no server. "No content type without a workbench": the `content` suite fails a type that has
## none and does not say why (`ContentDef.needs_workbench()`).
##
## USING ONE (WORKBENCHES 2, DECISIONS #207). Open it (the Content dock's "Open workbench"): the
## PIECE goes to the Inspector, where every field you change is the piece's own, and the bench's
## controls are in the WORKBENCH panel (beside the Inspector): its tests, its settings (which
## animation, which character it is tried on), and its actions (Save, Play as this, New from this,
## Copy into a genre). The bench redraws as you edit. The bench keeps nothing in its own scene file:
## using one never changes it.
##
## WRITING ONE. Subclass this as `<type>_workbench.gd`, scene `tools/workbench/<type>_workbench.tscn`
## (a genre's: `game/<genre>/workbench/`; both stay out of the builds). Implement `content_type()`,
## `load_item()` (show it), `test_actions()` and `run_test()` (play that moment and say what
## happened). Optional: `test_label()`/`test_info()` (the button's words), `controls()` +
## `set_control()` (its settings, drawn by the panel), `bench_actions()` + `do_action()` (its own
## buttons), `play_args()` (Play as this), `fit_checks()` (amber warnings), `fill_from_file()` (a
## dropped file becomes a piece: the base makes it in the right folder with the next free id), a
## `ThumbnailCamera`. The base does the listing, loading, live edits, saving, the badge, thumbnails
## and the common actions, so a workbench is mostly its tests.

## Handed over by the Content dock just before it opens this scene: the piece to load.
static var pending: ContentDef = null

## The piece on the bench. Edit it in the Inspector: the bench redraws as you do.
@export var item: ContentDef:
	set(v):
		_set_item(v)
	get:
		return _item
## Which moment to play (the choices are this bench's `test_actions()`).
@export var test: StringName = &""
@export_tool_button("Run test", "Play") var _run_button: Callable = run_selected_test
@export_tool_button("Previous", "ArrowLeft") var _prev_button: Callable = previous_item
@export_tool_button("Next", "ArrowRight") var _next_button: Callable = next_item
@export_tool_button("Save", "Save") var _save_button: Callable = save
@export_tool_button("Capture thumbnail", "Image") var _thumb_button: Callable = capture_and_store_thumbnail
## What the bench says about the piece: its badge, its problems, the last test.
@export_multiline var status: String = ""
@export_group("New from a file")
## A file to make a new piece from (a rigged model for a character, later a sound, a fish model):
## drag it here from the FileSystem, then New From File.
@export_file var intake_file: String = ""
## Who the new piece belongs to: a genre the game lists, or "foundation". Empty: the game's first
## genre (most new content is a genre's), else the foundation.
@export var intake_owner: String = ""
@export_tool_button("New From File", "Add") var _intake_button: Callable = new_from_intake

## Something the panel shows changed (the piece, a control's choices): it redraws.
signal panel_changed

const HUMANOID: String = "res://foundation/content/character/humanoid.tres"

## THE CHARACTER A PIECE IS TRIED ON (the ability, movement and status benches; DECISIONS #207):
## chosen in the panel ("Tried on"), by default the one that uses the piece (`default_character()`),
## else the humanoid. Its model is the bench's `Mannequin`. Unused where the piece IS a character.
var character: EntityDefinition = null:
	set(v):
		character = v
		var m: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
		if m != null and m.definition != v:
			m.definition = v
## The panel chose `character`: a new piece keeps it rather than taking its own default.
var _character_chosen: bool = false

## What the last test said.
var last_result: String = ""
var _item: ContentDef = null
var _ready_done: bool = false
## THE BENCH FOLLOWS EDITS. A script's fields do not announce a change (Godot emits `changed` for
## its own resource types only), so the bench compares the piece's saved fields a few times a second
## and redraws when they move: every content type gets this, with nothing to write.
var _seen: String = ""
var _watch_left: float = 0.0
const WATCH_SECONDS: float = 0.2

const THUMBNAILS: String = "res://tools/workbench/thumbnails"
const THUMB_SIZE: Vector2i = Vector2i(256, 256)


## The type this bench makes: `&"ability"`.
@abstract func content_type() -> StringName
## Show `def` (null: show nothing).
@abstract func load_item(def: ContentDef) -> void
## The moments this content lives in, to play: `[&"use_in_range", ...]`.
@abstract func test_actions() -> Array[StringName]
## Play one and say what happened, in a sentence (a coroutine may await).
@abstract func run_test(action: StringName) -> String


## The words on a test's button ("Start and stop" for `accelerate`). Default: the name, spaced.
func test_label(action: StringName) -> String:
	return String(action).replace("_", " ").capitalize()


## What a test plays, for its button's tooltip.
func test_info(_action: StringName) -> String:
	return ""


## THE BENCH'S SETTINGS, for the Workbench panel: one Dictionary each, {name, label, kind ("choice",
## "number", "toggle", "heading"), value, options (choice: Array of [value, label]), min, max, step
## (number), tooltip}. Read again whenever `panel_changed` fires.
func controls() -> Array[Dictionary]:
	return []


## A setting changed in the panel. A bench handles its own and passes the rest here (`character`).
func set_control(n: StringName, value: Variant) -> void:
	if n == &"character" and value is EntityDefinition:
		character = value
		_character_chosen = true
		_refresh()


## Whether this bench tries its piece on a character (the "Tried on" choice).
func tries_on_character() -> bool:
	return false


## The character a piece is tried on until the panel says otherwise: one that uses it, else the
## humanoid. A bench whose pieces a character links to finds that character here.
func default_character() -> EntityDefinition:
	return load(HUMANOID) as EntityDefinition


## The first character (this game's, then the template's) for which `uses` is true, or null.
static func character_using(uses: Callable) -> EntityDefinition:
	var all: Array[ContentDef] = ContentLibrary.items(&"character")
	all.sort_custom(func(a: ContentDef, b: ContentDef) -> bool: return a.id > b.id)   # a genre's first
	for d: ContentDef in all:
		if bool(uses.call(d)):
			return d as EntityDefinition
	return null


## The "Tried on" choice: every character.
func character_control() -> Dictionary:
	var options: Array = []
	for d: ContentDef in ContentLibrary.items(&"character"):
		options.append([d, "%s  (%s)" % [d.display_name, ContentLibrary.owner_of_path(d.resource_path)]])
	return {"name": &"character", "label": "Tried on", "kind": "choice", "value": character, "options": options,
		"tooltip": "The character this is tried on: its model, its animations, its movement"}


## The bench's own buttons beyond the tests and the common ones: [{name, label, tooltip}].
func bench_actions() -> Array[Dictionary]:
	return []


## Play as this piece: the game's command line for it ("--character=res://..."), or empty when this
## kind of piece is not played as.
func play_args() -> PackedStringArray:
	return PackedStringArray()


## EVERY BUTTON THE PANEL SHOWS beside the tests: the bench's own, then the common ones that apply
## to this piece. [{name, label, tooltip}]
func actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = bench_actions()
	if _item == null:
		return out
	if not play_args().is_empty():
		out.append({"name": &"play_as", "label": "Play as this", "tooltip": "Run the game as this piece (publishing first when the server does not have it yet)"})
	out.append({"name": &"save", "label": "Save", "tooltip": "Save the piece to its file"})
	out.append({"name": &"duplicate", "label": "New from this", "tooltip": "A new piece that starts as a copy of this one (its own id and file)"})
	if read_only_here():
		for g: String in ContentLibrary.owners():
			if g != ContentLibrary.FOUNDATION and ContentLibrary.may_own(content_type(), g):
				out.append({"name": StringName("copy_into:" + g), "label": "Copy into %s" % g,
					"tooltip": "The template's piece is read-only in a game: make %s's own copy and change that (it takes the template's place where the type allows: the same kind, the same status number)" % g})
	out.append({"name": &"thumbnail", "label": "Capture thumbnail", "tooltip": "The Catalog's picture of this piece"})
	return out


## Press one of `actions()`. Returns what the editor should do, for the panel: {} (done here),
## {"play": args}, {"edit": resource} (show it in the Inspector), {"open": piece} (on its own bench).
func do_action(action: StringName) -> Dictionary:
	match action:
		&"save":
			save()
			return {}
		&"duplicate":
			var owner: String = ContentLibrary.owner_of_path(_item.resource_path) if not read_only_here() else _default_owner()
			return {"edit": _item} if not duplicate_item(owner).is_empty() else {}
		&"thumbnail":
			capture_and_store_thumbnail()
			return {}
		&"play_as":
			return {"play": play_args()}
	if String(action).begins_with("copy_into:"):
		return {"edit": _item} if not duplicate_item(String(action).get_slice(":", 1), true).is_empty() else {}
	return {}


## Whether the piece is the template's while this is a game (it lists genres): the template's files
## are replaced on every update from it, so a game changes a copy of its own instead.
func read_only_here() -> bool:
	return _item != null and ContentLibrary.owner_of_path(_item.resource_path) == ContentLibrary.FOUNDATION \
		and ContentLibrary.owners().size() > 1


## NEW FROM THIS: a copy of the piece for `owner`, with its own id and file, put on the bench.
## `same_name`: keep its name (Copy into a genre: it takes the template's piece's place). Returns
## its path, or "" (and `last_result` says why).
func duplicate_item(owner: String, same_name: bool = false) -> String:
	if _item == null:
		return ""
	var errors: Array[String] = []
	var made: String = ContentLibrary.create_copy(_item, owner, _item.display_name if same_name else "%s copy" % _item.display_name, errors, same_name)
	if made.is_empty():
		last_result = "could not copy it: %s" % "; ".join(errors)
		_update_status()
		return ""
	_set_item(load(made) as ContentDef)
	last_result = "made %s (%s's)" % [made.get_file(), owner]
	_update_status()
	return made


## Checks only a bench can make (the reel 2 cm clear of the thigh across the clip), one sentence
## each: an amber badge. Empty: none.
func fit_checks() -> Array[String]:
	return []


## Fill `def` (just made, with its id and folder) from the file at `path`. "" when it worked, else
## why not, in a sentence. A bench whose type is not made from a file leaves this as it is.
func fill_from_file(_def: ContentDef, _path: String) -> String:
	return "a %s is not made from a file: use New in the Content dock" % content_type()


## NEW FROM A FILE: make a piece of this bench's type for `owner` (see `intake_owner`), fill it from
## `path`, save it, and put it on the bench. Returns its path, or "" (and `last_result` says why).
func new_from_file(path: String, owner: String = "") -> String:
	# A file dragged in from the FileSystem arrives as its uid ("uid://dd6y3..."): the new piece is
	# named from the file's real name, never from that.
	if path.begins_with("uid://"):
		var uid: int = ResourceUID.text_to_id(path)
		path = ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		last_result = "choose a file to make it from first"
		_update_status()
		return ""
	var o: String = owner if not owner.is_empty() else _default_owner()
	var errors: Array[String] = []
	var made: String = ContentLibrary.create(content_type(), o, path.get_file().get_basename().replace("_", " ").capitalize(), errors)
	if made.is_empty():
		last_result = "could not make it: %s" % "; ".join(errors)
		_update_status()
		return ""
	var def: ContentDef = ResourceLoader.load(made, "", ResourceLoader.CACHE_MODE_REPLACE) as ContentDef
	var why: String = fill_from_file(def, path)
	if not why.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(made))
		last_result = why
		_update_status()
		return ""
	ResourceSaver.save(def, made)
	_set_item(def)
	intake_file = ""
	last_result = "made %s from %s" % [made.get_file(), path.get_file()]
	_update_status()
	return made


func new_from_intake() -> void:
	new_from_file(intake_file, intake_owner)


func _default_owner() -> String:
	var owners: PackedStringArray = ContentLibrary.owners()
	return owners[1] if owners.size() > 1 else ContentLibrary.FOUNDATION


func _ready() -> void:
	_ready_done = true
	if pending != null and pending.content_type() == content_type():
		_set_item(pending)
		pending = null
	elif _item == null:
		var all: Array[ContentDef] = items()
		if not all.is_empty():
			_set_item(all[0])
	else:
		_refresh()


## Every piece of this bench's type.
func items() -> Array[ContentDef]:
	return ContentLibrary.items(content_type())


func next_item() -> void:
	_step(1)


func previous_item() -> void:
	_step(-1)


## Run the test chosen in the Inspector (the first, when none is).
func run_selected_test() -> void:
	var actions: Array[StringName] = test_actions()
	if actions.is_empty():
		return
	var a: StringName = test if actions.has(test) else actions[0]
	await run_named_test(a)


## Run one test and record what it said.
func run_named_test(action: StringName) -> String:
	last_result = "%s: running…" % action
	_update_status()
	last_result = "%s: %s" % [action, await run_test(action)]
	_update_status()
	return last_result


## green: nothing wrong; amber: a bench's fit check warns; red: the piece is invalid (the bake
## would refuse it). { level, sentences }.
func badge() -> Dictionary:
	if _item == null:
		return {"level": "red", "sentences": ["nothing on the bench"]}
	var bad: Array[String] = _item.validate()
	if not bad.is_empty():
		return {"level": "red", "sentences": bad}
	var warn: Array[String] = fit_checks()
	if not warn.is_empty():
		return {"level": "amber", "sentences": warn}
	return {"level": "green", "sentences": []}


## Save the piece to its file. OK, or the error.
func save() -> Error:
	if _item == null or _item.resource_path.is_empty():
		return ERR_UNCONFIGURED
	var err: Error = ResourceSaver.save(_item, _item.resource_path)
	last_result = "saved %s" % _item.resource_path.get_file() if err == OK else "could not save: %s" % error_string(err)
	_update_status()
	return err


## The Catalog's picture of this piece: the bench's `ThumbnailCamera` (else its first camera),
## rendered off screen. Null without a renderer (headless).
func capture_thumbnail() -> Image:
	var cam: Camera3D = get_node_or_null(^"ThumbnailCamera") as Camera3D
	if cam == null:
		var cams: Array[Node] = find_children("*", "Camera3D", true, false)
		cam = cams[0] as Camera3D if not cams.is_empty() else null
	if cam == null or DisplayServer.get_name() == "headless":
		return null
	var vp := SubViewport.new()
	vp.size = THUMB_SIZE
	vp.own_world_3d = false
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shot := Camera3D.new()
	shot.global_transform = cam.global_transform
	shot.fov = cam.fov
	vp.add_child(shot)
	add_child(vp)
	shot.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


## Render `def` in the workbench at `scene_path` WITHOUT opening it: the bench is built in a hidden
## viewport under `host`, the piece loaded, its ThumbnailCamera rendered, and the picture stored
## where the Catalog looks. Returns the image (null without a renderer). The Catalog's Regenerate.
static func render_offscreen(scene_path: String, def: ContentDef, host: Node) -> Image:
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(scene_path):
		return null
	var vp := SubViewport.new()
	vp.size = THUMB_SIZE
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	pending = def
	var bench: Node = (load(scene_path) as PackedScene).instantiate()
	vp.add_child(bench)
	var cam: Camera3D = bench.get_node_or_null(^"ThumbnailCamera") as Camera3D
	if cam != null:
		cam.current = true
	await bench.get_tree().process_frame
	# A picture, not a page: a bench's words are for the person at it, unreadable at this size.
	for l: Node in bench.find_children("*", "Label3D", true, false):
		(l as Label3D).visible = false
	for i: int in 3:
		await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img != null:
		var path: String = thumbnail_path(def)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		img.save_png(path)
	return img


## Capture and keep the thumbnail where the Catalog looks for it.
func capture_and_store_thumbnail() -> void:
	if _item == null:
		return
	var img: Image = await capture_thumbnail()
	if img == null:
		last_result = "no thumbnail: there is no renderer (headless)"
	else:
		var path: String = thumbnail_path(_item)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		img.save_png(path)
		last_result = "thumbnail saved"
	_update_status()


## Where a piece's thumbnail is kept: a cache under tools/workbench/thumbnails/ (not imported, not
## committed; Regenerate makes them again).
static func thumbnail_path(def: ContentDef) -> String:
	var owner: String = ContentLibrary.owner_of_path(def.resource_path)
	return "%s/%s/%s_%s.png" % [THUMBNAILS, def.content_type(), owner, def.resource_path.get_file().get_basename()]


## A piece's thumbnail, or null when none was captured.
static func thumbnail_of(def: ContentDef) -> Texture2D:
	var path: String = thumbnail_path(def)
	if not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null else null


func _process(delta: float) -> void:
	_watch_left -= delta
	if _watch_left > 0.0 or _item == null:
		return
	_watch_left = WATCH_SECONDS
	var now: String = fields_of(_item)
	if now != _seen:
		_seen = now
		_refresh()


## A piece's saved fields, as text (what the bench watches).
static func fields_of(def: ContentDef) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p: Dictionary in def.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_STORAGE != 0 and p["name"] != "script":
			parts.append("%s=%s" % [p["name"], var_to_str(def.get(p["name"]))])
	return "|".join(parts)


func _set_item(v: ContentDef) -> void:
	if _item != null and _item.changed.is_connected(_refresh):
		_item.changed.disconnect(_refresh)
	_item = v
	if _item != null:
		_item.changed.connect(_refresh)
		_seen = fields_of(_item)
		if tries_on_character() and (character == null or not _character_chosen):
			character = default_character()
	last_result = ""
	if _ready_done:
		_refresh()


func _refresh() -> void:
	load_item(_item)
	_update_status()


func _update_status() -> void:
	var b: Dictionary = badge()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s%s" % [String(b["level"]).to_upper(), "" if _item == null else "  %s %d %s" % [_item.content_type(), _item.id, _item.display_name]])
	for s: String in b["sentences"] as Array:
		lines.append("• " + s)
	if not last_result.is_empty():
		lines.append(last_result)
	if read_only_here():
		lines.insert(1, "the template's piece: read-only in this game (Copy into a genre to change it)")
	status = "\n".join(lines)
	notify_property_list_changed()
	panel_changed.emit()


func _step(by: int) -> void:
	var all: Array[ContentDef] = items()
	if all.is_empty():
		return
	var at: int = all.find(_item)
	_set_item(all[posmod(at + by, all.size())])


func _validate_property(p: Dictionary) -> void:
	# A BENCH KEEPS NOTHING IN ITS SCENE (DECISIONS #207): what is on it, which test, which character
	# it is tried on belong to the session, so opening and using one never changes its .tscn (a
	# game's copy of the template's benches stays the template's).
	if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
		p["usage"] = int(p["usage"]) & ~PROPERTY_USAGE_STORAGE
	if p["name"] == "test":
		p["hint"] = PROPERTY_HINT_ENUM
		p["hint_string"] = ",".join(test_actions().map(func(a: StringName) -> String: return String(a)))
	elif p["name"] == "status":
		p["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY   # shown, never saved in the scene
