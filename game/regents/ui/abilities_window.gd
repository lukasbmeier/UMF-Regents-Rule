class_name RegentsAbilitiesWindow extends UiWindow
## A WEAPON'S ABILITIES (Luke, 2026-11-14: "basic weapon ability ui once you click a weapon in your bar or your bag"): its
## own window, drawn in the ability bar's look (`RegentsBarStyle`, the setting's round or square), opened by clicking the
## weapon on the bar (`RegentsAbilityBar.weapon_pressed`) or "Abilities" on a weapon in the bag. It shows:
##   its level against your mastery (B2), and a bar to its next unlock
##   its four slots, Q E R F, as the bar draws them: on each what is there, locked ones with the level that opens them
##   each PICK OPEN now (E at its level 5, R at 20): a card per option, press to choose (`choose_pick`)
##   each pick CHOSEN: a card per option it could change to, with what that costs now (`change_pick`, Luke's B13: free
##   once a week from level 20, else the head's material at a workbench, doubling)
## Hover any card for what it does. It decides nothing: the server does (`choose_pick`, `change_pick`); a refusal is said
## in the HUD's side column. The placeholder windows (the bag, the skills) are to be redone later (`GAME.md`, the UI
## to-dos); this one is the first in the bar's look.

const CARD: Vector2 = Vector2(96, 0)
const KEYS: Array[String] = ["Q", "E", "R", "F"]

var inventory: SpaceTimeInventoryComponent = null
var combat: CombatComponent = null
var skilling: SkillingComponent = null
## The bag row of the weapon shown (-1: none).
var row: int = -1
var _style: RegentsBarStyle = null


func _init() -> void:
	super()
	title = "Abilities"
	place = Place.CENTER
	size_min = Vector2(460, 300)


## Show the weapon in bag row `item_row` (open, or kept open on it).
func show_row(item_row: int) -> void:
	row = item_row
	if not is_open():
		open()
	refresh()


## Draw it again from the bag (the HUD calls it when the bag or a skill changes).
func refresh() -> void:
	if not is_open() or inventory == null:
		return
	for c: Node in content.get_children():
		content.remove_child(c)
		c.queue_free()
	var st: SpaceTimeInventoryComponent.Stack = _stack()
	var it: ItemDef = ItemDef.by_id(st.item_def_id) if st != null else null
	var kit: KitDef = KitDef.by_key(it.weapon_kit) if it != null and it.weapon_kit != &"" else null
	if kit != null:
		kit = kit.for_role(ItemDef.role_of(it, st.instance_data))   # this item's role's pool (S1b)
	if kit == null:
		title = "Abilities"
		content.add_child(UiKit.note("No weapon: click a weapon in the bag, or the one you wield on the bar."))
		fit.call_deferred()
		return
	title = RegentsGrade.item_name(it, RegentsGrade.quality_of(st.instance_data))
	RegentsAbilityBar.define_setting()
	_style = RegentsAbilityBar.look(int(Settings.get_value(RegentsAbilityBar.SETTING)))
	var mastery: int = skilling.rank_in(kit.skill) if skilling != null and kit.skill != null else 1
	var xp: int = RegentsItemLevel.xp_of(st.instance_data)
	var picks: Array[int] = RegentsItemLevel.picks_of(st.instance_data)
	var p: Dictionary = RegentsItemLevel.progress(kit, xp, mastery)
	var use: int = int(p["usable"])
	_level(kit, p, mastery)
	_slots(kit, use, picks)
	if kit.skill_slots.is_empty():
		return
	for o: Dictionary in RegentsItemLevel.open_picks(kit, use, picks):
		_pick_row(st, kit, o)
	_change_rows(st, it, kit, int(p["level"]), use, picks)
	var foot: Label = UiKit.note("Q comes with the weapon; E and R are its picks, its own (another weapon, another build); F comes from the chest you wear.")
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size = Vector2(430, 0)
	content.add_child(foot)
	fit.call_deferred()


func _stack() -> SpaceTimeInventoryComponent.Stack:
	if inventory == null:
		return null
	for s: SpaceTimeInventoryComponent.Stack in inventory.items():
		if s.id == row:
			return s
	return null


