class_name FishingFx extends Node3D
## GENRE CODE. Everything fishing looks and sounds like, for one angler: the rod in their hand,
## the aim arc and the ring where the float will land, the line and float, the tell and the bite,
## a catch leaving the water, and the sounds of each.
##
## PRESENTATION ONLY (hard rule 11). It has no idea what a challenge or a catch row is; it is
## told "a float was cast to that point", "it is about to bite", "this came out", by
## `FishingFeedback`, which reads those facts off the components. That split is what lets
## `feel_preview.tscn` drive the same code with a keyboard and no server, and what lets a
## headless playtest count what was shown.
##
## Built for every angler on every client, local or remote: another player's float on the lake is
## most of what makes the water feel shared. Ripples go to whatever water the level has
## (`LakesideLevel.water()`), found when needed.

enum State { IDLE, WINDUP, FLYING, FLOATING, BITTEN, REELING, FIGHTING }

## When, into the cast clip (extra/Fish_Cast), the rod comes forward and lets the float go.
## Measured off `feel_preview.tscn --scenario=swing`: back over the shoulder until ~0.6 s, past
## vertical by 0.8 s. A float that leaves before this flies out of a rod still pointing behind
## the angler. `FishingComponent.RELEASE_SEC` counts from the same moment.
const RELEASE_SEC: float = 0.68
## A cast seen from outside (another angler's) has no known speed: its flight is timed by range.
const REMOTE_FLIGHT_BASE_SEC: float = 0.5
const REMOTE_FLIGHT_PER_M: float = 0.03
const REEL_SEC: float = 0.35
## Seconds a landed catch spends in the air.
const LEAP_SEC: float = 1.15
const LINE_SEGMENTS: int = 22
## A long line is drawn finer, so where it meets the water is a bend and not a kink.
const LINE_SEGMENTS_MAX: int = 90
const LINE_STEP_M: float = 0.6
## Slack line floats this far above the surface where it lies on the water.
const LINE_ON_WATER: float = 0.02
## Slack line touches down this many metres out per metre the rod tip is above the water.
const LINE_HANG_PER_M: float = 5.0
## How fast the line goes slack after landing, or taut when something pulls (per second, 0..1).
const LINE_SETTLE_RATE: float = 2.5
## The line's own colour, and the metres of a fight's slack that hang it as far as a resting line.
const LINE_COLOR: Color = Color(0.92, 0.94, 0.9, 0.85)
const FIGHT_SLACK_FULL_M: float = 2.0
## Colour-blind safe ramp by rarity (grey, blue, violet, gold, ember) — never red against green
## (ANIMATION_SPEC §7).
const RARITY_COLORS: Array[Color] = [
	Color(0.78, 0.82, 0.86), Color(0.38, 0.68, 1.0), Color(0.78, 0.5, 1.0), Color(1.0, 0.8, 0.25),
	Color(1.0, 0.5, 0.22),
]

## THE FIGHT'S TELLS. FfC's rule: "the catch is the cue, not the meter" — the ring on the water
## around what is hooked says when to let go. Colour-blind safe (never red against green), and
## each also MOVES its own way: the sweet spot pulses and grows, too far shakes.
const TELL_CALM: Color = Color(0.45, 0.62, 0.78, 0.8)
const TELL_BAND: Color = Color(1.0, 0.74, 0.22, 0.9)
const TELL_PERFECT: Color = Color(0.62, 1.0, 1.0, 0.95)
const TELL_OVER: Color = Color(1.0, 0.28, 0.52, 0.95)
const TELL_RUN: Color = Color(1.0, 0.45, 0.18, 0.95)

@export var rod_scene: PackedScene = preload("res://game/fishing/fishing_rod.tscn")
@export var sfx_cast: AudioStream = preload("res://game/fishing/sfx/cast.wav")
@export var sfx_plop: AudioStream = preload("res://game/fishing/sfx/plop.wav")
@export var sfx_splash: AudioStream = preload("res://game/fishing/sfx/splash.wav")
@export var sfx_catch: AudioStream = preload("res://game/fishing/sfx/catch.wav")
@export var sfx_catch_rare: AudioStream = preload("res://game/fishing/sfx/catch_rare.wav")

## Where ripples go when the scene has no fishing level (the feel preview's pond). Unset, they go
## to the level's water.
var ripple_override: Callable = Callable()

