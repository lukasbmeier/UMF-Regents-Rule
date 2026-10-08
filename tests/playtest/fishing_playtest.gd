extends Node
## FISHING PLAYTEST: can a person actually play this game?
##
## Every reducer in the fishing loop is covered by tests that call them directly. None of those
## touches the part a player uses, and that part has broken on its own before (DECISIONS
## #89-#91). So this playtest refuses to call a reducer to fish: it walks with the movement keys,
## aims with the look angles and plays the cast with the cast button, in the game's own level.
##
##   level        the lakeside is the scene, its bake is loaded, and the server spawned us where
##                the bake says
##   walk         spawn -> down the ramp -> out along the pier to the dock's end, on real keys,
##                prediction and terrain collision
##   aim          holding the button charges; the ring goes out over the water and says where;
##                look back at the village and it is dry land — and the angler TURNS to face
##                wherever the aim is, standing still (DECISIONS #136)
##   cast         letting go sends `cast` to the ring; the float leaves the rod at the clip's
##                release however long the server takes, lands on the lake with a plop and a
##                ripple, and the server's private roll comes back for the bite
##   bite         the float goes under; a press inside the window sets the hook, graded by the
##                client exactly as the module grades it (the twin)
##   fight        THE PUMP, played on the real buttons and the mouse wheel by the probe's ace:
##                load, release in the band, crank the slack, give line on a run. The fight is
##                shown (the float dragged in, the tell ring, a splash a pump), the mouse look is
##                damped while the mouse is the reel; the module REPLAYS the inputs and lands the
##                same catch, with the same combo: named, paid, splashed, leapt, line in
##   reel in      a press BEFORE the bite brings the line back empty, here and in the public row
##   refusal      a cast the server refuses — out of reach, dry land — reaches the player
##   standings    the live board, then the results, name the angler and their best catch
##   shop         shut mid-round (and the server says so), open between rounds, and a buy lands
##   animation    the character is a real rig, animated from the same movement it walks with
##
## A second client (fishing_observer.gd) checks the same cast from the village.
## Driven by tests/fishing_playtest.sh. Exits 0/1.
##
## PICTURES (`--shots=<dir>`, in a window: `SHOTS=<dir> tests/fishing_playtest.sh`): the game as
## the player sees it at every moment above, and round the angler (the camera swung to her side and
## front) while she waits, for a person or an agent to LOOK at. Taken off the last drawn frame, so
## they never hold up an input. Shots mode also leaves a line out when the round ends.

const OVERALL_TIMEOUT_SEC: float = 240.0
const STEP_TIMEOUT_SEC: float = 40.0
## Where the pier meets the dock's head. Walking north from the spawn stops against the head's
## far rail at z = 22.35 (the lakeside suite measures it).
const DOCK_HEAD_Z: float = 27.0
## The deck's height (tools/world/build_lakeside.gd DECK_Y).
const DECK_Y: float = 0.9
## Looking out over the lake from the dock: north, a little above the horizon.
const LAKE_YAW: float = 0.0
const AIM_PITCH: float = 0.25
## How long after the bite the playtest presses: well inside PERFECT (0.30 s).
const REACTION_SEC: float = 0.14

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false

var _entity: SpaceTimeEntity = null
var _body: CharacterBody3D = null
var _input: LocalInputComponent = null
var _fishing: FishingComponent = null
var _session: SessionComponent = null
var _movement: SpaceTimeMovementComponent = null
var _anim: AnimationDriverComponent = null
var _level: LakesideLevel = null
## Highest locomotion blend seen while walking to the dock.
var _peak_blend: float = 0.0
var _hud: Control = null
var _feedback: FishingFeedback = null
var _fx: FishingFx = null

var _released: Array[Vector3] = []
var _bites: int = 0
var _bite_msec: int = -1
var _grades: Array[int] = []
var _lost: Array[String] = []
var _catches: Array[Dictionary] = []
var _refusals: Array[String] = []
var _pumps: Array[int] = []
var _fights_started: int = 0
var _fight_end: int = -1
## The range the aim showed as the button came up.
var _aimed_range: float = -1.0
## Where the pictures go (`--shots=`), and how many have been taken.
var _shots_dir: String = ""
var _shot_n: int = 0


func _ready() -> void:
	# Deliver injected presses on the frame they are made rather than accumulating them.
	Input.use_accumulated_input = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.substr("--shots=".length())
	if not _shots_dir.is_empty():
		if DisplayServer.get_name() == "headless":
			push_warning("--shots: a headless run draws nothing; run it in a window")
			_shots_dir = ""
		else:
			DirAccess.make_dir_recursive_absolute(_shots_dir)
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(OVERALL_TIMEOUT_SEC).timeout.connect(_on_watchdog)
	print("== fishing playtest (simulated latency: %s) ==" % _latency_label())

	if not await _step_bind():
		_finish()
		return
	_step_cursor()
	if not _step_level():
		_finish()
		return
	_shot("spawn")
	await _step_walk_to_dock()
	await _step_aim()
	if await _step_cast():
		await _step_bite_and_hook()
	await _step_reel_in_early()
	await _step_refusals()
	await _step_shop_closed()
	if not _shots_dir.is_empty():
		await _step_line_out_at_the_bell()
	await _step_standings()
	await _step_shop_open()
	_shot("shop")
	_finish()


# --- steps -----------------------------------------------------------------------------

