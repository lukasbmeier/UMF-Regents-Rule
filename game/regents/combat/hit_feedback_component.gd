class_name HitFeedbackComponent extends SpaceTimeComponent
## A HIT, SHOWN (presentation only): every time its entity's health drops, the number floats up from it
## and its look gives a little shake; a heal floats up green. The training dummy has one, and so will
## creatures and players. It reads the health component's signals: it never decides anything.
##
## A HIT FLASHES (owner, 2026-10-21: "enemy flashing when you block/get hit and same for player getting hit"):
## the body lights up for a moment over its own look (`material_overlay` on each mesh): white for what you
## hit, red when it is you; a hit the GUARD stopped (blocking, the attacker in front, not an unblockable
## swing: the server's rule, `CombatComponent.guard_stops`) flashes steel blue and says "Blocked"; a STAGGER
## (a parried swing, or a finisher's) flashes gold, its word left to the target's status bar (Luke, 2026-11-02: the
## bar under its health shows it, and how long); your own PARRY says "Parried".
##
## AN UNBLOCKABLE SWING GLINTS (COMBAT_OVERHAUL.md §2, 2026-10-31: the pose plus one red glint): as its
## user's wind-up starts (its action component hears the use: `started_elsewhere`), a red spark flares at
## its head and its body flashes red. Only for an ability a kit lists `unblockable` (a foe's finisher).
##
## A SPARK WHERE THE BLOW LANDS (Luke's feedback 4098, 2026-10-31: "the hits dont have any weight"): a short
## burst and a slash streak at its chest, facing the attacker: warm on a hit, bigger on a big one, steel blue
## on a block, gold on a stagger (a parry's, a finisher's).
##
## A HIT-STOP (the same feedback; template DECISIONS #301): both sides of a blow stand still for a moment
## (`regents.hitstop_ms`, a big one or a stagger `regents.hitstop_big_ms`), then carry on. Not the local
## player's own swing: it played on this screen before the server's word arrived, and freezing it then would
## stop it a round trip after its blow.
##
## A HIT THAT WAS YOURS picks its entity as your target when you have none (owner, 2026-10-20: "auto
## highlight that enemy"; `CombatComponent.target_what_you_hit`). And while it BURNS (a fireball's: its
## `burning` row), a fire flickers on it.

const RISE_M: float = 1.1
const LIFE_S: float = 0.9
const HIT: Color = Color(1.0, 0.92, 0.55)
const BIG: Color = Color(1.0, 0.55, 0.3)
const HEAL: Color = Color(0.55, 1.0, 0.6)
## The flashes: what you hit, you hit, a block, a stagger.
const FLASH_HIT: Color = Color(1.0, 1.0, 1.0, 0.85)
const FLASH_HURT: Color = Color(1.0, 0.18, 0.12, 0.8)
const FLASH_BLOCK: Color = Color(0.45, 0.72, 1.0, 0.85)
const FLASH_STAGGER: Color = Color(1.0, 0.82, 0.25, 0.85)
const FLASH_S: float = 0.18
## The glint of an unblockable swing: its color, how long it flares, and how high it shows.
const GLINT: Color = Color(1.0, 0.1, 0.05, 0.95)
const GLINT_S: float = 0.35
const GLINT_Y: float = 1.9
## The sparks: their colors, how long a burst lives, how high on the body it shows, and how far towards
## the attacker.
const SPARK_HIT: Color = Color(1.0, 0.75, 0.35, 1.0)
const SPARK_BLOCK: Color = Color(0.55, 0.8, 1.0, 1.0)
const SPARK_STAGGER: Color = Color(1.0, 0.85, 0.25, 1.0)
const SPARK_S: float = 0.22
const SPARK_Y: float = 1.2
const SPARK_TOWARD_M: float = 0.35
## The statuses that change a flash (regents' status content).
const STATUS_BLOCKING: int = 102
const STATUS_STAGGERED: int = 103
## What a stagger plays once as it lands (the set's clip), before its status's held dazed pose shows.
const STAGGER_REACTION: StringName = &"react.stagger"