## Its level against your mastery, and a bar to its next unlock.
func _level(kit: KitDef, p: Dictionary, mastery: int) -> void:
	var words: String = "Level %d" % int(p["level"])
	if int(p["usable"]) < int(p["level"]):
		words += ", counting as %d for you (%s %d)" % [int(p["usable"]), kit.skill.display_name, mastery]
	var line: Label = UiKit.line(words, &"accent")
	line.name = "Level"
	content.add_child(line)
	if int(p["next"]) > 0:
		var bar: ProgressBar = RegentsHud.make_bar(content, _style.ring_fill, 14.0, "LevelBar")
		RegentsHud.set_bar(bar, float(p["frac"]), 1.0, "to level %d" % int(p["next"]))


## The four slots as the bar draws them, each with its key and name under it.
func _slots(kit: KitDef, use: int, picks: Array[int]) -> void:
	var row_box := HBoxContainer.new()
	row_box.name = "Slots"
	row_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row_box.add_theme_constant_override(&"separation", 14)
	content.add_child(row_box)
	var on_bar: Array[AbilityDef] = RegentsItemLevel.bar(kit, picks)
	for i: int in 4:
		var a: AbilityDef = on_bar[i]
		var d: Dictionary = {"key": KEYS[i], "state": RegentsAbilitySlot.EMPTY, "glyph": "", "count": -1}
		var under: String = "-"
		if a != null:
			var why: String = RegentsItemLevel.slot_refusal(kit, a, use, picks)
			d = {"key": KEYS[i], "name": a.display_name, "mark": RegentsAbilityBar.mark_of(a, kit), "icon": a.icon(), "ability_id": a.id,
				"state": RegentsAbilitySlot.READY if why.is_empty() else RegentsAbilitySlot.LOCKED, "count": -1,
				"note": "" if why.is_empty() else "lvl %d" % RegentsItemLevel.opens_at(kit, i),
				"tip": "%s\n%s%s" % [a.display_name, RegentsAbilityBar.ability_words(a, kit), "" if why.is_empty() else "\n" + why.left(1).to_upper() + why.substr(1) + "."]}
			under = a.display_name
		elif (i == RegentsItemLevel.E or i == RegentsItemLevel.R) and not RegentsItemLevel.choices_for(kit, 0 if i == RegentsItemLevel.E else 2).is_empty():
			var at: int = RegentsItemLevel.opens_at(kit, i)
			d["state"] = RegentsAbilitySlot.CHOOSE if use >= at else RegentsAbilitySlot.LOCKED
			d["note"] = "choose" if use >= at else "lvl %d" % at
			d["glyph"] = "+" if use >= at else ""
			d["tip"] = "A pick: choose below." if use >= at else "A pick at the weapon's level %d." % at
			under = "a pick" if use >= at else "level %d" % at
		elif i == RegentsItemLevel.F:
			d["tip"] = "The chest's ability goes here (armor comes later)."
		var card := VBoxContainer.new()
		card.name = "Slot_%s" % KEYS[i]
		card.custom_minimum_size = CARD
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override(&"separation", 10)   # room for a round slot's key under it
		var slot := RegentsAbilitySlot.new()
		slot.style = _style
		slot.custom_minimum_size = Vector2(_style.slot_size, _style.slot_size)
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.show_data(d, true)
		card.add_child(slot)
		var label: Label = Label.new()   # not `UiKit.note`: it holds a wide minimum, for a paragraph
		label.text = under
		label.name = "Name"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(label)
		row_box.add_child(card)


## A pick open now: a card per option, press to choose.
func _pick_row(st: SpaceTimeInventoryComponent.Stack, kit: KitDef, o: Dictionary) -> void:
	var n: int = int(o["n"])
	content.add_child(UiKit.divider())
	var head: Label = UiKit.line("Choose for %s (level %d): for good, though it can be changed." % ["R" if n == 2 else "E", kit.unlock_level(1 + n)], &"warn")
	head.name = "PickHead_%d" % n
	content.add_child(head)
	var box := HBoxContainer.new()
	box.name = "Pick_%d" % n
	box.add_theme_constant_override(&"separation", 8)
	for a: AbilityDef in o["options"] as Array[AbilityDef]:
		box.add_child(_card(kit, a, "Choose_%d" % a.id, func() -> void: choose(st.id, n, a)))
	content.add_child(box)


