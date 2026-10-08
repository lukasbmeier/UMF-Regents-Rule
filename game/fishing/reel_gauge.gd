class_name ReelGauge extends Control
## GENRE CODE. THE FIGHT ON THE HUD, as a rod and a reel (DECISIONS #144) — replacing two bars
## that had to be read as numbers. Drawn by hand, bottom right, so it never covers the angler whose
## heave and winding are the other half of the picture.
##
##   the ROD      an arc that fills as the rod is loaded, in the fight's tell colour — calm, the
##                band's amber, the sweet spot's cyan (it pulses), too far (pink, it shakes).
##                The sweet spot itself is NOT drawn (FfC's playtest: "seeing the perfect bar
##                makes it too easy"); the colour says when you are in it.
##   the LINE     the reel's rim: tension, with a white tick where the drag starts to slip and
##                pink near the snap, shaking.
##   the REEL     spins as you wind; a white arc round the spool counts down a heave's slack; the
##                hub glows when winding pays (green) or half-pays (amber) — the fish is spent or
##                resting, or there is slack to take.
##   the FISH     what it is doing, and how much fight it has left.
##
## It reads a `FightSim` and draws; it decides nothing.

const SIZE: Vector2 = Vector2(400.0, 220.0)
const PANEL: Color = Color(0.03, 0.055, 0.08, 0.55)
const TRACK: Color = Color(1.0, 1.0, 1.0, 0.13)
const LABEL: Color = Color(0.62, 0.69, 0.75)
const TEXT: Color = Color(0.81, 0.85, 0.88)
const GOOD: Color = Color(0.56, 0.82, 0.54)
## Reel-pays thresholds for the hub's glow.
const PAYS_WELL: float = 0.4
const PAYS_SOME: float = 0.2
## Line won pops off the reel as "+m" every POP_EVERY_M. A pop younger than POP_MERGE_SEC counts
## the next metres up instead of starting another: a steady wind (a resting fish comes in at
## 2 m/s) would stack the labels on top of each other. At POP_RISE px/s that keeps two pops at
## least POP_MERGE_SEC × POP_RISE apart, over the text's height.
const POP_EVERY_M: float = 0.8
const POP_MERGE_SEC: float = 0.5
const POP_LIFE_SEC: float = 1.2
const POP_RISE: float = 36.0
const POP_FONT: int = 13
## The rod arc's sweep (radians, 0 = right, clockwise on screen) and the rim's.
const ROD_FROM: float = PI * 1.08
const ROD_TO: float = PI * 1.92
const RIM_FROM: float = PI * 0.75
const RIM_TO: float = PI * 2.25

var _fight: FightSim = null
var _crank: float = 0.0
var _turn: float = 0.0
var _t: float = 0.0
## Line won since the last "+m" popped, and the pops in flight: [metres, age].
var _won: float = 0.0
var _last_out: float = -1.0
var _pops: Array[Array] = []
var _box: StyleBoxFlat = null


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = StyleBoxFlat.new()
	_box.bg_color = PANEL
	_box.set_corner_radius_all(14)


## Show `f` this frame, with the reel being worked at `crank` (0..1).
func show_fight(f: FightSim, crank: float, delta: float) -> void:
	_fight = f
	_crank = crank
	_t += delta
	_turn = fmod(_turn + crank * TAU * 2.5 * delta, TAU)
	if f != null:
		var out: float = f.line_out_m()
		if _last_out >= 0.0 and out < _last_out:
			_won += _last_out - out
		_last_out = out
		if _won >= POP_EVERY_M:
			if not _pops.is_empty() and float(_pops[-1][1]) < POP_MERGE_SEC:
				_pops[-1][0] = float(_pops[-1][0]) + _won
			else:
				_pops.append([_won, 0.0])
			_won = 0.0
	for p: Array in _pops:
		p[1] = float(p[1]) + delta
	_pops = _pops.filter(func(p: Array) -> bool: return float(p[1]) < POP_LIFE_SEC)
	queue_redraw()


## A new fight: nothing won yet.
func reset() -> void:
	_won = 0.0
	_last_out = -1.0
	_pops.clear()


## The "+m" labels in flight, oldest first: how high each has risen (px) and what it says. For tests.
func pops_risen() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p: Array in _pops:
		out.append(float(p[1]) * POP_RISE)
	return out


func pops_text() -> PackedStringArray:
	var out := PackedStringArray()
	for p: Array in _pops:
		out.append("+%.1f m" % float(p[0]))
	return out


## The rod's fill, 0..1 of a full overload.
func rod_fill() -> float:
	return clampf(_fight.load / maxf(_fight.params.overload_limit, 0.01), 0.0, 1.0) if _fight != null else 0.0


## The rim's fill, 0..1 of the snap.
func rim_fill() -> float:
	return clampf(_fight.tension_fraction(), 0.0, 1.0) if _fight != null else 0.0


func fish_word() -> String:
	if _fight == null:
		return ""
	match _fight.behavior:
		FightSim.Behavior.RUNNING:
			return "running"
		FightSim.Behavior.RESTING:
			return "resting"
		FightSim.Behavior.SNAGGED:
			return "snagged"
	if not _fight.profile.alive:
		return "dead weight"
	return "tiring" if _fight.worn() >= 0.65 else "fighting"


