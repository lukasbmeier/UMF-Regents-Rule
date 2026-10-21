class_name HitFeedbackComponent extends SpaceTimeComponent
## A HIT, SHOWN (presentation only): every time its entity's health drops, the number floats up from it
## and its look gives a little shake; a heal floats up green. The training dummy has one, and so will
## creatures and players. It reads the health component's signals: it never decides anything.
##
## A HIT THAT WAS YOURS picks its entity as your target when you have none (owner, 2026-10-20: "auto
## highlight that enemy"; `CombatComponent.target_what_you_hit`). And while it BURNS (a fireball's: its
## `burning` row), a fire flickers on it.

const RISE_M: float = 1.1
const LIFE_S: float = 0.9
const HIT: Color = Color(1.0, 0.92, 0.55)
const BIG: Color = Color(1.0, 0.55, 0.3)
const HEAL: Color = Color(0.55, 1.0, 0.6)

## A hit this big or more shows larger and redder.
@export var big_hit: float = 20.0
## Every number shown, newest last (tests read it).
var shown: Array[float] = []
var _health: SpaceTimeHealthComponent = null
var _shake_left: float = 0.0
## The fire while it burns, or null.
var fire: Node3D = null

const TABLE_BURNING: StringName = &"burning"
const FIRE: Color = Color(1.0, 0.5, 0.15)


func required_tables() -> Array[StringName]:
	return [TABLE_BURNING]


## Nothing burns until a fireball lands.
func optional_tables() -> Array[StringName]:
	return [TABLE_BURNING]


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table == TABLE_BURNING:
		set_burning(new != null)


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


func _on_health_changed(_current: float, _max: float, delta: float) -> void:
	if is_zero_approx(delta):
		return
	show_number(-delta)
	if delta < 0.0 and _health != null:
		var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
		var c: CombatComponent = me.find_component(CombatComponent) as CombatComponent if me != null else null
		if c != null:
			c.target_what_you_hit(entity_id, _health.get_last_damage_source())


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
