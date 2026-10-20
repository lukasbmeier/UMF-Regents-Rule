class_name RegentsBagWindow extends UiWindow
## THE BAG (I, owner 2026-10-20: dedicated UI, not text on screen): every stack as a slot; click one and
## below it says what it is (a tool's work and tier, a weapon's kit and damage, a handle's trait, its
## quality and handle), with WIELD / PUT AWAY on a weapon. It follows the bag as the server changes it.

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
		s.mark = UiSlot.initials(RegentsHud.item_name(st.item_def_id))
		s.count = st.qty
		s.selected = st.id == picked_row
		s.tooltip_text = "%s  x%d%s" % [RegentsHud.item_name(st.item_def_id), st.qty, _quality_text(st)]
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
	_detail.add_child(UiKit.line("%s  x%d%s" % [RegentsHud.item_name(st.item_def_id), st.qty, _quality_text(st)], &"accent"))
	if it == null:
		return
	if it.tool_tag != &"":
		_detail.add_child(UiKit.note("A tool: works %s nodes up to tier %d, from the bag." % [it.tool_tag, it.tool_tier]))
	if it.weapon_kit != &"":
		var kit: KitDef = KitDef.by_key(it.weapon_kit)
		var moves: PackedStringArray = PackedStringArray()
		if kit != null:
			for a: AbilityDef in kit.abilities():
				moves.append(a.display_name)
		_detail.add_child(UiKit.note("A weapon: the %s kit at %d%% damage. %s" % [it.weapon_kit, it.weapon_damage_pct, ", ".join(moves)]))
	if it.part_tag != &"" and not it.handle_trait().is_empty():
		_detail.add_child(UiKit.note("A %s: %s on what it is made into." % [it.part_tag, it.handle_trait()]))
	if it.weapon_kit != &"" and combat != null:
		var held: bool = combat.weapon_row == st.id
		var b := UiKit.button("Put away" if held else "Wield", "Wield_%d" % st.id)
		var row: int = st.id
		b.pressed.connect(func() -> void: combat.wield(-1 if held else row))
		_detail.add_child(b)


## "  quality 62%, oak handle" for a made item; "" for a plain one.
static func _quality_text(st: SpaceTimeInventoryComponent.Stack) -> String:
	var out: String = ""
	var at: int = st.instance_data.find("\"q\":")
	if at >= 0:
		out = "  quality %d%%" % (st.instance_data.substr(at + 4).to_int() / 10)
	var h: int = st.instance_data.find("\"h\":")
	if h >= 0:
		out += ", %s" % RegentsHud.item_name(st.instance_data.substr(h + 4).to_int()).to_lower()
	return out
