class_name RegentsWorldBuilder extends Node3D
## THE WORLD BUILDER & LORE STUDIO ("HYPIXEL CREATIVE MODE", `res://game/regents/builder/world_builder.tscn`, F6).
## Built per `docs/regents_rule/WORLD_BUILDER_PREP.md` (WB1–WB12):
##   - Start from scratch (blank `Terrain3D`), from a procedural base, or open an existing level (`frontier.tscn`).
##   - Non-destructive scene layers (`hand_settlements`, `hand_props`, `hand_gameplay`, `proc_scatter`) and
##     exclusion zones so re-running procedural scatter never wipes hand-built towns, roads, or quest camps.
##   - Dual-mode camera (`Tab`): Free-Fly Creative Mode (`WASD/QE`, scroll speed/yaw, 3D surface cursor & ghost)
##     and Drop-In Walk Mode (spawns your real `Adventurer` at the cursor to walk, jump, and press `E` on NPCs).
##   - Terrain3D sculpt/paint brushes (`RegentsTerrainBrush`), walkable ramps, road splines (`Path3D`), terrain-aware
##     MultiMesh clutter scatter/erase (`RegentsGroundClutter`), and automatic footprint leveling under buildings.
##   - Three mesh placement modes (`PropMode`: Cell Scene Node with `RegentsSolidProps`, `PropGroup` batch, and
##     `Terrain3D` MultiMesh Instancer) and three building tiers (parametric `KitHouse`, preset/demo houses, and
##     2 m grid-snap kit piece assembly + custom preset saving), plus click-to-draw `CastleWall` & Keep.
##   - Live 3D previews and tactical rings on every `LevelPoint` (`RegentsPointPreview`), friendly lore NPCs
##     (`NpcDef`), embedded `.dialogue` editor & live conversation tester (`CinemaDialogue` + `CinemaBalloon`),
##     World Map POI integration (`RegentsWorldMap`), Undo/Redo stack (`Ctrl+Z` / `Ctrl+Y`), and one-click
##     Save & Server Bake (`LevelBaker` + `LevelCells`) with a "What the Server Sees" overlay (`F2`).

enum CameraMode {
	FLY,
	WALK,
}

enum PropMode {
	SCENE_NODE,
	PROP_GROUP,
	TERRAIN_INSTANCER,
}

const LAYER_SETTLEMENTS: StringName = &"hand_settlements"
const LAYER_PROPS: StringName = &"hand_props"
const LAYER_GAMEPLAY: StringName = &"hand_gameplay"
const LAYER_PROCEDURAL: StringName = &"proc_scatter"
const LAYER_META: StringName = &"builder_layer"

const STYLES_DIR: String = "res://game/regents/town/styles/"
const DRESSING_PATH: String = "res://game/regents/town/dressing/village.tres"
const DEF_ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const DEF_GUIDE: EntityDefinition = preload("res://game/regents/content/character/guide.tres")
const SHADER_GROUND: Shader = preload("res://game/regents/levels/glade_ground.gdshader")

## Active world & level nodes
var level_root: Node3D = null
var level_info: LevelInfo = null
var cells_root: Node3D = null
var spawn_marker: LevelSpawn = null
var terrain: Terrain3D = null
var terrain_brush: RegentsTerrainBrush = null
var ground_paint: RegentsGroundPaint = null
var ground_clutter: RegentsGroundClutter = null
var solid_props: RegentsSolidProps = null
var instancer_root: Node3D = null

## Camera & player walk-test state
var camera_mode: CameraMode = CameraMode.FLY
var camera: Camera3D = null
var walk_actor: ShowcaseActor = null
var fly_speed: float = 28.0
var _yaw: float = 0.0
var _pitch: float = -0.35
var _looking: bool = false

## Cursor, active tool & placement settings
var active_category: StringName = &"settlements"
var active_group_filter: String = ""
var active_entry_id: String = "kit_townhouse"
var prop_mode: PropMode = PropMode.SCENE_NODE
var cursor_pos: Vector3 = Vector3.ZERO
var cursor_normal: Vector3 = Vector3.UP
var place_yaw: float = 0.0
var place_scale: float = 1.0
var story_level: int = 0
var snap_grid: bool = true
var grid_step_xz: float = 2.0
var grid_step_y: float = 3.0
var free_place_held: bool = false
var align_to_normal: bool = false
var auto_flatten_footprints: bool = true
var show_gizmo_rings: bool = true
var show_server_overlay: bool = false

const GRID_STEPS: Array[float] = [0.0, 0.25, 0.5, 1.0, 2.0, 4.0]
const GRID_STEP_LABELS: PackedStringArray = ["Snap: Free (Off)", "Snap: 0.25m", "Snap: 0.5m", "Snap: 1.0m", "Snap: 2.0m", "Snap: 4.0m", "Snap: Custom"]
const NPC_HELD_LABELS: PackedStringArray = ["No Held Item", "Iron Sword", "Yew Bow", "Yew Staff", "Smith's Hammer", "Mining Pickaxe", "Iron Hatchet", "Woodcutter's Axe"]
const NPC_HELD_PATHS: PackedStringArray = [
	"",
	"res://game/regents/combat/weapons/iron_sword.tscn",
	"res://game/regents/combat/weapons/yew_bow.tscn",
	"res://game/regents/combat/weapons/yew_staff.tscn",
	"res://game/regents/skilling/smithing/hammer.tscn",
	"res://game/regents/skilling/mining/pickaxe.tscn",
	"res://game/regents/skilling/woodcutting/iron_axe.tscn",
	"res://game/regents/skilling/woodcutting/axe.tscn",
]
const NPC_HAIR_LABELS: PackedStringArray = ["Hair: None", "Hair: Parted", "Hair: Long", "Hair: Buns", "Hair: Buzzed"]
const NPC_BEARD_LABELS: PackedStringArray = ["Beard: None", "Beard: Full", "Beard: Moustache", "Beard: Chops"]
const NPC_SKIN_LABELS: PackedStringArray = ["Skin: Light", "Skin: Dark"]

## Active Settlement, Custom Prefab Group & KitHouse / CastleWall parameters
var active_settlement: Settlement = null
var active_prefab_root: Node3D = null
var _prefab_origin_locked: bool = false
var _picking_prefab_origin: bool = false
var settlement_styles: Array[SettlementStyle] = []
var dye_palettes: Array[DyePalette] = []
var house_width: int = 3
var house_depth: int = 3
var house_floors: int = 2
var house_ground: KitHouse.Finish = KitHouse.Finish.UNEVEN_BRICK
var house_upper: KitHouse.Finish = KitHouse.Finish.PLASTER
var house_tiles: KitHouse.Tiles = KitHouse.Tiles.ROUND
var house_seed: int = 101
var wall_draft_corners: PackedVector3Array = PackedVector3Array()
var road_draft_points: PackedVector3Array = PackedVector3Array()
var ramp_start_point: Vector3 = Vector3.INF

## Selected node & NPC Dialogue / Lore Studio
var selected_node: Node3D = null
var active_npc_def: NpcDef = null
var dialogue: CinemaDialogue = CinemaDialogue.new()
var balloon: CinemaBalloon = null
var dialogue_active: bool = false
var last_dialogue_action: String = ""
var last_bake_result: Dictionary = {}

## Exclusion zones `(world_x, radius_m, world_z)` where procedural scatter never places anything.
var exclusion_zones: PackedVector3Array = PackedVector3Array()
## MultiMesh batches created in `PropMode.TERRAIN_INSTANCER`: `model_name -> MultiMeshInstance3D`.
var instancer_batches: Dictionary[String, MultiMeshInstance3D] = {}
var _instancer_xforms: Dictionary[String, Array] = {}

## Undo / Redo command stacks & continuous brush stroke state
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _point_counters: Dictionary[String, int] = {}
var _painting_drag: bool = false
var _stroke_before_snap: Dictionary = {}

## 3D Overlays (cursor, ghost preview, active prefab box, server view)
var _overlay_root: Node3D = null
var _cursor_ring: MeshInstance3D = null
var _ghost_root: Node3D = null
var _prefab_box_node: MeshInstance3D = null
var _server_overlay_node: Node3D = null
var _sun: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null

## UI Elements
var _ui_layer: CanvasLayer = null
var _top_bar: PanelContainer = null
var _status_label: Label = null
var _brush_radius_slider: HSlider = null
var _brush_radius_label: Label = null
var _brush_strength_slider: HSlider = null
var _brush_strength_label: Label = null
var _left_split: HSplitContainer = null
var _right_split: HSplitContainer = null
var _left_panel: PanelContainer = null
var _right_panel: PanelContainer = null
var _category_box: HBoxContainer = null
var _group_filter_opt: OptionButton = null
var _palette_list: ItemList = null
var _palette_entries: Array[Dictionary] = []
var _search_edit: LineEdit = null
var _inspector_box: VBoxContainer = null
var _prefab_section: VBoxContainer = null
var _npc_section: VBoxContainer = null
var _grid_snap_opt: OptionButton = null
var _grid_xz_spin: SpinBox = null
var _grid_y_spin: SpinBox = null
var _prefab_name_edit: LineEdit = null
var _prefab_status_label: Label = null
var _story_label: Label = null
var _npc_tab_idx: int = 0
var _npc_appearance_box: VBoxContainer = null
var _npc_lore_box: VBoxContainer = null
var _npc_new_name_edit: LineEdit = null
var _npc_key_edit: LineEdit = null
var _npc_name_edit: LineEdit = null
var _npc_title_edit: LineEdit = null
var _npc_body_opt: OptionButton = null
var _npc_outfit_opt: OptionButton = null
var _npc_palette_opt: OptionButton = null
var _npc_tabard_chk: CheckBox = null
var _npc_extras_chk: CheckBox = null
var _npc_hair_opt: OptionButton = null
var _npc_beard_opt: OptionButton = null
var _npc_skin_opt: OptionButton = null
var _npc_hair_color_btn: ColorPickerButton = null
var _npc_held_opt: OptionButton = null
var _npc_wander_slider: HSlider = null
var _npc_poi_chk: CheckBox = null
var _npc_lore_edit: TextEdit = null
var _npc_dialogue_edit: TextEdit = null
var _npc_validation_label: Label = null
var _world_map: RegentsWorldMap = null


func _ready() -> void:
	_load_settlement_styles()
	_build_environment()
	_build_overlays()
	_build_ui()
	dialogue.line_started.connect(_on_dialogue_line)
	dialogue.choices_presented.connect(_on_dialogue_choices)
	dialogue.action_triggered.connect(func(act: String, arg: String) -> void:
		last_dialogue_action = "%s(%s)" % [act, arg])
	dialogue.dialogue_ended.connect(_on_dialogue_ended)
	if level_root == null:
		start_from_scratch("builder_world", 90, 256.0, 2.0)
	select_category(&"settlements")


func _load_settlement_styles() -> void:
	settlement_styles.clear()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(STYLES_DIR)):
		var files: PackedStringArray = DirAccess.get_files_at(STYLES_DIR)
		files.sort()
		for f: String in files:
			if f.ends_with(".tres") and not f.begins_with("custom_"):
				var s: SettlementStyle = load(STYLES_DIR + f) as SettlementStyle
				if s != null:
					settlement_styles.append(s)
	dye_palettes.clear()
	for r: Resource in Wardrobe.load_all(Wardrobe.PALETTES):
		var dp: DyePalette = r as DyePalette
		if dp != null:
			dye_palettes.append(dp)


# =============================================================================================
# 1. WORLD INITIALIZATION: SCRATCH, PROCEDURAL BASE, OR EXISTING LEVEL (WB1, WB3)
# =============================================================================================

## Start a brand-new level from scratch with a flat `Terrain3D` canvas, `LevelInfo`, `Cells`, `GroundPaint`,
## `GroundClutter`, and `SolidProps`.
func start_from_scratch(p_level_name: String = "custom_world", p_level_id: int = 90,
		extent_m: float = 256.0, vertex_spacing: float = 2.0) -> Node3D:
	_clear_current_level()
	level_root = Node3D.new()
	level_root.name = p_level_name.capitalize().replace(" ", "")
	add_child(level_root)

	level_info = LevelInfo.new()
	level_info.name = "LevelInfo"
	level_info.level_name = p_level_name
	level_info.level_id = clampi(p_level_id, 1, 255)
	level_info.water_y = -6.0
	level_info.grid_spacing = 2.0
	level_info.streamed = true
	var half: float = extent_m * 0.5
	level_info.bake_bounds = AABB(Vector3(-half, -20.0, -half), Vector3(extent_m, 120.0, extent_m))
	level_root.add_child(level_info)
	level_info.owner = level_root

	cells_root = Node3D.new()
	cells_root.name = String(LevelCells.CELLS_NODE)
	level_info.add_child(cells_root)
	cells_root.owner = level_root

	spawn_marker = LevelSpawn.new()
	spawn_marker.name = "Spawn"
	spawn_marker.position = Vector3(0.0, 0.0, 8.0)
	level_root.add_child(spawn_marker)
	spawn_marker.owner = level_root

	terrain = RegentsTerrainBrush.create_terrain_node(extent_m, vertex_spacing, level_root)
	terrain_brush = RegentsTerrainBrush.new(terrain, extent_m, vertex_spacing)
	terrain_brush.water_y = level_info.water_y
	terrain_brush.init_blank(0.0, RegentsTerrainBrush.Tex.GRASS)

	_setup_level_helpers(extent_m)
	_position_camera_overview()
	_refresh_status()
	return level_root


## Start a world on a procedural terrain base (hills, mountain ridges, coastline) and scatter initial
## procedural trees, rocks, nodes, wildlife, and skeleton camps into the `proc_scatter` layer (WB3).
func start_from_procedural(p_level_name: String = "procedural_world", p_level_id: int = 91,
		seed_val: int = 4021, extent_m: float = 256.0, vertex_spacing: float = 2.0) -> Node3D:
	start_from_scratch(p_level_name, p_level_id, extent_m, vertex_spacing)
	terrain_brush.init_procedural(seed_val, 14.0, 32.0, 36.0)
	rescatter_procedural(seed_val)
	_refresh_status()
	return level_root


## Load an existing level scene (`frontier.tscn`, `continent.tscn`, or a saved custom level) into the builder.
func load_level_scene(scene_path: String) -> Node3D:
	if not ResourceLoader.exists(scene_path):
		push_error("RegentsWorldBuilder: scene not found: %s" % scene_path)
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	_clear_current_level()
	level_root = packed.instantiate() as Node3D
	level_root.scene_file_path = scene_path
	add_child(level_root)
	level_info = LevelBaker.find_info(level_root)
	if level_info == null:
		level_info = LevelInfo.new()
		level_info.name = "LevelInfo"
		level_info.level_name = scene_path.get_file().get_basename()
		level_info.level_id = 90
		level_root.add_child(level_info)
		level_info.owner = level_root
	cells_root = level_info.get_node_or_null(NodePath(LevelCells.CELLS_NODE)) as Node3D
	if cells_root == null:
		cells_root = Node3D.new()
		cells_root.name = String(LevelCells.CELLS_NODE)
		level_info.add_child(cells_root)
		cells_root.owner = level_root
	spawn_marker = level_root.find_child("Spawn", true, false) as LevelSpawn
	terrain = level_root.find_child("Terrain3D", true, false) as Terrain3D
	var ext_m: float = maxf(level_info.bake_bounds.size.x, 256.0)
	terrain_brush = RegentsTerrainBrush.new(terrain, ext_m, terrain.vertex_spacing if terrain != null else 2.0)
	terrain_brush.water_y = level_info.water_y
	ground_paint = level_root.find_child("GroundPaint", true, false) as RegentsGroundPaint
	ground_clutter = level_root.find_child("Clutter", true, false) as RegentsGroundClutter
	solid_props = level_root.find_child("SolidProps", true, false) as RegentsSolidProps
	if ground_clutter != null:
		ground_clutter.height_func = height_at
	RegentsPointPreview.attach_all(level_root, show_gizmo_rings)
	_position_camera_overview()
	_refresh_status()
	return level_root


func _setup_level_helpers(extent_m: float) -> void:
	# Ground fallback collider so physics raycasts & LevelBaker hit the ground even when Terrain3D runs headless.
	var fallback_body := StaticBody3D.new()
	fallback_body.name = "GroundCollider"
	fallback_body.collision_layer = SpaceTimeEntity.WORLD_MASK
	fallback_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(extent_m, 2.0, extent_m)
	cs.shape = box
	cs.position = Vector3(0.0, -1.0, 0.0)
	fallback_body.add_child(cs)
	level_root.add_child(fallback_body)
	fallback_body.owner = level_root
	cs.owner = level_root

	ground_paint = RegentsGroundPaint.new()
	ground_paint.name = "GroundPaint"
	ground_paint.extent_m = minf(extent_m, 256.0)
	ground_paint.level = ^".."
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_GROUND
	ground_paint.material = mat
	level_root.add_child(ground_paint)
	ground_paint.owner = level_root

	ground_clutter = RegentsGroundClutter.new()
	ground_clutter.name = "Clutter"
	ground_clutter.extent_m = minf(extent_m, 160.0)
	ground_clutter.paint = ^"../GroundPaint"
	ground_clutter.terrain = ^"../Terrain3D"
	ground_clutter.water_y = level_info.water_y
	ground_clutter.height_func = height_at
	ground_clutter.kinds = _default_clutter_kinds()
	level_root.add_child(ground_clutter)
	ground_clutter.owner = level_root

	solid_props = RegentsSolidProps.new()
	solid_props.name = "SolidProps"
	solid_props.props = ^"../LevelInfo/Cells"
	level_root.add_child(solid_props)
	solid_props.owner = level_root

	instancer_root = Node3D.new()
	instancer_root.name = "TerrainInstancer"
	level_root.add_child(instancer_root)
	instancer_root.owner = level_root


