@tool
class_name AbilityWorkbench extends Workbench
## THE ABILITY WORKBENCH (DECISIONS #203): an ability on the real character, against a dummy, with
## no server. The ring on the floor is its range; the bench reads every change you make to the
## ability in the Inspector. Its tests play the moment the ability lives in and say what the game
## would do, by the SAME rules the server uses (`use_ability`, Tier A: a targeted ability hits a
## target in range and is refused beyond it; an untargeted one, range 0, resolves as a miss; a
## second use inside the cooldown is refused).
##
##   use_in_range       the wind-up plays, then it lands on the dummy
##   use_out_of_range   the dummy just past the ring: refused, as the server would
##   cooldown           used twice at once: the second is refused until the cooldown is over

## Who uses it.
@export var character: EntityDefinition = preload("res://foundation/content/character/humanoid.tres"):
	set(v):
		character = v
		var m: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
		if m != null:
			m.definition = v
## How fast the tests play (1: as in the game; lower to watch a wind-up closely).
@export_range(0.1, 2.0, 0.05) var playback_speed: float = 1.0

const RING_WIDTH: float = 0.05
const READY: Color = Color(0.35, 0.85, 1.0)
const WINDING: Color = Color(1.0, 0.8, 0.3)
const HIT: Color = Color(1.0, 0.35, 0.3)
## The dummy is a capsule centred on its node: half its height up, so it stands on the floor.
const DUMMY_Y: float = 0.9

var _ring: MeshInstance3D = null
var _info: Label3D = null
var _result: Label3D = null
var _dummy_home: Vector3 = Vector3(0, 0, -1.6)
## What the last use did: "hit", "miss", "out_of_range", "cooling_down" (tests).
var last_outcome: String = ""


func content_type() -> StringName:
	return &"ability"


func test_actions() -> Array[StringName]:
	return [&"use_in_range", &"use_out_of_range", &"cooldown"]


func load_item(def: ContentDef) -> void:
	_build_props()
	var a: AbilityDef = def as AbilityDef
	if a == null:
		_info.text = "no ability on the bench"
		_ring.visible = false
		return
	_ring.visible = a.range_m > 0.0
	_set_ring(a.range_m, READY)
	_info.text = "%s  ·  range %s m  ·  wind-up %d ms  ·  cooldown %d ms  ·  damage %s  ·  animation '%s'" % [
		a.display_name, a.range_m, a.wind_up_ms, a.cooldown_ms, a.damage, a.animation]
	_dummy().position = Vector3(0, DUMMY_Y, -maxf(a.range_m * 0.8, 1.2))
	_face_dummy()
	_result.text = ""


## The ring's radius now (tests).
func ring_radius() -> float:
	var t: TorusMesh = _ring.mesh as TorusMesh if _ring != null else null
	return (t.inner_radius + t.outer_radius) * 0.5 if t != null else 0.0


func run_test(action: StringName) -> String:
	var a: AbilityDef = item as AbilityDef
	if a == null:
		return "nothing on the bench"
	match action:
		&"use_in_range":
			_dummy().position = Vector3(0, DUMMY_Y, -maxf(a.range_m * 0.8, 0.5))
			return await _use(a)
		&"use_out_of_range":
			_dummy().position = Vector3(0, DUMMY_Y, -(a.range_m + 1.0))
			_face_dummy()
			return await _use(a)
		&"cooldown":
			_dummy().position = Vector3(0, DUMMY_Y, -maxf(a.range_m * 0.8, 0.5))
			var first: String = await _use(a)
			var started: int = Time.get_ticks_msec()
			# Game time since the first use ended (the bench may be playing slowed down).
			var second: String = judge(a, _distance(), (Time.get_ticks_msec() - started) * playback_speed)
			last_outcome = second
			_say("again at once: %s" % _words(second, a), WINDING)
			await _wait(a.cooldown_ms / 1000.0)
			var third: String = judge(a, _distance(), (Time.get_ticks_msec() - started) * playback_speed)
			_say("after %d ms: %s" % [a.cooldown_ms, _words(third, a)], READY)
			return "%s; used again at once: %s; after the cooldown: %s" % [first, _words(second, a), _words(third, a)]
	return "no such test"


