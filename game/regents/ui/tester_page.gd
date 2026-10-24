class_name RegentsTesterPage extends PanelContainer
## THE TESTER PAGE (owner, 2026-10-23: "an admin button to reset the stats or manually adjust them"): a page
## of the Escape menu, offered to the admin only (as Rules (admin) is), to try a stretch of the game without
## playing up to it. Pick a player in this world (yourself first), then:
##   SKILLS     each skill's rank and XP, and a rank to set it to (down as well as up)
##   RESET ALL SKILLS   every skill back to rank 1, no recipe made before, no order filled
##   GIVE       any item, how many, and for one that does not stack (a tool, a weapon, a part) its quality
##   RESET THE BAG      emptied, and the starter kit again
## Every change is the server's (`admin_set_rank`, `admin_reset_skills`, `admin_give_item`,
## `admin_reset_bag` in `server/src/game/regents.rs`), which refuses anyone who is not the admin.

signal closed

var _who: OptionButton = null
var _skills: VBoxContainer = null
## Per skill id: {label: Label, rank: SpinBox}.
var _rows: Dictionary[int, Dictionary] = {}
var _items: OptionButton = null
var _qty: SpinBox = null
var _quality: SpinBox = null
var _grade: Label = null
var _status: Label = null
var _built: bool = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(640, 520)


func open() -> void:
	if not _built:
		_build()
	fill_players()
	refresh()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _process(_delta: float) -> void:
	if visible and _built:
		refresh()


## The player picked (an entity id), or -1.
func target() -> int:
	return _who.get_selected_id() if _who != null and _who.item_count > 0 else -1


## Pick `entity_id` in the player list (tests; it must be listed).
func pick(entity_id: int) -> void:
	var at: int = _who.get_item_index(entity_id)
	if at >= 0:
		_who.select(at)
		refresh()


## The players in this world, yourself first, by name.
func fill_players() -> void:
	var keep: int = target()
	_who.clear()
	var me: int = SpaceTimeSync.get_local_entity_id()
	if me > 0:
		_who.add_item("you (%s)" % _name_of(me), me)
	for id: int in EntityRegistry.all_entity_ids():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
		var plate: NameplateComponent = e.find_component(NameplateComponent) as NameplateComponent if e != null else null
		if id == me or plate == null or not plate.is_player():
			continue
		_who.add_item(plate.shown_name(), id)
	var at: int = _who.get_item_index(keep)
	if _who.item_count > 0:
		_who.select(at if at >= 0 else 0)


## Set `entity_id`'s rank in skill `skill_id`.
func set_rank(entity_id: int, skill_id: int, rank: int) -> ReducerRequest:
	return _send(&"admin_set_rank", [entity_id, skill_id, rank], ["u64", "u32", "u32"],
		"%s set to rank %d" % [_skill_name(skill_id), rank])


func reset_skills(entity_id: int) -> ReducerRequest:
	return _send(&"admin_reset_skills", [entity_id], ["u64"], "every skill back to rank 1")


## Give `entity_id` `qty` of `item_id`; `quality` (thousandths) is its grade when it does not stack (the
## server ignores it for one that stacks).
func give(entity_id: int, item_id: int, qty: int, quality: int) -> ReducerRequest:
	var it: ItemDef = ItemDef.by_id(item_id)
	return _send(&"admin_give_item", [entity_id, item_id, qty, quality], ["u64", "u32", "u32", "u32"],
		"gave %d %s" % [qty, it.display_name if it != null else "?"])


## THE GIVE BUTTON: the item, count and quality picked, to the player picked.
func give_selected() -> ReducerRequest:
	return give(target(), _items.get_selected_id(), int(_qty.value), int(_quality.value))


## Pick item `item_id`, `qty` of it, at `quality` in the Give row (tests).
func pick_item(item_id: int, qty: int, quality: int) -> void:
	_items.select(_items.get_item_index(item_id))
	_qty.value = qty
	_quality.value = quality
	refresh()


## The grade the Give row shows (tests).
func grade_text() -> String:
	return _grade.text


func reset_bag(entity_id: int) -> ReducerRequest:
	return _send(&"admin_reset_bag", [entity_id], ["u64"], "the bag emptied, the starter kit given again")