## A hit this big or more shows larger and redder.
@export var big_hit: float = 20.0
## Every number shown, newest last (tests read it).
var shown: Array[float] = []
var _health: SpaceTimeHealthComponent = null
var _shake_left: float = 0.0
## The fire while it burns, or null.
var fire: Node3D = null
## Every flash shown, newest last, by name: &"hit", &"hurt", &"block", &"stagger", &"glint" (tests read it).
var flashes: Array[StringName] = []
## Every spark shown, newest last: &"hit", &"big", &"block", &"stagger" (tests read it).
var sparks: Array[StringName] = []
## Every hit-stop asked, newest last, in seconds (tests read it).
var hit_stops: Array[float] = []
## When it last glinted (msec): its swing now is unblockable, so a hit from it is never "Blocked".
var glinted_ms: int = -100000
## How long a glint marks its user's swing as unblockable (longer than any wind-up and its landing).
const GLINT_MARKS_MS: int = 2000
var _status: StatusComponent = null
var _flash_mat: ShaderMaterial = null
var _flash_meshes: Array[GeometryInstance3D] = []
var _flash_tween: Tween = null

## THE PARRY RING (Luke, 2026-11-01, T4: the tutorial's yard only): on a foe whose FoeDef asks (`parry_ring`), a ring
## closes on each swing from `RING_FROM` times its size to its size as the blow lands, where a dim one waits; then
## both flash and go. Read from the swing as this screen saw it start, as the parry is judged.
const RING: Color = Color(1.0, 0.9, 0.55, 0.95)
const RING_M: float = 0.9
const RING_FROM: float = 3.2
const RING_Y: float = 1.25
## Every word said over it, in order (tests read it).
var said: Array[String] = []
## Every ring shown, by the ability it closed on (tests read it).
var rings: Array[int] = []

const TABLE_BURNING: StringName = &"burning"
## ITS POISE (Luke, 2026-11-02: a bar that breaks, shown on the target marker): the server's `poise_state` row, read
## for the ring under a player's target (`CombatComponent`), worked out as the server does (`rules::poise_now`).
const TABLE_POISE: StringName = &"poise_state"
var poise_left: float = 0.0
var poise_most: float = 0.0
var poise_hit_us: int = 0
var poise_steady_us: int = 0
## Its poise broke (refilled with a Steadied after it): the marker's burst.
signal poise_broke()
const FIRE: Color = Color(1.0, 0.5, 0.15)


func required_tables() -> Array[StringName]:
	return [TABLE_BURNING, TABLE_POISE]


## Nothing burns until a fireball lands; nothing has poise until it is hit (and a server from before has none).
func optional_tables() -> Array[StringName]:
	return [TABLE_BURNING, TABLE_POISE]


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table == TABLE_BURNING:
		set_burning(new != null)
	elif table == TABLE_POISE:
		set_poise(new)
		if old != null and new != null and int(new.get(&"steady_until")) > int(old.get(&"steady_until")):
			poise_broke.emit()


## Its poise from a `poise_state` row (null: none, whole).
func set_poise(row: RefCounted) -> void:
	poise_left = float(row.get(&"left")) if row != null else 0.0
	poise_most = float(row.get(&"most")) if row != null else 0.0
	poise_hit_us = int(row.get(&"hit_at")) if row != null else 0
	poise_steady_us = int(row.get(&"steady_until")) if row != null else 0


## How much of its poise is worn at `now_us` (server microseconds), 0 to 1: whole again once unhit for
## `regents.poise_regen_ms` (the server's `rules::poise_now`).
func poise_worn(now_us: int) -> float:
	if poise_most <= 0.0 or float(now_us - poise_hit_us) / 1000.0 >= HotRules.number(&"regents.poise_regen_ms"):
		return 0.0
	return clampf(1.0 - poise_left / poise_most, 0.0, 1.0)