func _default_clutter_kinds() -> Array[RegentsClutterKind]:
	var out: Array[RegentsClutterKind] = []
	for spec: Array in [
		["Grass_Common_Short.gltf", 28.0, 0.35, 0.7, Color(0.66, 0.78, 0.5), 0.75, 0.7, false],
		["Grass_Common_Tall.gltf", 5.0, 0.4, 0.7, Color(0.6, 0.74, 0.46), 0.9, 0.85, false],
		["Flower_3_Group.gltf", 1.5, 0.4, 0.65, Color.WHITE, 0.95, 0.1, false],
		["Pebble_Round_1.gltf", 2.5, 0.6, 1.5, Color.WHITE, 0.2, 0.9, true],
	]:
		var path: String = RegentsKitCatalog.NATURE_DIR + String(spec[0])
		if not ResourceLoader.exists(path):
			continue
		var k := RegentsClutterKind.new()
		k.model = load(path) as PackedScene
		k.per_100_m2 = float(spec[1])
		k.min_scale = float(spec[2])
		k.max_scale = float(spec[3])
		k.tint = spec[4] as Color
		k.patchy = float(spec[5])
		k.at_edges = float(spec[6])
		k.on_dirt = bool(spec[7])
		out.append(k)
	return out


func _clear_current_level() -> void:
	if walk_actor != null and is_instance_valid(walk_actor):
		walk_actor.free()
	walk_actor = null
	camera_mode = CameraMode.FLY
	selected_node = null
	active_settlement = null
	active_prefab_root = null
	story_level = 0
	_prefab_origin_locked = false
	_picking_prefab_origin = false
	NpcDef.clear_drafts()
	_painting_drag = false
	_stroke_before_snap.clear()
	wall_draft_corners.clear()
	road_draft_points.clear()
	ramp_start_point = Vector3.INF
	exclusion_zones.clear()
	instancer_batches.clear()
	_instancer_xforms.clear()
	_undo_stack.clear()
	_redo_stack.clear()
	_point_counters.clear()
	if level_root != null and is_instance_valid(level_root):
		remove_child(level_root)
		level_root.free()
	level_root = null
	level_info = null
	cells_root = null
	spawn_marker = null
	terrain = null
	terrain_brush = null
	ground_paint = null
	ground_clutter = null
	solid_props = null
	instancer_root = null


## World ground height at `(wx, wz)` from `terrain_brush`.
func height_at(wx: float, wz: float) -> float:
	if terrain_brush != null:
		return terrain_brush.height_at(wx, wz)
	return 0.0


# =============================================================================================
# 2. NON-DESTRUCTIVE PROCEDURAL SCATTER & EXCLUSION ZONES (WB3)
# =============================================================================================

## Add a circular exclusion zone `(wx, radius_m, wz)` where procedural scatter never places objects.
func add_exclusion_zone(wx: float, wz: float, radius_m: float) -> void:
	if radius_m <= 0.0:
		return
	exclusion_zones.append(Vector3(wx, radius_m, wz))


## True if `(wx, wz)` is inside any registered exclusion zone, settlement, or spawn clearing.
func is_excluded_from_procedural(wx: float, wz: float) -> bool:
	var p := Vector2(wx, wz)
	if spawn_marker != null and p.distance_to(Vector2(spawn_marker.position.x, spawn_marker.position.z)) < 16.0:
		return true
	for z: Vector3 in exclusion_zones:
		if p.distance_to(Vector2(z.x, z.z)) <= z.y:
			return true
	if cells_root != null:
		for c: Node in cells_root.get_children():
			if c is Settlement:
				var s: Settlement = c as Settlement
				var sr: float = float(s.get_meta(&"exclusion_radius", 42.0))
				if p.distance_to(Vector2(s.position.x, s.position.z)) <= sr:
					return true
	return false


## Re-scatter ONLY the `proc_scatter` layer across the terrain, preserving all `hand_*` settlements,
## buildings, props, roads, and gameplay points, and skipping all exclusion zones (WB3).
## Returns how many procedural nodes were placed.
func rescatter_procedural(seed_val: int = 0xC0417E17) -> int:
	if cells_root == null or terrain_brush == null:
		return 0
	# Remove only procedural nodes, never hand-placed ones.
	var to_remove: Array[Node] = []
	for c: Node in cells_root.get_children():
		var layer: StringName = c.get_meta(LAYER_META, &"") as StringName
		if layer == LAYER_PROCEDURAL or (c is LevelPoint and (c as LevelPoint).point_id.begins_with("w_")):
			to_remove.append(c)
	for n: Node in to_remove:
		cells_root.remove_child(n)
		n.free()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var half: float = float(terrain_brush.width - 1) * terrain_brush.spacing * 0.45
	var step: float = 32.0
	var placed_count: int = 0
	var x: float = -half
	while x < half:
		var z: float = -half
		while z < half:
			var px: float = x + rng.randf_range(4.0, step - 4.0)
			var pz: float = z + rng.randf_range(4.0, step - 4.0)
			var py: float = height_at(px, pz)
			if py > terrain_brush.water_y + 1.2 and terrain_brush.slope_at(px, pz) < 0.65 \
					and not is_excluded_from_procedural(px, pz):
				var roll: float = rng.randf()
				if roll < 0.35:
					var tree_tag: String = "Oak" if rng.randf() < 0.3 else "Tree"
					var lp: LevelPoint = _make_point("node", tree_tag, Vector3(px, py, pz), 0.6, "w_node_%d" % (placed_count + 1), LAYER_PROCEDURAL)
					cells_root.add_child(lp)
					lp.owner = level_root
					RegentsPointPreview.ensure_on(lp, show_gizmo_rings)
					placed_count += 1
				elif roll < 0.55:
					var rock_tag: String = "Iron rock" if rng.randf() < 0.35 else "Copper rock"
					var lp: LevelPoint = _make_point("node", rock_tag, Vector3(px, py, pz), 0.6, "w_rock_%d" % (placed_count + 1), LAYER_PROCEDURAL)
					cells_root.add_child(lp)
					lp.owner = level_root
					RegentsPointPreview.ensure_on(lp, show_gizmo_rings)
					placed_count += 1
				elif roll < 0.70:
					var foe_kind: String = "wolf" if rng.randf() < 0.4 else "deer"
					var lp: LevelPoint = _make_point(foe_kind, "", Vector3(px, py, pz), 0.5, "w_%s_%d" % [foe_kind, placed_count + 1], LAYER_PROCEDURAL)
					cells_root.add_child(lp)
					lp.owner = level_root
					RegentsPointPreview.ensure_on(lp, show_gizmo_rings)
					placed_count += 1
				elif roll < 0.85:
					var decor: Node3D = _instantiate_nature_prop("Bush_Large" if rng.randf() < 0.5 else "Rock_Medium_1",
						Vector3(px, py, pz), rng.randf() * TAU, rng.randf_range(0.8, 1.3), LAYER_PROCEDURAL)
					if decor != null:
						placed_count += 1
			z += step
		x += step
	return placed_count


## Count of children under `Cells` belonging to `layer` (`LAYER_SETTLEMENTS`, `LAYER_PROPS`, `LAYER_GAMEPLAY`, `LAYER_PROCEDURAL`).
func count_in_layer(layer: StringName) -> int:
	if cells_root == null:
		return 0
	var n: int = 0
	for c: Node in cells_root.get_children():
		if (c.get_meta(LAYER_META, &"") as StringName) == layer:
			n += 1
	return n


# =============================================================================================
# 3. DUAL-MODE CAMERA: FREE-FLY CREATIVE & DROP-IN WALK TEST (WB2)
# =============================================================================================

## Toggle between Free-Fly Creative Mode (`CameraMode.FLY`) and Drop-In Walk Mode (`CameraMode.WALK`).
func set_camera_mode(m: CameraMode, spawn_at: Vector3 = Vector3.INF) -> void:
	camera_mode = m
	if m == CameraMode.WALK:
		var start_pos: Vector3 = spawn_at if spawn_at != Vector3.INF else cursor_pos
		start_pos.y = height_at(start_pos.x, start_pos.z)
		if walk_actor == null or not is_instance_valid(walk_actor):
			walk_actor = ShowcaseActor.make(DEF_ADVENTURER, 0)
			walk_actor.name = "BuilderWalkTester"
			walk_actor.ground = height_at
			walk_actor.position = start_pos
			add_child(walk_actor)
		else:
			walk_actor.ground = height_at
			walk_actor.walk_to(start_pos, 0.0)
		walk_actor.visible = true
		if _overlay_root != null:
			_overlay_root.visible = false
	else:
		if walk_actor != null and is_instance_valid(walk_actor):
			walk_actor.visible = false
		if _overlay_root != null:
			_overlay_root.visible = true
	_refresh_status()


func toggle_camera_mode() -> void:
	set_camera_mode(CameraMode.WALK if camera_mode == CameraMode.FLY else CameraMode.FLY)


## Step the drop-in walk tester by `dt` seconds with movement input `move_dir` (e.g. `Vector2(0, -1)` forward)
## and optional `jump` / roll. Updates `walk_actor.ground` from the terrain height at its XZ.
func step_walk_mode(dt: float, move_dir: Vector2 = Vector2.ZERO, jump: bool = false) -> Vector3:
	if camera_mode != CameraMode.WALK or walk_actor == null or not is_instance_valid(walk_actor):
		return Vector3.ZERO
	walk_actor.ground = height_at
	var world_dir: Vector3 = Vector3(move_dir.x, 0.0, move_dir.y).rotated(Vector3.UP, _yaw)
	if jump:
		walk_actor.roll(world_dir)
	elif world_dir.length_squared() > 0.001:
		walk_actor.walk_to(walk_actor.position + world_dir.normalized() * 6.0, 5.2)
	else:
		walk_actor.walk_to(walk_actor.position, 0.0)
	walk_actor.step(dt)
	var after: Vector3 = walk_actor.global_position
	if camera != null:
		var back := Vector3(sin(_yaw), 0.0, cos(_yaw)) * 5.2
		camera.look_at_from_position(after + Vector3(0.0, 2.6, 0.0) + back, after + Vector3(0.0, 1.3, 0.0))
	return after


## Press `E` in Walk Mode: finds the nearest `npc` or `guide` `LevelPoint` within its interaction range and
## starts a live conversation with them (`start_dialogue_test`). Returns the `NpcDef` spoken to, or null.
func interact_in_walk_mode() -> NpcDef:
	if walk_actor == null or not is_instance_valid(walk_actor) or cells_root == null:
		return null
	var me: Vector3 = walk_actor.global_position
	var best_npc: NpcDef = null
	var best_point: Node3D = null
	var best_d: float = INF
	for n: Node in level_root.find_children("*", "Marker3D", true, false):
		var lp: LevelPoint = n as LevelPoint
		if lp == null:
			continue
		if lp.kind != "npc" and lp.kind != "guide":
			continue
		var key: StringName = StringName(lp.tags[0] if (lp.kind == "npc" and not lp.tags.is_empty()) else "drillmaster")
		var npc: NpcDef = NpcDef.by_key(key)
		if npc == null:
			continue
		var d: float = Vector2(lp.global_position.x - me.x, lp.global_position.z - me.z).length()
		if d <= npc.interact_m and d < best_d:
			best_d = d
			best_npc = npc
			best_point = lp
	if best_npc != null:
		start_dialogue_test(best_npc, best_point)
	return best_npc


# =============================================================================================
# 4. TERRAIN BRUSHES, RAMPS & ROAD SPLINES (WB4, WB6)
# =============================================================================================

## Current terrain/clutter brush radius in meters (`0.5 m` to `64.0 m`).
func brush_radius() -> float:
	return terrain_brush.radius_m if terrain_brush != null else 8.0


## Resize the terrain & texture paint brush (`0.5 m` to `64.0 m`) and update the 3D cursor circle + UI slider.
func set_brush_radius(r: float) -> void:
	var clamped: float = clampf(r, 0.5, 64.0)
	if terrain_brush != null:
		terrain_brush.radius_m = clamped
	if _cursor_ring != null and _cursor_ring.mesh is TorusMesh:
		var torus: TorusMesh = _cursor_ring.mesh as TorusMesh
		torus.outer_radius = clamped
		var band: float = clampf(clamped * 0.08, 0.10, 0.45)
		torus.inner_radius = maxf(clamped - band, 0.05)
	if _brush_radius_slider != null and not is_equal_approx(_brush_radius_slider.value, clamped):
		_brush_radius_slider.set_value_no_signal(clamped)
	if _brush_radius_label != null:
		_brush_radius_label.text = "Brush: %.1fm" % clamped
	_refresh_status()


## Set the terrain sculpt brush strength (`0.1` to `20.0`).
func set_brush_strength(s: float) -> void:
	var clamped: float = clampf(s, 0.1, 20.0)
	if terrain_brush != null:
		terrain_brush.strength = clamped
	if _brush_strength_slider != null and not is_equal_approx(_brush_strength_slider.value, clamped):
		_brush_strength_slider.set_value_no_signal(clamped)
	if _brush_strength_label != null:
		_brush_strength_label.text = "Str: %.1f" % clamped


## Apply the active terrain brush (`terrain_brush.mode`) at `at`, recording an Undo/Redo command.
func apply_terrain_brush(at: Vector3, override_mode: int = -1) -> void:
	if terrain_brush == null:
		return
	var before: Dictionary = terrain_brush.apply_stroke(at.x, at.z, override_mode)
	var after: Dictionary = terrain_brush.capture_matching(before)
	_push_undo({
		"kind": "terrain",
		"before": before,
		"after": after,
	})


## Carve a walkable ramp from `from` to `to` of width `width_m`, recording an Undo/Redo command.
func carve_terrain_ramp(from: Vector3, to: Vector3, width_m: float = 4.0, blend_m: float = 3.0,
		tex_id: int = RegentsTerrainBrush.Tex.DIRT) -> void:
	if terrain_brush == null:
		return
	var before: Dictionary = terrain_brush.carve_ramp(from, to, width_m, blend_m, tex_id)
	var after: Dictionary = terrain_brush.capture_matching(before)
	_push_undo({
		"kind": "terrain",
		"before": before,
		"after": after,
	})


## Draw a `Path3D` road or trail spline (`surface`: `"dirt"`, `"cobble"`, `"setts"`), optionally leveling the
## terrain roadbed cross-slope, adding an exclusion zone along it, and repainting `RegentsGroundPaint` +
## `RegentsGroundClutter` so grass clears off the road (WB6).
func draw_road_spline(points: PackedVector3Array, surface: String = "dirt", width_m: float = 3.0,
		flatten_bed: bool = true) -> Path3D:
	if points.size() < 2 or level_root == null:
		return null
	var curve := Curve3D.new()
	for p: Vector3 in points:
		var y: float = height_at(p.x, p.z)
		curve.add_point(Vector3(p.x, y + 0.05, p.z))
		add_exclusion_zone(p.x, p.z, width_m + 3.0)
	var path_node := Path3D.new()
	path_node.name = "Road_%s_%d" % [surface, _next_id("road")]
	path_node.curve = curve
	path_node.set_meta(&"road_surface", surface)
	path_node.set_meta(&"road_width_m", width_m)
	var parent: Node = ground_paint if ground_paint != null else level_root
	parent.add_child(path_node)
	path_node.owner = level_root

	var terrain_before: Dictionary = {}
	var terrain_after: Dictionary = {}
	if flatten_bed and terrain_brush != null:
		var tex_id: int = RegentsTerrainBrush.Tex.COBBLE if surface != "dirt" else RegentsTerrainBrush.Tex.DIRT
		terrain_before = terrain_brush.flatten_road_spline(curve, Transform3D.IDENTITY, width_m, 2.5, tex_id)
		terrain_after = terrain_brush.capture_matching(terrain_before)

	if ground_paint != null:
		ground_paint.trail_width_m = width_m
		ground_paint.repaint()
	if ground_clutter != null and not ground_clutter.made.is_empty():
		ground_clutter.scatter()

	_push_undo({
		"kind": "add_node",
		"node": path_node,
		"parent": parent,
		"terrain_before": terrain_before,
		"terrain_after": terrain_after,
	})
	selected_node = path_node
	return path_node


## Scatter or re-scatter `RegentsGroundClutter` across the terrain (WB6).
func scatter_clutter() -> int:
	if ground_clutter == null:
		return 0
	ground_clutter.height_func = height_at
	ground_clutter.scatter()
	return ground_clutter.count()


## Erase clutter in a `radius_m` circle at `at` (WB6).
func erase_clutter_at(at: Vector3, radius_m: float = 4.0) -> int:
	if ground_clutter == null:
		return 0
	ground_clutter.height_func = height_at
	ground_clutter.erase_in_circle(at.x, at.z, radius_m, true)
	return ground_clutter.count()


# =============================================================================================
# 5. SETTLEMENTS, KIT HOUSES, DEMO PREFABS, 2M SNAP PIECES & CASTLE WALLS (WB5, WB7)
# =============================================================================================

## Create a new `Settlement` container at `at` with a `SettlementStyle` preset and `VillageDressing`,
## register its procedural exclusion zone, and optionally add a World Map `poi` marker (WB7, WB11).
func create_settlement(title: String, at: Vector3, style_index: int = 1, exclusion_r: float = 48.0,
		add_map_poi: bool = true) -> Settlement:
	if cells_root == null:
		return null
	var s := Settlement.new()
	s.name = title.replace(" ", "") if not title.is_empty() else "Settlement_%d" % _next_id("settlement")
	var y: float = height_at(at.x, at.z)
	s.position = Vector3(at.x, y, at.z)
	s.town_seed = hash([title, roundi(at.x), roundi(at.z)])
	if not settlement_styles.is_empty():
		s.style = settlement_styles[clampi(style_index, 0, settlement_styles.size() - 1)]
	if ResourceLoader.exists(DRESSING_PATH):
		s.dressing = load(DRESSING_PATH) as VillageDressing
	s.set_meta(LAYER_META, LAYER_SETTLEMENTS)
	s.set_meta(&"exclusion_radius", exclusion_r)
	s.set_meta(&"settlement_title", title)
	cells_root.add_child(s)
	s.owner = level_root
	add_exclusion_zone(at.x, at.z, exclusion_r)
	active_settlement = s
	selected_node = s
	if add_map_poi and not title.is_empty():
		place_level_point("poi", title, s.position, 12.0, "poi_%s" % s.name.to_lower())
	_push_undo({
		"kind": "add_node",
		"node": s,
		"parent": cells_root,
	})
	return s


## Change the `SettlementStyle` of `settlement` (or `active_settlement`) live and re-dress all its buildings.
func restyle_settlement(style_index: int, settlement: Settlement = null) -> void:
	var target: Settlement = settlement if settlement != null else active_settlement
	if target == null or settlement_styles.is_empty():
		return
	var s: SettlementStyle = settlement_styles[clampi(style_index, 0, settlement_styles.size() - 1)]
	target.dress_all()
	target.restyle(s)


