extends Node
## THE SKILLING CHAIN, PLAYED (game/regents/tests/skilling_playtest.sh starts two of these): a real client
## through the latency simulator, in the frontier glade, through the real keys and clicks.
##   `--role=chopper`  chops tree_1 AFK (tap E; walking away stops it) and a round (hold E, A and D, the
##                     player held still); mines a round at a copper rock (clicks on the glow); smelts a round
##                     of copper bars (the bellows, the pour); makes rivets AFK at the anvil; asks the shell
##                     for what a fresh character cannot reach in a test (two logs, two iron bars); carves a
##                     handle AFK; picks the axe head with Q and shapes it in a round; assembles an Iron axe;
##                     chops again with the iron axe in the hand, at its speed
##   `--role=buddy`    chops tree_1 AFK beside them, gets logs too (or sees it fall), and sees them swing
## Every step checks what the server paid, the skill's XP, and how it looks. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 260.0
const TREE_1: Vector3 = Vector3(-9.0, 0.0, -6.0)
const COPPER_1: Vector3 = Vector3(14.0, 0.0, 16.0)
const FURNACE: Vector3 = Vector3(-6.0, 0.0, 14.0)
const ANVIL: Vector3 = Vector3(-2.0, 0.0, 16.5)
const BENCH: Vector3 = Vector3(4.0, 0.0, 15.0)
const LOGS: int = 40002
const AXE: int = 40001
const PICK: int = 40006
const COPPER_ORE: int = 40007
const COPPER_BAR: int = 40010
const IRON_BAR: int = 40011
const RIVETS: int = 40012
const HANDLE: int = 40013
const HEAD: int = 40014
const IRON_AXE: int = 40015
const OAK_LOGS: int = 40003
const OAK_HANDLE: int = 40016
const SKILL_WOODCUTTING: int = 40001
const SKILL_MINING: int = 40002
const SKILL_SMELTING: int = 40003
const SKILL_SMITHING: int = 40004
const SKILL_CRAFTING: int = 40005

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "chopper"
var me: SpaceTimeEntity
var skilling: SkillingComponent
var inv: SpaceTimeInventoryComponent
var hud: RegentsHud
var interaction: InteractionComponent
var look: SkillingLook
## The axe head's round score (its quality).
var shaped_q: int = 0
var driver: AnimationDriverComponent


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	me = await _local_entity()
	if me == null:
		_finish()
		return
	skilling = me.find_component(SkillingComponent) as SkillingComponent
	inv = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	hud = get_tree().current_scene.find_child("HUD", true, false) as RegentsHud
	interaction = me.find_component(InteractionComponent) as InteractionComponent
	look = me.find_component(SkillingLook) as SkillingLook
	driver = me.find_component(AnimationDriverComponent) as AnimationDriverComponent
	_check(skilling != null and inv != null and hud != null and look != null, "the adventurer has skilling, a bag and its look; the genre's HUD is up")
	if skilling == null or inv == null or hud == null:
		_finish()
		return
	await _until(func() -> bool: return inv.count(AXE) == 1 and inv.count(PICK) == 1, 5.0)
	_check(inv.count(AXE) == 1 and inv.count(PICK) == 1, "a Bronze axe and a Bronze pickaxe in the bag")
	var tree_id: int = await _node_at(TREE_1)
	_check(tree_id > 0, "tree_1 is a node, drawn as a Tree")
	if tree_id <= 0:
		_finish()
		return
	if _role == "buddy":
		await _buddy(tree_id)
	else:
		await _chopper(tree_id)
	_finish()


