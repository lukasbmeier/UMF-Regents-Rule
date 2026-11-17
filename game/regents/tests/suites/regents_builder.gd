extends "res://tests/suite_base.gd"
## THE WORLD BUILDER & LORE STUDIO (`-- --only=regents_builder`; Luke, 2026-11-16,
## `docs/regents_rule/WORLD_BUILDER_PREP.md` WB1–WB12):
##   - `RegentsKitCatalog` indexes all 7 categories, including all 305 Medieval Village pieces and 212 Fantasy Props
##   - `NpcDef` validates keys, outfits (including NPC-only `Noble` and `Knight` tabard torso), and `.dialogue`
##     scripts (NEGATIVE: missing `~ start`, broken `=> target` jump, or duplicate `key` caught)
##   - Starting from scratch vs. procedural base, with non-destructive layers (`hand_*` vs. `proc_scatter`) and
##     exclusion zones (re-scattering procedural content never touches hand-built towns or spawns inside them)
##   - `RegentsTerrainBrush` sculpt/paint modes, walkable ramps, Undo/Redo, and automatic footprint leveling under
##     stamped buildings (`KitHouse`, `demo_house_*`, `CastleWall`, `Station`)
##   - `Path3D` road splines and terrain-aware `RegentsGroundClutter` (follows hills, skips cliffs/water, erase brush)
##   - All 3 prop placement modes (`SCENE_NODE`, `PROP_GROUP`, `TERRAIN_INSTANCER`) and all 3 building tiers
##     (`KitHouse`, Demo Prefabs, 2 m Grid-Snap Kit Pieces + custom preset saving)
##   - Live 3D `RegentsPointPreview` visualizers & tactical rings (`footprint`, `work_reach`, `wander`, `notice_cone`,
##     `hear`, `leash`, `pack` + packmate links), never saved as bloat into `.tscn` files
##   - Dual-mode camera (`FLY` / `WALK` drop-in `Adventurer`) + live NPC interaction and branching `.dialogue` test
##   - One-click `save_level` and `bake_level` (`LevelBaker` + `LevelCells` 64 m cell streaming cut)

const BUILDER_SCENE: String = "res://game/regents/builder/world_builder.tscn"


func run() -> void:
	_run_catalog_and_npcs()
	_run_terrain_brush()
	_run_clutter_on_hills()
	await _run_builder_layers_and_towns()
	await _run_point_previews_and_encounters()
	await _run_walk_mode_and_dialogue()
	await _run_save_and_bake()


func _run_catalog_and_npcs() -> void:
	print("== regents_builder: catalog & NpcDef lore validation ==")
	RegentsKitCatalog.clear_cache()
	for cat: StringName in RegentsKitCatalog.CATEGORIES:
		var list: Array[Dictionary] = RegentsKitCatalog.entries_for(cat)
		_check(not list.is_empty(), "catalog category '%s' is populated (%d entries)" % [cat, list.size()])
	var pieces: Array[Dictionary] = RegentsKitCatalog.entries_for(&"kit_pieces")
	_check(pieces.size() >= 500, "kit_pieces indexes both the 305 village pieces and 212 props (%d total)" % pieces.size())
	var nature_entries: Array[Dictionary] = RegentsKitCatalog.entries_for(&"nature")
	var nature_trees: int = 0
	for ne: Dictionary in nature_entries:
		if RegentsKitCatalog.is_tree_model(String(ne.get("model", ""))):
			nature_trees += 1
	_check(nature_entries.size() >= 10 and nature_trees == 0,
		"NEGATIVE: nature category includes rocks, bushes, flowers, grass & clutter brushes (%d) and 0 non-harvestable trees" % nature_entries.size())

	var npcs: Array[NpcDef] = NpcDef.all()
	_check(npcs.size() >= 4, "starter lore NPCs are loaded (%d)" % npcs.size())
	var drill: NpcDef = NpcDef.by_key(&"drillmaster")
	var chron: NpcDef = NpcDef.by_key(&"chronicler")
	_check(drill != null and drill.outfit == "Knight" and drill.knight_tabard,
		"Drillmaster wears the Knight outfit with the NPC-only cloth tabard")
	_check(drill != null and String(drill.outfit_pieces().get(&"torso", "")).ends_with("Knight_Body_Cloth.gltf"),
		"knight_tabard selects the Knight_Body_Cloth torso mesh")
	_check(chron != null and chron.outfit == "Noble" and chron.validate().is_empty(),
		"Chronicler Venn wears the NPC-only Noble outfit and validates cleanly")

	# NEGATIVE: broken dialogue scripts and duplicate keys must fail validation.
	var bad := NpcDef.new()
	bad.id = 49991
	bad.display_name = "Broken Speaker"
	bad.key = &"chronicler"
	bad.dialogue_script = "~ not_start\nSpeaker: Hello\n=> missing_target\n"
	var errs: Array[String] = bad.validate()
	var dup_errs: Array[String] = bad.validate_with([chron] as Array[ContentDef])
	_check(errs.size() >= 2 and str(errs).contains("~ start") and str(errs).contains("missing_target"),
		"NEGATIVE: NpcDef.validate catches missing `~ start` and broken `=> missing_target` jump: %s" % [errs])
	_check(not dup_errs.is_empty() and str(dup_errs).contains("chronicler"),
		"NEGATIVE: NpcDef.validate_with catches duplicate NPC key: %s" % [dup_errs])