## Stamp a parametric `KitHouse` at `at` (rotated `yaw`), auto-leveling the terrain under its footprint when
## `auto_flatten_footprints` is on, and dressing it under `active_settlement` (or `Cells`).
func stamp_kit_house(at: Vector3, yaw: float = 0.0, params: Dictionary = {}) -> KitHouse:
	var parent: Node3D = _building_parent()
	if parent == null:
		return null
	var h := KitHouse.new()
	h.name = "KitHouse_%d" % _next_id("house")
	h.width = int(params.get("width", house_width))
	h.depth = int(params.get("depth", house_depth))
	h.floors = int(params.get("floors", house_floors))
	h.ground = int(params.get("ground", house_ground)) as KitHouse.Finish
	h.upper = int(params.get("upper", house_upper)) as KitHouse.Finish
	h.tiles = int(params.get("tiles", house_tiles)) as KitHouse.Tiles
	h.house_seed = int(params.get("seed", house_seed))
	h.set_meta(LAYER_META, LAYER_SETTLEMENTS)

	var wy: float = at.y if params.has("fixed_y") else height_at(at.x, at.z)
	var world_pos := Vector3(at.x, wy, at.z)
	var fp := Vector2(float(h.effective_width()) * KitHouse.CELL, float(h.depth) * KitHouse.CELL)
	var terrain_before: Dictionary = {}
	var terrain_after: Dictionary = {}
	if auto_flatten_footprints and terrain_brush != null:
		terrain_before = terrain_brush.flatten_footprint(world_pos, yaw, fp, 4.0)
		terrain_after = terrain_brush.capture_matching(terrain_before)
	add_exclusion_zone(world_pos.x, world_pos.z, maxf(fp.x, fp.y) + 4.0)

	parent.add_child(h)
	h.global_position = world_pos
	h.rotation.y = yaw
	h.owner = level_root
	h.build()
	if parent is Settlement and (parent as Settlement).style != null:
		var st: Settlement = parent as Settlement
		if st.dressing != null:
			st.dressing.place(h, st.props_rng(h))
		TownKit.dress(h, st.style, st.seed_of(h), world_pos.y)

	_push_undo({
		"kind": "add_node",
		"node": h,
		"parent": parent,
		"terrain_before": terrain_before,
		"terrain_after": terrain_after,
	})
	selected_node = h
	return h


## Stamp one of the Medieval Village kit's pre-built demo buildings (`demo_house_c`, `demo_house_d`,
## `demo_houses_a`, `demo_tower`) or a saved custom preset scene at `at`, gathering its collisions into one body
## and leveling its footprint (WB7).
func stamp_demo_house(scene_path: String, at: Vector3, yaw: float = 0.0,
		footprint: Vector2 = Vector2(10.0, 10.0)) -> Node3D:
	var parent: Node3D = _building_parent()
	if parent == null or not ResourceLoader.exists(scene_path):
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var inst: Node3D = _instantiate_building_centered(packed, scene_path.begins_with(RegentsKitCatalog.CUSTOM_PRESETS_DIR))
	inst.name = "%s_%d" % [scene_path.get_file().get_basename(), _next_id("demo")]
	inst.set_meta(LAYER_META, LAYER_SETTLEMENTS)

	var wy: float = height_at(at.x, at.z)
	var world_pos := Vector3(at.x, wy, at.z)
	var terrain_before: Dictionary = {}
	var terrain_after: Dictionary = {}
	if auto_flatten_footprints and terrain_brush != null:
		terrain_before = terrain_brush.flatten_footprint(world_pos, yaw, footprint, 4.0)
		terrain_after = terrain_brush.capture_matching(terrain_before)
	add_exclusion_zone(world_pos.x, world_pos.z, maxf(footprint.x, footprint.y) + 4.0)

	parent.add_child(inst)
	inst.global_position = world_pos
	inst.rotation.y = yaw
	inst.owner = level_root
	if parent is Settlement and (parent as Settlement).style != null:
		var st: Settlement = parent as Settlement
		TownKit.dress(inst, st.style, st.seed_of(inst), world_pos.y)

	_push_undo({
		"kind": "add_node",
		"node": inst,
		"parent": parent,
		"terrain_before": terrain_before,
		"terrain_after": terrain_after,
	})
	selected_node = inst
	return inst


## Place an individual piece from the 305 Medieval Village kit or 212 Fantasy Props kit (`TownKit.piece`),
## snapping to the configured grid (`grid_step_xz`, or 2 m XZ / 3 m Y default) when `use_grid_snap` is true
## and `free_place_held` (`Alt` / `Shift`) is not held (WB7 Tier 3: Custom Piece Mode).
func place_kit_piece(piece_name: String, at: Vector3, yaw: float = 0.0, use_grid_snap: bool = true,
		into_group: Node3D = null) -> Node3D:
	if not TownKit.has_piece(piece_name):
		push_warning("RegentsWorldBuilder: unknown kit piece '%s'" % piece_name)
		return null
	var parent: Node3D = into_group if into_group != null else _building_parent()
	if parent == null:
		return null
	var pos: Vector3 = at
	var rot_y: float = yaw
	var snap_active: bool = use_grid_snap and snap_grid and not free_place_held
	if snap_active:
		var is_struct: bool = not piece_name.begins_with("Prop_") and ResourceLoader.exists(TownKit.VILLAGE + piece_name + ".gltf")
		if grid_step_xz > 0.0:
			var gx: float = grid_step_xz if (is_struct or absf(grid_step_xz - 2.0) > 0.001) else 0.25
			pos.x = snappedf(pos.x, gx)
			pos.z = snappedf(pos.z, gx)
		if grid_step_y > 0.0:
			var gy: float = grid_step_y if (is_struct or absf(grid_step_y - 3.0) > 0.001) else 0.1
			var gy_ground: float = height_at(pos.x, pos.z)
			pos.y = gy_ground + snappedf(pos.y - gy_ground, gy)
		rot_y = snappedf(rot_y, PI * 0.5 if is_struct else PI / 12.0)
	# If this is the very first piece placed into an active prefab, lock the prefab's origin right onto this piece!
	if parent == active_prefab_root and (not _prefab_origin_locked or active_prefab_root.get_child_count() == 0):
		active_prefab_root.global_position = Vector3(pos.x, height_at(pos.x, pos.z), pos.z)
		_prefab_origin_locked = true
		_sync_prefab_box()
	var inst: Node3D = TownKit.piece(piece_name).instantiate() as Node3D
	inst.name = "%s_%d" % [piece_name, _next_id("piece")]
	inst.set_meta(LAYER_META, LAYER_SETTLEMENTS)
	parent.add_child(inst)
	inst.global_position = pos
	inst.rotation.y = rot_y
	inst.owner = level_root
	if parent is Settlement and (parent as Settlement).style != null:
		var st: Settlement = parent as Settlement
		TownKit.dress(inst, st.style, st.seed_of(inst), pos.y)
	_push_undo({
		"kind": "add_node",
		"node": inst,
		"parent": parent,
	})
	selected_node = inst
	if parent == active_prefab_root:
		_sync_prefab_box()
	_refresh_prefab_ui()
	return inst


## Save a custom building or group of kit pieces (`building_root`) as a reusable `.tscn` preset in
## `user://builder_presets/<preset_name>.tscn` so it appears in the Settlements & Houses catalog (WB7).
## Automatically recenters all child pieces around `(0, 0, 0)` so the saved prefab always stamps right at the cursor!
func save_custom_house_preset(building_root: Node3D, preset_name: String) -> String:
	if building_root == null or preset_name.strip_edges().is_empty():
		return ""
	var clean: String = preset_name.strip_edges().to_lower().replace(" ", "_")
	var abs_dir: String = ProjectSettings.globalize_path(RegentsKitCatalog.CUSTOM_PRESETS_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var copy: Node3D = building_root.duplicate() as Node3D
	copy.position = Vector3.ZERO
	_recenter_prefab_children(copy)
	_own_recursive(copy, copy)
	var packed := PackedScene.new()
	var err: Error = packed.pack(copy)
	copy.free()
	if err != OK:
		return ""
	var out_path: String = RegentsKitCatalog.CUSTOM_PRESETS_DIR + clean + ".tscn"
	if ResourceSaver.save(packed, out_path) != OK:
		return ""
	RegentsKitCatalog.clear_cache()
	_refresh_palette()
	return out_path


## Instantiate a building/preset scene and gather collisions into a single `Body`, recentering all direct children
## BEFORE `gather_collisions` runs when `recenter` is true so visual pieces AND physics shapes stay centered together.
static func _instantiate_building_centered(packed: PackedScene, recenter: bool) -> Node3D:
	var n: Node3D = packed.instantiate() as Node3D
	if recenter:
		_recenter_prefab_children(n)
	var body := StaticBody3D.new()
	body.name = "Body"
	TownKit.gather_collisions(n, body, Transform3D.IDENTITY)
	n.add_child(body)
	return n


## Recenters direct `Node3D` children of a custom prefab around their horizontal bounding center `(cx, min_y, cz)`
## so a prefab built anywhere on the map always previews and stamps dead-center inside the cursor circle.
static func _recenter_prefab_children(root: Node3D) -> void:
	if root == null or root is KitHouse or root is CastleWall:
		return
	var piece_nodes: Array[Node3D] = []
	for c: Node in root.get_children():
		if c is Node3D and not (c is StaticBody3D) and not (c is CollisionShape3D):
			piece_nodes.append(c as Node3D)
	if piece_nodes.is_empty():
		return
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var min_z: float = INF
	var max_z: float = -INF
	for pn: Node3D in piece_nodes:
		min_x = minf(min_x, pn.position.x)
		max_x = maxf(max_x, pn.position.x)
		min_y = minf(min_y, pn.position.y)
		min_z = minf(min_z, pn.position.z)
		max_z = maxf(max_z, pn.position.z)
	var offset := Vector3(0.5 * (min_x + max_x), min_y, 0.5 * (min_z + max_z))
	if offset.length_squared() < 0.0001:
		return
	for c: Node in root.get_children():
		var n3: Node3D = c as Node3D
		if n3 != null:
			n3.position -= offset


## Build a `CastleWall` (curtain wall with corner towers and gates, or a roofed `Keep`) from `corners` (world XZ).
func build_castle_wall(corners: PackedVector3Array, gates: PackedInt32Array = PackedInt32Array([0]),
		roofed: bool = false, roof_style: int = CastleWall.RoofStyle.CONE, round_towers: bool = true) -> CastleWall:
	if corners.size() < 2:
		return null
	var parent: Node3D = _building_parent()
	if parent == null:
		return null
	var mid := Vector3.ZERO
	for c: Vector3 in corners:
		mid += c
	mid /= float(corners.size())
	mid.y = height_at(mid.x, mid.z)

	var local_corners := PackedVector3Array()
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for c: Vector3 in corners:
		var rel := Vector3(c.x - mid.x, 0.0, c.z - mid.z)
		local_corners.append(rel)
		min_v = Vector2(minf(min_v.x, rel.x), minf(min_v.y, rel.z))
		max_v = Vector2(maxf(max_v.x, rel.x), maxf(max_v.y, rel.z))

	var wall := CastleWall.new()
	wall.name = ("Keep_%d" if roofed else "CastleWall_%d") % _next_id("wall")
	wall.corners = local_corners
	wall.gates = gates
	wall.roofed = roofed
	wall.roof_style = roof_style as CastleWall.RoofStyle
	wall.round_towers = round_towers
	if roofed:
		wall.height = 20.0
		wall.tower_height = 26.0
		wall.roof_slate = true
	wall.set_meta(LAYER_META, LAYER_SETTLEMENTS)

	var fp := Vector2(max_v.x - min_v.x + 8.0, max_v.y - min_v.y + 8.0)
	var terrain_before: Dictionary = {}
	var terrain_after: Dictionary = {}
	if auto_flatten_footprints and terrain_brush != null:
		terrain_before = terrain_brush.flatten_footprint(mid, 0.0, fp, 6.0)
		terrain_after = terrain_brush.capture_matching(terrain_before)

	parent.add_child(wall)
	wall.global_position = mid
	wall.owner = level_root
	wall.build()
	if parent is Settlement and (parent as Settlement).style != null:
		var st: Settlement = parent as Settlement
		TownKit.dress(wall, st.style, st.seed_of(wall), mid.y)

	_push_undo({
		"kind": "add_node",
		"node": wall,
		"parent": parent,
		"terrain_before": terrain_before,
		"terrain_after": terrain_after,
	})
	selected_node = wall
	return wall


## Stamp a complete `TownFurnish` prop arrangement (`"market"`, `"green"`, `"inn_front"`, `"training"`, `"smithy"`)
## as a single `PropGroup` at `at` (WB7).
func stamp_furnishing(preset: String, at: Vector3, yaw: float = 0.0, seed_val: int = 2611) -> PropGroup:
	var parent: Node3D = _building_parent()
	if parent == null:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var wy: float = height_at(at.x, at.z)
	var world_pos := Vector3(at.x, wy, at.z)
	var g: PropGroup = null
	match preset:
		"market":
			g = TownFurnish.market(parent, Vector3.ZERO, Vector2(18.0, 14.0), 5.5, 3.0, rng)
		"green":
			g = TownFurnish.green(parent, Vector3.ZERO, rng)
		"inn_front":
			g = TownFurnish.inn_front(parent, Vector3.ZERO, rng)
		"training":
			g = PropGroup.new()
			g.name = "TrainingYard_%d" % _next_id("furnish")
			TownFurnish.training(g, Vector3.ZERO, rng)
			parent.add_child(g)
		"smithy":
			g = PropGroup.new()
			g.name = "Smithy_%d" % _next_id("furnish")
			TownFurnish.smithy(g, Vector3.ZERO)
			parent.add_child(g)
	if g == null:
		return null
	g.global_position = world_pos
	g.rotation.y = yaw
	g.set_meta(LAYER_META, LAYER_SETTLEMENTS)
	g.owner = level_root
	if parent is Settlement and (parent as Settlement).style != null:
		var st: Settlement = parent as Settlement
		TownKit.dress(g, st.style, st.seed_of(g), world_pos.y)
	_push_undo({
		"kind": "add_node",
		"node": g,
		"parent": parent,
	})
	selected_node = g
	return g


## Start assembling a new custom building/house/town prefab at `at` (defaults to `cursor_pos`).
## Every kit piece (`3. Kit Pieces`) or prop placed while `active_prefab_root` is active is parented inside
## this prefab container so you can save the whole building as a reusable preset with `save_active_prefab`.
func start_new_prefab(prefab_name: String = "custom_house", at: Vector3 = Vector3.INF) -> Node3D:
	var parent: Node3D = active_settlement if (active_settlement != null and is_instance_valid(active_settlement)) else cells_root
	if parent == null:
		return null
	var pos: Vector3 = at if at != Vector3.INF else cursor_pos
	if snap_grid and not free_place_held and grid_step_xz > 0.0:
		pos.x = snappedf(pos.x, grid_step_xz)
		pos.z = snappedf(pos.z, grid_step_xz)
	pos.y = height_at(pos.x, pos.z)
	var root := Node3D.new()
	var clean_name: String = prefab_name.strip_edges().replace(" ", "_") if not prefab_name.strip_edges().is_empty() else ("Prefab_%d" % _next_id("prefab"))
	root.name = clean_name
	root.set_meta(LAYER_META, LAYER_SETTLEMENTS)
	parent.add_child(root)
	root.global_position = pos
	root.owner = level_root
	active_prefab_root = root
	_prefab_origin_locked = false
	_picking_prefab_origin = false
	selected_node = root
	story_level = 0
	if _prefab_name_edit != null and _prefab_name_edit.text.strip_edges().is_empty():
		_prefab_name_edit.text = clean_name
	_push_undo({
		"kind": "add_node",
		"node": root,
		"parent": parent,
	})
	_sync_prefab_box()
	_refresh_prefab_ui()
	_update_right_panel_visibility()
	_refresh_status()
	return root


## Save `active_prefab_root` (or `selected_node`) to `user://builder_presets/<preset_name>.tscn` and register
## it in `2. Towns & Houses -> Saved Custom Presets`.
func save_active_prefab(preset_name: String = "") -> String:
	var target: Node3D = active_prefab_root if (active_prefab_root != null and is_instance_valid(active_prefab_root)) else selected_node
	if target == null:
		return ""
	var chosen_name: String = preset_name.strip_edges()
	if chosen_name.is_empty() and _prefab_name_edit != null:
		chosen_name = _prefab_name_edit.text.strip_edges()
	if chosen_name.is_empty():
		chosen_name = target.name
	var saved_path: String = save_custom_house_preset(target, chosen_name)
	_refresh_prefab_ui(saved_path)
	return saved_path


## Exit active prefab assembly mode (leaving the constructed building in the scene).
func finish_active_prefab() -> void:
	active_prefab_root = null
	_prefab_origin_locked = false
	_picking_prefab_origin = false
	story_level = 0
	_sync_prefab_box()
	_refresh_prefab_ui()
	_update_right_panel_visibility()
	_refresh_status()


## Set the vertical story/floor level (`0` = Floor 1 +0m, `1` = Floor 2 +Y, etc.)
## when snapping kit pieces vertically (`grid_step_y`, 3 m default).
func set_story_level(level: int) -> void:
	story_level = clampi(level, 0, 5)
	if _story_label != null:
		var y_off: float = float(story_level) * grid_step_y
		var y_txt: String = ("%dm" % roundi(y_off)) if is_equal_approx(y_off, round(y_off)) else ("%.1fm" % y_off)
		_story_label.text = "Floor %d (+%s)" % [story_level + 1, y_txt]
	_sync_ghost_transform()
	_refresh_status()


func _building_parent() -> Node3D:
	if active_prefab_root != null and is_instance_valid(active_prefab_root) and active_prefab_root.is_inside_tree():
		return active_prefab_root
	if active_settlement != null and is_instance_valid(active_settlement) and active_settlement.is_inside_tree():
		return active_settlement
	return cells_root


# =============================================================================================
# 6. THREE MESH PLACEMENT MODES FOR NATURE & PROPS (WB5)
# =============================================================================================

## Place a nature model (`CommonTree_1`, `Rock_Big_1`, `Bush_Large`, etc.) at `at` using `mode_override`
## (or `prop_mode`):
##   - `PropMode.SCENE_NODE`: scene instance under `Cells` (`RegentsSolidProps` wraps solid rocks in Jolt hulls).
##   - `PropMode.PROP_GROUP`: batched under a `PropGroup` (single merged mesh & single StaticBody3D).
##   - `PropMode.TERRAIN_INSTANCER`: hardware MultiMesh batch under `TerrainInstancer`.
func place_nature_prop(model_name: String, at: Vector3, yaw: float = 0.0, scale_v: float = 1.0,
		mode_override: int = -1) -> Node3D:
	var m: PropMode = (mode_override as PropMode) if mode_override >= 0 else prop_mode
	var wy: float = height_at(at.x, at.z)
	var world_pos := Vector3(at.x, wy, at.z)
	match m:
		PropMode.SCENE_NODE:
			var inst: Node3D = _instantiate_nature_prop(model_name, world_pos, yaw, scale_v, LAYER_PROPS)
			if inst != null:
				_push_undo({"kind": "add_node", "node": inst, "parent": cells_root})
				selected_node = inst
			return inst
		PropMode.PROP_GROUP:
			var group_node: PropGroup = _ensure_nature_prop_group()
			var inst: Node3D = _instantiate_nature_prop(model_name, world_pos, yaw, scale_v, LAYER_PROPS, group_node)
			if inst != null:
				TownKit.gather_collisions(inst, group_node.body(), inst.transform)
				_push_undo({"kind": "add_node", "node": inst, "parent": group_node})
				selected_node = inst
			return inst
		PropMode.TERRAIN_INSTANCER:
			var mmi: MultiMeshInstance3D = _add_to_instancer(model_name, world_pos, yaw, scale_v)
			selected_node = mmi
			return mmi
	return null


func _instantiate_nature_prop(model_name: String, world_pos: Vector3, yaw: float, scale_v: float,
		layer: StringName, custom_parent: Node3D = null) -> Node3D:
	var target_parent: Node3D = custom_parent if custom_parent != null else cells_root
	if target_parent == null:
		return null
	var path: String = RegentsKitCatalog.NATURE_DIR + model_name + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var inst: Node3D = packed.instantiate() as Node3D
	inst.name = "%s_%d" % [model_name.to_lower(), _next_id("prop")]
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_v)
	if align_to_normal and terrain_brush != null:
		var nrm: Vector3 = terrain_brush.normal_at(world_pos.x, world_pos.z)
		var right: Vector3 = nrm.cross(Vector3.BACK).normalized()
		var fwd: Vector3 = right.cross(nrm).normalized()
		basis = (Basis(right, nrm, fwd) * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * scale_v)
	inst.set_meta(LAYER_META, layer)
	target_parent.add_child(inst)
	inst.global_transform = Transform3D(basis, world_pos)
	inst.owner = level_root
	return inst


