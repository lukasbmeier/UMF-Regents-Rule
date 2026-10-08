extends Node
## THE OTHER SIDE OF THE LAKE: a second client, watching the fishing playtest's angler.
##
## Every other check of the fishing loop runs inside the process doing the fishing. What makes a
## lake feel SHARED happens in somebody else's: that they see you turn to aim, swing the rod,
## see your float land, and see your catch come out of the water. None of it is visible to the
## angler's own process, so this one runs alongside it (tests/fishing_playtest.sh):
##
##   the turn   the angler, standing still on the dock, turns round to face their aim on THIS
##              screen — it rides on the input frames (`InputFrame.face`), so the module turns
##              the body for everyone (DECISIONS #136)
##   the draw   their rod comes out on THIS screen as it starts on theirs, before their line goes
##              in: their client reports its equip state (`equip_state`, DECISIONS #160)
##   swing      their character plays the cast clip here — announced from the public
##              `fishing_line` row, since the challenge behind it is private
##   float      a float flies out and settles on the lake where the line went in
##   the catch  a splash and a catch leaping out, and no reward jingle: not our catch
##
## Exits 0 once it has seen all of it, 1 on timeout or a failed check.

const TIMEOUT_SEC: float = 200.0
const CAST_CLIP: StringName = &"extra/Fish_Cast"
const WAIT_CLIP: StringName = &"extra/Fish_Cast_Idle"
const DRAW_CLIP: StringName = &"Sword_Enter"
## The playtest looks back at the village (yaw PI) while it charges.
const AIM_BACK_YAW: float = PI

var _passes: int = 0
var _failures: int = 0
var _finished: bool = false

