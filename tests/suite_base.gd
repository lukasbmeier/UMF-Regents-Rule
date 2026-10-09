extends Node
## THE TEST SUITES' COMMON GROUND (REVIEW 0.23.1 C2): the counters every suite adds to (static,
## so the runner reads one total), `_check`, and every helper, test double and constant more than
## one suite uses. Each suite in tests/suites/ extends this, and so does each genre's test base
## (`game/<genre>/tests/`); tests/test_runner.gd runs them in order.
## Split mechanically from the one-file runner: a member used by a single suite lives in that
## suite's file; anything shared lives here.


## Runs the suite. Overridden by each one; awaited by the runner.
func run() -> void:
	await get_tree().process_frame


static var _failures: int = 0
static var _passes: int = 0


## GDScript's `%` operator has no `%e` conversion (it raises "unsupported format character"),
## so scientific notation is built by hand. Output matches the Rust harness: `0.000e+00`.
static func _sci(v: float) -> String:
	if v == 0.0:
		return "0.000e+00"
	var exp: int = int(floor(log(absf(v)) / log(10.0)))
	var mantissa: float = v / pow(10.0, float(exp))
	return "%.3f%s%02d" % [mantissa, "e+" if exp >= 0 else "e-", absi(exp)]


# --- helpers -------------------------------------------------------------------

func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


class FakeRow extends RefCounted:
	var entity_id: int
	var current: float
	## health_state also needs these; defaults keep the older RowEvent tests unchanged.
	var max: float = 100.0
	var is_dead: bool = false
	var last_damage_source: int = 0
	func _init(eid: int, cur: float) -> void:
		entity_id = eid
		current = cur

class FakeGlobalRow extends RefCounted:
	var sim_authority: int = 0


## Despawn one entity through the spawner's own teardown path.
func _teardown_entity(spawner: Node, eid: int) -> void:
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()


## Mirrors fishing's `catch` table.
class FakeCatchRow extends RefCounted:
	var id: int
	var owner_entity_id: int
	var session_id: int
	var catch_key: String
	var kg: float
	var quality: float = 0.75
	var hookset: int = 1
	var spot: String = "dock_end"
	var deadlift: bool = false
	var coins: int = 5
	var round: int
	var caught_at: int = 0
	var best_combo: int = 3
	var fight_s: float = 11.5
	var clean: bool = true
	func _init(cid: int, owner: int, sess: int, rnd: int, key: String, weight: float) -> void:
		id = cid
		owner_entity_id = owner
		session_id = sess
		round = rnd
		catch_key = key
		kg = weight


# --- SpaceTimeComponent base (Phase 3 Task 2) ----------------------------------------

## Stand-in for SpaceTimeEntity. It is a CharacterBody3D and exposes `body` the same way the
## real one does, so components that write a transform are exercised for real rather than
## silently erroring on a missing property.
class FakeOwnerEntity extends CharacterBody3D:
	var entity_id: int = 99
	var is_local_authority: bool = true
	var body: CharacterBody3D:
		get:
			return self

## Snap a JSON-parsed number to f32.
##
## Godot's JSON parser does not round-trip f64 exactly: the golden file's half_width for
## mid_bar_easy is the f32 0.24500000476837158, and the parser hands back
## 0.24500000476837161 — one f64 ULP out. The vectors ARE f32 values, so reading them as f32
## is the correct interpretation, not a tolerance fudge; Rust's serde does the same implicitly
## by deserialising straight into f32. Without this the comparison drifts by ~1e-17 and the
## max_err = 0 rule reports a parity failure that does not exist.
static func _f32(v: float) -> float:
	return Vector3(v, 0.0, 0.0).x


# --- SpaceTimeEntity (Phase 3 Task 3) --------------------------------------------------

const PLAYER_SCENE: String = "res://foundation/entities/player.tscn"

## Autoloads cannot be named at compile time from this script: `-s` compiles it before the
## autoloads are added to the tree, which is a hard "Identifier not found" rather than a
## runtime nil. The suites run deferred, so by here they exist and can be fetched by path.
func _autoload(n: String) -> Node:
	return get_tree().root.get_node_or_null(NodePath("/root/" + n))

## A complete, valid initial row set for player.tscn. Every test that spawns or binds that
## scene goes through here: as the scene gains components (Movement in Task 6, Input in Task 7)
## the required tables grow, and without a single source of truth each spawn test breaks
## separately with a different confusing error.
class FakeMemberRow extends RefCounted:
	var id: int = 1
	var session_id: int
	var entity_id: int
	var score: int = 0
	var coins: int = 0
	func _init(eid: int, sid: int) -> void:
		entity_id = eid
		session_id = sid

