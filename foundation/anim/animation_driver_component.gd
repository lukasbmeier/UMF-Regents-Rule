class_name AnimationDriverComponent extends SpaceTimeComponent
## The ONLY writer of AnimationTree parameters (`docs/ANIMATION_SPEC.md` §2).
##
## Animation reads state and never produces it (hard rule 11). Everything here is downstream of
## the movement component's render state and of entity-local signals; nothing it does can reach
## the module, so a character that animates wrongly is a character that looks wrong, never one
## that desyncs.
##
## IT RUNS FOR REMOTE ENTITIES TOO, and that is most of the point: `move_state` and the discrete
## jump/land events are mirrored to every client (DECISIONS #82), so the same driver animates
## the player you control and the player across the level, from the same two inputs.
##
## LOCAL ONE-SHOTS ARE PREDICTED. `jumped` and `landed` fire from the prediction the instant they
## happen rather than a round trip later (DECISIONS #83), so your own jump animation starts on
## the frame you press the key. A prediction the server overrides is revoked, and the state
## machine drops back — the same contract sound and VFX already use.
##
## The set comes from `EntityDefinition.animation_set`, handed over before `bind()`. An entity
## with no set (the greybox capsule) simply does not animate: no tree is built, no warning is
## spammed, and the component costs nothing.

## The state machine moved. `state` is one of AnimationTreeBuilder's STATE_* names.
signal state_changed(state: StringName)

## Assigned by `SpaceTimeEntity._apply_presentation()` from the entity definition; may also be
## set in a scene for a one-off character.
@export var animation_set: AnimationSet
## Where the rigged model lives, relative to the entity.
@export var model_path: NodePath = ^"Visual/Model"
## How fast the locomotion blend follows the body's speed. Higher snaps sooner.
@export var speed_smoothing: float = 14.0
## How fast the model turns to the direction the body faces. The BODY snaps (it is simulated
## state, and the server has to agree with it); the model catching up is presentation, so it can
## ease. 0 turns instantly.
@export var turn_smoothing: float = 12.0
## Moving faster than this cancels a landing animation instead of watching it finish while the
## character slides. A landing that ends with the player already running is the tell.
@export var land_cancel_speed: float = 0.6
## And the same for an ACTION one-shot — a cast, an interact, an ability. Casting and then
## walking away played the whole cast over a character sliding sideways, because a one-shot runs
## to its own end and knows nothing about the body underneath it. 0 turns cancelling off, for a
## genre whose actions should play out wherever the character goes.
@export var action_cancel_speed: float = 0.7
## Downward speed at landing that counts as a heavy landing, in m/s.
@export var heavy_land_speed: float = 9.0
## How fast a held pose (`hold_pose`) blends in and out, in weight per second.
@export var pose_blend_rate: float = 8.0

var _tree: AnimationTree = null
var _playback: AnimationNodeStateMachinePlayback = null
var _blend_tree: AnimationNodeBlendTree = null
var _movement: SpaceTimeMovementComponent = null
var _blend: float = 0.0
## The strafing blend, in units of sprint speed: x sideways, y forwards.
var _blend2: Vector2 = Vector2.ZERO
var _strafing: bool = false
var _model: Node3D = null
var _shown_yaw: float = 0.0
var _shown_yaw_valid: bool = false
var _sprint_speed: float = 8.0
var _dead: bool = false
var _state: StringName = &""
## Has the character actually left the ground since the jump started? On the frame the jump is
## pressed the body is still touching the floor, and without this the take-off clip is
## immediately replaced by a landing.
var _airborne_since_jump: bool = false
## What the driver last ASKED the state machine for, until the machine confirms it. A travel is
## executed on the tree's own process tick, so for one frame `get_current_node()` still names
## the state we just left — long enough for the next frame's decision to undo it.
var _asked: StringName = &""
var _asked_age: float = 0.0

## If the machine has not reached what we asked for by now, it went somewhere else on its own
## (an auto transition) and its word is the truth again.
const ASK_TIMEOUT_SEC: float = 0.6