func _step_bind() -> bool:
	var ok: bool = await _until(func() -> bool:
		if EntityRegistry.local_entity_id < 0:
			return false
		var e: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
		return e != null and e.is_bound(), "the local player to spawn and bind")
	_check(ok, "local player spawned and bound")
	if not ok:
		return false
	_entity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	_body = _entity.body
	_input = _entity.find_component(LocalInputComponent) as LocalInputComponent
	_fishing = _entity.find_component(FishingComponent) as FishingComponent
	_session = _entity.find_component(SessionComponent) as SessionComponent
	_movement = _entity.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	_anim = _entity.find_component(AnimationDriverComponent) as AnimationDriverComponent
	_check(_input != null and _fishing != null and _movement != null,
		"the fisher carries input, movement and fishing components")
	if _input == null or _fishing == null or _movement == null:
		return false

	_fishing.cast_released.connect(func(target: Vector3, _flight: float) -> void: _released.append(target))
	_fishing.cast_refused.connect(func(why: String) -> void: _refusals.append(why))
	_fishing.bite_started.connect(func() -> void:
		_bites += 1
		_bite_msec = Time.get_ticks_msec())
	_fishing.hookset_graded.connect(func(grade: int, _reaction: float) -> void: _grades.append(grade))
	_fishing.line_lost.connect(func(why: String) -> void: _lost.append(why))
	_fishing.catch_landed.connect(func(c: Dictionary) -> void: _catches.append(c))
	_fishing.pumped.connect(func(grade: int, _m: float) -> void: _pumps.append(grade))
	_fishing.fight_started.connect(func(_key: String) -> void: _fights_started += 1)
	_fishing.fight_ended.connect(func(state: int) -> void: _fight_end = state)

	_hud = get_parent().get_node_or_null(^"Game/HUD") as Control
	_check(_hud != null, "the real fishing HUD is in the scene")

	_feedback = _entity.find_component(FishingFeedback) as FishingFeedback
	_fx = _feedback.fx() if _feedback != null else null
	_check(_fx != null, "the angler has its fishing presentation (FishingFx)")
	var rod: FishingRod = _fx.rod() if _fx != null else null
	_check(rod != null, "and a rod")
	var hand: BoneAttachment3D = rod.get_parent() as BoneAttachment3D if rod != null else null
	_check(hand != null and hand.bone_name == "hand_r",
		"held in the right hand, so it follows every clip (%s)"
		% (hand.bone_name if hand != null else "not in a hand"))
	# Dressed from the Quaternius packs (ModularCharacter): a real character, not a mannequin.
	var model: Node = _entity.get_node_or_null(^"Visual/Model")
	_check(model is ModularCharacter and (model as ModularCharacter).skeleton() != null,
		"the angler wears one of the game's looks (%s)" % (model.get_class() if model != null else "none"))

	var playing: bool = await _until(func() -> bool:
		return _session != null and _session.get_phase() == SessionComponent.Phase.PLAYING,
		"the session to reach PLAYING")
	_check(playing, "the session is in its PLAYING phase, so casting is allowed")
	return playing


## The shipped scene has to ASK for the cursor, or none of the capture policy matters. Headless
## has no cursor to take, so what is checked here is the request, which is the part that was
## missing: `capture_mouse` defaulted off and no scene turned it on.
func _step_cursor() -> void:
	print("-- cursor --")
	_check(MouseCapture.is_wanted(),
		"the spawned player asks for the mouse cursor (mouse look is impossible without it)")
	_check(_input.capture_mouse, "its input component is the thing asking")
	_check(MouseCapture.is_captured(), "and has it, so the cast button is live")
	var cross: Control = _hud.get_node_or_null(^"Crosshair") as Control if _hud != null else null
	_check(cross != null and cross.draw.is_connected(_hud.draw_crosshair),
		"the HUD draws a crosshair, so the player can see where they are aiming")


func _step_level() -> bool:
	print("-- the lakeside --")
	_level = get_tree().get_first_node_in_group(LakesideLevel.GROUP) as LakesideLevel
	_check(_level != null and _level.bake() != null, "the scene is the lakeside, with its bake loaded")
	if _level == null or _level.bake() == null:
		return false
	var spawn: Vector3 = _level.bake().spawn
	var at: Vector3 = _body.global_position
	print("   spawned at %s; the bake's spawn is %s" % [at, spawn])
	_check(Vector2(at.x, at.z).distance_to(Vector2(spawn.x, spawn.z)) < 1.5,
		"the server put us at the level's spawn, which it read from the same bake")
	_check(not _level.is_water(at), "on dry land")
	return true


func _step_walk_to_dock() -> void:
	print("-- walk to the end of the dock --")
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	_input.set_look(LAKE_YAW, 0.0)
	Input.action_press(&"move_forward")
	var last_z: float = INF
	var stuck: int = 0
	var shot_at: int = Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if shot_at > 0 and Time.get_ticks_msec() >= shot_at:
			shot_at = -1
			_shot("running")
		if _anim != null:
			_peak_blend = maxf(_peak_blend, _anim.speed_blend())
		var z: float = _body.global_position.z
		stuck = stuck + 1 if absf(z - last_z) < 0.002 else 0
		last_z = z
		if z < DOCK_HEAD_Z - 2.0 and stuck > 20:
			break   # against the head's far rail
	Input.action_release(&"move_forward")
	await _frames(30)
	var at: Vector3 = _body.global_position
	_shot("at_the_dock")
	print("   stopped at %s; locomotion blend peaked at %.2f" % [at, _peak_blend])
	_check(at.z < DOCK_HEAD_Z and absf(at.y - DECK_Y) < 0.15,
		"walked down the ramp and out along the pier to the dock head on the movement keys (%s)" % at)
	_check(_anim != null and _anim.is_animating() and _peak_blend > 0.3,
		"animated as moving on the way (%.2f)" % _peak_blend)
	_check(_anim != null and _anim.current_state() == AnimationTreeBuilder.STATE_GROUNDED,
		"and on its feet on the deck")
	_check(_prompt().begins_with("Hold the left mouse button"),
		"the HUD says how to cast: \"%s\"" % _prompt())


