@tool
class_name RegentsKitCatalog extends RefCounted
## THE WORLD BUILDER'S ASSET & TOOL CATALOG (WB4–WB11, `docs/regents_rule/WORLD_BUILDER_PREP.md`).
## Discovers and organizes every brush, building template, 2 m grid-snap kit piece (305 village + 212 props),
## nature model, gathering node, station, foe/encounter, friendly lore NPC, and World Map POI so the Creative
## Mode hotbar and palette can filter, search, and stamp any of them.

const CATEGORIES: Array[StringName] = [
	&"terrain",
	&"settlements",
	&"kit_pieces",
	&"nature",
	&"skilling",
	&"foes",
	&"npcs",
]

const CATEGORY_LABELS: Dictionary[StringName, String] = {
	&"terrain": "1. Terrain & Roads",
	&"settlements": "2. Towns & Houses",
	&"kit_pieces": "3. Kit Pieces (2m Snap)",
	&"nature": "4. Nature & Rocks",
	&"skilling": "5. Nodes & Stations",
	&"foes": "6. Foes & Wildlife",
	&"npcs": "7. NPCs, Lore & POIs",
}

const NATURE_DIR: String = "res://game/regents/art/nature/"
const DEMO_HOUSES: Dictionary[String, String] = {
	"demo_house_c": "res://game/regents/town/houses/demo_house_c.tscn",
	"demo_house_d": "res://game/regents/town/houses/demo_house_d.tscn",
	"demo_houses_a": "res://game/regents/town/houses/demo_houses_a.tscn",
	"demo_tower": "res://game/regents/town/houses/demo_tower.tscn",
}
const CUSTOM_PRESETS_DIR: String = "user://builder_presets/"

static var _cached_entries: Dictionary[StringName, Array] = {}


## Clear cached catalog entries (after creating a new `NpcDef` or saving a custom house preset).
static func clear_cache() -> void:
	_cached_entries.clear()


## All entries in `category` (`Array[Dictionary]`), each `{id, category, group, label, kind, ...}`.
static func entries_for(category: StringName) -> Array[Dictionary]:
	if not _cached_entries.has(category):
		_cached_entries[category] = _build_category(category)
	var out: Array[Dictionary] = []
	out.assign(_cached_entries[category])
	return out


