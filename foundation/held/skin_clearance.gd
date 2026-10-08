@tool
class_name SkinClearance
## ARMS AGAINST THE BODY, measured off the character's own SKIN (DECISIONS #163). Luke: "all
## animations should go through clipping checks to see if arms clip in the body". The bone
## capsules of `BodyClearance` are round and centred on the spine: a forearm across the belly of
## a corseted waist read 2.3 cm clear while it went through it. So this poses the character's
## meshes on the CPU, as the renderer would, and asks how deep any BODY skin lies inside an ARM:
## each arm piece is a capsule round its bone, as thick as its own sleeve (measured off its own
## vertices). Skin of the body inside it is two surfaces through each other.
##
##   var skin: Dictionary = SkinClearance.gather(skeleton)      # once per character
##   var hit: Dictionary = SkinClearance.arms_into_body(skeleton, skin)   # per pose
##   hit["depth"] (metres, 0 = clear), hit["arm"], hit["part"]
##
## A TOOL script with static functions over engine types, so a preview may call it too.

## The arm pieces: [name, from bone, to bone, share of the way along where it starts]. The upper
## arm starts part way down: at the shoulder it is meant to meet the body.
const ARMS: Array[Array] = [
	["left upper arm", &"upperarm_l", &"lowerarm_l", 0.45],
	["left forearm", &"lowerarm_l", &"hand_l", 0.0],
	["left hand", &"hand_l", &"middle_01_l", 0.0],
	["right upper arm", &"upperarm_r", &"lowerarm_r", 0.45],
	["right forearm", &"lowerarm_r", &"hand_r", 0.0],
	["right hand", &"hand_r", &"middle_01_r", 0.0],
]
## The body an arm must stay out of, by the bone its skin follows most, and the part's name.
const BODY: Dictionary[StringName, String] = {
	&"pelvis": "hips", &"spine_01": "belly", &"spine_02": "waist", &"spine_03": "chest",
	&"neck_01": "neck", &"Head": "head", &"thigh_l": "left thigh", &"thigh_r": "right thigh",
}
## Every Nth body vertex is kept: the skin is dense, and a few millimetres apart is plenty.
const EVERY: int = 2


## Read the skin of every mesh posed by `skeleton`: the body's points (by the bone they follow
## most, `BODY`) and each arm piece's radius (the median distance of its own vertices from its
## bone, at rest). Returns {"pos": PackedVector3Array (mesh space), "ref": PackedInt32Array and
## "weights": PackedFloat32Array (4 per point, into "binds"), "binds": Array[Transform3D] and
## "bind_bone": PackedInt32Array (each bind and the skeleton bone it follows), "part":
## PackedStringArray, "radius": Dictionary[String, float]}.
static func gather(skeleton: Skeleton3D) -> Dictionary:
	var pos := PackedVector3Array()
	var ref := PackedInt32Array()
	var weights := PackedFloat32Array()
	var binds: Array[Transform3D] = []
	var bind_bone := PackedInt32Array()
	var parts := PackedStringArray()
	var arm_dist: Dictionary[String, PackedFloat32Array] = {}
	var arm_of: Dictionary[int, int] = {}   # skeleton bone -> ARMS index
	for k: int in range(ARMS.size()):
		arm_dist[String(ARMS[k][0])] = PackedFloat32Array()
		arm_of[skeleton.find_bone(String(ARMS[k][1]))] = k
	var body_of: Dictionary[int, String] = {}
	for b: StringName in BODY:
		var i: int = skeleton.find_bone(String(b))
		if i >= 0:
			body_of[i] = BODY[b]
	var kept: int = 0
	for mi: MeshInstance3D in _meshes(skeleton):
		if mi.mesh == null or mi.skin == null or not mi.is_visible_in_tree():
			continue
		# This mesh's binds, appended to the shared list.
		var first: int = binds.size()
		for k: int in range(mi.skin.get_bind_count()):
			binds.append(mi.skin.get_bind_pose(k))
			var n: StringName = mi.skin.get_bind_name(k)
			bind_bone.append(skeleton.find_bone(String(n)) if not String(n).is_empty() else mi.skin.get_bind_bone(k))
		for s: int in range(mi.mesh.get_surface_count()):
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null or v.is_empty():
				continue
			var vb := PackedInt32Array(arrays[Mesh.ARRAY_BONES])
			var vw := PackedFloat32Array(arrays[Mesh.ARRAY_WEIGHTS])
			var per: int = vb.size() / v.size()
			for i: int in range(v.size()):
				var best: int = -1
				var best_w: float = -1.0
				for j: int in range(per):
					if vw[i * per + j] > best_w:
						best_w = vw[i * per + j]
						best = vb[i * per + j]
				if best < 0 or best >= mi.skin.get_bind_count():
					continue
				var bone: int = bind_bone[first + best]
				if arm_of.has(bone):
					# At rest the skeleton holds every bone at its rest: where this vertex is drawn then.
					# Only along the stretch that is measured: a shoulder's cap is bulkier than an elbow.
					var arm: Array = ARMS[arm_of[bone]]
					var rest: Vector3 = skeleton.get_bone_global_rest(bone) * binds[first + best] * v[i]
					var a: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(String(arm[1]))).origin
					var z: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(String(arm[2]))).origin
					var t: float = (rest - a).dot(z - a) / maxf((z - a).length_squared(), 1e-6)
					if t >= float(arm[3]) and t <= 1.0:
						arm_dist[String(arm[0])].append(BodyClearance.to_segment(rest, a, z))
					continue
				if not body_of.has(bone):
					continue
				kept += 1
				if kept % EVERY != 0:
					continue
				pos.append(v[i])
				parts.append(body_of[bone])
				for j: int in range(4):
					var ok: bool = j < per and vb[i * per + j] < mi.skin.get_bind_count()
					ref.append(first + vb[i * per + j] if ok else first)
					weights.append(vw[i * per + j] if ok else 0.0)
	var radius: Dictionary[String, float] = {}
	for name: String in arm_dist:
		var d: Array = Array(arm_dist[name])
		d.sort()
		radius[name] = float(d[d.size() / 2]) if not d.is_empty() else 0.04
	return {"pos": pos, "ref": ref, "weights": weights, "binds": binds, "bind_bone": bind_bone,
		"part": parts, "radius": radius}


