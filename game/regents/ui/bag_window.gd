class_name RegentsBagWindow extends UiWindow
## THE BAG (I, owner 2026-10-20: dedicated UI, not text on screen): every stack as a slot, a made item's
## edge in its grade's color; click one and below it says what it is (its graded name, its quality and
## handle, its POWER against the weapon you wield, a tool's work and tier, a weapon's kit and moves, a handle's
## trait), with WIELD / PUT AWAY on a weapon. A weapon of a kit with roles wears its handle's BADGE in a corner,
## and says what its handle does and names its last hit (COMBAT_OVERHAUL.md §5; Luke 2026-11-01: show, don't
## name: never the role's name). It follows the bag as the server changes it. Grades and
## Power: `RegentsGrade`.
##
## THE DOLL (W3; Luke: "from the bag (I), a paper doll of head, chest, legs and trinket; out of combat only"): four slots
## at the top, each the piece worn there (from the server's `worn` row, never from a click), its total Defense and what
## it takes off every hit beside them. Click a worn piece on the doll to take it off; pick a piece of armor in the bag
## and Wear it (a second one in a taken slot swaps). The server may refuse (in a fight): the reason is shown. A piece's
## words: its Defense as a number, as Power is, and what wearing it does ("Wearing it, you'd take 19% less, now 13%"),
## counted as the server counts (`RegentsDefense`, K the live `regents.defense_k`). A chest that gives an ability says
## what it does on F, in the bar's words. Never Light / Heavy, never a role. Minimal: the UI rebuild is Luke's to shape.

const COLUMNS: int = 6

var inventory: SpaceTimeInventoryComponent = null
var combat: CombatComponent = null
## Its holder's skills (their mastery of a weapon's kind, for its level as they use it).
var skilling: SkillingComponent = null
## A weapon's abilities window (the HUD's), opened from a weapon here.
var abilities: RegentsAbilitiesWindow = null
## The stack picked (its row id), or -1.
var picked_row: int = -1
## The player's worn armor (its `worn` row) and how to wear and take off: the doll's source. Null: no doll.
var armor: ArmorLookComponent = null
## The server's last refusal of a Wear or a Take off, as the player reads it ("" for none).
var refusal: String = ""
var _doll: HBoxContainer = null
var _total: Label = null
var _grid: GridContainer = null
var _detail: VBoxContainer = null


