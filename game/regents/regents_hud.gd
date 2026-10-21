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
var combat: CombatComponent = null
var _target_box: VBoxContainer
var _target_label: Label
var _target_bar: ProgressBar
var _skillbar: Label
## A bow's draw, under the crosshair while it is drawn.
var _draw_bar: ProgressBar
## The station prompt's next redraw (msec) and what it was for.
var _prompt_next_ms: int = 0
var _prompt_target: int = -1
## The windows (owner, 2026-10-20: dedicated UI, the foundation's kit): the bag (I), the skills (K), a
## station's (tap E at it).
var bag_window: RegentsBagWindow = null
var skills_window: RegentsSkillsWindow = null
var station_window: RegentsStationWindow = null
var _bag_weapon_row: int = -2


func _ready() -> void:
	# What lies on the ground is called and graded as in the bag (DECISIONS #269).
	GroundItems.name_of = ground_name
	GroundItems.grade_of = ground_grade
	# Spells in the world: a Frost Ring's circle, what burns (owner, 2026-10-20: the Staff).
	add_child(SpellLooks.new())
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
	_bag = _label(base, Vector2(16, 44), 15)
	_bag.modulate = Color(1, 1, 1, 0.6)
	_skills = _label(base, Vector2(16, 0), 17)
	_skills.visible = false
	bag_window = RegentsBagWindow.new()
	skills_window = RegentsSkillsWindow.new()
	station_window = RegentsStationWindow.new()
	for w: UiWindow in [bag_window, skills_window, station_window]:
		_layer.add_child(w)
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
	_target_box = VBoxContainer.new()
	_target_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_target_box.offset_top = 16.0
	_target_box.offset_left = -160.0
	_target_box.offset_right = 160.0
	_target_box.visible = false
	_target_label = Label.new()
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_target_label, 20)
	_target_box.add_child(_target_label)
	_target_bar = ProgressBar.new()
	_target_bar.custom_minimum_size = Vector2(320, 18)
	_target_bar.show_percentage = false
	_target_box.add_child(_target_bar)
	base.add_child(_target_box)
	_draw_bar = ProgressBar.new()
	_draw_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_draw_bar.offset_left = -80.0
	_draw_bar.offset_right = 80.0
	_draw_bar.offset_top = 40.0
	_draw_bar.offset_bottom = 48.0
	_draw_bar.max_value = 1.0
	_draw_bar.show_percentage = false
	_draw_bar.visible = false
	base.add_child(_draw_bar)
	_skillbar = Label.new()
	_skillbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_skillbar.offset_top = -44.0
	_skillbar.offset_left = -600.0
	_skillbar.offset_right = 600.0
	_skillbar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(_skillbar, 17)
	base.add_child(_skillbar)


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
	_update_combat()


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
	combat = me.find_component(CombatComponent) as CombatComponent
	if combat != null:
		combat.refused.connect(func(why: String) -> void: notice(why, Color(1, 0.6, 0.5)))
		combat.slew.connect(_on_slew)
	if _inventory != null:
		_inventory.inventory_changed.connect(_show_bag)
	bag_window.inventory = _inventory
	bag_window.combat = combat
	skills_window.skilling = s
	station_window.skilling = s
	station_window.inventory = _inventory
	s.station_opened.connect(func(t: int) -> void: station_window.show_station(t))
	_show_bag()
	_show_skills()


## The name of an item, or its number.
## What lies on the ground is called (`GroundItems.name_of`): its graded name.
static func ground_name(item_id: int, _qty: int, data: String) -> String:
	var it: ItemDef = ItemDef.by_id(item_id)
	return RegentsGrade.item_name(it, RegentsGrade.quality_of(data)) if it != null else item_name(item_id)


## Its grade (`GroundItems.grade_of`).
static func ground_grade(_item_id: int, data: String) -> int:
	return RegentsGrade.of_quality(RegentsGrade.quality_of(data))


