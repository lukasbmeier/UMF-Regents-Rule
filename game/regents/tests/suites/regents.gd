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
	_run_pull()
	_run_skin()
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
	_run_glade_look()
	_run_combat_pass()
	await _run_crosshair()
	await _run_shot_stops()
	await _run_cinema_lab()


func _run_cinema_lab() -> void:
	# Proof-of-concept cinematic parser, VO resolver, 4 dialog presenters, flashbacks, trailer, and director.
	var parsed: Dictionary = CinemaDialogue.parse(CinemaDialogue.FRONTIER_SCRIPT)
	_check(parsed.has("start") and parsed.has("start_hub") and parsed.has("flashback_prompt"),
		"cinema: frontier script sections parsed")

	var dlg: CinemaDialogue = CinemaDialogue.new()
	dlg.load_script(CinemaDialogue.FRONTIER_SCRIPT)
	dlg.start("start")
	_check(str(dlg.active_line.get("speaker", "")) == "Drillmaster" and str(dlg.active_line.get("line_id", "")) == "drill_01",
		"cinema: first line speaker and VO id")
	var first_tags: Dictionary = dlg.active_line.get("tags", {}) as Dictionary
	_check(str(first_tags.get("cam", "")) == "wide_camp" and str(first_tags.get("pose", "")) == "locomotion.idle",
		"cinema: inline cam and pose tags parsed")
	var vo: AudioStream = CinemaDialogue.resolve_voice(dlg.active_line)
	_check(vo is AudioStreamWAV and (vo as AudioStreamWAV).data.size() > 0,
		"cinema: VO resolver yields non-empty AudioStreamWAV fallback")
	dlg.state["asked_writ"] = true
	_check(not dlg.eval_condition("not asked_writ") and dlg.eval_condition("asked_writ"),
		"cinema: choice condition evaluator")

	var lab_scene: PackedScene = load("res://game/regents/cinema/cinema_lab.tscn") as PackedScene
	_check(lab_scene != null, "cinema: cinema_lab.tscn loads")
	if lab_scene == null:
		return
	var lab: CinemaLab = lab_scene.instantiate() as CinemaLab
	_check(lab != null, "cinema: cinema_lab instantiates CinemaLab")
	add_child(lab)
	await get_tree().process_frame

	_check(lab.dialogue != null and lab.balloon != null, "cinema: lab wires dialogue and balloon")

	# 1. All four dialog visual styles switch cleanly.
	lab.set_dialog_style(CinemaBalloon.Style.OSRS_BOX)
	_check(lab.balloon.current_style == CinemaBalloon.Style.OSRS_BOX
		and lab.balloon._osrs_panel.visible
		and not lab.balloon._bubble_root.visible
		and not lab.balloon._plain_box.visible
		and not lab.balloon._card_panel.visible,
		"cinema: OSRS_BOX presenter active")
	_check(lab.balloon._bust_mannequin != null and lab.balloon._bust_mannequin.definition != null,
		"cinema: OSRS 3D bust mannequin loaded")
	_check(lab.balloon._bust_mannequin.rotation.y > 2.5,
		"cinema: OSRS 3D bust faces +Z portrait camera")
	lab.balloon._process(1.0)
	_check(is_zero_approx(lab.balloon._bust_gesture_timer),
		"cinema: OSRS 3D bust returns to calm idle after opening gesture")

	var dm_fwd: Vector3 = -lab._drillmaster.global_transform.basis.z
	var to_adv: Vector3 = (lab._adventurer.global_position - lab._drillmaster.global_position).normalized()
	_check(dm_fwd.dot(to_adv) > 0.5,
		"cinema: Drillmaster -Z forward faces Adventurer")
	_check(lab._drillmaster._tree != null and lab._drillmaster._tree.tree_root is AnimationNodeBlendTree,
		"cinema: world actors use full AnimationTreeBuilder graph for non-looping one-shots")

	lab.set_dialog_style(CinemaBalloon.Style.SPEECH_BUBBLE)
	_check(lab.balloon._bubble_root.visible and not lab.balloon._osrs_panel.visible,
		"cinema: SPEECH_BUBBLE presenter active")

	lab.set_dialog_style(CinemaBalloon.Style.PLAIN_SUBTITLE)
	_check(lab.balloon._plain_box.visible and not lab.balloon._bubble_root.visible,
		"cinema: PLAIN_SUBTITLE presenter active")

	lab.set_dialog_style(CinemaBalloon.Style.REGENTS_CARD)
	_check(lab.balloon._card_panel.visible and not lab.balloon._plain_box.visible,
		"cinema: REGENTS_CARD presenter active")

	# 2. Branching hub choices + flag gating.
	lab.set_part(CinemaLab.Part.DIALOG)
	var safety: int = 0
	while lab.dialogue.active_choices.is_empty() and safety < 8:
		lab.dialogue.advance()
		safety += 1
	_check(lab.dialogue.active_choices.size() == 4, "cinema: hub presents 4 initial choices")
	lab.dialogue.choose(0)
	safety = 0
	while lab.dialogue.active_choices.is_empty() and safety < 8:
		lab.dialogue.advance()
		safety += 1
	_check(bool(lab.dialogue.state.get("asked_writ", false)) and lab.dialogue.active_choices.size() == 3,
		"cinema: asked_writ removes Writ branch on return to hub")

	# 3. Flashback modes (In-Place Echo and Isolated 3D Stage) + decision inside flashback.
	lab.launch_flashback_demo(CinemaLab.FlashbackMode.ECHO)
	_check(lab.active_part == CinemaLab.Part.FLASHBACK
		and lab.active_flashback == CinemaLab.FlashbackMode.ECHO
		and lab._echo_root.visible and not lab._present_root.visible and lab._memory_grade.visible,
		"cinema: In-Place Memory Echo swaps to echo cast + memory shader")
	var archer_rig: Dictionary = lab._actor_rigs.get(lab._echo_archer, {}) as Dictionary
	var archer_sword: MeshInstance3D = lab._echo_archer.skeleton.find_child("Skeleton_Sword", true, false) as MeshInstance3D
	_check(archer_sword != null and not archer_sword.visible and archer_rig.get("held", null) is HeldItem,
		"cinema: skeleton archer hides sword mesh and equips HeldItem bow")

	lab.launch_flashback_demo(CinemaLab.FlashbackMode.STAGE)
	_check(lab.active_flashback == CinemaLab.FlashbackMode.STAGE and lab._stage_container.visible,
		"cinema: Isolated 3D Stage shows diorama SubViewport")

	lab.dialogue.advance()
	_check(lab.dialogue.active_choices.size() == 2, "cinema: flashback presents tactical choice")
	lab.dialogue.choose(0)
	_check(str(lab.dialogue.state.get("memory_deed", "")) == "shield_wall",
		"cinema: flashback choice records memory_deed")
	lab.dialogue.advance()
	_check(lab.active_flashback == CinemaLab.FlashbackMode.NONE and lab._present_root.visible,
		"cinema: return_present ends flashback and restores frontier cast")

	# 4. Trailer slow-mo + Director free-cam dolly rail.
	lab.start_trailer()
	_check(lab.active_part == CinemaLab.Part.TRAILER and lab.trailer_playing and lab._tr_anvil != null,
		"cinema: trailer sequencer starts with forge anvil and directed shots")
	for _step: int in range(4):
		lab._process(1.0)
	_check(Engine.time_scale < 0.5 and lab._trailer_cue >= 9, "cinema: trailer shot 2 engages slow motion")

	lab.start_director()
	_check(lab.director_active and not lab.trailer_playing and is_equal_approx(Engine.time_scale, 1.0),
		"cinema: director resets trailer and restores normal time scale")
	lab.add_dolly_keyframe()
	lab._camera.global_position += Vector3(2.0, 0.5, -1.5)
	lab.add_dolly_keyframe()
	_check(lab._dolly_curve.point_count == 2, "cinema: director records Curve3D dolly keyframes")
	lab.play_dolly()
	lab._process(0.1)
	lab.clear_dolly()
	_check(lab._dolly_curve.point_count == 0, "cinema: director clears dolly curve")

	lab.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "cinema: Engine.time_scale clean on teardown")


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
	# NOT YET ON THE CONTINENT: glade points added since the continent was last built (`build_continent.tscn`: Luke's
	# say-so, it also brings the glade's new look over, PROGRESS step 59 "Left"). Each must really be missing: built
	# again, this list is emptied (the archer goes there with FOES_PREP.md section 9 step 7).
	var not_yet: Array[String] = []
	for id: String in not_yet:
		_check(moved.has(id) and not theirs.has(id), "%s is not on the continent yet (built again: take it off this list)" % id)
		moved.erase(id)
	_check(glade != null and moved.is_empty(), "the glade's %d points are all in its camp, where the glade has them (moved or missing: %s; not yet built in: %s)" % [glade_points.size(), str(moved), str(not_yet)])
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
		elif kind.begins_with("skeleton") or kind == "deer" or kind == "wolf":
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
	_check(sword.light.size() == 3 and sword.skills.size() == 5 and sword.skills[0].display_name == "Lunge" and sword.slot_of_skill(0) == KitDef.SLOT_BASE,
		"the sword: a string of three, Lunge on Q, then its pool (armor run P1: three options and an ult, placeholders)")
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
	var bar: String = RegentsAbilityBar.moves_words(c, null)
	# The string by its moves' names, the last the plain grip's (no row in a bag: the plain role); never "finisher".
	# The text line became the ability bar (step 72): its words are the weapon's tooltip (the regents_bar suite).
	_check(bar.contains("Iron sword") and bar.contains("Left click: Slash - Slash (second) - Piercing thrust")
		and bar.contains("Right click: tap to parry, hold for a light guard") and not bar.contains("Hold left click") and not bar.to_lower().contains("finisher"),
		"the weapon's moves: %s" % bar.replace("
", " / "))
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
	_check(" / ".join(names) == "Bolt bolt / Fireball bolt / Frost Ring area / Gale cone / Meteor (placeholder) area", "its spells: %s" % " / ".join(names))
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


## A challenge row as the SDK hands it (the fields `SkillingComponent` reads).
## Its fields by `get` (one of them is `seed`, a GDScript global, so not a member).
class ChallengeRow extends RefCounted:
	var fields: Dictionary = {}

	func _get(property: StringName) -> Variant:
		return fields.get(String(property))


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
	var all_foes: Array[FoeDef] = FoeDef.all()
	# The camp's two, the tutorial's sparring partner (Luke, 2026-11-01), the deer (hunting, 2026-11-09: never fights),
	# and the wolf (2026-11-10: hunts in packs, fights with its own kit).
	_check(all_foes.size() == 7 and all_foes.any(func(f: FoeDef) -> bool: return f.key == &"imp") and all_foes.any(func(f: FoeDef) -> bool: return f.key == &"sparring_skeleton")
		and all_foes.any(func(f: FoeDef) -> bool: return f.key == &"skeleton_archer")
		and all_foes.any(func(f: FoeDef) -> bool: return f.key == &"deer")
		and all_foes.any(func(f: FoeDef) -> bool: return f.key == &"wolf"), "seven foes: %s" % ", ".join(all_foes.map(func(f: FoeDef) -> String: return String(f.key))))
	var foes: Array[FoeDef] = all_foes.filter(func(f: FoeDef) -> bool: return f.fights)
	var deer: FoeDef = FoeDef.by_kind(106)
	var wolf: FoeDef = FoeDef.by_kind(107)
	var genre_defs: Array = (load("res://game/regents/genre.tres") as Resource).get(&"entity_definitions") as Array
	_check(deer != null and deer.key == &"deer" and not deer.fights and deer.kit == null and deer.validate().is_empty()
		and deer.character.brain == &"regents/deer" and genre_defs.has(deer.character) and deer.family == &"beast"
		and deer.character.animation_set.skeleton_family == &"deer" and deer.character.animation_set.missing_required().is_empty()
		and deer.character.animation_set.dangling_clips().is_empty() and deer.character.animation_set.anim_name(AnimationSet.RUN) == &"Gallop"
		and deer.character.movement_profile.run_speed > 8.0 and deer.poise >= 10000 and deer.to_bake()["brain"] == "regents/deer"
		and deer.to_bake()["fights"] == false,
		"the deer: never fights, no kit, its own brain, the genre's; a beast; its own clips (it gallops), faster than a sprint, never staggered")
	var wkit: KitDef = wolf.kit if wolf != null else null
	_check(wolf != null and wolf.key == &"wolf" and wolf.fights and wkit != null and wkit.key == &"wolf" and wolf.family == &"beast"
		and is_equal_approx(wolf.pack_m, 15.0) and wolf.character.animation_set.skeleton_family == &"wolf"
		and wolf.character.animation_set.missing_required().is_empty() and wolf.character.animation_set.dangling_clips().is_empty()
		and wkit.light.size() == 3 and wkit.hit_entry(wkit.light[1]) != null and wkit.hit_entry(wkit.light[1]).status.status == 108
		and wkit.hit_entry(wkit.light[1]).status_ms == 3000 and wkit.hit_entry(wkit.light[2]) != null
		and is_equal_approx(wkit.hit_entry(wkit.light[2]).push_mps, 10.0) and wkit.light[2].lunges
		and wolf.character.movement_profile.dash_impulse > 0.0,
		"the wolf: a pack beast (15 m), its three-step string (bite, hamstring bite that slows 3 s, unblockable lunge that leaps and pushes 10 m/s)")
	var bad_hit := KitHit.new()
	var bad_kit := KitDef.new()
	bad_kit.id = 40098
	bad_kit.display_name = "Bad"
	bad_kit.key = &"bad"
	bad_kit.skill = wkit.skill
	bad_kit.light = wkit.light.duplicate()
	bad_kit.hits = [bad_hit]
	_check(not bad_kit._validate_hits().is_empty(), "a KitHit with no ability or effect is refused: %s" % str(bad_kit._validate_hits()))
	var kitless := FoeDef.new()
	kitless.key = &"x"
	kitless.character = deer.character
	_check(kitless.validate().any(func(m: String) -> bool: return m.contains("kit")), "a foe that fights with no kit is still refused")
	# SMOOTH SHADED (Luke, 2026-11-10): the model is made flat (every triangle its own three corners); its import script
	# (`art/animals/smooth_shading_import.gd`) gives every corner at a point the same normal (a UV seam may keep corners
	# apart, never their normals). Flat, the corners at a point face each its own way.
	var look: Node = deer.character.visual_scene.instantiate()
	var shared_points: int = 0
	var bent: int = 0
	for mi: Node in look.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var at: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var first: Dictionary[Vector3, Vector3] = {}
			var counted: Dictionary[Vector3, bool] = {}
			for v: int in at.size():
				if not first.has(at[v]):
					first[at[v]] = normals[v]
					continue
				if not counted.has(at[v]):
					counted[at[v]] = true
					shared_points += 1
				if first[at[v]].dot(normals[v]) < 0.999:
					bent += 1
	look.free()
	_check(shared_points > 0 and bent == 0, "the deer is smooth shaded: %d points shared by corners, %d corners facing their own way" % [shared_points, bent])
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
		if lights.size() == 1:
			# A STRING OF ONE STEP HAS NO FINISHER (2026-11-12: a foe that shoots, its lone shove): nothing unblockable.
			_check(f.shot() != null and f.kit.unblockable.is_empty() and not f.kit.is_finisher(last),
				"%s's one swing, %s, is no finisher: it is a foe that shoots, with nothing unblockable" % [f.display_name, last.display_name])
		_check(lights.size() == 1 or f.kit.unblockable.size() == 1 and f.kit.unblockable[0] == last and KitDef.is_unblockable(last.id) and last.wind_up_ms >= 800,
			"%s's string (of more than one) ends in its finisher, %s: unblockable, winding up %d ms" % [f.display_name, last.display_name, last.wind_up_ms])
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


## The yaw that faces a body at `from` toward `at` (-Z forward): a foe that SEES in front (Luke's F9, 2026-11-13) is
## turned to face its test's player where the test is about what it does once it has noticed them.
static func _yaw_to(from: Vector3, at: Vector3) -> float:
	return atan2(-(at.x - from.x), -(at.z - from.z))


class _FoeWorld extends NpcWorldView:
	var way: PackedVector3Array = PackedVector3Array()
	var sight: bool = true
	var paths: int = 0
	func path(_from: Vector3, _to: Vector3, _radius: float, _height: float) -> PackedVector3Array:
		paths += 1
		return way
	func can_see(_a: Vector3, _b: Vector3) -> bool:
		return sight


## A FOE GOES ROUND THINGS, AND A TARGET OUT OF SIGHT IS NOT FORGOTTEN AT ONCE (Luke's continent playtest,
## 2026-10-24, #4: "a bush blocks a skeleton's sight and it turns back").
## A FOE'S BEHAVIOR IS A TREE (Luke's F2, 2026-11-12, FOES_PREP.md section 3.1): `chased` is a brain that has thought.
func _run_foe_tree(chased: NpcBrain) -> void:
	print("== regents: a foe's behavior is a tree ==")
	_check(chased.tree_status() == BT.SUCCESS, "the brain that chased ran a tree: one of its tasks did the think (%d)" % chased.tree_status())
	var trees_dir: String = String(chased.get(&"TREES_DIR"))
	for f: FoeDef in FoeDef.all():
		if not f.fights:
			continue
		var path: String = trees_dir + String(f.behavior) + ".tres"
		_check(f.behavior != &"" and ResourceLoader.exists(path) and load(path) is BehaviorTree,
			"%s fights by a tree the referee has (%s)" % [f.key, path])
	var none: FoeDef = FoeDef.by_kind(103).duplicate() as FoeDef
	none.behavior = &""
	_check(not none.validate().filter(func(e: String) -> bool: return e.contains("behavior")).is_empty(),
		"a foe that fights with no behavior: refused by its validate")
	none.behavior = &"no_such_tree"
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 2)
	b.self_id = 901
	b.set(&"foe", none)
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	them.pos = Vector3(3, 0, 0)
	w.states = {901: me, 1: them}
	w.kinds = {901: 103, 1: 0}
	b.think(me, w)
	_check(b.state == &"lost" and b.target() == 0 and not b.has_goal() and b.take_acts().is_empty(),
		"a behavior with no tree: it stands still beside a player, chasing and swinging nothing (%s)" % b.describe())


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
	me.yaw = _yaw_to(me.pos, them.pos)   # it faces them (F9: it sees in front)
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
	_run_foe_tree(brain)
	_run_foe_turns()
	_run_foe_aim()
	_run_deer_brain()
	_run_wolf_pack()
	_run_foe_string_chase(107)
	_run_foe_string_chase(103)
	_run_foe_archer()
	_run_foe_imp()
	_run_foe_notice()
	_run_foe_stagger_string()


## PARRIED, ITS STRING GOES ON (Luke, 2026-11-13: "I could consistently get hit 1 parried but then it jumps straight to
## hit 3"): a parry staggers the foe, and its next swing, sent then, was refused by the server ("you cannot while
## staggered") but counted, so its second step was lost. Staggered, it sends nothing; after, its NEXT step comes.
func _run_foe_stagger_string() -> void:
	print("== regents: a staggered foe's string waits, and goes on ==")
	var t: Array[int] = [960000]
	var kit: KitDef = FoeDef.by_kind(103).kit
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 61)
	b.clock = func() -> int: return t[0]
	b.self_id = 8501
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	them.pos = Vector3(FoeDef.by_kind(103).reach_m - 0.4, 0, 0)
	me.yaw = _yaw_to(me.pos, them.pos)
	w.states = {8501: me, 8601: them}
	w.kinds = {8501: 103, 8601: 0}
	var first: int = -1
	for i: int in 10:
		b.think(me, w)
		var acts: Array[Dictionary] = b.take_acts()
		if not acts.is_empty():
			first = int(acts[0]["ability"])
			break
		t[0] += 100
	_check(first == kit.light[0].id, "in reach, its string's first step (%d)" % first)
	w.statuses = {8501: 103}   # parried: Staggered
	var sent: int = 0
	for i: int in 30:
		t[0] += 100
		b.think(me, w)
		sent += b.take_acts().size()
	_check(sent == 0, "NEGATIVE: staggered for 3 s, it sends no swing to be refused (%d sent)" % sent)
	w.statuses = {}
	var next: int = -1
	for i: int in 30:
		t[0] += 100
		b.think(me, w)
		var acts: Array[Dictionary] = b.take_acts()
		if not acts.is_empty():
			next = int(acts[0]["ability"])
			break
	_check(next == kit.light[1].id, "on its feet again, its SECOND step (%d), not its finisher (%d)" % [next, kit.light[2].id])
	# A caster too: staggered it casts nothing, and the round of its casts is not moved on (its first is still an ember).
	var imp: FoeDef = FoeDef.by_kind(109)
	var ib: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 62)
	ib.clock = func() -> int: return t[0]
	ib.self_id = 8502
	var iw := _FoeWorld.new()
	var ime := MovementState.new()
	var prey := MovementState.new()
	prey.pos = Vector3(9.0, 0, 0)
	ime.yaw = _yaw_to(ime.pos, prey.pos)
	iw.states = {8502: ime, 8602: prey}
	iw.kinds = {8502: 109, 8602: 0}
	iw.statuses = {8502: 105}   # Flinched
	var cast_while: int = 0
	for i: int in 20:
		t[0] += 100
		ib.think(ime, iw)
		cast_while += ib.take_acts().size()
	iw.statuses = {}
	var cast: int = -1
	for i: int in 30:
		t[0] += 100
		ib.think(ime, iw)
		var acts: Array[Dictionary] = ib.take_acts()
		if not acts.is_empty():
			cast = int(acts[0]["ability"])
			break
	_check(cast_while == 0 and cast == imp.shot().id, "the imp, flinched, casts nothing; then its round's first, an ember (%d sent while, then %d)" % [cast_while, cast])


