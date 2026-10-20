class_name RegentsBagWindow extends UiWindow
## THE BAG (I, owner 2026-10-20: dedicated UI, not text on screen): every stack as a slot, a made item's
## edge in its grade's colour; click one and below it says what it is (its graded name, its quality and
## handle, its POWER against the weapon you wield, a tool's work and tier, a weapon's kit, a handle's
## trait), with WIELD / PUT AWAY on a weapon. It follows the bag as the server changes it. Grades and
## Power: `RegentsGrade`.

const COLUMNS: int = 6

var inventory: SpaceTimeInventoryComponent = null
var combat: CombatComponent = null
## The stack picked (its row id), or -1.
var picked_row: int = -1
var _grid: GridContainer = null
var _detail: VBoxContainer = null


func _init() -> void:
	super()
	title = "Bag"
	place = Place.RIGHT
	size_min = Vector2(420, 360)
	_grid = UiKit.slot_grid(COLUMNS)
	content.add_child(_grid)
	content.add_child(UiKit.divider())
	_detail = VBoxContainer.new()
	content.add_child(_detail)
	opened.connect(refresh)


## Draw it again from the bag (the HUD calls it when the bag changes).
func refresh() -> void:
	if not visible or inventory == null:
		return
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var stacks: Array[SpaceTimeInventoryComponent.Stack] = inventory.items()
	if stacks.filter(func(s: SpaceTimeInventoryComponent.Stack) -> bool: return s.id == picked_row).is_empty():
		picked_row = stacks[0].id if not stacks.is_empty() else -1
	for st: SpaceTimeInventoryComponent.Stack in stacks:
		var it: ItemDef = ItemDef.by_id(st.item_def_id)
		var s := UiSlot.new()
		s.name = "Slot_%d" % st.id
		s.tint = it.color if it != null else Color(0, 0, 0, 0)
		s.picture = it.icon() if it != null else null
		s.mark = UiSlot.initials(RegentsHud.item_name(st.item_def_id))
		s.count = st.qty
		s.grade = RegentsGrade.of_quality(RegentsGrade.quality_of(st.instance_data))
		s.selected = st.id == picked_row
		s.tooltip_text = "%s  x%d" % [_name(st), st.qty] if st.qty > 1 else _name(st)
		var row: int = st.id
		s.pressed.connect(func() -> void:
			picked_row = row
			refresh())
		_grid.add_child(s)
	_fill_detail(stacks)
	fit.call_deferred()


func _fill_detail(stacks: Array[SpaceTimeInventoryComponent.Stack]) -> void:
	for n: Node in _detail.get_children():
		_detail.remove_child(n)
		n.queue_free()
	if stacks.is_empty():
		_detail.add_child(UiKit.note("Empty."))
		return
	var st: SpaceTimeInventoryComponent.Stack = null
	for s: SpaceTimeInventoryComponent.Stack in stacks:
		if s.id == picked_row:
			st = s
	if st == null:
		return
	var it: ItemDef = ItemDef.by_id(st.item_def_id)
	var q: int = RegentsGrade.quality_of(st.instance_data)
	var head: Label = UiKit.grade_line("%s  x%d" % [_name(st), st.qty] if st.qty > 1 else _name(st), RegentsGrade.of_quality(q))
	head.name = "ItemName"
	_detail.add_child(head)
	var made: String = _made_text(st)
	if not made.is_empty():
		_detail.add_child(UiKit.note(made))
	if it == null:
		return
	var pw: int = RegentsGrade.power(it, q)
	if pw >= 0:
		var power_line: Label = _power_line(st, it, pw, stacks)
		power_line.name = "Power"
		_detail.add_child(power_line)
	if it.tool_tag != &"":
		_detail.add_child(UiKit.note("A tool: works %s nodes up to tier %d, from the bag." % [it.tool_tag, it.tool_tier]))
	if it.weapon_kit != &"":
		var kit: KitDef = KitDef.by_key(it.weapon_kit)
		var moves: PackedStringArray = PackedStringArray()
		if kit != null:
			for a: AbilityDef in kit.abilities():
				moves.append(a.display_name)
		_detail.add_child(UiKit.note("A weapon: the %s kit. %s" % [it.weapon_kit, ", ".join(moves)]))
	if it.part_tag != &"" and not it.handle_trait().is_empty():
		_detail.add_child(UiKit.note("A %s: %s on what it is made into." % [it.part_tag, it.handle_trait()]))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	_detail.add_child(buttons)
	var row: int = st.id
	if it.weapon_kit != &"" and combat != null:
		var held: bool = combat.weapon_row == st.id
		var b := UiKit.button("Put away" if held else "Wield", "Wield_%d" % st.id)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: combat.wield(-1 if held else row))
		buttons.add_child(b)
	# DROP it at your feet (DECISIONS #269): yours a minute, then anyone's. Not what you wield.
	if combat == null or combat.weapon_row != st.id:
		var d := UiKit.button("Drop" if st.qty <= 1 else "Drop all %d" % st.qty, "Drop_%d" % st.id)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var qty: int = st.qty
		d.pressed.connect(func() -> void: inventory.request_drop(row, qty))
		buttons.add_child(d)


## Its name with its grade ("Fine iron axe").
static func _name(st: SpaceTimeInventoryComponent.Stack) -> String:
	var it: ItemDef = ItemDef.by_id(st.item_def_id)
	return RegentsGrade.item_name(it, RegentsGrade.quality_of(st.instance_data)) if it != null else RegentsHud.item_name(st.item_def_id)


## "Fine · quality 62% · oak handle" for a made item; "" for a plain one.
static func _made_text(st: SpaceTimeInventoryComponent.Stack) -> String:
	var q: int = RegentsGrade.quality_of(st.instance_data)
	if q < 0:
		return ""
	var out: String = "%s · quality %d%%" % [RegentsGrade.grade_name(RegentsGrade.of_quality(q)), q / 10]
	var h: int = int(RegentsGrade.data_of(st.instance_data).get("h", -1))
	if h >= 0:
		out += " · %s" % RegentsHud.item_name(h).to_lower()
	return out


## "Power 112": a weapon's against the one you wield ("+12 on your Iron sword", green or red), "wielded"
## for that one itself; ammo's as it is.
func _power_line(st: SpaceTimeInventoryComponent.Stack, it: ItemDef, pw: int, stacks: Array[SpaceTimeInventoryComponent.Stack]) -> Label:
	if it.weapon_kit == &"" or combat == null or combat.weapon_row < 0:
		return UiKit.line("Power %d" % pw)
	if combat.weapon_row == st.id:
		return UiKit.line("Power %d  (wielded)" % pw)
	for w: SpaceTimeInventoryComponent.Stack in stacks:
		if w.id != combat.weapon_row:
			continue
		var wit: ItemDef = ItemDef.by_id(w.item_def_id)
		var wp: int = RegentsGrade.power(wit, RegentsGrade.quality_of(w.instance_data))
		if wp < 0:
			break
		var d: int = pw - wp
		return UiKit.line("Power %d  (%s%d on your %s)" % [pw, "+" if d >= 0 else "", d, _name(w)],
			&"good" if d > 0 else (&"bad" if d < 0 else &"text"))
	return UiKit.line("Power %d" % pw)
