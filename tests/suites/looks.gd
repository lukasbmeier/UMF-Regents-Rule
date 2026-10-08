extends "res://tests/suite_base.gd"
## The `looks` suite (tests/test_runner.gd runs it; `-- --only=looks` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_look_tests()



## A CHOSEN LOOK (DECISIONS #166): the text, the variant it names, the colours a look takes, an
## entity built in it, an entity rebuilt when it changes (not while it is busy), and the picker.
class FakeAppearanceRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var look: String
	func _init(eid: int, text: String) -> void:
		entity_id = eid
		look = text


## The SDK's cache, as far as a respawn reads it: rows by primary key, rows by predicate.
class FakeLookCache extends RefCounted:
	var tables: Dictionary = {}
	func put(table: StringName, pk: Variant, row: RefCounted) -> void:
		if not tables.has(table):
			tables[table] = {}
		tables[table][pk] = row
	func get_row_by_pk(table: StringName, pk: Variant) -> RefCounted:
		return (tables.get(table, {}) as Dictionary).get(pk)
	func find_where(table: StringName, pred: Callable) -> Array:
		var out: Array = []
		for r: Variant in (tables.get(table, {}) as Dictionary).values():
			if pred.call(r):
				out.append(r)
		return out


class FakeLookSdk extends Node:
	var cache: FakeLookCache = FakeLookCache.new()
	func get_local_database() -> Object:
		return cache


class FakeBusyComponent extends SpaceTimeComponent:
	var busy: bool = true
	func required_tables() -> Array[StringName]:
		return []
	func _on_row_updated(_t: StringName, _o: RefCounted, _n: RefCounted) -> void:
		pass
	func blocks_respawn() -> bool:
		return busy