func _chopper(tree_id: int) -> void:
	# --- WOODCUTTING: tap E (AFK), then hold E (a round, A and D) ---
	await _stand_by(TREE_1)
	await _chat_with_buddy()
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	_check(interaction.get_target() == tree_id, "facing it, the tree is the target (got %d)" % interaction.get_target())
	_check(hud._prompt.text.contains("Hold E"), "the prompt says tap or hold: \"%s\"" % hud._prompt.text)
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_target == tree_id, 3.0)
	_check(skilling.afk_target == tree_id and hud._prompt.text.contains("(AFK)"), "a tap of E: working the tree AFK (\"%s\")" % hud._prompt.text)
	await _until(func() -> bool: return look.tool != null and driver.pose_weight() > 0.6, 2.0)
	_check(look.tool != null and driver.pose_clip() == &"extra/TreeChopping", "chopping AFK, the character swings the bronze axe (%s)" % driver.pose_clip())
	var logs0: int = inv.count(LOGS)
	var node: NodeComponent = SkillingComponent.node_of(tree_id)
	for attempt: int in 3:
		await _until(func() -> bool: return (inv.count(LOGS) > logs0 and int(skilling.xp.get(SKILL_WOODCUTTING, 0)) >= 10) or node.depleted, 7.0)
		print("   AFK, tree %d: %d -> %d logs%s" % [attempt + 1, logs0, inv.count(LOGS), " (it fell)" if node.depleted else ""])
		if inv.count(LOGS) > logs0:
			break
		tree_id = await _standing_node(1, &"axe")
		node = SkillingComponent.node_of(tree_id)
		await _stand_by((EntityRegistry.get_entity(tree_id) as Node3D).global_position)
		await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
		await _tap(&"interact", 0.08)
	_check(inv.count(LOGS) > logs0 and int(skilling.xp.get(SKILL_WOODCUTTING, 0)) >= 10, "a log comes AFK, and woodcutting XP with it")
	if not node.depleted:
		await _stand_at((EntityRegistry.get_entity(tree_id) as Node3D).global_position + Vector3(0, 0.05, 4.0), Vector3.ZERO)
		await _until(func() -> bool: return skilling.afk_target == -1 and look.tool == null, 3.0)
		_check(skilling.afk_target == -1 and look.tool == null, "walking away stops it; the axe goes")
	tree_id = await _standing_node(1, &"axe")
	await _stand_by((EntityRegistry.get_entity(tree_id) as Node3D).global_position)
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	var logs1: int = inv.count(LOGS)
	if await _hold_for_round():
		var stood: Vector3 = me.global_position
		var chop: ChopMinigame = hud.game as ChopMinigame
		while chop.state == SkillMinigame.State.PLAYING:
			var m: ChopModel = chop.model
			var side: int = ChopModel.SIDE_RIGHT if m.head_branch() == ChopModel.BRANCH_LEFT else (ChopModel.SIDE_LEFT if m.head_branch() == ChopModel.BRANCH_RIGHT else m.side)
			await _key(KEY_A if side == ChopModel.SIDE_LEFT else KEY_D)
			await get_tree().create_timer(0.33).timeout
		print("   the chop as played: %s" % str(chop.live_result))
		_check(int(chop.live_result.get("hits", -1)) == 0 and int(chop.live_result.get("clean", 0)) >= 20, "played well through A and D")
		_check(me.global_position.distance_to(stood) < 0.2, "A and D chopped and did not walk")
		await _until(func() -> bool: return inv.count(LOGS) > logs1, 5.0)
		_check(inv.count(LOGS) > logs1, "the server replayed the chop and paid %d logs" % (inv.count(LOGS) - logs1))
		await _round_closed()

	# --- MINING: hold E at a copper rock (crack the rock, clicks on the glow) ---
	var rock_id: int = await _node_at(COPPER_1)
	await _stand_by(COPPER_1)
	await _until(func() -> bool: return interaction.get_target() == rock_id, 3.0)
	_check(interaction.get_target() == rock_id and hud._prompt.text.contains("mine"), "at the copper rock: \"%s\"" % hud._prompt.text)
	if await _hold_for_round():
		var crack: CrackMinigame = hud.game as CrackMinigame
		_check(crack != null, "holding E at a rock deals crack the rock")
		await _until(func() -> bool: return look.tool != null, 2.0)
		_check(look.tool != null and driver.pose_clip() == &"extra/Mining", "mining a round, the character swings the pickaxe (%s)" % driver.pose_clip())
		while crack != null and crack.state == SkillMinigame.State.PLAYING:
			var t: int = crack.elapsed_ms()
			if t >= crack.model.next_ok_ms + 200 and not crack.model.held:
				_click(crack, crack.from_face(crack.model.notch(crack.model.k)))
			await get_tree().process_frame
		print("   the crack as played: %s" % str(crack.live_result))
		_check(int(crack.live_result.get("hits", 0)) >= 8 and int(crack.live_result.get("splits", 0)) >= 1,
			"followed the seam by clicking its notches, and split the rock")
		await _until(func() -> bool: return inv.count(COPPER_ORE) > 0 and int(skilling.xp.get(SKILL_MINING, 0)) >= 10, 5.0)
		_check(inv.count(COPPER_ORE) > 0 and int(skilling.xp.get(SKILL_MINING, 0)) >= 10, "the server replayed the strikes: %d copper ore, and mining XP" % inv.count(COPPER_ORE))
		await _round_closed()

	# --- SMELTING: hold E at the furnace (bellows, then pour); two ores to a bar, so the shell tops it up ---
	print("GRANT_ORE %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(COPPER_ORE) >= 2, 20.0)
	var furnace: int = await _station_at(FURNACE)
	await _stand_by(FURNACE)
	await _until(func() -> bool: return interaction.get_target() == furnace, 3.0)
	_check(hud._prompt.text.contains("Copper bar"), "at the furnace, copper bars picked: \"%s\"" % hud._prompt.text.replace("\n", " / "))
	if inv.count(COPPER_ORE) > 0 and await _hold_for_round():
		var smelt: SmeltMinigame = hud.game as SmeltMinigame
		while smelt != null and smelt.state == SkillMinigame.State.PLAYING:
			var t: int = smelt.elapsed_ms()
			smelt.model.advance_to(t)
			# As a person plays it: a press per pump (down, then up), then hold to pour and let go at the line.
			if smelt.model.in_heat():
				smelt.button(not smelt._down and smelt.model.heat < smelt.model.band(smelt.model.tick).x)
			elif not smelt.model.pouring and not smelt.model.poured:
				smelt.button(not smelt._down)
			elif smelt.model.pouring:
				smelt.button(smelt.model.fill < smelt.model.target - (smelt.params as SmeltParams).pour_rate / 2)
			await get_tree().process_frame
		print("   the smelt as played: %s" % str(smelt.live_result))
		await _until(func() -> bool: return inv.count(COPPER_BAR) > 0 and int(skilling.xp.get(SKILL_SMELTING, 0)) >= 6, 5.0)
		_check(inv.count(COPPER_BAR) > 0 and int(skilling.xp.get(SKILL_SMELTING, 0)) >= 6, "smelted %d copper bars (the bellows, the pour), and smelting XP" % inv.count(COPPER_BAR))
		await _round_closed()

	# --- THE SHELL'S GIFT: two logs and two iron bars (a fresh character's iron needs mining rank 2) ---
	print("GRANT_ME %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(IRON_BAR) >= 2 and inv.count(LOGS) >= 2 and inv.count(OAK_LOGS) >= 2, 20.0)
	_check(inv.count(IRON_BAR) >= 2 and inv.count(LOGS) >= 2 and inv.count(OAK_LOGS) >= 2, "the shell gave two iron bars, two logs and two oak logs")

	# --- THE ANVIL: rivets AFK (tap E), then the axe head (Q, hold E: shape to the outline) ---
	var anvil: int = await _station_at(ANVIL)
	await _stand_by(ANVIL)
	await _until(func() -> bool: return interaction.get_target() == anvil, 3.0)
	_check(hud._prompt.text.contains("Copper rivets"), "at the anvil, rivets picked: \"%s\"" % hud._prompt.text.replace("\n", " / "))
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return hud.station_window.is_open(), 2.0)
	_check(hud.station_window.is_open() and hud.station_window.title == "Anvil" and hud.station_window.choices.size() >= 2,
		"a tap of E opens the anvil's window: %d things to make" % hud.station_window.choices.size())
	await _shot("station_anvil")
	_check(await _make("Copper rivets"), "rivets picked there, and MAKE pressed")
	await _until(func() -> bool: return inv.count(RIVETS) >= 4, 6.0)
	_check(inv.count(RIVETS) >= 4, "a tap of E: rivets made AFK (%d)" % inv.count(RIVETS))
	await _until(func() -> bool: return skilling.afk_target == -1, 15.0)
	_check(skilling.afk_target == -1 and inv.count(COPPER_BAR) == 0, "out of copper bars, the work stops by itself (%d rivets)" % inv.count(RIVETS))
	_check(await _pick("Iron axe head"), "the window picks the axe head (hold E plays a round of it)")
	hud.station_window.close()
	await _until(func() -> bool: return hud._prompt.text.contains("Iron axe head"), 2.0)
	_check(hud._prompt.text.contains("Iron axe head"), "the prompt says so: \"%s\"" % hud._prompt.text.replace("\n", " / "))
	if await _hold_for_round():
		var shape: ShapeMinigame = hud.game as ShapeMinigame
		await _until(func() -> bool: return look.tool != null, 2.0)
		_check(look.tool != null and look.tool_scene == SkillDef.by_key(&"smithing").tool_scene, "smithing, the hammer is in the hand")
		var outline: PackedInt32Array = (shape.params as ShapeParams).outline
		while shape != null and shape.state == SkillMinigame.State.PLAYING:
			var t: int = shape.elapsed_ms()
			if t >= shape.model.next_ok_ms:
				if shape.model.hot_until_ms - t < 500:
					_click(shape, Vector2(10, 10), MOUSE_BUTTON_RIGHT)
				else:
					var c: int = 0
					for i: int in shape.model.heights.size():
						if shape.model.heights[i] - outline[i] > shape.model.heights[c] - outline[c]:
							c = i
					if shape.model.heights[c] - outline[c] > 0:
						var r: Rect2 = shape.bar_rect()
						_click(shape, Vector2(r.position.x + (c + 0.5) * r.size.x / outline.size(), r.position.y + r.size.y * 0.5))
			await get_tree().process_frame
		print("   the head as shaped: %s" % str(shape.live_result))
		shaped_q = int(shape.live_result.get("score_pm", 0))
		await _until(func() -> bool: return inv.count(HEAD) == 1 and int(skilling.xp.get(SKILL_SMITHING, 0)) >= 30, 5.0)
		_check(inv.count(HEAD) == 1 and int(skilling.xp.get(SKILL_SMITHING, 0)) >= 30, "an iron axe head, shaped by clicks, and smithing XP (%d heads, %d XP)" % [inv.count(HEAD), int(skilling.xp.get(SKILL_SMITHING, 0))])
		await _round_closed()

	# --- THE WORKBENCH: a handle AFK, then the iron axe ---
	var bench: int = await _station_at(BENCH)
	await _stand_by(BENCH)
	await _until(func() -> bool: return interaction.get_target() == bench, 3.0)
	# E AT A STATION WORKS IT, IN STANCE TOO (owner, 2026-10-20: "pressing e says I dont have an ability
	# on that key yet"): a staff in hand (E is its Frost Ring), just swung, no target: E opens the bench.
	var fighter: CombatComponent = hud.combat
	var kept_kit: KitDef = fighter.kit
	fighter.kit = KitDef.by_key(&"staff")
	fighter._last_swing_ms = Time.get_ticks_msec()
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return hud.station_window.is_open(), 2.0)
	_check(hud.station_window.is_open() and fighter.in_stance() and not fighter.fighting(),
		"in stance with a staff (E: Frost Ring), no target: E at the workbench opens its window")
	fighter.kit = kept_kit
	# THE WINDOW STAYS PUT (owner, 2026-10-20: "crafting clicks dont feel immediate"): open and idle, it is
	# not rebuilt (it rebuilt every button twice a second, losing clicks and the list's scroll).
	var drawn0: int = hud.station_window.draws
	await get_tree().create_timer(2.0).timeout
	_check(hud.station_window.draws == drawn0, "open and idle for 2 s: drawn %d more times (none)" % (hud.station_window.draws - drawn0))
	hud.station_window.close()
	await get_tree().create_timer(0.3).timeout
	_check(await _make("Handle"), "the workbench's window: a handle, MAKE")
	await _until(func() -> bool: return inv.count(HANDLE) >= 1, 6.0)
	_check(inv.count(HANDLE) >= 1, "a handle carved from logs, AFK")
	if skilling.afk_target == bench:
		var stop_button: Button = hud.station_window.find_child("Stop", true, false) as Button
		_check(stop_button != null, "while it works, the window offers STOP")
		if stop_button != null:
			stop_button.pressed.emit()
	await _until(func() -> bool: return skilling.afk_target == -1, 4.0)
	_check(skilling.afk_target == -1, "STOP stops the carving")
	_check(skilling.rank_in(SkillDef.by_key(&"crafting")) >= 2, "the first handle's first-make bonus: crafting rank %d" % skilling.rank_in(SkillDef.by_key(&"crafting")))
	_check(await _make("Oak handle"), "the window: the oak handle, MAKE")
	await _until(func() -> bool: return inv.count(OAK_HANDLE) >= 1 and skilling.afk_target == -1, 12.0)
	_check(inv.count(OAK_HANDLE) == 1 and inv.count(OAK_LOGS) == 0, "an oak handle carved from oak logs; out of them, it stops by itself")
	_check(await _pick("Iron axe with oak handle"), "the window picks the iron axe with the oak handle")
	await _shot("station_workbench")
	hud.toggle_bag()
	hud.skills_window.open()
	await _shot("bag_and_skills")
	hud.toggle_bag()
	hud.skills_window.close()
	var said: String = RegentsHud.station_prompt(skilling, SkillingComponent.station_of(bench), inv)
	_check(said.contains("+15 quality") and said.contains("1 Oak handle (1)"), "it says its trait and takes the oak handle: \"%s\"" % said.replace("\n", " / "))
	var make_button: Button = hud.station_window.find_child("Make", true, false) as Button
	_check(make_button != null and not make_button.disabled, "MAKE is ready: the bag has what it takes")
	if make_button != null:
		make_button.pressed.emit()
	await _until(func() -> bool: return inv.count(IRON_AXE) == 1 and inv.count(HEAD) == 0, 8.0)
	_check(inv.count(IRON_AXE) == 1 and inv.count(HEAD) == 0 and inv.count(OAK_HANDLE) == 0 and inv.count(HANDLE) == 1,
		"the head, the oak handle and two rivets become an Iron axe (the plain handle is left)")
	var quality: String = ""
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == IRON_AXE:
			quality = s.instance_data
	var head_q: int = int(shaped_q)
	_check(quality == "{\"q\":%d,\"h\":%d}" % [mini(1000, head_q + 150), OAK_HANDLE],
		"the iron axe is its head's quality and the oak's +15, and remembers its handle (%s, head %d)" % [quality, head_q])
	await _until(func() -> bool: return skilling.afk_target == -1, 6.0)

	# --- THE IRON AXE AT WORK ---
	tree_id = await _standing_node(1, &"axe")
	await _stand_by((EntityRegistry.get_entity(tree_id) as Node3D).global_position)
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_target == tree_id and look.tool != null, 3.0)
	_check(int(skilling.afk.get("tool_item", 0)) == IRON_AXE and look.tool_scene == ItemDef.by_id(IRON_AXE).held_scene,
		"chopping now, it is with the iron axe, and the iron axe is what is in the hand")
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_target == -1, 3.0)
	_check(skilling.afk_target == -1, "a second tap stops the work")


