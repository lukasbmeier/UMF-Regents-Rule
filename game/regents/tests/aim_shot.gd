extends Node3D
## THE AIM, SHOWN (PROGRESS step 60; windowed, no server): the adventurer drawing the bow and casting, as the game
## poses them (the real animation tree: the aim poses over the upper body, the legs idle), seen from the game's
## camera (over the right shoulder) with the crosshair at the screen's center and a red ball on what is aimed at.
## For each pose it writes `<out>/<pose>_off.png` (as the clip leaves it), then the upper body turned (`AimTwist`)
## to the crosshair (`_on.png`) and to a Tab target well to the left and to the right (`_left.png`, `_right.png`),
## and prints how far off the red ball the pose's aim line still points.
##
## TO ADJUST where a pose ends up pointing: the numbers are `CombatLook`'s "pose points" on
## `adventurer.tscn` (Components/CombatLook): this reads them from there. If it prints "2.0 deg to the left", raise
## that pose's x by 2; "to the right", lower it; "over", raise y; "under", lower it. Run it again.
##   godot --path . res://game/regents/tests/aim_shot.tscn -- <out dir>

## [name, the held item's scene, the upper-body pose, where in it (0..1; -1: looping), the two bones whose line shows
## where the pose aims (measured, never used to turn it), what it is aimed with (`CombatLook.AIM_*`)]
const CASES: Array = [
	["bow_aim", "res://game/regents/content/item/yew_bow.tres", &"pose.bow_aim", -1.0, [&"hand_r", &"hand_l"], &"bow"],
	["bow_draw_half", "res://game/regents/content/item/yew_bow.tres", &"pose.bow_draw", 0.5, [&"hand_r", &"hand_l"], &"bow"],
	["spell_cast", "res://game/regents/content/item/yew_staff.tres", &"pose.spell_cast", -1.0, [&"upperarm_l", &"hand_l"], &"cast"],
	["spell_channel", "res://game/regents/content/item/yew_staff.tres", &"pose.spell_channel", -1.0, [&"upperarm_l", &"hand_l"], &"channel"],
]
## A Tab target this far to the left and to the right of straight ahead (degrees), this far off (m), its middle this high.
const SIDE_LEFT_DEG: float = 40.0
const SIDE_RIGHT_DEG: float = 45.0
const SIDE_AWAY_M: float = 9.0
const SIDE_HEIGHT_M: float = 0.5
## [name, the foe's character, its swing]: its cut drawn with its trail.
const SWINGS: Array = [
	["warrior", "res://game/regents/content/character/skeleton_warrior.tres", 40017],
	["axeman", "res://game/regents/content/character/skeleton_axeman.tres", 40021],
	["wolf", "res://game/regents/content/character/wolf.tres", 40029],
]
## The crosshair is on the ground this far ahead of the player (the camera's pitch follows).
const AIM_AHEAD_M: float = 12.0

var out_dir: String = "user://"
var _measured: Vector2 = Vector2.ZERO
var _line: Array = []
var _skel: Skeleton3D = null
var _target: Vector3 = Vector3.ZERO


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	get_window().size = Vector2i(960, 720)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var plane_shape := WorldBoundaryShape3D.new()
	shape.shape = plane_shape
	ground.add_child(shape)
	var gmesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	gmesh.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.55, 0.25)
	gmesh.material_override = gm
	ground.add_child(gmesh)
	add_child(ground)
	# The crosshair: a dot at the screen's center, as the HUD draws it.
	var dot := ColorRect.new()
	dot.color = Color.WHITE
	dot.size = Vector2(6, 6)
	dot.position = Vector2(get_window().size) * 0.5 - Vector2(3, 3)
	add_child(dot)
	for c: Array in CASES:
		await _case(c)
	for s: Array in SWINGS:
		await _swing(s)
	await _flights()
	AppExit.quit(get_tree(), 0)


