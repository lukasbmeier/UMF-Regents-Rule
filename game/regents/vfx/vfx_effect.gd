class_name VfxEffect extends Node3D
## ONE EFFECT (the VFX lab, 2026-11-14): a spell's charge, its missile, its blast, a slash, a parry's flash, a foe's
## warning. Its scene's root has this (or a script extending it); the script builds the look in code from `VfxKit`
## (`_build`) and moves it by its own clock (`_animate`), so slow motion and the lab's shots are exact. What a
## designer changes is the scene's exported values, in the Inspector (colors, sizes, how long, how many).
##
## Where it is: the effect's node is put where it happens, its -Z the way it faces (a slash's, a gust's, a shot's
## flight). `target` (world) is where an effect aimed at something goes (a missile flies to it). `caster` is the body
## that made it, when an effect shows something on it (Blink fades it); both optional.
##
## Presentation only (hard rule 11): an effect never decides anything; the server says what happened, and an effect
## shows it. It frees itself when done (`free_when_done`); the lab keeps it to play again.

signal finished()
## A request that the camera shake (`strength`, about 0..1, for `seconds`): the lab shakes its camera; in the game
## `VfxCameraShake` listens (this client's own camera, by how near it is; never for a `lighter` one).
signal shook(strength: float, seconds: float)

## ANOTHER PLAYER'S share of the particles (the lighter version, `make_lighter`): half as many, the same look.
const LIGHTER_PARTICLES: float = 0.5

@export_group("Timing")
## How long it lasts, start to gone.
@export_range(0.05, 10.0, 0.05, "suffix:s") var duration_s: float = 1.0
## Plays as soon as it enters the tree (the game's way); the lab plays it itself.
@export var autoplay: bool = true
## Frees itself when done (the game's way); the lab keeps it.
@export var free_when_done: bool = true

## Where an aimed effect goes (world), and the body that made it (or null).
var target: Vector3 = Vector3.ZERO
var caster: Node3D = null
## Its clock (s) since it began, and whether it is running.
var age: float = 0.0
var playing: bool = false
## The meshes and particles whose shader takes its clock (`fx_time`): kept as Variants (checked before each use).
var _clocked: Array = []
var _built: bool = false
## THE LIGHTER VERSION (before many players: every per-player cost is judged at 300): another player's effect, seen by this client. The same
## effect at a lower cost: its particle systems at `LIGHTER_PARTICLES` of their amount, no light of its own, no
## camera shake. Your own and a foe's (what you must read in a fight) stay whole. Set it (or call `make_lighter`)
## before or after it enters the tree.
var lighter: bool = false


func _ready() -> void:
	_ensure_built()
	if lighter:
		make_lighter()
	elif shook.get_connections().is_empty():
		VfxCameraShake.listen(self)
	if autoplay:
		play()
	else:
		visible = false


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build()


## Make it the lighter version (`lighter`): its particles thinned, its lights out. Once; safe before it is built.
func make_lighter() -> void:
	lighter = true
	if not _built or has_meta(&"vfx_lightened"):
		return
	set_meta(&"vfx_lightened", true)
	for n: Node in find_children("*", "", true, false):
		var p: GPUParticles3D = n as GPUParticles3D
		if p != null:
			p.amount = maxi(1, ceili(float(p.amount) * LIGHTER_PARTICLES))
		var l: Light3D = n as Light3D
		if l != null:
			l.visible = false


## Start from the beginning (again).
func play() -> void:
	_ensure_built()
	age = 0.0
	playing = true
	visible = true
	_start()
	_apply()


## Stop at once and hide (the lab, before another plays).
func stop() -> void:
	playing = false
	visible = false
	_end()


func _process(delta: float) -> void:
	if not playing:
		return
	age += delta
	_apply()
	if age >= duration_s:
		playing = false
		_end()
		finished.emit()
		if free_when_done:
			queue_free()
		else:
			visible = false


func _apply() -> void:
	_animate(age, clampf(age / duration_s, 0.0, 1.0))
	for v: Variant in _clocked:
		if is_instance_valid(v):
			(v as GeometryInstance3D).set_instance_shader_parameter(&"fx_time", age)


## Add `node` as a child whose shader runs on this effect's clock; returns it.
func clocked(node: GeometryInstance3D, parent: Node = null) -> GeometryInstance3D:
	(parent if parent != null else self).add_child(node)
	_clocked.append(node)
	return node


## Set one of a node's per-instance shader values (`fx_alpha`, `fx_erosion`, `fx_fill`, ...).
static func fx(node: GeometryInstance3D, value_name: StringName, value: Variant) -> void:
	node.set_instance_shader_parameter(value_name, value)


## Fire a one-shot particle burst from the start.
static func burst(p: GPUParticles3D) -> void:
	p.restart()
	p.emitting = true


## How far `a` is through the stretch `from`..`to` (s), 0..1.
static func span(a: float, from: float, to: float) -> float:
	return clampf((a - from) / maxf(to - from, 0.0001), 0.0, 1.0)


static func ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)


static func ease_in(t: float) -> float:
	return t * t


## Overshoots a little before it settles (a shard punching up).
static func ease_back(t: float) -> float:
	var c: float = 1.7
	var u: float = t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


## Build the look (once, before the first play): add parts with `clocked`.
func _build() -> void:
	pass


## It (re)starts: reset parts, fire bursts.
func _start() -> void:
	pass


## Each frame: `a` seconds in, `t` the share of `duration_s`.
func _animate(_a: float, _t: float) -> void:
	pass


## It ended or was stopped: stop streams, put back anything it changed on `caster`.
func _end() -> void:
	pass
