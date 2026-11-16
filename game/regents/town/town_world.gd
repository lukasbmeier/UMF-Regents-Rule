extends Node3D
## THE TOWN WORLD (Luke, 2026-11-15: "a small 3d scene (say 1km x 1km) that packs in a small village, middle market
## town and a castle with code made walls and reusing the walls"): open `res://game/regents/town/town_world.tscn` and
## press F6 (no server). A kilometer square: a VILLAGE round its green in the west, a walled MARKET TOWN in the middle,
## a CASTLE on its mound in the north-east, roads between them, woods round about. Every house is the Medieval Village
## kit's: built by `KitHouse` or one of the kit's own demo houses (`houses/`); every wall, tower and the keep is
## `CastleWall`, the same code for the town's wall and the castle's. Each place is a `Settlement` in its own style.
## Presentation only: nothing here is in the game yet, and nothing is furnished (the props come once Luke says).
##
##   1-9, 0   the views (overview, village, village lane, town, market, castle, castle gate, market stalls, inn,
##           castle yard)
##   right mouse, drag   look       W A S D   fly       Q E   down, up       Shift   faster       wheel   speed
##   L   day, dusk, night          S   every place's style to the next preset          H   this help
##
## SHOTS (windowed, no server): `"$GODOT" --path . res://game/regents/town/town_world.tscn -- <out dir>` saves each view
## by day and some by night as `<out>/town_<view>_<light>.png`, then quits.

const SIZE: float = 1000.0
const VILLAGE: Vector3 = Vector3(-280, 0, 250)
const TOWN: Vector3 = Vector3(40, 0, 70)
const CASTLE: Vector3 = Vector3(250, 0, -250)
## The castle's mound: its top's height, how far it is flat, where its foot is.
const MOUND_TOP: float = 14.0
const MOUND_FLAT: float = 72.0
const MOUND_FOOT: float = 150.0
## The town's wall: half its width (x) and depth (z).
const TOWN_HALF: Vector2 = Vector2(100, 80)
const MARKET_HALF: Vector2 = Vector2(22, 17)
const CASTLE_RADIUS: float = 58.0
const STYLES_DIR: String = "res://game/regents/town/styles/"
## Each place's first style (a file in `styles/`).
const FIRST_STYLES: Dictionary[StringName, String] = {&"village": "02_riverside", &"town": "04_hilltown",
	&"castle": "06_capital"}
const LIGHTS: PackedStringArray = ["Day", "Dusk", "Night"]
const HOUSES: Dictionary[String, String] = {"inn": "res://game/regents/town/houses/demo_house_d.tscn",
	"hall": "res://game/regents/town/houses/demo_house_c.tscn", "row": "res://game/regents/town/houses/demo_houses_a.tscn",
	"tower": "res://game/regents/town/houses/demo_tower.tscn"}

## The places, by name (village, town, castle).
var settlements: Dictionary[StringName, Settlement] = {}
## Roads (a.x, a.z, b.x, b.z) and paved squares (center x, z, half x, z), world meters. Every road is drawn in dirt;
## a street (inside a place) is paved over it in that place's paving, as a square is.
var roads: Array[Vector4] = []
var squares: Array[Vector4] = []
var square_places: Array[int] = []
var streets: Array[Vector4] = []
var street_places: Array[int] = []
## The places in the ground's paving order (`street_places`, `square_places`).
const PLACES: Array[StringName] = [&"village", &"town", &"castle"]
var view: int = 0
var light: int = 0
var styles: Array[SettlementStyle] = []
## How far every place's style has been stepped through `styles` (S).
var style_step: int = 0
var trees: int = 0

var _cam: Camera3D = null
## The ground's material (its paving is repainted when the styles step).
var _ground: ShaderMaterial = null
var _sun: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _info: Label = null
var _help: bool = true
var _looking: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _speed: float = 30.0
## Each house's footprint in the town, to keep them apart (town-local rects).
var _taken: Array[Rect2] = []
var _rng := RandomNumberGenerator.new()
## The props' own dice (`TownFurnish`), apart from the houses' so furnishing never moves a house.
var _props_rng := RandomNumberGenerator.new()
## At each new house's door (`TownFurnish.door`): the share with a lantern, a sign, things by it. Set per place.
var _door_odds: Vector3 = Vector3.ZERO
## The prop groups placed (the suite counts them).
var furnished: Array[PropGroup] = []