## THE AIM, and the bug that started this: the angler turns to face the cast.
func _step_aim() -> void:
	print("-- aim --")
	var heading: float = _movement.get_predicted_state().yaw
	# Look back at the village, standing still: the body stays facing the lake.
	_input.set_look(PI, AIM_PITCH)
	await _frames(20)
	_check(absf(angle_difference(_movement.get_predicted_state().yaw, heading)) < 0.02,
		"looking round at the village, standing still, does not turn the angler")
	_hold(&"fish_cast", true)
	await _frames(20)
	_check(_fishing.rig() == FishingComponent.Rig.CHARGING, "holding the cast button charges")
	_check(absf(angle_difference(_movement.get_predicted_state().yaw, PI)) < 0.02,
		"THE ANGLER TURNS TO FACE THE AIM while it charges (yaw %.2f)" % _movement.get_predicted_state().yaw)
	await _seconds(FishingComponent.CHARGE_SEC)
	_check(not bool(_fishing.aim()["valid"]) and _prompt().contains("dry land"),
		"aimed at the village the ring is on dry land, and the HUD says so: \"%s\"" % _prompt())
	# Back out over the lake, still holding.
	_input.set_look(LAKE_YAW, AIM_PITCH)
	await _frames(20)
	_check(absf(angle_difference(_movement.get_predicted_state().yaw, LAKE_YAW)) < 0.02,
		"and turns back with it to face the lake (yaw %.2f)" % _movement.get_predicted_state().yaw)
	var aim: Dictionary = _fishing.aim()
	var ring: Vector3 = aim["point"]
	_shot("aiming")
	_check(bool(aim["valid"]) and _level.is_water(ring),
		"at full charge the ring is out on the lake (%s, %.0f m)" % [ring, float(aim["range"])])
	_check(_fx != null and _fx.aim_visible(), "and it is drawn: the arc and the ring")
	var spot: Dictionary = aim["spot"] as Dictionary
	_check(_prompt().contains("%.0f m" % float(aim["range"])) and _prompt().begins_with(str(spot.get("name", "Open water"))),
		"the HUD names where it will land and how far: \"%s\"" % _prompt())


func _step_cast() -> bool:
	print("-- cast --")
	var ripples_before: int = _level.water().ripples_started()
	var ring: Vector3 = _fishing.aim()["point"]
	_aimed_range = float(_fishing.aim()["range"])
	var released_msec: int = Time.get_ticks_msec()
	_hold(&"fish_cast", false)
	await _frames(2)
	_shot("cast_released")
	_check(_released.size() == 1 and _released[0].is_equal_approx(ring),
		"letting go throws at the ring (%s)" % str(_released))
	_check(not _input.is_facing_held(), "and frees the body again")
	if _anim != null:
		_check(_anim.action_clip() == &"extra/Fish_Cast",
			"the rod cast plays, the genre's own clip (%s)" % _anim.action_clip())
	var confirmed: bool = await _until(func() -> bool: return not _fishing.cast_info().is_empty(),
		"the server to confirm the cast with its roll")
	_check(confirmed, "the server accepts the cast, and our private roll arrives")
	_check(_refusals.is_empty(), "nothing was refused (%s)" % str(_refusals))
	if not confirmed:
		return false
	var info: Dictionary = _fishing.cast_info()
	print("   on the line: %s, %.2f kg, bites after %.2f s, spot '%s'"
		% [info.get("catch", "?"), float(info.get("kg", 0.0)), float(info.get("bite", 0.0)), info.get("spot", "")])
	_check(Vector2(float(info["x"]), float(info["z"])).distance_to(Vector2(ring.x, ring.z)) < 0.05,
		"the server put the line where the ring was")

	# THE FLOAT. It waits at the rod tip through the wind-up and leaves at the clip's release —
	# measured from the button, so a slow server does not make the float late.
	if _fx == null:
		return true
	var flew_msec: int = -1
	var deadline: int = Time.get_ticks_msec() + 6000
	var flight_shot: bool = false
	while Time.get_ticks_msec() < deadline and _fx.state() != FishingFx.State.FLOATING:
		if flew_msec < 0 and _fx.state() == FishingFx.State.FLYING:
			flew_msec = Time.get_ticks_msec()
		elif not flight_shot and flew_msec >= 0 and Time.get_ticks_msec() > flew_msec + 250:
			flight_shot = true
			_shot("float_flying")
		await get_tree().process_frame
	var release_s: float = (flew_msec - released_msec) / 1000.0 if flew_msec >= 0 else -1.0
	print("   the float left the rod %.2f s after the button came up (the clip releases at %.2f s)"
		% [release_s, FishingFx.RELEASE_SEC])
	_check(flew_msec >= 0 and absf(release_s - FishingFx.RELEASE_SEC) < 0.1,
		"at the clip's release, whatever the latency (%.2f s, want %.2f)" % [release_s, FishingFx.RELEASE_SEC])
	_check(_fx.state() == FishingFx.State.FLOATING, "the float lands and floats")
	await _frames(20)
	_shot("waiting")
	var fp: Vector3 = _fx.float_position()
	_check(Vector2(fp.x, fp.z).distance_to(Vector2(ring.x, ring.z)) < 0.5
			and absf(fp.y - _level.water_y()) < 0.15,
		"on the lake where the ring was (%s)" % fp)
	_check(_fx.line_visible(), "with the line drawn to it")
	_check(_fx.count(&"cast") == 1 and _fx.count(&"plop") == 1,
		"the cast whooshed and the float plopped, once each (%d, %d)" % [_fx.count(&"cast"), _fx.count(&"plop")])
	_check(_level.water().ripples_started() > ripples_before, "and the lake rang where it landed")
	_check(_fishing.line_out() and _fishing.line_target().distance_to(Vector3(ring.x, _level.water_y(), ring.z)) < 0.1,
		"the public line row agrees: out, at the ring")
	return true


