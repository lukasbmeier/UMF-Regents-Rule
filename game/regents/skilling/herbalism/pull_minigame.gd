class_name PullMinigame extends SkillMinigame
## HERBALISM'S PULL THE ROOT, PLAYED (`HERBALISM_HUNTING_PREP.md` §3, Luke's H3, 2026-11-07; the trowel's work after his
## play, 2026-11-08; `PullModel` says what happens, this takes the presses and tells the stage). Two hands: HOLD Space
## or the left mouse button to pull, let go to ease the strain; A / D (or the arrows) stroke the TROWEL on that side.
## A round is a CLUMP (Luke, 2026-11-08): stem after stem until the time runs out. Dig round each stem first (packed
## soil holds the root); as the root comes up the soil CRACKS on the side of a side root about to catch: stroke that
## side to cut it, or pull through it gently. Past the top a stem snaps (the rest of that stem is lost, never the round).
## THE CUTAWAY (Luke, 2026-11-09: "cutaway, no chore", after the dig-both-sides chore and side roots that came unseen):
## a slice of the soil beside the stage shows the root and every side root still on it climbing to the surface (where an
## uncut one catches), the gold band where the trowel can reach one (the key to cut it), each side's soil packed or loose
## (some sides start loose, `loose_pm`: dig only the packed ones), and the strain as a bar with the next catch's jump
## marked on it (the stem still stretches, leans and creaks too). `PullStage` is the 3D stage behind it; without one (a
## panel not in the tree) it draws the round flat.

const STAGE: PackedScene = preload("res://game/regents/skilling/herbalism/pull_stage.tscn")

const SOIL: Color = Color(0.33, 0.23, 0.14)
const STEM: Color = Color(0.40, 0.62, 0.28)
const ROOT: Color = Color(0.62, 0.50, 0.33)
const SNAP: Color = Color(1.0, 0.45, 0.4)
const LOOSE: Color = Color(0.56, 0.41, 0.26)
const PACKED: Color = Color(0.25, 0.16, 0.09)
## The root in the slice: pale, so it reads on loose and packed soil alike.
const PALE_ROOT: Color = Color(0.93, 0.85, 0.66)
## The cutaway: where it sits in the panel, and how many pixels a thousandth of the root is.
const CUTAWAY: Rect2 = Rect2(16.0, 250.0, 184.0, 300.0)
const CUT_PX: float = 0.2

var model: PullModel
var _stage: PullStage = null
var _down: bool = false
var _events_seen: int = 0
var _plant_seen: int = 0
var _word: String = ""
var _word_color: Color = MinigameLook.INK
var _word_at: int = -100000


func _ready() -> void:
	theme = MinigameLook.theme()
	_stage = STAGE.instantiate() as PullStage
	_stage.show_behind_parent = true   # drawn under this panel's own words
	add_child(_stage)
	move_child(_stage, 0)


func plant_params() -> PullParams:
	return params as PullParams


func duration_ms() -> int:
	return plant_params().duration_ms if plant_params() != null else 0


func title() -> String:
	return "Pulling: %s" % plant_params().display_name if plant_params() != null else "Pulling"


func how_to() -> String:
	return "A / D: the trowel digs round the stem, or cuts a root where the soil cracks. Hold Space or the mouse to pull; ease off before it snaps"


func summary(r: Dictionary) -> String:
	return "Whole roots %d   Snapped %d   Cut %d" % [int(r.get("whole", 0)), int(r.get("snapped", 0)), int(r.get("cut", 0))]


func _new_model() -> void:
	model = PullModel.start(seed_value, plant_params())
	_down = false
	_events_seen = 0
	_plant_seen = 0
	_word = ""
	if _stage != null:
		_stage.new_plant(true)


func _model_result() -> Dictionary:
	return model.result()


func _end_model() -> void:
	model.finish()
	_down = false


func is_over() -> bool:
	return model != null and model.over


## An input `code` (DOWN, UP, LEFT, RIGHT) at `t_ms`: what the keys and the mouse call, and what tests drive.
func press_at(t_ms: int, code: int) -> int:
	if state != State.PLAYING:
		return PullModel.IGNORED
	record([t_ms, code])
	var ev: int = model.press(t_ms, code)
	_follow(t_ms)
	if _stage != null and (code == PullModel.LEFT or code == PullModel.RIGHT) and ev != PullModel.IGNORED:
		_stage.stroke(code == PullModel.LEFT, ev, model.pack_left if code == PullModel.LEFT else model.pack_right)
	if ev == PullModel.CUT:
		_say("Cut!", MinigameLook.GOLD, t_ms)
	queue_redraw()
	return ev


