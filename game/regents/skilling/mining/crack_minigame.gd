class_name CrackMinigame extends SkillMinigame
## MINING'S CRACK THE ROCK, PLAYED: FOLLOW THE SEAM (`CrackModel` says what happens; this draws it and
## takes the strikes). The rock face fills the middle with a faint crack outline across it; the next notch
## glows. Click it with the pick: the crack opens to it and chips fly. Open the whole seam and the rock
## splits (Crack!) and the next seam shows. A strike off the seam jars the pick (Clang!) and staggers you.
## Clicking ahead during a swing is fine: the strike is held and lands when the pick is back up.
## THE LOOK (`MINIGAMES_PREP.md` §5, Luke's M7, 2026-11-05): the rock and the pick are a 3D stage behind this panel
## (`MineStage`); the seam is drawn over the rock (the face square sits on it). Without the stage (a panel not in
## the tree) the rock is drawn flat, as before.

const STAGE: PackedScene = preload("res://game/regents/skilling/mining/mine_stage.tscn")

const ROCK: Color = Color(0.46, 0.44, 0.42)
const ROCK_DARK: Color = Color(0.30, 0.28, 0.27)
const CRACK: Color = Color(0.07, 0.06, 0.06)
const SEAM: Color = Color(0.16, 0.14, 0.13, 0.55)
const GLOW: Color = Color(1.0, 0.82, 0.30)
const JAR: Color = Color(1.0, 0.45, 0.35)
## A brittle notch (band 2's test): pale, icy.
const BRITTLE: Color = Color(0.75, 0.88, 1.0)

var model: CrackModel
var last_event: int = CrackModel.IGNORED
var last_event_ms: int = -100000
var last_at: Vector2 = Vector2.ZERO
var _acts_seen: int = 0
var _chips: Array[Chip] = []
var _stage: MineStage = null


func _ready() -> void:
	theme = MinigameLook.theme()
	_stage = STAGE.instantiate() as MineStage
	_stage.show_behind_parent = true   # drawn under the seam
	add_child(_stage)
	move_child(_stage, 0)
	if params != null:
		_stage.set_rock(node_of(rock()))


## The node whose round this is (for its rock model and ore), or null.
static func node_of(p: CrackParams) -> NodeDef:
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame == p or (n.minigame is CrackParams and p != null and (n.minigame as CrackParams).display_name == p.display_name):
			return n
	return null


class Chip:
	var pos: Vector2
	var vel: Vector2
	var size: float = 8.0


func rock() -> CrackParams:
	return params as CrackParams


func duration_ms() -> int:
	return rock().duration_ms if rock() != null else 0


func title() -> String:
	return rock().display_name if rock() != null else "Mining"


func how_to() -> String:
	return "Follow the seam: click its glowing notch, then the next; off the seam the pick jars"


func summary(r: Dictionary) -> String:
	return "Notches %d   Splits %d   Jars %d" % [r.get("hits", 0), r.get("splits", 0), r.get("jars", 0)]


func _new_model() -> void:
	model = CrackModel.start(seed_value, rock())
	last_event = CrackModel.IGNORED
	last_event_ms = -100000
	_acts_seen = 0
	_chips.clear()
	if _stage != null:
		_stage.set_rock(node_of(rock()))


func _model_result() -> Dictionary:
	return model.result()


func _end_model() -> void:
	model.finish()


## The rock face's square on screen: on the 3D rock (its middle, most of its height), else in the panel's middle.
func face() -> Rect2:
	var side: float = minf(size.x * 0.8, size.y - 120.0)
	if _stage != null and size.x > 0.0:
		var r: Rect2 = _stage.rock_rect()
		if r.size.x > 1.0:
			side = minf(side, minf(r.size.x, r.size.y) * 0.82)
			var c: Vector2 = r.get_center()
			return Rect2(c.x - side * 0.5, clampf(c.y - side * 0.5, 80.0, size.y - side - 20.0), side, side)
	return Rect2(size.x * 0.5 - side * 0.5, 80.0, side, side)


## A screen point as thousandths of the face.
func to_face(at: Vector2) -> Vector2i:
	var f: Rect2 = face()
	return Vector2i(int(roundf((at.x - f.position.x) / f.size.x * 1000.0)), int(roundf((at.y - f.position.y) / f.size.y * 1000.0)))