func _step_bite_and_hook() -> void:
	print("-- the bite --")
	var bite_s: float = float(_fishing.cast_info().get("bite", 0.0))
	var bit: bool = await _until(func() -> bool: return _bites > 0, "the bite")
	_check(bit, "it bites (the roll said after %.2f s)" % bite_s)
	if not bit:
		return
	_check(_fx != null and _fx.count(&"bite") == 1, "the float goes under")
	await _frames(1)
	_shot("bite")
	_check(_prompt().begins_with("BITE"), "and the HUD shouts it: \"%s\"" % _prompt())
	# A person reacts; so does this, after REACTION_SEC.
	while Time.get_ticks_msec() < _bite_msec + int(REACTION_SEC * 1000.0):
		await get_tree().process_frame
	var coins_before: int = _session.get_coins()
	var rolled: String = str(_fishing.cast_info().get("catch", ""))
	# The press that sets the hook is HELD: in the game it is still down when the fight starts,
	# and the fight must not take it for a pump.
	_hold(&"fish_cast", true)
	await _frames(3)
	_check(_grades.size() == 1 and _grades[0] == FishingData.HookSet.PERFECT,
		"a press %.2f s after the bite is a PERFECT hook-set here (%s)" % [REACTION_SEC, str(_grades)])
	var local_fight: FightSim = await _step_fight()
	var landed: bool = await _until(func() -> bool: return not _catches.is_empty(), "the catch")
	_check(landed, "and the server lands it")
	if not landed:
		return
	var c: Dictionary = _catches[0]
	var def: Dictionary = FishingData.catch_def(str(c["key"]))
	print("   caught %s, %.2f kg, hook-set %d, +%d coins%s" % [def.get("name", c["key"]), float(c["kg"]),
		int(c["hookset"]), int(c["coins"]), " (deadlift)" if bool(c["deadlift"]) else ""])
	# THE TWIN, PLAYED: the grade the player saw the instant they pressed is the module's.
	_check(int(c["hookset"]) == _grades[0], "graded PERFECT by the server too (%d)" % int(c["hookset"]))
	# AND THE FIGHT'S: the module replayed our inputs and got our fight.
	if local_fight != null:
		_check(int(c["best_combo"]) == local_fight.best_combo
				and absf(float(c["fight_s"]) - float(local_fight.ticks) / float(FightSim.tick_hz())) < 0.02,
			"the module's replay of our inputs is our fight: combo %d, %.2f s (ours %d, %.2f s)"
				% [int(c["best_combo"]), float(c["fight_s"]), local_fight.best_combo,
					float(local_fight.ticks) / float(FightSim.tick_hz())])
	_check(not rolled.is_empty() and str(c["key"]) == rolled,
		"what came out is what the roll put on the line (%s, rolled %s)" % [c["key"], rolled])
	_check(not def.is_empty(), "a catch the catalogue knows (%s)" % c["key"])
	_check(int(c["coins"]) > 0 and _session.get_coins() == coins_before + int(c["coins"]),
		"it paid %d coins (%d -> %d)" % [int(c["coins"]), coins_before, _session.get_coins()])
	await _frames(3)
	_shot("landed")
	_check(String(_hud._banner.text).begins_with(str(def.get("name", "?"))),
		"the banner names it: \"%s\"" % String(_hud._banner.text))
	if _fx != null:
		_check(_fx.count(&"splash") == 1 and _fx.count(&"splash_fx") == 1,
			"it broke the water: a splash, heard and seen")
		_check(_fx.count(&"catch_leap") == 1, "and came up out of it toward the angler")
		_check(_fx.count(&"catch") + _fx.count(&"catch_rare") == 1,
			"and the reward played for the one who caught it")
	var clear: bool = await _until(func() -> bool:
		return not _fishing.line_out() and _fishing.rig() == FishingComponent.Rig.READY, "the line to come in")
	_check(clear, "the line came in with it, here and in the public row, and the rod is ready")
	await _frames(30)
	_shot("after_the_catch")


