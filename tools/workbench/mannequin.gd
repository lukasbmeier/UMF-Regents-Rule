@tool
class_name Mannequin extends Node3D
## THE REAL CHARACTER, IN A WORKBENCH (DECISIONS #203): an `EntityDefinition`'s model, dressed and
## animated through its `AnimationSet` exactly the way the game plays it (`AnimationTreeBuilder.
## apply_clip`, speed scale and all), with no server. Every workbench that tests content against a
## character drops one in: the ability bench now; the held-item, fish-reveal and NPC benches next.
##
##   play(&"interact")            a semantic clip (falls back as the set says); loops, or once
##   clip_length(&"interact")     how long it runs at the speed the game plays it
##   bone_position(&"hand.r")     where a bone is now (fit checks)
##   preview(&"model/Walk")       ANY clip, to look at closely (DECISIONS #207): a semantic name, a
##                                set's clip ("extra/Fish_Cast") or the model's own ("model/Walk");
##                                with `preview_speed`, `preview_paused` and `seek_fraction`

## Which character. Any `EntityDefinition` with a model and an animation set.
@export var definition: EntityDefinition:
	set(v):
		definition = v
		if is_inside_tree():
			rebuild()
## Which of its looks (`visual_variants`), when it has several.
@export var look: int = 0:
	set(v):
		look = v
		if is_inside_tree():
			rebuild()

var model: Node3D = null
var skeleton: Skeleton3D = null
var _tree: AnimationTree = null
var _playing: StringName = &""
## PREVIEW: a clip looked at closely. The set's clips play on `_preview`; the model's own on the
## player it came with. Either stops the game-like tree while it plays.
var _preview: AnimationPlayer = null
var _preview_on: AnimationPlayer = null
var _preview_name: StringName = &""
var preview_speed: float = 1.0:
	set(v):
		preview_speed = v
		if _preview_on != null:
			_preview_on.speed_scale = v * _preview_clip_scale
var preview_paused: bool = false:
	set(v):
		preview_paused = v
		if _preview_on != null:
			if v:
				_preview_on.pause()
			elif not String(_preview_on.assigned_animation).is_empty():
				_preview_on.play()
var _preview_clip_scale: float = 1.0


func _ready() -> void:
	rebuild()


## Build the model again from the definition (after it changed).
func rebuild() -> void:
	for c: Node in get_children():
		c.queue_free()
	model = null
	skeleton = null
	_tree = null
	if definition == null:
		return
	var scene: PackedScene = definition.visual_scene
	if not definition.visual_variants.is_empty():
		scene = definition.visual_variants[clampi(look, 0, definition.visual_variants.size() - 1)]
	if scene == null:
		return
	model = scene.instantiate() as Node3D
	add_child(model)
	model.position = definition.visual_offset
	model.rotation.y = deg_to_rad(definition.visual_yaw_deg)
	model.scale = Vector3.ONE * definition.visual_scale
	_preview = null
	_preview_on = null
	_preview_name = &""
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n as Skeleton3D
		break
	var set: AnimationSet = definition.animation_set
	if set == null or skeleton == null:
		return
	if skeleton.name != &"Skeleton3D":
		skeleton.name = "Skeleton3D"
	_tree = AnimationTree.new()
	for lib_name: StringName in set.libraries:
		if set.libraries[lib_name] != null:
			_tree.add_animation_library(lib_name, set.libraries[lib_name])
	_tree.tree_root = AnimationNodeAnimation.new()
	model.add_child(_tree)
	_tree.root_node = _tree.get_path_to(skeleton.get_parent())
	_tree.active = true
	play(&"locomotion.idle")


## Play a semantic clip, the way the game does. False when the set has nothing for it.
func play(semantic: StringName, looped: bool = true) -> bool:
	if _tree == null or definition == null or definition.animation_set == null:
		return false
	_stop_preview()
	var set: AnimationSet = definition.animation_set
	if set.clip(semantic) == null:
		return false
	var node: AnimationNodeAnimation = _tree.tree_root as AnimationNodeAnimation
	AnimationTreeBuilder.apply_clip(node, set, semantic if set.has_exact(semantic) else _resolved(set, semantic))
	if node.use_custom_timeline:
		node.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	_tree.active = false
	_tree.active = true
	_playing = semantic
	return true


## What is playing (the game-like tree), or the clip being previewed.
func playing() -> StringName:
	return _preview_name if not _preview_name.is_empty() else _playing


