class_name RegentsHud extends Node
## REGENT'S RULE'S HUD (a genre scene, `genre.tres`), named `HUD` so it REPLACES the foundation's (Boot,
## DECISIONS #197): no match line (the world is the lobby: design pillar 1), but the foundation HUD's
## connection line until you are in, its hold prompt, timed-press bar and noises. The local player's
## skilling, shown: the prompt for the node or station in front of them (at a station, what Q has picked
## and what it takes); a round the server dealt, PLAYED here (its `SkillMinigame` over the game, the
## player held still and the cursor free) and its inputs handed to `SkillingComponent.submit_round`; what
## each piece of work gave ("+3 Copper ore", "+30 Mining XP", a rank, a rare find, the node worked out);
## the bag; the skills and their ranks. Presentation only.

const NOTICE_S: float = 3.0
## How long a round's end screen stays before the game comes back.
const ROUND_END_S: float = 1.6
const HOLD_REASON: StringName = &"regents_round"

var skilling: SkillingComponent = null
## The round on screen (its minigame), or null.
var game: SkillMinigame = null
var _layer: CanvasLayer
var _status: Label
var _prompt: Label
var _notices: VBoxContainer
var _bag: Label
var _skills: Label
var _round_box: Control
var _inventory: SpaceTimeInventoryComponent = null
var _interaction: InteractionComponent = null
var _input: LocalInputComponent = null


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	var base: Control = Control.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(base)
	base.add_child(HoldPrompt.new())
	base.add_child(TimingBar.new())
	base.add_child(NoiseFeedback.new())
	_status = _label(base, Vector2(16, 12), 18)
	_bag = _label(base, Vector2(16, 44), 17)
	_skills = _label(base, Vector2(16, 0), 17)
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -170.0
	_prompt.offset_left = -500.0
	_prompt.offset_right = 500.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_prompt, 22)
	base.add_child(_prompt)
	_notices = VBoxContainer.new()
	_notices.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_notices.offset_top = -200.0
	_notices.offset_left = -300.0
	_notices.offset_right = 300.0
	_notices.alignment = BoxContainer.ALIGNMENT_END
	base.add_child(_notices)
	_round_box = Control.new()
	_round_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_round_box.offset_left = -480.0
	_round_box.offset_right = 480.0
	_round_box.offset_top = -310.0
	_round_box.offset_bottom = 310.0
	_round_box.visible = false
	_round_box.clip_contents = true
	base.add_child(_round_box)


func _label(parent: Control, at: Vector2, font_size: int) -> Label:
	var l: Label = Label.new()
	l.position = at
	_outline(l, font_size)
	parent.add_child(l)
	return l


func _outline(l: Label, font_size: int) -> void:
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 6)


func _process(_delta: float) -> void:
	if skilling == null or not is_instance_valid(skilling):
		_find_player()
	_status.text = FoundationHud.connection_line() if skilling == null else ""
	_update_prompt()


func _find_player() -> void:
	skilling = null
	var me: SpaceTimeEntity = EntitySpawner.get_entity_node(EntityRegistry.local_entity_id) as SpaceTimeEntity if EntityRegistry.local_entity_id > 0 else null
	if me == null:
		return
	var s: SkillingComponent = me.find_component(SkillingComponent) as SkillingComponent
	if s == null or not s.is_bound():
		return
	skilling = s
	_inventory = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	_interaction = me.find_component(InteractionComponent) as InteractionComponent
	_input = me.find_component(LocalInputComponent) as LocalInputComponent
	s.round_dealt.connect(_on_round_dealt)
	s.round_closed.connect(_on_round_closed)
	s.worked.connect(_on_worked)
	s.xp_changed.connect(func(_id: int, _xp: int) -> void: _show_skills())
	s.refused.connect(func(why: String) -> void: notice(why, Color(1, 0.6, 0.5)))
	if _inventory != null:
		_inventory.inventory_changed.connect(_show_bag)
	_show_bag()
	_show_skills()


## The name of an item, or its number.
static func item_name(item_id: int) -> String:
	var it: ItemDef = ItemDef.by_id(item_id)
	return it.display_name if it != null else "item %d" % item_id


