class_name ShowcaseActor extends SpaceTimeEntity
## A CHARACTER THAT ACTS, WITH NO SERVER (the showcase, 2026-11-15): the login screen's people, the vista's and the
## battle lab's fighters. Built from the GAME'S OWN PARTS, so it moves and plays as a character in the game does
## (Luke, 2026-11-15: the first cut set positions by hand and played raw clips, and walked, struck and slid wrong):
##   - its body is the game's `MovementModel` with its character's movement config (`ShowcaseMovement`): it gets going,
##     brakes, turns and rolls as the game's bodies do, from inputs (`walk_to` steers it like a held key);
##   - its pose is the game's `AnimationDriverComponent` on the generated tree (`AnimationTreeBuilder`): the
##     locomotion blend matched to its speed, the model easing round to its facing, the swings' root travel taken
##     out, two action slots cross-fading swing into swing, the hit, the fall, held poses on the body or the arms;
##   - a swing is shown as `CombatComponent` shows one (`_began`): its clip held to just after the hit, then its
##     recovery (`recover.<id>`) cross-faded in; a ranged player's shot is an upper-body clip, a foe's every move a
##     whole-body one (the imp's cast is its tell, then its release); a roll is the dodge's dash and its clip.
## It ships (the login uses it): never the workbench's `Mannequin` (tools/ stays out of the build).
##
## Presentation only (hard rule 11): it decides nothing; a lab's timeline tells it what to do and where to go.
##
##   play(&"pose.smith")                    hold a pose (the body, or the arms for a draw, a cast, a guard)
##   play(&"locomotion.idle")               let go of any pose (and stand up from a fall)
##   act(&"ability.40001")                  a swing, a shot, a cast's release; `react.hit`, `react.stagger`, `react.death`
##   walk_to(Vector3(4, 0, 2), 1.6)        walk (run, sprint: by the speed asked) there as a held key would
##   roll(direction)                        the dodge roll that way
##   face(point)                            turn toward a point (the body at once, the model easing round)

## A move asked at this speed (m/s) or faster runs; slower walks.
@export_range(0.5, 10.0, 0.1, "suffix:m/s") var run_from_mps: float = 2.4
## A move asked at this speed or faster sprints.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var sprint_from_mps: float = 6.5
## Close enough to where it was sent (m).
@export_range(0.01, 1.0, 0.01, "suffix:m") var arrive_m: float = 0.06

## Where the ground is under a point (x, z) -> y; unset: the movement's flat ground. The world sets it.
var ground: Callable = Callable():
	set(v):
		ground = v
		if movement != null:
			movement.ground = v

var model: Node3D = null
var skeleton: Skeleton3D = null
var held: HeldItem = null
var foe: FoeDef = null
var movement: ShowcaseMovement = null
var driver: AnimationDriverComponent = null
var health: SpaceTimeHealthComponent = null

static var _next_id: int = 9_100_000

var _goal: Vector3 = Vector3.INF
var _gait: int = 0
var _dash_on_go: bool = false
var _face_at: Vector3 = Vector3.INF
var _roll_left: float = 0.0
var _roll_dir: Vector2 = Vector2.ZERO
var _roll_dashed: bool = false
## Game seconds the action is held whatever the body does, and the model faces its motion (the driver's own
## timers run on the wall clock, which a slowed shot or a film rendered slower than real time outruns).
var _commit_left: float = 0.0
var _face_motion_left: float = 0.0
var _recover_in: float = -1.0
var _recover_semantic: StringName = &""
var _recover_strike: StringName = &""
var _pose: StringName = &""
var _upper_pose: StringName = &""
## Down: it stays on the fall's last frame until `play` stands it up.
var _holding: bool = false
var _now: StringName = AnimationSet.IDLE
var _once_left: float = 0.0
## Where it was last drawn (to tell a move from outside).
var _drawn_at: Vector3 = Vector3.ZERO

