extends "res://game/fishing/tests/fishing_suite_base.gd"
## FISHING'S `fishing_world` suite (`-- --only=fishing_world` runs it alone), run because shared/game.json
## lists fishing. Moved from tests/suites/. Shared helpers: game/fishing/tests/fishing_suite_base.gd.


func run() -> void:
	await _run_fishing_world_tests()



## THE LAKE AROUND THE FISHING (DECISIONS #168-#171): the round's time of day and weather (named,
## favouring what they favour, drawn on the sky), other players' fights shown, the journal and the
## records, the rival's name, and the HUD's journal and keys.
class FakeConditionsRow extends RefCounted:
	var world_id: int = 0
	var round: int
	var time_of_day: int
	var weather: int
	func _init(r: int, t: int, w: int) -> void:
		round = r
		time_of_day = t
		weather = w


class FakeFishLineRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var spot: String = "dock_end"
	var x: float
	var z: float
	var challenge_id: int = 0
	func _init(eid: int, px: float, pz: float) -> void:
		entity_id = eid
		x = px
		z = pz


class FakeShowRow extends RefCounted:
	var entity_id: int
	var world_id: int = 0
	var state: int
	var load: float
	var line_m: float
	func _init(eid: int, s: int, l: float, m: float) -> void:
		entity_id = eid
		state = s
		load = l
		line_m = m