## A brain of foe `kind` (with `def` in place of its own, when given) at the origin facing -Z (yaw 0), and one player
## (id 1) at `at` moving `vel`, `sight` whether a ray reaches them: whether one think makes them its target.
func _noticed(at: Vector3, vel: Vector3, sight: bool, def: FoeDef = null) -> bool:
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 51)
	b.clock = func() -> int: return 800000
	b.self_id = 8401
	if def != null:
		b.set(&"foe", def)
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	them.pos = at
	them.vel = vel
	w.sight = sight
	w.states = {8401: me, 1: them}
	w.kinds = {8401: 103, 1: 0}
	b.think(me, w)
	return b.target() == 1


## NOTICING AND REST (Luke's F9-F11, 2026-11-13; FOES_PREP.md section 9 step 5): a foe SEES in front (`notice_arc_deg`
## at `notice_m`, in sight) and HEARS all round (`hear_m`; `hear_sprint_m` sprinting), so a camp can be come at from
## behind; at rest it WANDERS a few meters round its point; hit from beyond its sight it turns on WHO HIT IT.
func _run_foe_notice() -> void:
	print("== regents: a foe sees in front, hears all round, wanders, turns on who hit it ==")
	var skel: FoeDef = FoeDef.by_kind(103)
	_check(is_equal_approx(skel.notice_arc_deg, 140.0) and is_equal_approx(skel.hear_m, 4.0) and is_equal_approx(skel.hear_sprint_m, 8.0)
		and is_equal_approx(skel.wander_m, 3.0) and skel.notice_m > 8.0,
		"a skeleton warrior sees 140 degrees in front to %.0f m, hears 4 m all round (8 m a sprint), wanders 3 m" % skel.notice_m)
	var side60: Vector3 = Vector3(0, 0, -8).rotated(Vector3.UP, deg_to_rad(60.0))
	var side80: Vector3 = Vector3(0, 0, -8).rotated(Vector3.UP, deg_to_rad(80.0))
	_check(_noticed(Vector3(0, 0, -8), Vector3.ZERO, true), "8 m in front of it, in sight: seen")
	_check(_noticed(side60, Vector3.ZERO, true), "8 m off, 60 degrees from its front (inside its 70): seen")
	_check(not _noticed(side80, Vector3.ZERO, true), "NEGATIVE: 8 m off, 80 degrees from its front (past its 70): not seen")
	_check(not _noticed(Vector3(0, 0, 8), Vector3(0, 0, -5), true), "NEGATIVE: 8 m behind it, running at it (5 m/s): not seen, not heard")
	_check(not _noticed(Vector3(0, 0, -8), Vector3.ZERO, false), "NEGATIVE: 8 m in front but out of sight (a rock between): not seen")
	_check(_noticed(Vector3(0, 0, 3.5), Vector3.ZERO, false), "3.5 m behind it, out of sight: heard")
	_check(_noticed(Vector3(0, 0, 7), Vector3(0, 0, -8), true), "7 m behind it, SPRINTING (8 m/s): heard")
	_check(not _noticed(Vector3(0, 0, 7), Vector3(0, 0, -5), true), "NEGATIVE: 7 m behind it, running (5 m/s, no sprint): not heard")
	_check(not _noticed(Vector3(0, 0, 9), Vector3(0, 0, -8), true), "NEGATIVE: 9 m behind it, sprinting (past its 8 m): not heard")
	var all_round: FoeDef = skel.duplicate() as FoeDef
	all_round.notice_arc_deg = 360.0
	_check(_noticed(Vector3(0, 0, 8), Vector3.ZERO, true, all_round), "a foe of notice_arc_deg 360 sees all round: 8 m behind it, seen")

	# AT REST IT WANDERS (F10): a stand, then a few steps at a walk to a spot within wander_m of its point, and again.
	var t: Array[int] = [900000]
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 52)
	b.clock = func() -> int: return t[0]
	b.self_id = 8402
	var w := _FoeWorld.new()
	var me := MovementState.new()
	w.states = {8402: me}
	w.kinds = {8402: 103}
	b.think(me, w)
	_check(b.state == &"idle" and not b.has_goal(), "nobody near: it stands at its point first (%s)" % b.describe())
	var stand_max: int = int(b.get(&"WANDER_STAND_MAX_MS"))
	var spots: Array[Vector3] = []
	var walked: bool = true
	var stood: bool = true
	for i: int in 6:
		t[0] += stand_max + 1
		b.think(me, w)
		if not b.has_goal():
			walked = false
			break
		var spot: Vector3 = b.goal()
		spots.append(spot)
		walked = walked and b.walks() and b.frame(me).slow
		me.pos = spot
		b.frame(me)   # there: the goal is done with
		b.think(me, w)
		stood = stood and not b.has_goal() and not b.walks()
	var inside: bool = spots.size() == 6 and spots.all(func(v: Vector3) -> bool: return Vector2(v.x, v.z).length() <= skel.wander_m + 0.01)
	var ways: Dictionary[int, bool] = {}
	for v: Vector3 in spots:
		ways[int(floor((atan2(v.z, v.x) + PI) / (PI / 2.0))) % 4] = true
	_check(inside and walked and stood, "after each stand it walks (slow) to a spot within %.0f m of its point, then stands again: %s" % [skel.wander_m, str(spots)])
	_check(ways.size() >= 2, "its spots lie round its point, not one way (%d quarters of 4)" % ways.size())
	me.pos = Vector3(10, 0, 0)
	b.think(me, w)
	_check(b.has_goal() and b.goal().is_equal_approx(Vector3.ZERO) and not b.walks(),
		"10 m from its point (back from a fight): home first, at its own pace (%s)" % b.describe())
	me.pos = Vector3(skel.wander_m, 0, 0)
	b.think(me, w)
	_check(b.has_goal() and b.goal().is_equal_approx(Vector3.ZERO),
		"on its way home and inside its wander: it goes on home, all the way (%s)" % b.describe())
	me.pos = Vector3(0.5, 0, 0)
	b.think(me, w)
	_check(not b.has_goal() and not b.walks(), "home: it stands, then wanders again (%s)" % b.describe())
	var still: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 53)
	still.clock = func() -> int: return t[0]
	still.self_id = 8403
	var sw := _FoeWorld.new()
	var sme := MovementState.new()
	sw.states = {8403: sme}
	sw.kinds = {8403: 105}
	var sparring: FoeDef = FoeDef.by_kind(105)
	var moved: int = 0
	for i: int in 10:
		t[0] += stand_max + 1
		still.think(sme, sw)
		moved += 1 if still.has_goal() else 0
	_check(sparring != null and sparring.key == &"sparring_skeleton" and sparring.wander_m == 0.0 and moved == 0,
		"NEGATIVE: the tutorial's sparring skeleton (wander_m 0) stands at its point (%d walks in %d s)" % [moved, (stand_max + 1) * 10 / 1000])

	# WHO HIT IT (F11): Startled, it goes for the player the server names (the row's `by_entity`), not the nearest.
	var hit_by: Array[int] = [5]
	var hw := _FoeWorld.new()
	var hme := MovementState.new()
	var shooter := MovementState.new()
	shooter.pos = Vector3(0, 0, 14)   # behind it, past its hearing
	var bystander := MovementState.new()
	bystander.pos = Vector3(7, 0, 0)  # to its side, nearer, unseen and unheard
	hw.states = {8404: hme, 5: shooter, 6: bystander}
	hw.kinds = {8404: 103, 5: 0, 6: 0}
	var hb: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 54)
	hb.clock = func() -> int: return t[0]
	hb.self_id = 8404
	hb.set(&"status_by_of", func(_id: int) -> int: return hit_by[0])
	hb.think(hme, hw)
	var calm: bool = hb.target() == 0
	hw.statuses = {8404: 109}
	hb.think(hme, hw)
	_check(calm and hb.target() == 5 and hb.state == &"chase",
		"hit from behind by a player 14 m off, another 7 m off at its side: it turns on WHO HIT IT, not the nearest (%s)" % hb.describe())
	var nb: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 55)
	nb.clock = func() -> int: return t[0]
	nb.self_id = 8404
	nb.set(&"status_by_of", func(_id: int) -> int: return 0)
	nb.think(hme, hw)
	_check(nb.target() == 6, "NEGATIVE: with no word of who (an older server's row): the nearest within twice its leash, as before (%s)" % nb.describe())
	shooter.pos = Vector3(0, 0, skel.leash_m + 5.0)
	var fb: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 56)
	fb.clock = func() -> int: return t[0]
	fb.self_id = 8404
	fb.set(&"status_by_of", func(_id: int) -> int: return hit_by[0])
	fb.think(hme, hw)
	_check(fb.target() == 0, "NEGATIVE: who hit it is past its leash of home: it does not go, nor turns on the one near it (%s)" % fb.describe())


## THE SKELETON ARCHER (Luke's F1-F6, 2026-11-12, FOES_PREP.md section 6): the ranged tree. It walks in to its range,
## stands and shoots what it sees, naming its target (the server aims the shot); holds a draw it has begun; steps back
## from a target that is close, seldom; shoves one in its reach; and two archers never draw on one player together.
func _run_foe_archer() -> void:
	print("== regents: a foe that shoots ==")
	var foe: FoeDef = FoeDef.by_kind(108)
	_check(foe != null and foe.key == &"skeleton_archer" and foe.behavior == &"ranged" and foe.validate().is_empty(),
		"the skeleton archer is a foe of the ranged tree, and valid (%s)" % (str(foe.validate()) if foe != null else "none"))
	if foe == null:
		return
	var shot: AbilityDef = foe.shot()
	var spell: SpellDef = SpellDef.by_ability(shot.id) if shot != null else null
	_check(shot != null and spell != null and spell.kind == SpellDef.Kind.BOLT and shot.range_m == 0.0 and not shot.judged,
		"its shot is its kit's skill a bolt spell flies, with no range of its own and not judged")
	if shot == null or spell == null:
		return
	_check(shot.wind_up_ms == 1200 and foe.kit.lock_ms(shot) >= shot.wind_up_ms, "its tell is 1200 ms (%d), and it is held at least as long (%d)" % [shot.wind_up_ms, foe.kit.lock_ms(shot)])
	_check(not foe.kit.is_finisher(foe.kit.light[0]) and not KitDef.is_unblockable(foe.kit.light[0].id),
		"its lone shove is no finisher: it staggers nobody and may be blocked")
	for other: FoeDef in FoeDef.all():
		if other != foe and other.fights and other.key != &"imp":
			_check(other.shot() == null and other.ring() == null and other.behavior == &"melee", "%s does not shoot" % other.key)
	# NEGATIVE: the ranged tree with a kit that has no shot is refused.
	var no_shot: FoeDef = foe.duplicate() as FoeDef
	no_shot.kit = FoeDef.by_kind(103).kit
	_check(not no_shot.validate().filter(func(e: String) -> bool: return e.contains("no shot")).is_empty(),
		"NEGATIVE: a ranged foe whose kit has no shot is refused by its validate")

	var t: Array[int] = [200000]
	var brain: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 31)
	brain.clock = func() -> int: return t[0]
	brain.self_id = 7401
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	w.states = {7401: me, 7301: them}
	w.kinds = {7401: 108, 7301: 0}
	them.pos = Vector3(foe.notice_m + 4.0, 0, 0)
	me.yaw = _yaw_to(me.pos, them.pos)   # it faces the way they come from (F9: it sees in front)
	brain.think(me, w)
	_check(brain.state == &"idle" and brain.take_acts().is_empty(), "a player past its notice: it rests (%s)" % brain.describe())
	them.pos = Vector3(foe.shot_range_m + 1.0, 0, 0)
	brain.think(me, w)
	_check(brain.state == &"chase" and brain.target() == 7301 and brain.take_acts().is_empty(),
		"noticed, past its range: it walks in, and shoots nothing yet (%s)" % brain.describe())
	# Walking in, it stops a little inside its range, never at the edge.
	them.pos = Vector3(foe.shot_range_m - 0.5, 0, 0)
	brain.think(me, w)
	_check(brain.state == &"chase", "just inside its range it still walks in (%s)" % brain.describe())
	them.pos = Vector3(11.0, 0, 0)
	t[0] += 100
	brain.think(me, w)
	var acts: Array[Dictionary] = brain.take_acts()
	_check(brain.state == &"aim" and not brain.has_goal() and acts.size() == 1 and int(acts[0].get("ability", 0)) == shot.id,
		"in range and in sight: it stands and draws its shot (%s, %s)" % [brain.describe(), str(acts)])
	_check(acts.size() == 1 and int(acts[0].get("target", 0)) == 7301, "the shot NAMES ITS TARGET (the server aims at them): %s" % str(acts))
	var f: InputFrame = brain.frame(me)
	_check(f.face and absf(angle_difference(f.look_yaw, atan2(1.0, 0.0) + PI)) < 0.01, "it faces them as it draws")
	var drawn_at: int = t[0]
	# Mid-draw it stands, whatever they do: its opening.
	them.pos = Vector3(3.0, 0, 0)
	t[0] += 400
	brain.think(me, w)
	_check(brain.state == &"fight" and not brain.has_goal() and brain.take_acts().is_empty(),
		"mid-draw with them 3 m off: it stands and finishes the draw, no step back, no second shot (%s)" % brain.describe())
	# After the draw: they are close, so one step back, away from them, facing them.
	t[0] = drawn_at + foe.kit.lock_ms(shot) + 50
	brain.think(me, w)
	var spot: Vector3 = brain.goal()
	_check(brain.state == &"back" and brain.has_goal() and spot.is_equal_approx(Vector3(-foe.back_m, 0, 0)) and brain.take_acts().is_empty(),
		"the draw over and them within %.0f m: it steps back %.0f m straight away from them (%s, to %s)" % [foe.back_within_m, foe.back_m, brain.describe(), str(spot)])
	f = brain.frame(me)
	_check(f.face and not f.slow and f.move_dir.length() > 0.1, "it backs away at its own pace, facing them")
	me.pos = spot
	them.pos = spot + Vector3(3.0, 0, 0)   # they followed
	t[0] += 2500
	brain.think(me, w)
	brain.take_acts()
	# CAUGHT: it has stepped back once; within back_every_ms it does not again.
	t[0] += 200
	brain.think(me, w)
	_check(brain.state != &"back" and not brain.has_goal(),
		"followed at once: no second step back inside %d ms: it is caught (%s)" % [foe.back_every_ms, brain.describe()])
	# ... and in its reach, it shoves.
	var shoved: bool = false
	them.pos = me.pos + Vector3(1.5, 0, 0)
	for i: int in 60:
		t[0] += 100
		brain.think(me, w)
		for a: Dictionary in brain.take_acts():
			if int(a.get("ability", 0)) == foe.kit.light[0].id:
				shoved = true
		if shoved:
			break
	_check(shoved, "caught in its reach: it shoves (%s)" % brain.describe())
	# Past back_every_ms, they still close: it steps back again.
	them.pos = me.pos + Vector3(3.0, 0, 0)
	var backed: bool = false
	for i: int in 100:
		t[0] += 100
		brain.think(me, w)
		brain.take_acts()
		if brain.state == &"back":
			backed = true
			break
	_check(backed, "past %d ms it steps back again (%s)" % [foe.back_every_ms, brain.describe()])

	# NEGATIVE: it never shoots what it cannot see; it walks to where it last saw them.
	var blind: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 32)
	blind.clock = func() -> int: return t[0]
	blind.self_id = 7402
	var bme := MovementState.new()
	var bthem := MovementState.new()
	bthem.pos = Vector3(0, 0, 11.0)
	bme.yaw = _yaw_to(bme.pos, bthem.pos)
	var bw := _FoeWorld.new()
	bw.states = {7402: bme, 7302: bthem}
	bw.kinds = {7402: 108, 7302: 0}
	blind.think(bme, bw)
	_check(blind.take_acts().size() == 1, "(it draws on one it sees)")
	t[0] += foe.kit.lock_ms(shot) + foe.shot_rest_ms - 100
	blind.think(bme, bw)   # it sees them still, a moment before it is rested
	_check(blind.take_acts().is_empty(), "(not rested yet: no second shot)")
	t[0] += 200
	bw.sight = false
	var blind_shots: int = 0
	for i: int in 20:
		t[0] += 100
		blind.think(bme, bw)
		blind_shots += blind.take_acts().size()
	_check(blind_shots == 0 and blind.state == &"chase" and blind.goal().is_equal_approx(Vector3(0, 0, 11.0)),
		"NEGATIVE: rested, in range, but out of sight: no shot; it walks to where it last saw them (%s)" % blind.describe())

	# ONE SHOT AT A PLAYER AT A TIME (regents.ranged_tokens), and the rest between a foe's own shots.
	var tokens: int = int(HotRules.number(&"regents.ranged_tokens"))
	var pw := _FoeWorld.new()
	var prey := MovementState.new()
	pw.states = {7303: prey}
	pw.kinds = {7303: 0}
	var pair: Array[NpcBrain] = []
	for i: int in 2:
		var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 41 + i)
		b.clock = func() -> int: return t[0]
		b.self_id = 7411 + i
		var st := MovementState.new()
		st.pos = Vector3(11.0 if i == 0 else -11.0, 0, 0)
		st.yaw = _yaw_to(st.pos, prey.pos)
		pw.states[b.self_id] = st
		pw.kinds[b.self_id] = 108
		pair.append(b)
	var flight_ms: int = int(11.0 / spell.speed_mps * 1000.0)
	var draws: Array[Vector2i] = []   # (when, who)
	var end: int = t[0] + 30000
	while t[0] < end:
		for b: NpcBrain in pair:
			b.think(pw.states[b.self_id], pw)
			for a: Dictionary in b.take_acts():
				if int(a.get("ability", 0)) == shot.id:
					draws.append(Vector2i(t[0], b.self_id))
		t[0] += 100
	var overlaps: int = 0
	var own_gap_ok: bool = true
	var last_by: Dictionary[int, int] = {}
	for i: int in draws.size():
		if i > 0 and draws[i].x < draws[i - 1].x + shot.wind_up_ms + flight_ms:
			overlaps += 1
		if last_by.has(draws[i].y) and draws[i].x - last_by[draws[i].y] < foe.kit.lock_ms(shot) + foe.shot_rest_ms:
			own_gap_ok = false
		last_by[draws[i].y] = draws[i].x
	_check(tokens == 1 and draws.size() >= 8 and last_by.size() == 2 and overlaps == 0,
		"two archers on one player for 30 s: both shoot (%d draws), and never is a second drawn while the first is drawn or in the air (%d overlaps)" % [draws.size(), overlaps])
	_check(own_gap_ok, "no archer draws again sooner than its lock and its %d ms rest" % foe.shot_rest_ms)

	# ITS LOOK: the warrior's model with the sword hidden, the other colors, a bow in its hand.
	var model: Node3D = (foe.character.visual_scene as PackedScene).instantiate() as Node3D
	add_child(model)
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var look := FoeLook.new()
	look.dress(skel, foe)
	var sword: MeshInstance3D = skel.get_node_or_null(^"Skeleton_Sword") as MeshInstance3D
	var body: MeshInstance3D = skel.get_node_or_null(^"Skeleton_Body") as MeshInstance3D
	var worn: BaseMaterial3D = body.get_surface_override_material(0) as BaseMaterial3D if body != null else null
	_check(sword != null and not sword.visible and body != null and body.visible, "its sword is hidden, its body is not")
	_check(worn != null and worn.albedo_texture == foe.albedo and foe.albedo != null, "it wears the pack's second colors")
	_check(look.held != null and look.held.get_parent() is BoneAttachment3D and (look.held.get_parent() as BoneAttachment3D).bone_name == "hand_l",
		"a bow is in its left hand")
	var plain := FoeLook.new()
	var model2: Node3D = (FoeDef.by_kind(103).character.visual_scene as PackedScene).instantiate() as Node3D
	add_child(model2)
	var skel2: Skeleton3D = model2.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	plain.dress(skel2, FoeDef.by_kind(103))
	_check(plain.held == null and (skel2.get_node(^"Skeleton_Sword") as MeshInstance3D).visible
		and (skel2.get_node(^"Skeleton_Body") as MeshInstance3D).get_surface_override_material(0) == null,
		"NEGATIVE: the warrior keeps its sword, its own colors and an empty left hand")
	look.free()
	plain.free()
	model.queue_free()
	model2.queue_free()