## Poses the game holds on the arms only (`CombatComponent`'s draw, aim, cast, channel; the guard).
const UPPER_POSES: Array[StringName] = [&"pose.bow_draw", &"pose.bow_aim", &"pose.spell_cast", &"pose.spell_channel",
	&"pose.block"]


## Build it: `def`'s look `look` (an index into its `visual_variants`), holding `weapon` (a held item's scene) or, for
## a foe, dressed as `foe_def` says (its texture, the meshes it hides, what it holds).
static func make(def: EntityDefinition, look: int = 0, weapon: PackedScene = null, foe_def: FoeDef = null) -> ShowcaseActor:
	var a := ShowcaseActor.new()
	a.definition = def
	a.foe = foe_def
	a._build(look, weapon)
	return a


func _build(look: int, weapon: PackedScene) -> void:
	if definition == null:
		return
	var scene: PackedScene = definition.visual_scene
	if not definition.visual_variants.is_empty():
		scene = definition.visual_variants[clampi(look, 0, definition.visual_variants.size() - 1)]
	if scene == null:
		return
	# As the game's entity lays a character out (`SpaceTimeEntity._apply_presentation`): Visual/Model.
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	model = scene.instantiate() as Node3D
	model.name = "Model"
	visual.add_child(model)
	model.position = definition.visual_offset
	model.rotation.y = deg_to_rad(definition.visual_yaw_deg)
	model.scale = Vector3.ONE * definition.visual_scale
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = n as Skeleton3D
		break
	if skeleton != null and skeleton.name != &"Skeleton3D":
		# The set's clips address "Skeleton3D" (as the game's spawner and the Mannequin rename it).
		var own: AnimationPlayer = ClipMatcher.model_player(model)
		if own != null:
			var from: Node = own.get_node_or_null(own.root_node)
			for lib: StringName in own.get_animation_library_list():
				var copy: AnimationLibrary = ClipMatcher.readdressed(own.get_animation_library(lib), from, skeleton)
				own.remove_animation_library(lib)
				own.add_animation_library(lib, copy)
			own.root_node = own.get_path_to(skeleton.get_parent())
		skeleton.name = "Skeleton3D"
	if skeleton != null:
		if foe != null:
			_dress_as(foe)
		elif weapon != null:
			held = HeldItem.attach(skeleton, weapon)
	var holder := Node.new()
	holder.name = "Components"
	add_child(holder)
	movement = ShowcaseMovement.new()
	movement.name = "Movement"
	movement.config = definition.movement_config()
	movement.ground = ground
	movement.steer = _steer
	add_runtime_component(movement)
	driver = AnimationDriverComponent.new()
	driver.name = "AnimationDriver"
	driver.animation_set = definition.animation_set
	add_runtime_component(driver)
	# Never bound (it has no row): its signals are how the driver hears of a hit, a fall, a getting up.
	health = SpaceTimeHealthComponent.new()
	health.name = "Health"
	add_runtime_component(health)


func _ready() -> void:
	super()
	# Bound here, after `_ready` (hard rule 8), as the spawner binds a character it has just added; ours to pose
	# every frame (`is_local_authority`: the animation rate's full rate).
	entity_id = _next_id
	_next_id += 1
	is_local_authority = true
	movement.bind(self, {})
	if driver.animation_set != null:
		driver.bind(self, {})
	movement.place(position, movement.now_state().yaw)
	position = movement.get_render_state().pos
	_drawn_at = position


func _dress_as(f: FoeDef) -> void:
	for n: Node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n as MeshInstance3D
		if f.hidden_meshes.has(StringName(mi.name)):
			mi.visible = false
			continue
		if f.albedo == null or mi.mesh == null:
			continue
		for i: int in range(mi.mesh.get_surface_count()):
			var base: BaseMaterial3D = mi.get_active_material(i) as BaseMaterial3D
			if base == null:
				continue
			var mat: BaseMaterial3D = base.duplicate() as BaseMaterial3D
			mat.albedo_texture = f.albedo
			mi.set_surface_override_material(i, mat)
	if f.held_scene != null:
		held = HeldItem.attach(skeleton, f.held_scene)