## Each skill's line for the player picked: its rank and XP now.
func refresh() -> void:
	var sk: SkillingComponent = _skilling_of(target())
	for skill_id: int in _rows:
		var def: SkillDef = SkillDef.by_id(skill_id)
		var xp: int = int(sk.xp.get(skill_id, 0)) if sk != null else -1
		var line: Label = _rows[skill_id]["label"]
		line.text = "%s: rank %d (%d XP)" % [def.display_name, def.rank_of(xp), xp] if xp >= 0 else "%s: ?" % def.display_name
	if _grade != null:
		var it: ItemDef = ItemDef.by_id(_items.get_selected_id()) if _items.item_count > 0 else null
		var stacks: bool = it == null or it.max_stack > 1
		_quality.editable = not stacks
		_grade.text = "stacks: no quality" if stacks else RegentsGrade.grade_name(RegentsGrade.of_quality(int(_quality.value)))


## The skill lines listed (tests): skill id -> its line's text.
func skill_lines() -> Dictionary[int, String]:
	var out: Dictionary[int, String] = {}
	for skill_id: int in _rows:
		out[skill_id] = (_rows[skill_id]["label"] as Label).text
	return out


func _build() -> void:
	_built = true
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Tester (admin) — changes a player on THIS server"
	box.add_child(title)
	var who := HBoxContainer.new()
	box.add_child(who)
	who.add_child(_text("Player:"))
	_who = OptionButton.new()
	_who.custom_minimum_size.x = 260
	_who.item_selected.connect(func(_i: int) -> void: refresh())
	who.add_child(_who)
	who.add_child(_button("Refresh list", fill_players))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_skills = VBoxContainer.new()
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_skills)
	for def: SkillDef in SkillDef.all():
		_add_skill(def)
	box.add_child(_button("Reset all skills", func() -> void: reset_skills(target())))
	box.add_child(_give_row())
	box.add_child(_button("Reset the bag (back to the starter kit)", func() -> void: reset_bag(target())))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(_button("Back", close))


func _add_skill(def: SkillDef) -> void:
	var row := HBoxContainer.new()
	_skills.add_child(row)
	var line := _text(def.display_name)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	row.add_child(_text("rank"))
	var rank := SpinBox.new()
	rank.min_value = 1
	rank.max_value = def.xp_to_rank.size() + 1
	rank.value = 1
	row.add_child(rank)
	row.add_child(_button("Set", func() -> void: set_rank(target(), def.id, int(rank.value))))
	_rows[def.id] = {"label": line, "rank": rank}


func _give_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_text("Give"))
	_items = OptionButton.new()
	_items.custom_minimum_size.x = 200
	var all: Array[ItemDef] = []
	for d: ContentDef in RegentsContent.items(&"item"):
		if d is ItemDef:
			all.append(d as ItemDef)
	all.sort_custom(func(a: ItemDef, b: ItemDef) -> bool: return a.display_name < b.display_name)
	for it: ItemDef in all:
		_items.add_item(it.display_name, it.id)
	_items.item_selected.connect(func(_i: int) -> void: refresh())
	row.add_child(_items)
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = 10000
	_qty.value = 10
	row.add_child(_qty)
	row.add_child(_text("quality"))
	_quality = SpinBox.new()
	_quality.min_value = 0
	_quality.max_value = 1000
	_quality.step = 10
	_quality.value = 500
	_quality.value_changed.connect(func(_v: float) -> void: refresh())
	row.add_child(_quality)
	_grade = _text("")
	row.add_child(_grade)
	row.add_child(_button("Give", give_selected))
	return row


func _send(reducer: StringName, args: Array, types: Array[String], done: String) -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(reducer, args, types)
	var who: String = _who.get_item_text(_who.get_item_index(int(args[0]))) if _who != null and _who.get_item_index(int(args[0])) >= 0 else "player %d" % int(args[0])
	var say: Callable = func(r: ReducerRequest) -> void:
		if _status != null:
			_status.text = "%s: %s" % [who, done] if r.is_ok() else "%s: %s" % [reducer, r.error_message]
	if req.outcome == ReducerRequest.Outcome.PENDING:
		req.settled.connect(say)
	else:
		say.call(req)   # settled already (offline)
	return req


func _skilling_of(entity_id: int) -> SkillingComponent:
	var e: SpaceTimeEntity = EntityRegistry.get_entity(entity_id) as SpaceTimeEntity if entity_id > 0 else null
	return e.find_component(SkillingComponent) as SkillingComponent if e != null else null


func _name_of(entity_id: int) -> String:
	var e: SpaceTimeEntity = EntityRegistry.get_entity(entity_id) as SpaceTimeEntity
	var plate: NameplateComponent = e.find_component(NameplateComponent) as NameplateComponent if e != null else null
	return plate.shown_name() if plate != null else "player %d" % entity_id


func _skill_name(skill_id: int) -> String:
	var def: SkillDef = SkillDef.by_id(skill_id)
	return def.display_name if def != null else "skill %d" % skill_id


func _text(s: String) -> Label:
	var l := Label.new()
	l.text = s
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b