var _state: State = State.IDLE
var _rod: FishingRod = null
var _from: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _flight: float = 0.6
var _t: float = 0.0
var _bob_time: float = 0.0
var _twitch: float = 0.0
var _line: MeshInstance3D = null
var _line_mesh: ImmediateMesh = null
var _line_points: PackedVector3Array = PackedVector3Array()
## 0 taut .. 1 slack and lying on the water.
var _slack: float = 0.0
## In a fight: how close the line is to snapping (0..1), and the slack a heave left on it.
var _fight_tension: float = 0.0
var _fight_slack: float = 0.0
var _float: Node3D = null
var _aim: MeshInstance3D = null
var _aim_mesh: ImmediateMesh = null
var _aim_ring: MeshInstance3D = null
var _aim_ok: StandardMaterial3D = null
var _aim_bad: StandardMaterial3D = null
var _voice: AudioStreamPlayer3D = null
var _reward_voice: AudioStreamPlayer3D = null
## What was shown and heard, by name, for tests. Presentation is otherwise only checkable by
## watching it.
var _counts: Dictionary[StringName, int] = {}
var _in_air: int = 0
var _last_leap: Node3D = null
var _tell_ring: MeshInstance3D = null
var _tell_mat: StandardMaterial3D = null
var _fight_pos: Vector3 = Vector3.ZERO
var _fight_pulse: float = 0.0
var _fight_shake: float = 0.0


func _ready() -> void:
	_line_mesh = ImmediateMesh.new()
	_line = MeshInstance3D.new()
	_line.name = "Line"
	_line.mesh = _line_mesh
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = LINE_COLOR
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line.material_override = line_mat
	_line.visible = false
	add_child(_line)

	_float = _make_float()
	_float.visible = false
	add_child(_float)

	_aim_ok = _unshaded(Color(0.45, 0.95, 0.55, 0.9))
	_aim_bad = _unshaded(Color(1.0, 0.4, 0.3, 0.85))
	_aim_mesh = ImmediateMesh.new()
	_aim = MeshInstance3D.new()
	_aim.name = "AimArc"
	_aim.mesh = _aim_mesh
	_aim.top_level = true
	_aim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim.visible = false
	add_child(_aim)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.72
	ring.outer_radius = 0.86
	ring.rings = 32
	ring.ring_segments = 6
	_aim_ring = MeshInstance3D.new()
	_aim_ring.name = "AimRing"
	_aim_ring.mesh = ring
	_aim_ring.top_level = true
	_aim_ring.scale = Vector3(1.0, 0.25, 1.0)
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_ring.visible = false
	add_child(_aim_ring)

	_tell_mat = _unshaded(TELL_CALM)
	_tell_ring = MeshInstance3D.new()
	_tell_ring.name = "TellRing"
	_tell_ring.mesh = ring
	_tell_ring.top_level = true
	_tell_ring.material_override = _tell_mat
	_tell_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tell_ring.visible = false
	add_child(_tell_ring)

	_voice = _make_voice("Voice", -2.0)
	_reward_voice = _make_voice("Reward", 0.0)
	# Updated by hand every frame; interpolating them between physics ticks would only smear.
	for n: Node3D in [_line, _float, _aim, _aim_ring, _tell_ring, self]:
		n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


# --- API ------------------------------------------------------------------------------------

## Put the rod in this skeleton's right hand. Safe to call again.
func hold_rod(skeleton: Skeleton3D) -> bool:
	_rod = FishingRod.in_hand(skeleton)
	if _rod == null:
		_rod = HeldItem.attach(skeleton, rod_scene) as FishingRod
	return _rod != null


func rod() -> FishingRod:
	return _rod


## While charging: the arc the float would fly and the ring where it would land, green over water
## the server will take and red where it will not.
func show_aim(arc: PackedVector3Array, point: Vector3, valid: bool) -> void:
	_aim.visible = arc.size() >= 2
	_aim_ring.visible = true
	var mat: StandardMaterial3D = _aim_ok if valid else _aim_bad
	_aim_ring.material_override = mat
	_aim_ring.global_position = point + Vector3(0.0, 0.03, 0.0)
	_aim_mesh.clear_surfaces()
	if arc.size() >= 2:
		_aim_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for p: Vector3 in arc:
			_aim_mesh.surface_add_vertex(p)
		_aim_mesh.surface_end()


