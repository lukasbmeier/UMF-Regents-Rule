class_name PullStage extends SubViewportContainer
## HERBALISM'S 3D STAGE: PULL THE ROOT (`HERBALISM_HUNTING_PREP.md` §3, Luke's H3, 2026-11-07; redrawn after his play,
## 2026-11-08: "the shaking was too much it looked like jittering and the root was strange looking and abnormally
## long"). The story, left to right: a CLUMP of flax in a mound of soil; the trowel (floating: no character on a stage,
## Luke 2026-11-06) DIGS round the front stem, each side of the mound sinking and a dark furrow opening as it is dug;
## pulled, the stem comes up out of the soil with a short, tapering root and its rootlets; as a side root nears, the
## soil CRACKS on its side and the side root's pale tip pushes out (no shaking: the crack says where, and which key);
## the trowel cuts it there (the tip flies off), or, pulled through, the soil bursts on that side and the stem dips.
## The stem stretches a little and leans with the strain, and creaks. Past the top it snaps (the top falls away); up
## whole it is laid on the PILE beside the mound, and the next stem of the clump comes forward. `PullMinigame` tells it
## what `PullModel` says: PRESENTATION ONLY, it decides nothing. Its own world (`own_world_3d`).
##
## Designers: open `pull_stage.tscn` to move the camera, the sun, the mound's halves, the clump's stems, the pile, or the
## trowel's three poses: drag `TrowelRest`, `DigLeft` and `DigRight` (each shows the trowel, a preview only the editor
## sees; the markers' scale sizes it). The numbers below say how the plant moves. The sounds are `game/regents/art/sound/herbalism/`.

## How long the root is (the stem has risen this far when it is all up).
@export var root_len_m: float = 0.08
## How much the stem stretches (of its height) and leans (radians) at full strain.
@export var stem_stretch: float = 0.08
@export var lean: float = 0.08
## How far a side root's tip pushes out of the cracked soil when it is about to catch.
@export var tip_len_m: float = 0.065
## How many pulled stems the pile shows at most.
@export var pile_max: int = 8
## The trowel (a placeholder until a model is found: `trowel.tscn`).
@export var trowel: PackedScene = preload("res://game/regents/skilling/herbalism/trowel.tscn")

const ROOT: Color = Color(0.74, 0.62, 0.45)
const TIP: Color = Color(0.86, 0.78, 0.62)
const CRACK: Color = Color(0.12, 0.08, 0.05)
const FLAX: PackedScene = preload("res://game/regents/art/nature/Flower_3_Group.gltf")

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Stage/Camera
@onready var _stage3d: Node3D = $Viewport/Stage
@onready var _plant: Node3D = $Viewport/Stage/Plant
@onready var _clump: Node3D = $Viewport/Stage/Clump
@onready var _pile: Node3D = $Viewport/Stage/Pile
@onready var _mound_left: Node3D = $Viewport/Stage/MoundLeft
@onready var _mound_right: Node3D = $Viewport/Stage/MoundRight
@onready var _furrow_left: Node3D = $Viewport/Stage/FurrowLeft
@onready var _furrow_right: Node3D = $Viewport/Stage/FurrowRight
@onready var _soil_left: CPUParticles3D = $Viewport/Stage/SoilLeft
@onready var _soil_right: CPUParticles3D = $Viewport/Stage/SoilRight
@onready var _fibers: CPUParticles3D = $Viewport/Stage/Fibers
@onready var _dig: AudioStreamPlayer = $Dig
@onready var _strain_sound: AudioStreamPlayer = $Strain
@onready var _catch: AudioStreamPlayer = $Catch
@onready var _snap: AudioStreamPlayer = $Snap
@onready var _up: AudioStreamPlayer = $Up

