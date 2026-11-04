extends SceneTree
## CUTS A CLIP IN TWO, a strike and its recovery (Luke, 2026-11-02: the banner grip's rallying cut looked jumpy). A
## kit's swing holds its fighter for its clip's whole length (`KitDef.lock_ms`), and the client blends back through
## the `_Rec` that follows a strike (`recover.<id>` in the set). Most of the pack's sword clips come as a strike and a
## `_Rec`; some come whole, their recovery inside them (Sword_Light_D, 1.7 s). This writes each clip in `CUTS` as
## `<name>` (its start to `at_s`) and `<name>_Rec` (the rest) into the game's own library,
## `game/regents/anim/regents_cuts.res`, which the adventurer's set names `cuts` (so `cuts/<name>`). The template's
## libraries are never touched. Add a line to CUTS and run it again:
##   godot --headless --path . -s res://game/regents/tools/cut_clips.gd

const SOURCE: String = "res://game/anim/humanoid_extra.res"
const OUT: String = "res://game/regents/anim/regents_cuts.res"
## [the source clip, where the strike ends (s, in the clip), the new clip's name]
const CUTS: Array = [
	# The rallying cut (40023): a wide sweep across the body facing forward; its blow at 0.30 s, the arm out at 0.50.
	["Sword_Light_D", 0.5, "Sword_Light_D_Cut"],
]


func _init() -> void:
	var src: AnimationLibrary = load(SOURCE) as AnimationLibrary
	var out := AnimationLibrary.new()
	for c: Array in CUTS:
		var anim: Animation = src.get_animation(StringName(c[0]))
		if anim == null:
			printerr("cut_clips: %s has no clip %s" % [SOURCE, c[0]])
			quit(1)
			return
		var at: float = float(c[1])
		out.add_animation(StringName(c[2]), _slice(anim, 0.0, at))
		out.add_animation(StringName(String(c[2]) + "_Rec"), _slice(anim, at, anim.length))
		print("cut_clips: %s at %.2f s -> %s (%d ms) and %s_Rec (%d ms)" % [c[0], at, c[2], roundi(at * 1000.0), c[2], roundi((anim.length - at) * 1000.0)])
	var err: Error = ResourceSaver.save(out, OUT)
	if err != OK:
		printerr("cut_clips: could not save %s (%d)" % [OUT, err])
		quit(1)
		return
	print("cut_clips: wrote %s" % OUT)
	quit()


## `anim` from `from` to `to` (s), starting at 0: every key inside, and the pose at both ends.
static func _slice(anim: Animation, from: float, to: float) -> Animation:
	var a := Animation.new()
	a.length = to - from
	a.loop_mode = Animation.LOOP_NONE
	for tr: int in anim.get_track_count():
		var type: Animation.TrackType = anim.track_get_type(tr)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var n: int = a.add_track(type)
		a.track_set_path(n, anim.track_get_path(tr))
		a.track_set_interpolation_type(n, anim.track_get_interpolation_type(tr))
		a.track_insert_key(n, 0.0, _at(anim, tr, from))
		for k: int in anim.track_get_key_count(tr):
			var t: float = anim.track_get_key_time(tr, k)
			if t > from + 0.0005 and t < to - 0.0005:
				a.track_insert_key(n, t - from, anim.track_get_key_value(tr, k))
		a.track_insert_key(n, to - from, _at(anim, tr, to))
	return a


static func _at(anim: Animation, tr: int, t: float) -> Variant:
	match anim.track_get_type(tr):
		Animation.TYPE_ROTATION_3D:
			return anim.rotation_track_interpolate(tr, t)
		Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(tr, t)
	return anim.scale_track_interpolate(tr, t)