## THE IMP CASTER (Luke's F1, 2026-11-12, FOES_PREP.md section 6): the ranged tree again, with a ring every third cast
## and no step back. Its bolt and its ring both name their target; the server flies the one and lays the other.
func _run_foe_imp() -> void:
	print("== regents: a foe that casts ==")
	var foe: FoeDef = FoeDef.by_kind(109)
	_check(foe != null and foe.key == &"imp" and foe.family == &"fiend" and foe.behavior == &"ranged" and foe.validate().is_empty(),
		"the imp is a fiend of the ranged tree, and valid (%s)" % (str(foe.validate()) if foe != null else "none"))
	if foe == null:
		return
	var bolt: AbilityDef = foe.shot()
	var ring: AbilityDef = foe.ring()
	_check(bolt != null and ring != null and bolt != ring and foe.ring_every == 3, "it has a bolt and a ring, the ring every third cast")
	if bolt == null or ring == null:
		return
	var ring_spell: SpellDef = SpellDef.by_ability(ring.id)
	_check(ring.range_m == 0.0 and not ring.judged and ring_spell.kind == SpellDef.Kind.AREA and ring_spell.status == null and ring_spell.delay_ms >= 1200,
		"its ring has no range of its own, no status (damage only), and %d ms to leave it" % ring_spell.delay_ms)
	_check(SpellDef.by_ability(bolt.id).speed_mps < SpellDef.by_ability(FoeDef.by_kind(108).shot().id).speed_mps, "its bolt is slower than the archer's arrow")
	_check(foe.cast_at(0) == bolt and foe.cast_at(1) == bolt and foe.cast_at(2) == ring and foe.cast_at(3) == bolt and foe.cast_at(5) == ring,
		"bolt, bolt, ring, bolt, bolt, ring")
	_check(FoeDef.by_kind(108).ring() == null and FoeDef.by_kind(108).cast_at(2) == FoeDef.by_kind(108).shot(), "NEGATIVE: the archer has no ring: every cast is its arrow")
	var no_ring: FoeDef = FoeDef.by_kind(108).duplicate() as FoeDef
	no_ring.ring_every = 3
	_check(not no_ring.validate().filter(func(e: String) -> bool: return e.contains("no ring")).is_empty(),
		"NEGATIVE: `ring_every` on a foe whose kit has no ring is refused by its validate")
	for a: AbilityDef in foe.kit.abilities():
		_check(foe.character.animation_set.has_exact(StringName("ability.%d" % a.id)), "it plays its %s" % a.display_name)
	var t: Array[int] = [400000]
	var brain: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 51)
	brain.clock = func() -> int: return t[0]
	brain.self_id = 7501
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	them.pos = Vector3(9.0, 0, 0)
	me.yaw = _yaw_to(me.pos, them.pos)
	w.states = {7501: me, 7305: them}
	w.kinds = {7501: 109, 7305: 0}
	var casts: Array[int] = []
	var named: bool = true
	var moved: bool = false
	var end: int = t[0] + 26000
	while t[0] < end:
		# They come close for a while: an imp never steps back.
		them.pos = Vector3(3.0 if (t[0] > 408000 and t[0] < 411000) else 9.0, 0, 0)
		brain.think(me, w)
		moved = moved or brain.state == &"back" or (brain.has_goal() and brain.state != &"chase")
		for a: Dictionary in brain.take_acts():
			casts.append(int(a.get("ability", 0)))
			named = named and int(a.get("target", 0)) == 7305
		t[0] += 100
	var want: Array[int] = []
	for i: int in casts.size():
		want.append(ring.id if i % 3 == 2 else bolt.id)
	_check(casts.size() >= 6 and casts == want and named, "9 m off for 26 s: bolt, bolt, ring, and again, each naming its target (%s)" % str(casts))
	_check(not moved, "NEGATIVE: with them 3 m off it does not step back (back_m 0): it stands and casts")
	# A foe's ring is drawn in a danger's color, a player's own in its blue.
	var looks := SpellLooks.new()
	add_child(looks)
	looks.show_area(1, Vector3.ZERO, 3.0, ClockSync.server_usec() + 1_000_000, false, true)
	looks.show_area(2, Vector3(10, 0, 0), 3.0, ClockSync.server_usec() + 1_000_000, false, false)
	# Since PROGRESS 82 the rings are the VFX lab's (`VfxGroundRing`): a foe's of fire, a player's own of frost.
	var foe_ring: VfxGroundRing = looks.ring_of(1)
	var own_ring: VfxGroundRing = looks.ring_of(2)
	_check(foe_ring != null and own_ring != null and foe_ring.element == VfxGroundRing.Element.FIRE and own_ring.element == VfxGroundRing.Element.FROST
		and foe_ring.color.r > 0.9 and foe_ring.color.b < 0.3 and own_ring.color.b > 0.9,
		"a foe's ring is drawn orange-red (fire), a player's own blue (frost)")
	_check(own_ring != null and is_equal_approx(own_ring.radius_m, 3.0) and own_ring.warn_s > 0.8 and own_ring.warn_s < 1.05,
		"a ring is the row's radius, and its warning runs until the row's landing (%.2f s)" % (own_ring.warn_s if own_ring != null else -1.0))
	looks.queue_free()


## A FOE'S STRING FOLLOWS ITS TARGET (Luke, 2026-11-11: "the wolves start their attack and dont stop even if I move far
## away from the first one (so second and 3rd attack just hit air instead of gap closing and then performing the 2nd and
## 3rd hits) and I suspect skeletons do that too"). After a swing of its string, a target out of reach is never swung
## at: the foe runs it down and the string goes on where it stopped; out of reach past `string_chase_ms`, the string is
## dropped, and the next is its first swing again. NEGATIVE: the brain before swung its second step at the air.
func _run_foe_string_chase(kind: int) -> void:
	var foe: FoeDef = FoeDef.by_kind(kind)
	print("== regents: a foe's string follows its target (%s) ==" % foe.key)
	var kit: KitDef = foe.kit
	var t: Array[int] = [700000]
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	var pid: int = 9300 + kind
	var fid: int = 9500 + kind
	them.pos = Vector3(foe.reach_m - 0.4, 0, 0)
	w.states = {fid: me, pid: them}
	w.kinds = {fid: kind, pid: 0}
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 40 + kind)
	b.clock = func() -> int: return t[0]
	b.self_id = fid
	b.think(me, w)
	var first: Array[int] = _abilities_used(b)
	var began: bool = b.state == &"fight" and first == [kit.light[0].id]
	# They step 6 m out: through the swing's lock it stands (it cannot move), then it runs after them; never a swing.
	them.pos = Vector3(foe.reach_m + 6.0, 0, 0)
	var lock: int = kit.lock_ms(kit.light[0])
	var at_air: Array[int] = []
	var ran: bool = false
	var until: int = t[0] + lock + 400
	while t[0] < until:
		t[0] += 100
		b.think(me, w)
		at_air.append_array(_abilities_used(b))
		ran = ran or (b.state == &"chase" and b.has_goal() and b.goal().is_equal_approx(them.pos))
	# It reaches them inside the string's time: the SECOND swing, at once.
	me.pos = them.pos - Vector3(foe.reach_m - 0.4, 0, 0)
	t[0] += 100
	b.think(me, w)
	var second: Array[int] = _abilities_used(b)
	var went_on: bool = b.state == &"fight" and second == [kit.light[1].id]
	# They step out again and stay out past `string_chase_ms`: the string is dropped, it still runs after them.
	them.pos = me.pos + Vector3(foe.reach_m + 6.0, 0, 0)
	var lock2: int = kit.lock_ms(kit.light[1])
	var at_air2: Array[int] = []
	until = t[0] + lock2 + foe.string_chase_ms + 300
	while t[0] < until:
		t[0] += 100
		b.think(me, w)
		at_air2.append_array(_abilities_used(b))
	var still_after: bool = b.state == &"chase" and b.target() == pid
	# Caught again: the string starts over (its first swing), once its rest is over.
	me.pos = them.pos - Vector3(foe.reach_m - 0.4, 0, 0)
	var next: Array[int] = []
	until = t[0] + foe.rest_ms + foe.rest_jitter_ms + 500
	while t[0] < until and next.is_empty():
		t[0] += 100
		b.think(me, w)
		next = _abilities_used(b)
	_check(began and at_air.is_empty() and ran and went_on and at_air2.is_empty() and still_after and next == [kit.light[0].id],
		"%s: its first swing in reach (%s); they step 6 m out: no swing at the air (%s), it runs after them (%s); caught inside %d ms, its SECOND swing (%s); out again past that, none at the air (%s), still chased (%s), and caught, its string starts over (%s, the first is %d)"
			% [foe.display_name, began, str(at_air), ran, foe.string_chase_ms, str(second), str(at_air2), still_after, str(next), kit.light[0].id])


## The abilities `b` asked to use since the last look, in order.
func _abilities_used(b: NpcBrain) -> Array[int]:
	var out: Array[int] = []
	for act: Dictionary in b.take_acts():
		if String(act.get("do", "")) == "ability":
			out.append(int(act["ability"]))
	return out


## A DEER GRAZES AND FLEES (hunting, 2026-11-09, HERBALISM_HUNTING_PREP.md §7 step 3): it wanders near home at a walk;
## a player seen within its sight, or heard close, or a hit from nowhere (the server's Startled) sends it galloping
## straight away from them, inside its leash; calm a while with nobody near, it walks home; slain, it lies still. Its
## flight is planned once per threat, not each think.
func _run_deer_brain() -> void:
	print("== regents: a deer grazes and flees ==")
	var deer: FoeDef = FoeDef.by_kind(106)
	var b: NpcBrain = NpcBrainComponent.make_brain(&"regents/deer", 3)
	var t: Array[int] = [500000]
	b.clock = func() -> int: return t[0]
	b.self_id = 8001
	var w := _FoeWorld.new()
	var me := MovementState.new()
	var them := MovementState.new()
	them.pos = Vector3(200, 0, 0)
	w.states = {8001: me, 1: them}
	w.kinds = {8001: 106, 1: 0}
	w.way = PackedVector3Array()
	b.think(me, w)
	var calm_first: bool = b.state == &"graze" and b.target() == 0 and b.walks()
	var wandered: bool = false
	for i: int in 40:
		t[0] += 1000
		b.think(me, w)
		if b.has_goal():
			wandered = Vector2(b.goal().x, b.goal().z).length() <= deer.graze_m + 0.01
			break
	_check(calm_first and wandered and b.walks(), "nobody near: it grazes, a few steps at a walk to a spot within %.0f m of home (%s)" % [deer.graze_m, str(b.goal())])
	# Seen 12 m off: it gallops straight away from them.
	them.pos = Vector3(12, 0, 0)
	var paths0: int = w.paths
	b.think(me, w)
	var away: bool = b.state == &"flee" and b.target() == 1 and b.goal().x < -deer.flee_m + 0.5 and absf(b.goal().z) < 0.5 and not b.walks()
	for i: int in 5:
		t[0] += 100
		b.think(me, w)
	_check(away and w.paths - paths0 == 1, "a player seen %.0f m off: it gallops %.0f m straight away (goal %s), planned once, not each think (%d)" % [
		12.0, deer.flee_m, str(b.goal()), w.paths - paths0])
	# Unseen, out of earshot: it calms after its while, walks home; unseen in earshot: it bolts.
	w.sight = false
	them.pos = Vector3(12, 0, 0)
	t[0] += deer.calm_ms + 100
	me.pos = Vector3(-20, 0, 0)
	b.think(me, w)
	var homing: bool = b.state == &"home" and b.goal().is_equal_approx(Vector3.ZERO) and b.walks()
	them.pos = Vector3(-20, 0, deer.startle_m - 1.0)
	b.think(me, w)
	var heard: bool = b.state == &"flee" and b.goal().z < -20.0
	_check(homing and heard, "calm %d ms with nobody seen: home at a walk (%s); then heard %.0f m off, unseen: it bolts away (%s)" % [
		deer.calm_ms, str(homing), deer.startle_m - 1.0, str(b.goal())])
	# Hit from nowhere (the server's Startled): it runs from the nearest player, 40 m off and unseen.
	var b2: NpcBrain = NpcBrainComponent.make_brain(&"regents/deer", 4)
	b2.clock = func() -> int: return t[0]
	b2.self_id = 8002
	var me2 := MovementState.new()
	me2.pos = Vector3(500, 0, 0)
	var archer := MovementState.new()
	archer.pos = Vector3(500, 0, 40)
	var w2 := _FoeWorld.new()
	w2.sight = false
	w2.states = {8002: me2, 2: archer}
	w2.kinds = {8002: 106, 2: 0}
	b2.think(me2, w2)
	var unbothered: bool = b2.state == &"graze"
	w2.statuses = {8002: 109}
	b2.think(me2, w2)
	_check(unbothered and b2.state == &"flee" and b2.target() == 2 and b2.goal().z < -10.0,
		"an archer 40 m off and unseen: it grazes on; shot (Startled), it runs from them (%s)" % str(b2.goal()))
	# Never past its leash: chased toward its range's edge, it runs along it.
	var b3: NpcBrain = NpcBrainComponent.make_brain(&"regents/deer", 5)
	b3.clock = func() -> int: return t[0]
	b3.self_id = 8003
	var me3 := MovementState.new()
	var w3 := _FoeWorld.new()
	var chaser := MovementState.new()
	w3.states = {8003: me3, 3: chaser}
	w3.kinds = {8003: 106, 3: 0}
	b3.think(me3, w3)   # home is where it stands
	me3.pos = Vector3(-(deer.leash_m - 5.0), 0, 0)
	chaser.pos = me3.pos + Vector3(8, 0, 0)
	b3.think(me3, w3)
	_check(b3.state == &"flee" and Vector2(b3.goal().x, b3.goal().z).length() <= deer.leash_m + 0.01,
		"near the edge of its %.0f m leash, chased outward: it runs no further than the edge (%s)" % [deer.leash_m, str(b3.goal())])
	# Slain: it lies still, scared of nobody.
	w3.statuses = {8003: 106}
	b3.think(me3, w3)
	_check(b3.state == &"slain" and not b3.has_goal() and b3.target() == 0, "slain: it lies still (%s)" % b3.describe())


## WOLVES HUNT AS A PACK (Luke, 2026-11-10, HERBALISM_HUNTING_PREP.md §7 step 5): alerting or hitting one calls other
## wolves within `pack_m` to join the chase, even when the player is past their own `notice_m`; one past `pack_m` stays
## at peace.
func _run_wolf_pack() -> void:
	print("== regents: wolves hunt as a pack ==")
	var wolf: FoeDef = FoeDef.by_kind(107)
	var t: Array[int] = [600000]
	var w := _FoeWorld.new()
	var p := MovementState.new()
	p.pos = Vector3(8.0, 0.0, 0.0)   # 8 m from wolf 1 (inside its 10 m notice), 12 m from wolf 2 (past its 10 m notice)
	var w1 := MovementState.new()
	w1.pos = Vector3.ZERO
	w1.yaw = _yaw_to(w1.pos, p.pos)   # wolf 1 faces them (F9); wolf 2 would not see them at 12 m either way
	var w2 := MovementState.new()
	w2.pos = Vector3(-4.0, 0.0, 0.0)
	var w3 := MovementState.new()
	w3.pos = Vector3(-20.0, 0.0, 0.0)   # 20 m from wolf 1: past its 15 m pack call
	w.states = {1: p, 8101: w1, 8102: w2, 8103: w3}
	w.kinds = {1: 0, 8101: 107, 8102: 107, 8103: 107}
	var b1: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 21)
	var b2: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 22)
	var b3: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 23)
	for pair: Array in [[b1, 8101], [b2, 8102], [b3, 8103]]:
		var b: NpcBrain = pair[0] as NpcBrain
		b.clock = func() -> int: return t[0]
		b.self_id = int(pair[1])
	b2.think(w2, w)
	var alone_idle: bool = b2.state == &"idle" and b2.target() == 0
	b1.think(w1, w)
	b2.think(w2, w)
	b3.think(w3, w)
	_check(alone_idle and b1.state == &"chase" and b1.target() == 1 and b2.state == &"chase" and b2.target() == 1
		and b3.state == &"idle" and b3.target() == 0,
		"a player 8 m from wolf 1 and 12 m from wolf 2 (past its %.0f m sight): wolf 1 calls wolf 2 (4 m off, within %.0f m); wolf 3 (20 m off) stays idle"
			% [wolf.notice_m, wolf.pack_m])
	# Shot from 16 m away (past notice_m): Startled turns the hit wolf on the archer, and its packmate joins in.
	var ws := _FoeWorld.new()
	var archer := MovementState.new()
	archer.pos = Vector3(16.0, 0.0, 0.0)
	var s1 := MovementState.new()
	var s2 := MovementState.new()
	s2.pos = Vector3(0.0, 0.0, 4.0)
	ws.states = {2: archer, 8201: s1, 8202: s2}
	ws.kinds = {2: 0, 8201: 107, 8202: 107}
	ws.statuses = {8201: 109}
	var sb1: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 24)
	var sb2: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 25)
	sb1.clock = func() -> int: return t[0]
	sb2.clock = func() -> int: return t[0]
	sb1.self_id = 8201
	sb2.self_id = 8202
	sb1.think(s1, ws)
	sb2.think(s2, ws)
	_check(sb1.target() == 2 and sb2.target() == 2 and sb1.state == &"chase" and sb2.state == &"chase",
		"shot from 16 m off (Startled): the wolf turns on the archer and calls its packmate 4 m away")
	# EVERY FOE (Luke, 2026-11-11: "Every foe", not pack foes only): a skeleton warrior, which has no pack. An archer
	# 16 m off, past its sight: it stands; Startled, it goes for them. One 30 m off (past its leash of home): it stays.
	var skel: FoeDef = FoeDef.by_kind(103)
	var wk := _FoeWorld.new()
	var bowman := MovementState.new()
	bowman.pos = Vector3(16.0, 0.0, 0.0)
	var k1 := MovementState.new()
	wk.states = {3: bowman, 8301: k1}
	wk.kinds = {3: 0, 8301: 103}
	var kb: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 26)
	kb.clock = func() -> int: return t[0]
	kb.self_id = 8301
	kb.think(k1, wk)
	var unbothered: bool = kb.state == &"idle" and kb.target() == 0
	wk.statuses = {8301: 109}
	kb.think(k1, wk)
	var turned: bool = kb.state == &"chase" and kb.target() == 3
	var wf := _FoeWorld.new()
	var far_bowman := MovementState.new()
	far_bowman.pos = Vector3(skel.leash_m + 5.0, 0.0, 0.0)
	var k2 := MovementState.new()
	wf.states = {4: far_bowman, 8302: k2}
	wf.kinds = {4: 0, 8302: 103}
	wf.statuses = {8302: 109}
	var kf: NpcBrain = NpcBrainComponent.make_brain(&"regents/foe", 27)
	kf.clock = func() -> int: return t[0]
	kf.self_id = 8302
	kf.think(k2, wf)
	_check(skel.pack_m == 0.0 and skel.notice_m < 16.0 and unbothered and turned and kf.target() == 0,
		"every foe, a skeleton warrior (no pack, sight %.0f m): an archer 16 m off leaves it standing (%s); Startled, it goes for them (%s); one %.0f m off, past its leash, it does not (%s)"
			% [skel.notice_m, unbothered, turned, skel.leash_m + 5.0, kf.target() == 0])


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
	_check(is_equal_approx(FoeWorkbench.hit_damage(11.0, 70, 0, 1), 7.7) and is_equal_approx(FoeWorkbench.hit_damage(10.0, 100, 1000, SkillDef.RANK_TOP), 10.0 * 1.2 * 1.27)
		and is_equal_approx(FoeWorkbench.hit_damage(10.0, 100, 0, 12), 10.928),
		"its damage rule is the server's: a chop at 70 %% is 7.7; quality and the top rank add a fifth and 27 %%; rank 12 9.28 %%")
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
	# HOW IT NOTICES (F9, F10), on every foe's sheet.
	_check(sheet.contains("sees 10 m 140 degrees in front, hears 4 m all round (8 m a sprint); at rest it wanders 3 m"),
		"the sheet says how it notices and rests: %s" % sheet)
	# A FOE THAT SHOOTS (FOES_PREP.md section 9 step 6): its round of casts, not its shove, is its fight.
	_check(FoeWorkbench.shot_rhythm(warrior).is_empty() and FoeWorkbench.fight_rhythm(warrior)["dps"] == r["dps"] and not sheet.contains("it shoots"),
		"NEGATIVE: a melee foe has no round of shots: its fight is its string")
	var archer: FoeDef = FoeDef.by_kind(108)
	bench.item = archer
	await get_tree().process_frame
	var asheet: String = await bench.run_named_test(&"sheet")
	var shot: AbilityDef = archer.shot()
	var arrow: float = FoeWorkbench.hit_damage(shot.damage, archer.damage_pct, 0, 1)
	var round_ms: int = archer.kit.lock_ms(shot) + archer.shot_rest_ms
	var ar: Dictionary = FoeWorkbench.shot_rhythm(archer)
	_check(bool(bench.last_measure["shooter"]) and int(bench.last_measure["casts"]) == 1 and int(ar["ms"]) == round_ms
		and is_equal_approx(float(ar["dps"]), arrow / (float(round_ms) / 1000.0)) and is_equal_approx(arrow, 16.5),
		"the archer's fight is its arrow (16.5) every %d ms (its lock and %d ms rest): %.2f a second" % [round_ms, archer.shot_rest_ms, float(ar["dps"])])
	_check(asheet.contains("it shoots from 9 to 14 m") and asheet.contains("steps back 5 m") and asheet.contains("up close: Shove"),
		"its sheet: its range, its step back, its shove up close: %s" % asheet)
	await bench.run_named_test(&"versus")
	_check(is_equal_approx(float(bench.last_measure["kills_player_s"]), 100.0 / float(ar["dps"])),
		"versus: it kills a player who stands for every arrow in %.0f s (its shots, not its shove)" % float(bench.last_measure["kills_player_s"]))
	_check(bench.fit_checks().is_empty(), "the archer fits: %s" % str(bench.fit_checks()))
	var imp: FoeDef = FoeDef.by_kind(109)
	var ir: Dictionary = FoeWorkbench.shot_rhythm(imp)
	var icasts: Array = ir["casts"]
	var ember: float = FoeWorkbench.hit_damage(imp.shot().damage, imp.damage_pct, 0, 1)
	var cinder: float = FoeWorkbench.hit_damage(imp.ring().damage, imp.damage_pct, 0, 1)
	_check(icasts.size() == imp.ring_every and icasts.size() == 3 and not bool(icasts[0]["ring"]) and not bool(icasts[1]["ring"]) and bool(icasts[2]["ring"])
		and is_equal_approx(float(ir["damage"]), 2.0 * ember + cinder),
		"the imp's round: ember, ember, ring (%.2f, %.2f, %.2f: %.2f a round)" % [ember, ember, cinder, float(ir["damage"])])
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
	_check(heads == ["Grips", "Axes", "Swords", "Pickaxes", "Trowels", "Knives", "Armor", "Other"], "the workbench's list: one line a recipe, under Grips, Axes, Swords, Pickaxes, Trowels, Knives, Armor (every piece, S3), Other, each once %s" % str(heads))
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
	_check(RegentsHud.string_names(sword, tank) == "Slash - Slash (second) - Pommel bash" and RegentsHud.string_names(sword, null) == "Slash - Slash (second) - Piercing thrust",
		"the key line names the string's moves, the last the handle's: %s" % RegentsHud.string_names(sword, tank))
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


