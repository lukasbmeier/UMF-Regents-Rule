class_name AbilityVfx extends SpaceTimeComponent
## THE ABILITIES' EFFECTS ON A FIGHTER (Luke, 2026-11-14: "lets use the vfx in all the current abilites"; PROGRESS
## 81), on every player and foe, from the table `ability_vfx.tres` (`AbilityVfxSet`):
##   - A CHARGE in the hand(s) while a spell is cast (this client's own cast; another player's, while their `casting`
##     row says so; a foe's, through its wind-up: the imp's tell), a little in front of the palm, never in the wrist.
##   - AS IT LANDS, at the caster's feet facing the way it was aimed (Gale's gust): this client's own as it is cast;
##     another player's from the server's word that it landed (`spell_landed`, Luke 2026-11-15), while that is fresh.
##   - A JUMP (Blink): the caster seen to move 3 to 12 m in one frame, wielding a kit that casts: the columns at
##     both ends, the body faded in where it lands. Every client sees it (the jump is in the movement rows). This
##     client's own character only after it cast one (`JUMP_ARMED_MS`): a teleport of its own is no blink.
##   - A PARRY (this client's own): the flash at the blocking hand, out toward the attacker.
## What the game already draws is not here: the swings' cut (`SwingTrail`), missiles (their bodies' looks), the
## rings (`SpellLooks`). Presentation only (hard rule 11): it reads what happened and shows it; a referee draws none.

## A jump this long in one frame is a Blink (shorter: walking; longer: a respawn or a long teleport).
const JUMP_MIN_M: float = 3.0
const JUMP_MAX_M: float = 12.0
## This client's own jump shows a Blink only this long after it cast one (the server's move arrives a round trip later).
const JUMP_ARMED_MS: int = 2000
## The server's word that a spell landed (one row a caster, rewritten as each lands).
const TABLE_LANDED: StringName = &"spell_landed"
## A landed spell's row older than this as it arrives is history (handed over as this client came near), not a cast.
const FRESH_MS: int = 1500

## Every effect played here, newest last (tests read it): its scene's file name and the ability's id.
var played: Array[String] = []
var vfx_set: AbilityVfxSet = null
## The charge showing (a `VfxEffect`, kept as a Variant: checked before each use), its ability (-1: none), its row.
var charge: Variant = null
var charge_id: int = -1
var _entry: AbilityVfxEntry = null
var _combat: CombatComponent = null
var _action: SpaceTimeActionComponent = null
var _skel: Skeleton3D = null
## A foe's tell: which ability, until when (msec).
var _tell_id: int = -1
var _tell_until_ms: int = -1
var _last_pos: Vector3 = Vector3.INF
## Until when this client's own jump is a Blink (msec; -1: not armed).
var _jump_armed_until_ms: int = -1


func required_tables() -> Array[StringName]:
	return [TABLE_LANDED]


func optional_tables() -> Array[StringName]:
	return [TABLE_LANDED]


func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void:
	if table != TABLE_LANDED or new == null:
		return
	var at_usec: int = int(new.get(&"at"))
	if old != null and int(old.get(&"at")) == at_usec:
		return   # the same landing, its row moved
	landed_elsewhere(int(new.get(&"ability")), new.get(&"from") as Vector3, new.get(&"aim") as Vector3, at_usec)


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null or SpaceTimeMovementComponent.is_authority_process():
		set_process(false)   # a referee draws nothing
		return
	vfx_set = AbilityVfxSet.current()
	_combat = ent.find_component(CombatComponent) as CombatComponent
	_action = ent.find_component(SpaceTimeActionComponent) as SpaceTimeActionComponent
	if _action != null:
		_action.started_elsewhere.connect(began)
		_action.action_started.connect(func(id: int, _pid: int) -> void: began(id))
	if _combat != null:
		_combat.cast_sent.connect(func(id: int, _target: int, aim: Vector3, _at: Vector3) -> void: cast_landing(id, aim))
		_combat.parried.connect(parried)
	if is_local_authority and get_viewport() != null:
		VfxCameraShake.install(get_viewport().get_camera_3d(), ent)   # this client's camera feels the shakes near it
	set_process(true)


## Ability `id` began (a foe's, through the action stream): its tell's charge, for its wind-up.
func began(id: int) -> void:
	var e: AbilityVfxEntry = vfx_set.entry(id) if vfx_set != null else null
	if e == null or e.charge == null or e.ability.wind_up_ms <= 0:
		return
	_tell_id = id
	_tell_until_ms = Time.get_ticks_msec() + e.ability.wind_up_ms


## This client cast `id` aimed along `aim`: one with no cast time lands now (Gale's gust at the feet).
func cast_landing(id: int, aim: Vector3) -> void:
	var e: AbilityVfxEntry = vfx_set.entry(id) if vfx_set != null else null
	var spell: SpellDef = SpellDef.by_ability(id)
	if e != null and e.on_jump != null:
		_jump_armed_until_ms = Time.get_ticks_msec() + JUMP_ARMED_MS
	_land(e, spell, id, (entity as Node3D).global_position, aim)


