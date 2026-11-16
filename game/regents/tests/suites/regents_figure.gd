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
##   - WORN ARMOR (W2): the table `armor_looks.tres` covers every armor piece with files that exist and a palette; a
##     `worn` row dresses its wearer (the pieces, the material's palette), a slot back to 0 or the row gone gives the
##     Peasant piece back, another player's row dresses their body only, a reassembly keeps it, steel's pauldrons are
##     spiked (iron's round), a closed helm hides hair and beard and a hood the hair, the practice piece draws nothing
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
	_run_armor_table()
	_run_worn()


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
	# W4: the cache is BOUNDED. A body in colors nobody else wears makes its material; gone, its material is still held
	# while it is among the `Wardrobe.RECENT` newest (no churn as bodies spawn), and dropped once that many newer ones
	# were made: players coming and going never pile materials up.
	await get_tree().process_frame
	var lone: RegentsFigure = await _figure(MALE, RegentsColors.with_colors("peasant_m", {&"main": Color8(1, 2, 3), &"trim": Color8(4, 5, 6)}))
	var held: WeakRef = weakref(_mat(lone))
	var src: StandardMaterial3D = null
	for m: Node in lone.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			if Wardrobe.outfit_of(mi.mesh.surface_get_material(i)) == "Peasant":
				src = mi.mesh.surface_get_material(i) as StandardMaterial3D
	lone.free()
	_check(held.get_ref() != null and src != null, "its body gone, its material is held a while (among the newest)")
	for i: int in Wardrobe.RECENT:
		var p: DyePalette = RegentsColors.palette_of(RegentsColors.with_colors("peasant_m", {&"main": Color8(i >> 8, i & 255, 77)}))
		Wardrobe.shared_material(src, "Peasant", p)
	_check(held.get_ref() == null, "and dropped once %d newer ones were made: the cache is bounded" % Wardrobe.RECENT)
	_check(Wardrobe.shared_count() <= Wardrobe.RECENT + 8, "materials alive stay near the bound (%d)" % Wardrobe.shared_count())


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


const ITEMS: String = "res://game/regents/content/item/"


func _item(file: String) -> int:
	return (load(ITEMS + file + ".tres") as ItemDef).id


## Every armor piece in the content: its pattern has a row, for both bodies every file is a piece, and its material a
## palette (metal ones with their bar's finish).
func _run_armor_table() -> void:
	var looks: ArmorLooks = ArmorLooks.current()
	_check(looks != null and not looks.entries.is_empty(), "the armor table loads")
	var pieces: int = 0
	for f: String in ResourceLoader.list_directory(ITEMS):
		if not f.ends_with(".tres"):
			continue
		var it: ItemDef = load(ITEMS + f) as ItemDef
		if it == null or it.armor_slot.is_empty() or it.material == null or it.pattern == null:
			continue
		pieces += 1
		var e: ArmorLookEntry = looks.entry_for(it.pattern.key, it.material.key)
		_check(e != null, "%s: its pattern '%s' has a look" % [f, it.pattern.key])
		if e == null:
			continue
		for body: StringName in [&"male", &"female"]:
			var want: Dictionary[StringName, String] = e.pieces_for(body)
			_check(not want.is_empty(), "%s on a %s: puts something on" % [f, body])
			for slot: StringName in want:
				_check(want[slot].is_empty() or not ArmorLooks.piece_path(want[slot]).is_empty(), "%s, %s, %s: the piece %s exists" % [f, body, slot, want[slot]])
		var pal: DyePalette = looks.palettes.get(it.material.key, null) as DyePalette
		_check(pal != null and (it.material.family != MaterialDef.Family.METAL or pal.metal != null), "%s: its material '%s' has a palette" % [f, it.material.key])
	_check(pieces >= 17, "every armor piece the table made is covered (%d)" % pieces)
	var steel: Dictionary = looks.dress_for([_item("steel_cuirass")] as Array[int], &"male")[0]
	var iron: Dictionary = looks.dress_for([_item("iron_cuirass")] as Array[int], &"female")[0]
	_check(String((steel[&"shoulders"] as PackedScene).resource_path).contains("Spike"), "steel wears the spiked pauldrons (W3)")
	_check(String((iron[&"shoulders"] as PackedScene).resource_path).contains("Round"), "NEGATIVE: iron's are round")
	var armet: Dictionary = looks.dress_for([_item("copper_armet")] as Array[int], &"male")[0]
	var hood: Dictionary = looks.dress_for([_item("soft_leather_hood")] as Array[int], &"male")[0]
	_check(armet.has(&"hairstyle") and armet[&"hairstyle"] == null and armet.has(&"beard") and armet[&"beard"] == null, "a closed helm takes off the hair and beard")
	_check(hood.has(&"hairstyle") and hood[&"hairstyle"] == null and not hood.has(&"beard"), "a hood the hair only")
	var practice: Array = looks.dress_for([40067, 40068] as Array[int], &"male")
	_check((practice[0] as Dictionary).is_empty() and (practice[1] as Dictionary).is_empty(), "the practice pieces (no material) put on nothing")


