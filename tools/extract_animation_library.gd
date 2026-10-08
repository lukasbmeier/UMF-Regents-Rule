extends SceneTree
## Turn an imported character/animation source (.glb / .fbx / .gltf) into a standalone
## `AnimationLibrary` resource that any model with the same skeleton can play.
##
## WHY NOT JUST COMMIT THE SOURCE. The Quaternius libraries are 20 MB (GLB) and 68 MB (FBX)
## because they carry a mannequin mesh and its textures. The animation data alone is under
## 4 MB, and a library resource is what every character in the game shares — the model files
## stay out of the repository and only this artifact is committed, the same bargain as the
## vendored SDK: a fresh clone works offline, and the tool that produced the artifact is here
## next to it.
##
## WHAT IT FIXES. An imported source's tracks are addressed from ITS node names — `Rig/Skeleton3D`
## in the FBX export, `Armature/Skeleton3D` in the GLB — so a library lifted out of one source
## silently animates nothing on a model laid out differently. Every track is rewritten to
## `Skeleton3D:<bone>`, and `AnimationDriverComponent` roots the tree at the skeleton's parent,
## so a library plays on ANY model whose skeleton uses the same bone names. FBX take names
## (`Rig|Jump_Start`) lose their prefix at the same time.
##
## AND THE TRANSFORM THOSE NODES CARRIED. Dropping the node names drops their transforms with
## them, and for an FBX that is where the Z-up-to-Y-up conversion lives: Godot puts it on the
## `Rig` node and leaves the root bone's pose identity, while a GLB carries the same -90 deg in
## the pose itself. Re-address without accounting for it and the character animates flawlessly,
## lying on its back. The accumulated transform above the bones is composed into the tracks of
## every parentless bone, which makes a library from either kind of source mean the same thing.
##
## USAGE
##   1. copy the source files into res://game/anim/_import/  (git-ignored; delete them after)
##   2. godot --headless --path . --import
##   3. godot --headless --path . --script res://tools/extract_animation_library.gd
##   4. check the report, then delete res://game/anim/_import/
##
## Every run prints what it wrote, so a regenerated library can be diffed against the report in
## `game/anim/ATTRIBUTION.md`.

const IMPORT_DIR: String = "res://game/anim/_import"
const OUT_DIR: String = "res://game/anim"
## Bone tracks are rewritten onto a node with this name. Godot's importers already call the
## skeleton node this, and the driver enforces it on the model side.
const SKELETON_NODE: String = "Skeleton3D"


func _initialize() -> void:
	var dir: DirAccess = DirAccess.open(IMPORT_DIR)
	if dir == null:
		printerr("no %s — copy the source .glb/.fbx files there first (see the header)" % IMPORT_DIR)
		quit(1)
		return
	var sources: PackedStringArray = PackedStringArray()
	for f: String in dir.get_files():
		# Godot writes a .import sidecar per source; the source itself is what we load.
		if f.get_extension().to_lower() in ["glb", "gltf", "fbx"]:
			sources.append(IMPORT_DIR + "/" + f)
	if sources.is_empty():
		printerr("%s has no .glb/.gltf/.fbx sources" % IMPORT_DIR)
		quit(1)
		return

	var failures: int = 0
	for src: String in sources:
		if not _extract(src):
			failures += 1
	quit(1 if failures > 0 else 0)


func _extract(src: String) -> bool:
	print("== ", src)
	var packed: PackedScene = load(src) as PackedScene
	if packed == null:
		printerr("   could not load (did `--import` run?)")
		return false
	var root: Node = packed.instantiate()
	var player: AnimationPlayer = _find(root, "AnimationPlayer") as AnimationPlayer
	var skel: Skeleton3D = _find(root, "Skeleton3D") as Skeleton3D
	if player == null:
		printerr("   no AnimationPlayer in the source")
		root.free()
		return false
	print("   skeleton: %d bones" % (skel.get_bone_count() if skel != null else 0))

	# What the source's own nodes contributed above the skeleton's bones.
	var correction: Transform3D = _correction(player, skel)
	var root_bones: PackedStringArray = PackedStringArray()
	if skel != null:
		for b: int in skel.get_parentless_bones():
			root_bones.append(skel.get_bone_name(b))
	if correction != Transform3D.IDENTITY:
		print("   source nodes carry %s — composing it into %s"
			% [str(correction), str(root_bones)])

	var out_lib := AnimationLibrary.new()
	var renamed: int = 0
	var retracked: int = 0
	var total: int = 0
	for lib_name: StringName in player.get_animation_library_list():
		var lib: AnimationLibrary = player.get_animation_library(lib_name)
		for anim_name: StringName in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name).duplicate(true) as Animation
			retracked += _retrack(anim)
			_apply_correction(anim, correction, root_bones)
			var clean: StringName = _clean_name(anim_name)
			if clean != anim_name:
				renamed += 1
			out_lib.add_animation(clean, anim)
			total += 1

	var out_path: String = "%s/%s.res" % [OUT_DIR, src.get_file().get_basename().to_snake_case()]
	var err: int = ResourceSaver.save(out_lib, out_path)
	root.free()
	if err != OK:
		printerr("   save failed (%d) -> %s" % [err, out_path])
		return false
	var size: int = FileAccess.get_file_as_bytes(out_path).size()
	print("   %d animations (%d renamed, %d tracks re-addressed) -> %s, %.2f MB"
		% [total, renamed, retracked, out_path, float(size) / 1048576.0])
	return true


