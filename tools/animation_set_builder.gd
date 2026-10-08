extends SceneTree
## Writes the `AnimationSet` resources that map semantic names onto real clips
## (`docs/ANIMATION_SPEC.md` §3), by fuzzy-matching the animation names in a library.
##
## A library ships 127 clips called things like `Jog_Fwd` and `Death01`; the game asks for
## `locomotion.run` and `react.death`. Doing that mapping by hand for every character is how
## animation systems rot, so it is generated and REVIEWED: the run prints what it matched, what
## it could not, and which fallback will cover the gap. Adjusting a line afterwards is expected
## — unlike `movement_config.tres`, this output is a starting point, not a derived truth.
##
##   godot --headless --path . --script res://tools/animation_set_builder.gd
##
## Rerun it after replacing a library; commit the .tres it writes.

const LIBRARIES: Dictionary[StringName, String] = {
	&"": "res://game/anim/humanoid_core.res",
	&"extra": "res://game/anim/humanoid_extra.res",
}
const OUT_DIR: String = "res://game/anim"

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

## What each locomotion clip is SUPPOSED to travel at in this game: a gait, and whether it is
## the sideways or backwards gear of it. The clip's own authored speed is measured off its
## planted foot, and the difference becomes its `speed_scale` — that is the whole reason a
## character at 5 m/s playing a clip authored for 1 m/s looks like it is skating.
const LOCOMOTION_GEAR: Dictionary[StringName, Array] = {
	&"locomotion.walk": ["walk", "fwd"],
	&"locomotion.walk_back": ["walk", "back"],
	&"locomotion.walk_left": ["walk", "side"],
	&"locomotion.walk_right": ["walk", "side"],
	&"locomotion.run": ["run", "fwd"],
	&"locomotion.run_back": ["run", "back"],
	&"locomotion.run_left": ["run", "side"],
	&"locomotion.run_right": ["run", "side"],
	&"locomotion.sprint": ["sprint", "fwd"],
}
## A model to measure the clips on. Any rig with the same bones gives the same answer.
const MEASURE_MODEL: String = "res://game/characters/mannequin_f.glb"

## Clips whose length has to fit the GAME rather than the animator: a fraction of the time the
## player is actually in the air, computed from `shared/movement_config.json`. Quaternius'
## take-off is 1.33 s against this game's 0.8 s jump, so without this the character is still
## crouching to jump when it lands, and the airborne loop is never reached at all.
const AIRTIME_FRACTION: Dictionary[StringName, float] = {
	&"jump.start": 0.4,
	&"jump.land": 0.6,
}

## The sets to write: file name -> semantic overrides applied on top of the fuzzy match. A genre
## states the handful of clips that make its verbs read as that genre, and inherits the rest.
const VARIANTS: Dictionary[String, Dictionary] = {
	"humanoid": {
		# Putting a held item away on the back and drawing it again (DECISIONS #158): UAL's sword
		# sheathe and draw reach over the right shoulder, played on the upper body.
		&"item.draw": &"Sword_Enter",
		&"item.stow": &"Sword_Exit",
	},
	"fisher": {
		&"item.draw": &"Sword_Enter",
		&"item.stow": &"Sword_Exit",
		# Casting is the fishing genre's interact verb, so it gets the rod animation.
		&"interact": &"extra/Fish_Cast",
		&"ability.0": &"extra/Melee_Hook",
		# THE FIGHT, from UAL2's fishing clips (DECISIONS #144), held as poses by FishingFeedback:
		# waiting with the line out; the HEAVE — Fish_Reel is a brace-and-lift, rod forward to rod
		# upright, scrubbed by how far the rod is loaded; and a lost line.
		&"fishing.wait": &"extra/Fish_Cast_Idle",
		&"fishing.heave": &"extra/Fish_Reel",
		&"fishing.fail": &"extra/Fish_Reel_Failed",
	},
}


func _initialize() -> void:
	await _run()
	quit(1 if _failures > 0 else 0)


var _failures: int = 0


func _run() -> void:
	var libs: Dictionary[StringName, AnimationLibrary] = {}
	var names: Dictionary[StringName, PackedStringArray] = {}
	for key: StringName in LIBRARIES:
		var lib: AnimationLibrary = load(LIBRARIES[key]) as AnimationLibrary
		if lib == null:
			printerr("missing library: %s (run tools/extract_animation_library.gd first)"
				% LIBRARIES[key])
			quit(1)
			return
		libs[key] = lib
		var list: PackedStringArray = PackedStringArray()
		for n: StringName in lib.get_animation_list():
			list.append(String(n))
		names[key] = list
		print("library '%s': %d clips" % [key, list.size()])

	for variant: String in VARIANTS:
		if not await _write(variant, VARIANTS[variant], libs, names):
			_failures += 1


