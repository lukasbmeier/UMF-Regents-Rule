class_name CombatComponent extends SpaceTimeComponent
## A PLAYER'S COMBAT (owner, 2026-10-19: hybrid action combat; the weapon is the kit). On the local
## player it reads the keys and asks the server; on everyone it holds what they wield (the `wielded` row)
## and their block. It never decides a hit: swings are the foundation's abilities, which the world's
## referee judges along the way the body faces, and the server says what a hit does (`game/regents.rs`).
##
##   LMB tap    the kit's light combo: each tap the next step, inside its `combo_window_ms`
##   LMB hold   its heavy (fires once held `heavy_hold_ms`)
##   RMB hold   block (raised inside `regents.parry_ms` of a hit: a parry)
##   Ctrl       the dodge roll (the `dodge` action; slow-walk moves to Alt): the server's Rolling status
##              bursts you forward, and nothing hits you while it lasts
##   Q E R F    the kit's skills, unlocked at its mastery ranks (1, 3, 6, 9): IN STANCE only, else E
##              works what is in front of you and Q picks at a station as before
##   Tab        the next target in front of you: a ring under it, its health at the top. For reference,
##              not aim: a swing hits what it sweeps.
##   Esc        drops the target
## STANCE: a target picked, or a swing in the last `stance_s`: the body faces where the camera looks.

const TABLE_WIELDED: StringName = &"wielded"
const TABLE_STATE: StringName = &"combat_state"
const ACTION_DODGE: StringName = &"dodge"
const ACTION_SLOW: StringName = &"move_slow"
const FACING: StringName = &"regents_combat"
const SKILL_KEYS: Array[Key] = [KEY_Q, KEY_E, KEY_R, KEY_F]
## The dodge roll (`content/ability/dodge.tres`): everyone's, wielding or not.
const DODGE_ID: int = 40010

## The ability use asked of the server: (ability id, target) -> the predicted id. Tests replace it.
signal swung(ability_id: int)
## The target changed (-1: none).
signal target_changed(target_id: int)
## A key was refused here, and why (the server's refusals come back as revokes).
signal refused(why: String)

## How far Tab looks, and how wide in front (degrees, the whole arc).
@export var target_range_m: float = 25.0
@export var target_arc_deg: float = 120.0
## How long after the last swing the stance holds with no target.
@export var stance_s: float = 5.0

## What this player wields: the item, its kit, its bag row (0 / null / -1: nothing).
var weapon: ItemDef = null
var kit: KitDef = null
var weapon_row: int = -1
## Their block, from the server's row.
var blocking: bool = false
## The local player's target (an entity id), or -1.
var target_id: int = -1
## The light combo as this client swung it: the step last asked for, and when (msec).
var combo_step: int = -1
var combo_ms: int = -100000
var _last_swing_ms: int = -100000
var _lmb_down_ms: int = -1
var _heavy_fired: bool = false
var _rmb: bool = false
var _local_input: LocalInputComponent = null
var _action: SpaceTimeActionComponent = null
var _ring: MeshInstance3D = null


func required_tables() -> Array[StringName]:
	return [TABLE_WIELDED, TABLE_STATE]


func optional_tables() -> Array[StringName]:
	return [TABLE_WIELDED, TABLE_STATE]


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	_local_input = ent.find_component(LocalInputComponent) as LocalInputComponent if ent != null else null
	_action = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent if ent != null else null
	set_process(is_local_authority)
	if is_local_authority:
		bind_keys()
		if _action != null:
			_action.action_revoked.connect(func(_a: int, _p: int, why: String) -> void: refused.emit(why))


