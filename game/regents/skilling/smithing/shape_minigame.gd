class_name ShapeMinigame extends SkillMinigame
## SMITHING'S SHAPE TO THE OUTLINE, PLAYED (`ShapeModel` says what happens; this shows it and takes the strikes).
## The hot bar lies on the anvil (`AnvilStage`, a small 3D stage of the game's own models behind this panel), the
## part's outline drawn over it; strike a column to beat it down (a HEAVY strike spreads into its neighbors), TAP
## it to move it a little (finishing the line). The bar cools as you work: put it back in the fire. Match the
## outline: the closer, the better the part. (`MINIGAMES_PREP.md` §3.1, §5; Luke's M7 and M9, 2026-11-05.)
##
## WHICH BUTTONS TAP is a setting (Controls, "Smithing: the light tap"), so both can be tried: left click strikes
## in both; right click taps and R reheats, or Shift + left click taps and right click reheats. A round with no
## taps (`tap_drop` 0) reheats on right click in both.
##
## THE BANDS' RULES (Luke, 2026-11-05; `ShapeModel` says each), as played: the TEMPLATE (Space, or its button) shows
## the outline while it is on the bar; a click while it is on lifts it (no strike); HEATS, not a clock: the heats
## left and the best the part can still be are shown, and Enter (or its button) SETS THE PART DOWN, or QUENCHES it
## in a round with a quench (the window marked on the heat bar). RED heat shows on the bar and the heat bar.

const STAGE: PackedScene = preload("res://game/regents/skilling/smithing/anvil_stage.tscn")

## The setting that says which buttons tap.
const SETTING: StringName = &"regents_smith_buttons"
enum Buttons { RIGHT_TAPS, SHIFT_TAPS }
const BUTTON_CHOICES: PackedStringArray = [
	"Right click taps, R reheats",
	"Shift + left click taps, right click reheats",
]

const COLD: Color = Color(0.40, 0.38, 0.38)
const ANVIL: Color = Color(0.22, 0.22, 0.24)
const RED: Color = Color(0.70, 0.10, 0.06)
const PARCHMENT: Color = Color(0.93, 0.86, 0.70, 0.22)

var model: ShapeModel
var last_event: int = ShapeModel.IGNORED
var last_event_ms: int = -100000
var last_column: int = -1
var _acts_seen: int = 0
var _stage: AnvilStage = null
var _lay_button: Button = null
var _done_button: Button = null


## The setting, defined once (the HUD defines it at start so the settings panel lists it before a first round).
static func define_setting() -> void:
	if not Settings.entry(SETTING).is_empty():
		return
	Settings.define(SETTING, Settings.CONTROLS, "Smithing: the light tap", Settings.Kind.CHOICE, Buttons.RIGHT_TAPS, {
		"choices": BUTTON_CHOICES,
		"tooltip": "At the anvil, left click is the heavy strike. Which buttons give the light tap, and which put the bar back in the fire.",
	})


## Which buttons tap (`Buttons`).
static func buttons() -> int:
	define_setting()
	return int(Settings.get_value(SETTING))


func _ready() -> void:
	theme = MinigameLook.theme()
	define_setting()
	_stage = STAGE.instantiate() as AnvilStage
	_stage.show_behind_parent = true   # drawn under this panel's own readouts
	add_child(_stage)
	move_child(_stage, 0)
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	row.offset_top = 66.0
	row.offset_right = -16.0
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override(&"separation", 8)
	add_child(row)
	_lay_button = _button(row, toggle_template)
	_done_button = _button(row, set_down)
	if model != null:
		_show_stage()


func _button(row: HBoxContainer, act: Callable) -> Button:
	var b: Button = Button.new()
	b.focus_mode = Control.FOCUS_NONE   # Space and Enter are the round's keys, never a focused button's
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(act)
	b.visible = false
	row.add_child(b)
	return b


func part() -> ShapeParams:
	return params as ShapeParams


func duration_ms() -> int:
	return part().duration_ms if part() != null else 0


func title() -> String:
	return "Smithing: %s" % part().display_name if part() != null else "Smithing"


func has_taps() -> bool:
	return part() != null and part().tap_drop > 0


func has_template() -> bool:
	return part() != null and part().hide_outline > 0


func has_heats() -> bool:
	return part() != null and part().max_reheats > 0


func has_quench() -> bool:
	return part() != null and part().quench_hi_pm > 0


