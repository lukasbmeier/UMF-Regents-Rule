class_name SpellLooks extends Node3D
## WHAT SPELLS LOOK LIKE IN THE WORLD (owner, 2026-10-20: the Staff): every client draws, from the server's
## rows, an area spell's circle on the ground (`spell_area`) and its landing. (What burns: its
## `HitFeedbackComponent`. Missiles: bodies, their own looks.) Presentation only: the server decides what lands.
## The HUD adds one.
##
## THE RING IS THE VFX LAB'S (Luke, 2026-11-14: "lets use the vfx in all the current abilites"; PROGRESS 82): a
## `VfxGroundRing`, the staff's Frost Ring in frost (`frost_ring.tscn`), a foe's ring in fire (`cinder_ring.tscn`,
## the imp's: what to get out of, never the cool blue of a player's own), its warning filling for exactly the time
## the server gives until it lands (`lands`), then landing. Change their look in those two scenes. A spell with a
## ring of its own names it in the effects table (`AbilityVfxEntry.ring`: Meteor's `meteor_ring.tscn`, in fire).

const TABLE_AREA: StringName = &"spell_area"
const FROST_RING: PackedScene = preload("res://game/regents/vfx/effects/frost_ring.tscn")
const CINDER_RING: PackedScene = preload("res://game/regents/vfx/effects/cinder_ring.tscn")
## The shortest warning drawn (a row seen as it lands, or late) and the longest.
const MIN_WARN_S: float = 0.05
const MAX_WARN_S: float = 4.0

## area id -> {"node": VfxGroundRing, "seen_usec": int, "lands_usec": int, "landed_msec": int, "hostile": bool}
var _areas: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	name = "SpellLooks"
	EntityRegistry.global_row_event.connect(_on_global)


func _exit_tree() -> void:
	if EntityRegistry.global_row_event.is_connected(_on_global):
		EntityRegistry.global_row_event.disconnect(_on_global)


func _on_global(ev: RowEvent) -> void:
	if ev.table != TABLE_AREA:
		return
	if ev.kind == RowEvent.Kind.DELETED:
		forget_area(int(ev.old.get(&"id")) if ev.old != null else -1)
		return
	var row: RefCounted = ev.current()
	var owner_ent: SpaceTimeEntity = EntityRegistry.get_entity(int(row.get(&"owner"))) as SpaceTimeEntity
	var hostile: bool = owner_ent != null and is_instance_valid(owner_ent) and owner_ent.definition != null and FoeDef.by_kind(owner_ent.definition.kind) != null
	show_area(int(row.get(&"id")), row.get(&"pos") as Vector3, float(row.get(&"radius")), int(row.get(&"lands")), bool(row.get(&"landed")), hostile, owner_ent, int(row.get(&"ability")))


## A circle at `pos`, `radius` wide, landing at `lands_usec` (the server's clock); `landed` once it has.
func show_area(id: int, pos: Vector3, radius: float, lands_usec: int, landed: bool, hostile: bool = false, owner_ent: Node = null, ability_id: int = -1) -> void:
	var a: Dictionary = _areas.get(id, {})
	if a.is_empty():
		var ring: VfxGroundRing = ring_scene(ability_id, hostile).instantiate() as VfxGroundRing
		ring.name = "Area_%d" % id
		ring.radius_m = radius
		var left_s: float = float(lands_usec - ClockSync.server_usec()) / 1_000_000.0
		ring.warn_s = clampf(left_s, MIN_WARN_S, MAX_WARN_S) if not landed else MIN_WARN_S
		ring.free_when_done = false   # its row says when it goes (`forget_area`)
		ring.lighter = AbilityVfx.lighter_for(owner_ent)   # another player's ring: the lighter version
		ring.position = pos + Vector3(0, 0.02, 0)
		add_child(ring)
		a = {"node": ring, "seen_usec": ClockSync.server_usec(), "lands_usec": lands_usec, "landed_msec": -1, "hostile": hostile}
		_areas[id] = a
	if landed and int(a["landed_msec"]) < 0:
		a["landed_msec"] = Time.get_ticks_msec()


## THE RING drawn for an area of ability `ability_id`: its row's in the effects table (`AbilityVfxEntry.ring`:
## Meteor's in fire), else a foe's in fire (the cinder ring) and a player's in frost.
static func ring_scene(ability_id: int, hostile: bool) -> PackedScene:
	var e: AbilityVfxEntry = AbilityVfxSet.current().entry(ability_id) if ability_id >= 0 else null
	if e != null and e.ring != null:
		return e.ring
	return CINDER_RING if hostile else FROST_RING


## Its row is gone: a ring still landing plays on and frees itself; one done (or never seen) goes now.
func forget_area(id: int) -> void:
	var a: Dictionary = _areas.get(id, {})
	if not a.is_empty():
		var v: Variant = a["node"]
		if is_instance_valid(v):
			var ring: VfxGroundRing = v as VfxGroundRing
			if ring.playing:
				ring.free_when_done = true
			else:
				ring.queue_free()
	_areas.erase(id)


## The ring drawn for area `id` (null: none).
func ring_of(id: int) -> VfxGroundRing:
	var v: Variant = _areas.get(id, {}).get("node")
	return v as VfxGroundRing if is_instance_valid(v) else null


## How far circle `id` has filled, 0..1 (1 when it lands).
func area_fill(id: int) -> float:
	var a: Dictionary = _areas.get(id, {})
	if a.is_empty():
		return 0.0
	var span: float = float(maxi(int(a["lands_usec"]) - int(a["seen_usec"]), 1))
	return clampf(1.0 - float(int(a["lands_usec"]) - ClockSync.server_usec()) / span, 0.0, 1.0)
