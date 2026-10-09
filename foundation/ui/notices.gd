class_name Notices extends CanvasLayer
## WHAT THE GAME HAS TO TELL THE PLAYER, BRIEFLY (DECISIONS #202): every
## `SignalBus.notification_requested` ("Lost connection to server.", "the name 'Luke' is taken"),
## shown at the top of the screen and gone after a few seconds. Boot adds one to every game scene,
## outside the HUD, so a genre that brings its own HUD keeps them.
##
## severity: 0 information, 1 a warning, 2 something went wrong.

const SECONDS: float = 6.0
const MAX_SHOWN: int = 4
const COLOURS: Array[Color] = [Color(0.92, 0.92, 0.92), Color(1.0, 0.85, 0.45), Color(1.0, 0.5, 0.45)]

var _box: VBoxContainer


func _ready() -> void:
	layer = 50
	_box = VBoxContainer.new()
	_box.name = "Box"
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_box.position.y = 56.0
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	SignalBus.notification_requested.connect(show_notice)


## Show one now (also what the signal does).
func show_notice(text: String, severity: int = 0) -> void:
	if text.strip_edges().is_empty():
		return
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override(&"font_color", COLOURS[clampi(severity, 0, COLOURS.size() - 1)])
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(l)
	while _box.get_child_count() > MAX_SHOWN:
		_box.get_child(0).free()
	var t: Tween = l.create_tween()
	t.tween_interval(SECONDS)
	t.tween_property(l, ^"modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


## What is on screen now (tests).
func shown() -> PackedStringArray:
	var out := PackedStringArray()
	for c: Node in _box.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append((c as Label).text)
	return out
