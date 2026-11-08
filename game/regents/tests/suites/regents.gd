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
	_run_readout()
	_run_active_pay()
	_run_looks()
	_run_registry()
	_run_beat()
	_run_brittle()
	await _run_minigame()
	await _run_chain_minigames()
	await _run_two_strikes()
	await _run_stages()
	await _run_work_spot()
	await _run_lab()
	await _run_recipe_bench()
	await _run_foe_bench()
	await _run_combat()
	_run_polish()
	await _run_tester_page()
	await _run_crafting_choice()
	await _run_solid()
	_run_referee_walls()
	_run_cells()
	_run_continent()
	await _run_streamed_solids()
	await _run_roles()
	_run_status_bars()
	_run_tutorial()


## THE CONTINENT (PROGRESS step 23): the generated level is baked as level 21, streamed, with the glade's
## camp at its origin exactly as the glade has it, and every scattered point one the server can spawn.
func _run_continent() -> void:
	print("== regents: the continent ==")
	var bake: LevelBake = LevelBake.by_id(21)
	_check(bake != null, "level 21 is baked (shared/world/continent.json)")
	if bake == null:
		return
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://shared/world/continent.json")) as Dictionary
	_check(str(doc.get("level", "")) == "continent" and ResourceLoader.exists(str(doc.get("scene", ""))),
		"its scene is there: %s" % doc.get("scene", ""))
	var scene: PackedScene = load(str(doc["scene"])) as PackedScene
	var root: Node3D = scene.instantiate() as Node3D
	var info: LevelInfo = LevelBaker.find_info(root)
	_check(info != null and info.streamed and info.level_id == 21 and LevelCells.cells_node(root) != null,
		"a streamed level with its Cells")
	var cells: Dictionary[int, String] = LevelCells.read(LevelCells.folder_for(str(doc["scene"]), "continent"))
	_check(cells.size() > 300, "cut into cells for players' games: %d" % cells.size())
	root.free()
	# The camp: the glade's every point, at the same place, so whatever works in the glade works here.
	var glade: LevelBake = LevelBake.by_id(20)
	var theirs: Dictionary = {}
	for p: Dictionary in (doc["points"] as Array):
		theirs[str(p["id"])] = p
	var moved: Array[String] = []
	var glade_points: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://shared/world/frontier.json")) as Dictionary)["points"]
	for p: Dictionary in glade_points:
		var q: Dictionary = theirs.get(str(p["id"]), {})
		if q.is_empty() or Vector3(float(p["x"]), float(p["y"]), float(p["z"])).distance_to(Vector3(float(q["x"]), float(q["y"]), float(q["z"]))) > 0.01:
			moved.append(str(p["id"]))
	_check(glade != null and moved.is_empty(), "the glade's %d points are all in its camp, where the glade has them (moved or missing: %s)" % [glade_points.size(), str(moved)])
	# The rest: nodes of a known kind, foes of a known kind, on dry land.
	var bad: Array[String] = []
	var nodes: int = 0
	var foes: int = 0
	for p: Dictionary in (doc["points"] as Array):
		var kind: String = str(p["kind"])
		var at := Vector3(float(p["x"]), float(p["y"]), float(p["z"]))
		if not bake.can_stand(at.x, at.z) or bake.is_water(at.x, at.z):
			bad.append("%s in the sea" % p["id"])
		if kind == "node":
			nodes += 1
			var tags: Array = p["tags"]
			if tags.is_empty() or NodeDef.all_by_tier().filter(func(d: NodeDef) -> bool: return d.display_name == str(tags[0])).is_empty():
				bad.append("%s is no node (%s)" % [p["id"], str(tags)])
		elif kind.begins_with("skeleton"):
			foes += 1
			if FoeDef.all().filter(func(f: FoeDef) -> bool: return String(f.key) == kind).is_empty():
				bad.append("%s is no foe (%s)" % [p["id"], kind])
	_check(bad.is_empty(), "every point is a node or foe the game has, on dry land: %s" % str(bad.slice(0, 5)))
	_check(nodes > 300 and foes > 30, "a world to visit: %d nodes, %d foes" % [nodes, foes])
	# The sea: wet off the coast, dry at the camp; the server's grid is the coarse one.
	_check(not bake.is_water(0.0, 0.0) and bake.can_stand(0.0, 8.0), "the camp is dry ground")
	# A corner of the server's grid (off the grid counts as standable): open sea, past any coast.
	var grid: Dictionary = doc["depth_grid"]
	var sea := Vector2(float(grid["origin_x"]) + 20.0, float(grid["origin_z"]) + 20.0)
	_check(float(grid["spacing"]) == 4.0 and bake.is_water(sea.x, sea.y) and not bake.can_stand(sea.x, sea.y),
		"the sea at the grid's corner %s is deep water, not standable" % str(sea))


## A STREAMED LEVEL'S PROPS ARE SOLID AS THEIR CELL ARRIVES (PROGRESS step 23): a cell's scene added under
## the props after the level loaded gets its rocks wrapped under it, and they go with it.
func _run_streamed_solids() -> void:
	print("== regents: props solid as their cell streams in ==")
	var level := Node3D.new()
	var props := Node3D.new()
	props.name = "Cells"
	level.add_child(props)
	var solid: RegentsSolidProps = (load("res://game/regents/levels/solid_props.gd") as GDScript).new() as RegentsSolidProps
	solid.props = NodePath("../Cells")
	level.add_child(solid)
	add_child(level)
	await get_tree().process_frame
	var cell := Node3D.new()
	cell.name = "Cell_0_0"
	var rock: Node3D = (load("res://game/regents/art/nature/Rock_Medium_1.gltf") as PackedScene).instantiate() as Node3D
	cell.add_child(rock)
	var grass: Node3D = (load("res://game/regents/art/nature/Grass_Common_Short.gltf") as PackedScene).instantiate() as Node3D
	cell.add_child(grass)
	props.add_child(cell)
	await get_tree().process_frame
	var bodies: Array[Node] = cell.find_children("Solid", "StaticBody3D", false, false)
	_check(bodies.size() == 1 and solid.made_solid.has(rock) and not solid.made_solid.has(grass),
		"the rock in the arriving cell is solid, the grass is not (%d bodies)" % bodies.size())
	var body: Node = bodies[0] if not bodies.is_empty() else null
	cell.free()
	_check(body == null or not is_instance_valid(body), "and its shape goes with the cell")
	level.free()


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
	# A region referee reads the genre's list (template 1.5), a player's game the net config's: the same tables.
	var same: bool = genre.cell_tables.size() == cfg.cell_tables.size()
	for t: StringName in cfg.cell_tables:
		same = same and genre.cell_tables.has(t)
	_check(same, "genre.tres's cell tables are the net config's, so a region referee asks for them by cell too (%s)" % str(genre.cell_tables))


## Combat's client side, with no server: kits, the combo's steps, the stance, the keys, the skill bar.
func _run_combat() -> void:
	print("== regents: combat ==")
	var sword: KitDef = KitDef.by_key(&"sword")
	var axe: KitDef = KitDef.by_key(&"axe")
	_check(sword != null and axe != null and sword.validate().is_empty() and axe.validate().is_empty(), "the sword and axe kits, valid")
	_check(sword.light.size() == 3 and sword.skills.size() == 1 and sword.rank_for(0) == 1 and sword.rank_for(1) == 3,
		"the sword: a string of three, Lunge on Q at rank 1 (E would be 3)")
	# THE HEAVY MERGED INTO THE FINISHER (COMBAT_OVERHAUL.md §3): the last step, a little heavier and slower each.
	_check(sword.is_finisher(sword.light[2]) and not sword.is_finisher(sword.light[1]) and axe.light.size() == 2 and axe.is_finisher(axe.light[1]),
		"the finisher is the string's last step: the sword's third, the axe's second")
	for k: KitDef in [sword, axe]:
		for i: int in range(1, k.light.size()):
			_check(k.light[i].damage > k.light[i - 1].damage and k.light[i].wind_up_ms > k.light[i - 1].wind_up_ms,
				"%s: %s hits harder and winds up longer than %s" % [k.key, k.light[i].display_name, k.light[i - 1].display_name])
	_check(ContentLibrary.find(&"ability", 40004) == null and ContentLibrary.find(&"ability", 40007) == null,
		"the old heavy cut and second chop are gone (their ids retired)")
	var no_follow: KitDef = sword.duplicate() as KitDef
	no_follow.follow_ms = PackedInt32Array([200, 200, 200, 200])
	_check(no_follow.validate().any(func(e: String) -> bool: return e.contains("follow_ms")), "a follow-through for a step it does not have: refused")
	for a: AbilityDef in sword.light + axe.light:
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
	c.combo_ms = now - CombatComponent.combo_window_ms() - 1
	_check(CombatComponent.combo_window_ms() == 2000 and c.next_light_step(now) == 0, "too late (the window, a hot rule: 2 s): the string starts over")
	c.combo_step = 0
	c.combo_ms = now - 1500
	_check(c.next_light_step(now) == 1, "1.5 s after: still the second (the old window was 0.9 s)")
	# THE RIPOSTE: a parry seen opens it; the next tap is the first step, whatever the string was at.
	c.combo_step = 1
	c.combo_ms = now - 100
	c.parried_ms = now - 300
	c.swing_at_ms = now - 2000
	_check(c.riposte_open(now) and c.next_light_step(now) == 0, "a parry 300 ms ago: the tap is the riposte (the first step)")
	_check(not c.riposte_open(now + int(HotRules.number(&"regents.riposte_ms"))), "past the riposte window: none")
	c.swing_at_ms = now - 100
	_check(not c.riposte_open(now) and c.next_light_step(now) == 2, "a swing since the parry: the riposte is spent, the string goes on")
	c.parried_ms = -100000
	_check(not c.in_stance(), "a weapon, no target, no swing: no stance (Q and E work stations)")
	c.target_id = 7
	_check(c.in_stance(), "a target picked: in stance (Q E R F are skills)")
	c.weapon = iron_sword
	var bar: String = RegentsHud.skill_bar(c, null)
	# The string by its moves' names, the last the plain grip's (no row in a bag: the plain role); never "finisher".
	_check(bar.contains("Iron sword") and bar.contains("LMB Slash - Slash (second) - Piercing thrust") and bar.contains("Q Lunge")
		and bar.contains("RMB tap parry, hold for a light guard") and not bar.contains("hold LMB") and not bar.to_lower().contains("finisher"),
		"the skill bar: %s" % bar)
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
	_run_foe_brain()
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
	# THE WORLD MAP (Luke, 2026-10-26): every node of the level, named once seen, its skill and ??? before.
	var glade: LevelBake = LevelBake.by_id(20)
	var icons: Array[Dictionary] = RegentsWorldMap.icons_of(glade)
	var coal: Dictionary = {}
	var nodes_n: int = 0
	for ic: Dictionary in icons:
		if String(ic["kind"]) == "node":
			nodes_n += 1
			if String(ic["name"]) == "Coal rock":
				coal = ic
	_check(nodes_n == glade.points_of("node").size() and not coal.is_empty(), "an icon for each of the glade's %d nodes, a coal rock among them" % nodes_n)
	_check(RegentsWorldMap.label_of(coal, {}) == "Mining ???" and RegentsWorldMap.label_of(coal, {String(coal["point"]): true}) == "Coal rock",
		"unseen it says \"%s\"; seen, \"%s\"" % [RegentsWorldMap.label_of(coal, {}), RegentsWorldMap.label_of(coal, {String(coal["point"]): true})])
	var whole: Rect2 = RegentsWorldMap.area_of(LevelBake.by_id(21))
	var every_in: bool = true
	for p: Dictionary in LevelBake.by_id(21).points:
		every_in = every_in and whole.has_point(Vector2(float(p["x"]), float(p["z"])))
	_check(every_in and whole.size.x > 2000.0, "the continent's map holds every point (%.0f m across)" % whole.size.x)
	# The continent's icons in a moment, every node named (2026-10-27: looked up per point, its 545 nodes froze the
	# game ~90 s each time M opened, and the server dropped it for idle).
	var t0: int = Time.get_ticks_msec()
	var big: Array[Dictionary] = RegentsWorldMap.icons_of(LevelBake.by_id(21))
	var took: int = Time.get_ticks_msec() - t0
	var unnamed: int = 0
	for ic: Dictionary in big:
		unnamed += 1 if String(ic["kind"]) == "node" and String(ic.get("skill", "?")) == "?" else 0
	_check(took < 2000 and big.size() >= LevelBake.by_id(21).points_of("node").size() and unnamed == 0,
		"the continent's %d icons in %d ms, every node known (%d not)" % [big.size(), took, unnamed])
	# The Lunge plays whole (Luke's playtest, 2026-10-24: "cut off half way"); a light swing to just after its hit.
	var lunge: AbilityDef = load("res://game/regents/content/ability/sword_lunge.tres") as AbilityDef
	var chop: AbilityDef = KitDef.by_key(&"axe").light[0]
	_check(is_equal_approx(CombatComponent.commit_seconds(lunge, 1.2), 1.2)
		and is_equal_approx(CombatComponent.commit_seconds(chop, 1.2), float(chop.wind_up_ms + CombatComponent.COMMIT_AFTER_HIT_MS) / 1000.0),
		"a lunge's animation is held its whole clip, a chop's to just after its hit")
	# A level too big for one picture (Luke's playtest, 2026-10-24: "minimap doesn't update out here").
	_check(not RegentsMinimap.is_big(LevelBake.by_id(20)) and RegentsMinimap.is_big(LevelBake.by_id(21)),
		"the glade is pictured whole; the continent round you")
	var pic := Vector2(-144, -144)
	_check(not RegentsMinimap.leaves_picture(Vector2(0, 0), RegentsMinimap.RADIUS_MAX_M, pic, RegentsMinimap.AROUND_M),
		"at the middle of its picture the widest view is inside it")
	_check(RegentsMinimap.leaves_picture(Vector2(40, 0), RegentsMinimap.RADIUS_MAX_M, pic, RegentsMinimap.AROUND_M)
		and RegentsMinimap.leaves_picture(Vector2(-130, 600), RegentsMinimap.RADIUS_MAX_M, pic, RegentsMinimap.AROUND_M),
		"40 m east, the widest view nears its edge, and far out it is off it: pictured again round you")
	_check(RegentsMinimap.to_map(Vector2(0, -10), PI / 2.0, 2.0).is_equal_approx(Vector2(-20, 0)), "and north is to the left")
	var bake: LevelBake = LevelBake.by_id(20)
	var area: Rect2 = RegentsMinimap.area_of(bake)
	var all_in: bool = bake != null and not bake.points.is_empty()
	for pt: Dictionary in (bake.points if bake != null else []):
		all_in = all_in and area.has_point(Vector2(float(pt["x"]), float(pt["z"])))
	_check(all_in and area.size.x >= RegentsMinimap.CAPTURE_MIN_M and area.size.x <= RegentsMinimap.CAPTURE_MAX_M and is_equal_approx(area.size.x, area.size.y),
		"the frontier's picture: a square holding every point of its bake (%.0f m)" % area.size.x)
	_check(RegentsMinimap.color_of(0) == RegentsMinimap.PLAYER and RegentsMinimap.color_of(103) == RegentsMinimap.FOE
		and RegentsMinimap.color_of(101) == RegentsMinimap.STATION and RegentsMinimap.color_of(100) == RegentsMinimap.TREE,
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
	# A SPARK WHERE THE BLOW LANDS (Luke's feedback 4098): a burst and a streak at the chest, gone soon after.
	_check(hf.sparks.back() == &"hit" and body.get_node_or_null(^"Spark") != null, "and a spark bursts from it")
	hf._on_health_changed(65.0, 100.0, -25.0)
	_check(hf.sparks.back() == &"big", "a big hit (25): a bigger spark")
	_check(hf.hit_stops.size() == 2 and is_equal_approx(hf.hit_stops[0], HotRules.number(&"regents.hitstop_ms") / 1000.0)
		and is_equal_approx(hf.hit_stops[1], HotRules.number(&"regents.hitstop_big_ms") / 1000.0) and hf.hit_stops[1] > hf.hit_stops[0],
		"each hit asks a hit-stop, a big one longer (%s s)" % str(hf.hit_stops))
	var st := StatusComponent.new()
	st._status = HitFeedbackComponent.STATUS_BLOCKING
	hf._status = st
	hf._on_health_changed(85.0, 100.0, -5.0)
	_check(hf.flashes.back() == &"block" and hf.sparks.back() == &"block", "a hit taken while blocking: the block's flash, a steel spark")
	hf._on_status_changed(0, HitFeedbackComponent.STATUS_STAGGERED)
	_check(hf.flashes.back() == &"stagger" and hf.sparks.back() == &"stagger", "staggered (a parried swing): the stagger's flash, a gold spark")
	hf._on_health_changed(95.0, 100.0, 10.0)
	_check(hf.flashes.size() == 4 and hf.sparks.size() == 4, "a heal flashes nothing and sparks nothing")
	# THE STAGGER READS (Luke's feedback 4098, and 2026-11-01: "keep them in one spot and dazed animation for the
	# length"): a guard knocked aside once (`react.stagger`, the hit feedback's), then a dazed sway held while it lasts
	# (`react.dazed`, its pose), ROOTED (speed 0); the player and the skeletons alike (one set); a flinch keeps the hit.
	var staggered: StatusDef = load("res://game/regents/content/status/staggered.tres") as StatusDef
	var adv_anim: AnimationSet = load("res://game/regents/anim/adventurer.tres") as AnimationSet
	_check(staggered.pose == &"react.dazed" and adv_anim.anim_name(&"react.dazed") == &"extra/Zombie_Idle" and adv_anim.clip(&"react.dazed").loop
		and adv_anim.anim_name(&"react.stagger") == &"extra/Idle_Shield_Break" and HitFeedbackComponent.STAGGER_REACTION == &"react.stagger"
		and (load("res://game/regents/content/status/flinched.tres") as StatusDef).pose == &"react.hit",
		"Staggered: %s once, then holds %s; Flinched the hit react" % [adv_anim.anim_name(&"react.stagger"), adv_anim.anim_name(&"react.dazed")])
	_check(is_zero_approx(staggered.speed) and not staggered.can_act, "Staggered roots its body (speed 0) and it cannot act")
	# THE SWING'S RECOVERY (2026-11-01: "swing -> snap back"): each strike whose clip has a `_Rec` has its recovery
	# in the set, at the strike's speed, and every recovery clip is in the library.
	# (Read through the set's own libraries: a strike may be the game's own cut, `cuts/`, game/regents/tools/cut_clips.gd.)
	var recs: int = 0
	for sem: StringName in adv_anim.clips.keys():
		if not String(sem).begins_with("ability."):
			continue
		var strike: AnimationClipRef = adv_anim.clip(sem)
		var rec_sem: StringName = StringName(String(sem).replace("ability.", "recover."))
		var lib_name: String = String(strike.anim_name).get_slice("/", 0) if String(strike.anim_name).contains("/") else ""
		var lib: AnimationLibrary = adv_anim.libraries.get(StringName(lib_name), null)
		var short: String = String(strike.anim_name).get_slice("/", 1) if lib_name != "" else String(strike.anim_name)
		var has_rec: bool = lib != null and (lib.has_animation(StringName(short + "_Rec")) or (short == "Sword_Light_C" and lib.has_animation(&"SwordLight_C_Rec")))
		if has_rec:
			var rec: AnimationClipRef = adv_anim.clip(rec_sem) if adv_anim.has_exact(rec_sem) else null
			var rec_short: String = String(rec.anim_name).get_slice("/", 1) if rec != null else ""
			_check(rec != null and lib.has_animation(StringName(rec_short)) and is_equal_approx(rec.speed_scale, strike.speed_scale),
				"%s's strike (%s) is followed by its recovery (%s)" % [sem, strike.anim_name, rec.anim_name if rec != null else "none"])
			recs += 1
	_check(recs >= 12, "%d strikes have a recovery to blend back through" % recs)
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
	# A level's props: rocks solid; bushes and grass walked through (Luke's playtest, 2026-10-24).
	var level := Node3D.new()
	var decor := Node3D.new()
	decor.name = "Decor"
	level.add_child(decor)
	var big: Node3D = (load("res://game/regents/art/nature/Rock_Big_1.gltf") as PackedScene).instantiate() as Node3D
	big.position = Vector3(10, 0, 0)
	decor.add_child(big)
	var grass: Node3D = (load("res://game/regents/art/nature/Grass_Common_Short.gltf") as PackedScene).instantiate() as Node3D
	decor.add_child(grass)
	var bush: Node3D = (load("res://game/regents/art/nature/Bush_Large.gltf") as PackedScene).instantiate() as Node3D
	bush.position = Vector3(-10, 0, 0)
	decor.add_child(bush)
	var sp := RegentsSolidProps.new()
	level.add_child(sp)
	add_child(level)
	var walls: Array[Node] = decor.find_children("Solid*", "StaticBody3D", false, false)
	var wall_box: AABB = _points_box(walls[0].get_children() if not walls.is_empty() else [])
	_check(sp.made_solid == [big] and walls.size() == 1, "a level's rock is made solid, its grass and its bush are not (%d bodies)" % walls.size())
	_check(wall_box.has_point(Vector3(10, 0.5, 0)), "where the rock stands (%s)" % wall_box)
	level.free()


## THE REFEREE'S WALLS (template 1.7.2, DECISIONS #304; Luke's play, 2026-11-03, #8196: a skeleton walked
## through the copper mine's ore): `sidecar/genres/regents.gd` sizes each rock, tree and station from the
## same numbers the client builds its collision from, so a foe stops where a player does.
func _run_referee_walls() -> void:
	print("== regents: the referee's walls ==")
	var g: RefereeGenre = RefereeGenre.load_for("regents")
	_check(g != null, "the genre has a say for its referee (sidecar/genres/regents.gd)")
	if g == null:
		return
	var script: GDScript = g.get_script() as GDScript
	_check(g.sizes_kind(100) and g.sizes_kind(101) and not g.sizes_kind(0) and not g.sizes_kind(40000),
		"it sizes nodes and stations, nothing else")
	_check(g.wall_tables() == ([&"gather_node", &"station"] as Array[StringName]), "asked again on a node's or a station's row")
	_check(g.walls(987654321, 100).is_empty() and g.walls(987654321, 101).is_empty(), "nothing before an entity's row has come")
	var node_char: EntityDefinition = load("res://game/regents/content/character/node.tres") as EntityDefinition
	_check(node_char.blocks_in_status(StatusDef.NORMAL) and not node_char.blocks_in_status(NodeComponent.STATUS_DEPLETED) and not node_char.has_blocker(),
		"a node's wall is up while it stands and down worked out, sized by the genre alone")
	# A rock: its model's own box, as wide as the client's hulls and no wider (each model, two ores).
	for which: Array in [[40004, 3], [40004, 4], [40005, 3], [40005, 4]]:
		var rock: Array = _node_entity(NodeDef.by_id(int(which[0])), int(which[1]))
		var nc: NodeComponent = rock[1]
		var hulls: AABB = _points_box(nc.solid.get_children() if nc.solid != null else [])
		var w: Array[AABB] = []
		w.assign(script.call(&"node_walls", nc.def, int(which[1])))
		var wall: AABB = _union(w)
		_check(not w.is_empty() and wall.grow(0.05).encloses(hulls) and wall.size.x <= hulls.size.x * 1.15 + 0.1 and wall.size.z <= hulls.size.z * 1.15 + 0.1,
			"%s (entity %d): the referee's wall %s is where the player's hulls are %s" % [nc.def.display_name, int(which[1]), wall, hulls])
		(rock[0] as Node).free()
	# A tree: its trunk only, the client's cylinder.
	var tree: Array = _node_entity(NodeDef.by_id(40001), 1)
	var trunk: AABB = _points_box((tree[1] as NodeComponent).solid.get_children())
	var tw: Array[AABB] = []
	tw.assign(script.call(&"node_walls", NodeDef.by_id(40001), 1))
	_check(tw.size() == 1 and tw[0].position.is_equal_approx(trunk.position) and tw[0].size.is_equal_approx(trunk.size),
		"a tree: its trunk only, the client's own (%s, the client %s)" % [tw[0] if not tw.is_empty() else AABB(), trunk])
	(tree[0] as Node).free()
	# A station: wherever it is drawn (its body, every piece).
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
		var held: AABB = _points_box(sc.solid.get_children() if sc.solid != null else [])
		var sw: Array[AABB] = []
		sw.assign(script.call(&"station_walls", sc.def))
		var wall: AABB = _union(sw)
		_check(not sw.is_empty() and wall.grow(0.05).encloses(held) and wall.size.x <= held.size.x * 1.15 + 0.1 and wall.size.z <= held.size.z * 1.15 + 0.1,
			"the %s: the referee's walls %s are where the player's are %s" % [key, wall, held])
		ent.free()
	_check((script.call(&"node_walls", null, 1) as Array).is_empty() and (script.call(&"station_walls", null) as Array).is_empty(), "no def, no wall")


static func _union(boxes: Array[AABB]) -> AABB:
	var out := AABB()
	for i: int in boxes.size():
		out = boxes[i] if i == 0 else out.merge(boxes[i])
	return out


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


## THE WORK SPOT (Luke, 2026-11-06: "Move the player"; PROGRESS 44): pressed against a rock, the player steps back
## until the pick's swing (the adventurer's own front) meets the rock's drawn surface, and from there needs no more;
## facing away, or already clear, no step; never past the server's reach from the node's center.
func _run_work_spot() -> void:
	print("== regents: the work spot ==")
	var rock: Array = _node_entity(NodeDef.by_id(40004), 1)
	var nc: NodeComponent = rock[1]
	nc.entity = rock[0]
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Walk in from +X until the capsule (0.4 m) meets the rock's collider.
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(6, 1.0, 0), Vector3(0, 1.0, 0))
	var hit: Dictionary = (rock[0] as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	var stop: float = (hit["position"] as Vector3).x + 0.4 if not hit.is_empty() else 1.5
	var sk: SkillingComponent = SkillingComponent.new()
	var front: PackedVector2Array = sk.swing_front[&"pose.mine"]
	var gap: float = sk.work_spot_clearance_m
	sk.free()
	var west: Vector3 = Vector3(-1, 0, 0)
	var step: float = WorkSpot.step_back(nc, Vector3(stop, 0, 0), west, front, gap, 2.7)
	var again: float = WorkSpot.step_back(nc, Vector3(stop + step, 0, 0), west, front, gap, 2.7)
	var away: float = WorkSpot.step_back(nc, Vector3(stop, 0, 0), -west, front, gap, 2.7)
	var far: float = WorkSpot.step_back(nc, Vector3(stop + 1.6, 0, 0), west, front, gap, 2.7)
	var too_far: float = WorkSpot.step_back(nc, Vector3(stop + 4.5, 0, 0), west, front, gap, 2.7)
	var capped: float = WorkSpot.step_back(nc, Vector3(stop, 0, 0), west, front, gap, stop + 0.2)
	_check(not hit.is_empty() and step > 0.5 and absf(again) < 0.03 and away == 0.0 and absf(far + 1.6 - step) < 0.03
		and too_far == 0.0 and absf(capped - 0.2) < 0.01,
		"the work spot: pressed against the copper rock (%.2f m from its middle) the miner steps back %.2f m, then needs %.2f more; from 1.6 m farther, in %.2f; facing away %.2f; out of reach %.2f; kept inside the server's reach (%.2f of 0.20)"
		% [stop, step, again, -far, away, too_far, capped])
	# A station's skill (no swing listed) never steps.
	var sk2: SkillingComponent = SkillingComponent.new()
	_check(not sk2.swing_front.has(&"pose.smith") and sk2.swing_front.has(&"pose.chop"), "the work spot: the anvil's smith does not step; the woodcutter does")
	sk2.free()
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
		"its name: Masterwork iron axe, in the Masterwork color")
	var pw: Label = bag.find_child("Power", true, false) as Label
	_check(pw != null and pw.text == "Power 117  (+43 on your Copper axe)" and pw.get_theme_color(&"font_color").is_equal_approx(UiStyle.current().good),
		"Power 117, 43 over the copper axe you wield, in the good color (%s)" % (pw.text if pw != null else "none"))
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
	_check(bow != null and bow.draws and bow.draw_full_ms == 800 and bow.light.size() == 1, "the bow kit: drawn, full at 800 ms, one shot")
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
	var stave: ItemDef = RecipeDef.by_id(40011).output
	var strung: RecipeDef = RecipeDef.by_id(40039)
	_check(RecipeDef.by_id(40012).output_qty == 15 and RecipeDef.by_id(40013).input_qty[0] == 15 and stave.display_name == "Unstrung yew bow"
		and stave.weapon_kit == &"" and strung.output == yew and strung.inputs == [stave, ItemDef.by_id(40048)] and strung.quality == RecipeDef.Quality.FROM_INPUTS
		and RecipeDef.by_id(40038).station == &"spinning_wheel",
		"the workbench: a log to 15 shafts, 15 shafts and a bar to 15 arrows, yew logs carved to an unstrung bow (no weapon yet), strung with a bowstring (spun from flax) into the yew bow, as good as its stave")
	var body: BodyDef = load("res://game/regents/content/body/arrow.tres") as BodyDef
	_check(body.forces is ArrowFlight and body.launched_by.is_empty() and body.lifetime_s > 0.0, "the arrow: flown nose-first, never thrown by hand, gone in time")


