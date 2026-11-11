class_name SkinMinigame extends SkillMinigame
## SKINNING'S CUT LINE, PLAYED (`HERBALISM_HUNTING_PREP.md` H4, Luke 2026-11-07: "DRAG the knife along the cut line ...
## off the line tears the hide"; `SkinModel` says what happens, this takes the mouse and draws it). The carcass lies on
## the stage; a CUT LINE is marked on its flank. Press the left mouse button on the line's start (the gold ring) and
## DRAG the knife along it: the cut opens behind the knife, no faster than the knife cuts. Off the line, or run ahead
## of the cut, the knife TEARS the hide (a red rip; each one costs that line). Let go to stop safely, press again at the
## cut's end to go on. A line cut to its end, the knife lifts and the next line is marked. A round skins the WHOLE
## carcass (Luke, 2026-11-10): the better it is skinned, the more hides, up to the carcass's most.
##
## What is sent: the knife's place at most once a 50 ms tick while it is held (only when it moved), and each lift, as
## (time, x, y) in the hide's 1000 x 1000 (x = -1: lifted). `SkinStage` is the 3D stage behind it (the carcass, the
## floating knife) and says where the hide is on screen; without one (a panel not in the tree) it draws the round flat.

const STAGE: PackedScene = preload("res://game/regents/skilling/skinning/skin_stage.tscn")

const LINE: Color = Color(0.98, 0.92, 0.78)
const SEAM: Color = Color(0.30, 0.05, 0.05)
const SEAM_EDGE: Color = Color(0.86, 0.66, 0.58)
const TEAR: Color = Color(0.85, 0.12, 0.10)
const HIDE: Color = Color(0.55, 0.36, 0.22)

var model: SkinModel
var _stage: SkinStage = null
## The mouse button is held; the model lifted the knife at a line's end and the button has not been let go since.
var _held: bool = false
var _wait_release: bool = false
var _line_seen: int = 0
var _events_seen: int = 0
var _torn_seen: int = 0
var _last_sent_tick: int = -1
var _last_x: int = -1
var _last_y: int = -1
## Where the mouse is over the panel (for the knife), and this line's tears (hide units) and the lines done before.
var _mouse: Vector2 = Vector2.ZERO
var _rips: Array[Vector2i] = []
## The lines cut before this one (hide units), and this one's points (kept: the model draws the next as one ends).
var _done_lines: Array[PackedVector2Array] = []
var _line_pts: PackedVector2Array = PackedVector2Array()
var _clean_seen: int = 0
var _word: String = ""
var _word_color: Color = MinigameLook.INK
var _word_at: int = -100000


func _ready() -> void:
	theme = MinigameLook.theme()
	_stage = STAGE.instantiate() as SkinStage
	_stage.show_behind_parent = true   # drawn under this panel's own words
	add_child(_stage)
	move_child(_stage, 0)
	if params != null:
		_stage.set_carcass(node_of(skin_params()))


## The carcass whose round this is (for its model on the stage), or null.
static func node_of(p: SkinParams) -> NodeDef:
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame == p or (n.minigame is SkinParams and p != null and (n.minigame as SkinParams).display_name == p.display_name):
			return n
	return null


func skin_params() -> SkinParams:
	return params as SkinParams


func duration_ms() -> int:
	return skin_params().duration_ms if skin_params() != null else 0


func title() -> String:
	return "Skinning: %s" % skin_params().display_name if skin_params() != null else "Skinning"


func how_to() -> String:
	return "Hold the mouse on the gold ring and drag the knife along the line. Off the line, or too fast, it tears the hide"


func summary(r: Dictionary) -> String:
	return "Lines cut %d   Clean %d   Tears %d" % [int(r.get("lines", 0)), int(r.get("clean", 0)), int(r.get("torn", 0))]


func _new_model() -> void:
	model = SkinModel.start(seed_value, skin_params())
	_held = false
	_wait_release = false
	_line_seen = 0
	_events_seen = 0
	_torn_seen = 0
	_last_sent_tick = -1
	_last_x = -1
	_last_y = -1
	_rips.clear()
	_done_lines.clear()
	_line_pts = _points_now()
	_clean_seen = 0
	_word = ""
	if _stage != null:
		_stage.set_carcass(node_of(skin_params()))


func _model_result() -> Dictionary:
	return model.result()


func _end_model() -> void:
	model.finish()
	_held = false


func is_over() -> bool:
	return model != null and model.over


## The most inputs a round may send (the server's limit, `Minigame::score_eased`: a tick's worth and some to spare).
func max_inputs() -> int:
	return duration_ms() / SkinModel.TICK_MS + 60


