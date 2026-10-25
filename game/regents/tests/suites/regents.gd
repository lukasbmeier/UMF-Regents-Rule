extends "res://tests/suite_base.gd"
## REGENT'S RULE'S `regents` suite (`-- --only=regents` runs it alone), with no server:
##   - the skilling chain's content: skills and their curves, nodes, recipes, stations, items, all valid
##     and linked as the chain needs (logs -> handle, ore -> bar -> head, head + handle + rivets -> axe)
##   - woodcutting's branch dodge (`ChopModel`): the trunk from a seed (the challenge's own generator);
##     every chop rule; a perfect player scores in full; a replay of the inputs scores what was played
##   - every model against its golden file (the Rust twins are held to the same files)
##   - the minigames (`SkillMinigames`, each `SkillMinigame`): keep every input, play through the model,
##     and their end says the replay agrees; a faster tool swings faster; the skilling lab opens them all
##   - working, shown: each skill's pose in the adventurer's set, each tool a held item fitted to it

const L: int = ChopModel.SIDE_LEFT
const R: int = ChopModel.SIDE_RIGHT


func run() -> void:
	_run_content()
	_run_material_table()
	_run_material_table_writes()
	_run_trunk()
	_run_golden()
	_run_skill_goldens()
	_run_chops()
	_run_perfect_and_replay()
	_run_looks()
	_run_registry()
	await _run_minigame()
	await _run_chain_minigames()
	await _run_lab()
	await _run_recipe_bench()
	await _run_foe_bench()
	await _run_combat()
	_run_polish()
	await _run_tester_page()
	await _run_crafting_choice()
	await _run_solid()
	_run_cells()


## THE RING (template 1.0, this game's half): Regent's Rule is sent only the cells round its player, so
## each of its tables that describes a placed thing is a cell table, asked for `WHERE world_id AND chunk`.
## A cell table the bindings give no `chunk` would be a query the server refuses; one that is not also a
## world table would be sent whole to a WORLD client (the referee).
func _run_cells() -> void:
	print("== regents: the ring and its cell tables ==")
	var game: PackedScene = load("res://game/regents/regents_game.tscn") as PackedScene
	var root: Node = game.instantiate()
	var cfg: NetConfig = root.get_node("Boot").get(&"net_config") as NetConfig
	root.free()
	_check(cfg != null and cfg.interest == NetConfig.Interest.RING, "the game's Boot has ring interest")
	if cfg == null:
		return
	var genre: GenreModule = load("res://game/regents/genre.tres") as GenreModule
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SpaceTimeSync.BINDINGS_CONTRACT_PATH)) as Dictionary
	var tables: Dictionary = contract.get("tables", {}) as Dictionary
	for t: StringName in cfg.cell_tables:
		var row: String = str(tables.get(String(t), ""))
		_check(genre.tables.has(t) and genre.world_tables.has(t), "%s is subscribed, and by world for a WORLD client" % t)
		_check(row.contains("world_id:U32") and row.contains("chunk:U32"), "%s's rows carry world_id and chunk: %s" % [t, row])
	for t: StringName in cfg.follow_tables:
		_check(cfg.cell_tables.has(t) and str(tables.get(String(t), "")).contains("entity_id:U64"),
			"%s follows an entity: a cell table keyed by entity_id" % t)
	# Every table of ours with a chunk is asked for by cell; a new one left out would be sent world-wide.
	for t: StringName in genre.tables:
		if str(tables.get(String(t), "")).contains("chunk:U32"):
			_check(cfg.cell_tables.has(t), "%s has a chunk, so it is a cell table" % t)


## Combat's client side, with no server: kits, the combo's steps, the stance, the keys, the skill bar.
func _run_combat() -> void:
	print("== regents: combat ==")
	var sword: KitDef = KitDef.by_key(&"sword")
	var axe: KitDef = KitDef.by_key(&"axe")
	_check(sword != null and axe != null and sword.validate().is_empty() and axe.validate().is_empty(), "the sword and axe kits, valid")
	_check(sword.light.size() == 3 and sword.heavy != null and sword.skills.size() == 1 and sword.rank_for(0) == 1 and sword.rank_for(1) == 3,
		"the sword: a three-swing combo, a heavy, Lunge on Q at rank 1 (E would be 3)")
	for a: AbilityDef in sword.light + axe.light + [sword.heavy, axe.heavy]:
		_check(a.judged and a.reach_m > 1.0 and a.wind_up_ms >= AbilityDef.MIN_WIND_UP_MS and a.key == &"regents.combat",
			"%s: judged by the referee along the body's facing, reaching %.1f m, on the combat component's keys" % [a.display_name, a.reach_m])
	var iron_sword: ItemDef = ItemDef.by_id(40019)
	_check(iron_sword.weapon_kit == &"sword" and iron_sword.held_scene != null and ItemDef.by_id(40001).weapon_kit == &"axe",
		"the iron sword fights as a sword; the copper axe is a weapon too")
	var bad: ItemDef = iron_sword.duplicate() as ItemDef
	bad.max_stack = 5
	_check(bad.validate().any(func(e: String) -> bool: return e.contains("weapon does not stack")), "a stacking weapon is refused")
	var dummy: EntityDefinition = load("res://game/regents/content/character/dummy.tres") as EntityDefinition
	# No blocker: a referee drives the dummy (its stand-still brain makes it someone to hit), and a body the
	# referee simulates with a blocker of its own is pushed away by it (found 2026-10-19; a template fix).
	_check(dummy.kind == 102 and dummy.visual_scene != null and dummy.blocker_size == Vector3.ZERO, "the training dummy: kind 102, its model, no blocker")
	var c: CombatComponent = CombatComponent.new()
	_check(not c.in_stance() and c.next_light_step(0) == -1, "nothing wielded: no stance, no swing")
	c.kit = sword
	var now: int = 100000
	_check(c.next_light_step(now) == 0, "the first tap: the combo's first swing")
	c.combo_step = 0
	c.combo_ms = now - 300
	_check(c.next_light_step(now) == 1, "inside the window: the second")
	c.combo_step = 2
	_check(c.next_light_step(now) == 0, "after the third: the first again")
	c.combo_step = 0
	c.combo_ms = now - sword.combo_window_ms - 1
	_check(c.next_light_step(now) == 0, "too late: the combo starts over")
	_check(not c.in_stance(), "a weapon, no target, no swing: no stance (Q and E work stations)")
	c.target_id = 7
	_check(c.in_stance(), "a target picked: in stance (Q E R F are skills)")
	c.weapon = iron_sword
	var bar: String = RegentsHud.skill_bar(c, null)
	_check(bar.contains("Iron sword") and bar.contains("LMB Slash") and bar.contains("Q Lunge") and bar.contains("RMB block"), "the skill bar: %s" % bar)
	c.free()
	CombatComponent.bind_keys()
	var ctrl_dodges: bool = false
	for e: InputEvent in InputMap.action_get_events(&"dash"):
		ctrl_dodges = ctrl_dodges or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_CTRL)
	var slow_ctrl: bool = false
	for e: InputEvent in InputMap.action_get_events(&"move_slow"):
		slow_ctrl = slow_ctrl or (e is InputEventKey and ((e as InputEventKey).physical_keycode == KEY_CTRL or (e as InputEventKey).keycode == KEY_CTRL))
	var dash_q: bool = false
	for e: InputEvent in InputMap.action_get_events(&"dash"):
		dash_q = dash_q or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q)
	_check(ctrl_dodges and not slow_ctrl and not dash_q, "Ctrl rolls (the foundation's dash), not Q (a skill here); slow-walk is on Alt")
	_run_swing_timeline()
	_run_foes()
	_run_bow()
	_run_staff()
	await _run_grades()


## THE STAFF (owner, 2026-10-20, LOOT_AND_STYLES §4): its content holds together, and the client's casting.
func _run_staff() -> void:
	print("== regents: the staff ==")
	var staff: KitDef = KitDef.by_key(&"staff")
	_check(staff != null and staff.casts() and staff.resource.key == &"mana" and staff.validate().is_empty(),
		"the staff kit casts from mana, and is sound: %s" % (str(staff.validate()) if staff != null else "none"))
	var names: PackedStringArray = PackedStringArray()
	for a: AbilityDef in staff.light + staff.skills:
		var sp: SpellDef = SpellDef.by_ability(a.id)
		names.append("%s %s" % [a.display_name, ["bolt", "area", "blink", "cone"][sp.kind] if sp != null else "NONE"])
	_check(" / ".join(names) == "Bolt bolt / Fireball bolt / Frost Ring area / Blink blink / Gale cone", "its spells: %s" % " / ".join(names))
	var aset: AnimationSet = staff.timing_set
	for a: AbilityDef in staff.light + staff.skills:
		_check(aset.has_exact(StringName("ability.%d" % a.id)) and staff.lock_ms(a) > 0, "%s has its clip (%s)" % [a.display_name, aset.clip(StringName("ability.%d" % a.id)).anim_name])
	_check(aset.has_exact(&"pose.spell_cast") and aset.has_exact(&"pose.spell_channel"), "and the casting poses")
	var slowed: StatusDef = load("res://game/regents/content/status/slowed.tres") as StatusDef
	_check(slowed.status == 108 and is_equal_approx(slowed.speed, 0.6) and not slowed.can_sprint, "Slowed: 40 %% slower, no sprint")
	var yew_staff: ItemDef = ItemDef.by_id(40023)
	var held: HeldItem = yew_staff.held_scene.instantiate() as HeldItem
	_check(yew_staff.weapon_kit == &"staff" and held != null and held.grip.hand == &"hand_r" and RecipeDef.by_id(40014).output == yew_staff,
		"a yew staff: the staff kit, held in the right hand, made at the workbench")
	held.free()
	for b: String in ["bolt", "fireball"]:
		var body: BodyDef = load("res://game/regents/content/body/%s.tres" % b) as BodyDef
		_check(body.gravity_scale == 0.0 and body.launched_by.is_empty() and body.lifetime_s > 0.0, "the %s flies straight, never thrown by hand, gone in time" % b)
	# The client casting, offline.
	var c := CombatComponent.new()
	c.kit = staff
	var mana := ResourceComponent.new()
	c.pool_for_tests = mana
	var sent: Array = []
	c.cast_sent.connect(func(id: int, t: int, _aim: Vector3, _at: Vector3) -> void: sent.append([id, t]))
	var said: Array[String] = []
	c.refused.connect(func(why: String) -> void: said.append(why))
	var bolt: AbilityDef = staff.light[0]
	_check(c.cast(bolt) and sent == [[40012, 0]] and not c.casting() and c.spell_cooldown_sec(bolt) > 0.0,
		"a Bolt: sent at once (no target: where you look), free, on its own cooldown")
	_check(not c.may_cast(Time.get_ticks_msec()), "its clip holds you: a press now is queued, as a swing's")
	var fireball: AbilityDef = staff.skills[0]
	_check(c.cast(fireball) and sent.size() == 1 and said.size() == 1 and said[0].contains("Not enough mana"), "no mana: Fireball refused here (%s)" % str(said))
	mana._apply(_pool_row(40001, 100.0))
	c.swing_lock_ms = 0
	_check(c.cast(fireball) and sent.size() == 2 and c.casting() and c.cast_progress() < 0.2, "with mana: Fireball cast, its 0.6 s bar begun")
	_check(c.spell_cooldown_sec(fireball) > 6.0 and c.spell_cooldown_sec(bolt) > 0.0, "each on its own cooldown (Fireball %.1f s): no global one" % c.spell_cooldown_sec(fireball))
	c._tick_cast(Time.get_ticks_msec() + 700)
	_check(not c.casting(), "at its end it lands (the bar goes)")
	_check(c.cast(fireball) and said.back().contains("ready in"), "again at once: its cooldown says when (%s)" % said.back())
	c.free()
	mana.free()
	# What burns shows a fire (its HitFeedbackComponent, from its `burning` row), gone with the row.
	var burner := Node3D.new()
	add_child(burner)
	var hf := HitFeedbackComponent.new()
	hf.entity = burner
	hf._on_row_updated(&"burning", null, PoolRow.new())
	_check(hf.fire != null and burner.get_node_or_null(^"Burning") != null, "a burning row: a fire on it")
	hf._on_row_updated(&"burning", PoolRow.new(), null)
	_check(hf.fire == null, "its row gone: the fire is out")
	hf.free()
	burner.queue_free()
	# What spells look like: a circle filling until it lands.
	var looks := SpellLooks.new()
	add_child(looks)
	looks.show_area(5, Vector3(1, 0, 1), 4.0, ClockSync.server_usec() + 1_000_000, false)
	_check(looks.area_fill(5) < 0.1 and looks.get_node_or_null(^"Area_5") != null, "a Frost Ring's circle, just cast: nearly empty")
	looks.forget_area(5)
	_check(looks.area_fill(5) == 0.0, "gone with its row")
	looks.queue_free()


