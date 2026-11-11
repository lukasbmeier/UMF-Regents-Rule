class_name CarveMinigame extends SkillMinigame
## WOODWORKING'S CARVE, PLAYED (Luke, 2026-11-07: a vertical stave, wood off either side; `CarveModel` says what happens,
## this draws it and takes presses). The stave stands on the workbench (`CarveStage`); click a row LEFT of its middle to
## cut its left edge, RIGHT of it for the right edge: left click a deep cut, right click a fine shave. The pattern (both
## profiles, which need not match) is laid on at the start: look, then click or Space to lift it and carve from memory;
## Space to look again (it costs). Enter HELD sets the piece down when it is done (Luke's play, 2026-11-09: one Enter
## ended it at once). Lifted, the pattern FADES to a ghost or to nothing (`pattern_fade_ms`, `pattern_ghost_pm`).

const STAGE_LINE: Color = Color(1, 1, 1, 0.92)

var model: CarveModel
var _stage: CarveStage = null
var _cuts_seen: int = 0
## When the pattern was last lifted (round time, ms; -1: not yet).
var _lifted_ms: int = -1


func _ready() -> void:
	theme = MinigameLook.theme()
	_stage = CarveStage.new()
	_stage.show_behind_parent = true   # drawn under the profiles
	add_child(_stage)
	move_child(_stage, 0)
	if model != null:
		_stage.build(model.rows())


func recipe() -> CarveParams:
	return params as CarveParams


func duration_ms() -> int:
	return recipe().duration_ms if recipe() != null else 0


func title() -> String:
	return "Carving: %s" % recipe().display_name if recipe() != null else "Carving"


func how_to() -> String:
	return "Click a row left or right of its middle to cut that side: left click deep, right click a fine shave   Space: the pattern   Hold Enter: set it down"


func summary(r: Dictionary) -> String:
	return "Off the line %d   Cuts %d   Looks %d   Best it could be %d%%" % [int(r.get("error", 0)), int(r.get("cuts", 0)),
		int(r.get("lays", 0)), int(r.get("ceiling_pm", 1000)) / 10]


func _new_model() -> void:
	model = CarveModel.start(seed_value, recipe())
	_cuts_seen = 0
	_lifted_ms = -1
	if _stage != null and is_node_ready():
		_stage.build(model.rows())


func _model_result() -> Dictionary:
	return model.result()


func _end_model() -> void:
	model.finish()


func is_over() -> bool:
	return model != null and model.done_ms >= 0


## An input `code` (a cut, LAY, LIFT, DONE) at `t_ms`: what the mouse and keys call, and what tests drive.
func press_at(t_ms: int, code: int) -> int:
	if state != State.PLAYING:
		return CarveModel.IGNORED
	record([t_ms, code])
	var ev: int = model.press(t_ms, code)
	if code == CarveModel.LIFT and not model.laid:
		_lifted_ms = t_ms
	_follow()
	queue_redraw()
	return ev


## The row under screen y `y` (-1: off the stave).
func row_at(y: float) -> int:
	if _stage == null or model == null:
		return -1
	for i: int in model.rows():
		if y >= _stage.screen_point(float(i), 0.0).y and y < _stage.screen_point(float(i + 1), 0.0).y:
			return i
	return -1


## The side of row `row` screen x `x` is on: 0 left of the middle of its wood as it is now (an asymmetric row's middle is
## not the stave's line), 1 right.
func side_at(x: float, row: int) -> int:
	var middle: float = float(model.right[row] - model.left[row]) * 0.5
	return 0 if x < _stage.screen_point(float(row) + 0.5, middle).x else 1


## The pattern on, or off (Space).
func toggle_pattern() -> void:
	if state == State.PLAYING and recipe().hide_outline > 0:
		press_at(elapsed_ms(), CarveModel.LIFT if model.laid else CarveModel.LAY)