class WornRow extends RefCounted:
	var entity_id: int = 0
	var head_item: int = 0
	var chest_item: int = 0
	var legs_item: int = 0
	var trinket_item: int = 0
	var head_row: int = 0
	var chest_row: int = 0
	var legs_row: int = 0
	var trinket_row: int = 0


func _worn(head: int, chest: int, legs: int) -> WornRow:
	var r := WornRow.new()
	r.head_item = head
	r.chest_item = chest
	r.legs_item = legs
	return r


## A player as the game spawns one, out of the tree: an entity whose `Visual/Model` is a figure in `text`, with
## an `ArmorLookComponent` bound to it.
func _wearer(id: int, text: String) -> ArmorLookComponent:
	var ent := SpaceTimeEntity.new()
	ent.entity_id = id
	var visual := Node3D.new()
	visual.name = "Visual"
	ent.add_child(visual)
	var fig: RegentsFigure = (load(MALE) as PackedScene).instantiate() as RegentsFigure
	fig.name = "Model"
	fig.apply_appearance(text)
	visual.add_child(fig)
	var c := ArmorLookComponent.new()
	ent.add_child(c)
	c.bind(ent, {})
	return c


## The outfits a figure wears (Knight, Peasant, Ranger, Wizard), sorted.
func _outfits(f: RegentsFigure) -> Array[String]:
	var out: Array[String] = []
	for p: PackedScene in f.wearing():
		var o: String = ArmorLooks.outfit_of(p.resource_path.get_file().get_basename())
		if ["Knight", "Peasant", "Ranger", "Wizard"].has(o) and not out.has(o):
			out.append(o)
	out.sort()
	return out


func _surface_param(f: Node, outfit: String, param: StringName) -> Variant:
	for m: Node in f.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			if Wardrobe.outfit_of(mi.mesh.surface_get_material(i)) != outfit:
				continue
			var sm: ShaderMaterial = mi.get_surface_override_material(i) as ShaderMaterial
			return sm.get_shader_parameter(param) if sm != null else null
	return null


func _wears(f: RegentsFigure, part: String) -> bool:
	for p: PackedScene in f.wearing():
		if p.resource_path.contains(part):
			return true
	return false


