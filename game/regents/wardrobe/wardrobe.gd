class_name Wardrobe extends RefCounted
## THE WARDROBE (2026-11-14, before armor): every outfit piece we have, by body and slot, and the dye that colors any of
## them any way (`outfit_dye.gdshader`, `DyePalette`, `MetalFinish`). The wardrobe lab (`wardrobe_lab.tscn`, F6) is its
## window; the inventory and the plan are `docs/regents_rule/WARDROBE.md`.
##
## PIECES ARE FOUND, NOT LISTED: every `<Male|Female>_<Outfit>_<Part>.gltf` in `PIECE_DIRS` is a piece, its slot from
## its part's name (`SLOT_OF`). A new outfit is its files dropped in a folder here, its zones in `zones.json` and a
## bake (`game/regents/tools/wardrobe_assets.py`). The foundation's four outfits are in `game/characters/quaternius/`;
## the Knight is the genre's (`game/regents/art/outfits/knight/`).
##
## DRESSING: `dress(model, palette)` gives every outfit surface of an assembled `ModularCharacter` a dye material
## (one per outfit on that model, kept on the model and re-tinted on the next call, so a color picker can drag).
## Skin, hair and an outfit with no zones keep their own materials. Presentation only.

const PIECE_DIRS: Array[String] = [
	"res://game/characters/quaternius/models/",
	"res://game/regents/art/outfits/knight/models/",
]
const ZONES: String = "res://game/regents/wardrobe/zones/"
const SHADER: String = "res://game/regents/wardrobe/outfit_dye.gdshader"
const PALETTES: String = "res://game/regents/wardrobe/palettes/"
const METALS: String = "res://game/regents/wardrobe/metals/"
const HEADS: String = "res://game/characters/quaternius/models/Regular_%s_OnlyHead.gltf"
const SKIN_TEX: String = "res://game/characters/quaternius/textures/T_Regular_%s_%s_BaseColor.png"
## The slots a piece can fill, in the order a figure is dressed and the lab lists them.
const SLOTS: Array[StringName] = [&"head", &"shoulders", &"neck", &"torso", &"arms", &"legs", &"feet"]
## A part's name (after `<Sex>_<Outfit>_`) to its slot, by prefix. First match wins.
const SLOT_OF: Array[Array] = [
	["Body", &"torso"], ["Arms", &"arms"], ["Legs", &"legs"], ["Feet", &"feet"], ["Head", &"head"],
	["Acc_Pauldron", &"shoulders"], ["Acc_Gorget", &"neck"], ["Acc_Scarf", &"neck"],
]
## The slots a figure may leave empty (the rest would show the missing body: only a head is worn under clothes).
const OPTIONAL: Array[StringName] = [&"head", &"shoulders", &"neck"]
## The dye slots, as the zone mask numbers them (R / 40).
const DYE_SLOTS: Array[StringName] = [&"keep", &"metal", &"main", &"accent", &"trim", &"leather", &"under"]
## Headwear that hides hair, by part: "all" (a closed helm: hair and beard), "hair" (a hood: the beard stays). Hair
## would poke through either.
const HIDES_HAIR: Dictionary[String, String] = {"Head_Armet": "all", "Head_Horns": "all", "Head_Hood": "hair"}
const BEARDS: Array[String] = ["Hair_Beard", "Hair_Moustache", "Hair_MuttonChops"]
## On a model: { outfit: ShaderMaterial } it was dressed with.
const MATS_META: StringName = &"wardrobe_mats"

static var _pieces: Array[Dictionary] = []
static var _makeup: Dictionary[String, Dictionary] = {}