class FakeSessionRow extends RefCounted:
	var id: int
	var world_id: int = 0
	var kind: int = 0
	var phase: int = 0
	var phase_ends_at: int = 0
	var seed: int = 12345
	var max_members: int = 0
	var round: int = 1
	func _init(sid: int, p: int, ends: int) -> void:
		id = sid
		phase = p
		phase_ends_at = ends

func _player_rows(eid: int) -> Array:
	return [
		RowEvent.make(RowEvent.Kind.INSERTED, &"health_state", null,
			FakeHealthRow.new(eid, 100.0, 100.0)),
		RowEvent.make(RowEvent.Kind.INSERTED, &"movement_state", null,
			FakeMoveRow.new(eid, Vector3.ZERO, 0)),
		RowEvent.make(RowEvent.Kind.INSERTED, &"session_member", null,
			FakeMemberRow.new(eid, 1)),
		RowEvent.make(RowEvent.Kind.INSERTED, &"inventory_item", null,
			FakeItemRow.new(900 + eid, eid, 1, 1)),
	]

## Same set, pushed through the registry so the spawner picks it up as buffered initial state.
func _buffer_player_rows(reg: Node, eid: int) -> void:
	for ev: RowEvent in _player_rows(eid):
		reg._on_row_event(ev)


# --- EntitySpawner (Phase 3 Task 4) ----------------------------------------------------

## `entity` row stand-in: the spawner reads kind/world_id/owner off the row by name.
class FakeEntityRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var kind: int = 0
	var owner: PackedByteArray = PackedByteArray()
	func _init(eid: int, k: int = 0) -> void:
		entity_id = eid
		kind = k


# --- SpaceTimeHealthComponent (Phase 3 Task 5) -----------------------------------------

## Mirrors `health_state`. Values are read off by name, as the SDK's generated rows are.
class FakeHealthRow extends RefCounted:
	var entity_id: int
	var current: float
	var max: float
	var is_dead: bool
	var last_damage_source: int
	var last_change_server_tick: int = 0
	func _init(eid: int, cur: float, mx: float, dead: bool = false, src: int = 0) -> void:
		entity_id = eid
		current = cur
		max = mx
		is_dead = dead
		last_damage_source = src


class FakeMoveRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var pos: Vector3
	var vel: Vector3
	var yaw: float = 0.0
	var grounded: bool = true
	var move_state: int = 0
	var last_processed_seq: int = 0
	var server_tick: int = 0
	var server_ts: int = 0
	var teleport_flag: bool = false
	var correction_epoch: int = 0
	func _init(eid: int, p: Vector3, ts: int) -> void:
		entity_id = eid
		pos = p
		vel = Vector3.ZERO
		server_ts = ts

static func _move_ev(row: FakeMoveRow) -> RowEvent:
	return RowEvent.make(RowEvent.Kind.UPDATED, &"movement_state", null, row)


# --- LocalInputComponent (Phase 3 Task 7) ----------------------------------------------

func _make_input_component(is_local: bool) -> LocalInputComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = 88
	owner_entity.is_local_authority = is_local
	# The camera rig is what "forward" is relative to.
	var rig := Node3D.new()
	rig.name = "CameraRig"
	owner_entity.add_child(rig)
	get_tree().root.add_child(owner_entity)

	var c := LocalInputComponent.new()
	c.send_to_server = false
	get_tree().root.add_child(c)
	var empty: Dictionary[StringName, RefCounted] = {}
	c.bind(owner_entity, empty)
	return c

func _release_all_actions() -> void:
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right",
			&"jump", &"sprint"]:
		if InputMap.has_action(a):
			Input.action_release(a)


# --- Greybox scene integration (real level, real frames) --------------------------------
#
# Everything above this line is a unit test: objects wired by hand, `update_view()` called
# directly. This suite is the other kind — it loads the actual level, spawns the actual
# player.tscn through the actual EntitySpawner, and lets real physics frames elapse. It is
# what catches wiring that unit tests cannot see: a component that never gets processed, a
# body parented into nothing, a scene that will not instantiate at all.
#
# It is also the testbed the collision work will need. Phase 3 entities are passive — remote
# interpolation writes a transform directly, so walls are not exercised yet. Once Phase 4
# prediction or Task 13's sidecar drives a body with move_and_slide, this level already has
# the floor, walls and platform to run it into.

const GREYBOX_SCENE: String = "res://tests/levels/greybox.tscn"


## Advance BOTH clocks. The camera rig places itself in `_process`, and a headless run can take
## several physics steps inside a single idle frame — awaiting `physics_frame` alone left the
## rig unplaced and this suite reading a camera still sitting at the player's origin.
func _tick_frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame
		await get_tree().process_frame


# --- animation: the set, the generated tree, and a real rig ------------------------------

## THE FOUNDATION'S CHARACTER: a humanoid with every look and the plain humanoid set
## (`game/characters/`, `game/anim/`), what a game with no genre plays as.
const CHARACTER_DEF: String = "res://game/characters/character_definition.tres"
const HUMANOID_SET: String = "res://game/anim/humanoid.tres"



