class_name ShotLook extends Node3D
## A SHOT IN FLIGHT, SHOWN (Luke, 2026-11-11: "trails for arrow projectile to show where its flying (sometimes hard
## to see the actual arrow) and better magic vfx"): the root of an arrow's or a missile's look (a `BodyDef`'s
## `visual_scene`). It leaves a trail behind it (`RibbonTrail`, in the world, so it stays as the shot flies on),
## sheds sparks if it has any, makes a light named `Light` flicker, and bursts where it ends (`ImpactBurst`).
## Every number is this scene's own: open `arrow_look.tscn`, `bolt_look.tscn` or `fireball_look.tscn`.
##
## Presentation only (hard rule 11): the referee flies the shot and the server says what it hit.

@export_group("Trail")
## How long a stretch of trail shows (0: none), how wide at the shot, its color, and whether it glows.
@export_range(0.0, 2.0, 0.01, "suffix:s") var trail_life_s: float = 0.3
@export_range(0.005, 1.0, 0.005, "suffix:m") var trail_width_m: float = 0.06
@export var trail_color: Color = Color(1.0, 1.0, 1.0, 0.6)
@export var trail_glows: bool = false
@export_group("Sparks")
## Sparks shed a second as it flies (0: none), how long each lives, how big, and how far they scatter.
@export_range(0, 200) var sparks_per_s: int = 0
@export_range(0.05, 2.0, 0.05, "suffix:s") var spark_life_s: float = 0.4
@export_range(0.005, 0.5, 0.005, "suffix:m") var spark_size_m: float = 0.04
@export_range(0.0, 5.0, 0.1, "suffix:m/s") var spark_scatter_mps: float = 0.6
@export var spark_color: Color = Color(1.0, 0.7, 0.3)
@export_group("Light")
## How much a child light named `Light` flickers (0: steady), as a share of its energy.
@export_range(0.0, 1.0, 0.05) var flicker: float = 0.0
@export_group("Where it leaves")
## How long it takes to come from the hand or the bow that loosed it onto its true path (0: it is drawn on its path
## from the start, the middle of its shooter's body). The server starts every shot at the chest; this is the look's.
@export_range(0.0, 1.0, 0.01, "suffix:s") var leave_hand_s: float = 0.12
## A shot first seen farther than this from its shooter's hand is left on its path (it was loosed out of sight).
const LEAVE_HAND_MAX_M: float = 10.0
@export_group("Where it ends")
## The burst where it ends: how wide (0: none) and its color.
@export_range(0.0, 6.0, 0.05, "suffix:m") var burst_size_m: float = 0.0
@export var burst_color: Color = Color(1.0, 0.8, 0.5)
## An EFFECT played where it ends, instead of the burst (a `VfxEffect` scene: the fireball's blast, the bolt's
## flash; PROGRESS 82). On the ground below where it ended (`end_on_ground`: a blast, within `END_GROUND_M`), else
## right there.
@export var end_scene: PackedScene = null
@export var end_on_ground: bool = false
const END_GROUND_M: float = 4.0

var trail: RibbonTrail = null
## How far off its path it is drawn as it leaves (world), shrinking to nothing over `leave_hand_s`; whether the hand
## was looked for yet.
var hand_offset: Vector3 = Vector3.ZERO
var _leave_left: float = 0.0
var _hand_looked: bool = false
var _light: Light3D = null
var _light_energy: float = 0.0
var _age: float = 0.0
## ANOTHER PLAYER'S SHOT IS THE LIGHTER VERSION (PROGRESS 88): its riding effects thinned and their lights out, its own
## sparks halved, its light off (`make_lighter`). Decided once its body's owner is known (`_settle_lighter`); set it
## before it enters the tree to decide it (the lab).
var lighter: bool = false
var _lighter_settled: bool = false
## It is being cleared away, not ending: no effect where it was (`cancel_end`).
var _end_canceled: bool = false
## How long it waits for its body's owner to be known before it stays whole.
const OWNER_WAIT_S: float = 0.5


func _ready() -> void:
	_light = get_node_or_null(^"Light") as Light3D
	_light_energy = _light.light_energy if _light != null else 0.0
	if sparks_per_s > 0:
		add_child(_sparks())
	tree_exiting.connect(_ended)
	_settle_lighter()   # known already (the lab; a body bound before its look): lighter from its first frame


func _process(delta: float) -> void:
	_age += delta
	_settle_lighter()
	_leave_hand(delta)
	# The trail begins a frame in, once the body's entity has been put where the shot is (never a streak from
	# where its node was made).
	if trail == null and trail_life_s > 0.0 and _age > 0.02:
		trail = RibbonTrail.behind(self, trail_life_s, trail_width_m, trail_color, trail_glows)
	if _light != null and flicker > 0.0:
		_light.light_energy = _light_energy * (1.0 + flicker * (sin(_age * 37.0) * 0.6 + sin(_age * 91.0) * 0.4))