## THE FIRST ENEMIES (owner, 2026-10-19): the skeleton camp's content holds together.
func _run_foes() -> void:
	print("== regents: foes ==")
	var foes: Array[FoeDef] = FoeDef.all()
	# The camp's two, and the tutorial's sparring partner (Luke, 2026-11-01).
	_check(foes.size() == 3 and foes.any(func(f: FoeDef) -> bool: return f.key == &"sparring_skeleton"), "three foes: %s" % ", ".join(foes.map(func(f: FoeDef) -> String: return String(f.key))))
	var genre: Resource = load("res://game/regents/genre.tres")
	var defs: Array = genre.get(&"entity_definitions") as Array
	for f: FoeDef in foes:
		_check(f.validate().is_empty(), "%s is valid content: %s" % [f.display_name, str(f.validate())])
		_check(defs.has(f.character), "%s's character is the genre's, so a client can draw it" % f.display_name)
		_check(f.character.brain == &"regents/foe" and f.character.animation_set != null and f.character.visual_scene != null,
			"%s has the foe brain, the adventurer's animations and its Bestiary model" % f.display_name)
		for a: AbilityDef in f.kit.abilities():
			_check(f.character.animation_set.has_exact(StringName("ability.%d" % a.id)), "%s plays its %s" % [f.display_name, a.display_name])
	_check(FoeDef.by_kind(103) != null and FoeDef.by_kind(103).kit.key == &"skeleton_sword" and FoeDef.by_kind(104).kit.key == &"skeleton_axe",
		"the warrior fights with a skeleton sword, the axeman a skeleton axe: kits of their own, never a player's (COMBAT_OVERHAUL.md §2)")
	# FOES YOU CAN READ (COMBAT_OVERHAUL.md §2, 2026-10-31): slow swings, the last unblockable; no weapon wields a foe kit.
	for f: FoeDef in foes:
		var lights: Array[AbilityDef] = f.kit.light
		for a: AbilityDef in lights:
			_check(a.wind_up_ms >= 500, "%s's %s winds up %d ms: long enough to see coming (500 or more)" % [f.display_name, a.display_name, a.wind_up_ms])
		var last: AbilityDef = lights[lights.size() - 1]
		_check(f.kit.unblockable.size() == 1 and f.kit.unblockable[0] == last and KitDef.is_unblockable(last.id) and last.wind_up_ms >= 800,
			"%s's string ends in its finisher, %s: unblockable, winding up %d ms" % [f.display_name, last.display_name, last.wind_up_ms])
		for it: ItemDef in RegentsContent.items(&"item").map(func(d: ContentDef) -> ItemDef: return d as ItemDef):
			_check(it == null or it.weapon_kit != f.kit.key, "no weapon fights with %s's kit (%s)" % [f.display_name, it.display_name if it != null else "?"])
	for key: StringName in [&"sword", &"axe", &"bow", &"staff"]:
		var k: KitDef = KitDef.by_key(key)
		_check(k.unblockable.is_empty() and not k.abilities().any(func(a: AbilityDef) -> bool: return KitDef.is_unblockable(a.id)),
			"a player's %s has nothing unblockable" % key)
	var odd := KitDef.new()
	odd.unblockable = [FoeDef.by_kind(103).kit.light[2]]
	_check(odd.validate().any(func(m: String) -> bool: return m.contains("unblockable")), "a kit that lists another kit's ability as unblockable is refused")
	# A property above `script =` in a .tres is dropped on load: the skeletons' family was so, unseen (2026-10-29).
	_check(FoeDef.by_kind(103).family == &"undead" and FoeDef.by_kind(104).family == &"undead",
		"both skeletons are undead, as loaded (what a family trait reads): %s, %s" % [FoeDef.by_kind(103).family, FoeDef.by_kind(104).family])
	var bad := FoeDef.new()
	_check(bad.validate().size() >= 3, "a foe with no key, character or kit is refused: %s" % str(bad.validate()))
	_check(FoeDef.by_kind(103).loot_table != null and FoeDef.by_kind(103).loot_table.id == 40001 and FoeDef.by_kind(103).loot_table.lines[2].pity,
		"its loot is the skeleton camp's table, the gem with pity")


class _FoeWorld extends NpcWorldView:
	var way: PackedVector3Array = PackedVector3Array()
	var sight: bool = true
	func path(_from: Vector3, _to: Vector3, _radius: float, _height: float) -> PackedVector3Array:
		return way
	func can_see(_a: Vector3, _b: Vector3) -> bool:
		return sight


## A FOE GOES ROUND THINGS, AND A TARGET OUT OF SIGHT IS NOT FORGOTTEN AT ONCE (Luke's continent playtest,
## 2026-10-24, #4: "a bush blocks a skeleton's sight and it turns back").
func _run_foe_brain() -> void:
	print("== regents: a foe's chase ==")
	var brain: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 1)
	var t: Array[int] = [10000]
	brain.clock = func() -> int: return t[0]
	brain.self_id = 900
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	them.pos = Vector3(6, 0, 0)
	w.states = {900: me, 1: them}
	w.kinds = {900: 103, 1: 0}
	w.way = PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 3), Vector3(6, 0, 3), Vector3(6, 0, 0)])
	brain.think(me, w)
	_check(brain.state == &"chase" and brain.target() == 1, "a player 6 m off and in sight: chased (%s)" % brain.describe())
	_check(brain.route().size() == 3 and brain.route()[0] == Vector3(0, 0, 3),
		"round what is in the way, the walk map's way, not straight at them (%s)" % str(brain.route()))
	w.sight = false
	them.pos = Vector3(9, 0, 0)
	t[0] += 1500
	brain.think(me, w)
	var lost: FoeDef = FoeDef.by_kind(103)
	_check(brain.target() == 1 and brain.state == &"chase" and brain.goal().is_equal_approx(Vector3(6, 0, 0)),
		"out of sight %d ms: still after them, to where it last saw them, not where they are now (%s, goal %s)" % [1500, brain.describe(), str(brain.goal())])
	t[0] += lost.lose_sight_ms
	brain.think(me, w)
	_check(brain.target() == 0, "out of sight past %d ms: given up (%s)" % [lost.lose_sight_ms, brain.describe()])
	_run_foe_turns()
	_run_foe_aim()


## FOES TAKE TURNS (COMBAT_OVERHAUL.md §2, 2026-10-31; the playtest: "attacks came at the same time"): three
## skeletons round one player for 30 s. At most `regents.attack_tokens` fight at once, the rest circle; no two
## swings land closer than `regents.token_gap_ms`; each swings its whole string, then rests and lets another in.
func _run_foe_turns() -> void:
	print("== regents: foes take turns ==")
	var tokens: int = int(HotRules.number(&"regents.attack_tokens"))
	var gap: int = int(HotRules.number(&"regents.token_gap_ms"))
	var t: Array[int] = [50000]
	var w := _FoeWorld.new()
	var player := MovementState.new()
	w.states = {7001: player}
	w.kinds = {7001: 0}
	var brains: Array[NpcBrain] = []
	for i: int in 3:
		var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 11 + i)
		b.clock = func() -> int: return t[0]
		b.self_id = 7101 + i
		var s := MovementState.new()
		s.pos = Vector3(1.5, 0, 0).rotated(Vector3.UP, TAU * i / 3.0)
		w.states[b.self_id] = s
		w.kinds[b.self_id] = 103
		brains.append(b)
	var lands: Array[int] = []
	var by_foe: Dictionary[int, Array] = {}
	var most_fighting: int = 0
	var circled: bool = false
	var kit: KitDef = FoeDef.by_kind(103).kit
	while t[0] < 80000:
		var fighting: int = 0
		for b: NpcBrain in brains:
			b.think(w.states[b.self_id], w)
			fighting += 1 if b.state == &"fight" else 0
			circled = circled or b.state == &"circle"
			for act: Dictionary in b.take_acts():
				if String(act.get("do", "")) != "ability":
					continue
				var a: AbilityDef = null
				for k: AbilityDef in kit.light:
					if k.id == int(act["ability"]):
						a = k
				lands.append(t[0] + (a.wind_up_ms if a != null else 0))
				if not by_foe.has(b.self_id):
					by_foe[b.self_id] = []
				by_foe[b.self_id].append(int(act["ability"]))
		most_fighting = maxi(most_fighting, fighting)
		t[0] += 100
	lands.sort()
	var least: int = 1 << 30
	for i: int in range(1, lands.size()):
		least = mini(least, lands[i] - lands[i - 1])
	_check(most_fighting >= 1 and most_fighting <= tokens and circled,
		"at most %d of 3 fight at once (most seen %d); the others circle" % [tokens, most_fighting])
	_check(lands.size() >= 6 and least >= gap, "%d swings landed, never two within %d ms (the least gap %d ms)" % [lands.size(), gap, least])
	_check(by_foe.size() == 3, "every one of the three got its turn in 30 s (%d did)" % by_foe.size())
	var order: Array = by_foe.values()[0]
	_check(order.size() >= 3 and order[0] == kit.light[0].id and order[1] == kit.light[1].id and order[2] == kit.light[2].id,
		"a turn is the whole string, light, light, finisher: %s" % str(order))