## THE POLISH ROUND (owner, 2026-10-21: "more visually telling and easy to read"): the minimap's sums, the
## work's progress and Make X, the hit flashes, the HUD's bars.
func _run_polish() -> void:
	print("== regents: reading the game at a glance ==")
	# The minimap: ahead is up, whichever way the camera looks; north on the rim.
	_check(RegentsMinimap.facing_of(Vector3(0, 0, -1)) == 0.0 and is_equal_approx(RegentsMinimap.facing_of(Vector3(1, 0, 0)), PI / 2.0),
		"a camera looking north faces 0, looking east PI/2")
	_check(RegentsMinimap.to_map(Vector2(0, -10), 0.0, 2.0).is_equal_approx(Vector2(0, -20)), "facing north, a thing 10 m north is 20 px up")
	_check(RegentsMinimap.to_map(Vector2(10, 0), PI / 2.0, 2.0).is_equal_approx(Vector2(0, -20)), "facing east, a thing 10 m east is up")
	_check(RegentsMinimap.to_map(Vector2(0, -10), PI / 2.0, 2.0).is_equal_approx(Vector2(-20, 0)), "and north is to the left")
	var bake: LevelBake = LevelBake.by_id(20)
	var area: Rect2 = RegentsMinimap.area_of(bake)
	var all_in: bool = bake != null and not bake.points.is_empty()
	for pt: Dictionary in (bake.points if bake != null else []):
		all_in = all_in and area.has_point(Vector2(float(pt["x"]), float(pt["z"])))
	_check(all_in and area.size.x >= RegentsMinimap.CAPTURE_MIN_M and area.size.x <= RegentsMinimap.CAPTURE_MAX_M and is_equal_approx(area.size.x, area.size.y),
		"the frontier's picture: a square holding every point of its bake (%.0f m)" % area.size.x)
	_check(RegentsMinimap.colour_of(0) == RegentsMinimap.PLAYER and RegentsMinimap.colour_of(103) == RegentsMinimap.FOE
		and RegentsMinimap.colour_of(101) == RegentsMinimap.STATION and RegentsMinimap.colour_of(100) == RegentsMinimap.TREE,
		"dots: players white, foes yellow, stations blue, trees green")
	# The work's progress: from the run's start to the next piece, then piece to piece.
	var sk := SkillingComponent.new()
	var row := AfkRow.new()
	row.target_id = 77
	row.craft = true
	row.started_at = 1_000_000
	row.next_at = 3_000_000
	sk._on_row_updated(SkillingComponent.TABLE_AFK, null, row)
	_check(sk.afk_target == 77 and is_equal_approx(sk.afk_progress(2_000_000), 0.5), "half way from the start to the first piece: 0.5")
	var row2 := AfkRow.new()
	row2.target_id = 77
	row2.craft = true
	row2.started_at = 1_000_000
	row2.next_at = 5_000_000
	sk._on_row_updated(SkillingComponent.TABLE_AFK, row, row2)
	_check(is_equal_approx(sk.afk_progress(4_000_000), 0.5) and sk.afk_progress(9_000_000) == 1.0, "the next piece counts from when the last came")
	sk._on_row_updated(SkillingComponent.TABLE_AFK, row2, row2)
	_check(is_equal_approx(sk.afk_progress(4_000_000), 0.5), "the same row again moves nothing")
	# Make X: each batch made counts, the last asked for stops the run; gathering never counts.
	sk.make_limit = 2
	sk.made = 0
	var made_one: Dictionary = {"active": false, "qty": 4, "target_id": 77}
	sk._count_made(made_one)
	_check(sk.made == 1 and sk.make_limit == 2, "one of two made: it goes on")
	sk._count_made({"active": true, "qty": 4, "target_id": 77})
	_check(sk.made == 1, "a played round is not a Make X batch")
	sk._count_made(made_one)
	_check(sk.made == 2 and sk.make_limit == 0, "two of two: the limit is spent and the run is stopped")
	sk.afk["craft"] = false
	sk.make_limit = 1
	sk.made = 0
	sk._count_made(made_one)
	_check(sk.made == 0 and sk.make_limit == 1, "work at a node (gathering) is not counted")
	sk._on_row_updated(SkillingComponent.TABLE_AFK, row2, null)
	_check(sk.afk_target == -1 and sk.make_limit == 0 and sk.afk_progress(4_000_000) == 0.0, "the run over: no bar, no limit left")
	sk.free()
	# The hit flashes: a hit lights the body, a blocked one is steel, a stagger gold.
	var body := Node3D.new()
	add_child(body)
	var look := Node3D.new()
	look.name = "Visual"
	body.add_child(look)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	look.add_child(mesh)
	var hf := HitFeedbackComponent.new()
	hf.entity = body
	hf._on_health_changed(90.0, 100.0, -10.0)
	_check(hf.flashes.back() == &"hit" and mesh.material_overlay != null, "a hit: the body flashes")
	var st := StatusComponent.new()
	st._status = HitFeedbackComponent.STATUS_BLOCKING
	hf._status = st
	hf._on_health_changed(85.0, 100.0, -5.0)
	_check(hf.flashes.back() == &"block", "a hit taken while blocking: the block's flash")
	hf._on_status_changed(0, HitFeedbackComponent.STATUS_STAGGERED)
	_check(hf.flashes.back() == &"stagger", "staggered (a parried swing): the stagger's flash")
	hf._on_health_changed(95.0, 100.0, 10.0)
	_check(hf.flashes.size() == 3, "a heal flashes nothing")
	hf._unflash()
	_check(mesh.material_overlay == null, "the flash over, the body is its own again")
	st.free()
	hf.free()
	body.queue_free()
	# The skeletons face the way they fight (owner, 2026-10-21: "facing backwards"): the same Quaternius rig as
	# the adventurer, so the same turn of the model (its `visual_yaw_deg`, 180: the rig is made facing +Z).
	var hero: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	for f: String in ["skeleton_warrior", "skeleton_axeman"]:
		var foe_def: EntityDefinition = load("res://game/regents/content/character/%s.tres" % f) as EntityDefinition
		_check(foe_def.animation_set == hero.animation_set and is_equal_approx(foe_def.visual_yaw_deg, hero.visual_yaw_deg),
			"the %s's model is turned as the adventurer's (%.0f deg): it faces the way it swings" % [f, foe_def.visual_yaw_deg])
	# The HUD's bars.
	var bar := ProgressBar.new()
	var words := Label.new()
	words.name = "Text"
	bar.add_child(words)
	RegentsHud.set_bar(bar, 150.0, 100.0, "150 / 100")
	_check(bar.value == 100.0 and bar.max_value == 100.0 and words.text == "150 / 100", "a bar never runs past its most, and says its words")
	bar.free()


## EVERYTHING YOU SEE STOPS YOU, AND ORE SITS ON ITS ROCK (owner, 2026-10-21): hulls from the models, the
## rocks', the stations' and the level's props; the nuggets on the rock's surface or where a layout puts them.
func _run_solid() -> void:
	print("== regents: what stops you, and the ore on the rocks ==")
	# A hull is the mesh as drawn: moved, turned and scaled with it; a not-solid mesh is left out.
	var holder := Node3D.new()
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.transform = Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3(3, 0, 0))
	holder.add_child(box)
	var ghost := MeshInstance3D.new()
	ghost.mesh = SphereMesh.new()
	ghost.add_to_group(&"not_solid")
	holder.add_child(ghost)
	var body: StaticBody3D = RegentsSolid.wrap(holder, holder)
	var shapes: Array[Node] = body.get_children() if body != null else []
	var pts: AABB = _points_box(shapes)
	_check(body != null and shapes.size() == 1 and body.collision_layer == 1 and body.collision_mask == 0,
		"a model's body: one hull per solid mesh (the not-solid one left out), on the world's layer")
	_check(pts.position.distance_to(Vector3(2, -1, -1)) < 0.05 and pts.size.distance_to(Vector3(2, 2, 2)) < 0.05,
		"the hull is where the mesh is drawn, at its size (%s)" % pts)
	_check(RegentsSolid.hull_of(box.mesh) == RegentsSolid.hull_of(box.mesh), "a mesh's hull is worked out once")
	holder.free()
	# A rock blocks the way across its whole width (it stopped you at a 0.75 m cylinder on a 3 m rock). Copper
	# and iron, each of their models (an id that does not make the fallback's ring the layout's own).
	for which: Array in [[40004, 3], [40004, 4], [40005, 3], [40005, 4]]:
		await _check_rock(NodeDef.by_id(int(which[0])), int(which[1]))
	# With no layout: every nugget on the rock's own surface (none floats).
	var bare: Node3D = (load("res://game/regents/art/nature/Rock_Medium_1.gltf") as PackedScene).instantiate() as Node3D
	var surface: TriangleMesh = RegentsOreSpots.surface_of(bare)
	var spots: Array[Transform3D] = RegentsOreSpots.on_surface(bare, 5, 3)
	var on_it: int = 0
	for t: Transform3D in spots:
		var up: Vector3 = t.basis.y.normalized()
		var hit: Dictionary = surface.intersect_ray(t.origin + up * 0.5, -up)
		if not hit.is_empty() and absf((hit["position"] as Vector3).distance_to(t.origin) - RegentsOreSpots.SINK_M) < 0.02:
			on_it += 1
	_check(spots.size() == 5 and on_it == 5, "with no layout, each nugget lies on the rock's own surface, %.2f m in (%d of %d)" % [RegentsOreSpots.SINK_M, on_it, spots.size()])
	bare.free()
	# A tree: its trunk only (the canopy is walked under).
	var tree: Array = _node_entity(NodeDef.by_id(40001), 1)
	var tshapes: Array[Node] = (tree[1] as NodeComponent).solid.get_children()
	_check(tshapes.size() == 1 and (tshapes[0] as CollisionShape3D).shape is CylinderShape3D, "a tree blocks at its trunk")
	(tree[0] as Node).free()
	# A station: every piece of it, as drawn (the workbench is all pieces, no body).
	for key: StringName in [&"anvil", &"workbench", &"orders", &"furnace"]:
		var ent := Node3D.new()
		var comps := Node.new()
		comps.name = "Components"
		ent.add_child(comps)
		var look := Node3D.new()
		look.name = "Visual"
		ent.add_child(look)
		add_child(ent)
		var sc := StationComponent.new()
		comps.add_child(sc)
		sc.def = StationDef.by_key(key)
		sc.key = key
		sc._build()
		var drawn := AABB()
		var first: bool = true
		for mi: Node in look.find_children("*", "MeshInstance3D", true, false):
			if mi.is_in_group(&"not_solid"):
				continue
			var b: AABB = RegentsSolid.relative(look, mi as MeshInstance3D) * (mi as MeshInstance3D).get_aabb()
			drawn = b if first else drawn.merge(b)
			first = false
		var held: AABB = _points_box(sc.solid.get_children() if sc.solid != null else [])
		_check(sc.solid != null and held.grow(0.05).encloses(drawn), "the %s blocks wherever it is drawn (%s in %s)" % [key, drawn, held])
		ent.free()
	# A level's props: rocks and bushes solid, grass walked through.
	var level := Node3D.new()
	var decor := Node3D.new()
	decor.name = "Decor"
	level.add_child(decor)
	var big: Node3D = (load("res://game/regents/art/nature/Rock_Big_1.gltf") as PackedScene).instantiate() as Node3D
	big.position = Vector3(10, 0, 0)
	decor.add_child(big)
	var grass: Node3D = (load("res://game/regents/art/nature/Grass_Common_Short.gltf") as PackedScene).instantiate() as Node3D
	decor.add_child(grass)
	var sp := RegentsSolidProps.new()
	level.add_child(sp)
	add_child(level)
	var walls: Array[Node] = decor.find_children("Solid*", "StaticBody3D", false, false)
	var wall_box: AABB = _points_box(walls[0].get_children() if not walls.is_empty() else [])
	_check(sp.made_solid == [big] and walls.size() == 1, "a level's rock is made solid, its grass is not (%d bodies)" % walls.size())
	_check(wall_box.has_point(Vector3(10, 0.5, 0)), "where the rock stands (%s)" % wall_box)
	level.free()


## One rock of `def` (entity `id`): solid across its shape, its ore where its model's layout puts it, not
## solid itself; worked out it blocks nothing, back it blocks again.
func _check_rock(def: NodeDef, id: int) -> void:
	var rock: Array = _node_entity(def, id)
	var nc: NodeComponent = rock[1]
	var model_box: AABB = NodeComponent._aabb_of(nc._model)
	var solid_box: AABB = _points_box(nc.solid.get_children() if nc.solid != null else [])
	_check(nc.solid != null and solid_box.size.x >= model_box.size.x * nc.def.model_scale * 0.9 and solid_box.size.z >= model_box.size.z * nc.def.model_scale * 0.9,
		"%s (entity %d) is solid across its whole shape (%.2f x %.2f m, the model %.2f x %.2f)" % [def.display_name, id, solid_box.size.x, solid_box.size.z,
		model_box.size.x * nc.def.model_scale, model_box.size.z * nc.def.model_scale])
	# Its ore: as its model's layout puts it (`ore/<model>_ore.tscn`).
	var scene: PackedScene = nc.def.models[id % nc.def.models.size()]
	var laid: Array[Transform3D] = RegentsOreSpots.from_layout(load(RegentsOreSpots.layout_path(scene)) as PackedScene)
	var same: bool = nc.nuggets.size() == laid.size() and laid.size() > 0
	for i: int in mini(nc.nuggets.size(), laid.size()):
		same = same and nc.nuggets[i].transform.is_equal_approx(laid[i])
	_check(same, "%s: its nuggets are where %s's layout puts them (%d)" % [def.display_name, scene.resource_path.get_file(), laid.size()])
	_check(nc.nuggets.all(func(n: Node3D) -> bool: return n.is_in_group(&"not_solid")), "and they are no part of what blocks")
	nc._set_depleted(true)
	await get_tree().physics_frame
	_check(nc.solid.collision_layer == 0, "worked out, the rubble blocks nothing")
	nc._set_depleted(false)
	await get_tree().physics_frame
	_check(nc.solid.collision_layer == 1, "back, it blocks again")
	(rock[0] as Node).free()


## A node entity as the game builds one (an entity, its Components, its Visual) showing `def`.
func _node_entity(def: NodeDef, id: int) -> Array:
	var ent := Node3D.new()
	var comps := Node.new()
	comps.name = "Components"
	ent.add_child(comps)
	var look := Node3D.new()
	look.name = "Visual"
	ent.add_child(look)
	add_child(ent)
	var nc := NodeComponent.new()
	nc.entity_id = id
	comps.add_child(nc)
	nc._set_def(def)
	return [ent, nc]


## The box round every point of these collision shapes' hulls (in their body's space).
static func _points_box(shapes: Array) -> AABB:
	var out := AABB()
	var first: bool = true
	for n: Variant in shapes:
		var cs: CollisionShape3D = n as CollisionShape3D
		if cs == null:
			continue
		var hull: ConvexPolygonShape3D = cs.shape as ConvexPolygonShape3D
		var cyl: CylinderShape3D = cs.shape as CylinderShape3D
		var pts: PackedVector3Array = hull.points if hull != null else PackedVector3Array()
		if cyl != null:
			pts = PackedVector3Array([cs.position + Vector3(-cyl.radius, -cyl.height * 0.5, -cyl.radius), cs.position + Vector3(cyl.radius, cyl.height * 0.5, cyl.radius)])
		for p: Vector3 in pts:
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


class AfkRow extends RefCounted:
	var target_id: int
	var def_id: int = 40005
	var craft: bool
	var skill_id: int = 0
	var tool_item: int = 0
	var started_at: int
	var next_at: int


class PoolRow extends RefCounted:
	var resource_id: int
	var stored: float
	var at: int


func _pool_row(id: int, stored: float) -> PoolRow:
	var r := PoolRow.new()
	r.resource_id = id
	r.stored = stored
	r.at = ClockSync.server_usec()
	return r


