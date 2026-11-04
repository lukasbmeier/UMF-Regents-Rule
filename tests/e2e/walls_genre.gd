extends RefereeGenre
## THE WALLS TEST'S GENRE (tests/walls_test.sh, DECISIONS #304): what a genre such as Regent's Rule tells
## its referee, standing in for one the template does not have. It sizes resource nodes (kind 2) one by
## one: the box each puts up is `UMF_TEST_WALLS` (`<entity id>=<x>,<y>,<z>;...`, sizes from its feet), and
## a node not named there puts up none, so two nodes of one kind differ (the per-entity part). While a
## node is not Normal (worked out) it puts up none, read from its status row, as a genre with no
## character for the kind would say. Started with `--referee-genre=res://tests/e2e/walls_genre.gd`.

const RESOURCE_NODE: int = 2

var _sizes: Dictionary[int, Vector3] = {}


func _init() -> void:
	for part: String in OS.get_environment("UMF_TEST_WALLS").split(";", false):
		var kv: PackedStringArray = part.split("=")
		var xyz: PackedStringArray = kv[1].split(",") if kv.size() == 2 else PackedStringArray()
		if xyz.size() == 3:
			_sizes[int(kv[0])] = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
	print("[WallsGenre] walls for %s" % str(_sizes))


func sizes_kind(kind: int) -> bool:
	return kind == RESOURCE_NODE


func walls(entity_id: int, _kind: int) -> Array[AABB]:
	var out: Array[AABB] = []
	var st: RefCounted = SpaceTimeSync.get_row(&"status_state", entity_id)
	if _sizes.has(entity_id) and (st == null or int(st.get(&"status")) == StatusDef.NORMAL):
		var size: Vector3 = _sizes[entity_id]
		out.append(RefereeGenre.box(size, Vector3(0.0, size.y * 0.5, 0.0)))
	return out


func wall_tables() -> Array[StringName]:
	return [&"status_state"]