## Whether nothing wears its poise at `now_us`: just broken (Steadied).
func poise_steadied(now_us: int) -> bool:
	return now_us < poise_steady_us


## A fire on it, or none.
func set_burning(on: bool) -> void:
	if on == (fire != null):
		return
	if not on:
		fire.queue_free()
		fire = null
		return
	var ent: Node3D = entity as Node3D
	if ent == null:
		return
	fire = Node3D.new()
	fire.name = "Burning"
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = FIRE
	light.omni_range = 2.5
	light.position = Vector3(0, 1.0, 0)
	fire.add_child(light)
	var core := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.5
	core.mesh = s
	core.position = Vector3(0, 1.1, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(FIRE, 0.55)
	m.emission_enabled = true
	m.emission = FIRE
	m.emission_energy_multiplier = 2.0
	core.material_override = m
	fire.add_child(core)
	ent.add_child(fire)


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_health = ent.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent if ent != null else null
	if _health != null:
		_health.health_changed.connect(_on_health_changed)
	_status = ent.find_component(StatusComponent) as StatusComponent if ent != null else null
	if _status != null:
		_status.status_changed.connect(_on_status_changed)
	var actions: SpaceTimeActionComponent = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent if ent != null else null
	if actions != null:
		actions.started_elsewhere.connect(_on_started)
	var combat: CombatComponent = ent.find_component(CombatComponent) as CombatComponent if ent != null else null
	if combat != null:
		combat.parried.connect(func(by: int) -> void:
			flash(&"block")
			say("Parried", FLASH_STAGGER)
			spark(&"stagger", by))


func _on_started(ability_id: int) -> void:
	if KitDef.is_unblockable(ability_id):
		glint()
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	var foe: FoeDef = FoeDef.by_kind(ent.definition.kind) if ent != null and ent.definition != null else null
	if foe != null and foe.parry_ring and foe.kit != null:
		for a: AbilityDef in foe.kit.light:
			if a != null and a.id == ability_id:
				parry_ring(a.wind_up_ms)


## THE PARRY RING over `wind_up_ms`: shut as the blow lands.
func parry_ring(wind_up_ms: int) -> void:
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree() or wind_up_ms <= 0:
		return
	rings.append(wind_up_ms)
	var root := Node3D.new()
	root.name = "ParryRing"
	root.position = Vector3(0, RING_Y, 0)
	ent.add_child(root)
	var target := _ring_quad(Color(RING, 0.35))
	target.scale = Vector3.ONE * RING_M
	root.add_child(target)
	var closing := _ring_quad(RING)
	closing.scale = Vector3.ONE * RING_M * RING_FROM
	root.add_child(closing)
	var s_wind: float = float(wind_up_ms) / 1000.0
	var tw: Tween = root.create_tween()
	tw.tween_property(closing, ^"scale", Vector3.ONE * RING_M, s_wind)
	tw.tween_callback(func() -> void: (target.material_override as ShaderMaterial).set_shader_parameter(&"tint", Color(1.0, 1.0, 0.85, 1.0)))
	tw.tween_property(root, ^"scale", Vector3.ONE * 1.25, 0.12)
	tw.tween_callback(root.queue_free)


static var _ring_shader: Shader = null


## A camera-facing quad drawing a thin ring of `color` (a 1 m ring at scale 1).
static func _ring_quad(color: Color) -> MeshInstance3D:
	if _ring_shader == null:
		_ring_shader = Shader.new()
		_ring_shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float ring = smoothstep(0.80, 0.88, d) * (1.0 - smoothstep(0.92, 1.0, d));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * ring;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _ring_shader
	mat.set_shader_parameter(&"tint", color)
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## THE GLINT: a red spark at its head, flaring and gone in `GLINT_S`, and a red flash over its body.
func glint() -> void:
	glinted_ms = Time.get_ticks_msec()
	flash(&"glint")
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree():
		return
	# A STAR OF LIGHT (Luke's feedback, 2026-11-01: "just billboards with no texture"): a soft hot core and two crossed
	# streaks of the same soft light, turning a little as it flares, all faded together.
	var star := Node3D.new()
	star.name = "Glint"
	star.position = Vector3(0, GLINT_Y, 0)
	star.scale = Vector3.ONE * 0.2
	ent.add_child(star)
	var mat: StandardMaterial3D = _glow(GLINT)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX   # over what is behind it: added to a pale skull, red turned orange
	for size: Vector2 in [Vector2(0.45, 0.45), Vector2(1.3, 0.07), Vector2(0.07, 1.3)]:
		var part := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = size
		quad.material = mat
		part.mesh = quad
		star.add_child(part)
	var tw: Tween = star.create_tween()
	tw.tween_property(star, ^"scale", Vector3.ONE * 1.1, GLINT_S * 0.4).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(star, ^"rotation:z", 0.6, GLINT_S)
	tw.parallel().tween_property(mat, ^"albedo_color:a", 0.0, GLINT_S).set_ease(Tween.EASE_IN)
	tw.tween_callback(star.queue_free)


func _on_health_changed(_current: float, _max: float, delta: float) -> void:
	if is_zero_approx(delta):
		return
	show_number(-delta)
	if delta < 0.0:
		var source: int = _health.get_last_damage_source() if _health != null else 0
		if _status != null and _status.status() == STATUS_BLOCKING and _guard_stopped(source):
			flash(&"block")
			say("Blocked", FLASH_BLOCK)
			spark(&"block", source)
			hit_stop(source, false)
		else:
			flash(&"hurt" if is_local() else &"hit")
			spark(&"big" if -delta >= big_hit else &"hit", source)
			hit_stop(source, -delta >= big_hit)
	if delta < 0.0 and _health != null:
		var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
		var c: CombatComponent = me.find_component(CombatComponent) as CombatComponent if me != null else null
		if c != null:
			c.target_what_you_hit(entity_id, _health.get_last_damage_source())


func _on_status_changed(_from: int, to: int) -> void:
	if to == STATUS_STAGGERED:
		# The guard knocked aside, once, over the dazed sway its status holds for its length (Luke, 2026-11-01).
		var ent: SpaceTimeEntity = entity as SpaceTimeEntity
		var anim: AnimationDriverComponent = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent if ent != null else null
		if anim != null:
			anim.play_action(STAGGER_REACTION)
		flash(&"stagger")
		spark(&"stagger", _status.by_entity() if _status != null else 0)
		hit_stop(_status.by_entity() if _status != null else 0, true)


## A HIT-STOP for this body and the one that struck it (`from_id`; 0: none), a big one longer. The local
## player's own body is held only when it is the one struck.
func hit_stop(from_id: int, big: bool) -> void:
	var secs: float = maxf(HotRules.number(&"regents.hitstop_big_ms" if big else &"regents.hitstop_ms"), 0.0) / 1000.0
	hit_stops.append(secs)
	if secs <= 0.0:
		return
	var me: SpaceTimeEntity = entity as SpaceTimeEntity
	var mine: AnimationDriverComponent = me.find_component(AnimationDriverComponent) as AnimationDriverComponent if me != null else null
	if mine != null:
		mine.hold_still(secs)
	var by: SpaceTimeEntity = EntityRegistry.get_entity(from_id) as SpaceTimeEntity if from_id > 0 else null
	if by != null and by != me and from_id != EntityRegistry.local_entity_id:
		var theirs: AnimationDriverComponent = by.find_component(AnimationDriverComponent) as AnimationDriverComponent
		if theirs != null:
			theirs.hold_still(secs)


## A SPARK of `kind` (&"hit", &"big", &"block", &"stagger") at its chest, a little towards `from_id` (who struck;
## 0: straight on): a burst of embers and a streak across the blow, gone in `SPARK_S`.
func spark(kind: StringName, from_id: int) -> void:
	sparks.append(kind)
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree():
		return
	var color: Color = {&"block": SPARK_BLOCK, &"stagger": SPARK_STAGGER}.get(kind, SPARK_HIT)
	var size: float = 1.6 if kind == &"big" or kind == &"stagger" else 1.0
	var toward: Vector3 = Vector3.ZERO
	var from: Node3D = EntityRegistry.get_entity(from_id) as Node3D if from_id > 0 else null
	if from != null and from != ent:
		toward = from.global_position - ent.global_position
		toward.y = 0.0
		toward = toward.normalized() if toward.length() > 0.01 else Vector3.ZERO
	var at: Vector3 = ent.global_position + Vector3(0, SPARK_Y, 0) + toward * SPARK_TOWARD_M
	var root: Node3D = Node3D.new()
	root.name = "Spark"
	root.top_level = true
	ent.add_child(root)
	root.global_position = at
	var embers := CPUParticles3D.new()
	embers.one_shot = true
	embers.emitting = true
	embers.amount = int(12 * size)
	embers.lifetime = SPARK_S
	embers.explosiveness = 1.0
	embers.direction = toward if toward != Vector3.ZERO else Vector3.UP
	embers.spread = 70.0
	embers.initial_velocity_min = 3.5 * size
	embers.initial_velocity_max = 7.0 * size
	embers.gravity = Vector3(0, -6, 0)
	embers.scale_amount_min = 0.05
	embers.scale_amount_max = 0.1 * size
	# Each ember a soft dot of light, facing the camera as a particle, fading out over its life.
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	embers.color_ramp = fade
	var dot := QuadMesh.new()
	dot.size = Vector2(1, 1)
	var ember_mat: StandardMaterial3D = _glow(color)
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	ember_mat.vertex_color_use_as_albedo = true
	dot.material = ember_mat
	embers.mesh = dot
	root.add_child(embers)
	# The streak: a thin bright bar across the line of the blow, flaring and gone.
	var streak := MeshInstance3D.new()
	var bar := QuadMesh.new()
	bar.size = Vector2(0.9 * size, 0.07 * size)
	var mat: StandardMaterial3D = _glow(color)
	bar.material = mat
	streak.mesh = bar
	root.add_child(streak)
	var tw: Tween = root.create_tween()
	tw.tween_property(mat, ^"albedo_color:a", 0.0, SPARK_S * 0.6).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(streak, ^"scale", Vector3(1.4, 0.4, 1.0), SPARK_S * 0.6)
	tw.tween_interval(SPARK_S)
	tw.tween_callback(root.queue_free)


## An additive, unshaded, camera-facing material in `color`, drawn over the body: SOFT LIGHT (`soft_light`), bright
## in the middle and fading to nothing at the edge, so a quad never shows as a square.
static func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# Without it a billboard ignores its node's and its particle's scale: every "small" ember was drawn a whole 1 m
	# square (Luke's screenshot, 2026-11-01).
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.albedo_color = color
	m.albedo_texture = soft_light()
	return m


static var _soft: GradientTexture2D = null


## THE SOFT LIGHT: a round fall-off, white at the heart to clear at the rim (alpha), made once.
static func soft_light() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.55, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0)])
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


