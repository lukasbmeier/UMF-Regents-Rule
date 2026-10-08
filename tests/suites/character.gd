extends "res://tests/suite_base.gd"
## The `character` suite (tests/test_runner.gd runs it; `-- --only=character` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_character_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## CHARACTERS PUT TOGETHER FROM PIECES (ModularCharacter): what a look is made of, and who wears
## which. The pose suite measures them animating; this checks the assembly itself, which can be
## wrong in ways a pose would not show — a piece left on a skeleton of its own renders in its
## rest pose, frozen, next to a character that animates perfectly.
const PIECES_DIR: String = "res://game/characters/quaternius/models/"
const LOD_CONTROL: String = "res://game/world/kits/nature/Birch_1.gltf"

## How many LODs the renderer holds for a mesh's surfaces (the most of any surface).
static func _lod_count(mesh: Mesh) -> int:
	var most: int = 0
	if mesh == null:
		return 0
	for s: int in range(mesh.get_surface_count()):
		var surf: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		most = maxi(most, (surf.get("lods", []) as Array).size())
	return most


func _run_character_tests() -> void:
	print("== characters: looks ==")
	var fisher: EntityDefinition = load(FISHER_DEF) as EntityDefinition
	_check(fisher != null and fisher.visual_variants.size() >= 2,
		"anglers come in several looks (%d)" % (fisher.visual_variants.size() if fisher != null else 0))
	if fisher == null:
		return
	# WHO WEARS WHAT: by entity id, the same on every client, and neighbours never match.
	var n: int = fisher.visual_variants.size()
	var seen: Dictionary[PackedScene, bool] = {}
	for id: int in range(n):
		seen[fisher.visual_for(id)] = true
	_check(seen.size() == n, "%d consecutive entity ids wear %d different looks" % [n, seen.size()])
	_check(fisher.visual_for(n + 3) == fisher.visual_for(3) and fisher.visual_for(-1) == fisher.visual_for(n - 1),
		"and the choice is a pure function of the id, wrapping (and safe for any id)")
	var plain := EntityDefinition.new()
	plain.visual_scene = fisher.visual_variants[0]
	_check(plain.visual_for(12345) == plain.visual_scene, "a definition with no variants wears its one model")

	for look: PackedScene in _shipped_looks():
		var name: String = look.resource_path.get_file()
		var model: ModularCharacter = look.instantiate() as ModularCharacter
		_check(model != null, "%s is a ModularCharacter" % name)
		if model == null:
			continue
		# Assembled by instantiate() alone, before it is in any tree: the spawner and the
		# animation driver may look for its skeleton before its _ready ever runs.
		var skels: Array[Node] = model.find_children("*", "Skeleton3D", true, false)
		var skel: Skeleton3D = model.skeleton()
		_check(skels.size() == 1 and skel != null and skels[0] == skel,
			"%s comes out of instantiate() on ONE skeleton (%d)" % [name, skels.size()])
		# Into the tree the way the spawner puts it: the headless renderer objects to freeing a
		# mesh with material overrides that was never in one.
		get_tree().root.add_child(model)
		if skel == null:
			model.queue_free()
			continue
		var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
		var loose: Array[String] = []
		var unbound: Array[String] = []
		for node: Node in meshes:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.get_parent() != skel or mi.skeleton != NodePath(".."):
				loose.append(String(mi.name))
			if mi.skin != null:
				for b: int in range(mi.skin.get_bind_count()):
					var bone: StringName = mi.skin.get_bind_name(b)
					if bone == &"" or skel.find_bone(bone) < 0:
						unbound.append("%s:%s" % [mi.name, bone])
						break
		_check(meshes.size() > (model as ModularCharacter).parts.size(),
			"%s wears its head and every piece (%d meshes for %d pieces)" % [name, meshes.size(), model.parts.size()])
		_check(loose.is_empty(), "%s: every mesh is on the one skeleton (%s)" % [name, str(loose)])
		_check(unbound.is_empty(), "%s: every skin binds bones the skeleton has, by name (%s)" % [name, str(unbound)])
		_check(skel.get_bone_count() == 65, "%s has the 65-bone skeleton the clips are for (%d)" % [name, skel.get_bone_count()])
		var brows: Array[String] = []
		for node: Node in meshes:
			if is_instance_valid(node) and String(node.name).begins_with("Eyebrows"):
				brows.append(String(node.name))
		_check(brows.size() == 1, "%s has one pair of eyebrows, not the head's and its own (%s)" % [name, str(brows)])
		# EVERY PIECE SITS ON THIS BODY. A skin's bind poses are where its piece expects each bone
		# to be; the head's skeleton is where each bone IS. A piece modelled on another body (or a
		# head from another pack) would pass every check above and float off its wearer.
		var worst: float = 0.0
		var worst_at: String = ""
		for node: Node in meshes:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.skin == null:
				continue
			for i: int in range(mi.skin.get_bind_count()):
				var bone: int = skel.find_bone(mi.skin.get_bind_name(i))
				if bone < 0:
					continue
				var expected: Transform3D = mi.skin.get_bind_pose(i).affine_inverse()
				var off: float = expected.origin.distance_to(skel.get_bone_global_rest(bone).origin)
				if off > worst:
					worst = off
					worst_at = "%s/%s" % [mi.name, mi.skin.get_bind_name(i)]
		_check(worst < 0.005, "%s: every piece is bound where the head's skeleton has its bones (worst %.4f m at %s)"
			% [name, worst, worst_at])
		model.queue_free()

	# NO LODS ON A WORN PIECE (DECISIONS #177). The pieces are worn in layers a millimetre apart, and
	# an LOD simplifies each one on its own: at 8 m the buzzed hair sank into the scalp and the skin
	# showed through it in spots. The renderer's own surface data says what it would draw at a
	# distance; a kit tree, imported with LODs, proves this check can see them.
	var tree: Node = (load(LOD_CONTROL) as PackedScene).instantiate()
	var control_lods: int = 0
	for node: Node in tree.find_children("*", "MeshInstance3D", true, false):
		control_lods = maxi(control_lods, _lod_count((node as MeshInstance3D).mesh))
	tree.free()
	_check(control_lods > 0, "the check sees LODs where an import made them (%d on %s)" % [control_lods, LOD_CONTROL.get_file()])
	var with_lods: Array[String] = []
	var pieces: int = 0
	for f: String in DirAccess.get_files_at(PIECES_DIR):
		if not f.ends_with(".gltf"):
			continue
		pieces += 1
		var piece: Node = (load(PIECES_DIR + f) as PackedScene).instantiate()
		for node: Node in piece.find_children("*", "MeshInstance3D", true, false):
			if _lod_count((node as MeshInstance3D).mesh) > 0:
				with_lods.append("%s/%s" % [f.get_basename(), node.name])
		piece.free()
	_check(pieces >= 50 and with_lods.is_empty(),
		"none of the %d character pieces has an LOD to sink into the one under it (%s)" % [pieces, str(with_lods)])

	# COLOURS ARE PER CHARACTER. The pieces share their imported materials, so a tint written to
	# the shared one would dress every character in the last one's hair colour.
	var a: ModularCharacter = fisher.visual_variants[0].instantiate() as ModularCharacter
	var b: ModularCharacter = fisher.visual_variants[0].instantiate() as ModularCharacter
	var c: ModularCharacter = fisher.visual_variants[2].instantiate() as ModularCharacter
	for m: ModularCharacter in [a, b, c]:
		get_tree().root.add_child(m)
	var hair_of := func(m: ModularCharacter) -> StandardMaterial3D:
		for node: Node in m.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = node as MeshInstance3D
			for i: int in range(mi.mesh.get_surface_count()):
				var src: Material = mi.mesh.surface_get_material(i)
				if src != null and src.resource_name.begins_with(ModularCharacter.HAIR_PREFIX):
					return mi.get_surface_override_material(i) as StandardMaterial3D
		return null
	var ha: StandardMaterial3D = hair_of.call(a)
	var hb: StandardMaterial3D = hair_of.call(b)
	var hc: StandardMaterial3D = hair_of.call(c)
	_check(ha != null and hc != null and ha.albedo_color.is_equal_approx(a.hair_color)
			and hc.albedo_color.is_equal_approx(c.hair_color),
		"each look's hair is its own colour (%s, %s)"
			% [str(ha.albedo_color) if ha != null else "none", str(hc.albedo_color) if hc != null else "none"])
	_check(ha != null and hb != null and ha == hb,
		"two anglers in the same look share that look's copy rather than one each")
	var shared: bool = false
	for node: Node in a.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src != null and src.resource_name.begins_with(ModularCharacter.HAIR_PREFIX) \
					and not src.albedo_color.is_equal_approx(Color.WHITE):
				shared = true
	_check(not shared, "and the imported material itself is left as it came")
	for m: ModularCharacter in [a, b, c]:
		m.queue_free()
