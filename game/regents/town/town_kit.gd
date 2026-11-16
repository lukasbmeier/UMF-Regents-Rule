@tool
class_name TownKit extends RefCounted
## THE MEDIEVAL VILLAGE KIT, DRESSED (2026-11-15, `docs/regents_rule/SETTLEMENTS_PREP.md`): which kit material is which
## dye slot, the town dye's materials for a `SettlementStyle`, and the two things done to a building: DRESS it (every
## surface the style's material, a seed and a foot height for its nudge) and MERGE it (its pieces into one mesh, one
## surface per material: a house of a hundred pieces draws as a dozen).
##
## The pieces are the kit's glTF (Godot) exports in `res://game/regents/art/village/` (CC0, `ATTRIBUTION.md`), with
## their `-convcolonly` collisions. Their imported materials keep the kit's names (`MI_Plaster`, ...): that name is
## how a surface is found here, so a generated mesh (`CastleWall`) names its surfaces the same way
## (`placeholder`) and is dressed like any piece.
##
## Materials are shared: one per kit material per style, for every building that wears it. A building's own nudge is
## two instance uniforms, never a material of its own.

const VILLAGE: String = "res://game/regents/art/village/"
## The Fantasy Props kit (CC0, `ATTRIBUTION.md` there): market stalls, barrels, banners, furniture.
const PROPS: String = "res://game/regents/art/props/"
const SURFACE_SHADER: Shader = preload("res://game/regents/town/town_surface.gdshader")
const LEAVES_SHADER: Shader = preload("res://game/regents/town/town_leaves.gdshader")

enum Mode { ONE, PLASTER, TRIM, ROOF, GLASS, METAL, KEEP }

## Each kit material: its mode, its slots (`SettlementStyle.SLOTS`: a, b, c), its textures (`T_<tex>_BaseColor`,
## `_Normal`, `_Roughness` unless named) and its MEAN: the average linear brightness of its color texture (measured,
## `game/regents/tools/town_kit.py means`), which the dye scales from.
const SURFACES: Dictionary = {
	"MI_Plaster": {"mode": Mode.PLASTER, "slots": [&"plaster", &"stone"], "tex": "Plaster", "rough": "T_Plaster_ORM",
		"mean": 0.3509, "under": "Brick", "under_mean": 0.246},
	"MI_Brick": {"mode": Mode.ONE, "slots": [&"stone"], "tex": "Brick", "mean": 0.246},
	"MI_RockTrim": {"mode": Mode.ONE, "slots": [&"stone"], "tex": "RockTrim", "rough": "T_RockTrim_ORM", "mean": 0.2522},
	"MI_UnevenBrick": {"mode": Mode.ONE, "slots": [&"masonry"], "tex": "UnevenBrick", "mean": 0.2019},
	"MI_RedBrick": {"mode": Mode.ONE, "slots": [&"brick"], "tex": "RedBrick", "normal": "T_Brick_Normal",
		"rough": "T_Brick_Roughness", "mean": 0.2309},
	"MI_RoundRocks": {"mode": Mode.ONE, "slots": [&"paving"], "tex": "RoundRocks", "mean": 0.0753},
	"MI_RoundTiles": {"mode": Mode.ROOF, "slots": [&"roof"], "tex": "RoundTiles", "mean": 0.1631},
	"MI_FlatTiles": {"mode": Mode.ROOF, "slots": [&"roof"], "tex": "FlatTiles", "mean": 0.0871},
	"MI_WoodTrim": {"mode": Mode.TRIM, "slots": [&"planks", &"timber", &"stone"], "tex": "WoodTrim", "mean": 0.1851},
	"MI_WoodTrim_Wear": {"mode": Mode.TRIM, "slots": [&"planks", &"timber", &"stone"], "tex": "WoodTrim",
		"mean": 0.1851, "uv2_wear": true},
	"MI_MetalOrnaments": {"mode": Mode.METAL, "slots": [&"metal"], "tex": "MetalOrnaments", "normal": "T_Normal_Default",
		"mean": 0.2501, "metallic": 1.0},
	"MI_WindowGlass": {"mode": Mode.GLASS, "slots": [&"glass"], "albedo": "T_WindowGradient"},
	"MI_Vine": {"leaves": true, "slots": [&"foliage"], "albedo": "T_VineLeaf"},
	# The Fantasy Props kit (`PROPS`): its wood in the planks' color, its metal in the metal's, its cloth (banners,
	# awnings, stall covers) in the style's CLOTH; its props sheet and its signs keep their painting (and the props'
	# vertex colors, which tell their parts apart: fruit, rope, leather). The means measured like the village's.
	"MI_Trim_Furniture": {"mode": Mode.ONE, "slots": [&"planks"], "tex": "Trim_Furniture", "rough": "T_Trim_Furniture_ORM",
		"mean": 0.1776, "dir": PROPS},
	"MI_Trim_Metal": {"mode": Mode.METAL, "slots": [&"metal"], "tex": "Trim_Metal", "rough": "T_Trim_Metal_ORM",
		"mean": 0.2235, "metallic": 1.0, "dir": PROPS},
	"MI_Trim_Metal_Vertex": {"mode": Mode.METAL, "slots": [&"metal"], "tex": "Trim_Metal", "rough": "T_Trim_Metal_ORM",
		"mean": 0.2235, "metallic": 1.0, "vertex": true, "dir": PROPS},
	"MI_Trim_Cloth": {"mode": Mode.ONE, "slots": [&"cloth"], "tex": "Trim_Cloth", "rough": "T_Trim_Cloth_ORM",
		"mean": 0.3746, "dir": PROPS},
	"MI_Banner": {"mode": Mode.ONE, "slots": [&"cloth"], "tex": "Trim_Cloth", "rough": "T_Trim_Cloth_ORM",
		"mean": 0.3746, "dir": PROPS},
	"MI_Trim_Props": {"mode": Mode.KEEP, "slots": [&"planks"], "tex": "Trim_Props", "rough": "T_Trim_Props_ORM",
		"mean": 0.3121, "dir": PROPS},
	"MI_Trim_Props_Vertex": {"mode": Mode.KEEP, "slots": [&"planks"], "tex": "Trim_Props", "rough": "T_Trim_Props_ORM",
		"mean": 0.3121, "vertex": true, "dir": PROPS},
	"MI_WoodenSign": {"mode": Mode.KEEP, "slots": [&"planks"], "tex": "Trim_Cloth", "rough": "T_Trim_Cloth_ORM",
		"mean": 0.3746, "dir": PROPS},
	"MI_Page_1": {"mode": Mode.KEEP, "slots": [&"planks"], "albedo": "T_Page_Noise", "dir": PROPS},
	"MI_Page_2": {"mode": Mode.KEEP, "slots": [&"planks"], "albedo": "T_Page_Noise", "dir": PROPS},
	"MI_Page_Empty": {"mode": Mode.KEEP, "slots": [&"planks"], "albedo": "T_Page_Noise", "dir": PROPS},
	"MI_Runes": {"mode": Mode.KEEP, "slots": [&"metal"], "albedo": "T_Runes", "dir": PROPS},
}
## The wood trim sheet's band means (light planks, dark timber, end grain, the stone strip), measured like `mean`.
const TRIM_BANDS: Vector4 = Vector4(0.156, 0.071, 0.263, 0.307)

