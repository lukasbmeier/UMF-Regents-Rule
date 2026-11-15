extends Node3D
## THE WARDROBE LAB (Luke, 2026-11-14: "a lab that is basically a more advanced character selector ... a full inventory
## of what clothes/armor potential we have"): open `res://game/regents/wardrobe/wardrobe_lab.tscn` and press F6 (no
## server). One figure on a turntable, every piece we have in every slot, and the DYE: any color in each of the six dye
## slots (metal, main, accent, trim, leather, under), and a metal FINISH (copper, iron, steel, studies for later tiers).
##
##   One / Tiers / Outfits / Colorways (1-4)         one figure; a family's tiers (Metal: the Knight in every finish;
##                                                   Leather: the Ranger; Cloth: the Wizard; Starter: the Peasant); every outfit; each outfit's
##                                                   painted colorways beside the same colorway dyed (the dye's check)
##   Z   the dye zones as flat colors (red main, blue accent, orange trim, brown leather, green under, gray metal)
##   T   turn the figure          right mouse, drag   turn round it        wheel   nearer, farther
##   Save palette                  writes the colors to `palettes/custom_<time>.tres` (in the editor)
##
## How it works: `Wardrobe` (pieces found by file name, the dye material), `outfit_dye.gdshader`, `DyePalette`,
## `MetalFinish`, the zones baked by `game/regents/tools/wardrobe_assets.py`. The inventory and the plan:
## `docs/regents_rule/WARDROBE.md`. Presentation only: nothing here is in the game yet.
##
## SHOTS (windowed, no server): `"$GODOT" --path . res://game/regents/wardrobe/wardrobe_lab.tscn -- <out dir>` saves
## each view as `<out>/wardrobe_<name>.png` and the pieces' makeup as `<out>/wardrobe_inventory.md`, then quits.

const ADVENTURER: String = "res://game/regents/content/character/adventurer.tres"
const PIECE_SPACING: float = 1.15
const MODES: PackedStringArray = ["One", "Tiers", "Outfits", "Colorways"]
## The tier families: [name, the outfit that wears them, the palettes' file prefix ("" for Metal: its finishes)].
## Luke, 2026-11-14: everyone starts in the Peasant clothes in colors they pick; leather is the Ranger, cloth the
## Wizard, metal the Knight (the Noble is kept for NPCs).
const FAMILIES: Array[Array] = [["Metal", "Knight", ""], ["Leather", "Ranger", "leather_"], ["Cloth", "Wizard", "cloth_"],
	["Starter", "Peasant", "starter_"]]
const LIGHTS: PackedStringArray = ["Day", "Dusk", "Night"]
const PANEL_W: int = 400

## The figure being built in "One": { body, pieces: {slot: path}, skin (0/1), skin_tint, hair: [paths], hair_color }.
var look: Dictionary = {}
## The colors worn (the lab's own copy).
var palette: DyePalette = DyePalette.new()
var mode: int = 0
var show_zones: bool = false
var spinning: bool = true
## Which of FAMILIES the Tiers view shows.
var tier_family: int = 0

var _base_def: EntityDefinition = null
var _figures: Node3D = null
var _cam: Camera3D = null
var _sun: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _yaw: float = 0.0
var _pitch: float = -8.0
var _dist: float = 3.2
var _focus: Vector3 = Vector3(0, 1.0, 0)
var _dragging: bool = false
var _spin_angle: float = 0.0
var _info: Label = null
var _panel: Control = null
var _ui_root: VBoxContainer = null
var _palettes: Array[Resource] = []
var _metals: Array[Resource] = []
## Built per refresh of the controls: so a rebuild of the panel never fires its own handlers.
var _quiet: bool = false
var _hair_choice: int = 1
var _beard_choice: int = 0
var _brow_choice: int = 0
var _skin_choice: int = 0
var _hair_color_choice: int = 1


func _ready() -> void:
	_base_def = load(ADVENTURER) as EntityDefinition
	_palettes = Wardrobe.load_all(Wardrobe.PALETTES)
	_metals = Wardrobe.load_all(Wardrobe.METALS)
	_build_world()
	_set_body(&"male", "Knight")
	_build_ui()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):   # (the test runner passes its own "--only=")
		_shoot.call_deferred(args[0])
	else:
		show_mode(0)


# ---------------------------------------------------------------- the stage