## The game is going: the ground's hooks let go of this HUD's (a static Callable left behind a freed
## script instance crashed the engine on its way out).
func _exit_tree() -> void:
	GroundItems.name_of = Callable()
	GroundItems.grade_of = Callable()


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
		# At most four times a second: it lists every recipe there (owner, 2026-10-19: lag by a bench).
		var now: int = Time.get_ticks_msec()
		if now >= _prompt_next_ms or target != _prompt_target:
			_prompt_next_ms = now + 250
			_prompt_target = target
			_prompt.text = "" if station_window.is_open() else station_prompt(skilling, station, _inventory)
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
		return "%s, order %d of %d: %d %s for +%d %s XP (you have %d)%s\nE: open the board" % [name, int(o["slot"]) + 1,
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
		title = "%s with %s (%s)" % [r.display_name, part.display_name.to_lower(), part.handle_trait_text()]
	var rec: Dictionary = sk.recipe_record(r.id)
	var share: int = int(HotRules.number(&"regents.craft_work_share_pct"))
	var pay: String = "about %d XP a batch" % r.craft_xp(share)
	if int(rec["made"]) == 0:
		pay += ", FIRST MAKE: x%d bonus" % int(HotRules.number(&"regents.first_make_mult"))
	elif int(rec["fresh_pm"]) < 1000:
		pay += ", freshness %d%%" % (int(rec["fresh_pm"]) / 10)
	var play: String = "     Hold E: play a round of it" if r.minigame != null else ""
	return "%s: %s  <- %s\n%s\nE: open the %s (%d to make)%s" % [name, title, ", ".join(needs), pay, name.to_lower(), list.size(), play]


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
	station_window.close()
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
		var q: int = int(r["quality"])
		var quality: String = "  (quality %d%%)" % (q / 10) if q >= 0 else ""
		var round_note: String = "   (round %d%%)" % (int(r["score_pm"]) / 10) if bool(r["active"]) else ""
		var graded: Color = UiStyle.current().grade_color(RegentsGrade.of_quality(q))
		notice("+%d %s%s%s" % [int(r["qty"]), RegentsGrade.item_name(item, q) if item != null else item_name(int(r["item_id"])), quality, round_note],
			graded if graded.a > 0.0 else colour)
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


## A foe slain by this player: its name, and what it dropped.
func _on_slew(foe_id: int, loot: String) -> void:
	var foe: FoeDef = null
	for f: FoeDef in FoeDef.all():
		if f.id == foe_id:
			foe = f
	notice("Slain: %s" % (foe.display_name if foe != null else "a foe"), Color(1, 0.85, 0.6))
	for part: String in loot.split(",", false):
		var bits: PackedStringArray = part.split(":")
		if bits.size() == 2:
			var item: ItemDef = ItemDef.by_id(int(bits[0]))
			notice("+%d %s" % [int(bits[1]), item_name(int(bits[0]))], item.color if item != null else Color.WHITE)


## The target frame (name, health) and the skill bar (what each key does with the wielded weapon).
func _update_combat() -> void:
	if combat == null or not is_instance_valid(combat):
		_target_box.visible = false
		_skillbar.text = ""
		return
	var t: SpaceTimeEntity = EntityRegistry.get_entity(combat.target_id) as SpaceTimeEntity if combat.target_id >= 0 else null
	var h: SpaceTimeHealthComponent = t.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent if t != null else null
	_target_box.visible = h != null
	if h != null:
		_target_label.text = "%s   %d / %d" % [t.definition.display_name if t.definition != null else "?", roundi(h.get_current()), roundi(h.get_max())]
		_target_bar.max_value = h.get_max()
		_target_bar.value = h.get_current()
	_skillbar.text = skill_bar(combat, skilling)
	_draw_bar.visible = combat.drawing() or combat.casting()
	_draw_bar.value = combat.draw_progress() if combat.drawing() else combat.cast_progress()
	if bag_window.is_open() and combat.weapon_row != _bag_weapon_row:
		_bag_weapon_row = combat.weapon_row
		bag_window.refresh()


## What the skill bar says: the weapon, its moves, each skill key (locked ones with the rank they need).
static func skill_bar(c: CombatComponent, sk: SkillingComponent) -> String:
	if c.kit == null:
		return "No weapon wielded:  I  opens the bag"
	var keys: PackedStringArray = PackedStringArray(["Q", "E", "R", "F"])
	var parts: PackedStringArray = PackedStringArray()
	if c.kit.casts():
		var p: ResourceComponent = c.pool()
		var mana: String = "%d/%d %s" % [roundi(p.level(c.kit.resource.id)), roundi(p.max_of(c.kit.resource.id)), c.kit.resource.display_name.to_lower()] if p != null else "?"
		parts.append("%s:  LMB %s   Ctrl roll   Tab target   |   %s" % [c.weapon.display_name if c.weapon != null else "?", c.kit.light[0].display_name, mana])
		var r: int = sk.rank_in(c.kit.skill) if sk != null else 1
		for i: int in mini(4, c.kit.skills.size()):
			var a: AbilityDef = c.kit.skills[i]
			var sp: SpellDef = SpellDef.by_ability(a.id)
			var note: String = " (rank %d)" % c.kit.rank_for(i) if r < c.kit.rank_for(i) else (" %.0fs" % ceilf(c.spell_cooldown_sec(a)) if c.spell_cooldown_sec(a) > 0.0 else "")
			parts.append("%s %s %d%s" % [keys[i], a.display_name, roundi(sp.cost) if sp != null else 0, note])
		return "   |   ".join(parts) + ("" if c.in_stance() else "   (spells in stance)")
	if c.kit.draws:
		var line: String = "%s:  hold LMB draw, let go loose   RMB let go   Ctrl roll   Tab target   |   %d arrows" % [
			c.weapon.display_name if c.weapon != null else "?", c.ammo_count()]
		var chance: float = c.hit_chance_now()
		return line + ("   |   to hit %d%%" % roundi(chance) if chance >= 0.0 else "   |   no target: it flies where you aim")
	parts.append("%s:  LMB %s   hold LMB %s   RMB block   Ctrl roll   Tab target" % [c.weapon.display_name if c.weapon != null else "?",
		c.kit.light[0].display_name, c.kit.heavy.display_name if c.kit.heavy != null else "-"])
	var rank: int = sk.rank_in(c.kit.skill) if sk != null else 1
	for i: int in 4:
		if i < c.kit.skills.size():
			var locked: bool = rank < c.kit.rank_for(i)
			parts.append("%s %s%s" % [keys[i], c.kit.skills[i].display_name, " (rank %d)" % c.kit.rank_for(i) if locked else ""])
	return "   |   ".join(parts) + ("" if c.in_stance() else "   (skills in stance)")


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo or skilling == null or _round_box.visible:
		return
	if k.physical_keycode == KEY_I:
		toggle_bag()
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_K:
		skills_window.toggle()
		get_viewport().set_input_as_handled()


## Open or close the bag (I).
func toggle_bag() -> void:
	bag_window.combat = combat
	bag_window.toggle()


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


## The bag changed: its window follows; on screen, only the keys' hint.
func _show_bag() -> void:
	_bag.text = "I: bag     K: skills" if _inventory != null else ""
	bag_window.refresh()


func _show_skills() -> void:
	skills_window.refresh()
	if skilling == null:
		_skills.text = ""
		return
	var lines: PackedStringArray = PackedStringArray(["Skills"])
	for s: SkillDef in SkillDef.all():
		var xp: int = int(skilling.xp.get(s.id, 0))
		var p: Vector2i = s.progress(xp)
		lines.append("%s  %d%s" % [s.display_name, s.rank_of(xp), ("   %d / %d" % [p.x, p.y]) if p.y > 0 else "   (max)"])
	_skills.text = "\n".join(lines)