func _ready() -> void:
	_rng.seed = 1115
	_props_rng.seed = 2611
	_load_styles()
	_build_environment()
	_build_village()
	_build_town()
	_build_castle()
	_build_roads()
	_build_ground()
	_build_trees()
	_build_ui()
	set_light(0)
	set_view(0)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_shoot.call_deferred(args[0])


func _load_styles() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(STYLES_DIR)
	files.sort()
	for f: String in files:
		if f.ends_with(".tres"):
			styles.append(load(STYLES_DIR + f) as SettlementStyle)


func _style_named(file: String) -> SettlementStyle:
	return load(STYLES_DIR + file + ".tres") as SettlementStyle


## The ground's height at (x, z): gentle swells, flattened under the village and the town, the castle's mound.
static func height_at(x: float, z: float) -> float:
	var h: float = (sin(x * 0.011) + sin(z * 0.013 + 1.3) + sin((x + z) * 0.007)) * 0.9
	var dv: float = Vector2(x - VILLAGE.x, z - VILLAGE.z).length()
	var flat_v: float = 1.0 - smoothstep(110.0, 170.0, dv)
	var q: Vector2 = Vector2(absf(x - TOWN.x), absf(z - TOWN.z)) - TOWN_HALF - Vector2(25, 25)
	var dt: float = Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var flat_t: float = 1.0 - smoothstep(0.0, 60.0, dt)
	h *= 1.0 - maxf(flat_v, flat_t)
	var dc: float = Vector2(x - CASTLE.x, z - CASTLE.z).length()
	return lerpf(h, MOUND_TOP, 1.0 - smoothstep(MOUND_FLAT, MOUND_FOOT, dc))


func _settlement(key: StringName, at: Vector3, yaw: float) -> Settlement:
	var s := Settlement.new()
	s.name = String(key).capitalize()
	s.style = _style_named(FIRST_STYLES[key])
	s.town_seed = hash(key)
	s.position = Vector3(at.x, height_at(at.x, at.z), at.z)
	s.rotation.y = yaw
	settlements[key] = s
	return s


func _house(parent: Node3D, at: Vector3, yaw: float, w: int, d: int, floors: int, ground: KitHouse.Finish,
		upper: KitHouse.Finish) -> KitHouse:
	var h := KitHouse.new()
	h.width = w
	h.depth = d
	h.floors = floors
	h.ground = ground
	h.upper = upper
	h.tiles = KitHouse.Tiles.ROUND if _rng.randf() < 0.6 else KitHouse.Tiles.FLAT
	h.stone_gables = ground == KitHouse.Finish.UNEVEN_BRICK and _rng.randf() < 0.5
	h.round_openings = _rng.randf() < 0.7
	h.door_cell = _rng.randi_range(0, maxi(0, w - 1))
	h.chimney = _rng.randf() < 0.7
	h.house_seed = _rng.randi()
	h.position = at
	h.rotation.y = yaw
	parent.add_child(h)
	if _door_odds != Vector3.ZERO:
		furnished.append(TownFurnish.door(h, _props_rng, _door_odds.x, _door_odds.y, _door_odds.z))
	return h


func _demo(parent: Node3D, key: String, at: Vector3, yaw: float) -> Node3D:
	var n: Node3D = TownKit.instance_building(load(HOUSES[key]) as PackedScene)
	n.position = at
	n.rotation.y = yaw
	parent.add_child(n)
	return n


## THE VILLAGE: cottages round a green, facing it, the inn (the kit's House D) at its head, a few along the road out.
func _build_village() -> void:
	var s: Settlement = _settlement(&"village", VILLAGE, 0.0)
	_door_odds = Vector3(0.35, 0.04, 0.5)
	var finishes: Array[KitHouse.Finish] = [KitHouse.Finish.WOOD_WEAR, KitHouse.Finish.WOOD_BRICK, KitHouse.Finish.PLASTER,
		KitHouse.Finish.WOOD_WEAR]
	_demo(s, "inn", Vector3(0, 0, -30), 0.0)
	var rings: Array[Vector2] = [Vector2(27.0, 11), Vector2(47.0, 15)]
	for ring: Vector2 in rings:
		_village_ring(s, ring.x, int(ring.y), finishes)
	for k: int in 5:
		var at := Vector3(70.0 + k * 16.0, 0, -18.0 if k % 2 == 0 else 18.0)
		_house(s, at, 0.0 if at.z < 0 else PI, _rng.randi_range(2, 3), 2, 1, KitHouse.Finish.WOOD_WEAR,
			KitHouse.Finish.WOOD_WEAR)
	# The green's campfire and cart, the inn's tables, a wagon on the road out.
	furnished.append(TownFurnish.green(s, Vector3(0, 0, 2), _props_rng))
	furnished.append(TownFurnish.inn_front(s, Vector3(0, 0, -24.5), _props_rng))
	var road := PropGroup.new()
	road.name = "RoadOut"
	road.put("Wagon", Vector3(58, 0, 7), PI * 0.5)
	road.put("Barrel", Vector3(55.5, 0, 9.0), 0.5)
	road.put("Crate_Wooden", Vector3(56.5, 0, 9.6), 0.2)
	s.add_child(road)
	furnished.append(road)
	_door_odds = Vector3.ZERO
	add_child(s)


