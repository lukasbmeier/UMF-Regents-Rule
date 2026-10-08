class_name FishingFeedback extends SpaceTimeComponent
## GENRE CODE. Turns what `FishingComponent` knows into what `FishingFx` shows — for every angler,
## on every client.
##
## It owns no state of its own and reads no table (ANIMATION_SPEC §7: feedback reads state, it
## never produces gameplay). The facts arrive as the fishing component's signals:
##
##   line_changed(out, target, …)  a float went onto the water at `target` — cast it, or just show
##                                 it if it was already there when we arrived — or came out
##   catch_landed                  something came out: splash, the catch in the air, and, for the
##                                 angler who caught it, the reward
##
## and, for the LOCAL angler only, the rig: the aim while charging, the release, the tell as the
## bite comes, the bite itself, and a line lost with nothing on it.
##
## A sidecar draws nothing: it simulates anglers, it does not watch them.

## A line closing and its catch arriving come in the same transaction, in either order. Reeling
## in the float the moment the line row goes would put the splash at the rod tip; this long a
## wait lets a catch claim the float first.
const REEL_GRACE_SEC: float = 0.25
## How fast the float chases where the fight says the catch is (FfC's rig): a pump lands as a
## lurch that eases out — neither a teleport nor a constant-speed slide.
const CHASE_RATE: float = 5.5
## How far past where it was hooked a catch that takes line is drawn, as a share of the cast.
const RUN_PAST: float = 0.25

## THE ANGLER IN THE FIGHT (DECISIONS #144). How far into the heave clip (Fish_Reel: rod forward
## at 0, upright by 0.75) the angler is taken at the top of a pump.
const HEAVE_TOP: float = 0.75
## How fast the rod comes back down after a release: the heave clip played BACKWARDS at this many
## times its own pace (1: as it was animated). It came down in a fixed 0.35 s once, which ran a
## release from the sweet spot back through 1.7 s of the clip at five times its speed (Luke: "it
## plays the heave like 3x speed and looks strange", #156).
const HEAVE_DROP_PACE: float = 1.0
const HEAVE: StringName = &"fishing.heave"
## The time between another angler's reports, before two have arrived to measure it (the slowest
## that report regularly, the rival: too long only slows the first move, too short holds the rod
## still until the second report), and its bounds (a late report holds the pose at the last one
## rather than stretching the span for ever).
const SHOWN_SPAN_SEC: float = 0.5
const SHOWN_SPAN_MIN_SEC: float = 0.1
const SHOWN_SPAN_MAX_SEC: float = 1.0
## While another angler's catch runs or their line is too far out (the states the tell ring shakes
## for), the rod strains: the lift trembles by this much, this many times a second. A run holds the
## load steady, and the angler stood frozen in the heave until it ended (#181).
const STRAIN_LIFT: float = 0.03
const STRAIN_HZ: float = 4.0
## The rod's bend at the top of a pump, before the line's own tension takes over.
const BEND_AT_TOP: float = 0.8
## Turns of the reel's handle per second, winding flat out.
const REEL_TURNS_PER_SEC: float = 2.5
## The rod's bend while a float just sits on the water: the weight of the line.
const BEND_WAITING: float = 0.05
## HOW THE ROD IS HELD (DECISIONS #153, #156) is the animation's business: the rod reads what the
## body plays through the driver, and `rod_grip.tres` says where it sits in each (the cast, the
## waiting pose and the heave included).
## WHERE IT IS WHEN NOT FISHING (#158, #159) is the fisher's EquipComponent: with Away When Idle
## the rod is put away a moment after fishing ends and drawn when it starts; without, it is carried.
## This tells it when the rod is in use, and the rod follows it.

