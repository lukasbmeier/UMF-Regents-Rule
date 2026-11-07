class_name WorkSpot extends RefCounted
## THE WORK SPOT (Luke, 2026-11-06, PROGRESS step 44: "Move the player"). Walking up to a rock or a tree stops the
## body at its capsule against the node's collider, but the swing reaches about a meter in front of the feet (the
## pick ~1.25 m, the axe ~1.07 m), and a big tree's drawn trunk is wider than the trunk that blocks the way: the tool
## went into the rock or the bark; and worked from farther off (the server allows 3 m from the node's middle), the
## tool swung at the air. So before working a node, the player steps back, or in, until the swing's reach meets the
## node's DRAWN surface (`NodeComponent.surface_along`), facing it; then the work starts there (AFK work stops when the
## player moves `regents.afk_stop_moving_m`, so the step comes first). The step is walked by `force_move`: frames as
## the player's own, bounded by the server as any are. Never farther than the server lets a node be worked from.
##
## Designers: each skill's swing is `SkillingComponent.swing_front` (by the skill's pose, on the adventurer's Skilling
## node): how far the tool reaches in front of the feet at each height, as `game/regents/tests/work_spot_shot.tscn`
## prints it (FRONT) from the world's clip and tool; the gap left is `work_spot_clearance_m`.

## How far behind the feet the looking starts (a body can stand inside a big trunk's drawn bark, ~0.35 m).
const BEHIND_M: float = 0.6
## The most a player is stepped back, or in.
const MOST_M: float = 1.5
const MOST_IN_M: float = 2.0
## Kept inside the server's reach (`regents.work_reach_m`, from the node's edge: its footprint) by this much.
const REACH_MARGIN_M: float = 0.3


## How far to step BACK from `node` (along -`fwd`, flat) from the feet at `at` (negative: step IN, toward it), for a
## swing whose FRONT is `front` ((height above the feet, reach in front of them) points), so the swing's farthest
## point stops `clearance` short of the node's drawn surface. 0 when the node is not ahead (its middle behind the
## feet, or its surface not met within the reach and `MOST_IN_M`). Never so far back that the feet end farther than
## `max_from_center` from the node's middle.
static func step_back(node: NodeComponent, at: Vector3, fwd: Vector3, front: PackedVector2Array, clearance: float,
		max_from_center: float) -> float:
	if node == null:
		return 0.0
	var holder: Node3D = node.entity as Node3D
	if holder == null or not holder.is_inside_tree():
		return 0.0
	var f: Vector3 = Vector3(fwd.x, 0.0, fwd.z)
	if f.length_squared() < 0.0001:
		return 0.0
	f = f.normalized()
	var c: Vector3 = holder.global_position
	if Vector3(c.x - at.x, 0.0, c.z - at.z).dot(f) <= 0.0:
		return 0.0   # its middle is behind: not the node in front
	var need: float = -INF
	for p: Vector2 in front:
		var from: Vector3 = at + Vector3.UP * p.x - f * BEHIND_M
		var d: float = node.surface_along(from, f, BEHIND_M + p.y + clearance + MOST_IN_M)
		if d < INF:
			need = maxf(need, p.y + clearance - (d - BEHIND_M))
	if need == -INF:
		return 0.0
	if need < 0.0:
		return maxf(need, -MOST_IN_M)
	need = minf(need, MOST_M)
	# Inside the server's reach: the farthest along -f the feet may go and stay within `max_from_center`.
	var rel: Vector2 = Vector2(at.x - c.x, at.z - c.z)
	var back: Vector2 = Vector2(-f.x, -f.z)
	# |rel + back * s| = max: s = -b + sqrt(b^2 - (|rel|^2 - max^2)), b = rel . back.
	var b: float = rel.dot(back)
	var disc: float = b * b - (rel.length_squared() - max_from_center * max_from_center)
	if disc < 0.0:
		return 0.0
	return clampf(minf(need, -b + sqrt(disc)), 0.0, MOST_M)


## The flat forward of a look yaw (the body faces -Z at yaw 0).
static func forward_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))