## An input at `t_ms`: the knife in the hide at (x, y), or lifted (x = LIFT): what the mouse calls, and what tests drive.
func press_at(t_ms: int, x: int, y: int) -> int:
	if state != State.PLAYING or inputs.size() / 3 >= max_inputs():
		return SkinModel.IGNORED
	record([t_ms, x, y])
	var ev: int = model.press(t_ms, x, y)
	if x != SkinModel.LIFT:
		_last_sent_tick = t_ms / SkinModel.TICK_MS
		_last_x = x
		_last_y = y
	_follow(t_ms)
	queue_redraw()
	return ev


## Where on the panel hide point (x, y) is drawn.
func hide_to_panel(x: float, y: float) -> Vector2:
	if _stage != null and _stage.is_inside_tree():
		return _stage.hide_to_screen(x, y)
	var s: float = minf(size.x * 0.8, size.y * 2.0) / 1000.0
	return Vector2(size.x * 0.5 + (x - 500.0) * s, size.y * 0.55 + (y - 500.0) * s)


## The hide point (thousandths, clamped to the hide) under panel point `at`.
func panel_to_hide(at: Vector2) -> Vector2i:
	var o: Vector2 = hide_to_panel(0.0, 0.0)
	var ex: Vector2 = hide_to_panel(1000.0, 0.0) - o
	var ey: Vector2 = hide_to_panel(0.0, 1000.0) - o
	var d: Vector2 = at - o
	var det: float = ex.x * ey.y - ex.y * ey.x
	if absf(det) < 0.0001:
		return Vector2i(500, 500)
	var u: float = (d.x * ey.y - d.y * ey.x) / det
	var v: float = (ex.x * d.y - ex.y * d.x) / det
	return Vector2i(clampi(roundi(u * 1000.0), 0, 1000), clampi(roundi(v * 1000.0), 0, 1000))


## The mouse button went down or up over the panel.
func button(down: bool) -> void:
	if state != State.PLAYING or down == _held:
		return
	_held = down
	var t: int = elapsed_ms()
	if down:
		_wait_release = false
		var h: Vector2i = panel_to_hide(_mouse)
		press_at(t, h.x, h.y)
	elif model.down:
		press_at(t, SkinModel.LIFT, SkinModel.LIFT)
	_wait_release = false


## ONE LOOK AT THE ROUND at `t_ms`: the model run to now and shown FIRST, then the held knife's place sent. In that
## order (Luke, 2026-11-11: "at the end of a line you almost always result in a tear"): a place sent before the model
## had run was the input that ran the line's last tick, and so, the knife just lifted by the line's end, PRESSED IT
## DOWN AGAIN on the next line, where it tore every tick until the next press (the button's letting go sent nothing).
## Now a line's end is seen before anything is sent: the knife is out, and stays out, held or not, until the button is
## let go and pressed again.
func _look(t_ms: int) -> void:
	model.advance_to(t_ms)
	_follow(t_ms)
	_drag(t_ms)


## The knife held: its place sent once a tick at most, when it moved.
func _drag(t_ms: int) -> void:
	if not _held or _wait_release or not model.down:
		return
	var h: Vector2i = panel_to_hide(_mouse)
	if t_ms / SkinModel.TICK_MS <= _last_sent_tick or (h.x == _last_x and h.y == _last_y):
		return
	press_at(t_ms, h.x, h.y)


## Show what the model's ticks did since the last look (a cut, a tear, a line done).
func _follow(t_ms: int) -> void:
	if model.torn != _torn_seen:
		for k: int in model.torn - _torn_seen:
			_rips.append(Vector2i(model.kx, model.ky))
		_torn_seen = model.torn
		if _stage != null:
			_stage.tear()
		_say("Torn!", TEAR, t_ms)
	if model.line != _line_seen:
		_line_seen = model.line
		_rips.clear()
		_done_lines.append(_line_pts)
		_line_pts = _points_now()
		if _held:
			_wait_release = true   # the knife lifted itself: let go, then press at the next line's ring
		_say("Clean cut!" if model.clean > _clean_seen else "Cut through", MinigameLook.GOLD, t_ms)
		_clean_seen = model.clean
		if _stage != null:
			_stage.line_done()
	elif model.events != _events_seen and model.last_event == SkinModel.CUT and _stage != null:
		_stage.slice()
	_events_seen = model.events


## The line being cut, in hide units.
func _points_now() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for k: int in model.px.size():
		out.append(Vector2(model.px[k], model.py[k]))
	return out


func _say(word: String, color: Color, t_ms: int) -> void:
	_word = word
	_word_color = color
	_word_at = t_ms


func _gui_input(event: InputEvent) -> void:
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		_mouse = mm.position
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		_mouse = mb.position
		button(mb.pressed)
		accept_event()


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		var t: int = elapsed_ms()
		if is_visible_in_tree():
			_mouse = get_local_mouse_position()
		_look(t)
		if _stage != null:
			_stage.knife(_mouse, model.down, model.down and model.cuts_at(model.kx, model.ky))
	super(delta)


