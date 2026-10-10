@tool
class_name StatusWorkbench extends Workbench
## THE STATUS WORKBENCH (DECISIONS #206): a status on a real character, with no server. What it
## does to how the character moves is MEASURED by the real movement model with the status applied
## (`StatusDef.apply_to` and `filter_input`, exactly what prediction and the sidecar step by); its
## pose plays on the character; its timeline says what it becomes and when.
##
##   moves      how fast it runs and sprints in the status, against the character's own, and whether
##              it can jump (and how high)
##   burst      the speed of its burst, and for how long, then the speed after
##   pose       its pose on the character (or that the character has no clip for it: it moves as usual)
##   timeline   how long it lasts and what it becomes, to the end of the chain


const TRACE_COLOUR: Color = Color(1.0, 0.45, 0.4)

var _trace: MultiMeshInstance3D = null
var _info: Label3D = null
## The last test's numbers (tests).
var last_measure: Dictionary = {}


func content_type() -> StringName:
	return &"status"


func test_actions() -> Array[StringName]:
	return [&"moves", &"burst", &"pose", &"timeline"]


func test_info(action: StringName) -> String:
	match action:
		&"moves": return "How fast the character runs and sprints in it, against its own, and whether it can jump"
		&"burst": return "The speed of its burst, for how long, then the speed after"
		&"pose": return "Its pose on the character (or that the character has no clip for it)"
		&"timeline": return "How long it lasts and what it becomes, to the end"
	return ""


## Whose movement and model it is tried on: the "Tried on" choice (the humanoid until chosen).
func tries_on_character() -> bool:
	return true


func controls() -> Array[Dictionary]:
	return [character_control()]


func load_item(def: ContentDef) -> void:
	_build_props()
	var s: StatusDef = def as StatusDef
	if s == null:
		_info.text = "no status on the bench"
		return
	_info.text = "%s (status %d)  ·  speed ×%s%s%s  ·  %s" % [s.display_name, s.status, s.speed,
		"" if s.can_sprint else "  ·  no sprint", "" if s.can_jump else "  ·  no jump",
		"lasts %s s" % s.lasts_s if s.lasts_s > 0.0 else "until changed"]
	_info.modulate = s.color
	var m: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
	if m != null:
		m.visible = not s.hide_body


## The character's own movement, and in the status (bursting or not).
func _configs(s: StatusDef) -> Array[MovementConfig]:
	var own: MovementConfig = character.movement_config() if character != null else MovementConfig.shared()
	return [own, s.apply_to(own, false), s.apply_to(own, true)]


func run_test(action: StringName) -> String:
	var s: StatusDef = item as StatusDef
	if s == null:
		return "nothing on the bench"
	var cfgs: Array[MovementConfig] = _configs(s)
	match action:
		&"moves":
			var own: Dictionary = MovementWorkbench.measure_config(cfgs[0], &"top_speeds")
			var now: Dictionary = MovementWorkbench.measure_config(cfgs[1], &"top_speeds", s)
			var jump: Dictionary = MovementWorkbench.measure_config(cfgs[1], &"jump", s)
			last_measure = {"run": now["run"], "sprint": now["sprint"], "own_run": own["run"], "own_sprint": own["sprint"],
				"jump_m": jump["height_m"]}
			_draw(now.get("trace", []) as Array)
			if is_zero_approx(float(now["run"])):
				return "%s cannot move (speed 0)%s" % [s.display_name, "" if s.can_jump else ", nor jump"]
			return "runs %.2f m/s (its own %.2f), sprints %s; %s" % [now["run"], own["run"],
				"%.2f m/s (its own %.2f)" % [now["sprint"], own["sprint"]] if s.can_sprint else "no faster (no sprint)",
				"jumps %.2f m" % jump["height_m"] if s.can_jump else "cannot jump"]
		&"burst":
			if not s.bursting_at(0.0):
				last_measure = {}
				return "no burst (burst %s, burst_s %s)" % [s.burst, s.burst_s]
			var during: Dictionary = MovementWorkbench.measure_config(cfgs[2], &"top_speeds", s)
			var after: Dictionary = MovementWorkbench.measure_config(cfgs[1], &"top_speeds", s)
			last_measure = {"during": during["sprint"], "after": after["sprint"]}
			_draw(during.get("trace", []) as Array)
			return "sprints %.2f m/s for the first %.2f s, then %.2f m/s" % [during["sprint"], s.burst_s, after["sprint"]]
		&"pose":
			var m: Mannequin = get_node_or_null(^"Mannequin") as Mannequin
			if s.pose.is_empty():
				last_measure = {"pose": false}
				return "no pose: it moves as usual"
			var has: bool = character != null and character.animation_set != null and character.animation_set.has_exact(s.pose)
			last_measure = {"pose": has}
			if not has:
				return "the character has no '%s' clip: it moves as usual. Add one to its AnimationSet" % s.pose
			if m != null:
				m.play(s.pose)
			return "holds '%s' (%.2f s a loop)" % [s.pose, m.clip_length(s.pose) if m != null else 0.0]
		&"timeline":
			var steps: PackedStringArray = PackedStringArray()
			var seen: Array[StatusDef] = []
			var at: StatusDef = s
			while at != null and not seen.has(at):
				seen.append(at)
				if at.lasts_s <= 0.0:
					steps.append("%s until something changes it" % at.display_name)
					break
				steps.append("%s for %s s" % [at.display_name, at.lasts_s])
				at = at.then_status if at.then_status != null else StatusDef.normal()
				if seen.has(at):
					steps.append("then %s again (a loop)" % at.display_name)
			last_measure = {"steps": steps.size()}
			return ", then ".join(steps)
	return "no such test"


## Amber when its pose is one the character on the bench has no clip for: it would move as usual.
func fit_checks() -> Array[String]:
	var s: StatusDef = item as StatusDef
	var clips: AnimationSet = character.animation_set if character != null else null
	if s != null and not s.pose.is_empty() and clips != null and not clips.has_exact(s.pose):
		return ["%s has no '%s' clip: in this status it moves as usual" % [character.display_name, s.pose]]
	return []


func _draw(points: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.04
	dot.height = 0.08
	mm.mesh = dot
	mm.instance_count = points.size()
	for i: int in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), (points[i] as Vector3) + Vector3(1.2, 0, 0)))
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
