class_name RegentsBarLab extends Control
## THE ABILITY BAR LAB (Luke's B11, 2026-11-13: "maybe we do a small build of both like cinema lab"): open
## `res://game/regents/ui/bar_lab.tscn` and press F6 (no server). The ROUND and the SQUARE bar side by side, fed the
## same made-up player through the real `RegentsAbilityBar.model_for` (a real CombatComponent and SkillingComponent,
## with no body), so what shows here is what the game shows.
##
##   the buttons    the weapon (sword, axe, bow, staff, none); out of stance / in stance / in a fight; low mana
##   the slider     the weapon's level and your mastery together (locks, the ring toward the next unlock)
##   Take a pick    the first pick open takes its next option (as the bag's buttons do in play)
##   Q E R F        fire that slot (it flashes, then cools down), as the keys do in play
##   Use round / Use square    sets the game's setting (Settings, Game: "Ability bar"), saved
## Hover a slot (the cursor is free here) for its words; the panel on the right shows every ability of the weapon
## in the same words (`RegentsAbilityBar.ability_words`: damage, reach, a slow, a shove, a sweep that hits all). Each look is a `.tres` (`bar_round.tres`,
## `bar_square.tres`): change one in the Inspector and run the lab again.
##
## SHOTS (windowed, no server): `"$GODOT" --path . res://game/regents/ui/bar_lab.tscn -- <out dir>` saves the lab for
## the sword, the axe, the staff and the bow, each out of stance, in stance (its first slot just used) and in a fight, then quits.

const KITS: Array[StringName] = [&"sword", &"axe", &"bow", &"staff", &""]
const WEAPONS: Dictionary[StringName, int] = {&"sword": 40019, &"axe": 40001, &"bow": 40020, &"staff": 40023}
const STATE_NAMES: PackedStringArray = ["Out of stance", "In stance", "In a fight"]

var combat: CombatComponent = null
var skilling: SkillingComponent = null
var mana: ResourceComponent = null
var bars: Array[RegentsAbilityBar] = []
var kit_key: StringName = &"sword"
## 0 out of stance, 1 in stance, 2 in a fight.
var state: int = 1
var low_mana: bool = false
var rank: int = 12
var _rank_label: Label = null
var _words: Label = null


## A made-up pool row (what `ResourceComponent` reads from the server's).
class PoolRow extends RefCounted:
	var resource_id: int = 0
	var stored: float = 0.0
	var at: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiStyle.current().theme()
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.2, 0.26, 0.22)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	CombatComponent.bind_keys()   # the slots' keys (as the game binds them for its local player)
	combat = CombatComponent.new()
	skilling = SkillingComponent.new()
	mana = ResourceComponent.new()
	combat.pool_for_tests = mana
	for i: int in 2:
		var half: Control = Control.new()
		half.name = "Round" if i == 0 else "Square"
		half.set_anchors_preset(Control.PRESET_FULL_RECT)
		half.anchor_top = 0.18 + 0.41 * float(i)
		half.anchor_bottom = 0.18 + 0.41 * float(i + 1)
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(half)
		var title: Label = Label.new()
		title.text = RegentsAbilityBar.LOOK_NAMES[i]
		title.position = Vector2(24, 8)
		title.add_theme_font_size_override(&"font_size", 22)
		half.add_child(title)
		var use: Button = Button.new()
		use.text = "Use %s in the game" % RegentsAbilityBar.LOOK_NAMES[i].to_lower()
		use.position = Vector2(24, 44)
		use.focus_mode = Control.FOCUS_NONE
		var index: int = i
		use.pressed.connect(func() -> void:
			RegentsAbilityBar.define_setting()
			Settings.set_value(RegentsAbilityBar.SETTING, index))
		half.add_child(use)
		var bar: RegentsAbilityBar = RegentsAbilityBar.new()
		bar.follows_setting = false
		bar.style = RegentsAbilityBar.look(i)
		half.add_child(bar)
		bars.append(bar)
	_controls()
	_words = Label.new()
	_words.name = "Words"
	_words.set_anchors_preset(Control.PRESET_FULL_RECT)
	_words.anchor_left = 0.755
	_words.anchor_top = 0.16
	_words.offset_right = -12.0
	_words.offset_bottom = -8.0
	_words.clip_contents = true
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.add_theme_font_size_override(&"font_size", 11)
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_words)
	combat.swung.connect(func(id: int) -> void:
		for b: RegentsAbilityBar in bars:
			b.fired(id))
	_set_kit(kit_key)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_shoot.call_deferred(args[0])


## Save the lab for each kit and state into `dir`, then quit.
func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for k: StringName in [&"sword", &"axe", &"staff", &"bow"]:
		for st: int in 3:
			_set_kit(k)
			rank = 12 if k == &"staff" and st == 2 else 4   # the staff's last shot: past its first pick, Frost Ring taken
			_set_rank(float(rank) + 0.4)
			if k == &"staff" and st == 2:
				take_pick()
			state = st
			if st == 1 and combat.kit != null and not combat.kit.skills.is_empty():
				var a: AbilityDef = combat.kit.skills[0]
				combat.spell_ready_ms[a.id] = Time.get_ticks_msec() + int(combat.cooldown_total(a) * 1000.0 * 0.6)
			await get_tree().create_timer(0.45).timeout
			await RenderingServer.frame_post_draw
			var file: String = dir.path_join("bar_%s_%d.png" % [k, st])
			get_viewport().get_texture().get_image().save_png(file)
			print("saved ", file)
	AppExit.quit(get_tree(), 0)


