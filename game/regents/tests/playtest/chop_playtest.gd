extends Node
## WOODCUTTING, PLAYED (game/regents/tests/chop_playtest.sh starts two of these): a real client through
## the latency simulator, in the frontier glade, through the real keys.
##   `--role=chopper`  E tapped by tree_1: AFK, logs come; moving away stops it; E held: a round is dealt
##                     and played with A and D (the player held still), and the server pays what was played
##   `--role=buddy`    chops the same tree AFK beside them, and gets logs too (or sees it fall)
## Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 90.0
const TREE_1: Vector3 = Vector3(-9.0, 0.0, -6.0)
const LOGS: int = 40002
const AXE: int = 40001

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "chopper"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	var me: SpaceTimeEntity = await _local_entity()
	if me == null:
		_finish()
		return
	var skilling: SkillingComponent = me.find_component(SkillingComponent) as SkillingComponent
	var inv: SpaceTimeInventoryComponent = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	var hud: RegentsHud = get_tree().current_scene.find_child("HUD", true, false) as RegentsHud
	_check(skilling != null and inv != null and hud != null, "the adventurer has skilling and a bag, and the genre's HUD is up")
	if skilling == null or inv == null or hud == null:
		_finish()
		return
	await _until(func() -> bool: return inv.count(AXE) == 1, 5.0)
	_check(inv.count(AXE) == 1, "a Bronze axe in the bag")
	var tree_id: int = await _tree_at(TREE_1)
	_check(tree_id > 0, "tree_1 is an entity, drawn as a Tree")
	if tree_id <= 0:
		_finish()
		return
	if _role == "buddy":
		await _buddy(me, skilling, inv, tree_id)
	else:
		await _chopper(me, skilling, inv, hud, tree_id)
	_finish()


func _chopper(me: SpaceTimeEntity, skilling: SkillingComponent, inv: SpaceTimeInventoryComponent, hud: RegentsHud, tree_id: int) -> void:
	var interaction: InteractionComponent = me.find_component(InteractionComponent) as InteractionComponent
	await _stand_at(me, TREE_1 + Vector3(0, 0.05, 1.6))
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	_check(interaction.get_target() == tree_id, "facing it, the tree is the target (got %d)" % interaction.get_target())
	_check(hud._prompt.text.contains("Hold E"), "the prompt says tap or hold: \"%s\"" % hud._prompt.text)

	# TAP E: AFK.
	await _tap(&"interact", 0.08)
	await _until(func() -> bool: return skilling.afk_tree == tree_id, 3.0)
	_check(skilling.afk_tree == tree_id, "a tap of E: chopping it AFK (the server's afk_chop row)")
	_check(hud._prompt.text.begins_with("Chopping"), "the prompt says so: \"%s\"" % hud._prompt.text)
	var logs0: int = inv.count(LOGS)
	var tree: TreeNodeComponent = SkillingComponent.tree_of(tree_id)
	# The buddy chops this tree too, and any log may fell it (1 in 4 for a Tree): if it falls before ours
	# comes, that is the game; chop the next standing tree, three tries.
	for attempt: int in 3:
		await _until(func() -> bool: return inv.count(LOGS) > logs0 or tree.felled, 7.0)
		print("   AFK, tree %d: %d -> %d logs%s" % [attempt + 1, logs0, inv.count(LOGS), " (it fell)" if tree.felled else ""])
		if inv.count(LOGS) > logs0:
			break
		tree_id = await _standing_tree()
		if tree_id <= 0:
			break
		tree = SkillingComponent.tree_of(tree_id)
		await _stand_at(me, (EntityRegistry.get_entity(tree_id) as Node3D).global_position + Vector3(0, 0.05, 1.6))
		await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
		await _tap(&"interact", 0.08)
	_check(inv.count(LOGS) > logs0, "a log comes AFK (a log every 4 s)")
	_check(hud._notices.get_child_count() > 0, "and the HUD says so (\"+1 Logs\")")
	if not tree.felled:
		await _stand_at(me, (EntityRegistry.get_entity(tree_id) as Node3D).global_position + Vector3(0, 0.05, 4.0))
		await _until(func() -> bool: return skilling.afk_tree == -1, 2.0)
		_check(skilling.afk_tree == -1, "walking away stops AFK chopping")

	# HOLD E: a round, on a tree that stands.
	tree_id = await _standing_tree()
	_check(tree_id > 0, "a tree that stands to play a round on")
	if tree_id <= 0:
		return
	var at: Vector3 = (EntityRegistry.get_entity(tree_id) as Node3D).global_position
	await _stand_at(me, at + Vector3(0, 0.05, 1.6))
	await _until(func() -> bool: return interaction.get_target() == tree_id, 3.0)
	var logs1: int = inv.count(LOGS)
	Input.action_press(&"interact")
	await _until(func() -> bool: return hud._round_box.visible, 4.0)
	Input.action_release(&"interact")
	_check(hud._round_box.visible and hud.game.state == ChopMinigame.State.PLAYING, "holding E: the server deals a round, and it is on screen")
	if hud.game.state != ChopMinigame.State.PLAYING:
		return
	var stood: Vector3 = me.global_position
	# Play it through the keys: a press every swing, from the side the next branch is not on.
	var m: ChopModel = hud.game.model
	while hud.game.state == ChopMinigame.State.PLAYING:
		var side: int = ChopModel.SIDE_RIGHT if m.head_branch() == ChopModel.BRANCH_LEFT else (ChopModel.SIDE_LEFT if m.head_branch() == ChopModel.BRANCH_RIGHT else m.side)
		await _key(KEY_A if side == ChopModel.SIDE_LEFT else KEY_D)
		await get_tree().create_timer(0.33).timeout
	var live: Dictionary = hud.game.live_result
	print("   the round as played: %s" % str(live))
	_check(int(live.get("hits", -1)) == 0 and int(live.get("clean", 0)) >= 20, "played well through A and D: no hits, 20 logs' worth of chops or more")
	_check(me.global_position.distance_to(stood) < 0.2, "A and D chopped and did not walk (%.2f m)" % me.global_position.distance_to(stood))
	await _until(func() -> bool: return inv.count(LOGS) > logs1, 5.0)
	print("   the server paid %d logs for it" % (inv.count(LOGS) - logs1))
	_check(inv.count(LOGS) - logs1 >= 1, "the server replayed the round and paid logs for it")
	await _until(func() -> bool: return not hud._round_box.visible, 4.0)
	_check(not hud._round_box.visible and not MouseCapture.is_held_free(), "the round closes and the game comes back")


