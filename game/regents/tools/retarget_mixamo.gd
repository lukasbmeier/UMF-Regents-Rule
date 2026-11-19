extends SceneTree
## MIXAMO ONTO OUR SKELETON (2026-11-18, the first retarget: the bladed-bow question). Mixamo's clips come on its own
## rig (`mixamorig:Hips` ...); ours is the Quaternius 65-bone one (`pelvis`, `spine_01` ...). This turns a folder of
## Mixamo FBX files into one `AnimationLibrary` our characters play, as `extract_animation_library.gd` does for the
## Quaternius libraries.
##
## HOW. Both rigs stand in a T-pose, Y up, facing +Z, with one bone for one bone (`BONES` below), so a pose carries
## across as ROTATIONS IN THE CHARACTER'S SPACE: for every frame, how far each Mixamo bone has turned from its own rest
## (its global rotation times its rest's inverse) turns the matching bone of ours from OUR rest by the same amount,
## then each bone is made local to its parent again. Bone rolls and rest angles may differ between the two rigs: the
## turn is measured in the character's space, so they never enter it. Only the hips move: their path is scaled by the
## two rigs' hip heights (ours is ~0.88 of Mixamo's) around our pelvis's rest.
##
## IN PLACE. Mixamo's packs travel (a walk walks off). The body here is moved by the server, so the hips' drift over
## the clip (start to end, on the ground plane) is taken out; the sway stays. The report prints how far each traveled.
## LOOPS. Idle, walk, run, strafe and sprint clips loop (not a jump, a turn or a "to" transition).
##
## USAGE (the sources stay out of git: Mixamo's terms forbid sharing the raw files; `game/anim/_import/` is ignored)
##   1. each pack's .fbx files into  res://game/anim/_import/mixamo/<pack>/   (folder name = the library's name)
##   2. godot --headless --path . --import
##   3. godot --headless --path . --script res://game/regents/tools/retarget_mixamo.gd [-- <pack> ...]
##      writes res://game/regents/anim/mixamo_<pack>.res and prints each clip: length, keys, travel, how far
##      the hands' gap differs from the source's (scaled), the lowest foot
##   4. delete res://game/anim/_import/mixamo/ when the libraries are right
## The clips are then `mx_<pack>/<clip>` in `MotionClip.LIBRARIES` (the motion lab's clip sheets).
# ASSUMPTION: every Mixamo download used the same kind of rig (a T-pose bind, Y up, +Z forward, metres after the
# import). The probe of 2026-11-18 showed it for the Locomotion Pack and the three packs; the report's hand and foot
# errors would show one that is not.

const IMPORT_DIR: String = "res://game/anim/_import/mixamo"
const OUT_DIR: String = "res://game/regents/anim"
## Our skeleton: the mannequin the Quaternius libraries were made on (every outfit shares its bones and rests).
const TARGET: String = "res://game/characters/mannequin_f.glb"
const SKELETON_NODE: String = "Skeleton3D"
const FPS: float = 30.0
## Keys closer than this to the line through their neighbours are dropped (radians; metres for the hips).
const ROT_EPS: float = 0.0015
const POS_EPS: float = 0.0005

## Mixamo's bone (its prefix taken off) -> ours. The fingers follow in `_bone_map`.
const BONES: Dictionary[String, String] = {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03", "Neck": "neck_01",
	"Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"LeftToe_End": "ball_leaf_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
	"RightToe_End": "ball_leaf_r",
}
const FINGERS: Dictionary[String, String] = {
	"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Pinky": "pinky",
}
const LOOP_WORDS: PackedStringArray = ["idle", "walk", "run", "strafe", "sprint"]
const NO_LOOP_WORDS: PackedStringArray = ["jump", "turn", "to", "landing", "draw", "sheath"]

var _tgt: Skeleton3D
var _tgt_rest_g: Array[Transform3D] = []


func _initialize() -> void:
	var troot: Node = (load(TARGET) as PackedScene).instantiate()
	_tgt = _find(troot, "Skeleton3D") as Skeleton3D
	if _tgt == null:
		printerr("no skeleton in ", TARGET)
		quit(1)
		return
	for b: int in _tgt.get_bone_count():
		_tgt_rest_g.append(_tgt.get_bone_global_rest(b))
	var want: PackedStringArray = PackedStringArray(OS.get_cmdline_user_args())
	var dir: DirAccess = DirAccess.open(IMPORT_DIR)
	if dir == null:
		printerr("no %s: copy the packs there first (see the header)" % IMPORT_DIR)
		quit(1)
		return
	var failures: int = 0
	for pack: String in dir.get_directories():
		if not want.is_empty() and not want.has(pack):
			continue
		if not _pack(pack):
			failures += 1
	troot.free()
	quit(1 if failures > 0 else 0)


