@tool
class_name CharacterWorkbench extends Workbench
## THE CHARACTER WORKBENCH (DECISIONS #204, reworked by #207): where a character is made first, and
## then everything that hangs off it. The character's own fields are in the Inspector; this bench
## shows it the way the game does (`Mannequin`), inside the capsule its body really is, facing the
## game's forward (the yellow arrow), and the Workbench panel holds:
##
##   look at it        any look; ANY animation (what the game plays, every clip of its set, the
##                     model's own), played, paused, slowed and scrubbed
##   animations        which clip the game plays for each thing it needs (idle, walk, jump...), each
##                     one a choice; "Animation set from the model" makes the character's own set
##                     from a model's clips (a chicken's Idle, Walk, Jump)
##   how it plays      its movement (New movement for it / Open its movement) and its abilities (New
##                     ability for it): made from here, linked to it, opened on their own benches
##   Play as this      the game, played as this character
##   tests             every clip; which way its walk faces; every look
##
## Fit checks (amber): its feet are on the floor; its body (collision_*) fits its model.

## Feet this far off the floor, or a model this much taller or shorter than its body, warns.
const FEET_TOLERANCE_M: float = 0.06
const HEIGHT_TOLERANCE: float = 0.2
## Besides the clips the game cannot do without, the ones shown to choose in the panel.
const ALSO_MAPPED: Array[StringName] = [&"locomotion.sprint", &"react.hit", &"react.death", &"interact"]

## How long each clip plays in `every_clip`, and each look in `looks` (s).
var seconds_each: float = 0.8
## What the panel's animation picker plays (&"": what the game plays standing still).
var preview_clip: StringName = &""

## Its own animation set was changed here and not yet saved.
var _set_dirty: bool = false
## Where the previewed clip was, so a rebuild (an edit) carries on from there.
var _kept_fraction: float = 0.0
var _capsule: MeshInstance3D = null
var _label: Label3D = null
## What the last facing measurement found: "forward", "backward", "in_place", "unknown" (tests).
var last_facing: String = ""


func content_type() -> StringName:
	return &"character"


func test_actions() -> Array[StringName]:
	return [&"every_clip", &"walk_facing", &"looks"]


func test_label(action: StringName) -> String:
	match action:
		&"every_clip": return "Play every clip"
		&"walk_facing": return "Which way it faces"
		&"looks": return "Every look"
	return super(action)


func test_info(action: StringName) -> String:
	match action:
		&"every_clip": return "Plays each animation the game uses for it, and names any the game needs that it lacks"
		&"walk_facing": return "Reads which way its walk travels: a model facing backwards moonwalks in the game"
		&"looks": return "Wears each of its looks in turn"
	return ""


func load_item(def: ContentDef) -> void:
	_build_props()
	var d: EntityDefinition = def as EntityDefinition
	var m: Mannequin = _mannequin()
	m.definition = d
	var cap: CapsuleShape3D = d.body_capsule() if d != null else null
	_capsule.visible = cap != null
	if cap != null:
		var mesh: CapsuleMesh = _capsule.mesh as CapsuleMesh
		mesh.radius = cap.radius
		mesh.height = cap.height
		_capsule.position = Vector3(0.0, cap.height * 0.5, 0.0)
	var cam: Camera3D = get_node_or_null(^"ThumbnailCamera") as Camera3D
	if cam != null:
		var h: float = cap.height if cap != null else 1.8
		cam.look_at_from_position(Vector3(0.5, 0.8, -1.5) * h, Vector3(0.14, 0.53, 0.0) * h)   # a three-quarter front view
	_label.text = "" if d == null else "%s  ·  kind %d  ·  %s  ·  %d look(s)" % [d.display_name, d.kind,
		"no animation set" if d.animation_set == null else "%d clips" % d.animation_set.clips.size(),
		maxi(d.visual_variants.size(), 1 if d.visual_scene != null else 0)]
	# An edit rebuilds the model: the clip being looked at carries on from where it was (paused or
	# scrubbed), so changing a field never loses the frame you were fitting it on.
	if not preview_clip.is_empty():
		if m.preview(preview_clip):
			m.seek_fraction(_kept_fraction)
		else:
			preview_clip = &""


func _process(delta: float) -> void:
	var m: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
	if m != null and not preview_clip.is_empty():
		_kept_fraction = m.preview_fraction()
	super(delta)


# --- the panel ---------------------------------------------------------------------------------

