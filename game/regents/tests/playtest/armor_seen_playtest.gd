extends Node
## ANOTHER PLAYER'S ARMOR, SEEN (W2): two real clients at a simulated round trip in the frontier glade
## (game/regents/tests/armor_seen_playtest.sh starts them):
##   `--role=wearer`   asks the shell for three pieces (GRANT_ARMOR: a steel armet, an iron cuirass, soft leather
##                     trousers), wears them through the server (`wear`), sees them on its own body (WORN); when the
##                     watcher has looked (SEEN in the signal file), takes the chest off (`take_off`, CHEST_OFF).
##   `--role=watcher`  comes in after: the wearer's `worn` row comes with the ring, and their body wears the Knight's
##                     helm and chest (the chest's iron finish) and the Ranger's trousers, their hair hidden; ITS OWN
##                     body wears none of it (NEGATIVE). Then sees the chest come off: their Peasant shirt again.
## Exits 0/1.

const OVERALL_TIMEOUT_SEC: float = 150.0
const ARMET: int = 40078
const CUIRASS: int = 40075
const TROUSERS: int = 40083
const WEARER_AT: Vector3 = Vector3(7.0, 0.05, 28.0)
const WATCHER_AT: Vector3 = Vector3(11.0, 0.05, 28.0)

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false
var _role: String = "wearer"
var _wearer_id: int = -1
var _signal_path: String = ""
var me: SpaceTimeEntity
var inv: SpaceTimeInventoryComponent


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
		elif a.begins_with("--wearer="):
			_wearer_id = int(a.trim_prefix("--wearer="))
		elif a.begins_with("--signal="):
			_signal_path = a.trim_prefix("--signal=")
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	me = await _local_entity()
	if me == null:
		_finish()
		return
	inv = me.find_component(SpaceTimeInventoryComponent) as SpaceTimeInventoryComponent
	var look: ArmorLookComponent = me.find_component(ArmorLookComponent) as ArmorLookComponent
	_check(inv != null and look != null and look.figure() != null, "%s: the adventurer has its armor look on a RegentsFigure" % _role)
	if inv == null or look == null or look.figure() == null:
		_finish()
		return
	(me.find_component(LocalInputComponent) as LocalInputComponent).capture_mouse = false
	if _role == "wearer":
		await _wearer(look)
	else:
		await _watcher(look)
	_finish()


func _wearer(look: ArmorLookComponent) -> void:
	await _stand_at(WEARER_AT)
	print("GRANT_ARMOR %d %d %d %d" % [me.entity_id, ARMET, CUIRASS, TROUSERS])
	await _until(func() -> bool: return inv.count(ARMET) == 1 and inv.count(CUIRASS) == 1 and inv.count(TROUSERS) == 1, 20.0)
	for item: int in [ARMET, CUIRASS, TROUSERS]:
		var row: int = -1
		for s: SpaceTimeInventoryComponent.Stack in inv.items():
			if s.item_def_id == item:
				row = s.id
		var req: ReducerRequest = SpaceTimeSync.call_reducer(&"wear", [row], ["u64"])
		await _until(func() -> bool: return req.outcome != ReducerRequest.Outcome.PENDING, 5.0)
		_check(req.outcome == ReducerRequest.Outcome.OK, "wore item %d (row %d) through the server (%s)" % [item, row, req.error_message])
	await _until(func() -> bool: return _wears(look.figure(), "Knight_Body_Armor") and _wears(look.figure(), "Ranger_Legs"), 5.0)
	var f: RegentsFigure = look.figure()
	_check(_wears(f, "Knight_Head_Armet") and _wears(f, "Knight_Body_Armor") and _wears(f, "Ranger_Legs") and not _wears(f, "Hair_"),
		"my own body wears them, as the `worn` row came back: helm, chest, trousers, no hair")
	print("WORN")
	await _until(func() -> bool: return _signal().contains("SEEN"), 90.0)
	var off: ReducerRequest = SpaceTimeSync.call_reducer(&"take_off", ["chest"], ["string"])
	await _until(func() -> bool: return off.outcome != ReducerRequest.Outcome.PENDING, 5.0)
	_check(off.outcome == ReducerRequest.Outcome.OK, "took the chest off (%s)" % off.error_message)
	print("CHEST_OFF")
	await _until(func() -> bool: return _signal().contains("WATCHER_DONE"), 30.0)


