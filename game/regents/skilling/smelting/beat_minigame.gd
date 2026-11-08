class_name BeatMinigame extends SkillMinigame
## SMELTING AS A RHYTHM TRACK, PLAYED (Luke, 2026-11-07: "Full rhythm track"; `BeatModel` says what happens, this
## draws it and takes presses). The beat is knocked on the furnace from the start (a count-in, then the track); the
## notes come along the track from the right to the bellows' mark at the left; press Space or click as each one
## reaches it, and hold a long one to its end. A press on no note is wasted breath. Then the pour, as before: hold to
## tilt, let go at the mold's line.
## The 3D stage behind is smelting's own (`SmeltStage`): the fire burns with how the track is going, the bellows pump
## on each note, close slowly on a long draw, sputter on a wasted press; the crucible pours into the mold.

const STAGE: PackedScene = preload("res://game/regents/skilling/smelting/smelt_stage.tscn")

const NOTE: Color = Color(1.0, 0.62, 0.22)
const NOTE_DIM: Color = Color(0.55, 0.45, 0.38, 0.6)
## A slag note (band 2's test): dull and gray-green, a square, skimmed with the second button.
const SLAG: Color = Color(0.55, 0.62, 0.5)
const LANE: Color = Color(0.0, 0.0, 0.0, 0.45)
const METAL: Color = Color(1.0, 0.70, 0.25)
const BURN: Color = Color(0.95, 0.25, 0.20)
## How far ahead the track shows, in beats.
const AHEAD_BEATS: int = 4
## How long a word over the bellows' mark stays.
const WORD_MS: int = 450

var model: BeatModel
var _down: bool = false
var _stage: SmeltStage = null
## The last beat knocked (-1: none yet), the notes already called missed, and the last word shown.
var _knocked: int = -1
var _called: PackedByteArray = PackedByteArray()
var _word: String = ""
var _word_color: Color = Color.WHITE
var _word_at: int = -100000


func _ready() -> void:
	theme = MinigameLook.theme()
	_stage = STAGE.instantiate() as SmeltStage
	_stage.show_behind_parent = true   # drawn under the track
	add_child(_stage)
	move_child(_stage, 0)


func recipe() -> BeatParams:
	return params as BeatParams


func duration_ms() -> int:
	return BeatModel.duration_ms(recipe()) if recipe() != null else 0


func title() -> String:
	return "Smelting: %s" % recipe().display_name if recipe() != null else "Smelting"


func how_to() -> String:
	return "Press Space or click as each ember reaches the bellows; hold the long ones. Then hold to pour, let go at the line"


func summary(r: Dictionary) -> String:
	return "On the beat %d of %d   Close %d   Wasted %d   Pour %d%%" % [int(r.get("perfect", 0)), int(r.get("notes", 0)),
		int(r.get("good", 0)), int(r.get("strays", 0)), int(r.get("pour_pm", 0)) / 10]


func _new_model() -> void:
	model = BeatModel.start(seed_value, recipe())
	_down = false
	_knocked = -1
	_called = PackedByteArray()
	_called.resize(model.note_t.size())
	_word = ""
	if _stage != null:
		_stage.draw_on(false)


func _model_result() -> Dictionary:
	return model.result()


func _end_model() -> void:
	model.finish()
	if _stage != null:
		_stage.draw_on(false)


## An input `code` (DOWN, UP) at `t_ms`: what the keys and the mouse call, and what tests drive.
func press_at(t_ms: int, code: int) -> int:
	if state != State.PLAYING:
		return BeatModel.IGNORED
	record([t_ms, code])
	var ev: int = model.press(t_ms, code)
	if ev == BeatModel.PERFECT or ev == BeatModel.GOOD:
		_say("Perfect" if ev == BeatModel.PERFECT else "Good", MinigameLook.GOLD if ev == BeatModel.PERFECT else MinigameLook.INK, t_ms)
		if _stage != null:
			if model.holding >= 0:
				_stage.draw_on(true)
			else:
				_stage.pump()
	elif ev == BeatModel.STRAY:
		_say("Wasted breath", BURN, t_ms)
		if _stage != null:
			_stage.sputter()
	elif ev == BeatModel.RELEASED and _stage != null:
		_stage.draw_on(false)
	queue_redraw()
	return ev


## The button went down or up (Space, the mouse).
func button(down: bool) -> void:
	if state != State.PLAYING or down == _down:
		return
	_down = down
	press_at(elapsed_ms(), BeatModel.DOWN if down else BeatModel.UP)