## The least angle (degrees) the right hand is off straight ahead of the body (+Z, the rig's front), round the body,
## through the first `until_ms` of clip `sem` of `set` at its speed: how wide the blow is held before it comes.
func _least_hand_bearing(set: AnimationSet, sem: StringName, until_ms: int) -> float:
	var ref: AnimationClipRef = set.clip(sem)
	var anim: Animation = AnimationTreeBuilder.clip_animation(set, sem)
	if ref == null or anim == null:
		return -1.0
	var speed: float = ref.speed_scale if ref.speed_scale > 0.0 else 1.0
	var scene: Node3D = (load("res://game/characters/mannequin_f.glb") as PackedScene).instantiate() as Node3D
	var skel: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand: int = skel.find_bone("hand_r")
	var least: float = 180.0
	var t: float = 0.0
	while t <= minf(anim.length, float(until_ms) / 1000.0 * speed):
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
		least = minf(least, absf(rad_to_deg(atan2(p.x, p.z))))
		t += 1.0 / 240.0
	scene.free()
	return least


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
	_check(keys == [&"woodcutting", &"mining", &"smelting", &"smithing", &"crafting", &"swordsmanship", &"axemanship", &"archery", &"sorcery", &"herbalism", &"skinning"],
		"seven working skills (herbalism, 2026-11-07; skinning, 2026-11-09) and four weapon masteries: %s" % str(keys))
	var wc: SkillDef = SkillDef.by_key(&"woodcutting")
	# THE 1-33 TRACK (Luke's S1 + S2, 2026-11-13): the old ranks' XP lands on their new levels (2 -> 5, 4 -> 12, 10 -> 33).
	_check(wc.rank_of(0) == 1 and wc.rank_of(14) == 1 and wc.rank_of(15) == 2 and wc.rank_of(60) == 5 and wc.rank_of(280) == 12
		and wc.rank_of(2400) == SkillDef.RANK_TOP and wc.progress(100) == Vector2i(10, 30),
		"ranks come from the curve: rank 2 at 15 XP, 5 at 60 (the old 2), 12 at 280 (the old 4), 33 at 2400; 100 XP is 10 of rank 6's 30")
	var tops: bool = true
	for sd: SkillDef in SkillDef.all():
		tops = tops and sd.xp_to_rank.size() + 1 == SkillDef.RANK_TOP
	_check(tops, "every skill's curve ends at rank %d (the server's RANK_TOP)" % SkillDef.RANK_TOP)
	_check(SkillDef.mastery_bp(1) == 0 and SkillDef.mastery_bp(2) == 84 and SkillDef.mastery_bp(12) == 928 and SkillDef.mastery_bp(SkillDef.RANK_TOP) == 2700
		and SkillDef.mastery_bp(99) == 2700, "mastery's share: nothing at 1, 0.84 %% a rank, 27 %% at the top and never more (the server's mastery_bp)")
	var names: Array[String] = []
	for n: NodeDef in NodeDef.all_by_tier():
		names.append(n.display_name)
	_check(names == ["Tree", "Oak", "Yew", "Copper rock", "Iron rock", "Coal rock", "Flax", "Deer carcass", "Wolf carcass"],
		"nine nodes, by skill then tier (the deer's and the wolf's carcasses, skinning 2026-11-09/10): %s" % str(names))
	var carcass: NodeDef = NodeDef.all_by_tier()[7]
	_check(carcass.tool_tag == &"knife" and carcass.minigame is SkinParams and carcass.deplete_permille == 350 and carcass.yield_item.display_name == "Deer hide"
		and carcass.max_items == 4 and carcass.whole_round and absf(carcass.expected_items() - 2.347) < 0.001
		and carcass.skill == SkillDef.by_key(&"skinning") and carcass.validate().is_empty() and FoeDef.by_kind(106).carcass == carcass
		and carcass.models.size() == 1 and carcass.radii_cm()[0] > 30,
		"the deer's carcass: skinned with a knife (Skinning), the cut line its round, up to four hides (about %.2f AFK), skinned whole in a round, the deer's kill leaves it, a footprint of %d cm"
			% [carcass.expected_items(), carcass.radii_cm()[0]])
	var wolf_carcass: NodeDef = NodeDef.all_by_tier()[8]
	_check(wolf_carcass.tool_tag == &"knife" and wolf_carcass.tier == 2 and wolf_carcass.min_rank == 5 and wolf_carcass.minigame is SkinParams
		and wolf_carcass.yield_item.display_name == "Wolf pelt" and wolf_carcass.rare_item != null and wolf_carcass.rare_item.display_name == "Wolf fang"
		and wolf_carcass.rare_permille == 8 and wolf_carcass.max_items == 4 and wolf_carcass.whole_round
		and FoeDef.by_kind(107).carcass == wolf_carcass and wolf_carcass.models.size() == 1 and wolf_carcass.radii_cm()[0] > 30
		and SkinMinigame.node_of(wolf_carcass.minigame as SkinParams) == wolf_carcass,
		"the wolf's carcass: tier 2 at rank 5 (the old 2), gives Wolf pelt (up to 4, whole_round) and a rare Wolf fang (0.8 %%), its own stage model")
	var no_cap: NodeDef = carcass.duplicate() as NodeDef
	no_cap.max_items = 0
	var no_round: NodeDef = carcass.duplicate() as NodeDef
	no_round.minigame = null
	_check(no_cap.validate().any(func(m: String) -> bool: return m.contains("cap")) and not no_round.validate().is_empty(),
		"worked whole in a round with no cap, or no round, is refused")
	var flax: NodeDef = NodeDef.all_by_tier()[6]
	_check(flax.minigame is PullParams and (flax.minigame as PullParams).target_plants > 1 and flax.tool_tag == &"trowel"
		and flax.skill == SkillDef.by_key(&"herbalism") and flax.validate().is_empty(),
		"flax: herbalism's, pulled with a trowel; its round is pull the root, a clump (Luke, 2026-11-08: more than one stem for a full score), and valid")
	var afk_only: NodeDef = flax.duplicate() as NodeDef
	afk_only.minigame = null
	var wrong: NodeDef = flax.duplicate() as NodeDef
	wrong.minigame = BeatParams.new()
	_check(afk_only.validate().is_empty() and not wrong.validate().is_empty(),
		"a node may still have no round (AFK only); a station's round on a node is refused")
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
	_check(yew.min_tool_tier == 2 and yew.min_rank == 12, "a yew needs a tier 2 axe and woodcutting rank 12 (the old 4)")
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
	_check(RecipeDef.at(&"furnace").size() == 3 and RecipeDef.at(&"anvil").size() == 21 and RecipeDef.at(&"workbench").size() == 46
		and RecipeDef.at(&"spinning_wheel").size() == 1 and RecipeDef.at(&"tanning_rack").size() == 2 and RecipeDef.at(&"orders").is_empty(),
		"three recipes at the furnace (copper, iron, steel bars), twenty-one at the anvil (rivets, an axe head, a sword blade, a pickaxe head, a trowel blade, a knife blade and plates of each metal), forty-six at the workbench (three handles and six sword hilts; an axe, a sword, a pickaxe, a trowel and a knife of each metal; the yew bow's stave and its stringing, arrow shafts, copper arrows, the yew staff; seventeen pieces of armor, S3), one at the spinning wheel (the bowstring), two at the tanning rack (soft and supple leather), none at the order board")
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
	_check(keys == [&"copper", &"iron", &"plain_wood", &"oak", &"yew", &"steel", &"soft_leather", &"supple_leather", &"linen"]
		and pkeys == [&"bar", &"axe_head", &"sword_blade", &"handle", &"axe", &"sword", &"pickaxe_head", &"pickaxe", &"rivets", &"crossguard_hilt", &"banner_hilt",
			&"trowel_blade", &"trowel", &"knife_blade", &"knife", &"plates", &"armet", &"cuirass", &"legplates", &"hood", &"jerkin",
			&"leather_trousers", &"robe", &"cloth_trousers"],
		"nine materials (two leathers and linen for armor, S3) and twenty-four patterns (the sword's two hilts, COMBAT_OVERHAUL.md §5; herbalism's trowel, 2026-11-07; skinning's knife, 2026-11-09; armor's plates and pieces, S3): %s x %s" % [str(keys), str(pkeys)])
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
	_check(got.size() == 65 and kept and not got.values().has(-1) and got.get("copper:trowel", -1) == 40051 and got.get("copper:knife", -1) == 40059,
		"65 cells (three metals in sixteen patterns, three woods in three, two leathers in three, linen in two), every one made (the copper trowel 40051 and knife 40059, the starter's); the items players hold are the cells they were, ids pinned (the starters 40001 and 40006 now copper's): %s" % str(got))
	var problems: Array[String] = MaterialTable.problems()
	_check(problems.is_empty(), "the table is current: every cell and recipe as the table makes it%s" % ("" if problems.is_empty() else ": " + "; ".join(problems)))
	var dry: Dictionary = MaterialTable.generate(false)
	_check((dry["made"] as Array).is_empty() and (dry["updated"] as Array).is_empty() and (dry["errors"] as Array).is_empty(),
		"making it again would change nothing: %s" % str(dry["lines"]))
	_run_armor_cells()
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
	# Iron's armor follows its tier too (S3: a piece's Defense is its share x its material's tier).
	var armor_says: Array[String] = tier_says.filter(func(p: String) -> bool: return p.contains("defense: has"))
	_check(armor_says.size() == 3 and armor_says.any(func(p: String) -> bool: return p.begins_with("iron_cuirass.tres") and p.contains("defense: has 10, makes 15")),
		"and iron's three pieces of armor, their Defense its share x the new tier: %s" % str(armor_says))
	tier_says = tier_says.filter(func(p: String) -> bool: return not p.contains("defense: has"))
	_check(tier_says.size() == 4 and tier_says.all(func(p: String) -> bool: return p.contains("tool_tier: has 2, makes 3"))
		and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_axe.tres")) and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_pickaxe.tres"))
		and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_trowel.tres")) and tier_says.any(func(p: String) -> bool: return p.begins_with("iron_knife.tres")),
		"iron moved to tier 3: its axe's, pickaxe's, trowel's and knife's tool tiers are out of date (a sword's and a head's have none): %s" % str(tier_says))
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
	_check(steel_head.from_table and steel_head.inputs[0] == steel_bar and steel_head.min_rank == 8, "the table's steel axe head takes that bar (at smithing rank 8, the old 3)")
	steel_bar.by_hand = false
	_check(MaterialTable.problems(steel).any(func(p: String) -> bool: return p.contains("Steel has no raw form")),
		"unticked, the steel bar would be the table's, which cannot make it from no ore: said")
	steel_bar.by_hand = true
	var coal_rock: NodeDef = NodeDef.by_id(40006)
	_check(coal_rock.display_name == "Coal rock" and coal_rock.tier == 3 and coal_rock.min_tool_tier == 2 and coal_rock.min_rank == 8
		and coal_rock.yield_item == ItemDef.by_id(40024) and ItemDef.by_id(40024).display_name == "Coal",
		"the coal rock: mining tier 3, an iron pick (tier 2) and mining rank 8 (the old 3), yielding coal")
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
## ARMOR'S PIECES (S3, ARMOR_PREP.md A7, GAME.md W1): every armor cell is its pattern's slot and its pattern's share x its
## material's tier (the shares and the leathers' and linen's tiers are PLACEHOLDERS); what a look (W2) reads from an item id:
## its slot, its material's FAMILY (metal, hide, fiber) and its material (the tier's palette); cloth has no head.
func _run_armor_cells() -> void:
	var pieces: Array[String] = []
	var off: Array[String] = []
	for c: Dictionary in MaterialTable.plan():
		var m: MaterialDef = c["material"]
		var p: PatternDef = c["pattern"]
		if p.armor_slot == &"":
			continue
		var it: ItemDef = MaterialTable.cell(m, p)
		pieces.append(it.display_name)
		if it.armor_slot != p.armor_slot or it.defense != p.defense_share * m.tier or it.max_stack != 1:
			off.append("%s: %s %d (want %s %d x %d)" % [it.display_name, it.armor_slot, it.defense, p.armor_slot, p.defense_share, m.tier])
	_check(pieces.size() == 17 and off.is_empty(), "17 pieces, each worn in its pattern's slot at its share x its material's tier%s" % ("" if off.is_empty() else ": " + "; ".join(off)))
	var linen: MaterialDef = MaterialDef.by_key(&"linen")
	var pattern := func(key: StringName) -> PatternDef:
		for pd: PatternDef in MaterialTable.patterns():
			if pd.key == key:
				return pd
		return null
	_check(MaterialTable.cell(linen, pattern.call(&"armet")) == null and MaterialTable.cell(linen, pattern.call(&"hood")) == null
		and not MaterialTable.plan().any(func(c: Dictionary) -> bool: return (c["material"] as MaterialDef).family == MaterialDef.Family.FIBER and (c["pattern"] as PatternDef).armor_slot == &"head"),
		"NEGATIVE: cloth has no headwear (W1: hair shows until a hat exists)")
	# W2's lookup from a `worn` column's item id, content only.
	var look := func(name: String) -> String:
		var it: ItemDef = null
		for d: ContentDef in ContentLibrary.items(&"item"):
			if d.display_name == name:
				it = d as ItemDef
		if it == null or it.material == null:
			return "-"
		return "%s %s %s" % [it.armor_slot, MaterialDef.Family.keys()[it.material.family], it.material.key]
	_check(look.call("Steel cuirass") == "chest METAL steel" and look.call("Supple leather hood") == "head HIDE supple_leather"
		and look.call("Linen trousers") == "legs FIBER linen",
		"a look finds a piece's slot, family and material from its item: %s, %s, %s" % [look.call("Steel cuirass"), look.call("Supple leather hood"), look.call("Linen trousers")])
	var traits: Array[String] = []
	for c: Dictionary in MaterialTable.plan():
		var it: ItemDef = MaterialTable.cell(c["material"], c["pattern"])
		if it.armor_slot != &"" and (it.handle_trait != null or it.part_weapon_trait != null):
			traits.append(it.display_name)
	_check(traits.is_empty(), "NEGATIVE: no armor piece carries a trait (armor traits are Luke's): %s" % str(traits))


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
	var pull: Array = _golden_cases("pull")
	for c: Dictionary in pull:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: PullParams = _params_from(PullParams.new(), c["params"]) as PullParams
		var pm: PullModel = PullModel.start(seed_value, p)
		var start_ok: bool = pm.snag_depth == _flat([c["snag_depth"]]) and pm.snag_jump == _flat([c["snag_jump"]]) \
			and pm.snag_side == _flat([c["snag_side"]])
		var got: Dictionary = PullModel.play(seed_value, p, _flat(c["inputs"]))
		if not start_ok or got != _ints(c["expected"]):
			bad.append("pull %s: %s, wanted %s (catches %s)" % [c["name"], str(got), str(c["expected"]), start_ok])
	_check(pull.size() >= 10, "pull the root's golden rounds are there (%d)" % pull.size())
	var skin: Array = _golden_cases("skin")
	for c: Dictionary in skin:
		var seed_value: int = (int(c["seed_hi"]) << 32) | int(c["seed_lo"])
		var p: SkinParams = _params_from(SkinParams.new(), c["params"]) as SkinParams
		var sm: SkinModel = SkinModel.start(seed_value, p)
		var start_ok: bool = sm.px == _flat([c["line_x"]]) and sm.py == _flat([c["line_y"]])
		var got: Dictionary = SkinModel.play(seed_value, p, _flat(c["inputs"]))
		if not start_ok or got != _ints(c["expected"]):
			bad.append("skin %s: %s, wanted %s (first line %s)" % [c["name"], str(got), str(c["expected"]), start_ok])
	_check(skin.size() >= 10, "the cut line's golden rounds are there (%d)" % skin.size())
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
	# part; and the bands' rules are where he put them. Luke's play, 2026-11-09: the quench is off on every part; the
	# pattern fades once lifted, copper 3 s to a faint ghost, iron 1.5 s to a fainter one, steel 3 s to nothing; the
	# trowel blades (made by the table from the copper pattern) carry their metal's band too.
	var skilled: SimPlayer = SimPlayer.presets()[1]
	var ladder: Array[String] = []
	for part: String in ["axe head", "sword blade", "pickaxe head", "trowel blade"]:
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
			rules_ok = rules_ok and (rr.lay_cost_pm > 0) == (band >= 2) and (rr.red_ms > 0) == (band == 3) and rr.quench_hi_pm == 0
			rules_ok = rules_ok and [rr.pattern_fade_ms, rr.pattern_ghost_pm] == [[3000, 250], [1500, 120], [3000, 0]][band - 1]
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
	# Lifted, the outline FADES (Luke's play, 2026-11-09; iron: 1.5 s to 120 per mille, and stays that faint).
	var fresh_alpha: float = shape.outline_alpha()
	shape._started_usec -= 800 * 1000
	var mid_alpha: float = shape.outline_alpha()
	shape._started_usec -= 2000 * 1000
	var ghost_alpha: float = shape.outline_alpha()
	var fades: bool = fresh_alpha > 0.95 and mid_alpha < fresh_alpha and mid_alpha > ghost_alpha and absf(ghost_alpha - 0.12) < 0.001
	shape.toggle_template()
	var relaid: bool = shape.model.laid and shape.model.lays == 1 and shape.model.ceiling_pm() == 1000 - head.lay_cost_pm
	shape.toggle_template()
	shape.set_down()
	await get_tree().process_frame
	_check(lifted and fades and relaid and shape.state == SkillMinigame.State.DONE and shape.live_result == shape.replayed_result
		and int(shape.live_result["lays"]) == 1 and not shape.shows_clock(),
		"Space lifts the pattern (its outline fading %.2f, %.2f, %.2f) and lays it on again (iron: %d off the best it can be); setting it down ends the round, the replay agrees" % [
			fresh_alpha, mid_alpha, ghost_alpha, head.lay_cost_pm])
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
	# Luke's play, 2026-11-09: a TAP of Enter no longer sets it down (it says to hold); Enter HELD does.
	var enter_up: InputEventKey = InputEventKey.new()
	enter_up.keycode = KEY_ENTER
	enter_up.pressed = false
	carve._unhandled_key_input(enter)
	carve._unhandled_key_input(enter_up)
	carve._process(0.0)
	var tap_kept: bool = cm.done_ms < 0 and carve.state == SkillMinigame.State.PLAYING and carve.finish_hold() == 0.0
	carve._unhandled_key_input(enter)
	carve._process(0.0)
	var not_yet: bool = cm.done_ms < 0 and carve._finish_down_ms >= 0 and carve.finish_hold() < 1.0
	carve._finish_down_ms -= SkillMinigame.FINISH_HOLD_MS   # held the whole hold
	carve._process(0.0)
	var set_down: bool = tap_kept and not_yet and cm.done_ms >= 0 and carve.is_over()
	carve.finish()
	_check(bow_r.quality == RecipeDef.Quality.FROM_ROUND and cstage != null and _no_character(cstage) and carve.title().begins_with("Carving")
		and lifted and placed and deep_left and fine_right and asym and set_down and carve.live_result == carve.replayed_result,
		"carving the yew bow: a stave on the bench (%s); a click lifts the pattern (%s); left of a row's middle cuts its left edge deep (%s), right of it a fine shave off the right (%s); its back and belly differ (%s); a tap of Enter is kept, Enter held sets it down (%s); the replay agrees"
			% [cstage != null, lifted, deep_left, fine_right, asym, set_down])
	carve.queue_free()
	# HERBALISM (pull the root, PROGRESS 51; redrawn after Luke's play, 2026-11-08): a clump of flax in its mound, the
	# trowel alone (no character); A digs the left side (the mound's half sinks, its furrow opens), D the right; Space
	# held pulls (the stem rises, its short root showing); the soil cracks on a side root's side (its tip out, no
	# shaking) and a stroke there cuts it; held on, it snaps and the next stem comes forward; the round ends at its
	# time; the replay agrees.
	# (Its soil all packed here, so A has a side to dig: flax's loose sides, Luke's 2026-11-09, are checked after.)
	var flax_own: PullParams = NodeDef.all_by_tier()[6].minigame as PullParams
	var flax_round: PullParams = flax_own.duplicate() as PullParams
	flax_round.loose_pm = 0
	var pull: PullMinigame = SkillMinigames.make_ui(flax_round) as PullMinigame
	holder.add_child(pull)
	pull.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pull.begin(5, flax_round)
	await get_tree().process_frame
	var pstage: PullStage = pull.get_child(0) as PullStage
	var pm: PullModel = pull.model
	var a_key: InputEventKey = InputEventKey.new()
	a_key.physical_keycode = KEY_A
	a_key.pressed = true
	pull._started_usec = Time.get_ticks_usec() - 10 * 1000
	pull._unhandled_key_input(a_key)
	var mound_y: float = pstage._mound_left.scale.y
	for _f: int in 20:
		pstage._process(0.05)
	var dug_left: bool = pm.pack_left == 1000 - flax_round.dig_pm and pstage._soil_left.emitting and pstage._mound_left.scale.y < mound_y \
		and pstage._furrow_left.visible and not pstage._furrow_right.visible
	for at: Array in [[300, PullModel.LEFT], [600, PullModel.RIGHT], [900, PullModel.RIGHT]]:
		pull.press_at(at[0], at[1])
	var space: InputEventKey = InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	pull._started_usec = Time.get_ticks_usec() - 1200 * 1000
	pull._unhandled_key_input(space)
	var cracked: bool = false
	var tip_shown: bool = false
	var cut_ok: bool = false
	var rising: bool = false
	var at_ms: int = 1200
	while pm.cut == 0 and at_ms < 6000:
		at_ms += 50
		pm.advance_to(at_ms)
		pull._follow(at_ms)
		pstage._process(0.05)
		var side: int = pm.showing()
		if side != 0:
			cracked = (pstage._crack_left.visible if side == PullModel.LEFT else pstage._crack_right.visible) \
				and not (pstage._crack_right.visible if side == PullModel.LEFT else pstage._crack_left.visible)
			tip_shown = (pstage._crack_left if side == PullModel.LEFT else pstage._crack_right).get_node(^"Tip").scale.x > 0.1
			rising = pm.down and pm.up_by > 0 and pstage._held and pstage._up_by > 0.0 and pstage._plant.position.y > pstage._home.y
			cut_ok = cracked and pull.press_at(at_ms, side) == PullModel.CUT and pull._word == "Cut!" and is_instance_valid(pstage._cut_tip)
	# Held on until it snaps (side roots pulled through, the strain past the top), the stage told every tick.
	while pm.snapped == 0 and at_ms < flax_round.duration_ms:
		at_ms += 50
		pm.advance_to(at_ms)
		pull._follow(at_ms)
	var flew: bool = pstage._flying and pull._word == "Snapped!"
	var next_stem: bool = pm.plant == 1 and pm.up_by == 0 and pm.pack_left == 1000 and pull.state == SkillMinigame.State.PLAYING
	pull._started_usec = Time.get_ticks_usec() - (flax_round.duration_ms + 10) * 1000
	pull._process(0.016)   # its time run out: it finishes
	_check(pstage != null and _no_character(pstage) and pull.title().begins_with("Pulling") and dug_left and cracked and tip_shown
		and cut_ok and rising and flew and next_stem and pull.state == SkillMinigame.State.DONE and pull.live_result == pull.replayed_result,
		"pulling flax: A digs the left (the mound sinks, its furrow opens: %s); held, the stem rises with its root (%s); the soil cracks on the side root's side, its tip out (%s, %s), a stroke there cuts it (%s); held on it snaps (%s), the next stem comes forward packed (%s); the round ends at its time; the replay agrees"
			% [dug_left, rising, cracked, tip_shown, cut_ok, flew, next_stem])
	# LOOSE OR PACKED (Luke, 2026-11-09, "cutaway, no chore"): flax's stems start with some sides loose, from the soil's
	# own stream (the side roots the same as with none); a loose side is drawn dug.
	var loose_sides: int = 0
	var packed_sides: int = 0
	var same_roots: bool = true
	var loose_seed: int = -1
	for sd: int in range(1, 41):
		var lm: PullModel = PullModel.start(sd, flax_own)
		var pm0: PullModel = PullModel.start(sd, flax_round)
		loose_sides += int(lm.pack_left == 0) + int(lm.pack_right == 0)
		packed_sides += int(lm.pack_left == 1000) + int(lm.pack_right == 1000)
		same_roots = same_roots and lm.snag_depth == pm0.snag_depth and lm.snag_side == pm0.snag_side
		if loose_seed < 0 and lm.pack_left == 0 and lm.pack_right == 1000:
			loose_seed = sd
	pull.begin(loose_seed, flax_own)
	await get_tree().process_frame
	pull._follow(0)
	for _f: int in 20:
		pstage._process(0.05)
	var loose_drawn: bool = pstage._furrow_left.visible and not pstage._furrow_right.visible
	_check(flax_own.loose_pm > 0 and loose_sides > 20 and packed_sides > 20 and same_roots and loose_seed > 0 and loose_drawn,
		"flax: of 80 sides %d start loose, %d packed; the side roots the same as with all packed (%s); a loose left side drawn dug, the packed right not (%s)"
			% [loose_sides, packed_sides, same_roots, loose_drawn])
	pull.queue_free()
	# SKINNING (the cut line, 2026-11-10): the carcass on its stage, the knife floating; the mouse pressed on the line's
	# start and dragged along it cuts; off it a red rip; a line cut through lifts the knife (let go, then press again);
	# the hide's points and the panel's agree both ways; the replay agrees.
	var skin_p: SkinParams = NodeDef.all_by_tier()[7].minigame as SkinParams
	var skin: SkinMinigame = SkillMinigames.make_ui(skin_p) as SkinMinigame
	holder.add_child(skin)
	skin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skin.begin(7, skin_p)
	await get_tree().process_frame
	var sstage: SkinStage = skin.get_child(0) as SkinStage
	skin.set_process(false)   # the test drives the clock
	var sm: SkinModel = skin.model
	var start: Vector2i = sm.tip()
	var on_panel: Vector2 = skin.hide_to_panel(start.x, start.y)
	var back: Vector2i = skin.panel_to_hide(on_panel)
	var round_trip: bool = absi(back.x - start.x) <= 2 and absi(back.y - start.y) <= 2 and Rect2(Vector2.ZERO, skin.size).has_point(on_panel)
	skin._mouse = on_panel
	skin.button(true)
	var pressed: bool = sm.down and skin.inputs.size() == 3
	var st: int = 0
	var cut_some: bool = false
	var ripped: bool = false
	while st < 6000 and sm.line == 0:
		st += 50
		sm.advance_to(st)
		skin._follow(st)
		cut_some = cut_some or sm.f > 0 or sm.seg > 0
		ripped = ripped or not skin._rips.is_empty()
		var aim: Vector2 = sm.ahead(float(skin_p.cut_speed))
		var skew: float = 90.0 if st >= 600 and st < 700 else 0.0
		skin._mouse = skin.hide_to_panel(aim.x, aim.y + skew)
		skin._drag(st)
	var waits: bool = skin._wait_release and not sm.down
	sstage.knife(skin._mouse, true, true)
	var knife_seen: bool = sstage._knife != null and sstage._knife.visible
	skin.button(false)
	var released: bool = not skin._wait_release and not skin._held
	skin._end_model()
	var skin_r: Dictionary = skin.model.result()
	var skin_replay: Dictionary = SkillMinigames.play(7, skin_p, skin.inputs)
	_check(sstage != null and sstage.shown_carcass() != null and sstage.shown_carcass().find_children("*", "Skeleton3D", true, false).size() == 1 and round_trip and pressed and cut_some and ripped
		and sm.lines == 1 and sm.torn > 0 and waits and released and knife_seen and skin_r == skin_replay and skin.inputs.size() / 3 <= skin.max_inputs(),
		"skinning: the carcass on its stage (its one skeleton the carcass's), the knife floating; the hide and the panel agree (%s); pressed on the start (%s), dragged it cuts (%s), off the line a rip (%s, %d torn), a line cut through lifts the knife until the button is let go (%s, %s); the replay agrees (%s)"
			% [round_trip, pressed, cut_some, ripped, sm.torn, waits, released, str(skin_r)])
	skin.queue_free()
	await _run_skin_line_end(holder, skin_p)
	await _run_skin_stage_carcasses()
	holder.queue_free()
	await get_tree().process_frame