func _write(variant: String, overrides: Dictionary,
		libs: Dictionary[StringName, AnimationLibrary],
		names: Dictionary[StringName, PackedStringArray]) -> bool:
	print("\n== %s ==" % variant)
	var set := AnimationSet.new()
	set.libraries = libs
	set.skeleton_family = &"humanoid"
	var clips: Dictionary[StringName, AnimationClipRef] = {}

	for semantic: StringName in CANDIDATES:
		var chosen: StringName = _match(CANDIDATES[semantic], names)
		if chosen.is_empty():
			print("   %-22s MISSING -> falls back to %s"
				% [semantic, str(AnimationSet.FALLBACKS.get(semantic, ["nothing"]))])
			continue
		var ref: AnimationClipRef = AnimationClipRef.make(chosen, LOOPING.has(semantic))
		var scale: float = _fit_scale(semantic, chosen, libs)
		var why: String = "to fit the jump"
		if LOCOMOTION_GEAR.has(semantic):
			var measured: float = await _authored_speed(libs, chosen, String(LOCOMOTION_GEAR[semantic][1]))
			var wanted: float = _gear_speed(String(LOCOMOTION_GEAR[semantic][0]),
				String(LOCOMOTION_GEAR[semantic][1]))
			if measured > 0.01 and wanted > 0.0:
				scale = snappedf(wanted / measured, 0.01)
				why = "authored %.2f m/s, this game moves at %.2f" % [measured, wanted]
			else:
				printerr("   %-22s %s could not be measured (%.2f m/s); left unscaled"
					% [semantic, chosen, measured])
		if not is_equal_approx(scale, 1.0):
			ref.speed_scale = scale
			print("   %-22s %-16s x%.2f   (%s)" % [semantic, chosen, scale, why])
		else:
			print("   %-22s %s" % [semantic, chosen])
		clips[semantic] = ref

	for semantic: StringName in overrides:
		var wanted: StringName = overrides[semantic]
		if not _exists(wanted, names):
			printerr("   %-22s OVERRIDE %s is not in any library" % [semantic, wanted])
			return false
		clips[semantic] = AnimationClipRef.make(wanted, LOOPING.has(semantic))
		print("   %-22s %s   (genre override)" % [semantic, wanted])

	set.clips = clips
	set.strafe = set.has_directional_clips()
	print("   strafing: %s" % ("yes, the whole ring resolved" if set.strafe
		else "no — a directional clip is missing"))
	var missing: Array[StringName] = set.missing_required()
	if not missing.is_empty():
		printerr("   REQUIRED clips unresolved: %s — the driver will refuse this set" % str(missing))
		return false
	var dangling: Array[StringName] = set.dangling_clips()
	if not dangling.is_empty():
		printerr("   clips naming animations the libraries do not have: %s" % str(dangling))
		return false

	var out: String = "%s/%s.tres" % [OUT_DIR, variant]
	var err: int = ResourceSaver.save(set, out)
	if err != OK:
		printerr("   save failed (%d) -> %s" % [err, out])
		return false
	print("   -> %s" % out)
	return true


## How much to speed a clip up so it fits its share of the airtime. 1.0 when it already does,
## or when the movement config is unavailable.
func _fit_scale(semantic: StringName, chosen: StringName,
		libs: Dictionary[StringName, AnimationLibrary]) -> float:
	if not AIRTIME_FRACTION.has(semantic):
		return 1.0
	var cfg: MovementConfig = MovementConfig.shared()
	if cfg == null or cfg.gravity <= 0.0 or cfg.jump_velocity <= 0.0:
		return 1.0
	var airtime: float = 2.0 * cfg.jump_velocity / cfg.gravity
	var budget: float = airtime * float(AIRTIME_FRACTION[semantic])
	var s: String = String(chosen)
	var slash: int = s.find("/")
	var lib: AnimationLibrary = libs.get(StringName(s.substr(0, slash)) if slash >= 0 else &"", null)
	var clip: StringName = StringName(s.substr(slash + 1)) if slash >= 0 else chosen
	if lib == null or not lib.has_animation(clip) or budget <= 0.0:
		return 1.0
	var length: float = lib.get_animation(clip).length
	return 1.0 if length <= budget else snappedf(length / budget, 0.01)