## GRADES AND POWER (owner, 2026-10-20, LOOT_AND_STYLES.md): quality bands, graded names, Power from tier
## and quality, tier dominating, and the bag showing them.
func _run_grades() -> void:
	print("== regents: grades and Power ==")
	_check(RegentsGrade.of_quality(-1) == -1 and RegentsGrade.of_quality(0) == 0 and RegentsGrade.of_quality(399) == 0
		and RegentsGrade.of_quality(400) == 1 and RegentsGrade.of_quality(799) == 1 and RegentsGrade.of_quality(800) == 2
		and RegentsGrade.of_quality(1000) == 2, "bands: Common under 400, Fine from 400, Masterwork from 800 (hot rules); none without a quality")
	var iron_axe: ItemDef = ItemDef.by_id(40015)
	var copper_axe: ItemDef = ItemDef.by_id(40001)
	_check(RegentsGrade.quality_of("{\"q\":850,\"h\":40016}") == 850 and RegentsGrade.quality_of("{\"q\":300}") == 300
		and RegentsGrade.quality_of("") == -1, "a row's quality: 850 beside its handle, 300 alone, none for a plain item")
	_check(RegentsGrade.item_name(iron_axe, 734) == "Fine iron axe" and RegentsGrade.item_name(iron_axe, 900) == "Masterwork iron axe"
		and RegentsGrade.item_name(iron_axe, 100) == "Iron axe" and RegentsGrade.item_name(iron_axe, -1) == "Iron axe",
		"names: Fine iron axe, Masterwork iron axe; a Common or ungraded one as it is")
	_check(RegentsGrade.power(iron_axe, 0) == 100 and RegentsGrade.power(iron_axe, 1000) == 120 and RegentsGrade.power(iron_axe, 734) == 115
		and RegentsGrade.power(copper_axe, 0) == 70 and RegentsGrade.power(copper_axe, 1000) == 84,
		"Power: iron 100 to 120, copper 70 to 84, by quality")
	_check(RegentsGrade.power(iron_axe, 734) == roundi(FoeWorkbench.hit_damage(100.0, iron_axe.weapon_damage_pct, 734, 1)),
		"Power is the hit the server deals: the kit's 100 through the weapon and its quality (hit_damage)")
	_check(RegentsGrade.power(ItemDef.by_id(40022), -1) == 100 and RegentsGrade.power(ItemDef.by_id(40002), -1) == -1,
		"copper arrows: Power 100; logs: none")
	var all: Array[ItemDef] = []
	for d: ContentDef in RegentsContent.items(&"item"):
		if d is ItemDef:
			all.append(d as ItemDef)
	_check(RegentsGrade.tier_overlaps(all).is_empty(), "every tier dominates the one below it (%s)" % "; ".join(RegentsGrade.tier_overlaps(all)))
	var close: ItemDef = copper_axe.duplicate() as ItemDef
	close.weapon_damage_pct = 90
	var said: PackedStringArray = PackedStringArray(close.validate())
	_check(said.size() > 0 and "; ".join(said).contains("reaches Iron axe at its worst (Power 100): tier must dominate"),
		"a copper axe at 90 %% would reach the iron axe: its check says so (%s)" % "; ".join(said))
	# Icons drawn from the models (template #271, tools/render_icons.tscn): the bow's, the arrows' (their
	# world model); logs have no model and keep their initials.
	_check(ItemDef.by_id(40020).icon() != null and ItemDef.by_id(40022).icon() != null and ItemDef.by_id(40002).icon() == null,
		"the yew bow and the arrows have drawn icons; logs (no model) none")
	# The bag: graded edges, the graded name, Power against the weapon wielded.
	var layer := CanvasLayer.new()
	add_child(layer)
	var inv := SpaceTimeInventoryComponent.new()
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40015, 1, 0, "{\"q\":850,\"h\":40016}")
	inv._stacks[2] = SpaceTimeInventoryComponent.Stack.new(2, 40001, 1, 1, "{\"q\":300}")
	inv._stacks[3] = SpaceTimeInventoryComponent.Stack.new(3, 40002, 5, 2)
	var cc := CombatComponent.new()
	cc.weapon_row = 2
	var bag := RegentsBagWindow.new()
	bag.inventory = inv
	bag.combat = cc
	layer.add_child(bag)
	bag.picked_row = 1
	bag.open()
	await get_tree().process_frame
	var s1: UiSlot = bag.find_child("Slot_1", true, false) as UiSlot
	var s2: UiSlot = bag.find_child("Slot_2", true, false) as UiSlot
	var s3: UiSlot = bag.find_child("Slot_3", true, false) as UiSlot
	_check(s1 != null and s2 != null and s3 != null and s1.grade == 2 and s2.grade == 0 and s3.grade == -1,
		"slots: the iron axe Masterwork, the copper Common, the logs ungraded")
	var title: Label = bag.find_child("ItemName", true, false) as Label
	_check(title != null and title.text == "Masterwork iron axe" and title.get_theme_color(&"font_color").is_equal_approx(UiStyle.current().grade_colors[2]),
		"its name: Masterwork iron axe, in the Masterwork colour")
	var pw: Label = bag.find_child("Power", true, false) as Label
	_check(pw != null and pw.text == "Power 117  (+43 on your Copper axe)" and pw.get_theme_color(&"font_color").is_equal_approx(UiStyle.current().good),
		"Power 117, 43 over the copper axe you wield, in the good colour (%s)" % (pw.text if pw != null else "none"))
	bag.picked_row = 2
	bag.refresh()
	await get_tree().process_frame
	pw = bag.find_child("Power", true, false) as Label
	_check(pw != null and pw.text == "Power 74  (wielded)", "the wielded one: Power 74, wielded (%s)" % (pw.text if pw != null else "none"))
	bag.close()
	layer.queue_free()
	cc.free()
	inv.free()
	close = null
	await get_tree().process_frame


## The swing's timeline on the client (owner, 2026-10-19: animation-locked, a buffer, committed, cancels).
## THE YEW BOW (owner, 2026-10-20): its content holds together, and the client's draw.
func _run_bow() -> void:
	print("== regents: the bow ==")
	var bow: KitDef = KitDef.by_key(&"bow")
	_check(bow != null and bow.draws and bow.draw_full_ms == 800 and bow.heavy == null and bow.light.size() == 1, "the bow kit: drawn, full at 800 ms, one shot")
	var aset: AnimationSet = load("res://game/regents/anim/adventurer.tres") as AnimationSet
	_check(aset.has_exact(&"pose.bow_draw") and aset.has_exact(&"pose.bow_aim") and aset.clip(&"ability.40011").anim_name == &"extra/Bow_Shoot",
		"the set draws, aims and looses (Bow_Notch, Bow_Aim_Neutral, Bow_Shoot)")
	var yew: ItemDef = ItemDef.by_id(40020)
	var arrows: ItemDef = ItemDef.by_id(40022)
	_check(yew.weapon_kit == &"bow" and arrows.ammo_for == &"bow" and arrows.max_stack >= 100, "a yew bow fights with it; copper arrows are its ammo")
	var held: HeldItem = yew.held_scene.instantiate() as HeldItem
	_check(held != null and held.grip.hand == &"hand_l", "the bow is held in the left hand")
	held.free()
	var drawing: StatusDef = load("res://game/regents/content/status/drawing.tres") as StatusDef
	_check(drawing.status == 107 and drawing.speed <= 0.3 and not drawing.can_sprint and not drawing.can_jump and drawing.can_dash,
		"drawn, you walk: no sprint or jump; the roll is whole")
	_check(RecipeDef.by_id(40012).output_qty == 15 and RecipeDef.by_id(40013).input_qty[0] == 15 and RecipeDef.by_id(40011).output == yew,
		"the workbench: a log to 15 shafts, 15 shafts and a bar to 15 arrows, yew logs to a bow")
	var body: BodyDef = load("res://game/regents/content/body/arrow.tres") as BodyDef
	_check(body.forces is ArrowFlight and body.launched_by.is_empty() and body.lifetime_s > 0.0, "the arrow: flown nose-first, never thrown by hand, gone in time")


## THE FIRST ENEMIES (owner, 2026-10-19): the skeleton camp's content holds together.
func _run_foes() -> void:
	print("== regents: foes ==")
	var foes: Array[FoeDef] = FoeDef.all()
	_check(foes.size() == 2, "two foes: %s" % ", ".join(foes.map(func(f: FoeDef) -> String: return String(f.key))))
	var genre: Resource = load("res://game/regents/genre.tres")
	var defs: Array = genre.get(&"entity_definitions") as Array
	for f: FoeDef in foes:
		_check(f.validate().is_empty(), "%s is valid content: %s" % [f.display_name, str(f.validate())])
		_check(defs.has(f.character), "%s's character is the genre's, so a client can draw it" % f.display_name)
		_check(f.character.brain == &"regents/foe" and f.character.animation_set != null and f.character.visual_scene != null,
			"%s has the foe brain, the adventurer's animations and its Bestiary model" % f.display_name)
		for a: AbilityDef in f.kit.abilities():
			_check(f.character.animation_set.has_exact(StringName("ability.%d" % a.id)), "%s plays its %s" % [f.display_name, a.display_name])
	_check(FoeDef.by_kind(103) != null and FoeDef.by_kind(103).kit.key == &"sword" and FoeDef.by_kind(104).kit.key == &"axe",
		"the warrior fights with the sword kit, the axeman with the axe kit (the weapons their models carry)")
	var bad := FoeDef.new()
	_check(bad.validate().size() >= 3, "a foe with no key, character or kit is refused: %s" % str(bad.validate()))
	_check(FoeDef.by_kind(103).loot_table != null and FoeDef.by_kind(103).loot_table.id == 40001 and FoeDef.by_kind(103).loot_table.lines[2].pity,
		"its loot is the skeleton camp's table, the gem with pity")


func _run_swing_timeline() -> void:
	var axe: KitDef = KitDef.by_key(&"axe")
	var aset: AnimationSet = axe.timing_set
	for a: AbilityDef in axe.abilities():
		var sem: StringName = StringName("ability.%d" % a.id)
		var clip_ms: int = roundi(AnimationTreeBuilder.clip_length(aset, sem) / aset.clip(sem).speed_scale * 1000.0)
		_check(axe.lock_ms(a) == maxi(clip_ms, a.wind_up_ms + KitDef.MIN_RECOVERY_MS) and axe.lock_ms(a) > a.wind_up_ms,
			"%s locks for its clip's length (%d ms), past its wind-up (%d)" % [a.display_name, axe.lock_ms(a), a.wind_up_ms])
		_check(a.cooldown_ms <= axe.lock_ms(a) or axe.skills.has(a), "%s: its cooldown (%d) never outlasts its lock: a queued swing is never refused for it" % [a.display_name, a.cooldown_ms])
	var c: CombatComponent = CombatComponent.new()
	c.kit = axe
	var chop: AbilityDef = axe.light[0]
	c.swing_ability = chop
	c.swing_at_ms = 0
	c.swing_hit_ms = chop.wind_up_ms
	c.swing_lock_ms = axe.lock_ms(chop)
	c.combo_step = 0
	_check(c.swinging(10) and not c.may_start(axe.heavy, -1, 300), "a chop just begun holds you: no heavy 300 ms in")
	_check(c.may_start(axe.heavy, -1, axe.lock_ms(chop)), "free when its clip ends (%d ms)" % axe.lock_ms(chop))
	_check(not c.may_start(axe.light[1], 1, chop.wind_up_ms), "the combo's second waits for the first to land")
	_check(c.may_start(axe.light[1], 1, chop.wind_up_ms + axe.chain_ms), "and chains just after it lands (%d ms)" % (chop.wind_up_ms + axe.chain_ms))
	c.swing_cancelled = true
	_check(not c.swinging(10) and c.may_start(axe.heavy, -1, 10), "a swing a roll cancelled holds nothing")
	c.free()
	var adv: PackedScene = load("res://game/regents/adventurer.tscn") as PackedScene
	var body: Node = adv.instantiate()
	var drv: AnimationDriverComponent = body.get_node_or_null(^"Components/Animation") as AnimationDriverComponent
	var cfg: MovementConfig = MovementConfig.shared()
	_check(drv != null and drv.action_cancel_speed > cfg.walk_speed and drv.action_cancel_speed < cfg.run_speed,
		"a committed swing walks (%.1f m/s) under the speed that cuts it (%.1f); running (%.1f) cuts its recovery" % [cfg.walk_speed, drv.action_cancel_speed if drv != null else 0.0, cfg.run_speed])
	body.free()
	var swinging_status: StatusDef = load("res://game/regents/content/status/swinging.tres") as StatusDef
	var adv_cfg: MovementConfig = (load("res://game/regents/content/movement/adventurer.tres") as MovementProfileDef).apply_to(cfg)
	var in_swing: MovementConfig = swinging_status.apply_to(adv_cfg)
	_check(in_swing.run_speed >= adv_cfg.walk_speed and in_swing.run_speed < adv_cfg.walk_speed * 1.1 and not swinging_status.can_sprint,
		"the server's Swinging bound (%.2f m/s) lets the committed walk (%.1f) through, and no faster" % [in_swing.run_speed, adv_cfg.walk_speed])
	_check(swinging_status.can_dash and in_swing.dash_impulse > 0.0 and is_equal_approx(in_swing.dash_impulse, adv_cfg.dash_impulse),
		"and leaves the roll whole (a dash of %.0f in a swing, as out of one: DECISIONS #256)" % in_swing.dash_impulse)
	var adv_set: AnimationSet = load("res://game/regents/anim/adventurer.tres") as AnimationSet
	_check(adv_set.root_motion_bone == &"root", "the swings play in place: their root travel is taken out (%s)" % adv_set.root_motion_bone)


## The recipe bench: a recipe's numbers worked out from the content and the hot rules' defaults.
## The foe bench: a foe's fight worked out from the content, the server's damage rule mirrored.
func _run_foe_bench() -> void:
	print("== regents: the foe bench ==")
	var warrior: FoeDef = FoeDef.by_kind(103)
	_check(ContentLibrary.workbench_for(&"foe") == "res://game/regents/workbench/foe_workbench.tscn", "a foe has its bench")
	var bench: FoeWorkbench = (load(ContentLibrary.workbench_for(&"foe")) as PackedScene).instantiate() as FoeWorkbench
	add_child(bench)
	bench.item = warrior
	await get_tree().process_frame
	# The server's rule, mirrored: native tests hold the Rust; these the same numbers here.
	_check(is_equal_approx(FoeWorkbench.hit_damage(11.0, 70, 0, 1), 7.7) and is_equal_approx(FoeWorkbench.hit_damage(10.0, 100, 1000, 10), 10.0 * 1.2 * 1.27),
		"its damage rule is the server's: a chop at 70 %% is 7.7; quality and rank 10 add a fifth and 27 %%")
	var sheet: String = await bench.run_named_test(&"sheet")
	var r: Dictionary = FoeWorkbench.rhythm(warrior)
	_check(sheet.contains("120 health") and int(bench.last_measure["swings"]) == maxi(warrior.heavy_every, warrior.kit.light.size()) and float(bench.last_measure["dps"]) > 0.0,
		"the sheet: %s" % sheet)
	var slash: float = FoeWorkbench.hit_damage(warrior.kit.light[0].damage, warrior.damage_pct, 0, 1)
	_check(is_equal_approx(float((r["swings"] as Array)[0]["damage"]), slash) and int(r["ms"]) >= warrior.rest_ms,
		"its first swing does its slash at %d %% (%.1f), and its rhythm rests %d ms" % [warrior.damage_pct, slash, warrior.rest_ms])
	await bench.run_named_test(&"versus")
	var rows: Array = bench.last_measure["weapons"]
	_check(rows.size() >= 3 and float(rows[0]["seconds"]) <= float(rows[rows.size() - 1]["seconds"]),
		"versus: every weapon, fastest first (%s %.1f s ... %s %.1f s)" % [rows[0]["weapon"], float(rows[0]["seconds"]), rows[rows.size() - 1]["weapon"], float(rows[rows.size() - 1]["seconds"])])
	await bench.run_named_test(&"loot")
	_check(is_equal_approx(float(bench.last_measure.get("Copper ore", 0.0)), 0.6 * 1.5) and is_equal_approx(float(bench.last_measure.get("Uncut gem", 0.0)), 0.04),
		"loot: 0.9 copper ore a kill (60 %% of 1-2), 0.04 gems (its loot table's)")
	_check(bench.fit_checks().is_empty(), "the warrior fits: %s" % str(bench.fit_checks()))
	var brute := FoeDef.new()
	brute.kit = warrior.kit
	brute.character = warrior.character
	brute.hp = 100000
	brute.damage_pct = 1000
	bench.item = brute
	_check(bench.fit_checks().size() == 2, "a foe nothing kills in a minute, that kills you in seconds, is flagged: %s" % str(bench.fit_checks()))
	bench.queue_free()
	await get_tree().process_frame


func _run_recipe_bench() -> void:
	print("== regents: the recipe bench ==")
	var bar: RecipeDef = RecipeDef.by_id(40001)
	_check(bar.workbench_scene() == "res://game/regents/workbench/recipe_workbench.tscn", "a recipe has its bench (%s)" % bar.workbench_scene())
	var bench: RecipeWorkbench = (load(bar.workbench_scene()) as PackedScene).instantiate() as RecipeWorkbench
	add_child(bench)
	bench.item = bar
	await get_tree().process_frame
	var share: int = int(RecipeWorkbench.rule(&"craft_work_share_pct"))
	_check(share == 60 and RecipeWorkbench.batch_xp(bar) == bar.craft_xp(share), "it reads the hot rules' defaults (a %d %% share)" % share)
	var sheet: String = await bench.run_named_test(&"sheet")
	_check(sheet.contains("2 Copper ore") and sheet.contains("1 Copper bar") and sheet.contains("XP a batch: %d" % RecipeWorkbench.batch_xp(bar)), "the sheet: %s" % sheet)
	await bench.run_named_test(&"per_hour")
	var afk: Dictionary = bench.last_measure.get("afk", {})
	_check(int(afk.get("batches", 0)) == 3_600_000 / bar.afk_ms and int((afk.get("eats", {}) as Dictionary).get("Copper ore", 0)) == 2 * int(afk.get("batches", 0)),
		"an hour AFK: %d bars, eating twice as much ore" % int(afk.get("batches", 0)))
	_check(int(afk.get("xp_hour", 0)) < int(afk.get("xp_fresh", 0)) and int(afk.get("xp_hour", 0)) > int(afk.get("xp_fresh", 0)) / 2,
		"an hour of one recipe wears stale: %d XP, not %d" % [int(afk.get("xp_hour", 0)), int(afk.get("xp_fresh", 0))])
	await bench.run_named_test(&"chain")
	var raw: Dictionary = bench.last_measure.get("raw", {})
	_check(is_equal_approx(float(raw.get("Copper ore", 0.0)), 2.0) and float(bench.last_measure.get("minutes", 0.0)) > 0.0, "a bar's chain: two copper ore")
	var axe: RecipeDef = RecipeDef.by_id(40006)
	bench.item = axe
	await get_tree().process_frame
	await bench.run_named_test(&"chain")
	var axe_raw: Dictionary = bench.last_measure.get("raw", {})
	_check(axe_raw.has("Iron ore") and axe_raw.has("Copper ore") and axe_raw.has("Logs"), "the axe's chain goes back to iron ore, copper ore and logs: %s" % str(axe_raw))
	bench.item = bar
	_check((await bench.run_named_test(&"against")).contains("gathering Copper ore"), "against gathering: %s" % bench.last_result)
	bench.queue_free()
	await get_tree().process_frame