func controls() -> Array[Dictionary]:
	var d: EntityDefinition = item as EntityDefinition
	var out: Array[Dictionary] = []
	if d == null:
		return out
	var m: Mannequin = _mannequin()
	out.append({"kind": "heading", "label": "Look at it", "value": "Any animation, played the way you want to see it"})
	if d.visual_variants.size() > 1:
		var looks: Array = []
		for i: int in d.visual_variants.size():
			looks.append([i, d.variant_names()[i] if i < d.variant_names().size() else str(i)])
		out.append({"name": &"look", "label": "Look", "kind": "choice", "value": m.look, "options": looks})
	var clips: Array = [[&"", "(what the game plays: standing)"]]
	clips.append_array(m.clip_choices())
	out.append({"name": &"animation", "label": "Animation", "kind": "choice", "value": preview_clip, "options": clips,
		"tooltip": "Semantic names are what the game plays for each thing; 'clip:' is any clip of its set; 'model:' the model's own"})
	out.append({"name": &"speed", "label": "Speed", "kind": "number", "value": m.preview_speed, "min": 0.05, "max": 3.0, "step": 0.05})
	out.append({"name": &"paused", "label": "Paused", "kind": "toggle", "value": m.preview_paused})
	out.append({"name": &"position", "label": "Position (0-1)", "kind": "number", "value": m.preview_fraction(), "min": 0.0, "max": 1.0, "step": 0.01,
		"tooltip": "Scrub through the clip (pause first to hold a frame)"})
	var cap: CapsuleShape3D = d.body_capsule()
	out.append({"kind": "heading", "label": "Its body", "value": "The capsule drawn around it: what it collides with. Fit it, then fine-tune here (or in the Inspector)."})
	out.append({"name": &"body_height", "label": "Body height (m)", "kind": "number", "value": cap.height if cap != null else 0.0,
		"min": 0.05, "max": 10.0, "step": 0.01, "tooltip": "collision_height: from its feet to the top of its body"})
	out.append({"name": &"body_radius", "label": "Body radius (m)", "kind": "number", "value": cap.radius if cap != null else 0.0,
		"min": 0.02, "max": 5.0, "step": 0.01, "tooltip": "collision_radius: how wide its body is, from its middle"})
	out.append({"kind": "heading", "label": "Animations the game needs", "value": _set_note(d)})
	if _owns_set(d):
		var options: Array = [[&"", "(none: borrows another)"]]
		for lib: StringName in d.animation_set.libraries:
			if d.animation_set.libraries[lib] == null:
				continue
			for a: StringName in d.animation_set.libraries[lib].get_animation_list():
				if a != &"RESET":
					var q: StringName = ClipMatcher.qualify(lib, String(a))
					options.append([q, String(q)])
		var shown: Array[StringName] = []
		shown.append_array(AnimationSet.REQUIRED)
		shown.append_array(ALSO_MAPPED)
		for semantic: StringName in shown:
			var ref: AnimationClipRef = d.animation_set.clips.get(semantic)
			out.append({"name": StringName("map:" + String(semantic)), "label": String(semantic), "kind": "choice",
				"value": ref.anim_name if ref != null else &"", "options": options,
				"tooltip": "The clip the game plays for %s%s" % [semantic, " (the game cannot do without it)" if AnimationSet.REQUIRED.has(semantic) else ""]})
	out.append({"kind": "heading", "label": "How it plays", "value": _plays_note(d)})
	if not read_only_here():
		# Choose from the pieces there are (the Inspector's New on these fields makes a blank one
		# inside the character instead, which is rarely what is meant).
		var moves: Array = [[null, "(the game's default movement)"]]
		for p: ContentDef in ContentLibrary.items(&"movement"):
			moves.append([p, "%s  (%s)" % [p.display_name, ContentLibrary.owner_of_path(p.resource_path)]])
		out.append({"name": &"movement", "label": "Movement", "kind": "choice", "value": d.movement_profile, "options": moves,
			"tooltip": "The movement profile it moves by: any there is (New movement for it makes another)"})
		var adds: Array = [[null, "(choose one to add)"]]
		for a: ContentDef in ContentLibrary.items(&"ability"):
			if not d.abilities.has(a):
				adds.append([a, "%s  (%s)" % [a.display_name, ContentLibrary.owner_of_path(a.resource_path)]])
		out.append({"name": &"add_ability", "label": "Add ability", "kind": "choice", "value": null, "options": adds,
			"tooltip": "List an ability it can use (New ability for it makes another; remove one in the Inspector)"})
	out.append({"name": &"seconds_each", "label": "Seconds each (tests)", "kind": "number", "value": seconds_each, "min": 0.1, "max": 3.0, "step": 0.1})
	return out