func hide_aim() -> void:
	_aim.visible = false
	_aim_ring.visible = false


func aim_visible() -> bool:
	return _aim_ring.visible


## A float goes out to `target`: it hangs at the rod tip through the wind-up, flies for
## `flight_sec`, and lands. `release_in` is how long until the rod comes forward — RELEASE_SEC for
## a swing starting now, less for one that started a round trip ago on a button.
func cast_to_point(target: Vector3, release_in: float = RELEASE_SEC, flight_sec: float = -1.0) -> void:
	_target = target
	_flight = flight_sec if flight_sec > 0.0 \
		else REMOTE_FLIGHT_BASE_SEC + REMOTE_FLIGHT_PER_M * _tip().distance_to(target)
	_t = -maxf(0.0, release_in)
	_state = State.WINDUP if _t < 0.0 else State.FLYING
	_from = _tip()
	_twitch = 0.0
	_slack = 0.0
	_float.visible = true
	_line.visible = true
	hide_aim()
	_play(_voice, sfx_cast, &"cast")


## Snap the float straight onto the water, without a cast. For a line that was already out when
## this client arrived — it did not just happen, so it should not be performed.
func place_at(target: Vector3) -> void:
	_target = target
	_state = State.FLOATING
	_twitch = 0.0
	_slack = 1.0
	_float.visible = true
	_line.visible = true
	_float.global_position = _target


## THE FIGHT: what is hooked drags the float about the water, from where it was hooked toward the
## angler; `tell` colours the ring around it (the TELL_* constants), `pulse` 0..1 grows it (the
## sweet spot), `shake` 0..1 rattles it (too far, or it is running).
func fight_at(pos: Vector3, tell: Color, pulse: float, shake: float) -> void:
	if _state != State.FIGHTING:
		_state = State.FIGHTING
		_float.visible = true
		_line.visible = true
		_count(&"fight")
	_fight_pos = pos
	_tell_mat.albedo_color = tell
	_fight_pulse = clampf(pulse, 0.0, 1.0)
	_fight_shake = clampf(shake, 0.0, 1.0)
	_tell_ring.visible = true


## THE LINE IN THE FIGHT: `tension` 0..1 of the way to snapping tints it (white, the band's amber,
## then the over-the-limit pink), and `slack_m` — what a heave left, until it is wound in — lets
## it droop.
func set_line_strain(tension: float, slack_m: float) -> void:
	_fight_tension = clampf(tension, 0.0, 1.0)
	_fight_slack = maxf(slack_m, 0.0)


func line_tint() -> Color:
	return (_line.material_override as StandardMaterial3D).albedo_color


## A pump came in: the water churns where the catch is, harder for a perfect one.
func pump(perfect: bool, metres: float) -> void:
	var at: Vector3 = _float.global_position
	_ripple(at, 0.5 + minf(metres, 4.0) * 0.2)
	if perfect:
		_splash(at)
		_count(&"pump_perfect")
	_count(&"pump")
	_play(_voice, sfx_plop, &"pump_sound")


func tell_visible() -> bool:
	return _tell_ring.visible


## The line came out of the water without a catch.
func reel_in() -> void:
	_tell_ring.visible = false
	if _state == State.IDLE or _state == State.REELING:
		return
	_from = _float.global_position
	_t = 0.0
	_state = State.REELING


## The tell: 0..1, how close the bite is. The float twitches harder as it comes.
func twitch(amount: float) -> void:
	_twitch = clampf(amount, 0.0, 1.0)


## It bit: the float goes under and the water rings.
func bite() -> void:
	if _state != State.FLOATING:
		return
	_state = State.BITTEN
	_ripple(_target, 1.3)
	_play(_voice, sfx_plop, &"bite")