func _build_world() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.ssao_light_affect = 0.3
	_env.glow_enabled = true
	_env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	var fill := DirectionalLight3D.new()   # a soft light from behind the camera, so the front is never black
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-15, 200, 0)
	add_child(fill)
	set_light(0)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 40.0
	disc.bottom_radius = 40.0
	disc.height = 0.1
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.05
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.35, 0.33)
	fm.roughness = 0.95
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	_figures = Node3D.new()
	_figures.name = "Figures"
	add_child(_figures)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.make_current()
	_place_camera()


func set_light(i: int) -> void:
	match i:
		0:
			_sky.sky_top_color = Color(0.36, 0.55, 0.82)
			_sky.sky_horizon_color = Color(0.7, 0.78, 0.84)
			_sky.ground_horizon_color = Color(0.5, 0.5, 0.48)
			_sun.light_color = Color(1, 0.94, 0.84)
			_sun.light_energy = 1.3
			_sun.rotation_degrees = Vector3(-38, 30, 0)
			_env.ambient_light_energy = 1.0
		1:
			_sky.sky_top_color = Color(0.2, 0.25, 0.45)
			_sky.sky_horizon_color = Color(0.85, 0.5, 0.35)
			_sky.ground_horizon_color = Color(0.35, 0.3, 0.28)
			_sun.light_color = Color(1, 0.6, 0.4)
			_sun.light_energy = 0.9
			_sun.rotation_degrees = Vector3(-10, 60, 0)
			_env.ambient_light_energy = 0.6
		_:
			_sky.sky_top_color = Color(0.02, 0.03, 0.07)
			_sky.sky_horizon_color = Color(0.06, 0.08, 0.14)
			_sky.ground_horizon_color = Color(0.03, 0.04, 0.05)
			_sun.light_color = Color(0.55, 0.65, 1.0)
			_sun.light_energy = 0.25
			_sun.rotation_degrees = Vector3(-45, -30, 0)
			_env.ambient_light_energy = 0.3


func _place_camera() -> void:
	var dir: Vector3 = Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
	var offset: Vector3 = (dir * cos(deg_to_rad(-_pitch)) + Vector3.UP * sin(deg_to_rad(-_pitch))) * _dist
	_cam.position = _focus + offset
	_cam.look_at(_focus, Vector3.UP)
	# The panel covers the right of the screen: shift the picture left so the figures stand in what is left.
	var w: float = maxf(float(get_viewport().get_visible_rect().size.x), 1.0)
	_cam.h_offset = 0.0
	if _panel != null and _panel.visible:
		_cam.h_offset = _dist * tan(deg_to_rad(_cam.fov * 0.5)) * (float(PANEL_W) / w) * 0.9


func _process(delta: float) -> void:
	if spinning and mode == 0:
		_spin_angle += delta * 0.6
		for f: Node in _figures.get_children():
			(f as Node3D).rotation.y = PI + _spin_angle


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(1.2, _dist * 0.9)
			_place_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(30.0, _dist * 1.1)
			_place_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.3
		_pitch = clampf(_pitch - mm.relative.y * 0.2, -60.0, 20.0)
		_place_camera()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).keycode:
			KEY_Z:
				set_zones(not show_zones)
			KEY_T:
				spinning = not spinning
			KEY_1, KEY_2, KEY_3, KEY_4:
				show_mode(int((event as InputEventKey).keycode - KEY_1))


# ---------------------------------------------------------------- figures

## A figure at `at`, in `pal` (null: as painted), its painted colorway `way` (1 = the outfit's own). Returns its
## Mannequin (its `model` the assembled ModularCharacter).
func add_figure(l: Dictionary, pal: DyePalette, at: Vector3, title: String = "", way: Texture2D = null) -> Mannequin:
	var mc: ModularCharacter = Wardrobe.figure(l)
	mc.outfit_texture = way
	var scene := PackedScene.new()
	scene.pack(mc)
	mc.free()
	var def: EntityDefinition = _base_def.duplicate() as EntityDefinition
	var none: Array[PackedScene] = []
	def.visual_variants = none
	def.visual_scene = scene
	var root := Node3D.new()
	root.position = at
	root.rotation.y = PI   # the characters face -Z; the camera looks from +Z
	_figures.add_child(root)
	var m := Mannequin.new()
	m.definition = def
	root.add_child(m)
	if m.model != null and (pal != null or show_zones):
		Wardrobe.dress(m.model, pal, show_zones)
	root.set_meta(&"palette", pal)
	if not title.is_empty():
		var tag := Label3D.new()
		tag.text = title
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 40
		tag.outline_size = 10
		tag.pixel_size = 0.004
		# Every other one higher, so long names side by side never run into each other.
		tag.position.y = 2.1 + (0.28 if _figures.get_child_count() % 2 == 0 else 0.0)
		tag.width = 260.0
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(tag)
	return m