## The button went down or up (Space, the mouse).
func button(down: bool) -> void:
	if state != State.PLAYING or down == _down:
		return
	_down = down
	press_at(elapsed_ms(), PullModel.DOWN if down else PullModel.UP)


## Show what the model's ticks did since the last look (a catch, a snap, a root up, the next stem).
func _follow(t_ms: int) -> void:
	if model.events != _events_seen:
		_events_seen = model.events
		match model.last_event:
			PullModel.CAUGHT:
				if _stage != null:
					_stage.caught()
			PullModel.SNAPPED:
				_say("Snapped!", SNAP, t_ms)
				if _stage != null:
					_stage.snapped()
			PullModel.WHOLE:
				_say("Up whole!", MinigameLook.GOLD, t_ms)
				if _stage != null:
					_stage.whole()
	if model.plant != _plant_seen and not model.over:
		_plant_seen = model.plant
		if _stage != null:
			get_tree().create_timer(0.5).timeout.connect(_stage.new_plant.bind(false))
	if _stage != null:
		_stage.show_pull(model.up_by, model.strain, model.showing(), model.down and not model.stroking(t_ms),
			model.pack_left, model.pack_right)


func _say(word: String, color: Color, t_ms: int) -> void:
	_word = word
	_word_color = color
	_word_at = t_ms


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		button(mb.pressed)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or k.echo or state != State.PLAYING or not is_visible_in_tree():
		return
	if k.keycode == KEY_SPACE:
		button(k.pressed)
	elif not k.pressed:
		return
	elif k.physical_keycode == KEY_A or k.keycode == KEY_LEFT:
		press_at(elapsed_ms(), PullModel.LEFT)
	elif k.physical_keycode == KEY_D or k.keycode == KEY_RIGHT:
		press_at(elapsed_ms(), PullModel.RIGHT)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		var t: int = elapsed_ms()
		model.advance_to(t)
		_follow(t)
	super(delta)