func _update_prompt() -> void:
	if skilling == null or _round_box.visible:
		_prompt.text = ""
		return
	if skilling.afk_target >= 0:
		_prompt.text = "%s (AFK)...   E: stop   (moving stops it too)" % _target_name(skilling.afk_target)
		return
	var target: int = _interaction.get_target() if _interaction != null else -1
	var node: NodeComponent = SkillingComponent.node_of(target) if target >= 0 else null
	var station: StationComponent = SkillingComponent.station_of(target) if target >= 0 else null
	if node != null and node.def != null:
		var d: NodeDef = node.def
		if node.depleted:
			_prompt.text = "%s: worked out, coming back" % d.display_name
		elif skilling.rank_in(d.skill) < d.min_rank:
			_prompt.text = "%s: needs %s rank %d (yours %d)" % [d.display_name, d.skill.display_name, d.min_rank, skilling.rank_in(d.skill)]
		else:
			_prompt.text = "E: %s the %s (AFK)     Hold E: play" % ["chop" if d.tool_tag == &"axe" else "mine", d.display_name.to_lower()]
	elif station != null and station.def != null:
		_prompt.text = station_prompt(skilling, station, _inventory)
	else:
		_prompt.text = ""


## What the prompt says at `station`: the choice Q has picked (a recipe, with its handle, what it takes,
## what it pays and how fresh it is; or a work order) and the keys. Static so a test can read it.
static func station_prompt(sk: SkillingComponent, station: StationComponent, inv: SpaceTimeInventoryComponent) -> String:
	var list: Array[Dictionary] = sk.choices_at(station)
	var c: Dictionary = sk.choice_at(station)
	var name: String = station.def.display_name
	if c.has("order"):
		var o: Dictionary = c["order"]
		var skill: SkillDef = SkillDef.by_id(int(o["skill_id"]))
		var have: int = inv.count(int(o["item_id"])) if inv != null else 0
		var state: String = "   (filled)" if bool(o["filled"]) else ""
		return "%s, order %d of %d: %d %s for +%d %s XP (you have %d)%s\nE: hand them over     Q: next order" % [name, int(o["slot"]) + 1,
			list.size(), int(o["qty"]), item_name(int(o["item_id"])), int(o["xp"]), skill.display_name if skill != null else "?", have, state]
	if not c.has("recipe"):
		return "%s: %s" % [name, "no orders yet" if station.key == SkillingComponent.ORDER_BOARD else "nothing is made here"]
	var r: RecipeDef = c["recipe"]
	var part: ItemDef = c.get("part", null) as ItemDef
	var needs: PackedStringArray = PackedStringArray()
	for i: int in r.inputs.size():
		var it: ItemDef = part if i == r.part_slot and part != null else r.inputs[i]
		var have: int = inv.count(it.id) if inv != null else 0
		needs.append("%d %s (%d)" % [r.input_qty[i], it.display_name, have])
	var title: String = r.display_name
	if part != null and part != r.inputs[r.part_slot]:
		title = "%s with %s (%s)" % [r.display_name, part.display_name.to_lower(), part.handle_trait()]
	var rec: Dictionary = sk.recipe_record(r.id)
	var share: int = int(HotRules.number(&"regents.craft_work_share_pct"))
	var pay: String = "about %d XP a batch" % r.craft_xp(share)
	if int(rec["made"]) == 0:
		pay += ", FIRST MAKE: x%d bonus" % int(HotRules.number(&"regents.first_make_mult"))
	elif int(rec["fresh_pm"]) < 1000:
		pay += ", freshness %d%%" % (int(rec["fresh_pm"]) / 10)
	var play: String = "     Hold E: play" if r.minigame != null else ""
	return "%s: %s  <- %s\n%s\nE: make (AFK)%s     Q: next of %d" % [name, title, ", ".join(needs), pay, play, list.size()]


func _target_name(target: int) -> String:
	var node: NodeComponent = SkillingComponent.node_of(target)
	if node != null and node.def != null:
		return "Working the %s" % node.def.display_name.to_lower()
	var r: RecipeDef = RecipeDef.by_id(int(skilling.afk.get("def_id", 0)))
	var part: ItemDef = ItemDef.by_id(int(skilling.afk.get("tool_item", 0)))
	var with_part: String = " with %s" % part.display_name.to_lower() if part != null and r != null and r.part_slot >= 0 and part != r.inputs[r.part_slot] else ""
	return "Making %s%s" % [r.display_name if r != null else "something", with_part]


func _on_round_dealt(_id: int, seed_value: int, params: Resource, _target_id: int, _name: String) -> void:
	if game != null:
		game.queue_free()
	game = SkillMinigames.make_ui(params)
	if game == null:
		return
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_round_box.add_child(game)
	game.round_finished.connect(_on_round_finished)
	_round_box.visible = true
	if _input != null:
		_input.hold_still(HOLD_REASON, true)
	MouseCapture.hold_free(HOLD_REASON, true)
	game.begin(seed_value, params)