func _clear() -> void:
	for f: Node in _figures.get_children():
		_figures.remove_child(f)
		f.queue_free()


## The current figure's palette: null when nothing in it dyes (the painting as it is).
func worn_palette() -> DyePalette:
	return palette if _dyes(palette) else null


static func _dyes(p: DyePalette) -> bool:
	if p == null:
		return false
	if p.metal != null and p.metal.color.a > 0.0:
		return true
	for slot: StringName in DyePalette.CLOTH:
		if (p.get(slot) as Color).a > 0.0:
			return true
	return false


## Put the view up again: one figure, or a lineup.
func show_mode(m: int) -> void:
	mode = m
	_clear()
	_spin_angle = 0.0
	match m:
		0:
			add_figure(look, worn_palette(), Vector3.ZERO)
			_frame(1, 3.4)
		1:
			_tiers()
		2:
			_outfit_lineup()
		_:
			_colourway_lineup()
	_refresh_info()


## A FAMILY'S TIERS: its outfit's whole set in each of its palettes (`palettes/<prefix>*.tres`, in file order). Metal
## is THE ONE MESH, EVERY TIER: the Knight in each metal finish, the cloth as the palette has it.
func _tiers() -> void:
	var fam: Array = FAMILIES[tier_family]
	if not String(fam[2]).is_empty():
		var pals: Array[DyePalette] = tier_palettes(String(fam[2]))
		var k: int = pals.size()
		for i: int in k:
			var b: StringName = &"male" if i % 2 == 0 else &"female"
			add_figure(_look_with(b, Wardrobe.full_set(String(fam[1]), b, String(fam[0]) != "Starter")), pals[i],
				Vector3((float(i) - float(k - 1) * 0.5) * PIECE_SPACING, 0, 0), pals[i].title)
		_frame(maxi(k, 3), 0.0)
		return
	var n: int = _metals.size()
	for i: int in n:
		var finish: MetalFinish = _metals[i] as MetalFinish
		var pal: DyePalette = palette.copy()
		pal.metal = finish
		var body: StringName = &"male" if i % 2 == 0 else &"female"
		var l: Dictionary = _look_with(body, Wardrobe.full_set("Knight", body))
		add_figure(l, pal, Vector3((float(i) - float(n - 1) * 0.5) * PIECE_SPACING, 0, 0), finish.title)
	_frame(n, 0.0)


## The palettes whose file names start with `prefix`, in file order.
func tier_palettes(prefix: String) -> Array[DyePalette]:
	var out: Array[DyePalette] = []
	for r: Resource in _palettes:
		if r.resource_path.get_file().begins_with(prefix):
			out.append(r as DyePalette)
	return out


## EVERY OUTFIT, both bodies, in the palette (or as painted).
func _outfit_lineup() -> void:
	var outfits: Array[String] = Wardrobe.outfits()
	var i: int = 0
	var n: int = outfits.size() * 2
	for o: String in outfits:
		for body: StringName in [&"male", &"female"]:
			var l: Dictionary = _look_with(body, Wardrobe.full_set(o, body))
			add_figure(l, worn_palette(), Vector3((float(i) - float(n - 1) * 0.5) * PIECE_SPACING, 0, 0), o)
			i += 1
	_frame(n, 0.0)


## THE DYE'S CHECK: the outfit's painted colorways (the pack's textures, where we have them) beside the same colorway
## put back by the dye (`palettes/<outfit>_<n>.tres`). Close is the zones doing their job; far is a zone to fix.
func _colourway_lineup() -> void:
	var outfit: String = _main_outfit()
	var body: StringName = look.get("body", &"male") as StringName
	var l: Dictionary = _look_with(body, Wardrobe.full_set(outfit, body))
	var cols: Array[Array] = []
	for n: int in [1, 2, 3]:
		var pal: DyePalette = load(Wardrobe.PALETTES + "%s_%d.tres" % [outfit.to_lower(), n]) as DyePalette
		var tex_path: String = "res://game/characters/quaternius/textures/T_%s%s_BaseColor.png" % [outfit, "" if n == 1 else "_%d" % n]
		if outfit == "Knight":
			tex_path = "res://game/regents/art/outfits/knight/textures/T_Knight%s_BaseColor.png" % ("" if n == 1 else "_%d" % n)
		if ResourceLoader.exists(tex_path):
			cols.append(["%s %d, painted" % [outfit, n], null, load(tex_path) as Texture2D])
		if pal != null:
			cols.append(["%s %d, dyed" % [outfit, n], pal, null])
	var k: int = cols.size()
	for i: int in k:
		var c: Array = cols[i]
		add_figure(l, c[1] as DyePalette, Vector3((float(i) - float(k - 1) * 0.5) * PIECE_SPACING, 0, 0), String(c[0]),
			c[2] as Texture2D)
	_frame(k, 0.0)