## The dodge on Ctrl, slow-walk moved to Alt (owner, 2026-10-19: "Ctrl to roll is fine for now").
static func bind_keys() -> void:
	if not InputMap.has_action(ACTION_DODGE):
		InputMap.add_action(ACTION_DODGE)
		var ctrl: InputEventKey = InputEventKey.new()
		ctrl.physical_keycode = KEY_CTRL
		InputMap.action_add_event(ACTION_DODGE, ctrl)
	if InputMap.has_action(ACTION_SLOW):
		for e: InputEvent in InputMap.action_get_events(ACTION_SLOW):
			var k: InputEventKey = e as InputEventKey
			if k != null and (k.physical_keycode == KEY_CTRL or k.keycode == KEY_CTRL):
				InputMap.action_erase_event(ACTION_SLOW, e)
		var alt: InputEventKey = InputEventKey.new()
		alt.physical_keycode = KEY_ALT
		if not InputMap.action_has_event(ACTION_SLOW, alt):
			InputMap.action_add_event(ACTION_SLOW, alt)


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	match table:
		TABLE_WIELDED:
			weapon = ItemDef.by_id(int(new.get(&"item_id"))) if new != null else null
			kit = KitDef.by_key(StringName(String(new.get(&"kit")))) if new != null else null
			weapon_row = int(new.get(&"item_row")) if new != null else -1
		TABLE_STATE:
			blocking = new != null and bool(new.get(&"blocking"))


## Whether Q E R F are skills now: a weapon wielded, and a target picked or a swing just now.
func in_stance() -> bool:
	if kit == null:
		return false
	return target_id >= 0 or Time.get_ticks_msec() - _last_swing_ms < int(stance_s * 1000.0)


## The light step a tap now swings: the next after the last inside the window, else the first.
func next_light_step(now_ms: int) -> int:
	if kit == null or kit.light.is_empty():
		return -1
	if combo_step >= 0 and combo_step + 1 < kit.light.size() and now_ms - combo_ms <= kit.combo_window_ms:
		return combo_step + 1
	return 0


## Swing ability `a` now, aimed where the camera looks: the predicted id, or -1.
func swing(a: AbilityDef) -> int:
	if a == null or _action == null:
		return -1
	_last_swing_ms = Time.get_ticks_msec()
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var pid: int = _action.request_use(a.id, 0, Vector3(-sin(yaw), 0.0, -cos(yaw)))
	if pid >= 0:
		swung.emit(a.id)
	return pid


## A light tap: the next step of the combo.
func light() -> int:
	var now: int = Time.get_ticks_msec()
	var step: int = next_light_step(now)
	if step < 0:
		return -1
	var pid: int = swing(kit.light[step])
	if pid >= 0:
		combo_step = step
		combo_ms = now
	return pid


## Ctrl: the dodge roll, the way you are moving.
func dodge() -> int:
	if _action == null:
		return -1
	for d: ContentDef in ContentLibrary.items(&"ability"):
		if d.id == DODGE_ID and d is AbilityDef:
			return _action.request_use(DODGE_ID, 0, Vector3.ZERO)
	return -1


func heavy() -> int:
	if kit == null or kit.heavy == null:
		return -1
	combo_step = -1
	return swing(kit.heavy)


## Skill key `slot` (0 Q .. 3 F): its ability when the kit has it and our mastery unlocks it.
func skill(slot: int) -> int:
	if kit == null or slot >= kit.skills.size():
		refused.emit("No skill on that key yet")
		return -1
	var sk: SkillingComponent = (entity as SpaceTimeEntity).find_component(SkillingComponent) as SkillingComponent
	var rank: int = sk.rank_in(kit.skill) if sk != null else 1
	if rank < kit.rank_for(slot):
		refused.emit("%s needs %s rank %d" % [kit.skills[slot].display_name, kit.skill.display_name, kit.rank_for(slot)])
		return -1
	combo_step = -1
	return swing(kit.skills[slot])


## Raise or lower the block (the server's say: its row comes back).
func set_block(on: bool) -> ReducerRequest:
	_rmb = on
	return SpaceTimeSync.call_reducer(&"block", [on], ["bool"])


## Wield bag row `row` (a weapon), or put it away (-1).
func wield(row: int) -> ReducerRequest:
	if row < 0:
		return SpaceTimeSync.call_reducer(&"unwield", [], [])
	return SpaceTimeSync.call_reducer(&"wield", [row], ["u64"])


## Whether the mouse is ours (as the foundation's attack key asks: a game that captures it, captured).
func _mouse_ours() -> bool:
	return _local_input == null or not _local_input.capture_mouse or MouseCapture.is_captured()


func _can_fight() -> bool:
	return kit != null and (_local_input == null or not _local_input.is_held_still()) and _mouse_ours()