## CHOOSING PARTS AND TRAITS AT THE STATION (owner, 2026-10-23, MATERIALS.md step 3), offline: one line a
## recipe under its heading; a part slot's list of every part of its kind; the traits by the grade it will be
## made at, in use or left out; what `craft_choosing` is sent. (The server's half: the native tests and the
## integration suite; made for real: the skilling playtest.)
func _run_crafting_choice() -> void:
	print("== regents: crafting, choosing parts and traits ==")
	var room: Array[int] = []
	for q: int in [0, 399, 400, 799, 800, 1000]:
		room.append(SkillingComponent.trait_room(q))
	_check(room == [1, 1, 2, 2, 3, 3], "a crafted item holds Common 1, Fine 2, Masterwork 3 traits (hot rules) %s" % str(room))
	var steady: int = _trait_id(&"steady")
	var springy: int = _trait_id(&"springy")
	var gentle: int = _trait_id(&"gentle")
	var heavy: int = _trait_id(&"heavy")
	var thirsting: int = _trait_id(&"thirsting")
	# Each part offers a tool trait and a weapon trait; only the one that fits what is made counts (Luke, 2026-10-23).
	var oak: ItemDef = ItemDef.by_id(40016)
	var copper_r: ItemDef = ItemDef.by_id(40012)
	var steel_r: ItemDef = MaterialTable.cell(MaterialDef.by_key(&"steel"), _pattern(&"rivets"))
	var axe_i: ItemDef = ItemDef.by_id(40015)
	var sword_i: ItemDef = ItemDef.by_id(40019)
	_check(oak.trait_for(axe_i).id == steady and oak.trait_for(sword_i).id == heavy and copper_r.trait_for(axe_i).id == gentle
		and copper_r.trait_for(sword_i).id == thirsting and steel_r.trait_for(sword_i) == null and ItemDef.by_id(40013).trait_for(axe_i) == null,
		"an oak handle gives an axe Steady and a sword Heavy; copper rivets Gentle and Thirsting; steel rivets give a sword nothing yet; a plain handle nothing")
	var sk := SkillingComponent.new()
	var axe: RecipeDef = RecipeDef.by_id(40006)
	var sword: RecipeDef = RecipeDef.by_id(40010)
	var parts: Array[ItemDef] = sk.parts_of(axe)
	_check(parts.size() == 2 and parts[0].id == 40013 and parts[1].id == 40012 and sk.traits_of(axe).size() == 1 and sk.traits_of(axe)[0].id == gentle,
		"the iron axe: two part slots, the plain handle and copper rivets to start; the rivets offer Gentle, wanted")
	sk.set_part(axe, 0, 40016)
	var ids: Array[int] = []
	for t: TraitDef in sk.traits_of(axe):
		ids.append(t.id)
	_check(ids == [steady, gentle], "the oak handle picked: Steady and Gentle offered, both wanted, handle first")
	_check(sk.craft_args(9, axe, false) == [9, 40006, false, [40016, 40012], [steady, gentle]], "craft_choosing is sent the oak handle, the copper rivets, Steady then Gentle %s" % str(sk.craft_args(9, axe, false)))
	sk.want_trait(axe, steady, false)
	_check(sk.craft_args(9, axe, false)[4] == [gentle], "Steady unticked: Gentle alone is sent")
	sk.want_trait(axe, gentle, false)
	_check(sk.traits_of(axe).is_empty() and sk.craft_args(9, axe, false)[4] == [], "both unticked: none (a choice: the axe keeps none)")
	sk.set_part(axe, 0, 40017)
	_check(sk.traits_of(axe).size() == 2 and sk.traits_of(axe)[0].id == springy, "the yew handle picked instead: its Springy offered and ticked again, first")
	sk.set_part(axe, 0, 40004)
	_check(sk.parts_of(axe)[0].id == 40013, "yew LOGS are no handle: the slot keeps a handle (the plain one)")
	sk.set_part(sword, 0, 40016)
	var sword_ids: Array[int] = []
	for t: TraitDef in sk.traits_of(sword):
		sword_ids.append(t.id)
	_check(sword_ids == [heavy, thirsting], "a sword with an oak handle and copper rivets: Heavy and Thirsting, its weapon traits %s" % str(sword_ids))
	_check(SkillingComponent.group_of(axe) == "Axes" and SkillingComponent.group_of(RecipeDef.by_id(40012)) == "Other" and SkillingComponent.core_of(axe) == ItemDef.by_id(40014),
		"headings: the iron axe under Axes, arrow shafts under Other; the axe's core is its head")
	# Tooltips: what a material or a part is for (Luke, 2026-10-23).
	_check(ItemDef.by_id(40011).uses().has("Iron axe head") and ItemDef.by_id(40011).uses().has("Iron rivets") and oak.uses().has("Steel sword"),
		"an iron bar makes the iron axe head and iron rivets; an oak handle goes into any axe, sword or pickaxe")
	var tip: String = oak.tooltip_for()
	_check(tip.contains("On tools: Steady") and tip.contains("On weapons: Heavy") and tip.contains("Makes: "), "the oak handle's tooltip: Steady on tools, Heavy on weapons, what it makes")
	_check(oak.tooltip_for(sword_i).contains("On the iron sword: Heavy"),
		"in a sword's handle list, its tooltip names the one it gives there: Heavy")
	# The window, on the workbench: a Fine and a Masterwork iron axe head, an oak handle, a plain one and rivets.
	sk.part_pick.clear()
	sk.trait_pick.clear()
	var inv := SpaceTimeInventoryComponent.new()
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40014, 1, 0, "{\"q\":650}")
	inv._stacks[2] = SpaceTimeInventoryComponent.Stack.new(2, 40016, 1, 1)
	inv._stacks[3] = SpaceTimeInventoryComponent.Stack.new(3, 40012, 4, 2)
	inv._stacks[4] = SpaceTimeInventoryComponent.Stack.new(4, 40013, 1, 3)
	inv._stacks[5] = SpaceTimeInventoryComponent.Stack.new(5, 40014, 1, 4, "{\"q\":900}")
	_check(sk.core_grades(axe, inv) == {2: 1, 1: 1, 0: 0} and sk.grade_of(axe, inv) == 2 and sk.made_quality(axe, inv) == 900,
		"the heads by grade: one Masterwork, one Fine, no Common; the best (Masterwork, 900) to start")
	sk.grade_pick[axe.id] = 1
	_check(sk.grade_of(axe, inv) == 1 and sk.made_quality(axe, inv) == 650, "Fine picked: made with the Fine head (650)")
	sk.grade_pick[axe.id] = 0
	_check(sk.grade_of(axe, inv) == 2, "Common picked but none in the bag: the best there is")
	sk.grade_pick.clear()
	var st := StationComponent.new()
	st.key = &"workbench"
	st.def = StationDef.by_key(&"workbench")
	var layer := CanvasLayer.new()
	add_child(layer)
	var w := RegentsStationWindow.new()
	w.skilling = sk
	w.inventory = inv
	w.station = st
	w.target = 1
	layer.add_child(w)
	w.refresh()
	w.open()
	await get_tree().process_frame
	var heads: Array[String] = []
	for n: Node in w.find_children("Group_*", "Label", true, false):
		heads.append((n as Label).text)
	_check(heads == ["Handles", "Axes", "Swords", "Pickaxes", "Other"], "the workbench's list: one line a recipe, under Handles, Axes, Swords, Pickaxes, Other %s" % str(heads))
	_check(w.pick_named("Iron axe"), "the iron axe picked")
	var core: OptionButton = w.find_child("Core", true, false) as OptionButton
	_check(core != null and core.item_count == 3 and core.get_selected_id() == 2 and core.get_item_text(0).contains("Masterwork iron axe head")
		and not core.is_item_disabled(0) and not core.is_item_disabled(1) and core.is_item_disabled(2),
		"its head is a list by grade: Masterwork picked, Fine there, Common greyed (none)")
	var part_list: OptionButton = w.find_child("Part_0", true, false) as OptionButton
	_check(part_list != null and part_list.item_count == 3 and part_list.get_selected_id() == 40013 and part_list.get_item_text(1).ends_with("Oak handle: Steady"),
		"its handle slot lists the three handles, the plain one picked, each with the trait it gives (\"%s\")" % (part_list.get_item_text(1) if part_list != null else ""))
	_check(w.traits_line() == "A Masterwork iron axe holds 3 traits", "the traits, said plainly, no quality number (%s)" % w.traits_line())
	w.pick_grade(1)
	await get_tree().process_frame
	_check(w.traits_line() == "A Fine iron axe holds 2 traits", "Fine picked in the head's list: room for two (%s)" % w.traits_line())
	w.pick_part(0, 40016)
	await get_tree().process_frame
	var box: CheckBox = w.find_child("Trait_steady", true, false) as CheckBox
	var state: Label = w.find_child("TraitState_steady", true, false) as Label
	_check(box != null and box.button_pressed and box.text == "1. Steady" and state != null and state.text.ends_with("(in use)")
		and box.get_theme_stylebox(&"hover") is StyleBoxEmpty,
		"the oak handle picked: Steady ticked, first, in use; drawn as a checkbox, not a button")
	_check((w.find_child("TraitState_gentle", true, false) as Label).text.ends_with("(in use)"), "Gentle second, in use (Fine holds two)")
	w.pick_grade(0)
	inv._stacks[6] = SpaceTimeInventoryComponent.Stack.new(6, 40014, 1, 5, "{\"q\":200}")
	w.refresh()
	await get_tree().process_frame
	_check(w.traits_line() == "A Common iron axe holds 1 trait" and (w.find_child("TraitState_gentle", true, false) as Label).text.ends_with("(no room at this grade)"),
		"a Common head picked: room for one; Gentle, second, has no room (%s)" % w.traits_line())
	w.want_trait(steady, false)
	await get_tree().process_frame
	_check((w.find_child("TraitState_steady", true, false) as Label).text.ends_with("(left out)") and (w.find_child("TraitState_gentle", true, false) as Label).text.ends_with("(in use)"),
		"Steady unticked: left out, and Gentle moves up into the room")
	var make: Button = w.find_child("Make", true, false) as Button
	_check(make != null and not make.disabled, "the bag holds a Common head and the rest: MAKE is ready")
	inv._stacks.erase(6)
	w.refresh()
	await get_tree().process_frame
	make = w.find_child("Make", true, false) as Button
	_check(make != null and not make.disabled and w.traits_line() == "A Masterwork iron axe holds 3 traits" and (w.find_child("Core", true, false) as OptionButton).get_selected_id() == 2,
		"the Common head gone: the list falls back to the best there is (Masterwork), shown picked, MAKE ready (%s)" % w.traits_line())
	# REFIT (Luke, 2026-10-23): a made axe in the bag, its parts swapped at a cost.
	inv._stacks[7] = SpaceTimeInventoryComponent.Stack.new(7, 40015, 1, 6, "{\"q\":650,\"h\":40013,\"p\":[40013,40012],\"t\":[%d]}" % gentle)
	inv._stacks[8] = SpaceTimeInventoryComponent.Stack.new(8, 40011, 3, 7)
	sk.bag = inv
	w.refresh()
	await get_tree().process_frame
	var groups: Array[String] = []
	for n: Node in w.find_children("Group_*", "Label", true, false):
		groups.append((n as Label).text)
	_check(groups.back() == "Refit (swap its parts)" and w.pick_named("Fine iron axe (Gentle)"),
		"the iron axe made earlier is listed to refit, last, by its grade and traits %s" % str(groups))
	var data: String = inv._stacks[7].instance_data
	var cost_line: Label = w.find_child("RefitCost", true, false) as Label
	var refit_b: Button = w.find_child("Refit", true, false) as Button
	_check(cost_line != null and cost_line.text == "Costs: 2 Iron bar (you have 3)" and refit_b != null and refit_b.disabled,
		"as it is, nothing to change: only the bars would be paid, so REFIT is greyed (%s)" % (cost_line.text if cost_line != null else "none"))
	w.pick_part(0, 40016)
	await get_tree().process_frame
	cost_line = w.find_child("RefitCost", true, false) as Label
	refit_b = w.find_child("Refit", true, false) as Button
	_check(cost_line.text == "Costs: 1 Oak handle (you have 1), 2 Iron bar (you have 3)" and not refit_b.disabled
		and sk.refit_args(1, 7, axe, data) == [1, 7, [40016, 40012], [steady, gentle]],
		"the oak handle swapped in: it costs the handle and 2 iron bars (the head's metal), REFIT ready, Steady joins Gentle (%s)" % cost_line.text)
	inv._stacks.erase(8)
	w.refresh()
	await get_tree().process_frame
	_check((w.find_child("Refit", true, false) as Button).disabled, "no iron bars: REFIT greyed")
	sk.bag = null
	layer.queue_free()
	st.free()
	sk.free()
	inv.free()
	await get_tree().process_frame


## The pattern with key `key`.
func _pattern(key: StringName) -> PatternDef:
	for p: PatternDef in MaterialTable.patterns():
		if p.key == key:
			return p
	return null


