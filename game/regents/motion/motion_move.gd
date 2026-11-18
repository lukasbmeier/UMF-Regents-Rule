class_name MotionMove extends Resource
## A MOVE MADE IN CODE (Luke, 2026-11-17: "a lab that showcases motion made in code", no AI animation: `ABILITY_LIMITS.md`,
## `AI_ASSET_AUDIT.md`): over `length_s`, human-made CLIPS for the body (`clips`, Luke: "rebuild it with the clips": the
## code alone turned a stiff pose like a doll) and CODE for what a clip cannot do, on top of them. Each channel is an amount and
## a Curve over the move's time (0 to 1 across the Curve's width); the Curve's height (-1 to 1) times the amount is the
## channel's value then. No Curve: the channel does nothing. Open a move's `.tres` in the Inspector, drag the curves'
## points, run the lab again (`motion_lab.tscn`).
##
## The WHOLE BODY turns about a point `pivot_m` over its feet (the hips: a flip turns there, not at the feet):
## lift (up), spin (round), tip (forward), bank (to its right) and squash (shorter and wider, on a landing).
## The BONES bend on the pose the clip gives: the spine bends forward and twists left, the weapon arm rises forward,
## spreads to the side and reaches toward the move's target.
## TRAVEL is how far along its facing the body goes: the lab carries the body that far; in the game that is the
## server's (a lunge, a push), and a move only shows it.
##
## Presentation only (hard rule 11): a move decides nothing; it is played when something has already happened.

## How long it runs (s).
@export_range(0.05, 10.0, 0.01, "suffix:s") var length_s: float = 1.0
## THE BODY: human-made clips from the game's libraries, each over a stretch of the move, time-warped and blended
## (`MotionClip`). The channels below go on top of them: a spin, an arc stretched, an arm turned to a target.
@export var clips: Array[MotionClip] = []
## A clip of the game's to play with it (`ability.40003`, `react.stagger`; empty: none), when (share of the move).
@export var clip: StringName = &""
@export_range(0.0, 1.0, 0.01) var clip_at: float = 0.0
## When it lands its blow (share of the move; below 0: none): the lab's hit, flash and shake.
@export_range(-1.0, 1.0, 0.01) var impact_at: float = -1.0
## How high over the feet the body turns (m): the hips.
@export_range(0.0, 2.0, 0.01, "suffix:m") var pivot_m: float = 0.95

@export_group("The whole body")
## Up, at the Curve's 1 (m).
@export_range(0.0, 10.0, 0.01, "suffix:m") var lift_m: float = 0.0
@export var lift: Curve
## Along its facing by the move's end, at the Curve's 1 (m; negative: back). The Curve is the share gone by then.
@export_range(-20.0, 20.0, 0.1, "suffix:m") var travel_m: float = 0.0
@export var travel: Curve
## Turns round (positive: to the left, as Godot turns), at the Curve's 1.
@export_range(-20.0, 20.0, 0.05) var spin_turns: float = 0.0
@export var spin: Curve
## Tipped forward (deg; negative: back, -360 a back flip), at the Curve's 1.
@export_range(-1080.0, 1080.0, 1.0, "suffix:deg") var tip_deg: float = 0.0
@export var tip: Curve
## Banked to its right (deg), at the Curve's 1.
@export_range(-180.0, 180.0, 1.0, "suffix:deg") var bank_deg: float = 0.0
@export var bank: Curve
## Shorter and wider (a share: 0.1 is 10 % shorter), at the Curve's 1.
@export_range(0.0, 0.5, 0.01) var squash: float = 0.0
@export var squash_curve: Curve