## The held pose (`hold_pose`): which clip, the weight asked for and the weight shown, and where
## in the clip — 0..1 of its length, or < 0 to let it loop.
var _pose_semantic: StringName = &""
var _pose_target: float = 0.0
var _pose_weight: float = 0.0
var _pose_at: float = -1.0
var _pose_length: float = 0.0
var _pose_while_moving: bool = false
## For `semantic_weights`: what the action one-shot and the landing were last asked to play, and
## the two one-shots' weights, eased over their own fades.
var _action_semantic: StringName = AnimationSet.INTERACT
var _land_semantic: StringName = AnimationSet.JUMP_LAND
var _action_weight: float = 0.0
var _hit_weight: float = 0.0
## The upper-body one-shot (`play_upper`): what it was last asked to play, and its weight.
var _upper_semantic: StringName = &""
var _upper_weight: float = 0.0


func required_tables() -> Array[StringName]:
	return []


## No tables: this component watches its siblings, not the database.
func _on_row_updated(_table: StringName, _old: RefCounted, _new: RefCounted) -> void:
	pass


func _on_bound() -> void:
	set_process(false)
	if animation_set == null:
		return   # a character with no clips; the greybox capsule is the normal case
	var cfg: MovementConfig = MovementConfig.shared()
	if cfg != null and cfg.sprint_speed > 0.0:
		_sprint_speed = cfg.sprint_speed
	if not _install():
		return
	_connect_siblings()
	set_process(true)


func _exit_tree() -> void:
	# The tree is parented to the model, which the entity owns; nothing to free here, but an
	# entity being rebound must not keep driving a tree that is about to be replaced.
	if _tree != null and not is_instance_valid(_tree):
		_tree = null


# --- read API (UI, tests) ----------------------------------------------------------------

## True when the locomotion blend is a plane (the character strafes) rather than a line.
func is_strafing() -> bool:
	return _strafing


## The strafing blend: x sideways, y forwards, in units of sprint speed.
func strafe_blend() -> Vector2:
	return _blend2


func is_animating() -> bool:
	return _tree != null and _tree.active


## The state machine's current node, or "" before the first frame.
func current_state() -> StringName:
	return _playback.get_current_node() if _playback != null else &""


## 0 standing still, 1 at sprint speed — what the locomotion blend is being driven with.
func speed_blend() -> float:
	return _blend


func animation_tree() -> AnimationTree:
	return _tree


func hit_playing() -> bool:
	return _tree != null and bool(_tree.get(AnimationTreeBuilder.P_HIT_ACTIVE))


func action_playing() -> bool:
	return _tree != null and bool(_tree.get(AnimationTreeBuilder.P_ACTION_ACTIVE))


## The held pose's clip, or "" before one was asked for.
func pose_clip() -> StringName:
	if _blend_tree == null or _pose_semantic.is_empty():
		return &""
	var node: AnimationNodeAnimation = _blend_tree.get_node(
		AnimationTreeBuilder.NODE_POSE_CLIP) as AnimationNodeAnimation
	return node.animation if node != null else &""


## How much of the held pose is showing, 0..1.
func pose_weight() -> float:
	return _pose_weight


# --- the pose -----------------------------------------------------------------------------

## HOLD A POSE over whatever the body is doing: `semantic`'s clip, looping when `at` < 0, or
## frozen at `at` (0..1 of its length) — how far a rod is heaved, a bow drawn. `weight` 0..1
## blends it in at `pose_blend_rate`; moving faster than `action_cancel_speed` lets it go, the
## same bargain an action strikes. Call it every frame the pose should hold, from state the
## caller READS (hard rule 11): a genre's presentation asks, and only this writes the tree. A set
## without the clip holds nothing.
##
## `while_moving`: the pose replaces walking rather than waiting for the body to stop (a status's
## crawl, DECISIONS #206), so moving does not let it go.
func hold_pose(semantic: StringName, weight: float = 1.0, at: float = -1.0, while_moving: bool = false) -> void:
	if animation_set == null or not animation_set.has_exact(semantic) or _blend_tree == null:
		return
	if semantic != _pose_semantic:
		var node: AnimationNodeAnimation = _blend_tree.get_node(
			AnimationTreeBuilder.NODE_POSE_CLIP) as AnimationNodeAnimation
		if not AnimationTreeBuilder.apply_clip(node, animation_set, semantic, at < 0.0):
			return
		_pose_semantic = semantic
		_pose_length = AnimationTreeBuilder.clip_length(animation_set, semantic)
	_pose_target = clampf(weight, 0.0, 1.0)
	_pose_at = at
	_pose_while_moving = while_moving


