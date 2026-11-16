class_name RegentsLogin extends ConnectScreen
## REGENT'S RULE'S FRONT DOOR (2026-11-15): the foundation's connect screen (the form, signing in, the character,
## settings: all `ConnectScreen`'s, unchanged) dressed for this game: the valley at dusk behind it, live
## (`LoginBackdrop` in a SubViewport of its own world), the game's name large above, the form lower down in a dark
## panel with a gold edge. The picture is built when the screen shows and freed when it hides, so play pays nothing
## for it. Its looks are this scene's exported values (Inspector); the picture's are `login_backdrop`'s.
##
## `regents_game.tscn`'s Boot names this scene as its `connect_screen`.

const BACKDROP: Script = preload("res://game/regents/showcase/login_backdrop.gd")

@export_group("Title")
@export var game_title: String = "REGENT'S RULE"
## A line under the name (empty: none; Luke, 2026-11-15: none).
@export var tagline: String = ""
@export var title_color: Color = Color(0.98, 0.9, 0.7)
@export var title_size: int = 84
## Serif faces asked of the system in order (nothing is shipped: no font file).
@export var title_fonts: PackedStringArray = PackedStringArray(["Cinzel", "Trajan Pro", "Palatino Linotype",
	"Book Antiqua", "Palatino", "Georgia", "Times New Roman", "serif"])
@export_group("Panel")
@export var panel_color: Color = Color(0.06, 0.05, 0.07, 0.82)
@export var edge_color: Color = Color(0.78, 0.62, 0.34, 0.85)
## Where the form sits: the top of the area it is centered in (share of the screen's height).
@export_range(0.0, 0.9, 0.01) var form_from: float = 0.36
@export_group("Title card")
## Open on the name alone over the valley with one Play button in the title's letters; the form shows when it is
## pressed (Luke, 2026-11-15: "card first"), or as soon as it connects by itself (auto-connect, `--host`), so its
## status is seen. Off: the form at once.
@export var title_card: bool = true
@export var play_text: String = "PLAY"
@export var play_size: int = 46
@export_group("Picture")
## Draw the valley behind the form (off: the foundation's plain backdrop).
@export var live_backdrop: bool = true

var _picture: SubViewportContainer = null
var _viewport: SubViewport = null
var _headline: VBoxContainer = null
var _shade: TextureRect = null
var _play: Button = null
## The card's Play was pressed: the form from now on.
var _played: bool = false


func _ready() -> void:
	super()
	_dress()
	visibility_changed.connect(_on_visibility)


## Is the valley built (the screen is showing)?
func has_picture() -> bool:
	return _viewport != null and _viewport.get_child_count() > 0


func _dress() -> void:
	var serif := SystemFont.new()
	serif.font_names = title_fonts
	serif.font_weight = 600
	# The picture first (beneath everything), then a shade for the words, then the title.
	_picture = SubViewportContainer.new()
	_picture.name = "Picture"
	_picture.stretch = true
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_picture)
	move_child(_picture, 0)
	_viewport = SubViewport.new()
	_viewport.name = "View"
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_picture.add_child(_viewport)
	var backdrop: ColorRect = get_node_or_null(^"Backdrop") as ColorRect
	_shade = TextureRect.new()
	_shade.name = "Shade"
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.7)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 256
	_shade.texture = tex
	add_child(_shade)
	move_child(_shade, 1)
	if backdrop != null:
		backdrop.visible = not live_backdrop
	_headline = VBoxContainer.new()
	_headline.name = "Headline"
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_headline.offset_top = 0.0
	_headline.add_theme_constant_override(&"separation", 2)
	add_child(_headline)
	move_child(_headline, 2)
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 60)
	top_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_headline.add_child(top_gap)
	var name_label := Label.new()
	name_label.name = "GameTitle"
	name_label.text = game_title
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override(&"font", serif)
	name_label.add_theme_font_size_override(&"font_size", title_size)
	name_label.add_theme_color_override(&"font_color", title_color)
	name_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.75))
	name_label.add_theme_constant_override(&"shadow_offset_x", 0)
	name_label.add_theme_constant_override(&"shadow_offset_y", 4)
	name_label.add_theme_constant_override(&"shadow_outline_size", 14)
	name_label.add_theme_color_override(&"font_outline_color", Color(0.18, 0.1, 0.04, 0.9))
	name_label.add_theme_constant_override(&"outline_size", 3)
	_headline.add_child(name_label)
	if not tagline.is_empty():
		_headline.add_child(_tagline_label(serif))
	_play = _play_button(serif)
	add_child(_play)
	# The form: lower down, in the game's panel; the panel's own small title goes (the headline says it).
	var center: Control = get_node(^"Center") as Control
	center.anchor_top = form_from
	var panel: PanelContainer = get_node_or_null(^"Center/Panel") as PanelContainer
	if panel != null:
		var box := StyleBoxFlat.new()
		box.bg_color = panel_color
		box.border_color = edge_color
		box.set_border_width_all(1)
		box.border_width_top = 2
		box.set_corner_radius_all(4)
		box.shadow_color = Color(0, 0, 0, 0.55)
		box.shadow_size = 18
		panel.add_theme_stylebox_override(&"panel", box)
	var small_title: Label = get_node_or_null(^"Center/Panel/Margin/VBox/Title") as Label
	if small_title != null:
		small_title.visible = false
	_show_card(title_card)