func _pack(pack: String) -> bool:
	print("== ", pack)
	var lib := AnimationLibrary.new()
	var files: PackedStringArray = DirAccess.get_files_at(IMPORT_DIR.path_join(pack))
	var ok: bool = true
	for f: String in files:
		if f.get_extension().to_lower() != "fbx":
			continue
		var anim: Animation = _clip(IMPORT_DIR.path_join(pack).path_join(f))
		if anim == null:
			ok = false
			continue
		lib.add_animation(_clip_name(f), anim)
	var out: String = "%s/mixamo_%s.res" % [OUT_DIR, pack]
	var err: int = ResourceSaver.save(lib, out)
	if err != OK:
		printerr("   save failed (%d) -> %s" % [err, out])
		return false
	print("   %d clips -> %s, %.2f MB" % [lib.get_animation_list().size(), out,
		float(FileAccess.get_file_as_bytes(out).size()) / 1048576.0])
	return ok


## `great sword slash (2).fbx` -> `great_sword_slash_2`.
func _clip_name(file: String) -> StringName:
	var s: String = file.get_basename().to_lower()
	var out: String = ""
	for ch: String in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return StringName(out.strip_edges().trim_prefix("_").trim_suffix("_"))


## Mixamo bone -> our bone index for one source skeleton (-1: not ours).
func _bone_map(src: Skeleton3D) -> PackedInt32Array:
	var m: PackedInt32Array = PackedInt32Array()
	m.resize(src.get_bone_count())
	var re := RegEx.create_from_string("^mixamorig\\d*[_:]")
	for b: int in src.get_bone_count():
		var n: String = re.sub(src.get_bone_name(b), "")
		var ours: String = BONES.get(n, "")
		if ours.is_empty():
			for side: String in ["Left", "Right"]:
				for fk: String in FINGERS:
					var head: String = side + "Hand" + fk
					if n.begins_with(head) and n.length() == head.length() + 1:
						var k: int = n.substr(head.length()).to_int()
						var s: String = "_l" if side == "Left" else "_r"
						ours = "%s_0%d%s%s" % [FINGERS[fk], k, "_leaf" if k == 4 else "", s]
		m[b] = _tgt.find_bone(ours) if not ours.is_empty() else -1
	return m


