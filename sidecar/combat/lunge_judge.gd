class_name LungeJudge extends RefCounted
## WHAT A SWEEP HITS (DECISIONS #226): a ball of `radius` carried `reach` metres along a heading from
## `height` above the user's feet, stopped by the level's walls, and the first body in its way.
##
##   the walls     a shape cast against the level (`cast_motion`, the space's static geometry on
##                 `mask`): a fence stops the sweep, so a hen through a gap the ball cannot fit is out
##                 of reach, however close
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


## Forward for a heading (the movement model's: yaw 0 faces -Z).
static func forward(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## How far a ball of `radius` gets from `start` along `motion` before a wall (0..1 of it). No space:
## nothing stops it.
static func clear_share(space: PhysicsDirectSpaceState3D, start: Vector3, motion: Vector3, radius: float,
		mask: int = LEVEL_MASK, exclude: Array[RID] = []) -> float:
	if space == null or motion.length_squared() < 1e-8:
		return 1.0
	var ball := SphereShape3D.new()
	ball.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = ball
	q.transform = Transform3D(Basis.IDENTITY, start)
	q.motion = motion
	q.collision_mask = mask
	q.exclude = exclude
	q.collide_with_areas = false
	var r: PackedFloat32Array = space.cast_motion(q)
	return clampf(r[0], 0.0, 1.0) if r.size() >= 1 else 1.0


## JUDGE ONE SWEEP. `targets`: [{id, pos (feet), radius, height, center_y}], where each was. Returns
## {hit_id (0: none), reach (how far it got before a wall), along (how far along its path the hit
## was)}.
static func judge(space: PhysicsDirectSpaceState3D, feet: Vector3, yaw: float, reach: float, radius: float,
		height: float, targets: Array, mask: int = LEVEL_MASK, exclude: Array[RID] = []) -> Dictionary:
	var dir: Vector3 = forward(yaw)
	var start: Vector3 = feet + Vector3.UP * height
	var got: float = reach * clear_share(space, start, dir * reach, radius, mask, exclude)
	var end: Vector3 = start + dir * got
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
		var c: Array = closest_between(start, end, a, b)
		if (c[0] as Vector3).distance_to(c[1] as Vector3) > radius + r:
			continue
		var along: float = start.distance_to(c[0] as Vector3)
		if along < best_along and _in_sight(space, c[0] as Vector3, c[1] as Vector3, mask, exclude):
			best_along = along
			best_id = int(t["id"])
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
