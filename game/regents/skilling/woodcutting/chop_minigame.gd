class_name ChopMinigame extends Control
## WOODCUTTING'S BRANCH DODGE, PLAYED (`ChopModel` says what happens; this draws it and takes the
## presses). A trunk in the middle, the woodcutter beside it; A / Left or a click on the left half
## chops from the left, D / Right or a click on the right half from the right. A branch at your head
## on the side you chop from hits you: the swing is lost and you are staggered.
##
## `begin(seed, tree)` starts a round; it ends when the tree's time runs out, and `round_finished`
## says what the round scored: as played (`live`) and as a server would replay its inputs (`replayed`);
## the two are the same by construction (both go through `ChopModel.chop`), and the end screen says so.
## Every press of the round is kept in `inputs` (time, side), ignored ones too: they are what a client
## will send for the server to replay.

signal round_finished(live: Dictionary, replayed: Dictionary)

enum State { READY, PLAYING, DONE }

const SEGMENT_H: float = 64.0
const TRUNK_W: float = 92.0
const BRANCH_LEN: float = 112.0
const HUD_TOP: float = 70.0

const SKY: Color = Color(0.55, 0.72, 0.86)
const GROUND: Color = Color(0.33, 0.45, 0.24)
const BARK: Color = Color(0.45, 0.30, 0.18)
const BARK_DARK: Color = Color(0.36, 0.23, 0.13)
const HEAD_TINT: Color = Color(0.56, 0.38, 0.22)
const LEAVES: Color = Color(0.22, 0.48, 0.20)
const SHIRT: Color = Color(0.70, 0.20, 0.18)
const HURT: Color = Color(1.0, 0.35, 0.35)

var state: State = State.READY
var model: ChopModel
var tree: ChopParams
var seed_value: int = 0
## Every press of this round, flat pairs: milliseconds since it began, then the side.
var inputs: PackedInt32Array = PackedInt32Array()
var live_result: Dictionary = {}
var replayed_result: Dictionary = {}
## What the last press did (ChopModel.CLEAN / HIT / IGNORED) and when, for the swing and the ouch.
var last_event: int = ChopModel.IGNORED
var last_event_ms: int = -100000

var _started_usec: int = 0
## Chopped pieces flying off.
var _flying: Array[Piece] = []


## A chopped piece in the air: where, how fast, turned how far and how fast (pixels, seconds, radians).
class Piece:
	var pos: Vector2
	var vel: Vector2
	var angle: float = 0.0
	var spin: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## A round of `p` from `s`, timed from now.
func begin(s: int, p: ChopParams) -> void:
	seed_value = s
	tree = p
	model = ChopModel.start(s, p)
	inputs = PackedInt32Array()
	live_result = {}
	replayed_result = {}
	last_event = ChopModel.IGNORED
	last_event_ms = -100000
	_flying.clear()
	_started_usec = Time.get_ticks_usec()
	state = State.PLAYING
	grab_focus()
	queue_redraw()


## Show tree `p`'s trunk from `s` without starting a round: what a lab shows when the tree changes.
func preview(s: int, p: ChopParams) -> void:
	if state == State.PLAYING:
		return
	seed_value = s
	tree = p
	model = ChopModel.start(s, p)
	state = State.READY
	_flying.clear()
	queue_redraw()


## Milliseconds since the round began.
func elapsed_ms() -> int:
	return int((Time.get_ticks_usec() - _started_usec) / 1000)


## A press from `side` at `t_ms` into the round: what the keys and clicks call, and what tests drive.
func press_at(t_ms: int, side: int) -> int:
	if state != State.PLAYING:
		return ChopModel.IGNORED
	inputs.append(t_ms)
	inputs.append(side)
	var ev: int = model.chop(t_ms, side)
	if ev != ChopModel.IGNORED:
		last_event = ev
		last_event_ms = t_ms
	if ev == ChopModel.CLEAN:
		_throw_piece(side)
	queue_redraw()
	return ev