## A foe's swing with its trail (`SwingTrail`), shot as the blow lands: the model's own weapon found by its hand.
func _swing(s: Array) -> void:
	var def: EntityDefinition = load(String(s[1])) as EntityDefinition
	var who := Node3D.new()
	add_child(who)
	var vis := Node3D.new()
	vis.name = "Visual"
	who.add_child(vis)
	var man := Mannequin.new()
	man.name = "Model"
	man.definition = def
	vis.add_child(man)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(2.6, 1.5, -2.8)
	cam.look_at(Vector3(0.0, 0.9, -0.6))
	cam.make_current()
	var swing := SwingTrail.new()
	who.add_child(swing)
	swing.entity = who
	var trail := RibbonTrail.new()
	trail.lifetime_s = swing.lifetime_s
	trail.color = swing.foe_color
	add_child(trail)
	var a: AbilityDef = ContentLibrary.find(&"ability", int(s[2])) as AbilityDef
	var window: Vector2i = SwingTrail.cut_window(a, 0, swing.from_wind_up, swing.after_hit_ms)
	man.play(StringName("ability.%d" % a.id), false)
	var edge: Array = swing.blade_now()
	print("TRAIL %s: the blade is %s (%.2f m of it drawn)" % [s[0], "found" if edge.size() == 2 else "NOT FOUND", (edge[0] as Vector3).distance_to(edge[1]) if edge.size() == 2 else 0.0])
	var t: float = 0.0
	while t * 1000.0 < float(a.wind_up_ms) + 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		edge = swing.blade_now()
		if edge.size() == 2 and t * 1000.0 >= float(window.x):
			trail.add_blade(edge[0], edge[1])
	print("TRAIL %s: %d edges of it showing as the blow lands" % [s[0], trail.sample_count()])
	await _shot("%s/swing_%s.png" % [out_dir, s[0]])
	who.queue_free()
	trail.queue_free()
	cam.queue_free()
	await get_tree().process_frame


## An arrow, a bolt and a fireball in flight across the view, each with its trail, then the fireball's burst.
func _flights() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.6, 6.0)
	cam.look_at(Vector3(0.0, 1.4, 0.0))
	cam.make_current()
	var shots: Array[Node3D] = []
	var paths: Array[String] = ["res://game/regents/combat/arrow_look.tscn", "res://game/regents/combat/bolt_look.tscn", "res://game/regents/combat/fireball_look.tscn"]
	for i: int in range(paths.size()):
		var holder := Node3D.new()
		add_child(holder)
		holder.position = Vector3(-4.0, 2.2 - float(i) * 0.8, 0.0)
		holder.rotation.y = -PI / 2.0   # flying toward +X: a shot's nose is its -Z
		holder.add_child((load(paths[i]) as PackedScene).instantiate())
		shots.append(holder)
	var t: float = 0.0
	while t < 0.5:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		t += dt
		for h: Node3D in shots:
			h.position.x += 14.0 * dt
	await _shot("%s/flights.png" % out_dir)
	shots[2].queue_free()   # the fireball ends: its burst
	for i: int in range(5):
		await get_tree().process_frame
	await _shot("%s/burst.png" % out_dir)
	for h: Node3D in shots:
		if is_instance_valid(h):
			h.queue_free()
	cam.queue_free()
	await get_tree().create_timer(1.0).timeout