func set_control(n: StringName, value: Variant) -> void:
	var d: EntityDefinition = item as EntityDefinition
	var m: Mannequin = _mannequin()
	match n:
		&"look":
			m.look = int(value)
			if not preview_clip.is_empty():
				m.preview(preview_clip)
		&"animation":
			preview_clip = StringName(value)
			if preview_clip.is_empty():
				m.play(&"locomotion.idle")
			elif not m.preview(preview_clip):
				last_result = "the character has no clip '%s'" % preview_clip
		&"speed":
			m.preview_speed = float(value)
		&"paused":
			m.preview_paused = bool(value)
		&"position":
			m.seek_fraction(float(value))
			_kept_fraction = float(value)
		&"seconds_each":
			seconds_each = float(value)
		&"movement":
			if d != null and not read_only_here():
				d.movement_profile = value as MovementProfileDef
				last_result = "moves by %s (Save keeps it)" % (d.movement_profile.display_name if d.movement_profile != null else "the game's default")
		&"add_ability":
			if d != null and not read_only_here() and value is AbilityDef and not d.abilities.has(value):
				d.abilities.append(value as AbilityDef)
				last_result = "can use %s (Save keeps it)" % (value as AbilityDef).display_name
		&"body_height":
			if d != null and not read_only_here():
				d.collision_height = snappedf(float(value), 0.01)
				_refresh()
		&"body_radius":
			if d != null and not read_only_here():
				d.collision_radius = snappedf(float(value), 0.01)
				_refresh()
		_:
			if String(n).begins_with("map:") and d != null and _owns_set(d):
				var semantic: StringName = StringName(String(n).substr(4))
				if String(value).is_empty():
					d.animation_set.clips.erase(semantic)
				else:
					d.animation_set.clips[semantic] = AnimationClipRef.make(StringName(value), ClipMatcher.LOOPING.has(semantic))
				_set_dirty = true
				m.rebuild()
				last_result = "%s now plays %s (Save keeps it)" % [semantic, value if not String(value).is_empty() else "nothing of its own"]
	panel_changed.emit()


func bench_actions() -> Array[Dictionary]:
	var d: EntityDefinition = item as EntityDefinition
	var out: Array[Dictionary] = []
	if d == null or read_only_here():
		return out
	var scene: PackedScene = _model_scene(d)
	if scene != null and not ClipMatcher.model_clips(scene).is_empty():
		out.append({"name": &"make_set", "label": "Animation set from the model",
			"tooltip": "Make this character's own animation set from its model's clips (each matched by name; change any in the panel)"})
	out.append({"name": &"fit_body", "label": "Fit the body to the model", "tooltip": "Size its body to the CORE of the model: the outermost bits (a beak, head feathers, a tail) are left out. Then fine-tune Body height and Body radius"})
	if d.movement_profile == null:
		out.append({"name": &"new_movement", "label": "New movement for it", "tooltip": "A movement profile for this character (starting as the game's default), linked to it, opened on its bench"})
	else:
		out.append({"name": &"open_movement", "label": "Open its movement", "tooltip": "%s, on the movement bench" % d.movement_profile.display_name})
	out.append({"name": &"new_ability", "label": "New ability for it", "tooltip": "An ability this character can use, linked to it, opened on the ability bench"})
	for i: int in d.abilities.size():
		if d.abilities[i] != null:
			out.append({"name": StringName("open_ability:%d" % i), "label": "Open %s" % d.abilities[i].display_name,
				"tooltip": "%s, on the ability bench" % d.abilities[i].display_name})
	return out


func do_action(action: StringName) -> Dictionary:
	var d: EntityDefinition = item as EntityDefinition
	match action:
		&"make_set":
			return {"edit": d} if make_set_from_model() else {}
		&"fit_body":
			fit_body()
			return {"edit": d}
		&"new_movement":
			var mv: ContentDef = _new_linked(&"movement", "%s movement" % d.display_name)
			if mv != null:
				d.movement_profile = mv as MovementProfileDef
				save()
				return {"open": mv}
			return {}
		&"open_movement":
			return {"open": d.movement_profile}
		&"new_ability":
			var ab: ContentDef = _new_linked(&"ability", "%s ability" % d.display_name)
			if ab != null:
				d.abilities.append(ab as AbilityDef)
				save()
				return {"open": ab}
			return {}
	if String(action).begins_with("open_ability:"):
		var i: int = int(String(action).get_slice(":", 1))
		return {"open": d.abilities[i]} if i < d.abilities.size() and d.abilities[i] != null else {}
	return super(action)


