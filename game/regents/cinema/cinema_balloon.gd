class_name CinemaBalloon extends Control
## DIALOG VISUAL PRESENTER (cinema proof-of-concept).
## Displays lines and branching choices from `CinemaDialogue` across four live-switchable visual styles:
##   1) OSRS_BOX       — classic bottom parchment box with a live 3D talking-head bust (`Mannequin` in `SubViewport`)
##   2) SPEECH_BUBBLE  — world-projected 3D speech bubble anchored above the speaker's head + floating choices
##   3) PLAIN_SUBTITLE — clean letterboxed cinema subtitles with strong outline/shadow, no box background
##   4) REGENTS_CARD   — framed dark-parchment & gold-accented RPG card matching `RegentsTutorialCard`

signal advance_requested()
signal choice_picked(index: int)

enum Style {
	OSRS_BOX,
	SPEECH_BUBBLE,
	PLAIN_SUBTITLE,
	REGENTS_CARD,
}

const STYLE_NAMES: PackedStringArray = ["OSRS Box", "Speech Bubble", "Plain Text", "Regent's Card"]
const CHARS_PER_SEC: float = 48.0

var current_style: Style = Style.OSRS_BOX
var world_camera: Camera3D = null
var speaker_head_pos: Vector3 = Vector3.ZERO
var _full_text: String = ""
var _speaker: String = ""
var _line_id: String = ""
var _revealed_chars: float = 0.0
var _typing: bool = false
var _choices: Array[Dictionary] = []
var _voice_active: bool = false
var _bust_gesture_timer: float = 0.0

## Style 1: OSRS Box + 3D talking-head bust
var _osrs_panel: PanelContainer = null
var _bust_container: SubViewportContainer = null
var _bust_viewport: SubViewport = null
var _bust_camera: Camera3D = null
var _bust_mannequin: Mannequin = null
var _osrs_speaker: Label = null
var _osrs_body: RichTextLabel = null
var _osrs_hint: Label = null
var _osrs_choices: VBoxContainer = null
var _last_bust_def: EntityDefinition = null
var _last_bust_look: int = -1

## Style 2: 3D Speech Bubble
var _bubble_root: Control = null
var _bubble_panel: PanelContainer = null
var _bubble_speaker: Label = null
var _bubble_body: Label = null
var _bubble_hint: Label = null
var _bubble_tail: Control = null
var _bubble_choices_panel: PanelContainer = null
var _bubble_choices: VBoxContainer = null
var _bubble_anchor_px: Vector2 = Vector2.ZERO

## Style 3: Plain Subtitle
var _plain_box: VBoxContainer = null
var _plain_line: RichTextLabel = null
var _plain_hint: Label = null
var _plain_choices: VBoxContainer = null

## Style 4: Regent's Card
var _card_panel: PanelContainer = null
var _card_speaker: Label = null
var _card_voice_badge: Label = null
var _card_body: RichTextLabel = null
var _card_hint: Label = null
var _card_choices: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MinigameLook.theme()
	_build_osrs_box()
	_build_speech_bubble()
	_build_plain_subtitle()
	_build_regents_card()
	set_style(current_style)


func set_world_camera(cam: Camera3D) -> void:
	world_camera = cam


func set_style(s: Style) -> void:
	current_style = s
	if _osrs_panel == null:
		return
	_osrs_panel.visible = (s == Style.OSRS_BOX)
	_bubble_root.visible = (s == Style.SPEECH_BUBBLE)
	_plain_box.visible = (s == Style.PLAIN_SUBTITLE)
	_card_panel.visible = (s == Style.REGENTS_CARD)
	if _bust_viewport != null:
		_bust_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if s == Style.OSRS_BOX else SubViewport.UPDATE_DISABLED
	_sync_texts()
	_rebuild_choices()