var _fx: FishingFx = null
var _fishing: FishingComponent = null
var _driver: AnimationDriverComponent = null
var _reel_at_msec: int = -1
## Where the float is drawn along the fight: 0 where it was hooked, 1 at the rod. Chases the fight.
var _shown: float = 0.0
## The heave as shown (0..HEAVE_TOP), the reel handle's angle, and the hand on it (0..1).
var _heave: float = 0.0
var _reel_turn: float = 0.0
## The angler's equip state, and whether the rod follows it yet.
var _equip: EquipComponent = null
var _rod_placed: bool = false
## Another angler's float, shown along their line by what their fight shows (#170): metres out.
var _shown_line_m: float = -1.0
## ANOTHER ANGLER'S HEAVE, BETWEEN THEIR REPORTS (DECISIONS #181). They report their rod's load a
## few times a second (the rival twice); the lift is played from one report to the next over the
## time between them, like a remote position, so the pose moves every frame. Taken straight from
## each row it held still and jumped when the next arrived: the rival fought in a slideshow.
var _lift_from: float = 0.0
var _lift_to: float = 0.0
## How far from `_lift_from` to `_lift_to` (0..1), and over how long (the time between reports).
var _lift_t: float = 1.0
var _lift_span: float = SHOWN_SPAN_SEC
## The report last taken (`FishingComponent.shown_serial`), and when it arrived; -1 for none.
var _shown_seen: int = -1
var _shown_seen_msec: int = 0
## Where the strain's tremble is (radians), advanced by each frame's own time.
var _strain_phase: float = 0.0


func required_tables() -> Array[StringName]:
	return []


func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	if SpaceTimeMovementComponent.is_authority_process() or OS.has_feature("dedicated_server"):
		return
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_fishing = ent.find_component(FishingComponent) as FishingComponent
	if _fishing == null:
		push_warning("FishingFeedback: entity %d has no FishingComponent to show" % entity_id)
		return
	if _fx == null:
		_fx = FishingFx.new()
		_fx.name = "FishingFx"
		ent.add_child(_fx)
		_fx.hold_rod(_find_skeleton(ent))
	# Guarded: `rebind()` runs `bind()` again on reconnect, and a second connection would show
	# every cast twice.
	if not _fishing.line_changed.is_connected(_on_line_changed):
		_fishing.line_changed.connect(_on_line_changed)
		_fishing.catch_landed.connect(_on_catch_landed)
		_fishing.cast_released.connect(_on_cast_released)
		_fishing.cast_refused.connect(_on_cast_refused)
		_fishing.bite_started.connect(_on_bite)
		_fishing.line_lost.connect(_on_line_lost)
		_fishing.pumped.connect(_on_pumped)
		_fishing.fight_started.connect(_on_fight_started)
		_fishing.fight_ended.connect(_on_fight_ended)
	_driver = ent.find_component(AnimationDriverComponent) as AnimationDriverComponent
	_equip = ent.find_component(EquipComponent) as EquipComponent
	# The fishing component bound first (tree order) and has already replayed the rows that were
	# true when we arrived. A float already on the water is shown where it is, not cast again.
	if _fishing.line_out():
		_fx.place_at(_fishing.line_target())
	set_process(true)


func _process(delta: float) -> void:
	if _fx == null or _fishing == null:
		return
	if _reel_at_msec >= 0 and Time.get_ticks_msec() >= _reel_at_msec:
		_reel_at_msec = -1
		_fx.reel_in()
	_show_angler(delta)
	if not is_local_authority:
		_show_their_fight(delta)
		return
	match _fishing.rig():
		FishingComponent.Rig.CHARGING:
			var a: Dictionary = _fishing.aim()
			_fx.show_aim(a["arc"] as PackedVector3Array, a["point"] as Vector3, bool(a["valid"]))
		FishingComponent.Rig.WAITING:
			_fx.hide_aim()
			_fx.twitch(_fishing.bite_tell())
		FishingComponent.Rig.FIGHTING:
			_show_fight(delta)
		_:
			if _fx.aim_visible():
				_fx.hide_aim()