## Cottages round the green at radius r, facing it, leaving the inn's place (north) and the road's (east) open.
func _village_ring(s: Settlement, radius: float, count: int, finishes: Array[KitHouse.Finish]) -> void:
	for i: int in count:
		var ang: float = TAU * i / count + _rng.randf_range(-0.05, 0.05)
		var at := Vector3(sin(ang) * radius, 0, -cos(ang) * radius)
		if (at.z < -radius * 0.7 and absf(at.x) < 12.0) or (at.x > radius * 0.75 and absf(at.z) < 9.0):
			continue
		var r: float = radius + _rng.randf_range(-2, 3)
		at = at.normalized() * r
		var yaw: float = atan2(-at.x, -at.z)
		var ground: KitHouse.Finish = finishes[_rng.randi_range(0, finishes.size() - 1)]
		_house(s, at, yaw, _rng.randi_range(2, 3), 2, _rng.randi_range(1, 2), ground,
			KitHouse.Finish.PLASTER if _rng.randf() < 0.6 else ground)


## THE MARKET TOWN: its wall (`CastleWall`, square towers, gates north, south and west), two streets crossing at the
## market square, a lane either side, houses along every street facing it, the kit's demo houses among them.
func _build_town() -> void:
	var s: Settlement = _settlement(&"town", TOWN, 0.0)
	_door_odds = Vector3(0.5, 0.15, 0.45)
	var wall := CastleWall.new()
	wall.name = "TownWall"
	var hx: float = TOWN_HALF.x
	var hz: float = TOWN_HALF.y
	wall.corners = PackedVector3Array([Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)])
	wall.gates = PackedInt32Array([0, 2, 3])
	wall.height = 8.0
	wall.thickness = 2.2
	wall.tower_radius = 4.0
	wall.tower_height = 12.0
	wall.round_towers = false
	wall.gate_width = 6.0
	wall.gate_height = 5.5
	# The town's square towers hipped in its round tiles, a little bell to them.
	wall.roof_style = CastleWall.RoofStyle.CONE
	wall.roof_flare = 0.3
	wall.roof_pitch = 1.3
	s.add_child(wall)
	_taken.clear()
	_taken.append(Rect2(-MARKET_HALF, MARKET_HALF * 2.0))
	# The kit's own houses first, at the market's corners.
	_demo_in_town(s, "hall", Vector3(-MARKET_HALF.x - 8, 0, -MARKET_HALF.y - 7), PI, Vector2(13, 11))
	_demo_in_town(s, "row", Vector3(MARKET_HALF.x + 14, 0, -MARKET_HALF.y - 7), PI, Vector2(25, 11))
	_demo_in_town(s, "inn", Vector3(-MARKET_HALF.x - 6, 0, MARKET_HALF.y + 7), 0.0, Vector2(9, 11))
	# The kit's tower stands in the square's corner (the square is already kept clear of houses).
	_demo(s, "tower", Vector3(MARKET_HALF.x - 3, 0, MARKET_HALF.y - 3), 0.0)
	var street: float = 4.0
	# Along the north-south street, both sides; along the east-west street, both sides; the lanes at z = +-48.
	_row(s, -hz + 6, hz - 6, street, true)
	_row(s, -hz + 6, hz - 6, -street, true)
	_row(s, -hx + 6, hx - 6, street, false)
	_row(s, -hx + 6, hx - 6, -street, false)
	for lane: float in [-48.0, 48.0]:
		_row(s, -hx + 6, hx - 6, -street, false, lane)
		_row(s, -hx + 6, hx - 6, street, false, lane)
	_door_odds = Vector3.ZERO
	# The market's stalls, torches at the gates.
	var tower_spot: Vector2 = MARKET_HALF - Vector2(3, 3)
	furnished.append(TownFurnish.market(s, Vector3.ZERO, MARKET_HALF, 6.5, 3.5, _props_rng, 12.0,
		[Rect2(tower_spot - Vector2(4, 4), Vector2(8, 8))] as Array[Rect2]))
	var gates := PropGroup.new()
	gates.name = "Gates"
	var face: float = wall.thickness * 0.5 + 0.35
	var hw: float = wall.gate_width * 0.5 - 0.6
	TownFurnish.gate_torches(gates, Vector3(0, 0, -hz - face), Vector3.RIGHT, Vector3.FORWARD, hw, 3.4)
	TownFurnish.gate_torches(gates, Vector3(0, 0, hz + face), Vector3.RIGHT, Vector3.BACK, hw, 3.4)
	TownFurnish.gate_torches(gates, Vector3(-hx - face, 0, 0), Vector3.BACK, Vector3.LEFT, hw, 3.4)
	s.add_child(gates)
	furnished.append(gates)
	add_child(s)


