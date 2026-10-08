class_name AnimationSet extends Resource
## THE CONTRACT BETWEEN A CHARACTER AND THE GAME (`docs/ANIMATION_SPEC.md` §3).
##
## Gameplay never names a clip. It says "this entity is running" or "this entity was hit", and
## this resource says which animation that is for THIS character. Swapping a humanoid for a
## chicken is a different `AnimationSet` on the entity's `EntityDefinition`; no code changes,
## and because animation only ever reads state (hard rule 11) nothing it does can desync.
##
## The semantic names below are the foundation's minimum. A genre adds its own — `ability.3`,
## `emote.wave`, `fish.cast` — and reads them through the same `clip()` call.
##
## LIBRARIES. `libraries` maps the mixer's library name to the library itself. The default one
## is keyed `&""` and its clips are named plainly (`Idle`); a second library keyed `&"extra"`
## contributes `extra/Fish_Cast`. That is Godot's own naming, so a clip ref can be copied
## straight out of the editor's animation list.

# --- semantic names ---------------------------------------------------------------------
const IDLE: StringName = &"locomotion.idle"
const WALK: StringName = &"locomotion.walk"
const RUN: StringName = &"locomotion.run"
const SPRINT: StringName = &"locomotion.sprint"
## Strafing and backpedalling, per gait. A set that has these can keep the character facing the
## camera and move its feet sideways instead of sliding it like a chess piece.
const WALK_BACK: StringName = &"locomotion.walk_back"
const WALK_LEFT: StringName = &"locomotion.walk_left"
const WALK_RIGHT: StringName = &"locomotion.walk_right"
const RUN_BACK: StringName = &"locomotion.run_back"
const RUN_LEFT: StringName = &"locomotion.run_left"
const RUN_RIGHT: StringName = &"locomotion.run_right"
## Every clip a strafing blend needs, beyond the forward gaits.
const DIRECTIONAL: Array[StringName] = [
	WALK_BACK, WALK_LEFT, WALK_RIGHT, RUN_BACK, RUN_LEFT, RUN_RIGHT,
]
const JUMP_START: StringName = &"jump.start"
const JUMP_LOOP: StringName = &"jump.loop"
const JUMP_LAND: StringName = &"jump.land"
const JUMP_LAND_HEAVY: StringName = &"jump.land_heavy"
const HIT: StringName = &"react.hit"
const DEATH: StringName = &"react.death"
const REVIVE: StringName = &"react.revive"
const INTERACT: StringName = &"interact"

## Without these there is no locomotion and no jump, so the driver refuses to build a tree.
const REQUIRED: Array[StringName] = [IDLE, WALK, RUN, JUMP_START, JUMP_LOOP, JUMP_LAND]

## What to play when a semantic name is missing. Checked in order; a genre that ships no death
## animation still gets a working tree rather than a silent T-pose.
const FALLBACKS: Dictionary[StringName, Array] = {
	SPRINT: [RUN],
	WALK_BACK: [WALK],
	WALK_LEFT: [WALK],
	WALK_RIGHT: [WALK],
	RUN_BACK: [RUN],
	RUN_LEFT: [RUN],
	RUN_RIGHT: [RUN],
	JUMP_LAND_HEAVY: [JUMP_LAND],
	JUMP_LOOP: [JUMP_START],
	HIT: [IDLE],
	DEATH: [IDLE],
	REVIVE: [IDLE],
	INTERACT: [IDLE],
	RUN: [WALK],
	WALK: [IDLE],
}

@export var libraries: Dictionary[StringName, AnimationLibrary] = {}
## Use the directional clips: the character keeps facing where the camera looks and side-steps.
## False turns the locomotion blend back into a single forward axis, which is right for a genre
## whose characters turn to face the way they are going. Ignored unless every clip in
## `DIRECTIONAL` resolves exactly — half a strafe set is worse than none.
@export var strafe: bool = false
## Which skeleton these clips are authored for. The driver refuses to drive a model whose
## family does not match, because the failure mode otherwise is a silent T-pose or a folded-up
## character — bone names that half-match are worse than bone names that do not.
@export var skeleton_family: StringName = &"humanoid"
## semantic name -> clip
@export var clips: Dictionary[StringName, AnimationClipRef] = {}
## Bones the UPPER-BODY one-shot plays (drawing or stowing an item while walking, DECISIONS #158).
## Empty: the humanoid's chest, arms and fingers (`AnimationTreeBuilder.upper_body`).
@export var upper_body_filter: Array[StringName] = []


## The clip for a semantic name, following `FALLBACKS` when it is missing. Null only when
## nothing in the chain resolves.
func clip(semantic: StringName) -> AnimationClipRef:
	var direct: AnimationClipRef = clips.get(semantic, null)
	if direct != null and direct.is_valid():
		return direct
	for alt: StringName in FALLBACKS.get(semantic, [] as Array):
		var c: AnimationClipRef = clip(alt)
		if c != null:
			return c
	return null


## True when the set names this clip itself, rather than borrowing a fallback.
func has_exact(semantic: StringName) -> bool:
	var direct: AnimationClipRef = clips.get(semantic, null)
	return direct != null and direct.is_valid()


func anim_name(semantic: StringName) -> StringName:
	var c: AnimationClipRef = clip(semantic)
	return c.anim_name if c != null else &""


## Semantic names from `REQUIRED` that resolve to nothing. Empty means the set can drive a tree.
## Does this set name every clip a strafing blend needs? Independent of whether the game wants
## one — the generator asks this to decide what to put in `strafe`.
func has_directional_clips() -> bool:
	for semantic: StringName in DIRECTIONAL:
		if not has_exact(semantic):
			return false
	return true


## True when this set will drive a strafing blend: the game asked for one and the clips are there.
func can_strafe() -> bool:
	return strafe and has_directional_clips()


func missing_required() -> Array[StringName]:
	var missing: Array[StringName] = []
	for semantic: StringName in REQUIRED:
		if clip(semantic) == null:
			missing.append(semantic)
	return missing


## Every clip this set points at that its libraries do not actually contain. A typo in a clip
## name is otherwise invisible until that state is entered in play.
func dangling_clips() -> Array[StringName]:
	var bad: Array[StringName] = []
	for semantic: StringName in clips:
		var c: AnimationClipRef = clips[semantic]
		if c == null or not c.is_valid():
			continue
		if not _library_has(c.anim_name):
			bad.append(semantic)
	return bad


func _library_has(full_name: StringName) -> bool:
	var s: String = String(full_name)
	var slash: int = s.find("/")
	var lib_name: StringName = StringName(s.substr(0, slash)) if slash >= 0 else &""
	var clip_name: StringName = StringName(s.substr(slash + 1)) if slash >= 0 else full_name
	var lib: AnimationLibrary = libraries.get(lib_name, null)
	return lib != null and lib.has_animation(clip_name)