func _unhandled_input(event: InputEvent) -> void:
	if not is_local_authority or not is_bound():
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and _can_fight():
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lmb_down_ms = Time.get_ticks_msec()
				_heavy_fired = false
			elif _lmb_down_ms >= 0:
				if not _heavy_fired:
					light()
				_lmb_down_ms = -1
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed != _rmb:
			set_block(mb.pressed)
		return
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.is_action_pressed(ACTION_DODGE) and _mouse_ours() and (_local_input == null or not _local_input.is_held_still()):
		dodge()
		get_viewport().set_input_as_handled()
	elif k.physical_keycode == KEY_TAB:
		next_target()
		get_viewport().set_input_as_handled()
	elif in_stance() and _can_fight():
		var slot: int = SKILL_KEYS.find(k.physical_keycode)
		if slot >= 0:
			skill(slot)
			get_viewport().set_input_as_handled()


## Esc with a target drops the target first (the menu opens on the next), before the menu hears it.
func _input(event: InputEvent) -> void:
	if not is_local_authority or target_id < 0:
		return
	var k: InputEventKey = event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_ESCAPE:
		set_target(-1)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not is_bound():
		return
	if _lmb_down_ms >= 0 and not _heavy_fired and kit != null and Time.get_ticks_msec() - _lmb_down_ms >= kit.heavy_hold_ms:
		_heavy_fired = true
		heavy()
	if _rmb and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and DisplayServer.get_name() != "headless":
		set_block(false)
	if target_id >= 0 and not _target_ok(target_id):
		set_target(-1)
	if _local_input != null:
		_local_input.hold_facing(FACING, in_stance())
	_place_ring()


## Pick `id` as the target (-1: none).
func set_target(id: int) -> void:
	if id == target_id:
		return
	target_id = id
	target_changed.emit(id)


## The candidates Tab steps through: alive, with health, not us, within range in front of the camera,
## nearest the crosshair first.
func targets() -> Array[int]:
	var me: Node3D = entity as Node3D
	var yaw: float = _local_input.get_look_yaw() if _local_input != null else 0.0
	var fwd: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var scored: Array[Vector2] = []
	for id: int in EntityRegistry.all_entity_ids():
		if id == entity_id or not _target_ok(id):
			continue
		var n: Node3D = EntityRegistry.get_entity(id) as Node3D
		var to: Vector3 = n.global_position - me.global_position
		to.y = 0.0
		var d: float = to.length()
		if d > target_range_m or d < 0.01:
			continue
		var ang: float = rad_to_deg(fwd.angle_to(to / d))
		if ang > target_arc_deg * 0.5:
			continue
		scored.append(Vector2(ang + d, float(id)))
	scored.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[int] = []
	for v: Vector2 in scored:
		out.append(int(v.y))
	return out


## Tab: the next target after the one we have (the best first).
func next_target() -> int:
	var list: Array[int] = targets()
	if list.is_empty():
		set_target(-1)
		refused.emit("Nothing to target in front of you")
		return -1
	var at: int = list.find(target_id)
	set_target(list[(at + 1) % list.size()] if at >= 0 else list[0])
	return target_id


## Someone we may target: an entity with health, alive, not a player (no duels yet).
func _target_ok(id: int) -> bool:
	var ent: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
	if ent == null or not is_instance_valid(ent) or ent.find_component(SkillingComponent) != null:
		return false
	var h: SpaceTimeHealthComponent = ent.find_component(SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	return h != null and not h.is_dead()


func _place_ring() -> void:
	if target_id < 0 or not is_local_authority:
		if _ring != null:
			_ring.visible = false
		return
	var t: Node3D = EntityRegistry.get_entity(target_id) as Node3D
	if t == null:
		return
	if _ring == null:
		_ring = MeshInstance3D.new()
		var torus: TorusMesh = TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.68
		torus.rings = 48
		_ring.mesh = torus
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.78, 0.25, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring.material_override = mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.top_level = true
		add_child(_ring)
	_ring.visible = true
	_ring.global_position = t.global_position + Vector3(0, 0.04, 0)
	_ring.scale = Vector3(1.0, 0.15, 1.0)


func _exit_tree() -> void:
	if _local_input != null and is_instance_valid(_local_input):
		_local_input.hold_facing(FACING, false)
