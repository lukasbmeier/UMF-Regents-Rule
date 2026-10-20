class_name UiKit extends RefCounted
## SMALL PIECES FOR A WINDOW'S ROWS (DECISIONS #265), drawn by the game's `UiStyle` so a reskin reaches them:
## a heading, a note, a line in a role's colour (good / warn / bad), a button, a slot grid, a divider.


## A heading: the style's title look.
static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"UiTitle"
	return l


## A small, dim note. It wraps, so it is given a width to wrap at (`NOTE_WIDTH`, and the row's when wider):
## a wrapping label measured at no width wraps a letter a line and stretches its window down the screen.
static func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"UiNote"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(NOTE_WIDTH, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## The narrowest a note wraps at.
const NOTE_WIDTH: float = 240.0


## A line of text in a role's colour: "text", "dim", "accent", "good", "warn", "bad". One line (a note wraps).
static func line(text: String, role: StringName = &"text") -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override(&"font_color", colour(role))
	return l


## A role's colour in the game's style.
static func colour(role: StringName) -> Color:
	var s: UiStyle = UiStyle.current()
	match role:
		&"dim":
			return s.text_dim
		&"accent":
			return s.accent
		&"good":
			return s.good
		&"warn":
			return s.warn
		&"bad":
			return s.bad
	return s.text


## A button the style's height, named `node_name` when given (tests find it by name).
static func button(text: String, node_name: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if not node_name.is_empty():
		b.name = node_name
	b.custom_minimum_size = Vector2(0, UiStyle.current().button_height)
	return b


## A grid for slots, `columns` wide.
static func slot_grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override(&"h_separation", 6)
	g.add_theme_constant_override(&"v_separation", 6)
	return g


static func divider() -> HSeparator:
	return HSeparator.new()