func show_line(line: Dictionary, speaker_def: EntityDefinition, speaker_look: int, head_pos: Vector3, voiced: bool = false) -> void:
	_speaker = String(line.get("speaker", ""))
	_full_text = String(line.get("text", ""))
	_line_id = String(line.get("line_id", ""))
	_voice_active = voiced
	speaker_head_pos = head_pos
	_choices.clear()
	_revealed_chars = 0.0
	_typing = not _full_text.is_empty()
	_update_bust(speaker_def, speaker_look, true)
	_sync_texts()
	_rebuild_choices()


func show_choices(choices: Array[Dictionary]) -> void:
	_choices = choices.duplicate()
	_typing = false
	_revealed_chars = float(_full_text.length())
	_update_bust(_last_bust_def, _last_bust_look, false)
	_sync_texts()
	_rebuild_choices()


func clear_dialogue() -> void:
	_speaker = ""
	_full_text = ""
	_choices.clear()
	_typing = false
	visible = false


func reveal_all() -> void:
	_revealed_chars = float(_full_text.length())
	_typing = false
	_update_bust(_last_bust_def, _last_bust_look, false)
	_sync_texts()


func is_typing() -> bool:
	return _typing


func handle_continue() -> void:
	if _typing:
		reveal_all()
	elif _choices.is_empty():
		advance_requested.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	if _bust_gesture_timer > 0.0:
		_bust_gesture_timer = maxf(0.0, _bust_gesture_timer - delta)
		if _bust_gesture_timer <= 0.0 and _bust_mannequin != null and _bust_mannequin.definition != null:
			_bust_mannequin.play(&"locomotion.idle", true)
	if _typing:
		_revealed_chars = minf(float(_full_text.length()), _revealed_chars + delta * CHARS_PER_SEC)
		if int(_revealed_chars) >= _full_text.length():
			_typing = false
			_update_bust(_last_bust_def, _last_bust_look, false)
		_sync_texts()
	if current_style == Style.SPEECH_BUBBLE:
		_position_speech_bubble()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if not _choices.is_empty():
		var idx: int = -1
		if key.keycode >= KEY_1 and key.keycode <= KEY_9:
			idx = int(key.keycode - KEY_1)
		if idx >= 0 and idx < _choices.size():
			choice_picked.emit(idx)
			get_viewport().set_input_as_handled()
			return
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		if _choices.is_empty():
			handle_continue()
			get_viewport().set_input_as_handled()


# --- Builders ------------------------------------------------------------------------