# --- API ------------------------------------------------------------------------------------

## The presentation node, for tests and the preview.
func fx() -> FishingFx:
	return _fx


# --- facts ------------------------------------------------------------------------------------

## OUR cast: performed on the button, a round trip before the line row confirms it.
func _on_cast_released(target: Vector3, flight_sec: float) -> void:
	if _fx != null:
		_reel_at_msec = -1
		_fx.cast_to_point(target, FishingFx.RELEASE_SEC, flight_sec)


## OUR CAST, REFUSED after the float was thrown on the button (the bell rang as it went; the server
## has the last word on the phase, the reach and the water): the float comes back. Left out, it
## floated on with nothing behind it, and the rod was put away under a line still running from its
## tip (Luke's picture at the end of a round).
func _on_cast_refused(_why: String) -> void:
	if _fx != null and not _fishing.line_out() and _fishing.rig() == FishingComponent.Rig.READY:
		_reel_at_msec = -1
		_fx.reel_in()


func _on_line_changed(out: bool, target: Vector3, spot: String, is_news: bool) -> void:
	if _fx == null:
		return
	if not out:
		_reel_at_msec = Time.get_ticks_msec() + int(REEL_GRACE_SEC * 1000.0)
		return
	_reel_at_msec = -1
	if is_local_authority and _fx.state() != FishingFx.State.IDLE:
		return   # already cast on the button
	if is_news:
		_fx.cast_to_point(target)
		# Printed so a second client's log can say whether it SAW this angler cast — the part of
		# a shared lake no single process can check.
		print("[Fishing] %d casts into %s" % [entity_id, spot if not spot.is_empty() else "open water"])
	else:
		_fx.place_at(target)


## Where the hooked thing is on the water: from the float's landing point toward the angler as
## the fight's line comes in — past it when it takes line — and off to the side as it wanders.
## The same metres the HUD reads out (`FightSim.line_out_m`), eased (CHASE_RATE).
func _show_fight(delta: float) -> void:
	var f: FightSim = _fishing.fight()
	var ent: Node3D = entity as Node3D
	if f == null or ent == null:
		return
	var start: Vector3 = _fishing.line_target()
	var shore: Vector3 = Vector3(ent.global_position.x, start.y, ent.global_position.z)
	var out: Vector3 = start - shore
	# Never under the angler's feet: it comes in to a rod's length out.
	var near: Vector3 = shore + out.normalized() * minf(1.6, out.length()) if out.length() > 0.01 else shore
	var target: float = 1.0 - f.distance / f.start_distance if f.start_distance > 0.0 else 1.0
	# FfC: "A pump moves the catch in one discrete chunk. Chasing that with the VISUAL rather than
	# smoothing the model is the whole trick: the number jumps, the fish lurches, and it reads as a
	# heave instead of a teleport."
	_shown += (clampf(target, -RUN_PAST, 1.0) - _shown) * minf(delta * CHASE_RATE, 1.0)
	var along: Vector3 = start.lerp(near, _shown)
	var across: Vector3 = Vector3(-out.z, 0.0, out.x).normalized() if out.length() > 0.01 else Vector3.RIGHT
	var pos: Vector3 = along + across * f.lateral * f.params.lateral_range * (1.0 - maxf(_shown, 0.0) * 0.7)
	var running: bool = f.behavior == FightSim.Behavior.RUNNING
	_fx.fight_at(pos, tell_of(f), 1.0 if f.in_perfect() else 0.0,
		1.0 if running or f.is_overloaded() else clampf(f.shake * 0.5, 0.0, 1.0))


