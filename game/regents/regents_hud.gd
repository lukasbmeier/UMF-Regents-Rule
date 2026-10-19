class_name RegentsHud extends Node
## REGENT'S RULE'S HUD (a genre scene, `genre.tres`), named `HUD` so it REPLACES the foundation's (Boot,
## DECISIONS #197): no match line (the world is the lobby: design pillar 1), but the foundation HUD's
## connection line until you are in, its hold prompt, timed-press bar and noises. The local player's
## skilling, shown: the prompt for
## the tree in front of them; a round the server dealt, PLAYED here (`ChopMinigame` over the game, the
## player held still and the cursor free) and its inputs handed to `SkillingComponent.submit_round`;
## what each chop gave ("+3 Logs", a rare find, Timber!); and the bag. Presentation only.

const NOTICE_S: float = 3.0
## How long a round's end screen stays before the game comes back.
const ROUND_END_S: float = 1.6
const HOLD_REASON: StringName = &"regents_round"

var skilling: SkillingComponent = null
var game: ChopMinigame
var _layer: CanvasLayer
var _status: Label
var _prompt: Label
var _notices: VBoxContainer
var _bag: Label
var _round_box: Control
var _round_tree_id: int = -1
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
	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_font_size_override(&"font_size", 18)
	base.add_child(_status)
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -150.0
	_prompt.offset_left = -400.0
	_prompt.offset_right = 400.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override(&"font_size", 22)
	_prompt.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.add_theme_constant_override(&"outline_size", 6)
	_layer.add_child(_prompt)
	_notices = VBoxContainer.new()
	_notices.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_notices.offset_top = -170.0
	_notices.offset_left = -300.0
	_notices.offset_right = 300.0
	_notices.alignment = BoxContainer.ALIGNMENT_END
	_layer.add_child(_notices)
	_bag = Label.new()
	_bag.position = Vector2(16, 44)
	_bag.add_theme_font_size_override(&"font_size", 18)
	_bag.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_bag.add_theme_constant_override(&"outline_size", 5)
	_layer.add_child(_bag)
	_round_box = Control.new()
	_round_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_round_box.offset_left = -480.0
	_round_box.offset_right = 480.0
	_round_box.offset_top = -310.0
	_round_box.offset_bottom = 310.0
	_round_box.visible = false
	_round_box.clip_contents = true
	_layer.add_child(_round_box)
	game = ChopMinigame.new()
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_round_box.add_child(game)
	game.round_finished.connect(_on_round_finished)


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
	s.harvested.connect(_on_harvested)
	s.refused.connect(func(why: String) -> void: notice(why, Color(1, 0.6, 0.5)))
	if _inventory != null:
		_inventory.inventory_changed.connect(_show_bag)
	_show_bag()


func _update_prompt() -> void:
	if skilling == null or _round_box.visible:
		_prompt.text = ""
		return
	var target: int = _interaction.get_target() if _interaction != null else -1
	var tree: TreeNodeComponent = SkillingComponent.tree_of(target) if target >= 0 else null
	if skilling.afk_tree >= 0:
		var t: TreeNodeComponent = SkillingComponent.tree_of(skilling.afk_tree)
		_prompt.text = "Chopping %s (AFK)...   E: stop   (moving stops it too)" % (t.def.display_name if t != null and t.def != null else "")
	elif tree != null and tree.def != null:
		_prompt.text = ("%s: a stump, growing back" % tree.def.display_name) if tree.felled else \
			"E: chop the %s (AFK)     Hold E: play" % tree.def.display_name.to_lower()
	else:
		_prompt.text = ""


func _on_round_dealt(_id: int, seed_value: int, tree: TreeDef, tree_id: int) -> void:
	_round_tree_id = tree_id
	_round_box.visible = true
	if _input != null:
		_input.hold_still(HOLD_REASON, true)
	MouseCapture.hold_free(HOLD_REASON, true)
	game.begin(seed_value, tree.chop)


func _on_round_finished(_live: Dictionary, _replayed: Dictionary) -> void:
	if skilling != null and skilling.round_id >= 0:
		skilling.submit_round(skilling.round_id, game.inputs)
	get_tree().create_timer(ROUND_END_S).timeout.connect(_close_round)


func _on_round_closed(_id: int) -> void:
	if game.state == ChopMinigame.State.PLAYING:
		game.finish()   # the server took it away (it ran out): what was played is what it was


func _close_round() -> void:
	if game.state == ChopMinigame.State.PLAYING:
		return
	_round_box.visible = false
	if _input != null:
		_input.hold_still(HOLD_REASON, false)
	MouseCapture.hold_free(HOLD_REASON, false)


func _on_harvested(item_id: int, qty: int, rare_item: int, felled: bool, active: bool, score_pm: int) -> void:
	var item: ItemDef = ItemDef.by_id(item_id)
	var item_name: String = item.display_name if item != null else "item %d" % item_id
	if qty > 0:
		notice("+%d %s%s" % [qty, item_name, ("   (round %d%%)" % (score_pm / 10)) if active else ""], item.color if item != null else Color.WHITE)
	elif active:
		notice("Nothing from that round (%d%%)" % (score_pm / 10), Color(1, 0.75, 0.5))
	if rare_item > 0:
		var rare: ItemDef = ItemDef.by_id(rare_item)
		notice("Found: %s!" % (rare.display_name if rare != null else "something rare"), Color(1, 0.9, 0.3))
	if felled:
		notice("Timber!", Color(0.9, 1, 0.7))


func notice(text: String, color: Color = Color.WHITE) -> void:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", 24)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override(&"outline_size", 6)
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
		var item: ItemDef = ItemDef.by_id(s.item_def_id)
		lines.append("%s  x%d" % [item.display_name if item != null else "item %d" % s.item_def_id, s.qty])
	_bag.text = "\n".join(lines)
