extends "res://tests/suite_base.gd"
## A PLAYER'S BODY AND ITS OWN COLORS (`-- --only=regents_figure`; W1, Luke's W8, W2, W4), no server, no renderer:
##   - a color rides the `appearance` text as a number and comes back the same; the module would take the text
##   - an old text with no color keys is today's look (nothing dyed); a bad value is ignored, never a crash
##   - the colors are on the body after the first assembly AND after a reassembly (a new beard puts it together
##     again); NEGATIVE in the suite: the same body with its `assembled` handler cut loses them
##   - Peasant only: an old text's torso or colorway keys are read without them; the picker offers no clothes keys
##     but hair, beard, brows and skin
##   - bodies in the same colors share their materials; other colors get their own
##   - armor over it (W2's way in): a worn piece in its tier's palette, the empty slots in the player's own colors
##   - the adventurer offers only the genre's two Peasant looks
##   - THE PICKER (template 1.8.4): a color picked lands in the text as `main=<int>` and survives Done, the preview
##     dyed in it; NEGATIVE: on a look that does not offer the colors, the same pick is dropped at Done
## How it LOOKS: `"$GODOT" --path . res://game/regents/tests/figure_shot.tscn -- <out dir>` (windowed).

const MALE: String = "res://game/regents/looks/peasant_m.tscn"
const FEMALE: String = "res://game/regents/looks/peasant_f.tscn"
const KNIGHT_TORSO: String = "res://game/regents/art/outfits/knight/models/Male_Knight_Body_Armor.gltf"
const BLUE: Color = Color8(74, 106, 142)
const RED: Color = Color8(140, 40, 36)


func run() -> void:
	_run_text()
	await _run_dressed()
	await _run_reassembly()
	await _run_peasant_only()
	await _run_shared()
	await _run_armor()
	_run_adventurer()
	await _run_picker()


func _run_text() -> void:
	for c: Color in [BLUE, RED, Color.BLACK, Color.WHITE]:
		var back: Color = RegentsColors.decode(RegentsColors.encode(c))
		_check(back.to_html(false) == c.to_html(false) and back.a == 1.0, "a color as a number and back: %s" % c.to_html(false))
	var text: String = RegentsColors.with_colors("peasant_m;hair=3", {&"main": BLUE, &"trim": RED})
	_check(Appearance.look_name(text) == "peasant_m" and Appearance.choices(text).get("hair") == 3,
		"the look and the other choices are kept (%s)" % text)
	var got: Dictionary[StringName, Color] = RegentsColors.colors_in(text)
	_check(got.size() == 2 and (got[&"main"] as Color).to_html(false) == BLUE.to_html(false)
		and (got[&"trim"] as Color).to_html(false) == RED.to_html(false), "the colors come back from the text")
	_check(Appearance.is_valid(text) and text.length() < 120, "the module would take it (%d characters)" % text.length())
	var full: String = RegentsColors.with_colors("peasant_f", {&"main": BLUE, &"accent": RED, &"under": Color.BLACK,
		&"trim": Color.WHITE, &"leather": RED})
	_check(Appearance.is_valid(full) and RegentsColors.colors_in(full).size() == 5, "all five slots fit (%s)" % full)
	var off: String = RegentsColors.with_colors(text, {&"main": Color(1, 1, 1, 0)})
	_check(not RegentsColors.colors_in(off).has(&"main") and RegentsColors.colors_in(off).has(&"trim"), "a color taken off")
	for bad: String in ["peasant_m;main=abc", "peasant_m;main=-5", "peasant_m;main=999999999", "peasant_m;main=", "peasant_m;main"]:
		_check(RegentsColors.colors_in(bad).is_empty() and RegentsColors.palette_of(bad) == null, "a bad value is ignored: %s" % bad)
	_check(RegentsColors.palette_of("peasant_m;hair=2") == null, "an old text with no colors: no palette")
	_check(RegentsColors.palette_of(text) == RegentsColors.palette_of(RegentsColors.with_colors("peasant_f", {&"trim": RED, &"main": BLUE})),
		"the same colors are the same palette, whoever wears them")
	_check(not RegentsColors.swatches(&"main").is_empty(), "the picker's suggested swatches come from the starter palettes")


## A body from `path` with `text` on it, in the tree.
func _figure(path: String, text: String) -> RegentsFigure:
	var f: RegentsFigure = (load(path) as PackedScene).instantiate() as RegentsFigure
	f.apply_appearance(text)
	add_child(f)
	await get_tree().process_frame
	return f


## How many outfit surfaces wear a dye, and how many of those have `main` as their main color.
func _dyed(f: Node, main: Color) -> Vector2i:
	var n: int = 0
	var same: int = 0
	for m: Node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			if Wardrobe.outfit_of(mi.mesh.surface_get_material(i)).is_empty():
				continue
			var sm: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
			if sm == null:
				continue
			n += 1
			if (sm.get_shader_parameter(&"main_color") as Color).to_html(false) == main.to_html(false):
				same += 1
	return Vector2i(n, same)