func how_to() -> String:
	var keys: String
	if not has_taps():
		keys = "Click a column to beat it down to the outline; right click or R to reheat"
	elif buttons() == Buttons.SHIFT_TAPS:
		keys = "Click: a heavy strike   Shift + click: a light tap   Right click or R: reheat"
	else:
		keys = "Left click: a heavy strike   Right click: a light tap   R: reheat"
	if has_template():
		keys += "   Space: the pattern"
	if has_heats():
		keys += "   Enter: %s" % ("quench" if has_quench() else "set it down")
	return keys


func summary(r: Dictionary) -> String:
	var s: String = "Off the outline %d   Reheats %d" % [r.get("error", 0), r.get("reheats", 0)]
	if has_heats():
		s += "   Best it could be %d%%" % (int(r.get("ceiling_pm", 1000)) / 10)
	if has_quench():
		var q: int = int(r.get("quench_pm", 0))
		s += "   Quench %s%d%%" % ["+" if q >= 0 else "", q / 10]
	return s


func _new_model() -> void:
	model = ShapeModel.start(seed_value, part())
	last_event = ShapeModel.IGNORED
	last_event_ms = -100000
	_acts_seen = 0
	if _stage != null:
		_stage.build(model.heights.size())
		_show_stage()


func _model_result() -> Dictionary:
	return model.result()


func is_over() -> bool:
	return model != null and model.is_over(elapsed_ms())


func shows_clock() -> bool:
	return not has_heats()


## The bar's area on screen (the 3D bar's front, at the height of its outline's middle), and one column's width.
func bar_rect() -> Rect2:
	if _stage != null and model != null and size.x > 0.0:
		var top: int = _top()
		var n: int = model.heights.size()
		var mid: float = float(top) * 0.5
		var a: Vector2 = _stage.screen_point(0.0, mid)
		var b: Vector2 = _stage.screen_point(float(n), mid)
		var hi: float = _stage.screen_point(float(n) * 0.5, float(top)).y
		var lo: float = _stage.screen_point(float(n) * 0.5, 0.0).y
		return Rect2(a.x, hi, b.x - a.x, lo - hi)
	return Rect2(size.x * 0.12, 110.0, size.x * 0.76, size.y - 230.0)


func column_at(x: float) -> int:
	var r: Rect2 = bar_rect()
	if x < r.position.x or x >= r.end.x or part() == null:
		return -2
	return int((x - r.position.x) / r.size.x * part().outline.size())


## A strike on `column` (ShapeModel.REHEAT_COLUMN: reheat; `ShapeModel.TAP` + c: a tap; `DONE`, `LAY`, `LIFT`) at
## `t_ms`: what clicks and keys call, and tests drive.
func strike_at(t_ms: int, column: int) -> int:
	if state != State.PLAYING:
		return ShapeModel.IGNORED
	record([t_ms, column])
	var ev: int = model.strike(t_ms, column)
	_follow()
	queue_redraw()
	return ev


## The template on the bar, or off it (Space, its button).
func toggle_template() -> void:
	if state == State.PLAYING and has_template():
		strike_at(elapsed_ms(), ShapeModel.LIFT if model.laid else ShapeModel.LAY)


## Set the part down (or quench it): the round ends (Enter, its button).
func set_down() -> void:
	if state == State.PLAYING and has_heats():
		strike_at(elapsed_ms(), ShapeModel.DONE)


## Show the strike the model landed last (a click, or one held through a swing).
func _follow() -> void:
	if model.acts == _acts_seen:
		return
	_acts_seen = model.acts
	last_event = model.last_act
	last_event_ms = model.last_act_ms
	last_column = model.last_act_column
	if _stage == null:
		return
	var tap: bool = last_column >= ShapeModel.TAP
	var c: int = last_column - ShapeModel.TAP if tap else last_column
	if last_event == ShapeModel.REHEAT:
		_stage.reheat()
	elif last_event == ShapeModel.CRACKED:
		_stage.crack(c)
	elif last_event == ShapeModel.STRUCK or last_event == ShapeModel.COLD:
		_show_stage()
		_stage.strike(c, not tap, last_event == ShapeModel.COLD, heat())


func _now() -> int:
	return elapsed_ms() if state == State.PLAYING else (model.done_ms if model.done_ms >= 0 else model.last_t_ms)