var _level: LakesideLevel = null
var _watched: SpaceTimeEntity = null
var _fishing: FishingComponent = null
var _anim: AnimationDriverComponent = null
var _fx: FishingFx = null
## Every remote angler that has been seen turned round to face the village while standing still.
var _turned: Dictionary[int, bool] = {}
## Every remote angler seen drawing their rod here, from their reported equip state.
var _drew: Dictionary[int, bool] = {}
var _saw_swing: bool = false
var _saw_flight: bool = false
var _landed_on_lake: bool = false
var _ripples_at_cast: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_tree().create_timer(TIMEOUT_SEC).timeout.connect(_on_timeout)
	print("== fishing observer ==")
	_level = get_tree().get_first_node_in_group(LakesideLevel.GROUP) as LakesideLevel
	_check(_level != null, "the observer is at the lakeside too")
	# Find the angler: a remote fisher whose public line goes into the water. Until then, watch
	# every remote angler's heading for the turn.
	while _watched == null and not _finished:
		await get_tree().process_frame
		for id: int in EntityRegistry.all_entity_ids():
			if EntityRegistry.is_local(id):
				continue
			var e: SpaceTimeEntity = EntityRegistry.get_entity(id) as SpaceTimeEntity
			if e == null or e.definition == null or e.definition.kind != 0 or e.body == null:
				continue
			_watch_heading(e)
			_watch_equip(e)
			var f: FishingComponent = e.find_component(FishingComponent) as FishingComponent
			if f != null and f.line_out():
				_watched = e
				_fishing = f
				break
	if _finished:
		return
	_anim = _watched.find_component(AnimationDriverComponent) as AnimationDriverComponent
	var feedback: FishingFeedback = _watched.find_component(FishingFeedback) as FishingFeedback
	_fx = feedback.fx() if feedback != null else null
	print("   watching entity %d cast to %s" % [_watched.entity_id, _fishing.line_target()])
	_check(_turned.has(_watched.entity_id),
		"before casting, their angler turned round to face the aim, standing still, on this screen")
	var equip: EquipComponent = _watched.find_component(EquipComponent) as EquipComponent
	_check(_drew.has(_watched.entity_id),
		"before their line went in, their angler drew the rod on this screen, as it started on theirs (their equip row)")
	_check(equip != null and equip.reported() and equip.is_equipped(),
		"and their rod is in their hand here, as their row says")
	_check(_fx != null and _fx.rod() != null, "the other angler has a FishingFx and a rod on this client")
	_check(_watched.get_node_or_null(^"Visual/Model") is ModularCharacter,
		"and is dressed in one of the game's looks here too")
	if _fx == null or _level == null:
		_finish()
		return
	_ripples_at_cast = _level.water().ripples_started()

	# Watch the cast play out: the swing, the float in the air, the float on the water.
	var settle_by: int = Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < settle_by:
		# PLAYING, not merely pointed at: the action node is built aimed at the interact clip, so
		# `action_clip()` alone reads Fish_Cast before anything has been announced.
		if _anim != null and _anim.action_playing() and _anim.action_clip() == CAST_CLIP:
			_saw_swing = true
		if _fx.state() == FishingFx.State.WINDUP or _fx.state() == FishingFx.State.FLYING:
			_saw_flight = true
		if _fx.state() == FishingFx.State.FLOATING:
			var fp: Vector3 = _fx.float_position()
			_landed_on_lake = _level.is_water(fp) and absf(fp.y - _level.water_y()) < 0.15 \
				and Vector2(fp.x, fp.z).distance_to(Vector2(_fishing.line_target().x, _fishing.line_target().z)) < 0.5
			break
		await get_tree().process_frame
	_check(_saw_swing, "their character swung the rod on this screen (the cast clip played)")
	_check(_saw_flight, "their float left the rod and flew")
	_check(_landed_on_lake, "and settled on the lake where their line went in (%s)" % _fx.float_position())
	_check(_fx.count(&"plop") == 1, "with one plop (%d)" % _fx.count(&"plop"))
	_check(_level.water().ripples_started() > _ripples_at_cast, "and a ripple on the water")

	# Then wait for their catch — watching them hold the rod out while their line is in the water
	# (DECISIONS #144: the waiting pose, shown from their PUBLIC line row).
	var saw_waiting: bool = false
	# THEIR FIGHT, SHOWN (DECISIONS #170): their client reports it, and it is drawn here: the heave,
	# the float dragged in, the tell ring.
	var saw_fight: bool = false
	var most_heave: float = 0.0
	var their_feedback: FishingFeedback = _watched.find_component(FishingFeedback) as FishingFeedback
	while _fx.count(&"splash") == 0 and not _finished:
		if _anim != null and _anim.pose_clip() == WAIT_CLIP and _anim.pose_weight() > 0.9:
			saw_waiting = true
		if not _fishing.shown_fight().is_empty() and _fx.state() == FishingFx.State.FIGHTING and _fx.tell_visible():
			saw_fight = true
		if their_feedback != null:
			most_heave = maxf(most_heave, their_feedback.heave_shown())
		await get_tree().process_frame
	if _finished:
		return
	_check(saw_waiting, "while their line was out, their angler held the rod out waiting, on this screen")
	_check(saw_fight, "their fight was shown here: the float in a fight, with its tell ring")
	_check(most_heave > 0.1, "and they heaved, on this screen (%.2f of the clip)" % most_heave)
	_check(_fx.count(&"catch_leap") == 1, "their catch leapt out of the water here")
	_check(_fx.count(&"catch") + _fx.count(&"catch_rare") == 0, "with no reward jingle: it is not our catch")
	await get_tree().create_timer(0.8).timeout
	_check(not _fx.line_visible(), "and their line came in with it")
	_check(not _fishing.line_out(), "the public line row is gone here too")
	_finish()


## Facing the village from the dock: the playtest's aim, seen from here.
func _watch_heading(e: SpaceTimeEntity) -> void:
	if _turned.has(e.entity_id):
		return
	# Out on the dock's head and facing back at the village: the only time the playtest's angler
	# does that is while it aims there, standing still — it walked out facing the lake.
	if absf(angle_difference(e.body.rotation.y, AIM_BACK_YAW)) < 0.15 and e.body.global_position.z < 30.0:
		_turned[e.entity_id] = true


## Seen drawing: their reported equip state says the rod is coming out, and the draw plays here.
func _watch_equip(e: SpaceTimeEntity) -> void:
	if _drew.has(e.entity_id):
		return
	var equip: EquipComponent = e.find_component(EquipComponent) as EquipComponent
	var d: AnimationDriverComponent = e.find_component(AnimationDriverComponent) as AnimationDriverComponent
	if equip != null and d != null and equip.reported() and equip.state() == EquipComponent.State.DRAWING 			and d.upper_playing() and d.upper_clip() == DRAW_CLIP:
		_drew[e.entity_id] = true


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		printerr("  FAIL: ", msg)


func _on_timeout() -> void:
	if _finished:
		return
	printerr("  FAIL: the observer did not see a cast and a catch within %.0fs%s"
		% [TIMEOUT_SEC, "" if _watched == null else " (it saw the cast)"])
	_failures += 1
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("\nobserver: %d passed, %d failed" % [_passes, _failures])
	AppExit.quit(get_tree(), 1 if _failures > 0 else 0)
