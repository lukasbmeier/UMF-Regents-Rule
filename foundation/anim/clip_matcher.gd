@tool
class_name ClipMatcher extends RefCounted
## WHICH OF A MODEL'S CLIPS IS WHICH (ANIMATION_SPEC §3): a library ships clips called `Jog_Fwd`,
## `Death01`, `HitRecieve`; the game asks for `locomotion.run`, `react.death`, `react.hit`. This finds
## the best clip for each semantic name by name, the same way for the humanoid libraries
## (`tools/animation_set_builder.gd`) and for any model a designer brings (the character workbench's
## "Animation set from the model", DECISIONS #207). Its answer is a starting point to review: the
## workbench shows every choice and lets each be changed.

## semantic -> clip names to look for, best first. An exact match always wins; otherwise the
## SHORTEST name containing the pattern does, so `Idle` beats `Idle_LookAround` and a library
## that only has flavoured variants still resolves to something sane.
const CANDIDATES: Dictionary[StringName, Array] = {
	&"locomotion.idle": ["Idle"],
	&"locomotion.walk": ["Walk_Fwd", "Walk"],
	&"locomotion.run": ["Jog_Fwd", "Run_Fwd", "Run", "Jog"],
	&"locomotion.sprint": ["Sprint", "Run_Fast"],
	&"locomotion.walk_back": ["Walk_Bwd", "Walk_Back"],
	&"locomotion.walk_left": ["Walk_L", "Walk_Left"],
	&"locomotion.walk_right": ["Walk_R", "Walk_Right"],
	&"locomotion.run_back": ["Jog_Bwd", "Run_Bwd", "Run_Back"],
	&"locomotion.run_left": ["Jog_Left", "Run_L", "Run_Left"],
	&"locomotion.run_right": ["Jog_Right", "Run_R", "Run_Right"],
	&"jump.start": ["Jump_Start", "Jump"],
	&"jump.loop": ["Jump_Loop", "Jump_Idle", "Jump"],
	&"jump.land": ["Jump_Land", "Land"],
	&"jump.land_heavy": ["Jump_Land_Heavy", "Land_Heavy"],
	&"react.hit": ["Hit_Chest", "HitReact", "Hit"],
	&"react.death": ["Death01", "Death"],
	&"react.revive": ["Revive", "GetUp", "KipUp"],
	&"interact": ["Interact", "PickUp"],
}

## Clips that loop while they are the active state. The rest are one-shots.
const LOOPING: Array[StringName] = [
	&"locomotion.idle", &"locomotion.walk", &"locomotion.run", &"locomotion.sprint",
	&"locomotion.walk_back", &"locomotion.walk_left", &"locomotion.walk_right",
	&"locomotion.run_back", &"locomotion.run_left", &"locomotion.run_right",
	&"jump.loop", &"fishing.wait",
]

## What a set made from a model falls back to for a clip the game NEEDS and the model lacks, so the
## character still animates (the workbench says which, to be chosen properly): a landing is the
## jump's end, else standing.
const STAND_INS: Dictionary[StringName, Array] = {
	&"jump.land": [&"jump.start", &"locomotion.idle"],
	&"jump.start": [&"locomotion.idle"],
	&"jump.loop": [&"jump.start", &"locomotion.idle"],
	&"locomotion.walk": [&"locomotion.idle"],
	&"locomotion.run": [&"locomotion.walk", &"locomotion.idle"],
}


## The best clip for `patterns` among `names` (library -> its clip names), qualified "lib/clip"
## (just "clip" in the unnamed library), or &"" when none matches.
static func match_one(patterns: Array, names: Dictionary) -> StringName:
	for pattern: String in patterns:
		for lib: StringName in names:
			for n: String in names[lib]:
				if n == pattern:
					return qualify(lib, n)
	for pattern: String in patterns:
		var best: String = ""
		var best_lib: StringName = &""
		for lib: StringName in names:
			for n: String in names[lib]:
				if not n.to_lower().contains(pattern.to_lower()):
					continue
				if best.is_empty() or n.length() < best.length():
					best = n
					best_lib = lib
		if not best.is_empty():
			return qualify(best_lib, best)
	return &""


static func qualify(lib: StringName, clip: String) -> StringName:
	return StringName(clip) if lib.is_empty() else StringName("%s/%s" % [lib, clip])


