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
##
## A REFEREE'S WALL A GENRE SIZED (template 1.7.2, DECISIONS #304): the referee may build one of several
## boxes for one entity (`of_boxes`), from what its genre says of that entity (`RefereeGenre.walls`), and
## reshape it when that changes (`set_boxes`). Its statuses still come from the character (`blocks_in`);
## with no character known, it blocks in every status. Clients build only the character's box.

## Its entity (`InteractionComponent` reads it: aimed at, it is that entity).
var entity_id: int = -1
var _defn: EntityDefinition = null
var _on: bool = false
var _boxes: Array[AABB] = []


## A blocker for `defn`'s entity `p_entity_id`, not yet blocking (null: the character puts up none).
static func make(defn: EntityDefinition, p_entity_id: int) -> EntityBlocker:
	if defn == null or not defn.has_blocker():
		return null
	var boxes: Array[AABB] = [defn.blocker_box()]
	return of_boxes(p_entity_id, boxes, defn)


## A blocker for entity `p_entity_id` made of `boxes` (each from its feet, in its own terms), not yet
## blocking; the statuses it blocks in are `defn`'s (`blocks_in`; null: every one). Null: no boxes.
static func of_boxes(p_entity_id: int, boxes: Array[AABB], defn: EntityDefinition = null) -> EntityBlocker:
	if boxes.is_empty():
		return null
	var b := EntityBlocker.new()
	b.name = "Blocker"
	b.entity_id = p_entity_id
	b._defn = defn
	b.set_meta(&"entity_id", p_entity_id)
	b.collision_layer = 0
	b.collision_mask = 0
	b.set_boxes(boxes)
	return b


## Its shape, as `boxes` (each from its feet, in its own terms): the shapes it had are replaced.
func set_boxes(boxes: Array[AABB]) -> void:
	if boxes == _boxes:
		return
	_boxes = boxes.duplicate()
	for c: Node in get_children():
		if c is CollisionShape3D:
			remove_child(c)
			c.free()
	for a: AABB in _boxes:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = a.size
		shape.shape = box
		shape.position = a.get_center()
		add_child(shape)


## Its boxes (each from its feet, in its own terms).
func boxes() -> Array[AABB]:
	return _boxes


## Block, or not, as its entity's status `status` says.
func follow_status(status: int) -> void:
	set_blocking(_defn == null or _defn.blocks_in_status(status))


func set_blocking(on: bool) -> void:
	_on = on
	collision_layer = SpaceTimeEntity.WORLD_MASK if on else 0


func is_blocking() -> bool:
	return _on