## CHAT (DECISIONS #273), beside the buddy at tree_1: Enter, a line (typing W walks nowhere), Enter; it
## comes back to our box; the buddy's answer shows in it and over their head.
func _chat_with_buddy() -> void:
	var chat: ChatBox = _chat_box()
	_check(chat != null, "every game has the chat box")
	if chat == null:
		return
	await _key(KEY_ENTER)
	_check(chat.is_typing() and chat.input_line().has_focus(), "Enter: a line to write in")
	var at0: Vector3 = me.global_position
	Input.action_press(&"move_forward")
	await get_tree().create_timer(0.5).timeout
	Input.action_release(&"move_forward")
	_check(me.global_position.distance_to(at0) < 0.05, "W held while typing: it walks nowhere (%.2f m)" % me.global_position.distance_to(at0))
	chat.input_line().text = "timber!"
	await _key(KEY_ENTER)
	_check(not chat.is_typing(), "Enter: sent, and the line closes")
	await _until(func() -> bool: return not _said_by("timber!", chat).is_empty(), 4.0)
	_check(not _said_by("timber!", chat).is_empty(), "our line comes back from the server into our box (%s)" % str(chat.shown()))
	var buddy: Array[int] = [-1]
	await _until(func() -> bool:
		buddy[0] = _speaker_of("nice swing", chat)
		return buddy[0] > 0 and chat.bubble_of(buddy[0]) == "nice swing", 30.0)
	_check(buddy[0] > 0 and chat.bubble_of(buddy[0]) == "nice swing", "the buddy's answer: in our box and over their head (%s)" % str(chat.shown()))
	await get_tree().create_timer(0.5).timeout   # the new words drawn (the font makes their glyphs first)
	await _shot("chat")