## Distinct group names inside `category` (in display order), for the palette's sub-group filter dropdown.
static func groups_for(category: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for item: Dictionary in entries_for(category):
		var g: String = String(item.get("group", ""))
		if not g.is_empty() and not out.has(g):
			out.append(g)
	return out


## True if `stem` is a non-harvestable tree model (all trees in Regent's Rule are harvestable skilling nodes in `5. Nodes & Stations`).
static func is_tree_model(stem: String) -> bool:
	return stem.contains("Tree") or stem.begins_with("TallThick") or stem.begins_with("Pine") \
		or stem.begins_with("Birch") or stem.begins_with("Willow") or stem.begins_with("GiantPine")


## Search across `category` (or all categories when `category == &""`) by substring in `label`, `id`, or `group`,
## with an optional exact `group_filter`.
static func search(query: String, category: StringName = &"", group_filter: String = "") -> Array[Dictionary]:
	var q: String = query.strip_edges().to_lower()
	var cats: Array[StringName] = []
	if category != &"":
		cats.append(category)
	else:
		cats.assign(CATEGORIES)
	var out: Array[Dictionary] = []
	for c: StringName in cats:
		for item: Dictionary in entries_for(c):
			if not group_filter.is_empty() and String(item.get("group", "")) != group_filter:
				continue
			if q.is_empty() or String(item.get("label", "")).to_lower().contains(q) \
					or String(item.get("id", "")).to_lower().contains(q) \
					or String(item.get("group", "")).to_lower().contains(q):
				out.append(item)
	return out


## Look up a catalog entry by `id` across all categories.
static func find_entry(entry_id: String) -> Dictionary:
	for c: StringName in CATEGORIES:
		for item: Dictionary in entries_for(c):
			if String(item.get("id", "")) == entry_id:
				return item
	return {}


static func _build_category(category: StringName) -> Array[Dictionary]:
	match category:
		&"terrain":
			return _build_terrain()
		&"settlements":
			return _build_settlements()
		&"kit_pieces":
			return _build_kit_pieces()
		&"nature":
			return _build_nature()
		&"skilling":
			return _build_skilling()
		&"foes":
			return _build_foes()
		&"npcs":
			return _build_npcs()
	return []


static func _build_terrain() -> Array[Dictionary]:
	return [
		{"id": "terrain_raise", "category": &"terrain", "group": "Sculpt", "label": "Raise Terrain", "kind": "terrain_brush", "mode": RegentsTerrainBrush.Mode.RAISE},
		{"id": "terrain_lower", "category": &"terrain", "group": "Sculpt", "label": "Lower Terrain", "kind": "terrain_brush", "mode": RegentsTerrainBrush.Mode.LOWER},
		{"id": "terrain_smooth", "category": &"terrain", "group": "Sculpt", "label": "Smooth Terrain", "kind": "terrain_brush", "mode": RegentsTerrainBrush.Mode.SMOOTH},
		{"id": "terrain_flatten", "category": &"terrain", "group": "Sculpt", "label": "Flatten to Height", "kind": "terrain_brush", "mode": RegentsTerrainBrush.Mode.FLATTEN},
		{"id": "terrain_terrace", "category": &"terrain", "group": "Sculpt", "label": "Terrace / Plateau", "kind": "terrain_brush", "mode": RegentsTerrainBrush.Mode.TERRACE},
		{"id": "terrain_ramp", "category": &"terrain", "group": "Sculpt", "label": "Carve Walkable Ramp (A -> B)", "kind": "terrain_ramp"},
		{"id": "paint_grass", "category": &"terrain", "group": "Surface Paint", "label": "Paint Grass", "kind": "terrain_paint", "tex": RegentsTerrainBrush.Tex.GRASS},
		{"id": "paint_rock", "category": &"terrain", "group": "Surface Paint", "label": "Paint Rock", "kind": "terrain_paint", "tex": RegentsTerrainBrush.Tex.ROCK},
		{"id": "paint_sand", "category": &"terrain", "group": "Surface Paint", "label": "Paint Sand", "kind": "terrain_paint", "tex": RegentsTerrainBrush.Tex.SAND},
		{"id": "paint_dirt", "category": &"terrain", "group": "Surface Paint", "label": "Paint Trodden Dirt", "kind": "terrain_paint", "tex": RegentsTerrainBrush.Tex.DIRT},
		{"id": "paint_cobble", "category": &"terrain", "group": "Surface Paint", "label": "Paint Cobble", "kind": "terrain_paint", "tex": RegentsTerrainBrush.Tex.COBBLE},
		{"id": "paint_auto_slope", "category": &"terrain", "group": "Surface Paint", "label": "Auto-Slope Rock & Sand", "kind": "terrain_brush", "mode": RegentsTerrainBrush.Mode.AUTO_SLOPE},
		{"id": "road_dirt", "category": &"terrain", "group": "Roads & Trails", "label": "Draw Dirt Trail (Path3D)", "kind": "road_spline", "surface": "dirt"},
		{"id": "road_cobble", "category": &"terrain", "group": "Roads & Trails", "label": "Draw Cobblestone Street", "kind": "road_spline", "surface": "cobble"},
		{"id": "road_setts", "category": &"terrain", "group": "Roads & Trails", "label": "Draw Stone Setts Road", "kind": "road_spline", "surface": "setts"},
		{"id": "clutter_scatter", "category": &"terrain", "group": "Foliage Clutter", "label": "Re-Scatter Meadow Clutter", "kind": "clutter_scatter"},
		{"id": "clutter_erase", "category": &"terrain", "group": "Foliage Clutter", "label": "Erase Clutter Brush", "kind": "clutter_erase"},
	]


static func _build_settlements() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "settlement_new", "category": &"settlements", "group": "Settlements", "label": "New Settlement Zone", "kind": "settlement"},
		{"id": "kit_cottage", "category": &"settlements", "group": "Parametric KitHouse", "label": "Kit Cottage (2x2, 1F)", "kind": "kit_house", "width": 2, "depth": 2, "floors": 1, "ground": KitHouse.Finish.WOOD_WEAR, "upper": KitHouse.Finish.WOOD_WEAR, "tiles": KitHouse.Tiles.FLAT},
		{"id": "kit_townhouse", "category": &"settlements", "group": "Parametric KitHouse", "label": "Kit Townhouse (3x3, 2F)", "kind": "kit_house", "width": 3, "depth": 3, "floors": 2, "ground": KitHouse.Finish.UNEVEN_BRICK, "upper": KitHouse.Finish.PLASTER, "tiles": KitHouse.Tiles.ROUND},
		{"id": "kit_merchant", "category": &"settlements", "group": "Parametric KitHouse", "label": "Kit Merchant House (4x3, 3F)", "kind": "kit_house", "width": 4, "depth": 3, "floors": 3, "ground": KitHouse.Finish.UNEVEN_BRICK, "upper": KitHouse.Finish.WOOD_BRICK, "tiles": KitHouse.Tiles.ROUND},
		{"id": "kit_longhall", "category": &"settlements", "group": "Parametric KitHouse", "label": "Kit Longhall (6x4, 2F)", "kind": "kit_house", "width": 6, "depth": 4, "floors": 2, "ground": KitHouse.Finish.UNEVEN_BRICK, "upper": KitHouse.Finish.UNEVEN_BRICK, "tiles": KitHouse.Tiles.FLAT},
		{"id": "demo_house_d", "category": &"settlements", "group": "Kit Demo Prefabs", "label": "Tavern / Inn (Demo House D)", "kind": "demo_house", "scene": DEMO_HOUSES["demo_house_d"], "footprint": Vector2(9.0, 11.0)},
		{"id": "demo_house_c", "category": &"settlements", "group": "Kit Demo Prefabs", "label": "Gabled Guildhall (Demo House C)", "kind": "demo_house", "scene": DEMO_HOUSES["demo_house_c"], "footprint": Vector2(13.0, 11.0)},
		{"id": "demo_houses_a", "category": &"settlements", "group": "Kit Demo Prefabs", "label": "Townhouse Row (Demo Houses A)", "kind": "demo_house", "scene": DEMO_HOUSES["demo_houses_a"], "footprint": Vector2(25.0, 11.0)},
		{"id": "demo_tower", "category": &"settlements", "group": "Kit Demo Prefabs", "label": "Watchtower (Demo Tower)", "kind": "demo_house", "scene": DEMO_HOUSES["demo_tower"], "footprint": Vector2(8.0, 8.0)},
		{"id": "castle_wall", "category": &"settlements", "group": "Walls & Keeps", "label": "Draw Castle / Town Wall", "kind": "castle_wall", "roofed": false},
		{"id": "castle_keep", "category": &"settlements", "group": "Walls & Keeps", "label": "Draw Roofed Castle Keep", "kind": "castle_wall", "roofed": true},
		{"id": "furnish_market", "category": &"settlements", "group": "TownFurnish Stampers", "label": "Stamp Market Stalls & Bunting", "kind": "furnish", "preset": "market"},
		{"id": "furnish_green", "category": &"settlements", "group": "TownFurnish Stampers", "label": "Stamp Village Green & FirePit", "kind": "furnish", "preset": "green"},
		{"id": "furnish_inn", "category": &"settlements", "group": "TownFurnish Stampers", "label": "Stamp Inn Outdoor Tables", "kind": "furnish", "preset": "inn_front"},
		{"id": "furnish_training", "category": &"settlements", "group": "TownFurnish Stampers", "label": "Stamp Training Yard (Dummies & Racks)", "kind": "furnish", "preset": "training"},
		{"id": "furnish_smithy", "category": &"settlements", "group": "TownFurnish Stampers", "label": "Stamp Smithy Corner", "kind": "furnish", "preset": "smithy"},
	]
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CUSTOM_PRESETS_DIR)):
		var files: PackedStringArray = DirAccess.get_files_at(CUSTOM_PRESETS_DIR)
		files.sort()
		for f: String in files:
			if f.ends_with(".tscn"):
				var stem: String = f.get_basename()
				out.append({
					"id": "custom_" + stem,
					"category": &"settlements",
					"group": "Saved Custom Presets",
					"label": "Custom: " + stem.capitalize(),
					"kind": "custom_preset",
					"scene": CUSTOM_PRESETS_DIR + f,
					"footprint": Vector2(10.0, 10.0),
				})
	return out