## A LINE'S END, THE BUTTON STILL HELD AND THE HAND STILL MOVING (Luke, 2026-11-11: "at the end of a line you almost
## always result in a tear because the line finishes while you are holding left click"): the knife lifts itself and
## stays out until the button is let go and pressed again; nothing is sent meanwhile, nothing tears, the next press
## cuts, and the replay agrees. NEGATIVE: a place sent before the model has run (the old order) presses the knife down
## again on the next line, where it tears.
func _run_skin_line_end(holder: Control, skin_p: SkinParams) -> void:
	var skin: SkinMinigame = SkillMinigames.make_ui(skin_p) as SkinMinigame
	holder.add_child(skin)
	skin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skin.begin(7, skin_p)
	await get_tree().process_frame
	skin.set_process(false)   # the test drives the clock
	var sm: SkinModel = skin.model
	var start: Vector2i = sm.tip()
	skin._mouse = skin.hide_to_panel(start.x, start.y)
	skin.button(true)
	# A hand that never rests: every look its place is a little different, so every look it has something to send.
	var st: int = maxi(0, sm.last_t_ms)
	while st < 8000 and sm.line == 0:
		st += 50
		var aim: Vector2 = sm.ahead(float(skin_p.cut_speed))
		skin._mouse = skin.hide_to_panel(aim.x + float((st / 50) % 3) - 1.0, aim.y)
		skin._look(st)
	var sent_at_end: int = skin.inputs.size()
	var lifted_itself: bool = sm.line == 1 and not sm.down and skin._wait_release and skin._held
	# Still held, still moving, for a second: off toward where the next line starts.
	var next_start: Vector2i = sm.tip()
	for k: int in 20:
		st += 50
		skin._mouse = skin._mouse.lerp(skin.hide_to_panel(next_start.x, next_start.y), 0.2) + Vector2(float(k % 2), 0.0)
		skin._look(st)
	var held_harmless: bool = sm.torn == 0 and not sm.down and skin.inputs.size() == sent_at_end
	skin.button(false)
	var let_go_sends_nothing: bool = skin.inputs.size() == sent_at_end and not skin._wait_release
	# Pressed again on the next line's start: it cuts. (The press is stamped by the minigame's own clock, behind the
	# test's: the model takes it as now.)
	skin._mouse = skin.hide_to_panel(next_start.x, next_start.y)
	var again: int = skin.press_at(st + 100, next_start.x, next_start.y)
	skin._held = true
	var pressed_again: bool = again == SkinModel.PRESSED and sm.down and sm.torn == 0
	st += 100
	for k: int in 6:
		st += 50
		var aim2: Vector2 = sm.ahead(float(skin_p.cut_speed))
		skin._mouse = skin.hide_to_panel(aim2.x, aim2.y)
		skin._look(st)
	var cuts_next: bool = sm.torn == 0 and (sm.f > 0 or sm.seg > 0)
	skin._end_model()
	var agree: bool = skin.model.result() == SkillMinigames.play(7, skin_p, skin.inputs)
	# NEGATIVE: the model's own trap, which the old order walked into: an input that runs the line's last tick itself.
	var trap: SkinModel = SkinModel.start(7, skin_p)
	var tp: Vector2i = trap.tip()
	trap.press(0, tp.x, tp.y)
	var tt: int = 0
	while tt < 8000 and trap.line == 0:
		tt += 50
		var ta: Vector2 = trap.ahead(float(skin_p.cut_speed))
		trap.press(tt, clampi(roundi(ta.x), 0, 1000), clampi(roundi(ta.y), 0, 1000))   # no look first: this runs the tick
	var far: bool = Vector2(trap.kx, trap.ky).distance_to(Vector2(trap.tip())) > float(skin_p.reach)
	trap.advance_to(tt + 500)
	var trapped: bool = trap.line == 1 and trap.down and (trap.torn >= 9 or not far)
	_check(lifted_itself and held_harmless and let_go_sends_nothing and pressed_again and cuts_next and agree and trapped,
		"skinning, a line's end with the button held and the hand moving: the knife lifts itself (%s), a second held on sends and tears nothing (%s, %d torn), letting go sends nothing (%s), the next press cuts (%s, %s), the replay agrees (%s); NEGATIVE, a place sent before the look presses it down again on the next line (%s: %d torn in half a second)"
			% [lifted_itself, held_harmless, sm.torn, let_go_sends_nothing, pressed_again, cuts_next, agree, trapped, trap.torn])
	skin.queue_free()


## EVERY CARCASS IS PLACED ON THE SKINNING STAGE (Luke, 2026-11-11: the wolf's round showed bare grass): each node
## with a cut line round has its own round name (the stage finds its carcass by it) and its model placed under the
## stage's `Carcasses`; its round shows that one alone, its torso under the cut. NEGATIVE: a model not placed is not
## there.
func _run_skin_stage_carcasses() -> void:
	var stage: SkinStage = (load("res://game/regents/skilling/skinning/skin_stage.tscn") as PackedScene).instantiate() as SkinStage
	add_child(stage)
	await get_tree().process_frame   # each carcass held in its pose
	await get_tree().process_frame
	var holder3d: Node3D = stage.get_node(^"Viewport/Stage/Carcasses") as Node3D
	var mid: Vector3 = (stage.get_node(^"Viewport/Stage/HideLeft") as Node3D).position.lerp((stage.get_node(^"Viewport/Stage/HideRight") as Node3D).position, 0.5)
	var names: Array[String] = []
	var said: PackedStringArray = PackedStringArray()
	var ok: bool = true
	for n: NodeDef in NodeDef.all_by_tier():
		var sp: SkinParams = n.minigame as SkinParams
		if sp == null:
			continue
		var own_name: bool = not names.has(sp.display_name) and SkinMinigame.node_of(sp) == n
		names.append(sp.display_name)
		var placed: bool = stage.has_carcass(n)
		stage.set_carcass(n)
		var shown: Node3D = stage.shown_carcass()
		var seen: int = 0
		for c: Node in holder3d.get_children():
			seen += int((c as Node3D).visible)
		var alone: bool = shown != null and shown.scene_file_path == n.models[0].resource_path and seen == 1
		# Its flank under the cut: the middle of its torso bones within 0.25 m of the middle of the two markers, from above.
		var off_m: float = 99.0
		if shown != null:
			var sk: Skeleton3D = shown.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var sum: Vector3 = Vector3.ZERO
			var count: int = 0
			for b: int in sk.get_bone_count():
				if sk.get_bone_name(b).begins_with("Torso"):
					sum += holder3d.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(b).origin)
					count += 1
			if count > 0:
				var torso: Vector3 = sum / float(count)
				off_m = Vector2(torso.x - mid.x, torso.z - mid.z).length()
		said.append("%s %.2f m" % [sp.display_name, off_m])
		ok = ok and own_name and placed and alone and off_m < 0.25
	var stray: NodeDef = NodeDef.new()
	stray.display_name = "Stray"
	var stray_models: Array[PackedScene] = [load("res://game/regents/art/nature/Rock_Medium_1.gltf") as PackedScene]
	stray.models = stray_models
	var not_placed: bool = not stage.has_carcass(stray)
	_check(ok and names.size() >= 2 and not_placed,
		"skinning's stage: every carcass with a round (%s) has its own round name, is placed under Carcasses, is shown alone for its round, its torso under the cut (%s); one not placed is not there (%s)"
			% [", ".join(names), ", ".join(said), not_placed])
	stage.queue_free()


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
		var kset: AnimationSet = k.timing_set if k.timing_set != null else aset
		var abilities: Array[AbilityDef] = []
		abilities.assign(k.light + k.skills)
		for a: AbilityDef in abilities:
			# The driver plays an ability as `ability.<id>` (anything else falls back to Interact: owner, 2026-10-19).
			_check(a.animation == StringName("ability.%d" % a.id) and kset.has_exact(a.animation) and kset.clip(a.animation).anim_name != kset.clip(&"interact").anim_name,
				"the %s kit's %s plays the set's ability.%d, its own clip (%s)" % [k.key, a.display_name, a.id, kset.clip(a.animation).anim_name if kset.has_exact(a.animation) else "none"])
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
	_check(SkillMinigames.CHALLENGE == {&"chop": 100, &"crack": 101, &"smelt": 102, &"shape": 103, &"beat": 104, &"carve": 105, &"pull": 106,
		&"skin": 107}, "the challenge kinds the server deals them as")
	var skin_p: SkinParams = NodeDef.all_by_tier()[7].minigame as SkinParams
	var quick_knife: SkinParams = SkillMinigames.with_speed(skin_p, 50) as SkinParams
	var eased_knife: SkinParams = SkillMinigames.eased(skin_p, 12) as SkinParams
	var skin_ui: SkillMinigame = SkillMinigames.make_ui(skin_p)
	var is_skin_ui: bool = skin_ui is SkinMinigame
	skin_ui.free()
	_check(SkillMinigames.kind_of(skin_p) == SkillMinigames.SKIN and SkillMinigames.gathers(SkillMinigames.SKIN) and SkillMinigames.arity(SkillMinigames.SKIN) == 3
		and quick_knife.cut_speed == skin_p.cut_speed * 2 and eased_knife.near == skin_p.near * 112 / 100 and skin_p.near == 45
		and is_skin_ui,
		"the cut line: kind 107, a gathering round of (time, x, y); a knife twice as quick cuts twice as fast (%d), rank widens the line (%d)"
			% [quick_knife.cut_speed, eased_knife.near])
	var flax_p: PullParams = NodeDef.all_by_tier()[6].minigame as PullParams
	var quick_trowel: PullParams = SkillMinigames.with_speed(flax_p, 50) as PullParams
	var eased_p: PullParams = SkillMinigames.eased(flax_p, 12) as PullParams
	var pull_ui: SkillMinigame = SkillMinigames.make_ui(flax_p)
	var is_pull_ui: bool = pull_ui is PullMinigame
	pull_ui.free()
	_check(SkillMinigames.kind_of(flax_p) == SkillMinigames.PULL and SkillMinigames.kind_of_challenge(106) == SkillMinigames.PULL
		and is_pull_ui and SkillMinigames.duration_of(flax_p) == flax_p.duration_ms
		and quick_trowel.stroke_ms == flax_p.stroke_ms / 2 and flax_p.stroke_ms == 250
		and eased_p.jump_lo == flax_p.jump_lo * 88 / 100 and eased_p.jump_hi == flax_p.jump_hi * 88 / 100 and flax_p.jump_hi == 400
		and eased_p.hold_pm == flax_p.hold_pm * 88 / 100 and flax_p.hold_pm == 600,
		"pull the root: its own kind (106), its UI; a trowel twice as fast strokes in half the time, rank eases the side roots' jumps and the soil's hold; the content untouched")
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
## HERBALISM'S PULL THE ROOT (`HERBALISM_HUNTING_PREP.md` §3, Luke's H3; PROGRESS 51; the trowel's work after his play,
## 2026-11-08): packed soil holds the root back and a trowel stroke digs a side loose; held, the strain rises and the
## root comes up (faster at a higher strain), let go or while a stroke runs it eases; a side root shows (the soil
## cracks on its side) once the root is coming up near it, and a stroke on that side cuts it, the other side only digs;
## pulled through uncut it jumps the strain; past 1000 it snaps; up whole is 1000; a CLUMP (Luke, 2026-11-08): stem
## after stem until the time runs out, each packed again, a snap losing the rest of that stem, never the round.
## SKINNING'S CUT LINE (2026-11-10): the model's rules on a straight line (`SkinModel` writes them out).
func _run_skin() -> void:
	print("== regents: the cut line ==")
	var p: SkinParams = SkinParams.new()
	p.points = 2
	p.wobble = 0
	p.target_lines = 1
	var m: SkinModel = SkinModel.start(3, p)
	var dir: int = signi(m.px[1] - m.px[0])
	var straight: bool = m.py == PackedInt32Array([500, 500]) and absi(m.px[1] - m.px[0]) == 800 and m.seg_len[0] == 800
	m.press(0, m.px[0], 500)
	m.advance_to(500)
	var still: bool = m.f == 0 and m.torn == 0
	# Dragged at the cut's pace: 30 of 800 a tick is 37 thousandths of the stretch.
	var x: int = m.px[0]
	for k: int in 4:
		x += dir * 30
		m.press(550 + k * 50, x, 500)
	m.advance_to(750)
	var paced: bool = m.f == 37 * 4 and m.torn == 0
	m.press(800, x + dir * 30, 500 + 44)   # within 45 of the line: still cuts
	m.advance_to(850)
	var near_ok: bool = m.torn == 0 and m.f > 150
	m.press(850, x + dir * 60, 500 + 60)   # 60 off: tears
	m.advance_to(950)
	var off_tears: bool = m.torn == 2 and m.tears == 2
	var tip: Vector2i = m.tip()
	m.press(950, tip.x + dir * 200, 500)   # on the line, past its reach: tears
	m.advance_to(1000)
	var ahead_tears: bool = m.torn == 3
	m.press(1000, SkinModel.LIFT, SkinModel.LIFT)
	m.advance_to(1500)
	var lifted_safe: bool = m.torn == 3 and not m.down
	# Pressed again at the tip and dragged to the end: the line done, worth 1000 less 35 a tear, the knife lifted.
	var t: int = 1500
	tip = m.tip()
	x = tip.x
	m.press(t, x, 500)
	while t < 8000:
		t += 50
		m.advance_to(t)
		if m.line > 0:
			break
		x = clampi(x + dir * 30, 0, 1000)
		m.press(t, x, 500)
	var done: bool = m.lines == 1 and m.clean == 0 and m.worth == 1000 - 3 * 35 and not m.down and m.tears == 0 and m.seg == 0 and m.f == 0
	var lifted_at_end: int = m.press(t + 50, x, 500)
	m.finish()
	var part: SkinModel = SkinModel.start(3, p)
	part.press(0, part.px[0], 500)
	for k: int in 6:
		part.press(50 + k * 50, part.px[0] + dir * 30 * (k + 1), 500)
	part.press(350, SkinModel.LIFT, SkinModel.LIFT)
	part.advance_to(400)
	var cut_pm: int = part.done_pm()
	part.finish()
	var part_ok: bool = part.lines == 0 and cut_pm > 0 and part.worth == 1000 * cut_pm / 1000 * p.part_keep_pm / 1000
	_check(straight and still and paced and near_ok and off_tears and ahead_tears and lifted_safe and done and lifted_at_end == SkinModel.PRESSED and part_ok,
		"the cut line: a straight line 800 long; the knife held still on the start cuts nothing and tears nothing (%s); dragged at the cut's pace it runs 37 a tick (%s); 44 off the line still cuts (%s), 60 off tears and runs nothing (%s), 200 ahead on the line tears (%s); lifted, nothing tears (%s); cut through: worth 1000 less 35 a tear, the knife lifted, the next line drawn (%s); a line part cut at the end is worth half what was cut (%s)"
			% [still, paced, near_ok, off_tears, ahead_tears, lifted_safe, done, part_ok])
	var readout: Dictionary = MinigameReadout.measure(NodeDef.all_by_tier()[7].minigame, SimPlayer.presets()[1], 40)
	var careless: Dictionary = MinigameReadout.measure(NodeDef.all_by_tier()[7].minigame, SimPlayer.presets()[3], 40)
	_check(bool(readout["agree"]) and bool(careless["agree"]) and int(readout["mean"]) >= 900 and int(careless["mean"]) < int(readout["mean"]),
		"the deer's cut line, simulated: skilled %d %%, careless %d %%, every round replayed exactly" % [int(readout["mean"]) / 10, int(careless["mean"]) / 10])


