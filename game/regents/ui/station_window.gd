class_name RegentsStationWindow extends UiWindow
## A STATION'S WINDOW (owner, 2026-10-20: "dedicated UI preferred", no Q-cycling): tap E at a furnace, an
## anvil, the workbench or the order board and this opens. Left, what can be done there (each recipe once,
## under what it makes: Axes, Bars...); right, the one picked: what it makes, what it takes (have / need, in
## the style's good and bad; each PART SLOT a choice of any part of its kind, MATERIALS.md step 3), the
## TRAITS (the grade it will be made at and how many traits that holds, each trait its parts offer, ticked in
## use or not, owner 2026-10-23), what it pays, and the buttons: MAKE 1, MAKE X (the number
## beside it) or MAKE ALL work it AFK that many times (owner, 2026-10-21; it stays open, a bar fills to each
## batch, says how many are done, and offers STOP), PLAY A ROUND starts the round (and closes). At the order board, each
## order and FILL. The pick is the station's (`SkillingComponent.recipe_pick`), so holding E there plays
## a round of what was picked last. It closes when you walk away. Presentation only: the server decides.

var skilling: SkillingComponent = null
var inventory: SpaceTimeInventoryComponent = null
## The station shown (its entity), or -1.
var target: int = -1
var station: StationComponent = null
## What can be done here, as `SkillingComponent.choices_at` says.
var choices: Array[Dictionary] = []
var _list: VBoxContainer = null
var _detail: VBoxContainer = null
var _refresh_at: int = 0
## What it last drew (`_drawn_state`): it is drawn again only when that changes (owner, 2026-10-20: the
## window rebuilt every button twice a second, so clicks were lost and the list's scroll jumped).
var _drawn: String = ""
## How many times it has been drawn (tests).
var draws: int = 0
## Make X's number (kept while the window is open), and the bar while working.
var make_x: int = 5
var _progress: ProgressBar = null
var _progress_text: Label = null


func _init() -> void:
	super()
	place = Place.CENTER
	size_min = Vector2(720, 420)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	split.add_child(VSeparator.new())
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_detail)


## Open on station `station_id`: its choices, the one picked there last shown.
func show_station(station_id: int) -> void:
	_drawn = ""
	station = SkillingComponent.station_of(station_id)
	if station == null or skilling == null:
		return
	target = station_id
	title = station.def.display_name if station.def != null else "Station"
	refresh()
	open()


## Pick the first choice whose name holds `text` (what a player's click does; tests by name). True when found.
func pick_named(text: String) -> bool:
	for i: int in choices.size():
		if label_of(choices[i]).contains(text):
			pick(i)
			return true
	return false


## Pick choice `i`: it is the station's pick (hold E plays it), and the right side shows it.
func pick(i: int) -> void:
	_drawn = ""
	if i < 0 or i >= choices.size() or station == null:
		return
	skilling.recipe_pick[station.key] = SkillingComponent._choice_key(choices[i])
	refresh()


## The choice picked here now ({} for none).
func picked() -> Dictionary:
	return skilling.choice_at(station) if station != null and skilling != null else {}


## MAKE (AFK) or PLAY A ROUND of what is picked; FILL an order. A round closes the window (the round needs
## the screen).
func make(active: bool) -> void:
	if skilling == null or target < 0:
		return
	skilling.work(target, active)
	if active:
		close()


## MAKE `count` of what is picked AFK (0: all the bag allows).
func make_count(count: int) -> void:
	if skilling == null or target < 0:
		return
	skilling.make(target, count)


func stop() -> void:
	if skilling != null:
		skilling.stop_afk()


## A choice's name in the list: the recipe, or the order.
static func label_of(c: Dictionary) -> String:
	if c.has("order"):
		var o: Dictionary = c["order"]
		return "%d %s%s" % [int(o["qty"]), RegentsHud.item_name(int(o["item_id"])), "  (filled)" if bool(o["filled"]) else ""]
	if c.has("refit"):
		var made: RecipeDef = c["made_by"]
		return "%s%s" % [RegentsGrade.item_name(made.output, RegentsGrade.quality_of(String(c["data"]))), _traits_tag(String(c["data"]))]
	var r: RecipeDef = c.get("recipe", null) as RecipeDef
	return r.display_name if r != null else "?"


