class_name RegentsStationWindow extends UiWindow
## A STATION'S WINDOW (owner, 2026-10-20: "dedicated UI preferred", no Q-cycling): tap E at a furnace, an
## anvil, the workbench or the order board and this opens. Left, what can be done there (each recipe; a
## recipe with a handle once per handle in the bag); right, the one picked: what it makes, what it takes
## (have / need, in the style's good and bad), what it pays, and the buttons: MAKE 1, MAKE X (the number
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


## A choice's name in the list: the recipe (with its handle), or the order.
static func label_of(c: Dictionary) -> String:
	if c.has("order"):
		var o: Dictionary = c["order"]
		return "%d %s%s" % [int(o["qty"]), RegentsHud.item_name(int(o["item_id"])), "  (filled)" if bool(o["filled"]) else ""]
	var r: RecipeDef = c.get("recipe", null) as RecipeDef
	var part: ItemDef = c.get("part", null) as ItemDef
	if r == null:
		return "?"
	if part != null and r.part_slot >= 0 and part != r.inputs[r.part_slot]:
		return "%s with %s" % [r.display_name, part.display_name.to_lower()]
	return r.display_name


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
	for i: int in choices.size():
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
	var r: RecipeDef = c["recipe"]
	var part: ItemDef = c.get("part", null) as ItemDef
	var top := HBoxContainer.new()
	_detail.add_child(top)
	top.add_child(_slot_of(r.output, r.output_qty))
	var names := VBoxContainer.new()
	names.add_child(UiKit.line(label_of(c), &"accent"))
	if part != null and r.part_slot >= 0 and part != r.inputs[r.part_slot]:
		names.add_child(UiKit.note("Its handle's trait: %s" % part.handle_trait_text()))
	top.add_child(names)
	_detail.add_child(UiKit.note("Takes"))
	for i: int in r.inputs.size():
		var it: ItemDef = part if i == r.part_slot and part != null else r.inputs[i]
		var have: int = inventory.count(it.id) if inventory != null else 0
		var row := HBoxContainer.new()
		row.add_child(_slot_of(it, 0))
		row.add_child(UiKit.line("%d / %d  %s" % [have, r.input_qty[i], it.display_name], &"good" if have >= r.input_qty[i] else &"bad"))
		_detail.add_child(row)
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
		var r: RecipeDef = c.get("recipe", null) as RecipeDef
		if r != null:
			for it: ItemDef in r.inputs:
				parts.append(str(inventory.count(it.id) if inventory != null else 0))
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
	var r: RecipeDef = c.get("recipe", null) as RecipeDef
	if r == null or inventory == null:
		return false
	var part: ItemDef = c.get("part", null) as ItemDef
	for i: int in r.inputs.size():
		var it: ItemDef = part if i == r.part_slot and part != null else r.inputs[i]
		if inventory.count(it.id) < r.input_qty[i]:
			return false
	return true


static func _slot_of(it: ItemDef, qty: int) -> UiSlot:
	var s := UiSlot.new()
	if it != null:
		s.tint = it.color
		s.mark = UiSlot.initials(it.display_name)
		s.tooltip_text = it.display_name
	s.count = qty
	s.focus_mode = Control.FOCUS_NONE
	return s
