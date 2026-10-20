extends "res://tests/suite_base.gd"
## The `resources` suite (DECISIONS #270): an entity's pools (mana).
##   - what a pool holds after a while: the server's own cases (server/tests/resource.rs), on the twin
##   - the component: a row is a pool, its level now by the server's clock, a deleted row no pool
## Spending, refusing what cannot be paid, a world move: a genre's integration hook (Regent's Rule's staff).


class FakeResourceRow extends RefCounted:
	var id: int = 1
	var entity_id: int = 7
	var world_id: int = 0
	var resource_id: int
	var stored: float
	var at: int

	func _init(p_resource: int, p_stored: float, p_at: int) -> void:
		resource_id = p_resource
		stored = p_stored
		at = p_at


func run() -> void:
	var cases: Array = [[40.0, 100.0, 0.0, 4.0, 10.0, 5.0, 40.0], [40.0, 100.0, 3.0, 4.0, 10.0, 5.0, 52.0],
		[40.0, 100.0, 5.0, 4.0, 10.0, 5.0, 60.0], [40.0, 100.0, 7.0, 4.0, 10.0, 5.0, 80.0],
		[40.0, 100.0, 60.0, 4.0, 10.0, 5.0, 100.0], [0.0, 100.0, 10.0, 0.0, 0.0, 5.0, 0.0]]
	var all_match: bool = true
	for c: Array in cases:
		var got: float = ResourceDef.level(c[0], c[1], c[2], c[3], c[4], c[5])
		if absf(got - float(c[6])) > 1e-4:
			all_match = false
			print("    %s -> %f" % [str(c), got])
	_check(all_match, "the twin answers the server's cases: 3 s in a fight at 4, then 10 out of one, never past full")
	_check(ResourceDef.level(50.0, 100.0, -3.0, 4.0, 10.0, 5.0) == 50.0, "a clock behind: as it was")
	# The component, against a pool this test makes (no genre content in the template).
	var def := ResourceDef.new()
	def.id = 990001
	def.key = &"test_mana"
	def.max_amount = 100.0
	ResourceDef._by_id[def.id] = def
	var c := ResourceComponent.new()
	_check(not c.has_pool(def.id) and c.level(def.id) == 0.0, "no row: no pool")
	var now: int = ClockSync.server_usec()
	c._on_row_updated(&"resource_state", null, FakeResourceRow.new(def.id, 40.0, now - 7_000_000))
	_check(c.has_pool(def.id) and absf(c.level(def.id) - 80.0) < 0.1, "spent to 40 seven seconds ago: 80 now (%.2f)" % c.level(def.id))
	_check(c.can_pay(def.id, 75.0) and not c.can_pay(def.id, 90.0), "it can pay 75, not 90")
	c._on_row_updated(&"resource_state", FakeResourceRow.new(def.id, 40.0, now), null)
	_check(not c.has_pool(def.id), "its row gone: no pool")
	ResourceDef._by_id.erase(def.id)
	c.free()