## " (Steady, Gentle)" for an item's traits, "" for none.
static func _traits_tag(data: String) -> String:
	var names: PackedStringArray = PackedStringArray()
	for id: int in ItemDef.trait_ids(data):
		var t: TraitDef = Traits.def(id)
		if t != null:
			names.append(t.display_name)
	return " (%s)" % ", ".join(names) if not names.is_empty() else ""


## Put item `item_id` in part slot `n` of the recipe picked (what the slot's list does; tests).
func pick_part(n: int, item_id: int) -> void:
	var c: Dictionary = picked()
	if skilling == null:
		return
	if c.has("refit"):
		skilling.set_refit_part(int(c["refit"]), c["made_by"], String(c["data"]), n, item_id)
	elif c.get("recipe", null) != null:
		skilling.set_part(c["recipe"], n, item_id)
	_drawn = ""
	refresh()


## Make with heads of grade `grade` (0 Common, 1 Fine, 2 Masterwork: what the head's list does; tests).
func pick_grade(grade: int) -> void:
	var r: RecipeDef = picked().get("recipe", null) as RecipeDef
	if r == null or skilling == null:
		return
	skilling.grade_pick[r.id] = grade
	_drawn = ""
	refresh()


## Want trait `trait_id` on what the picked recipe makes, or not (what its box does; tests).
func want_trait(trait_id: int, on: bool) -> void:
	var c: Dictionary = picked()
	if skilling == null:
		return
	if c.has("refit"):
		skilling.want_refit_trait(int(c["refit"]), c["made_by"], String(c["data"]), trait_id, on)
	elif c.get("recipe", null) != null:
		skilling.want_trait(c["recipe"], trait_id, on)
	_drawn = ""
	refresh()


## What the traits section says (tests): its heading line.
func traits_line() -> String:
	var l: Label = _detail.find_child("TraitRoom", true, false) as Label if _detail != null else null
	return l.text if l != null else ""


func _process(_delta: float) -> void:
	if not visible:
		return
	# Walked away (or the station is gone): it closes, as a shopkeeper's counter would.
	var here: int = skilling.target_now() if skilling != null else -1
	if station == null or not is_instance_valid(station) or (here != target and skilling.afk_target != target):
		close()
		return
	if Time.get_ticks_msec() >= _refresh_at:
		refresh()
	if _progress != null and is_instance_valid(_progress) and skilling.afk_target == target:
		_progress.value = skilling.afk_progress(ClockSync.server_usec())
		_progress_text.text = made_text(skilling)


## What the working line says: how many of a Make X are done, or that it goes on until the bag runs out.
static func made_text(sk: SkillingComponent) -> String:
	if sk.make_limit > 0:
		return "Making %d of %d...  (moving stops it too)" % [mini(sk.made + 1, sk.make_limit), sk.make_limit]
	return "Making until the bag runs out...  (moving stops it too)"


## Draw it again from what the client knows now (the bag, the XP, the work going on), when any of that
## changed since it was last drawn.
func refresh() -> void:
	_refresh_at = Time.get_ticks_msec() + 500
	if station == null or skilling == null:
		return
	choices = skilling.choices_at(station)
	var picked_key: String = SkillingComponent._choice_key(picked()) if not picked().is_empty() else ""
	var state: String = _drawn_state(picked_key)
	if state == _drawn:
		return
	_drawn = state
	draws += 1
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var heading: String = ""
	for i: int in choices.size():
		var r: RecipeDef = choices[i].get("recipe", null) as RecipeDef
		var group: String = "Refit (swap its parts)" if choices[i].has("refit") else (SkillingComponent.group_of(r) if r != null else "")
		if not group.is_empty() and group != heading:
			heading = group
			var h := UiKit.note(heading)
			h.name = "Group_%s" % heading.validate_node_name()
			_list.add_child(h)
		var b := UiKit.button(label_of(choices[i]), "Choice_%d" % i)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = SkillingComponent._choice_key(choices[i]) == picked_key
		if not _can_make(choices[i]):
			b.add_theme_color_override(&"font_color", UiKit.colour(&"dim"))
		var idx: int = i
		b.pressed.connect(func() -> void: pick(idx))
		_list.add_child(b)
	if choices.is_empty():
		_list.add_child(UiKit.note("No orders yet." if station.key == SkillingComponent.ORDER_BOARD else "Nothing is made here."))
	_fill_detail(picked())
	fit.call_deferred()