## The body's skin points as `skeleton` is posed now (world space), from `gather`: each bind
## combined with its bone's pose once, then every point blended by its weights.
static func posed(skeleton: Skeleton3D, skin: Dictionary) -> PackedVector3Array:
	var pos: PackedVector3Array = skin["pos"]
	var ref: PackedInt32Array = skin["ref"]
	var weights: PackedFloat32Array = skin["weights"]
	var binds: Array[Transform3D] = skin["binds"]
	var bind_bone: PackedInt32Array = skin["bind_bone"]
	var to_world: Transform3D = skeleton.global_transform
	var combined: Array[Transform3D] = []
	combined.resize(binds.size())
	for k: int in range(binds.size()):
		var b: int = bind_bone[k]
		combined[k] = to_world * (skeleton.get_bone_global_pose(b) if b >= 0 else Transform3D()) * binds[k]
	var out := PackedVector3Array()
	out.resize(pos.size())
	for i: int in range(pos.size()):
		var p := Vector3.ZERO
		var total: float = 0.0
		for j: int in range(4):
			var w: float = weights[i * 4 + j]
			if w > 0.0:
				p += (combined[ref[i * 4 + j]] * pos[i]) * w
				total += w
		out[i] = p / total if total > 0.0 else pos[i]
	return out


## THE WORST ARM IN THE BODY as posed now: how deep the body's skin lies inside the deepest arm
## piece (metres; 0: none), which piece and which part of the body, and each piece's own deepest:
## {"depth", "arm", "part", "pieces": Dictionary[String, float]}.
static func arms_into_body(skeleton: Skeleton3D, skin: Dictionary) -> Dictionary:
	var pts: PackedVector3Array = posed(skeleton, skin)
	var parts: PackedStringArray = skin["part"]
	var radius: Dictionary = skin["radius"]
	var worst: Dictionary = {"depth": 0.0, "arm": "", "part": ""}
	var pieces: Dictionary[String, float] = {}
	for arm: Array in ARMS:
		pieces[String(arm[0])] = 0.0
		var a0: Vector3 = BodyClearance.bone_at(skeleton, arm[1])
		var z: Vector3 = BodyClearance.bone_at(skeleton, arm[2])
		if a0 == Vector3.INF or z == Vector3.INF:
			continue
		var a: Vector3 = a0.lerp(z, float(arm[3]))
		var r: float = float(radius.get(String(arm[0]), 0.04))
		var lo := Vector3(minf(a.x, z.x), minf(a.y, z.y), minf(a.z, z.z)) - Vector3.ONE * r
		var hi := Vector3(maxf(a.x, z.x), maxf(a.y, z.y), maxf(a.z, z.z)) + Vector3.ONE * r
		for i: int in range(pts.size()):
			var p: Vector3 = pts[i]
			if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
				continue
			var depth: float = r - BodyClearance.to_segment(p, a, z)
			if depth > pieces[String(arm[0])]:
				pieces[String(arm[0])] = depth
			if depth > float(worst["depth"]):
				worst = {"depth": depth, "arm": String(arm[0]), "part": parts[i]}
	worst["pieces"] = pieces
	return worst


static func _meshes(skeleton: Skeleton3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c: Node in skeleton.find_children("*", "MeshInstance3D", true, false):
		out.append(c as MeshInstance3D)
	return out
