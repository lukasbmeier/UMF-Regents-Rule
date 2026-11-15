extends "res://tests/suite_base.gd"
## THE WARDROBE (`-- --only=regents_wardrobe`; the wardrobe lab, 2026-11-14), with no server and no renderer:
##   - every outfit's pieces are found by file name, both bodies, each in its slot; a name that is not a piece is not
##   - every outfit has its zone mask, uncompressed and without mipmaps, every texel a dye slot; each colorway's palette
##     and the three tiers' metals load
##   - dressing gives every outfit surface the dye (one material per outfit, kept and re-tinted), never skin or hair;
##     undressing gives back what was worn before, a colorway's material too
##   - a closed helm hides hair and beard, a hood the hair only, a crown neither
##   - what a piece is made of: a helm all metal, the Knight's cloth torso cloth, shares that add up
##   - the lab opens and builds each view: one figure, a figure per metal (each in its own), every outfit on both
##     bodies, the Knight's colorways painted and dyed; Z dyes them all as zones
## How it LOOKS is the lab's shots (windowed): `"$GODOT" --path . res://game/regents/wardrobe/wardrobe_lab.tscn -- <dir>`.

const KNIGHT: String = "res://game/regents/art/outfits/knight/models/"
const BODY: String = "res://game/characters/quaternius/models/"


func run() -> void:
	_run_pieces()
	_run_zones_and_resources()
	await _run_dress()
	await _run_hair_under_helms()
	_run_makeup()
	await _run_lab()


func _run_pieces() -> void:
	var outfits: Array[String] = Wardrobe.outfits()
	for o: String in ["Knight", "Noble", "Peasant", "Ranger", "Wizard"]:
		_check(outfits.has(o), "the wardrobe finds the %s outfit" % o)
		for body: StringName in [&"male", &"female"]:
			var set: Dictionary[StringName, String] = Wardrobe.full_set(o, body)
			for slot: StringName in [&"torso", &"arms", &"legs", &"feet"]:
				_check(set.has(slot) and ResourceLoader.exists(set[slot]),
					"%s, %s: a %s piece (%s)" % [o, body, slot, set.get(slot, "none")])
	_check(Wardrobe.full_set("Knight", &"male")[&"torso"].ends_with("Male_Knight_Body_Armor.gltf"),
		"the Knight's whole set wears its armored torso, not its cloth one")
	_check(Wardrobe.pieces_for(&"female", &"head").size() == 4,
		"a woman's headwear: two helms, a crown and a hood (%d)" % Wardrobe.pieces_for(&"female", &"head").size())
	_check(Wardrobe.slot_of_part("Feet_Armor") == &"feet" and Wardrobe.slot_of_part("Acc_Scarf") == &"neck"
		and Wardrobe.slot_of_part("Acc_Pauldrons_Spike") == &"shoulders" and Wardrobe.slot_of_part("Body_Cloth") == &"torso",
		"a part's name gives its slot")
	_check(Wardrobe.slot_of_part("OnlyHead") == &"" and Wardrobe.slot_of_part("Cape") == &"",
		"NEGATIVE: a name that is no slot's is not a piece")
	for p: Dictionary in Wardrobe.pieces():
		_check(not String(p["file"]).begins_with("Regular_") and not String(p["file"]).begins_with("Hair_"),
			"NEGATIVE: heads and hair are not outfit pieces (%s)" % p["file"])


func _run_zones_and_resources() -> void:
	for o: String in Wardrobe.outfits():
		_check(Wardrobe.has_zones(o), "%s has a zone mask" % o)
		var img: Image = Wardrobe.zone_image(o)
		if img == null:
			continue
		_check(img.get_width() == 1024 and not img.has_mipmaps(), "%s's zones: 1024 px, no mipmaps" % o)
		var seen: Dictionary[int, bool] = {}
		var bad: int = 0
		for y: int in range(0, img.get_height(), 7):
			for x: int in range(0, img.get_width(), 7):
				var r: int = img.get_pixel(x, y).r8
				if r % 40 != 0 or r > 240:
					bad += 1
				seen[r / 40] = true
		_check(bad == 0, "%s's zones: every texel a dye slot, nothing between (%d off)" % [o, bad])
		_check(seen.has(1) and seen.has(2) and seen.has(5), "%s's zones hold metal, main cloth and leather" % o)
		for n: int in [1, 2, 3]:
			var pal: DyePalette = load(Wardrobe.PALETTES + "%s_%d.tres" % [o.to_lower(), n]) as DyePalette
			_check(pal != null and pal.metal != null and pal.main.a == 1.0,
				"%s's colorway %d as a palette, its metal too" % [o, n])
	var titles: PackedStringArray = []
	for r: Resource in Wardrobe.load_all(Wardrobe.METALS):
		var m: MetalFinish = r as MetalFinish
		titles.append(m.title)
		_check(m.metallic >= 0.0 and m.metallic <= 1.0 and m.roughness >= 0.0 and m.roughness <= 1.0,
			"the %s finish is in range" % m.title)
	for t: String in ["Copper", "Iron", "Steel"]:
		_check(" ".join(titles).contains(t), "a metal finish for %s" % t)
	_check(Wardrobe.outfit_of(_named("MI_Nothing")) == "" and Wardrobe.outfit_of(_named("MI_Regular_Male")) == ""
		and Wardrobe.outfit_of(null) == "", "NEGATIVE: a material with no zones is no outfit's")
	_check(Wardrobe.outfit_of(_named("MI_Knight")) == "Knight", "an outfit's material is its outfit's")


