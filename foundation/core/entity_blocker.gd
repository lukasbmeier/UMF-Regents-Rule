class_name EntityBlocker extends StaticBody3D
## A WALL AN ENTITY PUTS UP (DECISIONS #229): a shut gate, a dropped pallet, a door. A box (its
## character's `blocker_size`, at `blocker_offset` from its feet, in its own terms) on the level's
## layer, so it stops bodies as a fence does, and a referee's sweeps and sight lines with it, but only
## while the entity is in one of its character's `blocks_in` statuses (empty: always).
##
## Every client builds one under the entity (`SpaceTimeEntity`), and a referee builds its own where
## the entity stands (`ActionReferee`): the same box from the same numbers. The module never sees it
## (a MODULE world takes a client's position within a speed bound; walls are the client's): a genre
## that shuts one checks nobody is standing in it first.
##
## Aimed at, it stands for its entity: the crosshair on a shut gate targets the gate.

## Its entity (`InteractionComponent` reads it: aimed at, it is that entity).
var entity_id: int = -1
var _defn: EntityDefinition = null
var _on: bool = false


## A blocker for `defn`'s entity `entity_id`, not yet blocking (null: the character puts up none).
static func make(defn: EntityDefinition, p_entity_id: int) -> EntityBlocker:
	if defn == null or not defn.has_blocker():
		return null
	var b := EntityBlocker.new()
	b.name = "Blocker"
	b.entity_id = p_entity_id
	b._defn = defn
	b.set_meta(&"entity_id", p_entity_id)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = defn.blocker_size
	shape.shape = box
	shape.position = defn.blocker_offset
	b.add_child(shape)
	b.collision_layer = 0
	b.collision_mask = 0
	return b


## Block, or not, as its entity's status `status` says.
func follow_status(status: int) -> void:
	set_blocking(_defn != null and _defn.blocks_when(status))


func set_blocking(on: bool) -> void:
	_on = on
	collision_layer = SpaceTimeEntity.WORLD_MASK if on else 0


func is_blocking() -> bool:
	return _on
