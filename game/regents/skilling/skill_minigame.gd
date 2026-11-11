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


## The round is over before its time is up (smithing's part set down, or cold with no heats left): it finishes now.
func is_over() -> bool:
	return false


## Whether the round runs on a clock (the time bar at the top); smithing's heats replace it (2026-11-05).
func shows_clock() -> bool:
	return true


## FINISHING IS A HOLD (Luke's play, 2026-11-09: one Enter set a part down at once, and parts were lost far off the
## outline): Enter, or the round's finish button, held `FINISH_HOLD_MS` ends it; a tap only says to hold. A round
## that finishes early (the anvil, the carve) calls `finish_key` with its keys and says what to do in `_finish_held`.
const FINISH_HOLD_MS: int = 600
const FINISH_TAP_SAID_MS: int = 1800
var _finish_down_ms: int = -1
var _finish_tapped_ms: int = -100000


## Enter down or up: true when `k` was Enter (the caller marks it handled).
func finish_key(k: InputEventKey) -> bool:
	if k == null or k.echo or (k.keycode != KEY_ENTER and k.keycode != KEY_KP_ENTER):
		return false
	if k.pressed:
		finish_hold_begin()
	else:
		finish_hold_end()
	return true


## The finish button (or Enter) went down.
func finish_hold_begin() -> void:
	if state == State.PLAYING and _finish_down_ms < 0:
		_finish_down_ms = Time.get_ticks_msec()


## Let go before the hold was done: nothing happens, and the round says to hold it.
func finish_hold_end() -> void:
	if _finish_down_ms >= 0:
		_finish_down_ms = -1
		_finish_tapped_ms = Time.get_ticks_msec()


## How far the hold has come, 0 to 1 (0: not held).
func finish_hold() -> float:
	if _finish_down_ms < 0:
		return 0.0
	return clampf(float(Time.get_ticks_msec() - _finish_down_ms) / float(FINISH_HOLD_MS), 0.0, 1.0)


## What the round does when the finish has been held long enough (the anvil sets the part down).
func _finish_held() -> void:
	pass


## What finishing the round is called on screen ("set it down").
func finish_words() -> String:
	return "finish"


func _process(delta: float) -> void:
	if _finish_down_ms >= 0 and (state != State.PLAYING or not is_visible_in_tree()):
		_finish_down_ms = -1
	elif _finish_down_ms >= 0 and finish_hold() >= 1.0:
		_finish_down_ms = -1
		_finish_held()
	if state == State.PLAYING and (elapsed_ms() > duration_ms() or is_over()):
		finish()
	_animate(delta)
	if state != State.READY:
		queue_redraw()


## Presentation that moves on its own (flying pieces).
func _animate(_delta: float) -> void:
	pass


## What Escape does while it is played, under the time bar ("" for nothing): the HUD sets it (Luke's play,
## 2026-11-03: a round started by mistake had no way out).
var leave_hint: String = ""
## A RUN's tally (Luke's M11: rounds back to back), under the leave hint ("" for none): the HUD sets it.
var run_line: String = ""
## WHAT THIS ROUND PAYS SO FAR (Luke, 2026-11-09: "all minigames should have woodcutting like overview where it shows
## how many rounds and the current pay off"): the HUD sets what AFK work makes in a round this long (`pay_afk`, in
## items), the item's name and the pay's two hot rules; the frame then says what the score so far is worth, as the
## server pays it (`SkillingRules.active_factor`). Rounds that make one graded thing (the anvil, the carve) set none.
var pay_afk: float = 0.0
var pay_item: String = ""
var pay_mult: float = 1.25
var pay_floor: float = 0.75


## The time bar, the title and the end or start panel: call last in `_draw`.
func _draw_frame(counts: String) -> void:
	var font: Font = get_theme_default_font()
	var w: float = size.x
	draw_string(font, Vector2(16.0, 30.0), title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	if params != null:
		var t: float = float(elapsed_ms() if state == State.PLAYING else (duration_ms() if state == State.DONE else 0))
		var left: float = 1.0 - clampf(t / float(maxi(1, duration_ms())), 0.0, 1.0)
		if shows_clock():
			draw_rect(Rect2(16.0, 42.0, w - 32.0, 12.0), Color(0, 0, 0, 0.35))
			draw_rect(Rect2(16.0, 42.0, (w - 32.0) * left, 12.0), Color(0.95, 0.85, 0.30))
		draw_string(font, Vector2(w - 380.0, 30.0), counts, HORIZONTAL_ALIGNMENT_RIGHT, 364.0, 20, Color.WHITE)
		var pay: String = pay_words()
		if not pay.is_empty():
			MinigameLook.text(self, font, Vector2(w - 480.0, 80.0), pay, 20, MinigameLook.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 464.0)
		if not run_line.is_empty():
			MinigameLook.text(self, font, Vector2(w - 480.0, 102.0), run_line, 16, MinigameLook.INK, HORIZONTAL_ALIGNMENT_RIGHT, 464.0)
		if state == State.PLAYING and not leave_hint.is_empty():
			draw_string(font, Vector2(16.0, 74.0), leave_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.75))
		_draw_finish_hold(font)
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


## "This round: about 1.6 Copper ore" from the score so far ("" when the HUD set no pay, or before a round).
func pay_words() -> String:
	if pay_afk <= 0.0 or pay_item.is_empty() or state == State.READY:
		return ""
	var r: Dictionary = live_result if state == State.DONE else _model_result()
	var got: float = pay_afk * SkillingRules.active_factor(pay_mult, pay_floor, int(r.get("score_pm", 0)))
	return "This round: about %.1f %s" % [got, pay_item]


## Where the finish's hold bar is drawn (its words above it): at the foot of the panel; a round may move it.
func finish_hold_rect() -> Rect2:
	return Rect2(size.x * 0.5 - 140.0, size.y - 86.0, 280.0, 10.0)


## The finish being held: a bar filling at the foot of the panel; a tap: say to hold it.
func _draw_finish_hold(font: Font) -> void:
	if state != State.PLAYING:
		return
	var held: float = finish_hold()
	var r: Rect2 = finish_hold_rect()
	if held > 0.0:
		MinigameLook.text(self, font, Vector2(r.position.x - 60.0, r.position.y - 8.0), "Hold to %s..." % finish_words(), 18,
			MinigameLook.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 120.0)
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(r.position, Vector2(r.size.x * held, r.size.y)), MinigameLook.GOLD)
	elif Time.get_ticks_msec() - _finish_tapped_ms < FINISH_TAP_SAID_MS:
		MinigameLook.text(self, font, Vector2(r.position.x - 60.0, r.position.y - 8.0), "Hold Enter to %s" % finish_words(), 18,
			MinigameLook.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 120.0)


func _draw_panel(lines: PackedStringArray) -> void:
	var font: Font = get_theme_default_font()
	var h: float = 40.0 * lines.size() + 24.0
	var r: Rect2 = Rect2(size.x * 0.5 - 320.0, size.y * 0.30, 640.0, h)
	draw_rect(r, PANEL)
	for i: int in lines.size():
		draw_string(font, Vector2(r.position.x, r.position.y + 44.0 + 40.0 * i), lines[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26 if i == 0 else 20, Color.WHITE)