func _say(word: String, color: Color, t_ms: int) -> void:
	_word = word
	_word_color = color
	_word_at = t_ms


## The second button (F, the right mouse button) skims slag (band 2's test).
func skim() -> void:
	if state == State.PLAYING:
		var t: int = elapsed_ms()
		model.advance_to(t)
		var ev: int = press_at(t, BeatModel.SKIM)
		if ev == BeatModel.PERFECT or ev == BeatModel.GOOD:
			_say("Skimmed", MinigameLook.GOLD, t)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		button(mb.pressed)
		accept_event()
	elif mb != null and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and state == State.PLAYING and recipe().slag_pm > 0:
		skim()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or k.echo or state != State.PLAYING or not is_visible_in_tree():
		return
	if k.keycode == KEY_F and recipe().slag_pm > 0:
		if k.pressed:
			skim()
		get_viewport().set_input_as_handled()
		return
	if k.keycode != KEY_SPACE:
		return
	button(k.pressed)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		var t: int = elapsed_ms()
		model.advance_to(t)
		_keep_time(t)
	if _stage != null and model != null:
		var now: int = elapsed_ms() if state == State.PLAYING else duration_ms()
		_stage.show_melt(model.heat_now(now), model.fill, model.pouring, model.on_track(now))
		if _stage.drawing and model.holding < 0:
			_stage.draw_on(false)   # a long draw held through its end
	super(delta)