## Materials made so far: "<style id>|<kit material>" -> ShaderMaterial. Kept for the life of the game.
static var _made: Dictionary[String, ShaderMaterial] = {}
## Which style each made material wears (to refresh it after an edit): the same keys.
static var _style_of: Dictionary[String, SettlementStyle] = {}
static var _textures: Dictionary[String, Texture2D] = {}
static var _placeholders: Dictionary[String, StandardMaterial3D] = {}
## Kit material names met by `dress` that `SURFACES` does not know (left as imported). The suite reads it.
static var unknown: Dictionary[String, bool] = {}
## How dark it is (0 day, 1 night): every made material's windows.
static var night: float = 0.0


## A kit piece by its file name ("Wall_Plaster_Straight", "Barrel"): the village kit's, else the props kit's.
static func piece(piece_name: String) -> PackedScene:
	return load(_piece_path(piece_name)) as PackedScene


static func has_piece(piece_name: String) -> bool:
	return ResourceLoader.exists(_piece_path(piece_name))


static func _piece_path(piece_name: String) -> String:
	var village: String = VILLAGE + piece_name + ".gltf"
	return village if ResourceLoader.exists(village) else PROPS + piece_name + ".gltf"


static var _bounds: Dictionary[String, AABB] = {}


## A piece's drawn bounds in its own space (its meshes, not its collisions), measured once. The kit's pieces are
## mostly centered on their origin, not all: `Roof_*Tiles_6x4` starts at its origin and runs 5 m along +z.
static func piece_bounds(piece_name: String) -> AABB:
	if _bounds.has(piece_name):
		return _bounds[piece_name]
	var box := AABB()
	var first: bool = true
	var scene: PackedScene = piece(piece_name) if has_piece(piece_name) else null
	if scene != null:
		var root: Node3D = scene.instantiate() as Node3D
		var todo: Array[Node] = [root]
		while not todo.is_empty():
			var n: Node = todo.pop_back()
			todo.append_array(n.get_children())
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var b: AABB = _relative(root, mi) * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		root.free()
	_bounds[piece_name] = box
	return box


