class_name ArmorLookComponent extends SpaceTimeComponent
## WORN ARMOR, SEEN (W2; Luke's W1-W4): a player's `worn` row (one a wearer: `head_item`, `chest_item`, `legs_item`,
## `trinket_item`, 0 for nothing; a cell table, so others' rows come with the ring) put on their body, a
## `RegentsFigure`: each item's pieces and its material's palette from the table `armor_looks.tres` (`ArmorLooks`),
## through `RegentsFigure.wear_armor`. A slot with nothing worn shows the player's own Peasant piece in their colors
## (W4); the row gone takes it all off. Every client does it for every player it sees, so everyone sees everyone's.
## Presentation only (hard rule 11): it shows the row and decides nothing. A referee draws nothing.

const TABLE_WORN: StringName = &"worn"
## The slots, as the server names them (`take_off`), and each one's columns on the row.
const SLOTS: Array[StringName] = [&"head", &"chest", &"legs", &"trinket"]

## The worn row changed (the bag's doll draws from it): low frequency, this entity's own.
signal worn_changed()

## The items worn now, in the row's order (head, legs, chest, trinket), copied out of the row (rule 6).
var items: Array[int] = [0, 0, 0, 0]
## The bag row worn in each slot (`SLOTS` order), copied out of the row: 0 for nothing.
var rows: Dictionary[StringName, int] = {&"head": 0, &"chest": 0, &"legs": 0, &"trinket": 0}
## The body dressed last (kept as a Variant: checked before each use); a new model is dressed again.
var _figure: Variant = null


func required_tables() -> Array[StringName]:
	return [TABLE_WORN]


func optional_tables() -> Array[StringName]:
	return [TABLE_WORN]   # most players wear nothing: no row is no armor


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE_WORN:
		return
	var now: Array[int] = [0, 0, 0, 0]
	var now_rows: Dictionary[StringName, int] = {&"head": 0, &"chest": 0, &"legs": 0, &"trinket": 0}
	if new != null:
		for i: int in ArmorLooks.SLOT_COLUMNS.size():
			now[i] = int(new.get(ArmorLooks.SLOT_COLUMNS[i]))
		for slot: StringName in SLOTS:
			var r: Variant = new.get(StringName("%s_row" % slot))
			now_rows[slot] = int(r) if r != null else 0
	var rows_changed: bool = now_rows != rows
	rows = now_rows
	if now == items:
		if rows_changed:
			worn_changed.emit()
		return
	items = now
	if is_bound():
		dress()
	worn_changed.emit()


func _on_bound() -> void:
	if SpaceTimeMovementComponent.is_authority_process():
		set_process(false)
		return
	dress()


## A new model (a look chosen again) is dressed as it comes.
func _process(_delta: float) -> void:
	if not is_instance_valid(_figure) and is_bound() and figure() != null:
		dress()


## WEAR bag row `row` (this client's own player; the bag's doll): the server checks and answers; what is worn shows
## when the `worn` row comes back, never from this call.
func wear(row: int) -> ReducerRequest:
	return SpaceTimeSync.call_reducer(&"wear", [row], ["u64"])


## TAKE OFF what is worn in `slot` (head, chest, legs, trinket).
func take_off(slot: StringName) -> ReducerRequest:
	return SpaceTimeSync.call_reducer(&"take_off", [String(slot)], ["string"])


## The bag row worn in `slot` (0: nothing).
func row_in(slot: StringName) -> int:
	return int(rows.get(slot, 0))


## Put `items` on the body now. Whether there was a body to dress.
func dress() -> bool:
	var f: RegentsFigure = figure()
	if f == null:
		return false
	var looks: ArmorLooks = ArmorLooks.current()
	if looks == null:
		return false
	var got: Array = looks.dress_for(items, f.body)
	var pieces: Dictionary[StringName, PackedScene] = got[0]
	var palettes: Dictionary[String, DyePalette] = got[1]
	f.wear_armor(pieces, palettes)
	_figure = f
	return true


## The player's body (its `Visual/Model`), or null when it is not a `RegentsFigure`.
func figure() -> RegentsFigure:
	var me: Node = entity as Node
	return me.get_node_or_null(^"Visual/Model") as RegentsFigure if me != null else null
