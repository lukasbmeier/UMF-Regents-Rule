extends "res://tests/suite_base.gd"
## SETTLEMENTS (`-- --only=regents_town`; Luke, 2026-11-15, `docs/regents_rule/SETTLEMENTS_PREP.md`), with no server:
##   - every preset style loads, named, every slot a color
##   - every material the Medieval Village kit's pieces wear is a slot the town dye knows (and an unknown one is left
##     alone and reported); every texture the dye names is there
##   - a `KitHouse` builds from the kit's pieces, the same seed the same house; a footprint the kit has no roof for is
##     narrowed; its collisions are one body
##   - a `Settlement` dresses and merges every building: one mesh each, the dye's shared materials, each building its
##     own seed; a style edited live reaches its materials
##   - a `CastleWall`'s gate is open (and shut with no gate); its surfaces are named as the kit's; every ROOF STYLE
##     builds, a roofed tower rising solid to its eaves and its roof starting there (no battlements under it)
##   - the STREETS are code-made (no texture), each place's paving its style's, every preset's paving apart from its walls
##   - the PROPS kit: every material it wears a slot the dye knows; a `PropGroup` is one building (one mesh, one body),
##     its cloth in the style's cloth; the world's market, doors and yard furnished, no stall on the kit's tower
##   - the town world builds its three places inside its square kilometer, no two town houses overlapping
##   - the town lab shows every preset, six seeds, and a style changed live

const STYLES_DIR: String = "res://game/regents/town/styles/"


func run() -> void:
	_run_styles()
	_run_kit()
	_run_house()
	await _run_settlement()
	_run_wall()
	_run_roofs()
	_run_streets()
	await _run_props()
	await _run_world()
	await _run_lab()


func _styles() -> Array[SettlementStyle]:
	var out: Array[SettlementStyle] = []
	var files: PackedStringArray = DirAccess.get_files_at(STYLES_DIR)
	files.sort()
	for f: String in files:
		if f.ends_with(".tres") and not f.begins_with("custom_"):
			out.append(load(STYLES_DIR + f) as SettlementStyle)
	return out


func _run_styles() -> void:
	var all: Array[SettlementStyle] = _styles()
	_check(all.size() >= 8, "eight preset styles or more (%d)" % all.size())
	var titles: Dictionary[String, bool] = {}
	var ok: bool = true
	for s: SettlementStyle in all:
		ok = ok and s != null and not s.title.is_empty() and not s.note.is_empty()
		if s != null:
			titles[s.title] = true
			for slot: StringName in SettlementStyle.SLOTS:
				ok = ok and typeof(s.get(slot)) == TYPE_COLOR
	_check(ok, "every preset is a SettlementStyle with a title, a note and a color in every slot")
	_check(titles.size() == all.size(), "no two presets share a title")


## Every material name a kit's glTF pieces use (read from the files: the import keeps the names).
func _kit_materials(dir: String = TownKit.VILLAGE) -> Dictionary[String, bool]:
	var out: Dictionary[String, bool] = {}
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with(".gltf"):
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
		if typeof(j) != TYPE_DICTIONARY:
			continue
		for m: Variant in ((j as Dictionary).get("materials", []) as Array):
			var n: String = str((m as Dictionary).get("name", ""))
			if n != "Collision" and not n.is_empty():
				out[n] = true
	return out


