@tool
class_name RegentsPointPreview extends Node3D
## LIVE 3D VISUALIZER & GIZMO RINGS FOR A `LevelPoint` (WB8, `docs/regents_rule/WORLD_BUILDER_PREP.md` §8.1).
## Attached to any `LevelPoint` with `Node.INTERNAL_MODE_BACK` (and `owner = null`), so it shows the real tree,
## rock, station, dummy, foe, friendly NPC, or World Map POI beacon in the World Builder and editor, while never
## saving a single preview node into the `.tscn` file.
##
## Gizmo rings drawn on the ground (`rings`):
##   - `footprint`    solid trunk/rock edge (`NodeDef.radius_for`)
##   - `work_reach`   where a player works from (`footprint + 3.0 m`, gold)
##   - `wander`       where a foe or NPC wanders/grazes at rest (`wander_m` / `graze_m`, green)
##   - `notice_cone`  a foe's front sight cone (`notice_m`, `notice_arc_deg`, amber)
##   - `hear`         a foe's all-round hearing radius (`hear_m`, yellow)
##   - `leash`        where a foe gives up and walks home (`leash_m`, red)
##   - `pack`         pack call radius (`pack_m`, cyan) and lines to nearby packmates of the same kind

const PREVIEW_NAME: StringName = &"_BuilderPreview"
const NUGGET_SCENE: String = "res://game/regents/art/nature/Pebble_Round_1.gltf"
const DUMMY_SCENE: String = "res://game/regents/art/props/Dummy.gltf"
const WORK_REACH_M: float = 3.0

## Whether tactical rings (leash, sight cone, hearing, work reach) are drawn around the model.
var show_rings: bool = true:
	set(v):
		show_rings = v
		if _rings_root != null:
			_rings_root.visible = v

## Which rings were built for this point (`"footprint"`, `"work_reach"`, `"wander"`, `"notice_cone"`, `"hear"`,
## `"leash"`, `"pack"`, `"poi"`, `"interact"`), mapped to their radius in meters (tests read this).
var rings: Dictionary[StringName, float] = {}
## Positions (in local space) of nearby packmates linked by the pack gizmo (tests read this).
var pack_links: PackedVector3Array = PackedVector3Array()
## The 3D model root instantiated for this point (tests read this).
var model_root: Node3D = null
## Summary label text shown above the point.
var label_text: String = ""

var _rings_root: Node3D = null
var _label: Label3D = null


## Attach or refresh the `RegentsPointPreview` on `point`. Returns the preview node.
static func ensure_on(point: LevelPoint, with_rings: bool = true) -> RegentsPointPreview:
	if point == null:
		return null
	var existing: RegentsPointPreview = null
	for c: Node in point.get_children(true):
		if c is RegentsPointPreview:
			existing = c as RegentsPointPreview
			break
	if existing == null:
		existing = RegentsPointPreview.new()
		existing.name = String(PREVIEW_NAME)
		point.add_child(existing, false, Node.INTERNAL_MODE_BACK)
		existing.owner = null
	existing.show_rings = with_rings
	existing.rebuild(point)
	return existing


## Attach or refresh previews on every `LevelPoint` under `root`. Returns how many points were visualized.
static func attach_all(root: Node, with_rings: bool = true) -> int:
	if root == null:
		return 0
	var count: int = 0
	var all_points: Array[LevelPoint] = []
	if root is LevelPoint:
		all_points.append(root as LevelPoint)
	for n: Node in root.find_children("*", "Marker3D", true, false):
		if n is LevelPoint:
			all_points.append(n as LevelPoint)
	for lp: LevelPoint in all_points:
		ensure_on(lp, with_rings)
		count += 1
	return count


## Rebuild the 3D preview and rings from `point`'s current `kind`, `tags`, `radius`, and `point_id`.
func rebuild(point: LevelPoint) -> void:
	_clear_materials(self)
	for c: Node in get_children():
		remove_child(c)
		c.free()
	rings.clear()
	pack_links.clear()
	model_root = null
	label_text = ""
	if point == null:
		return
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)
	_rings_root = Node3D.new()
	_rings_root.name = "Rings"
	_rings_root.visible = show_rings
	add_child(_rings_root)

	var tag: String = point.tags[0] if not point.tags.is_empty() else ""
	var seed_hash: int = absi(hash(point.point_id if not point.point_id.is_empty() else point.name))
	# Match server yaw_of(point_id) when point itself has zero rotation, so preview orientation matches runtime.
	if is_zero_approx(point.rotation.y) and not point.point_id.is_empty():
		model_root.rotation.y = _server_yaw(point.point_id)

	match point.kind:
		"node":
			_build_node(point, tag, seed_hash)
		"station":
			_build_station(point, tag)
		"dummy":
			_build_dummy(point)
		"guide":
			_build_guide(point)
		"npc":
			_build_npc(point, tag)
		"poi":
			_build_poi(point, tag)
		_:
			var foe: FoeDef = foe_by_key(StringName(point.kind))
			if foe != null:
				_build_foe(point, foe)
			else:
				_build_unknown(point)