func _init() -> void:
	super()
	title = "Bag"
	place = Place.RIGHT
	size_min = Vector2(420, 360)
	_doll = HBoxContainer.new()
	_doll.name = "Doll"
	_doll.add_theme_constant_override(&"separation", 6)
	content.add_child(_doll)
	_total = UiKit.note("")
	_total.name = "DollTotal"
	content.add_child(_total)
	content.add_child(UiKit.divider())
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
	_fill_doll(stacks)
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
		var def: ItemDef = ItemDef.by_id(st.item_def_id)
		s.tooltip_text = ("%s  x%d" % [_name(st), st.qty] if st.qty > 1 else _name(st)) + ("\n" + def.tooltip_for().get_slice("\n", 1) if def != null and def.tooltip_for().contains("\n") else "")
		var role: RoleDef = ItemDef.role_of(def, st.instance_data)
		if role != null:
			var badge: TextureRect = RegentsRoleBadge.rect(role, 12)
			badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			badge.position = Vector2(-14, 2)
			s.add_child(badge)
			s.tooltip_text += "\n" + role_tooltip(def, role)
		if def != null and def.armor_slot != &"" and armor != null:
			s.tooltip_text += "\n" + "\n".join(armor_lines(st))
		var row: int = st.id
		s.pressed.connect(func() -> void:
			picked_row = row
			refusal = ""
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
	# Its TRAITS (template DECISIONS #275): each its name, what it gives and what it costs.
	for id: int in ItemDef.trait_ids(st.instance_data):
		var t: TraitDef = Traits.def(id)
		if t == null:
			continue
		var name_line: Label = UiKit.line(t.display_name, &"accent")
		name_line.name = "Trait_%s" % t.key
		_detail.add_child(name_line)
		_detail.add_child(UiKit.line("  + " + t.gives, &"good"))
		if not t.costs.is_empty():
			_detail.add_child(UiKit.line("  - " + t.costs, &"bad"))
	if it.armor_slot != &"" and armor != null:
		var lines: PackedStringArray = armor_lines(st)
		for i: int in lines.size():
			var l: Label = UiKit.line(lines[i]) if i == 0 else UiKit.note(lines[i])
			l.name = ["Defense", "Wearing", "OnF"][mini(i, 2)]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_detail.add_child(l)
	if it.tool_tag != &"":
		_detail.add_child(UiKit.note("A tool: works %s nodes up to tier %d, from the bag." % [it.tool_tag, it.tool_tier]))
	if it.weapon_kit != &"":
		var kit: KitDef = KitDef.by_key(it.weapon_kit)
		var role: RoleDef = ItemDef.role_of(it, st.instance_data)
		var moves: PackedStringArray = PackedStringArray()
		if kit != null:
			for a: AbilityDef in (kit.string_for(role) + kit.skills if kit.has_roles() else kit.abilities()):
				moves.append(a.display_name)
		_detail.add_child(UiKit.note("A weapon: the %s kit. %s" % [it.weapon_kit, ", ".join(moves)]))
		if kit != null and not kit.skill_slots.is_empty():
			_level_lines(st, kit)
		if role != null:
			var line := HBoxContainer.new()
			line.name = "RoleLine"
			line.add_theme_constant_override(&"separation", 6)
			line.add_child(RegentsRoleBadge.rect(role))
			var words := UiKit.note(role_tooltip(it, role))
			words.name = "RoleWords"
			words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(words)
			_detail.add_child(line)
	# What it leads to (owner, 2026-10-23): as a part, the trait it gives tools and weapons; what it makes.
	for line: String in it.part_lines():
		_detail.add_child(UiKit.note("As a %s, %s" % [it.part_tag, line[0].to_lower() + line.substr(1)]))
	if not it.uses().is_empty():
		var makes := UiKit.note("Makes: " + ", ".join(it.uses()))
		makes.name = "Makes"
		makes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(makes)
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
	if it.armor_slot != &"" and it.armor_slot != &"trinket" and armor != null:
		var on: bool = armor.row_in(it.armor_slot) == st.id
		var w := UiKit.button("Take off" if on else "Wear", "Wear_%d" % st.id)
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var slot: StringName = it.armor_slot
		w.pressed.connect(func() -> void:
			if on:
				take_off(slot)
			else:
				wear(row))
		buttons.add_child(w)
	if not refusal.is_empty():
		var r: Label = UiKit.line(refusal, &"bad")
		r.name = "Refusal"
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(r)
	# DROP it at your feet (DECISIONS #269): yours a minute, then anyone's. Not what you wield. Not what you wear.
	if (combat == null or combat.weapon_row != st.id) and (armor == null or not armor.rows.values().has(st.id)):
		var d := UiKit.button("Drop" if st.qty <= 1 else "Drop all %d" % st.qty, "Drop_%d" % st.id)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var qty: int = st.qty
		d.pressed.connect(func() -> void: inventory.request_drop(row, qty))
		buttons.add_child(d)


## THE WEAPON'S LEVEL (B11: against your mastery, here, not on the bar) and the way to its abilities: its own window
## (`RegentsAbilitiesWindow`, Luke 2026-11-14), where its picks are chosen and changed.
func _level_lines(st: SpaceTimeInventoryComponent.Stack, kit: KitDef) -> void:
	var mastery: int = skilling.rank_in(kit.skill) if skilling != null and kit.skill != null else 1
	var p: Dictionary = RegentsItemLevel.progress(kit, RegentsItemLevel.xp_of(st.instance_data), mastery)
	var words: String = "Level %d" % int(p["level"])
	if int(p["usable"]) < int(p["level"]):
		words += ", counting as %d for you (%s %d)" % [int(p["usable"]), kit.skill.display_name, mastery]
	var open: int = RegentsItemLevel.open_picks(kit, int(p["usable"]), RegentsItemLevel.picks_of(st.instance_data)).size()
	if open > 0:
		words += ".  A pick is open!"
	var level_line: Label = UiKit.line(words, &"warn" if open > 0 else &"accent")
	level_line.name = "Level"
	_detail.add_child(level_line)
	if abilities != null:
		var b := UiKit.button("Abilities", "Abilities_%d" % st.id)
		var item_row: int = st.id
		b.pressed.connect(func() -> void: abilities.show_row(item_row))
		_detail.add_child(b)


## A weapon's role in words, for its tooltip: its last hit by name, what its handle does ("Its last hit: Pommel
## bash. The string ends in ... Held, a full guard: ..."). Never the role's name.
static func role_tooltip(it: ItemDef, role: RoleDef) -> String:
	return "Its last hit: %s. %s" % [RegentsRoleBadge.last_hit_name(it, role), RegentsRoleBadge.does_line(it, role)]


## What the role line says now (tests): "" for none.
func role_line() -> String:
	var l: Label = _detail.find_child("RoleWords", true, false) as Label if _detail != null else null
	return l.text if l != null else ""


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


# ---------------------------------------------------------------- the doll (W3)

## Wear bag row `row`: asked of the server; the doll shows it when the `worn` row says so. A refusal's reason is shown.
func wear(row: int) -> ReducerRequest:
	refusal = ""
	var req: ReducerRequest = armor.wear(row)
	req.settled.connect(_on_answer.bind("Not worn"))
	return req


## Take off what is worn in `slot`, the same way.
func take_off(slot: StringName) -> ReducerRequest:
	refusal = ""
	var req: ReducerRequest = armor.take_off(slot)
	req.settled.connect(_on_answer.bind("Not taken off"))
	return req


func _on_answer(r: ReducerRequest, what: String) -> void:
	if r.outcome != ReducerRequest.Outcome.OK:
		refusal = "%s: %s." % [what, reason_of(r.error_message)]
		refresh()


## A refusal as the player reads it: without the reducer's name ("wear: not in a fight (...)" -> "not in a fight (...)").
static func reason_of(text: String) -> String:
	var t: String = text.strip_edges()
	for prefix: String in ["wear: ", "take_off: "]:
		t = t.trim_prefix(prefix)
	return t.trim_suffix(".")


## The total Defense worn now, as the server counts it (only pieces still in the bag, each in its own slot).
func worn_defense() -> float:
	var total: float = 0.0
	if armor == null:
		return total
	for slot: StringName in ArmorLookComponent.SLOTS:
		total += RegentsDefense.of_row(inventory, armor.row_in(slot), slot)
	return total


## A piece of armor's words: its Defense; what wearing it (or taking it off) does; a chest's ability on F.
func armor_lines(st: SpaceTimeInventoryComponent.Stack) -> PackedStringArray:
	var it: ItemDef = ItemDef.by_id(st.item_def_id)
	var out: PackedStringArray = PackedStringArray()
	if it == null or it.armor_slot == &"":
		return out
	var k: float = RegentsDefense.k_now()
	var d: float = RegentsDefense.piece(it.defense, maxi(RegentsGrade.quality_of(st.instance_data), 0))
	var total: float = worn_defense()
	var here: float = RegentsDefense.of_row(inventory, armor.row_in(it.armor_slot), it.armor_slot)
	out.append("Defense %d" % roundi(d))
	if armor.row_in(it.armor_slot) == st.id:
		var without: int = RegentsDefense.less_pct(total - here, k)
		out.append(("Worn. Without it you'd take %d%% less, now %d%%." % [without, RegentsDefense.less_pct(total, k)]) if without > 0
			else "Worn. Without it every hit would land whole; now you take %d%% less." % RegentsDefense.less_pct(total, k))
	else:
		out.append("Wearing it, you'd take %d%% less, now %d%%." % [RegentsDefense.less_pct(total - here + d, k), RegentsDefense.less_pct(total, k)])
	if it.worn_ability != null:
		out.append("While worn, it gives F: %s. %s" % [it.worn_ability.display_name, RegentsAbilityBar.ability_words(it.worn_ability, null)])
	return out


func _fill_doll(stacks: Array[SpaceTimeInventoryComponent.Stack]) -> void:
	for c: Node in _doll.get_children():
		_doll.remove_child(c)
		c.queue_free()
	_doll.visible = armor != null
	_total.visible = armor != null
	if armor == null:
		return
	var label := UiKit.note("Worn")
	label.custom_minimum_size = Vector2(44, 0)
	_doll.add_child(label)
	for slot: StringName in ArmorLookComponent.SLOTS:
		var s := UiSlot.new()
		s.name = "Doll_%s" % slot
		var row: int = armor.row_in(slot)
		var st: SpaceTimeInventoryComponent.Stack = null
		for x: SpaceTimeInventoryComponent.Stack in stacks:
			if x.id == row and row != 0:
				st = x
		var it: ItemDef = ItemDef.by_id(st.item_def_id) if st != null else null
		if it != null:
			s.tint = it.color
			s.picture = it.icon()
			s.mark = UiSlot.initials(RegentsHud.item_name(st.item_def_id))
			s.grade = RegentsGrade.of_quality(RegentsGrade.quality_of(st.instance_data))
			s.tooltip_text = "%s: %s\n%s\nClick to take it off." % [String(slot).capitalize(), _name(st), "\n".join(armor_lines(st))]
			s.pressed.connect(func() -> void: take_off(slot))
		else:
			s.mark = String(slot).left(1).to_upper()
			s.tint = Color(0, 0, 0, 0)
			s.tooltip_text = "%s: nothing worn." % String(slot).capitalize() if slot != &"trinket" else "Trinket: nothing to wear here yet."
		_doll.add_child(s)
	var total: float = worn_defense()
	_total.text = "Defense %d: you take %d%% less from every hit." % [roundi(total), RegentsDefense.less_pct(total, RegentsDefense.k_now())] if total > 0.0 else "Nothing worn: every hit lands whole."
