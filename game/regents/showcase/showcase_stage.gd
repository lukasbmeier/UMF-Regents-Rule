class_name ShowcaseStage extends Node3D
## THE SHOWCASE LABS' STAGE (2026-11-15): the valley (`ShowcaseWorld`), a camera that plays the lab's `shots`
## (`ShowcaseShot`s, in its scene), fades between them, letterbox bars, and three ways to run:
##
##   F6 in the editor (or no arguments)   look round: Left/Right a shot, 1-9 jump, Space pause, M the next mood,
##                                        F the free camera (WASD, Q/E down/up, hold RMB to look, wheel speed;
##                                        C prints where it is, for a shot), L the bars, H the help, P a still
##   -- stills <dir>                      every shot's still (at its `still_at`) as <dir>/<n>_<title>.png, then quits
##   -- reel                              every shot once, back to back, then quits (with --write-movie: a film)
##   -- clip <n>                          shot n once, then quits
##
## A lab extends this: `_cast()` puts its people on the stage once, `_reset_cast()` before each shot, and a shot's
## `beat` names a method of the lab that sets them moving.
##
##   godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie out.avi res://<lab>.tscn -- reel

@export var shots: Array[ShowcaseShot] = []
## The mood a shot with none plays in.
@export var mood: ShowcaseMood = null
@export_range(0.2, 1.0, 0.05) var detail: float = 1.0
## The bars (an aspect: 2.39 a film's; 0 none) and the fade between shots (s).
@export_range(0.0, 3.0, 0.01) var letterbox: float = 2.39
@export_range(0.0, 3.0, 0.05, "suffix:s") var fade_s: float = 0.6

var world: ShowcaseWorld = null
var camera: Camera3D = null
var _attrs: CameraAttributesPractical = null
var _shot_i: int = -1
var _t: float = 0.0
var _paused: bool = false
var _free: bool = false
var _free_speed: float = 6.0
var _looking: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _mode: String = ""
var _out_dir: String = ""
var _mood_override: int = -1
var _moods: Array[ShowcaseMood] = []
var _ui: CanvasLayer = null
var _help: Label = null
var _bars: Array[ColorRect] = []
var _fade: ColorRect = null
var _clock: float = 0.0
var _still_taken: bool = false
var _done: bool = false
## Effects kept at a body's hands as they move: [effect, actor, bones, ahead_m, toward].
var _follow: Array[Array] = []
## Everything a beat spawned (effects, arrows), freed when the next shot starts.
var _spawned: Array = []
var _shake: float = 0.0
## A beat's timeline: [game time (s) since the shot began, what to do], and that clock.
var _cues: Array[Array] = []
var _game_t: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 0.0