## ANOTHER ANGLER'S FIGHT, as they show it (DECISIONS #170): the float dragged in along their line
## to the metres they report, the tell ring in their colour, pulsing in the sweet spot and shaking
## too far or running. Their fight itself is private; this is what they choose to show.
func _show_their_fight(delta: float) -> void:
	var shown: Dictionary = _fishing.shown_fight()
	var ent: Node3D = entity as Node3D
	if shown.is_empty() or not _fishing.line_out() or ent == null:
		_shown_line_m = -1.0
		return
	var start: Vector3 = _fishing.line_target()
	var shore: Vector3 = Vector3(ent.global_position.x, start.y, ent.global_position.z)
	var out: Vector3 = start - shore
	if out.length() < 0.01:
		return
	var want: float = clampf(float(shown["line_m"]), 1.6, out.length() * (1.0 + RUN_PAST))
	_shown_line_m = want if _shown_line_m < 0.0 else _shown_line_m + (want - _shown_line_m) * minf(delta * CHASE_RATE, 1.0)
	var state: int = int(shown["state"])
	var shake: float = 1.0 if state == FishingComponent.Shown.FAR or state == FishingComponent.Shown.RUNNING else 0.0
	_fx.fight_at(shore + out.normalized() * _shown_line_m, tell_shown(state),
		1.0 if state == FishingComponent.Shown.SWEET else 0.0, shake)


## The tell ring's colour for a fight state another angler shows.
static func tell_shown(state: int) -> Color:
	match state:
		FishingComponent.Shown.RUNNING:
			return FishingFx.TELL_RUN
		FishingComponent.Shown.FAR:
			return FishingFx.TELL_OVER
		FishingComponent.Shown.SWEET:
			return FishingFx.TELL_PERFECT
		FishingComponent.Shown.BAND:
			return FishingFx.TELL_BAND
	return FishingFx.TELL_CALM


## THE ANGLER, shown from what the rig knows (ANIMATION_SPEC §7: presentation reads state). In our
## own fight: the heave follows the rod's load and eases back down after a release, the reel's
## handle turns with the winding (the left hand holds it whenever a two-handed animation shows:
## the rod's own rule, `FishingRod.two_handed`), the rod bends with the line's tension, and the
## line shows its strain and its slack. With a line out and nothing on it — ours
## or another player's, whose line is public — the angler holds the waiting pose. Otherwise the
## body is its own.
func _show_angler(delta: float) -> void:
	var rod: FishingRod = _fx.rod()
	var f: FightSim = _fishing.fight() if is_local_authority else null
	if f != null and _fishing.rig() == FishingComponent.Rig.FIGHTING:
		# Eased out: the rod answers the press at once and slows toward "too far". Released at the
		# lower edge of ANY catch's sweet spot, the rod is over half way up (0.56 of the top, a spent
		# bluegill's) and bent 0.45.
		var pump: float = pump_of(f)
		var lift: float = 1.0 - (1.0 - pump) * (1.0 - pump)
		var target: float = HEAVE_TOP * lift
		var back_per_sec: float = HEAVE_DROP_PACE / maxf(heave_clip_seconds(), 0.01)
		_heave = target if target > _heave else move_toward(_heave, target, back_per_sec * delta)
		if _driver != null:
			_driver.hold_pose(HEAVE, 1.0, _heave)
		var crank: float = _fishing.crank()
		_reel_turn = fmod(_reel_turn + crank * TAU * REEL_TURNS_PER_SEC * delta, TAU)
		if rod != null:
			rod.set_bend(maxf(f.tension_fraction(), lift * BEND_AT_TOP), _fx.float_position())
		_fx.set_line_strain(f.tension_fraction(), f.slack)
	elif not is_local_authority and _fishing.line_out() and not _fishing.shown_fight().is_empty():
		# Another angler's fight, as they show it (#170): the same heave, from the load they report,
		# played between their reports (#181); the rod bends with it.
		var shown: Dictionary = _fishing.shown_fight()
		var lift_shown: float = _lift_between_reports(shown, delta)
		var straining: bool = int(shown["state"]) == FishingComponent.Shown.FAR \
			or int(shown["state"]) == FishingComponent.Shown.RUNNING
		if straining:
			_strain_phase = fmod(_strain_phase + delta * TAU * STRAIN_HZ, TAU)
			lift_shown = clampf(lift_shown + STRAIN_LIFT * sin(_strain_phase), 0.0, 1.0)
		_heave = HEAVE_TOP * lift_shown
		if _driver != null:
			_driver.hold_pose(HEAVE, 1.0, _heave)
		if rod != null:
			rod.set_bend(lift_shown * BEND_AT_TOP, _fx.float_position())
		var tension: float = 0.9 if int(shown["state"]) == FishingComponent.Shown.FAR else lift_shown * 0.6
		_fx.set_line_strain(tension, 0.0)
	elif _fishing.line_out():
		_heave = 0.0
		_shown_seen = -1
		if _driver != null:
			_driver.hold_pose(&"fishing.wait", 1.0)
		if rod != null:
			rod.set_bend(BEND_WAITING, _fx.float_position())
	else:
		_heave = 0.0
		_shown_seen = -1
		if _driver != null:
			_driver.release_pose()
		if rod != null:
			rod.set_bend(0.0, rod.tip_position())
	if rod != null:
		rod.set_reel_turn(_reel_turn)
	# The rod reads the body's animation itself: where it sits is the grip for what is playing.
	if rod != null and rod.driver == null and _driver != null:
		rod.driver = _driver
	if rod != null:
		_place_rod(rod, delta, f)