func _outfit_surfaces(f: Node) -> int:
	var n: int = 0
	for m: Node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			n += 0 if Wardrobe.outfit_of(mi.mesh.surface_get_material(i)).is_empty() else 1
	return n


func _run_dressed() -> void:
	var old: RegentsFigure = await _figure(MALE, "peasant_m;hair=2")
	_check(old.colors == null and _dyed(old, BLUE).x == 0 and _outfit_surfaces(old) >= 4,
		"an old text: the Peasant as painted, nothing dyed (%d outfit surfaces)" % _outfit_surfaces(old))
	old.queue_free()
	var mine: RegentsFigure = await _figure(MALE, RegentsColors.with_colors("peasant_m", {&"main": BLUE}))
	var d: Vector2i = _dyed(mine, BLUE)
	_check(d.x == _outfit_surfaces(mine) and d.x >= 4 and d.y == d.x, "my colors: every Peasant surface dyed blue (%d of %d)" % [d.y, _outfit_surfaces(mine)])
	var bad: RegentsFigure = await _figure(FEMALE, "peasant_f;main=zz;accent=-1")
	_check(bad.colors == null and _dyed(bad, BLUE).x == 0, "bad values: the look as painted, no crash")
	mine.queue_free()
	bad.queue_free()


func _run_reassembly() -> void:
	var text: String = RegentsColors.with_colors("peasant_m", {&"main": RED})
	var kept: RegentsFigure = await _figure(MALE, text)
	var cut: RegentsFigure = await _figure(MALE, text)
	cut.assembled.disconnect(cut._on_assembled)   # the negative: no dressing on `assembled`
	var skel_before: Skeleton3D = kept.skeleton()
	# A new beard: the pieces change, so the body is put together again (a new skeleton, fresh meshes).
	kept.apply_appearance(text + ";beard=3")
	cut.apply_appearance(text + ";beard=3")
	await get_tree().process_frame
	_check(kept.skeleton() != skel_before, "a new beard puts the body together again")
	var dk: Vector2i = _dyed(kept, RED)
	_check(dk.x >= 4 and dk.y == dk.x and dk.x == _outfit_surfaces(kept), "the colors survive the reassembly (%d of %d)" % [dk.y, _outfit_surfaces(kept)])
	_check(_dyed(cut, RED).x == 0, "NEGATIVE: without the dressing on `assembled` they are lost (%d dyed)" % _dyed(cut, RED).x)
	# A color change alone re-dresses in place (no new pieces).
	kept.apply_appearance(RegentsColors.with_colors(text + ";beard=3", {&"main": BLUE}))
	await get_tree().process_frame
	_check(_dyed(kept, BLUE).y == _outfit_surfaces(kept), "a new color alone: dressed again in it")
	kept.queue_free()
	cut.queue_free()


func _run_peasant_only() -> void:
	var f: RegentsFigure = await _figure(MALE, "peasant_m;torso=2;torso_dye=2;legs=3;hair=2")
	var outfits: Array[String] = []
	for p: PackedScene in f.wearing():
		var o: String = CharacterLooks.outfit_of_file(p.resource_path)
		if not o.is_empty() and not outfits.has(o):
			outfits.append(o)
	_check(outfits == ["Peasant"], "an old text's clothes keys are read without them: Peasant only (%s)" % [outfits])
	_check(f.hair_color == (CharacterLooks.HAIRS[1]["color"] as Color), "and its other choices still apply (the hair color)")
	var keys: Array[String] = []
	for o: Dictionary in f.appearance_options():
		keys.append(String(o["key"]))
	for k: String in ["torso", "arms", "legs", "feet", "head", "shoulders", "neck", "torso_dye"]:
		_check(not keys.has(k), "the picker offers no '%s'" % k)
	for k: String in ["hairstyle", "beard", "skin", "hair"]:
		_check(keys.has(k), "the picker still offers '%s'" % k)
	# The free colors: offered only by a picker that shows a color option (template 1.8.4); declared either way.
	var has_colors: bool = RegentsFigure.picker_has_colors()
	_check(keys.has("main") == has_colors, "the color options shown only when the picker can show them (picker: %s)" % has_colors)
	var decl: Array[Dictionary] = RegentsFigure.color_options()
	_check(decl.size() == 5 and decl.all(func(o: Dictionary) -> bool: return bool(o["color"]) and not (o["swatches"] as Array).is_empty()),
		"five color options declared, each with its swatches")
	_check(RegentsFigure.without_clothes("peasant_m;arms=1;hair=4;main=12") == "peasant_m;hair=4;main=12", "without the clothes keys, the rest kept")
	f.queue_free()


func _run_shared() -> void:
	var a: RegentsFigure = await _figure(MALE, RegentsColors.with_colors("peasant_m", {&"main": BLUE, &"trim": RED}))
	var b: RegentsFigure = await _figure(FEMALE, RegentsColors.with_colors("peasant_f;skin=3", {&"trim": RED, &"main": BLUE}))
	var c: RegentsFigure = await _figure(MALE, RegentsColors.with_colors("peasant_m", {&"main": RED}))
	var before: int = Wardrobe.shared_count()
	var d: RegentsFigure = await _figure(MALE, RegentsColors.with_colors("peasant_m", {&"main": BLUE, &"trim": RED}))
	_check(Wardrobe.shared_count() == before, "a fourth body in colors already worn makes no new material")
	_check(_mat(a) != null and _mat(a) == _mat(b) and _mat(a) == _mat(d), "bodies in the same colors share their material")
	_check(_mat(c) != null and _mat(c) != _mat(a), "other colors, their own")
	for f: Node in [a, b, c, d]:
		f.queue_free()