## Let the held pose go: it blends out.
func release_pose() -> void:
	_pose_target = 0.0


## Fire `semantic` as the action one-shot: a genre's reaction that is neither an interact nor an
## ability (a line snapping). A set without the clip plays nothing.
func play_action(semantic: StringName) -> void:
	if animation_set == null or not animation_set.has_exact(semantic):
		return
	_fire(AnimationTreeBuilder.NODE_ACTION_CLIP, AnimationTreeBuilder.P_ACTION_REQUEST, semantic)


## Fire `semantic` on the UPPER BODY only (`AnimationTreeBuilder.upper_body`): the chest, arms and
## hands play it while the legs keep doing what they were (drawing or stowing an item while
## walking, DECISIONS #158). Moving does not cancel it; an action or a hit over the whole body ends
## it (`_end_covered_upper`). False when the set has no such clip.
func play_upper(semantic: StringName) -> bool:
	if animation_set == null or not animation_set.has_exact(semantic) or _blend_tree == null:
		return false
	_fire(AnimationTreeBuilder.NODE_UPPER_CLIP, AnimationTreeBuilder.P_UPPER_REQUEST, semantic)
	return true


## Let the upper-body one-shot go, fading out (a draw turned back half way).
func stop_upper() -> void:
	if _tree != null:
		_tree.set(AnimationTreeBuilder.P_UPPER_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func upper_playing() -> bool:
	return _tree != null and bool(_tree.get(AnimationTreeBuilder.P_UPPER_ACTIVE))


## The clip the upper-body one-shot will play (or is playing).
func upper_clip() -> StringName:
	if _blend_tree == null:
		return &""
	var node: AnimationNodeAnimation = _blend_tree.get_node(
		AnimationTreeBuilder.NODE_UPPER_CLIP) as AnimationNodeAnimation
	return node.animation if node != null else &""


## How long `semantic` plays for in a one-shot, in seconds (its set's speed included).
func shot_seconds(semantic: StringName) -> float:
	var ref: AnimationClipRef = animation_set.clip(semantic) if animation_set != null else null
	if ref == null:
		return 0.0
	var length: float = AnimationTreeBuilder.clip_length(animation_set, semantic)
	return length / ref.speed_scale if ref.speed_scale > 0.0 else length


## The clip the action one-shot will play (or is playing). Lets a test prove that an ability and
## an interact reach the tree as different animations.
func action_clip() -> StringName:
	if _blend_tree == null:
		return &""
	var node: AnimationNodeAnimation = _blend_tree.get_node(
		AnimationTreeBuilder.NODE_ACTION_CLIP) as AnimationNodeAnimation
	return node.animation if node != null else &""


# --- per frame ---------------------------------------------------------------------------

## Presentation runs on the render clock, not the physics clock: the body is interpolated
## between physics ticks (DECISIONS #74) and the pose has to follow what is drawn.
func _process(delta: float) -> void:
	if _movement == null or _tree == null:
		return
	var s: MovementState = _movement.get_render_state()
	if s == null:
		return
	var speed: float = Vector2(s.vel.x, s.vel.z).length()
	var target: float = clampf(speed / _sprint_speed, 0.0, 1.0)
	# IDLE is authoritative about standing still: interpolation noise on a remote entity can
	# leave a few cm/s of velocity, which reads as a permanent shuffle.
	if s.move_state == MovementState.Move.IDLE:
		target = 0.0
	var follow: float = 1.0 - exp(-speed_smoothing * delta)
	_blend = lerpf(_blend, target, follow)
	if _strafing:
		# Sideways and backwards are their own clips, so the blend has to be stated in the
		# character's OWN frame: x is its right, y is its forward, whatever it is facing.
		var local: Vector3 = Basis(Vector3.UP, -s.yaw) * Vector3(s.vel.x, 0.0, s.vel.z)
		var want := Vector2(local.x, -local.z) / _sprint_speed
		if s.move_state == MovementState.Move.IDLE:
			want = Vector2.ZERO
		if want.length() > 1.0:
			want = want.normalized()
		_blend2 = _blend2.lerp(want, follow)
		_tree.set(AnimationTreeBuilder.P_BLEND, _blend2)
	else:
		_tree.set(AnimationTreeBuilder.P_BLEND, _blend)
	_turn_model(s, delta)
	_cancel_action_if_moving(s)
	_update_pose(delta, speed)
	_follow_state(s, delta)
	_action_weight = _ease_shot(_action_weight, AnimationTreeBuilder.NODE_ACTION,
		AnimationTreeBuilder.P_ACTION_ACTIVE, delta)
	_hit_weight = _ease_shot(_hit_weight, AnimationTreeBuilder.NODE_HIT,
		AnimationTreeBuilder.P_HIT_ACTIVE, delta)
	_upper_weight = _ease_shot(_upper_weight, AnimationTreeBuilder.NODE_UPPER,
		AnimationTreeBuilder.P_UPPER_ACTIVE, delta)
	_end_covered_upper()


## A one-shot over the WHOLE body (an action, a hit) stops Godot processing the upper-body one under
## it, which then plays the rest of its clip after: Luke saw the rod's draw play again after the
## cast it had been cut short for. Once one covers the body, the upper-body clip is over. (Under its
## fade-in the two blend, so the arms go from one to the other.)
func _end_covered_upper() -> void:
	if (_action_weight >= 1.0 or _hit_weight >= 1.0) and bool(_tree.get(AnimationTreeBuilder.P_UPPER_ACTIVE)):
		_tree.set(AnimationTreeBuilder.P_UPPER_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_upper_weight = 0.0


## HOW MUCH OF EACH ANIMATION THE BODY IS SHOWING, by semantic name, summing to 1: what a held
## item blends its per-animation grips by (`HeldItem`, DECISIONS #153). Read off the parameters
## this driver writes — the state, the locomotion blend (on the same line or plane the tree
## blends on), the held pose's weight — and the two one-shots, eased over their fades. A state
## machine's cross-fade is not modelled: whoever reads this eases it.
func semantic_weights() -> Dictionary[StringName, float]:
	var out: Dictionary[StringName, float] = {}
	if _tree == null or _blend_tree == null:
		return out
	match current_state():
		AnimationTreeBuilder.STATE_GROUNDED:
			out = _locomotion_weights()
		AnimationTreeBuilder.STATE_JUMP_START:
			out = {AnimationSet.JUMP_START: 1.0}
		AnimationTreeBuilder.STATE_AIR:
			out = {AnimationSet.JUMP_LOOP: 1.0}
		AnimationTreeBuilder.STATE_LAND:
			out = {_land_semantic: 1.0}
		AnimationTreeBuilder.STATE_DEAD:
			out = {AnimationSet.DEATH: 1.0}
		_:
			out = {AnimationSet.IDLE: 1.0}
	_layer(out, _pose_semantic, _pose_weight)
	_layer(out, _upper_semantic, _upper_weight)
	_layer(out, AnimationSet.HIT, _hit_weight)
	_layer(out, _action_semantic, _action_weight)
	return out


## `semantic` laid over the rest at `weight`: the rest shrinks to make room.
static func _layer(weights: Dictionary[StringName, float], semantic: StringName, weight: float) -> void:
	if semantic.is_empty() or weight <= 0.0:
		return
	var w: float = clampf(weight, 0.0, 1.0)
	for k: StringName in weights.keys():
		weights[k] = weights[k] * (1.0 - w)
	weights[semantic] = float(weights.get(semantic, 0.0)) + w


## The locomotion blend's points weighted as the tree weighs them at the current blend position.
func _locomotion_weights() -> Dictionary[StringName, float]:
	var sm: AnimationNodeStateMachine = _blend_tree.get_node(
		AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	var ground: AnimationRootNode = sm.get_node(AnimationTreeBuilder.STATE_GROUNDED) if sm != null else null
	var out: Dictionary[StringName, float] = {}
	var w: PackedFloat32Array = PackedFloat32Array()
	var names: Array[StringName] = []
	if ground is AnimationNodeBlendSpace2D:
		w = plane_weights(ground as AnimationNodeBlendSpace2D, _blend2)
		names = AnimationTreeBuilder.PLANE_POINTS
	elif ground is AnimationNodeBlendSpace1D:
		w = line_weights(ground as AnimationNodeBlendSpace1D, _blend)
		names = AnimationTreeBuilder.LINE_POINTS
	for i: int in range(mini(w.size(), names.size())):
		if w[i] > 0.0001:
			out[names[i]] = float(out.get(names[i], 0.0)) + w[i]
	if out.is_empty():
		out[AnimationSet.IDLE] = 1.0
	return out


## A BlendSpace1D's weights at `p`: the two points either side, shared linearly.
static func line_weights(line: AnimationNodeBlendSpace1D, p: float) -> PackedFloat32Array:
	var n: int = line.get_blend_point_count()
	var w := PackedFloat32Array()
	w.resize(n)
	var lo: int = -1
	var hi: int = -1
	for i: int in range(n):
		var x: float = line.get_blend_point_position(i)
		if x <= p and (lo < 0 or x > line.get_blend_point_position(lo)):
			lo = i
		if x >= p and (hi < 0 or x < line.get_blend_point_position(hi)):
			hi = i
	if lo < 0 and hi < 0:
		return w
	if lo < 0 or hi < 0 or lo == hi:
		w[lo if lo >= 0 else hi] = 1.0
		return w
	var a: float = line.get_blend_point_position(lo)
	var b: float = line.get_blend_point_position(hi)
	var t: float = (p - a) / maxf(b - a, 1e-6)
	w[lo] = 1.0 - t
	w[hi] = t
	return w


## A BlendSpace2D's weights at `p`, as Godot works them out: the barycentric weights of the
## triangle it lies in or, outside every triangle, of the nearest point on one.
static func plane_weights(plane: AnimationNodeBlendSpace2D, p: Vector2) -> PackedFloat32Array:
	var n: int = plane.get_blend_point_count()
	var w := PackedFloat32Array()
	w.resize(n)
	var best_tri: int = -1
	var best_point: Vector2 = p
	var best_d: float = INF
	for t: int in range(plane.get_triangle_count()):
		var tri: Array[Vector2] = []
		for k: int in range(3):
			tri.append(plane.get_blend_point_position(plane.get_triangle_point(t, k)))
		if Geometry2D.point_is_inside_triangle(p, tri[0], tri[1], tri[2]):
			best_tri = t
			best_point = p
			best_d = 0.0
			break
		for k: int in range(3):
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, tri[k], tri[(k + 1) % 3])
			var d: float = q.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best_tri = t
				best_point = q
	if best_tri < 0:
		return w
	var a: Vector2 = plane.get_blend_point_position(plane.get_triangle_point(best_tri, 0))
	var b: Vector2 = plane.get_blend_point_position(plane.get_triangle_point(best_tri, 1))
	var c: Vector2 = plane.get_blend_point_position(plane.get_triangle_point(best_tri, 2))
	var v0: Vector2 = b - a
	var v1: Vector2 = c - a
	var v2: Vector2 = best_point - a
	var den: float = v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		w[plane.get_triangle_point(best_tri, 0)] = 1.0
		return w
	var wb: float = (v2.x * v1.y - v1.x * v2.y) / den
	var wc: float = (v0.x * v2.y - v2.x * v0.y) / den
	var wa: float = 1.0 - wb - wc
	w[plane.get_triangle_point(best_tri, 0)] += clampf(wa, 0.0, 1.0)
	w[plane.get_triangle_point(best_tri, 1)] += clampf(wb, 0.0, 1.0)
	w[plane.get_triangle_point(best_tri, 2)] += clampf(wc, 0.0, 1.0)
	return w


## A one-shot's weight, eased toward whether it is playing over its own fade in or out.
func _ease_shot(weight: float, node_name: StringName, active_param: String, delta: float) -> float:
	var shot: AnimationNodeOneShot = _blend_tree.get_node(node_name) as AnimationNodeOneShot \
		if _blend_tree != null else null
	var on: bool = _tree != null and bool(_tree.get(active_param))
	var fade: float = 0.1
	if shot != null:
		fade = shot.fadein_time if on else shot.fadeout_time
	return move_toward(weight, 1.0 if on else 0.0, delta / maxf(fade, 0.001))


## The held pose, eased toward what was asked, let go while the body moves, and scrubbed to its
## point in the clip (a scale of 0 and a seek each frame) or left to loop.
func _update_pose(delta: float, speed: float) -> void:
	var target: float = _pose_target
	if action_cancel_speed > 0.0 and speed > action_cancel_speed and not _pose_while_moving:
		target = 0.0
	_pose_weight = move_toward(_pose_weight, target, pose_blend_rate * delta)
	_tree.set(AnimationTreeBuilder.P_POSE_BLEND, _pose_weight)
	if _pose_at >= 0.0 and _pose_length > 0.0:
		_tree.set(AnimationTreeBuilder.P_POSE_SCALE, 0.0)
		_tree.set(AnimationTreeBuilder.P_POSE_SEEK, clampf(_pose_at, 0.0, 1.0) * _pose_length)
	else:
		_tree.set(AnimationTreeBuilder.P_POSE_SCALE, 1.0)


## An action one-shot plays over whatever the body is doing, which is right for a hit reaction
## and wrong for a cast: start walking and the arms keep casting while the legs slide. Fading it
## out hands the body back to locomotion, the same bargain `land_cancel_speed` strikes.
##
## FADE rather than abort: an action cut dead mid-swing pops. The clip loses its ending, which is
## the point — the player has already told us they would rather be walking.
func _cancel_action_if_moving(s: MovementState) -> void:
	if action_cancel_speed <= 0.0 or _tree == null:
		return
	if not bool(_tree.get(AnimationTreeBuilder.P_ACTION_ACTIVE)):
		return
	if Vector2(s.vel.x, s.vel.z).length() <= action_cancel_speed:
		return
	_tree.set(AnimationTreeBuilder.P_ACTION_REQUEST,
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## The model eases round to the way the body faces. The body itself snaps, because its yaw is
## simulated state the server mirrors (DECISIONS #100) — easing it there would be a second,
## unsynchronised simulation. Written as a GLOBAL rotation so the parent's yaw does not count
## twice, plus whatever `visual_yaw_deg` the definition needed to face the model forwards.
func _turn_model(s: MovementState, delta: float) -> void:
	if _model == null or not _model.is_inside_tree():
		return
	var offset: float = 0.0
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent != null and ent.definition != null:
		offset = deg_to_rad(ent.definition.visual_yaw_deg)
	if not _shown_yaw_valid or turn_smoothing <= 0.0:
		_shown_yaw = s.yaw
		_shown_yaw_valid = true
	else:
		_shown_yaw = lerp_angle(_shown_yaw, s.yaw, 1.0 - exp(-turn_smoothing * delta))
	_model.global_rotation = Vector3(0.0, _shown_yaw + offset, 0.0)


func _follow_state(s: MovementState, delta: float) -> void:
	if _playback == null:
		return
	var cur: StringName = _effective_state(delta)
	if cur.is_empty():
		_playback.start(AnimationTreeBuilder.STATE_GROUNDED)
		_announce()
		return
	if _dead:
		if cur != AnimationTreeBuilder.STATE_DEAD:
			_travel(AnimationTreeBuilder.STATE_DEAD)
		return
	if cur == AnimationTreeBuilder.STATE_DEAD:
		_travel(AnimationTreeBuilder.STATE_GROUNDED)
		return
	if not s.grounded:
		_airborne_since_jump = true
		if cur != AnimationTreeBuilder.STATE_AIR and cur != AnimationTreeBuilder.STATE_JUMP_START:
			_travel(AnimationTreeBuilder.STATE_AIR)
	elif cur == AnimationTreeBuilder.STATE_AIR \
			or (cur == AnimationTreeBuilder.STATE_JUMP_START and _airborne_since_jump):
		# Grounded again without a `landed` event: a remote entity whose row simply says so.
		_travel(AnimationTreeBuilder.STATE_LAND)
	elif cur == AnimationTreeBuilder.STATE_LAND \
			and Vector2(s.vel.x, s.vel.z).length() > land_cancel_speed:
		# Running out of a landing: the clip is a recovery from a stop, and watching it finish
		# while the character is already moving is the skate the player sees.
		_travel(AnimationTreeBuilder.STATE_GROUNDED)
	elif cur != AnimationTreeBuilder.STATE_GROUNDED and cur != AnimationTreeBuilder.STATE_LAND \
			and cur != AnimationTreeBuilder.STATE_JUMP_START:
		# JumpStart is left out on purpose: a take-off plays out while the feet are still down.
		_travel(AnimationTreeBuilder.STATE_GROUNDED)
	_announce()


# --- events ------------------------------------------------------------------------------

func _on_jumped() -> void:
	_airborne_since_jump = false
	_travel(AnimationTreeBuilder.STATE_JUMP_START)


func _on_landed(impact_speed: float) -> void:
	var heavy: bool = absf(impact_speed) >= heavy_land_speed
	_land_semantic = AnimationSet.JUMP_LAND_HEAVY if heavy else AnimationSet.JUMP_LAND
	_set_state_clip(AnimationTreeBuilder.STATE_LAND, _land_semantic)
	_travel(AnimationTreeBuilder.STATE_LAND)


## The server overrode the path the jump was predicted on. The clip cannot un-play, but the
## state machine must not sit in the air for a jump that did not happen.
func _on_event_revoked(kind: StringName, _event_id: int) -> void:
	if kind != &"jumped" or _movement == null:
		return
	var s: MovementState = _movement.get_render_state()
	if s != null and s.grounded:
		_travel(AnimationTreeBuilder.STATE_GROUNDED)


func _on_damaged(_amount: float, _source_id: int) -> void:
	_fire(AnimationTreeBuilder.NODE_HIT_CLIP, AnimationTreeBuilder.P_HIT_REQUEST, AnimationSet.HIT)


func _on_died(_killer_id: int) -> void:
	_dead = true
	_travel(AnimationTreeBuilder.STATE_DEAD)


func _on_revived() -> void:
	_dead = false
	_travel(AnimationTreeBuilder.STATE_GROUNDED)


func _on_interact_requested(_target_id: int) -> void:
	_fire(AnimationTreeBuilder.NODE_ACTION_CLIP, AnimationTreeBuilder.P_ACTION_REQUEST,
		AnimationSet.INTERACT)


## A genre names its ability clips `ability.<id>`; anything it has not authored falls back to
## the interact clip rather than playing nothing.
func _on_action_started(ability_id: int, _predicted_id: int) -> void:
	var semantic: StringName = StringName("ability.%d" % ability_id)
	if animation_set != null and not animation_set.has_exact(semantic):
		semantic = AnimationSet.INTERACT
	_fire(AnimationTreeBuilder.NODE_ACTION_CLIP, AnimationTreeBuilder.P_ACTION_REQUEST, semantic)


# --- internals ---------------------------------------------------------------------------

func _install() -> bool:
	var model: Node3D = entity.get_node_or_null(model_path) as Node3D if entity != null else null
	if model == null:
		push_warning("AnimationDriverComponent: entity %d has an animation set but no model at %s"
			% [entity_id, model_path])
		return false
	var skel: Skeleton3D = _find_skeleton(model)
	if skel == null:
		push_warning("AnimationDriverComponent: the model on entity %d has no Skeleton3D; is "
			% entity_id + "its visual_scene a rigged character?")
		return false
	# Track paths were normalised onto this name when the library was extracted
	# (tools/extract_animation_library.gd), so the library plays on any model laid out any way.
	if skel.name != &"Skeleton3D":
		skel.name = "Skeleton3D"
	var dangling: Array[StringName] = animation_set.dangling_clips()
	if not dangling.is_empty():
		push_warning("AnimationDriverComponent: %s name clips their libraries do not have"
			% str(dangling))

	_tree = AnimationTreeBuilder.build(animation_set)
	if _tree == null:
		return false
	_model = model
	_strafing = AnimationTreeBuilder.is_strafing(animation_set)
	_blend_tree = _tree.tree_root as AnimationNodeBlendTree
	model.add_child(_tree)
	_tree.root_node = _tree.get_path_to(skel.get_parent())
	_tree.active = true
	_playback = _tree.get(AnimationTreeBuilder.P_PLAYBACK) as AnimationNodeStateMachinePlayback
	return _playback != null


func _connect_siblings() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_movement = ent.find_component(SpaceTimeMovementComponent) as SpaceTimeMovementComponent
	if _movement != null:
		_movement.jumped.connect(_on_jumped)
		_movement.landed.connect(_on_landed)
		_movement.event_revoked.connect(_on_event_revoked)
	var health: SpaceTimeHealthComponent = ent.find_component(
		SpaceTimeHealthComponent) as SpaceTimeHealthComponent
	if health != null:
		health.damaged.connect(_on_damaged)
		health.died.connect(_on_died)
		health.revived.connect(_on_revived)
	var action: SpaceTimeActionComponent = ent.find_component(
		SpaceTimeActionComponent) as SpaceTimeActionComponent
	if action != null:
		action.action_started.connect(_on_action_started)
	var interaction: InteractionComponent = ent.find_component(
		InteractionComponent) as InteractionComponent
	if interaction != null:
		interaction.interact_requested.connect(_on_interact_requested)


## What the state machine is doing as far as the driver is concerned: what it asked for while
## that is still outstanding, otherwise what the machine reports.
func _effective_state(delta: float) -> StringName:
	var cur: StringName = _playback.get_current_node()
	if _asked.is_empty():
		return cur
	if cur == _asked:
		_asked = &""
		return cur
	_asked_age += delta
	if _asked_age >= ASK_TIMEOUT_SEC:
		_asked = &""
		return cur
	return _asked


func _travel(state: StringName) -> void:
	if _playback == null or _playback.get_current_node() == state or _asked == state:
		return
	# Re-issuing travel() to a state we are already crossing into restarts the fade, and a
	# caller that asks every frame (this component does) never gets there.
	var path: PackedStringArray = _playback.get_travel_path()
	if path.size() > 0 and StringName(path[path.size() - 1]) == state:
		return
	_asked = state
	_asked_age = 0.0
	_playback.travel(state)
	_announce()


func _announce() -> void:
	var now: StringName = current_state()
	if now == _state:
		return
	_state = now
	state_changed.emit(now)


func _set_state_clip(state: StringName, semantic: StringName) -> void:
	if _blend_tree == null or animation_set == null:
		return
	var sm: AnimationNodeStateMachine = _blend_tree.get_node(
		AnimationTreeBuilder.NODE_BODY) as AnimationNodeStateMachine
	if sm == null:
		return
	AnimationTreeBuilder.apply_clip(sm.get_node(state) as AnimationNodeAnimation,
		animation_set, semantic)


func _fire(clip_node: StringName, request_param: String, semantic: StringName) -> void:
	if _tree == null or _blend_tree == null or animation_set == null:
		return
	var node: AnimationNodeAnimation = _blend_tree.get_node(clip_node) as AnimationNodeAnimation
	if not AnimationTreeBuilder.apply_clip(node, animation_set, semantic):
		return
	if clip_node == AnimationTreeBuilder.NODE_ACTION_CLIP:
		_action_semantic = semantic
	elif clip_node == AnimationTreeBuilder.NODE_UPPER_CLIP:
		_upper_semantic = semantic
	_tree.set(request_param, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _find_skeleton(n: Node) -> Skeleton3D:
	var as_skel: Skeleton3D = n as Skeleton3D
	if as_skel != null:
		return as_skel
	for c: Node in n.get_children():
		var found: Skeleton3D = _find_skeleton(c)
		if found != null:
			return found
	return null