func from_face(p: Vector2i) -> Vector2:
	var f: Rect2 = face()
	return f.position + Vector2(p.x, p.y) / 1000.0 * f.size


## A strike at (x, y) thousandths, `t_ms` into the round: what clicks call, and what tests drive.
func strike_at(t_ms: int, x: int, y: int) -> int:
	if state != State.PLAYING:
		return CrackModel.IGNORED
	record([t_ms, x, y])
	var ev: int = model.strike(t_ms, x, y)
	_follow()
	queue_redraw()
	return ev


## Show every strike the model landed since the last look (a click, or one held through a swing).
func _follow() -> void:
	if model.acts == _acts_seen:
		return
	_acts_seen = model.acts
	last_event = model.last_act
	last_event_ms = model.last_act_ms
	last_at = from_face(model.last_act_at)
	if _stage != null:
		if last_event == CrackModel.HIT:
			_stage.strike(last_at, model.k % rock().notches == 0)
		elif last_event == CrackModel.JAR:
			_stage.jar(last_at)
		return
	if last_event == CrackModel.HIT:
		var n: int = 14 if model.k % rock().notches == 0 else 5   # the rock split: more flies
		for i: int in n:
			var c: Chip = Chip.new()
			c.pos = last_at
			c.vel = Vector2(randf_range(-300, 300), randf_range(-460, -120))
			c.size = randf_range(5.0, 12.0)
			_chips.append(c)


func _process(delta: float) -> void:
	if state == State.PLAYING and model != null:
		model.settle(elapsed_ms())
		_follow()
		if _stage != null:
			var f: Rect2 = face()
			var m: Vector2 = get_local_mouse_position()
			_stage.hover(Vector2(clampf(m.x, f.position.x, f.end.x), clampf(m.y, f.position.y, f.end.y)))
	super(delta)


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and state == State.PLAYING:
		var p: Vector2i = to_face(mb.position)
		strike_at(elapsed_ms(), p.x, p.y)
		accept_event()


func _animate(delta: float) -> void:
	for i: int in range(_chips.size() - 1, -1, -1):
		var c: Chip = _chips[i]
		c.pos += c.vel * delta
		c.vel.y += 1200.0 * delta
		if c.pos.y > size.y + 50.0:
			_chips.remove_at(i)


## The rock's outline: a rough boulder inside the face square (fixed, so it never jitters).
func _rock_shape(f: Rect2, shake: Vector2) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var bumps: Array[float] = [1.0, 0.93, 0.98, 0.9, 1.0, 0.95, 0.88, 0.97, 1.0, 0.92, 0.96, 0.9]
	var c: Vector2 = f.get_center() + shake
	for i: int in bumps.size():
		var a: float = TAU * float(i) / float(bumps.size()) - PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * f.size * 0.5 * 1.08 * bumps[i])
	return pts