## Whether a hit from `attacker_id` on this (blocking) entity was one its guard stops: from in front, not a
## swing that glinted. The server's rule, as this client sees it (presentation).
func _guard_stopped(attacker_id: int) -> bool:
	var a: SpaceTimeEntity = EntityRegistry.get_entity(attacker_id) as SpaceTimeEntity
	var me: SpaceTimeEntity = entity as SpaceTimeEntity
	if a == null or me == null:
		return true
	var fb: HitFeedbackComponent = a.find_component(HitFeedbackComponent) as HitFeedbackComponent
	if fb != null and Time.get_ticks_msec() - fb.glinted_ms < GLINT_MARKS_MS:
		return false
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var st: MovementState = (mv.get_predicted_state() if is_local() else mv.get_render_state()) if mv != null else null
	if st == null:
		return true
	return CombatComponent.guard_stops(st.yaw, a.global_position.x - me.global_position.x, a.global_position.z - me.global_position.z)


## Whether this is the local player's own body.
func is_local() -> bool:
	return entity_id > 0 and entity_id == EntityRegistry.local_entity_id


## LIGHT IT UP: every mesh of its look shows `kind`'s color over itself, fading over `FLASH_S`.
func flash(kind: StringName) -> void:
	flashes.append(kind)
	var color: Color = {&"hit": FLASH_HIT, &"hurt": FLASH_HURT, &"block": FLASH_BLOCK, &"stagger": FLASH_STAGGER, &"glint": GLINT}.get(kind, FLASH_HIT)
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree():
		return
	if _flash_mat == null:
		_flash_mat = ShaderMaterial.new()
		_flash_mat.shader = _rim_shader()
	_unflash()
	var look: Node = ent.get_node_or_null(^"Visual")
	for n: Node in (look if look != null else ent).find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if g is Label3D or g.material_overlay != null:
			continue   # its numbers, and anything that already has an overlay of its own (a grade's glow)
		g.material_overlay = _flash_mat
		_flash_meshes.append(g)
	_flash_mat.set_shader_parameter(&"tint", color)
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(a: float) -> void: _flash_mat.set_shader_parameter(&"tint", Color(color, a)),
		color.a, 0.0, FLASH_S).set_ease(Tween.EASE_IN)
	_flash_tween.tween_callback(_unflash)