func _frame(count: int, dist: float) -> void:
	_focus = Vector3(0, 1.05, 0)
	_yaw = 0.0
	_pitch = -6.0
	_dist = dist if dist > 0.0 else maxf(3.4, float(count) * PIECE_SPACING * 0.95 + 1.5)
	_place_camera()


func _look_with(body: StringName, pieces: Dictionary[StringName, String]) -> Dictionary:
	var l: Dictionary = look.duplicate(true)
	if l.get("body", &"") != body:
		l["body"] = body
		l["hair"] = _hair_paths(body)
	l["pieces"] = pieces
	return l


## The outfit of the torso worn (else the first piece's).
func _main_outfit() -> String:
	var pieces: Dictionary = look.get("pieces", {}) as Dictionary
	for slot: StringName in [&"torso", &"legs", &"arms"]:
		var path: String = String(pieces.get(slot, ""))
		if not path.is_empty():
			return path.get_file().get_basename().split("_")[1]
	return "Knight"


# ---------------------------------------------------------------- the look

func _set_body(body: StringName, outfit: String) -> void:
	look["body"] = body
	look["pieces"] = Wardrobe.full_set(outfit, body)
	look["skin"] = 1 if bool((CharacterLooks.SKINS[_skin_choice] as Dictionary)["dark"]) else 0
	look["skin_tint"] = (CharacterLooks.SKINS[_skin_choice] as Dictionary)["tint"] as Color
	look["hair_color"] = (CharacterLooks.HAIRS[_hair_color_choice] as Dictionary)["color"] as Color
	look["hair"] = _hair_paths(body)


func _hair_paths(body: StringName) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in [["hairstyle", _hair_choice], ["beard", _beard_choice], ["brows", _brow_choice]]:
		var list: Array = _hair_list(String(pair[0]), body)
		if list.is_empty():
			continue
		var pick: Array = list[clampi(int(pair[1]), 0, list.size() - 1)] as Array
		for file: String in String(pick[1]).split("+", false):
			out.append(CharacterLooks.PIECES + file + ".gltf")
	return out


static func _hair_list(key: String, body: StringName) -> Array:
	for slot: Dictionary in CharacterLooks.SLOTS:
		if String(slot["key"]) == key:
			return CharacterLooks.slot_list(slot, body)
	return []


func set_zones(on: bool) -> void:
	show_zones = on
	for f: Node in _figures.get_children():
		for c: Node in f.get_children():
			if c is Mannequin and (c as Mannequin).model != null:
				var pal: DyePalette = f.get_meta(&"palette") as DyePalette if f.has_meta(&"palette") else null
				Wardrobe.dress((c as Mannequin).model, pal, show_zones)


## Colors changed: dye the figures again (no rebuild). In the tiers lineup each keeps its own metal.
func recolor() -> void:
	if mode == 1 and not String(FAMILIES[tier_family][2]).is_empty():
		pass   # leather, cloth and starter tiers wear their own palettes
	elif mode == 1:
		var i: int = 0
		for f: Node in _figures.get_children():
			var pal: DyePalette = palette.copy()
			pal.metal = _metals[i] as MetalFinish
			f.set_meta(&"palette", pal)
			i += 1
	elif mode != 3:
		for f: Node in _figures.get_children():
			f.set_meta(&"palette", worn_palette())
	set_zones(show_zones)


# ---------------------------------------------------------------- the panel

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	_panel = panel
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_ui_root = VBoxContainer.new()
	_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ui_root)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.position = Vector2(12, 8)
	info.size = Vector2(520, 200)
	info.add_theme_color_override(&"font_outline_color", Color.BLACK)
	info.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(info)
	_info = info
	_fill_panel()