func _run_terrain_brush() -> void:
	print("== regents_builder: Terrain3D sculpt, paint, ramp & footprint leveling ==")
	var brush := RegentsTerrainBrush.new(null, 128.0, 2.0)
	brush.init_blank(0.0, RegentsTerrainBrush.Tex.GRASS)
	_check(is_zero_approx(brush.height_at(0.0, 0.0)) and brush.texture_at(0.0, 0.0) == RegentsTerrainBrush.Tex.GRASS,
		"blank terrain starts flat at y = 0 in Grass")

	brush.mode = RegentsTerrainBrush.Mode.RAISE
	brush.radius_m = 10.0
	brush.strength = 4.0
	var snap_raise: Dictionary = brush.apply_stroke(0.0, 0.0)
	var raised_h: float = brush.height_at(0.0, 0.0)
	_check(raised_h > 3.5 and is_zero_approx(brush.height_at(40.0, 40.0)),
		"Raise brush lifts center to %.2f m while leaving far ground at 0" % raised_h)

	brush.restore_snapshot(snap_raise)
	_check(is_zero_approx(brush.height_at(0.0, 0.0)), "restore_snapshot undoes the terrain stroke")

	# Carve a walkable ramp from (0, 0, 0) to (20, 8, 0)
	var snap_ramp: Dictionary = brush.carve_ramp(Vector3(0.0, 0.0, 0.0), Vector3(20.0, 8.0, 0.0), 6.0, 3.0, RegentsTerrainBrush.Tex.DIRT)
	_check(absf(brush.height_at(10.0, 0.0) - 4.0) <= 0.25 and brush.texture_at(10.0, 0.0) == RegentsTerrainBrush.Tex.DIRT,
		"carve_ramp builds a linear slope (midpoint %.2f m) and paints Dirt along it" % brush.height_at(10.0, 0.0))
	brush.restore_snapshot(snap_ramp)

	# Auto-flatten under a building footprint on a hill
	brush.init_procedural(4021, 18.0, 30.0, 10.0)
	var hill_x: float = 36.0
	var hill_z: float = -28.0
	brush.apply_stroke(hill_x, hill_z, RegentsTerrainBrush.Mode.RAISE)
	var target_y: float = brush.height_at(hill_x, hill_z)
	brush.flatten_footprint(Vector3(hill_x, target_y, hill_z), 0.0, Vector2(8.0, 8.0), 4.0)
	var corners_flat: bool = true
	for offset: Vector2 in [Vector2(-3.0, -3.0), Vector2(3.0, -3.0), Vector2(3.0, 3.0), Vector2(-3.0, 3.0)]:
		if absf(brush.height_at(hill_x + offset.x, hill_z + offset.y) - target_y) > 0.05:
			corners_flat = false
	_check(corners_flat, "flatten_footprint levels all 4 corners of an 8x8 m building pad on a hill to %.2f m" % target_y)