## A crack between two places, a little jagged (the same jag every frame: from the places themselves).
func _crack(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var mid: Vector2 = (a + b) * 0.5
	var n: Vector2 = (b - a).orthogonal().normalized()
	var jag: float = (float(int(a.x * 7.0 + b.y * 13.0) % 9) - 4.0) * 2.0
	draw_polyline(PackedVector2Array([a, mid + n * jag, b]), color, width)


func _draw() -> void:
	var font: Font = get_theme_default_font()
	if _stage == null:
		draw_rect(Rect2(0, 0, size.x, size.y), Color(0.16, 0.15, 0.15))
	var f: Rect2 = face()
	var t: int = elapsed_ms() if state == State.PLAYING else (model.last_t_ms if model != null else 0)
	var since: int = t - last_event_ms
	var jarred: bool = last_event == CrackModel.JAR and since < rock().stagger_ms
	var shake: Vector2 = Vector2(sin(float(since) * 0.09) * 5.0, 0.0) if jarred else Vector2.ZERO
	if _stage == null:
		var outline: PackedVector2Array = _rock_shape(f, shake)
		draw_colored_polygon(outline, ROCK)
		var inner: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in outline:
			inner.append(f.get_center() + shake + (p - f.get_center() - shake) * 0.86 + Vector2(-6, -8))
		draw_colored_polygon(inner, ROCK.lightened(0.06))
		outline.append(outline[0])
		draw_polyline(outline, ROCK_DARK, 4.0)
	if model != null:
		var n: int = rock().notches
		var seam: int = model.seam_of(model.k)
		var first: int = seam * n
		# The seam before this one split the rock: its crack stays, fainter.
		if seam > 0:
			for i: int in range(first - n, first - 1):
				_crack(from_face(model.notch(i)) + shake, from_face(model.notch(i + 1)) + shake, Color(CRACK, 0.35), 4.0)
		# This seam: opened so far (dark), the faint outline ahead (as far as the rock shows).
		for i: int in range(first, model.k - 1):
			_crack(from_face(model.notch(i)) + shake, from_face(model.notch(i + 1)) + shake, CRACK, 6.0)
		var last_shown: int = mini(first + n - 1, model.k + rock().reveal_ahead)
		for i: int in range(maxi(first, model.k - 1), last_shown):
			var a: Vector2 = from_face(model.notch(i)) + shake
			var b: Vector2 = from_face(model.notch(i + 1)) + shake
			if i < model.k:
				_crack(a, b, CRACK, 6.0)   # from the last opened notch, the crack is already reaching
			else:
				_crack(a, b, SEAM, 2.0)
		for i: int in range(model.k + 1, last_shown + 1):
			draw_circle(from_face(model.notch(i)) + shake, 4.0, SEAM)
		if state == State.PLAYING:
			# BRITTLE (band 2, a test, 2026-11-07): a brittle notch is pale and cracked; while the rock still rings, rings
			# spread from it and it does not glow ready (struck now, it cracks wrong).
			var brittle: bool = model.is_brittle(model.k)
			var ringing: bool = brittle and model.ringing(t)
			var ready: bool = t >= model.next_ok_ms and not ringing
			var at: Vector2 = from_face(model.notch(model.k)) + shake
			var r: float = float(rock().radius_pm) / 1000.0 * f.size.x
			var pulse: float = 0.5 + 0.5 * sin(float(t) * 0.012)
			var tint: Color = BRITTLE if brittle else GLOW
			draw_circle(at, r, Color(tint, (0.18 + 0.2 * pulse) if ready else 0.1))
			draw_arc(at, r, 0.0, TAU, 40, Color(tint, 0.9 if ready else 0.35), 3.0)
			if brittle:
				for c: int in 3:   # its cracks
					var ang: float = 0.7 + c * 2.1
					draw_line(at, at + Vector2(cos(ang), sin(ang)) * r * 0.8, Color(BRITTLE, 0.8), 2.0)
			if ringing:
				var ring_f: float = clampf(float(t - model.last_hit_ms) / float(maxi(1, rock().ring_ms)), 0.0, 1.0)
				for w: int in 2:
					var rr: float = r * (1.2 + 1.6 * fmod(ring_f + w * 0.5, 1.0))
					draw_arc(at, rr, 0.0, TAU, 40, Color(BRITTLE, 0.7 * (1.0 - ring_f)), 2.0)
			if model.held:
				draw_circle(from_face(Vector2i(model.held_x, model.held_y)) + shake, 6.0, Color(1, 1, 1, 0.5))
		if jarred:
			MinigameLook.text(self, font, last_at + Vector2(-30, -20), "Cracked wrong!" if model.cracked_wrong else "Clang!", 24, JAR)
		elif last_event == CrackModel.HIT and since < 700 and model.k % n == 0 and model.k > 0:
			MinigameLook.text(self, font, f.get_center() + Vector2(-50, 0), "Crack!", 40, GLOW)
		if state == State.PLAYING and _stage != null:
			var hint: String = "Click the glowing notch, then the next"
			if rock().brittle_permille > 0:
				hint += "; a pale one only once the rock stops ringing"
			MinigameLook.text(self, font, Vector2(0.0, size.y - 20.0), hint, 15, MinigameLook.HINT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	for c: Chip in _chips:
		draw_rect(Rect2(c.pos, Vector2(c.size, c.size)), ROCK_DARK)
	_draw_frame("Notches %d / %d   Jars %d" % [model.hits, rock().target_hits, model.jars] if model != null else "")