func _run_pull() -> void:
	print("== regents: pull the root ==")
	var p0: PullParams = PullParams.new()
	p0.snags = 0
	# Packed both sides: (10 + 40 x 40 / 1000) x (1000 - 600) / 1000 = 4 a tick; dug round: 11.
	var packed: PullModel = PullModel.start(1, p0)
	packed.press(0, PullModel.DOWN)
	packed.advance_to(50)
	var loose: PullModel = PullModel.start(1, p0)
	var dug: Array = [loose.press(0, PullModel.LEFT), loose.press(100, PullModel.LEFT), loose.press(250, PullModel.LEFT),
		loose.press(500, PullModel.RIGHT), loose.press(750, PullModel.RIGHT), loose.press(1000, PullModel.RIGHT)]
	var packs: Vector2i = Vector2i(loose.pack_left, loose.pack_right)
	loose.press(1250, PullModel.DOWN)
	loose.advance_to(1300)
	_check(packed.up_by == 4 and loose.up_by == 11 and packed.strain == 40
		and dug == [PullModel.DUG, PullModel.IGNORED, PullModel.DUG, PullModel.DUG, PullModel.DUG, PullModel.SCRAPED] and packs == Vector2i(0, 0)
		and loose.dug == 4,
		"packed soil holds the root (4 a tick, dug round 11); a stroke digs a side 500, none while one runs, none past loose (%s, %s)" % [str(dug), str(packs)])
	# A stroke stops the pull while it runs: held, the strain eases and nothing comes up.
	var mid: PullModel = PullModel.start(1, p0)
	mid.press(0, PullModel.DOWN)
	mid.advance_to(500)
	var before: Vector2i = Vector2i(mid.up_by, mid.strain)
	mid.press(500, PullModel.RIGHT)
	mid.advance_to(750)
	var during: Vector2i = Vector2i(mid.up_by, mid.strain)
	mid.advance_to(850)
	_check(during.x == before.x and during.y == before.y - 5 * p0.strain_ease and mid.up_by > during.x and mid.strain > during.y,
		"a stroke stops the pull while it runs (%s -> %s), then held it pulls again" % [str(before), str(during)])
	# The strain: let go it eases 60 a tick; past 1000 it snaps (worth a quarter of what came up), the next stem packed again.
	var top: PullParams = p0.duplicate() as PullParams
	top.hold_pm = 0
	var at_top: PullModel = PullModel.start(1, top)
	at_top.press(0, PullModel.DOWN)
	at_top.advance_to(25 * 50)
	var held_at_top: bool = at_top.strain == 1000 and at_top.snapped == 0 and at_top.whole == 0
	var up_at_top: int = at_top.up_by
	at_top.advance_to(26 * 50)
	var snap_ok: bool = at_top.snapped == 1 and at_top.worth == mini(1000, up_at_top + top.pull_rate + 1040 * top.pull_gain / 1000) * top.snap_keep_pm / 1000
	_check(held_at_top and snap_ok and not at_top.over and at_top.plant == 1 and at_top.up_by == 0 and at_top.strain == 0
		and at_top.pack_left == 1000 and at_top.pack_right == 1000 and at_top.last_event == PullModel.SNAPPED,
		"at exactly 1000 it holds; one tick past it snaps, worth a quarter of what came up (%d); the next stem starts packed, never the round's end" % at_top.worth)
	at_top.press(1300, PullModel.UP)
	at_top.advance_to(1400)
	_check(at_top.strain == 0 and at_top.press(1400, PullModel.UP) == PullModel.IGNORED, "let go, it eases (never below 0); an UP while up is nothing")
	# A side root: it shows once the root is coming up near it, on its side; the other side only digs; that side cuts it.
	var p1: PullParams = PullParams.new()
	p1.snags = 1
	p1.hold_pm = 0
	p1.jump_lo = 300
	p1.jump_hi = 300
	var sd: int = -1
	for k: int in 50:
		var probe: PullModel = PullModel.start(1 + k * 7919, p1)
		if probe.snag_depth[0] > p1.show_depth + 100:
			sd = 1 + k * 7919
			break
	var c: PullModel = PullModel.start(sd, p1)
	var depth: int = c.snag_depth[0]
	var side: int = c.snag_side[0]
	var other: int = PullModel.RIGHT if side == PullModel.LEFT else PullModel.LEFT
	var hidden_at_start: bool = c.showing() == 0
	c.press(0, PullModel.DOWN)
	var t: int = 0
	while c.showing() == 0 and t < 5000:
		t += 50
		c.advance_to(t)
	var shown_near: bool = c.showing() == side and depth - c.up_by <= p1.show_depth and depth - c.up_by > 0
	var wrong: int = c.press(t, other)
	var right_side: int = c.press(t + p1.stroke_ms, side)
	c.advance_to(t + p1.stroke_ms + 50)
	_check(sd > 0 and hidden_at_start and shown_near and wrong == PullModel.DUG and right_side == PullModel.CUT and c.cut == 1 and c.caught == 0
		and c.next_snag == 1 and c.showing() == 0 and c.plant == 0,
		"a side root (at %d, side %d) shows near it once the root comes up; a stroke on the other side digs, on its side it cuts: never caught" % [depth, side])
	var u: PullModel = PullModel.start(sd, p1)
	u.press(0, PullModel.DOWN)
	var strain_before: int = 0
	t = 0
	while u.caught == 0 and t < 5000:
		if u.strain > 600:
			u.press(t, PullModel.UP)
			u.advance_to(t + 300)
			u.press(t + 300, PullModel.DOWN)
			t += 300
		strain_before = u.strain
		t += 50
		u.advance_to(t)
	_check(u.caught == 1 and u.strain == strain_before + p1.strain_rise + 300 and u.last_event == PullModel.CAUGHT and u.snapped == 0,
		"uncut, pulling through it jumps the strain by its 300 (%d -> %d)" % [strain_before, u.strain])
	# Up whole, stem after stem until the time runs out: packed it comes up 40 a tick; dug round (4 strokes of 250) 100,
	# so 10 ticks a stem; two for a full score.
	var easy: PullParams = PullParams.new()
	easy.snags = 0
	easy.strain_rise = 1
	easy.pull_rate = 100
	easy.pull_gain = 0
	easy.target_plants = 2
	var w: PullModel = PullModel.start(3, easy)
	w.press(0, PullModel.DOWN)
	w.advance_to(9 * 50)
	var first_packed: bool = w.up_by == 40 * 9 and w.whole == 0
	w.finish()
	var b: PullModel = PullModel.start(3, easy)
	var stems_ok: bool = true
	var ms: int = 0
	for stem: int in 3:
		for side_k: int in 4:
			b.press(ms, PullModel.LEFT if side_k < 2 else PullModel.RIGHT)
			ms += easy.stroke_ms
		b.press(ms, PullModel.DOWN)
		ms += 10 * 50
		b.press(ms, PullModel.UP)
		stems_ok = stems_ok and b.whole == stem + 1 and b.plant == stem + 1 and b.pack_left == 1000 and b.up_by == 0
	b.finish()
	_check(first_packed and stems_ok and b.whole == 3 and b.worth == 3000 and b.score_pm() == 1000 and b.dug == 12 and w.over and w.snapped == 0,
		"up whole: 1000; each stem dug round anew; three in a clump, two wanted: a full score (%s)" % str(b.result()))
	# Dealt by the server (a challenge row of kind 106): the client finds the NODE (flax), not a recipe, and hands its
	# round to the UI at the trowel's speed (the skilling playtest found it went looking for a recipe and dropped it).
	var sk: SkillingComponent = SkillingComponent.new()
	var dealt: Array = []
	sk.round_dealt.connect(func(id: int, s: int, params: Resource, target: int, name: String) -> void: dealt.append([id, s, params, target, name]))
	var row: ChallengeRow = ChallengeRow.new()
	row.fields = {"id": 77, "kind": 106, "seed": 5, "payload": "1234 40007 50"}
	sk._on_challenge(null, row)
	var got_p: PullParams = (dealt[0][2] as PullParams) if dealt.size() == 1 else null
	_check(SkillMinigames.gathers(SkillMinigames.PULL) and not SkillMinigames.gathers(SkillMinigames.CARVE) and got_p != null
		and dealt[0][3] == 1234 and dealt[0][4] == "Flax" and got_p.stroke_ms == 125 and sk.round_def is NodeDef and sk.run_target == 1234,
		"a pull round dealt at flax: the client finds the node, plays it at the trowel's speed (a 125 ms stroke at 50 %%), and runs rounds back to back (%s)" % str(dealt))
	sk.free()
	var one: PullParams = easy.duplicate() as PullParams
	one.target_plants = 1
	one.duration_ms = 400
	one.hold_pm = 0
	var g: Dictionary = PullModel.play(3, one, PackedInt32Array([200, PullModel.DOWN]))
	_check(int(g["whole"]) == 0 and int(g["score_pm"]) == 4 * 100 * one.snap_keep_pm / 1000,
		"still in the ground at the end: worth a quarter of what came up (%s)" % str(g))
	_check(int(PullModel.play(3, one, PackedInt32Array()).get("score_pm", -1)) == 0, "nothing pulled: nothing")


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
	_check(buttons.size() == 32 and game is ChopMinigame and game.state == SkillMinigame.State.READY,
		"thirty-two rounds to play (nine nodes, flax's pull the root and the two carcasses' cut lines among them; three bars, eighteen smithed parts with the trowel and knife blades and armor's plates, the carved bow and staff), the first, a tree's, on show (%d)" % buttons.size())
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


## THE GLADE'S LOOK (PROGRESS step 59: foliage lit on both sides, a ground that wears where the level is used, a meadow
## of MultiMesh clutter). Every nature model's leaves, petals and blades are the foliage shader (a model imported
## without `nature_import.gd` is named); the glade's ground is painted from its own markers (dirt under a station, a
## trail and a worn patch, soil under a tree, none under flax or in open meadow); the clutter is many, seeded, off
## the dirt and the bare soil, gathered at the soil's rim, shadowless, and thinned by Detail. NEGATIVES: a plain
## foliage material is caught; a station moved away takes its dirt with it; with no painter the grass grows on
## the trails.
func _run_glade_look() -> void:
	print("== regents: the glade's foliage, ground and clutter ==")
	const NATURE: String = "res://game/regents/art/nature/"
	var plain := PackedStringArray()
	var lit: int = 0
	var models: int = 0
	for file: String in DirAccess.get_files_at(NATURE):
		if not file.ends_with(".gltf"):
			continue
		models += 1
		var model: Node = (load(NATURE + file) as PackedScene).instantiate()
		for mat_name: String in _plain_foliage(model):
			plain.append("%s: %s" % [file, mat_name])
		lit += _foliage_surfaces(model)
		model.free()
	_check(plain.is_empty() and lit >= 16, "every leaf, petal and blade of the %d nature models is the foliage shader (%d surfaces; plain: %s)" % [models, lit, plain])
	# NEGATIVE: a foliage material as the kit ships it is caught, and bark is not foliage.
	var kit_leaf := StandardMaterial3D.new()
	kit_leaf.resource_name = "Leaves_NormalTree"
	kit_leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var bark := StandardMaterial3D.new()
	bark.resource_name = "Bark_NormalTree"
	var probe := MeshInstance3D.new()
	var quad := ArrayMesh.new()
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, QuadMesh.new().get_mesh_arrays())
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, QuadMesh.new().get_mesh_arrays())
	quad.surface_set_material(0, kit_leaf)
	quad.surface_set_material(1, bark)
	probe.mesh = quad
	_check(_plain_foliage(probe) == PackedStringArray(["Leaves_NormalTree"]), "NEGATIVE: a leaf left as the kit's plain material is caught, bark is not (%s)" % _plain_foliage(probe))
	var swapped: ShaderMaterial = FoliageMaterial.from_standard(kit_leaf)
	_check(swapped.shader == FoliageMaterial.SHADER_CUTOUT and swapped.get_shader_parameter(&"shrink_to_m") == null,
		"swapped, a cut-out leaf is the cut-out foliage shader, and neither shrinks nor sways until the clutter says so")
	probe.free()

	var level: Node3D = (load("res://game/regents/levels/frontier.tscn") as PackedScene).instantiate() as Node3D
	add_child(level)
	var paint: RegentsGroundPaint = level.get_node("GroundPaint") as RegentsGroundPaint
	var clutter: RegentsGroundClutter = level.get_node("Clutter") as RegentsGroundClutter
	var field: CSGBox3D = level.get_node("Ground/Field") as CSGBox3D
	_check(paint != null and clutter != null and field.material == paint.material and paint.material.shader.resource_path.ends_with("glade_ground.gdshader"),
		"the glade has a ground painter and clutter, and its ground is the painter's material")
	if paint == null or clutter == null:
		level.free()
		return
	if DisplayServer.get_name() == "headless":
		_check(not paint.painted() and clutter.made.is_empty() and paint.dirt_at(-6.0, 14.0) == 0.0,
			"a headless process (the referee) paints and scatters nothing by itself")
	paint.repaint()
	var flax: Vector3 = Vector3.INF
	var tree: Vector3 = Vector3.INF
	for found: Node in level.get_node("Nodes").get_children():
		var point: LevelPoint = found as LevelPoint
		if point != null and point.tags.size() > 0 and point.tags[0] == "Flax" and flax == Vector3.INF:
			flax = point.global_position
		if point != null and point.tags.size() > 0 and point.tags[0] == "Tree" and tree == Vector3.INF:
			tree = point.global_position
	var rack: Marker3D = level.get_node("Stations/tanning_rack") as Marker3D
	var by_rack: Vector3 = rack.global_position + Vector3(0.0, 0.0, -1.0)
	_check(paint.painted() and paint.dirt_at(-6.0, 14.0) > 0.9 and paint.dirt_at(by_rack.x, by_rack.z) > 0.9,
		"trodden dirt under the furnace and by the tanning rack (%.2f, %.2f)" % [paint.dirt_at(-6.0, 14.0), paint.dirt_at(by_rack.x, by_rack.z)])
	_check(paint.dirt_at(35.0, -1.0) > 0.9 and paint.dirt_at(0.0, 8.0) > 0.9, "a worn patch where a plain marker stands (the skeleton camp, the camp)")
	var on_trail: float = 0.0
	for dz: int in range(-4, 5):
		on_trail = maxf(on_trail, paint.dirt_at(15.0, 5.25 + float(dz) * 0.4))
	_check(on_trail > 0.9, "a trail is worn along its curve (east of camp: %.2f)" % on_trail)
	_check(tree != Vector3.INF and paint.soil_at(tree.x, tree.z) > 0.9 and paint.dirt_at(tree.x, tree.z) == 0.0, "bare soil under a tree, not dirt")
	_check(flax != Vector3.INF and paint.soil_at(flax.x, flax.z) == 0.0, "flax grows in the grass: no soil under it (%.2f)" % paint.soil_at(flax.x, flax.z))
	_check(paint.dirt_at(-20.0, 24.0) == 0.0 and paint.soil_at(-20.0, 24.0) == 0.0 and paint.dirt_at(500.0, 0.0) == 0.0,
		"open meadow is neither, nor is anywhere off the picture")
	# NEGATIVE: the dirt is the marker's: the rack moved away, its ground is grass again and the dirt went with it.
	var rack_was: Vector3 = rack.position
	rack.position = Vector3(-40.0, 0.0, 40.0)
	paint.repaint()
	_check(paint.dirt_at(by_rack.x, by_rack.z) == 0.0 and paint.dirt_at(-40.0, 39.0) > 0.9,
		"NEGATIVE: the tanning rack moved, its dirt moved with it (%.2f where it was)" % paint.dirt_at(by_rack.x, by_rack.z))
	rack.position = rack_was
	paint.repaint()

	clutter.scatter()
	var total: int = clutter.count()
	var on_dirt: int = 0
	var in_soil: int = 0
	var at_rim: int = 0
	var plants: int = 0
	var grouped: bool = true
	for m: int in range(clutter.made.size()):
		var mmi: MultiMeshInstance3D = clutter.made[m]
		if not (mmi.is_in_group(GraphicsQuality.GROUP_DENSITY) and mmi.visibility_range_end > clutter.draw_distance_m
				and mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF):
			grouped = false
		var pebbles: bool = String(mmi.name).begins_with("Pebble")
		if clutter.places_in(m).size() != mmi.multimesh.instance_count:
			grouped = false
		for at: Vector3 in clutter.places_in(m):
			if paint.soil_at(at.x, at.z) > RegentsGroundClutter.SOIL_MAX:
				in_soil += 1
			if pebbles:
				continue
			plants += 1
			if paint.dirt_at(at.x, at.z) > RegentsGroundClutter.DIRT_MAX:
				on_dirt += 1
			if RegentsGroundClutter.at_foot(paint, at.x, at.z):
				at_rim += 1
	_check(total > 2000 and total < 12000 and clutter.made.size() > 25, "a meadow: %d scattered in %d MultiMeshes (the glade had 100 nodes)" % [total, clutter.made.size()])
	_check(grouped, "every one of them thins with Detail, is not drawn past its distance, casts no shadow and knows where its own are")
	_check(on_dirt == 0 and in_soil == 0, "no plant on trodden dirt, nothing in bare soil (%d, %d of %d)" % [on_dirt, in_soil, total])
	# How much of the ground that could grow something is a foot: a plant there is likelier than its share of it.
	var foot_m2: int = 0
	var open_m2: int = 0
	for gx: int in range(-60, 60):
		for gz: int in range(-60, 60):
			var wx: float = float(gx) + 0.5
			var wz: float = float(gz) + 0.5
			if paint.soil_at(wx, wz) > RegentsGroundClutter.SOIL_MAX or paint.dirt_at(wx, wz) > RegentsGroundClutter.DIRT_MAX:
				continue
			if RegentsGroundClutter.at_foot(paint, wx, wz):
				foot_m2 += 1
			else:
				open_m2 += 1
	var foot_density: float = float(at_rim) / maxf(float(foot_m2), 1.0)
	var open_density: float = float(plants - at_rim) / maxf(float(open_m2), 1.0)
	_check(foot_m2 > 200 and foot_density > open_density * 2.0,
		"plants gather at the foot of rocks and trees: %.2f a square meter there (%d on %d m2), %.2f on open ground" % [foot_density, at_rim, foot_m2, open_density])
	var first: MultiMeshInstance3D = clutter.made[0] if not clutter.made.is_empty() else null
	if first != null:
		var own: ShaderMaterial = first.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		var kit_model: Node = clutter.kinds[0].model.instantiate()
		var model_mesh: MeshInstance3D = kit_model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var kit: ShaderMaterial = model_mesh.mesh.surface_get_material(0) as ShaderMaterial
		var shrinks: Variant = own.get_shader_parameter(&"shrink_to_m") if own != null else null
		_check(own != null and kit != null and own != kit and shrinks is float and is_equal_approx(float(shrinks), clutter.draw_distance_m)
			and kit.get_shader_parameter(&"shrink_to_m") == null,
			"a tuft shrinks away by the clutter's distance on its own copy of the material: the model's is untouched")
		kit_model.free()
		var was: int = GraphicsQuality.detail
		GraphicsQuality.detail = GraphicsQuality.Detail.LOW
		GraphicsQuality.apply_node(first)
		var low: int = first.multimesh.visible_instance_count
		GraphicsQuality.detail = GraphicsQuality.Detail.HIGH
		GraphicsQuality.apply_node(first)
		_check(low == maxi(1, int(float(first.multimesh.instance_count) * 0.25)) and first.multimesh.visible_instance_count == -1,
			"Low detail draws a quarter of a cell's tufts (%d of %d), High all of them" % [low, first.multimesh.instance_count])
		GraphicsQuality.detail = was
		GraphicsQuality.apply_node(first)
	var places: PackedVector3Array = clutter.places()
	clutter.scatter()
	_check(clutter.count() == total and clutter.places() == places, "scattered again it is the same meadow (seeded)")
	# NEGATIVE: the painter is what keeps the grass off the trails: without it, plants stand on the dirt.
	var paint_path: NodePath = clutter.paint
	clutter.paint = NodePath("")
	clutter.scatter()
	var trampled: int = 0
	for m: int in range(clutter.made.size()):
		if String(clutter.made[m].name).begins_with("Pebble"):
			continue
		for at: Vector3 in clutter.places_in(m):
			if paint.dirt_at(at.x, at.z) > RegentsGroundClutter.DIRT_MAX:
				trampled += 1
	_check(trampled > 0, "NEGATIVE: with no painter the grass grows on the trails (%d plants on dirt)" % trampled)
	clutter.paint = paint_path
	level.free()