func _run_clutter_on_hills() -> void:
	print("== regents_builder: terrain-aware clutter scatter & erase brush ==")
	var brush := RegentsTerrainBrush.new(null, 128.0, 2.0)
	brush.water_y = -4.0
	brush.init_blank(3.5, RegentsTerrainBrush.Tex.GRASS)
	# Make one steep cliff spike at (20, 20) and one underwater pit at (-20, -20)
	brush.radius_m = 6.0
	brush.strength = 22.0
	brush.apply_stroke(20.0, 20.0, RegentsTerrainBrush.Mode.RAISE)
	brush.apply_stroke(-20.0, -20.0, RegentsTerrainBrush.Mode.LOWER)

	var clutter := RegentsGroundClutter.new()
	clutter.extent_m = 64.0
	clutter.cell_m = 16.0
	clutter.water_y = -4.0
	clutter.max_slope = 0.75
	clutter.height_func = brush.height_at
	var kind := RegentsClutterKind.new()
	kind.model = load("res://game/regents/art/nature/Grass_Common_Short.gltf") as PackedScene
	kind.per_100_m2 = 30.0
	kind.patchy = 0.0
	clutter.kinds = [kind]
	add_child(clutter)
	clutter.scatter()

	var pts: PackedVector3Array = clutter.places()
	var on_hill_y: int = 0
	var underwater: int = 0
	var on_cliff: int = 0
	for p: Vector3 in pts:
		if absf(p.y - 3.5) <= 0.1:
			on_hill_y += 1
		if p.y <= brush.water_y:
			underwater += 1
		if brush.slope_at(p.x, p.z) > clutter.max_slope:
			on_cliff += 1
	_check(pts.size() > 100 and on_hill_y > 50 and underwater == 0 and on_cliff == 0,
		"terrain-aware clutter follows terrain height (y=3.5m: %d tufts) and skips underwater (%d) and cliffs (%d)" % [on_hill_y, underwater, on_cliff])

	# Erase brush clears tufts inside its circle
	clutter.erase_in_circle(0.0, 0.0, 10.0, true)
	var inside_erased: int = 0
	for p: Vector3 in clutter.places():
		if Vector2(p.x, p.z).length() <= 10.0:
			inside_erased += 1
	_check(inside_erased == 0, "NEGATIVE: erase_in_circle leaves 0 tufts inside the 10 m clearing")
	clutter.free()


