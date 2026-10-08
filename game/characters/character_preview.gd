extends Node3D
## LOOK AT A CHARACTER without starting a server.
##
## `player.tscn` ships a greybox capsule on purpose: the real model arrives at runtime from
## `EntityDefinition.visual_scene`, so a game swaps characters by editing a `.tres` and never a
## scene (DECISIONS #60, #96). The cost of that is exactly what this scene fixes — opening
## `player.tscn` in the editor shows you the capsule, not your character.
##
## Press F6 here instead. It loads a definition the same way the spawner does — model, offset,
## facing, animation set — and plays its clips, alone, with no blending in the way.
##
##   LEFT / RIGHT   previous / next clip in the set
##   UP / DOWN      previous / next look, for a definition with `visual_variants`
##   L              every look side by side, playing the same clip
##   C              show the collision capsule the body actually uses
##   R              reload the definition from disk: edit the .tres, press R, see it
##   ESC            quit
##
## `--shot=<path>` renders a few frames, saves a PNG of this viewport and exits, which is how
## the animation work is checked without a person having to watch it. `--look=<n>` picks a look,
## `--lineup` shows them all, `--clip=<semantic>` pins a clip.

## Which character to look at. Any `EntityDefinition` with a `visual_scene`.
@export var definition: EntityDefinition
## Where the camera sits, relative to the character's feet.
@export var camera_offset: Vector3 = Vector3(0.0, 1.1, 3.2)

@onready var _holder: Node3D = $Model
@onready var _label: Label = $UI/Info
@onready var _capsule: MeshInstance3D = $CollisionPreview
@onready var _camera: Camera3D = $Camera3D

var _clips: Array[StringName] = []
var _index: int = 0
var _look: int = 0
var _lineup: bool = false
var _model: Node3D = null
var _skeleton: Skeleton3D = null
var _tree: AnimationTree = null
## Every shown look's tree, all playing the current clip (one of them, outside lineup mode).
var _trees: Array[AnimationTree] = []
var _shot_path: String = ""
var _show_capsule: bool = false
var _frames: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_path = arg.substr("--shot=".length())
		elif arg.begins_with("--clip="):
			_clips = [StringName(arg.substr("--clip=".length()))]
		elif arg == "--capsule":
			_show_capsule = true
		elif arg.begins_with("--look="):
			_look = int(arg.substr("--look=".length()))
		elif arg == "--lineup":
			_lineup = true
	_capsule.visible = _show_capsule
	_camera.position = camera_offset
	_camera.look_at(Vector3(0.0, 0.9, 0.0))
	_build()


func _build() -> void:
	for c: Node in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_model = null
	_skeleton = null
	_tree = null
	_trees.clear()
	var looks: Array[PackedScene] = _looks()
	if definition == null or looks.is_empty():
		_label.text = "no definition, or it has no visual_scene"
		return
	_look = posmod(_look, looks.size())
	var set: AnimationSet = definition.animation_set
	if set != null and _clips.size() != 1:   # --clip= pins one; otherwise every clip the set names
		_clips.assign(set.clips.keys())
		_clips.sort()
	_index = clampi(_index, 0, maxi(0, _clips.size() - 1))
	var shown: Array[int] = [_look]
	if _lineup:
		shown.assign(range(looks.size()))
	_camera.position = camera_offset * (maxf(1.0, looks.size() * 0.3) if _lineup else 1.0)
	_camera.look_at(Vector3(0.0, 0.9, 0.0))
	for i: int in shown:
		var model: Node3D = looks[i].instantiate() as Node3D
		_holder.add_child(model)
		var x: float = (i - (looks.size() - 1) * 0.5) * 1.1 if _lineup else 0.0
		model.position = definition.visual_offset + Vector3(x, 0.0, 0.0)
		# A lineup is for comparing outfits, so it faces the camera; one look shows its back, the
		# way the game's camera sees it.
		model.rotation.y = deg_to_rad(definition.visual_yaw_deg + (180.0 if _lineup else 0.0))
		var skel: Skeleton3D = null
		for n: Node in _all(model):
			if n is Skeleton3D:
				skel = n
		if i == _look:
			_model = model
			_skeleton = skel
		if set == null or skel == null:
			continue
		if skel.name != &"Skeleton3D":
			skel.name = "Skeleton3D"
		var tree := AnimationTree.new()
		for lib_name: StringName in set.libraries:
			if set.libraries[lib_name] != null:
				tree.add_animation_library(lib_name, set.libraries[lib_name])
		tree.tree_root = AnimationNodeAnimation.new()
		model.add_child(tree)
		tree.root_node = tree.get_path_to(skel.get_parent())
		tree.active = true
		_trees.append(tree)
		if i == _look:
			_tree = tree
	if set == null or _skeleton == null:
		_label.text = "%s: a model with no %s" % [definition.display_name,
			"skeleton" if _skeleton == null else "animation set"]
		return
	_play()