## Resolve a clip by its mixer-qualified name (`Idle`, `extra/Walk_Fwd`).
func _clip_in(set: AnimationSet, full: StringName) -> Animation:
	var s: String = String(full)
	var slash: int = s.find("/")
	var lib: AnimationLibrary = set.libraries.get(
		StringName(s.substr(0, slash)) if slash >= 0 else &"", null)
	var name: StringName = StringName(s.substr(slash + 1) if slash >= 0 else s)
	return lib.get_animation(name) if lib != null and lib.has_animation(name) else null


## Every model the game dresses a player in: the foundation's character's looks. A genre's suites
## override this with its own (fishing's adds the rival's).
func _shipped_looks() -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	var defn: EntityDefinition = load(CHARACTER_DEF) as EntityDefinition
	if defn != null:
		out.append_array(defn.visual_variants)
	return out


func _grip_entry(anim: StringName, pos: Vector3, rot: Vector3, steady: bool) -> GripEntry:
	var e := GripEntry.new()
	e.animation = anim
	e.position = pos
	e.rotation_degrees = rot
	e.steady = steady
	return e


func _bone_y(skel: Skeleton3D, bone: String) -> float:
	var i: int = skel.find_bone(bone)
	return skel.get_bone_global_pose(i).origin.y if i >= 0 else NAN


func _walk_nodes(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c: Node in n.get_children():
		out.append_array(_walk_nodes(c))
	return out


func _teardown_anim(reg: Node, spawner: Node, eid: int, prev_local: int, prev_ready: bool,
		level: Node3D) -> void:
	spawner._on_entity_deleted(RowEvent.make(
		RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()
	await get_tree().process_frame






## THE LOBBY (DECISIONS #174): the rules say whether a kind has one (ready-up, players, teams); a
## member's ready and team come from its row; the panel shows only in a lobby, lists who is here,
## and its keys ask the server (offline here: the refusal is said, not swallowed).
class FakeLobbyRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var session_id: int = 1
	var ready: bool
	var team: int
	func _init(eid: int, r: bool, t: int) -> void:
		entity_id = eid
		ready = r
		team = t



## Move a LOCAL_PREDICTED entity the way the server would: a teleport row under a new epoch,
## applied on the next tick. Lets a scene test put the body somewhere without reaching into
## private state.
func _place_predicted(m: SpaceTimeMovementComponent, pos: Vector3, seq_ref: Array[int],
		settle_frames: int = 20) -> void:
	var r := FakeMoveRow.new(m.entity_id, pos, 9_000_000 + seq_ref[0])
	r.last_processed_seq = seq_ref[0]
	r.correction_epoch = m.get_epoch() + 1
	r.teleport_flag = true
	r.grounded = false
	m.receive_row_event(_move_ev(r))
	await get_tree().physics_frame   # the row is applied at the top of this tick
	for i: int in range(settle_frames):
		await get_tree().physics_frame
		var f := InputFrame.new()
		seq_ref[0] += 1
		f.seq = seq_ref[0]
		m.push_input(f)



# --- LOCAL_PREDICTED reconciliation (PHASE4_SPEC §1, DECISIONS #71/#72) -----------------

## A predicted movement component whose fake body is NOT in the tree, so the collision resolver
## falls back to the pure model and every expected position is exact.
func _make_predicted(eid: int = 55) -> SpaceTimeMovementComponent:
	var owner_entity := FakeOwnerEntity.new()
	owner_entity.entity_id = eid
	var m := SpaceTimeMovementComponent.new()
	m.config = MovementConfig.new()
	m.mode = SpaceTimeMovementComponent.Mode.LOCAL_PREDICTED
	get_tree().root.add_child(m)
	var initial: Dictionary[StringName, RefCounted] = {
		&"movement_state": FakeMoveRow.new(eid, Vector3.ZERO, 1_000)}
	m.bind(owner_entity, initial)
	return m


# --- SpaceTimeInventoryComponent (Phase 3 Task 9) ---------------------------------------

## Mirrors `inventory_item`. NOTE the column is `owner_entity_id`, not `entity_id` — that is
## precisely what RowEvent's fallback exists for.
class FakeItemRow extends RefCounted:
	var id: int
	var owner_entity_id: int
	var item_def_id: int
	var qty: int
	var slot: int = -1
	var instance_data: String = ""
	func _init(p_id: int, owner: int, def_id: int, p_qty: int, p_slot: int = -1) -> void:
		id = p_id
		owner_entity_id = owner
		item_def_id = def_id
		qty = p_qty
		slot = p_slot

static func _item_ev(kind: RowEvent.Kind, old: FakeItemRow, new: FakeItemRow) -> RowEvent:
	return RowEvent.make(kind, &"inventory_item", old, new)