func _fill_detail(c: Dictionary) -> void:
	for n: Node in _detail.get_children():
		_detail.remove_child(n)
		n.queue_free()
	if c.is_empty():
		return
	if c.has("order"):
		_order_detail(c["order"])
		return
	if c.has("refit"):
		_refit_detail(c)
		return
	var r: RecipeDef = c["recipe"]
	var top := HBoxContainer.new()
	_detail.add_child(top)
	top.add_child(_slot_of(r.output, r.output_qty))
	var names := VBoxContainer.new()
	names.add_child(UiKit.line(label_of(c), &"accent"))
	top.add_child(names)
	_detail.add_child(UiKit.note("Takes"))
	var slots: PackedInt32Array = r.pick_slots()
	var takes: Array = skilling.takes(r)
	for i: int in takes.size():
		var it: ItemDef = takes[i][0]
		var need: int = int(takes[i][1])
		var have: int = inventory.count(it.id) if inventory != null else 0
		var row := HBoxContainer.new()
		row.add_child(_slot_of(it, 0))
		var n: int = slots.find(i)
		if n >= 0:
			row.add_child(_part_list(r, n, slots[n], it, need, r.output, func(idx: int, id: int) -> void: pick_part(idx, id)))
		elif it == SkillingComponent.core_of(r) and r.quality == RecipeDef.Quality.FROM_INPUTS:
			row.add_child(_core_list(r, it, need))
		else:
			row.add_child(UiKit.line("%d / %d  %s" % [have, need, it.display_name], &"good" if have >= need else &"bad"))
		_detail.add_child(row)
	if not slots.is_empty() and r.quality != RecipeDef.Quality.NONE:
		var g: int = skilling.grade_of(r, inventory)
		_traits_section(r.output, g, SkillingComponent.offered_traits(skilling.parts_of(r), r.output), skilling.traits_of(r),
			"no %s in the bag yet" % SkillingComponent.core_of(r).display_name.to_lower() if SkillingComponent.core_of(r) != null else "")
	var rank: int = skilling.rank_in(r.skill)
	if rank < r.min_rank:
		_detail.add_child(UiKit.line("Needs %s rank %d (yours %d)" % [r.skill.display_name, r.min_rank, rank], &"bad"))
	var rec: Dictionary = skilling.recipe_record(r.id)
	var pay: String = "About %d %s XP a batch" % [r.craft_xp(int(HotRules.number(&"regents.craft_work_share_pct"))), r.skill.display_name if r.skill != null else ""]
	if int(rec["made"]) == 0:
		pay += "   FIRST MAKE: x%d" % int(HotRules.number(&"regents.first_make_mult"))
	elif int(rec["fresh_pm"]) < 1000:
		pay += "   freshness %d%%" % (int(rec["fresh_pm"]) / 10)
	_detail.add_child(UiKit.line(pay, &"warn" if int(rec["made"]) == 0 else &"text"))
	_detail.add_child(UiKit.divider())
	var buttons := HBoxContainer.new()
	_detail.add_child(buttons)
	var working: bool = skilling.afk_target == target
	_progress = null
	if working:
		_progress_text = UiKit.line(made_text(skilling), &"accent")
		_detail.add_child(_progress_text)
		_progress = ProgressBar.new()
		_progress.name = "Progress"
		_progress.max_value = 1.0
		_progress.show_percentage = false
		_progress.custom_minimum_size = Vector2(0, 10)
		_progress.value = skilling.afk_progress(ClockSync.server_usec())
		_detail.add_child(_progress)
		var s := UiKit.button("Stop", "Stop")
		s.pressed.connect(stop)
		buttons.add_child(s)
	else:
		var can: bool = _can_make(c)
		var one := UiKit.button("Make 1", "Make")
		one.disabled = not can
		one.tooltip_text = "Make one batch AFK."
		one.pressed.connect(func() -> void: make_count(1))
		buttons.add_child(one)
		var x := SpinBox.new()
		x.name = "MakeX"
		x.min_value = 1
		x.max_value = 999
		x.value = make_x
		x.custom_minimum_size = Vector2(76, 0)
		x.value_changed.connect(func(v: float) -> void: make_x = int(v))
		buttons.add_child(x)
		var mx := UiKit.button("Make X", "MakeXGo")
		mx.disabled = not can
		mx.tooltip_text = "Make this many batches AFK, then stop."
		mx.pressed.connect(func() -> void: make_count(make_x))
		buttons.add_child(mx)
		var all := UiKit.button("Make all", "MakeAll")
		all.disabled = not can
		all.tooltip_text = "Make AFK until the bag runs out."
		all.pressed.connect(func() -> void: make_count(0))
		buttons.add_child(all)
	if r.minigame != null:
		var p := UiKit.button("Play a round", "Round")
		p.disabled = working or not _can_make(c)
		p.tooltip_text = "Hold E at the station does the same: a round of what is picked."
		p.pressed.connect(func() -> void: make(true))
		buttons.add_child(p)


