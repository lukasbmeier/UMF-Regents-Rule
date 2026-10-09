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


## What is playing.
func playing() -> StringName:
	return _playing


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