func _run_look_tests() -> void:
	print("== a chosen look ==")
	# --- the text ----------------------------------------------------------------------------
	_check(Appearance.look_name("ranger_f;skin=4;hair=2") == "ranger_f" and Appearance.look_name("") == "",
		"the look's name is the text before the first ;")
	_check(Appearance.choices("ranger_f;skin=4;hair=x;=3;outfit=2") == {"skin": 4, "outfit": 2},
		"the choices are key=number; anything else is skipped")
	_check(Appearance.make("noble_m", {"skin": 2, "hair": 0, "outfit": 1}) == "noble_m;outfit=1;skin=2",
		"made with its keys in order and the look's own choices (0) left out")
	_check(Appearance.is_valid("ranger_f;skin=4") and not Appearance.is_valid("Ranger F")
		and not Appearance.is_valid("x".repeat(Appearance.MAX_LENGTH + 1)),
		"only what the module takes is valid (lowercase, digits, _;=,.-, at most %d)" % Appearance.MAX_LENGTH)

	# --- the variant it names ------------------------------------------------------------------
	var fisher: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	_check(fisher.variant_names().size() == fisher.visual_variants.size() and fisher.variant_names().has("wizard_f"),
		"the angler's looks by name (%s)" % ", ".join(fisher.variant_names()))
	_check(fisher.visual_for(3, "wizard_f;hair=2").resource_path.ends_with("/wizard_f.tscn"),
		"an appearance names the look worn")
	_check(fisher.visual_for(3, "no_such_look") == fisher.visual_for(3) and fisher.visual_for(3, "") == fisher.visual_for(3),
		"a name that is not a look, or none, is the look picked from the id")

	# --- the colours a look takes --------------------------------------------------------------
	var peasant: ModularCharacter = (load("res://game/characters/looks/peasant_f.tscn") as PackedScene).instantiate() as ModularCharacter
	var keys: Array[String] = []
	for o: Dictionary in peasant.appearance_options():
		keys.append(String(o["key"]))
	_check(keys == ["torso", "torso_dye", "arms", "arms_dye", "legs", "legs_dye", "feet", "feet_dye", "head",
		"shoulders", "neck", "hairstyle", "skin", "hair"],
		"a woman's look offers every slot made for her body and its colours, her skin and hair colour (%s)" % str(keys))
	var hair_before: Color = _dressed_color(peasant, "MI_Hair")
	peasant.apply_appearance("peasant_f;hair=10;torso_dye=1;skin=5")
	_check(_dressed_color(peasant, "MI_Hair").is_equal_approx(CharacterLooks.HAIRS[9]["color"])
		and not hair_before.is_equal_approx(CharacterLooks.HAIRS[9]["color"]),
		"the hair is dressed in the colour chosen (%s, was %s)" % [_dressed_color(peasant, "MI_Hair"), hair_before])
	var skin: StandardMaterial3D = _dressed(peasant, "MI_Regular_")
	_check(skin != null and skin.albedo_texture != null and skin.albedo_texture.resource_path.ends_with("T_Regular_Female_Dark_BaseColor.png")
		and skin.albedo_color.is_equal_approx(CharacterLooks.SKINS[4]["tint"]),
		"the skin is her body's dark texture, in the tone chosen")
	var torso_mat: StandardMaterial3D = _piece_material(peasant, "Female_Peasant_Body", "MI_Peasant")
	var arms_mat: StandardMaterial3D = _piece_material(peasant, "Female_Peasant_Arms", "MI_Peasant")
	_check(torso_mat != null and torso_mat.albedo_texture.resource_path.ends_with("T_Peasant_BaseColor.png"),
		"her torso wears the colourway chosen for it")
	_check(arms_mat != null and arms_mat.albedo_texture.resource_path.ends_with("T_Peasant_2_BaseColor.png"),
		"and her arms, with none chosen, the look's own (%s)" % (arms_mat.albedo_texture.resource_path.get_file() if arms_mat != null else "none"))
	peasant.apply_appearance("peasant_f;hair=99;skin=-2")
	_check(_dressed_color(peasant, "MI_Hair").is_equal_approx(CharacterLooks.HAIRS[9]["color"]),
		"a choice out of range changes nothing")
	peasant.free()
	await _run_piece_tests()

	# --- an entity built in it, and rebuilt when it changes -------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(GREYBOX_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	var prev_sdk: Node = SpaceTimeSync._sdk
	var prev_cfg: NetConfig = SpaceTimeSync.config
	spawner.register_definition(fisher)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	var eid: int = 5401
	reg.local_entity_id = -1   # someone else: no camera, no input
	var fake := FakeLookSdk.new()
	add_child(fake)
	SpaceTimeSync._sdk = fake
	SpaceTimeSync.config = (load(FISHING_NET_CONFIG) as NetConfig).duplicate() as NetConfig
	Genres.merge_tables(SpaceTimeSync.config, Genres.modules())
	var entity_row := FakeEntityRow.new(eid, 0)
	fake.cache.put(&"entity", eid, entity_row)
	for ev: RowEvent in _player_rows(eid):
		fake.cache.put(ev.table, int(ev.current().get(&"entity_id") if ev.current().get(&"entity_id") != null else ev.current().get(&"id")), ev.current())
	var first := FakeAppearanceRow.new(eid, "wizard_f;hair=10")
	fake.cache.put(&"appearance", eid, first)
	_buffer_player_rows(reg, eid)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"appearance", null, first))
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, entity_row))
	for i: int in range(3):
		await get_tree().process_frame
	var me: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	var model: Node = me.get_node_or_null(^"Visual/Model") if me != null else null
	_check(model != null and model.scene_file_path.ends_with("/wizard_f.tscn") and me.appearance == "wizard_f;hair=10",
		"an entity whose row names a look is built wearing it (%s)" % (model.scene_file_path if model != null else "no model"))
	_check(model is ModularCharacter and _dressed_color(model as ModularCharacter, "MI_Hair").is_equal_approx(CharacterLooks.HAIRS[9]["color"]),
		"with the colours it names")
	# A change while a component is busy waits; once it is not, the entity is built again.
	var busy := FakeBusyComponent.new()
	me.add_runtime_component(busy)
	var second := FakeAppearanceRow.new(eid, "noble_m")
	fake.cache.put(&"appearance", eid, second)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, &"appearance", first, second))
	await get_tree().create_timer(0.8).timeout
	_check(spawner.get_entity_node(eid) == me, "a new look waits while the entity is in the middle of something")
	busy.busy = false
	await get_tree().create_timer(0.8).timeout
	var again: SpaceTimeEntity = spawner.get_entity_node(eid) as SpaceTimeEntity
	var new_model: Node = again.get_node_or_null(^"Visual/Model") if again != null else null
	_check(again != null and again != me and again.is_bound() and new_model != null
		and new_model.scene_file_path.ends_with("/noble_m.tscn") and again.appearance == "noble_m",
		"then it is built again, bound, in the new look (%s)" % (new_model.scene_file_path if new_model != null else "none"))
	_check(not is_instance_valid(me) or me.is_queued_for_deletion() or not me.is_inside_tree(), "and the old node is gone")
	var mv: SpaceTimeMovementComponent = again.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent if again != null else null
	_check(mv != null and mv.is_bound(), "its components bound again, from the cache's rows")
	spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", entity_row, null))
	spawner._flush_despawns()
	await get_tree().process_frame
	SpaceTimeSync._sdk = prev_sdk
	SpaceTimeSync.config = prev_cfg
	fake.queue_free()
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()

	# --- the picker ------------------------------------------------------------------------------
	var picker := CharacterPicker.new()
	picker.definition = fisher
	picker.appearance = "ranger_m;hair=3"
	get_tree().root.add_child(picker)
	picker.open()
	await get_tree().process_frame
	var name_label: Label = picker.find_child("LookName", true, false) as Label
	_check(picker.is_open() and picker.preview_model() != null
		and picker.preview_model().scene_file_path.ends_with("/ranger_m.tscn") and name_label.text == "Ranger M",
		"the picker opens on the look already chosen, turning in its preview (%s)" % name_label.text)
	var hair_pick: OptionButton = picker.find_child("hair", true, false) as OptionButton
	_check(hair_pick != null and hair_pick.selected == 3 and hair_pick.item_count == CharacterLooks.HAIRS.size() + 1,
		"its choices are the look's own, starting where they were")
	var before: String = picker.current()
	(picker.find_child("Next", true, false) as Button).pressed.emit()
	_check(picker.current().begins_with(fisher.variant_names()[(fisher.variant_names().find("ranger_m") + 1) % fisher.variant_names().size()])
		and picker.current() != before, "> steps to the next look (%s)" % picker.current())
	hair_pick = picker.find_child("hair", true, false) as OptionButton
	hair_pick.select(5)
	hair_pick.item_selected.emit(5)
	_check(picker.current().contains("hair=5"), "a choice is part of the look (%s)" % picker.current())
	var got: Array[String] = []
	picker.chosen.connect(func(t: String) -> void: got.append(t))
	var want: String = picker.current()
	(picker.find_child("Done", true, false) as Button).pressed.emit()
	_check(got == [want] and not picker.is_open() and Appearance.is_valid(want),
		"Done hands on the look as text the module takes (%s)" % str(got))
	picker.queue_free()


