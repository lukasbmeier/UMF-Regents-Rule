extends "res://tests/suite_base.gd"
## THE SHOWCASE AND THE LOGIN SCREEN (`-- --only=regents_showcase`; 2026-11-15), with no server and no renderer:
##   - the five moods load, each its own; a light's sky direction points where its elevation and azimuth say
##   - the valley: the camp's ground flat, the keep's hill and the ridges high, the lake's bowl under the water; trees,
##     rocks and grass placed; never in the lake, the keep's yard, a camera's line of sight, nor tall in a clearing;
##     whatever stands on the land stands on it as drawn (`ground_at`), NEGATIVE: not on the smooth shape
##   - a mood relights it: night shows the moon and the fireflies and hides the sun; day the reverse
##   - an actor: the look and the weapon in its hand, a one-shot played then back to its loop, a death held, a walk
##     that ends on the ground where it was sent; NEGATIVE: a clip its set has not is refused
##   - a shot's camera starts and ends where it says, swings by its orbit, and keeps real time through slow motion
##   - every lab shot's beat is a method of its lab, and every beat plays to its end: the swordsman's foes are down,
##     the imp is down, the archer is down, the wolves are down
##   - the login screen is the foundation's connect screen (its form, its buttons) with the valley built behind it while
##     it shows and freed when it hides; NEGATIVE: with the picture off, nothing is built; the game's Boot names it
## How it LOOKS is the labs' stills (windowed): `game/regents/tests/showcase_render.sh stills`.

const MOODS: Array[String] = ["dawn", "day", "golden", "dusk", "night"]
const ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const SWORD: PackedScene = preload("res://game/regents/combat/weapons/iron_sword.tscn")


func run() -> void:
	_run_moods()
	await _run_world()
	await _run_actor()
	_run_shot()
	await _run_labs()
	await _run_login()


func _run_moods() -> void:
	var names: Dictionary[String, bool] = {}
	for m: String in MOODS:
		var mood: ShowcaseMood = load("res://game/regents/showcase/moods/%s.tres" % m) as ShowcaseMood
		_check(mood != null, "the %s mood loads" % m)
		if mood != null:
			names[mood.display_name] = true
	_check(names.size() == MOODS.size(), "each mood has its own name (%s)" % [names.keys()])
	_check(ShowcaseMood.sky_direction(90.0, 0.0).distance_to(Vector3.UP) < 0.001, "a light at 90 deg is overhead")
	_check(ShowcaseMood.sky_direction(0.0, 0.0).distance_to(Vector3(0, 0, -1)) < 0.001, "azimuth 0 on the horizon is north (-Z)")
	_check(ShowcaseMood.sky_direction(0.0, 90.0).distance_to(Vector3(1, 0, 0)) < 0.001, "azimuth 90 is east (+X)")


func _run_world() -> void:
	var w := ShowcaseWorld.new()
	w.detail = 0.25
	w.mood = load("res://game/regents/showcase/moods/day.tres") as ShowcaseMood
	w.clear_paths = [[Vector3(30.0, 2.0, 30.0), Vector3(30.0, 2.0, -30.0), 5.0]]
	w.clearings = [Vector3(-30.0, 30.0, 10.0)]
	add_child(w)
	var flat: float = 0.0
	for p: Vector2 in [Vector2(0, 0), Vector2(5, 3), Vector2(-6, -4), Vector2(3, -7)]:
		flat = maxf(flat, absf(w.height_at(p.x, p.y)))
	_check(flat < 0.5, "the camp's ground is flat (highest %.2f m)" % flat)
	_check(w.height_at(w.keep_at.x, w.keep_at.y) > 15.0, "the keep stands on its hill (%.1f m)" % w.height_at(w.keep_at.x, w.keep_at.y))
	_check(w.height_at(w.lake_at.x, w.lake_at.y) < w.water_y - 2.0, "the lake's bed is under the water")
	var ridge: float = 0.0
	for a: int in range(24):
		var ang: float = TAU * float(a) / 24.0
		ridge = maxf(ridge, w.height_at(cos(ang) * 420.0, sin(ang) * 420.0))
	_check(ridge > 60.0, "the far ridges rise high (%.0f m)" % ridge)
	# Whatever stands on the land stands on it as drawn: at a grid point the drawn ground is the shape there; between
	# points on the lake's steep bowl, it is the triangle's, not the shape's (which the coarse grid cuts across).
	var gi: int = w._xs.size() / 2 + 7
	var gx: float = w._xs[gi]
	var gz: float = w._xs[gi + 3]
	_check(absf(w.ground_at(gx, gz) - w.height_at(gx, gz)) < 0.001, "at a grid point the drawn ground is the land's shape")
	var worst: float = 0.0
	for k: int in range(40):
		var p: Vector2 = w.lake_at + Vector2(cos(float(k)), sin(float(k))) * w.lake_radius * 1.0
		worst = maxf(worst, absf(w.ground_at(p.x, p.y) - w.height_at(p.x, p.y)))
	_check(worst > 0.05, "NEGATIVE: on the bowl the drawn ground is not the smooth shape (%.2f m apart at most)" % worst)
	_check(w.get_node_or_null(^"Land") != null and w.get_node_or_null(^"Keep") != null and w.get_node_or_null(^"Camp") != null,
		"the land, the keep and the camp are built")
	var trees: int = 0
	for k: String in w.placed:
		if k.begins_with("CommonTree") or k.begins_with("TallThick") or k.begins_with("TwistedTree"):
			trees += w.placed[k]
	_check(trees > 50, "trees are placed (%d)" % trees)
	_check(int(w.placed.get("Grass_Common_Short", 0)) > 100, "grass is placed (%d)" % int(w.placed.get("Grass_Common_Short", 0)))
	_check(not w._treeable(w.lake_at.x, w.lake_at.y, w.lake_at.length()), "NEGATIVE: no tree in the lake")
	_check(not w._treeable(w.keep_at.x + 5.0, w.keep_at.y, w.keep_at.length()), "NEGATIVE: no tree in the keep's yard")
	_check(w.in_view(32.0, 0.0) and not w.in_view(40.0, 0.0), "a camera's line of sight is clear, beside it is not")
	_check(w.in_clearing(-30.0, 30.0) and not w.in_clearing(-30.0, 45.0), "a clearing is where it was put")
	# A mood relights it.
	w.mood = load("res://game/regents/showcase/moods/night.tres") as ShowcaseMood
	_check(not w.sun.visible and w.moon.visible and w._fireflies.emitting, "night: the moon and the fireflies, no sun")
	w.mood = load("res://game/regents/showcase/moods/day.tres") as ShowcaseMood
	_check(w.sun.visible and not w.moon.visible and not w._fireflies.emitting, "day: the sun, no moon, no fireflies")
	_check(w.sun.global_basis.z.normalized().distance_to(ShowcaseMood.sky_direction(w.mood.sun_elevation, w.mood.sun_azimuth)) < 0.01,
		"the sun shines from where the mood puts it")
	w.queue_free()
	await get_tree().process_frame