func _fill_panel() -> void:
	_quiet = true
	for c: Node in _ui_root.get_children():
		_ui_root.remove_child(c)
		c.queue_free()
	_heading("View")
	var modes: HBoxContainer = _row()
	for i: int in MODES.size():
		_button(modes, MODES[i], show_mode.bind(i))
	var view: HBoxContainer = _row()
	var z := CheckBox.new()
	z.text = "Zones (Z)"
	z.button_pressed = show_zones
	z.toggled.connect(set_zones)
	view.add_child(z)
	var t := CheckBox.new()
	t.text = "Turn (T)"
	t.button_pressed = spinning
	t.toggled.connect(func(on: bool) -> void: spinning = on)
	view.add_child(t)
	for i: int in LIGHTS.size():
		_button(view, LIGHTS[i], set_light.bind(i))
	var fams: PackedStringArray = []
	for f: Array in FAMILIES:
		fams.append("%s tiers (%s)" % [f[0], f[1]])
	_option(_labeled("Tiers of"), fams, tier_family, func(i: int) -> void:
		tier_family = i
		show_mode(1))
	_heading("Body")
	var body: HBoxContainer = _row()
	_button(body, "Male", _pick_body.bind(&"male"))
	_button(body, "Female", _pick_body.bind(&"female"))
	var skins: PackedStringArray = []
	for s: Dictionary in CharacterLooks.SKINS:
		skins.append(String(s["name"]))
	_option(_labeled("Skin"), skins, _skin_choice, func(i: int) -> void:
		_skin_choice = i
		look["skin"] = 1 if bool((CharacterLooks.SKINS[i] as Dictionary)["dark"]) else 0
		look["skin_tint"] = (CharacterLooks.SKINS[i] as Dictionary)["tint"] as Color
		show_mode(mode))
	var b: StringName = look.get("body", &"male") as StringName
	for pair: Array in [["hairstyle", "Hair"], ["beard", "Beard"], ["brows", "Brows"]]:
		var list: Array = _hair_list(String(pair[0]), b)
		if list.size() < 2:
			continue
		var names: PackedStringArray = []
		for e: Array in list:
			names.append(String(e[0]))
		var key: String = String(pair[0])
		var cur: int = _hair_choice if key == "hairstyle" else (_beard_choice if key == "beard" else _brow_choice)
		_option(_labeled(String(pair[1])), names, cur, func(i: int) -> void:
			if key == "hairstyle":
				_hair_choice = i
			elif key == "beard":
				_beard_choice = i
			else:
				_brow_choice = i
			look["hair"] = _hair_paths(look["body"] as StringName)
			show_mode(0))
	var hairs: PackedStringArray = []
	for h: Dictionary in CharacterLooks.HAIRS:
		hairs.append(String(h["name"]))
	_option(_labeled("Hair color"), hairs, _hair_color_choice, func(i: int) -> void:
		_hair_color_choice = i
		look["hair_color"] = (CharacterLooks.HAIRS[i] as Dictionary)["color"] as Color
		show_mode(mode))
	_heading("Whole outfit")
	var whole: HFlowContainer = HFlowContainer.new()
	_ui_root.add_child(whole)
	for o: String in Wardrobe.outfits():
		_button(whole, o, func() -> void:
			look["pieces"] = Wardrobe.full_set(o, look["body"] as StringName)
			_fill_panel()
			show_mode(0))
	_heading("Pieces (what each is made of)")
	var worn: Dictionary = look.get("pieces", {}) as Dictionary
	for slot: StringName in Wardrobe.SLOTS:
		var list: Array[Dictionary] = Wardrobe.pieces_for(b, slot)
		var names: PackedStringArray = []
		var paths: Array[String] = []
		if Wardrobe.OPTIONAL.has(slot) or list.is_empty():
			names.append("None")
			paths.append("")
		for p: Dictionary in list:
			names.append("%s %s" % [p["outfit"], String(p["part"]).replace("_", " ")])
			paths.append(String(p["path"]))
		var at: int = maxi(paths.find(String(worn.get(slot, ""))), 0)
		var box: VBoxContainer = VBoxContainer.new()
		_ui_root.add_child(box)
		var line := HBoxContainer.new()
		box.add_child(line)
		var lab := Label.new()
		lab.text = String(slot).capitalize()
		lab.custom_minimum_size.x = 84
		line.add_child(lab)
		var s: StringName = slot
		_option(line, names, at, func(i: int) -> void:
			var pieces: Dictionary = look["pieces"] as Dictionary
			if paths[i].is_empty():
				pieces.erase(s)
			else:
				pieces[s] = paths[i]
			_fill_panel()
			show_mode(0))
		var mk := Label.new()
		mk.text = _makeup_text(paths[at])
		mk.add_theme_font_size_override(&"font_size", 11)
		mk.modulate = Color(1, 1, 1, 0.7)
		box.add_child(mk)
	_heading("Colors")
	var pal_names: PackedStringArray = ["(choose a palette)"]
	for r: Resource in _palettes:
		pal_names.append((r as DyePalette).title)
	_option(_labeled("Palette"), pal_names, 0, func(i: int) -> void:
		if i > 0:
			palette = (_palettes[i - 1] as DyePalette).copy()
			_fill_panel()
			recolor())
	var metal_names: PackedStringArray = ["Painted (the outfit's own)"]
	var metal_at: int = 0
	for i: int in _metals.size():
		metal_names.append((_metals[i] as MetalFinish).title)
		if palette.metal != null and palette.metal.title == (_metals[i] as MetalFinish).title:
			metal_at = i + 1
	_option(_labeled("Metal"), metal_names, metal_at, func(i: int) -> void:
		palette.metal = null if i == 0 else (_metals[i - 1] as MetalFinish).duplicate() as MetalFinish
		_fill_panel()
		recolor())
	if palette.metal != null:
		var mf: MetalFinish = palette.metal
		_color_row("Metal color", mf.color, func(c: Color) -> void:
			mf.color = c
			recolor())
		_slider("Metallic", mf.metallic, func(v: float) -> void:
			mf.metallic = v
			recolor())
		_slider("Roughness", mf.roughness, func(v: float) -> void:
			mf.roughness = v
			recolor())
		_slider("Wear", mf.wear, func(v: float) -> void:
			mf.wear = v
			recolor())
		_color_row("Wear color", mf.wear_color, func(c: Color) -> void:
			mf.wear_color = c
			recolor())
	for slot: StringName in DyePalette.CLOTH:
		var sl: StringName = slot
		_dye_row(String(slot).capitalize(), palette.get(slot) as Color, func(c: Color) -> void:
			palette.set(sl, c)
			recolor())
	_slider("Trim glow", palette.trim_glow / 4.0, func(v: float) -> void:
		palette.trim_glow = v * 4.0
		recolor())
	var acts: HBoxContainer = _row()
	_button(acts, "Random colors", random_palette)
	_button(acts, "Clear dye", func() -> void:
		palette = DyePalette.new()
		_fill_panel()
		recolor())
	_button(acts, "Save palette", save_palette)
	_quiet = false