func _controls() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.position = Vector2(24, 16)
	row.add_theme_constant_override(&"separation", 6)
	add_child(row)
	for k: StringName in KITS:
		var key: StringName = k
		_button(row, String(k).capitalize() if k != &"" else "No weapon", func() -> void: _set_kit(key))
	row.add_child(VSeparator.new())
	for i: int in STATE_NAMES.size():
		var s: int = i
		_button(row, STATE_NAMES[i], func() -> void: state = s)
	row.add_child(VSeparator.new())
	_button(row, "Low mana", func() -> void:
		low_mana = not low_mana
		_fill_mana())
	_button(row, "Take a pick", take_pick)
	var row2: HBoxContainer = HBoxContainer.new()
	row2.position = Vector2(24, 60)
	row2.add_theme_constant_override(&"separation", 8)
	add_child(row2)
	_rank_label = Label.new()
	row2.add_child(_rank_label)
	var slider: HSlider = HSlider.new()
	slider.custom_minimum_size = Vector2(260, 24)
	slider.min_value = 1.0
	slider.max_value = float(SkillDef.RANK_TOP) + 0.6
	slider.step = 0.05
	slider.value = float(rank)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_set_rank)
	row2.add_child(slider)
	var hint: Label = Label.new()
	hint.text = "   Q E R F: fire a slot      hover a slot for its words"
	row2.add_child(hint)
	_set_rank(float(rank))


func _button(row: HBoxContainer, text: String, act: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(act)
	row.add_child(b)


func _set_kit(key: StringName) -> void:
	kit_key = key
	combat.kit = KitDef.by_key(key) if key != &"" else null
	combat.weapon = ItemDef.by_id(int(WEAPONS.get(key, 0))) if WEAPONS.has(key) else null
	combat.spell_ready_ms.clear()
	combat.weapon_data_for_tests = ""
	_set_rank(float(rank))
	_fill_mana()
	_show_words()


## Every ability of the weapon (its handle's set), in the words its slot's tooltip uses.
func _show_words() -> void:
	if _words == null:
		return
	var k: KitDef = combat.pool_kit() if combat.kit != null else null
	if k == null:
		_words.text = ""
		return
	var out: PackedStringArray = PackedStringArray(["What each ability says (hover a slot for the same):"])
	for a: AbilityDef in k.skills:
		if a != null:
			out.append("%s
%s" % [a.display_name, RegentsAbilityBar.ability_words(a, k)])
	_words.text = "

".join(out)


## The weapon's level and your mastery both `r` (a fraction is that far into the level, for the ring).
func _set_rank(r: float) -> void:
	rank = int(r)
	var k: KitDef = combat.kit
	if _rank_label != null:
		_rank_label.text = "Weapon level and mastery %d" % rank
	if k == null or k.skill == null:
		return
	var from: int = RegentsAbilityBar._xp_for(k.skill, rank)
	var to: int = RegentsAbilityBar._xp_for(k.skill, rank + 1)
	var xp: int = from + int(float(to - from) * (r - float(rank)))
	skilling.xp[k.skill.id] = xp
	combat.mastery_for_tests = rank
	_set_item(xp, combat.item_picks())


## The made-up weapon's XP and picks (its row's `instance_data`, as the server keeps them).
func _set_item(xp: int, picks: Array[int]) -> void:
	combat.weapon_data_for_tests = JSON.stringify({"q": 650, "x": xp, "k": picks})


## Take the first pick open, its next option each press (as the bag's buttons do in play).
func take_pick() -> void:
	var k: KitDef = combat.kit
	var picks: Array[int] = combat.item_picks()
	var open: Array[Dictionary] = RegentsItemLevel.open_picks(k, combat.item_usable(), picks)
	if open.is_empty():
		picks = [0, 0, 0]   # nothing open: start over (the lab only)
	else:
		var options: Array[AbilityDef] = open[0]["options"] as Array[AbilityDef]
		picks[int(open[0]["n"])] = options[_next_option % options.size()].id
		_next_option += 1
	_set_item(combat.item_xp(), picks)


var _next_option: int = 0


func _fill_mana() -> void:
	var k: KitDef = combat.kit
	if k == null or k.resource == null:
		return
	var row := PoolRow.new()
	row.resource_id = k.resource.id
	row.stored = 10.0 if low_mana else k.resource.max_amount
	row.at = ClockSync.server_usec()
	mana._apply(row)


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var slot: int = [KEY_Q, KEY_E, KEY_R, KEY_F].find(k.physical_keycode)
	var a: AbilityDef = combat.on_slot(slot)
	if a == null or not RegentsItemLevel.slot_refusal(combat.kit, a, combat.item_usable(), combat.item_picks()).is_empty():
		return
	if combat.cooldown_left(a) > 0.0:
		return
	combat.spell_ready_ms[a.id] = Time.get_ticks_msec() + int(combat.cooldown_total(a) * 1000.0)
	combat.swung.emit(a.id)
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	combat.target_id = 1 if state >= 1 else -1
	combat.fought_ms = now if state == 2 else -100000
	var m: Dictionary = RegentsAbilityBar.model_for(combat, skilling, null)
	m["health"] = Vector2(64.0, 100.0)
	for b: RegentsAbilityBar in bars:
		b.show_model(m)


func _exit_tree() -> void:
	for n: Node in [combat, skilling, mana]:
		if is_instance_valid(n):
			n.free()