func _build_osrs_box() -> void:
	_osrs_panel = PanelContainer.new()
	_osrs_panel.name = "OsrsBox"
	_osrs_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_osrs_panel.offset_left = -390.0
	_osrs_panel.offset_right = 390.0
	_osrs_panel.offset_top = -236.0
	_osrs_panel.offset_bottom = -24.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.83, 0.75, 0.59, 0.97)
	bg.border_color = Color(0.28, 0.20, 0.12, 1.0)
	bg.set_border_width_all(4)
	bg.set_corner_radius_all(4)
	bg.shadow_color = Color(0, 0, 0, 0.6)
	bg.shadow_size = 8
	bg.content_margin_left = 14.0
	bg.content_margin_right = 14.0
	bg.content_margin_top = 12.0
	bg.content_margin_bottom = 12.0
	_osrs_panel.add_theme_stylebox_override(&"panel", bg)
	add_child(_osrs_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 16)
	_osrs_panel.add_child(hbox)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(156, 178)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.14, 0.11, 0.08, 1.0)
	frame_style.border_color = Color(0.38, 0.28, 0.17, 1.0)
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override(&"panel", frame_style)
	hbox.add_child(frame)

	_bust_container = SubViewportContainer.new()
	_bust_container.stretch = true
	_bust_container.custom_minimum_size = Vector2(150, 172)
	frame.add_child(_bust_container)

	_bust_viewport = SubViewport.new()
	_bust_viewport.own_world_3d = true
	_bust_viewport.size = Vector2i(150, 172)
	_bust_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_bust_container.add_child(_bust_viewport)

	var bust_world := Node3D.new()
	bust_world.name = "BustStage"
	_bust_viewport.add_child(bust_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.12, 0.09, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.68, 0.60, 1.0)
	env.ambient_light_energy = 0.75
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	bust_world.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-28.0, 26.0, 0.0)
	key_light.light_color = Color(1.0, 0.94, 0.84, 1.0)
	key_light.light_energy = 1.4
	bust_world.add_child(key_light)

	_bust_camera = Camera3D.new()
	_bust_camera.fov = 28.0
	_bust_camera.position = Vector3(0.0, 1.48, 0.95)
	bust_world.add_child(_bust_camera)
	_bust_camera.look_at_from_position(Vector3(0.0, 1.48, 0.95), Vector3(0.0, 1.42, 0.0))

	_bust_mannequin = Mannequin.new()
	_bust_mannequin.rotation.y = PI - 0.16
	bust_world.add_child(_bust_mannequin)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 6)
	hbox.add_child(right)

	_osrs_speaker = Label.new()
	_osrs_speaker.add_theme_font_size_override(&"font_size", 21)
	_osrs_speaker.add_theme_color_override(&"font_color", Color(0.45, 0.12, 0.08, 1.0))
	right.add_child(_osrs_speaker)

	_osrs_body = RichTextLabel.new()
	_osrs_body.fit_content = false
	_osrs_body.scroll_active = false
	_osrs_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_osrs_body.add_theme_font_size_override(&"normal_font_size", 19)
	_osrs_body.add_theme_color_override(&"default_color", Color(0.11, 0.08, 0.05, 1.0))
	right.add_child(_osrs_body)

	_osrs_choices = VBoxContainer.new()
	_osrs_choices.add_theme_constant_override(&"separation", 3)
	right.add_child(_osrs_choices)

	var cont_btn := Button.new()
	cont_btn.flat = true
	cont_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cont_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cont_btn.pressed.connect(handle_continue)
	right.add_child(cont_btn)

	_osrs_hint = Label.new()
	_osrs_hint.text = "Click or press Space to continue"
	_osrs_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_osrs_hint.add_theme_font_size_override(&"font_size", 14)
	_osrs_hint.add_theme_color_override(&"font_color", Color(0.12, 0.25, 0.56, 1.0))
	_osrs_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont_btn.custom_minimum_size = Vector2(0, 24)
	cont_btn.add_child(_osrs_hint)


func _build_speech_bubble() -> void:
	_bubble_root = Control.new()
	_bubble_root.name = "SpeechBubbleRoot"
	_bubble_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble_root)

	_bubble_tail = _BubbleTail.new()
	_bubble_tail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_root.add_child(_bubble_tail)

	_bubble_panel = PanelContainer.new()
	_bubble_panel.custom_minimum_size = Vector2(260, 60)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.97, 0.94, 0.87, 0.96)
	bg.border_color = Color(0.22, 0.17, 0.12, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(14)
	bg.shadow_color = Color(0, 0, 0, 0.45)
	bg.shadow_size = 6
	bg.content_margin_left = 14.0
	bg.content_margin_right = 14.0
	bg.content_margin_top = 10.0
	bg.content_margin_bottom = 10.0
	_bubble_panel.add_theme_stylebox_override(&"panel", bg)
	_bubble_root.add_child(_bubble_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 4)
	_bubble_panel.add_child(vbox)

	_bubble_speaker = Label.new()
	_bubble_speaker.add_theme_font_size_override(&"font_size", 14)
	_bubble_speaker.add_theme_color_override(&"font_color", Color(0.58, 0.34, 0.08, 1.0))
	vbox.add_child(_bubble_speaker)

	_bubble_body = Label.new()
	_bubble_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_body.custom_minimum_size = Vector2(360, 0)
	_bubble_body.add_theme_font_size_override(&"font_size", 17)
	_bubble_body.add_theme_color_override(&"font_color", Color(0.12, 0.09, 0.06, 1.0))
	vbox.add_child(_bubble_body)

	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	click_btn.custom_minimum_size = Vector2(0, 20)
	click_btn.pressed.connect(handle_continue)
	vbox.add_child(click_btn)

	_bubble_hint = Label.new()
	_bubble_hint.text = "[Space / Click]"
	_bubble_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bubble_hint.add_theme_font_size_override(&"font_size", 12)
	_bubble_hint.add_theme_color_override(&"font_color", Color(0.35, 0.30, 0.24, 0.85))
	_bubble_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_btn.add_child(_bubble_hint)

	_bubble_choices_panel = PanelContainer.new()
	_bubble_choices_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bubble_choices_panel.offset_left = -280.0
	_bubble_choices_panel.offset_right = 280.0
	_bubble_choices_panel.offset_top = -170.0
	_bubble_choices_panel.offset_bottom = -26.0
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.08, 0.07, 0.06, 0.85)
	cbg.border_color = Color(0.78, 0.62, 0.32, 0.9)
	cbg.set_border_width_all(2)
	cbg.set_corner_radius_all(8)
	cbg.content_margin_left = 12.0
	cbg.content_margin_right = 12.0
	cbg.content_margin_top = 8.0
	cbg.content_margin_bottom = 8.0
	_bubble_choices_panel.add_theme_stylebox_override(&"panel", cbg)
	_bubble_root.add_child(_bubble_choices_panel)

	_bubble_choices = VBoxContainer.new()
	_bubble_choices.add_theme_constant_override(&"separation", 4)
	_bubble_choices_panel.add_child(_bubble_choices)


