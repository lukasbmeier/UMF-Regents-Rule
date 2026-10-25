class_name AnimationRate extends RefCounted
## HOW OFTEN A CHARACTER'S POSE IS WORKED OUT, by the player's Detail setting (DECISIONS #282).
##
## Measured (tools/perf/perf_bench.gd, 60 reference humanoids, ~10 skinned meshes and 18k vertices
## each): on the Compatibility renderer the crowd was 93% of the GPU's time (5.1 ms with it, 0.4 without),
## and frozen poses took it to 0.6 ms; on Forward+ 3.4 ms to 2.2. A mesh is skinned again only when its
## skeleton's pose changes, so a character far away or off screen that changes pose 8 times a second
## instead of every frame costs a fraction, and still looks alive. Its POSITION still moves every
## frame (the movement component's); only the limbs step.
##
## `AnimationDriverComponent` asks `hz` each frame and, below every-frame, advances its tree itself
## with the time owed (staggered by entity, so a crowd does not all pose on one frame). High detail
## is every character every frame: the look before this existed. Your own character is always every
## frame.
##
## Tune the bands here: [within this many metres and on screen, Hz] pairs, nearest first; beyond the
## last, `FAR_HZ`; off screen, `OFF_SCREEN_HZ`. 0 Hz means every frame.

const EVERY_FRAME: float = 0.0

## Per detail level (GraphicsQuality.Detail: Low, Medium, High).
const BANDS: Array[Array] = [
	[[15.0, 30.0], [40.0, 15.0]],
	[[25.0, EVERY_FRAME], [60.0, 20.0]],
	[],
]
const FAR_HZ: PackedFloat32Array = [8.0, 10.0, EVERY_FRAME]
const OFF_SCREEN_HZ: PackedFloat32Array = [5.0, 8.0, EVERY_FRAME]
## How far another character is drawn at all (0: as far as the camera sees). Hidden ones are not
## skinned; their trees still run, at `FAR_HZ`.
const CHARACTER_RANGE: PackedFloat32Array = [80.0, 150.0, 0.0]

## Where a mesh keeps the draw distance it was made with.
const RANGE_META: StringName = &"umf_authored_range"
## A character this wide round its middle counts as on screen when any of it is.
const RADIUS_M: float = 1.5


## How often to pose a character `distance` m from the camera (0: every frame).
static func hz(detail: int, distance: float, on_screen: bool, is_local: bool) -> float:
	if is_local or detail < 0 or detail >= BANDS.size():
		return EVERY_FRAME
	if detail == GraphicsQuality.Detail.HIGH:
		return EVERY_FRAME
	if not on_screen:
		return OFF_SCREEN_HZ[detail]
	for band: Array in BANDS[detail]:
		if distance <= float(band[0]):
			return float(band[1])
	return FAR_HZ[detail]


## Whether a sphere of RADIUS_M round `at` is inside the camera's view.
static func on_screen(camera: Camera3D, at: Vector3) -> bool:
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(at) > RADIUS_M:
			return false
	return true


## Where in its first interval a character starts, so a crowd poses on different frames (0..1).
static func phase(entity_id: int) -> float:
	return fposmod(float(entity_id) * 0.618034, 1.0)


## A character's draw distance for the Detail setting, on every mesh of `model` the designer left
## unlimited (a piece with its own range keeps it).
static func apply_range(model: Node3D, detail: int) -> void:
	if model == null or detail < 0 or detail >= CHARACTER_RANGE.size():
		return
	for n: Node in model.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if not g.has_meta(RANGE_META):
			g.set_meta(RANGE_META, g.visibility_range_end)
		var authored: float = float(g.get_meta(RANGE_META))
		g.visibility_range_end = authored if authored > 0.0 else CHARACTER_RANGE[detail]


## One tree's pacing. The tree is the pacer's from the start (`take`, manual mode): CHANGING A TREE'S
## PROCESS MODE RESTARTS WHAT IT PLAYS (measured: a switch put a walk back to its first frame), so it
## is set once, before the tree first plays, and never again. Every step adds the frame's time to
## what is owed; at every frame the tree is advanced each step, below that once an interval has
## passed, by everything owed. An entity's first interval at a new rate is shortened by its `phase`,
## so a crowd does not pose on one frame.
class Pacer extends RefCounted:
	var owed: float = 0.0
	## The rate in use now, Hz (0: every frame).
	var hz: float = 0.0
	var _next_in: float = 0.0

	## Make `tree` a paced one. Before it first plays.
	static func take(tree: AnimationTree) -> void:
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	func step(tree: AnimationTree, rate: float, delta: float, start_phase: float) -> void:
		owed += delta
		if rate <= 0.0:
			hz = rate
			tree.advance(owed)
			owed = 0.0
			return
		if rate != hz:
			hz = rate
			_next_in = (1.0 - start_phase) / rate
		_next_in -= delta
		if _next_in <= 0.0:
			tree.advance(owed)
			owed = 0.0
			_next_in = maxf(_next_in + 1.0 / rate, 0.0)
