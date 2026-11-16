class_name VistaLab extends ShowcaseStage
## THE VISTA LAB (2026-11-15; `vista_lab.tscn`, F6): the valley in its five moods, from slow camera moves, with the
## camp's people at their work: a smith at the anvil, a ranger and a wizard by the fire, a guard, deer at the lake.
## For the composers (the stills and the reel: `game/regents/tests/showcase_render.sh`) and for judging the look.
## Its shots are its scene's `shots` (Inspector); `ShowcaseStage` says how to run it.

const ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const DEER: EntityDefinition = preload("res://game/regents/content/character/deer.tres")
const SWORD: PackedScene = preload("res://game/regents/combat/weapons/iron_sword.tscn")
const STAFF: PackedScene = preload("res://game/regents/combat/weapons/yew_staff.tscn")
const BOW: PackedScene = preload("res://game/regents/combat/weapons/yew_bow.tscn")
const HAMMER: PackedScene = preload("res://game/regents/skilling/smithing/hammer.tscn")

var smith: ShowcaseActor = null
var ranger: ShowcaseActor = null
var wizard: ShowcaseActor = null
var guard: ShowcaseActor = null
var walker: ShowcaseActor = null
var deer: Array[ShowcaseActor] = []


func _cast() -> void:
	# Looks: 0 peasant m, 1 ranger f, 2 wizard m, 3 noble f, 4 ranger m, 5 peasant f, 6 noble m, 7 wizard f.
	smith = _put(ADVENTURER, 0, HAMMER, Vector3(3.0, 0.0, 3.7))
	ranger = _put(ADVENTURER, 1, BOW, Vector3(-1.5, 0.0, 1.4))
	wizard = _put(ADVENTURER, 2, STAFF, Vector3(1.6, 0.0, -1.1))
	guard = _put(ADVENTURER, 6, SWORD, Vector3(-3.6, 0.0, -1.2))
	walker = _put(ADVENTURER, 4, SWORD, Vector3(-6.0, 0.0, 14.0))
	for i: int in range(3):
		var d: ShowcaseActor = ShowcaseActor.make(DEER)
		d.ground = world.ground_at
		add_child(d)
		deer.append(d)


func _put(def: EntityDefinition, look: int, weapon: PackedScene, at: Vector3) -> ShowcaseActor:
	var a: ShowcaseActor = ShowcaseActor.make(def, look, weapon)
	a.ground = world.ground_at
	add_child(a)
	a.walk_to(at, 0.0)
	return a


func _reset_cast() -> void:
	smith.walk_to(Vector3(3.0, 0.0, 3.7), 0.0)
	smith.face(Vector3(3.6, 0.0, 3.0), true)
	smith.play(&"pose.smith")
	ranger.walk_to(Vector3(-1.5, 0.0, 1.4), 0.0)
	ranger.face(Vector3.ZERO, true)
	ranger.play(&"locomotion.idle")
	wizard.walk_to(Vector3(1.6, 0.0, -1.1), 0.0)
	wizard.face(Vector3.ZERO, true)
	wizard.play(&"locomotion.idle")
	guard.walk_to(Vector3(-3.6, 0.0, -1.2), 0.0)
	guard.face(Vector3(-20.0, 0.0, -60.0), true)
	guard.play(&"locomotion.idle")
	walker.walk_to(Vector3(-6.0, 0.0, 14.0), 0.0)
	walker.visible = false
	var spots: Array[Vector3] = [Vector3(12.0, 0.0, -48.0), Vector3(10.0, 0.0, -54.0), Vector3(14.0, 0.0, -43.0)]
	for i: int in range(deer.size()):
		deer[i].walk_to(spots[i], 0.0)
		deer[i].face(Vector3(world.lake_at.x, 0.0, world.lake_at.y) + Vector3(float(i) * 6.0 - 6.0, 0.0, 0.0), true)
		deer[i].play(&"locomotion.idle")


# ------------------------------------------------------------------------------------------------ beats

## A traveler walks up the path into camp, past the fire.
func arrive() -> void:
	walker.visible = true
	walker.walk_to(Vector3(-6.0, 0.0, 16.0), 0.0)
	walker.walk_to(Vector3(-2.2, 0.0, 3.6), 1.45)
	ranger.face(Vector3(-2.2, 0.0, 3.6))


## The deer walk a few steps along the shore (at their own walk), stopping short of the water.
func graze() -> void:
	for i: int in range(deer.size()):
		var from: Vector3 = deer[i].position
		var to: Vector3 = from + Vector3(-0.5, 0.0, -2.4 - 0.5 * float(i))
		# Back along the way until it is on the bank.
		var u: float = 1.0
		while u > 0.1 and world.ground_at(from.lerp(to, u).x, from.lerp(to, u).z) < world.water_y + 0.2:
			u -= 0.1
		deer[i].walk_to(from.lerp(to, u), 1.0)


## The wizard calls a cold light between the hands while the ranger watches.
func channel() -> void:
	wizard.face(Vector3(-2.0, 0.0, 3.0), true)
	wizard.play(&"pose.spell_channel")
	# The ranger steps back out of the camera's way and watches.
	ranger.walk_to(Vector3(-3.0, 0.0, 0.0), 0.0)
	ranger.face(wizard.position, true)
	charge("frost_charge", wizard, [&"hand_l", &"hand_r"], 0.2, wizard.position + Vector3(-2.0, 1.2, 3.0), 9.0)