func play_args() -> PackedStringArray:
	if item == null or item.resource_path.is_empty():
		return PackedStringArray()
	return PackedStringArray(["--character=" + item.resource_path])


## Save the character, and its own animation set when its clips were changed here.
func save() -> Error:
	var d: EntityDefinition = item as EntityDefinition
	if d != null and _set_dirty and _owns_set(d):
		ResourceSaver.save(d.animation_set, d.animation_set.resource_path)
		_set_dirty = false
	return super()


## AN ANIMATION SET FROM THE MODEL (DECISIONS #207): the character's own, made from its model's clips
## (`ClipMatcher`), saved beside its owner's (game/<genre>/anim/<character>.tres) and linked. True
## when it was made; `last_result` says what plays what.
func make_set_from_model() -> bool:
	var d: EntityDefinition = item as EntityDefinition
	var scene: PackedScene = _model_scene(d) if d != null else null
	var report: Array[String] = []
	var set: AnimationSet = ClipMatcher.set_from_model(scene, report)
	if set == null:
		last_result = "its model has no clips of its own to make a set from"
		_update_status()
		return false
	var path: String = anim_path_for(d)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err: Error = ResourceSaver.save(set, path)
	if err != OK:
		last_result = "could not save %s: %s" % [path, error_string(err)]
		_update_status()
		return false
	d.animation_set = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as AnimationSet
	save()
	_refresh()
	var missing: Array[StringName] = d.animation_set.missing_required()
	last_result = "made %s: %s%s" % [path.get_file(), "; ".join(report),
		"" if missing.is_empty() else ". STILL MISSING what the game needs: %s" % ", ".join(missing)]
	_update_status()
	return true


## Where a character's own animation set is kept: beside its owner's content, never inside a content
## folder (those hold content only), and apart from the sets a tool generates for many characters
## (game/anim/humanoid.tres): game/<genre>/anim/characters/<file>.tres, or game/anim/characters/ for
## the template's.
static func anim_path_for(d: EntityDefinition) -> String:
	var owner: String = ContentLibrary.owner_of_path(d.resource_path)
	var root: String = ContentLibrary.root_of(owner).get_base_dir() if owner != ContentLibrary.FOUNDATION \
		else (ContentLibrary.root_override.path_join("game") if not ContentLibrary.root_override.is_empty() else "res://game")
	return root.path_join("anim/characters").path_join(d.resource_path.get_file())


## How much of the model's outline the body keeps: the top of the body is where all but the
## highest few percent of the model's points are (a crest, ears), its width where all but the
## outermost fifth are (a beak, a tail, arms held out). Luke: "I don't want its head feathers to be
## part of the collision, or its beak".
const FIT_HEIGHT_PERCENTILE: float = 0.95
const FIT_WIDTH_PERCENTILE: float = 0.8


## FIT THE BODY TO THE MODEL'S CORE: its capsule as tall as the model without its topmost bits, as
## wide as it without its outermost (`body_core`). Fine-tuned after in the panel or the Inspector.
func fit_body() -> void:
	var d: EntityDefinition = item as EntityDefinition
	var m: Mannequin = _mannequin()
	if d == null or m.model == null:
		return
	var core: Vector2 = body_core(m.model)
	if core == Vector2.ZERO:
		return
	d.collision_height = snappedf(core.x, 0.01)
	d.collision_radius = snappedf(clampf(core.y, 0.02, core.x * 0.5), 0.01)
	last_result = "body fitted to the model's core: %.2f m tall, %.2f m radius (the outermost bits left out; fine-tune Body height and Body radius; Save keeps it)" % [d.collision_height, d.collision_radius]
	_refresh()


## The model's core, as (height, radius): measured from its mesh points as it stands on the bench
## (its offset, turn and scale applied), the height from the floor to the `FIT_HEIGHT_PERCENTILE`
## point, the radius from the body's upright axis (where the capsule stands) to the
## `FIT_WIDTH_PERCENTILE` point. Zero when it has no mesh.
static func body_core(model: Node3D) -> Vector2:
	var heights: PackedFloat32Array = PackedFloat32Array()
	var reach: PackedFloat32Array = PackedFloat32Array()
	var base: Transform3D = model.get_parent_node_3d().global_transform.affine_inverse() if model.get_parent_node_3d() != null else Transform3D.IDENTITY
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_bench: Transform3D = base * mi.global_transform
		for s: int in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p: Vector3 = to_bench * v
				heights.append(p.y)
				reach.append(Vector2(p.x, p.z).length())
	if heights.is_empty():
		return Vector2.ZERO
	heights.sort()
	reach.sort()
	var floor_y: float = heights[0]
	var top: float = heights[mini(int(heights.size() * FIT_HEIGHT_PERCENTILE), heights.size() - 1)]
	var wide: float = reach[mini(int(reach.size() * FIT_WIDTH_PERCENTILE), reach.size() - 1)]
	return Vector2(top - floor_y, wide)


