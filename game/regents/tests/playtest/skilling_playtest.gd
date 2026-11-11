extends Node
## THE SKILLING CHAIN, PLAYED (game/regents/tests/skilling_playtest.sh starts two of these): a real client
## through the latency simulator, in the frontier glade, through the real keys and clicks.
##   `--role=chopper`  chops tree_1 AFK (tap E; walking away stops it) and a round (hold E, A and D, the
##                     player held still); mines a round at a copper rock (clicks on the glow); smelts a round
##                     of copper bars (the bellows, the pour); makes rivets AFK at the anvil; asks the shell
##                     for what a fresh character cannot reach in a test (two logs, two iron bars); carves a
##                     handle AFK; picks the axe head with Q and shapes it in a round; assembles an Iron axe;
##                     chops again with the iron axe in the hand, at its speed
##                     THE TUTORIAL (Luke, 2026-11-01): first E on the camp's guide twice (the offer, then taken), so
##                     the chain's real work ticks its lessons; last a copper sword (the shell's bars and rivets:
##                     GRANT_SWORD), blade at the anvil and sword at the workbench, each ticked as it is made
##   `--role=buddy`    chops tree_1 AFK beside them, gets logs too (or sees it fall), and sees them swing; offered the
##                     tutorial, not begun: the card says where the guide is
## Every step checks what the server paid, the skill's XP, and how it looks. Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 460.0   # 2026-11-07: a run's second round at the tree (~12 s)
## The camp's guide (the glade's `guide` point).
const GUIDE: Vector3 = Vector3(5.0, 0.0, 22.5)
const BLADE: int = 40027
const COPPER_SWORD: int = 40028
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
# Herbalism, step 1 (2026-11-07, HERBALISM_HUNTING_PREP.md): the glade's flax patches and the spinning wheel.
const FLAX_POINTS: Array[Vector3] = [Vector3(-12.0, 0.0, 2.0), Vector3(-15.0, 0.0, 5.0), Vector3(-10.0, 0.0, 6.0), Vector3(-16.0, 0.0, 0.0)]
const WHEEL: Vector3 = Vector3(8.0, 0.0, 14.0)
const FLAX: int = 40046
const BOWSTRING: int = 40048
const STAVE: int = 40049
const YEW_BOW: int = 40020
const COPPER_TROWEL: int = 40051
const SKILL_HERBALISM: int = 40010
# Skinning, step 4's first half (2026-11-09, HERBALISM_HUNTING_PREP.md): the glade's deer, its carcass, the tanning rack.
const COPPER_KNIFE: int = 40059
const DEER_HIDE: int = 40056
const SOFT_LEATHER: int = 40057
const SKILL_SKINNING: int = 40011
const DEER_CARCASS: int = 40008
const RACK: Vector3 = Vector3(11.0, 0.0, 14.0)

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
var tutorial: TutorialComponent


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
	tutorial = me.find_component(TutorialComponent) as TutorialComponent
	_check(skilling != null and inv != null and hud != null and look != null, "the adventurer has skilling, a bag and its look; the genre's HUD is up")
	if skilling == null or inv == null or hud == null:
		_finish()
		return
	await _until(func() -> bool: return inv.count(AXE) == 1 and inv.count(PICK) == 1, 5.0)
	_check(inv.count(AXE) == 1 and inv.count(PICK) == 1, "a Copper axe and a Copper pickaxe in the bag")
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
	await _tutorial_begin()
	# --- WOODCUTTING: tap E (AFK), then hold E (a round, A and D) ---
	await _stand_by(TREE_1)
	await _chat_with_buddy()
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	_check(interaction.get_target() == tree_id, "facing it, the tree is the target (got %d)" % interaction.get_target())
	_check(hud._prompt.text.contains("Hold E"), "the prompt says tap or hold: \"%s\"" % hud._prompt.text)
	_cam_yaw0 = (me.find_component(LocalInputComponent) as LocalInputComponent).get_look_yaw()
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_target == tree_id, 6.0)
	_check(skilling.afk_target == tree_id and hud._prompt.text.contains("(AFK)"), "a tap of E: working the tree AFK (\"%s\")" % hud._prompt.text)
	_check_work_spot(tree_id, "the tree")
	await _until(func() -> bool: return look.tool != null and driver.pose_weight() > 0.6, 2.0)
	_check(look.tool != null and driver.pose_clip() == &"extra/TreeChopping", "chopping AFK, the character swings the copper axe (%s)" % driver.pose_clip())
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
	# MOVING STOPS AFK WORK (Luke's play, 2026-11-06): a short step off the work spot, well inside the server's 1 m.
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_target == tree_id, 6.0)
	var spot: Vector3 = me.global_position
	var working: bool = skilling.afk_target == tree_id
	await _tap(&"move_back", 0.12)
	await _until(func() -> bool: return skilling.afk_target == -1, 3.0)
	var moved: float = Vector2(me.global_position.x - spot.x, me.global_position.z - spot.z).length()
	_check(working and skilling.afk_target == -1 and moved < 0.9, "a short step off the work spot (%.2f m) stops the AFK work" % moved)
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	var logs1: int = inv.count(LOGS)
	# Heard from before the round is played (a tree worked out in it ends the run as the round closes).
	var ended: Array[String] = ["-"]
	var on_end: Callable = func(on: bool, why: String) -> void:
		if not on:
			ended[0] = why
	skilling.run_changed.connect(on_end)
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
		# A RUN (Luke's M11, 2026-11-05): the next round comes by itself into the same panel, E not pressed; a round
		# with nothing pressed ends it (a player called away). A tree worked out ends it too, and says so.
		var first_ui: SkillMinigame = hud.game
		await _until(func() -> bool: return ended[0] != "-" or (hud.game == first_ui and first_ui.state == SkillMinigame.State.PLAYING), 6.0)
		if SkillingComponent.node_of(tree_id) != null and SkillingComponent.node_of(tree_id).depleted:
			await _round_closed()
			_check(ended[0].begins_with("Worked out"), "the tree was worked out in the first round: the run ended, and said so (\"%s\")" % ended[0])
		else:
			_check(ended[0] == "-" and hud.game == first_ui and first_ui.state == SkillMinigame.State.PLAYING and hud._round_box.visible
				and skilling.run_target == tree_id, "a run: the next round came by itself, into the same panel (E not pressed)")
			_check(first_ui.run_line.begins_with("This run: 1 round"), "the panel keeps the run's tally: \"%s\"" % first_ui.run_line)
			await _until(func() -> bool: return first_ui.state != SkillMinigame.State.PLAYING, 14.0)
			await _round_closed()
			_check(skilling.run_target == -1 and ended[0].begins_with("Nothing pressed"), "a round with nothing pressed ended the run (\"%s\")" % ended[0])
			await get_tree().create_timer(2.0).timeout
			_check(not hud._round_box.visible and skilling.round_id < 0, "and no third round came")

	skilling.run_changed.disconnect(on_end)

	# --- MINING: hold E at a copper rock (crack the rock, clicks on the glow) ---
	var rock_id: int = await _node_at(COPPER_1)
	await _stand_by(COPPER_1)
	await _until(func() -> bool: return interaction.get_target() == rock_id, 3.0)
	_check(interaction.get_target() == rock_id and hud._prompt.text.contains("mine"), "at the copper rock: \"%s\"" % hud._prompt.text)
	_cam_yaw0 = (me.find_component(LocalInputComponent) as LocalInputComponent).get_look_yaw()
	if await _hold_for_round():
		_check_work_spot(rock_id, "the copper rock")
		var crack: CrackMinigame = hud.game as CrackMinigame
		_check(crack != null, "holding E at a rock deals crack the rock")
		await get_tree().create_timer(0.3).timeout
		await _tap(&"interact", 0.08)
		_check(skilling.run_target == rock_id and skilling.run_stop_after and crack.leave_hint.contains("E: stop after this one"),
			"E during a run's round: it plays out, then the run stops (\"%s\")" % crack.leave_hint)
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
		await get_tree().create_timer(1.5).timeout
		_check(skilling.run_target == -1 and skilling.round_id < 0 and not hud._round_box.visible, "after E, no next round at the rock")

	# --- SMELTING: hold E at the furnace (the rhythm track, then the pour); two ores to a bar, so the shell tops it up ---
	print("GRANT_ORE %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(COPPER_ORE) >= 2, 20.0)
	var furnace: int = await _station_at(FURNACE)
	await _stand_by(FURNACE)
	await _until(func() -> bool: return interaction.get_target() == furnace, 3.0)
	_check(hud._prompt.text.contains("Copper bar"), "at the furnace, copper bars picked: \"%s\"" % hud._prompt.text.replace("\n", " / "))
	if inv.count(COPPER_ORE) > 0 and await _hold_for_round():
		# Smelting's rhythm track (Luke, 2026-11-07): as a person plays it, by the frame: down as a note reaches the
		# bellows, a tap let go a moment later, a long draw at its end; then hold to pour and let go at the line.
		var smelt: BeatMinigame = hud.game as BeatMinigame
		var down_at: int = -1
		await _tap(&"interact", 0.08)   # one round only: E stops the run after it
		_check(skilling.run_stop_after, "E at the furnace's round: the run stops after it")
		while smelt != null and smelt.state == SkillMinigame.State.PLAYING:
			var t: int = smelt.elapsed_ms()
			smelt.model.advance_to(t)
			var bp: BeatParams = smelt.params as BeatParams
			if smelt.model.on_track(t):
				var j: int = smelt.model.next_note(t)
				if not smelt._down and j >= 0 and t >= smelt.model.note_t[j] - 15:
					smelt.button(true)
					down_at = t
				elif smelt._down and smelt.model.holding < 0 and t >= down_at + 60:
					smelt.button(false)
				elif smelt._down and smelt.model.holding >= 0 and t >= smelt.model.note_end[smelt.model.holding] - 30:
					smelt.button(false)
			elif not smelt.model.pouring and not smelt.model.poured:
				if smelt._down:
					smelt.button(false)
				elif smelt.model.pour_ready(t):
					smelt.button(true)
			elif smelt.model.pouring:
				smelt.button(smelt.model.fill < smelt.model.target - bp.pour_rate / 2)
			await get_tree().process_frame
		print("   the smelt as played: %s" % str(smelt.live_result))
		_check(smelt != null and int(smelt.live_result.get("track_pm", 0)) >= 600 and int(smelt.live_result.get("strays", 99)) == 0,
			"the furnace's round is the rhythm track, played on the beat by the frame (track %d, wasted %d)" % [int(smelt.live_result.get("track_pm", 0)), int(smelt.live_result.get("strays", -1))])
		await _until(func() -> bool: return inv.count(COPPER_BAR) > 0 and int(skilling.xp.get(SKILL_SMELTING, 0)) >= 6, 5.0)
		_check(inv.count(COPPER_BAR) > 0 and int(skilling.xp.get(SKILL_SMELTING, 0)) >= 6, "smelted %d copper bars (the rhythm track, the pour), and smelting XP" % inv.count(COPPER_BAR))
		await _round_closed()

	# --- THE SHELL'S GIFT: two logs and two iron bars (a fresh character's iron needs mining rank 2) ---
	print("GRANT_ME %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(IRON_BAR) >= 2 and inv.count(LOGS) >= 2 and inv.count(OAK_LOGS) >= 2, 20.0)
	_check(inv.count(IRON_BAR) >= 2 and inv.count(LOGS) >= 2 and inv.count(OAK_LOGS) >= 2, "the shell gave two iron bars, two logs and two oak logs")

	# --- THE ANVIL: rivets AFK (tap E), then the axe head (Q, hold E: shape to the outline) ---
	var anvil: int = await _station_at(ANVIL)
	await _stand_by(ANVIL)
	await _until(func() -> bool: return interaction.get_target() == anvil, 3.0)
	# Nothing picked here yet: the prompt names the first line of the anvil's list (by what it makes: an axe head).
	var first_here: String = RegentsStationWindow.label_of(skilling.choices_at(SkillingComponent.station_of(anvil))[0])
	_check(hud._prompt.text.contains(first_here), "at the anvil, its first recipe (%s) offered: \"%s\"" % [first_here, hud._prompt.text.replace("\n", " / ")])
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return hud.station_window.is_open(), 2.0)
	_check(hud.station_window.is_open() and hud.station_window.title == "Anvil" and hud.station_window.choices.size() >= 2,
		"a tap of E opens the anvil's window: %d things to make" % hud.station_window.choices.size())
	await _shot("station_anvil")
	# MAKE X (owner, 2026-10-21): one batch asked for, one made, and the work stops by itself.
	hud.station_window.make_x = 1
	_check(await _make("Copper rivets", "MakeXGo"), "rivets picked there, Make X at 1 pressed")
	var bar_seen: Array[float] = [-1.0]
	await _until(func() -> bool:
		if skilling.afk_target >= 0 and hud.work_bar.visible:
			bar_seen[0] = maxf(bar_seen[0], hud.work_bar.value)
		return inv.count(RIVETS) >= 4 and skilling.afk_target == -1, 10.0)
	_check(inv.count(RIVETS) >= 4, "rivets made AFK (%d)" % inv.count(RIVETS))
	_check(bar_seen[0] > 0.2, "while it worked, the work bar filled toward the batch (to %.2f)" % bar_seen[0])
	_check(skilling.afk_target == -1 and inv.count(RIVETS) == 4, "Make X of 1: one batch (4 rivets) and it stopped by itself (%d, bars left %d)" % [inv.count(RIVETS), inv.count(COPPER_BAR)])
	if inv.count(COPPER_BAR) > 0:
		_check(await _make("Copper rivets"), "then MAKE ALL for the rest")
		await _until(func() -> bool: return inv.count(RIVETS) > 4, 6.0)
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
		var outline: PackedInt32Array = shape.model.outline   # this round's (it varies), seen while the pattern is on
		var p: ShapeParams = shape.params as ShapeParams
		while shape != null and shape.state == SkillMinigame.State.PLAYING:
			var t: int = shape.elapsed_ms()
			if shape.model.laid:
				_click(shape, Vector2(10, 10))   # a click lifts the pattern (no strike while it is on)
			elif t >= shape.model.next_ok_ms:
				var over_max: int = -1000
				for i: int in shape.model.heights.size():
					over_max = maxi(over_max, shape.model.heights[i] - outline[i])
				if over_max <= 0:
					await _hold_key(KEY_ENTER, 0.75)   # done: set it down (a hold since Luke's play, 2026-11-09)
				elif shape.model.hot_until_ms - p.red_ms - t < 500 and shape.model.reheats_left() != 0:
					await _key(KEY_R)   # back in the fire (right click is the light tap: MINIGAMES_PREP.md §3.1)
				else:
					var c: int = 0
					for i: int in shape.model.heights.size():
						if shape.model.heights[i] - outline[i] > shape.model.heights[c] - outline[c]:
							c = i
					if shape.model.heights[c] - outline[c] > 0:
						var r: Rect2 = shape.bar_rect()
						# A heavy strike (left click) to rough it out, a light tap (right click) to finish the line.
						var heavy: bool = shape.model.heights[c] - outline[c] >= (shape.params as ShapeParams).hammer_drop
						_click(shape, Vector2(r.position.x + (c + 0.5) * r.size.x / outline.size(), r.position.y + r.size.y * 0.5),
							MOUSE_BUTTON_LEFT if heavy else MOUSE_BUTTON_RIGHT)
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
	_check(await _make("Grip"), "the workbench's window: a handle, MAKE")
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
	_check(await _make("Oak grip"), "the window: the oak handle, MAKE")
	await _until(func() -> bool: return inv.count(OAK_HANDLE) >= 1 and skilling.afk_target == -1, 12.0)
	_check(inv.count(OAK_HANDLE) == 1 and inv.count(OAK_LOGS) == 0, "an oak handle carved from oak logs; out of them, it stops by itself")
	# One line a recipe; the handle is picked in its slot's list, and the traits under it (MATERIALS.md step 3).
	_check(await _pick("Iron axe"), "the window picks the iron axe")
	hud.station_window.pick_part(0, OAK_HANDLE)
	await get_tree().process_frame
	var slot_list: OptionButton = hud.station_window.find_child("Part_0", true, false) as OptionButton
	var steady_box: CheckBox = hud.station_window.find_child("Trait_steady", true, false) as CheckBox
	var steady_state: Label = hud.station_window.find_child("TraitState_steady", true, false) as Label
	_check(slot_list != null and slot_list.get_selected_id() == OAK_HANDLE and steady_box != null and steady_box.button_pressed
		and steady_state != null and steady_state.text.ends_with("(in use)") and hud.station_window.traits_line().begins_with("A "),
		"the oak handle in its slot; Steady ticked and in use; %s" % hud.station_window.traits_line())
	await _shot("station_workbench")
	hud.toggle_bag()
	hud.skills_window.open()
	await _shot("bag_and_skills")
	hud.toggle_bag()
	hud.skills_window.close()
	var said: String = RegentsHud.station_prompt(skilling, SkillingComponent.station_of(bench), inv)
	_check(said.contains("Steady") and said.contains("1 Oak grip (1)"), "it says its trait and takes the oak handle: \"%s\"" % said.replace("\n", " / "))
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
	var steady: TraitDef = ItemDef.by_id(OAK_HANDLE).handle_trait
	# Its traits (owner, 2026-10-23): Steady (the oak's) and Gentle (the copper rivets'), as many as its grade holds.
	var gentle: TraitDef = ItemDef.by_id(RIVETS).handle_trait
	var kept: String = "%d" % steady.id if SkillingComponent.trait_room(head_q) < 2 else "%d,%d" % [steady.id, gentle.id]
	_check(quality == "{\"q\":%d,\"h\":%d,\"p\":[%d,%d],\"t\":[%s]}" % [mini(1000, head_q), OAK_HANDLE, OAK_HANDLE, RIVETS, kept],
		"the iron axe is its head's quality, remembers its parts, and has Steady (the oak's) and Gentle (the rivets') as its grade holds (%s, head %d)" % [quality, head_q])
	# Its card in the bag: the trait, what it gives and what it costs (template DECISIONS #275).
	var axe_row: int = -1
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == IRON_AXE:
			axe_row = s.id
	if hud.station_window.visible:
		hud.station_window.close()
	hud.toggle_bag()
	hud.bag_window.picked_row = axe_row
	hud.bag_window.refresh()
	await get_tree().process_frame
	var trait_line: Label = hud.bag_window.find_child("Trait_steady", true, false) as Label
	_check(trait_line != null and trait_line.is_visible_in_tree(), "the iron axe's card shows its trait, Steady")
	await _shot("bag_traits")
	hud.toggle_bag()
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
	await _tutorial_sword()
	await _herbalism()
	await _skinning()


## SKINNING (Luke's H1; his knife and "the killer first, then anyone", 2026-11-09; SEVERAL HIDES and THE CUT LINE,
## 2026-11-10): the glade's deer slain as this player's kill (the shell's admin, `admin_slay`: the fight is the combat
## suites'); its carcass lies where it fell. HOLD E: the cut line (kind 107), played with the mouse as a person drags it
## (pressed on each line's ring, dragged at the cut's pace, let go when a line is through); the round skins the WHOLE
## carcass, paid in hides by its score (2 or 3 at a full score), and it is taken away. A second deer, TAP E: skinned
## AFK, a hide every 5 s until it is worked out (1 to 4). A hide tanned at the rack into soft leather, AFK.
func _skinning() -> void:
	_check(inv.count(COPPER_KNIFE) == 1, "the starter kit's copper knife is in the bag")
	var carcass: int = await _slain_deer(1)
	if carcass < 0:
		return
	_check(hud._prompt.text.begins_with("E: skin the deer carcass (AFK)") and hud._prompt.text.contains("Hold E: play"),
		"at the carcass the prompt offers AFK skinning and a round (\"%s\")" % hud._prompt.text)
	var hides0: int = inv.count(DEER_HIDE)
	var xp0: int = int(skilling.xp.get(SKILL_SKINNING, 0))
	if await _hold_for_round():
		var skin: SkinMinigame = hud.game as SkinMinigame
		_check(skin != null and skin.get_child(0) is SkinStage, "the carcass's round is the cut line, on its stage")
		while skin != null and skin.state == SkillMinigame.State.PLAYING:
			var m: SkinModel = skin.model
			if skin._wait_release:
				_mouse_button(skin, skin._mouse, false)
			elif not m.down:
				var tip: Vector2i = m.tip()
				var at: Vector2 = skin.hide_to_panel(tip.x, tip.y)
				_mouse_move(skin, at)
				await get_tree().process_frame
				_mouse_button(skin, at, true)
			else:
				_mouse_move(skin, skin.hide_to_panel(m.ahead(float((skin.params as SkinParams).cut_speed)).x,
					m.ahead(float((skin.params as SkinParams).cut_speed)).y))
			await get_tree().process_frame
		if skin != null and skin._held:
			_mouse_button(skin, skin._mouse, false)
		print("   the cut line as played: %s" % str(skin.live_result if skin != null else {}))
		_check(skin != null and int(skin.live_result.get("lines", 0)) >= 3 and int(skin.live_result.get("score_pm", 0)) >= 750
			and skin.live_result == skin.replayed_result,
			"the knife dragged along line after line with the mouse, by the frame, as a person plays it (%s)" % str(skin.live_result if skin != null else {}))
		await _until(func() -> bool: return inv.count(DEER_HIDE) > hides0 and int(skilling.xp.get(SKILL_SKINNING, 0)) > xp0, 5.0)
		var got: int = inv.count(DEER_HIDE) - hides0
		_check(got >= 2 and got <= 4 and int(skilling.xp.get(SKILL_SKINNING, 0)) == xp0 + got * 15,
			"the server replayed it and paid the whole carcass: %d hides (2.9 at a full score), %d skinning XP" % [got, int(skilling.xp.get(SKILL_SKINNING, 0)) - xp0])
		await _round_closed()
	await _until(func() -> bool: return SkillingComponent.node_of(carcass) == null, 10.0)
	_check(SkillingComponent.node_of(carcass) == null, "skinned whole in one round, the carcass is taken away")
	# A second deer, skinned AFK: a hide every 5 s, each the last with 35 %, never past 4.
	var second: int = await _slain_deer(2)
	if second < 0:
		return
	hides0 = inv.count(DEER_HIDE)
	xp0 = int(skilling.xp.get(SKILL_SKINNING, 0))
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_target == second, 4.0)
	_check(skilling.afk_target == second, "tap E at the second: skinning it, AFK")
	await _until(func() -> bool: return SkillingComponent.node_of(second) == null or skilling.afk_target == -1, 30.0)
	var afk_got: int = inv.count(DEER_HIDE) - hides0
	_check(afk_got >= 1 and afk_got <= 4 and int(skilling.xp.get(SKILL_SKINNING, 0)) == xp0 + afk_got * 15,
		"skinned AFK until it was worked out: %d hides (1 to 4), Skinning XP %d" % [afk_got, int(skilling.xp.get(SKILL_SKINNING, 0)) - xp0])
	await _until(func() -> bool: return SkillingComponent.node_of(second) == null, 10.0)
	_check(SkillingComponent.node_of(second) == null and skilling.afk_target == -1, "worked out, the carcass is taken away, the work over")
	var before_tan: int = inv.count(DEER_HIDE)
	var rack: int = await _station_at(RACK)
	await _stand_by(RACK)
	await _until(func() -> bool: return interaction.get_target() == rack, 3.0)
	hud.station_window.make_x = 1
	_check(await _make("Soft leather", "MakeXGo"), "at the tanning rack, soft leather picked, Make X at 1")
	await _until(func() -> bool: return inv.count(SOFT_LEATHER) >= 1 and skilling.afk_target == -1, 12.0)
	_check(inv.count(SOFT_LEATHER) == 1 and inv.count(DEER_HIDE) == before_tan - 1, "a deer hide tanned into soft leather, AFK")
	hud.station_window.close()