## Part slot `n` (input `slot`) of `r`: a list of every part of its kind, each with how many the bag holds,
## `now` picked; picking one puts it in the slot.
## Each entry says how many you have, and the trait that part offers `made` ("Oak handle: Steady").
func _part_list(r: RecipeDef, n: int, slot: int, now: ItemDef, need: int, made: ItemDef, on_pick: Callable) -> OptionButton:
	var pick := OptionButton.new()
	pick.name = "Part_%d" % n
	pick.custom_minimum_size = Vector2(260, 0)
	for it: ItemDef in r.part_choices(slot):
		var have: int = inventory.count(it.id) if inventory != null else 0
		var t: TraitDef = it.trait_for(made)
		pick.add_item("%d / %d  %s%s" % [have, need, it.display_name, ": " + t.display_name if t != null else ""], it.id)
		pick.set_item_tooltip(pick.item_count - 1, it.tooltip_for(made))
		if it == now:
			pick.select(pick.item_count - 1)
	var have_now: int = inventory.count(now.id) if inventory != null and now != null else 0
	pick.add_theme_color_override(&"font_color", UiKit.colour(&"good" if have_now >= need else &"bad"))
	pick.tooltip_text = "Any %s: its trait is offered for what this makes." % (now.part_tag if now != null else "part")
	pick.item_selected.connect(func(idx: int) -> void: on_pick.call(n, pick.get_item_id(idx)))
	return pick


## THE HEAD, BY GRADE (owner, 2026-10-23): "Masterwork iron axe head (1)", "Fine ... (2)", "Common ... (0)"
## (a grade the bag lacks greyed); a run uses only the grade picked. None at all: the list itself greyed.
func _core_list(r: RecipeDef, core: ItemDef, need: int) -> OptionButton:
	var pick := OptionButton.new()
	pick.name = "Core"
	pick.custom_minimum_size = Vector2(260, 0)
	var have: Dictionary[int, int] = skilling.core_grades(r, inventory)
	var now: int = skilling.grade_of(r, inventory)
	for g: int in [2, 1, 0]:
		pick.add_item("%d / %d  %s %s" % [have[g], need, RegentsGrade.grade_name(g), core.display_name.to_lower()], g)
		pick.set_item_disabled(pick.item_count - 1, have[g] < need)
		if g == now:
			pick.select(pick.item_count - 1)
	if now < 0:
		pick.add_item("0 / %d  %s: none in the bag" % [need, core.display_name], 9)
		pick.select(pick.item_count - 1)
		pick.disabled = true
	pick.add_theme_color_override(&"font_color", UiKit.colour(&"good" if now >= 0 else &"bad"))
	pick.tooltip_text = "Which %s to make with, by grade: its grade is what this makes, and how many traits it holds." % core.display_name.to_lower()
	pick.item_selected.connect(func(idx: int) -> void: pick_grade(pick.get_item_id(idx)))
	return pick


