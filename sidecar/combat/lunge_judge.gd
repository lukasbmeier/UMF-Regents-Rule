class_name LungeJudge extends RefCounted
## WHAT A SWEEP HITS (DECISIONS #226): a ball of `radius` carried `reach` metres along a heading from
## `height` above the user's feet, stopped by the level's walls, and the first body in its way.
##
##   the walls     a shape cast against the level (`cast_motion`, the space's static geometry on
##                 `mask`). A wall met head on stops it, so a hen through a gap the ball cannot fit
##                 is out of reach, however close; one it GRAZES it slides along, as a lunge does
##                 (Luke, 0.40.1: beside a hay bale and angled a little into it, the ball caught the
##                 corner and stopped 0.1 m out, and a hen right there was missed)
##   the bodies    each target a vertical capsule (its character's own collision shape) where the
##                 referee says it was (rewound); the sweep hits the one its path meets first, if
##                 nothing of the level is between the ball and it (never through a wall: a hen pressed
##                 to the far side of a fence is within a ball's reach of where it stopped, not hit)
##
## The bodies are tested by arithmetic, not by moving physics bodies about: a rewound position is a
## number, and the answer must not depend on when a physics step last ran.
##
## SERVER-ONLY (hard rule 7b).

## The level's layers a sweep is stopped by: what characters collide with (foundation/entities/
## player.tscn: mask 5, the level and its props). Characters themselves are on layer 2, not in it.
const LEVEL_MASK: int = 5
## How far a ball begun touching a wall behind it is set off it before it is cast.
const CONTACT_SLOP_M: float = 0.02


## Forward for a heading (the movement model's: yaw 0 faces -Z).
static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## How far a ball of `radius` gets from `start` along `motion` before a wall (0..1 of it). No space:
## nothing stops it.
static func clear_share(space: PhysicsDirectSpaceState3D, start: Vector3, motion: Vector3, radius: float,
		mask: int = LEVEL_MASK, exclude: Array[RID] = []) -> float:
	return float(_cast(space, start, motion, radius, mask, exclude)[0])


## [safe share, the wall's normal where it stopped (zero: it did not)].
static func _cast(space: PhysicsDirectSpaceState3D, start: Vector3, motion: Vector3, radius: float,
		mask: int, exclude: Array[RID]) -> Array:
	if space == null or motion.length_squared() < 1e-8:
		return [1.0, Vector3.ZERO]
	var ball := SphereShape3D.new()
	ball.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, start)
	q.motion = Vector3.ZERO
	q.collision_mask = mask
	q.exclude = exclude
	q.collide_with_areas = false
	# ITS BACK TO A WALL (Luke's playtest of Fowl Play's step 7): a ball cast from touching a wall it is
	# moving away from was stopped where it stood (a box) or a couple of metres on in the open (a mesh's
	# faces): an egg thrown by a hen backed onto a hay stack went 2.3 m of 9. Off it a hair first.
	var touching: Dictionary = space.get_rest_info(q)
	var n0: Vector3 = touching.get("normal", Vector3.ZERO)
	if n0.dot(motion) > 0.0:
		start += n0 * CONTACT_SLOP_M
		q.transform = Transform3D(Basis.IDENTITY, start)
	q.motion = motion
	var r: PackedFloat32Array = space.cast_motion(q)
	var safe: float = clampf(r[0], 0.0, 1.0) if r.size() >= 1 else 1.0
	if safe >= 1.0:
		return [1.0, Vector3.ZERO]
	# Touching it: where, and which way the wall faces.
	q.transform = Transform3D(Basis.IDENTITY, start + motion * clampf(r[1], 0.0, 1.0))
	q.motion = Vector3.ZERO
	var info: Dictionary = space.get_rest_info(q)
	var n: Vector3 = info.get("normal", Vector3.ZERO)
	return [safe, n]