var tool: FloatingTool = null
var _rest: Transform3D = Transform3D.IDENTITY
var _dig_left: Transform3D = Transform3D.IDENTITY
var _dig_right: Transform3D = Transform3D.IDENTITY
var _root: Node3D = null
var _home: Vector3 = Vector3.ZERO
var _mound_y: float = 0.3
## Each side's crack and side-root tip (built here), and the tip that flies off when cut.
var _crack_left: Node3D = null
var _crack_right: Node3D = null
var _cut_tip: Node3D = null
var _cut_vel: Vector3 = Vector3.ZERO
## What the model says now (`show_pull`).
var _up_by: float = 0.0
var _strain: float = 0.0
var _showing: int = 0
var _held: bool = false
var _pack_left: float = 1.0
var _pack_right: float = 1.0
## Shown: the rise eased toward the model's, a jolt's age and side, the stem's flight once it is out.
var _shown_up: float = 0.0
var _shown_left: float = 1.0
var _shown_right: float = 1.0
var _tip_out: float = 0.0
var _jolt: float = 10.0
var _flying: bool = false
var _to_pile: bool = false
var _fly_vel: Vector3 = Vector3.ZERO
var _fly_spin: float = 0.0
var _fly_age: float = 0.0
var _taken: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the presses
	_home = _plant.position
	_mound_y = _mound_left.scale.y
	_rest = FloatingTool.marker(self, ^"Viewport/Stage/TrowelRest")
	_dig_left = FloatingTool.marker(self, ^"Viewport/Stage/DigLeft")
	_dig_right = FloatingTool.marker(self, ^"Viewport/Stage/DigRight")
	tool = FloatingTool.make(trowel)
	tool.fall_s = 0.1
	tool.rise_s = 0.2
	_stage3d.add_child(tool)
	tool.set_poses(_rest, _dig_left)
	_root = _make_root()
	_plant.add_child(_root)
	_crack_left = _make_crack(-1.0)
	_crack_right = _make_crack(1.0)


## The root under the stem: a short taproot tapering down, two or three rootlets off it; its top at the stem's base
## (hidden in the soil until it comes up).
func _make_root() -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "Root"
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = ROOT
	mat.roughness = 1.0
	root.add_child(_taper(0.006, 0.0012, root_len_m, mat, Vector3(0.0, -root_len_m * 0.5, 0.0), Vector3.ZERO))
	for k: int in 3:
		var at: float = root_len_m * (0.3 + 0.22 * float(k))
		var side: float = -1.0 if k % 2 == 0 else 1.0
		var l: float = root_len_m * (0.45 - 0.1 * float(k))
		root.add_child(_taper(0.0022, 0.0006, l, mat, Vector3(side * l * 0.35, -at - l * 0.3, 0.0), Vector3(0.0, 0.0, side * 0.9)))
	return root


func _taper(top: float, bottom: float, length: float, mat: Material, at: Vector3, rot: Vector3) -> MeshInstance3D:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = mat
	var inst: MeshInstance3D = MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = at
	inst.rotation = rot
	return inst


## A side's crack in the soil (a dark split) and the side root's tip pushing out of it, hidden until it shows.
func _make_crack(side: float) -> Node3D:
	var crack: Node3D = Node3D.new()
	crack.name = "CrackLeft" if side < 0.0 else "CrackRight"
	crack.position = Vector3(side * 0.095, 0.04, 0.06)
	crack.rotation = Vector3(0.0, side * 0.5, 0.0)
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = CRACK
	dark.roughness = 1.0
	for k: int in 3:
		var bit: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.05 - 0.01 * float(k), 0.006, 0.007)
		box.material = dark
		bit.mesh = box
		bit.position = Vector3(side * 0.016 * float(k), 0.002 * float(k), -0.012 * float(k))
		bit.rotation = Vector3(0.0, 0.5 * float(k - 1), 0.0)
		crack.add_child(bit)
	var tip_mat: StandardMaterial3D = StandardMaterial3D.new()
	tip_mat.albedo_color = TIP
	tip_mat.roughness = 0.9
	var tip: Node3D = Node3D.new()
	tip.name = "Tip"
	tip.rotation = Vector3(0.0, 0.0, -side * 0.7)
	tip.add_child(_taper(0.006, 0.0015, tip_len_m, tip_mat, Vector3(0.0, tip_len_m * 0.5, 0.0), Vector3.ZERO))
	# Clods heaved up round the split.
	var soil: StandardMaterial3D = StandardMaterial3D.new()
	soil.albedo_color = Color(0.4, 0.28, 0.17)
	soil.roughness = 1.0
	for k: int in 4:
		var clod: MeshInstance3D = MeshInstance3D.new()
		var b: BoxMesh = BoxMesh.new()
		b.size = Vector3(0.012, 0.009, 0.011)
		b.material = soil
		clod.mesh = b
		clod.position = Vector3(side * (0.01 + 0.012 * float(k % 2)) - side * 0.02 * float(k / 2), 0.004, 0.012 - 0.016 * float(k))
		clod.rotation = Vector3(0.3 * float(k), 0.7 * float(k), 0.2)
		crack.add_child(clod)
	crack.add_child(tip)
	crack.visible = false
	_stage3d.add_child(crack)
	return crack


