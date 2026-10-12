class_name HoldPrompt extends VBoxContainer
## THE HOLD PROMPT AND ITS BAR (DECISIONS #209), for the local player, near the middle of the screen:
##
##   looking at something a hold applies to   "Hold E: Help up", with the bar when it is already part
##                                             done (a half-laid nest someone left)
##   holding it                                "Help up", the bar filling, how many are doing it
##
## The bar flashes red when it goes back: a genre took some of it away (a raid, a missed check).
##
## It reads what the components know (`InteractionComponent`, `HoldComponent`) every frame and owns
## nothing. The foundation's HUD carries one; a genre's HUD adds its own with `HoldPrompt.new()`.

var _label: Label
var _bar: ProgressBar

## The bar goes back by at least this much at once (not a slow undoing, which is a rate): it flashes
## `DROP_COLOR` for `DROP_FLASH_S`.
const DROP_MIN: float = 0.01
const DROP_FLASH_S: float = 0.8
const DROP_COLOR: Color = Color(1.0, 0.3, 0.25)
var _last_hold: int = -1
var _last_progress: float = -1.0
var _flash_until_msec: int = 0

## A GENRE'S WORD ON A HOLD (DECISIONS #220): each `func(me: SpaceTimeEntity, target_id: int, hold:
## HoldDef) -> String`, asked while the prompt offers a hold; the first that says something is shown
## after it, dimmed ("Hold E: Lay an egg  ·  you can lay again in 12 s"): why the server would refuse
## it, before the player tries. Asked too while the player holds it, and shown after it, not dimmed:
## what just happened to it ("Sit on the nest  ·  an egg cracked: -8 % warmth"). Added with `add_note`,
## from a genre's HUD.
static var _notes: Array[Callable] = []


## Add a genre's note (see `_notes`). Once per callable.
static func add_note(note: Callable) -> void:
	if note.is_valid() and not _notes.has(note):
		_notes.append(note)


## Take one away (a genre's HUD leaving the tree).
static func remove_note(note: Callable) -> void:
	_notes.erase(note)


## What the genres say about `hold` on `target_id` for `me`: the first non-empty note, or "".
static func note_for(me: SpaceTimeEntity, target_id: int, hold: HoldDef) -> String:
	for n: Callable in _notes.duplicate():
		if not n.is_valid():
			_notes.erase(n)
			continue
		var said: String = String(n.call(me, target_id, hold))
		if not said.is_empty():
			return said
	return ""


func _init() -> void:
	name = "HoldPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	custom_minimum_size = Vector2(320, 0)
	offset_left = -160
	offset_right = 160
	offset_top = -170
	offset_bottom = -110
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(300, 14)
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	add_child(_bar)
	visible = false


func _process(_delta: float) -> void:
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity \
		if EntityRegistry.local_entity_id >= 0 else null
	show_state(state_for(me))


## What the prompt shows for `me`: {visible, text, progress (-1: no bar), color}.
static func state_for(me: SpaceTimeEntity) -> Dictionary:
	var none: Dictionary = {"visible": false, "text": "", "progress": -1.0, "color": Color.WHITE}
	if me == null or not is_instance_valid(me):
		return none
	var mine: HoldComponent = me.find_component(HoldComponent) as HoldComponent
	if mine != null and mine.is_holding():
		var doing: Dictionary = mine.doing()
		var target: SpaceTimeEntity = EntityRegistry.get_entity(int(doing["target_id"])) as SpaceTimeEntity
		var on_it: HoldComponent = target.find_component(HoldComponent) as HoldComponent if target != null else null
		var d: HoldDef = HoldDef.by_id(int(doing["hold"]))
		if on_it == null or d == null:
			return none
		var hid: int = int(doing["hold_id"])
		var n: int = on_it.doers(hid)
		var said: String = note_for(me, int(doing["target_id"]), d)
		return {"visible": true, "text": d.prompt + ("  (%d together)" % n if n > 1 else "") + ("  ·  " + said if not said.is_empty() else ""),
			"progress": on_it.progress(hid), "color": d.color, "hold_id": hid, "note": said}
	var ic: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	if ic == null or not ic.has_target():
		return none
	var h: HoldDef = ic.hold_for(ic.get_target())
	if h == null:
		return none
	var there: SpaceTimeEntity = EntityRegistry.get_entity(ic.get_target()) as SpaceTimeEntity
	var hc: HoldComponent = there.find_component(HoldComponent) as HoldComponent if there != null else null
	var already: int = hc.hold_id_for(h.id) if hc != null else -1
	var note: String = note_for(me, ic.get_target(), h)
	return {"visible": true, "text": "Hold %s: %s" % [key_name(), h.prompt] + ("  ·  " + note if not note.is_empty() else ""),
		"progress": hc.progress(already) if already >= 0 else -1.0,
		"color": h.color if note.is_empty() else h.color.darkened(0.45), "note": note, "hold_id": already}


func show_state(s: Dictionary) -> void:
	visible = bool(s["visible"])
	if not visible:
		return
	_label.text = String(s["text"])
	var p: float = float(s["progress"])
	_bar.visible = p >= 0.0
	_bar.value = maxf(p, 0.0)
	var hid: int = int(s.get("hold_id", -1))
	if hid >= 0 and hid == _last_hold and p >= 0.0 and p < _last_progress - DROP_MIN:
		_flash_until_msec = Time.get_ticks_msec() + int(DROP_FLASH_S * 1000.0)
	elif hid != _last_hold:
		_flash_until_msec = 0
	_last_hold = hid
	_last_progress = p
	_bar.modulate = DROP_COLOR if is_flashing() else s["color"]


## The bar flashing for going back.
func is_flashing() -> bool:
	return Time.get_ticks_msec() < _flash_until_msec


## The interact key's name ("E"), from the input map.
static func key_name(action: StringName = InteractionComponent.ACTION_INTERACT) -> String:
	if InputMap.has_action(action):
		for ev: InputEvent in InputMap.action_get_events(action):
			var k: InputEventKey = ev as InputEventKey
			if k == null:
				continue
			# The key as this keyboard labels it (the physical E is A on a French one); a headless run has
			# no keyboard to ask, and names the physical key.
			var code: Key = k.keycode
			if k.physical_keycode != KEY_NONE:
				var headless: bool = DisplayServer.get_name() == "headless"
				code = k.physical_keycode if headless else DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
			if code != KEY_NONE:
				return OS.get_keycode_string(code)
	return "E" if action == InteractionComponent.ACTION_INTERACT else String(action)


## The key that presses a skill check (DECISIONS #218): its own, else the interact key (a game made
## before it had one).
static func check_key_name() -> String:
	if InputMap.has_action(InteractionComponent.ACTION_SKILL_CHECK) \
			and not InputMap.action_get_events(InteractionComponent.ACTION_SKILL_CHECK).is_empty():
		return key_name(InteractionComponent.ACTION_SKILL_CHECK)
	return key_name()


## The label and bar, for tests.
func text() -> String:
	return _label.text


func bar_value() -> float:
	return _bar.value if _bar.visible else -1.0
