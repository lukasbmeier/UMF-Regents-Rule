@tool
class_name KitHouse extends Node3D
## A HOUSE FROM THE KIT'S PIECES (2026-11-15, `docs/regents_rule/SETTLEMENTS_PREP.md` §6): set a footprint, floors,
## the finishes and the roof in the Inspector and the house builds itself from the Medieval Village kit, in the
## editor too. The pieces are built, never saved: the scene keeps only these fields.
##
## The kit's grid (read from its own sample scene): a wall is 2 m wide and 3 m tall, its outside is its +z; a house's
## origin is the middle of its footprint at its foot. The roof is the kit's one-piece roof for the footprint
## (`Roof_<tiles>_<depth m>x<width m>`, turned so its ridge runs along x), the gable ends `Roof_Front_*`.
## A footprint the kit has no roof for is narrowed to one it has (`effective_width`).
##
## The windows, shutters and doors are picked by `house_seed`: the same seed builds the same house.

enum Finish { PLASTER, UNEVEN_BRICK, WOOD_BRICK, WOOD_WEAR }
enum Tiles { ROUND, FLAT }

const FINISH_NAMES: PackedStringArray = ["Plaster", "UnevenBrick", "WoodBrick", "WoodWear"]
const CELL: float = 2.0
const STOREY: float = 3.0
## The kit's one-piece roofs: depth (m, the span across the ridge) -> the widths (m) it has.
const ROOFS: Dictionary[int, Array] = {4: [4, 6, 8], 6: [4, 6, 8, 10, 12, 14], 8: [8, 10, 12, 14]}
## Where a door leaf hangs from the middle of its wall (its hinge), and how deep in the wall.
const DOOR_OFFSET: Vector3 = Vector3(-0.55, 0.0, -0.08)
## How high the kit's roofs rise above the eaves, by depth (m): a chimney stands out of the slope.
const RIDGE: Dictionary[int, float] = {4: 3.73, 6: 4.89, 8: 6.0}

## Along x, in 2 m cells (the roof's ridge runs this way).
@export_range(1, 7) var width: int = 3:
	set(v):
		width = v
		_changed()
## Along z, in 2 m cells: 2, 3 or 4 (the roof spans 4, 6 or 8 m).
@export_range(2, 4) var depth: int = 3:
	set(v):
		depth = v
		_changed()
@export_range(1, 4) var floors: int = 2:
	set(v):
		floors = v
		_changed()
## The ground floor's walls.
@export var ground: Finish = Finish.UNEVEN_BRICK:
	set(v):
		ground = v
		_changed()
## The walls above.
@export var upper: Finish = Finish.PLASTER:
	set(v):
		upper = v
		_changed()
@export var tiles: Tiles = Tiles.ROUND:
	set(v):
		tiles = v
		_changed()
## Stone gable ends instead of boarded ones.
@export var stone_gables: bool = false:
	set(v):
		stone_gables = v
		_changed()
## Which cell of the front (+z) wall the door is in (from the left, -x); past the end, the last.
@export_range(0, 6) var door_cell: int = 1:
	set(v):
		door_cell = v
		_changed()
## Arched doors and windows, or square ones.
@export var round_openings: bool = true:
	set(v):
		round_openings = v
		_changed()
## How many wall cells have a window.
@export_range(0.0, 1.0) var window_share: float = 0.6:
	set(v):
		window_share = v
		_changed()
## How many windows have shutters (open or shut).
@export_range(0.0, 1.0) var shutter_share: float = 0.5:
	set(v):
		shutter_share = v
		_changed()
@export var chimney: bool = true:
	set(v):
		chimney = v
		_changed()
## Picks the windows, shutters, door and plaster grids.
@export var house_seed: int = 0:
	set(v):
		house_seed = v
		_changed()

## The pieces placed by the last build, by file name (the suite reads it).
var placed: PackedStringArray = []
var _pieces: Node3D = null
## One body for the whole house: every piece's collision shapes are moved into it (`TownKit.gather_collisions`).
var _body: StaticBody3D = null
var _queued: bool = false


func _ready() -> void:
	build()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild_later.call_deferred()


func _rebuild_later() -> void:
	_queued = false
	build()


## The width (cells) actually built: `width`, narrowed or widened to one the kit has a roof for at this depth.
func effective_width() -> int:
	var widths: Array = ROOFS[depth * 2]
	var want: int = width * 2
	var best: int = int(widths[0])
	for w: Variant in widths:
		if int(w) <= want:
			best = int(w)
	return floori(best / 2.0)


## The door: the middle of its cell on the front (+z) wall's face, at the foot (where a lantern or a sign goes beside it).
func door_point() -> Vector3:
	var w: int = effective_width()
	return Vector3(-w * CELL * 0.5 + 1.0 + mini(door_cell, w - 1) * CELL, 0.0, depth * CELL * 0.5)