func _buddy(me: SpaceTimeEntity, skilling: SkillingComponent, inv: SpaceTimeInventoryComponent, tree_id: int) -> void:
	await _stand_at(me, TREE_1 + Vector3(1.6, 0.05, 0.0))
	skilling.chop(tree_id, false)
	await _until(func() -> bool: return skilling.afk_tree == tree_id, 3.0)
	_check(skilling.afk_tree == tree_id, "the buddy chops the same tree AFK")
	var tree: TreeNodeComponent = SkillingComponent.tree_of(tree_id)
	await _until(func() -> bool: return inv.count(LOGS) > 0 or tree.felled, 9.0)
	print("   buddy: %d logs, the tree %s" % [inv.count(LOGS), "fell" if tree.felled else "stands"])
	_check(inv.count(LOGS) > 0 or tree.felled, "two at one tree: the buddy gets logs too (or sees it fall)")


## The standing tree nearest the spawn (the Trees first), or -1.
func _standing_tree() -> int:
	var best: int = -1
	var best_d: float = INF
	for id: int in EntityRegistry.all_entity_ids():
		var t: TreeNodeComponent = SkillingComponent.tree_of(id)
		if t == null or t.felled or t.def == null or t.def.tier != 1:
			continue
		var d: float = (EntityRegistry.get_entity(id) as Node3D).global_position.distance_to(Vector3(0, 0, 8))
		if d < best_d:
			best_d = d
			best = id
	return best


func _tree_at(at: Vector3) -> int:
	var found: int = -1
	var deadline: int = Time.get_ticks_msec() + 8000
	while found < 0 and Time.get_ticks_msec() < deadline:
		for id: int in EntityRegistry.all_entity_ids():
			var t: TreeNodeComponent = SkillingComponent.tree_of(id)
			if t != null and t.def != null and (EntityRegistry.get_entity(id) as Node3D).global_position.distance_to(at) < 0.5:
				found = id
		await get_tree().process_frame
	return found


func _stand_at(me: SpaceTimeEntity, at: Vector3) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [at], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return me.global_position.distance_to(at) < 0.4, 4.0)
	# Face the tree: north, as every stand here is south of its tree.
	(me.find_component(LocalInputComponent) as LocalInputComponent).set_look(0.0, 0.0)
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
	printerr("  FAIL: chop playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\nchop (%s): %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
