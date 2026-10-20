@tool
class_name UiStyle extends Resource
## THE GAME'S LOOK, IN ONE FILE (DECISIONS #265): the colours, sizes and fonts every window, button, list,
## slot and tooltip is drawn with. `theme()` turns them into a Godot `Theme`, and Boot puts it on the
## window's root, so every Control in the game (the foundation's Escape menu and settings, a genre's
## inventory and crafting windows) looks the same without styling itself.
##
## TO RESKIN A GAME (a fantasy look: parchment, gold, a serif title font): make a `.tres` of this, change
## what you like in the Inspector, and point the project setting `umf/ui/style` at it. Nothing else
## changes. Without the setting a game has the foundation's: this file's defaults (the Escape menu's
## dark blue panel).
##
## HOW IT REACHES EVERYTHING: it is merged into Godot's DEFAULT theme (`ThemeDB`), the theme every Control
## falls back to. A theme set on the root window does not do: it stops at the first plain Node between a
## control and the window (a HUD's CanvasLayer under a Node), so half the game kept Godot's look.
##
## A screen that needs a colour not in the theme (an item's own, a warning) asks this for it by role
## (`good`, `warn`, `bad`, `text_dim`) rather than typing one, so a reskin reaches it too.

const SETTING: String = "umf/ui/style"

@export_group("Panels")
## A window's or a menu's background, and its edge.
@export var panel_bg: Color = Color(0.1, 0.12, 0.15, 0.96)
@export var panel_border: Color = Color(0.3, 0.45, 0.6, 0.6)
## A window's title bar.
@export var title_bg: Color = Color(0.14, 0.18, 0.23, 1.0)
@export var corner_radius: int = 8
@export var border_width: int = 1
@export var shadow_size: int = 12
## Inside a window, round its content.
@export var padding: int = 16
## Between rows and items.
@export var gap: int = 8

@export_group("Text")
@export var text: Color = Color(0.9, 0.92, 0.95)
## Notes, hints, what is not available.
@export var text_dim: Color = Color(0.9, 0.92, 0.95, 0.55)
## Titles and what is picked.
@export var accent: Color = Color(0.55, 0.78, 1.0)
@export var good: Color = Color(0.55, 0.95, 0.6)
@export var warn: Color = Color(1.0, 0.82, 0.45)
@export var bad: Color = Color(1.0, 0.55, 0.5)
@export var font_size: int = 16
@export var title_size: int = 22
@export var small_size: int = 13
## Empty: Godot's own. A game's fantasy face goes here.
@export var font: Font
@export var title_font: Font

@export_group("Buttons")
@export var button_bg: Color = Color(0.18, 0.23, 0.3, 1.0)
@export var button_hover: Color = Color(0.24, 0.32, 0.42, 1.0)
@export var button_pressed: Color = Color(0.3, 0.45, 0.6, 1.0)
@export var button_disabled: Color = Color(0.14, 0.16, 0.19, 0.8)
@export var button_height: int = 36
@export var button_radius: int = 6

@export_group("Slots")
## An item slot (a bag square), and one picked.
@export var slot_bg: Color = Color(0.07, 0.09, 0.11, 0.95)
@export var slot_border: Color = Color(0.25, 0.32, 0.4, 0.8)
@export var slot_selected: Color = Color(0.55, 0.78, 1.0, 1.0)
@export var slot_size: int = 56
## An item's GRADE, as a colour (DECISIONS #267): the edge of its slot and its name. Index 0 is the lowest
## grade (a game's Common), each next one better; a game with more grades lists more.
@export var grade_colors: PackedColorArray = PackedColorArray([Color(0.72, 0.74, 0.78), Color(0.4, 0.85, 0.45), Color(1.0, 0.76, 0.28)])

static var _current: UiStyle = null
var _theme: Theme = null


## The game's style: the project's `umf/ui/style` file, else the foundation's defaults. Read once.
static func current() -> UiStyle:
	if _current == null:
		var path: String = String(ProjectSettings.get_setting(SETTING, "")) if ProjectSettings.has_setting(SETTING) else ""
		var loaded: UiStyle = load(path) as UiStyle if not path.is_empty() and ResourceLoader.exists(path) else null
		_current = loaded if loaded != null else UiStyle.new()
	return _current


## Use `style` from now on (a test, a settings screen that swaps themes): every Control is drawn with it.
static func use(style: UiStyle) -> void:
	_current = style
	ThemeDB.get_default_theme().merge_with(style.theme())


## Draw every Control with the game's style (Boot does, first thing). `_root` is kept for callers that
## pass their window; the style goes into the default theme either way.
static func apply(_root: Window = null) -> void:
	ThemeDB.get_default_theme().merge_with(current().theme())