func _clip(path: String) -> Animation:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		printerr("   %s: could not load (did --import run?)" % path)
		return null
	var root: Node = packed.instantiate()
	var src: Skeleton3D = _find(root, "Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = _find(root, "AnimationPlayer") as AnimationPlayer
	if src == null or player == null or player.get_animation_list().is_empty():
		printerr("   %s: no skeleton or no animation" % path)
		root.free()
		return null
	var srcanim: Animation = player.get_animation(player.get_animation_list()[0])
	var map: PackedInt32Array = _bone_map(src)
	var to_src: Dictionary[int, int] = {}
	for b: int in map.size():
		if map[b] >= 0:
			to_src[map[b]] = b
	var hips: int = -1
	for b: int in src.get_bone_count():
		if src.get_bone_parent(b) < 0:
			hips = b
	var pelvis: int = map[hips]
	if pelvis < 0 or to_src.size() < 50:
		printerr("   %s: only %d bones matched (a rig this tool does not know?)" % [path, to_src.size()])
		root.free()
		return null
	# What the nodes above the source skeleton carry (identity for these FBX files; kept honest anyway).
	var above: Transform3D = _above(player, src)

	var src_rest_g: Array[Transform3D] = []
	for b: int in src.get_bone_count():
		src_rest_g.append(above * src.get_bone_global_rest(b))
	var scale: float = _tgt_rest_g[pelvis].origin.y / src_rest_g[hips].origin.y
	var rot_track: PackedInt32Array = PackedInt32Array()
	var pos_track: PackedInt32Array = PackedInt32Array()
	for b: int in src.get_bone_count():
		var p := NodePath("%s:%s" % [_track_node(srcanim, src.get_bone_name(b)), src.get_bone_name(b)])
		rot_track.append(srcanim.find_track(p, Animation.TYPE_ROTATION_3D))
		pos_track.append(srcanim.find_track(p, Animation.TYPE_POSITION_3D))

	var frames: int = maxi(int(round(srcanim.length * FPS)), 1) + 1
	var times: PackedFloat32Array = PackedFloat32Array()
	for i: int in frames:
		times.append(minf(float(i) / FPS, srcanim.length))
	# Per target bone, the local rotation at each frame; the pelvis's position.
	var rots: Array[Array] = []
	for b: int in _tgt.get_bone_count():
		rots.append([])
	var pelvis_pos: Array[Vector3] = []
	var hips_g: Array[Vector3] = []
	var err_max: float = 0.0
	var foot_min: float = INF
	for t: float in times:
		var sg: Array[Transform3D] = _source_globals(src, srcanim, rot_track, pos_track, t, above)
		hips_g.append(sg[hips].origin)
		var tg: Array[Basis] = []
		tg.resize(_tgt.get_bone_count())
		for b: int in _tgt.get_bone_count():
			var parent: int = _tgt.get_bone_parent(b)
			var s: int = to_src.get(b, -1)
			var g: Basis
			if s >= 0:
				var turn: Basis = sg[s].basis.orthonormalized() * src_rest_g[s].basis.orthonormalized().inverse()
				g = turn * _tgt_rest_g[b].basis.orthonormalized()
			elif parent >= 0:
				g = tg[parent] * _tgt.get_bone_rest(b).basis.orthonormalized()
			else:
				g = _tgt_rest_g[b].basis.orthonormalized()
			tg[b] = g
			var local: Basis = (tg[parent].inverse() * g) if parent >= 0 else g
			rots[b].append(local.get_rotation_quaternion())
		var pg: Vector3 = _tgt_rest_g[pelvis].origin + (sg[hips].origin - src_rest_g[hips].origin) * scale
		pelvis_pos.append(pg)
		var e: Vector2 = _end_error(sg, tg, pg, map, to_src, scale, hips, pelvis, src_rest_g)
		err_max = maxf(err_max, e.x)
		foot_min = minf(foot_min, e.y)

	# In place: the drift from the first frame to the last, off the ground plane.
	var drift: Vector3 = hips_g[hips_g.size() - 1] - hips_g[0]
	drift.y = 0.0
	var travel: float = drift.length() * scale
	var out := Animation.new()
	out.length = srcanim.length
	var nm: String = path.get_file().get_basename().to_lower()
	var loops: bool = false
	for w: String in LOOP_WORDS:
		loops = loops or nm.contains(w)
	for w: String in NO_LOOP_WORDS:
		loops = loops and not (" %s " % nm).contains(" %s " % w) and not nm.contains(w + " ")
	out.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
	var root_parent: Transform3D = _tgt_rest_g[_tgt.get_bone_parent(pelvis)] if _tgt.get_bone_parent(pelvis) >= 0 \
		else Transform3D.IDENTITY
	var pos_keys: PackedVector3Array = PackedVector3Array()
	for i: int in frames:
		var f: float = times[i] / maxf(srcanim.length, 0.001)
		pos_keys.append(root_parent.affine_inverse() * (pelvis_pos[i] - drift * scale * f))
	var keys: int = 0
	var pt: int = out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pt, NodePath("%s:%s" % [SKELETON_NODE, _tgt.get_bone_name(pelvis)]))
	for i: int in _reduce_pos(pos_keys):
		out.position_track_insert_key(pt, times[i], pos_keys[i])
		keys += 1
	for b: int in _tgt.get_bone_count():
		if not to_src.has(b):
			continue
		var qs: Array[Quaternion] = []
		for v: Variant in rots[b]:
			var q: Quaternion = v
			if not qs.is_empty() and qs[qs.size() - 1].dot(q) < 0.0:
				q = -q
			qs.append(q)
		var rt: int = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rt, NodePath("%s:%s" % [SKELETON_NODE, _tgt.get_bone_name(b)]))
		for i: int in _reduce_rot(qs):
			out.rotation_track_insert_key(rt, times[i], qs[i])
			keys += 1
	print("   %-42s %5.2f s %5d keys  travel %4.2f m%s  hands gap off %4.1f cm  lowest foot %+5.1f cm"
		% [_clip_name(path.get_file()), srcanim.length, keys, travel, "  loop" if loops else "",
			err_max * 100.0, foot_min * 100.0])
	root.free()
	return out


## The source's bone transforms at `t`, in the character's space.
func _source_globals(src: Skeleton3D, anim: Animation, rot_track: PackedInt32Array, pos_track: PackedInt32Array,
		t: float, above: Transform3D) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(src.get_bone_count())
	for b: int in _order(src):
		var rest: Transform3D = src.get_bone_rest(b)
		var r: Quaternion = rest.basis.get_rotation_quaternion()
		var p: Vector3 = rest.origin
		if rot_track[b] >= 0:
			r = anim.rotation_track_interpolate(rot_track[b], t)
		if pos_track[b] >= 0:
			p = anim.position_track_interpolate(pos_track[b], t)
		var local := Transform3D(Basis(r), p)
		var parent: int = src.get_bone_parent(b)
		g[b] = (g[parent] * local) if parent >= 0 else (above * local)
	return g