## THE PATH A LUNGE TAKES: from `start` along `motion`, stopped by walls met head on, sliding along
## ones it grazes (up to three walls). Points, start first.
static func path(space: PhysicsDirectSpaceState3D, start: Vector3, motion: Vector3, radius: float,
		mask: int = LEVEL_MASK, exclude: Array[RID] = []) -> PackedVector3Array:
	var out := PackedVector3Array([start])
	var dir: Vector3 = motion.normalized()
	var pos: Vector3 = start
	var left: Vector3 = motion
	for i: int in 4:
		if left.length() < 0.01:
			break
		var c: Array = _cast(space, pos, left, radius, mask, exclude)
		var share: float = float(c[0])
		pos += left * share
		out.append(pos)
		if share >= 1.0:
			break
		var n: Vector3 = c[1]
		n.y = 0.0
		if n.length_squared() < 1e-6:
			break
		n = n.normalized()
		var rest: Vector3 = left * (1.0 - share)
		rest -= n * rest.dot(n)   # along the wall
		rest.y = 0.0
		# Only what still carries it forward: a wall met head on leaves nothing (a gap's posts, a fence).
		var ahead: float = rest.dot(dir)
		if ahead <= 0.05 * left.length():
			break
		left = rest
	return out


## JUDGE ONE SWEEP. `targets`: [{id, pos (feet), radius, height, center_y}], where each was. Returns
## {hit_id (0: none), reach (how far it got before a wall), along (how far along its path the hit
## was)}.
static func judge(space: PhysicsDirectSpaceState3D, feet: Vector3, yaw: float, reach: float, radius: float,
		height: float, targets: Array, mask: int = LEVEL_MASK, exclude: Array[RID] = []) -> Dictionary:
	var dir: Vector3 = forward(yaw)
	var start: Vector3 = feet + Vector3.UP * height
	var way: PackedVector3Array = path(space, start, dir * reach, radius, mask, exclude)
	var got: float = 0.0
	for i: int in range(1, way.size()):
		got += way[i - 1].distance_to(way[i])
	var best_id: int = 0
	var best_along: float = INF
	for t: Dictionary in targets:
		var p: Vector3 = t["pos"]
		var r: float = float(t.get("radius", 0.4))
		var h: float = float(t.get("height", 1.8))
		var cy: float = float(t.get("center_y", h * 0.5))
		var half: float = maxf(h * 0.5 - r, 0.0)
		var a: Vector3 = p + Vector3.UP * (cy - half)
		var b: Vector3 = p + Vector3.UP * (cy + half)
		var so_far: float = 0.0
		for i: int in range(1, way.size()):
			var c: Array = closest_between(way[i - 1], way[i], a, b)
			var along: float = so_far + way[i - 1].distance_to(c[0] as Vector3)
			so_far += way[i - 1].distance_to(way[i])
			if (c[0] as Vector3).distance_to(c[1] as Vector3) > radius + r:
				continue
			if along < best_along and _in_sight(space, c[0] as Vector3, c[1] as Vector3, mask, exclude):
				best_along = along
				best_id = int(t["id"])
			break
	return {"hit_id": best_id, "reach": got, "along": best_along if best_id != 0 else -1.0}


## Nothing of the level between the ball at `from` and the body at `to`.
static func _in_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, exclude: Array[RID]) -> bool:
	if space == null or from.distance_squared_to(to) < 1e-6:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = false
	q.hit_from_inside = false
	return space.intersect_ray(q).is_empty()


## The closest points between segments p1-q1 and p2-q2: [on the first, on the second].
static func closest_between(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1: Vector3 = q1 - p1
	var d2: Vector3 = q2 - p2
	var r: Vector3 = p1 - p2
	var a: float = d1.dot(d1)
	var e: float = d2.dot(d2)
	var f: float = d2.dot(r)
	var s: float = 0.0
	var t: float = 0.0
	if a <= 1e-9 and e <= 1e-9:
		return [p1, p2]
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c: float = d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b: float = d1.dot(d2)
			var denom: float = a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-9 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]
