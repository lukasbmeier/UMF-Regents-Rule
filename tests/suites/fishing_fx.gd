extends "res://tests/suite_base.gd"
## The `fishing_fx` suite (tests/test_runner.gd runs it; `-- --only=fishing_fx` runs it alone). Split
## verbatim from the one-file runner (REVIEW 0.23.1 C2): shared helpers are in tests/suite_base.gd.


func run() -> void:
	await _run_fishing_fx_tests()
	await _run_hud_layout_tests()



## THE HUD FITS THE WINDOW (DECISIONS #161). Luke's 860 x 445 game view had the fight gauge over
## the prompt; at 1280 x 720 they touched. Laid out in a viewport of each size: the gauge never covers
## the prompt or the hook-set bar, and stays on screen.
func _run_hud_layout_tests() -> void:
	print("== the HUD fits the window ==")
	for at: Vector2i in [Vector2i(860, 445), Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var view := SubViewport.new()
		view.size = at
		add_child(view)
		var hud: Control = (load("res://game/fishing/fishing_hud.tscn") as PackedScene).instantiate() as Control
		view.add_child(hud)
		await get_tree().process_frame
		await get_tree().process_frame
		var gauge: Rect2 = (hud.call("reel_gauge") as Control).get_global_rect()
		var prompt: Rect2 = (hud.get_node(^"Prompt") as Control).get_global_rect()
		var bar: Rect2 = (hud.get_node(^"Bar") as Control).get_global_rect()
		var screen := Rect2(Vector2.ZERO, Vector2(at))
		_check(not gauge.intersects(prompt) and not gauge.intersects(bar) and screen.encloses(gauge),
			"at %d x %d the fight gauge (%s) is on screen and clear of the prompt (%s) and the hook-set bar"
				% [at.x, at.y, gauge, prompt])
		view.free()

func _run_fishing_fx_tests() -> void:
	print("== fishing presentation: the line ==")
	var fx := FishingFx.new()
	fx.ripple_override = func(_at: Vector3, _strength: float) -> void: pass
	get_tree().root.add_child(fx)
	# No rod in hand: the line leaves from 1.5 m above the node, 2.5 m above the water here.
	fx.global_position = Vector3(0.0, 1.0, 0.0)
	var water := Vector3(0.0, 0.0, -40.0)
	fx.place_at(water)
	await get_tree().process_frame
	await get_tree().process_frame
	var pts: PackedVector3Array = fx.line_points()
	var under: int = 0
	var lying: int = 0
	for p: Vector3 in pts:
		if p.y < water.y:
			under += 1
		if is_equal_approx(p.y, water.y + FishingFx.LINE_ON_WATER):
			lying += 1
	_check(pts.size() > 40 and pts[0].is_equal_approx(Vector3(0.0, 2.5, 0.0))
			and Vector2(pts[-1].x, pts[-1].z).distance_to(Vector2(water.x, water.z)) < 0.01,
		"a 40 m line runs from the rod tip to the float, finely (%d points)" % pts.size())
	_check(under == 0, "and never under the lake (%d points under)" % under)
	_check(lying > pts.size() / 3 and pts[pts.size() / 10].y > water.y + 0.3,
		"it droops from the tip and lies on the water for much of its length (%d of %d points)" % [lying, pts.size()])
	fx.queue_free()
	await get_tree().process_frame
