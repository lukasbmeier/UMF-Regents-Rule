class_name RegentsAbilitySlot extends Control
## ONE SLOT OF THE ABILITY BAR (`RegentsAbilityBar`), drawn in the bar's look (`RegentsBarStyle`: round or square).
## It shows what `RegentsAbilityBar.model_for` says of it, and decides nothing:
##   its picture (the ability's icon, `icons/ability_<id>.png`, else its first letter), its key in the corner,
##   READY       full
##   COOLING     a shade over it that empties as it comes back (a sweep round, a wipe square), its seconds on it
##   COST        tinted: the pool cannot pay for it (the staff's mana)
##   LOCKED      dim, with what opens it ("rank 3")
##   EMPTY       a faint edge: nothing there yet (hover says what goes there)
##   CHOOSE      a "+" and a pulsing edge: a pick is open on the weapon (choose in the bag)
## A press that fires it flashes it (`flash`). Hover for what it does (`tooltip_text`), when the cursor is free.

const READY: StringName = &"ready"
const COOLING: StringName = &"cooling"
const COST: StringName = &"cost"
const LOCKED: StringName = &"locked"
const EMPTY: StringName = &"empty"
## A pick open on the weapon: its edge pulses until one is chosen (in the bag).
const CHOOSE: StringName = &"choose"
const FLASH_S: float = 0.3

var style: RegentsBarStyle = null
## What it shows: {key, name, glyph, icon, state, left, total, note, tip, count, ability_id}.
var data: Dictionary = {}
## Out of stance the edge is plain; in stance it is the stance color.
var lit: bool = false
var _flash_ms: int = -100000

## Pressed (a left click on it, the cursor free): the bar's weapon opens its abilities.
signal pressed()


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and pressed.get_connections().size() > 0:
		pressed.emit()
		accept_event()   # only a slot that does something on a click keeps it (the rest pass it to the game)


func _init() -> void:
	# PASS, never STOP: a click on a slot still reaches the game (a swing is never lost to the bar under the cursor),
	# and the slot still shows its words on hover.
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE


## Show `d` (a slot of the bar's model); redrawn only when something on it changed.
func show_data(d: Dictionary, stance: bool) -> void:
	var tip: String = String(d.get("tip", ""))
	if tooltip_text != tip:
		tooltip_text = tip
	if d == data and stance == lit and not _flashing():
		return
	data = d.duplicate()
	lit = stance
	queue_redraw()


func state() -> StringName:
	return StringName(String(data.get("state", EMPTY)))


## It fired: a short flash.
func flash() -> void:
	_flash_ms = Time.get_ticks_msec()
	queue_redraw()


func _flashing() -> bool:
	return Time.get_ticks_msec() - _flash_ms < int(FLASH_S * 1000.0)


func _process(_delta: float) -> void:
	if _flashing() or state() == COOLING or state() == CHOOSE:
		queue_redraw()