static func _tex(file: String, dir: String = VILLAGE) -> Texture2D:
	var path: String = dir + file + ".png"
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_textures[path] = t
	return t


## The town dye's material for a kit material under a style; null for a name `SURFACES` does not know.
static func material_for(kit_material: String, style: SettlementStyle) -> ShaderMaterial:
	if not SURFACES.has(kit_material) or style == null:
		return null
	var key: String = "%d|%s" % [style.get_instance_id(), kit_material]
	if _made.has(key):
		return _made[key]
	var e: Dictionary = SURFACES[kit_material]
	var mat := ShaderMaterial.new()
	mat.resource_name = kit_material
	mat.shader = LEAVES_SHADER if bool(e.get("leaves", false)) else SURFACE_SHADER
	var tex: String = str(e.get("tex", ""))
	var dir: String = str(e.get("dir", VILLAGE))
	if e.has("albedo"):
		mat.set_shader_parameter(&"albedo_tex", _tex(str(e["albedo"]), dir))
	elif not tex.is_empty():
		mat.set_shader_parameter(&"albedo_tex", _tex("T_%s_BaseColor" % tex, dir))
	if not bool(e.get("leaves", false)):
		mat.set_shader_parameter(&"mode", int(e["mode"]))
		mat.set_shader_parameter(&"uv2_wear", bool(e.get("uv2_wear", false)))
		mat.set_shader_parameter(&"use_vertex_color", bool(e.get("vertex", false)))
		if not tex.is_empty():
			mat.set_shader_parameter(&"normal_tex", _tex(str(e.get("normal", "T_%s_Normal" % tex)), dir))
			mat.set_shader_parameter(&"rough_tex", _tex(str(e.get("rough", "T_%s_Roughness" % tex)), dir))
		mat.set_shader_parameter(&"mean_luma", float(e.get("mean", 0.25)))
		mat.set_shader_parameter(&"metallic_value", float(e.get("metallic", 0.0)))
		mat.set_shader_parameter(&"band_means", TRIM_BANDS)
		if e.has("under"):
			var u: String = str(e["under"])
			mat.set_shader_parameter(&"under_tex", _tex("T_%s_BaseColor" % u))
			mat.set_shader_parameter(&"under_normal", _tex("T_%s_Normal" % u))
			mat.set_shader_parameter(&"under_rough", _tex("T_%s_Roughness" % u))
			mat.set_shader_parameter(&"under_mean", float(e["under_mean"]))
		mat.set_shader_parameter(&"top_wear_tex", _tex("T_TopWear"))
		mat.set_shader_parameter(&"bottom_wear_tex", _tex("T_BottomWear"))
		mat.set_shader_parameter(&"noise_tex", _tex("T_BrushedNoise"))
	var slots: Array = e["slots"]
	var ids := Vector3i.ZERO
	for i: int in 3:
		var slot: StringName = slots[mini(i, slots.size() - 1)] as StringName
		ids[i] = SettlementStyle.SLOTS.find(slot)
	mat.set_shader_parameter(&"slot_ids", ids)
	_made[key] = mat
	_style_of[key] = style
	apply_style(mat, kit_material, style)
	return mat


## A style's colors, weather and night onto one made material (also after the style changed: `refresh`).
static func apply_style(mat: ShaderMaterial, kit_material: String, style: SettlementStyle) -> void:
	var slots: Array = (SURFACES[kit_material] as Dictionary)["slots"]
	var names: Array[StringName] = [&"dye_a", &"dye_b", &"dye_c"]
	for i: int in 3:
		var slot: StringName = slots[mini(i, slots.size() - 1)] as StringName
		mat.set_shader_parameter(names[i], style.color_of(slot) if i < slots.size() else Color(1, 1, 1, 0))
	for n: StringName in SettlementStyle.NUMBERS:
		mat.set_shader_parameter(n, float(style.get(n)))
	for c: StringName in SettlementStyle.COLORS:
		mat.set_shader_parameter(c, style.get(c) as Color)
	mat.set_shader_parameter(&"night", night)


## Every material made for `style` again from its fields (the lab, after an edit).
static func refresh(style: SettlementStyle) -> void:
	for key: String in _made:
		if _style_of[key] == style:
			apply_style(_made[key], key.get_slice("|", 1), style)


## Day (0) to night (1), for every made material.
static func set_night(v: float) -> void:
	night = v
	for key: String in _made:
		_made[key].set_shader_parameter(&"night", v)


