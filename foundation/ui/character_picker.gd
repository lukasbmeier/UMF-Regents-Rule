class_name CharacterPicker extends CenterContainer
## THE CHARACTER PICKER (DECISIONS #166, #178): choose a look to start from, then change whatever
## that look offers (the fishing game's: every piece, slot by slot, and their colours), with the
## character turning in front of you as it will be drawn.
##
## Generic: the looks are the player definition's `visual_variants`, in order, and the choices are
## whatever the look's model offers (`appearance_options()` on its root: a list of {key, label,
## choices, swatches, beside}); a model without that method offers none. An option with `beside`
## shares that option's row. The options are asked for again after every choice, as the model now
## stands (a new piece may have other colours), and a choice the new options do not have is
## dropped. The picker never knows what a key means: it writes `Appearance` text and hands it to
## `apply_appearance` on the preview.
##
## Opened from the connect screen and the Escape menu (boot builds one for each). Done emits
## `chosen` with the text; boot remembers it (ConnectSettings) and, connected, tells the server
## (`set_appearance`), whose row every client then dresses that player by.

signal closed()
## Done: the look chosen, as `Appearance` text.
signal chosen(appearance: String)

const PREVIEW_SIZE: Vector2i = Vector2i(340, 480)
## Degrees a second the preview turns by itself.
const TURN_DEG_PER_SEC: float = 24.0

## Whose looks: the player's definition (its variants, model yaw and animation set).
var definition: EntityDefinition = null
## The look chosen so far (Done hands it on). Set before `open()` to start from it.
var appearance: String = ""

var _names: PackedStringArray = PackedStringArray()
var _index: int = 0
var _picked: Dictionary = {}
var _viewport: SubViewport = null
var _turntable: Node3D = null
var _model: Node3D = null
var _name_label: Label = null
var _options_box: VBoxContainer = null
var _drag: bool = false


func _init() -> void:
	name = "CharacterPicker"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	_names = definition.variant_names() if definition != null else PackedStringArray()
	_index = maxi(_names.find(Appearance.look_name(appearance)), 0)
	_picked = Appearance.choices(appearance)
	_build()
	_show_look()
	visible = true
	(find_child("Done", true, false) as Button).grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_clear_model()
	closed.emit()


func is_open() -> bool:
	return visible


## The look shown now, as text (what Done would hand on).
func current() -> String:
	return Appearance.make(_names[_index], _picked) if not _names.is_empty() else ""


## The model on the turntable (tests look at it).
func preview_model() -> Node3D:
	return _model


## Step through the looks: +1 next, -1 previous.
func step(by: int) -> void:
	if _names.is_empty():
		return
	_index = posmod(_index + by, _names.size())
	_show_look()


## Choose `index` for option `key` (0 = the look's own).
func pick(key: String, index: int) -> void:
	_picked[key] = index
	_show_model()
	_build_options()


func _process(delta: float) -> void:
	if visible and _turntable != null and not _drag:
		_turntable.rotate_y(deg_to_rad(TURN_DEG_PER_SEC) * delta)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# --- building ------------------------------------------------------------------------------

func _build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", SettingsPanel._panel_style())
	add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	margin.add_child(row)
	row.add_child(_build_preview())
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.add_theme_constant_override(&"separation", 12)
	row.add_child(side)
	var title := Label.new()
	title.text = "Character"
	title.add_theme_font_size_override(&"font_size", 22)
	side.add_child(title)
	var start := Label.new()
	start.text = "Start from a look"
	start.modulate = Color(1, 1, 1, 0.6)
	side.add_child(start)
	var looks := HBoxContainer.new()
	var prev := Button.new()
	prev.name = "Previous"
	prev.text = "<"
	prev.custom_minimum_size = Vector2(36, 34)
	prev.pressed.connect(func() -> void: step(-1))
	_name_label = Label.new()
	_name_label.name = "LookName"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var next := Button.new()
	next.name = "Next"
	next.text = ">"
	next.custom_minimum_size = Vector2(36, 34)
	next.pressed.connect(func() -> void: step(1))
	looks.add_child(prev)
	looks.add_child(_name_label)
	looks.add_child(next)
	side.add_child(looks)
	var change := Label.new()
	change.text = "Then change any part"
	change.modulate = Color(1, 1, 1, 0.6)
	side.add_child(change)
	var scroll := ScrollContainer.new()
	scroll.name = "OptionsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	_options_box = VBoxContainer.new()
	_options_box.name = "Options"
	_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_box.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_options_box)
	var hint := Label.new()
	hint.text = "Drag the character to turn it. Everyone sees what you pick."
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.add_theme_font_size_override(&"font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	var done := Button.new()
	done.name = "Done"
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 36)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(func() -> void:
		appearance = current()
		chosen.emit(appearance)
		close())
	var cancel := Button.new()
	cancel.name = "Cancel"
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(96, 36)
	cancel.pressed.connect(close)
	buttons.add_child(done)
	buttons.add_child(cancel)
	side.add_child(buttons)