static func _build_kit_pieces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir_pair: Array in [[TownKit.VILLAGE, "village"], [TownKit.PROPS, "props"]]:
		var dir: String = String(dir_pair[0])
		var source_kit: String = String(dir_pair[1])
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
			continue
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		files.sort()
		for f: String in files:
			if not f.ends_with(".gltf"):
				continue
			var piece: String = f.get_basename()
			var group: String = _kit_piece_group(piece, source_kit)
			var is_structural: bool = source_kit == "village" and not piece.begins_with("Prop_")
			out.append({
				"id": "piece_" + piece,
				"category": &"kit_pieces",
				"group": group,
				"label": piece.replace("_", " "),
				"kind": "kit_piece",
				"piece": piece,
				"path": dir + f,
				"snap_xz": 2.0 if is_structural else 0.25,
				"snap_y": 3.0 if is_structural else 0.1,
			})
	return out


static func _kit_piece_group(piece: String, source_kit: String) -> String:
	if source_kit == "village":
		if piece.begins_with("Wall_"):
			return "Walls"
		if piece.begins_with("Corner_") or piece.begins_with("Floor_") or piece.begins_with("Overhang_"):
			return "Corners & Floors"
		if piece.begins_with("Roof_"):
			return "Roofs & Gables"
		if piece.begins_with("Door") or piece.begins_with("Window"):
			return "Doors & Windows"
		if piece.begins_with("Stair") or piece.begins_with("Balcony"):
			return "Stairs & Balconies"
		return "Fences & Yard"
	if piece.begins_with("Stall_"):
		return "Market Stalls"
	if piece.begins_with("Sign_") or piece.begins_with("Banner_"):
		return "Banners & Signs"
	if piece.begins_with("Barrel") or piece.begins_with("Crate") or piece.begins_with("FarmCrate") or piece.begins_with("Bag") or piece.begins_with("Bucket"):
		return "Barrels & Crates"
	if piece.begins_with("Table") or piece.begins_with("Bench") or piece.begins_with("Chair") or piece.begins_with("Bed") or piece.begins_with("Shelf") or piece.begins_with("Book"):
		return "Furniture & Tavern"
	if piece.begins_with("Lantern") or piece.begins_with("Torch") or piece.begins_with("Candle") or piece.begins_with("Chandelier") or piece.begins_with("FirePit"):
		return "Lighting & Fire"
	return "Smithy & Decor"