func _demo_in_town(s: Settlement, key: String, at: Vector3, yaw: float, size: Vector2) -> void:
	_taken.append(Rect2(Vector2(at.x, at.z) - size * 0.5, size))
	_demo(s, key, at, yaw)


## Houses down one side of a street from `from` to `to`: the street runs along z (`along_z`) or x, on the town's middle
## line or `line`; the houses start `side` meters off it, on the side its sign says, each facing the street.
func _row(s: Settlement, from: float, to: float, side: float, along_z: bool, line: float = 0.0) -> void:
	var t: float = from
	while t < to:
		var w: int = _rng.randi_range(2, 4)
		var d: int = _rng.randi_range(3, 4)
		var floors: int = _rng.randi_range(2, 3)
		var wm: float = w * 2.0
		var dm: float = d * 2.0
		var gap: float = _rng.randf_range(1.0, 4.0)
		var c_along: float = t + wm * 0.5
		var c_across: float = line + side + signf(side) * dm * 0.5
		var at: Vector3 = Vector3(c_across, 0, c_along) if along_z else Vector3(c_along, 0, c_across)
		var size: Vector2 = Vector2(dm, wm) if along_z else Vector2(wm, dm)
		var rect := Rect2(Vector2(at.x, at.z) - size * 0.5, size).grow(0.8)
		var inside: bool = absf(at.x) + size.x * 0.5 < TOWN_HALF.x - 3.0 and absf(at.z) + size.y * 0.5 < TOWN_HALF.y - 3.0
		var free: bool = inside
		for r: Rect2 in _taken:
			if r.intersects(rect):
				free = false
				break
		# Keep the gates' mouths and the crossing open.
		if absf(c_along) < 8.0 and line == 0.0:
			free = false
		if free:
			_taken.append(rect)
			# Facing the street: the house's front (+z) toward the line.
			var face: Vector3 = Vector3(-signf(side), 0, 0) if along_z else Vector3(0, 0, -signf(side))
			var yaw: float = atan2(face.x, face.z)
			var ground: KitHouse.Finish = KitHouse.Finish.UNEVEN_BRICK if _rng.randf() < 0.65 else KitHouse.Finish.PLASTER
			var uppers: Array[KitHouse.Finish] = [KitHouse.Finish.PLASTER, KitHouse.Finish.WOOD_BRICK, KitHouse.Finish.PLASTER]
			var upper: KitHouse.Finish = uppers[_rng.randi_range(0, 2)]
			# Along x the house's width runs along the street; along z it is turned, so width still runs along it.
			_house(s, at, yaw, w, d, floors, ground, upper)
		t += wm + gap