## ANOTHER PLAYER'S spell `id` landed (the server's `spell_landed` row, stamped `at_usec`), cast from `from` aimed along
## `aim`: shown as their own client showed it, unless it is ours (shown as we cast it) or no longer fresh. Whether it
## was shown.
func landed_elsewhere(id: int, from: Vector3, aim: Vector3, at_usec: int) -> bool:
	if is_local_authority or vfx_set == null or not is_fresh(at_usec):
		return false
	return _land(vfx_set.entry(id), SpellDef.by_ability(id), id, from, aim) != null


## Whether a `spell_landed` row stamped `at_usec` is a landing to show now (not history handed over as we came near).
## The one test for every reader of the row (the effect here, the arms in `CombatComponent`).
static func is_fresh(at_usec: int) -> bool:
	return ClockSync.server_usec() - at_usec <= FRESH_MS * 1000


## A spell with no cast time landing: its `on_land` at `at`, facing along `aim` (level). Null when it shows none.
func _land(e: AbilityVfxEntry, spell: SpellDef, id: int, at: Vector3, aim: Vector3) -> VfxEffect:
	if e == null or e.on_land == null or (spell != null and spell.cast_ms > 0):
		return null
	var flat: Vector3 = Vector3(aim.x, 0.0, aim.z)
	if flat.length() < 0.01:
		flat = _forward()
	return play(e.on_land, id, at, at + flat.normalized())


## This client's parry turned `attacker_id`'s blow: the flash at the hand nearer the attacker, out toward them.
func parried(attacker_id: int) -> void:
	if vfx_set == null or vfx_set.parry == null:
		return
	var me: Node3D = entity as Node3D
	var foe: Node3D = EntityRegistry.get_entity(attacker_id) as Node3D
	var toward: Vector3 = foe.global_position + Vector3(0, 1.2, 0) if foe != null and is_instance_valid(foe) else me.global_position + _forward() * 2.0 + Vector3(0, 1.2, 0)
	var hand: Vector3 = _bone(&"hand_l")
	var other: Vector3 = _bone(&"hand_r")
	if hand == Vector3.INF or (other != Vector3.INF and other.distance_to(toward) < hand.distance_to(toward)):
		hand = other
	if hand == Vector3.INF:
		hand = me.global_position + Vector3(0, 1.2, 0)
	play(vfx_set.parry, -1, hand + (toward - hand).normalized() * 0.15, toward)


func _process(_delta: float) -> void:
	if vfx_set == null or not is_bound():
		return
	var now: int = Time.get_ticks_msec()
	var id: int = casting_now(now)
	if id != charge_id:
		_drop_charge()
		charge_id = id
		_entry = vfx_set.entry(id) if id >= 0 else null
		if _entry != null and _entry.charge != null:
			var fx: VfxEffect = play(_entry.charge, id, cast_point(_entry), Vector3.INF, Vector3.ZERO, null, false)
			if fx != null:
				fx.duration_s = maxf(_cast_left_s(id, now), 0.1)
				fx.free_when_done = false
				charge = fx
	if is_instance_valid(charge) and _entry != null:
		(charge as Node3D).global_position = cast_point(_entry)
	_watch_jump()


## Which ability this fighter is casting now (-1: none): this client's own cast, another player's `casting` row, a
## foe's tell.
func casting_now(now: int) -> int:
	if _combat != null:
		if _combat.is_local_authority:
			if _combat.casting():
				return _combat.cast_spell.ability.id
		elif _combat.remote_cast_ability >= 0:
			return _combat.remote_cast_ability
	return _tell_id if now < _tell_until_ms else -1


func _cast_left_s(id: int, now: int) -> float:
	if _combat != null and _combat.is_local_authority and _combat.casting():
		return float(_combat.cast_until_ms - now) / 1000.0
	if now < _tell_until_ms:
		return float(_tell_until_ms - now) / 1000.0
	var spell: SpellDef = SpellDef.by_ability(id)
	return float(spell.cast_ms) * HotRules.number(&"regents.cast_time_pct") / 100000.0 if spell != null else 0.6


func _drop_charge() -> void:
	if is_instance_valid(charge):
		(charge as Node).queue_free()
	charge = null