# ------------------------------------------------------------------------------------------------ asking

## Hold `semantic` from now on: a pose (the arms only for a draw, an aim, a cast, a guard; else the body, let go
## while it moves, as the game's), or `locomotion.*` to let go of any (and get up from a fall). False when its set
## has nothing for it.
func play(semantic: StringName) -> bool:
	if _holding:
		_holding = false
		health.revived.emit()
	if String(semantic).begins_with("locomotion."):
		_pose = &""
		_upper_pose = &""
		if driver != null:
			driver.release_pose()
			driver.release_upper_pose()
		if _once_left <= 0.0:
			_now = _loop_now()
		return has(semantic)
	if not has(semantic):
		return false
	if UPPER_POSES.has(semantic):
		_upper_pose = semantic
		_pose = &""
		driver.release_pose()
	else:
		_pose = semantic
		_upper_pose = &""
		driver.release_upper_pose()
	if _once_left <= 0.0:
		_now = semantic
	return true


## Do `semantic` once, as the game shows it: `ability.<id>` a swing (held to its hit, then its recovery), a ranged
## player's shot or cast's release (on the arms), the dodge roll (forward); `react.hit` a flinch, `react.stagger`
## the stagger, `react.death` the fall (it stays down; `hold` is kept for the labs' calls and changes nothing). Its
## length (s), or 0 when its set has no clip for it.
func act(semantic: StringName, _hold: bool = false) -> float:
	if driver == null or not has(semantic):
		return 0.0
	var secs: float = clip_length(semantic)
	if semantic == AnimationSet.DEATH:
		_holding = true
		_goal = Vector3.INF
		_roll_left = 0.0
		_recover_in = -1.0
		_pose = &""
		_upper_pose = &""
		health.died.emit(0)
	elif semantic == AnimationSet.HIT:
		health.damaged.emit(1.0, 0)
	elif String(semantic).begins_with("ability."):
		var a: AbilityDef = ContentLibrary.find(&"ability", int(String(semantic).get_slice(".", 1))) as AbilityDef
		if a != null and a.rolls:
			roll(_forward())
			return secs
		if foe == null and _on_the_arms(a):
			driver.play_upper(semantic)
		else:
			_swing(semantic, a)
	else:
		driver.play_action(semantic)
	_now = semantic
	_once_left = secs
	return secs


## The dodge roll toward `direction` (world; its length is the roll's): the dash and the roll's clip, the model
## facing the way it goes, as `RollComponent` does. False when it has no roll.
func roll(direction: Vector3) -> bool:
	var a: AbilityDef = definition.dodge_roll if definition != null else null
	if a == null or driver == null or _holding:
		return false
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector2(_forward().x, _forward().z)
	_roll_dir = flat.normalized()
	_roll_left = float(RollComponent.length_of(a)) / 1000.0
	_roll_dashed = false
	_goal = Vector3.INF
	var semantic := StringName("ability.%d" % a.id)
	driver.play_action(semantic)
	var s: float = driver.shot_seconds(semantic)
	if s <= 0.0:
		s = _roll_left
	_commit_for(s)
	_face_motion_left = s
	driver.face_motion(s)
	_now = semantic
	_once_left = s
	return true


## Does its set have a clip for `semantic`?
func has(semantic: StringName) -> bool:
	return definition != null and definition.animation_set != null and definition.animation_set.clip(semantic) != null


## How long `semantic` runs as the game plays it (s); 0 when there is no such clip.
func clip_length(semantic: StringName) -> float:
	if not has(semantic):
		return 0.0
	# The driver's `shot_seconds`: the clip's length at its set's speed.
	var ref: AnimationClipRef = definition.animation_set.clip(semantic)
	var length: float = AnimationTreeBuilder.clip_length(definition.animation_set, semantic)
	return length / ref.speed_scale if ref.speed_scale > 0.0 else length


