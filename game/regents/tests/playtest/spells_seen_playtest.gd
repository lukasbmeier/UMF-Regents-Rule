extends Node
## ANOTHER PLAYER'S SPELL, SEEN (Luke, 2026-11-15: "yes, add it": others see your Gale; PROGRESS 83). Two real clients
## at a simulated round trip in the frontier glade (game/regents/tests/spells_seen_playtest.sh starts them):
##   `--role=caster`   asks the shell for a staff with Gale on its first pick (GRANT_STAFF), picks it, wields it, and
##                     casts Gale once ALONE (GALE_1). When the shell says the watcher is watching (the signal file),
##                     casts it again, then once more straight at the server while it is cooling (refused: nothing
##                     lands). Its own client showed each of its two Gales once (not again from the server's row).
##   `--role=watcher`  comes in after the first Gale: the caster's `spell_landed` row is handed over, seconds old, and
##                     shows NOTHING (history, not a cast). Then sees the second: the gust where the caster stood,
##                     the way they aimed, once, and their ARMS play its release (Luke, 2026-11-15: "yes, add the
##                     pose"); the refused one shows nothing and moves no arm.
## Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 150.0
const STAFF: int = 40023
## Where they stand (the camp, clear of the dummy and the guide): the caster faces south, the watcher 4 m east of it.
const CASTER_AT: Vector3 = Vector3(7.0, 0.05, 28.0)
const WATCHER_AT: Vector3 = Vector3(11.0, 0.05, 28.0)
## South: the look's yaw for +z.
const SOUTH_YAW: float = PI

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "caster"
var _caster_id: int = -1
var _signal_path: String = ""
var me: SpaceTimeEntity
var combat: CombatComponent
var inv: SpaceTimeInventoryComponent
var input: LocalInputComponent
var vfx: AbilityVfx


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
		elif a.begins_with("--caster="):
			_caster_id = int(a.trim_prefix("--caster="))
		elif a.begins_with("--signal="):
			_signal_path = a.trim_prefix("--signal=")
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	me = await _local_entity()
	if me == null:
		_finish()
		return
	combat = me.find_component(CombatComponent) as CombatComponent
	inv = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	input = me.find_component(LocalInputComponent) as LocalInputComponent
	vfx = me.find_component(AbilityVfx) as AbilityVfx
	_check(combat != null and input != null and vfx != null, "%s: the adventurer has its combat and its effects" % _role)
	if combat == null or input == null or vfx == null:
		_finish()
		return
	input.capture_mouse = false
	if _role == "caster":
		await _caster()
	else:
		await _watcher()
	_finish()


func _gale() -> AbilityDef:
	return (ContentLibrary.find(&"spell", 40005) as SpellDef).ability


func _caster() -> void:
	var gale: AbilityDef = _gale()
	await _stand_at(CASTER_AT, SOUTH_YAW)
	print("GRANT_STAFF %d" % me.entity_id)
	await _until(func() -> bool: return inv.count(STAFF) == 1, 20.0)
	var row: int = -1
	for s: SpaceTimeInventoryComponent.Stack in inv.items():
		if s.item_def_id == STAFF:
			row = s.id
	_check(row >= 0, "the shell gave a staff")
	if row < 0:
		return
	# The shell levels it and our Sorcery after it gives it (GRANT_STAFF's reply: STAFF_READY in the signal file).
	await _until(func() -> bool: return _signal().contains("STAFF_READY"), 20.0)
	var picked: ReducerRequest = combat.choose_pick(row, 0, gale)
	await _until(func() -> bool: return picked.outcome != ReducerRequest.Outcome.PENDING, 5.0)
	_check(picked.outcome == ReducerRequest.Outcome.OK, "Gale picked on the staff's first pick (%s)" % picked.error_message)
	combat.wield(row)
	await _until(func() -> bool: return combat.kit != null and combat.kit.casts() and combat.on_slot(1) == gale, 5.0)
	_check(combat.kit != null and combat.kit.casts() and combat.on_slot(1) == gale, "the staff wielded, Gale on its E")
	input.set_look(SOUTH_YAW, 0.0)
	await get_tree().create_timer(0.5).timeout
	# ALONE: the first Gale, before the watcher is here.
	var played_before: int = vfx.played.size()
	combat.cast(gale)
	await get_tree().create_timer(1.0).timeout
	_check(_gales(vfx) == 1 and vfx.played.size() > played_before, "our first Gale: its gust here, as we cast it")
	print("GALE_1")
	# The watcher in, its stale check done (the shell writes WATCHING), and Gale ready again.
	await _until(func() -> bool: return _signal().contains("WATCHING"), 90.0)
	_check(_signal().contains("WATCHING"), "the watcher came in after our first Gale")
	await _until(func() -> bool: return combat.spell_cooldown_sec(gale) <= 0.0, 15.0)
	await get_tree().create_timer(0.5).timeout
	await _stand_at(CASTER_AT, SOUTH_YAW)
	combat.cast(gale)
	print("GALE_2")
	await get_tree().create_timer(0.6).timeout
	# Straight at the server while it is cooling (our own client would not send it): refused, nothing lands.
	var again: ReducerRequest = SpaceTimeSync.call_reducer(&"cast_spell", [gale.id, 0, Vector3(0, 0, 1), Vector3.ZERO],
		["u32", "u64", "vector3[f32,f32,f32]", "vector3[f32,f32,f32]"])
	await _until(func() -> bool: return again.outcome != ReducerRequest.Outcome.PENDING, 5.0)
	_check(again.outcome == ReducerRequest.Outcome.REJECTED and again.error_message.contains("not ready"),
		"NEGATIVE: a third Gale sent while it cools: the server refused it (%s)" % again.error_message)
	print("GALE_REFUSED")
	await get_tree().create_timer(4.0).timeout
	_check(_gales(vfx) == 2, "our own client showed each of our two Gales once, not again from the server's row (%d)" % _gales(vfx))
	await _until(func() -> bool: return _signal().contains("WATCHER_DONE"), 20.0)