## The names of `root`'s foliage materials that are still the kit's plain double-sided ones (lit black from behind).
func _plain_foliage(root: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n: Node in meshes:
		var mi: MeshInstance3D = n as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D and FoliageMaterial.is_foliage(mat):
				out.append(mat.resource_name)
	return out


## How many of `root`'s surfaces are drawn by the foliage shader.
func _foliage_surfaces(root: Node) -> int:
	var n: int = 0
	for found: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = found as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat: ShaderMaterial = mi.mesh.surface_get_material(i) as ShaderMaterial
			if mat != null and (mat.shader == FoliageMaterial.SHADER_CUTOUT or mat.shader == FoliageMaterial.SHADER_OPAQUE):
				n += 1
	return n


## A use the server never answers: enough of an `ability_def` row for the action component to begin one.
class RollDefRow extends RefCounted:
	var ability_id: int = CombatComponent.DODGE_ID
	var cooldown_ms: int = 1500
	var wind_up_ms: int = 100


## THE COMBAT PASS (Luke's list, 2026-11-11; PROGRESS step 60): a free shot flies to the crosshair; a shot the
## server aims goes to the middle of what it is aimed at; a roll goes a set length; the server is told how late
## this client shows a swing.
func _run_combat_pass() -> void:
	print("== regents: the combat pass ==")
	# TO THE CROSSHAIR. The camera sits 4 m behind and above the shoulder, looking down a little; the crosshair is
	# on a wolf's back (0.5 m up). The muzzle is at the chest.
	var muzzle := Vector3(0.0, CombatComponent.MUZZLE_HEIGHT_M, 0.0)
	var pitch: float = deg_to_rad(-8.0)
	var cam: Vector3 = Vector3(0.0, 1.6, 0.0) + Vector3(0.0, 0.0, 4.0).rotated(Vector3.RIGHT, pitch)
	var look := Vector3(0.0, sin(pitch), -cos(pitch))
	var wolf: Vector3 = cam + look * ((cam.y - 0.5) / -look.y)
	_check(wolf.z < -5.0 and is_equal_approx(wolf.y, 0.5), "(the crosshair is on a wolf %.1f m ahead)" % -wolf.z)
	for speed: float in [20.0, 35.0, 50.0]:
		var dir: Vector3 = CombatComponent.launch_direction(muzzle, wolf, speed, CombatComponent.ARROW_GRAVITY)
		var miss: float = _shot_miss(muzzle, dir * speed, wolf, CombatComponent.ARROW_GRAVITY)
		var old_miss: float = _shot_miss(muzzle, look * speed, wolf, CombatComponent.ARROW_GRAVITY)
		_check(is_equal_approx(dir.length(), 1.0) and miss < 0.05, "an arrow at %.0f m/s lands where the crosshair is (%.2f m off)" % [speed, miss])
		_check(old_miss > 0.25, "NEGATIVE: loosed along the look from the chest, as before, it passes %.2f m from it" % old_miss)
	for to: Vector3 in [Vector3(3.0, 0.0, -25.0), Vector3(-2.0, 4.0, -18.0), Vector3(0.5, 0.3, -3.0)]:
		var dir: Vector3 = CombatComponent.launch_direction(muzzle, to, 40.0, CombatComponent.ARROW_GRAVITY)
		_check(_shot_miss(muzzle, dir * 40.0, to, CombatComponent.ARROW_GRAVITY) < 0.05, "and on the ground far off, a ledge above, a point at its feet (%s)" % to)
	var bolt: Vector3 = CombatComponent.launch_direction(muzzle, wolf, 32.0, 0.0)
	_check(_shot_miss(muzzle, bolt * 32.0, wolf, 0.0) < 0.03 and _shot_miss(muzzle, look * 32.0, wolf, 0.0) > 0.1,
		"a bolt (no gravity) flies straight to it; along the look from the chest it did not")
	var out_of_reach: Vector3 = CombatComponent.launch_direction(muzzle, Vector3(0.0, 0.0, -500.0), 20.0, CombatComponent.ARROW_GRAVITY)
	_check(is_equal_approx(out_of_reach.y, sin(PI / 4.0)) and out_of_reach.z < 0.0, "out of an arrow's reach: 45 degrees up toward it (the server's rule)")
	# The crosshair's ray begins level with the muzzle: a thing between the camera and the player is not aimed at.
	var start: float = CombatComponent.aim_ray_start(cam, look, muzzle)
	_check(start > 3.5 and start < 4.5 and is_zero_approx(CombatComponent.aim_ray_start(muzzle + look, look, muzzle)),
		"the crosshair's ray starts past the player (%.1f m along it), never behind the camera" % start)
	# With no camera (headless) a shot goes along the look, as it did.
	var c: CombatComponent = CombatComponent.new()
	var far: Vector3 = c.crosshair_point()
	_check(far.distance_to(c.muzzle() + c.look_direction() * CombatComponent.AIM_FAR_M) < 0.001, "no camera: the crosshair is far along the look")
	# THE UPPER BODY TURNS TO THE SHOT (`AimTwist`): from the way the body faces to the target, less where the pose
	# points by itself. The bow's pose points 32 degrees left and 3.2 over (the aim pose is over the upper body only:
	# `aim_shot.tscn` measures it); the crosshair's point is right of straight ahead (the camera's shoulder).
	var ahead := Vector3(0.0, 0.0, -1.0)
	var bow_points := Vector2(deg_to_rad(32.0), deg_to_rad(3.2))
	var bow_line: Vector3 = AimTwist.rotation_for(ahead, Vector2(bow_points.x, -bow_points.y)) * ahead   # where the pose points
	var want := Vector3(0.3, -0.4, -12.0)
	var turn: Vector2 = AimTwist.turn_from(ahead, bow_points, want, deg_to_rad(95.0), deg_to_rad(40.0))
	var turned_line: Vector3 = AimTwist.rotation_for(bow_line, turn) * bow_line
	_check(turn.x < deg_to_rad(-30.0) and rad_to_deg(turned_line.angle_to(want)) < 0.5,
		"a bow pointing 32 degrees left of straight ahead is turned %.1f degrees right onto the crosshair (%.2f degrees off)" % [-rad_to_deg(turn.x), rad_to_deg(turned_line.angle_to(want))])
	_check(rad_to_deg(bow_line.angle_to(want)) > 30.0, "NEGATIVE: unturned, as before, it points %.0f degrees off" % rad_to_deg(bow_line.angle_to(want)))
	# A TAB TARGET, well to one side (Luke, 2026-11-12: "if tab target hand and bow should point towards them").
	for side_deg: float in [50.0, -50.0, 20.0]:
		var to_target: Vector3 = Vector3(0.0, -0.9, -9.0).rotated(Vector3.UP, deg_to_rad(side_deg))
		var side_turn: Vector2 = AimTwist.turn_from(ahead, bow_points, to_target, deg_to_rad(95.0), deg_to_rad(40.0))
		var onto: Vector3 = AimTwist.rotation_for(bow_line, side_turn) * bow_line
		_check(rad_to_deg(onto.angle_to(to_target)) < 1.5, "a target %.0f degrees to the %s: the bow is turned onto it (%.1f degrees off; turned %.0f)"
			% [absf(side_deg), "left" if side_deg > 0.0 else "right", rad_to_deg(onto.angle_to(to_target)), rad_to_deg(side_turn.x)])
		var to_crosshair: Vector2 = AimTwist.turn_from(ahead, bow_points, want, deg_to_rad(95.0), deg_to_rad(40.0))
		_check(absf(side_turn.x - to_crosshair.x) > deg_to_rad(15.0), "NEGATIVE: turned to the crosshair instead, it would be %.0f degrees off that target" % rad_to_deg(absf(side_turn.x - to_crosshair.x)))
	# The same turn whatever the hands are doing: it reads the body's facing, not the pose (the draw moves the hands).
	var behind: Vector2 = AimTwist.turn_from(ahead, Vector2.ZERO, Vector3(-0.2, 3.0, 1.0), deg_to_rad(95.0), deg_to_rad(40.0))
	_check(is_equal_approx(absf(behind.x), deg_to_rad(95.0)) and is_equal_approx(absf(behind.y), deg_to_rad(40.0)) and AimTwist.turn_from(ahead, bow_points, Vector3.UP, PI, PI) == Vector2.ZERO,
		"it turns no further than its limits (95 degrees round, 40 up), and not at all toward straight up")
	var aim_look := CombatLook.new()
	var shooter: CombatComponent = CombatComponent.new()
	shooter.is_local_authority = true
	aim_look._combat = shooter
	_check(aim_look.aiming_with() == CombatLook.AIM_NONE, "nothing wielded: nothing is aimed")
	shooter.kit = KitDef.by_key(&"bow")
	_check(aim_look.aiming_with() == CombatLook.AIM_NONE, "a bow, not drawn: the body is left as its clips pose it")
	shooter.draw_started_ms = Time.get_ticks_msec()
	var bow_deg: Vector2 = aim_look.bow_pose_points_deg
	_check(aim_look.aiming_with() == CombatLook.AIM_BOW and aim_look.pose_points(CombatLook.AIM_BOW).is_equal_approx(Vector2(deg_to_rad(bow_deg.x), deg_to_rad(bow_deg.y)))
		and bow_deg.x > 20.0 and bow_deg.x < 40.0,
		"drawing: turned, with where the bow's pose points by itself taken out (%s degrees left and over: the node's own numbers)" % bow_deg)
	shooter.draw_started_ms = -1
	shooter.shot_ms = Time.get_ticks_msec()
	_check(aim_look.aiming_with() == CombatLook.AIM_BOW, "just loosed: still turned, while the loose plays")
	shooter.shot_ms = Time.get_ticks_msec() - aim_look.aim_after_shot_ms - 1
	_check(aim_look.aiming_with() == CombatLook.AIM_NONE, "and let go after it")
	shooter.kit = KitDef.by_key(&"staff")
	shooter.shot_ms = Time.get_ticks_msec()
	_check(aim_look.aiming_with() == CombatLook.AIM_CAST and not aim_look.pose_points(CombatLook.AIM_CAST).is_equal_approx(aim_look.pose_points(CombatLook.AIM_CHANNEL)),
		"a bolt just cast: turned by the casting pose's own numbers (%s; a long cast's pose has its own, %s)" % [aim_look.cast_pose_points_deg, aim_look.channel_pose_points_deg])
	shooter.kit = KitDef.by_key(&"sword")
	_check(aim_look.aiming_with() == CombatLook.AIM_NONE, "a sword never is")
	_check(aim_look.muzzle_point() == Vector3.INF, "a character never seen to aim has no hand a shot leaves from: the shot is drawn on its path")
	var twist_default := AimTwist.new()
	var adv_model: Node3D = (load("res://game/regents/content/character/adventurer.tres") as EntityDefinition).visual_variants[0].instantiate() as Node3D
	var adv_skel: Skeleton3D = adv_model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_check(twist_default.spine_bones.size() == 3 and twist_default.spine_bones.all(func(bone: StringName) -> bool: return adv_skel.find_bone(String(bone)) >= 0)
		and adv_skel.find_bone(String(aim_look.bow_muzzle_bone)) >= 0 and adv_skel.find_bone(String(aim_look.cast_muzzle_bone)) >= 0,
		"the turn is shared over three spine bones the adventurer has (%s); the hands a shot leaves from are its bones" % str(twist_default.spine_bones))
	adv_model.free()
	twist_default.free()
	# FACE YOUR TARGET (Luke, 2026-11-12: "I can tab target and then face AWAY from the target and still shoot"): a
	# shot is aimed at a Tab target only inside the arc in front of the body.
	var arc: float = HotRules.number(&"regents.aim_arc_deg")
	_check(is_equal_approx(arc, 120.0) and CombatComponent.within_arc(0.0, 0.0, -5.0, arc) and CombatComponent.within_arc(0.0, 4.0, -3.0, arc),
		"a target straight ahead, or 53 degrees to the side, is faced (the arc: %.0f degrees)" % arc)
	_check(not CombatComponent.within_arc(0.0, 0.0, 5.0, arc) and not CombatComponent.within_arc(0.0, 5.0, -2.0, arc),
		"NEGATIVE: one behind you, or 68 degrees to the side, is not: the shot is refused")
	_check(CombatComponent.within_arc(PI, 0.0, 5.0, arc) and not CombatComponent.within_arc(PI, 0.0, -5.0, arc), "turned right round, it is the other way about")
	_check(CombatComponent.FACE_YOUR_TARGET == "Face your target", "and it says so")
	shooter.free()
	aim_look.free()
	# A SHOT THE SERVER AIMS (a Tab target) goes to the middle of what it is aimed at.
	var wolf_def: FoeDef = load("res://game/regents/content/foe/wolf.tres") as FoeDef
	var warrior: FoeDef = load("res://game/regents/content/foe/skeleton_warrior.tres") as FoeDef
	_check(wolf_def.aim_height_m() < wolf_def.character.collision_height and is_equal_approx(wolf_def.aim_height_m(), wolf_def.character.collision_height * 0.5),
		"a shot aimed at a wolf goes to the middle of its body (%.2f m of %.1f)" % [wolf_def.aim_height_m(), wolf_def.character.collision_height])
	_check(FoeDef.DEFAULT_AIM_HEIGHT_M > wolf_def.character.collision_height,
		"NEGATIVE: at a man's chest (%.1f m), as before, it flew over the wolf's back (%.1f m)" % [FoeDef.DEFAULT_AIM_HEIGHT_M, wolf_def.character.collision_height])
	_check(is_equal_approx(warrior.aim_height_m(), FoeDef.DEFAULT_AIM_HEIGHT_M) and is_equal_approx(float(wolf_def.to_bake()["aim_height_m"]), wolf_def.aim_height_m()),
		"a skeleton is aimed at where it was; the bake carries the height to the server")

	# TRAILS (`RibbonTrail`): behind a point that flies, and the sheet a blade sweeps; each fades off its tail.
	var flier := Node3D.new()
	add_child(flier)
	var trail := RibbonTrail.new()
	trail.lifetime_s = 0.2
	add_child(trail)
	trail.follow(flier)
	for i: int in range(6):
		flier.position.x += 0.5
		trail.step(0.02)
	_check(trail.sample_count() == 6 and trail.showing() and trail.mesh.get_surface_count() == 1, "a trail behind a flying point: a sample a frame, drawn as one ribbon")
	trail.step(0.15)
	_check(trail.sample_count() >= 1 and trail.sample_count() < 6, "its tail falls off after its lifetime (%d of 6 left)" % trail.sample_count())
	flier.position.x += 50.0
	trail.step(0.02)
	_check(trail.sample_count() == 1, "a jump (its entity placed, a teleport) starts it over: never a streak across the world")
	trail.step(0.5)
	_check(not trail.showing() and trail.mesh.get_surface_count() == 0, "left alone it is gone")
	var sheet := RibbonTrail.new()
	add_child(sheet)
	for i: int in range(5):
		sheet.add_blade(Vector3(0.0, 1.0, 0.0), Vector3(cos(float(i) * 0.3), 1.0, -sin(float(i) * 0.3)))
		sheet.step(0.016)
	sheet.add_blade(Vector3(0.0, 1.0, 0.0), Vector3(cos(1.2), 1.0, -sin(1.2)))
	_check(sheet.sample_count() == 5 and sheet.showing(), "a blade's sheet: an edge for every frame of the cut, none for a blade that has not moved")
	for n: Node3D in [flier, trail, sheet]:
		n.free()
	# Every shot's look has its trail; since PROGRESS 82 the spells' missiles are the VFX lab's (a riding
	# `VfxFireMissile`: its flame, its ribbon, its sparks) and end in an effect (the fireball's blast on the ground, the
	# bolt's flash); an arrow keeps its own plain trail and ends in nothing.
	for path: String in ["arrow", "bolt", "fireball"]:
		var shot: ShotLook = (load("res://game/regents/combat/%s_look.tscn" % path) as PackedScene).instantiate() as ShotLook
		var rider: VfxFireMissile = null
		for child: Node in shot.get_children() if shot != null else []:
			rider = child as VfxFireMissile if child is VfxFireMissile else rider
		if path == "arrow":
			_check(shot != null and shot.trail_life_s > 0.0 and shot.end_scene == null and rider == null, "the arrow's look: its own trail, no effect")
		else:
			var ends: Node = shot.end_scene.instantiate() if shot != null and shot.end_scene != null else null
			_check(rider != null and rider.rides and rider.trail_width_m > 0.0 and ends is VfxEffect and shot.end_on_ground == (path == "fireball"),
				"the %s's look: the lab's missile riding on it (its own ribbon), and an effect where it ends%s" % [path, " (on the ground)" if path == "fireball" else ""])
			if ends != null:
				ends.free()
		if shot != null:
			shot.free()
	# A SWING'S TRAIL (`SwingTrail`): only a swing draws one, through its cut; the blade found on what is shown.
	var cut: AbilityDef = ContentLibrary.find(&"ability", 40017) as AbilityDef
	var window: Vector2i = SwingTrail.cut_window(cut, 1000, 0.55, 130)
	_check(window == Vector2i(1000 + roundi(float(cut.wind_up_ms) * 0.55), 1000 + cut.wind_up_ms + 130), "a swing draws its cut from late in the wind-up to just after it lands (%s)" % window)
	_check(SwingTrail.cut_window(ContentLibrary.find(&"ability", CombatComponent.DODGE_ID) as AbilityDef, 0, 0.55, 130) == Vector2i(-1, -1)
		and SwingTrail.cut_window(ContentLibrary.find(&"ability", 40011) as AbilityDef, 0, 0.55, 130) == Vector2i(-1, -1)
		and SwingTrail.cut_window(null, 0, 0.55, 130) == Vector2i(-1, -1), "a roll and a bow's loose draw none")
	var edge: Array = SwingTrail.blade_in_box(AABB(Vector3(-0.05, -0.2, -0.05), Vector3(0.1, 1.2, 0.1)), Vector3.ZERO, 0.3)
	_check(edge.size() == 2 and (edge[1] as Vector3).is_equal_approx(Vector3(0.0, 1.0, 0.0)) and (edge[0] as Vector3).is_equal_approx(Vector3(0.0, 0.3, 0.0)),
		"a weapon's blade: along its longest side from the grip, its far end the tip, the hilt left out")
	for kind: int in [103, 104]:
		var foe_model: Node3D = FoeDef.by_kind(kind).character.visual_scene.instantiate() as Node3D
		add_child(foe_model)
		var foe_skel: Skeleton3D = foe_model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var found: Array = SwingTrail.blade_in_bone(foe_skel, foe_skel.find_bone("hand_r"), 0.3)
		_check(found.size() == 2 and (found[1] as Vector3).length() > 0.4 and (found[1] as Vector3).length() < 1.3,
			"%s's own weapon is found by its hand: its tip %.2f m from the grip" % [FoeDef.by_kind(kind).display_name, (found[1] as Vector3).length() if found.size() == 2 else 0.0])
		foe_model.free()
	var wolf_model: Node3D = wolf_def.character.visual_scene.instantiate() as Node3D
	add_child(wolf_model)
	var wolf_skel: Skeleton3D = wolf_model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var default_trail := SwingTrail.new()
	_check(wolf_skel.find_bone(String(default_trail.hand_bone)) < 0 and wolf_skel.find_bone(String(default_trail.head_bone)) >= 0,
		"a wolf has no hand: its trail is drawn at its head (%s)" % default_trail.head_bone)
	default_trail.free()
	wolf_model.free()
	for scene: String in ["res://game/regents/adventurer.tscn", "res://game/regents/combat/foe.tscn"]:
		var fighter: Node = (load(scene) as PackedScene).instantiate()
		_check(fighter.get_node_or_null(^"Components/SwingTrail") is SwingTrail, "%s carries the swing trail" % scene.get_file())
		fighter.free()
	# MORE ANTICIPATION (Luke, 2026-11-11): a foe's light swings wind up a fifth longer, their clips slowed to match.
	var foe_set: AnimationSet = load("res://game/regents/anim/adventurer.tres") as AnimationSet
	for row: Array in [[40017, 660], [40018, 700], [40020, 710], [40027, 650], [40028, 720]]:
		var swing_def: AbilityDef = ContentLibrary.find(&"ability", int(row[0])) as AbilityDef
		_check(swing_def.wind_up_ms == int(row[1]), "%s winds up %d ms" % [swing_def.display_name, swing_def.wind_up_ms])
	for id: int in [40017, 40018, 40020]:
		var swing_def: AbilityDef = ContentLibrary.find(&"ability", id) as AbilityDef
		var hand_ms: int = _fastest_hand_ms(foe_set, StringName("ability.%d" % id))
		_check(absi(hand_ms - swing_def.wind_up_ms) <= 60, "%s: the blow at %d ms in its slowed clip, its wind-up %d ms" % [swing_def.display_name, hand_ms, swing_def.wind_up_ms])
	# A TELL YOU CAN READ (Luke, 2026-11-13: the backswing could not be parried; his presses came 200-400 ms early):
	# through the first half of a foe's wind-up its sword hand is held WIDE, 40 degrees or more off straight ahead, so
	# the blow is plainly still to come. The old backswing (Sword_Heavy_B) began in front and drifted across it.
	for id: int in [40017, 40018, 40020]:
		var swing_def: AbilityDef = ContentLibrary.find(&"ability", id) as AbilityDef
		var wide: float = _least_hand_bearing(foe_set, StringName("ability.%d" % id), swing_def.wind_up_ms / 2)
		_check(wide >= 40.0, "%s: its hand held %.0f degrees or more off straight ahead through the first half of its wind-up" % [swing_def.display_name, wide])
	var old_set: AnimationSet = foe_set.duplicate() as AnimationSet
	old_set.clips = foe_set.clips.duplicate()   # its own map: the loaded set is everyone's
	var old_ref := AnimationClipRef.new()
	old_ref.anim_name = &"extra/Sword_Heavy_B"
	old_ref.speed_scale = 0.621
	old_set.clips[&"ability.40018"] = old_ref
	var old_wide: float = _least_hand_bearing(old_set, &"ability.40018", 350)
	_check(old_wide < 40.0, "NEGATIVE: the old backswing (Sword_Heavy_B) held it only %.0f degrees off: no tell" % old_wide)

	# A SET ROLL. The roll through the real input component and the real movement model, the adventurer's numbers.
	var cfg: MovementConfig = (load("res://game/regents/content/movement/adventurer.tres") as MovementProfileDef).apply_to(MovementConfig.shared())
	var roll_s: float = HotRules.number(&"regents.roll_ms") / 1000.0
	var plain: float = _roll_length(cfg, roll_s, true, false)
	var reversed: float = _roll_length(cfg, roll_s, true, true)
	var old_reversed: float = _roll_length(cfg, roll_s, false, true)
	_check(plain > 2.5 and absf(plain - reversed) < 0.01, "a roll forward goes %.2f m, and %.2f m with S pressed as it begins: a set length" % [plain, reversed])
	_check(old_reversed < plain * 0.6, "NEGATIVE: not held to its way, as before, S cut it to %.2f m" % old_reversed)
	# THE ROLL IS THE FOUNDATION'S (DECISIONS #309, PROGRESS 77): its direction (`RollComponent.direction_for`, the
	# foundation's own suite holds it), the adventurer's roll its content, and what a roll cancels in a fight ours.
	_check(RollComponent.direction_for(Vector2.ZERO, 0.0).is_equal_approx(Vector2(0.0, -1.0))
		and RollComponent.direction_for(Vector2(0.0, 1.0), 0.0).is_equal_approx(Vector2(0.0, 1.0)),
		"a roll goes the way the keys push; with none pressed, forward")
	var dodge: AbilityDef = ContentLibrary.find(&"ability", CombatComponent.DODGE_ID) as AbilityDef
	var adventurer: EntityDefinition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	_check(dodge != null and dodge.rolls and dodge.roll_status != null and dodge.roll_status.status == 101 and dodge.roll_ms_rule == &"regents.roll_ms"
		and not dodge.roll_in_air and dodge.key == &"" and adventurer.dodge_roll == dodge,
		"the dodge roll is the foundation's: it rolls, Rolling (101) for regents.roll_ms, not in the air, on the dash key; the adventurer's")
	_check(RollComponent.length_of(dodge) == int(HotRules.number(&"regents.roll_ms")), "its length the live regents.roll_ms (%d ms)" % RollComponent.length_of(dodge))
	# Ctrl: the foundation's roll taken, the body held to its way, and what it cancels here.
	var input := LocalInputComponent.new()
	input.send_to_server = false
	var act := SpaceTimeActionComponent.new()
	act._def_override = func(_id: int) -> RefCounted: return RollDefRow.new()
	act._reducer_override = func(_ab: int, _tg: int, _aim: Vector3, _pid: int) -> ReducerRequest: return ReducerRequest.new()
	var roller := RollComponent.new()
	roller.ability = dodge
	roller._input = input
	roller._action = act
	roller._grounded_override = func() -> bool: return true
	c._roll = roller
	roller.rolled.connect(c._on_rolled)
	var t0: int = Time.get_ticks_msec()
	var sword_kit: KitDef = KitDef.by_key(&"sword")
	c.kit = sword_kit
	c.swing_ability = sword_kit.light[0]
	c.swing_at_ms = t0
	c.swing_hit_ms = t0 + 500
	c.swing_lock_ms = t0 + 900
	c.swing_canceled = false
	c.queued = {"kind": "light", "slot": 0, "at": t0}
	c.combo_step = 1
	_check(not input.is_forced() and c.roll_until_ms < t0 and c.dodge() >= 0 and input.is_forced() and c.roll_until_ms >= t0 + 500,
		"Ctrl: the foundation's roll is taken, the body held to its way, and the combat component waits on it (roll_until_ms)")
	_check(c.swing_canceled and c.queued.is_empty() and c.combo_step == -1, "a roll in a swing's wind-up cancels it, the queue and the combo (`_on_rolled`)")
	_check(not c.may_start(sword_kit.light[0], 0, Time.get_ticks_msec()), "and nothing swings while it rolls")
	var first: InputFrame = input.sample()
	_check(first.dash and first.move_dir.is_equal_approx(Vector2(0.0, -1.0)), "its first frame dashes forward (no key pressed: the way it faces)")
	Input.action_press(LocalInputComponent.ACTION_BACK)
	var held: bool = true
	for i: int in range(ceili(roll_s * float(Engine.physics_ticks_per_second)) - 1):
		held = held and input.sample().move_dir.is_equal_approx(Vector2(0.0, -1.0))
	var after: InputFrame = input.sample()
	Input.action_release(LocalInputComponent.ACTION_BACK)
	_check(held and not input.is_forced() and after.move_dir.y > 0.5, "S pressed all the roll long: every frame of it goes forward; the frame after it is the key's again")
	c._roll = null
	roller.free()
	act.free()
	input.free()

	# A HIT DEALT AT ONCE AND TAKEN BACK (Luke, 2026-11-12): the health it took comes straight back; shown as the hit
	# undone, not as a heal.
	_check(HitFeedbackComponent.is_taken_back(14.0, 14.0, 180) and HitFeedbackComponent.is_taken_back(4.2, 4.2, HitFeedbackComponent.TAKEN_BACK_MS),
		"a rise the size of the last drop, soon after it: that hit taken back")
	_check(not HitFeedbackComponent.is_taken_back(8.0, 14.0, 180) and not HitFeedbackComponent.is_taken_back(14.0, 14.0, HitFeedbackComponent.TAKEN_BACK_MS + 1)
		and not HitFeedbackComponent.is_taken_back(14.0, 0.0, 10),
		"NEGATIVE: another amount (a rallying cut's 8), the same amount too long after, or with no drop before: a heal")
	var hurt_feed := HitFeedbackComponent.new()
	hurt_feed._on_health_changed(86.0, 100.0, -14.0)
	hurt_feed._on_health_changed(100.0, 100.0, 14.0)
	_check(hurt_feed.shown.size() == 1 and hurt_feed.taken_back == 1, "a hit of 14 shown, then taken back: one number (the hit), no green 14 after it (%s)" % str(hurt_feed.shown))
	hurt_feed._on_health_changed(100.0, 100.0, 8.0)
	_check(hurt_feed.shown.size() == 2 and hurt_feed.taken_back == 1, "a heal after that is a heal: its number shows")
	hurt_feed.free()
	_check(is_equal_approx(HotRules.number(&"regents.hit_at_once"), 1.0), "hits on a player are dealt at once (a hot rule: 0 makes them wait as before)")
	# THE SERVER IS TOLD HOW LATE THIS CLIENT SHOWS A SWING: once, then only when it has moved.
	_check(CombatComponent.seen_delay_moved(-1, 0) and not CombatComponent.seen_delay_moved(40, 44) and CombatComponent.seen_delay_moved(40, 52) and CombatComponent.seen_delay_moved(40, 30),
		"the delay is told as it joins, and again when it has moved %d ms" % CombatComponent.SEEN_TELL_STEP_MS)
	c._local_input = null
	c._action = null
	_check(c._tell_seen_delay(100000) and c.seen_delay_told == CombatComponent.seen_delay_ms() and not c._tell_seen_delay(100000 + CombatComponent.SEEN_TELL_EVERY_MS + 1),
		"told once (%d ms here); not again while it stays" % c.seen_delay_told)
	c.free()
	_check(is_equal_approx(HotRules.number(&"regents.roll_late_ms"), 50.0) and is_equal_approx(HotRules.number(&"regents.hit_hold_slack_ms"), 40.0),
		"the roll's late grace and the hit's wait slack are hot rules (50 and 40 ms)")


## THE CROSSHAIR, FOUND (step 60): the camera's ray against real bodies and ground. On a body, an arrow's arc is
## corrected onto it; beside it (the ground behind), the arrow leaves straight for that point: an arc to the far
## point would climb over what is near (the combat playtest's free shot, half a meter beside the dummy, flew over it).
func _run_crosshair() -> void:
	print("== regents: the crosshair ==")
	var at := Vector3(600.0, 300.0, 600.0)   # away from every other suite's level
	var stage := Node3D.new()
	add_child(stage)
	stage.position = at
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(200.0, 1.0, 200.0)
	ground_shape.shape = slab
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(ground_shape)
	stage.add_child(ground)
	var wolf := SpaceTimeEntity.new()   # somebody: an entity with health, as a foe is
	wolf.collision_layer = SpaceTimeEntity.ENTITY_MASK
	wolf.collision_mask = 0
	var wolf_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.0
	wolf_shape.shape = capsule
	wolf_shape.position = Vector3(0.0, 0.5, 0.0)
	wolf.add_child(wolf_shape)
	stage.add_child(wolf)
	wolf.entity_id = 9871
	wolf.position = Vector3(0.5, 0.0, -10.0)
	wolf.add_runtime_component(SpaceTimeHealthComponent.new())
	EntityRegistry.register(9871, wolf)
	# A tree: an entity too (a gathering node), with no health: never "somebody".
	var tree := SpaceTimeEntity.new()
	tree.collision_layer = SpaceTimeEntity.ENTITY_MASK
	tree.collision_mask = 0
	var trunk_shape := CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.5
	trunk.height = 6.0
	trunk_shape.shape = trunk
	trunk_shape.position = Vector3(0.0, 3.0, 0.0)
	tree.add_child(trunk_shape)
	stage.add_child(tree)
	tree.entity_id = 9872
	tree.position = Vector3(0.5, 0.0, -60.0)
	EntityRegistry.register(9872, tree)
	var who := Node3D.new()
	stage.add_child(who)
	var c: CombatComponent = CombatComponent.new()
	who.add_child(c)
	c.entity = who
	c.set_process(false)
	# The game's camera: over the right shoulder, the crosshair on the wolf's middle.
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.position = Vector3(0.5, 2.1, 4.4)
	cam.look_at(at + Vector3(0.5, 0.5, -10.0))
	cam.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var on: Vector3 = c.crosshair_point() - at
	_check(c.crosshair_on_body and on.distance_to(Vector3(0.5, 0.5, -10.0)) < 0.6, "the crosshair on a wolf 10 m off: it is on a body, at %s" % on)
	var muzzle: Vector3 = c.muzzle() - at
	var arced: Vector3 = CombatComponent.launch_direction(muzzle, on, 35.0, CombatComponent.ARROW_GRAVITY)
	_check(_shot_miss(muzzle, arced * 35.0, on, CombatComponent.ARROW_GRAVITY) < 0.05, "an arrow's arc is corrected onto it")
	# The wolf steps aside: the same crosshair is on the ground behind where it stood.
	wolf.position = Vector3(3.0, 0.0, -10.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var behind: Vector3 = c.crosshair_point() - at
	_check(not c.crosshair_on_body and absf(behind.y) < 0.05 and behind.z < -12.0, "beside it, the crosshair is on the ground behind (%s): not a body" % behind)
	# The look level at a man 10 m straight ahead of the body: the crosshair, over the right shoulder, passes half a
	# meter beside him (the combat playtest's free shot at the dummy) and meets nothing for 120 m. Sent straight for
	# that far point, a full draw still passes through him; arced to land on it, it goes meters over his head.
	cam.position = Vector3(0.5, 1.5, 4.5)
	cam.rotation = Vector3.ZERO
	await get_tree().process_frame
	var on_tree: Vector3 = c.crosshair_point() - at
	_check(not c.crosshair_on_body and absf(on_tree.z + 59.5) < 0.1, "the look level, past where it stood: the crosshair is on a tree 60 m off, an entity but nobody (%s)" % on_tree)
	tree.position = Vector3(30.0, 0.0, -60.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var far_point: Vector3 = c.crosshair_point() - at
	_check(not c.crosshair_on_body and far_point.z < -100.0 and absf(far_point.y - 1.5) < 0.01, "with no tree: nothing met, the crosshair far along the ray (%.0f m)" % -far_point.z)
	var chest := Vector3(0.0, 1.0, -10.0)
	var straight: Vector3 = CombatComponent.launch_direction(muzzle, far_point, 50.0, 0.0)
	var lobbed: Vector3 = CombatComponent.launch_direction(muzzle, far_point, 50.0, CombatComponent.ARROW_GRAVITY)
	var straight_miss: float = _shot_miss(muzzle, straight * 50.0, chest, CombatComponent.ARROW_GRAVITY)
	var lobbed_miss: float = _shot_miss(muzzle, lobbed * 50.0, chest, CombatComponent.ARROW_GRAVITY)
	_check(straight_miss < 0.4, "an arrow sent straight at the far point passes %.2f m from the middle of the man beside the crosshair: a hit" % straight_miss)
	_check(lobbed_miss > 2.0, "NEGATIVE: arced to land on the far point, it passes %.2f m off, over his head: why the arc is only onto a body" % lobbed_miss)
	# A thing between the camera and the player is never aimed at.
	cam.position = Vector3(0.5, 2.1, 4.4)
	cam.look_at(at + Vector3(0.5, 0.5, -10.0))
	wolf.position = Vector3(0.5, 1.2, 2.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	c.crosshair_point()
	_check(not c.crosshair_on_body, "a body between the camera and the player is not what the crosshair is on")
	EntityRegistry.unregister(9871)
	EntityRegistry.unregister(9872)
	stage.free()


## How near a shot from `from` at `vel` under gravity `g` comes to `to`, stepped a millisecond at a time.
func _shot_miss(from: Vector3, vel: Vector3, to: Vector3, g: float) -> float:
	var best: float = INF
	var p: Vector3 = from
	var v: Vector3 = vel
	for i: int in range(6000):
		best = minf(best, p.distance_to(to))
		v.y -= g * 0.001
		p += v * 0.001
	return best


## How far a roll forward from a standstill goes in `roll_s`: its first frame dashes; `held` holds it to its way
## (the input component's `force_move`, as the combat component asks); `back` presses S from its second frame on.
func _roll_length(cfg: MovementConfig, roll_s: float, held: bool, back: bool) -> float:
	var input := LocalInputComponent.new()
	input.send_to_server = false
	input.dash_once()
	if held:
		input.force_move(Vector2(0.0, -1.0), roll_s)
	var s := MovementState.new()
	s.pos = Vector3(0.0, cfg.ground_y, 0.0)
	s.grounded = true
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	for i: int in range(ceili(roll_s * float(Engine.physics_ticks_per_second))):
		if back and i == 1:
			Input.action_press(LocalInputComponent.ACTION_BACK)
		s = MovementModel.simulate(s, input.sample(), cfg, dt)
	Input.action_release(LocalInputComponent.ACTION_BACK)
	input.free()
	return Vector2(s.pos.x, s.pos.z).length()


## A SHOT ENDS WHERE IT FIRST TOUCHES (Luke, 2026-11-12: a bolt at a moving target "gets redeflected in a random
## direction"): a bolt, a fireball and an arrow flown by real physics into a body that is walking across their path,
## met off its middle. Each stops within a step of where it touched and stays; the hit is still reported. NEGATIVE:
## the same bolt with no `MissileFlight` skids on well past its target.
func _run_shot_stops() -> void:
	print("== regents: a shot ends where it first touches ==")
	for path: String in ["res://game/regents/content/body/bolt.tres", "res://game/regents/content/body/fireball.tres", "res://game/regents/content/body/arrow.tres"]:
		var def: BodyDef = load(path) as BodyDef
		_check(def.forces is MissileFlight, "%s flies by MissileFlight (or a kind of it)" % def.display_name)
		var got: Dictionary = await _fly_at_walker(def)
		_check(bool(got["hit"]), "%s: the hit on the walker is reported" % def.display_name)
		_check(float(got["past"]) < 0.5 and float(got["speed"]) < 0.1,
			"%s: it ends where it touched (%.2f m on from there, %.1f m/s left)" % [def.display_name, float(got["past"]), float(got["speed"])])
	var bare: BodyDef = (load("res://game/regents/content/body/bolt.tres") as BodyDef).duplicate() as BodyDef
	bare.forces = null
	var skid: Dictionary = await _fly_at_walker(bare)
	_check(bool(skid["hit"]) and float(skid["past"]) > 1.0 and float(skid["speed"]) > 1.0,
		"NEGATIVE: the bolt with no MissileFlight skids on past its target (%.2f m on, %.1f m/s left)" % [float(skid["past"]), float(skid["speed"])])


## `def` flown at 30 m/s at a man-sized body walking across its path (as the referee's stand-ins move: placed each
## frame), aimed to meet it off its middle. Says whether a hit on it was reported, and, 20 frames after, how far the
## shot is from where it touched and how fast it still goes.
func _fly_at_walker(def: BodyDef) -> Dictionary:
	var walker := AnimatableBody3D.new()
	walker.sync_to_physics = false
	walker.collision_layer = FlyingBody.PROXY_LAYER
	walker.collision_mask = 0
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = cap
	shape.position.y = 0.9
	walker.add_child(shape)
	get_tree().root.add_child(walker)
	walker.global_position = Vector3(-0.6, 500.0, 0.0)
	var b: FlyingBody = FlyingBody.make(def)
	get_tree().root.add_child(b)
	var hit_at: Array[Vector3] = []
	b.hit.connect(func(o: Object, p: Vector3, _n: Vector3, _s: float) -> void:
		if o == walker and hit_at.is_empty():
			hit_at.append(p))
	b.launch(Vector3(0.0, 501.0, 6.0), Vector3(0.0, 0.0, -30.0), Vector3.ZERO, Vector3.ZERO)
	var after: int = 0
	for i: int in 90:
		walker.global_position.x += 4.0 / 60.0   # walking across, 4 m/s
		await get_tree().physics_frame
		if not hit_at.is_empty():
			after += 1
			if after >= 20:
				break
	# Over the ground only: an arrow stopped in the air then falls, as it should.
	var out: Dictionary = {"hit": not hit_at.is_empty(), "past": 0.0, "speed": Vector2(b.linear_velocity.x, b.linear_velocity.z).length()}
	if not hit_at.is_empty():
		out["past"] = Vector2(b.global_position.x - hit_at[0].x, b.global_position.z - hit_at[0].z).length()
	b.queue_free()
	walker.queue_free()
	await get_tree().physics_frame
	return out