@export_group("The bones")
## The spine bent forward (deg; negative: arched back), shared over the spine's bones.
@export_range(-90.0, 90.0, 1.0, "suffix:deg") var bend_deg: float = 0.0
@export var bend: Curve
## The spine twisted to the left (deg), shared over the spine's bones.
@export_range(-180.0, 180.0, 1.0, "suffix:deg") var twist_deg: float = 0.0
@export var twist: Curve
## The weapon arm raised forward and up (deg: 180 is straight overhead).
@export_range(-180.0, 200.0, 1.0, "suffix:deg") var raise_deg: float = 0.0
@export var raise: Curve
## The weapon arm spread out to the side (deg: 90 is level with the shoulder).
@export_range(-90.0, 180.0, 1.0, "suffix:deg") var spread_deg: float = 0.0
@export var spread: Curve
## The weapon arm pointed at the move's target (0 to 1: how much).
@export_range(0.0, 1.0, 0.01) var reach: float = 0.0
@export var reach_curve: Curve


## Its root's height (skeleton units, the clips' blended) and its travel along the ground (skeleton frame, x and z, the
## clips' root moves times their `root_travel`) when it is `t` s in.
func root_at(t: float) -> Vector3:
	var out := Vector3.ZERO
	var y: float = 0.0
	for c: MotionClip in clips:
		var w: float = c.weight(t, length_s)
		var a: Animation = c.clip()
		if a == null:
			continue
		var tr: int = a.find_track(^"Skeleton3D:root", Animation.TYPE_POSITION_3D)
		if tr < 0:
			continue
		# Travel: where the clip's root has got to since the clip began (all of it once the clip is past).
		var t0: float = c.clip_time(c.at * length_s, length_s)
		var tc: float = c.clip_time(t, length_s) if t >= c.at * length_s else t0
		var moved: Vector3 = a.position_track_interpolate(tr, tc) - a.position_track_interpolate(tr, t0)
		out.x += moved.x * c.root_travel
		out.z += moved.z * c.root_travel
		if w > 0.0:
			y = lerpf(y, a.position_track_interpolate(tr, tc).y * c.root_height, w)
	out.y = y
	return out


## Where every channel is `t` seconds in (held at its last value after the end).
func at(t: float) -> Pose:
	var u: float = clampf(t / maxf(length_s, 0.001), 0.0, 1.0)
	var p := Pose.new()
	p.lift_m = lift_m * _sample(lift, u)
	p.travel_m = travel_m * _sample(travel, u)
	p.spin = spin_turns * TAU * _sample(spin, u)
	p.tip = deg_to_rad(tip_deg) * _sample(tip, u)
	p.bank = deg_to_rad(bank_deg) * _sample(bank, u)
	p.squash = squash * _sample(squash_curve, u)
	p.bend = deg_to_rad(bend_deg) * _sample(bend, u)
	p.twist = deg_to_rad(twist_deg) * _sample(twist, u)
	p.raise = deg_to_rad(raise_deg) * _sample(raise, u)
	p.spread = deg_to_rad(spread_deg) * _sample(spread, u)
	p.reach = reach * clampf(_sample(reach_curve, u), 0.0, 1.0)
	return p


static func _sample(c: Curve, u: float) -> float:
	if c == null or c.point_count == 0:
		return 0.0
	# A Curve's width may be other than 0 to 1 (Godot 4.4's domain): read it across whatever it is.
	return c.sample(lerpf(c.min_domain, c.max_domain, u))


## One moment of a move: every channel's value (lengths in m, turns in radians).
class Pose extends RefCounted:
	var lift_m: float = 0.0
	var travel_m: float = 0.0
	var spin: float = 0.0
	var tip: float = 0.0
	var bank: float = 0.0
	var squash: float = 0.0
	var bend: float = 0.0
	var twist: float = 0.0
	var raise: float = 0.0
	var spread: float = 0.0
	var reach: float = 0.0

	## Nothing on: a body standing as its clip has it.
	func is_rest() -> bool:
		return absf(lift_m) + absf(spin) + absf(tip) + absf(bank) + absf(squash) + absf(bend) + absf(twist) \
			+ absf(raise) + absf(spread) + absf(reach) < 0.0001