## Each pick chosen: a card per option it could change to, and what a change costs now.
func _change_rows(st: SpaceTimeInventoryComponent.Stack, it: ItemDef, kit: KitDef, item_level: int, use: int, picks: Array[int]) -> void:
	var price: Dictionary = RegentsItemLevel.change_price(it, st.instance_data, item_level, int(ClockSync.server_usec() / 1000000))
	var head: ItemDef = price["item"] as ItemDef
	var cost: String = "free this week" if bool(price["free"]) else ("%d %s, at a workbench" % [int(price["qty"]), head.display_name if head != null else "?"])
	for n: int in 3:
		if picks[n] == 0:
			continue
		var options: Array[AbilityDef] = []
		for a: AbilityDef in RegentsItemLevel.choices_for(kit, n):
			if RegentsItemLevel.change_refusal(kit, n, a, use, picks).is_empty():
				options.append(a)
		if options.is_empty():
			continue
		content.add_child(UiKit.divider())
		var was: AbilityDef = ContentLibrary.find(&"ability", picks[n]) as AbilityDef
		var words: Label = UiKit.note("Change %s from %s (%s):" % ["R" if n == 2 else "E", was.display_name if was != null else "?", cost])
		words.name = "Price_%d" % n
		content.add_child(words)
		var box := HBoxContainer.new()
		box.name = "Change_%d" % n
		box.add_theme_constant_override(&"separation", 8)
		for a: AbilityDef in options:
			box.add_child(_card(kit, a, "ChangeTo_%d" % a.id, func() -> void: change(st.id, n, a)))
		content.add_child(box)


## A card: the ability's slot drawn small and its name on a button; hover for what it does.
func _card(kit: KitDef, a: AbilityDef, card_name: String, act: Callable) -> Control:
	var b := UiKit.button(a.display_name, card_name)
	b.tooltip_text = "%s\n%s" % [a.display_name, RegentsAbilityBar.ability_words(a, kit)]
	b.custom_minimum_size = Vector2(130, _style.small_size + 8)
	var slot := RegentsAbilitySlot.new()
	slot.style = _style
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.position = Vector2(4, 4)
	slot.size = Vector2(_style.small_size, _style.small_size)
	slot.show_data({"mark": RegentsAbilityBar.mark_of(a, kit), "icon": a.icon(), "state": RegentsAbilitySlot.READY, "count": -1}, false)
	b.add_child(slot)
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.pressed.connect(act)
	return b


## The workbench in front of you (its entity id), or 0: where a paid change is made.
func workbench_in_front() -> int:
	var t: int = skilling.target_now() if skilling != null else -1
	var station: StationComponent = SkillingComponent.station_of(t) if t >= 0 else null
	return t if station != null and station.key == &"workbench" else 0


## Choose `ability` at pick `n` of the weapon in bag row `item_row`; a refusal is said (the HUD's side column).
func choose(item_row: int, n: int, ability: AbilityDef) -> ReducerRequest:
	if combat == null:
		return null
	return _said(combat.choose_pick(item_row, n, ability), "choose_pick: ")


## Change pick `n` of the weapon in bag row `item_row` to `ability`, at the workbench in front of you if any.
func change(item_row: int, n: int, ability: AbilityDef) -> ReducerRequest:
	if combat == null:
		return null
	return _said(combat.change_pick(workbench_in_front(), item_row, n, ability), "change_pick: ")


func _said(req: ReducerRequest, prefix: String) -> ReducerRequest:
	req.settled.connect(func(r: ReducerRequest) -> void:
		if r.outcome == ReducerRequest.Outcome.REJECTED or r.outcome == ReducerRequest.Outcome.FAILED:
			combat.refused.emit(r.error_message.trim_prefix(prefix)))
	return req