## The material a look's meshes are dressed in for source materials named `prefix`*.
func _dressed(look: ModularCharacter, prefix: String) -> StandardMaterial3D:
	for n: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(i)
			if src != null and src.resource_name.begins_with(prefix):
				var worn: Material = mi.get_surface_override_material(i)
				return (worn if worn != null else src) as StandardMaterial3D
	return null


## The material a piece's surface is drawn with (the override, else its own), by the piece's file.
func _piece_material(look: ModularCharacter, piece: String, prefix: String) -> StandardMaterial3D:
	for n: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi.mesh == null or String(mi.get_meta(ModularCharacter.PIECE_META, "")).get_file().get_basename() != piece:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var src: Material = mi.mesh.surface_get_material(i)
			if src != null and src.resource_name.begins_with(prefix):
				var worn: Material = mi.get_surface_override_material(i)
				return (worn if worn != null else src) as StandardMaterial3D
	return null


## The pieces a character is drawn wearing, by file name, sorted.
func _pieces_worn(look: ModularCharacter) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: Node in look.find_children("*", "MeshInstance3D", true, false):
		var piece: String = String(n.get_meta(ModularCharacter.PIECE_META, "")).get_file().get_basename()
		if not piece.is_empty() and not out.has(piece):
			out.append(piece)
	out.sort()
	return out