func _run_worn() -> void:
	var me: ArmorLookComponent = _wearer(9001, RegentsColors.with_colors("peasant_m;hair=2", {&"main": BLUE}))
	var them: ArmorLookComponent = _wearer(9002, RegentsColors.with_colors("peasant_m", {&"main": RED}))
	_check(me.required_tables() == [&"worn"] and me.optional_tables() == [&"worn"], "the look reads `worn` (optional: no row, no armor)")
	var fm: RegentsFigure = me.figure()
	var ft: RegentsFigure = them.figure()
	_check(_outfits(fm) == ["Peasant"], "no row: the Peasant (%s)" % [_outfits(fm)])
	var iron: MetalFinish = load("res://game/regents/wardrobe/metals/2_iron.tres") as MetalFinish
	me._on_row_updated(&"worn", null, _worn(0, _item("iron_cuirass"), 0))
	_check(_outfits(fm) == ["Knight", "Peasant"], "an iron cuirass worn: the Knight chest over the Peasant (%s)" % [_outfits(fm)])
	var metal: Variant = _surface_param(fm, "Knight", &"metal_color")
	_check(metal is Color and (metal as Color).is_equal_approx(iron.color), "in the iron finish (%s)" % [metal])
	_check(_dyed(fm, BLUE).y >= 1, "the Peasant pieces left (legs, feet) in my colors")
	_check(_outfits(ft) == ["Peasant"] and _dyed(ft, RED).y == _outfit_surfaces(ft), "another player: untouched by my row")
	them._on_row_updated(&"worn", null, _worn(_item("supple_leather_hood"), _item("supple_leather_jerkin"), _item("supple_leather_trousers")))
	_check(_outfits(ft) == ["Ranger"], "their own row: the Ranger leather, all of it (%s)" % [_outfits(ft)])
	var wolf: DyePalette = load("res://game/regents/wardrobe/palettes/leather_2_supple.tres") as DyePalette
	var main_t: Variant = _surface_param(ft, "Ranger", &"main_color")
	_check(main_t is Color and (main_t as Color).is_equal_approx(wolf.main), "in the supple leather palette (the wolf)")
	_check(_outfits(fm) == ["Knight", "Peasant"], "and mine as it was")
	# A reassembly (a new beard) keeps the armor and its palette.
	fm.apply_appearance(RegentsColors.with_colors("peasant_m;hair=2;beard=3", {&"main": BLUE}))
	var metal2: Variant = _surface_param(fm, "Knight", &"metal_color")
	_check(_outfits(fm) == ["Knight", "Peasant"] and metal2 is Color and (metal2 as Color).is_equal_approx(iron.color), "a reassembly keeps the armor in its finish")
	# A slot back to 0, then the row gone: the Peasant piece back.
	me._on_row_updated(&"worn", null, _worn(_item("steel_armet"), 0, _item("steel_legplates")))
	_check(_outfits(fm) == ["Knight", "Peasant"] and not _wears(fm, "Knight_Body_Armor") and _wears(fm, "Peasant_Body"), "the chest back to 0: the Peasant shirt again")
	_check(not _wears(fm, "Hair_"), "a closed helm: no hair")
	me._on_row_updated(&"worn", _worn(0, 0, 0), null)
	_check(_outfits(fm) == ["Peasant"] and _wears(fm, "Hair_") and _dyed(fm, BLUE).y == _outfit_surfaces(fm), "the row gone: all Peasant in my colors, the hair back")
	# The practice piece: nothing drawn, nothing broken.
	me._on_row_updated(&"worn", null, _worn(40068, 40067, 0))
	_check(_outfits(fm) == ["Peasant"], "the practice pieces draw nothing")
	# A new model (a look chosen again) is dressed as it comes.
	me._on_row_updated(&"worn", null, _worn(0, _item("linen_robe"), 0))
	var visual: Node = fm.get_parent()
	visual.remove_child(fm)
	fm.free()
	var fresh: RegentsFigure = (load(MALE) as PackedScene).instantiate() as RegentsFigure
	fresh.name = "Model"
	visual.add_child(fresh)
	me._process(0.0)
	_check(_outfits(fresh) == ["Peasant", "Wizard"], "a new model is dressed again (%s)" % [_outfits(fresh)])
	for c: ArmorLookComponent in [me, them]:
		(c.entity as Node).free()
