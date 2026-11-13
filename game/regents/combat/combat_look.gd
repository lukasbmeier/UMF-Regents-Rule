class_name CombatLook extends SpaceTimeComponent
## COMBAT, SHOWN, on every player's character (presentation only): the weapon they wield is in the hand
## (`ItemDef.held_scene`), except while they work a skill (the tool is then; `SkillingLook`). It reads the
## combat component's `weapon`, from the `wielded` row everyone has.
##
## And THE UPPER BODY TURNS TO WHERE A SHOT GOES (`AimTwist`): the Tab target when there is one in front of you, else
## the crosshair. TO ADJUST where the bow or the casting hand ends up pointing, change the "pose points" numbers
## below on this node in `adventurer.tscn` (Components/CombatLook) and run
## `game/regents/tests/aim_shot.tscn`: it prints how far off the target each pose still points, and saves pictures.

@export_group("Where each aim pose points by itself")
## How far off straight ahead each aim pose points before it is turned, in degrees: x to the LEFT of the way the
## body faces, y ABOVE level. The turn takes exactly this out, so: the bow still points left of the target, raise
## x by what the picture tool says is left; it points right of it, lower x.
@export var bow_pose_points_deg: Vector2 = Vector2(28.7, 1.2)
## The casting pose and the cast itself (the left hand thrown out).
@export var cast_pose_points_deg: Vector2 = Vector2(32.0, 9.1)
## A long cast's pose (both hands out in front).
@export var channel_pose_points_deg: Vector2 = Vector2(-0.9, -2.3)
@export_group("Where a shot is seen to leave")
## The bone an arrow and a spell's missile are seen to leave from (`ShotLook`): the bow hand, the casting hand.
@export var bow_muzzle_bone: StringName = &"hand_l"
@export var cast_muzzle_bone: StringName = &"hand_l"
@export_group("")
## How long after a shot leaves the upper body stays turned to it (its loose or cast clip playing), in ms.
@export var aim_after_shot_ms: int = 350
## How far ahead another player's shot is taken to go (their look's pitch is not sent: level, the way they face).
const REMOTE_AIM_M: float = 30.0
## What `aiming_with` answers.
const AIM_NONE: StringName = &""
const AIM_BOW: StringName = &"bow"
const AIM_CAST: StringName = &"cast"
const AIM_CHANNEL: StringName = &"channel"

var weapon_held: HeldItem = null
var weapon_scene: PackedScene = null
var aim_twist: AimTwist = null
var _combat: CombatComponent = null
var _skilling_look: SkillingLook = null
var _driver: AnimationDriverComponent = null


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_combat = ent.find_component(CombatComponent) as CombatComponent
	_skilling_look = ent.find_component(SkillingLook) as SkillingLook
	_driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent


func _process(_delta: float) -> void:
	if _combat == null or not is_bound():
		return
	var working: bool = _skilling_look != null and _skilling_look.working()
	var want: PackedScene = _combat.weapon.held_scene if _combat.weapon != null and not working else null
	if want != weapon_scene:
		if weapon_held != null:
			weapon_held.queue_free()
			weapon_held = null
		weapon_scene = want
	if weapon_held == null and weapon_scene != null:
		var skel: Skeleton3D = SkillingLook.skeleton_of(entity)
		if skel != null:
			weapon_held = HeldItem.attach(skel, weapon_scene)
			if weapon_held != null:
				weapon_held.driver = _driver
	_aim()


## THE UPPER BODY TURNS TO WHERE THE SHOT GOES (`AimTwist`) while this character draws a bow, casts, or has just
## shot: ours to the Tab target (in front of us) or the crosshair, another player's the way they face.
func _aim() -> void:
	var with: StringName = aiming_with()
	# A character that shoots keeps its turner from the first time on: it also says where a shot leaves (`muzzle`).
	if aim_twist == null or not is_instance_valid(aim_twist):
		if with == AIM_NONE:
			return
		var skel: Skeleton3D = SkillingLook.skeleton_of(entity)
		if skel == null:
			return
		aim_twist = AimTwist.new()
		aim_twist.name = "AimTwist"
		skel.add_child(aim_twist)
		skel.move_child(aim_twist, 0)   # before the held item's wrist and off hand: they follow the turned arm
	if _combat.kit != null:
		aim_twist.muzzle_bone = bow_muzzle_bone if _combat.kit.draws else (cast_muzzle_bone if _combat.kit.casts() else &"")
	if with == AIM_NONE:
		aim_twist.rest()
		return
	aim_twist.aim(aim_point(), body_facing(), pose_points(with))