func _tagline_label(serif: Font) -> Label:
	var line := Label.new()
	line.name = "Tagline"
	line.text = tagline.to_upper()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_override(&"font", serif)
	line.add_theme_font_size_override(&"font_size", 20)
	line.add_theme_color_override(&"font_color", Color(title_color, 0.8))
	line.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	line.add_theme_constant_override(&"shadow_outline_size", 3)
	line.add_theme_constant_override(&"shadow_offset_y", 2)
	return line


## The card's one button: the word in the title's letters and colors, a gold edge drawn round it on hover.
func _play_button(serif: Font) -> Button:
	var b := Button.new()
	b.name = "Play"
	b.text = play_text
	b.flat = false
	b.focus_mode = Control.FOCUS_ALL
	b.set_anchors_preset(Control.PRESET_CENTER)
	b.anchor_top = form_from + 0.2
	b.anchor_bottom = form_from + 0.2
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_BOTH
	b.custom_minimum_size = Vector2(260, 0)
	b.add_theme_font_override(&"font", serif)
	b.add_theme_font_size_override(&"font_size", play_size)
	b.add_theme_color_override(&"font_color", title_color)
	b.add_theme_color_override(&"font_hover_color", title_color.lightened(0.25))
	b.add_theme_color_override(&"font_pressed_color", title_color.darkened(0.15))
	b.add_theme_color_override(&"font_focus_color", title_color)
	b.add_theme_color_override(&"font_outline_color", Color(0.18, 0.1, 0.04, 0.9))
	b.add_theme_constant_override(&"outline_size", 3)
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(panel_color, 0.35)
	idle.border_color = Color(edge_color, 0.55)
	idle.border_width_top = 1
	idle.border_width_bottom = 1
	idle.content_margin_left = 36.0
	idle.content_margin_right = 36.0
	idle.content_margin_top = 6.0
	idle.content_margin_bottom = 8.0
	var hover: StyleBoxFlat = idle.duplicate() as StyleBoxFlat
	hover.bg_color = Color(panel_color, 0.6)
	hover.border_color = edge_color
	b.add_theme_stylebox_override(&"normal", idle)
	b.add_theme_stylebox_override(&"hover", hover)
	b.add_theme_stylebox_override(&"pressed", hover)
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.pressed.connect(_on_play)
	return b


## The card (only the Play button) or the form.
func _show_card(card: bool) -> void:
	var center: Control = get_node_or_null(^"Center") as Control
	if center != null:
		center.visible = not card
	if _play != null:
		_play.visible = card


## Play pressed: the form, for good.
func _on_play() -> void:
	_played = true
	_show_card(false)
	if is_open() and not is_connecting():
		_connect.grab_focus()


## Connecting by itself (auto-connect, a `--host` launch): the card steps aside so the form's status shows.
func _process(delta: float) -> void:
	super(delta)
	if showing_card() and is_connecting():
		_on_play()


## Is it showing the card (the Play button, no form)?
func showing_card() -> bool:
	return _play != null and _play.visible


func _on_visibility() -> void:
	if not live_backdrop:
		return
	if visible and title_card and not _played:
		_show_card(true)
	if visible and not has_picture():
		_viewport.add_child(BACKDROP.new() as Node3D)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif not visible and has_picture():
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		for c: Node in _viewport.get_children():
			_viewport.remove_child(c)
			c.queue_free()