## EVERY PIECE: [{path, file, body (&"male"/&"female"), outfit, part, slot}], sorted by outfit then part.
static func pieces() -> Array[Dictionary]:
	if not _pieces.is_empty():
		return _pieces
	for dir: String in PIECE_DIRS:
		for f: String in ResourceLoader.list_directory(dir):
			if not f.ends_with(".gltf"):
				continue
			var stem: String = f.get_basename()
			var bits: PackedStringArray = stem.split("_", false, 2)
			if bits.size() < 3 or not (bits[0] == "Male" or bits[0] == "Female"):
				continue
			var slot: StringName = slot_of_part(bits[2])
			if slot.is_empty():
				continue
			_pieces.append({"path": dir + f, "file": stem, "body": StringName(bits[0].to_lower()),
				"outfit": bits[1], "part": bits[2], "slot": slot})
	_pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["file"]) < String(b["file"]))
	return _pieces


## The slot a part name fills (`Body_Armor` -> torso), or empty for one that is not worn (a whole outfit's file).
static func slot_of_part(part: String) -> StringName:
	for pair: Array in SLOT_OF:
		if part.begins_with(String(pair[0])):
			return pair[1] as StringName
	return &""


## The pieces one body can wear in one slot.
static func pieces_for(body: StringName, slot: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in pieces():
		if p["body"] == body and p["slot"] == slot:
			out.append(p)
	return out


## The outfits found, in order.
static func outfits() -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in pieces():
		if not out.has(String(p["outfit"])):
			out.append(String(p["outfit"]))
	return out


## An outfit's whole set for a body, slot by slot: { slot: path }. Torso, arms, legs and feet; the first headwear,
## shoulders and neck it has when `extras`. (The Knight's armored torso before its cloth one.)
static func full_set(outfit: String, body: StringName, extras: bool = true) -> Dictionary[StringName, String]:
	var out: Dictionary[StringName, String] = {}
	for slot: StringName in SLOTS:
		if OPTIONAL.has(slot) and not extras:
			continue
		var best: String = ""
		for p: Dictionary in pieces_for(body, slot):
			if String(p["outfit"]) != outfit:
				continue
			if best.is_empty() or String(p["part"]).contains("Armor"):
				best = String(p["path"])
		if not best.is_empty():
			out[slot] = best
	return out


## Whether an outfit has baked zones (dyeable).
static func has_zones(outfit: String) -> bool:
	return ResourceLoader.exists(zone_path(outfit))


static func zone_path(outfit: String) -> String:
	return ZONES + "T_%s_Zones.png" % outfit


## The outfit an imported material belongs to (`MI_Knight` -> Knight), or "".
static func outfit_of(mat: Material) -> String:
	if mat == null or not mat.resource_name.begins_with("MI_"):
		return ""
	var o: String = mat.resource_name.trim_prefix("MI_")
	return o if has_zones(o) else ""


## Dress every outfit surface under `model` in `palette` (null: the outfits' own materials back). `show_zones` paints
## each slot one flat color. Returns how many surfaces wear the dye.
static func dress(model: Node, palette: DyePalette, show_zones: bool = false) -> int:
	var undress: bool = palette == null and not show_zones
	if undress and not model.has_meta(MATS_META):
		return 0   # never dressed: nothing to give back
	var mats: Dictionary = model.get_meta(MATS_META, {}) as Dictionary
	var count: int = 0
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			var outfit: String = outfit_of(src)
			if outfit.is_empty():
				continue
			# What the surface wore before the dye (a colorway's material, or none), given back undressed.
			var before: StringName = StringName("wardrobe_before_%d" % i)
			if undress:
				if mi.has_meta(before):
					mi.set_surface_override_material(i, (mi.get_meta(before) as Array)[0] as Material)
					mi.remove_meta(before)
				continue
			if not mi.has_meta(before):
				mi.set_meta(before, [mi.get_surface_override_material(i)])   # in an Array: a null would clear the meta
			var mat: ShaderMaterial = mats.get(outfit, null) as ShaderMaterial
			if mat == null:
				mat = material_for(src, outfit)
				mats[outfit] = mat
			mi.set_surface_override_material(i, mat)
			count += 1
	for m: Variant in mats.values():
		var sm: ShaderMaterial = m as ShaderMaterial
		sm.set_shader_parameter(&"show_zones", show_zones)
		if palette != null:
			palette.apply_to(sm)
		else:
			DyePalette.new().apply_to(sm)   # every alpha 0: the painting as it is
	if undress:
		model.remove_meta(MATS_META)
	else:
		model.set_meta(MATS_META, mats)
	return count


## DRESSED IN THE GAME (W1, before 300 players): every outfit surface under `model` in the palette `palette_of`
## gives its outfit (`func(outfit: String) -> DyePalette`; null leaves that outfit's surfaces as the foundation
## dressed them). The materials are SHARED: one per outfit and palette for every body in those colors (a palette's
## `share_key` meta, else the object itself), never re-tinted after it is made (the lab's `dress` re-tints its own).
## Returns how many surfaces wear the dye.
static func dress_shared(model: Node, palette_of: Callable) -> int:
	var count: int = 0
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			var outfit: String = outfit_of(src)
			if outfit.is_empty():
				continue
			var palette: DyePalette = palette_of.call(outfit) as DyePalette
			if palette == null:
				continue
			mi.set_surface_override_material(i, shared_material(src, outfit, palette))
			count += 1
	return count


## The one dye material for `outfit` (on `src`'s textures) in `palette`, made once and shared.
static func shared_material(src: StandardMaterial3D, outfit: String, palette: DyePalette) -> ShaderMaterial:
	# By the outfit's TEXTURE, not its material: every piece's glTF carries its own copy of the same material, and
	# both bodies paint from the one texture, so one material serves every piece of an outfit on every body.
	var tex: Texture2D = src.albedo_texture
	var key: String = "%s|%s|%s" % [outfit, tex.resource_path if tex != null and not tex.resource_path.is_empty() else str(src.get_instance_id()),
		String(palette.get_meta(&"share_key", str(palette.get_instance_id())))]
	var held: WeakRef = _shared.get(key, null) as WeakRef
	var mat: ShaderMaterial = held.get_ref() as ShaderMaterial if held != null else null
	if mat == null:
		mat = material_for(src, outfit)
		mat.set_shader_parameter(&"show_zones", false)
		palette.apply_to(mat)
		_shared[key] = weakref(mat)
		if _recent.size() < RECENT:
			_recent.resize(RECENT)
		_recent[_made % RECENT] = mat   # the newest few held a while: a body dressed twice as it spawns makes one
		_made += 1
		if _made % PRUNE_EVERY == 0:
			_prune()
	return mat


## How many shared dye materials are alive now (worn by some body): the tests', and the dye bench's count.
static func shared_count() -> int:
	_prune()
	return _shared.size()


## THE CACHE IS BOUNDED (W4, `game/regents/tests/dye_bench.tscn`): a material lives while a body wears it, or while
## it is among the `RECENT` newest; so players coming and going over a session never pile them up (before: 1297 kept
## after about 2000 bodies had come and gone; now at most `RECENT`). The keys of gone ones are swept now and then.
static func _prune() -> void:
	for k: String in _shared.keys():
		if (_shared[k] as WeakRef).get_ref() == null:
			_shared.erase(k)


## How many of the newest materials are held even when nobody wears them: a body dressed in its own colors and then
## covered by its armor as it spawns would otherwise make and free one each time (twice the spawn's cost, W4).
const RECENT: int = 256
## Every this many materials made, the gone ones' keys are swept.
const PRUNE_EVERY: int = 64
## key -> WeakRef of its ShaderMaterial.
static var _shared: Dictionary[String, WeakRef] = {}
static var _made: int = 0
static var _recent: Array[ShaderMaterial] = []


## A fresh dye material for one outfit, on the textures its imported material `src` uses.
static func material_for(src: StandardMaterial3D, outfit: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER) as Shader
	mat.set_shader_parameter(&"albedo_tex", src.albedo_texture)
	mat.set_shader_parameter(&"orm_tex", src.metallic_texture if src.metallic_texture != null else src.roughness_texture)
	mat.set_shader_parameter(&"normal_tex", src.normal_texture)
	mat.set_shader_parameter(&"zone_tex", load(zone_path(outfit)) as Texture2D)
	return mat


## WHAT A PIECE IS MADE OF: { dye slot: share of its vertices } (metal, main ... under), read from its outfit's zone
## mask at each vertex's UV. Vertices, not area: a fair guide to what a piece shows, not an exact one.
static func makeup(path: String) -> Dictionary:
	if _makeup.has(path):
		return _makeup[path]
	var out: Dictionary = {}
	if not ResourceLoader.exists(path):
		return out
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return out
	var root: Node = scene.instantiate()
	var counts: Dictionary[StringName, int] = {}
	var total: int = 0
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh == null:
			continue
		for s: int in range(mesh.get_surface_count()):
			var outfit: String = outfit_of(mesh.surface_get_material(s))
			if outfit.is_empty():
				continue
			var img: Image = zone_image(outfit)
			if img == null:
				continue
			var uvs: PackedVector2Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV] as PackedVector2Array
			for uv: Vector2 in uvs:
				var x: int = clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
				var y: int = clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
				var id: int = clampi(roundi(img.get_pixel(x, y).r8 / 40.0), 0, DYE_SLOTS.size() - 1)
				counts[DYE_SLOTS[id]] = counts.get(DYE_SLOTS[id], 0) + 1
				total += 1
	root.free()
	for k: StringName in counts:
		out[k] = float(counts[k]) / float(maxi(total, 1))
	_makeup[path] = out
	return out