## The next stem of the clump comes forward: down in the soil, its root under it, both sides packed again. `first`:
## the round's first (the clump whole).
func new_plant(first: bool = false) -> void:
	_flying = false
	_to_pile = false
	_up_by = 0.0
	_shown_up = 0.0
	_strain = 0.0
	_plant.position = _home
	_plant.rotation = Vector3.ZERO
	_plant.scale = Vector3.ONE
	_plant.visible = true
	_root.visible = true
	_root.scale = Vector3.ONE
	if first:
		_taken = 0
		for c: Node in _pile.get_children():
			c.queue_free()
	else:
		_taken += 1
	# The clump thins as its stems are taken, and grows back once all of them are (the round goes on).
	var stems: Array[Node] = _clump.get_children()
	for i: int in stems.size():
		(stems[i] as Node3D).visible = i >= _taken % (stems.size() + 1)


## The model now: how much of the root is up and the strain (of 1000), the side whose soil cracks (0 none,
## `PullModel.LEFT`/`RIGHT`), whether it is being pulled, each side's pack (1000 packed).
func show_pull(up_by: int, strain: int, showing: int, held: bool, pack_left: int, pack_right: int) -> void:
	_up_by = clampf(float(up_by) / 1000.0, 0.0, 1.0)
	_strain = clampf(float(strain) / 1000.0, 0.0, 1.0)
	if showing != _showing and showing != 0:
		_tip_out = 0.0
		_play(_dig, 0.6)   # the soil splitting
	_showing = showing
	_held = held
	_pack_left = clampf(float(pack_left) / 1000.0, 0.0, 1.0)
	_pack_right = clampf(float(pack_right) / 1000.0, 0.0, 1.0)


## A trowel stroke on a side (`left`): `what` is the model's (CUT, DUG, SCRAPED).
func stroke(left: bool, what: int, _pack: int) -> void:
	# It rests just above the side it last worked (lifted out of its dig), so it never swings through the stems.
	var dig: Transform3D = _dig_left if left else _dig_right
	tool.rest_pose = dig.translated(Vector3(0.0, 0.06, 0.0))
	tool.hit_pose = dig
	tool.swing()
	if what == PullModel.CUT:
		_cut(left)
		_play(_snap, 1.7)
	elif what == PullModel.DUG:
		(_soil_left if left else _soil_right).restart()
		_play(_dig, randf_range(0.9, 1.1))
	else:
		_play(_dig, 1.4)


## The cut side root's tip flies off; the crack closes.
func _cut(left: bool) -> void:
	var crack: Node3D = _crack_left if left else _crack_right
	var tip: Node3D = crack.get_node(^"Tip") as Node3D
	if is_instance_valid(_cut_tip):
		_cut_tip.queue_free()
	_cut_tip = tip.duplicate() as Node3D
	_stage3d.add_child(_cut_tip)
	_cut_tip.global_transform = tip.global_transform
	_cut_vel = Vector3(-0.5 if left else 0.5, 0.9, 0.25)
	(_soil_left if left else _soil_right).restart()
	_showing = 0


## A side root pulled through uncut: the soil bursts on its side and the stem dips.
func caught() -> void:
	_jolt = 0.0
	(_soil_left if _showing == PullModel.LEFT else _soil_right).restart()
	_play(_catch, randf_range(0.9, 1.05))


## Past the top: the stem snaps, its top falls away; the stub stays in the ground.
func snapped() -> void:
	_root.visible = false
	_fly(Vector3(randf_range(-0.25, 0.25), 0.7, 0.25), 4.0, false)
	_fibers.restart()
	_play(_snap, randf_range(0.95, 1.1))


## Up whole: it comes out of the soil with all its root and is laid on the pile.
func whole() -> void:
	_shown_up = 1.0
	_fly(Vector3.ZERO, 0.0, true)
	(_soil_left if randf() < 0.5 else _soil_right).restart()
	_play(_up, 1.0)


func _fly(vel: Vector3, spin: float, to_pile: bool) -> void:
	_flying = true
	_to_pile = to_pile
	_fly_vel = vel
	_fly_spin = spin
	_fly_age = 0.0
	_strain_sound.stop()
	for c: Node3D in [_crack_left, _crack_right]:
		c.visible = false