## The first dye material on a body.
func _mat(f: Node) -> ShaderMaterial:
	for m: Node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var sm: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
			if sm != null:
				return sm
	return null


func _run_armor() -> void:
	var f: RegentsFigure = await _figure(MALE, RegentsColors.with_colors("peasant_m", {&"main": BLUE}))
	var tier: DyePalette = load("res://game/regents/wardrobe/palettes/knight_1.tres") as DyePalette
	var torso: PackedScene = load(KNIGHT_TORSO) as PackedScene
	f.wear_armor({&"torso": torso}, {"Knight": tier})
	await get_tree().process_frame
	var knight: int = 0
	var peasant: int = 0
	var right: int = 0
	for m: Node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var o: String = Wardrobe.outfit_of(mi.mesh.surface_get_material(i))
			var sm: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
			if o.is_empty() or sm == null:
				continue
			var main: Color = sm.get_shader_parameter(&"main_color") as Color
			if o == "Knight":
				knight += 1
				right += 1 if main.to_html() == tier.main.to_html() else 0
			elif o == "Peasant":
				peasant += 1
				right += 1 if main.to_html(false) == BLUE.to_html(false) else 0
	_check(knight >= 1 and peasant >= 2, "armor over the Peasant: the Knight's torso and the Peasant's other pieces (%d, %d)" % [knight, peasant])
	_check(right == knight + peasant, "the armor in its tier's palette, the empty slots in my colors (%d of %d)" % [right, knight + peasant])
	f.wear_armor({})
	await get_tree().process_frame
	_check(_dyed(f, BLUE).y == _outfit_surfaces(f), "armor off: all Peasant in my colors again")
	f.queue_free()


func _run_adventurer() -> void:
	var def: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	_check(def.variant_names() == PackedStringArray(["peasant_m", "peasant_f"]), "the adventurer offers the two Peasant looks (%s)" % [def.variant_names()])
	for v: PackedScene in def.visual_variants:
		var n: Node = v.instantiate()
		_check(n is RegentsFigure, "%s is a RegentsFigure" % v.resource_path.get_file())
		n.free()
	_check(def.look_worn(7, "ranger_f;torso=2") in ["peasant_m", "peasant_f"], "an old Ranger look falls back to a Peasant")


## A picker on `def`, opened on `text`; `main` picked as BLUE; then Done. The text Done hands on.
func _pick_and_done(def: EntityDefinition, text: String) -> Array:
	var picker := CharacterPicker.new()
	picker.definition = def
	picker.appearance = text
	add_child(picker)
	picker.open()
	await get_tree().process_frame
	picker.pick_color("main", BLUE)
	await get_tree().process_frame
	var preview: RegentsFigure = picker.preview_model() as RegentsFigure
	var dyed_blue: bool = preview != null and _dyed(preview, BLUE).y == _outfit_surfaces(preview) and _outfit_surfaces(preview) > 0
	var got: Array[String] = []
	picker.chosen.connect(func(t: String) -> void: got.append(t))
	var done: Button = picker.find_child("Done", true, false) as Button
	if done != null:
		done.pressed.emit()
	await get_tree().process_frame
	picker.queue_free()
	return [got[0] if not got.is_empty() else "", dyed_blue]


func _run_picker() -> void:
	_check(RegentsFigure.picker_has_colors(), "the foundation's picker shows color options (template 1.8.4)")
	var def: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	var r: Array = await _pick_and_done(def, "peasant_f;hair=6;trim=%d" % RegentsColors.encode(RED))
	var text: String = String(r[0])
	_check(Appearance.choices(text).get("main") == RegentsColors.encode(BLUE), "a picked color lands in the text as main=<int> (%s)" % text)
	_check((RegentsColors.colors_in(text).get(&"main", Color()) as Color).to_html(false) == BLUE.to_html(false)
		and RegentsColors.colors_in(text).has(&"trim") and Appearance.choices(text).get("hair") == 6,
		"and survives Done, with the color it opened on and the other choices")
	_check(bool(r[1]), "the preview wears it as it is picked")
	_check(Appearance.is_valid(text), "the module would take what Done hands on")
	# NEGATIVE: the same pick on a look that does not offer the colors (the foundation's own Peasant) is dropped.
	var plain := EntityDefinition.new()
	plain.visual_variants = [load("res://game/characters/looks/peasant_m.tscn") as PackedScene, load("res://game/characters/looks/peasant_f.tscn") as PackedScene]
	var n: Array = await _pick_and_done(plain, "peasant_f;hair=6")
	_check(not Appearance.choices(String(n[0])).has("main"), "NEGATIVE: on a look with no color options the pick is dropped at Done (%s)" % n[0])