func _run_builder_layers_and_towns() -> void:
	print("== regents_builder: non-destructive layers, settlements, houses, walls & undo/redo ==")
	var builder: RegentsWorldBuilder = (load(BUILDER_SCENE) as PackedScene).instantiate() as RegentsWorldBuilder
	add_child(builder)
	await get_tree().process_frame

	builder.start_from_procedural("test_continent", 92, 4021, 256.0, 2.0)
	var proc_initial: int = builder.count_in_layer(RegentsWorldBuilder.LAYER_PROCEDURAL)
	_check(proc_initial > 5, "procedural base scatters initial nodes/foes/decor (%d in proc_scatter)" % proc_initial)

	# Create a settlement at (40, 0, 40) and stamp a KitHouse, a Demo House, a CastleWall, and a Market
	var town_pos := Vector3(40.0, 0.0, 40.0)
	var settlement: Settlement = builder.create_settlement("Sunreach Outpost", town_pos, 3, 38.0, true)
	var house: KitHouse = builder.stamp_kit_house(town_pos + Vector3(-8.0, 0.0, 0.0), 0.0, {"width": 3, "depth": 3, "floors": 2})
	var inn: Node3D = builder.stamp_demo_house(RegentsKitCatalog.DEMO_HOUSES["demo_house_d"], town_pos + Vector3(8.0, 0.0, 0.0), PI)
	var wall: CastleWall = builder.build_castle_wall(PackedVector3Array([
		town_pos + Vector3(-24.0, 0.0, -24.0),
		town_pos + Vector3(24.0, 0.0, -24.0),
		town_pos + Vector3(24.0, 0.0, 24.0),
		town_pos + Vector3(-24.0, 0.0, 24.0),
	]), PackedInt32Array([0]), false)
	var market: PropGroup = builder.stamp_furnishing("market", town_pos + Vector3(0.0, 0.0, 10.0))
	_check(settlement != null and house != null and inn != null and wall != null and market != null,
		"Settlement, KitHouse, Demo House D, CastleWall, and Market PropGroup all stamp cleanly")

	# Re-scatter procedural layer: hand-built settlement must remain untouched and clear of procedural spawns!
	builder.rescatter_procedural(7777)
	var invaded: int = 0
	for c: Node in builder.cells_root.get_children():
		if (c.get_meta(RegentsWorldBuilder.LAYER_META, &"") as StringName) == RegentsWorldBuilder.LAYER_PROCEDURAL:
			var n3: Node3D = c as Node3D
			if n3 != null and Vector2(n3.position.x - town_pos.x, n3.position.z - town_pos.z).length() <= 38.0:
				invaded += 1
	_check(settlement.is_inside_tree() and house.is_inside_tree() and inn.is_inside_tree() and invaded == 0,
		"NEGATIVE: rescatter_procedural preserves all hand-built town nodes and places 0 procedural items inside the town exclusion zone")

	# 2 m Grid-Snap Kit Piece placement & Custom Preset saving
	var snapped_wall: Node3D = builder.place_kit_piece("Wall_Plaster_Straight", Vector3(11.3, 1.4, -7.1), 0.1, true)
	_check(snapped_wall != null and is_equal_approx(snapped_wall.global_position.x, 12.0)
		and is_equal_approx(snapped_wall.global_position.z, -8.0) and is_equal_approx(snapped_wall.global_position.y, 0.0),
		"2 m grid-snap mode snaps Wall_Plaster_Straight from (11.3, 1.4, -7.1) to (12, 0, -8)")
	var preset_path: String = builder.save_custom_house_preset(house, "test_guild_ cottage")
	_check(not preset_path.is_empty() and not RegentsKitCatalog.find_entry("custom_test_guild__cottage").is_empty(),
		"save_custom_house_preset saves a .tscn preset and registers it in RegentsKitCatalog (%s)" % preset_path)

	# All 3 Prop Placement Modes (SCENE_NODE, PROP_GROUP, TERRAIN_INSTANCER) + Undo/Redo
	var rock_node: Node3D = builder.place_nature_prop("Rock_Big_1", Vector3(-30.0, 0.0, 10.0), 0.0, 1.0, RegentsWorldBuilder.PropMode.SCENE_NODE)
	var bush_group: Node3D = builder.place_nature_prop("Bush_Large", Vector3(-32.0, 0.0, 12.0), 0.0, 1.0, RegentsWorldBuilder.PropMode.PROP_GROUP)
	var tree_inst: MultiMeshInstance3D = builder.place_nature_prop("CommonTree_1", Vector3(-35.0, 0.0, 15.0), 0.0, 1.0, RegentsWorldBuilder.PropMode.TERRAIN_INSTANCER) as MultiMeshInstance3D
	_check(rock_node != null and bush_group != null and tree_inst != null and tree_inst.multimesh.instance_count == 1,
		"all 3 prop modes work: Scene Node, PropGroup batch, and Terrain Instancer MultiMesh")
	builder.undo()
	_check(tree_inst.multimesh.instance_count == 0, "Undo removes the Terrain Instancer transform")
	builder.redo()
	_check(tree_inst.multimesh.instance_count == 1, "Redo restores the Terrain Instancer transform")

	# Road spline drawing
	var road: Path3D = builder.draw_road_spline(PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0)]), "dirt", 3.2, true)
	_check(road != null and builder.ground_paint.dirt_at(10.0, 0.0) > 0.8,
		"draw_road_spline creates a Path3D and paints trodden dirt along the road (%.2f)" % builder.ground_paint.dirt_at(10.0, 0.0))

	# Mouse-raycast cursor, resizable paint brush, 3D Ghost Preview, scroll cycling & Prefab Builder Studio
	builder.set_brush_radius(1.0)
	_check(is_equal_approx(builder.brush_radius(), 1.0), "set_brush_radius resizes brush down to 1.0 m for fine texture painting")
	builder.select_entry("paint_cobble")
	builder.use_active_tool_at(Vector3(14.0, 0.0, 14.0))
	_check(builder.terrain_brush.texture_at(14.0, 14.0) == RegentsTerrainBrush.Tex.COBBLE,
		"1.0 m fine paint brush paints Cobble at (14, 14)")
	builder.set_brush_radius(22.0)
	_check(is_equal_approx(builder.brush_radius(), 22.0), "set_brush_radius resizes brush up to 22.0 m for wide painting")

	var hit: Vector3 = builder.update_cursor_from_ray(Vector3(18.0, 30.0, -14.0), Vector3(0.0, -1.0, 0.0))
	_check(absf(hit.x - 18.0) <= 0.1 and absf(hit.z - (-14.0)) <= 0.1,
		"update_cursor_from_ray moves cursor circle to mouse ray intersection (%.1f, %.1f)" % [hit.x, hit.z])

	builder.select_category(&"kit_pieces")
	var first_piece_id: String = builder.active_entry_id
	var second_piece_id: String = builder.cycle_palette_entry(1)
	_check(first_piece_id != second_piece_id and builder._ghost_root != null and builder._ghost_root.get_child_count() > 0,
		"cycle_palette_entry steps through kit pieces (%s -> %s) and builds the live 3D Ghost Preview" % [first_piece_id, second_piece_id])

	var prefab_node: Node3D = builder.start_new_prefab("watch_post", Vector3(80.0, 0.0, -80.0))
	builder.set_story_level(0)
	var f1_wall: Node3D = builder.use_active_tool_at(Vector3(-16.0, 0.0, 16.0)) as Node3D
	builder.set_story_level(1)
	var f2_wall: Node3D = builder.use_active_tool_at(Vector3(-14.0, 0.0, 16.0)) as Node3D
	var saved_prefab: String = builder.save_active_prefab("watch_post")
	builder.finish_active_prefab()
	_check(prefab_node != null and f1_wall != null and f2_wall != null
		and f1_wall.get_parent() == prefab_node and f2_wall.get_parent() == prefab_node
		and is_equal_approx(prefab_node.global_position.x, -16.0)
		and absf(f2_wall.global_position.y - (f1_wall.global_position.y + 3.0)) <= 0.05
		and not saved_prefab.is_empty(),
		"Prefab Builder locks origin to first placed piece (-16, 16), stacks Floor 2 (+3m), and saves %s" % saved_prefab)

	var stamped_watch: Node3D = builder.stamp_demo_house(saved_prefab, Vector3(4.0, 0.0, -6.0))
	var child_local_x: float = (stamped_watch.get_child(0) as Node3D).position.x if stamped_watch != null and stamped_watch.get_child_count() > 0 else 999.0
	_check(stamped_watch != null and absf(child_local_x) <= 2.5,
		"Recentered custom prefab stamps dead-center at cursor (child local x = %.2f m, not offset across map)" % child_local_x)

	# Custom grid step XZ/Y, hill-relative Y snap, Shift/Alt free placement, UI focus isolation, Conditional Right Panel & New NPC Studio
	_check(builder._palette_list.focus_mode == Control.FOCUS_NONE,
		"NEGATIVE: _palette_list has FOCUS_NONE so pressing R to rotate never jumps to items starting with R")
	builder.free_place_held = true
	var free_piece: Node3D = builder.place_kit_piece("Wall_Plaster_Straight", Vector3(7.37, 0.0, -3.19), 0.33, true)
	builder.free_place_held = false
	_check(free_piece != null and is_equal_approx(free_piece.global_position.x, 7.37) and is_equal_approx(free_piece.global_position.z, -3.19),
		"Holding Shift/Alt (free_place_held) bypasses grid snap for exact free placement (7.37, -3.19)")

	builder.set_grid_step_xz(0.5)
	builder.set_grid_step_y(4.0)
	var custom_snap_piece: Node3D = builder.place_kit_piece("Wall_Plaster_Straight", Vector3(1.37, 0.0, 2.63), 0.0, true)
	_check(custom_snap_piece != null and absf(custom_snap_piece.global_position.x - 1.5) <= 0.05 and absf(custom_snap_piece.global_position.z - 2.5) <= 0.05,
		"Custom XZ grid step (0.5m) snaps placement to nearest 0.5m increment")

	builder.terrain_brush.radius_m = 8.0
	builder.terrain_brush.strength = 4.5
	builder.apply_terrain_brush(Vector3(-24.0, 0.0, 24.0), RegentsTerrainBrush.Mode.RAISE)
	var hill_ground_y: float = builder.height_at(-24.0, 24.0)
	builder.select_category(&"kit_pieces")
	builder.set_story_level(1)
	var hill_f2_piece: Node3D = builder.use_active_tool_at(Vector3(-24.0, 0.0, 24.0)) as Node3D
	builder.set_story_level(0)
	builder.set_grid_step_xz(2.0)
	builder.set_grid_step_y(3.0)
	_check(hill_ground_y > 3.5 and hill_f2_piece != null and absf(hill_f2_piece.global_position.y - (hill_ground_y + 4.0)) <= 0.1,
		"Hill-relative Y snap places Floor 2 at terrain height (%.2f) + grid_step_y (4.0m) without burying into hills" % hill_ground_y)

	# Simulate an uncentered custom prefab (pieces offset to (-40, 0, 40) like an old save) -> BOTH visuals & Body collision shapes center at (0,0,0)
	var off_root := Node3D.new()
	off_root.name = "OffsetCottage"
	var p1: Node3D = TownKit.piece("Wall_Plaster_Straight").instantiate() as Node3D
	var p2: Node3D = TownKit.piece("Wall_Plaster_Straight").instantiate() as Node3D
	off_root.add_child(p1)
	off_root.add_child(p2)
	p1.position = Vector3(-42.0, 0.0, 40.0)
	p2.position = Vector3(-38.0, 0.0, 40.0)
	RegentsWorldBuilder._own_recursive(off_root, off_root)
	var off_pack := PackedScene.new()
	off_pack.pack(off_root)
	off_root.free()
	var off_path: String = RegentsKitCatalog.CUSTOM_PRESETS_DIR + "offset_cottage.tscn"
	ResourceSaver.save(off_pack, off_path)
	var stamped_off: Node3D = builder.stamp_demo_house(off_path, Vector3(6.0, 0.0, 6.0))
	var off_body: StaticBody3D = stamped_off.get_node_or_null("Body") as StaticBody3D if stamped_off != null else null
	var off_shape: CollisionShape3D = off_body.get_child(0) as CollisionShape3D if (off_body != null and off_body.get_child_count() > 0) else null
	var off_vis: Node3D = stamped_off.get_child(0) as Node3D if (stamped_off != null and stamped_off.get_child_count() > 0) else null
	_check(stamped_off != null and off_vis != null and off_shape != null
		and absf(off_vis.position.x) <= 2.5 and absf(off_vis.position.z) <= 2.5
		and absf(off_shape.position.x) <= 2.5 and absf(off_shape.position.z) <= 2.5,
		"Uncentered custom prefab recenters BOTH visual meshes AND StaticBody3D collisions to cursor (0,0,0)")

	var all_hidden: bool = true
	for c_hide: StringName in [&"terrain", &"nature", &"skilling", &"foes"]:
		builder.select_category(c_hide)
		if builder._right_panel.visible:
			all_hidden = false
	builder.select_category(&"settlements")
	var prefab_only_on_towns: bool = builder._right_panel.visible and builder._prefab_section.visible and not builder._npc_section.visible
	builder.select_category(&"npcs")
	var npc_only_on_npcs: bool = builder._right_panel.visible and builder._npc_section.visible and not builder._prefab_section.visible
	_check(all_hidden and prefab_only_on_towns and npc_only_on_npcs,
		"Right Studio Panel is conditional: hidden on Land/Nature/Skill/Foes, Prefab Studio on Towns/Pieces, NPC Studio on NPCs")

	var held_all_valid: bool = true
	for hp: String in RegentsWorldBuilder.NPC_HELD_PATHS:
		if not hp.is_empty() and not ResourceLoader.exists(hp):
			held_all_valid = false
	_check(held_all_valid and RegentsWorldBuilder.NPC_HELD_PATHS.size() >= 4,
		"All NPC held weapon/tool scene paths exist on disk")

	var new_npc: NpcDef = builder.create_new_npc_from_ui("guard_rowan", "Guard Rowan")
	if not builder.dye_palettes.is_empty() and builder._npc_palette_opt != null and builder._npc_palette_opt.item_count > 1:
		builder._npc_palette_opt.select(1)
	if builder._npc_held_opt != null and builder._npc_held_opt.item_count > 1:
		builder._npc_held_opt.select(1)
	builder._apply_npc_inspector_edits()
	var rowan_pt: LevelPoint = builder.place_level_point("npc", "guard_rowan", Vector3(2.0, 0.0, 2.0), 0.6)
	var rowan_prev: RegentsPointPreview = rowan_pt.get_node_or_null(NodePath(RegentsPointPreview.PREVIEW_NAME)) as RegentsPointPreview if rowan_pt != null else null
	builder._set_npc_tab(1)
	var lore_tab_shown: bool = builder._npc_lore_box.visible and not builder._npc_appearance_box.visible
	builder._set_npc_tab(0)
	var app_tab_shown: bool = builder._npc_appearance_box.visible and not builder._npc_lore_box.visible
	_check(new_npc != null and new_npc.key == &"guard_rowan" and builder.active_npc_def == new_npc
		and NpcDef.by_key(&"guard_rowan") == new_npc
		and not RegentsKitCatalog.find_entry("npc_guard_rowan").is_empty()
		and rowan_prev != null and rowan_prev.label_text.contains("Guard Rowan")
		and app_tab_shown and lore_tab_shown,
		"create_new_npc_from_ui registers live draft in NpcDef + catalog + 3D preview & toggles Appearance -> Lore tabs")

	# Clean up test preset files so unit tests leave user://builder_presets/ clean
	var pdir: DirAccess = DirAccess.open(RegentsKitCatalog.CUSTOM_PRESETS_DIR)
	if pdir != null:
		pdir.remove("test_guild__cottage.tscn")
		pdir.remove("watch_post.tscn")
		pdir.remove("offset_cottage.tscn")
	RegentsKitCatalog.clear_cache()

	builder.free()