## The beat knocked as it comes (a bar's first brighter), and a note let past called missed.
func _keep_time(t: int) -> void:
	var p: BeatParams = recipe()
	var k: int = mini(t / p.beat_ms, p.lead_beats + p.beats - 1)
	while _knocked < k:
		_knocked += 1
		if _stage != null:
			_stage.knock(posmod(_knocked - p.lead_beats, 4) == 0)
	for j: int in model.note_t.size():
		if _called[j] == 0 and model.got[j] < 0 and model.hit[j] == 0 and t > model.note_t[j] + p.good_ms:
			_called[j] = 1
			_say("Missed", MinigameLook.HINT, t)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if _stage == null:
		draw_rect(Rect2(0, 0, size.x, size.y), Color(0.13, 0.11, 0.10))
	if model == null:
		_draw_frame("")
		return
	var p: BeatParams = recipe()
	var t: int = elapsed_ms() if state == State.PLAYING else (duration_ms() if state == State.DONE else 0)
	var on_track: bool = model.on_track(t)
	# The track, low across the panel: the bellows' mark at the left, the notes coming from the right.
	var lane: Rect2 = Rect2(70.0, size.y - 170.0, size.x - 200.0, 70.0)
	var mark_x: float = lane.position.x + 70.0
	var px_per_ms: float = (lane.end.x - mark_x) / float(maxi(1, AHEAD_BEATS * p.beat_ms))
	var x_of: Callable = func(at: int) -> float: return mark_x + float(at - t) * px_per_ms
	var mid_y: float = lane.get_center().y
	draw_rect(lane, LANE if on_track else Color(0, 0, 0, 0.2))
	# The beats as lines, a bar's first brighter.
	var first: int = maxi(0, (t - 400) / p.beat_ms)
	for b: int in range(first, mini(p.lead_beats + p.beats, first + AHEAD_BEATS + 3) + 1):
		var x: float = float(x_of.call(b * p.beat_ms))
		if x < lane.position.x or x > lane.end.x:
			continue
		var bar: bool = posmod(b - p.lead_beats, 4) == 0
		draw_line(Vector2(x, lane.position.y + 6.0), Vector2(x, lane.end.y - 6.0), Color(1, 1, 1, 0.35 if bar else 0.12), 3.0 if bar else 1.5)
	# The notes: an ember for a press, a glowing bar for a long draw (to its end).
	for j: int in model.note_t.size():
		var x0: float = float(x_of.call(model.note_t[j]))
		var x1: float = float(x_of.call(model.note_end[j]))
		if x1 < lane.position.x - 30.0 or x0 > lane.end.x - 10.0:
			continue
		var played: bool = model.got[j] >= 0 or j == model.holding
		if played and model.note_end[j] == model.note_t[j]:
			continue   # a press played: it went into the fire
		var missed: bool = not played and t > model.note_t[j] + p.good_ms
		var c: Color = NOTE_DIM if missed or (model.got[j] >= 0 and model.got[j] < 1000 and model.note_end[j] > model.note_t[j]) else NOTE
		if model.note_end[j] > model.note_t[j]:
			var from_x: float = maxf(x0, mark_x) if j == model.holding else maxf(x0, lane.position.x)
			var to_x: float = minf(x1, lane.end.x)   # kept on the track
			draw_rect(Rect2(from_x, mid_y - 12.0, maxf(0.0, to_x - from_x), 24.0), Color(c, 0.75))
			if x1 <= lane.end.x:
				draw_circle(Vector2(x1, mid_y), 10.0, c)
			if j != model.holding and not played:
				draw_circle(Vector2(x0, mid_y), 20.0, c)
		elif model.is_slag(j):
			var sc: Color = Color(SLAG, 0.4) if missed else SLAG
			draw_rect(Rect2(x0 - 15.0, mid_y - 15.0, 30.0, 30.0), sc)
			draw_rect(Rect2(x0 - 15.0, mid_y - 15.0, 30.0, 30.0), Color(0.2, 0.22, 0.18), false, 2.0)
		else:
			draw_circle(Vector2(x0, mid_y), 18.0, c)
			draw_circle(Vector2(x0, mid_y), 9.0, Color(1, 0.9, 0.6, 0.9 if not missed else 0.3))
	# The bellows' mark.
	draw_line(Vector2(mark_x, lane.position.y - 10.0), Vector2(mark_x, lane.end.y + 10.0), MinigameLook.GOLD if _down and on_track else MinigameLook.INK, 4.0)
	draw_arc(Vector2(mark_x, mid_y), 24.0, 0.0, TAU, 32, MinigameLook.INK, 2.0)
	# The count-in, big over the track.
	if on_track and t < p.lead_beats * p.beat_ms and state == State.PLAYING:
		var left: int = p.lead_beats - t / p.beat_ms
		MinigameLook.text(self, font, Vector2(0.0, lane.position.y - 40.0), str(left), 56, MinigameLook.GOLD, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if t - _word_at < WORD_MS and not _word.is_empty():
		MinigameLook.text(self, font, Vector2(mark_x - 80.0, lane.position.y - 18.0), _word, 26, _word_color, HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	# The fire (how the track is going), left; the mold, right.
	var gauge: Rect2 = Rect2(20.0, 100.0, 30.0, size.y - 300.0)
	draw_rect(gauge, Color(0.2, 0.18, 0.17, 0.8))
	var heat: float = clampf(float(model.heat_now(t)) / 1000.0, 0.0, 1.0)
	draw_rect(Rect2(gauge.position.x + 6.0, gauge.end.y - heat * gauge.size.y, gauge.size.x - 12.0, heat * gauge.size.y), MinigameLook.EMBER)
	var mold: Rect2 = Rect2(size.x - 70.0, 100.0, 46.0, size.y - 300.0)
	draw_rect(mold, Color(0.25, 0.23, 0.22, 0.85))
	var fy: float = mold.end.y - clampf(float(model.fill) / 1000.0, 0.0, 1.0) * mold.size.y
	draw_rect(Rect2(mold.position.x + 8.0, fy, mold.size.x - 16.0, mold.end.y - fy), METAL)
	var ty: float = mold.end.y - float(model.target) / 1000.0 * mold.size.y
	draw_line(Vector2(mold.position.x - 16, ty), Vector2(mold.end.x + 16, ty), Color.WHITE, 3.0)
	MinigameLook.text(self, font, Vector2(mold.position.x - 4, mold.end.y + 28), "Pour", 20, MinigameLook.INK if not on_track else MinigameLook.HINT)
	if model.fill > 1000:
		MinigameLook.text(self, font, Vector2(mold.position.x - 60, mold.position.y - 14), "Spilled!", 24, BURN)
	var hint: String = "Press as each ember reaches the bellows; hold the long ones"
	if p.slag_pm > 0:
		hint += "; F or right click skims the gray slag"
	if not on_track:
		if not model.pour_ready(t):
			hint = "Hands off the bellows... ready to pour"
		elif model.pouring:
			hint = "Pouring... let go at the line"
		elif model.poured:
			hint = "Hold again to top it up, or leave it"
		else:
			hint = "Hold Space or the mouse to pour"
	MinigameLook.text(self, font, Vector2(0, size.y - 24), hint, 20, MinigameLook.INK, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	_draw_frame("Track %d%%   Pour %d%%" % [model.track_score() / 10, model.pour_score() / 10])