## Two measures of a pose. THE HANDS' GAP: how far apart our hands are against the source's (scaled): a two-handed
## grip that opens or closes shows here (the rigs' arms differ in length, so a few cm is the rigs). THE LOWEST FOOT:
## our ankles' lowest height against their rest height (below 0 sinks into the ground).
func _end_error(sg: Array[Transform3D], tg: Array[Basis], pelvis_g: Vector3, map: PackedInt32Array,
		to_src: Dictionary[int, int], scale: float, hips: int, pelvis: int,
		src_rest_g: Array[Transform3D]) -> Vector2:
	# Our bone positions by forward kinematics from the pelvis, rest offsets turned by the new rotations.
	var pos: Dictionary[int, Vector3] = {pelvis: pelvis_g}
	for b: int in _order(_tgt):
		if pos.has(b):
			continue
		var parent: int = _tgt.get_bone_parent(b)
		if parent < 0 or not pos.has(parent):
			continue
		pos[b] = pos[parent] + tg[parent] * _tgt.get_bone_rest(b).origin
	var hl: int = _tgt.find_bone("hand_l")
	var hr: int = _tgt.find_bone("hand_r")
	var ours: float = pos[hl].distance_to(pos[hr])
	var theirs: float = sg[to_src[hl]].origin.distance_to(sg[to_src[hr]].origin) * scale
	var low: float = minf(pos[_tgt.find_bone("foot_l")].y, pos[_tgt.find_bone("foot_r")].y)
	return Vector2(absf(ours - theirs), low - _tgt_rest_g[_tgt.find_bone("foot_l")].origin.y)


func _order(s: Skeleton3D) -> PackedInt32Array:
	var done: Dictionary[int, bool] = {}
	var out: PackedInt32Array = PackedInt32Array()
	for b: int in s.get_bone_count():
		_visit(s, b, done, out)
	return out


func _visit(s: Skeleton3D, b: int, done: Dictionary[int, bool], out: PackedInt32Array) -> void:
	if done.has(b):
		return
	var p: int = s.get_bone_parent(b)
	if p >= 0:
		_visit(s, p, done, out)
	done[b] = true
	out.append(b)


## Which node path the source's bone tracks name (`Skeleton3D`, or the importer's own chain).
func _track_node(anim: Animation, bone: String) -> String:
	for i: int in anim.get_track_count():
		var p: NodePath = anim.track_get_path(i)
		if p.get_concatenated_subnames() == bone:
			return String(p.get_concatenated_names())
	return SKELETON_NODE


func _above(player: AnimationPlayer, skel: Skeleton3D) -> Transform3D:
	var anim_root: Node = player.get_node_or_null(player.root_node)
	if anim_root == null:
		anim_root = player.get_parent()
	var t := Transform3D.IDENTITY
	var n: Node = skel
	var chain: Array[Node3D] = []
	while n != null and n != anim_root:
		var n3: Node3D = n as Node3D
		if n3 != null:
			chain.push_front(n3)
		n = n.get_parent()
	for c: Node3D in chain:
		t = t * c.transform
	return t


## The frames to keep: the first, the last, and each one the line between its kept neighbours misses by more than
## ROT_EPS.
func _reduce_rot(qs: Array[Quaternion]) -> PackedInt32Array:
	var keep: PackedInt32Array = PackedInt32Array([0])
	var k: int = 0
	var j: int = 2
	while j < qs.size():
		var ok: bool = true
		for i: int in range(k + 1, j):
			var w: float = float(i - k) / float(j - k)
			if qs[k].slerp(qs[j], w).angle_to(qs[i]) > ROT_EPS:
				ok = false
				break
		if not ok:
			k = j - 1
			keep.append(k)
		j += 1
	if qs.size() > 1:
		keep.append(qs.size() - 1)
	return keep


func _reduce_pos(ps: PackedVector3Array) -> PackedInt32Array:
	var keep: PackedInt32Array = PackedInt32Array([0])
	var k: int = 0
	var j: int = 2
	while j < ps.size():
		var ok: bool = true
		for i: int in range(k + 1, j):
			var w: float = float(i - k) / float(j - k)
			if ps[k].lerp(ps[j], w).distance_to(ps[i]) > POS_EPS:
				ok = false
				break
		if not ok:
			k = j - 1
			keep.append(k)
		j += 1
	if ps.size() > 1:
		keep.append(ps.size() - 1)
	return keep


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c: Node in n.get_children():
		var f: Node = _find(c, cls)
		if f != null:
			return f
	return null