func _makeup_text(path: String) -> String:
	if path.is_empty():
		return "  (nothing worn)"
	var m: Dictionary = Wardrobe.makeup(path)
	var cloth: float = 0.0
	for k: StringName in [&"main", &"accent", &"trim", &"under"]:
		cloth += float(m.get(k, 0.0))
	return "  metal %d %% · leather %d %% · cloth %d %%" % [
		roundi(float(m.get(&"metal", 0.0)) * 100.0), roundi(float(m.get(&"leather", 0.0)) * 100.0), roundi(cloth * 100.0)]


func _pick_body(body: StringName) -> void:
	_hair_choice = 1
	_beard_choice = 0
	_brow_choice = 0
	_set_body(body, _main_outfit())
	_fill_panel()
	show_mode(0)


## Any colors: each cloth slot a random hue, the metal a random finish. For seeing how far the dye goes.
func random_palette() -> void:
	var p := DyePalette.new()
	for slot: StringName in DyePalette.CLOTH:
		p.set(slot, Color.from_hsv(randf(), randf_range(0.3, 0.9), randf_range(0.25, 0.9), 1.0))
	p.leather = Color.from_hsv(randf_range(0.03, 0.1), randf_range(0.4, 0.8), randf_range(0.2, 0.5), 1.0)
	p.metal = (_metals[randi() % _metals.size()] as MetalFinish).duplicate() as MetalFinish
	p.title = "Random"
	palette = p
	_fill_panel()
	recolor()


## The colors as a palette file (in the editor; `palettes/custom_<time>.tres`). The path, or "" if it failed.
func save_palette() -> String:
	var p: DyePalette = palette.copy()
	p.title = "Custom %s" % Time.get_datetime_string_from_system().replace("T", " ")
	var path: String = Wardrobe.PALETTES + "custom_%d.tres" % int(Time.get_unix_time_from_system())
	if ResourceSaver.save(p, path) != OK:
		_info.text = "Could not save %s (an exported build cannot write res://)" % path
		return ""
	_palettes = Wardrobe.load_all(Wardrobe.PALETTES)
	_info.text = "Saved %s" % path
	_fill_panel()
	return path