## The looks this definition can wear: its variants, or its one model.
func _looks() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	if definition == null:
		return out
	if not definition.visual_variants.is_empty():
		out.assign(definition.visual_variants)
	elif definition.visual_scene != null:
		out.append(definition.visual_scene)
	return out


func _play() -> void:
	if _tree == null or _clips.is_empty():
		return
	for tree: AnimationTree in _trees:
		_play_on(tree)


func _play_on(tree: AnimationTree) -> void:
	var set: AnimationSet = definition.animation_set
	var semantic: StringName = _clips[_index]
	var clip: StringName = set.anim_name(semantic) if set.has_exact(semantic) else semantic
	var node: AnimationNodeAnimation = tree.tree_root as AnimationNodeAnimation
	# PLAY IT THE WAY THE GAME WILL, speed_scale and all. Pointing the node straight at the clip is
	# what this did before, and it meant the preview showed every clip at its authored speed — so a
	# clip the game played wrongly looked perfectly fine in here (DECISIONS #103).
	if set.has_exact(semantic):
		AnimationTreeBuilder.apply_clip(node, set, semantic)
	else:
		node.use_custom_timeline = false   # a raw clip name, not something the set speaks for
		node.animation = clip
	# Loop everything here: a one-shot clip left on its last frame looks like a broken rig. That
	# includes the node's own override, which is what `use_custom_timeline` switches the loop to.
	if node.use_custom_timeline:
		node.loop_mode = Animation.LOOP_LINEAR
	var anim: Animation = _find_anim(set, clip)
	if anim != null and anim.loop_mode == Animation.LOOP_NONE:
		anim.loop_mode = Animation.LOOP_LINEAR
	tree.active = false
	tree.active = true


func _process(_delta: float) -> void:
	_label.text = _status()
	_frames += 1
	if not _shot_path.is_empty() and _frames == 20:
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("[preview] wrote ", _shot_path)
		AppExit.quit(get_tree())


func _status() -> String:
	if definition == null:
		return "no definition"
	var lines: Array[String] = []
	var looks: Array[PackedScene] = _looks()
	lines.append("%s   look %d/%d %s" % [definition.display_name, _look + 1, looks.size(),
		looks[_look].resource_path.get_file() if _look < looks.size() else "-"])
	if _clips.is_empty():
		lines.append("no clips")
	else:
		var set: AnimationSet = definition.animation_set
		var semantic: StringName = _clips[_index]
		lines.append("[%d/%d]  %s  ->  %s" % [_index + 1, _clips.size(), semantic,
			set.anim_name(semantic) if set != null else "?"])
	if _skeleton != null:
		lines.append("head %.2f m   pelvis %.2f m   foot %.2f m   (yaw %.0f deg)"
			% [_bone_y("Head"), _bone_y("pelvis"), _bone_y("foot_l"), definition.visual_yaw_deg])
	lines.append("LEFT/RIGHT clip    UP/DOWN look    L lineup    C capsule    R reload    ESC quit")
	return "\n".join(lines)


func _bone_y(bone: String) -> float:
	var i: int = _skeleton.find_bone(bone)
	return _skeleton.get_bone_global_pose(i).origin.y if i >= 0 else NAN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		AppExit.quit(get_tree())
	elif event.is_action_pressed(&"ui_right") and not _clips.is_empty():
		_index = (_index + 1) % _clips.size()
		_play()
	elif event.is_action_pressed(&"ui_left") and not _clips.is_empty():
		_index = (_index - 1 + _clips.size()) % _clips.size()
		_play()
	elif event.is_action_pressed(&"ui_down"):
		_look += 1
		_build()
	elif event.is_action_pressed(&"ui_up"):
		_look -= 1
		_build()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key: InputEventKey = event
		if key.physical_keycode == KEY_C:
			_capsule.visible = not _capsule.visible
		elif key.physical_keycode == KEY_L:
			_lineup = not _lineup
			_build()
		elif key.physical_keycode == KEY_R:
			# Straight off disk, past the cache: edit the .tres, press R.
			if definition != null and not definition.resource_path.is_empty():
				definition = ResourceLoader.load(definition.resource_path, "",
					ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EntityDefinition
			_build()


func _find_anim(set: AnimationSet, full_name: StringName) -> Animation:
	var s: String = String(full_name)
	var slash: int = s.find("/")
	var lib: AnimationLibrary = set.libraries.get(
		StringName(s.substr(0, slash)) if slash >= 0 else &"", null)
	var clip: StringName = StringName(s.substr(slash + 1)) if slash >= 0 else full_name
	return lib.get_animation(clip) if lib != null and lib.has_animation(clip) else null


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c: Node in n.get_children():
		out.append_array(_all(c))
	return out