## IN THE HAND OR ON THE BACK (#158, #159, #160), through the angler's equip state. Our own fishing
## is our own rig doing anything (or a line out): it says exactly, and our cast waits for the rod
## (`FishingComponent.release_cast`). Another player's equip state follows the row their client
## reports, so their draw plays here as it starts there; the `needed()` below is ignored for them.
## One nobody reports for (an NPC) is decided from what is shown of it: a line out (the public
## row), or its body casting or holding a fishing pose. A cast that arrives already playing with the
## rod away puts it in hand at once, with no draw under it.
func _place_rod(rod: FishingRod, _delta: float, f: FightSim) -> void:
	if _equip == null:
		return
	var fishing: bool = f != null or _fishing.line_out()
	var cast_seen: bool = false
	if is_local_authority:
		fishing = fishing or _fishing.rig() != FishingComponent.Rig.READY
	elif _driver != null:
		cast_seen = _driver.action_playing()
		fishing = fishing or cast_seen or _driver.pose_weight() > 0.01
	if not _rod_placed:
		rod.follow(_equip)
		# Arriving: put away already, unless fishing is under way or the rod is carried (another
		# player's: as their row says, when there is one).
		if _equip.deciding():
			_equip.set_equipped_now(fishing or not _equip.away_when_idle or not rod.can_stow())
		_rod_placed = true
	if cast_seen and not _equip.is_equipped():
		_equip.set_equipped_now(true)
	if fishing:
		_equip.needed()
	elif _driver != null and (_driver.action_playing() or _driver.pose_weight() > 0.01):
		# Our own cast plays on after the rig is done with it (a refused cast, a short one): the rod
		# stays out until the body has finished with it, rather than going away under the cast.
		_equip.in_use()


## How far through a pump the rod is, 0..1: its load against the top of THIS catch's band, so "too
## far" is 1 for a tankard as for a sturgeon. Against the rod's own limit, a light catch's sweet
## spot (a quarter of it) left the heave in the bottom fifth of the clip and the bend at 0.15:
## holding the button showed nothing. The sweet spot's middle still lands anywhere from 0.53
## (a spent bluegill) to 0.91 (a fresh sturgeon) of a pump, so the pose gives no fixed point to
## release at. While the band is down (a run, a snag)
## it is the load against the rod's limit. The line's tint and the gauge stay ABSOLUTE: they warn
## of what the line can take.
static func pump_of(f: FightSim) -> float:
	var top: float = f.band_hi if f.band_hi > 0.01 else f.params.overload_limit
	return clampf(f.load / maxf(top, 0.01), 0.0, 1.0)