static func _build_nature() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "nature_clutter_scatter", "category": &"nature", "group": "Foliage Clutter", "label": "Re-Scatter Meadow Clutter (Grass, Flowers & Pebbles)", "kind": "clutter_scatter"},
		{"id": "nature_clutter_erase", "category": &"nature", "group": "Foliage Clutter", "label": "Erase Clutter in Brush Circle", "kind": "clutter_erase"},
	]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(NATURE_DIR)):
		return out
	var files: PackedStringArray = DirAccess.get_files_at(NATURE_DIR)
	files.sort()
	for f: String in files:
		if not f.ends_with(".gltf"):
			continue
		var stem: String = f.get_basename()
		# All trees in Regent's Rule are harvestable skilling nodes (`5. Nodes & Stations`), so exclude tree models here.
		if is_tree_model(stem):
			continue
		var group: String = "Grass, Flowers & Mushrooms"
		if stem.begins_with("Rock_") or stem.begins_with("Pebble_"):
			group = "Rocks & Boulders"
		elif stem.begins_with("Bush_") or stem.begins_with("Fern_"):
			group = "Bushes & Ferns"
		out.append({
			"id": "nature_" + stem,
			"category": &"nature",
			"group": group,
			"label": stem.replace("_", " "),
			"kind": "nature_prop",
			"model": stem,
			"path": NATURE_DIR + f,
			"solid": stem.begins_with("Rock_"),
		})
	return out


