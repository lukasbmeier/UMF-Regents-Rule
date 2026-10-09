@tool
class_name CharacterWorkbench extends Workbench
## THE CHARACTER WORKBENCH (DECISIONS #204): a character definition on the bench, its model dressed
## and animated the way the game does it (`Mannequin`), beside the collision capsule its entity
## really uses. Make a new one from a rigged model (New From File: drop the .glb), fit it in the
## Inspector (visual_offset, visual_yaw_deg), and test it:
##
##   every_clip    plays every clip its animation set names; lists any the game needs that are missing
##   walk_facing   reads which way its walk travels: a rig facing the wrong way moonwalks in the game
##   looks         wears each of its looks in turn
##
## Fit checks (amber): its feet are on the floor; its height fits its collision capsule.

## How long each clip plays in `every_clip`, and each look in `looks` (s).
@export_range(0.1, 3.0, 0.1) var seconds_each: float = 0.8

## Feet this far off the floor, or a model this much taller or shorter than its capsule, warns.
const FEET_TOLERANCE_M: float = 0.06
const HEIGHT_TOLERANCE: float = 0.2

var _capsule: MeshInstance3D = null
var _label: Label3D = null
## What the last facing measurement found: "forward", "backward", "in_place", "unknown" (tests).
var last_facing: String = ""


func content_type() -> StringName:
	return &"character"


func test_actions() -> Array[StringName]:
	return [&"every_clip", &"walk_facing", &"looks"]


func load_item(def: ContentDef) -> void:
	_build_props()
	var d: EntityDefinition = def as EntityDefinition
	var m: Mannequin = _mannequin()
	m.definition = d
	var cap: CapsuleShape3D = capsule_of(d)
	_capsule.visible = cap != null
	if cap != null:
		var mesh: CapsuleMesh = _capsule.mesh as CapsuleMesh
		mesh.radius = cap.radius
		mesh.height = cap.height
		_capsule.position.y = cap.height * 0.5
	var cam: Camera3D = get_node_or_null(^"ThumbnailCamera") as Camera3D
	if cam != null:
		cam.look_at_from_position(Vector3(0.9, 1.45, -2.7), Vector3(0.25, 0.95, 0.0))   # a three-quarter front view
	_label.text = "" if d == null else "%s  ·  kind %d  ·  %s  ·  %d look(s)" % [d.display_name, d.kind,
		"no animation set" if d.animation_set == null else "%d clips" % d.animation_set.clips.size(),
		maxi(d.visual_variants.size(), 1 if d.visual_scene != null else 0)]


func run_test(action: StringName) -> String:
	var d: EntityDefinition = item as EntityDefinition
	if d == null:
		return "nothing on the bench"
	var m: Mannequin = _mannequin()
	match action:
		&"every_clip":
			if d.animation_set == null:
				return "no animation set: this character does not animate"
			var played: Array[String] = []
			var names: Array = d.animation_set.clips.keys()
			names.sort()
			for semantic: StringName in names:
				if m.play(semantic):
					played.append(String(semantic))
					_label.text = String(semantic)
					await get_tree().create_timer(seconds_each).timeout
			m.play(&"locomotion.idle")
			var missing: Array[StringName] = d.animation_set.missing_required()
			return "played %d clip(s); %s" % [played.size(),
				"every clip the game needs is there" if missing.is_empty() else "MISSING what the game needs: %s" % ", ".join(missing)]
		&"walk_facing":
			last_facing = facing(d)
			match last_facing:
				"forward": return "its walk travels forward (-Z, the game's forward): it faces the way it walks"
				"backward": return "its walk travels BACKWARD: it would moonwalk; turn it 180 (visual_yaw_deg)"
				"in_place": return "its walk is in place (no root travel), so the facing cannot be read from it: look, the arrow on the floor is the game's forward, and the character must face it"
			return "no walk clip, or no model, to read the facing from"
		&"looks":
			var n: int = maxi(d.visual_variants.size(), 1)
			var names_worn: Array[String] = []
			for i: int in n:
				m.look = i
				names_worn.append(m.model.name if m.model != null else "?")
				await get_tree().create_timer(seconds_each).timeout
			m.look = 0
			return "%d look(s): %s" % [n, ", ".join(names_worn)]
	return "no such test"


func fit_checks() -> Array[String]:
	var d: EntityDefinition = item as EntityDefinition
	var out: Array[String] = []
	if d == null or _mannequin().model == null:
		return out
	var box: AABB = model_bounds(_mannequin().model)
	if box.size == Vector3.ZERO:
		return out
	if absf(box.position.y) > FEET_TOLERANCE_M:
		out.append("its feet are %d cm %s the floor: set visual_offset.y to %.2f" % [
			roundi(absf(box.position.y) * 100.0), "below" if box.position.y < 0.0 else "above", d.visual_offset.y - box.position.y])
	var cap: CapsuleShape3D = capsule_of(d)
	if cap != null:
		var ratio: float = box.size.y / cap.height
		if absf(ratio - 1.0) > HEIGHT_TOLERANCE:
			out.append("it is %.2f m tall and its collision capsule %.2f m: what others bump into is not what they see" % [box.size.y, cap.height])
	if last_facing == "backward":
		out.append("its walk travels backward: it would moonwalk (visual_yaw_deg)")
	return out