## What it is doing now: the one-shot while it runs (the fall after, while it is down), the walk or run while it
## moves, the held pose, else the idle.
func playing() -> StringName:
	return _now


## Walk to `to` as a held key would: below `run_from_mps` it walks, from there it runs, from `sprint_from_mps` it
## sprints (its own config's speeds); it brakes to a stop there. Speed 0 places it at once. `dash`: it goes with a
## burst (a wolf's lunge), as its config's dash gives one.
func walk_to(to: Vector3, speed: float, dash: bool = false) -> void:
	if speed <= 0.0:
		_goal = Vector3.INF
		_roll_left = 0.0
		movement.place(to, movement.now_state().yaw)
		position = movement.get_render_state().pos
		_drawn_at = position
		return
	_goal = to
	_gait = 2 if speed >= sprint_from_mps else (1 if speed >= run_from_mps else 0)
	_dash_on_go = dash
	if _once_left <= 0.0 and not _holding:
		_now = _loop_now()


## Is it still on its way somewhere?
func moving() -> bool:
	return _goal != Vector3.INF or _roll_left > 0.0


## Turn toward `at` (world) and keep facing it while it stands; `now`: the body turns this instant (the model eases
## round, as the game's does).
func face(at: Vector3, now: bool = false) -> void:
	_face_at = at
	if now and movement != null:
		var d: Vector3 = at - movement.now_state().pos
		if Vector2(d.x, d.z).length_squared() > 0.0001:
			var s: MovementState = movement.now_state()
			movement.place(s.pos, yaw_toward(d))


## The way its body faces (world, flat).
func facing() -> Vector3:
	return _forward()


## Where a bone is now (world), or INF.
func bone_position(bone: StringName) -> Vector3:
	if skeleton == null or not skeleton.is_inside_tree():
		return Vector3.INF
	var i: int = skeleton.find_bone(bone)
	return skeleton.to_global(skeleton.get_bone_global_pose(i).origin) if i >= 0 else Vector3.INF