## The AnimationPlayer a model brings (a .glb/.gltf imports with one), or null.
static func model_player(model: Node) -> AnimationPlayer:
	if model == null:
		return null
	for n: Node in model.find_children("*", "AnimationPlayer", true, false):
		return n as AnimationPlayer
	return null


## A copy of `lib`, each track addressed from `skel`'s parent instead of `from` (the model's own
## player's root), its skeleton as `Skeleton3D`. A track to nothing the model has is left as it is.
static func readdressed(lib: AnimationLibrary, from: Node, skel: Skeleton3D) -> AnimationLibrary:
	var out := AnimationLibrary.new()
	for a: StringName in lib.get_animation_list():
		var anim: Animation = lib.get_animation(a).duplicate(true) as Animation
		if skel != null and from != null:
			for t: int in anim.get_track_count():
				var path: NodePath = anim.track_get_path(t)
				var subs: String = path.get_concatenated_subnames()
				var node: Node = from.get_node_or_null(NodePath(path.get_concatenated_names())) if path.get_name_count() > 0 else null
				if node == null:
					continue
				var to: String = "Skeleton3D" if node == skel else String(skel.get_parent().get_path_to(node))
				anim.track_set_path(t, NodePath(to + (":" + subs if not subs.is_empty() else "")))
		out.add_animation(a, anim)
	return out


## A model's own clips: library -> names (the unnamed library is "").
static func model_clips(scene: PackedScene) -> Dictionary:
	var out: Dictionary = {}
	if scene == null:
		return out
	var root: Node = scene.instantiate()
	var player: AnimationPlayer = model_player(root)
	if player != null:
		for lib: StringName in player.get_animation_library_list():
			var names := PackedStringArray()
			for a: StringName in player.get_animation_library(lib).get_animation_list():
				if a != &"RESET":
					names.append(String(a))
			out[lib] = names
	root.free()
	return out


## AN ANIMATION SET FROM A MODEL'S OWN CLIPS: each semantic name matched by name, the clips the game
## needs and the model lacks filled with a stand-in (`STAND_INS`). `report` gets one line per
## semantic name: what it plays, "stand-in" or "none". Null when the model has no clips.
##
## The clips are COPIES, re-addressed the way every player of a set reads them: from the skeleton's
## parent, the skeleton called `Skeleton3D` (as `tools/extract_animation_library.gd` does). A model's
## own clips are addressed from ITS root ("CharacterArmature/Skeleton3D:Head" in a glTF chicken), and
## left so, not one bone moved in the game or on a bench.
static func set_from_model(scene: PackedScene, report: Array[String] = []) -> AnimationSet:
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var player: AnimationPlayer = model_player(root)
	var libs: Dictionary[StringName, AnimationLibrary] = {}
	var names: Dictionary = {}
	if player != null:
		var skel: Skeleton3D = null
		for n: Node in root.find_children("*", "Skeleton3D", true, false):
			skel = n as Skeleton3D
			break
		var from: Node = player.get_node_or_null(player.root_node)
		for lib: StringName in player.get_animation_library_list():
			libs[lib] = readdressed(player.get_animation_library(lib), from if from != null else player.get_parent(), skel)
			var list := PackedStringArray()
			for a: StringName in libs[lib].get_animation_list():
				if a != &"RESET":
					list.append(String(a))
			names[lib] = list
	root.free()
	if libs.is_empty():
		return null
	var set := AnimationSet.new()
	set.libraries = libs
	set.skeleton_family = StringName(scene.resource_path.get_file().get_basename())
	var clips: Dictionary[StringName, AnimationClipRef] = {}
	for semantic: StringName in CANDIDATES:
		var chosen: StringName = match_one(CANDIDATES[semantic], names)
		if not chosen.is_empty():
			clips[semantic] = AnimationClipRef.make(chosen, LOOPING.has(semantic))
			report.append("%s: %s" % [semantic, chosen])
	for semantic: StringName in AnimationSet.REQUIRED:
		if clips.has(semantic):
			continue
		for alt: StringName in STAND_INS.get(semantic, []) as Array:
			if clips.has(alt):
				clips[semantic] = AnimationClipRef.make(clips[alt].anim_name, LOOPING.has(semantic))
				report.append("%s: stand-in %s (the model has none of its own)" % [semantic, clips[alt].anim_name])
				break
	set.clips = clips
	set.strafe = false
	return set