## THE PUMP, on the real input: the probe's ace (FightBot) decides each physics tick what a
## player would press, and presses it — the cast button held and let go, the give button, and
## mouse-wheel notches for the crank, all through Input. Returns the client's own fight.
func _step_fight() -> FightSim:
	print("-- the fight --")
	var started: bool = await _until(func() -> bool:
		return _fishing.rig() == FishingComponent.Rig.FIGHTING, "the fight to start")
	_check(started and _fights_started == 1, "setting the hook starts the fight")
	if not started:
		_hold(&"fish_cast", false)
		return null
	var f: FightSim = _fishing.fight()
	await _frames(2)
	_check(String(_hud._banner.text).begins_with("FISH ON"), "the HUD says so: \"%s\"" % String(_hud._banner.text))
	# THE NUMBER THE AIM PROMISED. Reported: "the aim said 42 m, and when it bit it said 8". The
	# fight counts in its own length's metres (a bluegill's is a third of the cast); the player
	# is told the world's, and the float starts where it landed.
	var said: float = _metres_in(_prompt())
	_check(_aimed_range > 0.0 and absf(said - _aimed_range) < 0.2,
		"the fight starts as far out as the aim said: %.1f m (the aim: %.1f m; the fight's own length, %.1f)"
			% [said, _aimed_range, f.distance])
	var me: Vector3 = _body.global_position
	var hooked_at: Vector3 = _fishing.line_target()
	var float_from: float = -1.0
	if _fx != null:
		var fp0: Vector3 = _fx.float_position()
		float_from = Vector2(fp0.x - me.x, fp0.z - me.z).length()
		_check(Vector2(fp0.x, fp0.z).distance_to(Vector2(hooked_at.x, hooked_at.z)) < 1.0,
			"and the float is where it was hooked, not jumped in (%.2f m from it)"
				% Vector2(fp0.x, fp0.z).distance_to(Vector2(hooked_at.x, hooked_at.z)))
	# Written in the fishing component's _process: in a window, two physics frames can both run
	# before any _process does (a frame that took a picture), so wait for one.
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_equal_approx(_input.look_scale, FishingComponent.FIGHT_LOOK_SCALE),
		"and the mouse becomes the reel: looking around is damped to %.2f" % _input.look_scale)
	var saw_prompt: String = ""
	var saw_tell: bool = false
	var saw_gauge: bool = false
	var most_heave: float = 0.0
	var most_hand: float = 0.0
	var most_bend: float = 0.0
	var holding: bool = true
	var giving: bool = false
	var wheel_every: int = 0
	var deadline: int = Time.get_ticks_msec() + 90000
	# Shots mode: a picture every 0.9 s, the camera swung round her (behind, right, front, left) a
	# moment before each. Looking about does not turn her: facing is only held while charging.
	var next_shot: int = Time.get_ticks_msec() + 500
	var fight_shots: int = 0
	var swung: bool = false
	var look_yaw: float = _input.get_look_yaw()
	var look_pitch: float = _input.get_look_pitch()
	var sides: Array[float] = [0.0, -PI * 0.5, PI, PI * 0.5]
	var side_names: Array[String] = ["back", "right", "front", "left"]
	while _fishing.rig() == FishingComponent.Rig.FIGHTING and Time.get_ticks_msec() < deadline:
		if not _shots_dir.is_empty() and fight_shots < 12:
			if not swung and Time.get_ticks_msec() >= next_shot - 400:
				swung = true
				_input.set_look(look_yaw + sides[fight_shots % 4], 0.1)
			if Time.get_ticks_msec() >= next_shot:
				_shot("fight_%02d_%s" % [fight_shots + 1, side_names[fight_shots % 4]])
				fight_shots += 1
				next_shot += 900
				swung = false
		var d: PackedInt32Array = FightBot.decide(FightBot.Kind.ACE, f)
		if (d[0] == 1) != holding:
			holding = d[0] == 1
			_hold(&"fish_cast", holding)
		if (d[1] == 1) != giving:
			giving = d[1] == 1
			_hold(&"fish_give", giving)
		wheel_every = (wheel_every + 1) % 4
		if d[2] > 0 and wheel_every == 0:
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			Input.parse_input_event(wheel)
		if saw_prompt.is_empty() and _prompt().contains(" m"):
			saw_prompt = _prompt()
		saw_tell = saw_tell or (_fx != null and _fx.tell_visible())
		# THE PICTURE (DECISIONS #144): the rod-and-reel gauge, the angler heaving and winding.
		saw_gauge = saw_gauge or (_hud.reel_gauge() != null and _hud.reel_gauge().visible)
		if _feedback != null:
			most_heave = maxf(most_heave, _feedback.heave_shown())
			most_hand = maxf(most_hand, _feedback.hand_on_reel())
		if _fx != null and _fx.rod() != null:
			most_bend = maxf(most_bend, _fx.rod().bend())
		await get_tree().physics_frame
	_hold(&"fish_cast", false)
	_hold(&"fish_give", false)
	if not _shots_dir.is_empty():
		_input.set_look(look_yaw, look_pitch)
	if _fx != null and float_from > 0.0:
		var fp1: Vector3 = _fx.float_position()
		var float_to: float = Vector2(fp1.x - me.x, fp1.z - me.z).length()
		_check(float_to < 0.5 * float_from,
			"the float was brought in: %.1f m out when hooked, %.1f m at the end" % [float_from, float_to])
	print("   %s in %.1f s: %d pumps (%d perfect), best combo %d, %d runs, peak tension %.2f"
		% [FightSim.State.keys()[f.state], float(f.ticks) / float(FightSim.tick_hz()), f.pumps_total,
			f.pumps_good, f.best_combo, f.runs, f.peak_tension])
	_check(f.state == FightSim.State.LANDED and _fight_end == FightSim.State.LANDED,
		"played on the real buttons and the wheel, the fight is won (%s)" % FightSim.State.keys()[f.state])
	_check(_pumps.size() == f.pumps_total and f.pumps_total >= 1 and f.pumps_good >= 1,
		"pump by pump: %d released, %d perfect" % [f.pumps_total, f.pumps_good])
	_check(not saw_prompt.is_empty(), "the HUD talked the player through it: \"%s\"" % saw_prompt)
	_check(saw_tell and _fx.count(&"fight") == 1 and _fx.count(&"pump") == f.pumps_total,
		"the water showed it: the tell ring round the catch, a churn a pump (%d)" % _fx.count(&"pump"))
	_check(saw_gauge, "the rod-and-reel gauge was up for the fight")
	# Whatever was hooked: the lift follows the load against the catch's OWN band, so a perfect
	# release has the rod over half way up and bent over 0.4 (at least 0.56 and 0.45, a spent
	# bluegill's). Against the rod's limit a tankard showed 0.15 of the clip, and this failed.
	_check(most_heave > 0.5 * FishingFeedback.HEAVE_TOP and most_hand > 0.99 and most_bend > 0.4,
		"and the angler showed it: heaved the rod (%.2f of the clip), wound the reel with the left hand (%.2f), the rod bent (%.2f)"
			% [most_heave, most_hand, most_bend])
	await _frames(2)
	_check(_hud.reel_gauge() != null and not _hud.reel_gauge().visible,
		"and the gauge goes when the fight does")
	_check(_fishing.rig() == FishingComponent.Rig.RESOLVING or _fishing.rig() == FishingComponent.Rig.READY,
		"and the result went to the server (%s)" % FishingComponent.Rig.keys()[_fishing.rig()])
	await _seconds(FishingComponent.LOOK_RESTORE_SEC + 0.2)
	_check(is_equal_approx(_input.look_scale, 1.0), "the mouse is the camera's again (%.2f)" % _input.look_scale)
	return f


