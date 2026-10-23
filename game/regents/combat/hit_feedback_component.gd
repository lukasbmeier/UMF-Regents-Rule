class_name HitFeedbackComponent extends SpaceTimeComponent
## A HIT, SHOWN (presentation only): every time its entity's health drops, the number floats up from it
## and its look gives a little shake; a heal floats up green. The training dummy has one, and so will
## creatures and players. It reads the health component's signals: it never decides anything.
##
## A HIT FLASHES (owner, 2026-10-21: "enemy flashing when you block/get hit and same for player getting hit"):
## the body lights up for a moment over its own look (`material_overlay` on each mesh): white for what you
## hit, red when it is you; a hit taken while BLOCKING flashes steel blue and says "Blocked"; a STAGGER (a
## parried swing) flashes gold and says so.
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
## The statuses that change a flash (regents' status content).
const STATUS_BLOCKING: int = 102
const STATUS_STAGGERED: int = 103

## A hit this big or more shows larger and redder.
@export var big_hit: float = 20.0
## Every number shown, newest last (tests read it).
var shown: Array[float] = []
var _health: SpaceTimeHealthComponent = null
var _shake_left: float = 0.0
## The fire while it burns, or null.
var fire: Node3D = null
## Every flash shown, newest last, by name: &"hit", &"hurt", &"block", &"stagger" (tests read it).
var flashes: Array[StringName] = []
var _status: StatusComponent = null
var _flash_mat: StandardMaterial3D = null
var _flash_meshes: Array[GeometryInstance3D] = []
var _flash_tween: Tween = null

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
	_status = ent.find_component(StatusComponent) as StatusComponent if ent != null else null
	if _status != null:
		_status.status_changed.connect(_on_status_changed)


func _on_health_changed(_current: float, _max: float, delta: float) -> void:
	if is_zero_approx(delta):
		return
	show_number(-delta)
	if delta < 0.0:
		if _status != null and _status.status() == STATUS_BLOCKING:
			flash(&"block")
			say("Blocked", FLASH_BLOCK)
		else:
			flash(&"hurt" if is_local() else &"hit")
	if delta < 0.0 and _health != null:
		var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
		var c: CombatComponent = me.find_component(CombatComponent) as CombatComponent if me != null else null
		if c != null:
			c.target_what_you_hit(entity_id, _health.get_last_damage_source())


func _on_status_changed(_from: int, to: int) -> void:
	if to == STATUS_STAGGERED:
		flash(&"stagger")
		say("Staggered", FLASH_STAGGER)


## Whether this is the local player's own body.
func is_local() -> bool:
	return entity_id > 0 and entity_id == EntityRegistry.local_entity_id


## LIGHT IT UP: every mesh of its look shows `kind`'s colour over itself, fading over `FLASH_S`.
func flash(kind: StringName) -> void:
	flashes.append(kind)
	var colour: Color = {&"hit": FLASH_HIT, &"hurt": FLASH_HURT, &"block": FLASH_BLOCK, &"stagger": FLASH_STAGGER}.get(kind, FLASH_HIT)
	var ent: Node3D = entity as Node3D
	if ent == null or not ent.is_inside_tree():
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_unflash()
	var look: Node = ent.get_node_or_null(^"Visual")
	for n: Node in (look if look != null else ent).find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if g is Label3D or g.material_overlay != null:
			continue   # its numbers, and anything that already has an overlay of its own (a grade's glow)
		g.material_overlay = _flash_mat
		_flash_meshes.append(g)
	_flash_mat.albedo_color = colour
	if _flash_tween != null:
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, ^"albedo_color:a", 0.0, FLASH_S).set_ease(Tween.EASE_IN)
	_flash_tween.tween_callback(_unflash)


func _unflash() -> void:
	for g: GeometryInstance3D in _flash_meshes:
		if is_instance_valid(g) and g.material_overlay == _flash_mat:
			g.material_overlay = null
	_flash_meshes.clear()


## A word over it for a moment ("Blocked", "Staggered"), smaller than a number.
func say(text: String, colour: Color) -> void:
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
	l.modulate = Color(colour, 1.0)
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