## WHAT THE SERVER WOULD DO with a use of `a` at `distance` m from the target, `since_last_ms` after
## the last use (INF: never used): "hit", "miss", "out_of_range", "cooling_down". The same rules as
## `use_ability` in server/src/module/authorities.rs (Tier A).
static func judge(a: AbilityDef, distance: float, since_last_ms: float) -> String:
	if since_last_ms < a.cooldown_ms:
		return "cooling_down"
	if a.range_m <= 0.0:
		return "miss"
	if distance > a.range_m:
		return "out_of_range"
	return "hit"


func _use(a: AbilityDef) -> String:
	var who: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
	var outcome: String = judge(a, _distance(), INF)
	last_outcome = outcome
	if outcome == "out_of_range":
		_say("refused: out of range (%.1f m > %s m)" % [_distance(), a.range_m], HIT)
		return _words(outcome, a)
	var animated: bool = who != null and who.play(a.animation, false)
	_set_ring(a.range_m, WINDING)
	_say("wind-up %d ms%s" % [a.wind_up_ms, "" if animated else "  (the character has no '%s' animation)" % a.animation], WINDING)
	await _wait(a.wind_up_ms / 1000.0)
	_set_ring(a.range_m, HIT if outcome == "hit" else READY)
	_say(_words(outcome, a), HIT if outcome == "hit" else READY)
	await _wait(0.4)
	if who != null:
		who.play(&"locomotion.idle")
	_set_ring(a.range_m, READY)
	return _words(outcome, a)


static func _words(outcome: String, a: AbilityDef) -> String:
	match outcome:
		"hit": return "HIT for %s damage" % a.damage
		"miss": return "MISS (untargeted: range 0 resolves as a miss in a Tier A world)"
		"out_of_range": return "refused: out of range"
		"cooling_down": return "refused: on cooldown"
	return outcome


## The user turns to the target, as a player aiming at it would (the game's forward is -Z), and the
## thumbnail camera frames the two from the side, whatever the range.
func _face_dummy() -> void:
	var who: Node3D = get_node_or_null(^"Mannequin") as Node3D
	var to: Vector3 = _dummy().position
	if who != null:
		who.rotation.y = atan2(-to.x, -to.z)
	var cam: Camera3D = get_node_or_null(^"ThumbnailCamera") as Camera3D
	if cam != null:
		var mid: Vector3 = Vector3(to.x * 0.5, 0.9, to.z * 0.5)
		var span: float = maxf(Vector2(to.x, to.z).length(), 1.5)
		cam.look_at_from_position(mid + Vector3(span * 1.3 + 1.2, 1.2 + span * 0.3, 0.4), mid)


func _distance() -> float:
	return Vector2(_dummy().position.x, _dummy().position.z).length()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds / playback_speed, 0.0)).timeout


func _say(text: String, colour: Color) -> void:
	if _result != null:
		_result.text = text
		_result.modulate = colour


func _dummy() -> Node3D:
	return get_node(^"Dummy") as Node3D


func _set_ring(radius: float, colour: Color) -> void:
	var t: TorusMesh = _ring.mesh as TorusMesh
	t.inner_radius = maxf(radius - RING_WIDTH, 0.0)
	t.outer_radius = maxf(radius + RING_WIDTH, RING_WIDTH)
	(_ring.material_override as StandardMaterial3D).albedo_color = colour


func _build_props() -> void:
	if _ring != null:
		return
	_ring = MeshInstance3D.new()
	_ring.name = "RangeRing"
	var torus := TorusMesh.new()
	torus.rings = 64
	torus.ring_segments = 6
	_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = READY
	_ring.material_override = mat
	_ring.position.y = 0.02
	add_child(_ring)
	_info = Label3D.new()
	_info.name = "Info"
	_info.position = Vector3(0, 2.4, 0)
	_info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_info.pixel_size = 0.004
	add_child(_info)
	_result = Label3D.new()
	_result.name = "Result"
	_result.position = Vector3(0, 2.1, 0)
	_result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_result.pixel_size = 0.005
	_result.outline_size = 8
	add_child(_result)