func _draw() -> void:
	if _fight == null:
		return
	var f: FightSim = _fight
	var font: Font = ThemeDB.fallback_font
	if _box != null:
		draw_style_box(_box, Rect2(Vector2.ZERO, SIZE))
	var c := Vector2(SIZE.x * 0.5, 150.0)

	# THE ROD.
	var r: float = 92.0
	draw_arc(c, r, ROD_FROM, ROD_TO, 48, TRACK, 10.0, true)
	var tell: Color = FishingFeedback.tell_of(f)
	if f.load > 0.001:
		var end: float = lerpf(ROD_FROM, ROD_TO, rod_fill())
		var width: float = 12.0 + 3.0 * absf(sin(_t * 18.0)) if f.in_perfect() else 10.0
		draw_arc(c, r, ROD_FROM, end, 48, tell, width, true)
		var shake: Vector2 = Vector2(randf_range(-2.0, 2.0), 0.0) if f.is_overloaded() else Vector2.ZERO
		draw_circle(c + Vector2(cos(end), sin(end)) * r + shake, 5.0, Color.WHITE)
	draw_string(font, c + Vector2(cos(ROD_FROM), sin(ROD_FROM)) * r + Vector2(-16.0, 20.0), "rod",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, LABEL)

	# THE LINE: the reel's rim.
	var rr: float = 38.0
	var jitter: Vector2 = Vector2(randf_range(-1.5, 1.5), 0.0) if rim_fill() > 0.85 else Vector2.ZERO
	draw_arc(c + jitter, rr, RIM_FROM, RIM_TO, 40, TRACK, 7.0, true)
	var drag: float = f.effective_drag() / maxf(f.params.snap_tension, 0.01)
	var rim: Color = Color(0.56, 0.72, 0.83)
	if rim_fill() > 0.85:
		rim = FishingFx.TELL_OVER
	elif rim_fill() > drag:
		rim = FishingFx.TELL_BAND
	if rim_fill() > 0.0:
		draw_arc(c + jitter, rr, RIM_FROM, lerpf(RIM_FROM, RIM_TO, rim_fill()), 40, rim, 7.0, true)
	var tick: float = lerpf(RIM_FROM, RIM_TO, clampf(drag, 0.0, 1.0))
	draw_line(c + Vector2(cos(tick), sin(tick)) * (rr - 7.0), c + Vector2(cos(tick), sin(tick)) * (rr + 7.0),
		Color.WHITE, 2.0, true)
	draw_string(font, c + Vector2(-12.0, rr + 22.0), "line", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, TEXT)

	# THE REEL.
	var pays: float = f.reel_pays()
	var hub: Color = Color(1.0, 1.0, 1.0, 0.05)
	if pays >= PAYS_WELL:
		hub = Color(GOOD, 0.3)
	elif pays >= PAYS_SOME:
		hub = Color(FishingFx.TELL_BAND, 0.2)
	draw_circle(c, 27.0, hub)
	draw_arc(c, 27.0, 0.0, TAU, 32, TEXT, 2.0, true)
	for k: int in range(3):
		var a: float = _turn + k * TAU / 3.0
		draw_line(c, c + Vector2(cos(a), sin(a)) * 24.0, TEXT, 2.0, true)
	var knob: Vector2 = c + Vector2(cos(_turn), sin(_turn)) * 34.0
	draw_line(c, knob, Color(0.9, 0.83, 0.64), 3.0, true)
	draw_circle(knob, 5.0, Color(0.9, 0.83, 0.64))
	if f.slack > 0.0 and f.crank_left > 0.0:
		var left: float = clampf(f.crank_left / maxf(f.params.crank_window, 0.01), 0.0, 1.0)
		draw_arc(c, 31.0, -PI * 0.5, -PI * 0.5 + TAU * left, 32, Color.WHITE, 3.0, true)
	var pays_x: float = c.x - 150.0
	draw_string(font, Vector2(pays_x - 30.0, c.y - 60.0), "reel pays", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, LABEL)
	var pays_col: Color = GOOD if pays >= PAYS_WELL else (FishingFx.TELL_BAND if pays >= PAYS_SOME else TEXT)
	draw_string(font, Vector2(pays_x - 30.0, c.y - 32.0), "%d%%" % roundi(pays * 100.0),
		HORIZONTAL_ALIGNMENT_CENTER, 60.0, 20, pays_col)

	# THE FISH.
	var fx: Vector2 = Vector2(c.x + 150.0, c.y - 38.0)
	var word: String = fish_word()
	var fish: Color = FishingFx.TELL_RUN if word == "running" else (GOOD if word == "resting" else TEXT)
	draw_string(font, fx + Vector2(-30.0, -24.0), "fish", HORIZONTAL_ALIGNMENT_CENTER, 60.0, 11, LABEL)
	draw_set_transform(fx, 0.0, Vector2(1.0, 0.44))
	draw_circle(Vector2.ZERO, 16.0, fish)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([fx + Vector2(14.0, 0.0), fx + Vector2(24.0, -7.0),
		fx + Vector2(24.0, 7.0)]), fish)
	draw_string(font, fx + Vector2(-40.0, 26.0), word, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 12, fish)
	if f.profile.alive and not f.profile.never_tires:
		draw_rect(Rect2(fx + Vector2(-26.0, 32.0), Vector2(52.0, 5.0)), TRACK)
		draw_rect(Rect2(fx + Vector2(-26.0, 32.0), Vector2(52.0 * clampf(f.stamina, 0.0, 1.0), 5.0)), fish)

	# Line won, rising off the reel.
	var texts: PackedStringArray = pops_text()
	for i: int in range(_pops.size()):
		var age: float = float(_pops[i][1])
		draw_string(font, c + Vector2(44.0, -18.0 - age * POP_RISE), texts[i], HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, POP_FONT, Color(GOOD, 1.0 - age / POP_LIFE_SEC))

