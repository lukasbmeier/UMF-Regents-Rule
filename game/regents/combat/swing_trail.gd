class_name SwingTrail extends SpaceTimeComponent
## A SWING LEAVES A TRAIL (Luke, 2026-11-11: melee is "mostly visual clarity. trails for weapon swings (enemy and
## yours)"): on every fighter, the sheet its weapon sweeps through the cut, from late in the wind-up to just after
## the hit lands, fading behind it (`RibbonTrail`). A player's is pale; a foe's is warm, so a blow coming at you
## reads as one.
##
## WHERE THE BLADE IS, found from what the fighter shows (no per-weapon setup):
##   - a weapon in the hand (`CombatLook.weapon_held`, a player's): from its hold along its longest side;
##   - a weapon that is part of the model (a skeleton's sword or axe, a skinned mesh by its hand): the same, in the
##     hand bone's frame (`blade_in_bone`);
##   - neither (a wolf): a short upright edge at its `head_bone`, so a bite or a lunge still draws its path.
##
## Presentation only (hard rule 11): it reads when a swing began (the ability event everyone gets) and the pose.

## The trail's color on a player's weapon and on a foe's, and how long a stretch of it shows.
@export var player_color: Color = Color(0.92, 0.96, 1.0, 0.5)
@export var foe_color: Color = Color(1.0, 0.5, 0.22, 0.6)
@export_range(0.05, 1.0, 0.01, "suffix:s") var lifetime_s: float = 0.16
## It starts this far through the wind-up (the cut, not the drawing back) and goes on this long after the hit.
@export_range(0.0, 1.0, 0.05) var from_wind_up: float = 0.55
@export_range(0, 1000, 10, "suffix:ms") var after_hit_ms: int = 130
## How far along the weapon from the hand the sheet begins (the hilt draws nothing).
@export_range(0.0, 0.9, 0.05) var blade_from: float = 0.3
## The hand a weapon that is part of the model is in, and the bone a creature with no weapon bites with.
@export var hand_bone: StringName = &"hand_r"
@export var head_bone: StringName = &"Head"
## A weapon that is part of the model is a skinned mesh at least this long, this near its hand bone at rest.
const MODEL_WEAPON_MIN_M: float = 0.45
const MODEL_WEAPON_NEAR_M: float = 0.3
## Half the height of the edge drawn at a creature's head (m).
const BITE_HALF_M: float = 0.18

var trail: RibbonTrail = null
## The cut is drawn from `_from_ms` to `_until_ms` (msec; -1: none).
var _from_ms: int = -1
var _until_ms: int = -1
var _action: SpaceTimeActionComponent = null
var _look: CombatLook = null
var _skel: Skeleton3D = null
## The blade in the hand bone's frame, [base, tip], looked for once ([]: not yet; [null]: there is none).
var _bone_blade: Array = []
## The held weapon the blade below was worked out for, and the blade in its frame.
var _held_for: Variant = null
var _held_blade: Array = []


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null or SpaceTimeMovementComponent.is_authority_process():
		set_process(false)   # a referee draws nothing
		return
	_action = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	_look = ent.find_component(CombatLook) as CombatLook
	if _action != null:
		_action.action_started.connect(func(id: int, _pid: int) -> void: began(id))
		_action.started_elsewhere.connect(began)
	set_process(true)


## Ability `ability_id` began on this fighter now: a swing the referee judges draws its cut.
func began(ability_id: int) -> void:
	var a: AbilityDef = ContentLibrary.find(&"ability", ability_id) as AbilityDef
	var now: int = Time.get_ticks_msec()
	var window: Vector2i = cut_window(a, now, from_wind_up, after_hit_ms)
	_from_ms = window.x
	_until_ms = window.y


## When swing `a`, begun at `now_ms`, draws its cut: (from, until) in msec, or (-1, -1) for what is no swing (a
## roll, a shot, a spell: nothing the referee sweeps).
static func cut_window(a: AbilityDef, now_ms: int, from_share: float, after_ms: int) -> Vector2i:
	if a == null or not a.judged or a.wind_up_ms <= 0:
		return Vector2i(-1, -1)
	return Vector2i(now_ms + roundi(float(a.wind_up_ms) * clampf(from_share, 0.0, 1.0)), now_ms + a.wind_up_ms + after_ms)


## Whether the cut is being drawn at `now_ms`.
func cutting(now_ms: int) -> bool:
	return _from_ms >= 0 and now_ms >= _from_ms and now_ms <= _until_ms


func _process(_delta: float) -> void:
	if not is_bound() or not cutting(Time.get_ticks_msec()):
		return
	var edge: Array = blade_now()
	if edge.size() != 2:
		return
	if trail == null or not is_instance_valid(trail):
		trail = RibbonTrail.new()
		trail.name = "SwingTrail"
		trail.lifetime_s = lifetime_s
		trail.color = player_color if _look != null else foe_color
		add_child(trail)
	trail.add_blade(edge[0], edge[1])