## THE TESTER PAGE (owner, 2026-10-23), offline: what each control sends (the server's half, and its
## refusals, is the integration suite's), the grade it shows, and its button in the Escape menu, hidden
## from anyone who is not the admin.
func _run_tester_page() -> void:
	print("== regents: the tester page ==")
	var page := RegentsTesterPage.new()
	add_child(page)
	page.open()
	await get_tree().process_frame
	var lines: Dictionary[int, String] = page.skill_lines()
	_check(lines.size() == SkillDef.all().size() and lines.get(40002, "") == "Mining: ?",
		"a line per skill (%d); with no player picked, mining reads \"?\" (%s)" % [lines.size(), lines.get(40002, "")])
	var r: ReducerRequest = page.set_rank(77, 40002, 3)
	_check(r.reducer_name == &"admin_set_rank" and r.args == [77, 40002, 3], "Set: admin_set_rank(player, skill, rank) %s" % str(r.args))
	var status: Label = page.find_children("*", "Label", true, false).back() as Label
	_check(status.text == "admin_set_rank: not connected", "and what came of it is said (offline: %s)" % status.text)
	r = page.reset_skills(77)
	_check(r.reducer_name == &"admin_reset_skills" and r.args == [77], "Reset all skills: admin_reset_skills(player)")
	r = page.reset_bag(77)
	_check(r.reducer_name == &"admin_reset_bag" and r.args == [77], "Reset the bag: admin_reset_bag(player)")
	page.pick_item(40024, 25, 700)
	r = page.give_selected()
	_check(page.grade_text() == "stacks: no quality" and r.reducer_name == &"admin_give_item" and r.args == [-1, 40024, 25, 700],
		"Give 25 coal: it stacks, so the page says no quality (the server ignores the number) (%s)" % str(r.args))
	page.pick_item(40034, 1, 850)
	r = page.give_selected()
	_check(page.grade_text() == "Masterwork" and r.args == [-1, 40034, 1, 850], "Give a steel axe at 850: a Masterwork, its quality sent (%s)" % str(r.args))
	page.pick_item(40034, 1, 500)
	_check(page.grade_text() == "Fine", "at 500: Fine")
	page.queue_free()
	# The Escape menu gains the page's button, for the admin only (offline, nobody is).
	var menu: PauseMenu = (load("res://foundation/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	add_child(menu)
	var hud: RegentsHud = (load("res://game/regents/regents_hud.tscn") as PackedScene).instantiate() as RegentsHud
	add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var button: Button = menu.find_child("Tester", true, false) as Button
	_check(button != null and button.text == "Tester (admin)" and not button.visible and hud.tester_page != null and hud.tester_page.get_parent() == menu,
		"the Escape menu has a Tester (admin) button, hidden from a player who is not the admin, its page in the menu")
	# By its words, not its name: Godot renames a second node called "Tester", so a name finds one only.
	var count: Callable = func() -> int:
		return menu.find_children("*", "Button", true, false).filter(func(b: Node) -> bool: return (b as Button).text == "Tester (admin)").size()
	var buttons: int = count.call()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(buttons == 1 and count.call() == 1, "added once, not every frame (%d, then %d)" % [buttons, count.call()])
	hud.queue_free()
	menu.queue_free()
	await get_tree().process_frame


func _params(permille: int = 450) -> ChopParams:
	var p: ChopParams = ChopParams.new()
	p.duration_ms = 10000
	p.swing_ms = 300
	p.stagger_ms = 800
	p.branch_permille = permille
	p.safe_segments = 2
	p.target_chops = 22
	return p


## A model on `p` whose trunk is `trunk` (bottom first), padded with bare pieces.
func _model_with(p: ChopParams, trunk: Array[int]) -> ChopModel:
	var m: ChopModel = ChopModel.start(1, p)
	var segs: PackedInt32Array = m.segments
	for i: int in segs.size():
		segs[i] = trunk[i] if i < trunk.size() else ChopModel.BRANCH_NONE
	m.segments = segs
	return m


## The chain's content: valid, linked as the chain needs, the gathering tiers in order.
func _run_content() -> void:
	print("== regents: the chain's content ==")
	var bad: Array[String] = []
	for type: StringName in [&"skill", &"node", &"recipe", &"station", &"item"]:
		for d: ContentDef in ContentLibrary.items(type):
			if not d.validate().is_empty():
				bad.append("%s %s: %s" % [type, d.display_name, str(d.validate())])
	_check(bad.is_empty(), "every skill, node, recipe, station and item is valid%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))
	var keys: Array[StringName] = []
	for sk: SkillDef in SkillDef.all():
		keys.append(sk.key)
	_check(keys == [&"woodcutting", &"mining", &"smelting", &"smithing", &"crafting", &"swordsmanship", &"axemanship", &"archery", &"sorcery"],
		"five working skills and four weapon masteries: %s" % str(keys))
	var wc: SkillDef = SkillDef.by_key(&"woodcutting")
	_check(wc.rank_of(0) == 1 and wc.rank_of(59) == 1 and wc.rank_of(60) == 2 and wc.rank_of(280) == 4 and wc.progress(100) == Vector2i(40, 90),
		"ranks come from the curve: rank 2 at 60 XP, 4 at 280; 100 XP is 40 of rank 3's 90")
	var names: Array[String] = []
	for n: NodeDef in NodeDef.all_by_tier():
		names.append(n.display_name)
	_check(names == ["Tree", "Oak", "Yew", "Copper rock", "Iron rock", "Coal rock"], "six nodes, by skill then tier: %s" % str(names))
	var prev: ChopParams = null
	for n: NodeDef in NodeDef.all_by_tier():
		if not (n.minigame is ChopParams):
			continue
		var t: ChopParams = n.minigame as ChopParams
		_check(t.target_chops <= ChopModel.max_chops(t), "%s: a full score is reachable (%d of at most %d)" % [n.display_name, t.target_chops, ChopModel.max_chops(t)])
		if prev != null:
			_check(t.branch_permille > prev.branch_permille and t.target_chops > prev.target_chops, "%s is a harder round than the tier below" % n.display_name)
		prev = t
	var yew: NodeDef = NodeDef.by_id(40003)
	_check(yew.min_tool_tier == 2 and yew.min_rank == 4, "a yew needs a tier 2 axe and woodcutting rank 4")
	# The chain, by what each recipe takes and makes.
	var made: Dictionary[String, Array] = {}
	for r: RecipeDef in RecipeDef.all():
		var ins: Array[String] = []
		for i: ItemDef in r.inputs:
			ins.append(i.display_name)
		made[r.output.display_name] = [String(r.station), ins]
	_check(made.get("Copper bar", []) == ["furnace", ["Copper ore"]] and made.get("Iron bar", []) == ["furnace", ["Iron ore"]],
		"the furnace: ore into bars")
	_check(made.get("Iron axe head", []) == ["anvil", ["Iron bar"]] and made.get("Copper rivets", []) == ["anvil", ["Copper bar"]], "the anvil: bars into a head, rivets")
	_check(made.get("Handle", []) == ["workbench", ["Logs"]] and made.get("Iron axe", []) == ["workbench", ["Iron axe head", "Handle", "Copper rivets"]],
		"the workbench: logs into a handle; a head, a handle and rivets into an iron axe")
	var head: RecipeDef = RecipeDef.by_id(40004)
	var axe: RecipeDef = RecipeDef.by_id(40006)
	_check(head.quality == RecipeDef.Quality.FROM_ROUND and head.minigame is ShapeParams and axe.quality == RecipeDef.Quality.FROM_INPUTS and axe.minigame == null,
		"the head is shaped (as good as its round); the axe is assembled (as good as its head)")
	_check(RecipeDef.at(&"furnace").size() == 3 and RecipeDef.at(&"anvil").size() == 12 and RecipeDef.at(&"workbench").size() == 16 and RecipeDef.at(&"orders").is_empty(),
		"three recipes at the furnace (copper, iron, steel bars), twelve at the anvil (rivets, an axe head, a sword blade and a pickaxe head of each metal), sixteen at the workbench (three handles; an axe, a sword and a pickaxe of each metal; the yew bow, arrow shafts, copper arrows, the yew staff), none at the order board")
	_check(made.get("Oak handle", []) == ["workbench", ["Oak logs"]] and made.get("Yew handle", []) == ["workbench", ["Yew logs"]],
		"oak and yew logs carve into their handles")
	_check(RecipeDef.by_id(40001).input_qty[0] == 2 and RecipeDef.by_id(40002).input_qty[0] == 2, "two ores to a bar, never one to one")
	var choices: Array[String] = []
	for it: ItemDef in axe.part_choices():
		choices.append(it.display_name)
	_check(axe.part_slot == 1 and choices == ["Handle", "Oak handle", "Yew handle"], "the iron axe's handle slot takes any handle, plain first: %s" % str(choices))
	_check(RecipeDef.by_id(40001).part_choices().is_empty(), "a recipe with no part slot has no choices")
	var oak_h: ItemDef = ItemDef.by_id(40016)
	var yew_h: ItemDef = ItemDef.by_id(40017)
	_check(oak_h.handle_trait != null and oak_h.handle_trait.key == &"steady" and yew_h.handle_trait != null and yew_h.handle_trait.key == &"springy"
		and ItemDef.by_id(40013).handle_trait == null, "oak gives Steady, yew Springy, a plain handle nothing (template DECISIONS #275)")
	_check(oak_h.handle_trait_text() == "Steady: nodes are 20% less likely to run out; work 5% slower" and ItemDef.by_id(40013).handle_trait_text() == "",
		"a handle's trait in words, gain and cost: %s" % oak_h.handle_trait_text())
	_run_traits()
	var bar: RecipeDef = RecipeDef.by_id(40001)
	var ore_xp: int = (NodeDef.by_id(40004)).xp
	_check(RecipeDef.work_xp(bar.inputs[0]) == ore_xp and bar.craft_xp(100) == bar.xp + 2 * ore_xp and bar.craft_xp(0) == bar.xp,
		"craft XP pays for the work in the inputs (the server's numbers: genre::regents::craft_xp)")
	var bad_part: RecipeDef = axe.duplicate() as RecipeDef
	bad_part.part_slot = 0
	_check(bad_part.validate().any(func(e: String) -> bool: return e.contains("no part")), "a part slot on an item that is no part is refused")
	for key: StringName in [&"furnace", &"anvil", &"workbench"]:
		_check(StationDef.by_key(key) != null, "the %s is a station" % key)
	var iron: ItemDef = ItemDef.by_id(40015)
	_check(iron.tool_tag == &"axe" and iron.tool_tier == 2 and iron.tool_speed_pct == 85 and iron.held_scene != null, "the iron axe: tier 2, 85 % of the time, held as its own")


## THE MATERIAL TABLE as shipped (`MATERIALS.md` step 1): today's hand-written chain re-expressed as cells,
## their ids pinned, nothing out of date; and a cell gone wrong is caught where the bake will see it.
func _run_material_table() -> void:
	print("== regents: the material table ==")
	var keys: Array[StringName] = []
	for m: MaterialDef in MaterialTable.materials():
		keys.append(m.key)
	var pkeys: Array[StringName] = []
	for p: PatternDef in MaterialTable.patterns():
		pkeys.append(p.key)
	_check(keys == [&"copper", &"iron", &"plain_wood", &"oak", &"yew", &"steel"]
		and pkeys == [&"bar", &"axe_head", &"sword_blade", &"handle", &"axe", &"sword", &"pickaxe_head", &"pickaxe", &"rivets"],
		"six materials and nine patterns: %s x %s" % [str(keys), str(pkeys)])
	var bad: Array[String] = []
	for type: StringName in [&"material", &"pattern"]:
		for d: ContentDef in ContentLibrary.items(type):
			if not d.validate().is_empty():
				bad.append("%s: %s" % [d.display_name, str(d.validate())])
	_check(bad.is_empty(), "every material and pattern is valid%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))
	# The ids players hold, pinned: each cell IS the file it was (MATERIALS.md §2).
	var pinned: Dictionary[String, int] = {"copper:bar": 40010, "iron:bar": 40011, "iron:axe_head": 40014, "iron:sword_blade": 40018,
		"iron:axe": 40015, "iron:sword": 40019, "plain_wood:handle": 40013, "oak:handle": 40016, "yew:handle": 40017,
		"copper:axe": 40001, "copper:pickaxe": 40006, "steel:bar": 40025, "copper:rivets": 40012}
	var got: Dictionary[String, int] = {}
	for c: Dictionary in MaterialTable.plan():
		var m: MaterialDef = c["material"]
		var p: PatternDef = c["pattern"]
		var it: ItemDef = MaterialTable.cell(m, p)
		got["%s:%s" % [m.key, p.key]] = it.id if it != null else -1
	var kept: bool = true
	for k: String in pinned:
		kept = kept and got.get(k, -1) == pinned[k]
	_check(got.size() == 27 and kept and not got.values().has(-1),
		"27 cells (three metals in eight patterns, three woods in one), every one made; the items players hold are the cells they were, ids pinned (the starters 40001 and 40006 now copper's): %s" % str(got))
	var problems: Array[String] = MaterialTable.problems()
	_check(problems.is_empty(), "the table is current: every cell and recipe as the table makes it%s" % ("" if problems.is_empty() else ": " + "; ".join(problems)))
	var dry: Dictionary = MaterialTable.generate(false)
	_check((dry["made"] as Array).is_empty() and (dry["updated"] as Array).is_empty() and (dry["errors"] as Array).is_empty(),
		"making it again would change nothing: %s" % str(dry["lines"]))
	var iron: MaterialDef = MaterialDef.by_key(&"iron")
	var plain: MaterialDef = MaterialDef.by_key(&"plain_wood")
	var axe_p: PatternDef = MaterialTable.cell(iron, MaterialTable.patterns()[4]).pattern
	_check(axe_p.item_name(iron) == "Iron axe" and MaterialTable.patterns()[3].item_name(plain) == "Handle",
		"names: \"{m} axe\" of iron is \"Iron axe\"; \"{m} handle\" of plain wood is \"Handle\"")
	var wants: Dictionary = MaterialTable.item_wants(iron, axe_p)
	_check(wants["tool_tier"] == 2 and wants["tool_speed_pct"] == 85 and wants["weapon_damage_pct"] == 100 and wants["tool_tag"] == &"axe",
		"an iron axe's tier, tool speed and Power are iron's: %s" % str(wants))
	var errs: Array[String] = []
	var rw: Dictionary = MaterialTable.recipe_wants(iron, axe_p, ItemDef.by_id(40015), MaterialTable._index(MaterialTable._items()), errs)
	var ins: Array[String] = []
	for it: ItemDef in rw["inputs"] as Array:
		ins.append(it.display_name)
	_check(errs.is_empty() and ins == ["Iron axe head", "Handle", "Copper rivets"] and rw["part_slot"] == 1 and rw["input_qty"] == PackedInt32Array([1, 1, 2]),
		"its recipe from the slots: the iron head (the core), any handle (plain listed, the player's pick), two rivets: %s" % str(ins))
	# A cell gone wrong, in memory only: the bake refuses it through the material's own check.
	var axe: ItemDef = ItemDef.by_id(40015)
	axe.weapon_damage_pct = 90
	var iron_says: Array[String] = iron.validate_with(ContentLibrary.items(&"material"))
	var copper_says: Array[String] = MaterialDef.by_key(&"copper").validate_with(ContentLibrary.items(&"material"))
	_check(iron_says.size() == 1 and iron_says[0].contains("iron_axe.tres") and iron_says[0].contains("weapon_damage_pct: has 90, makes 100")
		and iron_says[0].contains("Make the table"), "an iron axe at 90 %%: iron's check names the file, the field and the fix: %s" % str(iron_says))
	_check(copper_says.is_empty(), "and copper's says nothing (each material reports its own cells)")
	axe.weapon_damage_pct = 100
	iron.tier = 3
	var tier_says: Array[String] = MaterialTable.problems()
	_check(tier_says.size() == 2 and tier_says.all(func(p: String) -> bool: return p.contains("tool_tier: has 2, makes 3"))
		and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_axe.tres")) and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_pickaxe.tres")),
		"iron moved to tier 3: its axe's and pickaxe's tool tiers are out of date (a sword's and a head's have none): %s" % str(tier_says))
	iron.tier = 2
	var recipe: RecipeDef = RecipeDef.by_id(40006)
	var was: Array[ItemDef] = recipe.inputs.duplicate()
	recipe.inputs = [was[0], ItemDef.by_id(40016), was[2]]
	_check(MaterialTable.problems().any(func(p: String) -> bool: return p.contains("iron_axe.tres") and p.contains("inputs")),
		"a table recipe listing an oak handle where the pattern lists the plain one is out of date")
	recipe.inputs = was
	var tuned: int = recipe.xp
	recipe.xp = tuned + 7
	_check(MaterialTable.problems().is_empty(), "a recipe's XP is the designer's: tuning it is never out of date")
	recipe.xp = tuned
	_check(MaterialTable.problems().is_empty(), "everything put back: current again")
	# STEP 2: copper, iron, steel (MATERIALS.md §8).
	var copper: MaterialDef = MaterialDef.by_key(&"copper")
	var steel: MaterialDef = MaterialDef.by_key(&"steel")
	_check(copper.tier == 1 and iron.tier == 2 and steel.tier == 3 and copper.weapon_damage_pct < iron.weapon_damage_pct
		and iron.weapon_damage_pct < steel.weapon_damage_pct and steel.tool_speed_pct < iron.tool_speed_pct and steel.raw == null,
		"the ladder: copper 1, iron 2, steel 3, each a stronger core and a quicker tool; steel has no ore")
	var starter_axe: ItemDef = ItemDef.by_id(40001)
	var starter_pick: ItemDef = ItemDef.by_id(40006)
	_check(starter_axe.display_name == "Copper axe" and starter_axe.material == copper and starter_axe.tool_tier == 1 and starter_axe.weapon_damage_pct == 70
		and starter_pick.display_name == "Copper pickaxe" and starter_pick.tool_tag == &"pick" and starter_pick.tool_tier == 1,
		"the starters are copper's cells, under their old ids: the Copper axe (tier 1, Power 70) and the Copper pickaxe")
	var swords: Array[int] = []
	for m: MaterialDef in [copper, iron, steel]:
		var sw: ItemDef = MaterialTable.cell(m, MaterialTable.patterns()[5])
		swords.append_array([RegentsGrade.power(sw, 0), RegentsGrade.power(sw, 1000)])
	_check(swords == [70, 84, 100, 120, 140, 168], "swords by tier, worst to best: copper 70-84, iron 100-120, steel 140-168: no overlap %s" % str(swords))
	var steel_bar: ItemDef = MaterialTable.cell(steel, MaterialTable.patterns()[0])
	var smelt_steel: RecipeDef = null
	for rr: RecipeDef in RecipeDef.all():
		if rr.output == steel_bar:
			smelt_steel = rr
	var steel_ins: Array[String] = []
	for it: ItemDef in smelt_steel.inputs:
		steel_ins.append(it.display_name)
	_check(steel_bar.by_hand and not smelt_steel.from_table and smelt_steel.station == &"furnace" and steel_ins == ["Iron ore", "Coal"]
		and smelt_steel.input_qty == PackedInt32Array([2, 2]), "the steel bar is a cell by hand: two iron ore and two coal at the furnace")
	var steel_head: RecipeDef = null
	for rr: RecipeDef in RecipeDef.all():
		if rr.output == MaterialTable.cell(steel, MaterialTable.patterns()[1]):
			steel_head = rr
	_check(steel_head.from_table and steel_head.inputs[0] == steel_bar and steel_head.min_rank == 3, "the table's steel axe head takes that bar (at smithing rank 3)")
	steel_bar.by_hand = false
	_check(MaterialTable.problems(steel).any(func(p: String) -> bool: return p.contains("Steel has no raw form")),
		"unticked, the steel bar would be the table's, which cannot make it from no ore: said")
	steel_bar.by_hand = true
	var coal_rock: NodeDef = NodeDef.by_id(40006)
	_check(coal_rock.display_name == "Coal rock" and coal_rock.tier == 3 and coal_rock.min_tool_tier == 2 and coal_rock.min_rank == 3
		and coal_rock.yield_item == ItemDef.by_id(40024) and ItemDef.by_id(40024).display_name == "Coal",
		"the coal rock: mining tier 3, an iron pick (tier 2) and mining rank 3, yielding coal")
	var iron_pick: ItemDef = MaterialTable.cell(iron, MaterialTable.patterns()[7])
	_check(iron_pick.display_name == "Iron pickaxe" and iron_pick.tool_tier >= coal_rock.min_tool_tier and starter_pick.tool_tier < coal_rock.min_tool_tier,
		"the iron pickaxe works coal; the starter's copper one does not")
	# What the types refuse.
	var stray: ItemDef = ItemDef.new()
	stray.id = 1
	stray.display_name = "Stray"
	stray.material = iron
	_check(stray.validate().any(func(e: String) -> bool: return e.contains("both its material and its pattern")), "a cell with a material and no pattern is refused")
	var no_core: PatternDef = axe_p.duplicate() as PatternDef
	var slots: Array[PartSlot] = []
	for s: PartSlot in axe_p.parts:
		var c2: PartSlot = s.duplicate() as PartSlot
		c2.core = false
		slots.append(c2)
	no_core.parts = slots
	_check(no_core.validate().any(func(e: String) -> bool: return e.contains("one slot is its core")), "a pattern with no core slot is refused")
	var nameless: PatternDef = axe_p.duplicate() as PatternDef
	nameless.name_format = "Axe"
	_check(nameless.validate().any(func(e: String) -> bool: return e.contains("{m}")), "a pattern whose names lack {m} is refused")
	var mine: RecipeDef = RecipeDef.by_id(40012).duplicate() as RecipeDef
	mine.from_table = true
	_check(mine.validate().any(func(e: String) -> bool: return e.contains("no cell the table makes")), "a table recipe for an item that is no cell (arrow shafts) is refused")


## MAKING THE TABLE, for real, in a scratch project: a new metal and a new wood become their cells and
## recipes; making it again changes nothing; the designer's numbers survive, the table's fields come back;
## a hole leaves its file (never deleted) and says so; a cell by hand is left alone.
func _run_material_table_writes() -> void:
	print("== regents: making the material table ==")
	var root: String = "user://material_table_test"
	_wipe_dir(root)
	ContentLibrary.root_override = root
	ContentLibrary.genres_override = PackedStringArray(["regents"])
	var c: String = root.path_join("game/regents/content")
	for d: String in ["item", "recipe", "material", "pattern"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(c.path_join(d)))
	var mod := GenreModule.new()
	mod.id = &"regents"
	mod.content_id_base = 40000
	ResourceSaver.save(mod, root.path_join("game/regents/genre.tres"))
	var ore: ItemDef = _scratch_item(c, 40001, "Tin ore")
	var ash_logs: ItemDef = _scratch_item(c, 40002, "Ash logs")
	var pins: ItemDef = _scratch_item(c, 40003, "Pins")
	var tin := MaterialDef.new()
	tin.id = 40001
	tin.display_name = "Tin"
	tin.key = &"tin"
	tin.prefix = "Tin"
	tin.tier = 3
	tin.raw = ore
	tin.weapon_damage_pct = 130
	tin.tool_speed_pct = 70
	tin.work_scale_pct = 200
	tin.rank = 5
	tin.color = Color(0.3, 0.4, 0.5)
	ResourceSaver.save(tin, c.path_join("material/tin.tres"))
	var ash := MaterialDef.new()
	ash.id = 40002
	ash.display_name = "Ash"
	ash.key = &"ash"
	ash.prefix = "Ash"
	ash.family = MaterialDef.Family.WOOD
	ash.raw = ash_logs
	ash.part_trait = load("res://game/regents/content/trait/steady.tres") as TraitDef
	ResourceSaver.save(ash, c.path_join("material/ash.tres"))
	tin = load(c.path_join("material/tin.tres")) as MaterialDef
	ash = load(c.path_join("material/ash.tres")) as MaterialDef
	var crafting: SkillDef = load("res://game/regents/content/skill/crafting.tres") as SkillDef
	var bar: PatternDef = _scratch_pattern(c, 40001, &"bar", "{m} bar", MaterialDef.Family.METAL, [_scratch_slot("ore", PartSlot.Takes.RAW, null, null, null, 2, true)], crafting)
	var head: PatternDef = _scratch_pattern(c, 40002, &"head", "{m} head", MaterialDef.Family.METAL, [_scratch_slot("bar", PartSlot.Takes.SAME_MATERIAL, bar, null, null, 3, true)], crafting)
	var handle: PatternDef = _scratch_pattern(c, 40003, &"handle", "{m} handle", MaterialDef.Family.WOOD, [_scratch_slot("logs", PartSlot.Takes.RAW, null, null, null, 2, true)], crafting, &"handle")
	var axe: PatternDef = _scratch_pattern(c, 40004, &"axe", "{m} axe", MaterialDef.Family.METAL, [
		_scratch_slot("head", PartSlot.Takes.SAME_MATERIAL, head, null, null, 1, true),
		_scratch_slot("handle", PartSlot.Takes.ANY_MATERIAL, handle, ash, null, 1, false),
		_scratch_slot("binding", PartSlot.Takes.ITEM, null, null, pins, 4, false)], crafting, &"", &"axe")
	var first: Dictionary = MaterialTable.generate()
	_check((first["errors"] as Array).is_empty() and (first["made"] as Array).size() == 8 and (first["updated"] as Array).is_empty(),
		"a new metal and a new wood: four cells and four recipes made %s %s" % [str(first["lines"]), str(first["errors"])])
	# As the bake reads them: from disk, every recipe LINKING its cells by file (a copy inside it has no id).
	var inside: Array[String] = []
	for path: String in first["made"] as Array:
		var fresh: RecipeDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RecipeDef
		if fresh == null:
			continue
		for linked: ItemDef in fresh.inputs + [fresh.output]:
			if linked == null or linked.resource_path.is_empty() or linked.resource_path.contains("::"):
				inside.append("%s: %s" % [path.get_file(), linked.display_name if linked != null else "none"])
	_check(inside.is_empty(), "read back from disk, each recipe links its cells by their files, made in the same run (none carried inside) %s" % str(inside))
	var t_axe: ItemDef = MaterialTable.cell(tin, axe)
	var a_handle: ItemDef = MaterialTable.cell(ash, handle)
	_check(t_axe != null and t_axe.display_name == "Tin axe" and t_axe.tool_tier == 3 and t_axe.tool_speed_pct == 70 and t_axe.weapon_damage_pct == 130
		and t_axe.tool_tag == &"axe" and t_axe.max_stack == 1 and t_axe.color == tin.color and t_axe.id >= 40004 and t_axe.resource_path.ends_with("item/tin_axe.tres"),
		"the Tin axe: tin's tier 3, tool speed 70 and Power 130, a new id (%d) and its own file" % (t_axe.id if t_axe != null else -1))
	_check(a_handle != null and a_handle.display_name == "Ash handle" and a_handle.part_tag == &"handle" and a_handle.handle_trait != null
		and a_handle.handle_trait.key == &"steady", "the Ash handle: a handle, giving ash's trait (Steady)")
	var r: RecipeDef = null
	for d: ContentDef in ContentLibrary.items(&"recipe"):
		if (d as RecipeDef).output != null and (d as RecipeDef).output.id == t_axe.id:
			r = d as RecipeDef
	var names: Array[String] = []
	for it: ItemDef in r.inputs:
		names.append(it.display_name)
	_check(r != null and r.from_table and names == ["Tin head", "Ash handle", "Pins"] and r.input_qty == PackedInt32Array([1, 1, 4]) and r.part_slot == 1,
		"its recipe: the tin head, an ash handle (the pick), four pins: %s" % str(names))
	_check(r.xp == 50 and r.afk_ms == 8000 and r.min_rank == 5, "new numbers start from the pattern, scaled by tin (200 %: 50 XP, 8 s) at tin's rank 5")
	var again: Dictionary = MaterialTable.generate()
	_check((again["made"] as Array).is_empty() and (again["updated"] as Array).is_empty() and MaterialTable.problems().is_empty(),
		"making it again changes nothing, and the table is current")
	# The designer tunes; someone edits a field that is the table's.
	r.xp = 999
	ResourceSaver.save(r, r.resource_path)
	t_axe.display_name = "Wrong"
	t_axe.color = Color(1, 0, 0)
	ResourceSaver.save(t_axe, t_axe.resource_path)
	var says: Array[String] = MaterialTable.problems()
	_check(says.size() == 1 and says[0].contains("tin_axe.tres") and says[0].contains("display_name"), "a renamed cell is out of date, its tuned XP and colour are not: %s" % str(says))
	var fix: Dictionary = MaterialTable.generate()
	var reread: ItemDef = load(t_axe.resource_path) as ItemDef
	_check((fix["updated"] as Array).size() == 1 and reread.display_name == "Tin axe" and reread.color == Color(1, 0, 0) and r.xp == 999,
		"making it puts the name back and keeps the colour and the XP")
	# The material moves.
	tin.tier = 4
	ResourceSaver.save(tin, tin.resource_path)
	var moved: Dictionary = MaterialTable.generate()
	_check((moved["updated"] as Array).size() == 1 and String((moved["updated"] as Array)[0]).ends_with("tin_axe.tres") and t_axe.tool_tier == 4,
		"tin to tier 4: only the axe changes (a bar and a head have no tier)")
	# A hole where a cell was: its file stays.
	axe.not_made_of = [tin]
	ResourceSaver.save(axe, axe.resource_path)
	var hole: Array[String] = MaterialTable.problems()
	MaterialTable.generate()
	_check(hole.any(func(p: String) -> bool: return p.contains("tin_axe.tres") and p.contains("does not make")) and FileAccess.file_exists(t_axe.resource_path),
		"a hole where the Tin axe was: said, and its file never deleted (its id may be in bags)")
	t_axe.by_hand = true
	ResourceSaver.save(t_axe, t_axe.resource_path)
	_check(MaterialTable.problems().is_empty(), "ticked by hand: the table leaves it alone")
	axe.not_made_of = []
	ResourceSaver.save(axe, axe.resource_path)
	t_axe.display_name = "My own axe"
	ResourceSaver.save(t_axe, t_axe.resource_path)
	var own: Dictionary = MaterialTable.generate()
	_check((own["made"] as Array).is_empty() and (own["updated"] as Array).is_empty() and t_axe.display_name == "My own axe",
		"a cell by hand counts as made, and stays as written")
	ContentLibrary.root_override = ""
	ContentLibrary.genres_override = null
	RegentsContent.clear()
	_wipe_dir(root)


func _scratch_item(c: String, id: int, n: String) -> ItemDef:
	var it := ItemDef.new()
	it.id = id
	it.display_name = n
	var path: String = c.path_join("item/%s.tres" % ContentLibrary.file_stem(n))
	ResourceSaver.save(it, path)
	return load(path) as ItemDef


func _scratch_pattern(c: String, id: int, key: StringName, fmt: String, fam: MaterialDef.Family, parts: Array[PartSlot], skill: SkillDef,
		part_tag: StringName = &"", kit: StringName = &"") -> PatternDef:
	var p := PatternDef.new()
	p.id = id
	p.display_name = String(key).capitalize()
	p.key = key
	p.name_format = fmt
	p.family = fam
	p.parts = parts
	p.skill = skill
	p.part_tag = part_tag
	p.carries_trait = part_tag != &""
	p.max_stack = 100 if part_tag != &"" else (1 if kit != &"" else 1000)
	p.tool_tag = kit
	p.weapon_kit = kit
	p.xp = 25
	p.afk_ms = 4000
	var path: String = c.path_join("pattern/%s.tres" % key)
	ResourceSaver.save(p, path)
	return load(path) as PatternDef


func _scratch_slot(n: String, t: PartSlot.Takes, pat: PatternDef, dm: MaterialDef, it: ItemDef, q: int, core: bool) -> PartSlot:
	var s := PartSlot.new()
	s.name = n
	s.takes = t
	s.pattern = pat
	s.default_material = dm
	s.item = it
	s.qty = q
	s.core = core
	return s


func _wipe_dir(dir: String) -> void:
	var abs: String = ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f: String in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs.path_join(f))
	for d: String in DirAccess.get_directories_at(abs):
		_wipe_dir(dir.path_join(d))
	DirAccess.remove_absolute(abs)


func _run_trunk() -> void:
	print("== regents: the trunk from a seed ==")
	# The challenge's own generator (pinned against Rust by shared/golden/challenge), so the twin agrees.
	var same_gen: bool = true
	for x: int in [1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 123456789]:
		same_gen = same_gen and ChopModel._next_u32(x) == ChallengeModel._next_u32(x)
	for s: int in [0, 1, -1, 0x1234567890ABCDEF, -0x7000000000000000]:
		same_gen = same_gen and ChopModel._seed_state(s) == ChallengeModel._seed_state(s)
	_check(same_gen, "the trunk's generator and seed fold are the challenge's (xorshift32), high bits included")
	var p: ChopParams = _params()
	var a: PackedInt32Array = ChopModel.branches(42, p, 200)
	_check(a == ChopModel.branches(42, p, 200), "a seed makes the same trunk every time")
	_check(ChopModel.branches(42, p, 20) == a.slice(0, 20), "and its bottom does not depend on how much is made")
	_check(a != ChopModel.branches(43, p, 200), "another seed, another trunk")
	_check(a[0] == ChopModel.BRANCH_NONE and a[1] == ChopModel.BRANCH_NONE, "the bottom pieces are safe (safe_segments 2)")
	var n: int = 20000
	var big: PackedInt32Array = ChopModel.branches(7, p, n)
	var left: int = big.count(ChopModel.BRANCH_LEFT)
	var right: int = big.count(ChopModel.BRANCH_RIGHT)
	var rate: float = float(left + right) / float(n - 2)
	_check(rate > 0.43 and rate < 0.47, "45 %% of pieces carry a branch (%.3f over %d)" % [rate, n])
	_check(absf(float(left) / float(left + right) - 0.5) < 0.03, "left and right alike (%d / %d)" % [left, right])
	_check(ChopModel.branches(7, _params(0), 500).count(ChopModel.BRANCH_NONE) == 500, "0 ‰: no branches")
	_check(ChopModel.branches(7, _params(1000), 500).count(ChopModel.BRANCH_NONE) == 2, "1000 ‰: every piece above the safe ones")


## The golden rounds (made by a third, Python version: `game/regents/tests/make_chop_golden.py`), which the
## server's Rust twin is held to as well (`server/tests/regents.rs`).
func _run_golden() -> void:
	print("== regents: the golden rounds ==")
	var f: FileAccess = FileAccess.open("res://shared/golden/regents/chop.json", FileAccess.READ)
	_check(f != null, "shared/golden/regents/chop.json is there")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var cases: Array = doc.get("cases", []) as Array
	_check(cases.size() >= 10, "it has its cases (%d)" % cases.size())
	var bad: Array[String] = []
	for c: Dictionary in cases:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var pp: Dictionary = c["params"]
		var p: ChopParams = ChopParams.new()
		p.duration_ms = int(pp["duration_ms"])
		p.swing_ms = int(pp["swing_ms"])
		p.stagger_ms = int(pp["stagger_ms"])
		p.branch_permille = int(pp["branch_permille"])
		p.safe_segments = int(pp["safe_segments"])
		p.target_chops = int(pp["target_chops"])
		var want_seg: PackedInt32Array = PackedInt32Array()
		for v: Variant in c["segments"]:
			want_seg.append(int(v))
		var inputs: PackedInt32Array = PackedInt32Array()
		for pair: Array in c["inputs"]:
			inputs.append(int(pair[0]))
			inputs.append(int(pair[1]))
		var e: Dictionary = c["expected"]
		var want: Dictionary = {"clean": int(e["clean"]), "hits": int(e["hits"]), "best_combo": int(e["best_combo"]), "score_pm": int(e["score_pm"])}
		var got: Dictionary = ChopModel.play(seed_value, p, inputs)
		if ChopModel.branches(seed_value, p, want_seg.size()) != want_seg or got != want:
			bad.append("%s: %s, wanted %s" % [c["name"], str(got), str(want)])
	_check(bad.is_empty(), "the GDScript twin plays every golden round exactly%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))


## A params resource from a golden case's numbers (an outline becomes a PackedInt32Array).
func _params_from(res: Resource, pp: Dictionary) -> Resource:
	for key: String in pp:
		var v: Variant = pp[key]
		if v is Array:
			var arr: PackedInt32Array = PackedInt32Array()
			for x: Variant in v:
				arr.append(int(x))
			res.set(key, arr)
		else:
			res.set(key, int(v))
	return res


func _golden_cases(name: String) -> Array:
	var f: FileAccess = FileAccess.open("res://shared/golden/regents/%s.json" % name, FileAccess.READ)
	if f == null:
		_check(false, "shared/golden/regents/%s.json is there" % name)
		return []
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	return doc.get("cases", []) as Array


## The flat inputs of a golden case (rows of 2 or 3).
func _flat(rows: Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for r: Array in rows:
		for v: Variant in r:
			out.append(int(v))
	return out


func _ints(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in d:
		out[k] = int(d[k])
	return out


## Crack the rock, bellows then pour, shape to the outline: the GDScript models against the golden files a
## third (Python) version made, which their Rust twins are held to as well.
func _run_skill_goldens() -> void:
	print("== regents: the chain's golden rounds ==")
	var bad: Array[String] = []
	var crack: Array = _golden_cases("crack")
	for c: Dictionary in crack:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: CrackParams = _params_from(CrackParams.new(), c["params"]) as CrackParams
		var pts: PackedInt32Array = CrackModel.seams(seed_value, p, 3)
		var got: Dictionary = CrackModel.play(seed_value, p, _flat(c["inputs"]))
		if pts != _flat([c["points"]]) or got != _ints(c["expected"]):
			bad.append("crack %s: %s, wanted %s" % [c["name"], str(got), str(c["expected"])])
	var smelt: Array = _golden_cases("smelt")
	for c: Dictionary in smelt:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: SmeltParams = _params_from(SmeltParams.new(), c["params"]) as SmeltParams
		var m: SmeltModel = SmeltModel.start(seed_value, p)
		var bands_ok: bool = true
		var i: int = 0
		for b: Array in c["bands"]:
			bands_ok = bands_ok and m.band(i * 7) == Vector2i(int(b[0]), int(b[1]))
			i += 1
		var got: Dictionary = SmeltModel.play(seed_value, p, _flat(c["inputs"]))
		if not bands_ok or got != _ints(c["expected"]):
			bad.append("smelt %s: %s, wanted %s (bands %s)" % [c["name"], str(got), str(c["expected"]), bands_ok])
	var shape: Array = _golden_cases("shape")
	for c: Dictionary in shape:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: ShapeParams = _params_from(ShapeParams.new(), c["params"]) as ShapeParams
		var start: PackedInt32Array = ShapeModel.start(seed_value, p).heights
		var got: Dictionary = ShapeModel.play(seed_value, p, _flat(c["inputs"]))
		if start != _flat([c["start"]]) or got != _ints(c["expected"]):
			bad.append("shape %s: %s, wanted %s" % [c["name"], str(got), str(c["expected"])])
	_check(crack.size() >= 6 and smelt.size() >= 6 and shape.size() >= 6 and bad.is_empty(),
		"the GDScript models play every golden round exactly (%d crack, %d smelt, %d shape)%s" % [crack.size(), smelt.size(), shape.size(),
			"" if bad.is_empty() else ": " + "; ".join(bad)])


func _run_chops() -> void:
	print("== regents: chopping ==")
	var p: ChopParams = _params()
	var m: ChopModel = _model_with(p, [0, L, 0, R])
	_check(m.head_branch() == L, "the branch at your head is the piece above the cut")
	_check(m.chop(0, L) == ChopModel.HIT and m.cut == 0 and m.hits == 1 and m.combo == 0, "chopping from the branch's side: hit, the trunk does not drop")
	_check(m.chop(799, R) == ChopModel.IGNORED and m.cut == 0, "staggered: a swing 799 ms after the hit is not swung")
	_check(m.chop(800, R) == ChopModel.CLEAN and m.cut == 1 and m.clean == 1, "at 800 ms (stagger_ms), from the other side: clean, the trunk drops")
	_check(m.head_branch() == ChopModel.BRANCH_NONE and m.chop(1099, R) == ChopModel.HELD and m.cut == 1, "mid-swing (299 ms after a chop): held, not dropped")
	_check(m.settle(1099) == ChopModel.IGNORED and m.settle(1100) == ChopModel.CLEAN and m.cut == 2 and m.head_branch() == R,
		"it swings the moment the swing ends (1100): clean, and the next branch is on your side")
	_check(m.chop(1400, R) == ChopModel.HIT and m.chop(2200, L) == ChopModel.CLEAN, "stay under it and it hits; step across and chop")
	_check(m.best_combo == 2 and m.combo == 1, "a hit ends a combo (best 2, now 1)")
	var q: ChopModel = _model_with(p, [])
	_check(q.chop(0, L) == ChopModel.CLEAN and q.chop(100, L) == ChopModel.HELD and q.chop(200, R) == ChopModel.HELD
		and q.chop(300, R) == ChopModel.HELD and q.side == R and q.clean == 2, "quick side switches: the latest held press swings when the swing ends")
	var e: ChopModel = _model_with(p, [])
	e.chop(9800, L)
	_check(e.chop(9900, R) == ChopModel.HELD and ChopModel.play(1, p, PackedInt32Array([9800, L, 9900, R]))["clean"] == 1,
		"a press held past the round's end never swings")
	var o: ChopModel = _model_with(p, [])
	_check(o.chop(-1, L) == ChopModel.IGNORED and o.chop(0, 0) == ChopModel.IGNORED and o.chop(0, 3) == ChopModel.IGNORED,
		"before the round, or no side: nothing")
	_check(o.chop(500, L) == ChopModel.CLEAN and o.chop(400, L) == ChopModel.IGNORED and o.chop(900, L) == ChopModel.CLEAN,
		"a press earlier than the last one is out of order: nothing")
	_check(o.chop(10000, R) == ChopModel.CLEAN and o.chop(10001, R) == ChopModel.IGNORED and o.clean == 3,
		"the round's last millisecond counts; after it, nothing")
	o.clean = 11
	_check(o.score_pm() == 500, "11 of a 22-log target scores half (%d)" % o.score_pm())
	o.clean = 40
	_check(o.score_pm() == 1000, "more than the target scores no more")


## A player who never misses: a swing every `swing_ms` from the side the next branch is not on.
func _perfect_inputs(seed_value: int, p: ChopParams) -> PackedInt32Array:
	var m: ChopModel = ChopModel.start(seed_value, p)
	var out: PackedInt32Array = PackedInt32Array()
	var t: int = 0
	while t <= p.duration_ms:
		var side: int = R if m.head_branch() == L else (L if m.head_branch() == R else m.side)
		out.append_array(PackedInt32Array([t, side]))
		m.chop(t, side)
		t += p.swing_ms
	return out


func _run_perfect_and_replay() -> void:
	print("== regents: a perfect round, and a replay ==")
	for n: NodeDef in NodeDef.all_by_tier():
		if not (n.minigame is ChopParams):
			continue
		var t: ChopParams = n.minigame as ChopParams
		var r: Dictionary = ChopModel.play(99, t, _perfect_inputs(99, t))
		_check(r["hits"] == 0 and r["clean"] == ChopModel.max_chops(t) and r["score_pm"] == 1000,
			"%s: never under a branch, every swing on time: %d logs, no hits, a full score" % [n.display_name, r["clean"]])
	# Pressing blind (always left) on a branchy tree: hit, staggered, far short.
	var p: ChopParams = _params(600)
	var blind: PackedInt32Array = PackedInt32Array()
	for k: int in 34:
		blind.append_array(PackedInt32Array([k * 300, L]))
	var b: Dictionary = ChopModel.play(5, p, blind)
	_check(b["hits"] > 0 and b["score_pm"] < 1000, "always the left on a branchy tree: hit %d times, scores %d ‰" % [b["hits"], b["score_pm"]])
	# The replay is the inputs': change one side and a different round is scored.
	var perfect: PackedInt32Array = _perfect_inputs(5, p)
	var m: ChopModel = ChopModel.start(5, p)
	var flip: int = -1
	var i: int = 0
	while i + 1 < perfect.size():
		if m.head_branch() != ChopModel.BRANCH_NONE:
			flip = i
			break
		m.chop(perfect[i], perfect[i + 1])
		i += 2
	var tampered: PackedInt32Array = perfect.duplicate()
	tampered[flip + 1] = m.head_branch()
	var pr: Dictionary = ChopModel.play(5, p, perfect)
	var tr: Dictionary = ChopModel.play(5, p, tampered)
	# The stagger puts every later swing off the perfect player's timing, so the hits go on from there.
	_check(flip >= 0 and pr["hits"] == 0 and int(tr["hits"]) >= 1 and tr["clean"] < pr["clean"],
		"one swing moved under a branch: the replay scores the hit and what it cost (%s vs %s)" % [str(tr), str(pr)])


## Working, shown: each skill's pose in the adventurer's set (UAL clips), each tool a held item fitted to its
## skill's pose, and the adventurer carries the skilling and the look of it.
func _run_looks() -> void:
	print("== regents: working, shown ==")
	var adv: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	var aset: AnimationSet = adv.animation_set if adv != null else null
	var clips: Dictionary[StringName, StringName] = {&"pose.chop": &"extra/TreeChopping", &"pose.mine": &"extra/Mining", &"pose.smith": &"extra/Mining",
		&"pose.smelt": &"Push", &"pose.craft": &"Interact"}
	for pose: StringName in clips:
		var ref: AnimationClipRef = aset.clip(pose) if aset != null and aset.has_exact(pose) else null
		_check(ref != null and ref.anim_name == clips[pose] and ref.loop, "the set's %s is %s, looping" % [pose, clips[pose]])
	_check(aset != null and aset.missing_required().is_empty(), "the set still drives a tree (nothing required missing)")
	for sk: SkillDef in SkillDef.all():
		if KitDef.all().any(func(k: KitDef) -> bool: return k.skill == sk):
			continue   # a weapon mastery: trained by fighting, no working pose
		_check(aset.has_exact(sk.pose), "%s works in the set's %s" % [sk.display_name, sk.pose])
	for k: KitDef in KitDef.all():
		var abilities: Array[AbilityDef] = []
		abilities.assign(k.light + k.skills)
		if k.heavy != null:
			abilities.append(k.heavy)   # a bow has none
		for a: AbilityDef in abilities:
			# The driver plays an ability as `ability.<id>` (anything else falls back to Interact: owner, 2026-10-19).
			_check(a.animation == StringName("ability.%d" % a.id) and aset.has_exact(a.animation) and aset.clip(a.animation).anim_name != aset.clip(&"interact").anim_name,
				"the %s kit's %s plays the set's ability.%d, its own clip (%s)" % [k.key, a.display_name, a.id, aset.clip(a.animation).anim_name if aset.has_exact(a.animation) else "none"])
	_check(aset.has_exact(&"ability.40010") and aset.clip(&"ability.40010").anim_name == &"Roll" and aset.has_exact(&"pose.block"), "the roll plays Roll; the block is in the set")
	var tools: Dictionary[String, StringName] = {"res://game/regents/skilling/woodcutting/axe.tscn": &"pose.chop",
		"res://game/regents/skilling/woodcutting/iron_axe.tscn": &"pose.chop", "res://game/regents/skilling/mining/pickaxe.tscn": &"pose.mine",
		"res://game/regents/skilling/smithing/hammer.tscn": &"pose.smith"}
	for path: String in tools:
		var node: Node = (load(path) as PackedScene).instantiate()
		var held: HeldItem = node as HeldItem
		var fitted: bool = false
		if held != null and held.grip != null:
			# Its own grip for the working pose, or one grip for all it uses there (the owner's way since #259).
			fitted = held.grip.universal and held.grip.resolve(tools[path]) != null
			for e: GripEntry in held.grip.entries:
				fitted = fitted or e.animation == tools[path]
		_check(held != null and held.grip.hand == &"hand_r" and fitted, "%s is a held item, held in %s (its own grip there, or its one grip for all)" % [path.get_file(), tools[path]])
		node.free()
	_check(ItemDef.by_id(40001).held_scene != null and ItemDef.by_id(40006).held_scene != null and SkillDef.by_key(&"smithing").tool_scene != null,
		"the copper axe and pickaxe show as themselves; the smith holds a hammer")
	var player: Node = (load("res://game/regents/adventurer.tscn") as PackedScene).instantiate()
	_check(player.get_node_or_null(^"Components/SkillingLook") is SkillingLook and player.get_node_or_null(^"Components/Skilling") is SkillingComponent,
		"the adventurer carries its skilling and the look of it")
	player.free()
	# Slain mid-chop: the death plays alone (a playtest, 2026-10-20: the chop went on over it, and after).
	var look := SkillingLook.new()
	var work := SkillingComponent.new()
	var hp := SpaceTimeHealthComponent.new()
	work.afk_target = 5
	look.set(&"_skilling", work)
	look.set(&"_health", hp)
	_check(look.working(), "chopping AFK: working (the pose plays)")
	hp.set(&"_is_dead", true)
	_check(not look.working(), "slain: not working, so no chop's pose over the death")
	hp.set(&"_is_dead", false)
	work.afk_target = -1
	_check(not look.working(), "up again, the work stopped by the server: still none")
	look.free()
	work.free()
	hp.free()


## The minigames in one place: their kinds, the server's challenge kinds, a faster tool's swing.
func _run_registry() -> void:
	print("== regents: the minigames' registry ==")
	_check(SkillMinigames.CHALLENGE == {&"chop": 100, &"crack": 101, &"smelt": 102, &"shape": 103}, "the challenge kinds the server deals them as")
	var chop: ChopParams = _params()
	var fast: ChopParams = SkillMinigames.with_speed(chop, 85) as ChopParams
	_check(fast != chop and fast.swing_ms == 255 and chop.swing_ms == 300, "a tool at 85 %% swings in 255 ms, and the content is left as it was")
	_check(SkillMinigames.with_speed(chop, 100) == chop and SkillMinigames.with_speed(SmeltParams.new(), 50) is SmeltParams,
		"as authored at 100 %%; a station round has no swing to speed")
	_check(SkillMinigames.arity(SkillMinigames.CRACK) == 3 and SkillMinigames.arity(SkillMinigames.SHAPE) == 2, "a strike on the rock is (time, x, y)")
	var baked: Dictionary = SkillMinigames.bake((RecipeDef.by_id(40004)).minigame)
	_check(baked.get("kind", "") == "shape" and (baked.get("outline", []) as Array).size() == 16 and not baked.has("display_name"),
		"a round bakes as its kind and its numbers")


func _run_minigame() -> void:
	print("== regents: the minigame ==")
	var g: ChopMinigame = ChopMinigame.new()
	g.size = Vector2(1280, 720)
	add_child(g)
	var p: ChopParams = _params(500)
	var seen: Array[Dictionary] = []
	g.round_finished.connect(func(live: Dictionary, replayed: Dictionary) -> void:
		seen.append(live)
		seen.append(replayed))
	_check(g.press_at(0, L) == ChopModel.IGNORED and g.inputs.is_empty(), "before a round, a press is nothing and is not kept")
	g.begin(77, p)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var t: int = -50
	var events: Dictionary = {}
	var sides: Array[int] = [L, R, L, R, 0]
	for k: int in 120:
		var side: int = sides[rng.randi_range(0, 4)]
		var ev: int = g.press_at(t, side)
		events[ev] = int(events.get(ev, 0)) + 1
		t += rng.randi_range(-40, 220)
	_check(g.inputs.size() == 240, "every press is kept, the ignored ones too (%d values)" % g.inputs.size())
	_check(events.has(ChopModel.CLEAN) and events.has(ChopModel.HIT) and events.has(ChopModel.IGNORED),
		"a messy player chops, gets hit, and swings when it cannot (%s)" % str(events))
	await get_tree().process_frame
	g.finish()
	_check(seen.size() == 2 and seen[0] == seen[1] and seen[0] == ChopModel.play(77, p, g.inputs),
		"the round's end: what was played is what a replay of its inputs scores (%s)" % (str(seen[0]) if seen.size() > 0 else "none"))
	_check(g.press_at(t, L) == ChopModel.IGNORED and g.inputs.size() == 240, "after the round, presses are nothing")
	g.queue_free()
	await get_tree().process_frame


## Crack the rock, bellows then pour, shape to the outline: played through their UIs, every input kept, and
## what was played is what a replay of the inputs scores.
func _run_chain_minigames() -> void:
	print("== regents: the chain's minigames, played ==")
	var crack: CrackMinigame = CrackMinigame.new()
	crack.size = Vector2(960, 620)
	add_child(crack)
	var rock: CrackParams = (NodeDef.by_id(40004)).minigame as CrackParams
	crack.begin(11, rock)
	var t: int = 0
	var hits: int = 0
	while t < rock.duration_ms:
		if t >= crack.model.next_ok_ms + 250:
			var g: Vector2i = crack.model.notch(crack.model.k)
			hits += int(crack.strike_at(t, g.x, g.y) == CrackModel.HIT)
		t += 10
	crack.strike_at(t, 0, 0)
	crack.finish()
	_check(hits >= 12 and crack.model.splits >= 1 and crack.live_result == crack.replayed_result and crack.inputs.size() % 3 == 0,
		"follow the seam: %d notches struck in order, %d split, every strike kept as (t, x, y), the replay agrees" % [hits, crack.model.splits])
	_check(crack.to_face(crack.from_face(Vector2i(300, 700))).distance_to(Vector2i(300, 700)) <= 1, "a click on the face is where the strike lands")
	crack.queue_free()
	# The seam's rules, one strike at a time.
	var cm: CrackModel = CrackModel.start(11, rock)
	var n0: Vector2i = cm.notch(0)
	var n1: Vector2i = cm.notch(1)
	var first: Vector2i = cm.notch(0)
	var across: bool = true
	for i: int in rock.notches - 1:
		across = across and absi(cm.notch(i + 1).x - cm.notch(i).x) <= rock.bend_pm and cm.notch(i + 1).y > cm.notch(i).y
	_check(first.y == rock.margin_pm and cm.notch(rock.notches - 1).y == 1000 - rock.margin_pm and across,
		"the first seam runs top to bottom, each notch within %d‰ across of the last" % rock.bend_pm)
	_check(cm.notch(rock.notches).x == rock.margin_pm and cm.notch(2 * rock.notches - 1).x == 1000 - rock.margin_pm,
		"the second runs left to right")
	_check(cm.strike(0, n1.x, n1.y) == CrackModel.JAR and cm.jars == 1, "a notch out of order is off the seam: the pick jars")
	_check(cm.strike(100, n0.x, n0.y) == CrackModel.IGNORED and cm.k == 0, "staggered: a strike then is lost")
	_check(cm.strike(rock.stagger_ms, n0.x + rock.radius_pm, n0.y) == CrackModel.HIT and cm.k == 1, "the next notch, at its radius's edge: the crack opens")
	_check(cm.strike(rock.stagger_ms + 10, n1.x, n1.y) == CrackModel.HELD and cm.k == 1, "mid-swing, the next strike is held")
	_check(cm.settle(rock.stagger_ms + rock.swing_ms) == CrackModel.HIT and cm.k == 2, "and lands the moment the pick is back up")
	var full: CrackModel = CrackModel.start(11, rock)
	var tt: int = 0
	for i: int in rock.notches:
		full.strike(tt, full.notch(i).x, full.notch(i).y)
		tt += rock.swing_ms
	_check(full.splits == 1 and full.next_ok_ms == tt - rock.swing_ms + rock.split_ms, "the whole seam opened: the rock splits, and the next seam waits %d ms" % rock.split_ms)
	var smelt: SmeltMinigame = SmeltMinigame.new()
	add_child(smelt)
	var bar: SmeltParams = (RecipeDef.by_id(40001)).minigame as SmeltParams
	smelt.begin(12, bar)
	t = 0
	while t < bar.heat_ms:
		smelt.model.advance_to(t)
		if smelt.model.heat < smelt.model.band(smelt.model.tick).x:
			smelt.press_at(t, SmeltModel.PUMP)
		t += 20
	_check(smelt.press_at(bar.heat_ms + 50, SmeltModel.POUR) == SmeltModel.IGNORED and not smelt.model.pouring,
		"mashing into the pour does not tilt the crucible (%d ms to be ready)" % bar.pour_ready_ms)
	_check(smelt.press_at(bar.heat_ms + 80, SmeltModel.STOP) == SmeltModel.IGNORED, "nor does letting go stop a pour that never began")
	t = bar.heat_ms + bar.pour_ready_ms
	_check(smelt.press_at(t, SmeltModel.POUR) == SmeltModel.DONE and smelt.model.pouring, "ready: holding tilts it")
	while smelt.model.fill < smelt.model.target and t < bar.heat_ms + bar.pour_ms - 100:
		t += 10
		smelt.model.advance_to(t)
	smelt.press_at(t, SmeltModel.STOP)
	smelt.finish()
	var top: SmeltModel = SmeltModel.start(12, bar)
	var ready: int = bar.heat_ms + bar.pour_ready_ms
	top.press(ready, SmeltModel.POUR)
	top.press(ready + 500, SmeltModel.STOP)
	var fill_once: int = top.fill
	_check(fill_once == 10 * bar.pour_rate and top.press(ready + 700, SmeltModel.POUR) == SmeltModel.DONE
		and top.press(ready + 750, SmeltModel.STOP) == SmeltModel.DONE and top.fill == fill_once + bar.pour_rate,
		"a pour stops when let go; tilting again tops it up (one tick: %d)" % bar.pour_rate)
	var sr: Dictionary = smelt.live_result
	_check(int(sr["heat_pm"]) > 600 and int(sr["pour_pm"]) > 800 and smelt.live_result == smelt.replayed_result,
		"bellows then pour: a steady hand keeps the heat (%d) and pours to the line (%d), the replay agrees" % [sr["heat_pm"], sr["pour_pm"]])
	smelt.queue_free()
	var shape: ShapeMinigame = ShapeMinigame.new()
	add_child(shape)
	var part: ShapeParams = (RecipeDef.by_id(40004)).minigame as ShapeParams
	shape.begin(13, part)
	t = 0
	while t < part.duration_ms:
		if t >= shape.model.next_ok_ms:
			if shape.model.hot_until_ms - t < 400:
				shape.strike_at(t, ShapeModel.REHEAT_COLUMN)
			else:
				var best: int = 0
				for i: int in shape.model.heights.size():
					if shape.model.heights[i] - part.outline[i] > shape.model.heights[best] - part.outline[best]:
						best = i
				if shape.model.heights[best] - part.outline[best] <= 0:
					break
				shape.strike_at(t, best)
		t += 10
	shape.finish()
	_check(int(shape.live_result["score_pm"]) > 600 and shape.live_result == shape.replayed_result,
		"shape to the outline: a careful smith comes close (%d), the replay agrees" % shape.live_result["score_pm"])
	shape.queue_free()
	await get_tree().process_frame


## The skilling lab: a button per round in the content; picking one shows that minigame, ready to play.
func _run_lab() -> void:
	print("== regents: the skilling lab ==")
	var lab: Node = (load("res://game/regents/skilling/skilling_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	await get_tree().process_frame
	var buttons: Array[Button] = []
	buttons.assign(lab.get("buttons"))
	var game: SkillMinigame = lab.get("game") as SkillMinigame
	_check(buttons.size() == 18 and game is ChopMinigame and game.state == SkillMinigame.State.READY,
		"eighteen rounds to play (six nodes; three bars and nine smithed parts), the first, a tree's, on show (%d)" % buttons.size())
	if buttons.size() == 9:
		buttons[3].pressed.emit()
		game = lab.get("game") as SkillMinigame
		_check(game is CrackMinigame and buttons[3].button_pressed and not buttons[0].button_pressed, "the copper rock's button shows crack the rock, lit alone")
		buttons[5].pressed.emit()
		game = lab.get("game") as SkillMinigame
		_check(game is SmeltMinigame, "a bar's shows bellows then pour")
		game.begin(1, game.params)
		buttons[7].pressed.emit()
		_check(lab.get("game") == game, "mid-round, the round stays as it is")
		game.finish()
		buttons[7].pressed.emit()
		_check(lab.get("game") is ShapeMinigame, "after it, the axe head's button shows shape to the outline")
	lab.queue_free()
	await get_tree().process_frame


## TRAITS IN REGENT'S RULE (template DECISIONS #275): the v1 pools, what an item is, and the client's twins
## of the server's numbers (`server/tests/regents.rs` has the same cases).
func _run_traits() -> void:
	print("== regents: traits ==")
	var keys: Array[String] = []
	for f: Dictionary in ContentLibrary.files():
		if String(f["path"]).begins_with(ContentLibrary.folder_for(&"trait", "regents") + "/"):
			var d: TraitDef = load(String(f["path"])) as TraitDef
			if d != null:
				keys.append(String(d.key))
				_check(d.validate().is_empty(), "%s is a trait that trades (%s)" % [d.key, str(d.validate())])
	keys.sort()
	_check(keys == ["balanced", "brutal", "gentle", "heavy", "hunters", "lucky", "prospectors", "springy", "steady", "swift_draw", "thirsting"],
		"the v1 pools, less what waits for crits, armour and reach: %s" % str(keys))
	var iron_axe: ItemDef = ItemDef.by_id(40015)
	var bow: ItemDef = null
	for d: ContentDef in RegentsContent.items(&"item"):
		if (d as ItemDef).weapon_kit == &"bow":
			bow = d as ItemDef
	_check(iron_axe.tags() == [&"tool", &"axe", &"weapon", &"axe", &"melee"] and bow != null and bow.tags() == [&"weapon", &"bow", &"bow"],
		"what an item is, as the server says (%s / %s)" % [str(iron_axe.tags()), str(bow.tags() if bow != null else [])])
	var yew: TraitDef = ItemDef.by_id(40017).handle_trait
	_check(ItemDef.trait_ids("{\"q\":612,\"h\":40017,\"t\":[%d]}" % yew.id) == ([yew.id] as Array[int]), "a made tool's traits, from its row")
	_check(ItemDef.trait_ids("{\"q\":700,\"h\":40016}") == ([ItemDef.by_id(40016).handle_trait.id] as Array[int]),
		"a tool made before traits (only its handle noted): its handle's")
	_check(ItemDef.trait_ids("{\"q\":700}").is_empty(), "a plain made item: none")
	# The twins (the server's `action_tags`, `lock_with`, `draw_full_with`).
	var axe_kit: KitDef = KitDef.by_key(&"axe")
	_check(CombatComponent.action_tags(axe_kit, axe_kit.light[0]) == [&"basic"] and CombatComponent.action_tags(axe_kit, axe_kit.light[-1]) == [&"basic", &"combo_last"]
		and CombatComponent.action_tags(axe_kit, axe_kit.heavy) == [&"heavy"] and CombatComponent.action_tags(axe_kit, axe_kit.skills[0]) == [&"skill"],
		"what an action is: basic, the combo's last, heavy, skill")
	var balanced: Array[int] = [_trait_id(&"balanced")]
	var heavy: Array[int] = [_trait_id(&"heavy")]
	_check(CombatComponent.lock_with(900, 400, Traits.mult(balanced, &"recovery", [&"basic"])) == 825
		and CombatComponent.lock_with(900, 400, Traits.mult(heavy, &"recovery", [&"basic"])) == 975 and CombatComponent.lock_with(900, 400, 1.0) == 900,
		"Balanced recovers 15% faster, Heavy 15% slower, the wind-up as it was (the server's 825 / 975)")
	_check(roundi(800.0 * Traits.mult([_trait_id(&"swift_draw")], &"draw_time")) == 640, "Swift Draw: 800 ms -> 640, as the server")


func _trait_id(key: StringName) -> int:
	for f: Dictionary in ContentLibrary.files():
		if String(f["path"]).begins_with(ContentLibrary.folder_for(&"trait", "regents") + "/"):
			var d: TraitDef = load(String(f["path"])) as TraitDef
			if d != null and d.key == key:
				return d.id
	return -1