func _run_actor() -> void:
	var a: ShowcaseActor = ShowcaseActor.make(ADVENTURER, 4, SWORD)
	add_child(a)
	_check(a.model != null and a.skeleton != null, "an actor wears its look")
	_check(a.held != null, "and holds its sword")
	_check(a.playing() == &"locomotion.idle", "it stands idle at first")
	var took: float = a.act(&"ability.40001")
	_check(took > 0.1 and a.playing() == &"ability.40001", "a swing plays once (%.2f s)" % took)
	a._process(took + 0.05)
	_check(a.playing() == &"locomotion.idle", "then it goes back to idle")
	_check(a.act(&"ability.99999") == 0.0 and a.playing() == &"locomotion.idle", "NEGATIVE: a clip its set has not is refused")
	a.act(&"react.death", true)
	a._process(5.0)
	_check(a._holding and a._once_left <= 0.0, "a death is held on its last frame")
	a.play(&"locomotion.idle")
	_check(not a._holding, "until it is told to play again")
	a.ground = func(x: float, _z: float) -> float: return x * 0.1
	a.position = Vector3.ZERO
	a.walk_to(Vector3(4.0, 0.0, 0.0), 2.0)
	_check(a.moving() and a.playing() == &"locomotion.walk", "a walk plays the walk")
	for i: int in range(30):
		a._process(0.1)
	_check(not a.moving() and a.position.distance_to(Vector3(4.0, 0.4, 0.0)) < 0.01,
		"and ends where it was sent, on the ground (%s)" % a.position)
	a.queue_free()
	await get_tree().process_frame


func _run_shot() -> void:
	var s := ShowcaseShot.new()
	s.eye_from = Vector3(10, 2, 0)
	s.eye_to = Vector3(10, 4, 0)
	s.at_from = Vector3.ZERO
	s.at_to = Vector3.ZERO
	s.fov_from = 40.0
	s.fov_to = 60.0
	var p0: Array = s.at_time(0.0)
	var p1: Array = s.at_time(1.0)
	_check((p0[0] as Vector3).distance_to(s.eye_from) < 0.001 and (p1[0] as Vector3).distance_to(s.eye_to) < 0.001,
		"a shot's camera starts and ends where it says")
	_check(is_equal_approx(float(p0[2]), 40.0) and is_equal_approx(float(p1[2]), 60.0), "and its lens with it")
	s.eye_to = s.eye_from
	s.orbit_deg = 90.0
	var o: Vector3 = s.at_time(1.0)[0]
	_check(o.distance_to(Vector3(0, 2, -10)) < 0.01, "an orbit swings it round what it looks at (%s)" % o)