## The shell slays the glade's deer as this player's kill (its `n`th: the shell waits for the deer to be back); its
## carcass found, and this player standing at it facing it. The carcass's entity, or -1.
func _slain_deer(n: int) -> int:
	print("SLAY_DEER %d %d" % [me.entity_id, n])
	var carcass: int = -1
	var deadline: int = Time.get_ticks_msec() + 40000
	while carcass < 0 and Time.get_ticks_msec() < deadline:
		for id: int in EntityRegistry.all_entity_ids():
			var node: NodeComponent = SkillingComponent.node_of(id)
			if node != null and node.def != null and node.def.id == DEER_CARCASS and not node.depleted:
				carcass = id
		await get_tree().process_frame
	_check(carcass >= 0, "slain deer %d's carcass lies here, a node to skin (%d)" % [n, carcass])
	if carcass < 0:
		return -1
	var at: Vector3 = (EntityRegistry.get_entity(carcass) as Node3D).global_position
	await _stand_at(at + Vector3(0, 0.05, 2.2), at)
	await _until(func() -> bool: return interaction.get_target() == carcass, 3.0)
	return carcass


## The mouse moved over `game` to `at` (its own coordinates), as the window sends it.
func _mouse_move(game: Control, at: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = game.get_global_transform_with_canvas() * at
	e.global_position = e.position
	Input.parse_input_event(e)


## The left mouse button pressed or let go over `game` at `at`, as the window sends it.
func _mouse_button(game: Control, at: Vector2, down: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = game.get_global_transform_with_canvas() * at
	e.global_position = e.position
	Input.parse_input_event(e)


## HERBALISM, STEP 1 (Luke, 2026-11-07): flax pulled AFK with the starter kit's copper trowel (no round yet: the prompt
## offers none); three spun into a bowstring at the spinning wheel; a carved stave (given by the shell at quality 650:
## carving is the integration suite's) strung at the workbench into the yew bow, which keeps the stave's quality.
func _herbalism() -> void:
	_check(inv.count(COPPER_TROWEL) == 1, "the starter kit's copper trowel is in the bag")
	# PULL THE ROOT (PROGRESS 51; the trowel's work after Luke's play, 2026-11-08): hold E at a patch, and the round as a
	# person plays it, by the frame: A and D dig each stem round, then Space pulls, let go as the stem strains near the
	# top, pull again once it has eased; where the soil cracks, that side's key cuts the side root. One round only: E
	# stops the run after it.
	var prompt_ok: bool = false
	var pulled: bool = false
	for at: Vector3 in FLAX_POINTS:
		var patch: int = await _node_at(at)
		var node: NodeComponent = SkillingComponent.node_of(patch)
		if node == null or node.depleted:
			continue
		await _stand_by(at)
		await _until(func() -> bool: return interaction.get_target() == patch, 3.0)
		prompt_ok = hud._prompt.text.begins_with("E: pull the flax (AFK)") and hud._prompt.text.contains("Hold E: play")
		var flax0: int = inv.count(FLAX)
		var xp0: int = int(skilling.xp.get(SKILL_HERBALISM, 0))
		if not await _hold_for_round():
			break
		var pull: PullMinigame = hud.game as PullMinigame
		_check(pull != null and pull.get_child(0) is PullStage, "the flax's round is pull the root, on its stage")
		await _tap(&"interact", 0.08)
		_check(skilling.run_stop_after, "E at the flax's round: the run stops after it")
		while pull != null and pull.state == SkillMinigame.State.PLAYING:
			var t: int = pull.elapsed_ms()
			pull.model.advance_to(t)
			var m: PullModel = pull.model
			var side: int = 0
			if not m.stroking(t):
				if m.showing() != 0:
					side = m.showing()
				elif m.up_by == 0 and m.pack_left > 0:
					side = PullModel.LEFT
				elif m.up_by == 0 and m.pack_right > 0:
					side = PullModel.RIGHT
			if side != 0:
				var key: InputEventKey = InputEventKey.new()
				key.physical_keycode = KEY_A if side == PullModel.LEFT else KEY_D
				key.pressed = true
				pull._unhandled_key_input(key)
			elif m.up_by > 0 or m.pack_left + m.pack_right == 0:
				pull.button(m.strain < 850 if pull._down else m.strain <= 450)
			await get_tree().process_frame
		print("   the pull as played: %s" % str(pull.live_result if pull != null else {}))
		_check(pull != null and int(pull.live_result.get("whole", 0)) >= 2 and int(pull.live_result.get("cut", 0)) >= 2
			and int(pull.live_result.get("dug", 0)) >= 1 and pull.live_result == pull.replayed_result,
			"a clump's packed sides dug (loose ones left: Luke, 2026-11-09), cut and pulled stem after stem by the frame, as a person plays it: two up whole or more (%s)" % str(pull.live_result if pull != null else {}))
		await _until(func() -> bool: return inv.count(FLAX) > flax0 and int(skilling.xp.get(SKILL_HERBALISM, 0)) > xp0, 5.0)
		_check(inv.count(FLAX) > flax0 and int(skilling.xp.get(SKILL_HERBALISM, 0)) > xp0,
			"the server replayed it and paid %d flax and %d herbalism XP" % [inv.count(FLAX) - flax0, int(skilling.xp.get(SKILL_HERBALISM, 0)) - xp0])
		await _round_closed()
		pulled = true
		break
	_check(prompt_ok and pulled, "at a flax patch the prompt offers AFK work and a round (\"%s\")" % hud._prompt.text)
	# Then AFK (tap E) until there are three for a bowstring.
	for at: Vector3 in FLAX_POINTS:
		if inv.count(FLAX) >= 3:
			break
		var patch: int = await _node_at(at)
		var node: NodeComponent = SkillingComponent.node_of(patch)
		if node == null or node.depleted:
			continue
		await _stand_by(at)
		await _until(func() -> bool: return interaction.get_target() == patch, 3.0)
		await _tap(&"interact", 0.08)
		await _until(func() -> bool: return skilling.afk_target == patch, 4.0)   # the work begun (the press, the server's row)
		await _until(func() -> bool: return inv.count(FLAX) >= 3 or skilling.afk_target == -1, 20.0)
		if skilling.afk_target >= 0:
			await _tap(&"interact", 0.08)
			await _until(func() -> bool: return skilling.afk_target == -1, 3.0)
	_check(inv.count(FLAX) >= 3 and int(skilling.xp.get(SKILL_HERBALISM, 0)) > 0,
		"flax pulled with the trowel: %d flax, herbalism XP %d" % [inv.count(FLAX), int(skilling.xp.get(SKILL_HERBALISM, 0))])
	var wheel: int = await _station_at(WHEEL)
	await _stand_by(WHEEL)
	await _until(func() -> bool: return interaction.get_target() == wheel, 3.0)
	hud.station_window.make_x = 1
	_check(await _make("Bowstring", "MakeXGo"), "at the spinning wheel, a bowstring picked, Make X at 1")
	await _until(func() -> bool: return inv.count(BOWSTRING) >= 1 and skilling.afk_target == -1, 10.0)
	_check(inv.count(BOWSTRING) == 1, "three flax spun into a bowstring, AFK (%d left)" % inv.count(FLAX))
	hud.station_window.close()
	print("GRANT_STAVE %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(STAVE) == 1, 20.0)
	var bows0: int = inv.count(YEW_BOW)
	var bench: int = await _station_at(BENCH)
	await _stand_by(BENCH)
	await _until(func() -> bool: return interaction.get_target() == bench, 3.0)
	hud.station_window.make_x = 1
	_check(await _make("Yew bow", "MakeXGo"), "at the workbench, stringing the yew bow picked")
	await _until(func() -> bool: return inv.count(YEW_BOW) > bows0 and skilling.afk_target == -1, 10.0)
	var q: int = -1
	for st: SpaceTimeInventoryComponent.Stack in inv.items():
		if st.item_def_id == YEW_BOW:
			q = int((JSON.parse_string(st.instance_data) as Dictionary).get("q", -1)) if not st.instance_data.is_empty() else -1
	_check(inv.count(YEW_BOW) == bows0 + 1 and inv.count(STAVE) == 0 and inv.count(BOWSTRING) == 0 and q == 650,
		"the stave and the bowstring strung into a yew bow as good as its stave (quality %d)" % q)
	hud.station_window.close()


## CHAT (DECISIONS #273), beside the buddy at tree_1: Enter, a line (typing W walks nowhere), Enter; it
## comes back to our box; the buddy's answer shows in it and over their head.
func _chat_with_buddy() -> void:
	var chat: ChatBox = _chat_box()
	if DisplayServer.get_name() == "headless":
		# Headless, Boot adds no UI: the chopper gets the box it would have had, as the buddy does.
		if chat == null:
			chat = ChatBox.new()
			get_tree().root.add_child(chat)
	else:
		_check(chat != null, "every game with a window has the chat box")
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


## Pick `text` in the station's window and press `button` (MAKE ALL, AFK until the bag runs out; "Make" is
## Make 1, "MakeXGo" Make X). False when it is not there or cannot be made.
func _make(text: String, button: String = "MakeAll") -> bool:
	if not await _pick(text):
		return false
	var b: Button = hud.station_window.find_child(button, true, false) as Button
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
	_check(tutorial != null and tutorial.state == TutorialComponent.OFFERED and hud.tutorial_card.visible
		and hud.tutorial_card._body.text.contains("training yard"), "the buddy, not begun: offered, the card says where the guide is")
	_check(inv.count(LOGS) > 0 or node.depleted, "two at one tree: the buddy gets logs too (or sees it fall)")


## THE TUTORIAL BEGUN AT THE GUIDE: offered (a new character's), the card says where; E on the guide, their offer;
## E again, taken: the card shows the first lesson.
func _tutorial_begin() -> void:
	_check(tutorial != null, "the adventurer has the tutorial")
	if tutorial == null:
		return
	await _until(func() -> bool: return tutorial.state != TutorialComponent.NONE, 5.0)
	_check(tutorial.state == TutorialComponent.OFFERED and hud.tutorial_card.visible and hud.tutorial_card._keys.text.contains("press E"),
		"a new character is offered the tutorial: the card says the guide is by the yard (state %d)" % tutorial.state)
	await _stand_by(GUIDE)
	# (Looked for as we wait: just stepped here, the guide's entity may still be on its way to us.)
	await _until(func() -> bool: return TutorialComponent.is_guide(interaction.get_target()), 4.0)
	var guide: int = interaction.get_target()
	await _until(func() -> bool: return hud._prompt.text.contains("talk to the drillmaster"), 1.0)   # the HUD's next frame
	var guides: Array[String] = []
	for id: int in EntityRegistry.all_entity_ids():
		if TutorialComponent.is_guide(id):
			guides.append("%d at %s" % [id, str((EntityRegistry.get_entity(id) as Node3D).global_position)])
	_check(TutorialComponent.is_guide(guide) and hud._prompt.text.contains("talk to the drillmaster"),
		"facing the guide, E is to talk to them (\"%s\"; target %d; guides %s; me at %s)" % [hud._prompt.text, guide, str(guides), str(me.global_position)])
	await _tap(&"interact", 0.08)
	await get_tree().process_frame
	_check(hud.tutorial_card.offering() and hud.tutorial_card._body.text == tutorial.greeting and hud.tutorial_card._keys.text.contains("E: show me"),
		"E: the guide offers the lessons in their words (\"%s\")" % hud.tutorial_card._body.text)
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return tutorial.state == TutorialComponent.ON, 4.0)
	await get_tree().process_frame
	_check(tutorial.state == TutorialComponent.ON and hud.tutorial_card._title.text.begins_with("Chop wood") and hud.tutorial_card._title.text.ends_with("1 / 15"),
		"E again: taken; the card shows the first lesson (\"%s\")" % hud.tutorial_card._title.text)


## THE SWORD MADE (the tutorial's chain, finished by hand): the chain's work so far ticked its lessons; the shell's two
## bars become a copper sword blade at the anvil, which with a grip and two rivets is a copper sword at the workbench.
func _tutorial_sword() -> void:
	if tutorial == null or tutorial.state != TutorialComponent.ON:
		return
	var names: Array[String] = []
	for id: int in tutorial.done:
		names.append(LessonDef.by_id(id).display_name)
	_check(names.has("Chop wood") and names.has("Carve a grip") and names.has("Mine copper") and names.has("Smelt copper") and names.has("Smith rivets"),
		"the chain's own work ticked its lessons, seen by the server: %s" % str(names))
	await get_tree().process_frame
	_check(hud.tutorial_card._title.text.begins_with("Smith a blade"), "the card now: \"%s\"" % hud.tutorial_card._title.text)
	print("GRANT_SWORD %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(COPPER_BAR) >= 2 and inv.count(RIVETS) >= 2, 10.0)
	var ticked: Array[String] = []
	tutorial.lesson_ticked.connect(func(l: LessonDef) -> void: ticked.append(l.display_name))
	await _stand_by(ANVIL)
	await _until(func() -> bool: return interaction.get_target() == _station_id(ANVIL), 3.0)
	_check(await _make("Copper sword blade", "Make"), "at the anvil: a copper sword blade, MAKE 1")
	await _until(func() -> bool: return inv.count(BLADE) >= 1, 12.0)
	hud.station_window.close()
	await _until(func() -> bool: return ticked.has("Smith a blade"), 4.0)
	_check(inv.count(BLADE) >= 1 and ticked.has("Smith a blade"), "a blade smithed: its lesson ticked (%s)" % str(ticked))
	await _stand_by(BENCH)
	await _until(func() -> bool: return interaction.get_target() == _station_id(BENCH), 3.0)
	_check(await _make("Copper sword", "Make"), "at the workbench: a copper sword, MAKE 1")
	await _until(func() -> bool: return inv.count(COPPER_SWORD) >= 1, 12.0)
	hud.station_window.close()
	await _until(func() -> bool: return ticked.has("Make your sword"), 4.0)
	await get_tree().process_frame
	_check(inv.count(COPPER_SWORD) == 1 and ticked.has("Make your sword") and hud.tutorial_card._title.text.begins_with("Take it in hand"),
		"a copper sword of your own: its lesson ticked; the card: \"%s\"" % hud.tutorial_card._title.text)


func _station_id(at: Vector3) -> int:
	var st: int = -1
	for id: int in EntityRegistry.all_entity_ids():
		var s: StationComponent = SkillingComponent.station_of(id)
		if s != null and (EntityRegistry.get_entity(id) as Node3D).global_position.distance_to(at) < 0.6:
			st = id
	return st


## THE WORK SPOT (Luke, 2026-11-06, PROGRESS 44): working a node, the player's BODY has turned to face it (the camera
## left where it was: "have the model face them but allow the camera to rotate") and stepped to where the swing meets
## its drawn surface (no more step wanted from here).
var _cam_yaw0: float = 0.0


func _check_work_spot(target: int, what: String) -> void:
	var node: NodeComponent = SkillingComponent.node_of(target)
	var input: LocalInputComponent = me.find_component(LocalInputComponent) as LocalInputComponent
	var mv: SpaceTimeMovementComponent = me.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	var to: Vector3 = (EntityRegistry.get_entity(target) as Node3D).global_position - me.global_position
	var off: float = absf(angle_difference(mv.get_predicted_state().yaw, atan2(-to.x, -to.z)))
	var cam: float = absf(angle_difference(input.get_look_yaw(), _cam_yaw0))
	var need: float = skilling.work_spot_need(node)
	_check(node != null and not skilling.stepping() and absf(need) < 0.12 and off < 0.12 and cam < 0.001 and not input.is_body_yaw_held(),
		"working %s, the body faces it (%.0f degrees off), the camera did not turn (%.1f degrees), at the work spot (%.2f m more wanted)"
		% [what, rad_to_deg(off), rad_to_deg(cam), need])
	# Luke (2026-11-06): no more than a few moments between E and the work ("0.5 maybe less").
	_check(skilling.step_took_s <= 0.6, "the step there took %.2f s (half a second or so at most)" % skilling.step_took_s)
	print("   the step to %s took %.2f s" % [what, skilling.step_took_s])


## Hold E on the target until the server deals its round and the HUD shows it (after the step to the work spot). True
## when it did.
func _hold_for_round() -> bool:
	Input.action_press(&"interact")
	await _until(func() -> bool: return hud._round_box.visible and hud.game != null and hud.game.state == SkillMinigame.State.PLAYING, 8.0)
	Input.action_release(&"interact")
	var ok: bool = hud._round_box.visible and hud.game != null
	_check(ok, "holding E: the server deals a round, and it is on screen (%s)" % (hud.game.get_class() if hud.game != null else "none"))
	if ok:
		# Every round in the big panel in the middle (Luke's play, 2026-11-06), a 3D stage behind it.
		var r: Rect2 = hud._round_box.get_global_rect()
		var view: Vector2 = hud._round_box.get_viewport_rect().size
		var placed: bool = r.size.is_equal_approx(hud.MIDDLE_PANEL) and absf(r.get_center().x - view.x * 0.5) < 1.0
		_check(placed and hud.game.get_child(0) is SubViewportContainer,
			"%s: in the middle panel (%s), its 3D stage behind it" % [hud.game.title(), str(r)])
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


## A key held `seconds`, then let go (the anvil's set down is a hold: a tap only says to hold it).
func _hold_key(code: Key, seconds: float) -> void:
	for down: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		if down:
			await get_tree().create_timer(seconds).timeout
		else:
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
