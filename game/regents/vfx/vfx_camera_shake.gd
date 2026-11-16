class_name VfxCameraShake extends Node
## THE GAME'S CAMERA LISTENING TO `VfxEffect.shook` (HANDOFF next 4): a child of this client's camera, put there by
## the local player's `AbilityVfx` (`install`). An effect asks for a shake (`shook`); it shakes as hard as asked
## when it is within `NEAR_M` of this client's character, fading to nothing by `FAR_M`; a `lighter` effect (another
## player's) never shakes it. It moves the picture only (`h_offset`, `v_offset`), never the rig nor the aim.
## Presentation only (hard rule 11). The lab and the showcase keep their own shakes (they install none).

const NEAR_M: float = 6.0
const FAR_M: float = 20.0
## How far (m, at strength 1) the picture moves.
const AMPLITUDE_M: float = 0.25

## The one listening now (null: none, as in the lab).
static var current: VfxCameraShake = null

var who: Node3D = null
var _strength: float = 0.0
var _left: float = 0.0
var _total: float = 0.0


## Put a listener on `camera` for the character `body` (once; a second call moves it).
static func install(camera: Camera3D, body: Node3D) -> VfxCameraShake:
	if camera == null:
		return null
	var s: VfxCameraShake = camera.get_node_or_null(^"VfxCameraShake") as VfxCameraShake
	if s == null:
		s = VfxCameraShake.new()
		s.name = "VfxCameraShake"
		camera.add_child(s)
	s.who = body
	current = s
	return s


## Connect effect `fx` to the listener now, if there is one.
static func listen(fx: VfxEffect) -> void:
	if is_instance_valid(current) and current.is_inside_tree():
		fx.shook.connect(current.heard.bind(fx))


## Effect `fx` asked for a shake: how hard it is taken here (0: none). Tests read the return.
func heard(strength: float, seconds: float, fx: VfxEffect) -> float:
	if not is_instance_valid(fx) or fx.lighter or not is_instance_valid(who):
		return 0.0
	var d: float = fx.global_position.distance_to(who.global_position)
	var k: float = strength * (1.0 - clampf((d - NEAR_M) / (FAR_M - NEAR_M), 0.0, 1.0))
	if k > _strength * (_left / maxf(_total, 0.001)):
		_strength = k
		_left = seconds
		_total = seconds
	return k


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(delta: float) -> void:
	var cam: Camera3D = get_parent() as Camera3D
	if cam == null:
		return
	if _left <= 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		return
	_left = maxf(_left - delta, 0.0)
	var k: float = _strength * (_left / maxf(_total, 0.001)) * AMPLITUDE_M
	cam.h_offset = randf_range(-1.0, 1.0) * k
	cam.v_offset = randf_range(-1.0, 1.0) * k