## THE CASTLE: on its mound, its curtain wall a pentagon of `CastleWall` with round towers and a gatehouse facing the
## town, the keep (a small closed `CastleWall`, roofed, taller towers), a hall, barracks, a stable and the kit's tower.
func _build_castle() -> void:
	var to_town: Vector3 = (TOWN - CASTLE)
	to_town.y = 0.0
	to_town = to_town.normalized()
	var s: Settlement = _settlement(&"castle", CASTLE, atan2(to_town.x, to_town.z))
	var curtain := CastleWall.new()
	curtain.name = "Curtain"
	var pts := PackedVector3Array()
	for k: int in 5:
		var a: float = deg_to_rad(54.0 + k * 72.0)
		pts.append(Vector3(cos(a), 0, sin(a)) * CASTLE_RADIUS)
	curtain.corners = pts
	curtain.gates = PackedInt32Array([0])
	curtain.height = 13.0
	curtain.thickness = 3.5
	curtain.tower_radius = 5.5
	curtain.tower_height = 20.0
	curtain.gate_width = 6.0
	curtain.gate_height = 7.0
	# The castle's round towers: tall slate bells.
	curtain.roof_style = CastleWall.RoofStyle.CONE
	curtain.roof_slate = true
	curtain.roof_flare = 0.5
	curtain.roof_pitch = 2.6
	s.add_child(curtain)
	var keep := CastleWall.new()
	keep.name = "Keep"
	keep.corners = PackedVector3Array([Vector3(-12, 0, -20), Vector3(12, 0, -20), Vector3(12, 0, 4), Vector3(-12, 0, 4)])
	keep.gates = PackedInt32Array()
	keep.height = 22.0
	keep.thickness = 3.0
	keep.tower_radius = 3.6
	keep.tower_height = 29.0
	keep.roofed = true
	keep.roof_style = CastleWall.RoofStyle.TURRET
	keep.roof_slate = true
	keep.roof_flare = 0.45
	keep.roof_pitch = 2.4
	s.add_child(keep)
	_door_odds = Vector3(0.6, 0.0, 0.3)
	_house(s, Vector3(-30, 0, 4), PI * 0.5, 7, 4, 2, KitHouse.Finish.UNEVEN_BRICK, KitHouse.Finish.UNEVEN_BRICK)
	_house(s, Vector3(30, 0, 4), -PI * 0.5, 5, 3, 2, KitHouse.Finish.UNEVEN_BRICK, KitHouse.Finish.PLASTER)
	_house(s, Vector3(22, 0, 30), -PI * 0.5, 4, 3, 1, KitHouse.Finish.WOOD_WEAR, KitHouse.Finish.WOOD_WEAR)
	_demo(s, "tower", Vector3(-24, 0, 28), 0.0)
	_door_odds = Vector3.ZERO
	# The yard's gear; banners on the keep's front and inside the gate; torches at the gate.
	furnished.append(TownFurnish.castle_yard(s, _props_rng))
	var dress := PropGroup.new()
	dress.name = "Banners"
	var keep_face: float = 4.0 + keep.thickness * 0.5
	TownFurnish.wall_banners(dress, [Vector3(-5, 19, keep_face), Vector3(5, 19, keep_face)] as Array[Vector3], Vector3.BACK, 3.0)
	var gate_z: float = CASTLE_RADIUS * sin(deg_to_rad(54.0))
	var inner: float = gate_z - curtain.thickness * 0.5
	TownFurnish.wall_banners(dress, [Vector3(-11, 12, inner), Vector3(11, 12, inner)] as Array[Vector3], Vector3.FORWARD, 2.2)
	TownFurnish.gate_torches(dress, Vector3(0, 0, gate_z + curtain.thickness * 0.5 + 0.35), Vector3.RIGHT, Vector3.BACK,
		curtain.gate_width * 0.5 - 0.6, 4.2)
	s.add_child(dress)
	furnished.append(dress)
	add_child(s)


## The roads between the places, the streets inside them, the squares; painted on the ground (`town_ground.gdshader`).
func _build_roads() -> void:
	var castle_gate: Vector3 = _castle_point(Vector3(0, 0, CASTLE_RADIUS * cos(deg_to_rad(36.0)) + 4.0))
	_road_path([TOWN + Vector3(0, 0, -TOWN_HALF.y - 2), TOWN + Vector3(30, 0, -170), CASTLE + (castle_gate - CASTLE) * 2.2,
		castle_gate])
	_road_path([TOWN + Vector3(-TOWN_HALF.x - 2, 0, 0), Vector3(-120, 0, 120), VILLAGE + Vector3(60, 0, 0)])
	_road_path([VILLAGE + Vector3(18, 0, 0), VILLAGE + Vector3(60, 0, 0)])
	_road_path([TOWN + Vector3(0, 0, TOWN_HALF.y + 2), Vector3(70, 0, 300), Vector3(60, 0, 500)])
	_road_path([VILLAGE + Vector3(-18, 0, 0), Vector3(-420, 0, 230), Vector3(-500, 0, 260)])
	_road_path([VILLAGE + Vector3(60, 0, 0), VILLAGE + Vector3(150, 0, 0)])
	_road_path([TOWN + Vector3(0, 0, -TOWN_HALF.y), TOWN + Vector3(0, 0, TOWN_HALF.y)], 1)
	_road_path([TOWN + Vector3(-TOWN_HALF.x, 0, 0), TOWN + Vector3(TOWN_HALF.x - 4, 0, 0)], 1)
	for lane: float in [-48.0, 48.0]:
		_road_path([TOWN + Vector3(-TOWN_HALF.x + 4, 0, lane), TOWN + Vector3(TOWN_HALF.x - 4, 0, lane)], 1)
	var ring: Array[Vector3] = []
	for k: int in 13:
		var a: float = TAU * k / 12.0
		ring.append(VILLAGE + Vector3(cos(a), 0, sin(a)) * 18.0)
	_road_path(ring)
	_road_path([castle_gate, _castle_point(Vector3(0, 0, 8))], 2)
	squares.append(Vector4(TOWN.x, TOWN.z, MARKET_HALF.x, MARKET_HALF.y))
	square_places.append(1)
	squares.append(Vector4(CASTLE.x, CASTLE.z, 34, 34))
	square_places.append(2)


