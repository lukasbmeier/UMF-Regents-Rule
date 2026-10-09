@tool
@abstract
class_name Workbench extends Node3D
## WHERE A PIECE OF CONTENT IS MADE AND TESTED (docs/CONTENT_TOOLING_SPEC.md §3, DECISIONS #203):
## a `@tool` scene with the real character, the real animations and the real moment in the game,
## and no server. "No content type without a workbench": the `content` suite fails a type that has
## none and does not say why (`ContentDef.needs_workbench()`).
##
## USING ONE. Open it (the Content dock's "Open workbench" opens it with the chosen piece loaded),
## select the root node, and the Inspector has everything: `item` (the piece; edit it right there,
## the bench follows every change), the `test` to run and **Run test**, **Previous** / **Next**
## piece, **Save**, **Capture thumbnail** (the Catalog's picture), and `status` (what is wrong,
## green / amber / red, and what the last test showed).
##
## WRITING ONE. Subclass this as `<type>_workbench.gd`, scene `tools/workbench/<type>_workbench.tscn`
## (a genre's: `game/<genre>/workbench/`; both stay out of the builds). Implement `content_type()`,
## `load_item()` (show it), `test_actions()` and `run_test()` (play that moment and say what
## happened). Optional: `fit_checks()` (amber warnings), `new_item_from()` (a dropped file becomes a
## piece), a `ThumbnailCamera`. The base does the listing, loading, live edits, saving, the badge
## and thumbnails, so a workbench is mostly its tests.

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


## Checks only a bench can make (the reel 2 cm clear of the thigh across the clip), one sentence
## each: an amber badge. Empty: none.
func fit_checks() -> Array[String]:
	return []


## A dropped file (a .glb, a .wav) made into a new piece of this type, or null when this type is not
## made from a file.
func new_item_from(_path: String) -> ContentDef:
	return null


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
	status = "\n".join(lines)
	notify_property_list_changed()


func _step(by: int) -> void:
	var all: Array[ContentDef] = items()
	if all.is_empty():
		return
	var at: int = all.find(_item)
	_set_item(all[posmod(at + by, all.size())])


func _validate_property(p: Dictionary) -> void:
	if p["name"] == "test":
		p["hint"] = PROPERTY_HINT_ENUM
		p["hint_string"] = ",".join(test_actions().map(func(a: StringName) -> String: return String(a)))
	elif p["name"] == "status":
		p["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY   # shown, never saved in the scene