const FX: String = "res://game/regents/vfx/effects/"
## The least a camera stands over the land (m).
const CAMERA_ABOVE_M: float = 0.6


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Only the three ways to run (a test runner's own arguments are none of them).
	if args.size() > 0 and args[0] in ["stills", "reel", "clip"]:
		_mode = args[0]
	if _mode == "stills" and args.size() > 1:
		_out_dir = args[1]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	for f: String in ["dawn", "day", "golden", "dusk", "night"]:
		_moods.append(load("res://game/regents/showcase/moods/%s.tres" % f) as ShowcaseMood)
	world = ShowcaseWorld.new()
	world.name = "World"
	world.detail = detail
	world.mood = mood
	world.clear_paths = _views()
	world.clearings = _clearings()
	add_child(world)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.far = 3000.0
	camera.near = 0.08
	# Moved every frame by the shot, not by physics.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_attrs = CameraAttributesPractical.new()
	camera.attributes = _attrs
	add_child(camera)
	camera.make_current()
	_build_ui()
	_cast()
	if shots.is_empty():
		return
	var first: int = 0
	if _mode == "clip" and args.size() > 1:
		first = clampi(int(args[1]), 0, shots.size() - 1)
	_start_shot(first)


## Every shot's line of sight, from where its camera stands most of the way to what it looks at (at most 70 m), and
## the people's ground: kept clear of trees and rocks.
func _views() -> Array[Array]:
	var out: Array[Array] = []
	for s: ShowcaseShot in shots:
		for u: float in [0.0, 0.5, 1.0]:
			var p: Array = s.at_time(u)
			var eye: Vector3 = p[0]
			var at: Vector3 = p[1]
			var reach: Vector3 = eye + (at - eye).limit_length(minf(eye.distance_to(at) * 0.75, 70.0))
			out.append([eye, reach, 5.0])
	return out


## Do `f` `seconds` (game time) from now: a beat's timeline.
func after(seconds: float, f: Callable) -> void:
	var at: float = _game_t + seconds
	var i: int = 0
	while i < _cues.size() and float(_cues[i][0]) <= at:
		i += 1
	_cues.insert(i, [at, f])


## Every frame (game time): a lab's own clockwork.
func _tick(_delta: float) -> void:
	pass


## An effect from `vfx/effects/<scene>.tscn` at `at`, facing `toward` (a point), aimed at `target`; `prep` sets it up
## before it enters the tree (where it starts). Freed with the shot.
func spawn_fx(scene: String, at: Vector3, toward: Vector3 = Vector3.INF, target: Vector3 = Vector3.ZERO,
		who: Node3D = null, prep: Callable = Callable()) -> VfxEffect:
	var fx: VfxEffect = (load(FX + scene + ".tscn") as PackedScene).instantiate() as VfxEffect
	fx.target = target
	fx.caster = who
	if prep.is_valid():
		prep.call(fx)
	fx.shook.connect(func(strength: float, seconds: float) -> void:
		_shake = strength
		_shake_left = seconds
		_shake_total = seconds)
	fx.position = at
	if toward != Vector3.INF:
		var flat: Vector3 = Vector3(toward.x, at.y, toward.z) - at
		if flat.length() > 0.01:
			fx.basis = Basis.looking_at(flat, Vector3.UP)
	add_child(fx)
	_spawned.append(fx)
	return fx


## Where a spell leaves `who`'s hand(s): the bones' middle, `ahead_m` on toward `toward`.
func cast_point(who: ShowcaseActor, bones: Array, ahead_m: float, toward: Vector3) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var n: int = 0
	for b: Variant in bones:
		var p: Vector3 = who.bone_position(b as StringName)
		if p != Vector3.INF:
			sum += p
			n += 1
	if n == 0:
		return who.global_position + Vector3(0, 1.3, 0)
	var at: Vector3 = sum / float(n)
	var dir: Vector3 = toward - at
	return at + dir.normalized() * ahead_m if dir.length() > 0.01 else at


## A charge held in front of `who`'s hand(s) as the pose moves them.
func charge(scene: String, who: ShowcaseActor, bones: Array, ahead_m: float, toward: Vector3, seconds: float) -> VfxEffect:
	var fx: VfxEffect = spawn_fx(scene, cast_point(who, bones, ahead_m, toward), Vector3.INF, Vector3.ZERO, null,
		func(e: VfxEffect) -> void: e.duration_s = seconds)
	_follow.append([fx, who, bones, ahead_m, toward])
	return fx


func _keep_following() -> void:
	for i: int in range(_follow.size() - 1, -1, -1):
		var f: Array = _follow[i]
		var fx: Variant = f[0]
		if not is_instance_valid(fx):
			_follow.remove_at(i)
			continue
		(fx as Node3D).global_position = cast_point(f[1] as ShowcaseActor, f[2] as Array, float(f[3]), f[4] as Vector3)


func _clear_spawned() -> void:
	for n: Variant in _spawned:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_spawned.clear()
	_follow.clear()
	_shake_left = 0.0


## The lab's trodden ground: (x, z, radius m), kept clear of bushes and tall grass. The camp's by default.
func _clearings() -> Array[Vector3]:
	return [Vector3(0.0, 0.0, 8.0)]


## The lab's people, put on the stage once.
func _cast() -> void:
	pass


## Before each shot: everyone back to their marks.
func _reset_cast() -> void:
	pass


func shot() -> ShowcaseShot:
	return shots[_shot_i] if _shot_i >= 0 and _shot_i < shots.size() else null


func _start_shot(i: int) -> void:
	_shot_i = posmod(i, shots.size())
	_t = 0.0
	_still_taken = false
	var s: ShowcaseShot = shot()
	var m: ShowcaseMood = s.mood if s.mood != null else mood
	if _mood_override >= 0:
		m = _moods[_mood_override]
	if m != null and world.mood != m:
		world.mood = m
	Engine.time_scale = s.time_scale
	_clear_spawned()
	_cues.clear()
	_game_t = 0.0
	_reset_cast()
	if s.beat != &"" and has_method(s.beat):
		call(s.beat)
	_place_camera(0.0)
	_update_help()


func _process(delta: float) -> void:
	# The camera keeps real time through a slow-motion shot.
	var real: float = delta / maxf(Engine.time_scale, 0.0001)
	_clock += real
	_keep_following()
	_game_t += delta
	while not _cues.is_empty() and float(_cues[0][0]) <= _game_t:
		var c: Array = _cues.pop_front()
		(c[1] as Callable).call()
	_tick(delta)
	if _free:
		_fly(real)
		return
	var s: ShowcaseShot = shot()
	if s == null or _done:
		return
	if not _paused:
		_t += real
	var u: float = _t / s.seconds
	_place_camera(u)
	_fade_for(s)
	if _mode == "stills" and not _still_taken and u >= s.still_at:
		_still_taken = true
		_take_still()
		return
	if u >= 1.0:
		if _mode == "clip" or ((_mode == "reel" or _mode == "stills") and _shot_i == shots.size() - 1):
			_finish()
		elif _mode != "stills" or _still_taken:
			_start_shot(_shot_i + 1)


func _place_camera(u: float) -> void:
	var s: ShowcaseShot = shot()
	if s == null:
		return
	var p: Array = s.at_time(u)
	var eye: Vector3 = p[0]
	var at: Vector3 = p[1]
	if s.handheld_m > 0.0:
		eye += Vector3(sin(_clock * 1.3) + 0.5 * sin(_clock * 3.1), sin(_clock * 1.7 + 1.0) * 0.7,
			cos(_clock * 1.1) * 0.6) * s.handheld_m
	# Never under the land (looking out through the back of a hillside): at least `CAMERA_ABOVE_M` over it.
	eye.y = maxf(eye.y, world.ground_at(eye.x, eye.z) + CAMERA_ABOVE_M)
	if _shake_left > 0.0:
		_shake_left -= get_process_delta_time()
		var k: float = _shake * maxf(_shake_left, 0.0) / maxf(_shake_total, 0.001)
		eye += Vector3(sin(_clock * 61.0), sin(_clock * 47.0 + 2.0), cos(_clock * 53.0)) * k * 0.12
	camera.look_at_from_position(eye, at)
	camera.fov = p[2]
	_attrs.dof_blur_far_enabled = s.focus_m > 0.0
	_attrs.dof_blur_near_enabled = s.focus_m > 0.0 and s.focus_m < 6.0
	if s.focus_m > 0.0:
		_attrs.dof_blur_far_distance = s.focus_m * 1.6
		_attrs.dof_blur_far_transition = s.focus_m * 2.0
		_attrs.dof_blur_near_distance = s.focus_m * 0.45
		_attrs.dof_blur_near_transition = s.focus_m * 0.3
		_attrs.dof_blur_amount = 0.06


func _fade_for(s: ShowcaseShot) -> void:
	if fade_s <= 0.0 or _mode == "stills":
		_fade.color.a = 0.0
		return
	var a: float = 1.0 - smoothstep(0.0, fade_s, _t)
	a = maxf(a, smoothstep(s.seconds - fade_s, s.seconds, _t))
	_fade.color.a = a


func _take_still() -> void:
	await RenderingServer.frame_post_draw
	var s: ShowcaseShot = shot()
	var file: String = _out_dir.path_join("%02d_%s.png" % [_shot_i + 1, s.title.to_snake_case().validate_filename().replace("'", "")])
	get_viewport().get_texture().get_image().save_png(file)
	print("[still] %s" % file)
	if _shot_i == shots.size() - 1:
		_finish()
	else:
		_start_shot(_shot_i + 1)


func _finish() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	print("[showcase] done")
	AppExit.quit(get_tree(), 0)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ------------------------------------------------------------------------------------------------ looking round

func _fly(real: float) -> void:
	var move: Vector3 = Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	camera.rotation = Vector3(_pitch, _yaw, 0.0)
	camera.position += camera.basis * move * _free_speed * real


func _unhandled_input(event: InputEvent) -> void:
	if _mode != "":
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_free_speed = minf(_free_speed * 1.25, 120.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_free_speed = maxf(_free_speed / 1.25, 0.5)
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null and _looking and _free:
		_yaw -= mm.relative.x * 0.004
		_pitch = clampf(_pitch - mm.relative.y * 0.004, -1.5, 1.5)
		return
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_RIGHT:
			_start_shot(_shot_i + 1)
		KEY_LEFT:
			_start_shot(_shot_i - 1)
		KEY_SPACE:
			_paused = not _paused
		KEY_R:
			_start_shot(_shot_i)
		KEY_M:
			_mood_override = (_mood_override + 1) % _moods.size()
			world.mood = _moods[_mood_override]
		KEY_N:
			_mood_override = -1
			_start_shot(_shot_i)
		KEY_F:
			_free = not _free
			if _free:
				_yaw = camera.rotation.y
				_pitch = camera.rotation.x
		KEY_C:
			var at: Vector3 = camera.global_position - camera.global_basis.z * 10.0
			print("[showcase] eye %s  at %s  fov %.1f" % [camera.global_position, at, camera.fov])
		KEY_L:
			letterbox = 0.0 if letterbox > 0.0 else 2.39
			_layout_bars()
		KEY_H:
			_help.visible = not _help.visible
		KEY_P:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://showcase"))
			var file: String = "user://showcase/still_%d.png" % Time.get_ticks_msec()
			get_viewport().get_texture().get_image().save_png(file)
			print("[showcase] saved %s" % ProjectSettings.globalize_path(file))
		_:
			if k.keycode >= KEY_1 and k.keycode <= KEY_9:
				var i: int = int(k.keycode - KEY_1)
				if i < shots.size():
					_start_shot(i)
	_update_help()


# ------------------------------------------------------------------------------------------------ the frame

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	for i: int in range(2):
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(bar)
		_bars.append(bar)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_fade)
	_help = Label.new()
	_help.position = Vector2(16, 12)
	_help.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.85))
	_help.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	_help.add_theme_constant_override(&"outline_size", 4)
	_help.visible = _mode == ""
	_ui.add_child(_help)
	get_viewport().size_changed.connect(_layout_bars)
	_layout_bars()


func _layout_bars() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var h: float = 0.0
	if letterbox > 0.0:
		h = maxf(0.0, (size.y - size.x / letterbox) * 0.5)
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(size.x, h)
	_bars[1].position = Vector2(0.0, size.y - h)
	_bars[1].size = Vector2(size.x, h)


func _update_help() -> void:
	if _help == null:
		return
	var s: ShowcaseShot = shot()
	var title: String = "%d/%d  %s" % [_shot_i + 1, shots.size(), s.title] if s != null else "no shots"
	var m: String = world.mood.display_name if world != null and world.mood != null else ""
	_help.text = "%s   (%s)%s%s\n←/→ shot · 1-9 jump · R again · Space pause · M mood · N its own mood · F free camera%s · L bars · P still · H help" % [
		title, m, "  PAUSED" if _paused else "", "  FREE CAMERA" if _free else "",
		" (WASD, Q/E, RMB look, wheel speed, C print)" if _free else ""]