func _castle_point(local: Vector3) -> Vector3:
	var s: Settlement = settlements[&"castle"]
	return s.global_transform * local


## A road through `pts`; with a place (`PLACES`), a street paved in that place's paving.
func _road_path(pts: Array, place: int = -1) -> void:
	for i: int in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		roads.append(Vector4(a.x, a.z, b.x, b.z))
		if place >= 0:
			streets.append(Vector4(a.x, a.z, b.x, b.z))
			street_places.append(place)


## Distance from (x, z) to the nearest road.
func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best: float = INF
	for r: Vector4 in roads:
		var a := Vector2(r.x, r.y)
		var b := Vector2(r.z, r.w)
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## The ground: a 1 km grid at 4 m, its heights from `height_at`, worn by `town_ground.gdshader`.
func _build_ground() -> void:
	var cells: int = 250
	var step: float = SIZE / cells
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in cells:
		for i: int in cells:
			var x0: float = -SIZE * 0.5 + i * step
			var z0: float = -SIZE * 0.5 + j * step
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x0 + step, height_at(x0 + step, z0), z0)
			var p01 := Vector3(x0, height_at(x0, z0 + step), z0 + step)
			var p11 := Vector3(x0 + step, height_at(x0 + step, z0 + step), z0 + step)
			for p: Vector3 in [p00, p10, p11, p00, p11, p01]:
				st.set_uv(Vector2(p.x, p.z) * 0.5)
				st.add_vertex(p)
	st.index()
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://game/regents/town/town_ground.gdshader") as Shader
	var rs := PackedVector4Array()
	for r: Vector4 in roads:
		rs.append(r)
	mat.set_shader_parameter(&"roads", rs)
	mat.set_shader_parameter(&"road_count", roads.size())
	var sq := PackedVector4Array()
	for q: Vector4 in squares:
		sq.append(q)
	mat.set_shader_parameter(&"squares", sq)
	mat.set_shader_parameter(&"square_place", PackedInt32Array(square_places))
	mat.set_shader_parameter(&"square_count", squares.size())
	var ss := PackedVector4Array()
	for r: Vector4 in streets:
		ss.append(r)
	mat.set_shader_parameter(&"streets", ss)
	mat.set_shader_parameter(&"street_place", PackedInt32Array(street_places))
	mat.set_shader_parameter(&"street_count", streets.size())
	mi.material_override = mat
	add_child(mi)
	_ground = mat
	paint_paving()


## Each place's paving onto the ground, from its style (again after S).
func paint_paving() -> void:
	if _ground == null:
		return
	var cols := PackedVector4Array()
	var mixes := PackedVector4Array()
	var patterns := PackedInt32Array()
	for i: int in 4:
		var s: SettlementStyle = settlements[PLACES[i]].style if i < PLACES.size() else null
		var c: Color = (s.paving_color() if s != null else SettlementStyle.PAVING_PAINTED).srgb_to_linear()
		var m: Color = s.paving_mix if s != null else Color(0, 0, 0, 0)
		var share: float = m.a
		m = m.srgb_to_linear()
		m.a = share
		cols.append(Vector4(c.r, c.g, c.b, 1.0))
		mixes.append(Vector4(m.r, m.g, m.b, m.a))
		patterns.append(s.paving_pattern if s != null else 0)
	_ground.set_shader_parameter(&"paving", cols)
	_ground.set_shader_parameter(&"paving_mix", mixes)
	_ground.set_shader_parameter(&"paving_pattern", patterns)


