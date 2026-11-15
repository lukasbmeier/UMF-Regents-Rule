class_name ShowcaseActor extends Node3D
## A CHARACTER THAT ACTS, WITH NO SERVER (the showcase, 2026-11-15): the login screen's people, the vista's and the
## battle lab's fighters. An `EntityDefinition`'s model in one of its looks, a weapon in its hand, played through its
## `AnimationSet` by the same semantic names the game uses (`ability.40001`, `react.stagger`, `pose.bow_aim`), with a
## short crossfade between clips, as a camera close up wants. It ships (the login uses it), so it does not use the
## workbench's `Mannequin` (tools/ stays out of the build).
##
## Presentation only (hard rule 11): it decides nothing; a lab's timeline tells it what to play and where to go.
##
##   play(&"locomotion.idle")              loop a clip
##   act(&"ability.40001")                 play once, then back to what was looping; returns its length (s)
##   walk_to(Vector3(4, 0, 2), 1.6)        walk (or run, fast enough) there and stop facing the way it went
##   face(point)                            turn toward a point (smoothly, `turn_rate`)

## Its clips' crossfade (s).
@export_range(0.0, 1.0, 0.01, "suffix:s") var blend_s: float = 0.16
## How fast it turns to face where it is told (rad/s).
@export_range(0.5, 30.0, 0.5) var turn_rate: float = 9.0
## At or above this speed (m/s) a move plays the run, below it the walk.
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var run_from_mps: float = 2.4
## Where the ground is under a point (x, z) -> y; unset: y stays as it is. The world sets it.
var ground: Callable = Callable()

var definition: EntityDefinition = null
var model: Node3D = null
var skeleton: Skeleton3D = null
var held: HeldItem = null
var _tree: AnimationTree = null
var _anims: Array[AnimationNodeAnimation] = []
var _side: int = 0
var _loop: StringName = &"locomotion.idle"
var _once: StringName = &""
var _once_left: float = 0.0
## A one-shot that stays on its last frame (a death) until the next `play`.
var _holding: bool = false
## The clip last started (what `playing` says).
var _now: StringName = &"locomotion.idle"
var _goal: Vector3 = Vector3.INF
var _speed: float = 0.0
var _face_at: Vector3 = Vector3.INF


## Build it: `def`'s look `look` (an index into its `visual_variants`), holding `weapon` (a held item's scene) or, for
## a foe, dressed as `foe` says (its texture, the meshes it hides, what it holds).
static func make(def: EntityDefinition, look: int = 0, weapon: PackedScene = null, foe: FoeDef = null) -> ShowcaseActor:
	var a := ShowcaseActor.new()
	a.definition = def
	a._build(look, weapon, foe)
	return a


func _build(look: int, weapon: PackedScene, foe: FoeDef) -> void:
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
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n as Skeleton3D
		break
	var set: AnimationSet = definition.animation_set
	if set == null or skeleton == null:
		return
	if skeleton.name != &"Skeleton3D":
		# The set's clips address "Skeleton3D" (as the game's spawner and the Mannequin rename it).
		var own: AnimationPlayer = ClipMatcher.model_player(model)
		if own != null:
			var from: Node = own.get_node_or_null(own.root_node)
			for lib: StringName in own.get_animation_library_list():
				var copy: AnimationLibrary = ClipMatcher.readdressed(own.get_animation_library(lib), from, skeleton)
				own.remove_animation_library(lib)
				own.add_animation_library(lib, copy)
			own.root_node = own.get_path_to(skeleton.get_parent())
		skeleton.name = "Skeleton3D"
	if foe != null:
		_dress_as(foe)
	elif weapon != null:
		held = HeldItem.attach(skeleton, weapon)
	# Two clip players and a crossfade between them: each new clip goes to the side not playing.
	_tree = AnimationTree.new()
	for lib_name: StringName in set.libraries:
		if set.libraries[lib_name] != null:
			_tree.add_animation_library(lib_name, set.libraries[lib_name])
	var blend := AnimationNodeBlendTree.new()
	var xfade := AnimationNodeTransition.new()
	xfade.xfade_time = blend_s
	xfade.input_count = 2
	xfade.set_input_name(0, "a")
	xfade.set_input_name(1, "b")
	# Each clip from its first frame when its side fades in.
	xfade.set_input_reset(0, true)
	xfade.set_input_reset(1, true)
	blend.add_node(&"xfade", xfade)
	for i: int in range(2):
		var anim := AnimationNodeAnimation.new()
		_anims.append(anim)
		blend.add_node(StringName("clip%d" % i), anim)
		blend.connect_node(&"xfade", i, StringName("clip%d" % i))
	blend.connect_node(&"output", 0, &"xfade")
	_tree.tree_root = blend
	model.add_child(_tree)
	_tree.root_node = _tree.get_path_to(skeleton.get_parent())
	_tree.active = true
	_start(&"locomotion.idle", true)