## EVERY PIECE, SLOT BY SLOT (DECISIONS #178): any piece made for a body can be worn on any look of
## that body, alone in its slot, on the one skeleton, bound where it expects the bones; a colourway
## dresses only its own outfit; every choice at once still fits on the row; and the picker shows a
## slot's colours beside it and asks again after each choice.
func _run_piece_tests() -> void:
	print("== a chosen look: every piece ==")
	var looks: Dictionary[String, PackedScene] = {
		"female": load("res://game/characters/looks/peasant_f.tscn") as PackedScene,
		"male": load("res://game/characters/looks/peasant_m.tscn") as PackedScene,
	}
	var tried: int = 0
	var wrong: Array[String] = []
	var longest: Dictionary = {}
	for body: String in looks:
		for slot: Dictionary in CharacterLooks.SLOTS:
			var list: Array = CharacterLooks.slot_list(slot, StringName(body))
			var key: String = String(slot["key"])
			if list.size() >= 2:
				longest[key] = maxi(int(longest.get(key, 0)), list.size())
			for i: int in range(list.size()):
				var look: ModularCharacter = looks[body].instantiate() as ModularCharacter
				look.apply_appearance("x;%s=%d" % [key, i + 1])
				tried += 1
				var want: PackedStringArray = String(list[i][1]).split("+", false)
				var in_slot: PackedStringArray = PackedStringArray()
				for piece: String in _pieces_worn(look):
					if CharacterLooks.slot_of(piece) == key:
						in_slot.append(piece)
				want.sort()
				var skel: Skeleton3D = look.skeleton()
				var skels: int = look.find_children("*", "Skeleton3D", true, false).size()
				var bad: String = ""
				if in_slot != want:
					bad = "wears %s" % str(in_slot)
				elif skel == null or skels != 1:
					bad = "%d skeletons" % skels
				else:
					for n: Node in look.find_children("*", "MeshInstance3D", true, false):
						var mi: MeshInstance3D = n as MeshInstance3D
						if mi.get_parent() != skel or mi.skin == null:
							continue
						for b: int in range(mi.skin.get_bind_count()):
							var bone: int = skel.find_bone(mi.skin.get_bind_name(b))
							if bone < 0 or mi.skin.get_bind_pose(b).affine_inverse().origin.distance_to(
									skel.get_bone_global_rest(bone).origin) > 0.005:
								bad = "%s is not bound to this body at %s" % [mi.name, mi.skin.get_bind_name(b)]
								break
				if not bad.is_empty():
					wrong.append("%s %s=%s: %s" % [body, key, list[i][0], bad])
				get_tree().root.add_child(look)
				look.queue_free()
	_check(tried >= 60 and wrong.is_empty(),
		"each of %d pieces, worn on its body's look, is alone in its slot on the one skeleton, bound to that body (%s)"
			% [tried, str(wrong)])
	await get_tree().process_frame

	# Swapped, the piece's own colours, and a colourway that is not its outfit's never reaches it.
	var p: ModularCharacter = looks["female"].instantiate() as ModularCharacter
	get_tree().root.add_child(p)
	var skel_before: Skeleton3D = p.skeleton()
	p.apply_appearance("peasant_f;torso=3")
	_check(_pieces_worn(p).has("Female_Noble_Body") and not _pieces_worn(p).has("Female_Peasant_Body")
		and _pieces_worn(p).has("Female_Peasant_Arms"),
		"a noble torso on a peasant: the torso swapped, the rest hers (%s)" % ", ".join(_pieces_worn(p)))
	_check(p.skeleton() != null and p.skeleton() != skel_before and p.find_children("*", "Skeleton3D", true, false).size() == 1,
		"put together again on one new skeleton")
	var noble: StandardMaterial3D = _piece_material(p, "Female_Noble_Body", "MI_Noble")
	_check(noble != null and noble.albedo_texture.resource_path.ends_with("T_Noble_BaseColor.png"),
		"the noble torso keeps the noble colours, not the look's peasant colourway (%s)"
			% (noble.albedo_texture.resource_path.get_file() if noble != null else "none"))
	var dye_choices: int = 0
	for o: Dictionary in p.appearance_options():
		if String(o["key"]) == "torso_dye":
			dye_choices = (o["choices"] as PackedStringArray).size()
	_check(dye_choices == CharacterLooks.colourways("Noble").size() + 1,
		"its colours are the noble torso's (%d choices)" % dye_choices)
	p.apply_appearance("peasant_f;torso=3;torso_dye=2")
	noble = _piece_material(p, "Female_Noble_Body", "MI_Noble")
	_check(noble != null and noble.albedo_texture.resource_path.ends_with("T_Noble_2_BaseColor.png"),
		"and dyed, it wears the noble colourway chosen")
	p.apply_appearance("peasant_f")
	_check(_pieces_worn(p).has("Female_Peasant_Body") and not _pieces_worn(p).has("Female_Noble_Body"),
		"with the choice gone, she wears her own torso again")
	p.queue_free()
	var r: ModularCharacter = (load("res://game/characters/looks/rival.tscn") as PackedScene).instantiate() as ModularCharacter
	get_tree().root.add_child(r)
	r.apply_appearance("rival;beard=1;brows=1")
	var brows: Array[String] = []
	for n: Node in r.find_children("Eyebrows*", "MeshInstance3D", true, false):
		brows.append(String(n.name))
	_check(not _pieces_worn(r).has("Hair_Moustache") and not _pieces_worn(r).has("Hair_MuttonChops"),
		"no beard takes off every beard piece a look wears (his moustache and his chops)")
	_check(brows == ["Eyebrows_Regular"], "one pair of eyebrows, the ones chosen (%s)" % str(brows))
	r.queue_free()

	# Every choice at once is text the module takes.
	var all: Dictionary = {"skin": CharacterLooks.SKINS.size(), "hair": CharacterLooks.HAIRS.size()}
	for k: Variant in longest:
		all[k] = longest[k]
		all[String(k) + CharacterLooks.DYE] = 3
	var everything: String = Appearance.make("wizard_f", all)
	_check(Appearance.is_valid(everything),
		"every choice at once fits what the module takes (%d of %d characters)" % [everything.length(), Appearance.MAX_LENGTH])

	# The picker: a slot's colours beside it, asked again after a choice, a stale one dropped.
	var picker := CharacterPicker.new()
	picker.definition = load(FISHER_DEF) as EntityDefinition
	picker.appearance = "peasant_f;torso_dye=3"
	add_child(picker)
	picker.open()
	var torso_row: Node = picker.find_child("Row_torso", true, false)
	_check(torso_row != null and torso_row.get_node_or_null(^"torso") != null and torso_row.get_node_or_null(^"torso_dye") != null,
		"the torso's colours sit in the torso's row")
	var dye: OptionButton = picker.find_child("torso_dye", true, false) as OptionButton
	_check(dye != null and dye.item_count == CharacterLooks.colourways("Peasant").size() + 1 and dye.selected == 3,
		"a peasant torso offers the peasant's colourways, the third chosen")
	(picker.find_child("torso", true, false) as OptionButton).item_selected.emit(3)
	dye = picker.find_child("torso_dye", true, false) as OptionButton
	_check(dye != null and dye.item_count == CharacterLooks.colourways("Noble").size() + 1,
		"a noble torso picked, its colours are asked for again (%d)" % (dye.item_count if dye != null else 0))
	_check(picker.current().contains("torso=3") and not picker.current().contains("torso_dye"),
		"and the third colourway, which the noble torso lacks, is dropped (%s)" % picker.current())
	var shown: ModularCharacter = picker.preview_model() as ModularCharacter
	_check(shown != null and _pieces_worn(shown).has("Female_Noble_Body"), "the preview wears it")
	picker.close()
	picker.queue_free()
	await get_tree().process_frame


func _dressed_color(look: ModularCharacter, prefix: String) -> Color:
	var m: StandardMaterial3D = _dressed(look, prefix)
	return m.albedo_color if m != null else Color(0, 0, 0, 0)