## Builds the house from its fields (dropping the last build). Returns how many pieces it placed.
func build() -> int:
	if _pieces != null and is_instance_valid(_pieces):
		_pieces.free()
	_pieces = Node3D.new()
	_pieces.name = "Pieces"
	add_child(_pieces)
	_body = StaticBody3D.new()
	_body.name = "Body"
	_pieces.add_child(_body)
	placed = PackedStringArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(house_seed)
	var w: int = effective_width()
	var hw: float = w * CELL * 0.5
	var hd: float = depth * CELL * 0.5
	var top: float = floors * STOREY
	var arch: String = "Round" if round_openings else "Flat"
	for f: int in floors:
		var finish: Finish = ground if f == 0 else upper
		var fname: String = FINISH_NAMES[finish]
		var y: float = f * STOREY
		# Each side: the first cell's middle, the step to the next, how many, the way it faces.
		var sides: Array[Array] = [
			[Vector3(-hw + 1.0, y, hd), Vector3(CELL, 0, 0), w, 0.0, true],
			[Vector3(hw - 1.0, y, -hd), Vector3(-CELL, 0, 0), w, 180.0, false],
			[Vector3(hw, y, hd - 1.0), Vector3(0, 0, -CELL), depth, 90.0, false],
			[Vector3(-hw, y, -hd + 1.0), Vector3(0, 0, CELL), depth, -90.0, false],
		]
		for s: Array in sides:
			for i: int in int(s[2]):
				var at: Vector3 = (s[0] as Vector3) + (s[1] as Vector3) * i
				var yaw: float = float(s[3])
				var front: bool = bool(s[4])
				if f == 0 and front and i == mini(door_cell, w - 1):
					_door(fname, arch, at, yaw, rng)
				elif rng.randf() < window_share:
					_window(fname, at, yaw, rng)
				elif finish == Finish.PLASTER and f > 0 and rng.randf() < 0.35:
					_put("Wall_Plaster_WoodGrid", at, yaw)
				else:
					_put("Wall_%s_Straight" % fname, at, yaw)
		_corners(finish, y, hw, hd)
	for i: int in w:
		for j: int in depth:
			var floor_piece: String = "Floor_Brick" if ground == Finish.UNEVEN_BRICK else "Floor_WoodDark"
			_put(floor_piece, Vector3(-hw + 1.0 + i * CELL, 0.0, -hd + 1.0 + j * CELL), 0.0)
	var tile_name: String = "RoundTiles" if tiles == Tiles.ROUND else "FlatTiles"
	var roof: String = "Roof_%s_%dx%d" % [tile_name, depth * 2, w * 2]
	# Centered on its measured bounds: not every kit roof is centered on its origin (the 6x4 starts at it).
	var rb: AABB = TownKit.piece_bounds(roof)
	var shift := Vector3(-(rb.position.x + rb.size.x * 0.5), 0.0, -(rb.position.z + rb.size.z * 0.5))
	_put_xf(roof, _xf(Vector3(0, top, 0), -90.0) * Transform3D(Basis.IDENTITY, shift))
	var gable: String = "Roof_Front_%s%d" % ["Brick" if stone_gables else "Wood", depth * 2]
	_put(gable, Vector3(-hw, top, 0), -90.0)
	_put(gable, Vector3(hw, top, 0), 90.0)
	if chimney:
		var cx: float = (hw - 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		_put("Prop_Chimney", Vector3(cx, top + RIDGE[depth * 2] * 0.45, -hd * 0.5), 0.0)
	return placed.size()


func _door(fname: String, arch: String, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var xf: Transform3D = _xf(at, yaw)
	_put_xf("Wall_%s_Door_%s" % [fname, arch], xf)
	_put_xf("DoorFrame_%s_%s" % [arch, "Brick" if fname == "UnevenBrick" else "WoodDark"], xf)
	_put_xf("Door_%d_%s" % [rng.randi_range(1, 8), arch], xf * Transform3D(Basis.IDENTITY, DOOR_OFFSET))


func _window(fname: String, at: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var kind: String = (["Thin_Round", "Wide_Round"][rng.randi_range(0, 1)] as String) if round_openings else "Wide_Flat"
	_put("Wall_%s_Window_%s" % [fname, kind], at, yaw)
	_put("Window_%s%d" % [kind, rng.randi_range(1, 3)], at, yaw)
	if rng.randf() < shutter_share:
		_put("WindowShutters_%s_%s" % [kind, "Open" if rng.randf() < 0.6 else "Closed"], at, yaw)


func _corners(finish: Finish, y: float, hw: float, hd: float) -> void:
	if finish == Finish.UNEVEN_BRICK:
		# The kit's stone corner faces one way: turned per corner as its sample scene does.
		_put("Corner_Exterior_Brick", Vector3(hw, y, -hd), 0.0)
		_put("Corner_Exterior_Brick", Vector3(hw, y, hd), -90.0)
		_put("Corner_Exterior_Brick", Vector3(-hw, y, hd), 180.0)
		_put("Corner_Exterior_Brick", Vector3(-hw, y, -hd), 90.0)
	else:
		for c: Vector3 in [Vector3(hw, y, hd), Vector3(-hw, y, hd), Vector3(hw, y, -hd), Vector3(-hw, y, -hd)]:
			_put("Corner_Exterior_Wood", c, 0.0)


static func _xf(at: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)


func _put(piece_name: String, at: Vector3, yaw: float) -> Node3D:
	return _put_xf(piece_name, _xf(at, yaw))


func _put_xf(piece_name: String, xf: Transform3D) -> Node3D:
	var scene: PackedScene = TownKit.piece(piece_name) if TownKit.has_piece(piece_name) else null
	if scene == null:
		push_warning("KitHouse: the kit has no piece %s" % piece_name)
		return null
	var n: Node3D = scene.instantiate() as Node3D
	TownKit.gather_collisions(n, _body, xf)
	n.transform = xf
	_pieces.add_child(n)
	placed.append(piece_name)
	return n