func _ensure_nature_prop_group() -> PropGroup:
	if cells_root == null:
		return null
	var existing: PropGroup = cells_root.get_node_or_null("HandPropBatch") as PropGroup
	if existing != null:
		return existing
	var g := PropGroup.new()
	g.name = "HandPropBatch"
	g.set_meta(LAYER_META, LAYER_PROPS)
	cells_root.add_child(g)
	g.owner = level_root
	return g


func _add_to_instancer(model_name: String, world_pos: Vector3, yaw: float, scale_v: float) -> MultiMeshInstance3D:
	if instancer_root == null:
		return null
	var path: String = RegentsKitCatalog.NATURE_DIR + model_name + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	if not _instancer_xforms.has(model_name):
		_instancer_xforms[model_name] = []
	var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_v), world_pos)
	(_instancer_xforms[model_name] as Array).append(xform)
	var mmi: MultiMeshInstance3D = instancer_batches.get(model_name, null) as MultiMeshInstance3D
	if mmi == null:
		var temp: Node = (load(path) as PackedScene).instantiate()
		var first_mi: MeshInstance3D = temp as MeshInstance3D
		if first_mi == null:
			for c: Node in temp.find_children("*", "MeshInstance3D", true, false):
				first_mi = c as MeshInstance3D
				if first_mi != null and first_mi.mesh != null:
					break
		var mesh: Mesh = first_mi.mesh.duplicate() if (first_mi != null and first_mi.mesh != null) else BoxMesh.new()
		temp.free()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mmi = MultiMeshInstance3D.new()
		mmi.name = "Instancer_" + model_name
		mmi.multimesh = mm
		instancer_root.add_child(mmi)
		mmi.owner = level_root
		instancer_batches[model_name] = mmi
	var list: Array = _instancer_xforms[model_name] as Array
	mmi.multimesh.instance_count = list.size()
	for i: int in list.size():
		mmi.multimesh.set_instance_transform(i, list[i] as Transform3D)
	_push_undo({
		"kind": "instancer_add",
		"model": model_name,
		"xform": xform,
	})
	return mmi


# =============================================================================================
# 7. GAMEPLAY SPAWNS: NODES, STATIONS, FOES, ENCOUNTERS & POIS (WB8, WB11)
# =============================================================================================

## Place a `LevelPoint` under `Cells` (in `LAYER_GAMEPLAY`), attach its live 3D `RegentsPointPreview` &
## tactical rings, refresh packmate links if it is a pack foe, and record an Undo command.
func place_level_point(kind: String, tag: String = "", at: Vector3 = Vector3.ZERO, radius: float = 0.6,
		custom_id: String = "") -> LevelPoint:
	if cells_root == null:
		return null
	var wy: float = height_at(at.x, at.z)
	var world_pos := Vector3(at.x, wy, at.z)
	var prefix: String = (tag.to_lower().replace(" ", "_") if not tag.is_empty() else kind)
	var pid: String = custom_id if not custom_id.is_empty() else "%s_%d" % [prefix, _next_id(prefix)]
	var lp: LevelPoint = _make_point(kind, tag, world_pos, radius, pid, LAYER_GAMEPLAY)

	var terrain_before: Dictionary = {}
	var terrain_after: Dictionary = {}
	if kind == "station" and auto_flatten_footprints and terrain_brush != null:
		terrain_before = terrain_brush.flatten_footprint(world_pos, 0.0, Vector2(2.4, 2.4), 2.5)
		terrain_after = terrain_brush.capture_matching(terrain_before)

	cells_root.add_child(lp)
	lp.owner = level_root
	RegentsPointPreview.ensure_on(lp, show_gizmo_rings)
	_refresh_sibling_pack_links(lp)
	if ground_paint != null and (kind == "node" or kind == "station" or kind == "dummy" or kind == "guide"):
		ground_paint.repaint()

	_push_undo({
		"kind": "add_node",
		"node": lp,
		"parent": cells_root,
		"terrain_before": terrain_before,
		"terrain_after": terrain_after,
	})
	selected_node = lp
	return lp


## Stamp a multi-point encounter (`"skeleton_camp"`, `"wolf_pack"`, `"deer_pair"`) at `at` (WB8).
func stamp_encounter(preset: String, at: Vector3) -> Array[LevelPoint]:
	var made: Array[LevelPoint] = []
	match preset:
		"skeleton_camp":
			var offsets: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(3.0, 3.5), Vector2(4.0, -3.5), Vector2(8.0, 4.0)]
			var kinds: Array[String] = ["skeleton_warrior", "skeleton_axeman", "skeleton_warrior", "skeleton_archer"]
			for i: int in 4:
				var p: Vector3 = at + Vector3(offsets[i].x, 0.0, offsets[i].y)
				made.append(place_level_point(kinds[i], "", p, 0.5))
			made.append(place_level_point("poi", "Skeleton camp", at, 10.0))
		"wolf_pack":
			for i: int in 3:
				var ang: float = TAU * float(i) / 3.0
				var p: Vector3 = at if i == 0 else at + Vector3(cos(ang) * 4.0, 0.0, sin(ang) * 4.0)
				made.append(place_level_point("wolf", "", p, 0.5))
		"deer_pair":
			made.append(place_level_point("deer", "", at, 0.5))
			made.append(place_level_point("deer", "", at + Vector3(4.0, 0.0, 1.5), 0.5))
	return made


func _make_point(kind: String, tag: String, pos: Vector3, radius: float, pid: String, layer: StringName) -> LevelPoint:
	var lp := LevelPoint.new()
	lp.name = pid
	lp.point_id = pid
	lp.kind = kind
	lp.radius = radius
	if not tag.is_empty():
		lp.tags = PackedStringArray([tag])
	lp.position = pos
	lp.set_meta(LAYER_META, layer)
	return lp


func _refresh_sibling_pack_links(changed_point: LevelPoint) -> void:
	if changed_point == null or cells_root == null:
		return
	for c: Node in cells_root.get_children():
		var other: LevelPoint = c as LevelPoint
		if other != null and other != changed_point and other.kind == changed_point.kind:
			RegentsPointPreview.ensure_on(other, show_gizmo_rings)


## All World Map `poi` points currently in the level (`Array[LevelPoint]`).
func poi_points() -> Array[LevelPoint]:
	var out: Array[LevelPoint] = []
	if level_root == null:
		return out
	for n: Node in level_root.find_children("*", "Marker3D", true, false):
		var lp: LevelPoint = n as LevelPoint
		if lp != null and lp.kind == "poi":
			out.append(lp)
	return out


# =============================================================================================
# 8. FRIENDLY NPCS, WARDROBE & LIVE DIALOGUE / LORE STUDIO (WB9, WB10)
# =============================================================================================

## Create or update an `NpcDef` in memory (and optionally save to `save_path` if non-empty), then refresh
## any `LevelPoint` in the scene referencing `npc.key`.
func create_or_update_npc_def(key: StringName, display_name: String, title: String, outfit: String = "Noble",
		body: String = "male", dialogue_script: String = "", lore_entry: String = "",
		knight_tabard: bool = false, save_path: String = "") -> NpcDef:
	var npc: NpcDef = NpcDef.by_key(key)
	if npc == null:
		npc = NpcDef.new()
		npc.id = ContentLibrary.next_free_id(&"npc", "regents")
		npc.key = key
	npc.display_name = display_name
	npc.title = title
	npc.outfit = outfit
	npc.body = body
	npc.knight_tabard = knight_tabard
	npc.lore_entry = lore_entry
	if not dialogue_script.is_empty():
		npc.dialogue_script = dialogue_script
	elif npc.dialogue_script.is_empty():
		npc.dialogue_script = "~ start\n%s: [#cam=over_shoulder_npc] [#pose=interact] Greetings, traveler.\n=> END\n" % display_name
	if not save_path.is_empty():
		NpcDef.unregister_draft(npc.key)
		ResourceSaver.save(npc, save_path)
		RegentsContent.clear()
		NpcDef.clear_cache()
		RegentsKitCatalog.clear_cache()
	else:
		NpcDef.register_draft(npc)
	active_npc_def = npc
	_refresh_npc_previews(key)
	return npc


func _refresh_npc_previews(key: StringName) -> void:
	if level_root == null:
		return
	for n: Node in level_root.find_children("*", "Marker3D", true, false):
		var lp: LevelPoint = n as LevelPoint
		if lp != null and lp.kind == "npc" and not lp.tags.is_empty() and lp.tags[0] == String(key):
			RegentsPointPreview.ensure_on(lp, show_gizmo_rings)


## Start a live conversation test (`CinemaDialogue` + `CinemaBalloon`) with `npc` right in the World Builder
## (supports `CinemaBalloon.Style.OSRS_BOX`, `SPEECH_BUBBLE`, `PLAIN_SUBTITLE`, `REGENTS_CARD`, WB10).
func start_dialogue_test(npc: NpcDef, speaker_node: Node3D = null,
		balloon_style: int = CinemaBalloon.Style.REGENTS_CARD) -> bool:
	if npc == null or npc.dialogue_script.strip_edges().is_empty():
		return false
	var errs: Array[String] = NpcDef.validate_dialogue(npc.dialogue_script)
	if not errs.is_empty():
		return false
	active_npc_def = npc
	if balloon != null:
		balloon.visible = true
		balloon.set_world_camera(camera)
		balloon.set_style(balloon_style as CinemaBalloon.Style)
		if speaker_node != null:
			balloon.speaker_head_pos = speaker_node.global_position + Vector3(0.0, 1.8, 0.0)
		else:
			balloon.speaker_head_pos = cursor_pos + Vector3(0.0, 1.8, 0.0)
	dialogue_active = true
	dialogue.load_script(npc.dialogue_script)
	dialogue.start("start")
	return not dialogue.finished


func advance_dialogue() -> void:
	if dialogue_active:
		dialogue.advance()


func choose_dialogue_option(choice_idx: int) -> void:
	if dialogue_active:
		dialogue.choose(choice_idx)


func set_dialogue_balloon_style(s: CinemaBalloon.Style) -> void:
	if balloon != null:
		balloon.set_style(s)


func _on_dialogue_line(line: Dictionary) -> void:
	if balloon != null:
		balloon.show_line(line, DEF_GUIDE, 0, balloon.speaker_head_pos, false)


func _on_dialogue_choices(choices: Array[Dictionary]) -> void:
	if balloon != null:
		balloon.show_choices(choices)


func _on_dialogue_ended() -> void:
	dialogue_active = false
	if balloon != null:
		balloon.hide_all()
		balloon.visible = false


# =============================================================================================
# 9. UNDO / REDO STACK (`Ctrl+Z` / `Ctrl+Y`) (WB1, WB4)
# =============================================================================================

func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var cmd: Dictionary = _undo_stack.pop_back() as Dictionary
	var kind: String = String(cmd.get("kind", ""))
	match kind:
		"terrain":
			if terrain_brush != null:
				terrain_brush.restore_snapshot(cmd.get("before", {}) as Dictionary)
		"add_node":
			var node: Node = cmd.get("node", null) as Node
			var parent: Node = cmd.get("parent", null) as Node
			if node != null and is_instance_valid(node) and parent != null and node.get_parent() == parent:
				parent.remove_child(node)
			var t_before: Dictionary = cmd.get("terrain_before", {}) as Dictionary
			if not t_before.is_empty() and terrain_brush != null:
				terrain_brush.restore_snapshot(t_before)
			if ground_paint != null and ground_paint.painted():
				ground_paint.repaint()
		"instancer_add":
			var model_name: String = String(cmd.get("model", ""))
			if _instancer_xforms.has(model_name):
				var list: Array = _instancer_xforms[model_name] as Array
				if not list.is_empty():
					list.pop_back()
				var mmi: MultiMeshInstance3D = instancer_batches.get(model_name, null) as MultiMeshInstance3D
				if mmi != null:
					mmi.multimesh.instance_count = list.size()
					for i: int in list.size():
						mmi.multimesh.set_instance_transform(i, list[i] as Transform3D)
	_redo_stack.append(cmd)
	_refresh_status()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var cmd: Dictionary = _redo_stack.pop_back() as Dictionary
	var kind: String = String(cmd.get("kind", ""))
	match kind:
		"terrain":
			if terrain_brush != null:
				terrain_brush.restore_snapshot(cmd.get("after", {}) as Dictionary)
		"add_node":
			var node: Node = cmd.get("node", null) as Node
			var parent: Node = cmd.get("parent", null) as Node
			if node != null and is_instance_valid(node) and parent != null and node.get_parent() == null:
				parent.add_child(node)
				node.owner = level_root
			var t_after: Dictionary = cmd.get("terrain_after", {}) as Dictionary
			if not t_after.is_empty() and terrain_brush != null:
				terrain_brush.restore_snapshot(t_after)
			if ground_paint != null and ground_paint.painted():
				ground_paint.repaint()
		"instancer_add":
			var model_name: String = String(cmd.get("model", ""))
			var xform: Transform3D = cmd.get("xform", Transform3D.IDENTITY)
			if _instancer_xforms.has(model_name):
				var list: Array = _instancer_xforms[model_name] as Array
				list.append(xform)
				var mmi: MultiMeshInstance3D = instancer_batches.get(model_name, null) as MultiMeshInstance3D
				if mmi != null:
					mmi.multimesh.instance_count = list.size()
					for i: int in list.size():
						mmi.multimesh.set_instance_transform(i, list[i] as Transform3D)
	_undo_stack.append(cmd)
	_refresh_status()
	return true


func _push_undo(cmd: Dictionary) -> void:
	_undo_stack.append(cmd)
	for discarded: Dictionary in _redo_stack:
		if String(discarded.get("kind", "")) == "add_node":
			var orphan: Node = discarded.get("node", null) as Node
			if orphan != null and is_instance_valid(orphan) and orphan.get_parent() == null:
				orphan.free()
	_redo_stack.clear()
	_refresh_status()


# =============================================================================================
# 10. SAVE LEVEL, ONE-CLICK SERVER BAKE & SERVER-VIEW OVERLAY (WB1, WB12)
# =============================================================================================

## Save `level_root` to `scene_path` (`res://...` or `user://...`). Internal preview nodes (`INTERNAL_MODE_BACK`)
## are never packed by Godot's `PackedScene.pack`, keeping the saved `.tscn` clean for the server and game.
func save_level(scene_path: String) -> bool:
	if level_root == null or scene_path.is_empty():
		return false
	var abs_dir: String = ProjectSettings.globalize_path(scene_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)
	_own_level_tree(level_root)
	var packed := PackedScene.new()
	var err: Error = packed.pack(level_root)
	if err != OK:
		push_error("RegentsWorldBuilder: could not pack level (%s)" % error_string(err))
		return false
	err = ResourceSaver.save(packed, scene_path)
	if err != OK:
		push_error("RegentsWorldBuilder: could not save %s (%s)" % [scene_path, error_string(err)])
		return false
	level_root.scene_file_path = scene_path
	return true


## Bake the current level for the server (`LevelBaker.bake` + `LevelCells.cut` when `streamed == true`)
## into `out_dir` (`"res://shared/world/"` or a scratch `user://` dir for tests), and refresh the
## "What the Server Sees" overlay.
func bake_level(out_dir: String = "res://shared/world/") -> Dictionary:
	if level_root == null or level_info == null:
		return {"ok": false, "error": "no level loaded"}
	if level_root.scene_file_path.is_empty():
		level_root.scene_file_path = out_dir.path_join(level_info.level_name + ".tscn")
	last_bake_result = LevelBaker.bake(level_root, out_dir)
	if show_server_overlay:
		_rebuild_server_overlay()
	_refresh_status()
	return last_bake_result


## Toggle the "What the Server Sees" 3D overlay (`64 m` cell grid, water surface, bake bounds, and server point radii).
func set_server_overlay_visible(v: bool) -> void:
	show_server_overlay = v
	if v:
		_rebuild_server_overlay()
	elif _server_overlay_node != null:
		_server_overlay_node.visible = false