func _counts() -> String:
	if model == null:
		return ""
	return "Lines %d   Clean %d" % [model.lines, model.clean]


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if _stage == null:
		_draw_flat()
	if model != null and state != State.READY:
		_draw_cut(font)
	if model != null and state == State.PLAYING:
		var t: int = elapsed_ms()
		if not _word.is_empty() and t - _word_at < 900:
			MinigameLook.text(self, font, Vector2(0.0, size.y * 0.24 - (t - _word_at) * 0.03), _word, 32, _word_color, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		var hint: String = "Let go, then press on the gold ring" if _wait_release else "Hold the mouse and drag the knife along the line; off it tears"
		MinigameLook.text(self, font, Vector2(0.0, size.y - 20.0), hint, 15, MinigameLook.HINT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_frame(_counts())


## The cut drawn over the carcass: the lines done (dark seams), this line's cut (an open seam) and what is left of it
## (pale dashes over a faint band as wide as the knife may stray), its start ring (when the knife is out), the tip, and
## each tear (a red rip).
func _draw_cut(font: Font) -> void:
	var p: SkinParams = skin_params()
	var s: float = (hide_to_panel(1000.0, 500.0) - hide_to_panel(0.0, 500.0)).length() / 1000.0
	for done: PackedVector2Array in _done_lines:
		var on_panel: PackedVector2Array = PackedVector2Array()
		for q: Vector2 in done:
			on_panel.append(hide_to_panel(q.x, q.y))
		draw_polyline(on_panel, Color(SEAM, 0.55), 5.0, true)
	var tip: Vector2i = model.tip()
	var cut: PackedVector2Array = PackedVector2Array()
	for k: int in model.seg + 1:
		cut.append(hide_to_panel(model.px[k], model.py[k]))
	cut.append(hide_to_panel(tip.x, tip.y))
	var ahead: PackedVector2Array = PackedVector2Array([hide_to_panel(tip.x, tip.y)])
	for k: int in range(model.seg + 1, model.px.size()):
		ahead.append(hide_to_panel(model.px[k], model.py[k]))
	draw_polyline(ahead, Color(LINE, 0.10), maxf(2.0, p.near * 2.0 * s), true)
	_dashes(ahead, Color(LINE, 0.9), 2.5)
	if cut.size() >= 2 and (model.seg > 0 or model.f > 0):
		draw_polyline(cut, SEAM_EDGE, 7.0, true)
		draw_polyline(cut, SEAM, 4.0, true)
	var tp: Vector2 = hide_to_panel(tip.x, tip.y)
	if not model.down and state == State.PLAYING:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_arc(tp, 10.0 + 4.0 * pulse, 0.0, TAU, 28, MinigameLook.GOLD, 3.0, true)
		MinigameLook.text(self, font, tp + Vector2(-60.0, -22.0), "Start here", 16, MinigameLook.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	else:
		draw_circle(tp, 4.0, MinigameLook.GOLD)
	var end: Vector2 = hide_to_panel(model.px[model.px.size() - 1], model.py[model.py.size() - 1])
	draw_circle(end, 3.5, Color(LINE, 0.9))
	for k: int in _rips.size():
		var r: Vector2 = hide_to_panel(_rips[k].x, _rips[k].y)
		var j: float = float((k * 7919) % 13) - 6.0
		draw_polyline(PackedVector2Array([r + Vector2(-7.0, -3.0 + j * 0.3), r + Vector2(-2.0, 3.0), r + Vector2(2.0, -3.0),
			r + Vector2(7.0, 3.0 - j * 0.3)]), TEAR, 2.5, true)


## A dashed line along `pts`.
func _dashes(pts: PackedVector2Array, color: Color, width: float) -> void:
	var on: bool = true
	var left: float = 10.0
	for k: int in pts.size() - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var d: float = a.distance_to(b)
		var at: float = 0.0
		while at < d:
			var step: float = minf(left, d - at)
			if on:
				draw_line(a.lerp(b, at / d), a.lerp(b, (at + step) / d), color, width, true)
			at += step
			left -= step
			if left <= 0.0:
				on = not on
				left = 10.0 if on else 7.0


## The round flat (no stage): a hide on the ground.
func _draw_flat() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.38, 0.22))
	var a: Vector2 = hide_to_panel(40.0, 280.0)
	var b: Vector2 = hide_to_panel(960.0, 720.0)
	draw_rect(Rect2(a, b - a), HIDE)
	if model != null and model.down:
		draw_line(_mouse, _mouse + Vector2(26.0, -40.0), Color(0.8, 0.5, 0.3), 4.0)