## An outfit's zone mask as an Image (the imported texture's; else the PNG itself, which a headless run with no
## renderer needs). Null when it has none.
static func zone_image(outfit: String) -> Image:
	if not has_zones(outfit):
		return null
	var img: Image = (load(zone_path(outfit)) as Texture2D).get_image()
	if img == null or img.is_empty():
		img = Image.load_from_file(ProjectSettings.globalize_path(zone_path(outfit)))
	if img != null and img.is_compressed():
		img.decompress()
	return img


## Every `.tres` in a folder, loaded, by file name.
static func load_all(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var files: Array[String] = []
	for f: String in ResourceLoader.list_directory(dir):
		if f.ends_with(".tres"):
			files.append(f)
	files.sort()
	for f: String in files:
		var r: Resource = load(dir + f)
		if r != null:
			out.append(r)
	return out


## A `ModularCharacter` put together from a look: { body, pieces: {slot: path}, skin (0 light, 1 dark), skin_tint,
## hair: [paths], hair_color }. Not yet assembled (it assembles when instantiated or added to the tree).
static func figure(look: Dictionary) -> ModularCharacter:
	var body: StringName = look.get("body", &"male") as StringName
	var who: String = "Female" if body == &"female" else "Male"
	var mc := ModularCharacter.new()
	mc.head = load(HEADS % who) as PackedScene
	mc.body = body
	var parts: Array[PackedScene] = []
	var worn: Dictionary = look.get("pieces", {}) as Dictionary
	for slot: StringName in SLOTS:
		var path: String = String(worn.get(slot, ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			parts.append(load(path) as PackedScene)
	var hides: String = ""
	var head_piece: String = String(worn.get(&"head", "")).get_file().get_basename()
	for part: String in HIDES_HAIR:
		if head_piece.ends_with(part):
			hides = HIDES_HAIR[part]
	for h: Variant in look.get("hair", []) as Array:
		var file: String = String(h).get_file().get_basename()
		if file.begins_with("Hair_") and (hides == "all" or (hides == "hair" and not BEARDS.has(file))):
			continue
		if ResourceLoader.exists(String(h)):
			parts.append(load(String(h)) as PackedScene)
	mc.parts = parts
	mc.skin_texture = load(SKIN_TEX % [who, "Dark" if int(look.get("skin", 0)) == 1 else "Light"]) as Texture2D
	mc.skin_tint = look.get("skin_tint", Color.WHITE) as Color
	mc.hair_color = look.get("hair_color", Color(0.24, 0.16, 0.08)) as Color
	return mc
