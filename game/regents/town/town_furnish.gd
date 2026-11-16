class_name TownFurnish extends RefCounted
## FURNISHING A PLACE (2026-11-15; Luke: "once i okay the test Ill want to see how eveything furnishes"): the Fantasy
## Props kit's stalls, barrels, crates, banners, lanterns and yard gear set out in a market, at house doors, round a
## village green, in a castle yard. Each set is a `PropGroup` (one building to its `Settlement`: dressed in its style,
## merged, one body), so a place's cloth, wood and metal take its colors.
##
## Every placement is from a `RandomNumberGenerator` the caller seeds: the same seed, the same market.

const STALLS: PackedStringArray = ["Stall_Vegetables_Full", "Stall_Potions", "Stall_Blacksmith", "Stall_Cart_Empty",
	"Stall_Empty"]
## What stands about a stall or a door.
const CLUTTER: PackedStringArray = ["Barrel", "Barrel_Apples", "Crate_Wooden", "FarmCrate_Apple", "FarmCrate_Carrot",
	"FarmCrate_Leek", "Bag", "Bag_2", "Bucket_Wooden_1"]
const SIGNS: PackedStringArray = ["Sign_Food", "Sign_Potions", "Sign_Blacksmith", "Sign_Armory", "Sign_Pub"]


## At a house's door: a lantern beside it (share `lantern`), now and then a sign over it (`sign`), a barrel, crates or a
## bench by it (`clutter`). A group under the house: merged with it.
static func door(h: KitHouse, rng: RandomNumberGenerator, lantern: float, sign: float, clutter: float) -> PropGroup:
	var g := PropGroup.new()
	g.name = "AtTheDoor"
	var d: Vector3 = h.door_point()
	var side: float = -1.0 if rng.randf() < 0.5 else 1.0
	if rng.randf() < lantern:
		g.put("Lantern_Wall", d + Vector3(side * 0.95, 1.55, 0.05))
	if rng.randf() < sign:
		# A hanging sign sticks out of the wall (its +x turned to the front).
		g.put(SIGNS[rng.randi_range(0, SIGNS.size() - 1)], d + Vector3(-side * 1.0, 2.7, 0.05), -PI * 0.5)
	if rng.randf() < clutter:
		var spot: Vector3 = d + Vector3(-side * 1.7, 0.0, 0.55)
		if rng.randf() < 0.3:
			g.put("Bench", d + Vector3(side * 2.4, 0.0, 0.45))
		else:
			g.put(CLUTTER[rng.randi_range(0, CLUTTER.size() - 1)], spot, rng.randf_range(-0.6, 0.6))
			if rng.randf() < 0.5:
				g.put("Barrel", spot + Vector3(-side * 0.8, 0, 0.1), rng.randf() * TAU)
	h.add_child(g)
	return g


## A market in the rectangle `half` (x, z) round `center`: two rows of stalls facing each other across it (z = +-row),
## and with `back_row`, two more behind them (z = +-back_row) facing out, back to back; the middle lane (|x| < `lane`)
## left open, goods by each stall, benches and a table at the ends, bunting over it. No stall in `avoid` (the market's
## own x, z: a building standing in the square).
static func market(parent: Node3D, center: Vector3, half: Vector2, row: float, lane: float, rng: RandomNumberGenerator,
		back_row: float = 0.0, avoid: Array[Rect2] = []) -> PropGroup:
	var g := PropGroup.new()
	g.name = "Market"
	g.position = center
	var k: int = rng.randi_range(0, STALLS.size() - 1)
	var lines: Array[Vector2] = [Vector2(-row, 1.0), Vector2(row, -1.0)]
	if back_row > 0.0:
		lines.append_array([Vector2(-back_row, -1.0), Vector2(back_row, 1.0)])
	for line: Vector2 in lines:
		var x: float = -half.x + 3.0
		# A stall's counter faces its +z; `line.y` says which way this row faces (+1 toward +z).
		var facing: float = line.y
		while x < half.x - 2.0:
			if absf(x) < lane + 1.5:
				x += 3.6
				continue
			var at := Vector3(x + rng.randf_range(-0.3, 0.3), 0, line.x)
			var footprint := Rect2(at.x - 2.4, at.z - 1.8, 3.6, 3.6)
			var clear: bool = true
			for r: Rect2 in avoid:
				clear = clear and not r.intersects(footprint)
			if not clear:
				x += 3.6
				continue
			g.put(STALLS[k % STALLS.size()], at, 0.0 if facing > 0.0 else PI)
			k += 1
			# Goods beside it, behind the counter.
			var side: float = -facing
			var behind: float = side * 1.4
			for j: int in rng.randi_range(1, 3):
				g.put(CLUTTER[rng.randi_range(0, CLUTTER.size() - 1)],
					at + Vector3(rng.randf_range(-1.6, 0.6), 0, behind + rng.randf_range(-0.2, 0.4) * side), rng.randf() * TAU)
			x += rng.randf_range(3.8, 4.8)
	# At the ends: a long table and its benches, barrels by it.
	for end: float in [-1.0, 1.0]:
		var t := Vector3(end * (half.x - 4.0), 0, 0)
		g.put("Table_Large", t, PI * 0.5)
		g.put("Bench", t + Vector3(-0.9, 0, 0), PI * 0.5)
		g.put("Bench", t + Vector3(0.9, 0, 0), PI * 0.5)
		g.put("Barrel", t + Vector3(0, 0, 2.2), 0.3)
		g.put("Barrel", t + Vector3(0.6, 0, 2.6), 1.1)
	# Bunting over the square, high enough to walk under.
	for z: float in [-row * 0.5, row * 0.5]:
		g.put("Banner_SmallTriangles_Long", Vector3(0, 3.4, z), 0.0, minf(1.0, (half.x - 1.0) / 13.84))
	parent.add_child(g)
	return g