func _build_plain_subtitle() -> void:
	_plain_box = VBoxContainer.new()
	_plain_box.name = "PlainSubtitles"
	_plain_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_plain_box.offset_left = -460.0
	_plain_box.offset_right = 460.0
	_plain_box.offset_top = -220.0
	_plain_box.offset_bottom = -20.0
	_plain_box.alignment = BoxContainer.ALIGNMENT_END
	_plain_box.add_theme_constant_override(&"separation", 8)
	add_child(_plain_box)

	_plain_choices = VBoxContainer.new()
	_plain_choices.add_theme_constant_override(&"separation", 4)
	_plain_box.add_child(_plain_choices)

	_plain_line = RichTextLabel.new()
	_plain_line.bbcode_enabled = true
	_plain_line.fit_content = true
	_plain_line.scroll_active = false
	_plain_line.add_theme_font_size_override(&"normal_font_size", 22)
	_plain_line.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.95))
	_plain_line.add_theme_constant_override(&"outline_size", 6)
	_plain_line.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.85))
	_plain_line.add_theme_constant_override(&"shadow_offset_x", 2)
	_plain_line.add_theme_constant_override(&"shadow_offset_y", 2)
	_plain_box.add_child(_plain_line)

	var cont_btn := Button.new()
	cont_btn.flat = true
	cont_btn.custom_minimum_size = Vector2(0, 22)
	cont_btn.pressed.connect(handle_continue)
	_plain_box.add_child(cont_btn)

	_plain_hint = Label.new()
	_plain_hint.text = "Space / Click to continue"
	_plain_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plain_hint.add_theme_font_size_override(&"font_size", 13)
	_plain_hint.add_theme_color_override(&"font_color", Color(0.96, 0.92, 0.84, 0.7))
	_plain_hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_plain_hint.add_theme_constant_override(&"outline_size", 4)
	_plain_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont_btn.add_child(_plain_hint)