func _counts() -> String:
	if model == null:
		return ""
	return "Whole %d   Snapped %d" % [model.whole, model.snapped]


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if _stage == null:
		_draw_flat()
	if model != null and state == State.PLAYING:
		var t: int = elapsed_ms()
		if not _word.is_empty() and t - _word_at < 900:
			MinigameLook.text(self, font, Vector2(0.0, size.y * 0.30 - (t - _word_at) * 0.03), _word, 32, _word_color, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		MinigameLook.text(self, font, Vector2(0.0, size.y - 20.0), "A / D: dig a packed side, or cut a side root in the gold   Hold Space: pull, let go to ease",
			15, MinigameLook.HINT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	if model != null and state != State.READY:
		_draw_cutaway(font)
	_draw_frame(_counts())


## The slice of soil (see the header): the soil's two sides, the gold band, the root and its side roots, the strain.
func _draw_cutaway(font: Font) -> void:
	var r: Rect2 = CUTAWAY
	var p: PullParams = plant_params()
	var surface: float = r.position.y + 70.0
	var cx: float = r.position.x + r.size.x * 0.5
	var up: int = mini(model.up_by, 1000)
	draw_rect(r.grow(4.0), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(r.position, Vector2(r.size.x, surface - r.position.y)), Color(0.52, 0.66, 0.78, 0.9))
	for side: int in [PullModel.LEFT, PullModel.RIGHT]:
		var left: bool = side == PullModel.LEFT
		var pack: int = model.pack_left if left else model.pack_right
		var half: Rect2 = Rect2(r.position.x if left else cx, surface, r.size.x * 0.5, r.end.y - surface)
		draw_rect(half, LOOSE.lerp(PACKED, clampf(float(pack) / 1000.0, 0.0, 1.0)))
		var key: String = "A" if left else "D"
		var words: String = "packed" if pack >= 1000 else ("dug half" if pack > 0 else "loose")
		var dig: bool = pack > 0 and up == 0
		MinigameLook.text(self, font, Vector2(half.position.x + 6.0, surface + 20.0), words, 14, MinigameLook.GOLD if dig else MinigameLook.INK)
		if dig:
			MinigameLook.text(self, font, Vector2(half.position.x + 6.0, surface + 38.0), "%s: dig" % key, 14, MinigameLook.GOLD)
	# The gold band: a side root this close under the surface can be cut (the trowel reaches it).
	var band: float = float(p.show_depth) * CUT_PX
	draw_rect(Rect2(r.position.x, surface, r.size.x, band), Color(MinigameLook.GOLD, 0.13))
	draw_line(Vector2(r.position.x, surface + band), Vector2(r.end.x, surface + band), Color(MinigameLook.GOLD, 0.5), 1.0)
	draw_line(Vector2(r.position.x, surface), Vector2(r.end.x, surface), Color(0.12, 0.08, 0.05), 3.0)
	# The root: its top at the stem's base, risen by how much is up.
	var top: float = maxf(r.position.y, surface - float(up) * CUT_PX)   # past the slice's top: cut off there
	var bottom: float = top + 1000.0 * CUT_PX
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 6.0, top), Vector2(cx + 6.0, top), Vector2(cx + 1.0, bottom),
		Vector2(cx - 1.0, bottom)]), PALE_ROOT)
	draw_line(Vector2(cx, top), Vector2(cx, maxf(r.position.y, top - 46.0)), STEM, 5.0)
	# The side roots still on it: each climbs with the root; at the surface an uncut one catches.
	var showing: int = model.showing()
	for k: int in range(model.next_snag, model.snag_depth.size()):
		var y: float = surface + float(model.snag_depth[k] - up) * CUT_PX
		if y > r.end.y + 20.0:
			continue
		var dir: float = -1.0 if model.snag_side[k] == PullModel.LEFT else 1.0
		var next: bool = k == model.next_snag
		var reach: bool = next and showing != 0
		var c: Color = MinigameLook.GOLD if reach else (PALE_ROOT if next else Color(PALE_ROOT, 0.55))
		var tip: Vector2 = Vector2(cx + dir * 56.0, y + 20.0)
		draw_line(Vector2(cx, y), Vector2(cx + dir * 30.0, y + 6.0), c, 4.0 if reach else 3.0)
		draw_line(Vector2(cx + dir * 30.0, y + 6.0), tip, c, 3.0 if reach else 2.0)
		if reach:
			MinigameLook.text(self, font, tip + Vector2(-18.0 if dir < 0.0 else -4.0, 22.0), "%s: cut" % ("A" if dir < 0.0 else "D"),
				18, MinigameLook.GOLD)
	# The strain: a bar beside the slice, red as it nears the top (past it the stem snaps), the next catch's jump marked.
	var bar: Rect2 = Rect2(r.end.x + 12.0, r.position.y + 10.0, 14.0, r.size.y - 40.0)
	var strain: float = clampf(float(model.strain) / 1000.0, 0.0, 1.0)
	draw_rect(bar.grow(2.0), Color(0, 0, 0, 0.6))
	var fill: Color = STEM.lerp(MinigameLook.EMBER, strain).lerp(SNAP, maxf(0.0, strain - 0.7) / 0.3)
	draw_rect(Rect2(bar.position.x, bar.end.y - bar.size.y * strain, bar.size.x, bar.size.y * strain), fill)
	if model.next_snag < model.snag_jump.size():
		var jump: float = clampf(float(model.snag_jump[model.next_snag]) / 1000.0, 0.0, 1.0)
		var j0: float = bar.end.y - bar.size.y * strain
		var j1: float = maxf(bar.position.y, j0 - bar.size.y * jump)
		draw_rect(Rect2(bar.position.x - 3.0, j1, bar.size.x + 6.0, j0 - j1), Color(SNAP, 0.55), false, 2.0)
	draw_line(Vector2(bar.position.x - 5.0, bar.position.y), Vector2(bar.end.x + 5.0, bar.position.y), SNAP, 2.0)
	MinigameLook.text(self, font, Vector2(bar.position.x - 14.0, bar.end.y + 22.0), "Strain", 14, MinigameLook.INK)


## The round drawn flat (no stage): the soil, the stem risen by how much root is up, stretched by the strain, the
## cracking side marked.
func _draw_flat() -> void:
	var gy: float = size.y * 0.7
	draw_rect(Rect2(0, 0, size.x, size.y), Color(0.55, 0.72, 0.86))
	draw_rect(Rect2(0, gy, size.x, size.y - gy), SOIL)
	if model == null:
		return
	var x: float = size.x * 0.5
	var up: float = float(mini(model.up_by, 1000)) / 1000.0 * 60.0
	var tall: float = 140.0 * (1.0 + float(model.strain) / 1000.0 * 0.15)
	draw_line(Vector2(x, gy - up), Vector2(x, gy - up - tall), STEM, 6.0)
	draw_line(Vector2(x, gy - up), Vector2(x, gy - up + 60.0), ROOT, 4.0)
	draw_rect(Rect2(0, gy, size.x, size.y - gy), SOIL)   # the root still in the ground is hidden
	var side: int = model.showing()
	if side != 0:
		var cx: float = x + (-40.0 if side == PullModel.LEFT else 40.0)
		draw_line(Vector2(cx - 12.0, gy + 2.0), Vector2(cx + 12.0, gy - 4.0), Color(0.15, 0.1, 0.06), 3.0)