## Torches either side of a gate: `at` the middle of the wall's outer face at the gate, `out` the way it faces.
static func gate_torches(g: PropGroup, at: Vector3, along: Vector3, out: Vector3, half_width: float, height: float) -> void:
	var yaw: float = atan2(out.x, out.z)
	for side: float in [-1.0, 1.0]:
		g.put("Torch_Metal", at + along * side * (half_width + 0.9) + Vector3.UP * height + out * 0.05, yaw, 1.6)


## A village green's middle: a campfire with its cauldron, benches round it, a cart, crates of produce.
static func green(parent: Node3D, center: Vector3, rng: RandomNumberGenerator) -> PropGroup:
	var g := PropGroup.new()
	g.name = "Green"
	g.position = center
	g.put("FirePit", Vector3.ZERO)
	g.put("CampfireTripod", Vector3(-0.2, 0, 0))
	g.put("Cauldron", Vector3(0.0, 0, 0.0), 0.0, 0.7)
	for i: int in 4:
		var a: float = TAU * i / 4.0 + 0.4
		g.put("Bench", Vector3(cos(a), 0, sin(a)) * 3.2, -a + PI * 0.5)
	g.put("Stall_Cart_Empty", Vector3(7.5, 0, -3.0), 0.6)
	for i: int in 4:
		g.put(CLUTTER[rng.randi_range(0, 5)], Vector3(8.5 + rng.randf_range(-1, 1), 0, -1.0 + i * 0.8), rng.randf() * TAU)
	parent.add_child(g)
	return g


## Outside an inn: tables and benches, barrels, its sign.
static func inn_front(parent: Node3D, front: Vector3, rng: RandomNumberGenerator) -> PropGroup:
	var g := PropGroup.new()
	g.name = "InnFront"
	g.position = front
	for x: float in [-3.5, 3.5]:
		var t := Vector3(x, 0, 3.0)
		g.put("Table_Large", t)
		g.put("Bench", t + Vector3(0, 0, -0.95))
		g.put("Bench", t + Vector3(0, 0, 0.95))
		g.put("Mug", t + Vector3(rng.randf_range(-0.8, 0.8), 0.81, rng.randf_range(-0.2, 0.2)))
	g.put("Barrel_Holder", Vector3(6.5, 0, 0.8))
	g.put("Barrel", Vector3(-6.5, 0, 0.9), 0.4)
	g.put("Barrel", Vector3(-7.3, 0, 1.4), 1.2)
	g.put("Sign_Pub", Vector3(1.6, 3.0, 0.05), -PI * 0.5)
	g.put("Lantern_Wall", Vector3(-1.6, 1.6, 0.05))
	parent.add_child(g)
	return g


## A castle yard: a training yard (dummies, weapon stands), a smithy corner, a stable's gear; positions are the
## castle's own (`town_world.gd` `_build_castle`). The town lab's Places view sets out the same training and smithy.
static func castle_yard(parent: Node3D, rng: RandomNumberGenerator) -> PropGroup:
	var g := PropGroup.new()
	g.name = "Yard"
	training(g, Vector3(-1.6, 0, 27.0), rng)
	smithy(g, Vector3(-21.5, 0, 16.0))
	# The stable's gear.
	g.put("Wagon", Vector3(12.0, 0, 37.0), 0.35)
	for i: int in 4:
		g.put(["Barrel", "Crate_Wooden", "Bag", "Barrel_Apples"][i] as String, Vector3(16.0 + i * 0.9, 0, 23.5 + rng.randf_range(0, 0.6)),
			rng.randf() * TAU)
	g.put("Bucket_Wooden_1", Vector3(18.0, 0, 36.0))
	g.put("Ladder", Vector3(19.4, 0, 24.5), PI * 0.5)
	parent.add_child(g)
	return g


## A training yard round `at` (the middle dummy's place): three dummies, a weapon stand either side, a barrel holder.
static func training(g: PropGroup, at: Vector3, rng: RandomNumberGenerator) -> void:
	for i: int in 3:
		g.put("Dummy", at + Vector3(-3.4 + i * 3.4, 0, rng.randf_range(-0.4, 0.4)), PI + rng.randf_range(-0.3, 0.3))
	g.put("WeaponStand", at + Vector3(-7.9, 0, -3.0), PI * 0.5)
	g.put("WeaponStand", at + Vector3(9.1, 0, -3.0), -PI * 0.5)
	g.put("Barrel_Holder", at + Vector3(0.1, 0, 4.5), PI)


## A smithy corner round `at` (the anvil's place): the anvil on its log, a workbench, a fire, a bucket, a crate.
static func smithy(g: PropGroup, at: Vector3) -> void:
	g.put("Anvil_Log", at, 0.4)
	g.put("Anvil", at + Vector3(0, 1.07, 0), 0.4)
	g.put("Workbench", at + Vector3(-2.5, 0, 2.5), PI * 0.5)
	g.put("FirePit", at + Vector3(2.5, 0, 2.5))
	g.put("Bucket_Metal", at + Vector3(1.5, 0, -1.0))
	g.put("Crate_Wooden", at + Vector3(-3.0, 0, -1.5), 0.2)


## Tall banners hanging on a wall's face: `at` each one's top middle on the face, `out` the way the face looks.
static func wall_banners(g: PropGroup, points: Array[Vector3], out: Vector3, size: float) -> void:
	var yaw: float = atan2(out.x, out.z)
	for i: int in points.size():
		var p: Vector3 = points[i]
		g.put("Banner_Vertical_1" if i % 2 == 0 else "Banner_Vertical_2", p - Vector3.UP * 2.35 * size + out * 0.1, yaw, size)