## Whether the character's animation set is its own to change here (not the template's in a game,
## not one shared from elsewhere): a file under its owner's anim folder.
func _owns_set(d: EntityDefinition) -> bool:
	if d == null or d.animation_set == null or d.animation_set.resource_path.is_empty():
		return false
	if read_only_here():
		return false
	return d.animation_set.resource_path == anim_path_for(d)


func _set_note(d: EntityDefinition) -> String:
	if d.animation_set == null:
		return "None: this character does not animate. \"Animation set from the model\" makes one from its model's clips."
	var missing: Array[StringName] = d.animation_set.missing_required()
	var gap: String = "" if missing.is_empty() else " MISSING what the game needs: %s." % ", ".join(missing)
	if _owns_set(d):
		return "Its own (%s): choose the clip for each.%s" % [d.animation_set.resource_path, gap]
	return "Shared: %s (change it where it is made; or make this character its own from its model).%s" % [d.animation_set.resource_path, gap]


func _plays_note(d: EntityDefinition) -> String:
	var names := PackedStringArray()
	for a: AbilityDef in d.abilities:
		if a != null:
			names.append(a.display_name)
	return "Movement: %s.  Abilities: %s." % [
		d.movement_profile.display_name if d.movement_profile != null else "the game's default",
		", ".join(names) if not names.is_empty() else "none listed (it may use any)"]


## A new piece of `type` for this character's owner (a genre's, in a game), saved; null when it could not be made.
func _new_linked(type: StringName, display_name: String) -> ContentDef:
	var owner: String = ContentLibrary.owner_of_path(item.resource_path)
	var errors: Array[String] = []
	var path: String = ContentLibrary.create(type, owner, display_name, errors)
	if path.is_empty():
		last_result = "could not make it: %s" % "; ".join(errors)
		_update_status()
		return null
	return load(path) as ContentDef


static func _model_scene(d: EntityDefinition) -> PackedScene:
	if d == null:
		return null
	if d.visual_scene != null:
		return d.visual_scene
	return d.visual_variants[0] if not d.visual_variants.is_empty() else null


# --- tests -------------------------------------------------------------------------------------

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
	var cap: CapsuleShape3D = d.body_capsule()
	if cap != null:
		var core: float = body_core(_mannequin().model).x
		var ratio: float = core / cap.height
		if absf(ratio - 1.0) > HEIGHT_TOLERANCE:
			out.append("it is %.2f m tall (its core) and its body %.2f m: what others bump into is not what they see (Fit the body to the model, or visual_scale)" % [core, cap.height])
	if last_facing == "backward":
		out.append("its walk travels backward: it would moonwalk (visual_yaw_deg)")
	return out


## FILL FROM A RIGGED MODEL: the model is its look; it plays the reference humanoid's animations
## when its skeleton has the humanoid's bones, else its own clips (an animation set made from them);
## its entity is the foundation's player; its body is fitted to the model.
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
	var shared_rig: bool = skel != null and humanoid.animation_set != null and _shares_rig(skel, humanoid)
	if shared_rig:
		d.animation_set = humanoid.animation_set
		d.visual_yaw_deg = humanoid.visual_yaw_deg
	probe.free()
	return ""


## After New From File: a model with clips of its own gets its own set; the body is fitted to it.
func new_from_file(path: String, owner: String = "") -> String:
	var made: String = super(path, owner)
	var d: EntityDefinition = item as EntityDefinition
	if made.is_empty() or d == null:
		return made
	var said: String = last_result
	if d.animation_set == null and not ClipMatcher.model_clips(_model_scene(d)).is_empty():
		make_set_from_model()
		said += "; " + last_result
	fit_body()
	save()
	last_result = said + "; " + last_result
	_update_status()
	return made


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


## The collision capsule the definition's body is (its own size, else its scene's), or null.
static func capsule_of(d: EntityDefinition) -> CapsuleShape3D:
	return d.body_capsule() if d != null else null


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
	# ITS BODY, AROUND IT (DECISIONS #207): the capsule drawn where the body is, over the model, so a
	# body that does not fit the model shows.
	_capsule = MeshInstance3D.new()
	_capsule.name = "Capsule"
	_capsule.mesh = CapsuleMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.8, 1.0, 0.16)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	_capsule.material_override = mat
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