## Where the blade is now, [base, tip] in the world; [] when the fighter is not drawn.
func blade_now() -> Array:
	var held: Variant = _look.weapon_held if _look != null else null
	if held != null and is_instance_valid(held) and (held as HeldItem).is_inside_tree():
		var item: HeldItem = held as HeldItem
		if not is_same(_held_for, held):
			_held_for = held
			_held_blade = blade_of_item(item, blade_from)
		if _held_blade.size() == 2:
			return [item.global_transform * (_held_blade[0] as Vector3), item.global_transform * (_held_blade[1] as Vector3)]
	if _skel == null or not is_instance_valid(_skel):
		_skel = SkillingLook.skeleton_of(entity)
	if _skel == null or not _skel.is_inside_tree():
		return []
	var hand: int = _skel.find_bone(String(hand_bone))
	if hand >= 0:
		if _bone_blade.is_empty():
			var found: Array = blade_in_bone(_skel, hand, blade_from)
			_bone_blade = found if found.size() == 2 else [null]
		if _bone_blade.size() == 2:
			var bone: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(hand)
			return [bone * (_bone_blade[0] as Vector3), bone * (_bone_blade[1] as Vector3)]
	var head: int = _skel.find_bone(String(head_bone))
	if head < 0:
		return []
	var at: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(head).origin
	return [at - Vector3(0.0, BITE_HALF_M, 0.0), at + Vector3(0.0, BITE_HALF_M, 0.0)]


## A held weapon's blade in its own frame, [base, tip]: from where the fist closes (`Hold`) toward the far end of
## its longest side, the first `from_share` of the way left out. [] for an item with no mesh.
static func blade_of_item(item: HeldItem, from_share: float) -> Array:
	var box: AABB = AABB()
	var any: bool = false
	for n: Node in item.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_item: Transform3D = item.global_transform.affine_inverse() * mi.global_transform if item.is_inside_tree() else _to_ancestor(mi, item)
		var b: AABB = to_item * mi.mesh.get_aabb()
		box = b if not any else box.merge(b)
		any = true
	if not any:
		return []
	return blade_in_box(box, item.hold_offset().origin, from_share)


## A node's transform in the frame of `ancestor` (neither need be in the tree).
static func _to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var t: Transform3D = Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The blade of a weapon filling `box`, held at `grip`: [base, tip] along the box's longest side, the tip its end
## farther from the grip, the base `from_share` of the way from the grip to it.
static func blade_in_box(box: AABB, grip: Vector3, from_share: float) -> Array:
	var axis: int = box.get_longest_axis_index()
	var center: Vector3 = box.get_center()
	var low: Vector3 = center
	var high: Vector3 = center
	low[axis] = box.position[axis]
	high[axis] = box.end[axis]
	var tip: Vector3 = high if absf(high[axis] - grip[axis]) >= absf(low[axis] - grip[axis]) else low
	var hilt: Vector3 = center
	hilt[axis] = grip[axis]
	return [hilt.lerp(tip, clampf(from_share, 0.0, 0.9)), tip]


## THE BLADE OF A WEAPON THAT IS PART OF THE MODEL (a skeleton's sword: a skinned mesh of its own beside its hand),
## in bone `hand`'s frame as [base, tip]; [] when the model has none. The mesh is the skinned one, not the
## largest (the body), at least `MODEL_WEAPON_MIN_M` long and within `MODEL_WEAPON_NEAR_M` of the hand at rest.
static func blade_in_bone(skel: Skeleton3D, hand: int, from_share: float) -> Array:
	var rest: Transform3D = skel.get_bone_global_rest(hand)
	var best: AABB = AABB()
	var found: bool = false
	var largest: float = 0.0
	for n: Node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh != null and mi.skin != null:
			largest = maxf(largest, (mi.transform * mi.mesh.get_aabb()).get_volume())
	for n: Node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or mi.skin == null:
			continue
		var box: AABB = mi.transform * mi.mesh.get_aabb()
		if box.get_volume() >= largest or box.get_longest_axis_size() < MODEL_WEAPON_MIN_M:
			continue
		if not box.grow(MODEL_WEAPON_NEAR_M).has_point(rest.origin):
			continue
		# Of several by the hand (a pauldron reaches near it too), the one centered nearest it.
		if not found or box.get_center().distance_to(rest.origin) < best.get_center().distance_to(rest.origin):
			best = box
			found = true
	if not found:
		return []
	var edge: Array = blade_in_box(best, rest.origin, from_share)
	var to_bone: Transform3D = rest.affine_inverse()
	return [to_bone * (edge[0] as Vector3), to_bone * (edge[1] as Vector3)]