## The round is over: score it as played and as replayed from its inputs.
func finish() -> void:
	if state != State.PLAYING:
		return
	state = State.DONE
	live_result = model.result()
	replayed_result = ChopModel.play(seed_value, tree, inputs)
	queue_redraw()
	round_finished.emit(live_result, replayed_result)


func _process(delta: float) -> void:
	if state == State.PLAYING and elapsed_ms() > tree.duration_ms:
		finish()
	for i: int in range(_flying.size() - 1, -1, -1):
		var f: Piece = _flying[i]
		f.pos += f.vel * delta
		f.vel.y += 1400.0 * delta
		f.angle += f.spin * delta
		if f.pos.y > size.y + 200.0:
			_flying.remove_at(i)
	if state != State.READY:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		press_at(elapsed_ms(), ChopModel.SIDE_LEFT if mb.position.x < size.x * 0.5 else ChopModel.SIDE_RIGHT)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or state != State.PLAYING:
		return
	if k.physical_keycode == KEY_A or k.keycode == KEY_LEFT:
		press_at(elapsed_ms(), ChopModel.SIDE_LEFT)
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_D or k.keycode == KEY_RIGHT:
		press_at(elapsed_ms(), ChopModel.SIDE_RIGHT)
		get_viewport().set_input_as_handled()


func _throw_piece(side: int) -> void:
	# Knocked away from the axe: chopped from the left, it flies right.
	var dir: float = 1.0 if side == ChopModel.SIDE_LEFT else -1.0
	var p: Piece = Piece.new()
	p.pos = Vector2(_trunk_x() + TRUNK_W * 0.5, _ground_y() - SEGMENT_H * 0.5)
	p.vel = Vector2(dir * 520.0, -380.0)
	p.spin = dir * 7.0
	_flying.append(p)


func _ground_y() -> float:
	return size.y * 0.84


func _trunk_x() -> float:
	return size.x * 0.5 - TRUNK_W * 0.5


func _draw() -> void:
	var w: float = size.x
	var gy: float = _ground_y()
	var tx: float = _trunk_x()
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(0, 0, w, size.y), SKY)
	draw_rect(Rect2(0, gy, w, size.y - gy), GROUND)
	draw_rect(Rect2(tx - 14.0, gy - 6.0, TRUNK_W + 28.0, 14.0), BARK_DARK)   # the stump's flare
	if model != null:
		_draw_trunk(tx, gy)
		_draw_woodcutter(tx, gy, font)
	for f: Piece in _flying:
		draw_set_transform(f.pos, f.angle)
		draw_rect(Rect2(-TRUNK_W * 0.5, -SEGMENT_H * 0.5, TRUNK_W, SEGMENT_H), BARK)
		draw_set_transform(Vector2.ZERO)
	_draw_hud(w, font)


func _draw_trunk(tx: float, gy: float) -> void:
	var j: int = 0
	while model.cut + j < model.segments.size():
		var top: float = gy - (j + 1) * SEGMENT_H
		if top + SEGMENT_H < HUD_TOP:
			break
		var colour: Color = HEAD_TINT if j == 1 else (BARK if j % 2 == 0 else BARK_DARK.lerp(BARK, 0.5))
		draw_rect(Rect2(tx, top, TRUNK_W, SEGMENT_H), colour)
		draw_line(Vector2(tx + 10.0, top + 2.0), Vector2(tx + TRUNK_W - 10.0, top + 2.0), BARK_DARK, 2.0)
		var b: int = model.segments[model.cut + j]
		if b != ChopModel.BRANCH_NONE:
			# The bottom piece's branch broke off as it came down: a stub. Above it, a whole branch.
			var length: float = 18.0 if j == 0 else BRANCH_LEN
			var mid: float = top + SEGMENT_H * 0.5
			var x0: float = tx - length if b == ChopModel.BRANCH_LEFT else tx + TRUNK_W
			draw_rect(Rect2(x0, mid - 8.0, length, 16.0), BARK_DARK)
			if j > 0:
				var tip: float = x0 if b == ChopModel.BRANCH_LEFT else x0 + length
				draw_circle(Vector2(tip, mid - 6.0), 26.0, LEAVES)
		j += 1