## A press before the bite brings the line back empty — the other half of the rig.
func _step_reel_in_early() -> void:
	print("-- reel in before the bite --")
	var caught: int = _catches.size()
	_lost.clear()
	_hold(&"fish_cast", true)
	await _seconds(FishingComponent.CHARGE_SEC + 0.1)
	_hold(&"fish_cast", false)
	var floating: bool = await _until(func() -> bool:
		return _fishing.rig() == FishingComponent.Rig.WAITING, "the second float to land")
	_check(floating, "a second cast lands and waits (rig %s, refused %s, lost %s, released %d)"
		% [FishingComponent.Rig.keys()[_fishing.rig()], str(_refusals), str(_lost), _released.size()])
	if not floating:
		return
	await _press(&"fish_cast")
	_check(_lost.size() == 1 and _lost[0].contains("reeled in"), "pressing now reels it in: %s" % str(_lost))
	var gone: bool = await _until(func() -> bool: return not _fishing.line_out(), "the line row to go")
	_check(gone, "and the server takes the line out of the water for everyone")
	await _seconds(1.0)
	_check(_catches.size() == caught, "with nothing on it")


## A refusal has to reach the player. Sent by hand, because the ring correctly never offers
## either of these.
func _step_refusals() -> void:
	print("-- casts the server refuses --")
	var at: Vector3 = _body.global_position
	_refusals.clear()
	_fishing.request_cast(Vector3(at.x, 0.0, at.z - 90.0))
	var far: bool = await _until(func() -> bool: return not _refusals.is_empty(), "a refusal for reach")
	_check(far and _refusals[0].contains("further than"), "90 m out is further than the rod reaches: %s" % str(_refusals))
	await _frames(2)
	_check(far and String(_hud._banner.text).contains("further"),
		"and the player SEES it: \"%s\"" % String(_hud._banner.text))
	_refusals.clear()
	_fishing.request_cast(Vector3(at.x, 0.0, at.z + 12.0))   # back along the pier
	var dry: bool = await _until(func() -> bool: return not _refusals.is_empty(), "a refusal for dry land")
	_check(dry and _refusals[0].contains("dry land"), "the pier behind us is dry land: %s" % str(_refusals))


## THE SHOP, PLAYED. The round loop only means something if what you earn buys something, and
## the phase gate is the whole of its integrity — a rod bought mid-cast would change a cast
## already in the water. So this presses the key in the wrong phase first and checks the refusal
## ARRIVES, then in the right one and checks the tier moved (DECISIONS #91).
func _step_shop_closed() -> void:
	print("-- the shop, mid-round --")
	var gear: GearComponent = _entity.find_component(GearComponent) as GearComponent
	_check(gear != null, "the angler carries a gear component")
	if gear == null or _session == null:
		return
	_check(gear.rod_tier() == 0, "starting on the base rod (%d)" % gear.rod_tier())
	var refusals: Array[String] = []
	gear.purchase_refused.connect(func(reason: String) -> void: refusals.append(reason))
	var buys: Array[int] = []
	gear.purchase_succeeded.connect(func(kind: int) -> void: buys.append(kind))
	_check(not _prompt().begins_with("SHOP"), "mid-round the HUD does not offer the shop: \"%s\"" % _prompt())
	await _press(&"shop_buy_1")
	await _frames(6)
	_check(refusals.is_empty() and buys.is_empty(),
		"and the key does nothing, rather than firing a purchase the server would refuse")
	gear.request_buy(GearComponent.Kind.ROD)
	var refused: bool = await _until(func() -> bool: return not refusals.is_empty(),
		"the server to refuse a purchase made mid-round")
	_check(refused and refusals[0].to_lower().contains("between rounds"),
		"asked anyway, the server refuses and says why: \"%s\"" % (refusals[0] if refused else ""))
	_check(gear.rod_tier() == 0, "the tier did not move (%d)" % gear.rod_tier())