## What this game moves at in that gear.
func _gear_speed(tier: String, direction: String) -> float:
	var cfg: MovementConfig = MovementConfig.shared()
	if cfg == null:
		return 0.0
	var base: float = cfg.run_speed
	if tier == "walk":
		base = cfg.walk_speed
	elif tier == "sprint":
		base = cfg.sprint_speed
	if direction == "side":
		return base * cfg.strafe_speed_mult
	if direction == "back":
		return base * cfg.back_speed_mult
	return base


## What the CLIP travels at, measured rather than trusted: an in-place cycle drags its planted
## foot backwards at exactly the speed the character is meant to be moving.
func _authored_speed(libs: Dictionary[StringName, AnimationLibrary], clip: StringName,
		direction: String) -> float:
	var scene: PackedScene = load(MEASURE_MODEL) as PackedScene
	if scene == null:
		return 0.0
	var model: Node3D = scene.instantiate() as Node3D
	root.add_child(model)
	var skel: Skeleton3D = _skeleton(model)
	if skel == null:
		model.queue_free()
		return 0.0
	var tree := AnimationTree.new()
	for lib_name: StringName in libs:
		tree.add_animation_library(lib_name, libs[lib_name])
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	tree.tree_root = node
	model.add_child(tree)
	tree.root_node = tree.get_path_to(skel.get_parent())
	tree.active = true
	# One real frame before sampling: a tree that has never processed still reports the rest
	# pose, and the first clip measured came back as a character standing perfectly still.
	await process_frame
	tree.advance(0.0)

	var dt: float = 1.0 / 60.0
	var left: int = skel.find_bone("foot_l")
	var right: int = skel.find_bone("foot_r")
	var prev_l: Vector3 = Vector3.ZERO
	var prev_r: Vector3 = Vector3.ZERO
	var samples: Array[float] = []
	var length: float = _clip_length(libs, clip)
	for i: int in range(int(length / dt)):
		tree.advance(dt)
		var l: Vector3 = skel.get_bone_global_pose(left).origin
		var r: Vector3 = skel.get_bone_global_pose(right).origin
		if i > 0:
			var vl: Vector3 = (l - prev_l) / dt
			var vr: Vector3 = (r - prev_r) / dt
			# Whichever foot is being dragged hardest THE WAY THE CHARACTER CAME FROM is the
			# one on the ground. The sign matters: in a backwards clip the planted foot travels
			# forwards, and taking the magnitude instead measures the swinging foot.
			if direction == "side":
				samples.append(maxf(absf(vl.x), absf(vr.x)))
			elif direction == "back":
				samples.append(maxf(vl.z, vr.z))
			else:
				samples.append(maxf(-vl.z, -vr.z))
		prev_l = l
		prev_r = r
	model.queue_free()
	await process_frame
	if samples.is_empty():
		return 0.0
	samples.sort()
	# The upper quartile: the stance phase, not the swing foot and not the moment of transfer.
	return samples[int(float(samples.size()) * 0.75)]


func _clip_length(libs: Dictionary[StringName, AnimationLibrary], full: StringName) -> float:
	var s: String = String(full)
	var slash: int = s.find("/")
	var lib: AnimationLibrary = libs.get(StringName(s.substr(0, slash)) if slash >= 0 else &"", null)
	var name: StringName = StringName(s.substr(slash + 1) if slash >= 0 else s)
	return lib.get_animation(name).length if lib != null and lib.has_animation(name) else 0.0


func _skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c: Node in n.get_children():
		var f: Skeleton3D = _skeleton(c)
		if f != null:
			return f
	return null


## Exact match first, across libraries in declaration order; then the shortest name containing
## the pattern. Returns the mixer-qualified name (`Idle`, `extra/Fish_Cast`).
func _match(patterns: Array, names: Dictionary[StringName, PackedStringArray]) -> StringName:
	for pattern: String in patterns:
		for lib: StringName in names:
			for n: String in names[lib]:
				if n == pattern:
					return _qualify(lib, n)
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
			return _qualify(best_lib, best)
	return &""


func _exists(qualified: StringName, names: Dictionary[StringName, PackedStringArray]) -> bool:
	var s: String = String(qualified)
	var slash: int = s.find("/")
	var lib: StringName = StringName(s.substr(0, slash)) if slash >= 0 else &""
	var clip: String = s.substr(slash + 1) if slash >= 0 else s
	return names.has(lib) and names[lib].has(clip)


func _qualify(lib: StringName, clip: String) -> StringName:
	return StringName(clip) if lib.is_empty() else StringName("%s/%s" % [lib, clip])