func _draw() -> void:
	if style == null:
		return
	var s: Vector2 = size
	var c: Vector2 = s * 0.5
	var r: float = minf(s.x, s.y) * 0.5
	var st: StringName = state()
	var is_round: bool = style.round_slots()
	# The ground.
	var bg: Color = style.slot_bg
	if st == EMPTY:
		bg.a *= 0.55
	_fill(c, r, s, bg)
	# Its picture.
	var icon: Texture2D = data.get("icon", null) as Texture2D
	var dim: Color = style.locked_tint if st == LOCKED else Color.WHITE
	if st == EMPTY:
		dim = Color(1, 1, 1, 0.35)
	elif st == COOLING:
		dim = Color(1, 1, 1, 0.3)   # under the seconds, faint
	if icon != null:
		var inset: float = r * (0.42 if is_round else 0.18)
		draw_texture_rect(icon, Rect2(Vector2(inset, inset), s - Vector2(inset, inset) * 2.0), false, dim)
	else:
		var glyph: String = String(data.get("glyph", ""))
		var mark: String = String(data.get("mark", ""))
		var small: bool = s.x < float(style.slot_size) - 1.0
		var mc: Vector2 = c if is_round else c + Vector2(0, 8.0 if small else 4.0)   # under a square's corner key
		if not mark.is_empty():
			draw_mark(self, mark, mc, r * (0.4 if small and not is_round else 0.48), Color(style.text_color, dim.a))
		elif not glyph.is_empty():
			var fs: int = style.glyph_font_size if s.x >= style.slot_size - 1 else int(style.glyph_font_size * 0.72)
			_text(glyph, c + Vector2(0, fs * 0.36), fs, style.text_color * dim, true)
	# What it costs it cannot pay.
	if st == COST:
		_fill(c, r, s, style.no_cost_tint)
	# Its cooldown: a shade that empties as it comes back.
	var total: float = float(data.get("total", 0.0))
	var left: float = float(data.get("left", 0.0))
	if st == COOLING and total > 0.0:
		var frac: float = clampf(left / total, 0.0, 1.0)
		if is_round:
			_pie(c, r - style.border_width * 0.5, frac, style.cooldown_shade)
		else:
			var h: float = s.y * frac
			draw_rect(Rect2(Vector2(0, s.y - h), Vector2(s.x, h)), style.cooldown_shade)
		var secs: String = ("%.1f" % left) if left < 3.0 else str(ceili(left))
		_text(secs, c + Vector2(0, style.count_font_size * 0.36), style.count_font_size, style.text_color, true)
	# What opens it.
	var note: String = String(data.get("note", ""))
	if st == LOCKED:
		_lock(c + Vector2(0, -r * 0.18), r * 0.26)
	if not note.is_empty():
		_text(note, Vector2(c.x, c.y + r * (0.62 if is_round else 0.78)), maxi(10, style.key_font_size - 3), Color(1, 1, 1, 0.85), true)
	# A count on it (arrows).
	var count: int = int(data.get("count", -1))
	if count >= 0:
		_text(str(count), Vector2(s.x - 4.0, s.y - 5.0), style.key_font_size, style.text_color, false, HORIZONTAL_ALIGNMENT_RIGHT)
	# The edge: the stance color while Q E R F are abilities.
	var edge: Color = style.stance_border if lit and st != EMPTY else style.slot_border
	if st == EMPTY:
		edge.a *= 0.45
	elif st == CHOOSE:
		edge = style.ring_fill.lerp(Color.WHITE, 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) / 180.0))
	_edge(c, r, s, edge)
	# The flash as it fires.
	var since: float = float(Time.get_ticks_msec() - _flash_ms) / 1000.0
	if since < FLASH_S:
		var f: Color = style.fire_flash
		f.a *= 1.0 - since / FLASH_S
		_fill(c, r, s, f)
	# Its key, in the corner (square) or on a small pill under it (round).
	var key: String = String(data.get("key", ""))
	if not key.is_empty():
		if is_round:
			var at: Vector2 = Vector2(c.x, s.y + 4.0)
			var w: float = maxf(18.0, 9.0 * key.length() + 8.0)
			draw_rect(Rect2(at - Vector2(w * 0.5, 9.0), Vector2(w, 16.0)), Color(0, 0, 0, 0.75))
			_text(key, at + Vector2(0, 3.5), style.key_font_size - 2, style.key_color, true)
		else:
			var kfs: int = style.key_font_size - (3 if s.x < float(style.slot_size) - 1.0 else 0)
			_text(key, Vector2(4.0, kfs + 1.0), kfs, style.key_color, false, HORIZONTAL_ALIGNMENT_LEFT)


func _fill(c: Vector2, r: float, s: Vector2, color: Color) -> void:
	if style.round_slots():
		draw_circle(c, r, color)
	else:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.set_corner_radius_all(style.corner_radius)
		draw_style_box(box, Rect2(Vector2.ZERO, s))


func _edge(c: Vector2, r: float, s: Vector2, color: Color) -> void:
	if style.round_slots():
		draw_arc(c, r - style.border_width * 0.5, 0.0, TAU, 48, color, style.border_width, true)
	else:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = color
		box.set_border_width_all(int(style.border_width))
		box.set_corner_radius_all(style.corner_radius)
		draw_style_box(box, Rect2(Vector2.ZERO, s))


## A pie of `frac` of the circle, clockwise from the top (the part still to come back).
func _pie(c: Vector2, r: float, frac: float, color: Color) -> void:
	if frac <= 0.0:
		return
	var pts: PackedVector2Array = PackedVector2Array([c])
	var steps: int = maxi(3, ceili(48.0 * frac))
	var start: float = -PI * 0.5
	for i: int in steps + 1:
		var a: float = start + TAU * (1.0 - frac) + TAU * frac * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, color)