## A BLINK SEEN: a jump of JUMP_MIN_M..JUMP_MAX_M in one frame by a fighter wielding a kit that casts.
func _watch_jump() -> void:
	var me: Node3D = entity as Node3D
	var here: Vector3 = me.global_position
	var was: Vector3 = _last_pos
	_last_pos = here
	if was == Vector3.INF or _combat == null or _combat.kit == null or not _combat.kit.casts():
		return
	if _combat.is_local_authority and Time.get_ticks_msec() > _jump_armed_until_ms:
		return   # our own character moved by something else (a teleport, a respawn nearby)
	var d: float = Vector2(here.x - was.x, here.z - was.z).length()
	if d < JUMP_MIN_M or d > JUMP_MAX_M:
		return
	for e: AbilityVfxEntry in vfx_set.entries:
		if e != null and e.on_jump != null:
			var fx: VfxEffect = play(e.on_jump, e.ability.id if e.ability != null else -1, was, here, here, _visual(), true, func(f: VfxEffect) -> void:
				var blink: VfxBlink = f as VfxBlink
				if blink != null:
					blink.moves_caster = false   # the server moved it already
					blink.gone_at_s = 0.0   # it is already gone from here: it fades in where it landed
					blink.back_at_s = minf(blink.back_at_s, 0.12))
			if fx != null:
				_jump_armed_until_ms = -1
				return


## (Here, not on `VfxEffect`: naming CombatComponent there makes a load cycle through SpellLooks' ring scenes.)
## Whether an effect shown for `who` (the fighter it belongs to) is the lighter version: another PLAYER's, seen by
## this client. Not this client's own, not a foe's or a creature's (a foe's warning must read at a glance), not one
## with no fighter (the lab, the showcase).
static func lighter_for(who: Node) -> bool:
	var ent: SpaceTimeEntity = who as SpaceTimeEntity if is_instance_valid(who) else null
	if ent == null or ent.is_local_authority or ent.definition == null:
		return false
	return FoeDef.by_kind(ent.definition.kind) == null and ent.find_component(CombatComponent) != null


## Whether a shot's end (`ShotLook` under a missile's body) is the lighter version: its body's owner's
## (`BodyComponent.owner_id`) as `lighter_for` says.
static func lighter_for_shot(look: Node) -> bool:
	var n: Node = look
	while n != null and not (n is SpaceTimeEntity):
		n = n.get_parent()
	var body: BodyComponent = (n as SpaceTimeEntity).find_component(BodyComponent) as BodyComponent if n != null else null
	return body != null and body.owner_id != 0 and lighter_for(EntityRegistry.get_entity(body.owner_id))


## Play `scene` at `at`, facing `toward` (a point), aimed at `target`, showing on `caster`: placed and set up before it
## enters the world (where it starts), beside the fighter so it outlives them. Null when it is no effect.
func play(scene: PackedScene, ability_id: int, at: Vector3, toward: Vector3 = Vector3.INF, target: Vector3 = Vector3.ZERO,
		caster: Node3D = null, frees: bool = true, prep: Callable = Callable()) -> VfxEffect:
	var fx: VfxEffect = scene.instantiate() as VfxEffect
	if fx == null:
		return null
	fx.target = target
	fx.caster = caster
	fx.free_when_done = frees
	fx.lighter = lighter_for(entity)   # another player's: the lighter version
	fx.position = at
	if toward != Vector3.INF:
		var flat: Vector3 = Vector3(toward.x - at.x, 0.0, toward.z - at.z)
		if flat.length() > 0.01:
			fx.basis = Basis.looking_at(flat, Vector3.UP)
	if prep.is_valid():
		prep.call(fx)
	var me: Node = entity as Node
	var world: Node = me.get_parent() if me != null and me.get_parent() != null else get_tree().root
	world.add_child(fx)
	played.append("%s:%d" % [scene.resource_path.get_file().get_basename(), ability_id])
	return fx


## Where a cast's charge sits: in front of the hand (or between both), toward where the fighter faces.
func cast_point(e: AbilityVfxEntry) -> Vector3:
	var me: Node3D = entity as Node3D
	var hands: Array[Vector3] = []
	for b: StringName in ([&"hand_l", &"hand_r"] if e.two_hands else [e.hand_bone]):
		var p: Vector3 = _bone(b)
		if p != Vector3.INF:
			hands.append(p)
	if hands.is_empty():
		return me.global_position + Vector3(0, 1.3, 0) + _forward() * 0.4
	var at: Vector3 = Vector3.ZERO
	for p: Vector3 in hands:
		at += p
	at /= float(hands.size())
	return at + _forward() * e.ahead_m


## The way the fighter faces (level): its look's forward.
func _forward() -> Vector3:
	var v: Node3D = _visual()
	var f: Vector3 = -(v.global_basis.z if v != null else (entity as Node3D).global_basis.z)
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func _visual() -> Node3D:
	var me: Node3D = entity as Node3D
	return me.get_node_or_null(^"Visual") as Node3D if me != null else null


## Where bone `name` is now (world), or Vector3.INF.
func _bone(bone_name: StringName) -> Vector3:
	if _skel == null or not is_instance_valid(_skel):
		_skel = SkillingLook.skeleton_of(entity)
	if _skel == null or not _skel.is_inside_tree():
		return Vector3.INF
	var i: int = _skel.find_bone(String(bone_name))
	return _skel.global_transform * _skel.get_bone_global_pose(i).origin if i >= 0 else Vector3.INF