## `Rig|Jump_Start` -> `Jump_Start`. FBX stores each take as `<armature>|<take>`; GLB does not.
func _clean_name(n: StringName) -> StringName:
	var s: String = String(n)
	var bar: int = s.rfind("|")
	return StringName(s.substr(bar + 1)) if bar >= 0 else n


## Re-address every bone track onto `Skeleton3D`. Returns how many tracks were changed.
func _retrack(anim: Animation) -> int:
	var changed: int = 0
	for i: int in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(i)
		var subs: int = path.get_subname_count()
		if subs == 0 or path.get_name_count() == 0:
			continue   # not a bone track (mesh visibility, blend shapes on a named node)
		if path.get_name(path.get_name_count() - 1) != SKELETON_NODE:
			continue
		var bone: String = path.get_concatenated_subnames()
		var wanted := NodePath("%s:%s" % [SKELETON_NODE, bone])
		if path != wanted:
			anim.track_set_path(i, wanted)
			changed += 1
	return changed


## Everything the source put between the animation root and the bones: the intermediate nodes'
## transforms and the skeleton node's own. Identity for a GLB; a -90 deg X rotation for an FBX,
## where that is how Godot converts Z-up.
func _correction(player: AnimationPlayer, skel: Skeleton3D) -> Transform3D:
	if skel == null:
		return Transform3D.IDENTITY
	var anim_root: Node = player.get_node_or_null(player.root_node)
	if anim_root == null:
		anim_root = player.get_parent()
	var chain: Array[Node3D] = []
	var n: Node = skel
	while n != null and n != anim_root:
		var n3: Node3D = n as Node3D
		if n3 != null:
			chain.push_front(n3)
		n = n.get_parent()
	var t := Transform3D.IDENTITY
	for c: Node3D in chain:
		t = t * c.transform
	return t


## Compose `correction` into the tracks. Its two halves apply to different things:
##
##   ROTATION re-orients the whole hierarchy, so it belongs on the bones with no parent — every
##   other bone is already expressed relative to one of those.
##   SCALE is a change of UNITS. An FBX is authored in centimetres and Godot compensates with a
##   x100 on the node above the skeleton, so EVERY position track is off by that factor, not
##   just the root's. Leaving the others alone gave an upright character with its pelvis at
##   9 mm and its feet three quarters of a metre underground.
func _apply_correction(anim: Animation, correction: Transform3D,
		root_bones: PackedStringArray) -> void:
	if correction == Transform3D.IDENTITY:
		return
	var rot: Quaternion = correction.basis.get_rotation_quaternion()
	var scale: Vector3 = correction.basis.get_scale()
	for i: int in range(anim.get_track_count()):
		var path: NodePath = anim.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var is_root: bool = root_bones.has(path.get_concatenated_subnames())
		var kind: int = anim.track_get_type(i)
		for k: int in range(anim.track_get_key_count(i)):
			match kind:
				Animation.TYPE_POSITION_3D:
					var pos: Vector3 = anim.track_get_key_value(i, k)
					anim.track_set_key_value(i, k, correction * pos if is_root else pos * scale)
				Animation.TYPE_ROTATION_3D:
					if is_root:
						anim.track_set_key_value(i, k,
							rot * (anim.track_get_key_value(i, k) as Quaternion))
				_:
					pass


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c: Node in n.get_children():
		var f: Node = _find(c, cls)
		if f != null:
			return f
	return null