## A whole stem laid on the pile (a copy, lying down), the oldest taken off past `pile_max`.
func _lay_on_pile() -> void:
	var n: int = _pile.get_child_count()
	if n >= pile_max:
		_pile.get_child(0).queue_free()
	var laid: Node3D = Node3D.new()
	var stem: Node3D = FLAX.instantiate() as Node3D
	stem.scale = Vector3.ONE * 0.13
	laid.add_child(stem)
	laid.position = Vector3(0.0, 0.008 * float(n % 4), 0.022 * float(n % 4) - 0.03)
	laid.rotation = Vector3(0.0, 0.08 * float(n % 3) - 0.08, -PI * 0.5 + 0.06)   # the root at the mound, the top away
	_pile.add_child(laid)


func _play(player: AudioStreamPlayer, pitch: float) -> void:
	player.pitch_scale = pitch
	player.play()


func _process(delta: float) -> void:
	_jolt += delta
	# Each side of the mound sinks as it is dug, its furrow opening.
	_shown_left = lerpf(_shown_left, _pack_left, minf(1.0, delta * 10.0))
	_shown_right = lerpf(_shown_right, _pack_right, minf(1.0, delta * 10.0))
	_mound_left.scale.y = _mound_y * (0.45 + 0.55 * _shown_left)
	_mound_right.scale.y = _mound_y * (0.45 + 0.55 * _shown_right)
	_furrow_left.visible = _shown_left < 0.95
	_furrow_right.visible = _shown_right < 0.95
	_furrow_left.scale = Vector3(1.0, 1.0, 1.0) * (1.0 - _shown_left * 0.6)
	_furrow_right.scale = Vector3(1.0, 1.0, 1.0) * (1.0 - _shown_right * 0.6)
	# The crack on the side root's side, its tip pushing out.
	_tip_out = minf(1.0, _tip_out + delta * 3.0)
	_crack_left.visible = _showing == PullModel.LEFT and not _flying
	_crack_right.visible = _showing == PullModel.RIGHT and not _flying
	for c: Node3D in [_crack_left, _crack_right]:
		(c.get_node(^"Tip") as Node3D).scale = Vector3.ONE * maxf(0.05, _tip_out)
	if is_instance_valid(_cut_tip):
		_cut_vel.y -= 4.0 * delta
		_cut_tip.position += _cut_vel * delta
		_cut_tip.rotation.z += 8.0 * delta
		if _cut_tip.position.y < -0.2:
			_cut_tip.queue_free()
			_cut_tip = null
	if _flying:
		_fly_age += delta
		if _to_pile:
			# Lifted clear, then swung over to the pile.
			var k: float = minf(1.0, _fly_age / 0.45)
			_plant.position = _home.lerp(_pile.position + Vector3(0.0, 0.05, 0.0), k) + Vector3(0.0, sin(k * PI) * 0.12 + root_len_m, 0.0)
			_plant.rotation = Vector3(0.0, 0.0, -k * PI * 0.5)
			if k >= 1.0:
				_flying = false
				_to_pile = false
				_plant.visible = false
				_lay_on_pile()
		else:
			_fly_vel.y -= 3.5 * delta
			_plant.position += _fly_vel * delta
			_plant.rotation.z -= _fly_spin * delta * 0.3
			if _plant.position.y < -0.3:
				_plant.visible = false
		return
	_shown_up = lerpf(_shown_up, _up_by, minf(1.0, delta * 12.0))
	var pos: Vector3 = _home + Vector3(0.0, _shown_up * root_len_m, 0.0)
	var away: float = 0.0 if _showing == 0 else (1.0 if _showing == PullModel.LEFT else -1.0)
	var rot: Vector3 = Vector3(-_strain * lean, 0.0, away * 0.04 * _tip_out)
	if _jolt < 0.25:
		var j: float = 1.0 - _jolt / 0.25
		pos.y -= 0.02 * j * j
	_plant.position = pos
	_plant.rotation = rot
	var s: float = 1.0 + _strain * stem_stretch
	_plant.scale = Vector3(1.0 / sqrt(s), s, 1.0 / sqrt(s))   # thinner as it stretches
	# The stem's creak while it is pulled: louder and higher as the strain rises.
	if _held:
		_strain_sound.volume_db = lerpf(-26.0, -8.0, _strain)
		_strain_sound.pitch_scale = lerpf(0.8, 1.3, _strain)
		if not _strain_sound.playing:
			_strain_sound.play()
	elif _strain_sound.playing:
		_strain_sound.stop()
