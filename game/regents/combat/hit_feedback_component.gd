class_name HitFeedbackComponent extends SpaceTimeComponent
## A HIT, SHOWN (presentation only): every time its entity's health drops, the number floats up from it
## and its look gives a little shake; a heal floats up green. The training dummy has one, and so will
## creatures and players. It reads the health component's signals: it never decides anything.

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


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_health = ent.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent if ent != null else null
	if _health != null:
		_health.health_changed.connect(_on_health_changed)


func _on_health_changed(_current: float, _max: float, delta: float) -> void:
	if is_zero_approx(delta):
		return
	show_number(-delta)


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
	var v: Node3D = get_node_or_null(^"../../Visual") as Node3D
	if v == null:
		return
	if _shake_left > 0.0:
		_shake_left -= delta
		v.rotation.z = sin(_shake_left * 60.0) * 0.08 * (_shake_left / 0.25)
	elif not is_zero_approx(v.rotation.z):
		v.rotation.z = 0.0