## A plain material named as a kit material, showing its texture: what a generated mesh wears until it is dressed
## (and in the editor, where nothing is dressed).
static func placeholder(kit_material: String) -> StandardMaterial3D:
	if _placeholders.has(kit_material):
		return _placeholders[kit_material]
	var m := StandardMaterial3D.new()
	m.resource_name = kit_material
	var e: Dictionary = SURFACES.get(kit_material, {})
	var tex: String = str(e.get("tex", ""))
	if not tex.is_empty():
		m.albedo_texture = _tex("T_%s_BaseColor" % tex)
		m.normal_enabled = true
		m.normal_texture = _tex(str(e.get("normal", "T_%s_Normal" % tex)))
	_placeholders[kit_material] = m
	return m


## The kit material a surface wears: its override, else the mesh's own; "" for none.
static func surface_kit_material(mi: MeshInstance3D, i: int) -> String:
	var m: Material = mi.get_surface_override_material(i)
	if m == null and mi.mesh != null:
		m = mi.mesh.surface_get_material(i)
	return m.resource_name if m != null else ""


## Dresses a building in a style: every kit surface under `root` the style's material, every mesh the building's
## `building_seed` and foot height. Returns how many surfaces were dressed. A name `SURFACES` does not know is left as it is
## and noted in `unknown`.
static func dress(root: Node, style: SettlementStyle, building_seed: int, base_y: float) -> int:
	var count: int = 0
	var seed_f: float = float(posmod(building_seed, 100003)) * 0.137
	for n: Node in [root] + root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var kit_name: String = surface_kit_material(mi, i)
			var mat: ShaderMaterial = material_for(kit_name, style)
			if mat == null:
				if not kit_name.is_empty():
					unknown[kit_name] = true
				continue
			mi.set_surface_override_material(i, mat)
			count += 1
		mi.set_instance_shader_parameter(&"building_seed", seed_f)
		mi.set_instance_shader_parameter(&"building_base", base_y)
	return count


## A kit scene to place as a building (a demo house, a piece): instanced, its pieces' many collision bodies made one
## (`gather_collisions`). Place kit scenes through this: a town of separate piece bodies passes the physics engine's
## body limit (10240) long before it looks full.
static func instance_building(scene: PackedScene) -> Node3D:
	var n: Node3D = scene.instantiate() as Node3D
	var body := StaticBody3D.new()
	body.name = "Body"
	gather_collisions(n, body, Transform3D.IDENTITY)
	n.add_child(body)
	return n


## Every collision shape under `root` (a scene not yet in the tree) moved into `into`, placed by `xf` (where `root`
## stands in `into`'s parent), and the bodies they came from freed.
static func gather_collisions(root: Node, into: StaticBody3D, xf: Transform3D) -> int:
	var moved: int = 0
	for b: Node in root.find_children("*", "StaticBody3D", true, false):
		var body: StaticBody3D = b as StaticBody3D
		var rel: Transform3D = _relative(root, body)
		for c: Node in body.get_children():
			var shape: CollisionShape3D = c as CollisionShape3D
			if shape == null:
				continue
			var t: Transform3D = xf * rel * shape.transform
			body.remove_child(shape)
			shape.owner = null
			into.add_child(shape)
			shape.transform = t
			moved += 1
		body.get_parent().remove_child(body)
		body.free()
	return moved


## `n`'s transform in `root`'s space, out of the tree (the chain of local transforms).
static func _relative(root: Node, n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		var n3: Node3D = cur as Node3D
		if n3 != null:
			t = n3.transform * t
		cur = cur.get_parent()
	return t


## Every mesh under `root` into ONE MeshInstance3D child of `root`, a surface per material (and per vertex format),
## its pieces' meshes then freed (their collisions stay). Returns the new mesh's node, or null with no meshes.
static func merge(root: Node3D) -> MeshInstance3D:
	var groups: Dictionary[String, SurfaceTool] = {}
	var group_mat: Dictionary[String, Material] = {}
	var order: Array[String] = []
	var inv: Transform3D = root.global_transform.affine_inverse()
	var used: Array[MeshInstance3D] = []
	const FORMAT_BITS: int = Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_COLOR \
		| Mesh.ARRAY_FORMAT_TANGENT
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		used.append(mi)
		var xf: Transform3D = inv * mi.global_transform
		for i: int in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			var fmt: int = mi.mesh.surface_get_format(i) & FORMAT_BITS
			var key: String = "%d|%d" % [m.get_instance_id() if m != null else 0, fmt]
			if not groups.has(key):
				var st := SurfaceTool.new()
				groups[key] = st
				group_mat[key] = m
				order.append(key)
			groups[key].append_from(mi.mesh, i, xf)
	if order.is_empty():
		return null
	var mesh := ArrayMesh.new()
	for key: String in order:
		mesh = groups[key].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, group_mat[key])
	for mi: MeshInstance3D in used:
		mi.get_parent().remove_child(mi)
		mi.free()
	var out := MeshInstance3D.new()
	out.name = "Merged"
	out.mesh = mesh
	root.add_child(out)
	return out