## EVERY CLIP THIS CHARACTER COULD PLAY, for a picker: [[name, label]]. Its set's semantic names
## first (what the game plays), then each clip of its set's libraries, then the model's own clips
## ("model/Walk").
func clip_choices() -> Array:
	var out: Array = []
	var set: AnimationSet = definition.animation_set if definition != null else null
	if set != null:
		var semantics: Array = set.clips.keys()
		semantics.sort()
		for s: StringName in semantics:
			out.append([s, "%s  (%s)" % [s, set.clips[s].anim_name]])
		for lib: StringName in set.libraries:
			if set.libraries[lib] == null:
				continue
			for a: StringName in set.libraries[lib].get_animation_list():
				var q: StringName = ClipMatcher.qualify(lib, String(a))
				out.append([q, "clip: %s" % q])
	var own: AnimationPlayer = ClipMatcher.model_player(model)
	if own != null:
		for lib: StringName in own.get_animation_library_list():
			for a: StringName in own.get_animation_library(lib).get_animation_list():
				if a != &"RESET":
					out.append([StringName("model/" + String(ClipMatcher.qualify(lib, String(a)))), "model: %s" % ClipMatcher.qualify(lib, String(a))])
	return out


## PREVIEW ANY CLIP (the character workbench's picker): `what` is a semantic name (played at the
## speed the game plays it), a set's clip, or "model/<clip>" (the model's own). False when there is
## no such clip on this character.
func preview(what: StringName) -> bool:
	_stop_preview()
	if model == null:
		return false
	var s: String = String(what)
	var player: AnimationPlayer = null
	var anim: StringName = &""
	_preview_clip_scale = 1.0
	if s.begins_with("model/"):
		player = ClipMatcher.model_player(model)
		anim = StringName(s.substr("model/".length()))
	else:
		var set: AnimationSet = definition.animation_set if definition != null else null
		if set == null or skeleton == null:
			return false
		var ref: AnimationClipRef = set.clip(what) if not s.contains("/") or set.clips.has(what) else null
		anim = ref.anim_name if ref != null else what
		if ref != null:
			_preview_clip_scale = ref.speed_scale
		if _preview == null:
			_preview = AnimationPlayer.new()
			_preview.name = "Preview"
			for lib_name: StringName in set.libraries:
				if set.libraries[lib_name] != null:
					_preview.add_animation_library(lib_name, set.libraries[lib_name])
			model.add_child(_preview)
			_preview.root_node = _preview.get_path_to(skeleton.get_parent())
		player = _preview
	if player == null or not player.has_animation(anim):
		return false
	if _tree != null:
		_tree.active = false
	player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
	player.play(anim)
	player.speed_scale = preview_speed * _preview_clip_scale
	if preview_paused:
		player.pause()
	_preview_on = player
	_preview_name = what
	return true


## How long the previewed clip is (s, at its own speed), 0 with none.
func preview_length() -> float:
	if _preview_on == null or String(_preview_on.assigned_animation).is_empty():
		return 0.0
	return _preview_on.get_animation(_preview_on.assigned_animation).length


## Where in the previewed clip, 0..1.
func preview_fraction() -> float:
	var l: float = preview_length()
	return _preview_on.current_animation_position / l if l > 0.0 else 0.0


## Jump to `f` (0..1) of the previewed clip: scrub it, paused or playing.
func seek_fraction(f: float) -> void:
	var l: float = preview_length()
	if l > 0.0:
		_preview_on.seek(clampf(f, 0.0, 1.0) * l, true)


func _stop_preview() -> void:
	if _preview_on != null:
		_preview_on.stop()
	_preview_on = null
	_preview_name = &""
	if _tree != null:
		_tree.active = true


## How long a semantic clip runs at the speed the game plays it (0 when the set has none).
func clip_length(semantic: StringName) -> float:
	if _tree == null or definition == null or definition.animation_set == null:
		return 0.0
	var ref: AnimationClipRef = definition.animation_set.clip(semantic)
	if ref == null:
		return 0.0
	var anim: Animation = _tree.get_animation(ref.anim_name)
	return anim.length / maxf(ref.speed_scale, 0.001) if anim != null else 0.0


## Where a bone is now, in world space; Vector3.INF when there is no such bone.
func bone_position(bone: StringName) -> Vector3:
	if skeleton == null:
		return Vector3.INF
	var i: int = skeleton.find_bone(bone)
	return skeleton.to_global(skeleton.get_bone_global_pose(i).origin) if i >= 0 else Vector3.INF


## The semantic name the set actually holds for `semantic` (following its fallbacks).
static func _resolved(set: AnimationSet, semantic: StringName) -> StringName:
	if set.has_exact(semantic):
		return semantic
	for alt: StringName in AnimationSet.FALLBACKS.get(semantic, [] as Array):
		var r: StringName = _resolved(set, alt)
		if r != &"":
			return r
	return &""


## What it wears is the bench's choice of the moment, never saved into the bench's scene (DECISIONS #207).
func _validate_property(p: Dictionary) -> void:
	if p["name"] == "definition" or p["name"] == "look":
		p["usage"] = int(p["usage"]) & ~PROPERTY_USAGE_STORAGE
