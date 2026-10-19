class_name ChopMinigame extends SkillMinigame
## WOODCUTTING'S BRANCH DODGE, PLAYED (`ChopModel` says what happens; this draws it and takes the
## presses). A trunk in the middle, the woodcutter beside it; A / Left or a click on the left half chops
## from the left, D / Right or a click on the right half from the right. A branch at your head on the side
## you chop from hits you: the swing is lost and you are staggered.

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

var model: ChopModel
## What the last press did (ChopModel.CLEAN / HIT) and when, for the swing and the ouch.
var last_event: int = ChopModel.IGNORED
var last_event_ms: int = -100000
var _acts_seen: int = 0
var _flying: Array[Piece] = []


## A chopped piece in the air: where, how fast, turned how far and how fast (pixels, seconds, radians).
class Piece:
	var pos: Vector2
	var vel: Vector2
	var angle: float = 0.0
	var spin: float = 0.0


func tree() -> ChopParams:
	return params as ChopParams


func duration_ms() -> int:
	return tree().duration_ms if tree() != null else 0


func title() -> String:
	return tree().display_name if tree() != null else "Woodcutting"


func how_to() -> String:
	return "Chop from the side the next branch is NOT on: A / Left or click left, D / Right or click right"


func summary(r: Dictionary) -> String:
	return "Logs %d   Hits %d   Best combo %d" % [r.get("clean", 0), r.get("hits", 0), r.get("best_combo", 0)]


func _new_model() -> void:
	model = ChopModel.start(seed_value, tree())
	last_event = ChopModel.IGNORED
	last_event_ms = -100000
	_acts_seen = 0
	_flying.clear()


func _model_result() -> Dictionary:
	return model.result()


## A press from `side` at `t_ms` into the round: what the keys and clicks call, and what tests drive.
func press_at(t_ms: int, side: int) -> int:
	if state != State.PLAYING:
		return ChopModel.IGNORED
	record([t_ms, side])
	var ev: int = model.chop(t_ms, side)
	_follow()
	return ev


## Show every swing the model landed since the last look (a press, or one held through a swing).
func _follow() -> void:
	if model.acts == _acts_seen:
		return
	_acts_seen = model.acts
	last_event = model.last_act
	last_event_ms = model.last_act_ms
	if last_event == ChopModel.CLEAN:
		_throw_piece(model.side)
	queue_redraw()


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		model.settle(elapsed_ms())
		_follow()
	super(delta)


func _end_model() -> void:
	model.finish()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		press_at(elapsed_ms(), ChopModel.SIDE_LEFT if mb.position.x < size.x * 0.5 else ChopModel.SIDE_RIGHT)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or state != State.PLAYING or not is_visible_in_tree():
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


func _animate(delta: float) -> void:
	for i: int in range(_flying.size() - 1, -1, -1):
		var f: Piece = _flying[i]
		f.pos += f.vel * delta
		f.vel.y += 1400.0 * delta
		f.angle += f.spin * delta
		if f.pos.y > size.y + 200.0:
			_flying.remove_at(i)


func _ground_y() -> float:
	return size.y * 0.84


func _trunk_x() -> float:
	return size.x * 0.5 - TRUNK_W * 0.5


func _draw() -> void:
	var gy: float = _ground_y()
	var tx: float = _trunk_x()
	draw_rect(Rect2(0, 0, size.x, size.y), SKY)
	draw_rect(Rect2(0, gy, size.x, size.y - gy), GROUND)
	draw_rect(Rect2(tx - 14.0, gy - 6.0, TRUNK_W + 28.0, 14.0), BARK_DARK)   # the stump's flare
	if model != null:
		_draw_trunk(tx, gy)
		_draw_woodcutter(tx, gy)
	for f: Piece in _flying:
		draw_set_transform(f.pos, f.angle)
		draw_rect(Rect2(-TRUNK_W * 0.5, -SEGMENT_H * 0.5, TRUNK_W, SEGMENT_H), BARK)
		draw_set_transform(Vector2.ZERO)
	_draw_frame("Logs %d   Combo %d   Hits %d" % [model.clean, model.combo, model.hits] if model != null else "")


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


func _draw_woodcutter(tx: float, gy: float) -> void:
	var font: Font = get_theme_default_font()
	var left: bool = model.side == ChopModel.SIDE_LEFT
	var x: float = tx - 62.0 if left else tx + TRUNK_W + 62.0
	var t: int = elapsed_ms() if state == State.PLAYING else model.last_t_ms
	var since: int = t - last_event_ms
	var hurt: bool = last_event == ChopModel.HIT and since < tree().stagger_ms
	var shake: float = sin(float(since) * 0.08) * 4.0 if hurt else 0.0
	draw_rect(Rect2(x - 14.0 + shake, gy - 70.0, 28.0, 70.0), HURT if hurt else SHIRT)
	draw_circle(Vector2(x + shake, gy - 86.0), 15.0, Color(0.95, 0.80, 0.65))
	# The axe: raised, swung down onto the bottom piece over the first part of a swing, raised again.
	var swing: float = 1.0
	if last_event == ChopModel.CLEAN and since >= 0 and since < tree().swing_ms:
		var k: float = float(since) / float(tree().swing_ms)
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