func _draw_woodcutter(tx: float, gy: float, font: Font) -> void:
	var left: bool = model.side == ChopModel.SIDE_LEFT
	var x: float = tx - 62.0 if left else tx + TRUNK_W + 62.0
	var t: int = elapsed_ms() if state == State.PLAYING else model.last_t_ms
	var since: int = t - last_event_ms
	var hurt: bool = last_event == ChopModel.HIT and since < tree.stagger_ms
	var shake: float = sin(float(since) * 0.08) * 4.0 if hurt else 0.0
	var body: Color = HURT if hurt else SHIRT
	draw_rect(Rect2(x - 14.0 + shake, gy - 70.0, 28.0, 70.0), body)
	draw_circle(Vector2(x + shake, gy - 86.0), 15.0, Color(0.95, 0.80, 0.65))
	# The axe: raised, swung down onto the bottom piece over the first part of a swing, raised again.
	var swing: float = 1.0
	if last_event == ChopModel.CLEAN and since >= 0 and since < tree.swing_ms:
		var k: float = float(since) / float(tree.swing_ms)
		swing = k / 0.35 if k < 0.35 else 1.0 - (k - 0.35) / 0.65
		swing = 1.0 - clampf(swing, 0.0, 1.0)
	var toward: float = 1.0 if left else -1.0
	var shoulder: Vector2 = Vector2(x + toward * 10.0 + shake, gy - 62.0)
	var angle: float = lerpf(-1.25, 0.15, 1.0 - swing) * toward
	var head: Vector2 = shoulder + Vector2(toward * 58.0, 0.0).rotated(angle)
	draw_line(shoulder, head, Color(0.55, 0.40, 0.25), 5.0)
	draw_rect(Rect2(head - Vector2(8.0, 10.0), Vector2(16.0, 20.0)), Color(0.75, 0.78, 0.80))
	if hurt:
		draw_string(font, Vector2(x - 26.0, gy - 112.0), "Ouch!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, HURT)


func _draw_hud(w: float, font: Font) -> void:
	var title: String = tree.display_name if tree != null else "Woodcutting"
	draw_string(font, Vector2(16.0, 30.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	if model != null:
		var left: float = 1.0 - clampf(float(elapsed_ms() if state == State.PLAYING else tree.duration_ms) / float(tree.duration_ms), 0.0, 1.0)
		draw_rect(Rect2(16.0, 42.0, w - 32.0, 12.0), Color(0, 0, 0, 0.35))
		draw_rect(Rect2(16.0, 42.0, (w - 32.0) * left, 12.0), Color(0.95, 0.85, 0.30))
		var line: String = "Logs %d   Combo %d   Hits %d" % [model.clean, model.combo, model.hits]
		draw_string(font, Vector2(w - 360.0, 30.0), line, HORIZONTAL_ALIGNMENT_RIGHT, 344.0, 20, Color.WHITE)
	if state == State.DONE:
		var r: Dictionary = live_result
		var same: bool = live_result == replayed_result
		var lines: PackedStringArray = PackedStringArray([
			"Round over",
			"Logs %d   Hits %d   Best combo %d" % [r["clean"], r["hits"], r["best_combo"]],
			"Score %d%%" % [int(r["score_pm"]) / 10],
			("The server's replay agrees" if same else "REPLAY DISAGREES: %s" % str(replayed_result)),
		])
		_draw_panel(lines, font)
	elif state == State.READY:
		_draw_panel(PackedStringArray(["Woodcutting", "Chop from the side the next branch is NOT on",
			"A / Left or click left    D / Right or click right"]), font)


func _draw_panel(lines: PackedStringArray, font: Font) -> void:
	var h: float = 40.0 * lines.size() + 24.0
	var r: Rect2 = Rect2(size.x * 0.5 - 300.0, size.y * 0.30, 600.0, h)
	draw_rect(r, Color(0, 0, 0, 0.6))
	for i: int in lines.size():
		draw_string(font, Vector2(r.position.x, r.position.y + 44.0 + 40.0 * i), lines[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26 if i == 0 else 20, Color.WHITE)