func _run_fishing_world_tests() -> void:
	print("== the lake around the fishing ==")
	# --- the conditions, as data ------------------------------------------------------------
	_check(str(FishingData.time_of_day(0).get("id")) == "dawn" and FishingData.times_count() == 4
		and str(FishingData.weather(2).get("id")) == "rain" and FishingData.time_of_day(9).is_empty(),
		"the times of day and the weathers come from fishing.json, in order")
	_check(is_equal_approx(FishingData.likes("fish_whoa", PackedStringArray(["night", "fog"])), 3.6)
		and FishingData.likes("fish_trash", PackedStringArray(["night"])) == 1.0,
		"a like multiplies, and nothing liked is 1 (the server's rule, for showing)")
	var fav: PackedStringArray = FishingData.favoured_by(PackedStringArray(["night", "fog"]), 3)
	_check(fav == PackedStringArray(["strange fish", "Channel Catfish", "things that should not be here"]),
		"what a foggy night favours, most first, in words (%s)" % ", ".join(fav))
	var cond := FishingConditions.new()
	add_child(cond)
	var heard: Array[int] = [0]
	cond.changed.connect(func() -> void: heard[0] += 1)
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.INSERTED, FishingConditions.TABLE, null,
		FakeConditionsRow.new(3, 2, 2)))
	_check(cond.known and cond.round_number == 3 and cond.words() == "Dusk, rain" and heard[0] == 1,
		"the server's row is read and named (%s)" % cond.words())
	_check(cond.describe().begins_with("Dusk, rain: ") and cond.describe().contains("biting")
		and cond.tags() == PackedStringArray(["dusk", "rain"]),
		"and said with what it favours (%s)" % cond.describe())
	EntityRegistry.global_row_event.emit(RowEvent.make(RowEvent.Kind.UPDATED, FishingConditions.TABLE, null,
		FakeConditionsRow.new(3, 2, 2)))
	_check(heard[0] == 1, "the same conditions again are not news")

	# --- the sky shows them -----------------------------------------------------------------
	var stage := Node3D.new()
	add_child(stage)
	var sun := DirectionalLight3D.new()
	stage.add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.sky = Sky.new()
	we.environment.sky.sky_material = ProceduralSkyMaterial.new()
	we.environment.fog_density = 0.0016   # the lakeside's own
	var original_env: Environment = we.environment
	stage.add_child(we)
	var sky: SkyDirector = (load("res://game/world/sky_director.tscn") as PackedScene).instantiate() as SkyDirector
	stage.add_child(sky)
	sky._find_level()
	var looks_missing: Array[String] = []
	for i: int in range(FishingData.times_count()):
		var id: String = str(FishingData.time_of_day(i).get("id"))
		if not sky.times.has(id):
			looks_missing.append(id)
	for i: int in range(8):
		var w: Dictionary = FishingData.weather(i)
		if not w.is_empty() and not sky.weathers.has(str(w.get("id"))):
			looks_missing.append(str(w.get("id")))
	_check(looks_missing.is_empty(), "every time of day and weather in fishing.json has a look in sky_director.tscn %s" % str(looks_missing))
	cond.set_conditions(4, 3, 2)   # night, rain
	sky.snap()
	var night: SkyLook = sky.times["night"]
	var rain: WeatherLook = sky.weathers["rain"]
	_check(is_equal_approx(sun.light_energy, night.sun_energy * rain.sun_energy_mult) and sky._rain.emitting
		and is_equal_approx(we.environment.fog_density, night.fog_density + rain.fog_density_add),
		"a rainy night: the moon's light under cloud, the rain falling, the fog thicker")
	_check(we.environment != original_env and original_env.fog_density != we.environment.fog_density,
		"on the director's own copy of the environment, not the level's")
	cond.set_conditions(2, 1, 0)   # day, clear
	sky.snap()
	var day: SkyLook = sky.times["day"]
	_check(not sky._rain.emitting and is_equal_approx(sun.light_energy, day.sun_energy) and sun.global_basis.z.y > 0.3,
		"a clear day: no rain, the full sun, high in the sky")
	sky._phase = SessionComponent.Phase.PLAYING
	sky._phase_ends_usec = ClockSync.server_usec() + int(Rules.phase_seconds(0, SessionComponent.Phase.PLAYING) * 0.25 * 1e6)
	_check(is_equal_approx(snappedf(sky.round_progress(), 0.01), 0.75) and
		is_equal_approx(float(sky.target()["elevation"]), lerpf(day.sun_elevation_deg, day.sun_elevation_end_deg, sky.round_progress())),
		"the sun moves through the round (%.2f of the way, at %.1f degrees)" % [sky.round_progress(), float(sky.target()["elevation"])])
	stage.queue_free()
	cond.queue_free()

	# --- another player's fight, shown -------------------------------------------------------
	var reg: Node = _autoload("EntityRegistry")
	var spawner: Node = _autoload("EntitySpawner")
	var level: Node3D = (load(LAKESIDE_SCENE) as PackedScene).instantiate() as Node3D
	get_tree().root.add_child(level)
	var prev_local: int = reg.local_entity_id
	var prev_ready: bool = spawner._world_ready
	spawner.register_definition(load(FISHER_DEF) as EntityDefinition)
	spawner.world_root_path = spawner.get_path_to(level.get_node(^"WorldRoot"))
	spawner._world_ready = true
	reg.local_entity_id = 5501
	var them: int = 5502
	for eid: int in [5501, them]:
		_buffer_player_rows(reg, eid)
		spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(eid, 0)))
	for i: int in range(4):
		await get_tree().process_frame
	var other: SpaceTimeEntity = spawner.get_entity_node(them) as SpaceTimeEntity
	var fishing: FishingComponent = other.find_component(FishingComponent) as FishingComponent
	var feedback: FishingFeedback = other.find_component(FishingFeedback) as FishingFeedback
	other.global_position = Vector3(0.0, 0.9, 30.0)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, FishingComponent.LINE_TABLE, null, FakeFishLineRow.new(them, 0.0, 10.0)))
	for i: int in range(20):
		await get_tree().process_frame
	_check(fishing.line_out() and fishing.shown_fight().is_empty() and feedback.heave_shown() == 0.0,
		"their line is out with nothing on it: they wait")
	var show := FakeShowRow.new(them, FishingComponent.Shown.SWEET, 0.8, 8.0)
	reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, FishingComponent.SHOW_TABLE, null, show))
	# A report is reached over the time between reports (#181): longer than that, then look.
	await get_tree().create_timer(FishingFeedback.SHOWN_SPAN_SEC + 0.15).timeout
	var fx: FishingFx = feedback.fx()
	var float_at: Vector3 = fx.float_position()
	var shore := Vector3(other.global_position.x, float_at.y, other.global_position.z)
	_check(fishing.shown_fight().get("state") == FishingComponent.Shown.SWEET and fx.state() == FishingFx.State.FIGHTING,
		"their fight arrives, and is drawn as a fight")
	_check(feedback.heave_shown() > 0.5 * FishingFeedback.HEAVE_TOP,
		"they heave with the load they show (%.2f of %.2f)" % [feedback.heave_shown(), FishingFeedback.HEAVE_TOP])
	_check(absf(float_at.distance_to(shore) - 8.0) < 1.5,
		"their float is dragged in to the metres they show (%.1f m out)" % float_at.distance_to(shore))
	_check(fx.tell_visible() and FishingFeedback.tell_shown(FishingComponent.Shown.SWEET) == FishingFx.TELL_PERFECT
		and FishingFeedback.tell_shown(FishingComponent.Shown.RUNNING) == FishingFx.TELL_RUN,
		"with the tell ring in the colour of what they show")
	# THEIR HEAVE MOVES EVERY FRAME (DECISIONS #181). Reports half a second apart, as the rival's
	# are: between two, the pose is on its way from one to the next, never holding still and never
	# jumping when a row lands (Luke: "the rival animations look like a slideshow").
	var last_show: FakeShowRow = show
	var frames_between: Array = []
	for load: float in [0.3, 0.9, 0.4]:
		var next_show := FakeShowRow.new(them, FishingComponent.Shown.BAND, load, 8.0)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, FishingComponent.SHOW_TABLE, last_show, next_show))
		last_show = next_show
		var seen: Array[float] = []
		var until: int = Time.get_ticks_msec() + 500
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			seen.append(feedback.heave_shown())
		frames_between.append(seen)
	# From 0.3's heave to 0.9's, starting at the last frame before the report landed.
	var rise: Array = [(frames_between[0] as Array).back()] + (frames_between[1] as Array)
	var low: float = FishingFeedback.HEAVE_TOP * (1.0 - pow(1.0 - 0.3, 2.0))
	var high: float = FishingFeedback.HEAVE_TOP * (1.0 - pow(1.0 - 0.9, 2.0))
	var moving: int = 0
	var biggest_step: float = 0.0
	var reached_at: int = -1
	for i: int in range(1, rise.size()):
		var step: float = absf(float(rise[i]) - float(rise[i - 1]))
		biggest_step = maxf(biggest_step, step)
		if reached_at < 0 and absf(float(rise[i]) - high) < 0.01:
			reached_at = i
		elif reached_at < 0 and step > 1e-6:
			moving += 1
	var climbing: int = reached_at if reached_at > 0 else rise.size()
	_check(rise.size() > 10 and climbing > 5 and moving >= int(0.9 * float(climbing - 1)),
		"between two of their reports the heave moves on every frame until it gets there (%d of %d frames)"
			% [moving, climbing - 1])
	_check(biggest_step < 0.5 * (high - low),
		"and never jumps when a report lands (largest step %.3f of a %.3f climb)" % [biggest_step, high - low])
	_check(reached_at > 0, "and reaches what they reported before the next report (%.3f, want %.3f)"
		% [float(rise[rise.size() - 1]), high])
	# A run reports the same load again and again: the rod strains rather than standing still.
	for i: int in range(2):
		var run_show := FakeShowRow.new(them, FishingComponent.Shown.RUNNING, 0.4, 8.0)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.UPDATED, FishingComponent.SHOW_TABLE, last_show, run_show))
		last_show = run_show
		await get_tree().create_timer(0.4).timeout
	var still: int = 0
	var run_frames: int = 0
	var before: float = feedback.heave_shown()
	var run_until: int = Time.get_ticks_msec() + 400
	while Time.get_ticks_msec() < run_until:
		await get_tree().process_frame
		run_frames += 1
		if absf(feedback.heave_shown() - before) < 1e-6:
			still += 1
		before = feedback.heave_shown()
	_check(run_frames > 10 and still <= run_frames / 10,
		"while their catch runs at a steady load, the rod strains: still on %d of %d frames" % [still, run_frames])
	reg._on_row_event(RowEvent.make(RowEvent.Kind.DELETED, FishingComponent.SHOW_TABLE, last_show, null))
	for i: int in range(90):
		await get_tree().process_frame
	_check(fishing.shown_fight().is_empty() and feedback.heave_shown() < 0.05,
		"when they stop showing a fight, the heave comes back down (%.2f)" % feedback.heave_shown())

	# OUR fight is reported, a few times a second and at once on a change.
	var mine: FishingComponent = (spawner.get_entity_node(5501) as SpaceTimeEntity).find_component(FishingComponent) as FishingComponent
	mine._fight = FightSim.new(FightSim.params_for(0, 0, 0, FishingData.HookSet.GOOD, false),
		FightSim.profile_of("bluegill"), 7, 14.0, true)
	mine._report_fight()
	var first: int = mine._show_sent_msec
	mine._report_fight()
	_check(first >= 0 and mine._show_sent_msec == first and mine._show_sent_state == FishingComponent.shown_of(mine._fight),
		"our fight is reported, and not again within %.1f s while it shows the same" % FishingComponent.SHOW_INTERVAL_SEC)
	mine._show_sent_state = -9
	mine._report_fight()
	_check(mine._show_sent_state == FishingComponent.shown_of(mine._fight), "a change is reported at once")
	mine._fight = null

	# --- the journal and the records ----------------------------------------------------------
	var catches: Array = [[1, 5501, "bluegill", 0.31], [2, 5501, "bluegill", 0.42], [3, 5501, "golden_koi", 6.2],
		[4, them, "bluegill", 0.9], [5, them, "carp", 8.0]]
	for c: Array in catches:
		var row := FakeCatchRow.new(int(c[0]), int(c[1]), 1, 1, str(c[2]), float(c[3]))
		row.coins = 10 * int(c[0])
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null, row))
	await get_tree().process_frame
	var journal: Array[Dictionary] = FishingRecords.journal(mine)
	var by_key: Dictionary = {}
	for r: Dictionary in journal:
		by_key[r["key"]] = r
	_check(journal.size() == (FishingData.doc()["catches"] as Array).size() and FishingRecords.kinds_caught(journal) == 2,
		"the journal lists every kind in the catalogue, and we have caught 2 of them")
	_check(int(by_key["bluegill"]["count"]) == 2 and is_equal_approx(float(by_key["bluegill"]["best_kg"]), 0.42)
		and int(by_key["bluegill"]["best_coins"]) == 20 and int(by_key["carp"]["count"]) == 0,
		"each kind: how many, the biggest, the best paid; another's catch is not ours")
	var missing: PackedStringArray = FishingRecords.missing(journal)
	_check(missing.size() > 0 and missing[0] == "things that should not be here" and not missing.has("strange fish")
		and not missing.has("small fish"), "the rarities still to find, rarest first (%s)" % ", ".join(missing))
	var biggest: Array[Dictionary] = FishingRecords.biggest()
	var big: Dictionary = {}
	for b: Dictionary in biggest:
		big[b["key"]] = b
	_check(is_equal_approx(float(big["bluegill"]["kg"]), 0.9) and not bool(big["bluegill"]["is_local"])
		and str(biggest[0]["key"]) == "golden_koi", "the records: the biggest bluegill is theirs, the rarest catch first")
	var anglers: Array[Dictionary] = FishingRecords.anglers()
	_check(anglers.size() == 2 and int(anglers[0]["coins"]) == 90 and int(anglers[1]["coins"]) == 60
		and str(anglers[1]["best_key"]) == "golden_koi" and bool(anglers[1]["is_local"]),
		"anglers by what their catches paid, with their best catch")
	var page := CatchJournal.new()
	add_child(page)
	page.open()
	await get_tree().process_frame
	var summary: Label = page.find_child("Summary", true, false) as Label
	var tabs: TabContainer = page.find_child("Tabs", true, false) as TabContainer
	_check(tabs.get_tab_count() == 2 and summary.text.begins_with("2 of %d kinds caught" % journal.size()),
		"the journal page: our catches and the records (%s)" % summary.text)
	var unknowns: int = 0
	for l: Node in page.find_child("Grid", true, false).get_children():
		if (l as Label).text == CatchJournal.UNKNOWN:
			unknowns += 1
	_check(unknowns == journal.size() - 2, "a kind not caught yet is ??? (%d)" % unknowns)
	page.queue_free()

	# AN ANGLER ARRIVES WITH THEIR HISTORY (DECISIONS #180): 25 catches already on the server when
	# they spawn, all of them on the record. The entity used to hand its components only the newest
	# row of each table, and Luke's journal showed one catch where the server had dozens.
	var veteran: int = 5503
	_buffer_player_rows(reg, veteran)
	for i: int in range(25):
		var old := FakeCatchRow.new(700 + i, veteran, 1, 1, "muskellunge" if i == 0 else "bluegill", 15.2 if i == 0 else 0.2)
		reg._on_row_event(RowEvent.make(RowEvent.Kind.INSERTED, &"catch", null, old))
	spawner._on_entity_inserted(RowEvent.make(RowEvent.Kind.INSERTED, &"entity", null, FakeEntityRow.new(veteran, 0)))
	for i: int in range(3):
		await get_tree().process_frame
	var vet: SpaceTimeEntity = spawner.get_entity_node(veteran) as SpaceTimeEntity
	var vet_fishing: FishingComponent = vet.find_component(FishingComponent) as FishingComponent if vet != null else null
	_check(vet_fishing != null and vet_fishing.all_catches().size() == 25,
		"an angler who arrives with 25 catches has all 25 on the record (got %d)"
			% (vet_fishing.all_catches().size() if vet_fishing != null else -1))
	var vet_row: Dictionary = {}
	for a: Dictionary in FishingRecords.anglers():
		if int(a["catches"]) == 25:
			vet_row = a
	_check(not vet_row.is_empty() and str(vet_row["best_key"]) == "muskellunge",
		"and the records count them all, their muskellunge the best (%s)" % str(vet_row))
	for eid: int in [5501, them, veteran]:
		spawner._on_entity_deleted(RowEvent.make(RowEvent.Kind.DELETED, &"entity", FakeEntityRow.new(eid, 0), null))
	spawner._flush_despawns()
	await get_tree().process_frame
	reg.local_entity_id = prev_local
	spawner._world_ready = prev_ready
	level.queue_free()

	# --- the rival's name, the HUD's journal and keys ------------------------------------------
	var rival_def: EntityDefinition = load("res://game/fishing/rival_definition.tres") as EntityDefinition
	_check(rival_def.display_name == str(FishingData.rival().get("name")),
		"the rival's nameplate is the name fishing.json gives him (%s)" % rival_def.display_name)
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child(menu)
	var hud: Control = (load("res://game/fishing/fishing_hud.tscn") as PackedScene).instantiate() as Control
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var journal_button: Button = menu.find_child("Journal", true, false) as Button
	_check(journal_button != null, "the HUD adds Journal to the Escape menu")
	if journal_button != null:
		journal_button.pressed.emit()
		_check((hud.call("journal") as CatchJournal).is_open() and menu.is_page_open(), "and it opens the journal there")
	_check(Settings.entries("Fishing").size() >= 3 and Settings.entry(&"fish_cast").get("tab") == "Fishing"
		and Settings.entry(&"open_journal").get("kind") == Settings.Kind.KEY,
		"fishing's keys are in the settings, to rebind")
	hud.queue_free()
	menu.queue_free()
	await get_tree().process_frame