## The world's chat box (Boot adds one to every game).
func _chat_box() -> ChatBox:
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if n is ChatBox:
			return n as ChatBox
	return null


## The line in `chat` that says `text` ("name: text"), or "".
func _said_by(text: String, chat: ChatBox) -> String:
	for l: String in chat.shown():
		if l.ends_with(": " + text):
			return l
	return ""


## Who said `text` in `chat` (their entity), or -1.
func _speaker_of(text: String, chat: ChatBox) -> int:
	for id: int in chat._lines:
		if String(chat._lines[id]["text"]) == text:
			return int(chat._lines[id]["entity"])
	return -1


## SHOTS: save what the player sees now as `<name>.png` in the --shots directory (none: nothing).
func _shot(name: String) -> void:
	var dir: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.substr(8)
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))


## Open the station's window (a tap of E) if it is not, and pick `text` in it (what a click does).
func _pick(text: String) -> bool:
	if not hud.station_window.is_open():
		await _tap(&"interact", 0.08)
		await _until(func() -> bool: return hud.station_window.is_open(), 2.0)
	var ok: bool = hud.station_window.pick_named(text)
	await get_tree().process_frame
	return ok


## Pick `text` in the station's window and press MAKE (AFK). False when it is not there or cannot be made.
func _make(text: String) -> bool:
	if not await _pick(text):
		return false
	var b: Button = hud.station_window.find_child("Make", true, false) as Button
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func _buddy(tree_id: int) -> void:
	await _stand_at(TREE_1 + Vector3(1.6, 0.05, 0.0), TREE_1)
	# CHAT: the chopper's line reaches us, and we answer. Headless, Boot adds no UI, so the buddy gets the
	# box it would have had: the same code hearing the same rows.
	var chat: ChatBox = _chat_box()
	if chat == null:
		chat = ChatBox.new()
		get_tree().root.add_child(chat)
	await _until(func() -> bool: return chat != null and chat.shown().has(_said_by("timber!", chat)), 40.0)
	var line: String = _said_by("timber!", chat) if chat != null else ""
	_check(not line.is_empty() and chat.shown().has(line), "the chopper's line reaches the buddy's chat box (%s)" % line)
	if chat != null:
		await _key(KEY_ENTER)
		chat.input_line().text = "nice swing"
		await _key(KEY_ENTER)
	skilling.work(tree_id, false)
	await _until(func() -> bool: return skilling.afk_target == tree_id, 3.0)
	_check(skilling.afk_target == tree_id, "the buddy chops the same tree AFK")
	# The chopper beside us, as WE draw them: their afk_work row reaches us, and their axe swings here too.
	var seen: Array[bool] = [false]
	await _until(func() -> bool:
		for id: int in EntityRegistry.all_entity_ids():
			var other: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if other == null or other == me:
				continue
			var s: SkillingComponent = other.find_component(SkillingComponent) as SkillingComponent
			var l: SkillingLook = other.find_component(SkillingLook) as SkillingLook
			var d: AnimationDriverComponent = other.find_component(AnimationDriverComponent) as AnimationDriverComponent
			if s != null and s.afk_target >= 0 and l != null and l.tool != null and d != null and d.pose_clip() == &"extra/TreeChopping":
				seen[0] = true
		return seen[0], 8.0)
	_check(seen[0], "the other player chopping is drawn swinging an axe on this client too")
	var node: NodeComponent = SkillingComponent.node_of(tree_id)
	await _until(func() -> bool: return inv.count(LOGS) > 0 or node.depleted, 9.0)
	print("   buddy: %d logs, the tree %s" % [inv.count(LOGS), "fell" if node.depleted else "stands"])
	_check(inv.count(LOGS) > 0 or node.depleted, "two at one tree: the buddy gets logs too (or sees it fall)")