func _refresh_info() -> void:
	if _info == null:
		return
	var lines: PackedStringArray = ["WARDROBE: %s" % MODES[mode]]
	match mode:
		0:
			lines.append("%d pieces worn. Z: the dye zones. T: turn." % (look.get("pieces", {}) as Dictionary).size())
		1:
			if tier_family == 0:
				lines.append("One Knight mesh, every metal: only the finish (MetalFinish) changes.")
			else:
				lines.append("%s tiers on the %s: one mesh, a palette a tier (palettes/%s*.tres)." % FAMILIES[tier_family])
		2:
			lines.append("Every outfit we have, both bodies%s." % (", in the palette" if worn_palette() != null else ", as painted"))
		_:
			lines.append("Painted (the pack's texture) beside dyed (the shader, from the bake's palette).")
	_info.text = "\n".join(lines)


# small builders

func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 17)
	l.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.55))
	_ui_root.add_child(l)


func _row() -> HBoxContainer:
	var r := HBoxContainer.new()
	_ui_root.add_child(r)
	return r


func _labeled(text: String) -> HBoxContainer:
	var r: HBoxContainer = _row()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 84
	r.add_child(l)
	return r


func _button(parent: Control, text: String, act: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(act)
	parent.add_child(b)
	return b


func _option(parent: Control, names: PackedStringArray, selected: int, act: Callable) -> OptionButton:
	var o := OptionButton.new()
	for n: String in names:
		o.add_item(n)
	o.selected = clampi(selected, 0, maxi(names.size() - 1, 0))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	o.item_selected.connect(func(i: int) -> void:
		if not _quiet:
			act.call(i))
	parent.add_child(o)
	return o


func _color_row(text: String, c: Color, act: Callable) -> void:
	var r: HBoxContainer = _labeled(text)
	var pick := ColorPickerButton.new()
	pick.color = Color(c.r, c.g, c.b, 1.0)
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(120, 26)
	pick.color_changed.connect(func(nc: Color) -> void:
		act.call(Color(nc.r, nc.g, nc.b, c.a)))
	r.add_child(pick)


## A dye slot: a check (dye it or keep the painting) and its color.
func _dye_row(text: String, c: Color, act: Callable) -> void:
	var r: HBoxContainer = _labeled(text)
	var on := CheckBox.new()
	on.text = "dye"
	on.button_pressed = c.a > 0.0
	r.add_child(on)
	var pick := ColorPickerButton.new()
	pick.color = Color(c.r, c.g, c.b, 1.0)
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(120, 26)
	r.add_child(pick)
	on.toggled.connect(func(v: bool) -> void:
		act.call(Color(pick.color.r, pick.color.g, pick.color.b, 1.0 if v else 0.0)))
	pick.color_changed.connect(func(nc: Color) -> void:
		on.set_pressed_no_signal(true)
		act.call(Color(nc.r, nc.g, nc.b, 1.0)))


func _slider(text: String, v: float, act: Callable) -> void:
	var r: HBoxContainer = _labeled(text)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.value = v
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(nv: float) -> void: act.call(nv))
	r.add_child(s)


# ---------------------------------------------------------------- shots

## Every view as a picture, and the inventory, into `dir`; then quit.
func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1600, 900)
	spinning = false
	_write_inventory(dir.path_join("wardrobe_inventory.md"))
	# One figure, the panel showing (the lab as Luke will see it).
	await _snap(dir, "lab", func() -> void: show_mode(0), true)
	_panel.visible = false
	_info.visible = false
	await _snap(dir, "outfits", func() -> void:
		palette = DyePalette.new()
		show_mode(2))
	await _snap(dir, "outfits_zones", func() -> void:
		show_zones = true
		show_mode(2))
	show_zones = false
	await _snap(dir, "tiers", func() -> void:
		palette = DyePalette.new()
		show_mode(1))
	await _snap(dir, "tiers_dyed", func() -> void:
		palette = DyePalette.new()
		palette.main = Color(0.55, 0.08, 0.08, 1.0)
		palette.trim = Color(0.85, 0.65, 0.25, 1.0)
		palette.under = Color(0.12, 0.12, 0.14, 1.0)
		show_mode(1))
	for i: int in range(1, FAMILIES.size()):
		await _snap(dir, "tiers_%s" % String(FAMILIES[i][0]).to_lower(), func() -> void:
			tier_family = i
			show_mode(1))
	await _snap(dir, "tiers_leather_back", func() -> void:
		tier_family = 1
		show_mode(1)
		for f: Node in _figures.get_children():
			(f as Node3D).rotation.y = 0.0)
	tier_family = 0
	for o: String in Wardrobe.outfits():
		await _snap(dir, "colourways_%s" % o.to_lower(), func() -> void:
			_set_body(&"male", o)
			show_mode(3))
	await _snap(dir, "custom", func() -> void:
		_custom_lineup())
	await _snap(dir, "custom_back", func() -> void:
		for f: Node in _figures.get_children():
			(f as Node3D).rotation.y = 0.0)
	AppExit.quit(get_tree(), 0)