## How far into the heave the angler is shown (0..HEAVE_TOP), and the left hand on the reel (0..1).
## For tests.
func heave_shown() -> float:
	return _heave


## The lift (0..1) another angler's reports put the rod at now: the newest report's, reached over the
## time since the one before, starting from wherever the rod is drawn when it arrives (#181).
func _lift_between_reports(shown: Dictionary, delta: float) -> float:
	var now_lift: float = lerpf(_lift_from, _lift_to, _lift_t)
	var serial: int = _fishing.shown_serial()
	if serial != _shown_seen:
		var now: int = Time.get_ticks_msec()
		if _shown_seen < 0:
			now_lift = _heave / HEAVE_TOP   # the first report of a fight starts from the rod as it is
			_lift_span = SHOWN_SPAN_SEC
		else:
			_lift_span = clampf(float(now - _shown_seen_msec) / 1000.0, SHOWN_SPAN_MIN_SEC, SHOWN_SPAN_MAX_SEC)
		_shown_seen = serial
		_shown_seen_msec = now
		_lift_from = now_lift
		_lift_to = 1.0 - pow(1.0 - clampf(float(shown["load"]), 0.0, 1.0), 2.0)
		_lift_t = 0.0
	_lift_t = minf(_lift_t + delta / maxf(_lift_span, 0.001), 1.0)
	return lerpf(_lift_from, _lift_to, _lift_t)


## The heave clip's length in seconds, as this angler's set plays it (0: no clip to show).
func heave_clip_seconds() -> float:
	if _driver == null or _driver.animation_set == null:
		return 0.0
	return AnimationTreeBuilder.clip_length(_driver.animation_set, HEAVE)


func hand_on_reel() -> float:
	var rod: FishingRod = _fx.rod() if _fx != null else null
	return rod.hand_on_reel() if rod != null else 0.0


func _on_fight_ended(state: int) -> void:
	if state == FightSim.State.SNAPPED and _driver != null:
		_driver.play_action(&"fishing.fail")


## The fight's tell, as FishingFx draws it.
static func tell_of(f: FightSim) -> Color:
	if f.behavior == FightSim.Behavior.RUNNING:
		return FishingFx.TELL_RUN
	if f.is_overloaded():
		return FishingFx.TELL_OVER
	if f.in_perfect():
		return FishingFx.TELL_PERFECT
	if f.in_band():
		return FishingFx.TELL_BAND
	return FishingFx.TELL_CALM


func _on_fight_started(_catch_key: String) -> void:
	_shown = 0.0


func _on_pumped(grade: int, metres: float) -> void:
	if _fx != null:
		_fx.pump(grade == FightSim.Grade.PERFECT, metres)


func _on_bite() -> void:
	if _fx != null:
		_fx.bite()


func _on_line_lost(_reason: String) -> void:
	if _fx != null:
		_fx.reel_in()


func _on_catch_landed(c: Dictionary) -> void:
	if _fx == null:
		return
	_reel_at_msec = -1
	var ent: Node3D = entity as Node3D
	var toward: Vector3 = ent.global_position if ent != null else _fx.global_position
	_fx.land_catch(str(c["key"]), float(c["kg"]), toward, is_local_authority)
	var def: Dictionary = FishingData.catch_def(str(c["key"]))
	print("[Fishing] %d landed %s (%.2f kg)" % [entity_id, def.get("name", c["key"]), float(c["kg"])])


# --- lookups ----------------------------------------------------------------------------------

static func _find_skeleton(ent: Node) -> Skeleton3D:
	var model: Node = ent.get_node_or_null(^"Visual/Model")
	if model == null:
		return null
	if model is Skeleton3D:
		return model as Skeleton3D
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		return n as Skeleton3D
	return null