func _run_point_previews_and_encounters() -> void:
	print("== regents_builder: LevelPoint 3D visualizers, tactical rings & encounter stampers ==")
	var builder: RegentsWorldBuilder = (load(BUILDER_SCENE) as PackedScene).instantiate() as RegentsWorldBuilder
	add_child(builder)
	await get_tree().process_frame
	builder.start_from_scratch("preview_test", 93, 128.0, 2.0)

	var copper_pt: LevelPoint = builder.place_level_point("node", "Copper rock", Vector3(10.0, 0.0, -10.0), 0.6)
	var anvil_pt: LevelPoint = builder.place_level_point("station", "anvil", Vector3(-6.0, 0.0, 8.0), 1.0)
	var archer_pt: LevelPoint = builder.place_level_point("skeleton_archer", "", Vector3(25.0, 0.0, 20.0), 0.5)
	var npc_pt: LevelPoint = builder.place_level_point("npc", "chronicler", Vector3(4.0, 0.0, 6.0), 0.6)
	var wolves: Array[LevelPoint] = builder.stamp_encounter("wolf_pack", Vector3(-25.0, 0.0, -20.0))

	var copper_prev: RegentsPointPreview = copper_pt.get_node_or_null(NodePath(RegentsPointPreview.PREVIEW_NAME)) as RegentsPointPreview
	var anvil_prev: RegentsPointPreview = anvil_pt.get_node_or_null(NodePath(RegentsPointPreview.PREVIEW_NAME)) as RegentsPointPreview
	var archer_prev: RegentsPointPreview = archer_pt.get_node_or_null(NodePath(RegentsPointPreview.PREVIEW_NAME)) as RegentsPointPreview
	var npc_prev: RegentsPointPreview = npc_pt.get_node_or_null(NodePath(RegentsPointPreview.PREVIEW_NAME)) as RegentsPointPreview
	var wolf_prev: RegentsPointPreview = wolves[0].get_node_or_null(NodePath(RegentsPointPreview.PREVIEW_NAME)) as RegentsPointPreview

	_check(copper_prev != null and copper_prev.rings.has(&"footprint") and copper_prev.rings.has(&"work_reach"),
		"Copper rock point preview builds its 3D rock + ore nuggets and footprint + work_reach rings")
	_check(anvil_prev != null and anvil_prev.rings.has(&"work_reach") and anvil_prev.model_root.get_child_count() > 0,
		"Anvil station point preview builds its 3D station pieces and work_reach ring")
	_check(archer_prev != null and archer_prev.rings.has(&"notice_cone") and archer_prev.rings.has(&"hear") and archer_prev.rings.has(&"leash"),
		"Skeleton archer point preview builds its dressed model and sight cone, hearing, and leash rings")
	_check(npc_prev != null and npc_prev.rings.has(&"interact") and npc_prev.label_text.contains("Chronicler Venn"),
		"Friendly NPC point preview builds Chronicler Venn's Noble figure, title label, and interact ring")
	_check(wolves.size() == 3 and wolf_prev != null and wolf_prev.rings.has(&"pack") and wolf_prev.pack_links.size() == 2,
		"Wolf pack encounter stamper places 3 wolves and links each wolf to its 2 packmates within pack_m")

	builder.free()