static var _rim: Shader = null


## THE FLASH'S LIGHT (Luke's feedback, 2026-11-01): a rim round the body's edge and a faint wash over its face,
## added over its own look, so the struck thing still reads as itself.
static func _rim_shader() -> Shader:
	if _rim == null:
		_rim = Shader.new()
		_rim.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * rim * rim;
}
"""
	return _rim


func _unflash() -> void:
	for g: GeometryInstance3D in _flash_meshes:
		if is_instance_valid(g) and g.material_overlay == _flash_mat:
			g.material_overlay = null
	_flash_meshes.clear()


## A word over it for a moment ("Blocked", "Parried"), smaller than a number.
func say(text: String, color: Color) -> void:
	said.append(text)
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree():
		return
	var l: Label3D = Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0022
	l.font_size = 30
	l.outline_size = 8
	l.modulate = Color(color, 1.0)
	l.position = Vector3(0, 2.3, 0)
	ent.add_child(l)
	var tw: Tween = l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, ^"position:y", l.position.y + 0.5, LIFE_S).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, ^"modulate:a", 0.0, LIFE_S).set_delay(LIFE_S * 0.5)
	tw.chain().tween_callback(l.queue_free)


## Float `amount` up from the entity (a hit positive, a heal negative).
func show_number(amount: float) -> void:
	shown.append(amount)
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree():
		return
	var l: Label3D = Label3D.new()
	l.text = str(roundi(absf(amount)))
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0022
	l.font_size = 40 if amount < big_hit else 56
	l.outline_size = 10
	l.modulate = HEAL if amount < 0.0 else (BIG if amount >= big_hit else HIT)
	l.position = Vector3(randf_range(-0.25, 0.25), 1.9, randf_range(-0.25, 0.25))
	ent.add_child(l)
	var tw: Tween = l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, ^"position:y", l.position.y + RISE_M, LIFE_S).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, ^"modulate:a", 0.0, LIFE_S).set_delay(LIFE_S * 0.4)
	tw.chain().tween_callback(l.queue_free)
	if amount > 0.0:
		_shake_left = 0.25


func _process(delta: float) -> void:
	if fire != null:
		(fire.get_node(^"Light") as OmniLight3D).light_energy = 1.2 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.023)
	var v: Node3D = get_node_or_null(^"../../Visual") as Node3D
	if v == null:
		return
	if _shake_left > 0.0:
		_shake_left -= delta
		v.rotation.z = sin(_shake_left * 60.0) * 0.08 * (_shake_left / 0.25)
	elif not is_zero_approx(v.rotation.z):
		v.rotation.z = 0.0
