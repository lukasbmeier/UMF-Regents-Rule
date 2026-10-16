@tool
class_name BodyWorkbench extends Workbench
## THE BODY WORKBENCH (DECISIONS #246): a body beside a real character, with no server.
##
##   size     how big it is next to the character's hand (its diameter, its mass)
##   arc      its hardest throw, 30 degrees up from a hand's height: how far, how high, how long, under
##            gravity and its drag, stepped at 60 Hz as the game steps it (drawn). Its FORCES (a disc's
##            lift and fade) are not in it: the editor runs no physics, so they are tried in the game
##   bounce   dropped from 2 m: how high its first bounce comes back up (its bounce, on the ground)
##   limits   who may throw it, how hard and spun, from how far, how many, how long it lasts
##
## The body is drawn at its true size, 0.6 m in front of the character at a hand's height.

const TRACE_COLOUR: Color = Color(0.95, 0.6, 0.2)
const HAND: Vector3 = Vector3(0.0, 1.4, -0.6)
const DT: float = 1.0 / 60.0
const GRAVITY: float = 9.8

var _trace: MultiMeshInstance3D = null
var _info: Label3D = null
var _shown: Node3D = null
## The last test's numbers (tests).
var last_measure: Dictionary = {}


func content_type() -> StringName:
	return &"body"


func test_actions() -> Array[StringName]:
	return [&"size", &"arc", &"bounce", &"limits"]


func test_info(action: StringName) -> String:
	match action:
		&"size": return "How big it is next to the character's hand"
		&"arc": return "Its hardest throw: how far, how high, how long (gravity and drag; its forces are tried in the game)"
		&"bounce": return "Dropped from 2 m: how high it comes back up"
		&"limits": return "Who may throw it, how hard, from how far, how many, how long it lasts"
	return ""


func tries_on_character() -> bool:
	return true


func controls() -> Array[Dictionary]:
	return [character_control()]


func load_item(def: ContentDef) -> void:
	_build_props()
	var b: BodyDef = def as BodyDef
	if _shown != null:
		_shown.queue_free()
		_shown = null
	if b == null:
		_info.text = "no body on the bench"
		return
	_shown = b.make_visual()
	_shown.name = "Body"
	_shown.position = HAND
	add_child(_shown)
	_info.text = "%s  ·  %s" % [b.display_name, b.summary()]
	_info.modulate = b.color


## Its hardest throw at `angle_deg`, gravity and linear drag only, at 60 Hz from a hand's height until
## it is back on the ground: {range_m, apex_m, seconds, trace}.
static func arc(b: BodyDef, angle_deg: float = 30.0) -> Dictionary:
	var a: float = deg_to_rad(angle_deg)
	var vel := Vector3(0.0, sin(a), -cos(a)) * b.max_speed_mps
	var pos: Vector3 = HAND
	var apex: float = pos.y
	var t: float = 0.0
	var trace: Array = []
	while t < 30.0:
		vel.y -= GRAVITY * b.gravity_scale * DT
		vel *= maxf(0.0, 1.0 - b.linear_damp * DT)
		pos += vel * DT
		t += DT
		apex = maxf(apex, pos.y)
		if int(t / DT) % 3 == 0:
			trace.append(pos)
		if pos.y <= b.radius_m and vel.y < 0.0:
			break
	return {"range_m": absf(pos.z - HAND.z), "apex_m": apex, "seconds": t, "trace": trace}


func run_test(action: StringName) -> String:
	var b: BodyDef = item as BodyDef
	if b == null:
		return "nothing on the bench"
	match action:
		&"size":
			var across: float = b.radius_m * 2.0 if b.shape != BodyDef.Shape.BOX else maxf(b.box_size.x, b.box_size.z)
			last_measure = {"across_m": across}
			return "%.0f cm across, %.0f g%s" % [across * 100.0, b.mass_kg * 1000.0,
				"; %.1f cm thick" % (b.height_m * 100.0) if b.shape == BodyDef.Shape.CYLINDER else ""]
		&"arc":
			var r: Dictionary = arc(b)
			last_measure = r
			_draw(r["trace"] as Array)
			return "thrown at its fastest (%.0f m/s), 30 degrees up: %.1f m away, %.1f m up, %.2f s in the air%s" % [
				b.max_speed_mps, r["range_m"], r["apex_m"], r["seconds"], "; its forces are tried in the game" if b.forces != null else ""]
		&"bounce":
			var back: float = 2.0 * b.bounce * b.bounce
			last_measure = {"back_m": back}
			return "dropped from 2 m it comes back %.2f m (bounce %.2f), then rolls to rest (ground drag %.2f a second)" % [back, b.bounce, b.ground_drag]
		&"limits":
			var who: Array = HoldDef.kinds_of(b.launched_by)
			last_measure = {"kinds": who}
			return "%s; at most %.0f m/s and %.0f rad/s, within %.1f m of the thrower, %s each, lasting %s" % [
				"thrown by kinds %s" % [who] if not who.is_empty() else "launched only by its genre",
				b.max_speed_mps, b.max_spin_rps, b.reach_m,
				"%d" % b.max_per_owner if b.max_per_owner > 0 else "any number",
				"%.0f s" % b.lifetime_s if b.lifetime_s > 0.0 else "until its genre takes it away"]
	return "no such test"


func _draw(points: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	mm.mesh = dot
	mm.instance_count = points.size()
	for i: int in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i] as Vector3))
	_trace.multimesh = mm
	(_trace.material_override as StandardMaterial3D).albedo_color = TRACE_COLOUR


func _build_props() -> void:
	if _trace != null:
		return
	_trace = MultiMeshInstance3D.new()
	_trace.name = "Trace"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trace.material_override = mat
	add_child(_trace)
	_info = Label3D.new()
	_info.name = "Info"
	_info.position = Vector3(0, 2.4, 0)
	_info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_info.pixel_size = 0.005
	add_child(_info)