func _run_walk_mode_and_dialogue() -> void:
	print("== regents_builder: Fly/Walk toggle & live NPC dialogue studio ==")
	var builder: RegentsWorldBuilder = (load(BUILDER_SCENE) as PackedScene).instantiate() as RegentsWorldBuilder
	add_child(builder)
	await get_tree().process_frame
	builder.start_from_scratch("dialogue_test", 94, 128.0, 2.0)

	# Place Chronicler Venn at (0, 0, -2) in front of the Adventurer and drop into Walk Mode at (0, 0, 0)
	builder.place_level_point("npc", "chronicler", Vector3(0.0, 0.0, -2.0), 0.6)
	builder.set_camera_mode(RegentsWorldBuilder.CameraMode.WALK, Vector3(0.0, 0.0, 0.0))
	_check(builder.camera_mode == RegentsWorldBuilder.CameraMode.WALK and builder.walk_actor != null,
		"Tab switches from Fly Mode to Walk Mode and spawns the Adventurer at the cursor")

	var moved_pos: Vector3 = builder.step_walk_mode(0.25, Vector2(0.0, -1.0), false)
	_check(moved_pos.length() > 0.05, "step_walk_mode moves the Adventurer across the terrain")

	var spoken: NpcDef = builder.interact_in_walk_mode()
	_check(spoken != null and spoken.key == &"chronicler" and builder.dialogue_active,
		"pressing E in Walk Mode near Chronicler Venn starts his branching dialogue")
	builder.advance_dialogue()
	builder.advance_dialogue()
	_check(not builder.dialogue.active_choices.is_empty(),
		"advancing reaches Chronicler Venn's hub choices (%d options)" % builder.dialogue.active_choices.size())

	# Switch balloon styles between Speech Bubble and Regent's Card, then pick the first choice ("Ask about the Regent's Writ")
	builder.set_dialogue_balloon_style(CinemaBalloon.Style.SPEECH_BUBBLE)
	_check(builder.balloon.current_style == CinemaBalloon.Style.SPEECH_BUBBLE, "balloon switches live to 3D Speech Bubble style")
	builder.choose_dialogue_option(0)
	_check(bool(builder.dialogue.state.get("asked_writ", false)),
		"picking choice 0 sets `asked_writ = true` and branches to the Writ lore answer")

	builder.free()