func _named(n: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = n
	return m


## A figure from a look, in the tree (so it assembles).
func _figure(l: Dictionary) -> ModularCharacter:
	var mc: ModularCharacter = Wardrobe.figure(l)
	add_child(mc)
	await get_tree().process_frame
	return mc


## Every surface of `mc` whose own material is an outfit's: [MeshInstance3D, surface].
func _outfit_surfaces(mc: Node) -> Array[Array]:
	var out: Array[Array] = []
	for n: Node in mc.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			if not Wardrobe.outfit_of(mi.mesh.surface_get_material(i)).is_empty():
				out.append([mi, i])
	return out


func _run_dress() -> void:
	# A mixed figure: Knight legs and feet under a Noble torso and arms, with hair.
	var pieces: Dictionary[StringName, String] = {&"torso": BODY + "Male_Noble_Body.gltf", &"arms": BODY + "Male_Noble_Arms.gltf",
		&"legs": KNIGHT + "Male_Knight_Legs_Armor.gltf", &"feet": KNIGHT + "Male_Knight_Feet_Armor.gltf"}
	var mc: ModularCharacter = await _figure({"body": &"male", "pieces": pieces, "hair": [BODY + "Hair_Buzzed.gltf"]})
	var surfaces: Array[Array] = _outfit_surfaces(mc)
	_check(surfaces.size() >= 4, "the mixed figure has outfit surfaces to dye (%d)" % surfaces.size())
	var pal := DyePalette.new()
	pal.main = Color(0.1, 0.2, 0.9, 1.0)
	pal.metal = load(Wardrobe.METALS + "1_copper.tres") as MetalFinish
	var count: int = Wardrobe.dress(mc, pal)
	_check(count == surfaces.size(), "every outfit surface wears the dye (%d of %d)" % [count, surfaces.size()])
	var mats: Dictionary[String, ShaderMaterial] = {}
	for s: Array in surfaces:
		var mat: ShaderMaterial = (s[0] as MeshInstance3D).get_surface_override_material(int(s[1])) as ShaderMaterial
		var outfit: String = Wardrobe.outfit_of((s[0] as MeshInstance3D).mesh.surface_get_material(int(s[1])))
		_check(mat != null and mat.get_shader_parameter(&"zone_tex") != null, "a dyed surface has its outfit's zones")
		if mat == null:
			continue
		if mats.has(outfit):
			_check(mats[outfit] == mat, "one dye material per outfit on a figure")
		mats[outfit] = mat
		_check((mat.get_shader_parameter(&"main_color") as Color).is_equal_approx(pal.main)
			and (mat.get_shader_parameter(&"metal_color") as Color).is_equal_approx(pal.metal.color),
			"the dye wears the palette's main and its metal")
	_check(mats.size() == 2, "two outfits, two dye materials (%d)" % mats.size())
	for n: Node in mc.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count()):
			if Wardrobe.outfit_of(mi.mesh.surface_get_material(i)).is_empty():
				_check(not (mi.get_surface_override_material(i) is ShaderMaterial),
					"NEGATIVE: skin and hair keep their own material (%s)" % mi.name)
	# Re-tinted, not rebuilt.
	pal.main = Color(0.9, 0.1, 0.1, 1.0)
	Wardrobe.dress(mc, pal, true)
	var again: ShaderMaterial = (surfaces[0][0] as MeshInstance3D).get_surface_override_material(int(surfaces[0][1])) as ShaderMaterial
	_check(mats.values().has(again) and (again.get_shader_parameter(&"main_color") as Color).is_equal_approx(pal.main)
		and bool(again.get_shader_parameter(&"show_zones")), "a second dressing re-tints the same materials, zones on")
	Wardrobe.dress(mc, null)
	var given_back: bool = true
	for s: Array in surfaces:
		given_back = given_back and (s[0] as MeshInstance3D).get_surface_override_material(int(s[1])) == null
	_check(given_back and not mc.has_meta(Wardrobe.MATS_META), "undressed, the figure wears its own materials again")
	_check(Wardrobe.dress(mc, null) == 0, "NEGATIVE: undressing an undressed figure does nothing")
	mc.queue_free()
	# A painted colorway's material is given back, not dropped.
	var way: ModularCharacter = Wardrobe.figure({"body": &"male", "pieces": Wardrobe.full_set("Peasant", &"male", false)})
	way.outfit_texture = load("res://game/characters/quaternius/textures/T_Peasant_2_BaseColor.png") as Texture2D
	add_child(way)
	await get_tree().process_frame
	var ws: Array[Array] = _outfit_surfaces(way)
	var before: Material = (ws[0][0] as MeshInstance3D).get_surface_override_material(int(ws[0][1]))
	_check(before is StandardMaterial3D, "a painted colorway wears its own material")
	Wardrobe.dress(way, pal)
	Wardrobe.dress(way, pal)
	Wardrobe.dress(way, null)
	_check((ws[0][0] as MeshInstance3D).get_surface_override_material(int(ws[0][1])) == before,
		"undressed (after two dressings), the colorway's material is back")
	way.queue_free()