## A FOE'S AIM TRACKS, THEN LOCKS (COMBAT_OVERHAUL.md §2): it turns after its target through the wind-up and
## stops `regents.foe_aim_lock_ms` before the hit (the referee sweeps along its facing at the landing).
func _run_foe_aim() -> void:
	print("== regents: a foe's aim locks before the hit ==")
	var lock: int = int(HotRules.number(&"regents.foe_aim_lock_ms"))
	var t: Array[int] = [200000]
	var w := _FoeWorld.new()
	var player := MovementState.new()
	player.pos = Vector3(0, 0, -1.5)
	var me := MovementState.new()
	w.states = {7201: player, 7301: me}
	w.kinds = {7201: 0, 7301: 103}
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 5)
	b.clock = func() -> int: return t[0]
	b.self_id = 7301
	b.think(me, w)
	var acts: Array[Dictionary] = b.take_acts()
	_check(b.state == &"fight" and acts.size() == 1, "in reach with a free turn: it swings at once (%s)" % b.describe())
	var wind: int = FoeDef.by_kind(103).kit.light[0].wind_up_ms
	var yaw_at_press: float = b.frame(me).look_yaw
	# Early in the wind-up the player steps aside: it turns after them.
	t[0] += wind - lock - 150
	player.pos = Vector3(1.5, 0, 0)
	b.think(me, w)
	var yaw_tracked: float = b.frame(me).look_yaw
	_check(absf(angle_difference(yaw_tracked, yaw_at_press)) > 1.0, "a step aside %d ms before the hit: it turns after them (%.2f -> %.2f rad)" % [lock + 150, yaw_at_press, yaw_tracked])
	# Inside the lock it holds its aim, wherever they go.
	t[0] += 200
	player.pos = Vector3(-1.5, 0, 0)
	b.think(me, w)
	_check(is_equal_approx(b.frame(me).look_yaw, yaw_tracked), "a step %d ms before the hit (inside its %d ms lock): its aim holds, so the swing misses" % [lock - 50, lock])
	t[0] += 400
	b.think(me, w)
	_check(absf(angle_difference(b.frame(me).look_yaw, yaw_tracked)) > 1.0, "after the hit it turns to them again")


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
	var cleave: AbilityDef = axe.skills[0]
	_check(c.swinging(10) and not c.may_start(cleave, -1, 300), "a chop just begun holds you: no skill 300 ms in")
	_check(c.may_start(cleave, -1, axe.lock_ms(chop)), "free when its clip ends (%d ms)" % axe.lock_ms(chop))
	_check(not c.may_start(axe.light[1], 1, chop.wind_up_ms), "the string's second waits for the first to land")
	_check(not c.may_start(axe.light[1], 1, chop.wind_up_ms + 60), "and for its FOLLOW-THROUGH: not 60 ms after the hit (the old chain cut the arc, Luke's #8)")
	_check(c.may_start(axe.light[1], 1, chop.wind_up_ms + axe.follow_for(0)), "the next step once the follow-through is over (%d ms)" % (chop.wind_up_ms + axe.follow_for(0)))
	# STAGGERED, A PRESS WAITS (Luke's feedback 4097: "cant do this while staggered" in the middle of the screen):
	# the client holds it, as the server would refuse it, and sends it once the stagger is over.
	var stag := StatusComponent.new()
	stag._status = HitFeedbackComponent.STATUS_STAGGERED
	c._status = stag
	_check(not c.can_act() and not c.may_start(axe.light[1], 1, chop.wind_up_ms + axe.follow_for(0)), "staggered: no swing starts (it waits)")
	c._status = null
	_check(c.can_act() and c.may_start(axe.light[1], 1, chop.wind_up_ms + axe.follow_for(0)), "the stagger over: it may")
	stag.free()
	c.swing_canceled = true
	_check(not c.swinging(10) and c.may_start(cleave, -1, 10), "a swing a roll canceled holds nothing")
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
	_check(sheet.contains("120 health") and int(bench.last_measure["swings"]) == warrior.kit.light.size() and float(bench.last_measure["dps"]) > 0.0,
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
	# Only the core sets it (Luke's M12, 2026-11-05): a handle of quality 1000 never lifts a 900 head.
	inv._stacks[2] = SpaceTimeInventoryComponent.Stack.new(2, 40016, 1, 1, "{\"q\":1000}")
	_check(sk.made_quality(axe, inv) == 900, "a Masterwork handle on a 900 head: the axe is the head's, 900 (got %d)" % sk.made_quality(axe, inv))
	inv._stacks[2] = SpaceTimeInventoryComponent.Stack.new(2, 40016, 1, 1)
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
	# Every heading in the list, in order (not by node name: a second "Group_Handles" is renamed by Godot, and so hid
	# the doubled Handles heading Luke saw, 2026-11-01).
	var heads: Array[String] = []
	for n: Node in w._list.get_children():
		if n is Label:
			heads.append((n as Label).text)
	_check(heads == ["Grips", "Axes", "Swords", "Pickaxes", "Trowels", "Other"], "the workbench's list: one line a recipe, under Grips, Axes, Swords, Pickaxes, Trowels, Other, each once %s" % str(heads))
	# The window looks again every 500 ms while it is open; with nothing changed that look must cost next to nothing
	# (Luke's play, 2026-11-03, feedback #8194/#8195: by the workbench a 140-210 ms frame every half second, the
	# game at 50-70 fps: each look listed the patterns folder from disk once per comparison of its sort).
	var look0: int = Time.get_ticks_usec()
	for i: int in 10:
		w.refresh()
	var look_ms: float = float(Time.get_ticks_usec() - look0) / 10000.0
	_check(look_ms < 4.0, "the workbench window's look with nothing changed: %.2f ms (under 4)" % look_ms)
	# The prompt facing the workbench is written every frame (its list asked twice): a frame's share, not a frame.
	var say0: int = Time.get_ticks_usec()
	for i: int in 10:
		RegentsHud.station_prompt(sk, st, inv)
	var say_ms: float = float(Time.get_ticks_usec() - say0) / 10000.0
	_check(say_ms < 1.5, "the workbench's prompt, written each frame: %.2f ms (under 1.5)" % say_ms)
	# Escape leaves a round (Luke's play, 2026-11-03, #8193): a recipe's is withdrawn and forgotten here at once (so
	# nothing submits it after); a gathering round is not withdrawn (it is ended by sending what was played).
	sk.round_id = 77
	sk.round_def = NodeDef.by_id(40001)
	_check(sk.cancel_round() == null and sk.round_id == 77, "a gathering round is not withdrawn by leaving it")
	sk.round_def = axe
	_check(sk.cancel_round() != null and sk.round_id == -1 and sk.round_def == null, "a crafting round left: withdrawn, forgotten here")
	_check(sk.cancel_round() == null, "and with no round on, there is nothing to leave")
	var hilt_at: int = -1
	var buttons: Array[String] = []
	for n: Node in w._list.get_children():
		if n is Button:
			buttons.append((n as Button).text)
	hilt_at = buttons.find("Crossguard grip")
	_check(hilt_at >= 0 and hilt_at < buttons.find(buttons.filter(func(t: String) -> bool: return t.ends_with("axe"))[0]),
		"the shaped grips list under Grips, before the axes (%s)" % str(buttons.slice(0, 10)))
	_check(w.pick_named("Iron axe"), "the iron axe picked")
	var core: OptionButton = w.find_child("Core", true, false) as OptionButton
	_check(core != null and core.item_count == 3 and core.get_selected_id() == 2 and core.get_item_text(0).contains("Masterwork iron axe head")
		and not core.is_item_disabled(0) and not core.is_item_disabled(1) and core.is_item_disabled(2),
		"its head is a list by grade: Masterwork picked, Fine there, Common grayed (none)")
	var part_list: OptionButton = w.find_child("Part_0", true, false) as OptionButton
	_check(part_list != null and part_list.item_count == 9 and part_list.get_selected_id() == 40013 and part_list.get_item_text(1).ends_with("Oak grip: Steady"),
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
		"as it is, nothing to change: only the bars would be paid, so REFIT is grayed (%s)" % (cost_line.text if cost_line != null else "none"))
	w.pick_part(0, 40016)
	await get_tree().process_frame
	cost_line = w.find_child("RefitCost", true, false) as Label
	refit_b = w.find_child("Refit", true, false) as Button
	_check(cost_line.text == "Costs: 1 Oak grip (you have 1), 2 Iron bar (you have 3)" and not refit_b.disabled
		and sk.refit_args(1, 7, axe, data) == [1, 7, [40016, 40012], [steady, gentle]],
		"the oak handle swapped in: it costs the handle and 2 iron bars (the head's metal), REFIT ready, Steady joins Gentle (%s)" % cost_line.text)
	inv._stacks.erase(8)
	w.refresh()
	await get_tree().process_frame
	_check((w.find_child("Refit", true, false) as Button).disabled, "no iron bars: REFIT grayed")
	sk.bag = null
	layer.queue_free()
	st.free()
	sk.free()
	inv.free()
	await get_tree().process_frame


## ROLES BY THE HANDLE (COMBAT_OVERHAUL.md §5, Luke 2026-11-01), the sword first: three roles, one plain; the
## hilts, fitting a sword only; the role map and its last hits, each clip's hand fastest at its wind-up; what the
## craft window, the bag and the key line show: badges and words, never a role's name.
func _run_roles() -> void:
	print("== regents: roles by the handle ==")
	var roles: Array[RoleDef] = RoleDef.all()
	var keys: Array[StringName] = []
	for r: RoleDef in roles:
		keys.append(r.key)
	var damage: RoleDef = RoleDef.by_id(40001)
	var tank: RoleDef = RoleDef.by_id(40002)
	var support: RoleDef = RoleDef.by_id(40003)
	_check(keys == [&"damage", &"tank", &"support"] and RoleDef.plain_role() == damage, "three roles, the plain one Damage %s" % str(keys))
	_check(tank.full_block and not damage.full_block and not support.full_block, "the guard handle's guard is full, the others' light")
	var all_roles: Array[ContentDef] = []
	all_roles.assign(roles)
	for r: RoleDef in roles:
		_check(r.validate().is_empty() and r.validate_with(all_roles).is_empty(), "%s is valid %s" % [r.key, str(r.validate() + r.validate_with(all_roles))])
	_check(is_equal_approx(tank.threat_now(), HotRules.number(&"regents.guard_threat_pct")) and damage.threat_now() == 100.0
		and support.threat_now() <= damage.threat_now(), "threat: the guard handle's a live rule; the banner's (healing) no more than the plain's")
	# NEGATIVE: a role that names itself on screen, a rule nobody declares, a second plain role.
	var bad := RoleDef.new()
	bad.id = 40099
	bad.key = &"bad"
	bad.display_name = "Bad"
	bad.guard_words = "a tank's guard"
	bad.threat_rule = &"no_such_rule"
	var probs: Array[String] = bad.validate()
	_check(probs.any(func(p: String) -> bool: return p.contains("name a role")) and probs.any(func(p: String) -> bool: return p.contains("no rule set declares")),
		"a role whose words name it, or whose rule is nowhere, is refused %s" % str(probs))
	bad.plain = true
	var with_bad: Array[ContentDef] = all_roles.duplicate()
	with_bad.append(bad)
	_check(not bad.validate_with(with_bad).is_empty(), "two plain roles are refused")
	# THE ROLE MAP: each role's last hit, the string's other steps its own.
	var sword: KitDef = KitDef.by_key(&"sword")
	var thrust: AbilityDef = ContentLibrary.find(&"ability", 40003) as AbilityDef
	var bash: AbilityDef = ContentLibrary.find(&"ability", 40022) as AbilityDef
	var rally: AbilityDef = ContentLibrary.find(&"ability", 40023) as AbilityDef
	_check(sword.finisher_for(damage) == thrust and sword.finisher_for(tank) == bash and sword.finisher_for(support) == rally and sword.finisher_for(null) == thrust,
		"the sword's last hit: a piercing thrust, a pommel bash, a rallying cut (none known: the plain one's)")
	_check(sword.light_at(2, tank) == bash and sword.light_at(1, tank) == sword.light[1] and sword.light_at(0, support) == sword.light[0] and sword.light_at(3, tank) == null,
		"a handle changes only the string's last step")
	_check(sword.is_finisher(bash) and sword.is_finisher(rally) and sword.is_finisher(thrust) and not sword.is_finisher(sword.light[1]) and not sword.is_finisher(sword.skills[0]),
		"every role's last hit is the finisher (armor, the flinch, the stagger); a middle step and Q are not")
	_check(CombatComponent.action_tags(sword, bash) == [&"basic", &"combo_last"] and CombatComponent.action_tags(sword, sword.light[0]) == [&"basic"]
		and CombatComponent.action_tags(sword, sword.skills[0]) == [&"skill"], "traits read a role's last hit as the string's last (Heavy lengthens its stagger)")
	_check(sword.abilities().has(bash) and sword.abilities().has(rally) and sword.validate().is_empty(), "the kit lists every last hit, and is valid %s" % str(sword.validate()))
	_check([thrust.damage, bash.damage, rally.damage] == [26.0, 14.0, 14.0] and [thrust.wind_up_ms, bash.wind_up_ms, rally.wind_up_ms] == [380, 340, 400]
		and is_equal_approx(thrust.reach_m, 2.4) and rally.radius_m > thrust.radius_m, "Luke's numbers: 26 / 14 / 14, 380 / 340 / 400 ms, the thrust 2.4 m, the rallying cut's arc widest")
	_check(sword.role_entry(tank).stagger_pct == 150 and is_equal_approx(sword.role_entry(support).heal, 8.0) and sword.role_entry(damage).heal == 0.0,
		"the pommel bash staggers 1.5 times as long; the rallying cut heals 8")
	# The server's locks are this client's (it predicts the lock of the last hit it fires).
	var baked: Dictionary = {}
	var kits: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/content/regents/kit.json"))
	for k: Dictionary in (kits as Dictionary)["items"]:
		if String(k["key"]) == "sword":
			for pair: Array in k["locks"]:
				baked[int(pair[0])] = int(pair[1])
	_check(int(baked.get(40022, -1)) == sword.lock_ms(bash) and int(baked.get(40023, -1)) == sword.lock_ms(rally) and int(baked.get(40003, -1)) == sword.lock_ms(thrust),
		"the server's locks for the three are the client's (%s)" % str(baked))
	# EACH CLIP'S HAND IS FASTEST AT ITS WIND-UP (ANIMATIONS.md §3): where the blow lands is where it looks to.
	var set: AnimationSet = sword.timing_set
	for a: AbilityDef in [thrust, bash, rally]:
		var t: int = _fastest_hand_ms(set, StringName("ability.%d" % a.id))
		_check(absi(t - a.wind_up_ms) <= 20, "%s: its clip's hand is fastest at %d ms, its wind-up %d" % [a.display_name, t, a.wind_up_ms])
	# EACH LAST HIT FLOWS ON from the second slash (Luke, 2026-11-02: the rallying cut "looks more jumpy"; its clip began
	# turned away, so the blend whipped the body round): the chest's turn while it fades in from the second slash's
	# recovery stays near the thrust's and the bash's, which look fluid (604 and 815 deg/s; the old cut 1258).
	var after_b: StringName = StringName("recover.%d" % sword.light[1].id)
	for a: AbilityDef in [thrust, bash, rally]:
		var turn: int = _fade_in_turn(set, after_b, StringName("ability.%d" % a.id))
		_check(turn > 0 and turn <= 1000, "%s fades in from the second slash turning the chest at most %d deg/s (1000 at most)" % [a.display_name, turn])
	# NEGATIVE: the old clip (Sword_Heavy_C at 1.21) whips round past it.
	var old := AnimationSet.new()
	old.libraries = set.libraries
	old.clips = {after_b: set.clip(after_b), &"ability.old": AnimationClipRef.make(&"extra/Sword_Heavy_C", false, 0.15, 1.21)}
	_check(_fade_in_turn(old, after_b, &"ability.old") > 1000, "NEGATIVE: the old rallying cut's clip whips the chest round faster (%d deg/s)" % _fade_in_turn(old, after_b, &"ability.old"))
	# NEGATIVE: a role map gone wrong is refused.
	var k2 := KitDef.new()
	k2.id = 40099
	k2.key = &"test"
	k2.skill = sword.skill
	k2.light = sword.light.duplicate()
	var e1 := KitRole.new()
	e1.role = damage
	e1.finisher = bash
	e1.does = "a hit"
	var e2 := KitRole.new()
	e2.role = tank
	e2.finisher = sword.light[1]
	e2.does = "the tank's own"
	k2.roles = [e1, e2]
	var p2: Array[String] = k2._validate_roles()
	_check(p2.any(func(p: String) -> bool: return p.contains("plain role's last hit")) and p2.any(func(p: String) -> bool: return p.contains("a step or a skill"))
		and p2.any(func(p: String) -> bool: return p.contains("names a role")), "a plain role not ending the string, a step reused, a role named: each refused %s" % str(p2))
	e2.finisher = bash
	e2.does = "a hit"
	k2.roles = [e2]
	_check(k2._validate_roles().any(func(p: String) -> bool: return p.contains("no plain role")), "a role map with no plain role is refused")
	# THE SHAPES: every grip slot takes nine (three shapes in each wood), the axe's too (Luke, 2026-11-01).
	var iron_sword: ItemDef = ItemDef.by_id(40019)
	var iron_axe: ItemDef = ItemDef.by_id(40015)
	var cg: ItemDef = ItemDef.by_id(40040)
	_check(cg.role == tank and ItemDef.by_id(40043).role == support and cg.fits(iron_sword) and cg.fits(iron_axe) and ItemDef.by_id(40013).fits(iron_axe),
		"a crossguard grip gives the guard role and fits a sword and an axe alike; so does the plain grip")
	var only_swords := ItemDef.new()
	only_swords.part_tag = &"handle"
	only_swords.fits_kit = &"sword"
	_check(only_swords.fits(iron_sword) and not only_swords.fits(iron_axe), "NEGATIVE: a part for swords alone (`fits_kit`) fits no axe")
	var sword_r: RecipeDef = RecipeDef.by_id(40010)
	var axe_r: RecipeDef = RecipeDef.by_id(40006)
	_check(sword_r.part_choices(sword_r.pick_slots()[0]).size() == 9 and axe_r.part_choices(axe_r.pick_slots()[0]).size() == 9,
		"the iron sword's grip list: nine; the iron axe's: nine")
	_check(ItemDef.role_of(iron_sword, "{\"q\":500,\"h\":40042,\"p\":[40042,40012],\"t\":[]}") == tank and ItemDef.role_of(iron_sword, "{\"q\":500,\"h\":40016}") == damage
		and ItemDef.role_of(iron_sword, "") == damage and ItemDef.role_of(iron_axe, "{\"q\":500,\"p\":[40013,40012]}") == null,
		"a sword's role from its parts (an oak crossguard hilt: the guard role; an old one's oak handle, or none: plain); an axe has none yet")
	var odd := ItemDef.new()
	odd.id = 40099
	odd.display_name = "Odd"
	odd.role = tank
	_check(odd.validate().any(func(p: String) -> bool: return p.contains("no part")), "a shape that gives a role but is no part is refused")
	# BADGES: three shapes, three colors; none for no role.
	var tb: ImageTexture = RegentsRoleBadge.texture(tank)
	var db: ImageTexture = RegentsRoleBadge.texture(damage)
	var sb: ImageTexture = RegentsRoleBadge.texture(support)
	_check(tb != null and db != null and sb != null and tb.get_image().get_data() != db.get_image().get_data() and sb.get_image().get_data() != db.get_image().get_data()
		and RegentsRoleBadge.texture(null) == null, "three badges, each its own; no role, no badge")
	# WORDS: what a handle does, never a role's name (show, don't name).
	for r: RoleDef in roles:
		var line: String = RegentsRoleBadge.does_line(iron_sword, r)
		_check(not line.is_empty() and not _names_a_role(line), "%s's handle, in words: %s" % [r.key, line])
	_check(RegentsRoleBadge.does_line(iron_sword, tank).contains("pommel bash") and RegentsRoleBadge.does_line(iron_sword, tank).contains("a full guard")
		and RegentsRoleBadge.does_line(iron_sword, support).contains("rallying cut") and RegentsRoleBadge.does_line(iron_axe, tank) == "",
		"the crossguard says its pommel bash and full guard, the banner its rallying cut; an axe says nothing yet")
	_check(RegentsHud._string_names(sword, tank) == "Slash - Slash (second) - Pommel bash" and RegentsHud._string_names(sword, null) == "Slash - Slash (second) - Piercing thrust",
		"the key line names the string's moves, the last the handle's: %s" % RegentsHud._string_names(sword, tank))
	# THE CRAFT WINDOW: the iron sword's handle row, badges and a line; the axe's, neither.
	var sk := SkillingComponent.new()
	var inv := SpaceTimeInventoryComponent.new()
	inv._stacks[1] = SpaceTimeInventoryComponent.Stack.new(1, 40018, 1, 0, "{\"q\":650}")
	inv._stacks[2] = SpaceTimeInventoryComponent.Stack.new(2, 40040, 1, 1)
	inv._stacks[3] = SpaceTimeInventoryComponent.Stack.new(3, 40012, 4, 2)
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
	_check(w.pick_named("Iron sword"), "the iron sword picked")
	var handles: OptionButton = w.find_child("Part_0", true, false) as OptionButton
	var icons: int = 0
	for i: int in (handles.item_count if handles != null else 0):
		icons += 1 if handles.get_item_icon(i) != null else 0
	_check(handles != null and handles.item_count == 9 and icons == 9, "its handle list: nine, each with its badge (%d)" % icons)
	_check(w.role_line().contains("piercing thrust") and not _names_a_role(w.role_line()), "the plain handle picked: %s" % w.role_line())
	w.pick_part(0, 40040)
	await get_tree().process_frame
	_check(w.role_line().contains("pommel bash") and w.role_line().contains("a full guard") and not _names_a_role(w.role_line()),
		"the crossguard hilt picked: %s" % w.role_line())
	_check(w.pick_named("Iron axe"), "the iron axe picked")
	await get_tree().process_frame
	var axe_handles: OptionButton = w.find_child("Part_0", true, false) as OptionButton
	_check(axe_handles != null and axe_handles.item_count == 9 and axe_handles.get_item_icon(0) == null and w.role_line() == "",
		"the axe's grip row: all nine shapes, no badges, no line (a shape matters only where the kit has roles: not the axe yet)")
	# THE BAG: a sword with a banner hilt wears its badge and says what it does; an axe neither.
	inv._stacks[4] = SpaceTimeInventoryComponent.Stack.new(4, 40019, 1, 3, "{\"q\":650,\"h\":40041,\"p\":[40041,40012],\"t\":[]}")
	inv._stacks[5] = SpaceTimeInventoryComponent.Stack.new(5, 40015, 1, 4, "{\"q\":650,\"h\":40013,\"p\":[40013,40012],\"t\":[]}")
	var bag := RegentsBagWindow.new()
	bag.inventory = inv
	layer.add_child(bag)
	bag.picked_row = 4
	bag.open()
	await get_tree().process_frame
	var s4: UiSlot = bag.find_child("Slot_4", true, false) as UiSlot
	var s5: UiSlot = bag.find_child("Slot_5", true, false) as UiSlot
	_check(s4 != null and s4.find_child("RoleBadge", false, false) != null and s5 != null and s5.find_child("RoleBadge", false, false) == null,
		"the sword's slot wears its badge; the axe's none")
	_check(s4 != null and s4.tooltip_text.contains("Its last hit: Rallying cut") and not _names_a_role(s4.tooltip_text), "its tooltip: %s" % (s4.tooltip_text if s4 != null else ""))
	_check(bag.role_line().contains("Rallying cut") and bag.role_line().contains("mends") and not _names_a_role(bag.role_line()), "its detail: %s" % bag.role_line())
	bag.picked_row = 5
	bag.refresh()
	await get_tree().process_frame
	_check(bag.role_line() == "", "the axe's detail: no role line")
	layer.queue_free()
	st.free()
	sk.free()
	inv.free()
	await get_tree().process_frame


## THE TARGET'S STATUS BARS (Luke, 2026-11-01: "a status bar under the enemy hp ... how long the enemy is staggered
## for"): what was done to it, with its time left, longest first; never its own swing; an effect too.
func _run_status_bars() -> void:
	print("== regents: the target's status bars ==")
	var st := StatusComponent.new()
	st.entity_id = 77
	var now: int = ClockSync.server_usec()
	st._status = 103   # Staggered, by another, 1.2 s, begun 0.2 s ago
	st._lasts_ms = 1200
	st._since_usec = now - 200_000
	st._by_entity = 5
	st._effects[1] = {"status": 108, "since": now - 1_000_000, "lasts_ms": 3000, "serial": 1}   # Slowed, 2 s left
	var rows: Array[Dictionary] = RegentsHud.status_rows(st)
	_check(rows.size() == 2 and String(rows[0]["name"]) == "Slowed" and String(rows[1]["name"]) == "Staggered"
		and absf(float(rows[1]["left"]) - 1.0) < 0.1 and is_equal_approx(float(rows[1]["total"]), 1.2) and is_equal_approx(float(rows[0]["total"]), 3.0),
		"a staggered, slowed target: two bars, the longest left first, each its time left of its whole (%s)" % str(rows))
	st._status = 104   # its own swing (by itself)
	st._by_entity = 77
	st._effects.clear()
	_check(RegentsHud.status_rows(st).is_empty(), "its own swing shows no bar")
	st._status = 106   # Slain: no time on it
	st._by_entity = 5
	st._lasts_ms = 0
	_check(RegentsHud.status_rows(st).is_empty(), "a status with no end shows no bar")
	_check(RegentsHud.status_rows(null).is_empty(), "no target, no bars")
	st.free()
	# ITS POISE, READ FOR THE MARKER (Luke, 2026-11-02): worn as the server works it out, whole again unhit, steadied.
	var pf := HitFeedbackComponent.new()
	var now_us: int = ClockSync.server_usec()
	var regen_ms: float = HotRules.number(&"regents.poise_regen_ms")
	var prow := PoiseRow.new()
	prow.left = 21.0
	prow.most = 70.0
	prow.hit_at = now_us - 500_000
	prow.steady_until = 0
	pf.set_poise(prow)
	_check(is_equal_approx(pf.poise_worn(now_us), 0.7) and not pf.poise_steadied(now_us), "21 of 70 left, hit half a second ago: 70 %% worn (%.2f)" % pf.poise_worn(now_us))
	_check(is_zero_approx(pf.poise_worn(prow.hit_at + int(regen_ms * 1000.0) + 1)), "NEGATIVE: unhit for regents.poise_regen_ms, it is whole: nothing worn")
	var broke: Array[bool] = []
	pf.poise_broke.connect(func() -> void: broke.append(true))
	var after := PoiseRow.new()
	after.left = 70.0
	after.most = 70.0
	after.hit_at = now_us
	after.steady_until = now_us + 3_800_000
	pf._on_row_updated(&"poise_state", prow, after)
	_check(broke == [true] and pf.poise_steadied(now_us) and is_zero_approx(pf.poise_worn(now_us)), "broken: it bursts once, whole, and steadied")
	pf._on_row_updated(&"poise_state", after, after)
	_check(broke.size() == 1, "NEGATIVE: the same row again is no second burst")
	pf.free()
	# THE BAR SAYS IT (Luke, 2026-11-02): a stagger flashes the body, and no word floats over it.
	var fb := HitFeedbackComponent.new()
	fb._on_status_changed(0, 103)
	_check(fb.flashes.has(&"stagger") and not fb.said.has("Staggered"), "a stagger: the gold flash, no word over the body (said %s)" % str(fb.said))
	fb.say("Blocked", Color.WHITE)
	_check(fb.said == ["Blocked"], "NEGATIVE: the other words are still said (%s)" % str(fb.said))
	fb.free()


class PoiseRow extends RefCounted:
	var left: float
	var most: float
	var hit_at: int
	var steady_until: int


class TutorialRow extends RefCounted:
	var entity_id: int
	var state: int
	var done: Array = []


func _tutorial_row(state: int, done: Array) -> TutorialRow:
	var r := TutorialRow.new()
	r.entity_id = 9
	r.state = state
	r.done = done
	return r


## THE TUTORIAL (Luke, 2026-11-01: make your own sword, then the fight with it; progress on the server): the
## lessons as content, their checks, the component reading its row, the guide's card, the yard's partner and ring.
func _run_tutorial() -> void:
	print("== regents: the tutorial ==")
	var all: Array[LessonDef] = LessonDef.all()
	var names: Array[String] = []
	var problems: Array[String] = []
	for l: LessonDef in all:
		names.append(l.display_name)
		for pr: String in l.validate() + l.validate_with(RegentsContent.items(&"lesson")):
			problems.append("%s: %s" % [l.display_name, pr])
	_check(names == ["Chop wood", "Carve a grip", "Mine copper", "Smelt copper", "Smith a blade", "Smith rivets", "Make your sword",
		"Take it in hand", "Three in a row", "Roll through", "Parry", "Strike back", "Hold your guard", "The red glint", "Your grip"],
		"fifteen lessons in order: the sword made, then the fight, the grip's shape last (%s)" % str(names))
	_check(problems.is_empty(), "every lesson passes its checks %s" % str(problems))
	_check(all.all(func(l: LessonDef) -> bool: return not _names_a_role(l.words) and not _names_a_role(l.display_name)),
		"no lesson names a role or the last hit (show, don't name)")
	# Each lesson sends the player somewhere on the frontier that is there.
	var points: Array = (JSON.parse_string(FileAccess.get_file_as_string("res://shared/world/frontier.json")) as Dictionary)["points"]
	var ids: Array[String] = []
	for pt: Dictionary in points:
		ids.append(String(pt["id"]))
	var nowhere: Array[String] = []
	for l: LessonDef in all:
		if l.at != &"" and not ids.has(String(l.at)):
			nowhere.append("%s -> %s" % [l.display_name, l.at])
	_check(nowhere.is_empty() and ids.has("guide") and ids.has("sparring_1"), "every lesson's place, the guide and the partner are on the frontier %s" % str(nowhere))
	# WANTS: a kind where the lesson says so.
	var grip: LessonDef = all[1]
	var sword: LessonDef = all[6]
	_check(grip.wants(ItemDef.by_id(40042)) and grip.wants(ItemDef.by_id(40013)) and not grip.wants(ItemDef.by_id(40012)),
		"any grip carves the grip (an oak crossguard grip too); rivets do not")
	_check(sword.wants(ItemDef.by_id(40019)) and not sword.wants(ItemDef.by_id(40027)) and not sword.wants(null),
		"any sword makes the sword; NEGATIVE: a sword blade does not")
	_check(not all[0].wants(ItemDef.by_id(40007)), "NEGATIVE: chopping wants logs, nothing else")
	# THE CHECKS, NEGATIVE: an item where the deed names none; a kind with no item; a role word; a weapon that is none.
	var odd := LessonDef.new()
	odd.id = 1
	odd.display_name = "Odd"
	odd.done_when = LessonDef.Done.PARRIED
	odd.item = ItemDef.by_id(40002)
	odd.any_of_its_kind = true
	odd.words = "Land the finisher"
	var said: Array[String] = odd.validate()
	_check(said.any(func(p: String) -> bool: return p.contains("names none")) and said.any(func(p: String) -> bool: return p.contains("any_of_its_kind"))
		and said.any(func(p: String) -> bool: return p.contains("never its name")), "a lesson with an item it cannot use, and a role's word, is refused %s" % str(said))
	odd.done_when = LessonDef.Done.WIELDED
	odd.any_of_its_kind = false
	odd.words = "Hold it"
	_check(odd.validate().any(func(p: String) -> bool: return p.contains("no weapon")), "NEGATIVE: logs cannot be wielded")
	odd.order = all[3].order
	_check(odd.validate_with(RegentsContent.items(&"lesson")).any(func(p: String) -> bool: return p.contains("too")), "NEGATIVE: two lessons at one place in the run")
	# THE COMPONENT reads its row: the lesson now, its place, the ticks seen.
	var tut := TutorialComponent.new()
	tut.entity_id = 9
	_check(tut.state == TutorialComponent.NONE and tut.current() == null and RegentsTutorialCard.card_text(tut, false).is_empty(),
		"no row (a server from before): nothing shown")
	tut._on_row_updated(&"tutorial", null, _tutorial_row(TutorialComponent.OFFERED, []))
	var offered: Dictionary = RegentsTutorialCard.card_text(tut, false)
	var offer: Dictionary = RegentsTutorialCard.card_text(tut, true)
	_check(tut.current() == null and String(offered.get("keys", "")).contains("press E") and String(offer["body"]) == tut.greeting
		and String(offer["keys"]).contains("E: show me") and String(offer["keys"]).contains("N: not now"),
		"offered: the card says the guide is by the yard; E on them: their greeting, E to begin, N not now (%s)" % str(offer))
	tut._bound = true
	var ticked: Array[String] = []
	tut.lesson_ticked.connect(func(l: LessonDef) -> void: ticked.append(l.display_name))
	var finished: Array[bool] = []
	tut.finished.connect(func() -> void: finished.append(true))
	tut._on_row_updated(&"tutorial", _tutorial_row(TutorialComponent.OFFERED, []), _tutorial_row(TutorialComponent.ON, []))
	var card: Dictionary = RegentsTutorialCard.card_text(tut, false)
	_check(tut.current() == all[0] and tut.place() == Vector2i(1, 15) and String(card["title"]) == "Chop wood   1 / 15" and String(card["body"]) == all[0].words,
		"under way: the first lesson, 1 of 15, in the guide's words (%s)" % str(card))
	tut._on_row_updated(&"tutorial", _tutorial_row(TutorialComponent.ON, []), _tutorial_row(TutorialComponent.ON, [all[0].id, all[10].id]))
	_check(ticked == ["Chop wood", "Parry"] and tut.current() == all[1] and tut.place() == Vector2i(2, 15),
		"two ticks (one out of order): both seen, the lesson now the first not done (%s)" % str(ticked))
	_check(RegentsTutorialCard.card_text(tut, true).get("body", "") == all[1].words, "E on the guide under way: the lesson now again, no offer")
	var every: Array = []
	for l: LessonDef in all:
		every.append(l.id)
	tut._on_row_updated(&"tutorial", _tutorial_row(TutorialComponent.ON, [all[0].id]), _tutorial_row(TutorialComponent.FINISHED, every))
	_check(finished == [true] and tut.current() == null and RegentsTutorialCard.card_text(tut, false).is_empty()
		and RegentsTutorialCard.card_text(tut, true).get("body", "") == tut.again, "finished: the farewell once, nothing shown, the guide offers it again")
	for t: Dictionary in [offered, offer, card]:
		_check(not _names_a_role(String(t.get("title", "")) + String(t.get("body", "")) + String(t.get("keys", ""))), "the card names no role: %s" % str(t))
	_check(not _names_a_role(tut.greeting + tut.again + tut.farewell), "the guide's own words name no role")
	tut.free()
	# The adventurer carries it, after the skilling (so its E is asked first, then the skilling's).
	var adv: Node = (load("res://game/regents/adventurer.tscn") as PackedScene).instantiate()
	var comps: Array[String] = []
	for c: Node in adv.get_node(^"Components").get_children():
		comps.append(c.name)
	_check(comps.has("Tutorial") and comps.find("Tutorial") > comps.find("Skilling"), "the adventurer has the tutorial, after the skilling %s" % str(comps))
	adv.free()
	# THE GUIDE AND THE PARTNER: the guide's kind is the component's, both are drawn; only the partner shows the ring.
	var genre: GenreModule = load("res://game/regents/genre.tres") as GenreModule
	var kinds: Array[int] = []
	for d: EntityDefinition in genre.entity_definitions:
		kinds.append(d.kind)
	var guide: EntityDefinition = load("res://game/regents/content/character/guide.tres") as EntityDefinition
	_check(guide.kind == TutorialComponent.GUIDE_KIND and kinds.has(guide.kind) and kinds.has(105) and genre.tables.has(&"tutorial"),
		"the guide (kind %d) and the sparring skeleton are drawn; the tutorial's table is the genre's" % guide.kind)
	var spar: FoeDef = FoeDef.by_kind(105)
	_check(spar != null and spar.parry_ring and spar.xp_pct == 0 and spar.loot_table == null
		and FoeDef.all().filter(func(f: FoeDef) -> bool: return f.parry_ring).size() == 1,
		"the sparring skeleton alone shows the parry ring, and pays nothing")
	var set: AnimationSet = load("res://game/regents/anim/adventurer.tres") as AnimationSet
	var slow: bool = true
	for a: AbilityDef in spar.kit.light:
		slow = slow and a.wind_up_ms >= 900 and set.clip(StringName("ability.%d" % a.id)) != null and set.clip(StringName("recover.%d" % a.id)) != null
	_check(slow and spar.kit.unblockable.size() == 1 and spar.kit.unblockable[0] == spar.kit.light[2],
		"its swings are slow (900 ms or more), each with its clip and recovery; its last glints")
	# The swing's blow in each clip lands at its wind-up (the ring shuts as it lands).
	for a: AbilityDef in spar.kit.light:
		var hand: int = _fastest_hand_ms(set, StringName("ability.%d" % a.id))
		_check(absi(hand - a.wind_up_ms) <= 60, "%s: the blow at %d ms in its clip, its wind-up %d ms" % [a.display_name, hand, a.wind_up_ms])


## Whether `text` names a role or the last hit's slot (Luke, 2026-11-01: show, don't name).
static func _names_a_role(text: String) -> bool:
	var t: String = text.to_lower()
	for w: String in ["tank", "damage", "support", "finisher", "dps", "healer"]:
		if t.contains(w):
			return true
	return false


## When the right hand moves fastest in clip `sem` of `set`, at its speed (ms): the blow (ANIMATIONS.md §3).
func _fastest_hand_ms(set: AnimationSet, sem: StringName) -> int:
	var ref: AnimationClipRef = set.clip(sem)
	var anim: Animation = AnimationTreeBuilder.clip_animation(set, sem)
	if ref == null or anim == null:
		return -1
	var scene: Node3D = (load("res://game/characters/mannequin_f.glb") as PackedScene).instantiate() as Node3D
	var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand: int = skel.find_bone("hand_r")
	var dt: float = 1.0 / 120.0
	var prev: Vector3 = Vector3.ZERO
	var best_t: float = 0.0
	var best_v: float = 0.0
	var t: float = 0.0
	while t <= anim.length:
		for tr: int in anim.get_track_count():
			var b: int = skel.find_bone(String(anim.track_get_path(tr).get_concatenated_subnames()))
			if b < 0:
				continue
			match anim.track_get_type(tr):
				Animation.TYPE_ROTATION_3D:
					skel.set_bone_pose_rotation(b, anim.rotation_track_interpolate(tr, t))
				Animation.TYPE_POSITION_3D:
					skel.set_bone_pose_position(b, anim.position_track_interpolate(tr, t))
		var p: Vector3 = _bone_origin(skel, hand)
		if t > 0.0 and (p - prev).length() / dt > best_v:
			best_v = (p - prev).length() / dt
			best_t = t
		prev = p
		t += dt
	scene.free()
	return roundi(best_t * 1000.0 / (ref.speed_scale if ref.speed_scale > 0.0 else 1.0))


## THE CHEST'S PEAK TURN (deg/s) while clip `to` of `set` fades in over its blend time from `from` playing (as the
## driver's one-shot cross-fades), at 60 Hz: the angle between frames, so no axis is assumed.
func _fade_in_turn(set: AnimationSet, from: StringName, to: StringName) -> int:
	var a: Animation = AnimationTreeBuilder.clip_animation(set, from)
	var b: Animation = AnimationTreeBuilder.clip_animation(set, to)
	var ra: AnimationClipRef = set.clip(from)
	var rb: AnimationClipRef = set.clip(to)
	if a == null or b == null:
		return -1
	var scene: Node3D = (load("res://game/characters/mannequin_f.glb") as PackedScene).instantiate() as Node3D
	var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var chest: int = skel.find_bone("spine_03")
	var dt: float = 1.0 / 60.0
	var peak: float = 0.0
	var prev: Quaternion = Quaternion.IDENTITY
	var t: float = 0.0
	while t <= rb.blend_time + 0.0001:
		var w: float = clampf(t / rb.blend_time, 0.0, 1.0)
		for tr: int in b.get_track_count():
			if b.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
				continue
			var path: NodePath = b.track_get_path(tr)
			var bone: int = skel.find_bone(String(path.get_concatenated_subnames()))
			var ta: int = a.find_track(path, Animation.TYPE_ROTATION_3D)
			if bone < 0 or ta < 0:
				continue
			var qa: Quaternion = a.rotation_track_interpolate(ta, minf(t * ra.speed_scale, a.length))
			skel.set_bone_pose_rotation(bone, qa.slerp(b.rotation_track_interpolate(tr, minf(t * rb.speed_scale, b.length)), w))
		var q: Quaternion = Quaternion(_bone_basis(skel, chest))
		if t > 0.0:
			peak = maxf(peak, rad_to_deg(prev.angle_to(q)) / dt)
		prev = q
		t += dt
	scene.free()
	return roundi(peak)


static func _bone_basis(skel: Skeleton3D, b: int) -> Basis:
	var x: Basis = Basis(skel.get_bone_pose_rotation(b))
	var parent: int = skel.get_bone_parent(b)
	while parent >= 0:
		x = Basis(skel.get_bone_pose_rotation(parent)) * x
		parent = skel.get_bone_parent(parent)
	return x.orthonormalized()


## Bone `b`'s place in the skeleton's space, from the poses set (no tree, no update needed).
static func _bone_origin(skel: Skeleton3D, b: int) -> Vector3:
	var x: Transform3D = Transform3D(Basis(skel.get_bone_pose_rotation(b)), skel.get_bone_pose_position(b))
	var parent: int = skel.get_bone_parent(b)
	while parent >= 0:
		x = Transform3D(Basis(skel.get_bone_pose_rotation(parent)), skel.get_bone_pose_position(parent)) * x
		parent = skel.get_bone_parent(parent)
	return x.origin


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
	# WHAT WAS REFUSED GOES TO THE SIDE (Luke's feedback 4097): its own column at the right, a few at most;
	# the middle keeps what you got.
	var middle: int = hud._notices.get_child_count()
	for why: String in ["no roll in the air", "use_ability: you cannot while staggered", "still swinging", "not now"]:
		hud.refused(why)
	await get_tree().process_frame
	var column: Rect2 = hud.refusals.get_global_rect()
	var screen: Vector2 = hud.get_viewport().get_visible_rect().size
	_check(hud._notices.get_child_count() == middle and hud.refusals.get_child_count() == RegentsHud.REFUSALS_SHOWN
		and (hud.refusals.get_child(hud.refusals.get_child_count() - 1) as Label).text == "Not now"
		and is_equal_approx(hud.refusals.anchor_left, 1.0) and absf(column.end.x - (screen.x - 24.0)) < 1.0,
		"refusals in a column pinned to the right edge (%d shown, the newest last; its edge at %.0f of %.0f), none in the middle"
		% [hud.refusals.get_child_count(), column.end.x, screen.x])
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
	_check(keys == [&"woodcutting", &"mining", &"smelting", &"smithing", &"crafting", &"swordsmanship", &"axemanship", &"archery", &"sorcery", &"herbalism"],
		"six working skills (herbalism, 2026-11-07) and four weapon masteries: %s" % str(keys))
	var wc: SkillDef = SkillDef.by_key(&"woodcutting")
	_check(wc.rank_of(0) == 1 and wc.rank_of(59) == 1 and wc.rank_of(60) == 2 and wc.rank_of(280) == 4 and wc.progress(100) == Vector2i(40, 90),
		"ranks come from the curve: rank 2 at 60 XP, 4 at 280; 100 XP is 40 of rank 3's 90")
	var names: Array[String] = []
	for n: NodeDef in NodeDef.all_by_tier():
		names.append(n.display_name)
	_check(names == ["Tree", "Oak", "Yew", "Copper rock", "Iron rock", "Coal rock", "Flax"], "seven nodes, by skill then tier: %s" % str(names))
	var flax: NodeDef = NodeDef.all_by_tier()[6]
	_check(flax.minigame == null and flax.tool_tag == &"trowel" and flax.skill == SkillDef.by_key(&"herbalism") and flax.validate().is_empty(),
		"flax: herbalism's, pulled with a trowel; no round yet (AFK only: pull the root is step 2) and valid without one")
	var prev: ChopParams = null
	for n: NodeDef in NodeDef.all_by_tier():
		if not (n.minigame is ChopParams):
			continue
		var t: ChopParams = n.minigame as ChopParams
		_check(t.target_chops <= ChopModel.max_chops(t), "%s: a full score is reachable (%d of at most %d)" % [n.display_name, t.target_chops, ChopModel.max_chops(t)])
		if prev != null:
			# Harder: more branches, and a higher target or (band 2's knots, 2026-11-07) more knots to chop through.
			_check(t.branch_permille > prev.branch_permille and (t.target_chops > prev.target_chops or t.knot_permille > prev.knot_permille),
				"%s is a harder round than the tier below" % n.display_name)
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
	_check(made.get("Grip", []) == ["workbench", ["Logs"]] and made.get("Iron axe", []) == ["workbench", ["Iron axe head", "Grip", "Copper rivets"]],
		"the workbench: logs into a handle; a head, a handle and rivets into an iron axe")
	var head: RecipeDef = RecipeDef.by_id(40004)
	var axe: RecipeDef = RecipeDef.by_id(40006)
	_check(head.quality == RecipeDef.Quality.FROM_ROUND and head.minigame is ShapeParams and axe.quality == RecipeDef.Quality.FROM_INPUTS and axe.minigame == null,
		"the head is shaped (as good as its round); the axe is assembled (as good as its head)")
	_check(RecipeDef.at(&"furnace").size() == 3 and RecipeDef.at(&"anvil").size() == 15 and RecipeDef.at(&"workbench").size() == 26
		and RecipeDef.at(&"spinning_wheel").size() == 1 and RecipeDef.at(&"orders").is_empty(),
		"three recipes at the furnace (copper, iron, steel bars), fifteen at the anvil (rivets, an axe head, a sword blade, a pickaxe head and a trowel blade of each metal), twenty-six at the workbench (three handles and six sword hilts; an axe, a sword, a pickaxe and a trowel of each metal; the yew bow's stave and its stringing, arrow shafts, copper arrows, the yew staff), one at the spinning wheel (the bowstring), none at the order board")
	_check(made.get("Oak grip", []) == ["workbench", ["Oak logs"]] and made.get("Yew grip", []) == ["workbench", ["Yew logs"]],
		"oak and yew logs carve into their handles")
	_check(RecipeDef.by_id(40001).input_qty[0] == 2 and RecipeDef.by_id(40002).input_qty[0] == 2, "two ores to a bar, never one to one")
	var choices: Array[String] = []
	for it: ItemDef in axe.part_choices():
		choices.append(it.display_name)
	_check(axe.part_slot == 1 and choices == ["Grip", "Oak grip", "Yew grip", "Crossguard grip", "Banner grip", "Oak crossguard grip", "Oak banner grip", "Yew crossguard grip", "Yew banner grip"], "the iron axe's grip slot takes any grip, plain first: %s" % str(choices))
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
		and pkeys == [&"bar", &"axe_head", &"sword_blade", &"handle", &"axe", &"sword", &"pickaxe_head", &"pickaxe", &"rivets", &"crossguard_hilt", &"banner_hilt",
			&"trowel_blade", &"trowel"],
		"six materials and thirteen patterns (the sword's two hilts, COMBAT_OVERHAUL.md §5; herbalism's trowel, 2026-11-07): %s x %s" % [str(keys), str(pkeys)])
	var bad: Array[String] = []
	for type: StringName in [&"material", &"pattern"]:
		for d: ContentDef in ContentLibrary.items(type):
			if not d.validate().is_empty():
				bad.append("%s: %s" % [d.display_name, str(d.validate())])
	_check(bad.is_empty(), "every material and pattern is valid%s" % ("" if bad.is_empty() else ": " + "; ".join(bad)))
	# The ids players hold, pinned: each cell IS the file it was (MATERIALS.md §2).
	var pinned: Dictionary[String, int] = {"copper:bar": 40010, "iron:bar": 40011, "iron:axe_head": 40014, "iron:sword_blade": 40018,
		"iron:axe": 40015, "iron:sword": 40019, "plain_wood:handle": 40013, "oak:handle": 40016, "yew:handle": 40017,
		"copper:axe": 40001, "copper:pickaxe": 40006, "steel:bar": 40025, "copper:rivets": 40012,
		"plain_wood:crossguard_hilt": 40040, "plain_wood:banner_hilt": 40041, "oak:crossguard_hilt": 40042, "oak:banner_hilt": 40043,
		"yew:crossguard_hilt": 40044, "yew:banner_hilt": 40045}
	var got: Dictionary[String, int] = {}
	for c: Dictionary in MaterialTable.plan():
		var m: MaterialDef = c["material"]
		var p: PatternDef = c["pattern"]
		var it: ItemDef = MaterialTable.cell(m, p)
		got["%s:%s" % [m.key, p.key]] = it.id if it != null else -1
	var kept: bool = true
	for k: String in pinned:
		kept = kept and got.get(k, -1) == pinned[k]
	_check(got.size() == 39 and kept and not got.values().has(-1) and got.get("copper:trowel", -1) == 40051,
		"39 cells (three metals in ten patterns, three woods in three), every one made (the copper trowel 40051, the starter's); the items players hold are the cells they were, ids pinned (the starters 40001 and 40006 now copper's): %s" % str(got))
	var problems: Array[String] = MaterialTable.problems()
	_check(problems.is_empty(), "the table is current: every cell and recipe as the table makes it%s" % ("" if problems.is_empty() else ": " + "; ".join(problems)))
	var dry: Dictionary = MaterialTable.generate(false)
	_check((dry["made"] as Array).is_empty() and (dry["updated"] as Array).is_empty() and (dry["errors"] as Array).is_empty(),
		"making it again would change nothing: %s" % str(dry["lines"]))
	var iron: MaterialDef = MaterialDef.by_key(&"iron")
	var plain: MaterialDef = MaterialDef.by_key(&"plain_wood")
	var axe_p: PatternDef = MaterialTable.cell(iron, MaterialTable.patterns()[4]).pattern
	_check(axe_p.item_name(iron) == "Iron axe" and MaterialTable.patterns()[3].item_name(plain) == "Grip",
		"names: \"{m} axe\" of iron is \"Iron axe\"; \"{m} grip\" of plain wood is \"Grip\"")
	var wants: Dictionary = MaterialTable.item_wants(iron, axe_p)
	_check(wants["tool_tier"] == 2 and wants["tool_speed_pct"] == 85 and wants["weapon_damage_pct"] == 100 and wants["tool_tag"] == &"axe",
		"an iron axe's tier, tool speed and Power are iron's: %s" % str(wants))
	var errs: Array[String] = []
	var rw: Dictionary = MaterialTable.recipe_wants(iron, axe_p, ItemDef.by_id(40015), MaterialTable._index(MaterialTable._items()), errs)
	var ins: Array[String] = []
	for it: ItemDef in rw["inputs"] as Array:
		ins.append(it.display_name)
	_check(errs.is_empty() and ins == ["Iron axe head", "Grip", "Copper rivets"] and rw["part_slot"] == 1 and rw["input_qty"] == PackedInt32Array([1, 1, 2]),
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
	_check(tier_says.size() == 3 and tier_says.all(func(p: String) -> bool: return p.contains("tool_tier: has 2, makes 3"))
		and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_axe.tres")) and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_pickaxe.tres"))
		and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_trowel.tres")),
		"iron moved to tier 3: its axe's, pickaxe's and trowel's tool tiers are out of date (a sword's and a head's have none): %s" % str(tier_says))
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
	_check(says.size() == 1 and says[0].contains("tin_axe.tres") and says[0].contains("display_name"), "a renamed cell is out of date, its tuned XP and color are not: %s" % str(says))
	var fix: Dictionary = MaterialTable.generate()
	var reread: ItemDef = load(t_axe.resource_path) as ItemDef
	_check((fix["updated"] as Array).size() == 1 and reread.display_name == "Tin axe" and reread.color == Color(1, 0, 0) and r.xp == 999,
		"making it puts the name back and keeps the color and the XP")
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
	var knotted: int = 0
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
		p.knot_permille = int(pp.get("knot_permille", 0))   # knots (2026-11-07): absent before them
		p.knot_beat_ms = int(pp.get("knot_beat_ms", 0))
		var want_seg: PackedInt32Array = PackedInt32Array()
		for v: Variant in c["segments"]:
			want_seg.append(int(v))
		if c.has("knots"):
			var want_knots: PackedByteArray = PackedByteArray()
			for v: Variant in c["knots"]:
				want_knots.append(int(v))
			knotted += 1
			if ChopModel.knots_of(seed_value, p, want_knots.size()) != want_knots:
				bad.append("%s: the knots" % c["name"])
		var inputs: PackedInt32Array = PackedInt32Array()
		for pair: Array in c["inputs"]:
			inputs.append(int(pair[0]))
			inputs.append(int(pair[1]))
		var e: Dictionary = c["expected"]
		var want: Dictionary = {"clean": int(e["clean"]), "hits": int(e["hits"]), "best_combo": int(e["best_combo"]), "score_pm": int(e["score_pm"])}
		var got: Dictionary = ChopModel.play(seed_value, p, inputs)
		if ChopModel.branches(seed_value, p, want_seg.size()) != want_seg or got != want:
			bad.append("%s: %s, wanted %s" % [c["name"], str(got), str(want)])
	_check(bad.is_empty() and knotted >= 3, "the GDScript twin plays every golden round exactly (%d with knots)%s" % [knotted, "" if bad.is_empty() else ": " + "; ".join(bad)])


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
	var brittle_cases: int = 0
	for c: Dictionary in crack:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: CrackParams = _params_from(CrackParams.new(), c["params"]) as CrackParams
		var pts: PackedInt32Array = CrackModel.seams(seed_value, p, 3)
		var got: Dictionary = CrackModel.play(seed_value, p, _flat(c["inputs"]))
		if c.has("brittle"):   # brittle notches (band 2, a test, 2026-11-07)
			var want_b: PackedByteArray = PackedByteArray()
			for v: Variant in c["brittle"]:
				want_b.append(int(v))
			brittle_cases += 1
			if CrackModel.brittle_of(seed_value, p, want_b.size()) != want_b:
				bad.append("crack %s: the brittle notches" % c["name"])
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
		var round_outline: PackedInt32Array = ShapeModel.start(seed_value, p).outline
		var got: Dictionary = ShapeModel.play(seed_value, p, _flat(c["inputs"]))
		if start != _flat([c["start"]]) or round_outline != _flat([c["outline"]]) or got != _ints(c["expected"]):
			bad.append("shape %s: %s, wanted %s" % [c["name"], str(got), str(c["expected"])])
	var beat: Array = _golden_cases("beat")
	var slag_cases: int = 0
	for c: Dictionary in beat:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: BeatParams = _params_from(BeatParams.new(), c["params"]) as BeatParams
		var bm: BeatModel = BeatModel.start(seed_value, p)
		var notes: PackedInt32Array = PackedInt32Array()
		for j: int in bm.note_t.size():
			notes.append_array(PackedInt32Array([bm.note_t[j], bm.note_end[j]]))
		var got: Dictionary = BeatModel.play(seed_value, p, _flat(c["inputs"]))
		if c.has("slag"):   # slag (band 2, a test, 2026-11-07)
			var want_slag: PackedByteArray = PackedByteArray()
			for v: Variant in c["slag"]:
				want_slag.append(int(v))
			slag_cases += 1
			if bm.slag != want_slag:
				bad.append("beat %s: the slag" % c["name"])
		if notes != _flat([c["notes"]]) or got != _ints(c["expected"]):
			bad.append("beat %s: %s, wanted %s" % [c["name"], str(got), str(c["expected"])])
	var carve: Array = _golden_cases("carve")
	for c: Dictionary in carve:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: CarveParams = _params_from(CarveParams.new(), c["params"]) as CarveParams
		var cm: CarveModel = CarveModel.start(seed_value, p)
		var start_ok: bool = cm.left == _flat([c["start_left"]]) and cm.right == _flat([c["start_right"]]) \
			and cm.target_left == _flat([c["target_left"]]) and cm.target_right == _flat([c["target_right"]])
		var got: Dictionary = CarveModel.play(seed_value, p, _flat(c["inputs"]))
		if not start_ok or got != _ints(c["expected"]):
			bad.append("carve %s: %s, wanted %s (start %s)" % [c["name"], str(got), str(c["expected"]), start_ok])
	_check(carve.size() >= 6, "the carve's golden rounds are there (%d)" % carve.size())
	_check(crack.size() >= 6 and brittle_cases >= 3 and smelt.size() >= 6 and shape.size() >= 6 and beat.size() >= 6 and slag_cases >= 3 and bad.is_empty(),
		"the GDScript models play every golden round exactly (%d crack, %d smelt, %d shape, %d beat)%s" % [crack.size(), smelt.size(), shape.size(), beat.size(),
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
		var played: ChopModel = ChopModel.start(99, t)
		var ins: PackedInt32Array = _perfect_inputs(99, t)
		for k: int in range(0, ins.size(), 2):
			played.chop(ins[k], ins[k + 1])
		played.finish()
		var r: Dictionary = played.result()
		# Every swing lands: a cut, or (a knotted piece, band 2) a bite the next swing from the same side cuts.
		_check(r["hits"] == 0 and r["clean"] + played.bites == ChopModel.max_chops(t) and r["score_pm"] == 1000 and r == ChopModel.play(99, t, ins),
			"%s: never under a branch, every swing on time: %d logs (%d bites into knots), no hits, a full score" % [n.display_name, r["clean"], played.bites])
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


## THE DIFFICULTY READOUT (`MINIGAMES_PREP.md` §6, Luke's M4 2026-11-05): simulated players of set skill play every
## round in the content through its own model. Pinned here: each simulated round is a real one (its replay is what
## the bot saw), the readout is the same every run, more skill never scores less, and nobody pressing scores
## nothing. The grade-share targets are pinned when smithing's ladder is tuned (§8 step 3).
func _run_readout() -> void:
	print("== regents: the difficulty readout ==")
	const N: int = 16
	var rounds: Array[Resource] = []
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame != null:
			rounds.append(n.minigame)
	for r: RecipeDef in RecipeDef.all():
		if r.minigame != null:
			rounds.append(r.minigame)
	var sims: Array[SimPlayer] = SimPlayer.presets()
	var disagree: Array[String] = []
	var unordered: Array[String] = []
	for p: Resource in rounds:
		var means: Array[int] = []
		for sim: SimPlayer in sims:
			var m: Dictionary = MinigameReadout.measure(p, sim, N)
			means.append(int(m["mean"]))
			if not bool(m["agree"]):
				disagree.append("%s by %s" % [p.get(&"display_name"), sim.display_name])
		# Flawless never below anyone; skilled never below careless.
		if means[0] < means.max() or means[1] < means[3]:
			unordered.append("%s %s" % [p.get(&"display_name"), str(means)])
	_check(rounds.size() >= 18 and disagree.is_empty(),
		"%d rounds x %d players x %d seeds: every simulated round replays as it was played (disagree: %s)" % [rounds.size(), sims.size(), N, str(disagree)])
	_check(unordered.is_empty(), "more skill never scores less: flawless the best, skilled above careless (out of order: %s)" % str(unordered))
	var tree: Resource = (NodeDef.all_by_tier()[0] as NodeDef).minigame
	var a: Dictionary = MinigameReadout.measure(tree, sims[2], N)
	var b: Dictionary = MinigameReadout.measure(tree, sims[2], N)
	_check(a["scores"] == b["scores"] and not (a["scores"] as PackedInt32Array).is_empty(), "the readout is the same every run: %s" % str(a["scores"]))
	var flawless_trees: bool = true
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame is ChopParams:
			flawless_trees = flawless_trees and int(MinigameReadout.measure(n.minigame, sims[0], N)["mean"]) == 1000
	_check(flawless_trees, "the flawless player chops every tree to a full score")
	# The negative: a player too slow ever to press scores what an untouched round does (a bar left on the anvil is
	# already partly the shape: up to ~30 % on the pickaxe head), never a Fine part, never more than AFK.
	var absent: SimPlayer = SimPlayer.make("Absent", 60000, 0, 0, 0, 1, false)
	var gained: Array[String] = []
	for p: Resource in rounds:
		var m: Dictionary = MinigameReadout.measure(p, absent, 4)
		var untouched: int = int(SkillMinigames.play(1, p, PackedInt32Array()).get("score_pm", -1))
		if int(m["fine_pct"]) != 0 or int(m["beats_afk_pct"]) != 0 or not bool(m["agree"]) or int((m["scores"] as PackedInt32Array)[0]) != untouched:
			gained.append("%s %s" % [p.get(&"display_name"), str(m["scores"])])
	_check(gained.is_empty(), "nobody pressing: each round scores as untouched, no Fine part, no gain on AFK (gained: %s)" % str(gained))
	var text: String = MinigameReadout.report(tree, 4)
	_check(text.contains("Flawless") and text.contains("Careless") and text.contains("beats AFK"), "the readout reads: %s" % text.get_slice("\n", 1))


## SMITHING'S TWO STRIKES AND ITS 3D STAGE (`MINIGAMES_PREP.md` §3.1, §5; Luke's M7 and M9, 2026-11-05): a heavy strike
## that spreads, a light tap that does not, a tap switched off by a 0; which buttons tap is a setting, tried both
## ways; the anvil's stage follows the model and decides nothing.
func _run_two_strikes() -> void:
	print("== regents: smithing's two strikes ==")
	var p: ShapeParams = ShapeParams.new()
	p.outline = PackedInt32Array([10, 10, 10, 10])
	p.start_jitter = 0
	p.hammer_drop = 6
	p.spread_pct = 17
	p.tap_drop = 1
	var m: ShapeModel = ShapeModel.start(1, p)
	_check(m.heights == PackedInt32Array([20, 20, 20, 20]), "a bar of four, 20 high")
	_check(m.strike(0, 1) == ShapeModel.STRUCK and m.heights == PackedInt32Array([21, 14, 21, 20]), "a heavy strike: 6 down, 1 into each neighbor (%s)" % str(m.heights))
	_check(m.strike(280, ShapeModel.TAP + 0) == ShapeModel.STRUCK and m.heights == PackedInt32Array([20, 14, 21, 20]), "a light tap: 1 down, nothing spread (%s)" % str(m.heights))
	_check(m.strike(300, ShapeModel.TAP + 3) == ShapeModel.HELD and m.settle(560) == ShapeModel.STRUCK and m.heights[3] == 19, "a tap mid-swing is held and lands as the swing ends, as a strike is")
	_check(m.strike(900, ShapeModel.TAP + 4) == ShapeModel.IGNORED and m.strike(900, ShapeModel.TAP - 1) == ShapeModel.IGNORED, "a tap off the bar's end is not a tap")
	var off: ShapeParams = p.duplicate() as ShapeParams
	off.tap_drop = 0
	var mo: ShapeModel = ShapeModel.start(1, off)
	_check(mo.strike(0, ShapeModel.TAP + 1) == ShapeModel.IGNORED and mo.heights == PackedInt32Array([20, 20, 20, 20]) and mo.next_ok_ms == 0 and mo.strike(0, 1) == ShapeModel.STRUCK,
		"tap_drop 0: a tap is ignored and costs no swing (a round from before taps replays unchanged)")
	# Every anvil round in the content has both strikes, and its heavy strike spreads (6 x 17 % = 1 a side; at 4 x 20 %
	# it was 0, so the bar could never rise).
	var no_taps: Array[String] = []
	for r: RecipeDef in RecipeDef.all():
		var sp: ShapeParams = r.minigame as ShapeParams
		if sp != null and (sp.tap_drop <= 0 or sp.hammer_drop * sp.spread_pct / 100 < 1):
			no_taps.append(r.display_name)
	_check(no_taps.is_empty(), "every part at the anvil has a light tap and a heavy strike that spreads (not: %s)" % str(no_taps))
	# The readout: the tap is what lifts the anvil's ceiling (the flawless smith, with it and with it switched off).
	var head: ShapeParams = (RecipeDef.by_id(40004)).minigame as ShapeParams
	var head_off: ShapeParams = head.duplicate() as ShapeParams
	head_off.tap_drop = 0
	var flawless: SimPlayer = SimPlayer.presets()[0]
	var with_tap: Dictionary = MinigameReadout.measure(head, flawless, 8)
	var without: Dictionary = MinigameReadout.measure(head_off, flawless, 8)
	var tapped: bool = false
	var played: PackedInt32Array = MinigameReadout.play_round(1, head, flawless)["inputs"]
	for i: int in range(1, played.size(), 2):
		tapped = tapped or played[i] >= ShapeModel.TAP
	_check(tapped and int(with_tap["mean"]) > int(without["mean"]) + 30 and bool(with_tap["agree"]),
		"the readout's smith taps, and taps lift the iron axe head's ceiling (%d with, %d without, per mille)" % [with_tap["mean"], without["mean"]])

	# THE BANDS (Luke's test, 2026-11-05: copper 1, iron 2, steel 3): the same hands do worse each band up, on every
	# part; and the bands' rules are where he put them.
	var skilled: SimPlayer = SimPlayer.presets()[1]
	var ladder: Array[String] = []
	for part: String in ["axe head", "sword blade", "pickaxe head"]:
		var means: Array[int] = []
		var rules_ok: bool = true
		for metal: String in ["Copper", "Iron", "Steel"]:
			var rr: ShapeParams = null
			for r: RecipeDef in RecipeDef.all():
				if r.display_name == "%s %s" % [metal, part]:
					rr = r.minigame as ShapeParams
			means.append(int(MinigameReadout.measure(rr, skilled, 12)["mean"]))
			var band: int = ["Copper", "Iron", "Steel"].find(metal) + 1
			rules_ok = rules_ok and rr.max_reheats > 0 and rr.reheat_cost_pm > 0 and rr.hide_outline == 1 and rr.outline_vary > 0
			rules_ok = rules_ok and (rr.lay_cost_pm > 0) == (band >= 2) and (rr.red_ms > 0 and rr.quench_hi_pm > 0) == (band == 3)
		if not (means[0] > means[1] and means[1] > means[2]) or not rules_ok:
			ladder.append("%s %s%s" % [part, str(means), "" if rules_ok else " (rules misplaced)"])
	_check(ladder.is_empty(), "copper, iron, steel: each band's rules where Luke put them, and a skilled smith does worse each band up (not: %s)" % str(ladder))

	# THE BUTTONS: a setting (Controls), both ways.
	ShapeMinigame.define_setting()
	var e: Dictionary = Settings.entry(ShapeMinigame.SETTING)
	_check(not e.is_empty() and String(e["tab"]) == Settings.CONTROLS and (e["choices"] as PackedStringArray).size() == 2,
		"which buttons tap at the anvil is a Controls setting with two choices")
	var kept: int = ShapeMinigame.buttons()
	var holder: Control = Control.new()
	holder.size = Vector2(960, 620)
	add_child(holder)
	var shape: ShapeMinigame = ShapeMinigame.new()
	holder.add_child(shape)
	shape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shape.begin(3, head)
	await get_tree().process_frame
	await get_tree().process_frame
	# THE PATTERN (band 2's iron axe head has one): on the bar as the round starts; a click lifts it and strikes nothing.
	var first_look: bool = shape.model.laid and shape._shows_outline()
	shape._gui_input(_mouse(shape.size * 0.5, MOUSE_BUTTON_LEFT, false))
	_check(first_look and _columns_sent(shape.inputs) == PackedInt32Array([ShapeModel.LIFT]) and not shape.model.laid
		and shape.model.strikes == 0 and not shape._shows_outline(),
		"the pattern is on the bar as the round starts; a click lifts it (no strike), and the outline is gone")
	shape.inputs = PackedInt32Array()
	var r: Rect2 = shape.bar_rect()
	var picked: Array[int] = []
	var want: Array[int] = []
	for c: int in head.outline.size():
		picked.append(shape.column_at(r.position.x + (c + 0.5) * r.size.x / head.outline.size()))
		want.append(c)
	var stage: AnvilStage = shape.get_child(0) as AnvilStage
	_check(stage != null and stage.show_behind_parent and Rect2(Vector2.ZERO, shape.size).encloses(r) and r.size.x > 300.0 and picked == want,
		"the anvil is a 3D stage behind the panel; the bar is on screen (%s) and each column is clicked where it is drawn" % str(r))
	Settings.set_value(ShapeMinigame.SETTING, ShapeMinigame.Buttons.RIGHT_TAPS)
	var at: Vector2 = Vector2(r.position.x + 4.5 * r.size.x / head.outline.size(), r.get_center().y)
	shape._gui_input(_mouse(at, MOUSE_BUTTON_LEFT, false))
	shape._gui_input(_mouse(at, MOUSE_BUTTON_RIGHT, false))
	shape._gui_input(_mouse(at, MOUSE_BUTTON_LEFT, true))
	var right_taps: PackedInt32Array = _columns_sent(shape.inputs)
	Settings.set_value(ShapeMinigame.SETTING, ShapeMinigame.Buttons.SHIFT_TAPS)
	shape.inputs = PackedInt32Array()
	shape._gui_input(_mouse(at, MOUSE_BUTTON_LEFT, false))
	shape._gui_input(_mouse(at, MOUSE_BUTTON_LEFT, true))
	shape._gui_input(_mouse(at, MOUSE_BUTTON_RIGHT, false))
	var shift_taps: PackedInt32Array = _columns_sent(shape.inputs)
	_check(right_taps == PackedInt32Array([4, ShapeModel.TAP + 4, 4]) and shift_taps == PackedInt32Array([4, ShapeModel.TAP + 4, ShapeModel.REHEAT_COLUMN]),
		"left click strikes; right click taps (R reheats), or Shift + click taps and right click reheats (%s, %s)" % [str(right_taps), str(shift_taps)])
	# The stage follows what the model landed: the struck column flashes, sparks fly there, and nothing in it decides.
	var flashed: float = stage._flash[4]
	_check(flashed > 0.0 and stage._sparks.emitting and is_equal_approx(stage._sparks.position.x, stage.column_x(4)),
		"a strike lands on the stage where the model says: column 4 flashes (%.2f), sparks fly from it" % flashed)
	shape.finish()   # (its inputs were cleared between the two ways: no replay to compare; the suites above do that)
	var plain: ShapeParams = head.duplicate() as ShapeParams
	plain.tap_drop = 0
	plain.hide_outline = 0
	shape.begin(3, plain)
	Settings.set_value(ShapeMinigame.SETTING, ShapeMinigame.Buttons.RIGHT_TAPS)
	shape._gui_input(_mouse(at, MOUSE_BUTTON_RIGHT, false))
	_check(_columns_sent(shape.inputs) == PackedInt32Array([ShapeModel.REHEAT_COLUMN]), "a round with no tap: right click reheats, as before")
	# SPACE lays the pattern on and lifts it; while it is on a click strikes nothing; ENTER sets the part down and the
	# round ends there, its replay the same.
	shape.begin(5, head)
	await get_tree().process_frame
	shape.toggle_template()
	var lifted: bool = not shape.model.laid
	shape.toggle_template()
	var relaid: bool = shape.model.laid and shape.model.lays == 1 and shape.model.ceiling_pm() == 1000 - head.lay_cost_pm
	shape.toggle_template()
	shape.set_down()
	await get_tree().process_frame
	_check(lifted and relaid and shape.state == SkillMinigame.State.DONE and shape.live_result == shape.replayed_result
		and int(shape.live_result["lays"]) == 1 and not shape.shows_clock(),
		"Space lifts the pattern and lays it on again (iron: %d off the best it can be); Enter sets the part down, the round ends, the replay agrees" % head.lay_cost_pm)
	Settings.set_value(ShapeMinigame.SETTING, kept)
	holder.queue_free()
	await get_tree().process_frame


## THE OTHER THREE ON THEIR 3D STAGES (`MINIGAMES_PREP.md` §5; Luke's M7, 2026-11-05): woodcutting, mining and smelting
## each show their round on a stage of the game's own models, the real tool swinging on its own (no character: Luke's
## play, 2026-11-06); each stage follows what its model landed, and the round plays and replays exactly as before.
func _run_stages() -> void:
	print("== regents: the minigames' 3D stages ==")
	var holder: Control = Control.new()
	holder.size = Vector2(960, 620)
	add_child(holder)
	# WOODCUTTING: the axe is on the side the model says, swings into the trunk on a clean chop, is knocked back by a branch.
	var chop: ChopMinigame = ChopMinigame.new()
	holder.add_child(chop)
	chop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tree_p: ChopParams = NodeDef.all_by_tier()[0].minigame as ChopParams
	chop.begin(5, tree_p)
	await get_tree().process_frame
	var wood: WoodStage = chop.get_child(0) as WoodStage
	var has_axe: bool = wood != null and wood.tool != null and _no_character(wood)
	var shown: int = wood._pieces.size() if wood != null else 0
	var t: int = 0
	var side_ok: bool = true
	var thrown: bool = false
	var swung: bool = true
	var sides: Dictionary[int, bool] = {}
	for _k: int in 12:
		var hb: int = chop.model.head_branch()
		var at: int = ChopModel.SIDE_RIGHT if hb == ChopModel.BRANCH_LEFT else ChopModel.SIDE_LEFT
		var did: int = chop.press_at(t, at)
		# The axe's blow lands on the trunk's side the model chops from, at the bottom piece.
		var head: Vector3 = wood.tool.head_at_hit()
		var on_side: bool = (head.x < 0.0) == (chop.model.side == ChopModel.SIDE_LEFT)
		var at_trunk: bool = absf(absf(head.x) - wood.trunk_r) < 0.12 and absf(head.y - (wood.stump_h + wood.piece_h * 0.5)) < 0.15
		side_ok = side_ok and wood._side == chop.model.side and on_side and at_trunk
		if did == ChopModel.CLEAN:
			swung = swung and wood.tool.is_swinging()
			sides[chop.model.side] = true
		thrown = thrown or (did == ChopModel.CLEAN and not wood._flying.is_empty())
		t = chop.model.next_ok_ms
	var hb2: int = chop.model.head_branch()
	var flinched: bool = false
	if hb2 != ChopModel.BRANCH_NONE:
		flinched = chop.press_at(t, hb2) == ChopModel.HIT and wood.tool._jarred and wood.tool.is_swinging()
	chop.finish()
	_check(wood != null and wood.show_behind_parent and has_axe and shown == ChopModel.VIEW_SEGMENTS and side_ok and swung
		and sides.size() == 2 and thrown and (flinched or hb2 == ChopModel.BRANCH_NONE) and chop.live_result == chop.replayed_result,
		"woodcutting's stage: no character, the axe alone; its blow lands on the trunk's side the model chops from (both sides seen), a clean chop swings it and throws the piece, a branch knocks it back; the replay agrees")
	chop.queue_free()
	# KNOTS (band 2, a test, 2026-11-07): the yew's knotted piece shows a burl; the first chop bites (the axe swings, the
	# piece stays, "Again!"); the next from the same side in a beat cuts it; one from the other side, or late, bites again.
	var yew_p: ChopParams = null
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame is ChopParams and (n.minigame as ChopParams).knot_permille > 0:
			yew_p = n.minigame as ChopParams
	var knot_seed: int = -1
	for i: int in 400:   # seeds spread as the readout's (nearby small seeds draw nearly alike; a round's is random)
		var ks: int = 1 + i * 7919
		var km: ChopModel = ChopModel.start(ks, yew_p)
		if km.knots[yew_p.safe_segments] == 1 and km.segments[yew_p.safe_segments + 1] == ChopModel.BRANCH_NONE:
			knot_seed = ks   # a knot on the first piece past the safe ones, nothing at the head above it
			break
	var kchop: ChopMinigame = ChopMinigame.new()
	holder.add_child(kchop)
	kchop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	kchop.begin(knot_seed, yew_p)
	await get_tree().process_frame
	var kwood: WoodStage = kchop.get_child(0) as WoodStage
	var kt: int = 0
	for _i: int in yew_p.safe_segments:
		kchop.press_at(kt, ChopModel.SIDE_RIGHT if kchop.model.head_branch() == ChopModel.BRANCH_LEFT else ChopModel.SIDE_LEFT)
		kt = kchop.model.next_ok_ms
	var burl: bool = kwood._pieces[0].find_child("Knot", false, false) != null
	var bit: bool = kchop.press_at(kt, ChopModel.SIDE_LEFT) == ChopModel.BITE and kchop.model.knotted() and kwood.tool.is_swinging()
	kt = kchop.model.next_ok_ms
	var other: bool = kchop.press_at(kt, ChopModel.SIDE_RIGHT) == ChopModel.BITE   # the other side: a fresh bite
	kt = kchop.model.next_ok_ms + yew_p.knot_beat_ms + 1
	var late: bool = kchop.press_at(kt, ChopModel.SIDE_RIGHT) == ChopModel.BITE   # too late: a fresh bite
	kt = kchop.model.next_ok_ms
	var cut_through: bool = kchop.press_at(kt, ChopModel.SIDE_RIGHT) == ChopModel.CLEAN and kchop.model.cut == yew_p.safe_segments + 1
	kchop.finish()
	_check(yew_p != null and knot_seed > 0 and burl and bit and other and late and cut_through and kchop.model.bites == 3
		and kchop.live_result == kchop.replayed_result,
		"the yew's knots: a burl on the piece (%s); the first chop bites (%s), the other side (%s) or a late one (%s) bites again, the next from the same side in a beat cuts it (%s); bites %d, seed %d; the replay agrees"
			% [burl, bit, other, late, cut_through, kchop.model.bites, knot_seed])
	kchop.queue_free()
	# MINING: the rock is the node's own (its ore), the seam's face sits on it, strikes and jars show where they land.
	var crack: CrackMinigame = CrackMinigame.new()
	holder.add_child(crack)
	crack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rock_node: NodeDef = null
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame is CrackParams and rock_node == null:
			rock_node = n
	crack.begin(9, rock_node.minigame)
	await get_tree().process_frame
	await get_tree().process_frame
	var mine: MineStage = crack.get_child(0) as MineStage
	var face: Rect2 = crack.face()
	var rock_r: Rect2 = mine.rock_rect() if mine != null else Rect2()
	var notch: Vector2i = crack.model.notch(0)
	var hit: bool = crack.strike_at(0, notch.x, notch.y) == CrackModel.HIT and mine._chips.emitting and mine.tool.is_swinging()
	# The pick's tip comes down where the strike landed, on the rock's front.
	var tip_ok: bool = mine.tool.head_at_hit().distance_to(mine._world(crack.from_face(notch))) < 0.01
	var off: Vector2i = crack.model.notch(crack.model.k) + Vector2i(400, 0)
	crack.strike_at(crack.model.next_ok_ms, clampi(off.x, 0, 1000), off.y)
	var jarred: bool = crack.model.jars == 1 and mine._sparks.emitting and mine.tool._jarred
	crack.finish()
	_check(mine != null and CrackMinigame.node_of(rock_node.minigame as CrackParams) == rock_node and mine.tool != null
		and _no_character(mine) and rock_r.encloses(face) and Rect2(Vector2.ZERO, crack.size).encloses(face) and hit and tip_ok
		and jarred and crack.live_result == crack.replayed_result,
		"mining's stage: no character, the pick alone; the node's own rock, the seam's face on it (%s in %s), a strike brings the pick's tip down on it and throws chips, a jar bounces it and sparks; the replay agrees" % [str(face), str(rock_r)])
	crack.queue_free()
	# SMELTING (its rhythm track, 2026-11-07): a note pressed pumps the bellows, a long draw closes them slowly until let
	# go, a press on no note sputters; pouring tilts the crucible and shows the stream.
	holder.size = Vector2(960, 620)
	var smelt: BeatMinigame = BeatMinigame.new()
	holder.add_child(smelt)
	smelt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bar_p: BeatParams = (RecipeDef.by_id(40001)).minigame as BeatParams
	var draw_seed: int = 1
	while draw_seed < 200 and _first_draw(BeatModel.start(draw_seed, bar_p)) < 1:
		draw_seed += 1
	smelt.begin(draw_seed, bar_p)
	await get_tree().process_frame
	var furnace: SmeltStage = smelt.get_child(0) as SmeltStage
	var m0: BeatModel = smelt.model
	smelt.press_at(100, BeatModel.DOWN)   # in the count-in: on no note
	var sputtered: bool = m0.strays == 1 and furnace._squash > 0.2
	smelt.press_at(102, BeatModel.UP)
	smelt.press_at(m0.note_t[0], BeatModel.DOWN)
	var pumped: bool = furnace._squash > 0.5 and not furnace.drawing
	smelt.press_at(m0.note_t[0] + 60, BeatModel.UP)
	var d: int = _first_draw(m0)
	var mid: int = (m0.note_t[d] + m0.note_end[d]) / 2
	smelt.press_at(m0.note_t[d], BeatModel.DOWN)
	var drawing: bool = furnace.drawing
	smelt.press_at(mid, BeatModel.UP)
	var let_go: bool = not furnace.drawing and m0.got[d] > 0 and m0.got[d] < 1000
	var ready: int = BeatModel.track_end_ms(bar_p) + bar_p.pour_ready_ms
	smelt.model.advance_to(ready)
	smelt.press_at(ready, BeatModel.DOWN)
	smelt.model.advance_to(ready + 400)
	furnace.show_melt(smelt.model.heat_now(ready + 400), smelt.model.fill, smelt.model.pouring, smelt.model.on_track(ready + 400))
	var pouring: bool = furnace._stream.visible and furnace._metal.visible
	smelt.press_at(ready + 400, BeatModel.UP)
	furnace.show_melt(smelt.model.heat_now(ready + 400), smelt.model.fill, smelt.model.pouring, smelt.model.on_track(ready + 400))
	smelt.finish()
	_check(furnace != null and _no_character(furnace) and pumped and sputtered and drawing and let_go and pouring and not furnace._stream.visible
		and smelt.live_result == smelt.replayed_result,
		"smelting's stage, the rhythm track: a note pumps the bellows (%s), a long draw holds them until let go (%s, %s: half held, part paid: %d), a press on no note sputters (%s); pouring shows the stream and the metal (%s), stopping stops it; the replay agrees" % [pumped, drawing, let_go, m0.got[d], sputtered, pouring])
	# CARVING (woodworking; Luke 2026-11-07: "vertical and have wood you can take off from either side"): the yew bow's
	# round is the carve: a stave standing on the bench (no character, the knife alone); the pattern on at the start (no
	# cuts), a click lifts it; a click left of a row's middle cuts its left edge, right of it its right edge; a deep cut
	# and a fine shave; the two profiles differ (the bow's back and belly); Enter sets it down; the replay agrees.
	var bow_r: RecipeDef = RecipeDef.by_id(40011)
	var bow_p: CarveParams = bow_r.minigame as CarveParams
	# Cuts before the stage has drawn a frame (a round begun and cut at once): no error (the suite fails on any).
	var quick: CarveMinigame = SkillMinigames.make_ui(bow_p) as CarveMinigame
	holder.add_child(quick)
	quick.begin(99, bow_p)
	quick.press_at(100, CarveModel.LIFT)
	quick.press_at(200, CarveModel.LEFT_DEEP + 3)
	quick.press_at(500, CarveModel.RIGHT_FINE + 4)
	quick.finish()
	quick.queue_free()
	var carve: CarveMinigame = SkillMinigames.make_ui(bow_p) as CarveMinigame
	holder.add_child(carve)
	carve.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	carve.begin(5, bow_p)
	await get_tree().process_frame
	await get_tree().process_frame
	var cstage: CarveStage = carve.get_child(0) as CarveStage
	var cm: CarveModel = carve.model
	var row: int = 4
	var mid_y: float = (cstage.screen_point(float(row), 0.0).y + cstage.screen_point(float(row + 1), 0.0).y) * 0.5
	var left_x: float = cstage.screen_point(float(row) + 0.5, -2.0).x
	var right_x: float = cstage.screen_point(float(row) + 0.5, 2.0).x
	var l0: int = cm.left[row]
	var r0: int = cm.right[row]
	var click: Callable = func(at: Vector2, button: MouseButton) -> void:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = button
		e.position = at
		e.pressed = true
		carve._gui_input(e)
	click.call(Vector2(left_x, mid_y), MOUSE_BUTTON_LEFT)   # the pattern is on: this lifts it, cuts nothing
	var lifted: bool = not cm.laid and cm.cuts == 0 and cm.left[row] == l0
	var placed: bool = carve.row_at(mid_y) == row and carve.side_at(left_x, row) == 0 and carve.side_at(right_x, row) == 1
	carve._started_usec = Time.get_ticks_usec() - 1000 * 1000
	click.call(Vector2(left_x, mid_y), MOUSE_BUTTON_LEFT)
	var deep_left: bool = cm.left[row] == l0 - bow_p.deep_cut and cm.right[row] == r0 and cstage._chips.emitting
	carve._started_usec = Time.get_ticks_usec() - 2000 * 1000
	# Right of the row's middle as it is NOW (the deep cut moved it): left and right are of the wood you see.
	right_x = cstage.screen_point(float(row) + 0.5, float(cm.right[row] - cm.left[row]) * 0.5 + 2.0).x
	click.call(Vector2(right_x, mid_y), MOUSE_BUTTON_RIGHT)
	var fine_right: bool = cm.right[row] == r0 - bow_p.fine_cut and cm.left[row] == l0 - bow_p.deep_cut
	var asym: bool = bow_p.left_outline != bow_p.right_outline
	var enter: InputEventKey = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	carve._started_usec = Time.get_ticks_usec() - 3000 * 1000
	carve._unhandled_key_input(enter)
	var set_down: bool = cm.done_ms >= 0 and carve.is_over()
	carve.finish()
	_check(bow_r.quality == RecipeDef.Quality.FROM_ROUND and cstage != null and _no_character(cstage) and carve.title().begins_with("Carving")
		and lifted and placed and deep_left and fine_right and asym and set_down and carve.live_result == carve.replayed_result,
		"carving the yew bow: a stave on the bench (%s); a click lifts the pattern (%s); left of a row's middle cuts its left edge deep (%s), right of it a fine shave off the right (%s); its back and belly differ (%s); Enter sets it down (%s); the replay agrees"
			% [cstage != null, lifted, deep_left, fine_right, asym, set_down])
	carve.queue_free()
	holder.queue_free()
	await get_tree().process_frame


## A stage shows no character (Luke's play, 2026-11-06): the player's own is the one working.
func _no_character(stage: Node) -> bool:
	return stage.find_children("*", "Skeleton3D", true, false).is_empty()


func _mouse(at: Vector2, button: MouseButton, shift: bool) -> InputEventMouseButton:
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = at
	ev.button_index = button
	ev.pressed = true
	ev.shift_pressed = shift
	return ev


## The columns of a shape round's inputs (time, column pairs).
func _columns_sent(inputs: PackedInt32Array) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, inputs.size(), 2):
		out.append(inputs[i])
	return out


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
	_check(SkillMinigames.CHALLENGE == {&"chop": 100, &"crack": 101, &"smelt": 102, &"shape": 103, &"beat": 104, &"carve": 105}, "the challenge kinds the server deals them as")
	_check(SkillMinigames.kind_of(BeatParams.new()) == SkillMinigames.BEAT and SkillMinigames.with_speed(BeatParams.new(), 50) is BeatParams
		and SkillMinigames.duration_of(BeatParams.new()) == 20 * 600 + 4000,
		"smelting's rhythm track: its own kind, no swing to speed, as long as its count-in, its beats and its pour")
	var chop: ChopParams = _params()
	var fast: ChopParams = SkillMinigames.with_speed(chop, 85) as ChopParams
	_check(fast != chop and fast.swing_ms == 255 and chop.swing_ms == 300, "a tool at 85 %% swings in 255 ms, and the content is left as it was")
	_check(SkillMinigames.with_speed(chop, 100) == chop and SkillMinigames.with_speed(SmeltParams.new(), 50) is SmeltParams,
		"as authored at 100 %%; a station round has no swing to speed")
	_check(SkillMinigames.arity(SkillMinigames.CRACK) == 3 and SkillMinigames.arity(SkillMinigames.SHAPE) == 2, "a strike on the rock is (time, x, y)")
	var baked: Dictionary = SkillMinigames.bake((RecipeDef.by_id(40004)).minigame)
	_check(baked.get("kind", "") == "shape" and (baked.get("outline", []) as Array).size() == 16 and not baked.has("display_name"),
		"a round bakes as its kind and its numbers")


## WHAT A PLAYED ROUND PAYS, AND RUNS (Luke's M11, 2026-11-05; built 2026-11-07): pay runs from a floor at a score of 0 to
## the multiplier at a full one (break-even near half); the rare edge grows with the score; gathering and smelting
## rounds run back to back, making a part never does; a run's tally, and what ends it.
func _run_active_pay() -> void:
	print("== regents: what a played round pays, and runs ==")
	var mult: float = HotRules.number(&"regents.active_yield_mult")
	var floor_share: float = HotRules.number(&"regents.active_yield_floor")
	_check(is_equal_approx(mult, 1.25) and is_equal_approx(floor_share, 0.75) and is_equal_approx(HotRules.number(&"regents.active_rare_mult"), 3.0),
		"the content's numbers: x%.2f at a full score, x%.2f at none, rares x%.1f at a full score" % [mult, floor_share, HotRules.number(&"regents.active_rare_mult")])
	_check(SkillingRules.break_even_pm(1.25, 0.75) == 500 and SkillingRules.break_even_pm(1.25, 0.0) == 800 and MinigameReadout.afk_break_even_pm() == 500,
		"break-even: half a score with the floor (80 %% without it, the curve before)")
	_check(is_equal_approx(SkillingRules.active_factor(1.25, 0.75, 1000), 1.25) and is_equal_approx(SkillingRules.active_factor(1.25, 0.75, 300), 0.9)
		and is_equal_approx(SkillingRules.active_factor(1.25, 0.75, 0), 0.75), "a full round x1.25, a poor one (30 %%) x0.9, none x0.75 of AFK")
	_check(is_equal_approx(SkillingRules.rare_factor(3.0, 0), 1.0) and is_equal_approx(SkillingRules.rare_factor(3.0, 500), 2.0),
		"a round nobody played finds rares as AFK does; half a round, twice as often")
	# Which rounds run.
	var tree: NodeDef = NodeDef.all_by_tier()[0]
	_check(SkillingComponent.runs(tree) and SkillingComponent.runs(RecipeDef.by_id(40001)) and not SkillingComponent.runs(RecipeDef.by_id(40004)),
		"rounds run back to back at a tree and a furnace, never at the anvil (one part, one round)")
	# A run's bookkeeping.
	var s: SkillingComponent = SkillingComponent.new()
	var said: Array[String] = []
	s.run_changed.connect(func(on: bool, why: String) -> void: said.append("%s:%s" % [on, why]))
	s._start_run(77)
	s.round_id = 5
	var logs: int = tree.yield_item.id
	s._count_run({"active": true, "target_id": 77, "qty": 3, "item_id": logs, "rare_item": 0, "depleted": false, "ran_out": false})
	s._count_run({"active": false, "target_id": 77, "qty": 9, "item_id": logs, "rare_item": 0, "depleted": false, "ran_out": false})
	s._count_run({"active": true, "target_id": 78, "qty": 9, "item_id": logs, "rare_item": 0, "depleted": false, "ran_out": false})
	s._count_run({"active": true, "target_id": 77, "qty": 2, "item_id": logs, "rare_item": 1, "depleted": false, "ran_out": false})
	_check(s.run_rounds == 2 and int(s.run_got[logs]) == 5 and s.run_rares == 1 and s.run_words().begins_with("2 rounds: 5 ")
		and s.run_words().ends_with("1 rare find"), "the run's tally counts its own played rounds only: \"%s\"" % s.run_words())
	s.stop_run_after_round()
	_check(s.run_target == 77 and s.run_stop_after, "E mid-round: the run goes on until the round closes")
	s.round_id = -1
	s.end_run(s._run_end_why)
	_check(s.run_target == -1 and said == ["true:", "false:"], "then it ends, said as the player's own stop (%s)" % str(said))
	s._start_run(77)
	s.round_id = 6
	s._count_run({"active": true, "target_id": 77, "qty": 1, "item_id": logs, "rare_item": 0, "depleted": true, "ran_out": false})
	_check(s.run_target == 77 and s.run_stop_after and s._run_end_why.begins_with("Worked out"), "a node worked out: the run ends as its round closes")
	s.round_id = -1
	s.stop_run_after_round("gone")
	_check(s.run_target == -1 and said.back() == "false:gone", "between rounds, a stop is now")
	s.free()
	# RANK EASES THE ROUND (Luke's M3): a copy of the round, a window wider (or a branch's stagger shorter) by the ease,
	# number for number with the server's `Minigame::score_eased`; the content itself untouched.
	var rock: CrackParams = (NodeDef.all_by_tier().filter(func(n: NodeDef) -> bool: return n.minigame is CrackParams)[0] as NodeDef).minigame as CrackParams
	var chop_p: ChopParams = tree.minigame as ChopParams
	var head: ShapeParams = (RecipeDef.by_id(40004)).minigame as ShapeParams
	var bar: BeatParams = (RecipeDef.by_id(40001)).minigame as BeatParams
	var steel_bar: BeatParams = (RecipeDef.by_id(40015)).minigame as BeatParams
	var rock_e: CrackParams = SkillMinigames.eased(rock, 12) as CrackParams
	var chop_e: ChopParams = SkillMinigames.eased(chop_p, 12) as ChopParams
	var head_e: ShapeParams = SkillMinigames.eased(head, 12) as ShapeParams
	var bar_e: BeatParams = SkillMinigames.eased(bar, 12) as BeatParams
	var steel_e: BeatParams = SkillMinigames.eased(steel_bar, 12) as BeatParams
	_check(rock_e != rock and rock_e.radius_pm == rock.radius_pm * 112 / 100 and chop_e.stagger_ms == chop_p.stagger_ms * 88 / 100
		and head_e.error_scale == head.error_scale * 112 / 100 and head_e.heat_ms == head.heat_ms * 112 / 100 and SkillMinigames.eased(rock, 0) == rock,
		"eased 12 %%: the rock's notch %d -> %d, a branch's stagger %d -> %d ms, the anvil's error scale %d -> %d; 0: as authored"
			% [rock.radius_pm, rock_e.radius_pm, chop_p.stagger_ms, chop_e.stagger_ms, head.error_scale, head_e.error_scale])
	_check(bar_e.perfect_ms == bar.perfect_ms * 112 / 100 and bar_e.good_ms == bar.beat_ms / 4 and steel_e.good_ms == mini(steel_bar.good_ms * 112 / 100, steel_bar.beat_ms / 4)
		and steel_e.perfect_ms == steel_bar.perfect_ms * 112 / 100 and bar.perfect_ms == 70,
		"the beat's windows wider, the outer never past a quarter beat (copper %d -> %d/%d ms, steel %d/%d -> %d/%d); the content untouched"
			% [bar.perfect_ms, bar_e.perfect_ms, bar_e.good_ms, steel_bar.perfect_ms, steel_bar.good_ms, steel_e.perfect_ms, steel_e.good_ms])
	var skilled: SimPlayer = SimPlayer.presets()[1]
	var at_req: int = int(MinigameReadout.measure(head, skilled, 12)["mean"])
	var three_on: int = int(MinigameReadout.measure(head_e, skilled, 12)["mean"])
	_check(three_on > at_req, "three ranks on, a skilled smith shapes the iron axe head better (%d -> %d)" % [at_req, three_on])


## BRITTLE NOTCHES (band 2's new thing for mining, a TEST, 2026-11-07): the coal rock's brittle notch struck while the
## rock still rings cracks wrong (a jar); struck once the ring fades, it opens; a seam's first notch is never brittle.
func _run_brittle() -> void:
	print("== regents: brittle notches ==")
	var coal: CrackParams = null
	for n: NodeDef in NodeDef.all_by_tier():
		if n.minigame is CrackParams and (n.minigame as CrackParams).brittle_permille > 0:
			coal = n.minigame as CrackParams
	_check(coal != null and coal.ring_ms > coal.swing_ms, "a rock with brittle notches, ringing longer than a swing (so a held strike lands too soon)")
	if coal == null:
		return
	var sd: int = -1
	for i: int in 400:
		if CrackModel.start(1 + i * 7919, coal).is_brittle(1):
			sd = 1 + i * 7919
			break
	var firsts_ok: bool = true
	for i: int in 30:
		var bm: CrackModel = CrackModel.start(1 + i * 7919, coal)
		for seam: int in 3:
			firsts_ok = firsts_ok and not bm.is_brittle(seam * coal.notches)
	var soon: CrackModel = CrackModel.start(sd, coal)
	var n0: Vector2i = soon.notch(0)
	var n1: Vector2i = soon.notch(1)
	soon.strike(0, n0.x, n0.y)
	var held: bool = soon.strike(100, n1.x, n1.y) == CrackModel.HELD   # mid-swing: held to the swing's end, still in the ring
	soon.settle(coal.swing_ms)
	var wait: CrackModel = CrackModel.start(sd, coal)
	wait.strike(0, n0.x, n0.y)
	_check(sd > 0 and firsts_ok and held and soon.jars == 1 and soon.cracked_wrong and soon.k == 1
		and wait.strike(coal.ring_ms, n1.x, n1.y) == CrackModel.HIT and wait.k == 2,
		"a brittle notch: struck mid-swing it lands in the ring and cracks wrong; struck as the ring fades, it opens; never a seam's first")


## SMELTING AS A RHYTHM TRACK (Luke, 2026-11-07: "Full rhythm track"; `BeatModel`): the track drawn from the seed, how a
## press is judged, the long draws, mashing never paying, the pour after it; the copper, iron and steel bars' rounds.
func _run_beat() -> void:
	print("== regents: smelting's rhythm track ==")
	var copper: BeatParams = (RecipeDef.by_id(40001)).minigame as BeatParams
	_check(copper != null and SkillMinigames.duration_of(copper) == BeatModel.duration_ms(copper), "the copper bar is smelted on the rhythm track")
	if copper == null:
		return
	# The track: a bar's first beat always has a note (or is inside a draw); notes in order, half a beat apart at the
	# least; a draw ends by the last beat and nothing is played inside it; rounds' tracks differ.
	var bad: Array[String] = []
	var tracks: Dictionary = {}
	var draws: int = 0
	var offbeats: int = 0
	for sd: int in range(1, 41):
		var m: BeatModel = BeatModel.start(sd, copper)
		tracks[str(m.note_t)] = true
		for i: int in range(0, copper.beats, 4):
			var at: int = (copper.lead_beats + i) * copper.beat_ms
			if not m.note_t.has(at):
				var in_draw: bool = false
				for j: int in m.note_t.size():
					in_draw = in_draw or (m.note_end[j] > m.note_t[j] and m.note_t[j] < at and m.note_end[j] >= at)
				if not in_draw:
					bad.append("seed %d: no note on bar beat %d" % [sd, i])
		for j: int in m.note_t.size():
			offbeats += int(posmod(m.note_t[j], copper.beat_ms) != 0)
			if j > 0 and m.note_t[j] - m.note_end[j - 1] < copper.beat_ms / 2:
				bad.append("seed %d: note %d too near the last" % [sd, j])
			if m.note_end[j] > m.note_t[j]:
				draws += 1
				if m.note_end[j] > (copper.lead_beats + copper.beats - 1) * copper.beat_ms:
					bad.append("seed %d: a draw past the last beat" % sd)
	_check(bad.is_empty() and tracks.size() >= 38 and draws > 0 and offbeats > 0,
		"the track: every bar starts on a note (or inside a draw), notes half a beat apart at least, draws end inside it; %d tracks of 40 differ, %d draws, %d off-beats %s" % [tracks.size(), draws, offbeats, str(bad)])
	# Judging a press.
	var m1: BeatModel = BeatModel.start(3, copper)
	var t0: int = m1.note_t[0]
	_check(m1.press(t0 - 40, BeatModel.DOWN) == BeatModel.PERFECT and m1.press(t0 + 20, BeatModel.DOWN) == BeatModel.IGNORED,
		"pressed 40 ms early: on the beat; pressed again while down: nothing")
	m1.press(t0 + 60, BeatModel.UP)
	var t1: int = m1.note_t[1]
	_check(m1.press(t1 + copper.perfect_ms + 1, BeatModel.DOWN) == BeatModel.GOOD, "%d ms late: close, worth %d" % [copper.perfect_ms + 1, copper.good_pm])
	var m2: BeatModel = BeatModel.start(3, copper)
	var gap: int = (copper.lead_beats * copper.beat_ms) / 2   # in the count-in: nothing to press
	_check(m2.press(gap, BeatModel.DOWN) == BeatModel.STRAY and m2.strays == 1 and m2.press(gap + 10, BeatModel.UP) == BeatModel.IGNORED,
		"a press in the count-in meets no note: wasted, and costs")
	_check(m2.press(m2.note_t[0] + copper.good_ms + 1, BeatModel.DOWN) == BeatModel.STRAY, "%d ms after a note: too late, wasted" % (copper.good_ms + 1))
	# Mashing never pays; holding the button down the whole track plays one note.
	var mash: PackedInt32Array = PackedInt32Array()
	for t: int in range(0, BeatModel.track_end_ms(copper), 40):
		mash.append_array(PackedInt32Array([t, BeatModel.DOWN if (t / 40) % 2 == 0 else BeatModel.UP]))
	var mashed: Dictionary = BeatModel.play(7, copper, mash)
	var held: Dictionary = BeatModel.play(7, copper, PackedInt32Array([BeatModel.start(7, copper).note_t[0], BeatModel.DOWN]))
	_check(int(mashed["track_pm"]) == 0 and int(held["perfect"]) == 1 and int(held["track_pm"]) < 150,
		"mashing the bellows scores nothing on the track (%d wasted); held down from the first note, one note (%d)" % [mashed["strays"], held["track_pm"]])
	# A long draw: held through its end it is paid in full, let go halfway about half.
	var sd2: int = 1
	while sd2 < 200 and _first_draw(BeatModel.start(sd2, copper)) < 0:
		sd2 += 1
	var full: BeatModel = BeatModel.start(sd2, copper)
	var d: int = _first_draw(full)
	full.press(full.note_t[d], BeatModel.DOWN)
	full.advance_to(full.note_end[d])
	var half: BeatModel = BeatModel.start(sd2, copper)
	half.press(half.note_t[d], BeatModel.DOWN)
	half.press((half.note_t[d] + half.note_end[d]) / 2, BeatModel.UP)
	var near: BeatModel = BeatModel.start(sd2, copper)
	near.press(near.note_t[d], BeatModel.DOWN)
	near.press(near.note_end[d] - copper.good_ms, BeatModel.UP)
	_check(d >= 0 and full.got[d] == 1000 and full.holding < 0 and half.got[d] == 500 and near.got[d] == 1000,
		"a long draw: held to its end, all of it (%d); let go halfway, half (%d); let go just before its end, all (%d)" % [full.got[d], half.got[d], near.got[d]])
	# The pour: not until it is ready.
	var end: int = BeatModel.track_end_ms(copper)
	var m3: BeatModel = BeatModel.start(3, copper)
	_check(m3.press(end + 10, BeatModel.DOWN) == BeatModel.IGNORED and m3.press(end + 20, BeatModel.UP) == BeatModel.IGNORED
		and m3.press(end + copper.pour_ready_ms, BeatModel.DOWN) == BeatModel.POUR and m3.press(end + copper.pour_ready_ms + 500, BeatModel.UP) == BeatModel.STOP
		and m3.fill == 10 * copper.pour_rate, "the pour: a press as the track ends does nothing; ready, holding tilts it and letting go stops it")
	# Each metal quicker and busier than the last.
	var iron: BeatParams = (RecipeDef.by_id(40002)).minigame as BeatParams
	var steel: BeatParams = (RecipeDef.by_id(40015)).minigame as BeatParams
	_check(iron != null and steel != null and copper.beat_ms > iron.beat_ms and iron.beat_ms > steel.beat_ms
		and copper.offbeat_pm < iron.offbeat_pm and iron.offbeat_pm < steel.offbeat_pm and copper.perfect_ms > iron.perfect_ms and iron.perfect_ms > steel.perfect_ms,
		"copper, iron, steel: each a quicker beat, more off-beats, a tighter window")
	# SLAG (band 2's test, 2026-11-07): steel's gray notes are skimmed with the second button, never pumped; copper
	# has none and ignores a skim.
	var sd3: int = -1
	for i: int in 200:
		var sm: BeatModel = BeatModel.start(1 + i * 7919, steel)
		if sm.slag.count(1) > 0:
			sd3 = 1 + i * 7919
			break
	var skimmed: BeatModel = BeatModel.start(sd3, steel)
	var sj: int = skimmed.slag.find(1)
	var pumped: BeatModel = BeatModel.start(sd3, steel)
	var none_on_copper: bool = BeatModel.start(sd3, copper).slag.count(1) == 0 and BeatModel.start(3, copper).press(2400, BeatModel.SKIM) == BeatModel.IGNORED
	_check(steel.slag_pm > 0 and copper.slag_pm == 0 and sj >= 0 and skimmed.press(skimmed.note_t[sj], BeatModel.SKIM) == BeatModel.PERFECT
		and pumped.press(pumped.note_t[sj], BeatModel.DOWN) == BeatModel.STRAY and pumped.got[sj] < 0
		and skimmed.press(skimmed.note_t[sj] + 1, BeatModel.SKIM) == BeatModel.STRAY and none_on_copper,
		"slag on steel: skimmed on its time, full value; pumped with the main button, wasted and still there; a second skim on none, wasted; copper has none and ignores a skim")


## The first long draw of a track (-1: none).
func _first_draw(m: BeatModel) -> int:
	for j: int in m.note_t.size():
		if m.note_end[j] > m.note_t[j]:
			return j
	return -1


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
	var bar: SmeltParams = SmeltParams.new()   # no content plays it since 2026-11-07 (the rhythm track): kept for old rounds
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
	# A careful smith's round (the readout's skilled player: the pattern lifted, worked from memory, checked once,
	# set down), played through the minigame's own strike_at.
	var played: PackedInt32Array = MinigameReadout.play_round(13, part, SimPlayer.presets()[1])["inputs"]
	for k: int in range(0, played.size(), 2):
		shape.strike_at(played[k], played[k + 1])
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
	_check(buttons.size() == 23 and game is ChopMinigame and game.state == SkillMinigame.State.READY,
		"twenty-three rounds to play (six nodes, flax having none yet; three bars, twelve smithed parts with the trowel blades, the carved bow and staff), the first, a tree's, on show (%d)" % buttons.size())
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
	# T: the difficulty readout of the round on show (MINIGAMES_PREP.md §6), cleared when another is picked.
	lab.call("show_readout", 4)
	var shown: String = (lab.get("_readout") as Label).text
	_check(shown.begins_with("Tree") and shown.contains("Flawless") and shown.contains("beats AFK"), "T: the tree's readout, four players: %s" % shown.get_slice("\n", 1))
	lab.call("pick", 1)
	_check((lab.get("_readout") as Label).text.is_empty(), "another round picked: its readout waits for T")
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
		"the v1 pools, less what waits for crits, armor and reach: %s" % str(keys))
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
		and CombatComponent.action_tags(axe_kit, axe_kit.skills[0]) == [&"skill"],
		"what an action is: basic, the string's last (its finisher), skill")
	# HEAVY, ON POISE (Luke, 2026-11-02): the last hit wears 35 % more of a foe's poise; a stagger is no longer longer.
	var heavy_ids: Array[int] = [_trait_id(&"heavy")]
	_check(is_equal_approx(Traits.mult(heavy_ids, &"poise", [&"basic", &"combo_last"]), 1.35) and is_equal_approx(Traits.mult(heavy_ids, &"poise", [&"basic"]), 1.0)
		and is_equal_approx(Traits.mult(heavy_ids, &"stagger_time", [&"basic", &"combo_last"]), 1.0),
		"Heavy: the last hit wears poise x1.35, a first step's untouched, no stagger lengthened")
	var heavy_def: TraitDef = load("res://game/regents/content/trait/heavy.tres") as TraitDef
	_check(not _names_a_role(heavy_def.gives) and heavy_def.gives.contains("off balance"), "Heavy says what it does, no move's name: \"%s\"" % heavy_def.gives)
	# THE GUARD FACES FORWARD: the server's `in_guard_arc`, twinned (yaw 0 faces -z; 120 degrees in all).
	_check(CombatComponent.guard_stops(0.0, 0.0, -2.0) and CombatComponent.guard_stops(0.0, 1.0, -1.0) and not CombatComponent.guard_stops(0.0, 2.0, 0.0)
		and not CombatComponent.guard_stops(0.0, 0.0, 2.0) and CombatComponent.guard_stops(PI, 0.0, 2.0),
		"the guard stops a hit in front or 45 degrees off; not from the side or behind; turned round, behind is in front")
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