## Woods: trees, bushes and rocks from the nature kit, kept off the places and the roads.
func _build_trees() -> void:
	# The kit's common trees only: its twisted and tall-thick trees have red and blue leaves (fantasy woods).
	var kinds: Array[Array] = [["CommonTree_1", 3], ["CommonTree_2", 3], ["CommonTree_3", 3], ["Bush_Large", 2],
		["Bush_Long_1", 1], ["Rock_Medium_1", 1], ["Rock_Big_1", 1]]
	var scenes: Array[PackedScene] = []
	var weights: Array[int] = []
	for k: Array in kinds:
		scenes.append(load("res://game/regents/art/nature/%s.gltf" % k[0]) as PackedScene)
		weights.append(int(k[1]))
	var total: int = 0
	for w: int in weights:
		total += w
	var woods := Node3D.new()
	woods.name = "Woods"
	add_child(woods)
	var tries: int = 0
	while trees < 520 and tries < 8000:
		tries += 1
		var x: float = _rng.randf_range(-SIZE * 0.48, SIZE * 0.48)
		var z: float = _rng.randf_range(-SIZE * 0.48, SIZE * 0.48)
		# Woods in clumps: keep a spot by a slow noise, thinner in the open.
		var clump: float = sin(x * 0.017 + 0.7) * sin(z * 0.021 + 1.9) + sin((x - z) * 0.009) * 0.6
		if clump < 0.15 and _rng.randf() < 0.85:
			continue
		if Vector2(x - VILLAGE.x, z - VILLAGE.z).length() < 75.0:
			continue
		if absf(x - TOWN.x) < TOWN_HALF.x + 18.0 and absf(z - TOWN.z) < TOWN_HALF.y + 18.0:
			continue
		if Vector2(x - CASTLE.x, z - CASTLE.z).length() < CASTLE_RADIUS + 22.0:
			continue
		if road_distance(x, z) < 9.0:
			continue
		var pick: int = _rng.randi_range(0, total - 1)
		var idx: int = 0
		while pick >= weights[idx]:
			pick -= weights[idx]
			idx += 1
		var t: Node3D = scenes[idx].instantiate() as Node3D
		t.position = Vector3(x, height_at(x, z) - 0.1, z)
		t.rotation.y = _rng.randf() * TAU
		t.scale = Vector3.ONE * _rng.randf_range(0.85, 1.4)
		woods.add_child(t)
		for g: Node in t.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).visibility_range_end = 700.0
		trees += 1


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	sky.sky_material = _sky
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_density = 0.00035
	_env.fog_aerial_perspective = 0.6
	_env.ssao_enabled = true
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 320.0
	add_child(_sun)
	_cam = Camera3D.new()
	_cam.far = 2500.0
	add_child(_cam)


func set_light(i: int) -> void:
	light = posmod(i, LIGHTS.size())
	match light:
		0:
			_sun.rotation_degrees = Vector3(-48, -35, 0)
			_sun.light_color = Color(1.0, 0.96, 0.9)
			_sun.light_energy = 1.25
			_sky.sky_top_color = Color(0.35, 0.52, 0.78)
			_sky.sky_horizon_color = Color(0.72, 0.78, 0.84)
			_sky.ground_horizon_color = Color(0.6, 0.62, 0.6)
			_env.ambient_light_energy = 1.0
			_env.fog_light_color = Color(0.7, 0.76, 0.84)
			TownKit.set_night(0.0)
		1:
			_sun.rotation_degrees = Vector3(-9, -110, 0)
			_sun.light_color = Color(1.0, 0.62, 0.36)
			_sun.light_energy = 1.0
			_sky.sky_top_color = Color(0.24, 0.26, 0.45)
			_sky.sky_horizon_color = Color(0.95, 0.6, 0.38)
			_sky.ground_horizon_color = Color(0.5, 0.38, 0.3)
			_env.ambient_light_energy = 0.6
			_env.fog_light_color = Color(0.8, 0.55, 0.42)
			TownKit.set_night(0.5)
		2:
			_sun.rotation_degrees = Vector3(-55, 40, 0)
			_sun.light_color = Color(0.55, 0.65, 0.95)
			_sun.light_energy = 0.12
			_sky.sky_top_color = Color(0.01, 0.015, 0.04)
			_sky.sky_horizon_color = Color(0.05, 0.06, 0.1)
			_sky.ground_horizon_color = Color(0.02, 0.02, 0.03)
			_env.ambient_light_energy = 0.25
			_env.fog_light_color = Color(0.05, 0.06, 0.1)
			TownKit.set_night(1.0)
	_refresh_info()