func _watcher(look: ArmorLookComponent) -> void:
	await _stand_at(WATCHER_AT)
	var wearer: SpaceTimeEntity = null
	var deadline: int = Time.get_ticks_msec() + 20_000
	while wearer == null and Time.get_ticks_msec() < deadline:
		var e: SpaceTimeEntity = EntityRegistry.get_entity(_wearer_id) as SpaceTimeEntity
		wearer = e if e != null and e.is_bound() else null
		await get_tree().process_frame
	_check(wearer != null and not wearer.is_local_authority, "the wearer (entity %d) is here, another player" % _wearer_id)
	if wearer == null:
		return
	var theirs: ArmorLookComponent = wearer.find_component(ArmorLookComponent) as ArmorLookComponent
	_check(theirs != null and theirs.figure() != null, "their body is a RegentsFigure with its armor look")
	if theirs == null:
		return
	await _until(func() -> bool: return _wears(theirs.figure(), "Knight_Body_Armor"), 10.0)
	var f: RegentsFigure = theirs.figure()
	_check(_wears(f, "Knight_Head_Armet") and _wears(f, "Knight_Body_Armor") and _wears(f, "Ranger_Legs") and not _wears(f, "Hair_"),
		"their armor, seen here: the armet, the cuirass, the leather trousers, their hair hidden")
	var iron: MetalFinish = load("res://game/regents/wardrobe/metals/2_iron.tres") as MetalFinish
	var metal: Variant = _param(f, "Knight", &"metal_color")
	_check(metal is Color and (metal as Color).is_equal_approx(iron.color), "the Knight pieces in the chest's iron finish (%s)" % [metal])
	var mine: RegentsFigure = look.figure()
	_check(not _wears(mine, "Knight_") and not _wears(mine, "Ranger_") and _wears(mine, "Peasant_Body"),
		"NEGATIVE: their row dresses their body only: mine is all Peasant")
	print("SEEN")
	await _until(func() -> bool: return not _wears(theirs.figure(), "Knight_Body_Armor"), 20.0)
	f = theirs.figure()
	_check(not _wears(f, "Knight_Body_Armor") and _wears(f, "Peasant_Body") and _wears(f, "Knight_Head_Armet"),
		"their chest taken off, seen here: their Peasant shirt again, the helm still on")
	print("WATCHER_DONE")


func _wears(f: RegentsFigure, part: String) -> bool:
	if f == null:
		return false
	for p: PackedScene in f.wearing():
		if p != null and p.resource_path.contains(part):
			return true
	return false


func _param(f: Node, outfit: String, param: StringName) -> Variant:
	for m: Node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			if Wardrobe.outfit_of(mi.mesh.surface_get_material(i)) != outfit:
				continue
			var sm: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
			return sm.get_shader_parameter(param) if sm != null else null
	return null


## What the shell has written to the signal file (its replies: SEEN, WATCHER_DONE).
func _signal() -> String:
	if _signal_path == "" or not FileAccess.file_exists(_signal_path):
		return ""
	return FileAccess.get_file_as_string(_signal_path)


func _stand_at(at: Vector3) -> void:
	SpaceTimeSync.call_reducer(&"teleport", [at], ["vector3[f32,f32,f32]"])
	await _until(func() -> bool: return me.global_position.distance_to(at) < 0.4, 4.0)
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
	printerr("  FAIL: armor-seen playtest (%s) exceeded %.0fs" % [_role, OVERALL_TIMEOUT_SEC])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\narmor seen (%s): %d passed, %d failed" % [_role, _passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