func _run_kit() -> void:
	var names: Dictionary[String, bool] = _kit_materials()
	_check(names.size() >= 12, "the kit's pieces are in (%d materials)" % names.size())
	var missing: Array[String] = []
	for n: String in names:
		if not TownKit.SURFACES.has(n):
			missing.append(n)
	_check(missing.is_empty(), "every material the kit's pieces wear is a slot the town dye knows (missing: %s)" % [missing])
	var style: SettlementStyle = _styles()[1]
	var textures_ok: bool = true
	for n: String in TownKit.SURFACES:
		var m: ShaderMaterial = TownKit.material_for(n, style)
		textures_ok = textures_ok and m != null and m.get_shader_parameter(&"albedo_tex") != null
		if not bool((TownKit.SURFACES[n] as Dictionary).get("leaves", false)) and str((TownKit.SURFACES[n] as Dictionary).get("tex", "")) != "":
			textures_ok = textures_ok and m.get_shader_parameter(&"normal_tex") != null \
				and m.get_shader_parameter(&"rough_tex") != null
	_check(textures_ok, "every texture the dye names is in the kit's folder")
	_check(TownKit.material_for("MI_NotAKitMaterial", style) == null, "a name the dye does not know gets no material")
	_check(TownKit.material_for("MI_Plaster", style) == TownKit.material_for("MI_Plaster", style),
		"a style's material for a kit material is made once and shared")
	_check(TownKit.material_for("MI_Plaster", style) != TownKit.material_for("MI_Plaster", _styles()[2]),
		"two styles, two materials")


func _house(w: int, d: int, floors: int, seed_v: int) -> KitHouse:
	var h := KitHouse.new()
	h.width = w
	h.depth = d
	h.floors = floors
	h.house_seed = seed_v
	add_child(h)
	return h


func _run_house() -> void:
	var h: KitHouse = _house(3, 3, 2, 7)
	var placed: PackedStringArray = h.placed
	_check(placed.has("Roof_RoundTiles_6x6") and placed.count("Roof_Front_Wood6") == 2,
		"a 6 x 6 m house: the kit's 6x6 roof and two gable ends")
	_check(placed.count("Corner_Exterior_Brick") == 4 and placed.count("Corner_Exterior_Wood") == 4,
		"four stone corners on the stone floor, four posts on the plaster one")
	var doors: int = 0
	for p: String in placed:
		if p.begins_with("Door_"):
			doors += 1
	_check(doors == 1, "one door")
	var bodies: Array[Node] = h.find_children("*", "StaticBody3D", true, false)
	var shapes: int = 0
	for b: Node in bodies:
		shapes += b.get_child_count()
	_check(bodies.size() == 1 and shapes > 20, "the pieces' collisions are one body (%d bodies, %d shapes)" % [bodies.size(), shapes])
	var again: KitHouse = _house(3, 3, 2, 7)
	var other: KitHouse = _house(3, 3, 2, 8)
	_check(again.placed == placed, "the same seed builds the same house")
	_check(other.placed != placed, "another seed, other windows and shutters")
	var wide: KitHouse = _house(2, 4, 1, 1)
	_check(wide.effective_width() == 4 and wide.placed.has("Roof_RoundTiles_8x8"),
		"no 8 x 4 roof in the kit: a deep house is widened to the 8 x 8 one")
	var long_one: KitHouse = _house(7, 2, 1, 1)
	_check(long_one.effective_width() == 4 and long_one.placed.has("Roof_RoundTiles_4x8"),
		"no 4 x 14 roof: a long shallow house is narrowed to the 4 x 8 one")
	for n: KitHouse in [h, again, other, wide, long_one]:
		n.free()
	# Every footprint and both tiles: the roof's drawn bounds centered over the house and covering it (the kit's 6x4
	# roofs start at their origin: Luke saw one hang off a 4 x 6 house, 2026-11-15).
	var off: Array[String] = []
	for tiles: int in [KitHouse.Tiles.ROUND, KitHouse.Tiles.FLAT]:
		for d: int in range(2, 5):
			for w: int in range(1, 8):
				var k: KitHouse = _house(w, d, 1, 3)
				k.tiles = tiles as KitHouse.Tiles
				k.build()
				var hw: float = k.effective_width() * KitHouse.CELL * 0.5
				var hd: float = d * KitHouse.CELL * 0.5
				for i: int in k.placed.size():
					var p: String = k.placed[i]
					if not p.begins_with("Roof_") or p.begins_with("Roof_Front"):
						continue
					var node: Node3D = k.get_node("Pieces").get_child(i + 1) as Node3D
					var b: AABB = node.transform * TownKit.piece_bounds(p)
					var c: Vector3 = b.get_center()
					if absf(c.x) > 0.3 or absf(c.z) > 0.3 or b.size.x < hw * 2.0 or b.size.z < hd * 2.0:
						off.append("%s on %dx%d (center %.2f, %.2f)" % [p, w, d, c.x, c.z])
				k.free()
	_check(off.is_empty(), "every footprint's roof sits centered over the house and covers it (off: %s)" % [off])


