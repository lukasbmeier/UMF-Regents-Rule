extends SceneTree
## THE ANIMALS' ANIMATION SETS, FROM THEIR MODELS' OWN CLIPS (hunting, HERBALISM_HUNTING_PREP.md §7 step 3; as Fowl Play's
## `build_animation_sets.gd` did for its wolf, from the same pack). Each model (Quaternius's CC0 Ultimate Animated
## Animals, glTF, `game/regents/art/animals/`) carries its own skeleton and clips; `ClipMatcher.set_from_model` lifts them
## out, and this names the ones the game asks for (a deer's run is its Gallop, standing still it grazes). Writes, here:
##   deer_clips.res, deer_animation.tres, wolf_clips.res, wolf_animation.tres
## Run again after a model changes (its clips are copies):
##   godot --headless --path . --import
##   godot --headless --path . -s res://game/regents/anim/build_animal_sets.gd
## The sets are content to look over and change by hand after: this only writes them. A new animal (the stag)
## is one more table below and one more `_build` line.

const MODELS: String = "res://game/regents/art/animals/"
const OUT: String = "res://game/regents/anim/"

## semantic -> [clip, loop, speed scale]: what the deer plays.
const DEER: Dictionary = {
	# Standing still it grazes (its head down, chewing): a deer at rest in a meadow.
	&"locomotion.idle": [&"Eating", true, 1.0],
	&"locomotion.walk": [&"Walk", true, 1.0],
	# Fleeing it gallops (its run and its sprint both: an animal has one fast gait).
	&"locomotion.run": [&"Gallop", true, 1.0],
	&"locomotion.sprint": [&"Gallop", true, 1.1],
	&"jump.start": [&"Gallop_Jump", false, 1.0],
	&"jump.loop": [&"Gallop_Jump", false, 1.0],
	&"jump.land": [&"Jump_toIdle", false, 1.6],
	&"react.hit": [&"Idle_HitReact1", false, 1.0],
	&"react.death": [&"Death", false, 1.0],
	&"interact": [&"Eating", true, 1.0],
}
## The bones an upper-body one-shot moves on a deer (the humanoid's chest and arms are not there): its neck and head.
const DEER_UPPER: Array[StringName] = [&"Neck1", &"Neck2", &"Neck3", &"Head"]

## semantic -> [clip, loop, speed scale]: what the wolf plays (`HERBALISM_HUNTING_PREP.md` §7 step 5).
const WOLF: Dictionary = {
	&"locomotion.idle": [&"Idle", true, 1.0],
	&"locomotion.walk": [&"Walk", true, 1.0],
	&"locomotion.run": [&"Gallop", true, 1.0],
	&"locomotion.sprint": [&"Gallop", true, 1.1],
	&"jump.start": [&"Gallop_Jump", false, 1.0],
	&"jump.loop": [&"Gallop_Jump", false, 1.0],
	&"jump.land": [&"Jump_ToIdle", false, 1.6],
	&"react.hit": [&"Idle_HitReact1", false, 1.0],
	&"react.stagger": [&"Idle_HitReact2", false, 0.8],
	&"react.dazed": [&"Idle_2_HeadLow", true, 1.0],
	&"react.death": [&"Death", false, 1.0],
	&"interact": [&"Eating", true, 1.0],
	&"ability.40027": [&"Attack", false, 1.4],
	&"ability.40028": [&"Attack", false, 1.25],
	&"ability.40029": [&"Attack", false, 1.0],
}
const WOLF_UPPER: Array[StringName] = [&"Neck1", &"Neck2", &"Neck3", &"Head"]


func _initialize() -> void:
	var ok: bool = _build("Deer.gltf", "deer", DEER, DEER_UPPER) and _build("Wolf.gltf", "wolf", WOLF, WOLF_UPPER)
	quit(0 if ok else 1)


func _build(model: String, name: String, wanted: Dictionary, upper: Array[StringName]) -> bool:
	var scene: PackedScene = load(MODELS + model) as PackedScene
	if scene == null:
		printerr("no %s (import the project first)" % model)
		return false
	var report: Array[String] = []
	var set: AnimationSet = ClipMatcher.set_from_model(scene, report)
	if set == null or not set.libraries.has(&""):
		printerr("%s has no clips" % model)
		return false
	# The library as its own file, so the set (and a diff of it) is small.
	var lib: AnimationLibrary = set.libraries[&""]
	var lib_path: String = OUT + name + "_clips.res"
	if ResourceSaver.save(lib, lib_path) != OK:
		printerr("could not write " + lib_path)
		return false
	set.libraries = {&"": load(lib_path) as AnimationLibrary}
	var clips: Dictionary[StringName, AnimationClipRef] = {}
	for semantic: StringName in wanted:
		var w: Array = wanted[semantic]
		if not lib.has_animation(w[0]):
			printerr("%s: no clip %s for %s" % [model, w[0], semantic])
			return false
		clips[semantic] = AnimationClipRef.make(w[0], bool(w[1]), 0.15, float(w[2]))
	set.clips = clips
	set.skeleton_family = StringName(name)
	set.strafe = false
	set.upper_body_filter = upper.duplicate()
	var missing: Array[StringName] = set.missing_required()
	var dangling: Array[StringName] = set.dangling_clips()
	if not missing.is_empty() or not dangling.is_empty():
		printerr("%s: the set lacks %s, names clips it has not %s" % [model, str(missing), str(dangling)])
		return false
	var set_path: String = OUT + name + "_animation.tres"
	if ResourceSaver.save(set, set_path) != OK:
		printerr("could not write " + set_path)
		return false
	print("%s: %d clips (%s), the set %s" % [model, lib.get_animation_list().size(), ", ".join(lib.get_animation_list()), set_path])
	for semantic: StringName in clips:
		print("   %s -> %s x%.2f" % [semantic, clips[semantic].anim_name, clips[semantic].speed_scale])
	return true