func _run_labs() -> void:
	for lab_name: String in ["vista_lab", "battle_lab"]:
		var lab: ShowcaseStage = (load("res://game/regents/showcase/%s.tscn" % lab_name) as PackedScene).instantiate() as ShowcaseStage
		_check(lab != null and not lab.shots.is_empty(), "%s has shots" % lab_name)
		if lab == null:
			continue
		for s: ShowcaseShot in lab.shots:
			_check(s.seconds > 0.0 and s.mood != null, "%s: %s has a length and a mood" % [lab_name, s.title])
			_check(s.beat == &"" or lab.has_method(s.beat), "%s: %s's beat %s is a method of the lab" % [lab_name, s.title, s.beat])
		lab.detail = 0.25
		add_child(lab)
		await get_tree().process_frame
		_check(lab._mode == "", "%s: the test runner's own arguments are no way to run it" % lab_name)
		var sunk: ShowcaseShot = lab.shots[0].duplicate() as ShowcaseShot
		sunk.eye_from = Vector3(1.0, -30.0, -68.0)
		lab.shots[0] = sunk
		lab._start_shot(0)
		_check(lab.camera.global_position.y >= lab.world.ground_at(1.0, -68.0) + 0.5,
			"%s: a shot's camera set under the land is lifted over it (%.1f m)" % [lab_name, lab.camera.global_position.y])
		if lab_name == "battle_lab":
			await _run_battle_beats(lab as BattleLab)
		lab.queue_free()
		Engine.time_scale = 1.0
		await get_tree().process_frame


## Each beat played to its end on the stage's clock (no renderer: the effects build, nothing is drawn).
func _run_battle_beats(lab: BattleLab) -> void:
	var outcomes: Dictionary[StringName, Array] = {
		&"steel": [lab.warrior, lab.axeman],
		&"fire": [lab.imp],
		&"arrows": [lab.archer],
		&"pack": [lab.wolves[0], lab.wolves[1]],
	}
	for i: int in range(lab.shots.size()):
		var s: ShowcaseShot = lab.shots[i]
		lab._start_shot(i)
		# Held on this shot (the lab would go on to the next when its time is up); the beat's clock still runs.
		lab._paused = true
		if not outcomes.has(s.beat):
			continue
		for k: int in range(int(s.seconds * s.time_scale / 0.1) + 30):
			lab._process(0.1 * Engine.time_scale)
			for a: ShowcaseActor in lab._all:
				a._process(0.1)
			# The effects keep their own clocks (a missile lands on its own): stepped with the rest.
			for fx: Variant in lab._spawned.duplicate():
				if is_instance_valid(fx) and fx is VfxEffect:
					(fx as VfxEffect)._process(0.1)
		var down: bool = true
		for a: Variant in outcomes[s.beat]:
			down = down and (a as ShowcaseActor)._holding and (a as ShowcaseActor).visible
		_check(down, "battle: %s plays to its end, its foes down" % s.title)
		_check(lab._cues.is_empty(), "battle: %s's timeline ran out" % s.title)
	# A shot resets the stage: no one left from the last.
	lab._start_shot(0)
	_check(not lab.imp.visible and lab.hero.visible and lab.warrior.visible and not lab.warrior._holding,
		"NEGATIVE: a new shot starts clean (the imp gone, the skeleton up again)")


func _run_login() -> void:
	var game: String = FileAccess.get_file_as_string("res://game/regents/regents_game.tscn")
	_check(game.contains("res://game/regents/ui/login/regents_login.tscn"), "the game's Boot opens with Regent's Rule's login screen")
	var screen: RegentsLogin = (load("res://game/regents/ui/login/regents_login.tscn") as PackedScene).instantiate() as RegentsLogin
	_check(screen is ConnectScreen, "the login screen is the foundation's connect screen")
	add_child(screen)
	await get_tree().process_frame
	for n: String in ["Host", "Name", "AutoConnect", "Connect", "Quit", "Status", "Settings", "Character"]:
		_check(screen.get_node_or_null("%" + n) != null, "it keeps the form's %s" % n)
	_check(not screen.visible and not screen.has_picture(), "hidden, it builds nothing")
	screen.open("127.0.0.1", "Tester", false)
	await get_tree().process_frame
	_check(screen.visible and screen.has_picture(), "shown, the valley is built behind the form")
	var backdrop: LoginBackdrop = screen._viewport.get_child(0) as LoginBackdrop
	_check(backdrop != null and backdrop.world != null and backdrop.camera != null, "the valley has its world and its camera")
	_check(screen._viewport.own_world_3d, "in a world of its own (never the game's)")
	screen.visible = false
	await get_tree().process_frame
	_check(not screen.has_picture(), "hidden again (the game began), the valley is freed")
	_check(screen._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "and its view stops drawing")
	screen.queue_free()
	var plain: RegentsLogin = (load("res://game/regents/ui/login/regents_login.tscn") as PackedScene).instantiate() as RegentsLogin
	plain.live_backdrop = false
	add_child(plain)
	await get_tree().process_frame
	plain.open("127.0.0.1", "Tester", false)
	await get_tree().process_frame
	_check(plain.visible and not plain.has_picture(), "NEGATIVE: with the picture off, nothing is built")
	plain.queue_free()
	await get_tree().process_frame