## This style as a Godot `Theme`, built once.
func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	if font != null:
		t.default_font = font
	t.default_font_size = font_size
	t.set_stylebox(&"panel", &"PanelContainer", panel_style())
	t.set_stylebox(&"panel", &"Panel", panel_style())
	t.set_stylebox(&"panel", &"TooltipPanel", tooltip_style())
	t.set_color(&"font_color", &"TooltipLabel", text)
	t.set_color(&"font_color", &"Label", text)
	for kind: StringName in [&"Button", &"OptionButton", &"MenuButton", &"CheckButton", &"CheckBox"]:
		t.set_stylebox(&"normal", kind, _button(button_bg))
		t.set_stylebox(&"hover", kind, _button(button_hover))
		t.set_stylebox(&"pressed", kind, _button(button_pressed))
		t.set_stylebox(&"disabled", kind, _button(button_disabled))
		t.set_stylebox(&"focus", kind, _focus())
		t.set_color(&"font_color", kind, text)
		t.set_color(&"font_hover_color", kind, text)
		t.set_color(&"font_pressed_color", kind, text)
		t.set_color(&"font_disabled_color", kind, text_dim)
	t.set_stylebox(&"normal", &"LineEdit", _button(slot_bg))
	t.set_stylebox(&"focus", &"LineEdit", _focus())
	t.set_stylebox(&"panel", &"ItemList", _flat(slot_bg, slot_border, 1, button_radius))
	t.set_stylebox(&"selected", &"ItemList", _button(button_pressed))
	t.set_stylebox(&"selected_focus", &"ItemList", _button(button_pressed))
	t.set_stylebox(&"background", &"ProgressBar", _flat(slot_bg, slot_border, 1, 4))
	t.set_stylebox(&"fill", &"ProgressBar", _flat(accent.darkened(0.25), Color(0, 0, 0, 0), 0, 4))
	t.set_stylebox(&"panel", &"TabContainer", panel_style())
	t.set_stylebox(&"tab_selected", &"TabContainer", _tab(button_pressed))
	t.set_stylebox(&"tab_unselected", &"TabContainer", _tab(button_bg))
	t.set_stylebox(&"tab_hovered", &"TabContainer", _tab(button_hover))
	t.set_constant(&"separation", &"VBoxContainer", gap)
	t.set_constant(&"separation", &"HBoxContainer", gap)
	# A window's parts, by type variation (`UiWindow` sets them).
	t.add_type(&"UiTitleBar")
	t.set_type_variation(&"UiTitleBar", &"PanelContainer")
	t.set_stylebox(&"panel", &"UiTitleBar", title_style())
	t.add_type(&"UiTitle")
	t.set_type_variation(&"UiTitle", &"Label")
	t.set_font_size(&"font_size", &"UiTitle", title_size)
	t.set_color(&"font_color", &"UiTitle", accent)
	if title_font != null:
		t.set_font(&"font", &"UiTitle", title_font)
	t.add_type(&"UiNote")
	t.set_type_variation(&"UiNote", &"Label")
	t.set_font_size(&"font_size", &"UiNote", small_size)
	t.set_color(&"font_color", &"UiNote", text_dim)
	_theme = t
	return t


## A window's or menu's panel.
func panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = _flat(panel_bg, panel_border, border_width, corner_radius)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = shadow_size
	s.set_content_margin_all(padding)
	return s


## A window's title bar: the top of its panel.
func title_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = _flat(title_bg, Color(0, 0, 0, 0), 0, corner_radius)
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	s.content_margin_left = padding
	s.content_margin_right = padding * 0.5
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func tooltip_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = _flat(panel_bg, panel_border, border_width, button_radius)
	s.set_content_margin_all(8)
	return s


## An item slot's square, picked or not, its edge in `edge` when given (an item's own colour, or its
## grade's: then `width` 2, so a grade reads at a glance).
func slot_style(selected: bool, edge: Color = Color(0, 0, 0, 0), width: int = 1) -> StyleBoxFlat:
	var border: Color = slot_selected if selected else (edge if edge.a > 0.0 else slot_border)
	return _flat(slot_bg, border, 2 if selected else width, button_radius)


## Grade `grade`'s colour (0 the lowest); transparent for none (-1) or one this style has no colour for.
func grade_color(grade: int) -> Color:
	return grade_colors[grade] if grade >= 0 and grade < grade_colors.size() else Color(0, 0, 0, 0)


func _button(bg: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = _flat(bg, panel_border.darkened(0.2), 1, button_radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _tab(bg: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = _button(bg)
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	return s


func _focus() -> StyleBoxFlat:
	var s: StyleBoxFlat = _flat(Color(0, 0, 0, 0), accent, 1, button_radius)
	s.draw_center = false
	return s


static func _flat(bg: Color, edge: Color, width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	return s