## Whether it is another player's (`AbilityVfx.lighter_for` its body's owner), once the owner is known.
func _settle_lighter() -> void:
	if _lighter_settled:
		return
	if lighter:
		_lighter_settled = true
		make_lighter()
		return
	var n: Node = get_parent()
	while n != null and not (n is SpaceTimeEntity):
		n = n.get_parent()
	var body: BodyComponent = (n as SpaceTimeEntity).find_component(BodyComponent) as BodyComponent if n != null else null
	if body == null or body.owner_id == 0:
		_lighter_settled = n == null or _age > OWNER_WAIT_S   # no body (the lab), or no owner by now: whole
		return
	_lighter_settled = true
	if AbilityVfx.lighter_for(EntityRegistry.get_entity(body.owner_id)):
		make_lighter()


## Make it the lighter version: every riding `VfxEffect` (`VfxEffect.make_lighter`: half the particles, no light), its
## own sparks halved and its light off. Once.
func make_lighter() -> void:
	lighter = true
	if has_meta(&"shot_lightened"):
		return
	set_meta(&"shot_lightened", true)
	for c: Node in find_children("*", "", true, false):
		if c is VfxEffect:
			(c as VfxEffect).make_lighter()
	var sparks: CPUParticles3D = get_node_or_null(^"Sparks") as CPUParticles3D
	if sparks != null:
		sparks.amount = maxi(1, ceili(float(sparks.amount) * VfxEffect.LIGHTER_PARTICLES))
	if _light != null:
		_light.visible = false
		_light = null   # (no flicker)


## IT LEAVES THE HAND (Luke, 2026-11-12: shots came from "the middle of where my character is standing"): the first
## frame it is drawn where its shooter's bow hand or casting hand is (`CombatLook.muzzle_point`), and it comes onto
## its true path over `leave_hand_s`. Presentation only: the body the referee flies is where it always was.
func _leave_hand(delta: float) -> void:
	var parent: Node3D = get_parent() as Node3D
	if parent == null:
		return
	if not _hand_looked:
		_hand_looked = true
		var hand: Vector3 = shooter_hand()
		if leave_hand_s > 0.0 and hand != Vector3.INF and hand.distance_to(parent.global_position) <= LEAVE_HAND_MAX_M:
			hand_offset = hand - parent.global_position
			_leave_left = leave_hand_s
	if _leave_left <= 0.0:
		return
	_leave_left = maxf(_leave_left - delta, 0.0)
	var k: float = _leave_left / leave_hand_s
	global_position = parent.global_position + hand_offset * (k * k)


## Where the one who shot this has the hand it left from, or `Vector3.INF`: the body's owner (`BodyComponent`), their
## `CombatLook`.
func shooter_hand() -> Vector3:
	var n: Node = get_parent()
	while n != null and not (n is SpaceTimeEntity):
		n = n.get_parent()
	var body_entity: SpaceTimeEntity = n as SpaceTimeEntity
	var body: BodyComponent = body_entity.find_component(BodyComponent) as BodyComponent if body_entity != null else null
	var shooter: SpaceTimeEntity = EntityRegistry.get_entity(body.owner_id) as SpaceTimeEntity if body != null and body.owner_id != 0 else null
	var look: CombatLook = shooter.find_component(CombatLook) as CombatLook if shooter != null and is_instance_valid(shooter) else null
	return look.muzzle_point() if look != null else Vector3.INF


## It is being cleared away (the VFX lab starting another showcase), not hitting anything: when it goes, it shows no
## end effect.
func cancel_end() -> void:
	_end_canceled = true


## It is gone (it hit, or its time ran out): its effect or a burst where it was.
func _ended() -> void:
	if _age <= 0.05 or _end_canceled or not is_inside_tree():
		return
	if end_scene != null:
		var fx: Node3D = end_scene.instantiate() as Node3D
		if fx != null:
			fx.position = end_point()
			if fx is VfxEffect:
				(fx as VfxEffect).lighter = AbilityVfx.lighter_for_shot(self)   # another player's: the lighter version
			get_tree().root.add_child.call_deferred(fx)
		return
	if burst_size_m > 0.0:
		ImpactBurst.at(get_tree(), global_position, burst_color, burst_size_m)


## Where its end effect plays: on the ground under it (`end_on_ground`, a ray straight down), else where it is.
func end_point() -> Vector3:
	var at: Vector3 = global_position
	if not end_on_ground or not is_inside_tree():
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.2, 0), at - Vector3(0, END_GROUND_M, 0), 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] as Vector3 if not hit.is_empty() else at


## The sparks it sheds: small glowing quads left behind in the world, shrinking as they go out.
func _sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.amount = maxi(roundi(float(sparks_per_s) * spark_life_s), 1)
	p.lifetime = spark_life_s
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0.0, -1.0, 0.0)
	p.initial_velocity_min = spark_scatter_mps * 0.3
	p.initial_velocity_max = spark_scatter_mps
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var quad := QuadMesh.new()
	quad.size = Vector2(spark_size_m, spark_size_m)
	quad.material = ImpactBurst.glow_material(spark_color, true)
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p
