class_name TimingBar extends Control
## THE TIMED PRESS ON SCREEN (DECISIONS #210): the bar, the target for this press, the marker sweeping
## by the server's clock, a pip per press (what this client predicted, then what the server judged),
## and, under the bar, a strip for each RECENT press, across checks, NEWEST AT THE TOP, flowing down
## as more are made (DECISIONS #214, #215, #216): that press's zone (lighter, its Great band brighter), a WHITE line where the marker was
## drawn when it was pressed and an ORANGE one where the server judged it, so a player can tell their
## timing from the game's. A word for the last press ("Great", "Good", "Miss"). After the last press
## it all stays until the player moves away, or 15 s (`TimedPressComponent.results_linger_s`). It reads the local player's
## `TimedPressComponent` every frame and owns nothing. The foundation's HUD carries one; a genre's
## HUD adds its own with `TimingBar.new()`.

const BAR_SIZE: Vector2 = Vector2(360, 18)
## The height of each press's strip under the bar.
const HISTORY_ROW: float = 10.0

var _label: Label
var _state: Dictionary = {}


func _init() -> void:
	name = "TimingBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -BAR_SIZE.x / 2.0
	offset_right = BAR_SIZE.x / 2.0
	offset_top = -240
	offset_bottom = -190
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, -24)
	_label.size = Vector2(BAR_SIZE.x, 22)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	visible = false


func _process(_delta: float) -> void:
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity \
		if EntityRegistry.local_entity_id >= 0 else null
	show_state(state_for(me))


## What the bar shows for `me`: {visible, text, marker, target, half, pips: [[predicted, judged]]}.
static func state_for(me: SpaceTimeEntity) -> Dictionary:
	var none: Dictionary = {"visible": false, "text": "", "marker": 0.0, "target": 0.5, "half": 0.0, "pips": [], "judged": [], "history": []}
	if me == null or not is_instance_valid(me):
		return none
	var tp: TimedPressComponent = me.find_component(TimedPressComponent) as TimedPressComponent
	if tp == null:
		return none
	var id: int = tp.current()
	var last: Dictionary = tp.last_judged
	var word: String = word_for(float(last["quality"])) if not last.is_empty() else ""
	if id < 0:
		# Finished: the results stay until the player moves away, or a while (`results_visible`).
		if not tp.results_visible():
			return none
		return {"visible": true, "text": word, "marker": float(last["position"]), "target": float(last.get("target", 0.5)),
			"half": float(last.get("half", 0.0)), "pips": _pips(tp, int(last["challenge_id"])),
			"judged": [], "history": newest_first(tp)}
	var round: int = tp.presses_made(id)
	var text: String = "Get ready…" if tp.elapsed(id) < 0.0 else "Press %s  (%d of %d)%s" % [HoldPrompt.key_name(), round + 1, tp.rounds(id),
		("   " + word) if not word.is_empty() and int(last["challenge_id"]) == id else ""]
	return {"visible": true, "text": text, "marker": tp.marker(id), "target": tp.target(id, round), "half": tp.half_width(id), "pips": _pips(tp, id),
		"judged": tp.judged_positions(id), "history": newest_first(tp)}


## The recent presses as the strips show them: newest at the top (Luke: "like it's flowing down").
static func newest_first(tp: TimedPressComponent) -> Array[Dictionary]:
	var out: Array[Dictionary] = tp.recent_presses()
	out.reverse()
	return out


static func _pips(tp: TimedPressComponent, id: int) -> Array:
	var out: Array = []
	var p: Array = tp.predictions(id)
	var q: Array = tp.qualities(id)
	for i: int in tp.rounds(id):
		out.append([float(p[i]) if i < p.size() else -1.0, float(q[i]) if i < q.size() else -1.0])
	return out


## "Great", "Good", "Miss": a word for a press's quality.
static func word_for(q: float) -> String:
	if q >= 0.75:
		return "Great"
	if q > 0.0:
		return "Good"
	return "Miss"


func show_state(s: Dictionary) -> void:
	_state = s
	visible = bool(s["visible"])
	_label.text = String(s["text"])
	queue_redraw()


func _draw() -> void:
	if _state.is_empty() or not bool(_state["visible"]):
		return
	var w: float = BAR_SIZE.x
	draw_rect(Rect2(Vector2.ZERO, BAR_SIZE), Color(0, 0, 0, 0.55))
	var half: float = float(_state["half"])
	var t: float = float(_state["target"])
	draw_rect(Rect2(Vector2((t - half) * w, 0), Vector2(half * 2.0 * w, BAR_SIZE.y)), Color(0.3, 0.8, 0.4, 0.6))
	draw_rect(Rect2(Vector2((t - half * 0.25) * w, 0), Vector2(half * 0.5 * w, BAR_SIZE.y)), Color(0.5, 1.0, 0.5, 0.8))
	var m: float = float(_state["marker"]) * w
	draw_rect(Rect2(Vector2(m - 2.0, -4.0), Vector2(4.0, BAR_SIZE.y + 8.0)), Color.WHITE)
	# Each press made: its own zone, where it was drawn when pressed (white), where it was judged (orange).
	var history: Array = _state.get("history", []) as Array
	for i: int in history.size():
		var h: Dictionary = history[i]
		var y: float = BAR_SIZE.y + 6.0 + float(i) * (HISTORY_ROW + 2.0)
		var hh: float = float(h["half"])
		var ht: float = float(h["target"])
		draw_rect(Rect2(Vector2(0, y), Vector2(w, HISTORY_ROW)), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(Vector2((ht - hh) * w, y), Vector2(hh * 2.0 * w, HISTORY_ROW)), Color(0.55, 0.95, 0.75, 0.35))
		draw_rect(Rect2(Vector2((ht - hh * 0.25) * w, y), Vector2(hh * 0.5 * w, HISTORY_ROW)), Color(0.7, 1.0, 0.85, 0.6))
		draw_rect(Rect2(Vector2(float(h["pressed"]) * w - 1.0, y - 1.0), Vector2(2.0, HISTORY_ROW + 2.0)), Color.WHITE)
		if float(h["judged"]) >= 0.0:
			draw_rect(Rect2(Vector2(float(h["judged"]) * w - 1.0, y - 1.0), Vector2(2.0, HISTORY_ROW + 2.0)), Color(1.0, 0.6, 0.2, 1.0))
	var pip_y: float = float(history.size()) * (HISTORY_ROW + 2.0)
	var pips: Array = _state["pips"]
	for i: int in pips.size():
		var judged_q: float = float(pips[i][1])
		var guess: float = float(pips[i][0])
		var q: float = judged_q if judged_q >= 0.0 else guess
		var c: Color = Color(0.4, 0.4, 0.4) if q < 0.0 else (Color(0.4, 1.0, 0.5) if q >= 0.75 else (Color(1.0, 0.85, 0.3) if q > 0.0 else Color(1.0, 0.35, 0.3)))
		if judged_q < 0.0 and guess >= 0.0:
			c.a = 0.5   # predicted, not yet judged
		draw_circle(Vector2(w / 2.0 + (i - (pips.size() - 1) / 2.0) * 18.0, BAR_SIZE.y + 14.0 + pip_y), 5.0, c)