## Something came out. Splash where the float was, send the catch leaping toward `toward`, and —
## if `celebrate`, which is for the angler who caught it — play the reward. Fish are drawn; junk
## and treasure are the props kit's own models (`FishingData.model_path`).
func land_catch(catch_key: String, kg: float, toward: Vector3, celebrate: bool) -> void:
	var at: Vector3 = _float.global_position if _float.visible else _target
	_ripple(at, 1.9)
	_splash(at)
	_count(&"splash_fx")
	_play(_voice, sfx_splash, &"splash")
	var rarity: int = maxi(FishingData.rarity_of(catch_key), 0)
	_leap(at, toward, catch_key, kg, rarity)
	if celebrate:
		var rare: bool = rarity >= 2
		_play(_reward_voice, sfx_catch_rare if rare else sfx_catch, &"catch_rare" if rare else &"catch")
	# The catch took the float with it.
	_state = State.IDLE
	_float.visible = false
	_line.visible = false
	_tell_ring.visible = false


func state() -> State:
	return _state


func float_position() -> Vector3:
	return _float.global_position


func line_visible() -> bool:
	return _line.visible


## How many times `what` was shown or played. For tests.
func count(what: StringName) -> int:
	return _counts.get(what, 0)


## Catches in the air right now.
func in_air() -> int:
	return _in_air


## The last catch sent leaping, while it is still in the air. For tests and the preview.
func last_leap() -> Node3D:
	return _last_leap if is_instance_valid(_last_leap) else null


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


# --- per frame ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	match _state:
		State.WINDUP:
			# Dangling from the tip while the rod goes back and comes forward.
			_float.global_position = _tip() + Vector3(0.0, -0.25, 0.0)
			_t += delta
			if _t >= 0.0:
				_t = 0.0
				_from = _float.global_position
				_state = State.FLYING
		State.FLYING:
			_t += delta / maxf(_flight, 0.05)
			if _t >= 1.0:
				_state = State.FLOATING
				_float.global_position = _target
				_play(_voice, sfx_plop, &"plop")
				_ripple(_target, 1.0)
			else:
				_float.global_position = _arc(_from, _target, _t, clampf(_flight * 2.2, 1.0, 6.0))
		State.FLOATING:
			_bob_time += delta
			var bob: float = sin(_bob_time * 2.3) * 0.02
			# The tell: sharp downward twitches, harder as the bite comes.
			if _twitch > 0.0:
				bob -= absf(sin(_bob_time * 14.0)) * 0.12 * _twitch
				if fmod(_bob_time, 0.45) < delta:
					_ripple(_target, 0.35 * _twitch)
			_float.global_position = _target + Vector3(0.0, bob, 0.0)
		State.BITTEN:
			_bob_time += delta
			_float.global_position = _target + Vector3(0.0, -0.18 + sin(_bob_time * 18.0) * 0.05, 0.0)
		State.FIGHTING:
			_bob_time += delta
			var rattle: Vector3 = Vector3(sin(_bob_time * 37.0), 0.0, cos(_bob_time * 29.0)) * 0.1 * _fight_shake
			_float.global_position = _fight_pos + rattle \
				+ Vector3(0.0, -0.15 + sin(_bob_time * 16.0) * 0.05, 0.0)
			_tell_ring.global_position = _fight_pos + Vector3(0.0, 0.03, 0.0) + rattle
			var grow: float = 1.0 + 0.45 * _fight_pulse * absf(sin(_bob_time * 9.0))
			_tell_ring.scale = Vector3(grow, 0.25, grow)
		State.REELING:
			_t += delta / REEL_SEC
			if _t >= 1.0:
				_state = State.IDLE
				_float.visible = false
				_line.visible = false
			else:
				_float.global_position = _from.lerp(_tip(), _t * _t)
		_:
			pass
	if _line.visible:
		# In the air the line is taut behind the float; resting it goes slack and settles onto the
		# water; bitten or fighting it is pulled tight. Eased, so it settles and snaps rather than
		# jumping between shapes.
		var want: float = 1.0 if _state == State.FLOATING else (0.3 if _state == State.REELING else 0.0)
		if _state == State.FIGHTING:
			# A heave's slack hangs off the rod until it is wound in (FishingFeedback).
			want = clampf(_fight_slack / FIGHT_SLACK_FULL_M, 0.0, 1.0)
		_slack = move_toward(_slack, want, delta * LINE_SETTLE_RATE)
		var tint: Color = LINE_COLOR
		if _state == State.FIGHTING:
			tint = LINE_COLOR.lerp(TELL_BAND, clampf((_fight_tension - 0.45) / 0.3, 0.0, 1.0))
			if _fight_tension > 0.85:
				tint = TELL_OVER
		(_line.material_override as StandardMaterial3D).albedo_color = tint
		_draw_line()


