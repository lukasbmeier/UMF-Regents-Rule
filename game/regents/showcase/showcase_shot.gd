class_name ShowcaseShot extends Resource
## ONE CAMERA SHOT OF THE SHOWCASE (2026-11-15): where the camera starts and ends, what it looks at, its lens, how
## long, in which mood, and (a battle's) the beat its actors play. A lab's `shots` list holds them, in its scene: a
## designer adds or moves one in the Inspector. To find a good place: the lab's free camera (F), then C prints the
## eye and the point it looks at, to paste here.

@export var title: String = "Shot"
## Its mood (null: the lab's own).
@export var mood: ShowcaseMood = null
@export_range(0.5, 120.0, 0.1, "suffix:s") var seconds: float = 8.0
@export_group("Camera")
@export var eye_from: Vector3 = Vector3(0.0, 2.0, 8.0)
@export var eye_to: Vector3 = Vector3(0.0, 2.0, 6.0)
@export var at_from: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var at_to: Vector3 = Vector3(0.0, 1.0, 0.0)
## Swing round the point it looks at as it goes (deg, + is to the left).
@export_range(-360.0, 360.0, 0.5, "suffix:deg") var orbit_deg: float = 0.0
@export_range(10.0, 100.0, 0.5, "suffix:deg") var fov_from: float = 50.0
@export_range(10.0, 100.0, 0.5, "suffix:deg") var fov_to: float = 50.0
## Ease in and out of the move (0: steady all the way).
@export_range(0.0, 1.0, 0.05) var easing: float = 0.6
## A held camera's drift (m): 0 a tripod, 0.05 a hand.
@export_range(0.0, 0.3, 0.005, "suffix:m") var handheld_m: float = 0.0
## Focus: things nearer or farther than this blur (m); 0 sharp all through.
@export_range(0.0, 200.0, 0.5, "suffix:m") var focus_m: float = 0.0
@export_group("Action")
## The lab's method that sets this shot's people moving (a battle's beat), called as it starts; empty: none.
@export var beat: StringName = &""
## Slow motion for the whole shot (1 normal).
@export_range(0.05, 2.0, 0.01) var time_scale: float = 1.0
## Where in the shot its still is taken (0..1: the lab's `stills`).
@export_range(0.0, 1.0, 0.01) var still_at: float = 0.5


## Where the camera is at `u` (0..1 through the shot): [eye, at, fov].
func at_time(u: float) -> Array:
	var e: float = _eased(clampf(u, 0.0, 1.0))
	var at: Vector3 = at_from.lerp(at_to, e)
	var eye: Vector3 = eye_from.lerp(eye_to, e)
	if orbit_deg != 0.0:
		var arm: Vector3 = eye - at
		eye = at + arm.rotated(Vector3.UP, deg_to_rad(orbit_deg) * e)
	return [eye, at, lerpf(fov_from, fov_to, e)]


func _eased(u: float) -> float:
	var smooth: float = u * u * (3.0 - 2.0 * u)
	return lerpf(u, smooth, easing)