func _build_preview() -> Control:
	var holder := SubViewportContainer.new()
	holder.name = "Preview"
	holder.stretch = true
	holder.custom_minimum_size = Vector2(PREVIEW_SIZE)
	holder.gui_input.connect(_on_preview_input)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = PREVIEW_SIZE
	holder.add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.7
	_viewport.add_child(env)
	# A key light from the front left, a softer fill from the front right, and a rim from behind.
	for l: Array in [[Vector3(-30.0, -35.0, 0.0), 1.2], [Vector3(-15.0, 40.0, 0.0), 0.45], [Vector3(-20.0, 180.0, 0.0), 0.6]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = l[0]
		light.light_energy = float(l[1])
		_viewport.add_child(light)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.05, 3.3)
	cam.fov = 34.0
	_viewport.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.92, 0.0))
	cam.current = true
	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_viewport.add_child(_turntable)
	return holder


func _on_preview_input(event: InputEvent) -> void:
	var b: InputEventMouseButton = event as InputEventMouseButton
	if b != null and b.button_index == MOUSE_BUTTON_LEFT:
		_drag = b.pressed
	var m: InputEventMouseMotion = event as InputEventMouseMotion
	if m != null and _drag and _turntable != null:
		_turntable.rotate_y(deg_to_rad(m.relative.x * 0.6))


# --- showing -------------------------------------------------------------------------------

## A new look: its name, its own choices, and the model.
func _show_look() -> void:
	if _names.is_empty():
		_name_label.text = "(no looks)"
		return
	_name_label.text = _names[_index].capitalize()
	_show_model()
	_build_options()


## The model as chosen, built fresh: a choice of 0 is the look's own, which only a fresh model has.
func _show_model() -> void:
	_clear_model()
	if _names.is_empty() or definition == null:
		return
	var scene: PackedScene = definition.variant_named(_names[_index])
	if scene == null:
		return
	var model: Node = scene.instantiate()
	if model.has_method(&"apply_appearance"):
		model.call(&"apply_appearance", current())
	_model = model as Node3D
	if _model == null:
		model.free()
		return
	# Facing the camera: the definition's yaw turns the model to the game's forward (-Z, away from
	# this camera), so half a turn more shows its face.
	_model.rotation.y = deg_to_rad(definition.visual_yaw_deg + 180.0)
	_turntable.add_child(_model)
	play_idle(_model, definition)


func _build_options() -> void:
	for c: Node in _options_box.get_children():
		_options_box.remove_child(c)
		c.queue_free()
	if _model == null or not _model.has_method(&"appearance_options"):
		return
	var options: Array = _model.call(&"appearance_options")
	var rows: Dictionary[String, HBoxContainer] = {}
	var offered: Dictionary[String, int] = {}
	for o: Variant in options:
		var opt: Dictionary = o as Dictionary
		var key: String = String(opt.get("key", ""))
		var labels: PackedStringArray = PackedStringArray(opt.get("choices", PackedStringArray()))
		offered[key] = labels.size()
		var row: HBoxContainer = rows.get(String(opt.get("beside", "")), null)
		if row == null:
			row = HBoxContainer.new()
			row.name = "Row_" + key
			row.add_theme_constant_override(&"separation", 6)
			var label := Label.new()
			label.text = String(opt.get("label", key))
			label.custom_minimum_size = Vector2(84, 0)
			row.add_child(label)
			_options_box.add_child(row)
			rows[key] = row
		var pick_button := OptionButton.new()
		pick_button.name = key
		pick_button.tooltip_text = String(opt.get("label", key))
		pick_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick_button.clip_text = true
		var swatches: Array = opt.get("swatches", [])
		for i: int in range(labels.size()):
			var sw: Color = swatches[i] if i < swatches.size() else Color(0, 0, 0, 0)
			if sw.a > 0.0:
				pick_button.add_icon_item(_swatch(sw), labels[i])
			else:
				pick_button.add_item(labels[i])
		pick_button.select(clampi(int(_picked.get(key, 0)), 0, maxi(labels.size() - 1, 0)))
		pick_button.item_selected.connect(func(i: int) -> void: pick(key, i))
		row.add_child(pick_button)
	# A choice this model does not offer (a colourway the new piece lacks) is not part of the look.
	var stale: bool = false
	for key: Variant in _picked.keys():
		if int(_picked[key]) >= int(offered.get(String(key), 0)) and int(_picked[key]) > 0:
			_picked.erase(key)
			stale = true
	if stale:
		_show_model()


func _clear_model() -> void:
	if _model != null:
		if _model.get_parent() != null:
			_model.get_parent().remove_child(_model)
		_model.queue_free()
		_model = null


## The definition's idle, looping, so the look stands as it will in the game (the picker's preview
## and the lobby screen's stage).
static func play_idle(model: Node3D, definition: EntityDefinition) -> void:
	if definition == null:
		return
	var set: AnimationSet = definition.animation_set
	if set == null or not set.has_exact(AnimationSet.IDLE):
		return
	var skel: Skeleton3D = _find_skeleton(model)
	if skel == null:
		return
	var player := AnimationPlayer.new()
	player.name = "PickerIdle"
	model.add_child(player)
	player.root_node = player.get_path_to(skel.get_parent())
	for lib: StringName in set.libraries:
		player.add_animation_library(lib, set.libraries[lib])
	var anim: StringName = set.anim_name(AnimationSet.IDLE)
	if player.has_animation(anim):
		# Again when it ends, rather than changing the clip's loop: the library is the game's own.
		player.animation_finished.connect(func(_n: StringName) -> void: player.play(anim))
		player.play(anim)


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.get_children():
		var s: Skeleton3D = _find_skeleton(c)
		if s != null:
			return s
	return null


static func _swatch(c: Color) -> ImageTexture:
	var img: Image = Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)
