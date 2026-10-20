extends "res://tests/suite_base.gd"
## The `ground_items` suite (DECISIONS #269): what lies on the ground, shown, and walked over.
##   - a `ground_item` row is a sack where it lies, its ring in its grade's colour, its name above
##   - a row that changes (anyone's now) keeps its one sack; a row gone takes it away
##   - walking within reach asks the server for it once, not again at once, and never from afar
## The server's side (the owner's window, anyone's, gone; who may pick up, from how far; drop_item; a
## kill's loot on the ground): tests/integration_test.sh and server/tests/ground.rs.


class FakeGroundRow extends RefCounted:
	var id: int
	var world_id: int = 0
	var item_def_id: int
	var qty: int
	var instance_data: String = ""
	var pos: Vector3
	var owner_id: int = 0
	var anyone: bool = false

	func _init(p_id: int, p_item: int, p_qty: int, p_pos: Vector3) -> void:
		id = p_id
		item_def_id = p_item
		qty = p_qty
		pos = p_pos


func run() -> void:
	var view := GroundItems.new()
	view.auto_pickup = false
	add_child(view)
	var was_name: Callable = GroundItems.name_of
	var was_grade: Callable = GroundItems.grade_of
	GroundItems.name_of = func(item: int, _qty: int, _data: String) -> String: return "Gem" if item == 7 else "Ore"
	GroundItems.grade_of = func(item: int, _data: String) -> int: return 2 if item == 7 else -1
	var gem := FakeGroundRow.new(1, 7, 1, Vector3(1, 0, 2))
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, &"ground_item", null, gem))
	var sack: Node3D = view.sack(1)
	_check(view.count() == 1 and sack != null and sack.position.is_equal_approx(Vector3(1, 0, 2)), "a row is a sack where it lies")
	var ring: MeshInstance3D = sack.get_node(^"Glow") as MeshInstance3D if sack != null else null
	var label: Label3D = sack.get_node(^"Name") as Label3D if sack != null else null
	_check(ring != null and (ring.material_override as StandardMaterial3D).albedo_color.is_equal_approx(UiStyle.current().grade_colors[2])
		and label != null and label.text == "Gem", "its ring in its grade's colour (the game's grade 2), its name above it (the game's)")
	var ore := FakeGroundRow.new(2, 8, 3, Vector3(20, 0, 0))
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, &"ground_item", null, ore))
	var ore_label: Label3D = view.sack(2).get_node(^"Name") as Label3D
	_check(ore_label.text == "Ore x3" and ore_label.modulate.is_equal_approx(UiStyle.current().text), "a stack of three, ungraded: the text colour")
	var anyones := FakeGroundRow.new(1, 7, 1, Vector3(1, 0, 2))
	anyones.anyone = true
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.UPDATED, &"ground_item", gem, anyones))
	_check(view.count() == 2 and view.sack(1) == sack, "anyone's now: the same one sack")
	# Walking over it.
	var asked: Array[int] = view.pick_up_near(Vector3(1.5, 0, 2))
	_check(asked == [1], "within reach: asks the server for the gem, not the ore 19 m off (%s)" % str(asked))
	_check(view.pick_up_near(Vector3(1.5, 0, 2)).is_empty(), "and not again at once (a slow answer, a refusal)")
	_check(view.pick_up_near(Vector3(10, 0, 0)).is_empty(), "nothing from between them")
	# Gone.
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.DELETED, &"ground_item", gem, null))
	_check(view.count() == 1 and view.sack(1) == null, "a row gone (picked up, its time up): its sack goes")
	GroundItems.name_of = was_name
	GroundItems.grade_of = was_grade
	view.queue_free()
	await get_tree().process_frame
