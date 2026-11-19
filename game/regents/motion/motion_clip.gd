class_name MotionClip extends Resource
## ONE CLIP IN A MOVE (`MotionMove.clips`, Luke 2026-11-17: "rebuild it with the clips"): a human-made clip from the
## game's libraries (Quaternius, CC0: `core/BackFlip`, `extra/Sword_GroundPound_RM`), played over a stretch of the move
## (`at` to `until`, shares of it), a part of the clip (`from_s` to `to_s`) time-warped to fit that stretch, blended in
## and out over the pose under it, on the whole body or a part (`mask`). Its ROOT bone's travel along the ground is
## taken off the pose and given to the body (`root_travel` times it), so the feet and the ground agree; its root's
## height stays in the pose (a jump's own arc). Clips that overlap blend in their order, the later on top.

enum Mask { FULL, UPPER, LEGS }

## The libraries a clip's name may begin with.
const LIBRARIES: Dictionary[String, String] = {
	"core": "res://game/anim/humanoid_core.res",
	"extra": "res://game/anim/humanoid_extra.res",
	"cuts": "res://game/regents/anim/regents_cuts.res",
	# Mixamo's, retargeted onto our skeleton (`game/regents/tools/retarget_mixamo.gd`, 2026-11-18): not in any
	# animation set yet, the lab's clip sheets only.
	"mx_great_sword": "res://game/regents/anim/mixamo_great_sword.res",
	"mx_sword_shield": "res://game/regents/anim/mixamo_sword_shield.res",
	"mx_magic": "res://game/regents/anim/mixamo_magic.res",
	"mx_locomotion": "res://game/regents/anim/mixamo_locomotion.res",
}

## The clip: `<library>/<name>`, as the animation sets name them (`extra/Sword_Dash_RM`).
@export var animation: StringName = &""
## The stretch of the move it plays over (shares of the move).
@export_range(0.0, 1.0, 0.005) var at: float = 0.0
@export_range(0.0, 1.0, 0.005) var until: float = 1.0
## The part of the clip played (s; `to_s` 0 or less: to its end). `to_s` below `from_s` plays it backward; the two
## equal holds that one frame (a pose).
@export_range(0.0, 10.0, 0.01, "suffix:s") var from_s: float = 0.0
@export_range(-1.0, 10.0, 0.01, "suffix:s") var to_s: float = -1.0
## How long it takes to come in over the pose under it, and to go (s).
@export_range(0.0, 2.0, 0.01, "suffix:s") var blend_in_s: float = 0.12
@export_range(0.0, 2.0, 0.01, "suffix:s") var blend_out_s: float = 0.15
## Which bones it moves: all, the spine and up (arms, head), or the legs.
@export var mask: Mask = Mask.FULL
## How much of its root's travel along the ground the body is carried (1: its own; 2: twice as far; 0: none).
@export_range(-5.0, 5.0, 0.05) var root_travel: float = 1.0
## Its root's height (a jump's arc), times this (1: its own; 0: on the ground).
@export_range(0.0, 3.0, 0.05) var root_height: float = 1.0

static var _anims: Dictionary[StringName, Animation] = {}


## The clip itself (null: no such clip).
func clip() -> Animation:
	return find(animation)


static func find(name: StringName) -> Animation:
	if _anims.has(name):
		return _anims[name]
	var parts: PackedStringArray = String(name).split("/", false, 1)
	var a: Animation = null
	if parts.size() == 2 and LIBRARIES.has(parts[0]):
		var lib: AnimationLibrary = load(LIBRARIES[parts[0]]) as AnimationLibrary
		if lib != null and lib.has_animation(parts[1]):
			a = lib.get_animation(parts[1])
	_anims[name] = a
	return a


## Let the clips go (a lab closing).
static func release() -> void:
	_anims.clear()


## The clip's time when the move is `t` s in (of `length` s); clamped to the part played.
func clip_time(t: float, length: float) -> float:
	var a: Animation = clip()
	var end_s: float = to_s
	if a != null:
		end_s = a.length if to_s <= 0.0 else minf(to_s, a.length)
	var start: float = at * length
	var span: float = maxf((until - at) * length, 0.001)
	var k: float = clampf((t - start) / span, 0.0, 1.0)
	return lerpf(from_s, end_s, k)


## How much it shows when the move is `t` s in: 0 outside its stretch, eased in and out at its ends.
func weight(t: float, length: float) -> float:
	var start: float = at * length
	var end: float = until * length
	if t < start or t > end:
		return 0.0
	var w: float = 1.0
	if blend_in_s > 0.0:
		w = minf(w, (t - start) / blend_in_s)
	if blend_out_s > 0.0:
		w = minf(w, (end - t) / blend_out_s)
	w = clampf(w, 0.0, 1.0)
	return w * w * (3.0 - 2.0 * w)