func _watcher() -> void:
	await _stand_at(WATCHER_AT, SOUTH_YAW)
	var caster: SpaceTimeEntity = null
	var deadline: int = Time.get_ticks_msec() + 20_000
	while caster == null and Time.get_ticks_msec() < deadline:
		var e: SpaceTimeEntity = EntityRegistry.get_entity(_caster_id) as SpaceTimeEntity
		caster = e if e != null and e.is_bound() else null
		await get_tree().process_frame
	_check(caster != null and not caster.is_local_authority, "the caster (entity %d) is here, another player" % _caster_id)
	if caster == null:
		return
	var theirs: AbilityVfx = caster.find_component(AbilityVfx) as AbilityVfx
	var their_combat: CombatComponent = caster.find_component(CombatComponent) as CombatComponent
	var their_arms: AnimationDriverComponent = caster.find_component(AnimationDriverComponent) as AnimationDriverComponent
	_check(theirs != null and their_combat != null and their_arms != null, "their character has its effects, its combat and its animation")
	if theirs == null or their_combat == null or their_arms == null:
		return
	# Their first Gale's row, handed over as we came in: seconds old, so it shows nothing.
	await _until(func() -> bool: return SpaceTimeSync.get_row(&"spell_landed", _caster_id) != null, 10.0)
	var old: RefCounted = SpaceTimeSync.get_row(&"spell_landed", _caster_id)
	var age_s: float = float(ClockSync.server_usec() - int(old.get(&"at"))) / 1e6 if old != null else -1.0
	_check(old != null and int(old.get(&"ability")) == _gale().id and age_s > float(AbilityVfx.FRESH_MS) / 1000.0,
		"their first Gale's row reached us, %.1f s old" % age_s)
	await get_tree().create_timer(2.0).timeout
	_check(_gales(theirs) == 0 and _gale_nodes().is_empty(), "NEGATIVE: a Gale cast before we came is history: nothing shows (%s)" % str(theirs.played))
	_check(their_combat.remote_landed_ability == -1, "NEGATIVE: and their arms did not play it")
	print("WATCHING")
	# Their second: the gust where they stood, the way they aimed.
	var seen: Node3D = null
	deadline = Time.get_ticks_msec() + 40_000
	while seen == null and Time.get_ticks_msec() < deadline:
		var nodes: Array[Node] = _gale_nodes()
		seen = nodes[0] as Node3D if not nodes.is_empty() else null
		await get_tree().process_frame
	_check(seen != null and _gales(theirs) == 1, "their second Gale showed here (%s)" % str(theirs.played))
	if seen != null:
		var row: RefCounted = SpaceTimeSync.get_row(&"spell_landed", _caster_id)
		var from: Vector3 = row.get(&"from") as Vector3 if row != null else Vector3.INF
		var facing: Vector3 = -seen.global_basis.z
		_check(Vector2(seen.global_position.x - CASTER_AT.x, seen.global_position.z - CASTER_AT.z).length() < 0.6
			and seen.global_position.distance_to(from) < 0.01,
			"at their feet, where the server says they stood (%s; they stood at %s)" % [seen.global_position, from])
		_check(facing.dot(Vector3(0, 0, 1)) > 0.99, "facing the way they aimed: south (%s)" % facing)
	var clip: StringName = their_arms.animation_set.anim_name(StringName("ability.%d" % _gale().id)) if their_arms.animation_set != null else &""
	_check(their_combat.remote_landed_ability == _gale().id and clip != &"" and their_arms.upper_clip() == clip,
		"and their arms played its release, as their own client did (%s; the clip for Gale is %s)" % [their_arms.upper_clip(), clip])
	their_combat.remote_landed_ability = -1
	await _until(func() -> bool: return _signal().contains("GALE_REFUSED"), 15.0)
	await get_tree().create_timer(2.0).timeout
	_check(_gales(theirs) == 1 and their_combat.remote_landed_ability == -1,
		"NEGATIVE: their refused third Gale showed nothing and moved no arm (%d shown)" % _gales(theirs))
	_check(_gales(vfx) == 0, "NEGATIVE: and none played on our own character")
	print("WATCHER_DONE")


func _gales(on: AbilityVfx) -> int:
	return on.played.count("gale:%d" % _gale().id)


func _gale_nodes() -> Array[Node]:
	return get_tree().root.find_children("*", "VfxGale", true, false)


## What the shell has written to the signal file (its replies: STAFF_READY, WATCHING, GALE_REFUSED, WATCHER_DONE).
func _signal() -> String:
	if _signal_path == "" or not FileAccess.file_exists(_signal_path):
		return ""
	return FileAccess.get_file_as_string(_signal_path)


func _stand_at(at: Vector3, yaw: float) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [at], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return me.global_position.distance_to(at) < 0.4, 4.0)
	input.set_look(yaw, 0.0)
	await get_tree().create_timer(0.5).timeout


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
		print("   ok: ", msg)
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: spells-seen playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\nspells seen (%s): %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