func _rebuild_server_overlay() -> void:
	if _overlay_root == null:
		return
	if _server_overlay_node != null and is_instance_valid(_server_overlay_node):
		_server_overlay_node.free()
	_server_overlay_node = Node3D.new()
	_server_overlay_node.name = "ServerViewOverlay"
	_server_overlay_node.visible = show_server_overlay
	_overlay_root.add_child(_server_overlay_node)
	if level_info == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var cell_m: float = Cells.cell_m()
	var b: AABB = level_info.bake_bounds
	var x0: float = floor(b.position.x / cell_m) * cell_m
	var x1: float = ceil(b.end.x / cell_m) * cell_m
	var z0: float = floor(b.position.z / cell_m) * cell_m
	var z1: float = ceil(b.end.z / cell_m) * cell_m
	var y: float = 0.25
	var x: float = x0
	while x <= x1 + 0.01:
		st.add_vertex(Vector3(x, y, z0))
		st.add_vertex(Vector3(x, y, z1))
		x += cell_m
	var z: float = z0
	while z <= z1 + 0.01:
		st.add_vertex(Vector3(x0, y, z))
		st.add_vertex(Vector3(x1, y, z))
		z += cell_m
	var grid_mi := MeshInstance3D.new()
	grid_mi.name = "CellGrid64m"
	grid_mi.mesh = st.commit()
	grid_mi.material_override = RegentsPointPreview._unshaded_mat(Color(0.25, 0.85, 1.0, 0.65))
	_server_overlay_node.add_child(grid_mi)


# =============================================================================================
# 11. PALETTE SELECTION, SCROLL CYCLING, GHOST PREVIEW & CLICK DISPATCH
# =============================================================================================

## Set the horizontal grid-snap step in meters (`0.0` = Free placement, `0.25`, `0.5`, `1.0`, `2.0`, `4.0`, or any custom value).
func set_grid_step_xz(step_m: float) -> void:
	grid_step_xz = maxf(step_m, 0.0)
	snap_grid = grid_step_xz > 0.0
	if _grid_xz_spin != null:
		_grid_xz_spin.set_value_no_signal(grid_step_xz)
	if _grid_snap_opt != null:
		var matched: bool = false
		for i: int in GRID_STEPS.size():
			if absf(GRID_STEPS[i] - grid_step_xz) <= 0.001:
				if _grid_snap_opt.selected != i:
					_grid_snap_opt.select(i)
				matched = true
				break
		if not matched and _grid_snap_opt.item_count > GRID_STEPS.size():
			_grid_snap_opt.select(GRID_STEPS.size())
	_sync_ghost_transform()
	_refresh_status()


## Set the vertical grid-snap step in meters (`3.0` default floor height, `0.0` = Free Y).
func set_grid_step_y(step_y: float) -> void:
	grid_step_y = maxf(step_y, 0.0)
	if _grid_y_spin != null:
		_grid_y_spin.set_value_no_signal(grid_step_y)
	set_story_level(story_level)


## Move `active_prefab_root`'s origin to `at` (keeping placed child pieces at their current world positions).
func set_active_prefab_origin(at: Vector3) -> void:
	if active_prefab_root == null or not is_instance_valid(active_prefab_root):
		return
	var saved_globals: Array[Transform3D] = []
	var kids: Array[Node3D] = []
	for c: Node in active_prefab_root.get_children():
		var n3: Node3D = c as Node3D
		if n3 != null:
			kids.append(n3)
			saved_globals.append(n3.global_transform)
	var new_origin := Vector3(at.x, height_at(at.x, at.z), at.z)
	if snap_grid and not free_place_held and grid_step_xz > 0.0:
		new_origin.x = snappedf(new_origin.x, grid_step_xz)
		new_origin.z = snappedf(new_origin.z, grid_step_xz)
		new_origin.y = height_at(new_origin.x, new_origin.z)
	active_prefab_root.global_position = new_origin
	for i: int in kids.size():
		kids[i].global_transform = saved_globals[i]
	_prefab_origin_locked = true
	_picking_prefab_origin = false
	_sync_prefab_box()
	_refresh_prefab_ui()
	_refresh_status()


func _release_search_focus() -> void:
	if _search_edit != null and _search_edit.has_focus():
		_search_edit.release_focus()


func select_category(cat: StringName) -> void:
	_release_search_focus()
	active_category = cat
	active_group_filter = ""
	_populate_group_filter()
	_refresh_palette()
	_update_right_panel_visibility()
	if not _palette_entries.is_empty():
		select_entry(String(_palette_entries[0]["id"]))


func select_group_filter(group_name: String) -> void:
	_release_search_focus()
	active_group_filter = group_name
	_refresh_palette()
	if not _palette_entries.is_empty():
		select_entry(String(_palette_entries[0]["id"]))


func select_entry(entry_id: String) -> void:
	active_entry_id = entry_id
	var entry: Dictionary = RegentsKitCatalog.find_entry(entry_id)
	if not entry.is_empty():
		active_category = entry.get("category", active_category) as StringName
		if String(entry.get("kind", "")) == "level_point" and String(entry.get("point_kind", "")) == "npc":
			active_npc_def = NpcDef.by_key(StringName(String(entry.get("tag", ""))))
			_populate_npc_inspector()
	if _palette_list != null:
		for i: int in _palette_entries.size():
			if String(_palette_entries[i].get("id", "")) == entry_id:
				if not _palette_list.is_selected(i):
					_palette_list.select(i)
				_palette_list.ensure_current_is_visible()
				break
	_update_right_panel_visibility()
	_rebuild_ghost_preview()
	_refresh_status()


func _update_right_panel_visibility() -> void:
	if _right_panel == null:
		return
	var has_active_prefab: bool = active_prefab_root != null and is_instance_valid(active_prefab_root)
	var show_npc: bool = (active_category == &"npcs")
	var show_prefab: bool = (not show_npc) and (active_category == &"settlements" or active_category == &"kit_pieces" or has_active_prefab)
	if _prefab_section != null:
		_prefab_section.visible = show_prefab
	if _npc_section != null:
		_npc_section.visible = show_npc
	_right_panel.visible = show_prefab or show_npc


## Step through the current palette list by `step` (`+1` next, `-1` previous) — used by Mouse Wheel or Up/Down arrows
## so you can rapidly preview and cycle kit pieces, buildings, props, rocks, foes, and NPCs right at the 3D cursor.
func cycle_palette_entry(step: int) -> String:
	if _palette_entries.is_empty():
		return active_entry_id
	var cur_idx: int = 0
	for i: int in _palette_entries.size():
		if String(_palette_entries[i].get("id", "")) == active_entry_id:
			cur_idx = i
			break
	var next_idx: int = posmod(cur_idx + step, _palette_entries.size())
	var next_id: String = String(_palette_entries[next_idx].get("id", ""))
	select_entry(next_id)
	return next_id


## Returns true if the currently selected tool is a terrain/clutter brush where Mouse Wheel should resize the brush
## and holding LMB should paint/sculpt continuously along the drag path.
func is_brush_tool_active() -> bool:
	var entry: Dictionary = RegentsKitCatalog.find_entry(active_entry_id)
	var kind: String = String(entry.get("kind", ""))
	return kind == "terrain_brush" or kind == "terrain_paint" or kind == "clutter_erase"


## True if `mouse_pos` (viewport coordinates) is hovering over the Top Bar, Left Palette, or Right Studio Panel
## so mouse clicks/scrolls on UI never trigger 3D world actions or move the 3D ground cursor.
func _is_mouse_over_ui(mouse_pos: Vector2) -> bool:
	if _top_bar != null and _top_bar.visible and _top_bar.get_global_rect().has_point(mouse_pos):
		return true
	if _left_panel != null and _left_panel.visible and _left_panel.get_global_rect().has_point(mouse_pos):
		return true
	if _right_panel != null and _right_panel.visible and _right_panel.get_global_rect().has_point(mouse_pos):
		return true
	if balloon != null and balloon.visible:
		return true
	if get_viewport() != null:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered != null and hovered.is_visible_in_tree():
			return true
	return false


## True if a `LineEdit` or `TextEdit` currently owns keyboard focus (so typing letters doesn't fly or rotate).
func _is_typing_in_text_box() -> bool:
	if get_viewport() == null:
		return false
	var f: Control = get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Project a ray from `camera` through `mouse_pos` (viewport pixel coordinates) onto the `Terrain3D` heightfield,
## updating `cursor_pos`, `_cursor_ring`, and `_ghost_root` so the circle and ghost follow the mouse smoothly.
func update_cursor_from_mouse(mouse_pos: Vector2) -> Vector3:
	if camera == null:
		return cursor_pos
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	return update_cursor_from_ray(ray_origin, ray_dir)


