@abstract
class_name SkillMinigame extends Control
## A SKILLING MINIGAME, PLAYED: what every one of them (branch dodge, crack the rock, bellows then pour,
## shape to the outline) shares. `begin(seed, params)` starts a round; it ends when its time is up, and
## `round_finished` says what it scored as played (`live`) and as a server would replay its inputs
## (`replayed`, `SkillMinigames.play`); the two are the same by construction (the live game plays through
## the same model), and the end screen says so. Every input of the round is kept in `inputs`, ignored ones
## too: they are what the client sends for the server to replay. A subclass says how long a round is, keeps
## its model, draws it and turns presses into inputs (`record`).

signal round_finished(live: Dictionary, replayed: Dictionary)

enum State { READY, PLAYING, DONE }

const PANEL: Color = Color(0, 0, 0, 0.6)

var state: State = State.READY
var params: Resource
var seed_value: int = 0
## Every input of this round, flat (a time first, then its values).
var inputs: PackedInt32Array = PackedInt32Array()
var live_result: Dictionary = {}
var replayed_result: Dictionary = {}
var _started_usec: int = 0


## How long a round of `params` lasts.
@abstract func duration_ms() -> int
## Make the model for `seed_value` and `params`.
@abstract func _new_model() -> void
## The model's result now.
@abstract func _model_result() -> Dictionary
## What the round is called on screen.
@abstract func title() -> String
## What its end screen says beyond the score (its own counts).
@abstract func summary(r: Dictionary) -> String
## How to play it, before a round.
@abstract func how_to() -> String


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true


## A round of `p` from `s`, timed from now.
func begin(s: int, p: Resource) -> void:
	seed_value = s
	params = p
	inputs = PackedInt32Array()
	live_result = {}
	replayed_result = {}
	_new_model()
	_started_usec = Time.get_ticks_usec()
	state = State.PLAYING
	grab_focus()
	queue_redraw()


## Show `p`'s round from `s` without starting it (a lab picking what to play).
func preview(s: int, p: Resource) -> void:
	if state == State.PLAYING:
		return
	seed_value = s
	params = p
	_new_model()
	state = State.READY
	queue_redraw()


## Milliseconds since the round began.
func elapsed_ms() -> int:
	return int((Time.get_ticks_usec() - _started_usec) / 1000)


## Keep one input (its time first).
func record(values: Array[int]) -> void:
	for v: int in values:
		inputs.append(v)


## The round is over: what was played, and what a replay of its inputs scores.
func finish() -> void:
	if state != State.PLAYING:
		return
	state = State.DONE
	_end_model()
	live_result = _model_result()
	replayed_result = SkillMinigames.play(seed_value, params, inputs)
	queue_redraw()
	round_finished.emit(live_result, replayed_result)


## Anything the model needs to finish (run its last ticks).
func _end_model() -> void:
	pass


func _process(delta: float) -> void:
	if state == State.PLAYING and elapsed_ms() > duration_ms():
		finish()
	_animate(delta)
	if state != State.READY:
		queue_redraw()


## Presentation that moves on its own (flying pieces).
func _animate(_delta: float) -> void:
	pass


## The time bar, the title and the end or start panel: call last in `_draw`.
func _draw_frame(counts: String) -> void:
	var font: Font = get_theme_default_font()
	var w: float = size.x
	draw_string(font, Vector2(16.0, 30.0), title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	if params != null:
		var t: float = float(elapsed_ms() if state == State.PLAYING else (duration_ms() if state == State.DONE else 0))
		var left: float = 1.0 - clampf(t / float(maxi(1, duration_ms())), 0.0, 1.0)
		draw_rect(Rect2(16.0, 42.0, w - 32.0, 12.0), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(16.0, 42.0, (w - 32.0) * left, 12.0), Color(0.95, 0.85, 0.30))
		draw_string(font, Vector2(w - 380.0, 30.0), counts, HORIZONTAL_ALIGNMENT_RIGHT, 364.0, 20, Color.WHITE)
	if state == State.DONE:
		var same: bool = live_result == replayed_result
		_draw_panel(PackedStringArray([
			"Round over",
			summary(live_result),
			"Score %d%%" % [int(live_result.get("score_pm", 0)) / 10],
			("The server's replay agrees" if same else "REPLAY DISAGREES: %s" % str(replayed_result)),
		]))
	elif state == State.READY:
		_draw_panel(PackedStringArray([title(), how_to()]))


func _draw_panel(lines: PackedStringArray) -> void:
	var font: Font = get_theme_default_font()
	var h: float = 40.0 * lines.size() + 24.0
	var r: Rect2 = Rect2(size.x * 0.5 - 320.0, size.y * 0.30, 640.0, h)
	draw_rect(r, PANEL)
	for i: int in lines.size():
		draw_string(font, Vector2(r.position.x, r.position.y + 44.0 + 40.0 * i), lines[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26 if i == 0 else 20, Color.WHITE)