func _on_round_finished(_live: Dictionary, _replayed: Dictionary) -> void:
	if skilling != null and skilling.round_id >= 0:
		skilling.submit_round(skilling.round_id, game.inputs)
	get_tree().create_timer(ROUND_END_S).timeout.connect(_close_round)


func _on_round_closed(_id: int) -> void:
	if game != null and game.state == SkillMinigame.State.PLAYING:
		game.finish()   # the server took it away (it ran out): what was played is what it was


func _close_round() -> void:
	if game != null and game.state == SkillMinigame.State.PLAYING:
		return
	_round_box.visible = false
	if _input != null:
		_input.hold_still(HOLD_REASON, false)
	MouseCapture.hold_free(HOLD_REASON, false)


func _on_worked(r: Dictionary) -> void:
	var item: ItemDef = ItemDef.by_id(int(r["item_id"]))
	var colour: Color = item.color if item != null else Color.WHITE
	var board: StationComponent = SkillingComponent.station_of(int(r["target_id"]))
	if bool(r["ran_out"]):
		notice("Out of %s" % item_name(int(r["item_id"])), Color(1, 0.75, 0.5))
	elif board != null and board.key == SkillingComponent.ORDER_BOARD:
		notice("Order filled: %d %s" % [int(r["qty"]), item_name(int(r["item_id"]))], Color(1, 0.9, 0.5))
	elif int(r["qty"]) > 0:
		var quality: String = "  (quality %d%%)" % (int(r["quality"]) / 10) if int(r["quality"]) >= 0 else ""
		var round_note: String = "   (round %d%%)" % (int(r["score_pm"]) / 10) if bool(r["active"]) else ""
		notice("+%d %s%s%s" % [int(r["qty"]), item_name(int(r["item_id"])), quality, round_note], colour)
	elif bool(r["active"]):
		notice("Nothing from that round (%d%%)" % (int(r["score_pm"]) / 10), Color(1, 0.75, 0.5))
	var skill: SkillDef = SkillDef.by_id(int(r["skill_id"]))
	if int(r["xp"]) > 0 and skill != null:
		notice("+%d %s XP" % [int(r["xp"]), skill.display_name], skill.color)
	if int(r["rank"]) > 0 and skill != null:
		notice("%s rank %d!" % [skill.display_name, int(r["rank"])], Color(1, 0.95, 0.4))
	if int(r["rare_item"]) > 0:
		notice("Found: %s!" % item_name(int(r["rare_item"])), Color(1, 0.9, 0.3))
	if bool(r["depleted"]):
		var node: NodeComponent = SkillingComponent.node_of(int(r["target_id"]))
		notice("Timber!" if node == null or not node.is_rock() else "The rock is worked out", Color(0.9, 1, 0.7))


func notice(text: String, color: Color = Color.WHITE) -> void:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(l, 24)
	l.add_theme_color_override(&"font_color", color)
	_notices.add_child(l)
	var tw: Tween = l.create_tween()
	tw.tween_interval(NOTICE_S)
	tw.tween_property(l, ^"modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _show_bag() -> void:
	if _inventory == null:
		_bag.text = ""
		return
	var lines: PackedStringArray = PackedStringArray(["Bag"])
	for s: SpaceTimeInventoryComponent.Stack in _inventory.items():
		var q: String = ""
		var at: int = s.instance_data.find("\"q\":")
		if at >= 0:
			q = "  (%d%%)" % (s.instance_data.substr(at + 4).to_int() / 10)
		var h: int = s.instance_data.find("\"h\":")
		if h >= 0:
			q += "  %s" % item_name(s.instance_data.substr(h + 4).to_int()).to_lower()
		lines.append("%s  x%d%s" % [item_name(s.item_def_id), s.qty, q])
	_bag.text = "\n".join(lines)
	_skills.position.y = 44.0 + 24.0 * (lines.size() + 1)


func _show_skills() -> void:
	if skilling == null:
		_skills.text = ""
		return
	var lines: PackedStringArray = PackedStringArray(["Skills"])
	for s: SkillDef in SkillDef.all():
		var xp: int = int(skilling.xp.get(s.id, 0))
		var p: Vector2i = s.progress(xp)
		lines.append("%s  %d%s" % [s.display_name, s.rank_of(xp), ("   %d / %d" % [p.x, p.y]) if p.y > 0 else "   (max)"])
	_skills.text = "\n".join(lines)