## SLACK LINE LIES ON THE WATER. It hangs from the rod tip in a curve that meets the surface
## level — the way any hanging line meets what it comes to rest on — and floats from there out to
## the float. Drawn instead as a sag by its length, a long cast's line dived under the lake halfway
## out and came back up at the float, and a clamped sag met the water at a kink.
func _draw_line() -> void:
	var a: Vector3 = _tip()
	var b: Vector3 = _float.global_position + Vector3(0.0, 0.03, 0.0)
	var surface: float = _target.y + LINE_ON_WATER
	var run: float = Vector2(b.x - a.x, b.z - a.z).length()
	# How far out it hangs before it touches down: further from a higher tip, never past halfway.
	var hang: float = clampf((a.y - surface) * LINE_HANG_PER_M, 0.5, maxf(run * 0.5, 0.5))
	var n: int = clampi(int(a.distance_to(b) / LINE_STEP_M), LINE_SEGMENTS, LINE_SEGMENTS_MAX)
	_line_points.resize(n + 1)
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i: int in range(n + 1):
		var t: float = float(i) / n
		var p: Vector3 = a.lerp(b, t)
		if _slack > 0.0 and a.y > surface:
			var s: float = t * run
			var k: float = maxf(1.0 - s / hang, 0.0)
			var lying: float = surface + (a.y - surface) * k * k
			# The last half-metre rises (or dips) to wherever the float is riding.
			lying = lerpf(lying, b.y, smoothstep(run - 0.5, run, s))
			p.y = lerpf(p.y, lying, _slack)
		_line_points[i] = p
		_line_mesh.surface_add_vertex(p)
	_line_mesh.surface_end()


## The points the line was last drawn through, rod tip first. For tests: a headless renderer
## keeps no mesh to read back.
func line_points() -> PackedVector3Array:
	return _line_points


# --- pieces --------------------------------------------------------------------------------

func _tip() -> Vector3:
	if _rod != null and is_instance_valid(_rod) and _rod.is_inside_tree():
		return _rod.tip_position()
	# No rod (no skeleton to hold one): from roughly where a hand would be.
	return global_position + Vector3(0.0, 1.5, 0.0)


static func _arc(a: Vector3, b: Vector3, t: float, height: float) -> Vector3:
	var p: Vector3 = a.lerp(b, t)
	p.y += height * 4.0 * t * (1.0 - t)
	return p


## Ring the level's water, if it has any.
func _ripple(at: Vector3, strength: float) -> void:
	if ripple_override.is_valid():
		ripple_override.call(at, strength)
		return
	if not is_inside_tree():
		return
	var level: LakesideLevel = get_tree().get_first_node_in_group(LakesideLevel.GROUP) as LakesideLevel
	if level != null and level.water() != null:
		level.water().ripple(at, strength)


## A classic float: red over white, with a little antenna.
func _make_float() -> Node3D:
	var root := Node3D.new()
	root.name = "Float"
	root.top_level = true
	var top := MeshInstance3D.new()
	var top_mesh := SphereMesh.new()
	top_mesh.radius = 0.06
	top_mesh.height = 0.12
	top_mesh.is_hemisphere = true
	top.mesh = top_mesh
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.92, 0.18, 0.12)
	red.roughness = 0.4
	top.material_override = red
	root.add_child(top)
	var bottom := MeshInstance3D.new()
	bottom.mesh = top_mesh
	bottom.rotation = Vector3(PI, 0.0, 0.0)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.92)
	white.roughness = 0.4
	bottom.material_override = white
	root.add_child(bottom)
	var antenna := MeshInstance3D.new()
	var stick := CylinderMesh.new()
	stick.top_radius = 0.005
	stick.bottom_radius = 0.005
	stick.height = 0.1
	antenna.mesh = stick
	antenna.material_override = red
	antenna.position = Vector3(0.0, 0.1, 0.0)
	root.add_child(antenna)
	return root


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	return m