## What this character is aiming with now: `AIM_BOW`, `AIM_CAST`, `AIM_CHANNEL` (a long cast), or `AIM_NONE`.
func aiming_with() -> StringName:
	if _combat == null or _combat.kit == null:
		return AIM_NONE
	var shooting: bool = false
	var long_cast: bool = false
	if _combat.is_local_authority:
		shooting = _combat.drawing() or _combat.casting() or Time.get_ticks_msec() - _combat.shot_ms < aim_after_shot_ms
		long_cast = _combat.casting() and _combat.cast_spell.cast_ms >= 800
	else:
		shooting = _combat.remote_cast_ability >= 0 or (_combat._status != null and _combat._status.status() == CombatComponent.STATUS_DRAWING)
		var their: SpellDef = SpellDef.by_ability(_combat.remote_cast_ability) if _combat.remote_cast_ability >= 0 else null
		long_cast = their != null and their.cast_ms >= 800
	if not shooting:
		return AIM_NONE
	if _combat.kit.draws:
		return AIM_BOW
	if _combat.kit.casts():
		return AIM_CHANNEL if long_cast else AIM_CAST
	return AIM_NONE


## Where the pose aimed with `with` points by itself (radians: x left of the body's facing, y above level).
func pose_points(with: StringName) -> Vector2:
	var deg: Vector2 = bow_pose_points_deg if with == AIM_BOW else (channel_pose_points_deg if with == AIM_CHANNEL else cast_pose_points_deg)
	return Vector2(deg_to_rad(deg.x), deg_to_rad(deg.y))


## The way the body is DRAWN facing now (world, flat): the model's own turn (it eases round after the body's), the
## body's with no model.
func body_facing() -> Vector3:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var me: Node3D = entity as Node3D
	var model: Node3D = entity.get_node_or_null(^"Visual/Model") as Node3D if entity != null else null
	if model != null and model.is_inside_tree():
		var yaw: float = model.global_rotation.y - (deg_to_rad(ent.definition.visual_yaw_deg) if ent != null and ent.definition != null else 0.0)
		return Vector3(-sin(yaw), 0.0, -cos(yaw))
	var fwd: Vector3 = -me.global_basis.z if me != null and me.is_inside_tree() else Vector3.FORWARD
	return Vector3(fwd.x, 0.0, fwd.z).normalized()


## Where this character's shot goes: ours at the Tab target's middle when we face it (a shot at one we do not face
## is refused: `CombatComponent.target_in_front`), else where the crosshair is; another player's far ahead the way
## their body faces.
func aim_point() -> Vector3:
	var me: Node3D = entity as Node3D
	if _combat.is_local_authority:
		var t: Node3D = EntityRegistry.get_entity(_combat.target_id) as Node3D if _combat.target_id >= 0 else null
		if t != null and is_instance_valid(t) and _combat.target_in_front(_combat.target_id):
			return t.global_position + Vector3(0.0, target_height(_combat.target_id), 0.0)
		return _combat.crosshair_point()
	var fwd: Vector3 = -me.global_basis.z if me != null else Vector3.FORWARD
	return (me.global_position if me != null else Vector3.ZERO) + Vector3(0.0, CombatComponent.MUZZLE_HEIGHT_M, 0.0) + Vector3(fwd.x, 0.0, fwd.z).normalized() * REMOTE_AIM_M


## WHERE A SHOT OF THIS CHARACTER'S IS SEEN TO LEAVE (`ShotLook`): its bow hand or casting hand as last posed, the
## turn in it. `Vector3.INF` when it has not been posed lately (nobody saw it shoot).
func muzzle_point() -> Vector3:
	if aim_twist == null or not is_instance_valid(aim_twist) or aim_twist.muzzle_msec < 0 or Time.get_ticks_msec() - aim_twist.muzzle_msec > 250:
		return Vector3.INF
	return aim_twist.muzzle


## How high on entity `id` a shot the server aims goes: the middle of a foe's body (`FoeDef.aim_height_m`), else a
## man's chest.
static func target_height(id: int) -> float:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
	var h: float = ent.definition.collision_height if ent != null and ent.definition != null else 0.0
	return h * 0.5 if h > 0.0 else FoeDef.DEFAULT_AIM_HEIGHT_M
