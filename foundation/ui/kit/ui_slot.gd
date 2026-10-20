class_name UiSlot extends Button
## AN ITEM SLOT (DECISIONS #265): a square in a bag, a recipe's inputs, a loot window. It shows the item's
## mark (`mark`: its icon when it has one, else its initials on its colour), how many (`count`, a corner
## number; 0 or 1 shows none), and whether it is picked; hovering shows `tooltip_text`. Click it (`pressed`).
## Drawn by the game's `UiStyle` (`slot_size`, `slot_style`), so a reskin reaches every slot.

## The item's colour: the edge, and the initials' tint.
var tint: Color = Color(0, 0, 0, 0):
	set(value):
		tint = value
		_restyle()
## Its picture, when it has one; else `mark` is written on the slot.
var picture: Texture2D = null:
	set(value):
		picture = value
		icon = value
		_mark_label.visible = value == null
## A short word for it when it has no picture: its initials.
var mark: String = "":
	set(value):
		mark = value
		_mark_label.text = value
var count: int = 0:
	set(value):
		count = value
		_count_label.text = str(value) if value > 1 else ""
var selected: bool = false:
	set(value):
		selected = value
		_restyle()

var _mark_label: Label = null
var _count_label: Label = null


func _init() -> void:
	expand_icon = true
	clip_contents = true
	_mark_label = Label.new()
	_mark_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark_label)
	_count_label = Label.new()
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.offset_left = -40
	_count_label.offset_top = -22
	_count_label.offset_right = -5
	_count_label.offset_bottom = -2
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.theme_type_variation = &"UiNote"
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)


func _ready() -> void:
	var style: UiStyle = UiStyle.current()
	custom_minimum_size = Vector2(style.slot_size, style.slot_size)
	_count_label.add_theme_color_override(&"font_color", style.text)
	_restyle()


## An item's initials, for `mark`: "Copper ore" -> "CO", "Logs" -> "Lo".
static func initials(item_name: String) -> String:
	var words: PackedStringArray = item_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return item_name.left(2)


func _restyle() -> void:
	if _mark_label == null:
		return
	var style: UiStyle = UiStyle.current()
	var normal: StyleBoxFlat = style.slot_style(selected, tint)
	var hover: StyleBoxFlat = style.slot_style(true, tint)
	for state: StringName in [&"normal", &"disabled"]:
		add_theme_stylebox_override(state, normal)
	for state: StringName in [&"hover", &"pressed", &"focus"]:
		add_theme_stylebox_override(state, hover if state != &"focus" else normal)
	_mark_label.add_theme_color_override(&"font_color", tint.lightened(0.35) if tint.a > 0.0 else style.text)
