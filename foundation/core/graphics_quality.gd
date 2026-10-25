class_name GraphicsQuality extends RefCounted
## WHAT THE VIDEO SETTINGS DO TO A LEVEL (DECISIONS #282). A level is the designer's: its
## WorldEnvironment turns on SSAO, glow, fog, and its lights cast shadows. A player on a weak machine
## turns them DOWN from there, never up past what the level asked for, and back up to exactly it. So
## each Environment and light keeps what it was authored with (`AUTHORED_META`, read the first time it
## is seen) and is set from that and the player's choice; `Settings` calls `apply_tree` when a choice
## changes and `apply_node` for each node as it enters the tree.
##
##   effects (Off / Reduced / Full)   Full: as authored. Reduced: SSAO and glow only (no SSIL, SSR,
##                                     SDFGI, volumetric fog). Off: none of them (fog stays: it is the
##                                     look of the distance, and costs nothing).
##   shadows (Off / Low / Medium / High)  Off: no light casts one. The rest is the filter and atlas.
##   detail (Low / Medium / High)     mesh LOD, how far the sun's shadows reach, and THE DESIGNER'S
##                                     GROUPS below.
##
## A DESIGNER'S DETAIL, with no code: put a node in a group in the Inspector.
##   `detail_high`     shown only on High detail (a second layer of props, close-up clutter);
##   `detail_medium`   hidden on Low;
##   `detail_density`  a MultiMeshInstance3D drawn at `DENSITY` of its instances (grass, pebbles):
##                     the first ones are kept, so scatter them in a random order.

const AUTHORED_META: StringName = &"umf_authored"
const GROUP_HIGH: StringName = &"detail_high"
const GROUP_MEDIUM: StringName = &"detail_medium"
const GROUP_DENSITY: StringName = &"detail_density"

enum Effects { OFF, REDUCED, FULL }
enum Detail { LOW, MEDIUM, HIGH }

## Per detail level: Godot's mesh LOD threshold (pixels of error allowed; 1 is the default), the
## share of the sun's authored shadow distance, and the share of a `detail_density` multimesh drawn.
const LOD_THRESHOLD: PackedFloat32Array = [4.0, 2.0, 1.0]
const SHADOW_REACH: PackedFloat32Array = [0.5, 0.75, 1.0]
const DENSITY: PackedFloat32Array = [0.25, 0.5, 1.0]

## The choices now (Settings sets them before applying).
static var effects: int = Effects.FULL
static var shadows_on: bool = true
static var detail: int = Detail.HIGH


## Every Environment, light and detail node under `root`, set from the choices.
static func apply_tree(root: Node) -> void:
	if root == null:
		return
	var window: Window = root as Window
	if window != null:
		window.mesh_lod_threshold = LOD_THRESHOLD[detail]
	_apply_world(root.get_viewport().world_3d if root.get_viewport() != null else null)
	for n: Node in root.find_children("*", "", true, false):
		apply_node(n)


## One node as it enters the tree (Settings listens to `node_added`). Cheap for any other node.
static func apply_node(n: Node) -> void:
	if n is WorldEnvironment:
		apply_environment((n as WorldEnvironment).environment)
	elif n is Light3D:
		apply_light(n as Light3D)
	elif n is Camera3D:
		var cam: Camera3D = n as Camera3D
		if cam.environment != null:
			apply_environment(cam.environment)
	if n is Node3D and (n.is_in_group(GROUP_HIGH) or n.is_in_group(GROUP_MEDIUM)):
		_apply_group_visibility(n as Node3D)
	if n is MultiMeshInstance3D and n.is_in_group(GROUP_DENSITY):
		_apply_density(n as MultiMeshInstance3D)


static func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var a: Dictionary = _authored_env(env)
	var full: bool = effects == Effects.FULL
	var some: bool = effects != Effects.OFF
	# Only Forward+ draws SSAO, SSIL, SSR, SDFGI and volumetric fog; asked for them, the others
	# warn and draw nothing, so off they go (glow works everywhere).
	var forward: bool = RenderingServer.get_current_rendering_method() in ["forward_plus", "dummy"]
	env.ssao_enabled = bool(a["ssao"]) and some and forward
	env.glow_enabled = bool(a["glow"]) and some
	env.ssil_enabled = bool(a["ssil"]) and full and forward
	env.ssr_enabled = bool(a["ssr"]) and full and forward
	env.sdfgi_enabled = bool(a["sdfgi"]) and full and forward
	env.volumetric_fog_enabled = bool(a["volumetric_fog"]) and full and forward


static func apply_light(light: Light3D) -> void:
	if light == null:
		return
	var a: Dictionary = _authored_light(light)
	light.shadow_enabled = bool(a["shadow"]) and shadows_on
	var sun: DirectionalLight3D = light as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_max_distance = float(a["reach"]) * SHADOW_REACH[detail]


## What `o` was authored with: read once and kept on it, stamped with its own id, because
## `duplicate()` copies meta: a copy (Regent's Rule's minimap duplicates the level's Environment and
## turns its effects off) is read afresh, never given the original's.
static func _kept(o: Object) -> Dictionary:
	if not o.has_meta(AUTHORED_META):
		return {}
	var a: Dictionary = o.get_meta(AUTHORED_META) as Dictionary
	return a if int(a.get("id", 0)) == o.get_instance_id() else {}


static func _authored_env(env: Environment) -> Dictionary:
	var a: Dictionary = _kept(env)
	if not a.is_empty():
		return a
	a = {"id": env.get_instance_id(), "ssao": env.ssao_enabled, "glow": env.glow_enabled, "ssil": env.ssil_enabled,
		"ssr": env.ssr_enabled, "sdfgi": env.sdfgi_enabled, "volumetric_fog": env.volumetric_fog_enabled}
	env.set_meta(AUTHORED_META, a)
	return a


static func _authored_light(light: Light3D) -> Dictionary:
	var a: Dictionary = _kept(light)
	if not a.is_empty():
		return a
	var sun: DirectionalLight3D = light as DirectionalLight3D
	a = {"id": light.get_instance_id(), "shadow": light.shadow_enabled,
		"reach": sun.directional_shadow_max_distance if sun != null else 0.0}
	light.set_meta(AUTHORED_META, a)
	return a


## The world's own environment (a scene with no WorldEnvironment node may set one in code).
static func _apply_world(world: World3D) -> void:
	if world != null and world.environment != null:
		apply_environment(world.environment)


static func _apply_group_visibility(n: Node3D) -> void:
	var a: Dictionary = _kept(n)
	if a.is_empty():
		a = {"id": n.get_instance_id(), "visible": n.visible}
		n.set_meta(AUTHORED_META, a)
	var authored: bool = bool(a["visible"])
	var shown: bool = detail == Detail.HIGH or (detail == Detail.MEDIUM and not n.is_in_group(GROUP_HIGH))
	n.visible = authored and shown


static func _apply_density(m: MultiMeshInstance3D) -> void:
	if m.multimesh == null:
		return
	var mm: MultiMesh = m.multimesh
	if detail == Detail.HIGH:
		mm.visible_instance_count = -1
	else:
		mm.visible_instance_count = maxi(1, int(float(mm.instance_count) * DENSITY[detail]))


## The authored values back on `n` (tests: a node taken out of a level whose meta must not linger).
static func authored(n: Object) -> Dictionary:
	return n.get_meta(AUTHORED_META, {}) as Dictionary