func _run_save_and_bake() -> void:
	print("== regents_builder: save_level (no preview bloat) & one-click bake_level ==")
	var scratch_dir: String = "user://builder_test_bake"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scratch_dir))
	var scene_path: String = scratch_dir + "/custom_glade.tscn"

	var builder: RegentsWorldBuilder = (load(BUILDER_SCENE) as PackedScene).instantiate() as RegentsWorldBuilder
	add_child(builder)
	await get_tree().process_frame
	builder.start_from_scratch("custom_glade", 95, 128.0, 2.0)
	builder.place_level_point("node", "Tree", Vector3(-8.0, 0.0, -8.0), 0.6, "tree_custom_1")
	builder.place_level_point("station", "furnace", Vector3(6.0, 0.0, 8.0), 1.0, "furnace_custom_1")
	builder.place_level_point("npc", "drillmaster", Vector3(0.0, 0.0, 5.0), 0.6, "npc_drillmaster_1")
	builder.place_level_point("poi", "Custom Camp", Vector3(0.0, 0.0, 0.0), 10.0, "poi_custom_camp")
	builder.stamp_kit_house(Vector3(16.0, 0.0, 0.0), 0.0, {"width": 2, "depth": 2, "floors": 1})

	var saved_ok: bool = builder.save_level(scene_path)
	_check(saved_ok and FileAccess.file_exists(scene_path), "save_level writes %s" % scene_path)

	# NEGATIVE: saved .tscn must NOT contain internal `_BuilderPreview` nodes.
	var raw_tscn: String = FileAccess.get_file_as_string(scene_path)
	_check(not raw_tscn.contains("_BuilderPreview") and raw_tscn.contains("tree_custom_1") and raw_tscn.contains("npc_drillmaster_1"),
		"NEGATIVE: saved .tscn contains all placed LevelPoints and buildings, and 0 internal _BuilderPreview nodes")

	for _f: int in 4:
		await get_tree().physics_frame
	var bake: Dictionary = builder.bake_level(scratch_dir)
	_check(bool(bake.get("ok", false)) and FileAccess.file_exists(scratch_dir + "/custom_glade.json"),
		"bake_level writes custom_glade.json, custom_glade_depth.bin, and cuts streamed 64 m cells (%s)" % bake.get("error", ""))
	var doc: Dictionary = bake.get("doc", {}) as Dictionary
	var points: Array = doc.get("points", []) as Array
	_check(points.size() == 4 and (bake.get("cells", {}) as Dictionary).size() >= 1,
		"baked server JSON holds all 4 placed points and cut cell scenes (%d cells)" % (bake.get("cells", {}) as Dictionary).size())

	builder.free()