## The views: [name, eye, looking at], world meters (y above the ground there).
func views() -> Array[Array]:
	var to_town: Vector3 = (TOWN - CASTLE)
	to_town.y = 0.0
	to_town = to_town.normalized()
	var gate: Vector3 = CASTLE + to_town * 50.0
	return [
		["overview", Vector3(-120, 330, 470), Vector3(20, 0, -20)],
		["village", VILLAGE + Vector3(70, 38, 75), VILLAGE + Vector3(0, 2, -6)],
		["village_lane", VILLAGE + Vector3(-6, 1.8, 14), VILLAGE + Vector3(4, 5, -30)],
		["town", TOWN + Vector3(-170, 85, 170), TOWN + Vector3(0, 0, -10)],
		["market", TOWN + Vector3(14, 1.8, 15), TOWN + Vector3(-14, 6, -22)],
		["castle", CASTLE + to_town * 190.0 + Vector3(60, 40, 0), CASTLE + Vector3(0, 10, 0)],
		["castle_gate", gate + to_town * 55.0 + Vector3(0, 1.8, 0), gate + Vector3(0, 8, 0)],
		["market_stalls", TOWN + Vector3(-9, 7, 21), TOWN + Vector3(3, 0, -2)],
		["inn", VILLAGE + Vector3(7, 2.4, -13), VILLAGE + Vector3(-1, 1.5, -26)],
		["castle_yard", _castle_point(Vector3(10, 7, 42)), _castle_point(Vector3(-6, 2, 14))],
	]


func set_view(i: int) -> void:
	var all: Array[Array] = views()
	view = posmod(i, all.size())
	var eye: Vector3 = all[view][1]
	var look: Vector3 = all[view][2]
	eye.y += height_at(eye.x, eye.z)
	look.y += height_at(look.x, look.z)
	_cam.look_at_from_position(eye, look)
	_yaw = _cam.rotation.y
	_pitch = _cam.rotation.x
	_refresh_info()


## Every place's style one preset on (S).
func step_styles() -> void:
	style_step += 1
	for key: StringName in settlements:
		var first: int = styles.find(_style_named(FIRST_STYLES[key]))
		settlements[key].restyle(styles[posmod(first + style_step, styles.size())])
	paint_paving()
	_refresh_info()


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move -= _cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S) and _looking:
		move += _cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		move -= _cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		move += _cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move != Vector3.ZERO:
		var fast: float = 4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var p: Vector3 = _cam.global_position + move.normalized() * _speed * fast * delta
		p.y = maxf(p.y, height_at(p.x, p.z) + 1.2)
		_cam.global_position = p


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = minf(_speed * 1.25, 400.0)
			_refresh_info()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = maxf(_speed / 1.25, 3.0)
			_refresh_info()
	elif event is InputEventMouseMotion and _looking:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.004
		_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.5, 1.5)
		_cam.rotation = Vector3(_pitch, _yaw, 0)
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			set_view(k - KEY_1)
		elif k == KEY_0:
			set_view(9)
		elif k == KEY_L:
			set_light(light + 1)
		elif k == KEY_S and not _looking:
			step_styles()
		elif k == KEY_H:
			_help = not _help
			_refresh_info()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_info = Label.new()
	_info.position = Vector2(14, 10)
	_info.add_theme_color_override(&"font_color", Color(1, 1, 1))
	_info.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_info.add_theme_constant_override(&"outline_size", 5)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_info)


func _refresh_info() -> void:
	if _info == null:
		return
	var lines: PackedStringArray = []
	var all: Array[Array] = views()
	lines.append("THE TOWN WORLD   view %d: %s   %s   speed %d m/s" % [view + 1, all[view][0], LIGHTS[light], int(_speed)])
	for key: StringName in settlements:
		var s: Settlement = settlements[key]
		lines.append("  %s: %s (%d buildings)" % [String(key).capitalize(), s.style.title, s.buildings.size()])
	if _help:
		lines.append("1-9, 0 views   right mouse look   WASD QE fly   Shift fast   wheel speed   L light   S next styles   H help")
	_info.text = "\n".join(lines)


## The shots: each view by day, the places by dusk and night, then quit.
func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	_help = false
	var plan: Array[Array] = []
	for i: int in views().size():
		plan.append([i, 0])
	for i: int in [0, 2, 4, 6, 7, 8]:
		plan.append([i, 2])
	plan.append([3, 1])
	for p: Array in plan:
		set_light(int(p[1]))
		set_view(int(p[0]))
		for f: int in 8:
			await get_tree().process_frame
		var path: String = dir.path_join("town_%s_%s.png" % [views()[view][0], LIGHTS[light].to_lower()])
		get_viewport().get_texture().get_image().save_png(path)
		print("shot: ", path)
	step_styles()
	set_light(0)
	set_view(3)
	for f: int in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join("town_town_restyled.png"))
	AppExit.quit(get_tree(), 0)