func _make_voice(voice_name: String, volume_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = voice_name
	p.volume_db = volume_db
	p.bus = Settings.BUS_EFFECTS   # its volume is the player's (DECISIONS #165)
	p.unit_size = 6.0
	p.max_distance = 60.0
	add_child(p)
	return p


func _play(voice: AudioStreamPlayer3D, stream: AudioStream, what: StringName) -> void:
	_count(what)
	if stream == null:
		return
	# The splash, the plop and the bite come from the water, not from the angler.
	if what == &"plop" or what == &"splash" or what == &"bite":
		voice.global_position = _float.global_position if _float.visible else _target
	else:
		voice.position = Vector3(0.0, 1.5, 0.0)
	voice.stream = stream
	voice.play()


func _count(what: StringName) -> void:
	_counts[what] = _counts.get(what, 0) + 1


## Droplets thrown up and out, falling back under gravity.
func _splash(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.name = "Splash"
	p.top_level = true
	p.one_shot = true
	p.emitting = false
	p.amount = 48
	p.lifetime = 0.9
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 38.0
	p.initial_velocity_min = 2.4
	p.initial_velocity_max = 4.6
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.07
	drop.radial_segments = 6
	drop.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.9, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.55, 0.7)
	drop.material = mat
	p.mesh = drop
	add_child(p)
	p.global_position = at
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


## THE PAYOFF (carried over from Fishing for Compliments): the catch comes out of the water and
## over in an arc toward the angler, where you can see what you pulled up — a fish drawn to its
## size and coloured by its rarity, or the actual barrel, anvil or chest.
func _leap(from: Vector3, toward: Vector3, catch_key: String, kg: float, rarity: int) -> void:
	var body: Node3D = _make_catch(catch_key, kg, rarity)
	add_child(body)
	body.global_position = from
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_in_air += 1
	_last_leap = body
	_count(&"catch_leap")
	var end: Vector3 = from.lerp(toward + Vector3(0.0, 1.2, 0.0), 0.72)
	var heading: float = atan2(end.x - from.x, end.z - from.z)
	var spin: float = 1.0 if FishingData.model_path(catch_key).is_empty() else 0.25
	var height: float = clampf(1.4 + 0.4 * log(maxf(kg, 0.1) + 1.0), 1.4, 3.2)
	# Nose up leaving the water, nose down coming over the top, thrashing (or tumbling) all the way.
	var fly: Callable = func(t: float) -> void:
		body.global_position = _arc(from, end, t, height)
		body.rotation = Vector3(lerpf(-1.0, 1.0, t) * spin, heading + t * TAU * (1.0 - spin) * 0.5,
			sin(t * 30.0) * 0.35 * spin)
	var gone: Callable = func() -> void:
		_in_air -= 1
		body.queue_free()
	var tw: Tween = body.create_tween()
	tw.tween_method(fly, 0.0, 1.0, LEAP_SEC)
	tw.tween_property(body, ^"scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(gone)


func _make_catch(catch_key: String, kg: float, rarity: int) -> Node3D:
	var path: String = FishingData.model_path(catch_key)
	if not path.is_empty() and ResourceLoader.exists(path):
		var scene: PackedScene = load(path) as PackedScene
		var prop: Node3D = scene.instantiate() as Node3D if scene != null else null
		if prop != null:
			prop.name = "Catch"
			prop.top_level = true
			# A prop from the kit carries a static body: a flying one would shove the angler.
			for body: Node in prop.find_children("*", "CollisionObject3D", true, false):
				body.queue_free()
			return prop
	return _make_fish(rarity_color(rarity), clampf(0.3 * pow(maxf(kg, 0.05), 0.33), 0.14, 2.2))


static func _make_fish(tint: Color, size: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Catch"
	root.top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.metallic = 0.35
	mat.roughness = 0.35
	mat.emission_enabled = true
	mat.emission = tint * 0.25
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.5
	body_mesh.height = 1.0
	body.mesh = body_mesh
	body.material_override = mat
	body.scale = Vector3(0.28, 0.4, 1.0) * size
	root.add_child(body)
	var tail := MeshInstance3D.new()
	var tail_mesh := PrismMesh.new()
	tail_mesh.size = Vector3(0.5, 0.5, 0.06)
	tail.mesh = tail_mesh
	tail.material_override = mat
	tail.rotation = Vector3(0.0, PI * 0.5, PI * 0.5)
	tail.scale = Vector3.ONE * size
	tail.position = Vector3(0.0, 0.0, -0.58 * size)
	root.add_child(tail)
	return root