static func node_by_name(node_name: String) -> NodeDef:
	for d: NodeDef in NodeDef.all_by_tier():
		if d.display_name == node_name or str(d.id) == node_name:
			return d
	return null


static func foe_by_key(foe_key: StringName) -> FoeDef:
	for f: FoeDef in FoeDef.all():
		if f.key == foe_key:
			return f
	return null


func _build_node(point: LevelPoint, tag: String, seed_hash: int) -> void:
	var def: NodeDef = node_by_name(tag)
	if def == null:
		_build_unknown(point, "Node? (%s)" % tag)
		return
	label_text = "%s (Rank %d)" % [def.display_name, def.min_rank]
	if not def.models.is_empty():
		var scene: PackedScene = def.models[seed_hash % def.models.size()]
		if scene != null:
			var inst: Node3D = scene.instantiate() as Node3D
			inst.scale = Vector3.ONE * def.model_scale
			model_root.add_child(inst)
			if def.ore_color.a > 0.0:
				_add_ore_nuggets(inst, scene, def.ore_color, seed_hash)
	var foot_r: float = def.radius_for(seed_hash)
	if foot_r <= 0.0:
		foot_r = maxf(point.radius, 0.5)
	_add_ring(&"footprint", foot_r, Color(0.35, 0.85, 0.45, 0.85), 0.05)
	_add_ring(&"work_reach", foot_r + WORK_REACH_M, Color(0.95, 0.82, 0.3, 0.45), 0.04)
	_add_label(label_text, Vector3(0.0, 2.6, 0.0), Color(0.85, 0.95, 0.75))


func _add_ore_nuggets(target_model: Node3D, scene: PackedScene, color: Color, seed_hash: int) -> void:
	if not ResourceLoader.exists(NUGGET_SCENE):
		return
	var nugget_pack: PackedScene = load(NUGGET_SCENE) as PackedScene
	if nugget_pack == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.6
	mat.roughness = 0.35
	for spot: Transform3D in RegentsOreSpots.spots_for(scene, target_model, NodeComponent.NUGGETS, seed_hash):
		var n: Node3D = nugget_pack.instantiate() as Node3D
		n.transform = spot
		for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat
		target_model.add_child(n)