## THE TRAITS (owner, 2026-10-23, MATERIALS.md §4; worded after his playtest): "A Fine iron axe holds 2 traits"
## (grade `grade`; -1: none known yet, then what each grade holds and `why_none`); each trait `offered`, ticked
## to want it, numbered in the order wanted, and marked in use, left out, or with no room at this grade.
func _traits_section(made: ItemDef, grade: int, offered: Array[TraitDef], wanted: Array[TraitDef], why_none: String) -> void:
	_detail.add_child(UiKit.divider())
	var room: int = SkillingComponent.trait_room(_grade_q(grade))
	var head: Label
	if grade < 0:
		head = UiKit.line("Traits: Common holds %d, Fine %d, Masterwork %d%s" % [SkillingComponent.trait_room(0), SkillingComponent.trait_room(_grade_q(1)),
			SkillingComponent.trait_room(_grade_q(2)), " (%s)" % why_none if not why_none.is_empty() else ""], &"text")
	else:
		head = UiKit.grade_line("A %s %s holds %d trait%s" % [RegentsGrade.grade_name(grade), made.display_name.to_lower(), room, "" if room == 1 else "s"], grade)
	head.name = "TraitRoom"
	_detail.add_child(head)
	if offered.is_empty():
		_detail.add_child(UiKit.note("Its parts offer it no trait: pick an oak or yew handle, or iron or copper rivets."))
		return
	for t: TraitDef in offered:
		var at: int = wanted.find(t)
		var row := HBoxContainer.new()
		var box := CheckBox.new()
		box.name = "Trait_%s" % t.key
		box.button_pressed = at >= 0
		box.text = ("%d. " % (at + 1) if at >= 0 else "") + t.display_name
		box.tooltip_text = "%s; %s" % [t.gives, t.costs] if not t.costs.is_empty() else t.gives
		# A checkbox, not a button: no box drawn round it (the style's button look reached it).
		for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			box.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var id: int = t.id
		box.toggled.connect(func(on: bool) -> void: want_trait(id, on))
		row.add_child(box)
		var state_text: String = "left out" if at < 0 else ("in use" if grade < 0 or at < room else "no room at this grade")
		var note := UiKit.line("%s   (%s)" % [box.tooltip_text, state_text], &"good" if state_text == "in use" else &"dim")
		note.name = "TraitState_%s" % t.key
		row.add_child(note)
		_detail.add_child(row)


## A quality inside grade `grade` (for how many traits it holds).
static func _grade_q(grade: int) -> int:
	match grade:
		2:
			return 1000
		1:
			return int(HotRules.number(&"regents.grade_fine_q"))
	return 0


## REFIT AN ITEM (owner, 2026-10-23): what it is, its parts (each a list, as when making it), its traits picked
## again within ITS grade's room, what the swap costs (each part changed, and bars of its head's metal: the old
## part is lost), and REFIT.
func _refit_detail(c: Dictionary) -> void:
	var r: RecipeDef = c["made_by"]
	var row_id: int = int(c["refit"])
	var data: String = String(c["data"])
	var q: int = RegentsGrade.quality_of(data)
	var top := HBoxContainer.new()
	_detail.add_child(top)
	top.add_child(_slot_of(r.output, 1))
	var names := VBoxContainer.new()
	names.add_child(UiKit.grade_line(label_of(c), RegentsGrade.of_quality(q)))
	names.add_child(UiKit.note("Swap its parts: the new ones are used up, the old ones lost. Its head and quality stay."))
	top.add_child(names)
	_detail.add_child(UiKit.note("Parts"))
	var slots: PackedInt32Array = r.pick_slots()
	var now: Array[ItemDef] = skilling.refit_parts(row_id, r, data)
	for n: int in slots.size():
		var row := HBoxContainer.new()
		row.add_child(_slot_of(now[n], 0))
		row.add_child(_part_list(r, n, slots[n], now[n], r.input_qty[slots[n]], r.output, func(idx: int, id: int) -> void: pick_part(idx, id)))
		_detail.add_child(row)
	_traits_section(r.output, RegentsGrade.of_quality(q), SkillingComponent.offered_traits(now, r.output), skilling.refit_traits(row_id, r, data), "")
	_detail.add_child(UiKit.divider())
	var cost: Array = skilling.refit_cost(row_id, r, data)
	var lines: PackedStringArray = PackedStringArray()
	for pair: Array in cost:
		var it: ItemDef = pair[0]
		lines.append("%d %s (you have %d)" % [int(pair[1]), it.display_name, inventory.count(it.id) if inventory != null else 0])
	var cost_line := UiKit.line("Costs: " + ", ".join(lines), &"good" if _can_make(c) else &"bad")
	cost_line.name = "RefitCost"
	_detail.add_child(cost_line)
	var go := UiKit.button("Refit", "Refit")
	go.disabled = not _can_make(c)
	go.tooltip_text = "Swap the parts as picked, and keep the traits ticked."
	go.pressed.connect(func() -> void: make(false))
	_detail.add_child(go)