## WHO WON. While the round runs, a live board; when it ends, the results. Both are built from
## what the entities already hold (FishingStandings).
func _step_standings() -> void:
	print("-- the live board --")
	await _frames(30)   # the board is rebuilt every 0.25 s
	var board: Control = _hud.get_node(^"Board") as Control
	var results: Control = _hud.get_node(^"Results") as Control
	_check(board.visible and not results.visible,
		"while the round is played the live leaderboard is up, and the results are not")
	var mine: Dictionary = _my_standing()
	_check(String(mine.get("name", "")) == PLAYER_NAME,
		"the local player is on it, under the name they chose (%s)" % mine.get("name", ""))
	_check(int(mine.get("score", -1)) == _session.get_score() and _session.get_score() > 0,
		"with the score the server settled on (%d, session says %d)" % [int(mine.get("score", -1)), _session.get_score()])
	var npcs: Array[int] = []
	for row: Dictionary in _hud.standings():
		var e: SpaceTimeEntity = EntityRegistry.get_entity(int(row["entity_id"])) as SpaceTimeEntity
		if e != null and e.definition != null and e.definition.kind != 0:
			npcs.append(int(row["entity_id"]))
	_check(npcs.is_empty(), "and only anglers are ranked: no NPC rival listed (%s)" % str(npcs))

	# Only NOW ask the harness to end the round — it watches for this exact line.
	print("-- show the results --")
	var over: bool = await _until(func() -> bool: return _session.get_phase() == SessionComponent.Phase.RESULTS,
		"the session to reach RESULTS")
	_check(over, "the round ends")
	if not over:
		return
	await _frames(30)
	_shot("results")
	await _shots_around("results")
	_check(results.visible and not board.visible, "and the results replace the live board")
	_check(_hud.sfx_count(&"round_end") == 1, "on a bell (%d)" % _hud.sfx_count(&"round_end"))
	var winner: String = String((_hud.get_node(^"Results/VBox/Winner") as Label).text)
	_check(winner == "You win with %d points!" % _session.get_score(),
		"the only angler in the round is told they won: \"%s\"" % winner)
	mine = _my_standing()
	var this_round: Array[Dictionary] = _fishing.catches_in(_session.get_session_id(), _session.get_round())
	_check(int(mine.get("catches", -1)) == this_round.size() and this_round.size() == _catches.size(),
		"the catch count is this round's catches (%d)" % int(mine.get("catches", -1)))
	var caught: Dictionary = _catches[0] if not _catches.is_empty() else {}
	_check(str(mine.get("best_catch", "")) == str(caught.get("key", "-"))
			and is_equal_approx(float(mine.get("best_kg", 0.0)), float(caught.get("kg", -1.0))),
		"and the best catch is the one that was landed (%s)" % str(mine))
	var best_text: String = "%s %.2f kg" % [FishingData.catch_def(str(caught.get("key", ""))).get("name", "?"),
		float(caught.get("kg", 0.0))]
	_check(_grid_has(_hud.get_node(^"Results/VBox/Grid") as GridContainer, best_text),
		"the panel SHOWS it by name: \"%s\"" % best_text)
	_check(_grid_has(_hud.get_node(^"Results/VBox/Grid") as GridContainer, PLAYER_NAME + "  (you)"),
		"and marks which row is you")
	_check(_prompt().begins_with("Round over"), "the prompt says the round is over: \"%s\"" % _prompt())


## THE SHOP, OPEN. Continues `_step_shop_closed`: the same key, in the phase that allows it.
func _step_shop_open() -> void:
	print("-- the shop, between rounds --")
	var gear: GearComponent = _entity.find_component(GearComponent) as GearComponent
	if gear == null or _session == null:
		_check(false, "the angler carries a gear component")
		return
	var refusals: Array[String] = []
	gear.purchase_refused.connect(func(reason: String) -> void: refusals.append(reason))
	var buys: Array[int] = []
	gear.purchase_succeeded.connect(func(kind: int) -> void: buys.append(kind))
	# Only NOW ask the harness to open the shop — it watches for this exact line.
	print("-- open the shop --")
	var open_now: bool = await _until(func() -> bool: return _session.get_phase() == SessionComponent.Phase.SHOP,
		"the session to reach the SHOP phase")
	_check(open_now, "the shop opens between rounds")
	if not open_now:
		return
	await _frames(4)   # the prompt is repainted in _process, a frame after the phase lands
	_check(_prompt().begins_with("SHOP") and _prompt().contains(gear.next_name(GearComponent.Kind.ROD)),
		"and the HUD offers rod, reel and line by name and price: \"%s\"" % _prompt())
	# FfC's gate, said where it is bought: the next rod names the water it reaches (#143).
	var opens: PackedStringArray = FishingData.spots_opened_by(gear.rod_tier() + 1, _level.bake())
	_check(not opens.is_empty() and _prompt().contains("reaches %s" % ", ".join(opens)),
		"and says which water the next rod reaches (%s)" % ", ".join(opens))
	var coins: int = _session.get_coins()
	var cost: int = gear.next_cost(GearComponent.Kind.ROD)
	var reach_before: float = FishingData.max_cast_m(gear.rod_tier())
	print("   %d coins, the next rod costs %d" % [coins, cost])
	await _press(&"shop_buy_1")
	if coins >= cost:
		var bought: bool = await _until(func() -> bool: return gear.rod_tier() > 0, "the rod upgrade to arrive")
		_check(bought, "pressing 1 in the shop buys a rod (tier %d, %s)" % [gear.rod_tier(), gear.item_name(GearComponent.Kind.ROD)])
		var told: bool = await _until(func() -> bool: return not buys.is_empty(), "the purchase confirmation")
		_check(told, "and the client is told it landed, so the HUD can say so")
		_check(_session.get_coins() == coins - cost,
			"the coins were spent, once: %d -> %d" % [coins, _session.get_coins()])
		_check(_hud.sfx_count(&"coin") == 1, "with the sound of money (%d)" % _hud.sfx_count(&"coin"))
		_check(FishingData.max_cast_m(gear.rod_tier()) > reach_before,
			"and the new rod reaches further (%.0f m -> %.0f m)" % [reach_before, FishingData.max_cast_m(gear.rod_tier())])
	else:
		var told: bool = await _until(func() -> bool: return not refusals.is_empty(),
			"the server to refuse a purchase we cannot afford")
		_check(told, "a rod we cannot afford is refused rather than silently ignored")
	await _frames(20)
	_check((_hud.get_node(^"Results") as Control).visible, "the results stay on screen while the shop is open")
	var footer: String = String((_hud.get_node(^"Results/VBox/Footer") as Label).text)
	_check(footer.begins_with("Shop open"), "and say the shop is open: \"%s\"" % footer)