## Hold E on the target until the server deals its round and the HUD shows it. True when it did.
func _hold_for_round() -> bool:
	Input.action_press(&"interact")
	await _until(func() -> bool: return hud._round_box.visible and hud.game != null and hud.game.state == SkillMinigame.State.PLAYING, 4.0)
	Input.action_release(&"interact")
	var ok: bool = hud._round_box.visible and hud.game != null
	_check(ok, "holding E: the server deals a round, and it is on screen (%s)" % (hud.game.get_class() if hud.game != null else "none"))
	return ok


func _round_closed() -> void:
	await _until(func() -> bool: return not hud._round_box.visible, 4.0)
	_check(not hud._round_box.visible and not MouseCapture.is_held_free(), "the round closes and the game comes back")


## A click on the minigame `game` at `at` (its own coordinates), as the mouse sends it.
func _click(game: Control, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = button
	e.position = at
	e.pressed = true
	game._gui_input(e)


## The standing node of `tier` with tool `tag` nearest the spawn, or -1.
func _standing_node(tier: int, tag: StringName) -> int:
	var best: int = -1
	var best_d: float = INF
	for id: int in EntityRegistry.all_entity_ids():
		var n: NodeComponent = SkillingComponent.node_of(id)
		if n == null or n.depleted or n.def == null or n.def.tier != tier or n.def.tool_tag != tag:
			continue
		var d: float = (EntityRegistry.get_entity(id) as Node3D).global_position.distance_to(Vector3(0, 0, 8))
		if d < best_d:
			best_d = d
			best = id
	return best


func _node_at(at: Vector3) -> int:
	return await _entity_at(at, func(id: int) -> bool: return SkillingComponent.node_of(id) != null and SkillingComponent.node_of(id).def != null)


func _station_at(at: Vector3) -> int:
	return await _entity_at(at, func(id: int) -> bool: return SkillingComponent.station_of(id) != null and SkillingComponent.station_of(id).def != null)


func _entity_at(at: Vector3, wanted: Callable) -> int:
	var found: int = -1
	var deadline: int = Time.get_ticks_msec() + 8000
	while found < 0 and Time.get_ticks_msec() < deadline:
		for id: int in EntityRegistry.all_entity_ids():
			if bool(wanted.call(id)) and (EntityRegistry.get_entity(id) as Node3D).global_position.distance_to(at) < 0.5:
				found = id
		await get_tree().process_frame
	return found


## Stand 1.5 m south of `target`, facing it.
func _stand_by(target: Vector3) -> void:
	await _stand_at(target + Vector3(0, 0.05, 1.5), target)


func _stand_at(at: Vector3, face: Vector3) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [at], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return me.global_position.distance_to(at) < 0.4, 4.0)
	var to: Vector3 = face - at
	(me.find_component(LocalInputComponent) as LocalInputComponent).set_look(atan2(-to.x, -to.z) if to.length() > 0.01 else 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout


func _tap(action: StringName, hold_s: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(hold_s).timeout
	Input.action_release(action)
	await get_tree().physics_frame


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().physics_frame


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame


func _local_entity() -> SpaceTimeEntity:
	var deadline: int = Time.get_ticks_msec() + 30_000
	while Time.get_ticks_msec() < deadline:
		var id: int = EntityRegistry.local_entity_id
		if id >= 0:
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e != null and e.is_bound():
				return e
		await get_tree().process_frame
	_check(false, "local player spawned and bound")
	return null


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: skilling playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\nskilling (%s): %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