## A MARK FOR WHAT IT DOES, until it has an icon (`icons/ability_<id>.png`, which wins): drawn on `ci` round `c`,
## `r` its size. "roll" a turning arrow; "bolt" a missile and its tail; "area" a ring on the ground; "blink" a jump
## through a gap; "cone" a fan; "lunge" an arrow forward; "strike" a cut.
static func draw_mark(ci: CanvasItem, mark: String, c: Vector2, r: float, col: Color) -> void:
	var w: float = maxf(2.0, r * 0.2)
	match mark:
		"roll":
			var to_a: float = deg_to_rad(420.0)
			ci.draw_arc(c, r, deg_to_rad(150.0), to_a, 24, col, w, true)
			_head(ci, c + Vector2(cos(to_a), sin(to_a)) * r, Vector2(-sin(to_a), cos(to_a)), r * 0.5, col)
		"bolt":
			var head: Vector2 = c + Vector2(r * 0.35, -r * 0.35)
			var back: Vector2 = Vector2(-1, 1).normalized()
			var side: Vector2 = Vector2(1, 1).normalized()
			for k: int in 3:
				var off: Vector2 = side * r * 0.22 * float(k - 1)
				ci.draw_line(head + off * 0.6, head + back * r * (1.3 - 0.25 * absf(float(k - 1))) + off, Color(col, col.a * (0.9 - 0.25 * absf(float(k - 1)))), w * 0.8, true)
			ci.draw_circle(head, r * 0.38, col)
		"area":
			ci.draw_arc(c + Vector2(0, r * 0.15), r * 0.9, 0.0, TAU, 32, col, w, true)
			ci.draw_arc(c + Vector2(0, r * 0.15), r * 0.45, 0.0, TAU, 24, Color(col, col.a * 0.7), w * 0.8, true)
			for k: int in 4:
				var a: float = TAU * float(k) / 4.0 + PI * 0.25
				ci.draw_line(c + Vector2(0, r * 0.15) + Vector2(cos(a), sin(a)) * r * 0.55, c + Vector2(0, r * 0.15) + Vector2(cos(a), sin(a)) * r * 0.8, col, w * 0.7, true)
		"blink":
			ci.draw_circle(c + Vector2(-r * 0.7, r * 0.35), r * 0.18, Color(col, col.a * 0.45))
			for k: int in 3:
				ci.draw_circle(c + Vector2(-r * 0.3 + r * 0.22 * float(k), r * 0.15 - r * 0.12 * float(k)), r * 0.07, Color(col, col.a * 0.7))
			ci.draw_line(c + Vector2(r * 0.25, -r * 0.1), c + Vector2(r * 0.8, -r * 0.55), col, w, true)
			_head(ci, c + Vector2(r * 0.85, -r * 0.6), Vector2(1, -0.8).normalized(), r * 0.45, col)
		"cone":
			var pts: PackedVector2Array = PackedVector2Array([c + Vector2(-r * 0.8, 0)])
			for k: int in 9:
				var a: float = deg_to_rad(-35.0 + 70.0 * float(k) / 8.0)
				pts.append(c + Vector2(-r * 0.8, 0) + Vector2(cos(a), sin(a)) * r * 1.6)
			pts.append(c + Vector2(-r * 0.8, 0))
			ci.draw_polyline(pts, col, w, true)
			for k: int in 2:
				ci.draw_arc(c + Vector2(-r * 0.8, 0), r * (0.7 + 0.45 * float(k)), deg_to_rad(-25.0), deg_to_rad(25.0), 8, Color(col, col.a * 0.7), w * 0.7, true)
		"lunge":
			ci.draw_line(c + Vector2(-r * 0.85, r * 0.0), c + Vector2(r * 0.55, 0), col, w * 1.2, true)
			_head(ci, c + Vector2(r * 0.9, 0), Vector2.RIGHT, r * 0.55, col)
			for k: int in 2:
				ci.draw_line(c + Vector2(-r * 0.9, -r * 0.35 + r * 0.7 * float(k)), c + Vector2(-r * 0.35, -r * 0.35 + r * 0.7 * float(k)), Color(col, col.a * 0.55), w * 0.7, true)
		"strike":
			ci.draw_arc(c + Vector2(-r * 0.5, r * 0.5), r * 1.15, deg_to_rad(-80.0), deg_to_rad(-10.0), 16, col, w * 1.3, true)
			ci.draw_arc(c + Vector2(-r * 0.5, r * 0.5), r * 0.8, deg_to_rad(-75.0), deg_to_rad(-15.0), 12, Color(col, col.a * 0.55), w * 0.8, true)


## An arrow's head at `tip`, pointing along `dir`.
static func _head(ci: CanvasItem, tip: Vector2, dir: Vector2, size_px: float, col: Color) -> void:
	var d: Vector2 = dir.normalized()
	var side: Vector2 = Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - d * size_px + side * size_px * 0.55, tip - d * size_px - side * size_px * 0.55]), col)


## A small padlock.
func _lock(c: Vector2, r: float) -> void:
	var col: Color = Color(1, 1, 1, 0.8)
	draw_arc(c + Vector2(0, -r * 0.2), r * 0.55, PI, TAU, 12, col, maxf(2.0, r * 0.22), true)
	draw_rect(Rect2(c + Vector2(-r * 0.85, -r * 0.2), Vector2(r * 1.7, r * 1.25)), col)


func _text(t: String, at: Vector2, fs: int, color: Color, centered: bool, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font: Font = ThemeDB.fallback_font
	var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = at.x - w * 0.5 if centered else (at.x - w if align == HORIZONTAL_ALIGNMENT_RIGHT else at.x)
	draw_string_outline(font, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