func _hair_meshes(mc: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	for n: Node in mc.find_children("*", "MeshInstance3D", true, false):
		if String(n.name).begins_with("Hair_"):
			out.append(String(n.name))
	return out


func _run_hair_under_helms() -> void:
	var hair: Array[String] = [BODY + "Hair_Buzzed.gltf", BODY + "Hair_Beard.gltf", BODY + "Eyebrows_Regular.gltf"]
	var cases: Array[Array] = [
		["Knight armet", KNIGHT + "Male_Knight_Head_Armet.gltf", false, false],
		["Ranger hood", BODY + "Male_Ranger_Head_Hood.gltf", false, true],
		["Noble crown", BODY + "Male_Noble_Head_Crown.gltf", true, true],
		["no headwear", "", true, true],
	]
	for c: Array in cases:
		var pieces: Dictionary[StringName, String] = Wardrobe.full_set("Peasant", &"male", false)
		if not String(c[1]).is_empty():
			pieces[&"head"] = String(c[1])
		var mc: ModularCharacter = await _figure({"body": &"male", "pieces": pieces, "hair": hair})
		var shown: PackedStringArray = _hair_meshes(mc)
		var has_hair: bool = false
		var has_beard: bool = false
		for h: String in shown:
			has_hair = has_hair or h.begins_with("Hair_Buzzed")
			has_beard = has_beard or h.begins_with("Hair_Beard")
		_check(has_hair == bool(c[2]) and has_beard == bool(c[3]),
			"%s: hair %s, beard %s (%s)" % [c[0], "shown" if c[2] else "hidden", "shown" if c[3] else "hidden", ", ".join(shown)])
		mc.queue_free()


func _run_makeup() -> void:
	var helm: Dictionary = Wardrobe.makeup(KNIGHT + "Male_Knight_Head_Armet.gltf")
	_check(float(helm.get(&"metal", 0.0)) > 0.95, "the armet is metal (%s)" % helm)
	var cloth: Dictionary = Wardrobe.makeup(KNIGHT + "Male_Knight_Body_Cloth.gltf")
	_check(float(cloth.get(&"main", 0.0)) > 0.05, "the Knight's cloth torso has main cloth (%s)" % cloth)
	var sum: float = 0.0
	for v: Variant in cloth.values():
		sum += float(v)
	_check(absf(sum - 1.0) < 0.001, "a piece's shares add up (%.3f)" % sum)
	_check(Wardrobe.makeup("res://nothing/here.gltf").is_empty(), "NEGATIVE: no piece, no makeup")


func _figure_count(lab: Node) -> int:
	return (lab.get(&"_figures") as Node3D).get_child_count()


## The dye material a lab figure wears on its first outfit surface (null if none).
func _first_dye(figure_root: Node) -> ShaderMaterial:
	for c: Node in figure_root.get_children():
		if c is Mannequin and (c as Mannequin).model != null:
			for s: Array in _outfit_surfaces((c as Mannequin).model):
				return (s[0] as MeshInstance3D).get_surface_override_material(int(s[1])) as ShaderMaterial
	return null


func _run_lab() -> void:
	var packed: PackedScene = load("res://game/regents/wardrobe/wardrobe_lab.tscn") as PackedScene
	_check(packed != null, "the wardrobe lab's scene loads")
	if packed == null:
		return
	var lab: Node3D = packed.instantiate() as Node3D
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_figure_count(lab) == 1, "the lab opens on one figure")
	var root: Node = (lab.get(&"_figures") as Node3D).get_child(0)
	_check(root.get_child(0) is Mannequin and (root.get_child(0) as Mannequin).model is ModularCharacter,
		"the figure is a dressed ModularCharacter, animated (a Mannequin)")
	lab.call(&"show_mode", 1)
	var metals: Array[Resource] = Wardrobe.load_all(Wardrobe.METALS)
	_check(_figure_count(lab) == metals.size(), "metal tiers: a figure per finish (%d)" % _figure_count(lab))
	var figures: Array[Node] = (lab.get(&"_figures") as Node3D).get_children()
	for i: int in mini(figures.size(), metals.size()):
		var mat: ShaderMaterial = _first_dye(figures[i])
		_check(mat != null and (mat.get_shader_parameter(&"metal_color") as Color).is_equal_approx((metals[i] as MetalFinish).color),
			"metal tiers: figure %d wears %s" % [i, (metals[i] as MetalFinish).title])
	# Luke, 2026-11-14: leather is the Ranger, cloth the Wizard, everyone starts in the Peasant clothes.
	for fam: Array in [[1, "Ranger", "leather_", 3], [2, "Wizard", "cloth_", 3], [3, "Peasant", "starter_", 4]]:
		lab.set(&"tier_family", int(fam[0]))
		lab.call(&"show_mode", 1)
		var pals: Array = lab.call(&"tier_palettes", String(fam[2])) as Array
		_check(pals.size() == int(fam[3]) and _figure_count(lab) == pals.size(),
			"%s tiers: a figure per palette (%d figures, %d palettes)" % [fam[1], _figure_count(lab), pals.size()])
		var tf: Array[Node] = (lab.get(&"_figures") as Node3D).get_children()
		for i: int in mini(tf.size(), pals.size()):
			var mat: ShaderMaterial = _first_dye(tf[i])
			_check(mat != null and (mat.get_shader_parameter(&"leather_color") as Color).is_equal_approx((pals[i] as DyePalette).leather),
				"%s tiers: figure %d wears %s" % [fam[1], i, (pals[i] as DyePalette).title])
			var worn_head: bool = false
			for c: Node in tf[i].get_children():
				if c is Mannequin:
					for m: Node in (c as Mannequin).model.find_children("*Head_*", "MeshInstance3D", true, false):
						worn_head = true
			_check(worn_head == (String(fam[1]) == "Ranger"), "%s tiers: headwear %s" % [fam[1], "worn" if worn_head else "none"])
	lab.set(&"tier_family", 0)
	lab.call(&"show_mode", 2)
	_check(_figure_count(lab) == Wardrobe.outfits().size() * 2, "outfits: every outfit on both bodies (%d)" % _figure_count(lab))
	lab.call(&"show_mode", 3)
	_check(_figure_count(lab) == 6, "colorways: the Knight's three painted and three dyed (%d)" % _figure_count(lab))
	lab.call(&"set_zones", true)
	var all_zones: bool = true
	for f: Node in (lab.get(&"_figures") as Node3D).get_children():
		var mat: ShaderMaterial = _first_dye(f)
		all_zones = all_zones and mat != null and bool(mat.get_shader_parameter(&"show_zones"))
	_check(all_zones, "Z: every figure shows its zones, the painted ones too")
	lab.call(&"set_zones", false)
	lab.call(&"show_mode", 0)
	lab.call(&"random_palette")
	var pal: DyePalette = lab.get(&"palette") as DyePalette
	var mat0: ShaderMaterial = _first_dye((lab.get(&"_figures") as Node3D).get_child(0))
	_check(mat0 != null and (mat0.get_shader_parameter(&"main_color") as Color).is_equal_approx(pal.main),
		"random colors re-dye the figure")
	lab.queue_free()
	await get_tree().process_frame