static func _build_skilling() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for nd: NodeDef in NodeDef.all_by_tier():
		if nd.whole_round:
			continue   # carcasses are left by slain creatures, not hand-placed gathering nodes
		var radius: float = float(nd.radii_cm()[0]) / 100.0 if not nd.radii_cm().is_empty() else 0.6
		out.append({
			"id": "node_" + nd.display_name.to_lower().replace(" ", "_"),
			"category": &"skilling",
			"group": "Gathering Nodes (%s)" % (nd.skill.display_name if nd.skill != null else "Skilling"),
			"label": "%s (Rank %d)" % [nd.display_name, nd.min_rank],
			"kind": "level_point",
			"point_kind": "node",
			"tag": nd.display_name,
			"radius": maxf(radius, 0.5),
			"def_id": nd.id,
		})
	for d: ContentDef in RegentsContent.items(&"station"):
		var st: StationDef = d as StationDef
		if st == null:
			continue
		out.append({
			"id": "station_" + String(st.key),
			"category": &"skilling",
			"group": "Crafting Stations",
			"label": st.display_name,
			"kind": "level_point",
			"point_kind": "station",
			"tag": String(st.key),
			"radius": 1.0,
			"def_id": st.id,
		})
	out.append({
		"id": "point_dummy",
		"category": &"skilling",
		"group": "Training Yard",
		"label": "Training Dummy",
		"kind": "level_point",
		"point_kind": "dummy",
		"tag": "",
		"radius": 0.5,
	})
	return out


static func _build_foes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for foe: FoeDef in FoeDef.all():
		out.append({
			"id": "foe_" + String(foe.key),
			"category": &"foes",
			"group": "Single Foes" if foe.fights else "Wildlife (Hunted)",
			"label": "%s (%d HP)" % [foe.display_name, foe.hp],
			"kind": "level_point",
			"point_kind": String(foe.key),
			"tag": "",
			"radius": 0.5,
			"foe_id": foe.id,
		})
	out.append_array([
		{
			"id": "stamp_skeleton_camp",
			"category": &"foes",
			"group": "Encounter Stampers",
			"label": "Skeleton Camp (2 Warriors, 1 Axeman, 1 Archer + POI)",
			"kind": "encounter_stamp",
			"preset": "skeleton_camp",
		},
		{
			"id": "stamp_wolf_pack",
			"category": &"foes",
			"group": "Encounter Stampers",
			"label": "Wolf Pack (3 Packmates within 4m)",
			"kind": "encounter_stamp",
			"preset": "wolf_pack",
		},
		{
			"id": "stamp_deer_pair",
			"category": &"foes",
			"group": "Encounter Stampers",
			"label": "Grazing Deer Pair (2 Deer)",
			"kind": "encounter_stamp",
			"preset": "deer_pair",
		},
	])
	return out


static func _build_npcs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for npc: NpcDef in NpcDef.all():
		var role: String = " (%s)" % npc.title if not npc.title.is_empty() else ""
		out.append({
			"id": "npc_" + String(npc.key),
			"category": &"npcs",
			"group": "Friendly Lore NPCs",
			"label": "%s%s [%s]" % [npc.display_name, role, npc.outfit],
			"kind": "level_point",
			"point_kind": "npc",
			"tag": String(npc.key),
			"radius": 0.6,
			"npc_id": npc.id,
		})
	out.append_array([
		{
			"id": "point_guide",
			"category": &"npcs",
			"group": "Tutorial & Map Markers",
			"label": "Camp Drillmaster (`guide` point)",
			"kind": "level_point",
			"point_kind": "guide",
			"tag": "",
			"radius": 0.5,
		},
		{
			"id": "point_poi",
			"category": &"npcs",
			"group": "Tutorial & Map Markers",
			"label": "World Map Point of Interest (`poi`)",
			"kind": "level_point",
			"point_kind": "poi",
			"tag": "New Landmark",
			"radius": 10.0,
		},
		{
			"id": "point_spawn",
			"category": &"npcs",
			"group": "Tutorial & Map Markers",
			"label": "Move World Spawn Point (`LevelSpawn`)",
			"kind": "move_spawn",
		},
	])
	return out