func _order_detail(o: Dictionary) -> void:
	var skill: SkillDef = SkillDef.by_id(int(o["skill_id"]))
	var have: int = inventory.count(int(o["item_id"])) if inventory != null else 0
	var it: ItemDef = ItemDef.by_id(int(o["item_id"]))
	var top := HBoxContainer.new()
	top.add_child(_slot_of(it, int(o["qty"])))
	top.add_child(UiKit.line("Order %d: %d %s" % [int(o["slot"]) + 1, int(o["qty"]), RegentsHud.item_name(int(o["item_id"]))], &"accent"))
	_detail.add_child(top)
	_detail.add_child(UiKit.line("Pays %d %s XP" % [int(o["xp"]), skill.display_name if skill != null else ""], &"warn"))
	_detail.add_child(UiKit.line("You have %d" % have, &"good" if have >= int(o["qty"]) else &"bad"))
	if bool(o["filled"]):
		_detail.add_child(UiKit.note("You have filled this one."))
	var f := UiKit.button("Hand them over", "Fill")
	f.disabled = bool(o["filled"]) or have < int(o["qty"])
	f.pressed.connect(func() -> void: make(false))
	_detail.add_child(f)


## Everything the window shows, as one string: the choices and whether each can be made, the pick, what
## it takes and what you have, the rank and the record, the work going on.
func _drawn_state(picked_key: String) -> String:
	var parts: PackedStringArray = [picked_key, str(skilling.afk_target == target)]
	for c: Dictionary in choices:
		parts.append("%s|%s" % [label_of(c), _can_make(c)])
		if c.has("refit"):
			var made: RecipeDef = c["made_by"]
			parts.append(String(c["data"]))
			for it: ItemDef in skilling.refit_parts(int(c["refit"]), made, String(c["data"])):
				parts.append("%d:%d" % [it.id, inventory.count(it.id) if inventory != null else 0])
			for t: TraitDef in skilling.refit_traits(int(c["refit"]), made, String(c["data"])):
				parts.append("t%d" % t.id)
			for pair: Array in skilling.refit_cost(int(c["refit"]), made, String(c["data"])):
				parts.append("c%d:%d" % [(pair[0] as ItemDef).id, inventory.count((pair[0] as ItemDef).id) if inventory != null else 0])
		var r: RecipeDef = c.get("recipe", null) as RecipeDef
		if r != null:
			parts.append("g%d" % skilling.grade_of(r, inventory))
			for pair: Array in skilling.takes(r):
				parts.append("%d:%d" % [(pair[0] as ItemDef).id, inventory.count((pair[0] as ItemDef).id) if inventory != null else 0])
			for t: TraitDef in skilling.traits_of(r):
				parts.append("t%d" % t.id)
			parts.append(str(skilling.made_quality(r, inventory)))
			parts.append(str(skilling.rank_in(r.skill)))
			parts.append(str(skilling.recipe_record(r.id)))
		elif c.has("order"):
			parts.append(str(c["order"]))
	return "
".join(parts)


## Whether the bag holds what `c` takes (a rank too low is the server's to say).
func _can_make(c: Dictionary) -> bool:
	if c.has("order"):
		var o: Dictionary = c["order"]
		return not bool(o["filled"]) and inventory != null and inventory.count(int(o["item_id"])) >= int(o["qty"])
	if c.has("refit"):
		var made: RecipeDef = c["made_by"]
		var row: int = int(c["refit"])
		var cost: Array = skilling.refit_cost(row, made, String(c["data"]))
		var traits_now: Array[int] = ItemDef.trait_ids(String(c["data"]))
		var traits_want: Array[int] = []
		for t: TraitDef in skilling.refit_traits(row, made, String(c["data"])):
			traits_want.append(t.id)
		var bars_only: bool = cost.size() <= 1 and (cost.is_empty() or (cost[0][0] as ItemDef).part_tag == &"")
		if bars_only and traits_now == traits_want:
			return false   # nothing would change
		for pair: Array in cost:
			if inventory == null or inventory.count((pair[0] as ItemDef).id) < int(pair[1]):
				return false
		return true
	var r: RecipeDef = c.get("recipe", null) as RecipeDef
	if r == null or inventory == null:
		return false
	var core: ItemDef = SkillingComponent.core_of(r)
	for pair: Array in skilling.takes(r):
		var need: int = int(pair[1])
		if pair[0] == core and r.quality == RecipeDef.Quality.FROM_INPUTS:
			var g: int = skilling.grade_of(r, inventory)
			if g < 0 or skilling.core_grades(r, inventory)[g] < need:
				return false
		elif inventory.count((pair[0] as ItemDef).id) < need:
			return false
	return true


static func _slot_of(it: ItemDef, qty: int) -> UiSlot:
	var s := UiSlot.new()
	if it != null:
		s.tint = it.color
		s.mark = UiSlot.initials(it.display_name)
		s.tooltip_text = it.tooltip_for()
	s.count = qty
	s.focus_mode = Control.FOCUS_NONE
	return s