## Intersect a 3D ray `(ray_origin, ray_dir)` with the terrain surface (plus `story_level * 3 m` when placing kit pieces),
## applying grid snapping when active (and bypassed when holding `Alt` / `Shift`), and updating `_cursor_ring` + `_ghost_root`.
func update_cursor_from_ray(ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var dir: Vector3 = ray_dir.normalized()
	var hit_pos: Vector3 = cursor_pos
	var found: bool = false
	var prev_d: float = 0.5
	var prev_above: float = ray_origin.y + dir.y * prev_d - height_at(ray_origin.x + dir.x * prev_d, ray_origin.z + dir.z * prev_d)
	var d: float = 2.5
	while d <= 600.0:
		var p: Vector3 = ray_origin + dir * d
		var gh: float = height_at(p.x, p.z)
		var above: float = p.y - gh
		if above <= 0.0 and prev_above >= 0.0:
			var lo: float = prev_d
			var hi: float = d
			for _iter: int in 6:
				var mid: float = 0.5 * (lo + hi)
				var mp: Vector3 = ray_origin + dir * mid
				if mp.y - height_at(mp.x, mp.z) > 0.0:
					lo = mid
				else:
					hi = mid
			var final_p: Vector3 = ray_origin + dir * (0.5 * (lo + hi))
			hit_pos = Vector3(final_p.x, height_at(final_p.x, final_p.z), final_p.z)
			found = true
			break
		prev_d = d
		prev_above = above
		d += 2.0
	if not found and dir.y < -0.01:
		var t: float = clampf(-ray_origin.y / dir.y, 1.0, 400.0)
		var p2: Vector3 = ray_origin + dir * t
		hit_pos = Vector3(p2.x, height_at(p2.x, p2.z), p2.z)
		found = true
	if found:
		var entry: Dictionary = RegentsKitCatalog.find_entry(active_entry_id)
		var kind: String = String(entry.get("kind", ""))
		var snap_now: bool = snap_grid and not free_place_held and grid_step_xz > 0.0
		if kind == "kit_piece":
			var piece_name: String = String(entry.get("piece", ""))
			var is_struct: bool = not piece_name.begins_with("Prop_") and ResourceLoader.exists(TownKit.VILLAGE + piece_name + ".gltf")
			if snap_now:
				var gx: float = grid_step_xz if (is_struct or absf(grid_step_xz - 2.0) > 0.001) else 0.25
				hit_pos.x = snappedf(hit_pos.x, gx)
				hit_pos.z = snappedf(hit_pos.z, gx)
			hit_pos.y = height_at(hit_pos.x, hit_pos.z) + float(story_level) * grid_step_y
		elif snap_now and (kind == "kit_house" or kind == "demo_house" or kind == "custom_preset" or kind == "nature_prop" or kind == "furnish"):
			if absf(grid_step_xz - 2.0) > 0.001 or kind == "kit_house" or kind == "demo_house" or kind == "custom_preset":
				hit_pos.x = snappedf(hit_pos.x, grid_step_xz)
				hit_pos.z = snappedf(hit_pos.z, grid_step_xz)
				hit_pos.y = height_at(hit_pos.x, hit_pos.z)
		cursor_pos = hit_pos
		cursor_normal = terrain_brush.normal_at(cursor_pos.x, cursor_pos.z) if terrain_brush != null else Vector3.UP
		if _cursor_ring != null:
			_cursor_ring.global_position = Vector3(cursor_pos.x, height_at(cursor_pos.x, cursor_pos.z) + 0.08, cursor_pos.z)
		_sync_ghost_transform()
	return cursor_pos


## Execute the currently selected catalog entry at `at` (called on LMB click in the 3D viewport or by tests).
func use_active_tool_at(at: Vector3) -> Variant:
	if _picking_prefab_origin and active_prefab_root != null and is_instance_valid(active_prefab_root):
		set_active_prefab_origin(at)
		return active_prefab_root
	var entry: Dictionary = RegentsKitCatalog.find_entry(active_entry_id)
	if entry.is_empty():
		return null
	var kind: String = String(entry.get("kind", ""))
	match kind:
		"terrain_brush":
			apply_terrain_brush(at, int(entry.get("mode", RegentsTerrainBrush.Mode.RAISE)))
			return true
		"terrain_paint":
			if terrain_brush != null:
				terrain_brush.paint_tex = int(entry.get("tex", RegentsTerrainBrush.Tex.GRASS))
			apply_terrain_brush(at, RegentsTerrainBrush.Mode.PAINT_TEXTURE)
			return true
		"terrain_ramp":
			if ramp_start_point == Vector3.INF:
				ramp_start_point = at
				return false
			var start_p: Vector3 = ramp_start_point
			ramp_start_point = Vector3.INF
			carve_terrain_ramp(start_p, at, 4.0)
			return true
		"road_spline":
			road_draft_points.append(at)
			if road_draft_points.size() >= 2:
				var pts: PackedVector3Array = road_draft_points.duplicate()
				road_draft_points.clear()
				return draw_road_spline(pts, String(entry.get("surface", "dirt")), 3.0, true)
			return null
		"clutter_scatter":
			return scatter_clutter()
		"clutter_erase":
			return erase_clutter_at(at, terrain_brush.radius_m if terrain_brush != null else 4.0)
		"settlement":
			return create_settlement("Settlement %d" % _next_id("town"), at, 1)
		"kit_house":
			return stamp_kit_house(at, place_yaw, entry)
		"demo_house", "custom_preset":
			return stamp_demo_house(String(entry.get("scene", "")), at, place_yaw, entry.get("footprint", Vector2(10, 10)) as Vector2)
		"castle_wall":
			var corners := PackedVector3Array([
				at + Vector3(-16.0, 0.0, -16.0),
				at + Vector3(16.0, 0.0, -16.0),
				at + Vector3(16.0, 0.0, 16.0),
				at + Vector3(-16.0, 0.0, 16.0),
			])
			var roofed: bool = bool(entry.get("roofed", false))
			return build_castle_wall(corners, PackedInt32Array() if roofed else PackedInt32Array([0]), roofed)
		"furnish":
			return stamp_furnishing(String(entry.get("preset", "market")), at, place_yaw)
		"kit_piece":
			var piece_at: Vector3 = at
			if piece_at.y <= height_at(piece_at.x, piece_at.z) + 0.01 and story_level > 0:
				piece_at.y = height_at(piece_at.x, piece_at.z) + float(story_level) * grid_step_y
			return place_kit_piece(String(entry.get("piece", "")), piece_at, place_yaw, snap_grid and not free_place_held)
		"nature_prop":
			return place_nature_prop(String(entry.get("model", "")), at, place_yaw, place_scale)
		"level_point":
			return place_level_point(String(entry.get("point_kind", "node")), String(entry.get("tag", "")), at, float(entry.get("radius", 0.6)))
		"encounter_stamp":
			return stamp_encounter(String(entry.get("preset", "skeleton_camp")), at)
		"move_spawn":
			if spawn_marker != null:
				spawn_marker.position = Vector3(at.x, height_at(at.x, at.z), at.z)
				return spawn_marker
	return null


# =============================================================================================
# 12. ENVIRONMENT, 3D GHOST PREVIEW, OVERLAYS, INPUT & RESIZABLE UI
# =============================================================================================

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "BuilderEnvironment"
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sky_top_color = Color(0.35, 0.52, 0.78)
	_sky.sky_horizon_color = Color(0.72, 0.78, 0.84)
	_sky.ground_horizon_color = Color(0.60, 0.62, 0.60)
	sky.sky_material = _sky
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.name = "BuilderSun"
	_sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	_sun.light_color = Color(1.0, 0.96, 0.90)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 260.0
	add_child(_sun)

	camera = Camera3D.new()
	camera.name = "BuilderCamera"
	camera.far = 2500.0
	add_child(camera)


func _build_overlays() -> void:
	_overlay_root = Node3D.new()
	_overlay_root.name = "BuilderOverlays"
	add_child(_overlay_root)

	_cursor_ring = MeshInstance3D.new()
	_cursor_ring.name = "CursorRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 7.4
	torus.outer_radius = 8.0
	_cursor_ring.mesh = torus
	_cursor_ring.material_override = RegentsPointPreview._unshaded_mat(Color(0.35, 0.95, 0.65, 0.85))
	_cursor_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay_root.add_child(_cursor_ring)

	_ghost_root = Node3D.new()
	_ghost_root.name = "GhostPreview"
	_overlay_root.add_child(_ghost_root)

	_prefab_box_node = MeshInstance3D.new()
	_prefab_box_node.name = "ActivePrefabBox"
	_prefab_box_node.visible = false
	_prefab_box_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay_root.add_child(_prefab_box_node)


## Rebuild the live 3D Ghost Preview inside `_ghost_root` for the currently selected catalog entry so the
## designer sees the exact building, kit piece, prop, rock, gathering node, foe, or NPC under their mouse cursor.
func _rebuild_ghost_preview() -> void:
	if _ghost_root == null:
		return
	RegentsPointPreview._clear_materials(_ghost_root)
	for c: Node in _ghost_root.get_children():
		_ghost_root.remove_child(c)
		c.free()
	var entry: Dictionary = RegentsKitCatalog.find_entry(active_entry_id)
	if entry.is_empty():
		return
	var kind: String = String(entry.get("kind", ""))
	if _cursor_ring != null:
		var ring_col := Color(0.35, 0.95, 0.65, 0.85)
		if kind == "terrain_paint":
			ring_col = Color(1.0, 0.82, 0.28, 0.9)
		elif kind == "terrain_brush" or kind == "clutter_erase":
			ring_col = Color(0.35, 0.85, 1.0, 0.85)
		_cursor_ring.material_override = RegentsPointPreview._unshaded_mat(ring_col)
		if is_brush_tool_active():
			set_brush_radius(brush_radius())
		elif _cursor_ring.mesh is TorusMesh:
			var t: TorusMesh = _cursor_ring.mesh as TorusMesh
			t.outer_radius = 1.6
			t.inner_radius = 1.45

	match kind:
		"kit_piece":
			var piece_name: String = String(entry.get("piece", ""))
			if TownKit.has_piece(piece_name):
				var inst: Node3D = TownKit.piece(piece_name).instantiate() as Node3D
				_ghost_root.add_child(inst)
				_strip_ghost_colliders(inst)
				_apply_ghost_tint(inst, Color(0.55, 0.95, 0.85, 0.62))
		"kit_house":
			var h := KitHouse.new()
			h.width = int(entry.get("width", house_width))
			h.depth = int(entry.get("depth", house_depth))
			h.floors = int(entry.get("floors", house_floors))
			h.ground = int(entry.get("ground", house_ground)) as KitHouse.Finish
			h.upper = int(entry.get("upper", house_upper)) as KitHouse.Finish
			h.tiles = int(entry.get("tiles", house_tiles)) as KitHouse.Tiles
			h.house_seed = house_seed
			_ghost_root.add_child(h)
			h.build()
			_strip_ghost_colliders(h)
			_apply_ghost_tint(h, Color(0.55, 0.95, 0.85, 0.58))
		"demo_house", "custom_preset":
			var sp: String = String(entry.get("scene", ""))
			if ResourceLoader.exists(sp):
				var packed: PackedScene = load(sp) as PackedScene
				if packed != null:
					var inst: Node3D = packed.instantiate() as Node3D
					if kind == "custom_preset":
						_recenter_prefab_children(inst)
					_ghost_root.add_child(inst)
					_strip_ghost_colliders(inst)
					_apply_ghost_tint(inst, Color(0.55, 0.95, 0.85, 0.58))
		"furnish":
			var rng := RandomNumberGenerator.new()
			rng.seed = 2611
			var holder := Node3D.new()
			_ghost_root.add_child(holder)
			var preset: String = String(entry.get("preset", "market"))
			match preset:
				"market":
					TownFurnish.market(holder, Vector3.ZERO, Vector2(18.0, 14.0), 5.5, 3.0, rng)
				"green":
					TownFurnish.green(holder, Vector3.ZERO, rng)
				"inn_front":
					TownFurnish.inn_front(holder, Vector3.ZERO, rng)
				"training":
					var g := PropGroup.new()
					TownFurnish.training(g, Vector3.ZERO, rng)
					holder.add_child(g)
				"smithy":
					var g2 := PropGroup.new()
					TownFurnish.smithy(g2, Vector3.ZERO)
					holder.add_child(g2)
			_strip_ghost_colliders(holder)
			_apply_ghost_tint(holder, Color(0.55, 0.95, 0.85, 0.58))
		"nature_prop":
			var model_name: String = String(entry.get("model", ""))
			var path: String = RegentsKitCatalog.NATURE_DIR + model_name + ".gltf"
			if ResourceLoader.exists(path):
				var inst: Node3D = (load(path) as PackedScene).instantiate() as Node3D
				_ghost_root.add_child(inst)
				_strip_ghost_colliders(inst)
				_apply_ghost_tint(inst, Color(0.65, 1.0, 0.72, 0.65))
		"level_point":
			var dummy_pt := LevelPoint.new()
			dummy_pt.point_id = "ghost_preview"
			dummy_pt.kind = String(entry.get("point_kind", "node"))
			dummy_pt.radius = float(entry.get("radius", 0.6))
			var tag: String = String(entry.get("tag", ""))
			if not tag.is_empty():
				dummy_pt.tags = PackedStringArray([tag])
			_ghost_root.add_child(dummy_pt)
			RegentsPointPreview.ensure_on(dummy_pt, true)
	if _ghost_root.get_child_count() > 0:
		_add_ghost_facing_arrow(_ghost_root)
	_sync_ghost_transform()


func _sync_ghost_transform() -> void:
	if _ghost_root == null:
		return
	_ghost_root.global_position = cursor_pos
	var rot_y: float = place_yaw
	var entry: Dictionary = RegentsKitCatalog.find_entry(active_entry_id)
	if String(entry.get("kind", "")) == "kit_piece" and snap_grid and not free_place_held and grid_step_xz > 0.0:
		var piece_name: String = String(entry.get("piece", ""))
		var is_struct: bool = not piece_name.begins_with("Prop_") and ResourceLoader.exists(TownKit.VILLAGE + piece_name + ".gltf")
		rot_y = snappedf(rot_y, PI * 0.5 if is_struct else PI / 12.0)
	_ghost_root.rotation = Vector3(0.0, rot_y, 0.0)
	var sc: float = place_scale if String(entry.get("kind", "")) == "nature_prop" else 1.0
	_ghost_root.scale = Vector3.ONE * sc


static func _strip_ghost_colliders(root: Node) -> void:
	for n: Node in root.find_children("*", "CollisionObject3D", true, false):
		var co: CollisionObject3D = n as CollisionObject3D
		if co != null:
			co.collision_layer = 0
			co.collision_mask = 0


static func _apply_ghost_tint(root: Node, color: Color) -> void:
	var mat: StandardMaterial3D = RegentsPointPreview._unshaded_mat(color)
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi != null:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.material_override = mat


static func _add_ghost_facing_arrow(parent: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.add_vertex(Vector3(0.0, 0.25, 0.0))
	st.add_vertex(Vector3(0.0, 0.25, 1.8))
	st.add_vertex(Vector3(0.0, 0.25, 1.8))
	st.add_vertex(Vector3(-0.35, 0.25, 1.35))
	st.add_vertex(Vector3(0.0, 0.25, 1.8))
	st.add_vertex(Vector3(0.35, 0.25, 1.35))
	var mi := MeshInstance3D.new()
	mi.name = "GhostArrow"
	mi.mesh = st.commit()
	mi.material_override = RegentsPointPreview._unshaded_mat(Color(1.0, 0.88, 0.25, 0.95))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _local_xf_in(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func _prefab_local_bounds(root: Node3D) -> AABB:
	var has_box: bool = false
	var box := AABB()
	for c: Node in root.get_children():
		if c is StaticBody3D or c is CollisionShape3D:
			continue
		var c3: Node3D = c as Node3D
		if c3 == null:
			continue
		var sub_meshes: Array[Node] = c3.find_children("*", "MeshInstance3D", true, false)
		if c3 is MeshInstance3D:
			sub_meshes.append(c3)
		if sub_meshes.is_empty():
			var pt_box := AABB(c3.position - Vector3(1.0, 0.0, 1.0), Vector3(2.0, 3.0, 2.0))
			box = pt_box if not has_box else box.merge(pt_box)
			has_box = true
			continue
		for mn: Node in sub_meshes:
			var mi: MeshInstance3D = mn as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var rel_xf: Transform3D = _local_xf_in(root, mi)
			var maabb: AABB = rel_xf * mi.mesh.get_aabb()
			box = maabb if not has_box else box.merge(maabb)
			has_box = true
	if not has_box:
		return AABB(Vector3(-1.5, 0.0, -1.5), Vector3(3.0, 3.0, 3.0))
	return box.grow(0.35)


func _sync_prefab_box() -> void:
	if _prefab_box_node == null:
		return
	if active_prefab_root == null or not is_instance_valid(active_prefab_root):
		_prefab_box_node.visible = false
		return
	if active_prefab_root.get_child_count() == 0 and not _prefab_origin_locked:
		_prefab_box_node.visible = false
		return
	var box: AABB = _prefab_local_bounds(active_prefab_root)
	var p0: Vector3 = box.position
	var p1: Vector3 = box.end
	p0.y = maxf(p0.y, 0.05)
	p1.y = maxf(p1.y, p0.y + 3.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var corners: Array[Vector3] = [
		Vector3(p0.x, p0.y, p0.z), Vector3(p1.x, p0.y, p0.z), Vector3(p1.x, p0.y, p1.z), Vector3(p0.x, p0.y, p1.z),
		Vector3(p0.x, p1.y, p0.z), Vector3(p1.x, p1.y, p0.z), Vector3(p1.x, p1.y, p1.z), Vector3(p0.x, p1.y, p1.z),
	]
	for i: int in 4:
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 4])
		st.add_vertex(corners[i + 4])
		st.add_vertex(corners[((i + 1) % 4) + 4])
		st.add_vertex(corners[i])
		st.add_vertex(corners[i + 4])
	# Origin crosshair marker
	st.add_vertex(Vector3(-0.7, 0.15, 0.0))
	st.add_vertex(Vector3(0.7, 0.15, 0.0))
	st.add_vertex(Vector3(0.0, 0.15, -0.7))
	st.add_vertex(Vector3(0.0, 0.15, 0.7))
	_prefab_box_node.mesh = st.commit()
	_prefab_box_node.material_override = RegentsPointPreview._unshaded_mat(Color(1.0, 0.82, 0.25, 0.88))
	_prefab_box_node.global_position = active_prefab_root.global_position
	_prefab_box_node.visible = true


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "BuilderUI"
	add_child(_ui_layer)

	var root_ctrl := Control.new()
	root_ctrl.name = "RootControl"
	root_ctrl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root_ctrl)

	# Top toolbar with live status + Grid Snap + Brush Size & Strength sliders + action buttons
	_top_bar = PanelContainer.new()
	_top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_bar.custom_minimum_size = Vector2(0, 46)
	root_ctrl.add_child(_top_bar)
	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	_top_bar.add_child(top_hbox)

	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.clip_text = true
	top_hbox.add_child(_status_label)

	_grid_snap_opt = OptionButton.new()
	_grid_snap_opt.focus_mode = Control.FOCUS_NONE
	_grid_snap_opt.tooltip_text = "Grid Snap Preset (G to toggle, or hold Shift / Alt for Free Placement)"
	for lbl: String in GRID_STEP_LABELS:
		_grid_snap_opt.add_item(lbl)
	_grid_snap_opt.select(4)   # Default: 2.0m
	_grid_snap_opt.item_selected.connect(func(idx: int) -> void:
		if idx >= 0 and idx < GRID_STEPS.size():
			set_grid_step_xz(GRID_STEPS[idx]))
	top_hbox.add_child(_grid_snap_opt)

	_grid_xz_spin = SpinBox.new()
	_grid_xz_spin.min_value = 0.0
	_grid_xz_spin.max_value = 64.0
	_grid_xz_spin.step = 0.25
	_grid_xz_spin.value = grid_step_xz
	_grid_xz_spin.suffix = "m XZ"
	_grid_xz_spin.custom_minimum_size = Vector2(88, 26)
	_grid_xz_spin.tooltip_text = "Horizontal grid snap step in meters (0 = Free)"
	_grid_xz_spin.value_changed.connect(set_grid_step_xz)
	var xz_le: LineEdit = _grid_xz_spin.get_line_edit()
	if xz_le != null:
		xz_le.text_submitted.connect(func(_t: String) -> void:
			if get_viewport() != null:
				get_viewport().gui_release_focus())
	top_hbox.add_child(_grid_xz_spin)

	_grid_y_spin = SpinBox.new()
	_grid_y_spin.min_value = 0.0
	_grid_y_spin.max_value = 32.0
	_grid_y_spin.step = 0.1
	_grid_y_spin.value = grid_step_y
	_grid_y_spin.suffix = "m Y"
	_grid_y_spin.custom_minimum_size = Vector2(84, 26)
	_grid_y_spin.tooltip_text = "Vertical floor / Y snap step in meters (0 = Free Y)"
	_grid_y_spin.value_changed.connect(set_grid_step_y)
	var y_le: LineEdit = _grid_y_spin.get_line_edit()
	if y_le != null:
		y_le.text_submitted.connect(func(_t: String) -> void:
			if get_viewport() != null:
				get_viewport().gui_release_focus())
	top_hbox.add_child(_grid_y_spin)

	_brush_radius_label = Label.new()
	_brush_radius_label.text = "Brush: 8.0m"
	top_hbox.add_child(_brush_radius_label)

	_brush_radius_slider = HSlider.new()
	_brush_radius_slider.focus_mode = Control.FOCUS_NONE
	_brush_radius_slider.min_value = 0.5
	_brush_radius_slider.max_value = 48.0
	_brush_radius_slider.step = 0.5
	_brush_radius_slider.value = 8.0
	_brush_radius_slider.custom_minimum_size = Vector2(100, 24)
	_brush_radius_slider.tooltip_text = "Brush Size (0.5m - 48m) · [ / ] or Shift+Scroll"
	_brush_radius_slider.value_changed.connect(set_brush_radius)
	top_hbox.add_child(_brush_radius_slider)

	_brush_strength_label = Label.new()
	_brush_strength_label.text = "Str: 1.5"
	top_hbox.add_child(_brush_strength_label)

	_brush_strength_slider = HSlider.new()
	_brush_strength_slider.focus_mode = Control.FOCUS_NONE
	_brush_strength_slider.min_value = 0.2
	_brush_strength_slider.max_value = 12.0
	_brush_strength_slider.step = 0.2
	_brush_strength_slider.value = 1.5
	_brush_strength_slider.custom_minimum_size = Vector2(72, 24)
	_brush_strength_slider.tooltip_text = "Sculpt Brush Strength"
	_brush_strength_slider.value_changed.connect(set_brush_strength)
	top_hbox.add_child(_brush_strength_slider)

	var btn_fly_walk := Button.new()
	btn_fly_walk.focus_mode = Control.FOCUS_NONE
	btn_fly_walk.text = "Fly / Walk (Tab)"
	btn_fly_walk.pressed.connect(toggle_camera_mode)
	top_hbox.add_child(btn_fly_walk)

	var btn_undo := Button.new()
	btn_undo.focus_mode = Control.FOCUS_NONE
	btn_undo.text = "Undo"
	btn_undo.tooltip_text = "Undo (Ctrl+Z)"
	btn_undo.pressed.connect(undo)
	top_hbox.add_child(btn_undo)

	var btn_redo := Button.new()
	btn_redo.focus_mode = Control.FOCUS_NONE
	btn_redo.text = "Redo"
	btn_redo.tooltip_text = "Redo (Ctrl+Y)"
	btn_redo.pressed.connect(redo)
	top_hbox.add_child(btn_redo)

	var btn_server := Button.new()
	btn_server.focus_mode = Control.FOCUS_NONE
	btn_server.text = "Server View (F2)"
	btn_server.pressed.connect(func() -> void: set_server_overlay_visible(not show_server_overlay))
	top_hbox.add_child(btn_server)

	var btn_bake := Button.new()
	btn_bake.focus_mode = Control.FOCUS_NONE
	btn_bake.text = "Bake World"
	btn_bake.pressed.connect(func() -> void: bake_level())
	top_hbox.add_child(btn_bake)

	# Main Resizable Split Layout (Left Palette | Center 3D Viewport | Conditional Right Studio)
	_left_split = HSplitContainer.new()
	_left_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left_split.offset_top = 48
	_left_split.offset_left = 8
	_left_split.offset_right = -8
	_left_split.offset_bottom = -8
	_left_split.split_offset = 390
	_left_split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_left_split)

	# Left Asset & Tool Palette (Resizable!)
	_left_panel = PanelContainer.new()
	_left_panel.custom_minimum_size = Vector2(260, 480)
	_left_split.add_child(_left_panel)
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	_left_panel.add_child(left_vbox)

	_category_box = HBoxContainer.new()
	left_vbox.add_child(_category_box)
	const SHORT_CAT: PackedStringArray = ["1.Land", "2.Towns", "3.Pieces", "4.Nature", "5.Skill", "6.Foes", "7.NPCs"]
	for i: int in RegentsKitCatalog.CATEGORIES.size():
		var cat: StringName = RegentsKitCatalog.CATEGORIES[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = SHORT_CAT[i] if i < SHORT_CAT.size() else str(i + 1)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = RegentsKitCatalog.CATEGORY_LABELS[cat]
		b.pressed.connect(select_category.bind(cat))
		_category_box.add_child(b)

	_group_filter_opt = OptionButton.new()
	_group_filter_opt.focus_mode = Control.FOCUS_NONE
	_group_filter_opt.tooltip_text = "Filter by sub-group (Walls, Roofs, Doors, Props, Rocks...)"
	_group_filter_opt.item_selected.connect(func(idx: int) -> void:
		if idx <= 0:
			select_group_filter("")
		else:
			select_group_filter(_group_filter_opt.get_item_text(idx)))
	left_vbox.add_child(_group_filter_opt)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search pieces, houses, rocks, foes, NPCs..."
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(func(_t: String) -> void:
		_refresh_palette()
		if not _palette_entries.is_empty():
			select_entry(String(_palette_entries[0]["id"])))
	_search_edit.text_submitted.connect(func(_t: String) -> void:
		_release_search_focus())
	left_vbox.add_child(_search_edit)

	var hint_lbl := Label.new()
	hint_lbl.text = "Scroll in 3D: cycle pieces · R: rotate · Hold Shift/Alt: free place"
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.modulate = Color(0.78, 0.88, 0.96)
	left_vbox.add_child(hint_lbl)

	# FOCUS_NONE on `_palette_list` prevents Godot's ItemList from hijacking R / W / A / S / D for alphabetical search!
	_palette_list = ItemList.new()
	_palette_list.focus_mode = Control.FOCUS_NONE
	_palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_palette_list.item_selected.connect(func(idx: int) -> void:
		_release_search_focus()
		if idx >= 0 and idx < _palette_entries.size():
			select_entry(String(_palette_entries[idx]["id"])))
	left_vbox.add_child(_palette_list)

	# Right Split Container (Center Pass-Through Viewport | Conditional Right Studio Panel)
	_right_split = HSplitContainer.new()
	_right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_split.split_offset = -400
	_right_split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_split.add_child(_right_split)

	var center_viewport_pass := Control.new()
	center_viewport_pass.name = "ViewportPassThrough"
	center_viewport_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_viewport_pass.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_viewport_pass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_split.add_child(center_viewport_pass)

	# Right Inspector: Conditional — shows ONLY Prefab Studio (in 2.Towns / 3.Pieces) or NPC Studio (in 7.NPCs)!
	_right_panel = PanelContainer.new()
	_right_panel.custom_minimum_size = Vector2(300, 480)
	_right_split.add_child(_right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_panel.add_child(right_scroll)

	_inspector_box = VBoxContainer.new()
	_inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_box.add_theme_constant_override("separation", 6)
	right_scroll.add_child(_inspector_box)

	# --- 1. CONDITIONAL PREFAB BUILDER STUDIO (Shown in 2.Towns & 3.Pieces) ---
	_prefab_section = VBoxContainer.new()
	_prefab_section.add_theme_constant_override("separation", 6)
	_inspector_box.add_child(_prefab_section)

	var prefab_header := Label.new()
	prefab_header.text = "Building & Prefab Studio"
	prefab_header.modulate = Color(1.0, 0.88, 0.45)
	_prefab_section.add_child(prefab_header)

	var prefab_help := Label.new()
	prefab_help.text = "• Click '1. Start New Prefab', then place your 1st piece in 3D (that sets origin, or click 'Pick Origin in 3D').\n• Hold Shift or Alt for free (non-grid) placement.\n• Click '3. Save Prefab' to center & save to '2.Towns -> Saved Custom Presets'."
	prefab_help.add_theme_font_size_override("font_size", 12)
	prefab_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prefab_section.add_child(prefab_help)

	_prefab_name_edit = LineEdit.new()
	_prefab_name_edit.placeholder_text = "Prefab Name (e.g. blacksmith_shop)"
	_prefab_name_edit.text = "custom_cottage"
	_prefab_section.add_child(_prefab_name_edit)

	var prefab_btns := HBoxContainer.new()
	_prefab_section.add_child(prefab_btns)

	var btn_start_prefab := Button.new()
	btn_start_prefab.focus_mode = Control.FOCUS_NONE
	btn_start_prefab.text = "1. Start New Prefab"
	btn_start_prefab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_start_prefab.pressed.connect(func() -> void:
		start_new_prefab(_prefab_name_edit.text if _prefab_name_edit != null else "custom_cottage")
		select_category(&"kit_pieces"))
	prefab_btns.add_child(btn_start_prefab)

	var btn_save_prefab := Button.new()
	btn_save_prefab.focus_mode = Control.FOCUS_NONE
	btn_save_prefab.text = "3. Save Prefab"
	btn_save_prefab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_save_prefab.pressed.connect(func() -> void:
		save_active_prefab(_prefab_name_edit.text if _prefab_name_edit != null else ""))
	prefab_btns.add_child(btn_save_prefab)

	var origin_row := HBoxContainer.new()
	_prefab_section.add_child(origin_row)

	var btn_set_origin := Button.new()
	btn_set_origin.focus_mode = Control.FOCUS_NONE
	btn_set_origin.text = "Pick Origin in 3D"
	btn_set_origin.tooltip_text = "Click, then left-click in the 3D viewport to place this prefab's origin"
	btn_set_origin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_set_origin.pressed.connect(func() -> void:
		if active_prefab_root == null or not is_instance_valid(active_prefab_root):
			start_new_prefab(_prefab_name_edit.text if _prefab_name_edit != null else "custom_cottage")
			select_category(&"kit_pieces")
		_picking_prefab_origin = not _picking_prefab_origin
		_refresh_prefab_ui())
	origin_row.add_child(btn_set_origin)

	var btn_done_prefab := Button.new()
	btn_done_prefab.focus_mode = Control.FOCUS_NONE
	btn_done_prefab.text = "Finish Prefab"
	btn_done_prefab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_done_prefab.pressed.connect(finish_active_prefab)
	origin_row.add_child(btn_done_prefab)

	var story_row := HBoxContainer.new()
	_prefab_section.add_child(story_row)
	_story_label = Label.new()
	_story_label.text = "Floor 1 (+0m)"
	_story_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_row.add_child(_story_label)
	for fl: int in 4:
		var fb := Button.new()
		fb.focus_mode = Control.FOCUS_NONE
		fb.text = "F%d" % (fl + 1) if fl < 3 else "Roof"
		fb.tooltip_text = "Snap height +%dm (Z/X keys)" % (fl * 3)
		fb.pressed.connect(set_story_level.bind(fl))
		story_row.add_child(fb)

	_prefab_status_label = Label.new()
	_prefab_status_label.text = "Prefab: None active (placing directly in world)"
	_prefab_status_label.add_theme_font_size_override("font_size", 12)
	_prefab_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prefab_section.add_child(_prefab_status_label)

	# --- 2. CONDITIONAL NPC CREATOR, APPEARANCE, WARDROBE, LORE & DIALOGUE STUDIO (Shown in 7.NPCs) ---
	_npc_section = VBoxContainer.new()
	_npc_section.add_theme_constant_override("separation", 6)
	_inspector_box.add_child(_npc_section)

	var lore_header := Label.new()
	lore_header.text = "NPC Creator, Wardrobe & Lore Studio"
	lore_header.modulate = Color(0.55, 0.92, 1.0)
	_npc_section.add_child(lore_header)

	var npc_create_row := HBoxContainer.new()
	_npc_section.add_child(npc_create_row)

	_npc_new_name_edit = LineEdit.new()
	_npc_new_name_edit.placeholder_text = "New NPC Name (e.g. Mayor Rowan)"
	_npc_new_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_new_name_edit.text_submitted.connect(func(t: String) -> void:
		create_new_npc_from_ui("", t)
		if get_viewport() != null:
			get_viewport().gui_release_focus())
	npc_create_row.add_child(_npc_new_name_edit)

	var btn_new_npc := Button.new()
	btn_new_npc.focus_mode = Control.FOCUS_NONE
	btn_new_npc.text = "+ New NPC"
	btn_new_npc.tooltip_text = "Create a new NpcDef draft and start customizing Appearance & Wardrobe"
	btn_new_npc.pressed.connect(func() -> void: create_new_npc_from_ui())
	npc_create_row.add_child(btn_new_npc)

	var npc_file_row := HBoxContainer.new()
	_npc_section.add_child(npc_file_row)

	var btn_save_npc := Button.new()
	btn_save_npc.focus_mode = Control.FOCUS_NONE
	btn_save_npc.text = "Save NPC (.tres)"
	btn_save_npc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_save_npc.pressed.connect(save_active_npc_to_disk)
	npc_file_row.add_child(btn_save_npc)

	var btn_place_npc := Button.new()
	btn_place_npc.focus_mode = Control.FOCUS_NONE
	btn_place_npc.text = "Select to Place in 3D"
	btn_place_npc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_place_npc.pressed.connect(func() -> void:
		_apply_npc_inspector_edits()
		if active_npc_def != null:
			select_entry("npc_" + String(active_npc_def.key))
			if get_viewport() != null:
				get_viewport().gui_release_focus())
	npc_file_row.add_child(btn_place_npc)

	var npc_tab_row := HBoxContainer.new()
	npc_tab_row.name = "NpcTabRow"
	_npc_section.add_child(npc_tab_row)

	var btn_tab_app := Button.new()
	btn_tab_app.name = "TabAppearance"
	btn_tab_app.focus_mode = Control.FOCUS_NONE
	btn_tab_app.toggle_mode = true
	btn_tab_app.text = "1. Appearance & Wardrobe"
	btn_tab_app.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tab_app.pressed.connect(func() -> void: _set_npc_tab(0))
	npc_tab_row.add_child(btn_tab_app)

	var btn_tab_lore := Button.new()
	btn_tab_lore.name = "TabLore"
	btn_tab_lore.focus_mode = Control.FOCUS_NONE
	btn_tab_lore.toggle_mode = true
	btn_tab_lore.text = "2. Lore & Dialogue"
	btn_tab_lore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tab_lore.pressed.connect(func() -> void: _set_npc_tab(1))
	npc_tab_row.add_child(btn_tab_lore)

	_npc_appearance_box = VBoxContainer.new()
	_npc_appearance_box.add_theme_constant_override("separation", 6)
	_npc_section.add_child(_npc_appearance_box)

	var npc_key_row := HBoxContainer.new()
	_npc_appearance_box.add_child(npc_key_row)
	var key_lbl := Label.new()
	key_lbl.text = "Key ID:"
	npc_key_row.add_child(key_lbl)
	_npc_key_edit = LineEdit.new()
	_npc_key_edit.placeholder_text = "unique_npc_key"
	_npc_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_key_edit.text_submitted.connect(func(_t: String) -> void:
		_apply_npc_inspector_edits()
		if get_viewport() != null:
			get_viewport().gui_release_focus())
	npc_key_row.add_child(_npc_key_edit)

	_npc_name_edit = LineEdit.new()
	_npc_name_edit.placeholder_text = "NPC Display Name (e.g. Mayor Rowan)"
	_npc_name_edit.text_changed.connect(func(_t: String) -> void: _apply_npc_inspector_edits())
	_npc_appearance_box.add_child(_npc_name_edit)

	_npc_title_edit = LineEdit.new()
	_npc_title_edit.placeholder_text = "NPC Title / Role (e.g. Lord of Sunreach)"
	_npc_title_edit.text_changed.connect(func(_t: String) -> void: _apply_npc_inspector_edits())
	_npc_appearance_box.add_child(_npc_title_edit)

	var body_outfit_row := HBoxContainer.new()
	_npc_appearance_box.add_child(body_outfit_row)

	_npc_body_opt = OptionButton.new()
	_npc_body_opt.focus_mode = Control.FOCUS_NONE
	_npc_body_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for b_str: String in NpcDef.BODIES:
		_npc_body_opt.add_item("Body: " + b_str.capitalize())
	_npc_body_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	body_outfit_row.add_child(_npc_body_opt)

	_npc_outfit_opt = OptionButton.new()
	_npc_outfit_opt.focus_mode = Control.FOCUS_NONE
	_npc_outfit_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for o: String in NpcDef.OUTFITS:
		_npc_outfit_opt.add_item("Outfit: " + o)
	_npc_outfit_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	body_outfit_row.add_child(_npc_outfit_opt)

	_npc_palette_opt = OptionButton.new()
	_npc_palette_opt.focus_mode = Control.FOCUS_NONE
	_npc_palette_opt.tooltip_text = "Wardrobe Dye Palette preset (`game/regents/wardrobe/palettes/`)"
	_npc_palette_opt.add_item("Wardrobe Palette: Default (Painted)")
	for dp: DyePalette in dye_palettes:
		var pname: String = dp.title if not dp.title.is_empty() else dp.resource_path.get_file().get_basename()
		_npc_palette_opt.add_item("Palette: " + pname)
	_npc_palette_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	_npc_appearance_box.add_child(_npc_palette_opt)

	var tabard_extras_row := HBoxContainer.new()
	_npc_appearance_box.add_child(tabard_extras_row)

	_npc_tabard_chk = CheckBox.new()
	_npc_tabard_chk.focus_mode = Control.FOCUS_NONE
	_npc_tabard_chk.text = "Knight Cloth Tabard"
	_npc_tabard_chk.toggled.connect(func(_v: bool) -> void: _apply_npc_inspector_edits())
	tabard_extras_row.add_child(_npc_tabard_chk)

	_npc_extras_chk = CheckBox.new()
	_npc_extras_chk.focus_mode = Control.FOCUS_NONE
	_npc_extras_chk.text = "Hat / Pauldrons"
	_npc_extras_chk.button_pressed = true
	_npc_extras_chk.toggled.connect(func(_v: bool) -> void: _apply_npc_inspector_edits())
	tabard_extras_row.add_child(_npc_extras_chk)

	var hair_beard_row := HBoxContainer.new()
	_npc_appearance_box.add_child(hair_beard_row)

	_npc_hair_opt = OptionButton.new()
	_npc_hair_opt.focus_mode = Control.FOCUS_NONE
	_npc_hair_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for hl: String in NPC_HAIR_LABELS:
		_npc_hair_opt.add_item(hl)
	_npc_hair_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	hair_beard_row.add_child(_npc_hair_opt)

	_npc_beard_opt = OptionButton.new()
	_npc_beard_opt.focus_mode = Control.FOCUS_NONE
	_npc_beard_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for bl: String in NPC_BEARD_LABELS:
		_npc_beard_opt.add_item(bl)
	_npc_beard_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	hair_beard_row.add_child(_npc_beard_opt)

	var skin_held_row := HBoxContainer.new()
	_npc_appearance_box.add_child(skin_held_row)

	_npc_skin_opt = OptionButton.new()
	_npc_skin_opt.focus_mode = Control.FOCUS_NONE
	for sl: String in NPC_SKIN_LABELS:
		_npc_skin_opt.add_item(sl)
	_npc_skin_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	skin_held_row.add_child(_npc_skin_opt)

	_npc_hair_color_btn = ColorPickerButton.new()
	_npc_hair_color_btn.focus_mode = Control.FOCUS_NONE
	_npc_hair_color_btn.custom_minimum_size = Vector2(42, 26)
	_npc_hair_color_btn.color = Color(0.24, 0.16, 0.08)
	_npc_hair_color_btn.tooltip_text = "Hair & Beard Color"
	_npc_hair_color_btn.color_changed.connect(func(_c: Color) -> void: _apply_npc_inspector_edits())
	skin_held_row.add_child(_npc_hair_color_btn)

	_npc_held_opt = OptionButton.new()
	_npc_held_opt.focus_mode = Control.FOCUS_NONE
	_npc_held_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for h_lbl: String in NPC_HELD_LABELS:
		_npc_held_opt.add_item(h_lbl)
	_npc_held_opt.item_selected.connect(func(_i: int) -> void: _apply_npc_inspector_edits())
	skin_held_row.add_child(_npc_held_opt)

	var wander_poi_row := HBoxContainer.new()
	_npc_appearance_box.add_child(wander_poi_row)

	var wander_lbl := Label.new()
	wander_lbl.text = "Wander:"
	wander_poi_row.add_child(wander_lbl)

	_npc_wander_slider = HSlider.new()
	_npc_wander_slider.focus_mode = Control.FOCUS_NONE
	_npc_wander_slider.min_value = 0.0
	_npc_wander_slider.max_value = 16.0
	_npc_wander_slider.step = 0.5
	_npc_wander_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_wander_slider.value_changed.connect(func(_v: float) -> void: _apply_npc_inspector_edits())
	wander_poi_row.add_child(_npc_wander_slider)

	_npc_poi_chk = CheckBox.new()
	_npc_poi_chk.focus_mode = Control.FOCUS_NONE
	_npc_poi_chk.text = "Map POI"
	_npc_poi_chk.toggled.connect(func(_v: bool) -> void: _apply_npc_inspector_edits())
	wander_poi_row.add_child(_npc_poi_chk)

	var btn_next_lore := Button.new()
	btn_next_lore.focus_mode = Control.FOCUS_NONE
	btn_next_lore.text = "Next: Lore & Dialogue ->"
	btn_next_lore.pressed.connect(func() -> void: _set_npc_tab(1))
	_npc_appearance_box.add_child(btn_next_lore)

	_npc_lore_box = VBoxContainer.new()
	_npc_lore_box.add_theme_constant_override("separation", 6)
	_npc_section.add_child(_npc_lore_box)

	var btn_back_app := Button.new()
	btn_back_app.focus_mode = Control.FOCUS_NONE
	btn_back_app.text = "<- Back: Appearance & Wardrobe"
	btn_back_app.pressed.connect(func() -> void: _set_npc_tab(0))
	_npc_lore_box.add_child(btn_back_app)

	var lore_lbl := Label.new()
	lore_lbl.text = "Lore & Codex Background:"
	_npc_lore_box.add_child(lore_lbl)

	_npc_lore_edit = TextEdit.new()
	_npc_lore_edit.placeholder_text = "World-building & Lore Codex notes..."
	_npc_lore_edit.custom_minimum_size = Vector2(0, 72)
	_npc_lore_edit.text_changed.connect(_apply_npc_text_fields)
	_npc_lore_box.add_child(_npc_lore_edit)

	var dlg_lbl := Label.new()
	dlg_lbl.text = "Dialogue Script (CinemaDialogue):"
	_npc_lore_box.add_child(dlg_lbl)

	_npc_dialogue_edit = TextEdit.new()
	_npc_dialogue_edit.placeholder_text = "~ start\nSpeaker: Line text\n=> END"
	_npc_dialogue_edit.custom_minimum_size = Vector2(0, 160)
	_npc_dialogue_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_npc_dialogue_edit.text_changed.connect(_apply_npc_text_fields)
	_npc_lore_box.add_child(_npc_dialogue_edit)

	_npc_validation_label = Label.new()
	_npc_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_npc_lore_box.add_child(_npc_validation_label)

	var npc_btns := HBoxContainer.new()
	_npc_lore_box.add_child(npc_btns)
	var btn_test_box := Button.new()
	btn_test_box.focus_mode = Control.FOCUS_NONE
	btn_test_box.text = "Test Card"
	btn_test_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_test_box.pressed.connect(func() -> void:
		_apply_npc_inspector_edits()
		if active_npc_def != null:
			start_dialogue_test(active_npc_def, selected_node, CinemaBalloon.Style.REGENTS_CARD))
	npc_btns.add_child(btn_test_box)

	var btn_test_bubble := Button.new()
	btn_test_bubble.focus_mode = Control.FOCUS_NONE
	btn_test_bubble.text = "Test 3D Bubble"
	btn_test_bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_test_bubble.pressed.connect(func() -> void:
		_apply_npc_inspector_edits()
		if active_npc_def != null:
			start_dialogue_test(active_npc_def, selected_node, CinemaBalloon.Style.SPEECH_BUBBLE))
	npc_btns.add_child(btn_test_bubble)

	_set_npc_tab(0)

	balloon = CinemaBalloon.new()
	balloon.name = "DialogueBalloon"
	balloon.visible = false
	balloon.advance_requested.connect(advance_dialogue)
	balloon.choice_picked.connect(choose_dialogue_option)
	root_ctrl.add_child(balloon)


func _set_npc_tab(tab_idx: int) -> void:
	_npc_tab_idx = clampi(tab_idx, 0, 1)
	if _npc_appearance_box != null:
		_npc_appearance_box.visible = (_npc_tab_idx == 0)
	if _npc_lore_box != null:
		_npc_lore_box.visible = (_npc_tab_idx == 1)
	if _npc_section != null:
		var tab_app: Button = _npc_section.get_node_or_null("NpcTabRow/TabAppearance") as Button
		var tab_lore: Button = _npc_section.get_node_or_null("NpcTabRow/TabLore") as Button
		if tab_app != null:
			tab_app.set_pressed_no_signal(_npc_tab_idx == 0)
		if tab_lore != null:
			tab_lore.set_pressed_no_signal(_npc_tab_idx == 1)


## Create a brand-new `NpcDef` from the NPC Studio UI (generating a unique key if blank or taken),
## register it as an active draft, select it in `7.NPCs` (with live 3D ghost), and open Appearance & Wardrobe.
func create_new_npc_from_ui(custom_key: String = "", custom_name: String = "") -> NpcDef:
	var disp: String = custom_name.strip_edges()
	if disp.is_empty() and _npc_new_name_edit != null:
		disp = _npc_new_name_edit.text.strip_edges()
	var raw_key: String = custom_key.strip_edges()
	if raw_key.is_empty():
		raw_key = disp if not disp.is_empty() else ("villager_%d" % _next_id("npc"))
	raw_key = raw_key.to_lower().replace(" ", "_")
	var base_key: String = raw_key
	while NpcDef.by_key(StringName(raw_key)) != null:
		raw_key = "%s_%d" % [base_key, _next_id("npc")]
	if disp.is_empty():
		disp = raw_key.capitalize()
	if _npc_new_name_edit != null:
		_npc_new_name_edit.text = ""
	var npc: NpcDef = create_or_update_npc_def(StringName(raw_key), disp, "Townsperson", "Peasant", "male")
	if active_category != &"npcs":
		active_category = &"npcs"
		active_group_filter = ""
		_populate_group_filter()
	RegentsKitCatalog.clear_cache()
	_refresh_palette()
	select_entry("npc_" + raw_key)
	_set_npc_tab(0)
	return npc


## Save `active_npc_def` to `res://game/regents/content/npc/<key>.tres` (or `save_dir` in tests) and refresh the catalog.
func save_active_npc_to_disk(save_dir: String = "res://game/regents/content/npc/") -> String:
	_apply_npc_inspector_edits()
	if active_npc_def == null or active_npc_def.key == &"":
		return ""
	var abs_dir: String = ProjectSettings.globalize_path(save_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var out_path: String = save_dir.path_join(String(active_npc_def.key) + ".tres")
	NpcDef.unregister_draft(active_npc_def.key)
	if ResourceSaver.save(active_npc_def, out_path) != OK:
		NpcDef.register_draft(active_npc_def)
		return ""
	RegentsContent.clear()
	NpcDef.clear_cache()
	RegentsKitCatalog.clear_cache()
	_refresh_palette()
	select_entry("npc_" + String(active_npc_def.key))
	return out_path


func _populate_group_filter() -> void:
	if _group_filter_opt == null:
		return
	_group_filter_opt.clear()
	var groups: PackedStringArray = RegentsKitCatalog.groups_for(active_category)
	_group_filter_opt.add_item("All Groups (%d)" % RegentsKitCatalog.entries_for(active_category).size())
	for g: String in groups:
		_group_filter_opt.add_item(g)


func _refresh_palette() -> void:
	if _palette_list == null:
		return
	_palette_list.clear()
	var q: String = _search_edit.text if _search_edit != null else ""
	_palette_entries = RegentsKitCatalog.search(q, active_category if q.is_empty() else &"", active_group_filter if q.is_empty() else "")
	for i: int in _palette_entries.size():
		var e: Dictionary = _palette_entries[i]
		var grp: String = String(e.get("group", ""))
		var lbl: String = String(e.get("label", ""))
		var row_text: String = lbl if (not active_group_filter.is_empty() or grp.is_empty()) else ("%s  ·  %s" % [lbl, grp])
		_palette_list.add_item(row_text)
		_palette_list.set_item_tooltip(i, "[%s] %s\nID: %s" % [grp, lbl, String(e.get("id", ""))])


func _refresh_prefab_ui(saved_path: String = "") -> void:
	if _prefab_status_label == null:
		return
	if not saved_path.is_empty():
		_prefab_status_label.text = "Saved & centered -> %s (now in '2.Towns -> Saved Custom Presets'!)" % saved_path.get_file()
	elif active_prefab_root != null and is_instance_valid(active_prefab_root):
		if _picking_prefab_origin:
			_prefab_status_label.text = "Picking Origin: Left-click anywhere in the 3D world to set '%s' origin!" % active_prefab_root.name
		elif active_prefab_root.get_child_count() == 0 and not _prefab_origin_locked:
			_prefab_status_label.text = "Active Prefab '%s': place your 1st piece in 3D to set origin (or click Pick Origin in 3D)." % active_prefab_root.name
		else:
			_prefab_status_label.text = "Active Prefab '%s': %d pieces (auto-centered on Save)" % [
				active_prefab_root.name, active_prefab_root.get_child_count()
			]
	else:
		_prefab_status_label.text = "Prefab: None active (placing directly in world)"


var _updating_npc_ui: bool = false

func _populate_npc_inspector() -> void:
	if active_npc_def == null or _npc_name_edit == null:
		return
	_updating_npc_ui = true
	if _npc_key_edit != null:
		_npc_key_edit.text = String(active_npc_def.key)
	_npc_name_edit.text = active_npc_def.display_name
	_npc_title_edit.text = active_npc_def.title
	if _npc_body_opt != null:
		var b_idx: int = NpcDef.BODIES.find(active_npc_def.body)
		if b_idx >= 0:
			_npc_body_opt.select(b_idx)
	var o_idx: int = NpcDef.OUTFITS.find(active_npc_def.outfit)
	if o_idx >= 0:
		_npc_outfit_opt.select(o_idx)
	if _npc_palette_opt != null:
		var p_idx: int = 0
		if active_npc_def.palette != null:
			for i: int in dye_palettes.size():
				if dye_palettes[i] == active_npc_def.palette or (not active_npc_def.palette.resource_path.is_empty() and dye_palettes[i].resource_path == active_npc_def.palette.resource_path):
					p_idx = i + 1
					break
		_npc_palette_opt.select(p_idx)
	if _npc_tabard_chk != null:
		_npc_tabard_chk.button_pressed = active_npc_def.knight_tabard
	if _npc_extras_chk != null:
		_npc_extras_chk.button_pressed = active_npc_def.wear_extras
	if _npc_hair_opt != null:
		_npc_hair_opt.select(clampi(active_npc_def.hair_style, 0, NPC_HAIR_LABELS.size() - 1))
	if _npc_beard_opt != null:
		_npc_beard_opt.select(clampi(active_npc_def.beard_style, 0, NPC_BEARD_LABELS.size() - 1))
	if _npc_skin_opt != null:
		_npc_skin_opt.select(clampi(active_npc_def.skin_tone, 0, NPC_SKIN_LABELS.size() - 1))
	if _npc_hair_color_btn != null:
		_npc_hair_color_btn.color = active_npc_def.hair_color
	if _npc_held_opt != null:
		var hp: String = active_npc_def.held_scene.resource_path if active_npc_def.held_scene != null else ""
		var h_idx: int = NPC_HELD_PATHS.find(hp)
		_npc_held_opt.select(maxi(h_idx, 0))
	if _npc_wander_slider != null:
		_npc_wander_slider.set_value_no_signal(active_npc_def.wander_m)
	if _npc_poi_chk != null:
		_npc_poi_chk.button_pressed = active_npc_def.map_poi
	_npc_lore_edit.text = active_npc_def.lore_entry
	_npc_dialogue_edit.text = active_npc_def.dialogue_script
	var errs: Array[String] = active_npc_def.validate()
	_npc_validation_label.text = "Valid (.dialogue OK)" if errs.is_empty() else "; ".join(errs)
	_updating_npc_ui = false


func _apply_npc_text_fields() -> void:
	if _updating_npc_ui or active_npc_def == null or _npc_lore_edit == null:
		return
	active_npc_def.lore_entry = _npc_lore_edit.text
	active_npc_def.dialogue_script = _npc_dialogue_edit.text
	var errs: Array[String] = active_npc_def.validate()
	_npc_validation_label.text = "Valid (.dialogue OK)" if errs.is_empty() else "; ".join(errs)


func _apply_npc_inspector_edits() -> void:
	if _updating_npc_ui or active_npc_def == null or _npc_name_edit == null:
		return
	var old_key: StringName = active_npc_def.key
	if _npc_key_edit != null and not _npc_key_edit.text.strip_edges().is_empty():
		active_npc_def.key = StringName(_npc_key_edit.text.strip_edges().to_lower().replace(" ", "_"))
	active_npc_def.display_name = _npc_name_edit.text
	active_npc_def.title = _npc_title_edit.text
	if _npc_body_opt != null and _npc_body_opt.selected >= 0:
		active_npc_def.body = NpcDef.BODIES[_npc_body_opt.selected]
	active_npc_def.outfit = NpcDef.OUTFITS[_npc_outfit_opt.selected] if _npc_outfit_opt.selected >= 0 else "Peasant"
	if _npc_palette_opt != null and _npc_palette_opt.selected >= 0:
		var pi: int = _npc_palette_opt.selected
		active_npc_def.palette = dye_palettes[pi - 1] if (pi > 0 and pi - 1 < dye_palettes.size()) else null
	if _npc_tabard_chk != null:
		active_npc_def.knight_tabard = _npc_tabard_chk.button_pressed
	if _npc_extras_chk != null:
		active_npc_def.wear_extras = _npc_extras_chk.button_pressed
	if _npc_hair_opt != null and _npc_hair_opt.selected >= 0:
		active_npc_def.hair_style = _npc_hair_opt.selected
	if _npc_beard_opt != null and _npc_beard_opt.selected >= 0:
		active_npc_def.beard_style = _npc_beard_opt.selected
	if _npc_skin_opt != null and _npc_skin_opt.selected >= 0:
		active_npc_def.skin_tone = _npc_skin_opt.selected
	if _npc_hair_color_btn != null:
		active_npc_def.hair_color = _npc_hair_color_btn.color
	if _npc_held_opt != null and _npc_held_opt.selected >= 0 and _npc_held_opt.selected < NPC_HELD_PATHS.size():
		var h_path: String = NPC_HELD_PATHS[_npc_held_opt.selected]
		active_npc_def.held_scene = (load(h_path) as PackedScene) if (not h_path.is_empty() and ResourceLoader.exists(h_path)) else null
	if _npc_wander_slider != null:
		active_npc_def.wander_m = _npc_wander_slider.value
	if _npc_poi_chk != null:
		active_npc_def.map_poi = _npc_poi_chk.button_pressed
	active_npc_def.lore_entry = _npc_lore_edit.text
	active_npc_def.dialogue_script = _npc_dialogue_edit.text
	if old_key != active_npc_def.key and active_npc_def.resource_path.is_empty():
		NpcDef.unregister_draft(old_key)
		NpcDef.register_draft(active_npc_def)
		RegentsKitCatalog.clear_cache()
		_refresh_palette()
	var errs: Array[String] = active_npc_def.validate()
	_npc_validation_label.text = "Valid (.dialogue OK)" if errs.is_empty() else "; ".join(errs)
	_refresh_npc_previews(active_npc_def.key)
	_rebuild_ghost_preview()


func _refresh_status() -> void:
	if _status_label == null:
		return
	var mode_str: String = "FLY" if camera_mode == CameraMode.FLY else "WALK"
	var lvl: String = level_info.level_name if level_info != null else "none"
	var entry: Dictionary = RegentsKitCatalog.find_entry(active_entry_id)
	var tool_lbl: String = String(entry.get("label", active_entry_id))
	var snap_str: String = "Free" if (not snap_grid or free_place_held or grid_step_xz <= 0.0) else ("%sm / Y:%sm" % [str(grid_step_xz), str(grid_step_y)])
	var prefab_str: String = ("  ·  Prefab: %s (F%d)" % [active_prefab_root.name, story_level + 1]) if (active_prefab_root != null and is_instance_valid(active_prefab_root)) else ""
	_status_label.text = "[%s] %s  ·  %s  ·  Snap: %s  ·  Yaw: %d°%s  ·  Undo: %d/%d" % [
		mode_str, lvl, tool_lbl, snap_str, roundi(rad_to_deg(place_yaw)), prefab_str, _undo_stack.size(), _redo_stack.size()
	]
	_refresh_prefab_ui()


func _position_camera_overview() -> void:
	if camera == null:
		return
	camera.look_at_from_position(Vector3(0.0, 28.0, 48.0), Vector3(0.0, 0.0, 0.0))
	_yaw = camera.rotation.y
	_pitch = camera.rotation.x


func _process(delta: float) -> void:
	free_place_held = Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_SHIFT)
	if _is_typing_in_text_box():
		return
	if camera_mode == CameraMode.WALK:
		var mv := Vector2.ZERO
		if Input.is_key_pressed(KEY_W):
			mv.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			mv.y += 1.0
		if Input.is_key_pressed(KEY_A):
			mv.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			mv.x += 1.0
		step_walk_mode(delta, mv.normalized(), Input.is_key_pressed(KEY_SPACE))
		return

	if camera != null:
		var move := Vector3.ZERO
		if Input.is_key_pressed(KEY_W):
			move -= camera.global_transform.basis.z
		if Input.is_key_pressed(KEY_S):
			move += camera.global_transform.basis.z
		if Input.is_key_pressed(KEY_A):
			move -= camera.global_transform.basis.x
		if Input.is_key_pressed(KEY_D):
			move += camera.global_transform.basis.x
		if Input.is_key_pressed(KEY_E):
			move += Vector3.UP
		if Input.is_key_pressed(KEY_Q):
			move -= Vector3.UP
		if move != Vector3.ZERO:
			var boost: float = 3.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0
			camera.global_position += move.normalized() * fly_speed * boost * delta
		if get_viewport() != null and not _looking:
			var mp: Vector2 = get_viewport().get_mouse_position()
			if not _is_mouse_over_ui(mp):
				update_cursor_from_mouse(mp)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE and get_viewport() != null:
			get_viewport().gui_release_focus()
			return
		if _is_typing_in_text_box():
			return
		if ke.keycode == KEY_TAB:
			toggle_camera_mode()
		elif ke.keycode == KEY_F2:
			set_server_overlay_visible(not show_server_overlay)
		elif ke.keycode == KEY_Z and ke.ctrl_pressed:
			undo()
		elif ke.keycode == KEY_Y and ke.ctrl_pressed:
			redo()
		elif ke.keycode == KEY_E and camera_mode == CameraMode.WALK:
			interact_in_walk_mode()
		elif ke.keycode == KEY_R and not ke.ctrl_pressed:
			var step_angle: float = PI / 12.0 if ke.alt_pressed else (PI * 0.5 if ke.shift_pressed else PI * 0.25)
			place_yaw = fposmod(place_yaw + step_angle, TAU)
			house_seed += 1
			_rebuild_ghost_preview()
			_refresh_status()
		elif ke.keycode == KEY_BRACKETLEFT:
			set_brush_radius(brush_radius() - (0.5 if brush_radius() <= 3.0 else 1.5))
		elif ke.keycode == KEY_BRACKETRIGHT:
			set_brush_radius(brush_radius() + (0.5 if brush_radius() < 3.0 else 1.5))
		elif ke.keycode == KEY_Z and not ke.ctrl_pressed:
			set_story_level(story_level - 1)
		elif ke.keycode == KEY_X and not ke.ctrl_pressed:
			set_story_level(story_level + 1)
		elif ke.keycode == KEY_G and not ke.ctrl_pressed:
			set_grid_step_xz(0.0 if snap_grid else 2.0)
		elif ke.keycode == KEY_V and not ke.ctrl_pressed:
			show_gizmo_rings = not show_gizmo_rings
			if level_root != null:
				RegentsPointPreview.attach_all(level_root, show_gizmo_rings)
		elif ke.keycode == KEY_UP or ke.keycode == KEY_PAGEUP:
			cycle_palette_entry(-1)
		elif ke.keycode == KEY_DOWN or ke.keycode == KEY_PAGEDOWN:
			cycle_palette_entry(1)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if _is_mouse_over_ui(mb.position) and not _looking:
			return
		if get_viewport() != null and mb.pressed:
			get_viewport().gui_release_focus()
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if _looking:
				fly_speed = clampf(fly_speed * 1.15, 4.0, 160.0)
			elif mb.shift_pressed or is_brush_tool_active():
				set_brush_radius(brush_radius() + (0.5 if brush_radius() < 3.0 else 1.5))
			else:
				cycle_palette_entry(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if _looking:
				fly_speed = clampf(fly_speed / 1.15, 4.0, 160.0)
			elif mb.shift_pressed or is_brush_tool_active():
				set_brush_radius(brush_radius() - (0.5 if brush_radius() <= 3.0 else 1.5))
			else:
				cycle_palette_entry(1)
		elif mb.button_index == MOUSE_BUTTON_LEFT and camera_mode == CameraMode.FLY:
			free_place_held = mb.alt_pressed or mb.shift_pressed
			if mb.pressed:
				update_cursor_from_mouse(mb.position)
				if is_brush_tool_active() and not _picking_prefab_origin:
					_painting_drag = true
				use_active_tool_at(cursor_pos)
			else:
				_painting_drag = false
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		free_place_held = mm.alt_pressed or mm.shift_pressed
		if _search_edit != null and _search_edit.has_focus() and _left_panel != null and not _left_panel.get_global_rect().has_point(mm.position):
			_search_edit.release_focus()
		if _looking and camera != null:
			_yaw -= mm.relative.x * 0.004
			_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.45, 1.45)
			camera.rotation = Vector3(_pitch, _yaw, 0.0)
		elif camera_mode == CameraMode.FLY and not _is_mouse_over_ui(mm.position):
			update_cursor_from_mouse(mm.position)
			if _painting_drag and is_brush_tool_active() and not _picking_prefab_origin:
				use_active_tool_at(cursor_pos)


# =============================================================================================
# HELPERS
# =============================================================================================

func _next_id(prefix: String) -> int:
	_point_counters[prefix] = _point_counters.get(prefix, 0) + 1
	return _point_counters[prefix]


static func _own_recursive(n: Node, root_owner: Node) -> void:
	if n != root_owner:
		n.owner = root_owner
	if not n.scene_file_path.is_empty() and n != root_owner:
		return
	for c: Node in n.get_children():
		_own_recursive(c, root_owner)


static func _own_level_tree(root_owner: Node) -> void:
	for c: Node in root_owner.get_children():
		_own_recursive(c, root_owner)


func _exit_tree() -> void:
	NpcDef.clear_drafts()
	if _overlay_root != null:
		RegentsPointPreview._clear_materials(_overlay_root)
	if level_root != null:
		RegentsPointPreview._clear_materials(level_root)