## The yaw that faces along `d` (the game's: forward is -Z at yaw 0).
static func yaw_toward(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


# ------------------------------------------------------------------------------------------------ time

func _process(delta: float) -> void:
	_tick(delta)


## One frame of it by hand, the pose too (a suite, with processing off).
func step(delta: float) -> void:
	_tick(delta)
	if driver != null and not driver.is_processing() and driver.animation_tree() != null:
		driver._process(delta)


func _tick(delta: float) -> void:
	if movement == null:
		return
	# Moved from outside since it was last drawn (a blink carries its caster): the body is put there, as a teleport.
	if position.distance_to(_drawn_at) > 0.001:
		movement.place(position, movement.now_state().yaw)
		_goal = Vector3.INF
	if _commit_left > 0.0:
		_commit_left = maxf(_commit_left - delta, 0.0)
		driver.commit_action(_commit_left)
	if _face_motion_left > 0.0:
		_face_motion_left = maxf(_face_motion_left - delta, 0.0)
		driver.face_motion(_face_motion_left)
	if _recover_in >= 0.0:
		_recover_in -= delta
		if _recover_in < 0.0 and driver.action_playing() and driver.action_clip() == _recover_strike:
			driver.play_action(_recover_semantic)
	if _roll_left > 0.0:
		_roll_left = maxf(_roll_left - delta, 0.0)
	if _once_left > 0.0:
		_once_left -= delta
		if _once_left <= 0.0 and not _holding:
			_now = _loop_now()
	if not _holding and driver != null:
		if _pose != &"":
			driver.hold_pose(_pose, 1.0)
		if _upper_pose != &"":
			driver.hold_upper_pose(_upper_pose, 1.0)
	movement.advance(delta)
	position = movement.get_render_state().pos
	_drawn_at = position


## The next tick's input, as a player's keys would give it: the roll's way while it rolls, toward where it is going
## (braking in time to stop there), else turned to what it faces.
func _steer() -> InputFrame:
	var f := InputFrame.new()
	var s: MovementState = movement.now_state()
	f.look_yaw = s.yaw
	if _holding:
		return f
	if _roll_left > 0.0:
		f.move_dir = _roll_dir
		f.dash = not _roll_dashed
		_roll_dashed = true
		return f
	if _goal != Vector3.INF:
		var d := Vector3(_goal.x - s.pos.x, 0.0, _goal.z - s.pos.z)
		var dist: float = d.length()
		var speed: float = Vector2(s.vel.x, s.vel.z).length()
		var friction: float = maxf(movement.config.friction if movement.config != null else 60.0, 0.1)
		if dist <= maxf(arrive_m, speed * speed / (2.0 * friction)):
			_goal = Vector3.INF
			if _once_left <= 0.0:
				_now = _loop_now()
		else:
			var dir: Vector3 = d / dist
			f.move_dir = Vector2(dir.x, dir.z)
			f.look_yaw = yaw_toward(dir)
			f.slow = _gait == 0
			f.sprint = _gait == 2
			f.dash = _dash_on_go
			_dash_on_go = false
			return f
	if _face_at != Vector3.INF:
		var t := Vector3(_face_at.x - s.pos.x, 0.0, _face_at.z - s.pos.z)
		if t.length_squared() > 0.0001:
			f.face = true
			f.look_yaw = yaw_toward(t)
	return f


# ------------------------------------------------------------------------------------------------ the game's ways

## A swing as `CombatComponent._began` shows one: the driver fires the ability's clip (the interact, when the set has
## none: `_on_action_started`), held to just after its hit (a lunge its whole clip), and its recovery cross-faded
## in as the strike ends (`_plan_recovery`).
func _swing(semantic: StringName, a: AbilityDef) -> void:
	var fired: StringName = semantic if definition.animation_set.has_exact(semantic) else AnimationSet.INTERACT
	driver.play_action(fired)
	if a == null:
		return
	var strike_s: float = driver.shot_seconds(semantic)
	_commit_for(CombatComponent.commit_seconds(a, strike_s))
	_recover_semantic = StringName("recover.%d" % a.id)
	_recover_in = -1.0
	if definition.animation_set.has_exact(_recover_semantic):
		var strike: AnimationClipRef = definition.animation_set.clip(semantic)
		_recover_strike = strike.anim_name if strike != null else &""
		_recover_in = maxf(strike_s - CombatComponent.RECOVER_LEAD_S, 0.0)


func _commit_for(seconds: float) -> void:
	_commit_left = maxf(seconds, 0.0)
	driver.commit_action(_commit_left)


## Whether a player shows `a` on the arms, the legs free: a spell's release or a bow's loose (`CombatComponent`'s
## `play_upper`), never a melee swing.
func _on_the_arms(a: AbilityDef) -> bool:
	if a == null:
		return false
	for k: KitDef in KitDef.all():
		if not k.abilities().has(a):
			continue
		# A casting kit's spell (`CombatComponent.cast`), or a drawing kit's shot (`loose`).
		if k.casts() and SpellDef.by_ability(a.id) != null:
			return true
		if k.draws and not k.light.is_empty() and k.light[0] == a:
			return true
	return false


## What it is doing between one-shots.
func _loop_now() -> StringName:
	if _holding:
		return AnimationSet.DEATH
	if _goal != Vector3.INF:
		return [AnimationSet.WALK, AnimationSet.RUN, AnimationSet.SPRINT][_gait]
	if _pose != &"":
		return _pose
	if _upper_pose != &"":
		return _upper_pose
	return AnimationSet.IDLE


func _forward() -> Vector3:
	var yaw: float = movement.now_state().yaw if movement != null else 0.0
	return Vector3(-sin(yaw), 0.0, -cos(yaw))