func _case(c: Array) -> void:
	var def: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	# The player, as the spawner builds it: Visual/Model facing -Z, the driver on its set.
	var who := Node3D.new()
	add_child(who)
	var vis := Node3D.new()
	vis.name = "Visual"
	who.add_child(vis)
	var model: Node3D = def.visual_variants[0].instantiate() as Node3D
	model.name = "Model"
	vis.add_child(model)
	model.rotation.y = deg_to_rad(def.visual_yaw_deg)
	model.scale = Vector3.ONE * def.visual_scale
	var driver := AnimationDriverComponent.new()
	driver.animation_set = def.animation_set
	who.add_child(driver)
	driver.entity = who
	driver.set_process(false)
	if not driver._install():
		print("AIM %s: no tree" % c[0])
		return
	_skel = SkillingLook.skeleton_of(who)
	var item: ItemDef = load(String(c[1])) as ItemDef
	var held: HeldItem = HeldItem.attach(_skel, item.held_scene)
	if held != null:
		held.driver = driver
	# The game's camera: the rig at the pivot, the camera over the right shoulder, pitched onto a point ahead.
	var cfg: CameraRigConfig = def.camera_rig
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = cfg.fov
	var pivot := Vector3(0.0, cfg.pivot_height, 0.0)
	var pitch: float = -atan2(cfg.pivot_height, AIM_AHEAD_M + cfg.boom_length)
	cam.position = pivot + Vector3(cfg.shoulder_offset, 0.0, cfg.boom_length).rotated(Vector3.RIGHT, pitch)
	cam.rotation = Vector3(pitch, 0.0, 0.0)
	cam.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Where the crosshair is: the combat component's own ray.
	var combat := CombatComponent.new()
	who.add_child(combat)
	combat.entity = who
	combat.set_process(false)
	_target = combat.crosshair_point()
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	ball.mesh = sphere
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0.1, 0.1)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = red
	add_child(ball)
	ball.global_position = _target
	_line = c[4]
	_skel.skeleton_updated.connect(_measure)
	var pose: StringName = c[2]
	var at: float = c[3]
	# Off: the pose as the clip leaves it.
	await _hold(driver, pose, at, 40)
	if _line.is_empty():
		_print_arms(String(c[0]))
	else:
		print("AIM %s off: the line points %.1f deg to the %s of the crosshair's point and %.1f deg %s it"
			% [c[0], absf(rad_to_deg(_measured.x)), "left" if _measured.x > 0.0 else "right", absf(rad_to_deg(_measured.y)), "under" if _measured.y > 0.0 else "over"])
	await _shot("%s/%s_off.png" % [out_dir, c[0]])
	# On: the upper body turned to the crosshair, then to a Tab target to each side: the game's own numbers
	# (`CombatLook` on adventurer.tscn) and the game's own turner.
	if not _line.is_empty():
		var adventurer: Node = (load("res://game/regents/adventurer.tscn") as PackedScene).instantiate()
		var look: CombatLook = adventurer.get_node(^"Components/CombatLook") as CombatLook
		var points: Vector2 = look.pose_points(StringName(c[5]))
		var twist := AimTwist.new()
		_skel.add_child(twist)
		_skel.move_child(twist, 0)
		twist.muzzle_bone = look.bow_muzzle_bone if StringName(c[5]) == CombatLook.AIM_BOW else look.cast_muzzle_bone
		adventurer.free()
		var side := Vector3(0.0, SIDE_HEIGHT_M, -SIDE_AWAY_M)
		for t: Array in [["on", _target], ["left", side.rotated(Vector3.UP, deg_to_rad(SIDE_LEFT_DEG))], ["right", side.rotated(Vector3.UP, -deg_to_rad(SIDE_RIGHT_DEG))]]:
			_target = t[1]
			ball.global_position = _target
			twist.aim(_target, Vector3.FORWARD, points)
			await _hold(driver, pose, at, 40)
			print("AIM %s %s: still %.1f deg to the %s, %.1f deg %s (turned %.1f deg round, %.1f up; the shot leaves the hand %.2f m from the chest's middle)"
				% [c[0], t[0], absf(rad_to_deg(_measured.x)), "left" if _measured.x > 0.0 else "right", absf(rad_to_deg(_measured.y)), "under" if _measured.y > 0.0 else "over",
					rad_to_deg(twist.turned.x), -rad_to_deg(twist.turned.y), twist.muzzle.distance_to(Vector3(0.0, CombatComponent.MUZZLE_HEIGHT_M, 0.0))])
			await _shot("%s/%s_%s.png" % [out_dir, c[0], t[0]])
	_skel.skeleton_updated.disconnect(_measure)
	who.queue_free()
	cam.queue_free()
	ball.queue_free()
	await get_tree().process_frame


## Hold `pose` on the upper body for `frames` frames, the tree advanced as the driver advances it.
func _hold(driver: AnimationDriverComponent, pose: StringName, at: float, frames: int) -> void:
	for i: int in range(frames):
		driver.hold_upper_pose(pose, 1.0, at)
		driver._update_upper_pose(1.0 / 60.0)
		driver._tree.advance(1.0 / 60.0)
		await get_tree().process_frame


## After the skeleton's modifiers: how far the aim line points from the crosshair's point (x: yaw, positive to the
## left; y: positive under it).
func _measure() -> void:
	if _line.size() != 2 or _skel == null:
		return
	var a: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(String(_line[0]))).origin
	var b: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(String(_line[1]))).origin
	var left: Vector2 = AimTwist.turn_for(b - a, _target - b, PI, PI)
	_measured = Vector2(-left.x, -left.y)


## With no line named yet: where each arm points, to choose one.
func _print_arms(name_: String) -> void:
	for side: String in ["l", "r"]:
		var a: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("upperarm_" + side)).origin
		var b: Vector3 = _skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone("hand_" + side)).origin
		var d: Vector3 = b - a
		print("AIM %s arm_%s: shoulder to hand %s (%.2f m long; forward is -Z)" % [name_, side, d, d.length()])


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)