## Four looks made with the dye alone, to show its reach.
func _custom_lineup() -> void:
	mode = 0
	_clear()
	var looks: Array[Array] = [
		["Knight", &"male", 3, [Color(0.12, 0.2, 0.45), Color(0.8, 0.8, 0.82), Color(0.85, 0.7, 0.3), Color(0.25, 0.15, 0.08), Color(0.08, 0.08, 0.1)], "Steel, royal blue"],
		["Knight", &"female", 6, [Color(0.5, 0.05, 0.05), Color(0.1, 0.1, 0.1), Color(0.75, 0.55, 0.2), Color(0.15, 0.1, 0.08), Color(0.2, 0.05, 0.05)], "Blackened, crimson"],
		["Ranger", &"male", 1, [Color(0.35, 0.3, 0.2), Color(0.45, 0.4, 0.3), Color(0.6, 0.5, 0.3), Color(0.3, 0.18, 0.1), Color(0.2, 0.18, 0.12)], "Copper, desert"],
		["Noble", &"female", 5, [Color(0.3, 0.1, 0.4), Color(0.9, 0.85, 0.7), Color(0.9, 0.75, 0.3), Color(0.2, 0.12, 0.1), Color(0.1, 0.06, 0.12)], "Gilded, violet"],
		["Wizard", &"male", 4, [Color(0.08, 0.35, 0.3), Color(0.6, 0.7, 0.65), Color(0.85, 0.85, 0.9), Color(0.25, 0.2, 0.15), Color(0.05, 0.12, 0.1)], "Blued, teal"],
		["Peasant", &"female", 0, [Color(0.7, 0.55, 0.3), Color(0.35, 0.45, 0.25), Color(0.8, 0.75, 0.6), Color(0.35, 0.22, 0.12), Color(0.3, 0.25, 0.2)], "Painted metal, harvest"],
	]
	var n: int = looks.size()
	for i: int in n:
		var e: Array = looks[i]
		var p := DyePalette.new()
		var cols: Array = e[3] as Array
		for k: int in DyePalette.CLOTH.size():
			p.set(DyePalette.CLOTH[k], cols[k] as Color)
		var mi: int = int(e[2])
		p.metal = null if mi == 0 else _metals[mi - 1] as MetalFinish
		var body: StringName = e[1] as StringName
		add_figure(_look_with(body, Wardrobe.full_set(String(e[0]), body)), p,
			Vector3((float(i) - float(n - 1) * 0.5) * PIECE_SPACING, 0, 0), String(e[4]))
	_frame(n, 0.0)


func _snap(dir: String, name: String, setup: Callable, panel: bool = false) -> void:
	setup.call()
	if panel:
		_fill_panel()
		_place_camera()
	for i: int in 24:
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("wardrobe_%s.png" % name))
	print("WARDROBE SHOT %s" % name)


## Every piece and what it is made of, as a Markdown table.
func _write_inventory(path: String) -> void:
	var lines: PackedStringArray = [
		"| body | outfit | slot | piece | metal | leather | main | accent | trim | under |",
		"|---|---|---|---|---|---|---|---|---|---|"]
	for p: Dictionary in Wardrobe.pieces():
		var m: Dictionary = Wardrobe.makeup(String(p["path"]))
		var row: PackedStringArray = [String(p["body"]), String(p["outfit"]), String(p["slot"]), String(p["part"])]
		for k: StringName in [&"metal", &"leather", &"main", &"accent", &"trim", &"under"]:
			var v: int = roundi(float(m.get(k, 0.0)) * 100.0)
			row.append("%d %%" % v if v > 0 else "")
		lines.append("| " + " | ".join(row) + " |")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
