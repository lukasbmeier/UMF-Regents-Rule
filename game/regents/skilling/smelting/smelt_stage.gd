class_name SmeltStage extends SubViewportContainer
## SMELTING'S 3D STAGE (`MINIGAMES_PREP.md` §5; Luke's M7, 2026-11-05): the furnace's fire under a crucible, the
## game's own bellows beside it (they pump on their own: no character on a stage, the player's own is the one working,
## Luke's play 2026-11-06), and the mold. The fire burns brighter with the heat; the crucible goes to the mold and tilts while
## it pours, a molten stream filling the mold. `SmeltMinigame` keeps the heat's band and the mold's line as 2D gauges
## over it (readouts) and tells it what `SmeltModel` says: PRESENTATION ONLY.
##
## Designers: open `smelt_stage.tscn` to move the camera or the props; the sounds are
## `game/regents/art/sound/smelting/` (`make_skill_sounds.py`).

## Where the crucible sits on the fire, and above the mold to pour.
@export var crucible_on_fire: Vector3 = Vector3(-0.15, 1.12, 0.0)
@export var crucible_pouring: Vector3 = Vector3(0.78, 0.92, 0.0)
## The mold's inside: its floor's height and how deep it is (the metal rises to the brim at a fill of 1000).
@export var mold_floor_y: float = 0.47
@export var mold_depth: float = 0.12

const MOLTEN: Color = Color(1.0, 0.55, 0.12)

@onready var viewport: SubViewport = $Viewport
@onready var camera: Camera3D = $Viewport/Stage/Camera
@onready var _fire: CPUParticles3D = $Viewport/Stage/Fire
@onready var _glow: OmniLight3D = $Viewport/Stage/FireGlow
@onready var _bellows: Node3D = $Viewport/Stage/Bellows
@onready var _crucible: Node3D = $Viewport/Stage/Crucible
@onready var _melt: MeshInstance3D = $Viewport/Stage/Crucible/Melt
@onready var _stream: MeshInstance3D = $Viewport/Stage/Stream
@onready var _metal: MeshInstance3D = $Viewport/Stage/Mold/Metal
@onready var _spill: MeshInstance3D = $Viewport/Stage/Spill
@onready var _breath: AudioStreamPlayer = $Bellows
@onready var _pour: AudioStreamPlayer = $Pour

var _squash: float = 0.0
var _bellows_scale: Vector3
var _heat: float = 0.0
var _pouring: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the minigame under it takes the presses
	stretch = true
	_bellows_scale = _bellows.scale
	show_melt(0, 0, false, true)


## A pump of the bellows: they squash and breathe, the fire flares.
func pump() -> void:
	_squash = 1.0
	_breath.pitch_scale = randf_range(0.9, 1.1)
	_breath.play()


## What the round has now: the heat (0-1000), the mold's fill (0-1000, more spills), whether it pours, and whether it
## is still in the heat (the crucible on the fire) or on to the pour (the crucible at the mold).
func show_melt(heat: int, fill: int, pouring: bool, heating: bool) -> void:
	_heat = clampf(float(heat) / 1000.0, 0.0, 1.0)
	var at: Vector3 = crucible_on_fire if heating else crucible_pouring
	_crucible.position = _crucible.position.lerp(at, 0.2)
	_crucible.rotation.z = lerpf(_crucible.rotation.z, -1.1 if pouring else 0.0, 0.25)
	_stream.visible = pouring and not heating
	var level: float = clampf(float(fill) / 1000.0, 0.0, 1.0)
	_metal.visible = fill > 0
	_metal.scale.y = maxf(0.01, level)
	_metal.position.y = mold_floor_y + mold_depth * level * 0.5
	_spill.visible = fill > 1000
	if pouring and not _pouring:
		_pour.play()
	elif not pouring and _pouring:
		_pour.stop()
	_pouring = pouring
	var mat: StandardMaterial3D = _melt.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 0.6 + 3.0 * _heat


func _process(delta: float) -> void:
	_squash = maxf(0.0, _squash - delta * 5.0)
	_bellows.scale = Vector3(_bellows_scale.x, _bellows_scale.y * (1.0 - 0.18 * _squash), _bellows_scale.z)
	_glow.light_energy = 0.8 + 3.2 * _heat + 1.5 * _squash
	_fire.scale_amount_min = 0.6 + 0.8 * _heat
	_fire.scale_amount_max = 1.0 + 1.4 * _heat
	_fire.initial_velocity_max = 0.5 + 0.9 * _heat + 0.8 * _squash