func _dress_as(foe: FoeDef) -> void:
	for n: Node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if foe.hidden_meshes.has(StringName(mi.name)):
			mi.visible = false
			continue
		if foe.albedo == null or mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var base: BaseMaterial3D = mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var mat: BaseMaterial3D = base.duplicate() as BaseMaterial3D
			mat.albedo_texture = foe.albedo
			mi.set_surface_override_material(i, mat)
	if foe.held_scene != null:
		held = HeldItem.attach(skeleton, foe.held_scene)


## Loop `semantic` from now on (and after any `act`). False when its set has nothing for it.
func play(semantic: StringName) -> bool:
	_loop = semantic
	_holding = false
	if _once_left > 0.0:
		return has(semantic)
	return _start(semantic, true)


## Play `semantic` once, then go back to the loop (or, `hold`, stay on its last frame: a death). Its length (s), or 0
## when there is no such clip.
func act(semantic: StringName, hold: bool = false) -> float:
	if not _start(semantic, false):
		return 0.0
	_once = semantic
	_once_left = clip_length(semantic)
	_holding = hold
	return _once_left


## Does its set have a clip for `semantic`?
func has(semantic: StringName) -> bool:
	return definition != null and definition.animation_set != null and definition.animation_set.clip(semantic) != null


## How long `semantic` runs as the game plays it (s); 0 when there is no such clip.
func clip_length(semantic: StringName) -> float:
	if _tree == null or not has(semantic):
		return 0.0
	var ref: AnimationClipRef = definition.animation_set.clip(semantic)
	var anim: Animation = _tree.get_animation(ref.anim_name)
	return anim.length / maxf(ref.speed_scale, 0.001) if anim != null else 0.0


## What it is playing now: the one-shot while it runs (a held death after), the walk while it walks, else the loop.
func playing() -> StringName:
	return _now


## Walk (or run) to `to` at `speed` m/s; it faces where it goes and stops there. Speed 0 places it at once.
func walk_to(to: Vector3, speed: float) -> void:
	if speed <= 0.0:
		position = _grounded(to)
		_goal = Vector3.INF
		return
	_goal = to
	_speed = speed
	if _once_left <= 0.0 and not _holding:
		_start(&"locomotion.run" if speed >= run_from_mps else &"locomotion.walk", true)


## Is it still on its way somewhere?
func moving() -> bool:
	return _goal != Vector3.INF


## Turn toward `at` (world); `now`: at once.
func face(at: Vector3, now: bool = false) -> void:
	_face_at = at
	if now:
		var d: Vector3 = at - global_position if is_inside_tree() else at - position
		if Vector2(d.x, d.z).length_squared() > 0.0001:
			rotation.y = yaw_toward(d)


## Where a bone is now (world), or INF.
func bone_position(bone: StringName) -> Vector3:
	if skeleton == null:
		return Vector3.INF
	var i: int = skeleton.find_bone(bone)
	return skeleton.to_global(skeleton.get_bone_global_pose(i).origin) if i >= 0 else Vector3.INF


## The yaw that makes a model (its visual forward turned to -Z by `visual_yaw_deg`) face along `d`.
static func yaw_toward(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _process(delta: float) -> void:
	if _once_left > 0.0:
		_once_left -= delta
		if _once_left <= 0.0 and _holding:
			_once = &""
		elif _once_left <= 0.0:
			_once = &""
			var back: StringName = _loop
			if moving():
				back = &"locomotion.run" if _speed >= run_from_mps else &"locomotion.walk"
			_start(back, true)
	if _goal != Vector3.INF:
		var d: Vector3 = _goal - position
		d.y = 0.0
		var step: float = _speed * delta
		if d.length() <= step:
			position = _grounded(_goal)
			_goal = Vector3.INF
			if _once_left <= 0.0 and not _holding:
				_start(_loop, true)
		else:
			position = _grounded(position + d.normalized() * step)
			rotation.y = lerp_angle(rotation.y, yaw_toward(d), minf(1.0, turn_rate * delta))
			return
	if _face_at != Vector3.INF:
		var f: Vector3 = _face_at - global_position
		if Vector2(f.x, f.z).length_squared() > 0.0001:
			rotation.y = lerp_angle(rotation.y, yaw_toward(f), minf(1.0, turn_rate * delta))


func _grounded(p: Vector3) -> Vector3:
	if ground.is_valid():
		return Vector3(p.x, float(ground.call(p.x, p.z)), p.z)
	return p


func _start(semantic: StringName, looped: bool) -> bool:
	if _tree == null or not has(semantic):
		return false
	var set: AnimationSet = definition.animation_set
	var resolved: StringName = semantic if set.has_exact(semantic) else _resolved(set, semantic)
	_side = 1 - _side
	var node: AnimationNodeAnimation = _anims[_side]
	AnimationTreeBuilder.apply_clip(node, set, resolved, looped)
	_tree.set("parameters/xfade/transition_request", "b" if _side == 1 else "a")
	_now = semantic
	if held != null:
		held.set_animation_weights({semantic: 1.0})
	return true


static func _resolved(set: AnimationSet, semantic: StringName) -> StringName:
	if set.has_exact(semantic):
		return semantic
	for alt: StringName in AnimationSet.FALLBACKS.get(semantic, [] as Array):
		var r: StringName = _resolved(set, alt)
		if r != &"":
			return r
	return &""