func _build_station(point: LevelPoint, tag: String) -> void:
	var st: StationDef = StationDef.by_key(StringName(tag))
	if st == null:
		_build_unknown(point, "Station? (%s)" % tag)
		return
	label_text = st.display_name
	if st.body_size != Vector3.ZERO:
		var body_mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = st.body_size
		body_mi.mesh = box
		body_mi.position = Vector3(0.0, st.body_size.y * 0.5, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = st.body_color
		mat.roughness = 0.95
		body_mi.material_override = mat
		model_root.add_child(body_mi)
	for i: int in st.pieces.size():
		if st.pieces[i] != null:
			var p: Node3D = st.pieces[i].instantiate() as Node3D
			p.transform = st.piece_transforms[i] if i < st.piece_transforms.size() else Transform3D.IDENTITY
			model_root.add_child(p)
	_add_ring(&"footprint", maxf(point.radius, 0.8), Color(0.9, 0.65, 0.25, 0.85), 0.05)
	_add_ring(&"work_reach", WORK_REACH_M, Color(0.95, 0.82, 0.3, 0.45), 0.04)
	_add_label(label_text, Vector3(0.0, 2.3, 0.0), Color(1.0, 0.86, 0.55))


func _build_dummy(point: LevelPoint) -> void:
	label_text = "Training Dummy"
	if ResourceLoader.exists(DUMMY_SCENE):
		var d: Node3D = (load(DUMMY_SCENE) as PackedScene).instantiate() as Node3D
		model_root.add_child(d)
	else:
		_add_capsule_standin(Color(0.75, 0.58, 0.36))
	_add_ring(&"footprint", maxf(point.radius, 0.5), Color(0.85, 0.7, 0.4, 0.8), 0.04)
	_add_label(label_text, Vector3(0.0, 2.2, 0.0), Color(0.95, 0.85, 0.65))


func _build_guide(point: LevelPoint) -> void:
	var npc: NpcDef = NpcDef.by_key(&"drillmaster")
	if npc != null:
		_build_npc(point, "drillmaster")
		return
	label_text = "Drillmaster (Guide)"
	_add_capsule_standin(Color(0.35, 0.65, 0.95))
	_add_ring(&"interact", WORK_REACH_M, Color(0.4, 0.8, 1.0, 0.65), 0.04)
	_add_label(label_text, Vector3(0.0, 2.3, 0.0), Color(0.65, 0.9, 1.0))


func _build_npc(_point: LevelPoint, tag: String) -> void:
	var key: StringName = StringName(tag if not tag.is_empty() else "drillmaster")
	var npc: NpcDef = NpcDef.by_key(key)
	if npc == null:
		label_text = "NPC (%s)" % String(key)
		_add_capsule_standin(Color(0.4, 0.85, 0.95))
		_add_ring(&"interact", 2.8, Color(0.4, 0.85, 1.0, 0.65), 0.04)
		_add_label(label_text, Vector3(0.0, 2.3, 0.0), Color(0.65, 0.9, 1.0))
		return
	label_text = npc.display_name + ("\n<%s>" % npc.title if not npc.title.is_empty() else "")
	var fig: ModularCharacter = npc.build_figure()
	model_root.add_child(fig)
	_add_ring(&"interact", npc.interact_m, Color(0.38, 0.85, 1.0, 0.7), 0.04)
	if npc.wander_m > 0.0:
		_add_ring(&"wander", npc.wander_m, Color(0.4, 0.9, 0.55, 0.45), 0.03)
	_add_label(label_text, Vector3(0.0, 2.35, 0.0), Color(0.65, 0.92, 1.0))


func _build_foe(point: LevelPoint, foe: FoeDef) -> void:
	label_text = "%s (%d HP)" % [foe.display_name, foe.hp]
	if foe.character != null and foe.character.visual_scene != null:
		var m: Node3D = foe.character.visual_scene.instantiate() as Node3D
		m.scale = Vector3.ONE * foe.character.visual_scale
		model_root.add_child(m)
		var skel: Skeleton3D = _find_skeleton(m)
		if skel != null:
			var look := FoeLook.new()
			look.dress(skel, foe)
			look.free()
	else:
		_add_capsule_standin(Color(0.9, 0.32, 0.28))
	var wander: float = foe.wander_m if foe.fights else foe.graze_m
	if wander > 0.0:
		_add_ring(&"wander", wander, Color(0.35, 0.88, 0.45, 0.55), 0.035)
	if foe.fights:
		_add_cone(&"notice_cone", foe.notice_m, foe.notice_arc_deg, Color(1.0, 0.72, 0.22, 0.65))
		if foe.hear_m > 0.0:
			_add_ring(&"hear", foe.hear_m, Color(0.95, 0.9, 0.3, 0.45), 0.03)
	else:
		_add_ring(&"hear", foe.startle_m, Color(0.95, 0.9, 0.3, 0.5), 0.03)
	if foe.leash_m > 0.0:
		_add_ring(&"leash", foe.leash_m, Color(0.95, 0.3, 0.28, 0.45), 0.04)
	if foe.pack_m > 0.0:
		_add_ring(&"pack", foe.pack_m, Color(0.3, 0.85, 0.95, 0.5), 0.035)
		_build_pack_links(point, foe.pack_m)
	_add_label(label_text, Vector3(0.0, 2.2, 0.0), Color(1.0, 0.62, 0.55) if foe.fights else Color(0.75, 0.95, 0.75))


func _build_pack_links(point: LevelPoint, pack_m: float) -> void:
	var parent: Node = point.get_parent()
	if parent == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var count: int = 0
	for sib: Node in parent.get_children():
		var other: LevelPoint = sib as LevelPoint
		if other == null or other == point or other.kind != point.kind:
			continue
		var delta: Vector3 = other.position - point.position
		var dist: float = Vector2(delta.x, delta.z).length()
		if dist <= pack_m and dist > 0.01:
			pack_links.append(delta)
			st.add_vertex(Vector3(0.0, 0.25, 0.0))
			st.add_vertex(delta + Vector3(0.0, 0.25, 0.0))
			count += 1
	if count > 0:
		var mi := MeshInstance3D.new()
		mi.name = "PackLinks"
		mi.mesh = st.commit()
		mi.material_override = _unshaded_mat(Color(0.3, 0.9, 1.0, 0.85))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rings_root.add_child(mi)


func _build_poi(point: LevelPoint, tag: String) -> void:
	var title: String = tag if not tag.is_empty() else point.point_id
	label_text = "POI: %s" % title
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.22
	cyl.height = 4.5
	pillar.mesh = cyl
	pillar.position = Vector3(0.0, 2.25, 0.0)
	pillar.material_override = _unshaded_mat(Color(1.0, 0.84, 0.28, 0.8))
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model_root.add_child(pillar)
	_add_ring(&"poi", maxf(point.radius, 4.0), Color(1.0, 0.84, 0.28, 0.75), 0.06)
	_add_label(label_text, Vector3(0.0, 4.9, 0.0), Color(1.0, 0.9, 0.45))


func _build_unknown(point: LevelPoint, text: String = "") -> void:
	label_text = text if not text.is_empty() else "%s (%s)" % [point.point_id, point.kind]
	_add_capsule_standin(Color(0.8, 0.4, 0.9))
	_add_ring(&"footprint", maxf(point.radius, 0.5), Color(0.8, 0.4, 0.9, 0.75), 0.04)
	_add_label(label_text, Vector3(0.0, 2.0, 0.0), Color(0.9, 0.7, 1.0))


func _add_capsule_standin(color: Color) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	mi.mesh = cap
	mi.position = Vector3(0.0, 0.85, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mi.material_override = mat
	model_root.add_child(mi)


func _add_ring(key: StringName, radius: float, color: Color, width: float = 0.04) -> void:
	if radius <= 0.0:
		return
	rings[key] = radius
	var mi := MeshInstance3D.new()
	mi.name = "Ring_%s" % String(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = clampi(int(radius * 6.0), 24, 72)
	var r0: float = maxf(0.02, radius - width * 0.5)
	var r1: float = radius + width * 0.5
	var y: float = 0.06
	for i: int in steps:
		var a0: float = TAU * float(i) / float(steps)
		var a1: float = TAU * float(i + 1) / float(steps)
		var p00 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, y, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, y, sin(a1) * r1)
		for p: Vector3 in [p00, p01, p11, p00, p11, p10]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	mi.mesh = st.commit()
	mi.material_override = _unshaded_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings_root.add_child(mi)


func _add_cone(key: StringName, radius: float, arc_deg: float, color: Color) -> void:
	if radius <= 0.0:
		return
	rings[key] = radius
	var mi := MeshInstance3D.new()
	mi.name = "Cone_%s" % String(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var half_rad: float = deg_to_rad(clampf(arc_deg, 10.0, 360.0) * 0.5)
	var steps: int = 32
	var y: float = 0.08
	# Forward in model_root's frame (which carries the server yaw if point.rotation.y == 0).
	var basis_yaw: float = model_root.rotation.y if model_root != null else 0.0
	var prev := Vector3.ZERO
	for i: int in range(steps + 1):
		var a: float = basis_yaw - half_rad + (2.0 * half_rad) * float(i) / float(steps)
		var pt := Vector3(sin(a) * radius, y, cos(a) * radius)
		if i == 0 or i == steps:
			st.add_vertex(Vector3(0.0, y, 0.0))
			st.add_vertex(pt)
		if i > 0:
			st.add_vertex(prev)
			st.add_vertex(pt)
		prev = pt
	mi.mesh = st.commit()
	mi.material_override = _unshaded_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings_root.add_child(mi)


func _add_label(text: String, offset: Vector3, color: Color) -> void:
	_label = Label3D.new()
	_label.name = "Label"
	_label.text = text
	_label.position = offset
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.pixel_size = 0.0045
	_label.font_size = 42
	_label.outline_size = 10
	_label.modulate = color
	add_child(_label)


static func _unshaded_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c: Node in n.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


static func _clear_materials(root: Node) -> void:
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi != null:
			mi.material_override = null
			for i: int in mi.get_surface_override_material_count():
				mi.set_surface_override_material(i, null)


## Matches `regents.rs` `yaw_of(point_id)` so preview models face the exact direction the server spawns them.
static func _server_yaw(point_id: String) -> float:
	var h: int = 7
	for b: int in point_id.to_utf8_buffer():
		h = (h * 31 + b) & 0x7FFFFFFFFFFFFFFF
	var permille: int = posmod(h * 1103515245 + 12345, 1000)
	return float(permille) * TAU / 1000.0