## SHOTS MODE ONLY: a line on the water when the round ends (Luke's picture of the rod on her back
## with the line still running from its tip to the float).
func _step_line_out_at_the_bell() -> void:
	print("-- a line out at the bell --")
	_hold(&"fish_cast", true)
	await _seconds(FishingComponent.CHARGE_SEC + 0.1)
	_hold(&"fish_cast", false)
	var floating: bool = await _until(func() -> bool:
		return _fishing.rig() == FishingComponent.Rig.WAITING, "the float to land")
	await _shots_around("line_out_waiting")


# --- helpers -----------------------------------------------------------------------------

## A picture of what the player sees, off the last drawn frame (`--shots=`).
func _shot(label: String) -> void:
	if _shots_dir.is_empty():
		return
	_shot_n += 1
	var path: String = "%s/%02d_%s.png" % [_shots_dir, _shot_n, label]
	get_viewport().get_texture().get_image().save_png(path)
	print("   shot: ", path)


## Pictures from behind, her right, her front and her left: the camera swung round her (looking
## about; facing is only held while charging, so she does not turn), then put back.
func _shots_around(label: String) -> void:
	if _shots_dir.is_empty() or _input == null:
		return
	var yaw: float = _input.get_look_yaw()
	var pitch: float = _input.get_look_pitch()
	for side: Array in [[0.0, "back"], [-PI * 0.5, "right"], [PI, "front"], [PI * 0.5, "left"]]:
		_input.set_look(yaw + float(side[0]), 0.1)
		await _frames(12)
		_shot("%s_%s" % [label, side[1]])
	_input.set_look(yaw, pitch)
	await _frames(6)

## The harness launches with this name, so the standings can be checked against it.
const PLAYER_NAME: String = "Playtester"


func _my_standing() -> Dictionary:
	for row: Dictionary in _hud.standings():
		if bool(row["is_local"]):
			return row
	return {}


func _grid_has(grid: GridContainer, text: String) -> bool:
	for c: Node in grid.get_children():
		var l: Label = c as Label
		if l != null and l.text == text:
			return true
	return false


## Hold or let go of an action through the real input system, as a mouse button would.
func _hold(action: StringName, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	Input.parse_input_event(ev)


## A real key press, through the real input system: down one frame, up the next.
func _press(action: StringName) -> void:
	_hold(action, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_hold(action, false)
	await get_tree().process_frame


## The "12.3 m" at the end of a HUD line, or -1.
static func _metres_in(text: String) -> float:
	var re := RegEx.create_from_string("([0-9]+(?:\\.[0-9]+)?) m$")
	var m: RegExMatch = re.search(text)
	return float(m.get_string(1)) if m != null else -1.0


## What the HUD is telling the player right now.
func _prompt() -> String:
	return "" if _hud == null else String(_hud._prompt.text)


func _frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame


## Wait, then land on a physics frame. Timers fire AFTER the frame's `_process` calls, so a press
## made straight off one is seen by nobody: `is_action_just_released` is keyed to the frame it
## arrived in, and that frame's `_process` has already run. A real mouse button arrives at the
## top of a frame; this puts the next injected press there too.
func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
	await get_tree().physics_frame


func _latency_label() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--latency="):
			return arg.substr("--latency=".length()) + " ms round trip"
	return "%d ms round trip" % SpaceTimeSync.get_simulated_latency().x


func _until(pred: Callable, what: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(STEP_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	printerr("  TIMEOUT after %.0fs waiting for %s" % [STEP_TIMEOUT_SEC, what])
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_watchdog() -> void:
	if _finished:
		return
	printerr("  FAIL: playtest exceeded %.0fs overall" % OVERALL_TIMEOUT_SEC)
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for a: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"fish_cast"]:
		Input.action_release(a)
	print("\n%d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