func _run_settlement() -> void:
	var style: SettlementStyle = _styles()[1].copy()
	var s := Settlement.new()
	s.style = style
	var a: KitHouse = KitHouse.new()
	a.position = Vector3(-20, 0, 0)
	s.add_child(a)
	var b: KitHouse = KitHouse.new()
	b.position = Vector3(0, 0, 0)
	s.add_child(b)
	var demo: Node3D = TownKit.instance_building(load("res://game/regents/town/houses/demo_house_c.tscn") as PackedScene)
	demo.position = Vector3(25, 0, 0)
	var group := Node3D.new()
	group.add_child(demo)
	s.add_child(group)
	var w := CastleWall.new()
	w.position = Vector3(0, 0, -40)
	s.add_child(w)
	TownKit.unknown.clear()
	add_child(s)
	await get_tree().process_frame
	_check(s.buildings.size() == 4, "the settlement finds its four buildings, one inside a plain group (%d)" % s.buildings.size())
	var one_mesh: bool = true
	var dyed: bool = true
	var mats: Dictionary[String, Material] = {}
	var shared: bool = true
	for bld: Node3D in s.buildings:
		var meshes: Array[Node] = bld.find_children("*", "MeshInstance3D", true, false)
		one_mesh = one_mesh and meshes.size() == 1
		for mn: Node in meshes:
			var mi: MeshInstance3D = mn as MeshInstance3D
			for i: int in mi.mesh.get_surface_count():
				var m: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
				dyed = dyed and m != null and (m.shader == TownKit.SURFACE_SHADER or m.shader == TownKit.LEAVES_SHADER)
				if m != null:
					if mats.has(m.resource_name) and mats[m.resource_name] != m:
						shared = false
					mats[m.resource_name] = m
	_check(one_mesh, "every building merged into one mesh")
	_check(dyed, "every surface wears the town dye")
	_check(shared, "a kit material is one material across the settlement's buildings")
	_check(TownKit.unknown.is_empty(), "no surface the dye does not know (%s)" % [TownKit.unknown.keys()])
	var seed_a: Variant = (a.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_instance_shader_parameter(&"building_seed")
	var seed_b: Variant = (b.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).get_instance_shader_parameter(&"building_seed")
	_check(seed_a != null and seed_b != null and float(seed_a) != float(seed_b), "each building its own seed (%s, %s)" % [seed_a, seed_b])
	style.plaster = Color(0.1, 0.8, 0.3, 1.0)
	TownKit.refresh(style)
	var plaster: ShaderMaterial = TownKit.material_for("MI_Plaster", style)
	_check((plaster.get_shader_parameter(&"dye_a") as Color).is_equal_approx(Color(0.1, 0.8, 0.3, 1.0)),
		"a style changed live reaches its materials")
	var stranger := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var sm := StandardMaterial3D.new()
	sm.resource_name = "MI_Stranger"
	bm.material = sm
	stranger.mesh = bm
	add_child(stranger)
	var dressed: int = TownKit.dress(stranger, style, 1, 0.0)
	_check(dressed == 0 and stranger.get_surface_override_material(0) == null and TownKit.unknown.has("MI_Stranger"),
		"a surface the dye does not know is left as it is, and reported")
	stranger.free()
	TownKit.unknown.clear()
	s.free()


func _run_wall() -> void:
	var w := CastleWall.new()
	w.corners = PackedVector3Array([Vector3(-20, 0, 0), Vector3(20, 0, 0)])
	w.closed = false
	w.gates = PackedInt32Array([0])
	add_child(w)
	var gate_point := Vector3(0, 2, 0)
	_check(not _inside_any(w, gate_point), "the gate is open: nothing solid in its middle")
	_check(_inside_any(w, Vector3(-10, 2, 0)), "the wall beside it is solid")
	var names: Dictionary[String, bool] = {}
	var mi: MeshInstance3D = w.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	for i: int in mi.mesh.get_surface_count():
		names[mi.mesh.surface_get_material(i).resource_name] = true
	_check(names.has(CastleWall.MASONRY) and names.has(CastleWall.CUT) and names.has(CastleWall.ROOF)
		and names.has(CastleWall.TIMBER), "its surfaces are named as the kit's materials (%s)" % [names.keys()])
	w.gates = PackedInt32Array()
	w.build()
	_check(_inside_any(w, gate_point), "with no gate, the same spot is wall")
	w.free()


## A wall's vertices by surface name.
func _verts(w: CastleWall) -> Dictionary[String, PackedVector3Array]:
	var out: Dictionary[String, PackedVector3Array] = {}
	var mi: MeshInstance3D = w.find_children("Walls", "MeshInstance3D", true, false)[0] as MeshInstance3D
	for i: int in mi.mesh.get_surface_count():
		out[mi.mesh.surface_get_material(i).resource_name] = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
	return out


func _roof_try(style: CastleWall.RoofStyle, slate: bool, roofs_on: bool = true, round_ones: bool = true) -> CastleWall:
	var w := CastleWall.new()
	w.corners = PackedVector3Array([Vector3(-8, 0, 0), Vector3(8, 0, 0)])
	w.closed = false
	w.gates = PackedInt32Array()
	w.height = 9.0
	w.tower_radius = 3.5
	w.tower_height = 14.0
	w.roof_style = style
	w.roof_slate = slate
	w.tower_roofs = roofs_on
	w.round_towers = round_ones
	add_child(w)
	return w


## How a tower's top is built: [the roof's lowest y, its widest reach from the tower's middle, the masonry's highest y
## within the tower, whether a merlon stands on the tower's top] for the tower at (-8, 0, 0).
func _tower_top(w: CastleWall) -> Array:
	var v: Dictionary[String, PackedVector3Array] = _verts(w)
	var c := Vector2(-8, 0)
	var roof_lo: float = INF
	var reach: float = 0.0
	for key: String in [CastleWall.ROOF, CastleWall.SLATE]:
		for p: Vector3 in v.get(key, PackedVector3Array()):
			if p.x < 0.0:
				roof_lo = minf(roof_lo, p.y)
				reach = maxf(reach, Vector2(p.x, p.z).distance_to(c))
	var masonry_hi: float = 0.0
	for p: Vector3 in v.get(CastleWall.MASONRY, PackedVector3Array()):
		if Vector2(p.x, p.z).distance_to(c) < w.tower_radius + 0.5:
			masonry_hi = maxf(masonry_hi, p.y)
	var merlon: bool = false
	for p: Vector3 in v.get(CastleWall.CUT, PackedVector3Array()):
		var r: float = Vector2(p.x, p.z).distance_to(c)
		# A merlon's top corners: inside the tower's rim, at the merlons' height (a cap's middle vertex is at r = 0).
		if r > 1.0 and r < w.tower_radius - 0.05 and absf(p.y - (w.tower_height + w.merlon_height)) < 0.05:
			merlon = true
	return [roof_lo, reach, masonry_hi, merlon]


func _run_roofs() -> void:
	var eave: float = 14.0 + 1.3
	var cone: CastleWall = _roof_try(CastleWall.RoofStyle.CONE, false)
	var top: Array = _tower_top(cone)
	var names: Dictionary[String, PackedVector3Array] = _verts(cone)
	_check(names.has(CastleWall.ROOF) and names.has(CastleWall.METAL) and names.has(CastleWall.TIMBER),
		"a cone: round tiles, a metal finial, the eaves' timber underside (%s)" % [names.keys()])
	_check(float(top[2]) >= eave - 0.01 and not bool(top[3]),
		"a roofed tower rises solid to its eaves, no battlements under the roof (masonry to %.2f; merlon: %s)" % [top[2], top[3]])
	_check(float(top[0]) >= eave - 0.6 and float(top[0]) <= eave + 0.01 and float(top[1]) >= 3.5 + 0.2 + 0.6,
		"its roof starts at the eaves and reaches past the wall (lowest %.2f, reach %.2f)" % [top[0], top[1]])
	var cone_count: int = names[CastleWall.ROOF].size()
	var slate: CastleWall = _roof_try(CastleWall.RoofStyle.CONE, true)
	var sv: Dictionary[String, PackedVector3Array] = _verts(slate)
	_check(sv.has(CastleWall.SLATE) and not sv.has(CastleWall.ROOF), "slate: flat tiles, no round ones")
	var stepped: CastleWall = _roof_try(CastleWall.RoofStyle.STEPPED, false)
	_check(_verts(stepped)[CastleWall.ROOF].size() > cone_count, "courses: the cone laid in three, more of it")
	var kit: CastleWall = _roof_try(CastleWall.RoofStyle.KIT, false)
	var kit_roofs: int = 0
	for n: Node in kit.find_children("*", "Node3D", true, false):
		if (n as Node3D).scene_file_path.contains(CastleWall.KIT_ROOF_ROUND):
			kit_roofs += 1
	_check(kit_roofs == 2 and not _verts(kit).has(CastleWall.ROOF), "the kit's own: its tower roof on both towers (%d)" % kit_roofs)
	var turret: CastleWall = _roof_try(CastleWall.RoofStyle.TURRET, false)
	var tt: Array = _tower_top(turret)
	_check(bool(tt[3]) and float(tt[0]) >= 14.0 + 3.0 - 0.6, "a turret: the battlements kept, its roof on a turret above them")
	var open: CastleWall = _roof_try(CastleWall.RoofStyle.OPEN, false)
	var ov: Dictionary[String, PackedVector3Array] = _verts(open)
	_check(bool(_tower_top(open)[3]) and not ov.has(CastleWall.ROOF) and not ov.has(CastleWall.SLATE), "open: battlements, no roof")
	var off: CastleWall = _roof_try(CastleWall.RoofStyle.CONE, false, false)
	_check(bool(_tower_top(off)[3]) and not _verts(off).has(CastleWall.ROOF), "NEGATIVE: tower roofs off, a cone style builds no roof")
	var square: CastleWall = _roof_try(CastleWall.RoofStyle.CONE, false, true, false)
	var hi: float = 0.0
	for p: Vector3 in _verts(square)[CastleWall.ROOF]:
		hi = maxf(hi, p.y)
	_check(hi > eave + 3.0, "a square tower's roof: a hipped pyramid rising over it (top %.1f)" % hi)
	for w: CastleWall in [cone, slate, stepped, kit, turret, open, off, square]:
		w.free()


## Whether a style's streets are kept apart from its walls: the paving at least `gap` from stone and masonry (RGB), for
## the slots the style colors.
static func _paving_apart(s: SettlementStyle, gap: float = 0.15) -> bool:
	var pv: Color = s.paving_color()
	for slot: StringName in [&"stone", &"masonry"]:
		var c: Color = s.color_of(slot)
		if c.a > 0.0 and Vector3(pv.r - c.r, pv.g - c.g, pv.b - c.b).length() < gap:
			return false
	return true


func _run_streets() -> void:
	var near: Array[String] = []
	for s: SettlementStyle in _styles():
		if not _paving_apart(s):
			near.append(s.title)
	_check(near.is_empty(), "every preset's paving is well apart from its stone and masonry (too near: %s)" % [near])
	var same: SettlementStyle = _styles()[5].copy()
	same.paving = same.masonry
	_check(not _paving_apart(same), "NEGATIVE: paving the masonry's color is caught")
	var textured: bool = false
	for path: String in ["res://game/regents/town/town_ground.gdshader", "res://game/regents/town/town_street.gdshader",
			"res://game/regents/town/town_paving.gdshaderinc"]:
		textured = textured or FileAccess.get_file_as_string(path).contains("sampler2D")
	_check(not textured, "the streets are code-made: no texture in the ground's, the street's or the paving's shader")


func _run_props() -> void:
	var names: Dictionary[String, bool] = _kit_materials(TownKit.PROPS)
	_check(names.size() >= 10, "the props kit is in (%d materials)" % names.size())
	var missing: Array[String] = []
	for n: String in names:
		if not TownKit.SURFACES.has(n):
			missing.append(n)
	_check(missing.is_empty(), "every material the props kit wears is a slot the dye knows (missing: %s)" % [missing])
	_check(not TownKit.has_piece("Not_A_Prop") and TownKit.has_piece("Barrel") and TownKit.has_piece("Wall_Plaster_Straight"),
		"a piece is found in either kit, an unknown name in neither")
	var style: SettlementStyle = _styles()[1].copy()
	style.cloth = Color(0.2, 0.7, 0.3, 1.0)
	var s := Settlement.new()
	s.style = style
	var g := PropGroup.new()
	g.put("Stall_Vegetables_Full", Vector3.ZERO)
	g.put("Barrel", Vector3(2, 0, 0))
	g.put("Banner_1_Cloth", Vector3(-2, 2, 0))
	s.add_child(g)
	add_child(s)
	await get_tree().process_frame
	_check(s.buildings.size() == 1 and s.buildings[0] == g, "a prop group is one building to its settlement")
	var meshes: Array[Node] = g.find_children("*", "MeshInstance3D", true, false)
	var bodies: Array[Node] = g.find_children("*", "StaticBody3D", true, false)
	_check(meshes.size() == 1 and bodies.size() == 1 and bodies[0].get_child_count() > 3,
		"its props merged to one mesh and one body (%d meshes, %d bodies)" % [meshes.size(), bodies.size()])
	var cloth_ok: bool = false
	var mi: MeshInstance3D = meshes[0] as MeshInstance3D
	for i: int in mi.mesh.get_surface_count():
		var m: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
		if m != null and m.resource_name == "MI_Banner":
			cloth_ok = (m.get_shader_parameter(&"dye_a") as Color).is_equal_approx(style.cloth)
	_check(cloth_ok, "its cloth wears the style's cloth color")
	s.free()


func _inside_any(w: CastleWall, p: Vector3) -> bool:
	for b: Array in w.boxes:
		var xf: Transform3D = b[0]
		var size: Vector3 = b[1]
		var local: Vector3 = xf.affine_inverse() * p
		if absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5 and absf(local.z) <= size.z * 0.5:
			return true
	return false


func _run_world() -> void:
	var world: Node3D = (load("res://game/regents/town/town_world.tscn") as PackedScene).instantiate() as Node3D
	add_child(world)
	await get_tree().process_frame
	var places: Dictionary = world.get("settlements") as Dictionary
	_check(places.size() == 3 and places.has(&"village") and places.has(&"town") and places.has(&"castle"),
		"the world's three places: a village, a town, a castle")
	var counts: Array[int] = []
	for key: StringName in [&"village", &"town", &"castle"]:
		counts.append((places[key] as Settlement).buildings.size())
	_check(counts[0] >= 15 and counts[1] >= 60 and counts[2] >= 5, "village, town and castle full (%s)" % [counts])
	var inside: bool = true
	for key: Variant in places:
		for bld: Node3D in (places[key] as Settlement).buildings:
			var p: Vector3 = bld.global_position
			inside = inside and absf(p.x) < 500.0 and absf(p.z) < 500.0
	_check(inside, "every building inside the square kilometer")
	var walls: int = 0
	for key: Variant in places:
		for bld: Node3D in (places[key] as Settlement).buildings:
			if bld is CastleWall:
				walls += 1
	_check(walls >= 3, "the town's wall, the curtain and the keep are CastleWalls (%d)" % walls)
	var taken: Array = world.get("_taken") as Array
	var overlaps: Array[String] = []
	for i: int in taken.size():
		for j: int in range(i + 1, taken.size()):
			if (taken[i] as Rect2).intersects(taken[j] as Rect2):
				overlaps.append("%d:%s x %d:%s" % [i, taken[i], j, taken[j]])
	_check(overlaps.is_empty() and taken.size() > 30, "no two town houses overlap (%d footprints; %s)" % [taken.size(), overlaps])
	_check(int(world.get("trees")) > 200 and (world.get("roads") as Array).size() > 10, "woods and roads")
	# The streets: the town's and the castle's paved, each in its place's paving; again after the styles step.
	var places_paved: Array = world.get("street_places") as Array
	_check(places_paved.has(1) and places_paved.has(2) and (world.get("square_places") as Array).size() == 2,
		"the town's streets and the castle's road paved, the market and the yard squares")
	var ground: ShaderMaterial = world.get("_ground") as ShaderMaterial
	var paving: PackedVector4Array = ground.get_shader_parameter(&"paving")
	var want: Color = (places[&"town"] as Settlement).style.paving_color().srgb_to_linear()
	_check(Vector3(paving[1].x, paving[1].y, paving[1].z).is_equal_approx(Vector3(want.r, want.g, want.b)),
		"the town's paving is its style's")
	world.call("step_styles")
	paving = ground.get_shader_parameter(&"paving")
	want = (places[&"town"] as Settlement).style.paving_color().srgb_to_linear()
	_check(Vector3(paving[1].x, paving[1].y, paving[1].z).is_equal_approx(Vector3(want.r, want.g, want.b)),
		"and the next style's after S")
	# Furnished: every place has its props; the market's stalls, none on the kit's tower.
	var groups: Array = world.get("furnished") as Array
	var by_name: Dictionary[String, int] = {}
	var stalls: int = 0
	var on_tower: int = 0
	var tower := Rect2(Vector2(19, 14) - Vector2(3.5, 3.5), Vector2(7, 7))
	for gn: Variant in groups:
		var pg: PropGroup = gn as PropGroup
		by_name[String(pg.name)] = by_name.get(String(pg.name), 0) + 1
		if pg.name == &"Market":
			for c: Node in pg.get_children():
				var n3: Node3D = c as Node3D
				if n3 != null and n3.scene_file_path.contains("Stall_"):
					stalls += 1
					if tower.has_point(Vector2(n3.position.x, n3.position.z)):
						on_tower += 1
	_check(by_name.has("Market") and by_name.has("Green") and by_name.has("InnFront") and by_name.has("Yard")
		and by_name.has("Banners") and by_name.get("AtTheDoor", 0) > 60,
		"furnished: the market, the green, the inn, the yard, the banners, the doors (%s)" % [by_name])
	_check(stalls >= 20 and on_tower == 0, "the market's stalls (%d), none on the kit's tower" % stalls)
	world.free()


func _run_lab() -> void:
	var lab: Node3D = (load("res://game/regents/town/town_lab.tscn") as PackedScene).instantiate() as Node3D
	add_child(lab)
	await get_tree().process_frame
	var presets: int = _styles().size()
	_check((lab.get("sets") as Array).size() == presets, "the lab shows every preset's street (%d)" % presets)
	lab.call("show_mode", 2)
	_check((lab.get("sets") as Array).size() == 6, "six streets of one style, six seeds")
	lab.call("show_mode", 1)
	var style: SettlementStyle = lab.get("style") as SettlementStyle
	lab.call("_set_field", Color(0.9, 0.1, 0.1, 1.0), &"roof")
	var roof: ShaderMaterial = TownKit.material_for("MI_RoundTiles", style)
	_check((roof.get_shader_parameter(&"dye_a") as Color).is_equal_approx(Color(0.9, 0.1, 0.1, 1.0)),
		"the panel's change reaches the street's roofs")
	lab.call("show_mode", 3)
	_check((lab.get("sets") as Array).size() == presets, "one house in every preset")
	lab.call("show_mode", 0)
	var furnished: bool = true
	for st: Variant in lab.get("sets") as Array:
		furnished = furnished and (st as Node).find_children("Market", "PropGroup", true, false).size() == 1
	_check(furnished and (lab.get("streets") as Array).size() == presets, "every preset's street paved and furnished")
	lab.call("show_mode", 4)
	_check((lab.get("sets") as Array).size() == (lab.get("ROOF_TRIES") as Array).size(), "the roofs, side by side")
	lab.free()
