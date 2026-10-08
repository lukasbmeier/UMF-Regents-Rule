extends Node3D
## LOOK AT FISHING without a server: an angler with a rod beside a real pond, driven by keys.
##
## Same `FishingFx`, same pond scene, same rod and sounds as the game — only the facts that drive
## them come from the keyboard instead of the module. Press F6 here to see and hear a change to
## any of them without publishing anything.
##
##   C      cast                     N / M   the tell / the bite
##   1..5   land a fish, trash to illegal        6 / 7   an anvil / the legendary chest
##   R      reel in                  V       change the camera        ESC  quit
##
## `--shot=<path> --scenario=idle|cast|float|catch|swing [--view=over|side|close] [--at=<s>]`
## renders one moment and exits: how the look of all this is checked without a person watching
## it. `swing` plays the cast clip with no float, shot `--at` seconds in — for timing the release.

@export var definition: EntityDefinition

@onready var _pond: PondVisual = $Pond/Visual
@onready var _angler: Node3D = $Angler
@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $UI/Info

const _VIEWS: Dictionary[String, Array] = {
	"over": [Vector3(1.4, 2.4, 5.0), Vector3(0.0, 0.5, 0.2)],
	"side": [Vector3(4.2, 1.5, 1.6), Vector3(0.0, 0.8, 0.9)],
	"close": [Vector3(1.3, 1.8, 3.2), Vector3(-0.1, 1.2, 1.5)],
}

var _fx: FishingFx = null
var _tree: AnimationTree = null
var _view: String = "over"
var _shot_path: String = ""
var _scenario: String = "idle"
var _clock: float = 0.0
var _script_step: int = 0
var _at: float = -1.0


func _ready() -> void:
	# Its pond plays the looping ambience: closing the window quits through AppExit (DECISIONS #151).
	AppExit.hold_close_request(get_tree())
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.substr("--shot=".length())
		elif arg.begins_with("--scenario="):
			_scenario = arg.substr("--scenario=".length())
		elif arg.begins_with("--view="):
			_view = arg.substr("--view=".length())
		elif arg.begins_with("--at="):
			_at = float(arg.substr("--at=".length()))
	_build_angler()
	_place_camera()


func _build_angler() -> void:
	if definition == null or definition.visual_for(0) == null:
		_label.text = "no definition with a visual_scene"
		return
	var model: Node3D = definition.visual_for(0).instantiate() as Node3D
	model.name = "Model"
	$Angler/Visual.add_child(model)
	model.position = definition.visual_offset
	model.rotation.y = deg_to_rad(definition.visual_yaw_deg)
	var skeleton: Skeleton3D = null
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n as Skeleton3D
	if skeleton != null and definition.animation_set != null:
		skeleton.name = "Skeleton3D"
		_tree = AnimationTree.new()
		var set: AnimationSet = definition.animation_set
		for lib_name: StringName in set.libraries:
			if set.libraries[lib_name] != null:
				_tree.add_animation_library(lib_name, set.libraries[lib_name])
		_tree.tree_root = AnimationNodeAnimation.new()
		model.add_child(_tree)
		_tree.root_node = _tree.get_path_to(skeleton.get_parent())
		_play(AnimationSet.IDLE)
	_fx = FishingFx.new()
	_fx.name = "FishingFx"
	_fx.ripple_override = _pond.ripple
	_angler.add_child(_fx)
	var held: bool = _fx.hold_rod(skeleton)
	print("[feel] rod in hand: ", held)


func _play(semantic: StringName) -> void:
	if _tree == null:
		return
	var node: AnimationNodeAnimation = _tree.tree_root as AnimationNodeAnimation
	AnimationTreeBuilder.apply_clip(node, definition.animation_set, semantic)
	_tree.active = false
	_tree.active = true


func _place_camera() -> void:
	var v: Array = _VIEWS.get(_view, _VIEWS["over"])
	_camera.position = v[0]
	_camera.look_at(v[1])


func _process(delta: float) -> void:
	_clock += delta
	_label.text = "%s   float: %s   ripples %d\nC cast   N/M tell/bite   1-7 catch   R reel   V view" \
		% [_view, FishingFx.State.keys()[_fx.state()] if _fx != null else "-",
		_pond.ripples_started()]
	if _shot_path.is_empty() or _fx == null:
		return
	_run_scenario()


## A moment, then a picture. Steps are gated on the clock so a slow first frame cannot rush them.
func _run_scenario() -> void:
	var cast_at: float = 0.4
	var shot_at: float = 1.0
	match _scenario:
		"cast":
			shot_at = cast_at + (_at if _at >= 0.0 else FishingFx.RELEASE_SEC + 0.3)
		"float":
			shot_at = cast_at + 2.4
		"catch":
			shot_at = cast_at + 2.6 + 0.4
		"swing":
			shot_at = cast_at + maxf(0.0, _at)
			if _script_step == 0 and _clock >= cast_at:
				_script_step = 1
				_play(AnimationSet.INTERACT)
		_:
			cast_at = INF
	if _script_step == 0 and _clock >= cast_at and _scenario != "swing":
		_script_step = 1
		_play(AnimationSet.INTERACT)
		_cast()
	if _script_step == 1 and _scenario == "catch" and _clock >= cast_at + 2.6:
		_script_step = 2
		_fx.land_catch("legendary_chest", 60.0, _angler.global_position, true)
	if _clock >= shot_at and _script_step < 9:
		_script_step = 9
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("[feel] wrote ", _shot_path)
		AppExit.quit(get_tree())


## Into the pond, the way the game casts into the lake: to a point on the water.
func _cast() -> void:
	_fx.cast_to_point(_pond.landing_point(_angler.global_position + Vector3(0.0, 1.5, 0.0)),
		FishingFx.RELEASE_SEC, 0.55)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		AppExit.quit(get_tree())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		AppExit.quit(get_tree())
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or _fx == null:
		return
	match key.physical_keycode:
		KEY_C:
			_play(AnimationSet.INTERACT)
			_cast()
		KEY_N:
			_fx.twitch(1.0)
		KEY_M:
			_fx.bite()
		KEY_R:
			_fx.reel_in()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			var keys: Array[String] = ["bluegill", "largemouth_bass", "northern_pike", "golden_koi",
				"lake_marlin", "anvil", "legendary_chest"]
			var pick: String = keys[key.physical_keycode - KEY_1]
			_fx.land_catch(pick, float(FishingData.catch_def(pick).get("kg", 1.0)),
				_angler.global_position, true)
		KEY_V:
			var views: Array[String] = []
			views.assign(_VIEWS.keys())
			_view = views[(views.find(_view) + 1) % views.size()]
			_place_camera()