## FILL FROM A RIGGED MODEL: the model is its look; it plays the reference humanoid's animations
## when its skeleton has the humanoid's bones, else none yet; its entity is the foundation's player.
func fill_from_file(def: ContentDef, path: String) -> String:
	var d: EntityDefinition = def as EntityDefinition
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return "%s is not a model (a .glb, .gltf or a scene)" % path.get_file()
	var probe: Node = scene.instantiate()
	var skel: Skeleton3D = null
	for n: Node in probe.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var humanoid: EntityDefinition = load("res://foundation/content/character/humanoid.tres") as EntityDefinition
	d.visual_scene = scene
	d.scene = load("res://foundation/entities/player.tscn") as PackedScene
	d.camera_rig = humanoid.camera_rig
	d.visual_yaw_deg = 0.0
	if skel != null and humanoid.animation_set != null and _shares_rig(skel, humanoid):
		d.animation_set = humanoid.animation_set
		d.visual_yaw_deg = humanoid.visual_yaw_deg
	probe.free()
	return ""


## Which way the walk clip travels, read from the animation itself (no playback): "forward" (-Z,
## the game's forward, after the definition's yaw), "backward", "in_place", or "unknown".
static func facing(d: EntityDefinition) -> String:
	if d == null or d.animation_set == null:
		return "unknown"
	var ref: AnimationClipRef = d.animation_set.clip(&"locomotion.walk")
	if ref == null:
		return "unknown"
	var anim: Animation = null
	for lib_name: StringName in d.animation_set.libraries:
		var lib: AnimationLibrary = d.animation_set.libraries[lib_name]
		var short: StringName = StringName(String(ref.anim_name).get_slice("/", 1)) if String(ref.anim_name).contains("/") else ref.anim_name
		if lib != null and lib.has_animation(short) and (lib_name == &"" or String(ref.anim_name).begins_with(String(lib_name) + "/")):
			anim = lib.get_animation(short)
	if anim == null:
		return "unknown"
	var best: Vector3 = Vector3.ZERO
	for t: int in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D or anim.track_get_key_count(t) < 2:
			continue
		var travel: Vector3 = anim.position_track_interpolate(t, anim.length * 0.9) - anim.position_track_interpolate(t, 0.0)
		travel.y = 0.0
		if travel.length() > best.length():
			best = travel
	if best.length() < 0.05:
		return "in_place"
	var world: Vector3 = best.rotated(Vector3.UP, deg_to_rad(d.visual_yaw_deg))
	return "forward" if world.dot(Vector3.FORWARD) > 0.0 else "backward"


## The collision capsule the definition's entity scene uses, or null.
static func capsule_of(d: EntityDefinition) -> CapsuleShape3D:
	if d == null or d.scene == null:
		return null
	var root: Node = d.scene.instantiate()
	var out: CapsuleShape3D = null
	for n: Node in root.find_children("*", "CollisionShape3D", true, false):
		if (n as CollisionShape3D).shape is CapsuleShape3D:
			out = ((n as CollisionShape3D).shape as CapsuleShape3D).duplicate() as CapsuleShape3D
			break
	root.free()
	return out


## Every mesh under `model`, as one box in the model's parent's space.
static func model_bounds(model: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	var base: Transform3D = model.get_parent_node_3d().global_transform.affine_inverse() if model.get_parent_node_3d() != null else Transform3D.IDENTITY
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (base * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _shares_rig(skel: Skeleton3D, humanoid: EntityDefinition) -> bool:
	var scene: PackedScene = humanoid.visual_scene if humanoid.visual_scene != null else (humanoid.visual_variants[0] if not humanoid.visual_variants.is_empty() else null)
	if scene == null:
		return false
	var ref: Node = scene.instantiate()
	var ref_skel: Skeleton3D = null
	for n: Node in ref.find_children("*", "Skeleton3D", true, false):
		ref_skel = n as Skeleton3D
		break
	var same: bool = ref_skel != null and ref_skel.get_bone_count() == skel.get_bone_count()
	if same:
		for i: int in skel.get_bone_count():
			if skel.get_bone_name(i) != ref_skel.get_bone_name(i):
				same = false
				break
	ref.free()
	return same


func _mannequin() -> Mannequin:
	return get_node(^"Mannequin") as Mannequin


func _build_props() -> void:
	if _capsule != null:
		return
	_capsule = MeshInstance3D.new()
	_capsule.name = "Capsule"
	_capsule.mesh = CapsuleMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.18)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_capsule.material_override = mat
	_capsule.position.x = 0.9
	add_child(_capsule)
	# The game's forward (-Z): a character must face this arrow, or it walks backward in the game.
	var arrow := MeshInstance3D.new()
	arrow.name = "Forward"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.12
	cone.height = 0.3
	arrow.mesh = cone
	arrow.rotation_degrees.x = -90.0
	arrow.position = Vector3(0, 0.03, -0.75)
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(1.0, 0.85, 0.3)
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow.material_override = amat
	add_child(arrow)
	_label = Label3D.new()
	_label.name = "Info"
	_label.position = Vector3(0, 2.3, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.004
	add_child(_label)