func _build_regents_card() -> void:
	_card_panel = PanelContainer.new()
	_card_panel.name = "RegentsCard"
	_card_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_card_panel.offset_left = -380.0
	_card_panel.offset_right = 380.0
	_card_panel.offset_top = -245.0
	_card_panel.offset_bottom = -24.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.07, 0.06, 0.90)
	bg.border_color = Color(0.78, 0.62, 0.32, 0.95)
	bg.border_width_left = 4
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.set_corner_radius_all(5)
	bg.shadow_color = Color(0, 0, 0, 0.65)
	bg.shadow_size = 10
	bg.content_margin_left = 18.0
	bg.content_margin_right = 18.0
	bg.content_margin_top = 14.0
	bg.content_margin_bottom = 12.0
	_card_panel.add_theme_stylebox_override(&"panel", bg)
	add_child(_card_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	_card_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	_card_speaker = Label.new()
	_card_speaker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_speaker.add_theme_font_size_override(&"font_size", 20)
	_card_speaker.add_theme_color_override(&"font_color", MinigameLook.GOLD)
	header.add_child(_card_speaker)

	_card_voice_badge = Label.new()
	_card_voice_badge.add_theme_font_size_override(&"font_size", 12)
	_card_voice_badge.add_theme_color_override(&"font_color", Color(0.78, 0.85, 0.72, 0.8))
	header.add_child(_card_voice_badge)

	_card_body = RichTextLabel.new()
	_card_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_body.scroll_active = false
	_card_body.add_theme_font_size_override(&"normal_font_size", 19)
	_card_body.add_theme_color_override(&"default_color", MinigameLook.INK)
	vbox.add_child(_card_body)

	_card_choices = VBoxContainer.new()
	_card_choices.add_theme_constant_override(&"separation", 4)
	vbox.add_child(_card_choices)

	var cont_btn := Button.new()
	cont_btn.flat = true
	cont_btn.custom_minimum_size = Vector2(0, 22)
	cont_btn.pressed.connect(handle_continue)
	vbox.add_child(cont_btn)

	_card_hint = Label.new()
	_card_hint.text = "Space / Click to continue"
	_card_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_card_hint.add_theme_font_size_override(&"font_size", 13)
	_card_hint.add_theme_color_override(&"font_color", MinigameLook.HINT)
	_card_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cont_btn.add_child(_card_hint)


# --- Synchronization -----------------------------------------------------------------

func _sync_texts() -> void:
	if _osrs_speaker == null:
		return
	var shown: String = _full_text.substr(0, mini(_full_text.length(), int(_revealed_chars)))
	var show_cont: bool = _choices.is_empty() and not _full_text.is_empty()
	var cont_str: String = "Skip..." if _typing else "Click or press Space to continue"

	_osrs_speaker.text = _speaker
	_osrs_body.text = shown
	_osrs_hint.visible = show_cont
	_osrs_hint.text = cont_str

	_bubble_speaker.text = _speaker
	_bubble_body.text = shown
	_bubble_hint.visible = show_cont
	_bubble_hint.text = "[Space]"

	var sp_prefix: String = ("[color=#facc5c]%s:[/color] " % _speaker) if not _speaker.is_empty() else ""
	_plain_line.text = "[center]%s%s[/center]" % [sp_prefix, shown]
	_plain_hint.visible = show_cont

	_card_speaker.text = _speaker
	_card_voice_badge.text = ("VO: %s" % _line_id) if (_voice_active and not _line_id.is_empty()) else ("VO Synth" if _voice_active else "")
	_card_body.text = shown
	_card_hint.visible = show_cont
	_card_hint.text = cont_str


func _rebuild_choices() -> void:
	var containers: Array[VBoxContainer] = [_osrs_choices, _bubble_choices, _plain_choices, _card_choices]
	for box: VBoxContainer in containers:
		if box == null:
			continue
		for c: Node in box.get_children():
			c.queue_free()
	var has_choices: bool = not _choices.is_empty()
	if _bubble_choices_panel != null:
		_bubble_choices_panel.visible = has_choices and current_style == Style.SPEECH_BUBBLE
	if not has_choices:
		return
	for i: int in _choices.size():
		var item: Dictionary = _choices[i]
		var label: String = "%d. %s" % [i + 1, String(item.get("text", ""))]
		var idx: int = i
		for s_idx: int in containers.size():
			var box: VBoxContainer = containers[s_idx]
			if box == null:
				continue
			var btn := Button.new()
			btn.text = label
			btn.alignment = HORIZONTAL_ALIGNMENT_CENTER if s_idx == 2 else HORIZONTAL_ALIGNMENT_LEFT
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			btn.add_theme_font_size_override(&"font_size", 16)
			if s_idx == 0:
				btn.flat = true
				btn.add_theme_color_override(&"font_color", Color(0.10, 0.22, 0.52, 1.0))
				btn.add_theme_color_override(&"font_hover_color", Color(0.60, 0.14, 0.08, 1.0))
			elif s_idx == 2:
				btn.flat = true
				btn.add_theme_color_override(&"font_color", MinigameLook.INK)
				btn.add_theme_color_override(&"font_hover_color", MinigameLook.GOLD)
			else:
				btn.add_theme_color_override(&"font_color", MinigameLook.INK)
				btn.add_theme_color_override(&"font_hover_color", MinigameLook.GOLD)
			btn.pressed.connect(func() -> void: choice_picked.emit(idx))
			box.add_child(btn)


func _update_bust(def: EntityDefinition, look_idx: int, talking: bool) -> void:
	if _bust_mannequin == null:
		return
	_bust_mannequin.rotation.y = PI - 0.16
	if def != null and (def != _last_bust_def or look_idx != _last_bust_look):
		_last_bust_def = def
		_last_bust_look = look_idx
		_bust_mannequin.look = maxi(0, look_idx)
		_bust_mannequin.definition = def
		_bust_mannequin.play(&"locomotion.idle", true)
	if _bust_mannequin.definition != null:
		if talking:
			if _bust_mannequin.play(&"interact", false):
				_bust_gesture_timer = 0.85
			else:
				_bust_gesture_timer = 0.0
				_bust_mannequin.play(&"locomotion.idle", true)
		elif _bust_gesture_timer <= 0.0:
			_bust_mannequin.play(&"locomotion.idle", true)


func _position_speech_bubble() -> void:
	if _bubble_panel == null:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x < 10.0 or vp_size.y < 10.0:
		vp_size = Vector2(1280.0, 720.0)
	var b_size: Vector2 = _bubble_panel.size
	if b_size.x < 10.0:
		b_size = Vector2(390.0, 110.0)
	var target_px: Vector2 = Vector2(vp_size.x * 0.5, vp_size.y * 0.35)
	if world_camera != null and is_instance_valid(world_camera) and world_camera.is_inside_tree():
		if not world_camera.is_position_behind(speaker_head_pos):
			target_px = world_camera.unproject_position(speaker_head_pos + Vector3(0.0, 0.35, 0.0))
	_bubble_anchor_px = Vector2(clampf(target_px.x, 40.0, vp_size.x - 40.0), clampf(target_px.y, 120.0, vp_size.y - 190.0))
	var box_pos: Vector2 = Vector2(
		clampf(_bubble_anchor_px.x - b_size.x * 0.5, 24.0, vp_size.x - b_size.x - 24.0),
		clampf(_bubble_anchor_px.y - b_size.y - 28.0, 72.0, vp_size.y - b_size.y - 190.0)
	)
	_bubble_panel.position = box_pos
	var tail: _BubbleTail = _bubble_tail as _BubbleTail
	if tail != null:
		tail.box_rect = Rect2(box_pos, b_size)
		tail.tip = _bubble_anchor_px
		tail.queue_redraw()


class _BubbleTail extends Control:
	var box_rect: Rect2 = Rect2()
	var tip: Vector2 = Vector2.ZERO

	func _draw() -> void:
		if box_rect.size.x <= 1.0:
			return
		var base_x: float = clampf(tip.x, box_rect.position.x + 24.0, box_rect.end.x - 24.0)
		var base_y: float = box_rect.end.y - 2.0
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(base_x - 12.0, base_y),
			Vector2(base_x + 12.0, base_y),
			tip,
		])
		draw_colored_polygon(pts, Color(0.97, 0.94, 0.87, 0.96))
		draw_line(pts[0], pts[2], Color(0.22, 0.17, 0.12, 1.0), 2.0)
		draw_line(pts[1], pts[2], Color(0.22, 0.17, 0.12, 1.0), 2.0)