## Show the cut the model landed last (a click, or one held through a swing).
func _follow() -> void:
	if model.cuts == _cuts_seen:
		return
	_cuts_seen = model.cuts
	if _stage == null:
		return
	var kind: int = model.last_cut_code / 1000
	_stage.show_stave(model.left, model.right, -1, 0)   # the stave as it is now, before the knife goes to it
	_stage.cut(model.last_cut_code % 1000, 0 if kind <= 2 else 1, kind == 1 or kind == 3)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or state != State.PLAYING:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	accept_event()
	if model.laid:
		press_at(elapsed_ms(), CarveModel.LIFT)   # no cuts while the pattern is on: a click lifts it
		return
	var row: int = row_at(mb.position.y)
	if row < 0:
		return
	var left: bool = side_at(mb.position.x, row) == 0
	var deep: bool = mb.button_index == MOUSE_BUTTON_LEFT
	var kind: int = (CarveModel.LEFT_DEEP if deep else CarveModel.LEFT_FINE) if left else (CarveModel.RIGHT_DEEP if deep else CarveModel.RIGHT_FINE)
	press_at(elapsed_ms(), kind + row)


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k != null and state == State.PLAYING and is_visible_in_tree() and finish_key(k):
		get_viewport().set_input_as_handled()   # Enter held sets it down (`SkillMinigame.finish_key`)
		return
	if k == null or not k.pressed or k.echo or state != State.PLAYING or not is_visible_in_tree():
		return
	if k.keycode == KEY_SPACE:
		toggle_pattern()
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		model.settle(elapsed_ms())
		_follow()
	if _stage != null and model != null:
		var hover_row: int = -1
		var hover_side: int = 0
		if state == State.PLAYING and not model.laid:
			var m: Vector2 = get_local_mouse_position()
			hover_row = row_at(m.y)
			if hover_row >= 0:
				hover_side = side_at(m.x, hover_row)
		_stage.show_stave(model.left, model.right, hover_row, hover_side)
	super(delta)


## Whether the profiles show now: with no pattern always; with one while it is on, and once the round is over.
func _finish_held() -> void:
	press_at(elapsed_ms(), CarveModel.DONE)


func finish_words() -> String:
	return "set it down"


## How strongly the profiles are drawn now (1 full, 0 not at all): the pattern on, or fading after it was lifted.
func profile_alpha() -> float:
	if model == null or recipe() == null:
		return 0.0
	var now: int = elapsed_ms() if state == State.PLAYING else model.last_t_ms
	return MinigameLook.pattern_alpha(_shows_profiles(), now, _lifted_ms, recipe().pattern_fade_ms, recipe().pattern_ghost_pm)


func _shows_profiles() -> bool:
	return recipe().hide_outline <= 0 or model.laid or state == State.DONE


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if model == null or _stage == null:
		_draw_frame("")
		return
	var alpha: float = profile_alpha()
	if alpha > 0.0:
		for side: int in 2:
			var line: PackedInt32Array = model.target_left if side == 0 else model.target_right
			var out_dir: float = -1.0 if side == 0 else 1.0
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in model.rows():
				pts.append(_stage.screen_point(float(i), out_dir * float(line[i])))
				pts.append(_stage.screen_point(float(i + 1), out_dir * float(line[i])))
			draw_polyline(pts, Color(0, 0, 0, 0.6 * alpha), 5.0)
			var line_color: Color = STAGE_LINE if not model.laid else MinigameLook.GOLD
			draw_polyline(pts, Color(line_color, line_color.a * alpha), 2.0)
	var hint: String = how_to()
	if state == State.PLAYING and model.laid:
		hint = "The pattern: look, then click or Space to lift it and carve from memory" + ("" if model.lays == 0 else "   (each look costs)")
	if state == State.PLAYING:
		MinigameLook.text(self, font, Vector2(0.0, size.y - 22.0), hint, 15, MinigameLook.HINT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_frame("Off the line %d   Cuts %d" % [model.error(), model.cuts] if _shows_profiles() else "Cuts %d   Best it can be %d%%" % [
		model.cuts, model.ceiling_pm() / 10])
