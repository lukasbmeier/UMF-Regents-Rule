extends "res://tests/suite_base.gd"
## The `camera` suite (tests/test_runner.gd runs it; `-- --only=camera` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	_run_camera_tests()
	await get_tree().process_frame   # the runner awaits run(): always a coroutine



## THE CONTRACT, not the content. A character says "I am running"; this suite proves that turns
## into the right clip, that a character missing a clip still animates, and that a set naming a
## clip its library does not have is caught here rather than on the frame the player dies.
## The wheel zoom. Presentation, but a boom that ignores its limits puts the camera inside the
## character or out in the next room, and nothing else in the suite ever moves it.
func _run_camera_tests() -> void:
	print("== CameraRig zoom ==")
	var cfg := CameraRigConfig.new()
	cfg.first_person = false
	cfg.boom_length = 4.0
	cfg.boom_min = 1.5
	cfg.boom_max = 7.0
	cfg.zoom_step = 0.5
	cfg.zoom_smoothing = 0.0   # snap, so a test does not have to wait out an ease
	var rig := CameraRig.new()
	rig.config = cfg
	get_tree().root.add_child(rig)
	_check(is_equal_approx(rig._zoom(0.016), 4.0), "the boom starts where the preset put it")

	rig._input = LocalInputComponent.new()   # the rig only zooms for the entity that owns it
	var wheel_in := InputEventAction.new()
	wheel_in.action = &"camera_zoom_in"
	wheel_in.pressed = true
	for i: int in range(3):
		rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), 2.5),
		"three notches in pull it to 2.5 m (%.2f)" % rig._zoom(0.016))
	for i: int in range(10):
		rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), cfg.boom_min),
		"and it stops at boom_min rather than ending up inside the character (%.2f)"
			% rig._zoom(0.016))

	var wheel_out := InputEventAction.new()
	wheel_out.action = &"camera_zoom_out"
	wheel_out.pressed = true
	for i: int in range(40):
		rig._unhandled_input(wheel_out)
	_check(is_equal_approx(rig._zoom(0.016), cfg.boom_max),
		"pushing out stops at boom_max (%.2f)" % rig._zoom(0.016))
	# While a genre has the mouse (a reel being wound: look damped), the wheel is not the camera's.
	rig._input.look_scale = 0.1
	var held_at: float = rig._zoom(0.016)
	for i: int in range(3):
		rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), held_at),
		"with the mouse lent to the game (look_scale 0.1) the wheel does not zoom (%.2f)" % rig._zoom(0.016))
	rig._input.look_scale = 1.0
	rig._unhandled_input(wheel_in)
	_check(rig._zoom(0.016) < held_at, "and it zooms again once the mouse is the camera's")
	cfg.first_person = true
	var before: float = rig._zoom(0.016)
	rig._unhandled_input(wheel_in)
	_check(is_equal_approx(rig._zoom(0.016), before), "a first-person rig has no boom to zoom")
	rig._input.free()
	rig.queue_free()

	# IN FIRST PERSON, ONE'S OWN BODY (DECISIONS #223): not drawn for its player (its shadow still
	# is), and it faces where they look, standing still too. Third person: drawn, facing free.
	for fp: bool in [true, false]:
		var ent := SpaceTimeEntity.new()
		ent.is_local_authority = true
		var visual := Node3D.new()
		visual.name = "Visual"
		ent.add_child(visual)
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		visual.add_child(mesh)
		get_tree().root.add_child(ent)
		var input := LocalInputComponent.new()
		ent.add_runtime_component(input)
		input.set_physics_process(false)
		var own := CameraRig.new()
		var own_cfg := CameraRigConfig.new()
		own_cfg.first_person = fp
		own.config = own_cfg
		own._entity = ent
		own._input = input
		own.apply_first_person()
		if fp:
			_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "first person: its own model is not drawn for its player, only its shadow")
			_check(input.sample().face, "and its body faces where they look, standing still (the frame says face)")
		else:
			_check(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not input.sample().face,
				"third person: its model drawn, its facing its own")
		own.free()
		ent.queue_free()