## How hot the bar is now: 1 fresh from the fire, 0 too cold to shape.
func heat() -> float:
	if model == null or part() == null:
		return 0.0
	return float(model.heat_pm(_now())) / 1000.0


func _in_fire() -> bool:
	return state == State.PLAYING and model != null and model.last_act == ShapeModel.REHEAT and elapsed_ms() < model.next_ok_ms


func _show_stage() -> void:
	var hover: int = column_at(get_local_mouse_position().x) if state == State.PLAYING and not model.laid else -1
	_stage.show_bar(model.heights, heat(), hover, _in_fire(), model.is_red(_now()) and not _in_fire())


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		model.settle(elapsed_ms())
		_follow()
	if _stage != null and model != null:
		_show_stage()
	if _lay_button != null:
		var playing: bool = state == State.PLAYING and model != null
		_lay_button.visible = playing and has_template()
		_done_button.visible = playing and has_heats()
		if playing:
			_lay_button.text = "Lift the pattern (Space)" if model.laid else "Lay the pattern on (Space)"
			_done_button.text = "Quench (Enter)" if has_quench() else "Set it down (Enter)"
	super(delta)


func _end_model() -> void:
	model.finish()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or state != State.PLAYING:
		return
	if model.laid and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		strike_at(elapsed_ms(), ShapeModel.LIFT)   # no strikes while the pattern is on: a click lifts it
		accept_event()
		return
	var mapping: int = buttons()
	var c: int = column_at(mb.position.x)
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if has_taps() and mapping == Buttons.RIGHT_TAPS:
			if c >= 0:
				strike_at(elapsed_ms(), ShapeModel.TAP + c)
		else:
			strike_at(elapsed_ms(), ShapeModel.REHEAT_COLUMN)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		if c >= 0:
			var tap: bool = has_taps() and mapping == Buttons.SHIFT_TAPS and mb.shift_pressed
			strike_at(elapsed_ms(), (ShapeModel.TAP if tap else 0) + c)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or state != State.PLAYING or not is_visible_in_tree():
		return
	if k.keycode == KEY_R:
		strike_at(elapsed_ms(), ShapeModel.REHEAT_COLUMN)
	elif k.keycode == KEY_SPACE and has_template():
		toggle_template()
	elif (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and has_heats():
		set_down()
	else:
		return
	get_viewport().set_input_as_handled()


func _top() -> int:
	var top: int = 1
	for h: int in model.heights:
		top = maxi(top, h)
	for h: int in model.outline:
		top = maxi(top, h)
	return top


## Whether the outline is shown now: always without a template; with one, while it is on, and once the round is over
## (to see how close it came).
func _shows_outline() -> bool:
	return not has_template() or model.laid or state == State.DONE


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if _stage == null:
		draw_rect(Rect2(0, 0, size.x, size.y), Color(0.12, 0.12, 0.14))
	if model == null:
		_draw_frame("")
		return
	if _stage == null:
		_draw_flat()
	elif _shows_outline():
		_draw_outline()
	_draw_heat(font)
	if has_heats():
		_draw_heats(font)
	if state == State.PLAYING:
		MinigameLook.text(self, font, Vector2(0.0, size.y - 52.0), how_to(), 15, MinigameLook.HINT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_frame("Off the outline %d   Strikes %d" % [model.error(), model.strikes] if _shows_outline() else "Strikes %d" % model.strikes)


## The heat bar: how hot the bar is, its red end (a strike there cracks it) and the quench's window, and what to do.
func _draw_heat(font: Font) -> void:
	var r: Rect2 = Rect2(size.x * 0.12, size.y - 118.0, size.x * 0.76, 12.0)
	var hot: float = heat()
	var t: int = _now()
	draw_rect(r.grow(2.0), Color(0, 0, 0, 0.55))
	var red_frac: float = clampf(float(part().red_ms) / float(part().heat_ms), 0.0, 1.0)
	if red_frac > 0.0:
		draw_rect(Rect2(r.position, Vector2(r.size.x * red_frac, r.size.y)), Color(RED, 0.35))
	var fill: Color = RED if model.is_red(t) else COLD.lerp(MinigameLook.EMBER, hot).lerp(MinigameLook.GOLD, hot * hot)
	draw_rect(Rect2(r.position, Vector2(r.size.x * hot, r.size.y)), fill)
	if has_quench():
		var lo: float = r.position.x + r.size.x * float(part().quench_lo_pm) / 1000.0
		var hi: float = r.position.x + r.size.x * float(part().quench_hi_pm) / 1000.0
		draw_rect(Rect2(lo, r.position.y - 5.0, hi - lo, r.size.y + 10.0), MinigameLook.GOLD, false, 2.0)
	var words: String
	var reheat_key: String = "right click or R" if not has_taps() or buttons() == Buttons.SHIFT_TAPS else "R"
	var left: int = model.reheats_left()
	if _in_fire():
		words = "In the fire..."
	elif model.laid and state == State.PLAYING:
		words = "The pattern is on: click or Space to lift it and strike"
	elif model.is_red(t):
		words = "Red: a strike now cracks it. %s to put it back in the fire" % (reheat_key.left(1).to_upper() + reheat_key.substr(1))
	elif hot > 0.0:
		words = "Hot" + ("   Quench when it is in the gold mark" if has_quench() and state == State.PLAYING else "")
	elif left == 0:
		words = "Cold, and no heats left"
	else:
		words = "Cold: %s to put it back in the fire" % reheat_key
	MinigameLook.text(self, font, Vector2(r.position.x, r.end.y + 28.0), words, 20,
		MinigameLook.GOLD if hot <= 0.0 or model.is_red(t) else MinigameLook.INK)


## Heats left (one mark each) and the best the part can still be, where a round on a clock has its time bar.
func _draw_heats(font: Font) -> void:
	var left: int = model.reheats_left()
	var x: float = 16.0
	MinigameLook.text(self, font, Vector2(x, 60.0), "Heats left", 16, MinigameLook.HINT)
	x += 90.0
	for i: int in part().max_reheats:
		var c: Vector2 = Vector2(x + 14.0 * i, 54.0)
		draw_circle(c, 5.0, MinigameLook.EMBER if i < left else Color(0, 0, 0, 0.5))
		draw_arc(c, 5.0, 0.0, TAU, 16, Color(0, 0, 0, 0.6), 1.0)
	MinigameLook.text(self, font, Vector2(x + 14.0 * part().max_reheats + 16.0, 60.0),
		"The best it can be now: %d%%" % (model.ceiling_pm() / 10), 16, MinigameLook.INK)


## The round's outline over the 3D bar: a dark line under a bright one, so it reads on hot and cold metal alike; with
## a template on, a pale plate behind it, as the pattern laid on the bar.
func _draw_outline() -> void:
	var n: int = model.outline.size()
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		pts.append(_stage.screen_point(float(i), float(model.outline[i])))
		pts.append(_stage.screen_point(float(i + 1), float(model.outline[i])))
	if has_template() and model.laid:
		var plate: PackedVector2Array = pts.duplicate()
		plate.append(_stage.screen_point(float(n), 0.0))
		plate.append(_stage.screen_point(0.0, 0.0))
		draw_colored_polygon(plate, PARCHMENT)
	draw_polyline(pts, Color(0, 0, 0, 0.6), 5.0)
	draw_polyline(pts, Color(1, 1, 1, 0.92), 2.0)
	var hover: int = column_at(get_local_mouse_position().x) if state == State.PLAYING and not model.laid else -1
	if hover >= 0:
		var a: Vector2 = _stage.screen_point(float(hover), 0.0)
		var b: Vector2 = _stage.screen_point(float(hover + 1), 0.0)
		draw_line(a + Vector2(0, 6), b + Vector2(0, 6), MinigameLook.GOLD, 3.0)


## The bar flat in 2D: without the stage (a panel not yet in the tree).
func _draw_flat() -> void:
	var r: Rect2 = bar_rect()
	draw_rect(Rect2(r.position.x - 20, r.end.y, r.size.x + 40, 40), ANVIL)
	var n: int = model.heights.size()
	var col_w: float = r.size.x / n
	var px: float = r.size.y / float(_top() + 4)
	var metal: Color = COLD.lerp(MinigameLook.EMBER, heat())
	for i: int in n:
		var h: float = model.heights[i] * px
		draw_rect(Rect2(r.position.x + i * col_w + 1.0, r.end.y - h, col_w - 2.0, h), metal)
	if not _shows_outline():
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in n:
		var y: float = r.end.y - model.outline[i] * px
		pts.append(Vector2(r.position.x + i * col_w, y))
		pts.append(Vector2(r.position.x + (i + 1) * col_w, y))
	draw_polyline(pts, Color.WHITE, 3.0)
