class_name BattleLab extends ShowcaseStage
## THE BATTLE LAB (2026-11-15; `battle_lab.tscn`, F6): the game's fights acted out in the valley for the camera, with
## the game's own swings, clips and effects (the crescent cut along the real blade, the parry's flash, Fireball, Frost
## Ring, Blink, the imp's cinder ring, arrows with their trail). For the composers (stills and clips:
## `game/regents/tests/showcase_render.sh`) and a trailer's first cut. Its shots are its scene's `shots`; each names a
## beat below, a timeline of who does what when (game seconds from the shot's start). Not the game's combat: nothing
## here is judged, the timeline says who is hit.

const ADVENTURER: EntityDefinition = preload("res://game/regents/content/character/adventurer.tres")
const SWORD: PackedScene = preload("res://game/regents/combat/weapons/iron_sword.tscn")
const STAFF: PackedScene = preload("res://game/regents/combat/weapons/yew_staff.tscn")
const BOW: PackedScene = preload("res://game/regents/combat/weapons/yew_bow.tscn")
const ARROW: PackedScene = preload("res://game/regents/combat/arrow_look.tscn")
## The fights' ground: east of the camp, on the flat.
const ARENA: Vector3 = Vector3(16.0, 0.0, 12.0)
## A foe's cut, warmer than a player's.
const FOE_CUT: Color = Color(1.0, 0.5, 0.32)

var hero: ShowcaseActor = null
var mage: ShowcaseActor = null
var ranger: ShowcaseActor = null
var warrior: ShowcaseActor = null
var axeman: ShowcaseActor = null
var archer: ShowcaseActor = null
var imp: ShowcaseActor = null
var wolves: Array[ShowcaseActor] = []
var _all: Array[ShowcaseActor] = []
## Shots in flight: [carrier, from, to, seconds, age, on_arrive].
var _flying: Array[Array] = []


func _clearings() -> Array[Vector3]:
	return [Vector3(0.0, 0.0, 8.0), Vector3(ARENA.x, ARENA.z, 13.0), Vector3(ARENA.x - 9.0, ARENA.z + 3.0, 9.0)]


func _cast() -> void:
	hero = _make(ADVENTURER, 4, SWORD, "")
	mage = _make(ADVENTURER, 7, STAFF, "")
	ranger = _make(ADVENTURER, 1, BOW, "")
	warrior = _make(_def("skeleton_warrior"), 0, null, "skeleton_warrior")
	axeman = _make(_def("skeleton_axeman"), 0, null, "skeleton_axeman")
	archer = _make(_def("skeleton_archer"), 0, null, "skeleton_archer")
	imp = _make(_def("imp"), 0, null, "imp")
	for i: int in range(2):
		wolves.append(_make(_def("wolf"), 0, null, "wolf"))


static func _def(name: String) -> EntityDefinition:
	return load("res://game/regents/content/character/%s.tres" % name) as EntityDefinition


func _make(def: EntityDefinition, look: int, weapon: PackedScene, foe: String) -> ShowcaseActor:
	var fd: FoeDef = load("res://game/regents/content/foe/%s.tres" % foe) as FoeDef if foe != "" else null
	var a: ShowcaseActor = ShowcaseActor.make(def, look, weapon, fd)
	a.ground = world.ground_at
	add_child(a)
	_all.append(a)
	return a


func _reset_cast() -> void:
	for f: Array in _flying:
		if is_instance_valid(f[0]):
			(f[0] as Node).queue_free()
	_flying.clear()
	for a: ShowcaseActor in _all:
		a.visible = false
		a.play(&"locomotion.idle")
		a.walk_to(Vector3(0.0, -50.0, 0.0), 0.0)


func _tick(delta: float) -> void:
	for i: int in range(_flying.size() - 1, -1, -1):
		var f: Array = _flying[i]
		if not is_instance_valid(f[0]):
			_flying.remove_at(i)
			continue
		var carrier: Node3D = f[0] as Node3D
		var age: float = float(f[4]) + delta
		f[4] = age
		var u: float = clampf(age / float(f[3]), 0.0, 1.0)
		var from: Vector3 = f[1]
		var to: Vector3 = f[2]
		var p: Vector3 = from.lerp(to, u) + Vector3.UP * sin(u * PI) * from.distance_to(to) * 0.03
		var ahead: Vector3 = from.lerp(to, minf(u + 0.02, 1.0)) + Vector3.UP * sin(minf(u + 0.02, 1.0) * PI) * from.distance_to(to) * 0.03
		carrier.global_position = p
		if ahead.distance_to(p) > 0.001:
			carrier.look_at(ahead, Vector3.UP)
		if u >= 1.0:
			_flying.remove_at(i)
			var done: Callable = f[5]
			if done.is_valid():
				done.call()
			carrier.queue_free()


# ------------------------------------------------------------------------------------------------ moves

## Stand `a` at ARENA + `at`, facing ARENA + `look`.
func _place(a: ShowcaseActor, at: Vector3, look: Vector3) -> void:
	a.visible = true
	a.walk_to(ARENA + at, 0.0)
	a.face(ARENA + look, true)


## `who` swings ability `id`: the clip, its crescent along the real blade, and at the hit `target` reacts (`react`,
## held if it is a death). A foe's swing wears a warmer cut.
func swing(who: ShowcaseActor, id: int, target: ShowcaseActor, react: StringName = &"react.hit", ground: bool = false) -> void:
	who.act(StringName("ability.%d" % id))
	var a: AbilityDef = ContentLibrary.find(&"ability", id) as AbilityDef
	var hit: float = float(a.wind_up_ms) / 1000.0 + 0.06 if a != null else 0.3
	if who.held != null:
		var tint: Color = FOE_CUT if who.definition != ADVENTURER else Color(1.0, 0.9, 0.72)
		spawn_fx("blade_cut", Vector3.ZERO, Vector3.INF, Vector3.ZERO, null, func(fx: VfxEffect) -> void:
			var cut: VfxBladeCut = fx as VfxBladeCut
			cut.weapon = who.held
			cut.color = tint
			cut.cut_from_s = hit * 0.45
			cut.hit_at_s = hit
			cut.ground_m = 0.55 if ground else 0.0)
	if target != null and react != &"":
		after(hit, func() -> void: target.act(react, react == &"react.death"))


## `who`'s blow is turned aside by `by`: the parry's flash where the blades meet, `who` staggers.
func parried(who: ShowcaseActor, id: int, by: ShowcaseActor) -> void:
	who.act(StringName("ability.%d" % id))
	var a: AbilityDef = ContentLibrary.find(&"ability", id) as AbilityDef
	var hit: float = float(a.wind_up_ms) / 1000.0 + 0.06 if a != null else 0.4
	after(maxf(hit - 0.18, 0.0), func() -> void: by.play(&"pose.block"))
	after(hit, func() -> void:
		var meet: Vector3 = (who.global_position + by.global_position) * 0.5 + Vector3(0.0, 1.25, 0.0)
		spawn_fx("parry_flash", meet, who.global_position)
		who.act(&"react.stagger"))
	after(hit + 0.25, func() -> void: by.play(&"locomotion.idle"))


## `who` rolls `side_m` to its right (negative: left) in half a second.
func roll(who: ShowcaseActor, side_m: float) -> void:
	who.act(&"ability.40010")
	var right: Vector3 = who.global_basis.x.normalized()
	var to: Vector3 = who.position + right * side_m
	who.walk_to(to, absf(side_m) / 0.5)


## A shot of `look` (a `ShotLook` scene) from `from` to `to` at `speed` m/s; `done` when it lands.
func fly(look: PackedScene, from: Vector3, to: Vector3, speed: float, done: Callable = Callable()) -> void:
	var carrier := Node3D.new()
	add_child(carrier)
	carrier.global_position = from
	carrier.look_at(to, Vector3.UP)
	carrier.add_child(look.instantiate())
	_spawned.append(carrier)
	_flying.append([carrier, from, to, maxf(from.distance_to(to) / speed, 0.05), 0.0, done])


func _chest(a: ShowcaseActor) -> Vector3:
	return a.global_position + Vector3(0.0, 1.15, 0.0)


## A fireball from `who` to `at`: the charge in the hand, the throw, the missile, the blast; `done` at the blast.
func fireball(who: ShowcaseActor, at: ShowcaseActor, done: Callable) -> void:
	var aim: Vector3 = _chest(at)
	who.face(at.global_position, true)
	who.play(&"pose.spell_cast")
	charge("fire_charge", who, [&"hand_l"], 0.16, aim, 0.6)
	after(0.6, func() -> void:
		who.play(&"locomotion.idle")
		who.act(&"ability.40013"))
	after(0.66, func() -> void:
		var from: Vector3 = cast_point(who, [&"hand_l"], 0.3, aim)
		var missile: VfxFireMissile = spawn_fx("fire_missile", from, Vector3.INF, _chest(at)) as VfxFireMissile
		missile.arrived.connect(func(_where: Variant) -> void:
			spawn_fx("fire_blast", at.global_position, Vector3.INF)
			done.call()))


# ------------------------------------------------------------------------------------------------ beats

## Steel: the sword's string on a skeleton, its cut parried, the finisher; a second one runs in and goes down.
func steel() -> void:
	_place(hero, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	_place(warrior, Vector3(0.0, 0.0, -0.95), Vector3(0.0, 0.0, 1.0))
	_place(axeman, Vector3(9.0, 0.0, -7.0), Vector3(0.0, 0.0, 0.0))
	after(0.3, func() -> void: swing(hero, 40001, warrior))
	after(0.95, func() -> void: swing(hero, 40002, warrior))
	after(1.9, func() -> void: parried(warrior, 40017, hero))
	after(2.95, func() -> void: swing(hero, 40003, warrior))
	after(3.7, func() -> void: swing(hero, 40023, warrior, &"react.death", true))
	after(4.2, func() -> void:
		axeman.walk_to(ARENA + Vector3(1.4, 0.0, -0.6), 4.2)
		hero.face(ARENA + Vector3(1.4, 0.0, -0.6)))
	after(6.3, func() -> void:
		axeman.face(hero.global_position, true)
		axeman.act(&"ability.40020"))
	after(6.75, func() -> void: roll(hero, -2.4))
	after(7.6, func() -> void:
		hero.face(axeman.global_position, true)
		swing(hero, 40005, axeman, &"react.stagger"))
	after(8.5, func() -> void: swing(hero, 40001, axeman))
	after(9.15, func() -> void: swing(hero, 40002, axeman))
	after(9.9, func() -> void: swing(hero, 40023, axeman, &"react.death", true))


## The finisher alone, close, for a slowed shot.
func finisher() -> void:
	_place(hero, Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -1.0))
	_place(warrior, Vector3(0.0, 0.0, -0.95), Vector3(0.0, 0.0, 1.0))
	after(0.1, func() -> void: swing(hero, 40002, warrior))
	after(0.8, func() -> void: swing(hero, 40023, warrior, &"react.death", true))


## Fire and frost: the imp's ember answered by a fireball, its cinder ring left by a blink, a frost ring, a last fire.
func fire(o: Vector3 = Vector3.ZERO) -> void:
	_place(mage, o + Vector3(-3.0, 0.0, 4.0), o + Vector3(3.0, 0.0, -4.0))
	_place(imp, o + Vector3(3.0, 0.0, -4.0), o + Vector3(-3.0, 0.0, 4.0))
	after(0.3, func() -> void: fireball(mage, imp, func() -> void: imp.act(&"react.stagger")))
	after(2.4, func() -> void:
		imp.face(mage.global_position, true)
		imp.act(&"ability.40033")
		spawn_fx("cinder_ring", mage.global_position, Vector3.INF))
	after(3.3, func() -> void:
		var to: Vector3 = ARENA + o + Vector3(-6.2, 0.0, 0.6)
		to.y = world.ground_at(to.x, to.z)
		mage.act(&"ability.40012")
		spawn_fx("blink", mage.global_position, to, to, mage))
	after(4.4, func() -> void:
		mage.face(imp.global_position, true)
		mage.play(&"pose.spell_channel")
		charge("frost_charge", mage, [&"hand_l", &"hand_r"], 0.2, _chest(imp), 1.0))
	after(5.4, func() -> void:
		mage.play(&"locomotion.idle")
		mage.act(&"ability.40014")
		spawn_fx("frost_ring", imp.global_position + Vector3(0.0, 0.0, 0.0), Vector3.INF))
	after(6.3, func() -> void: imp.act(&"react.hit"))
	after(7.4, func() -> void: fireball(mage, imp, func() -> void: imp.act(&"react.death", true)))


## Arrows: the skeleton archer's shot rolled clear, two answered; it falls to the second.
func arrows() -> void:
	_place(ranger, Vector3(-3.0, 0.0, 4.5), Vector3(3.0, 0.0, -5.0))
	_place(archer, Vector3(3.0, 0.0, -5.0), Vector3(-3.0, 0.0, 4.5))
	after(0.2, func() -> void: archer.play(&"pose.bow_aim"))
	after(0.4, func() -> void: ranger.play(&"pose.bow_draw"))
	after(1.4, func() -> void:
		archer.play(&"locomotion.idle")
		archer.act(&"ability.40030")
		var aim: Vector3 = _chest(ranger)
		fly(ARROW, archer.bone_position(&"hand_l") if archer.bone_position(&"hand_l") != Vector3.INF else _chest(archer),
			aim + (aim - _chest(archer)).normalized() * 6.0, 32.0))
	after(1.55, func() -> void:
		ranger.play(&"locomotion.idle")
		roll(ranger, 2.6))
	for k: int in range(2):
		var t: float = 2.8 + float(k) * 1.7
		after(t, func() -> void:
			ranger.face(archer.global_position, true)
			ranger.play(&"pose.bow_draw"))
		after(t + 0.8, func() -> void:
			ranger.play(&"locomotion.idle")
			ranger.act(&"ability.40011")
			var from: Vector3 = ranger.bone_position(&"hand_l")
			if from == Vector3.INF:
				from = _chest(ranger)
			var last: bool = k == 1
			fly(ARROW, from, _chest(archer), 38.0, func() -> void:
				archer.act(&"react.death" if last else &"react.hit", last)))


## The pack: two wolves circle in the dark and go for the swordsman; a lunge rolled, a bite parried, both put down.
func pack() -> void:
	_place(hero, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -3.0))
	_place(wolves[0], Vector3(-5.0, 0.0, -5.0), Vector3.ZERO)
	_place(wolves[1], Vector3(5.5, 0.0, -4.0), Vector3.ZERO)
	wolves[0].walk_to(ARENA + Vector3(-3.6, 0.0, -2.2), 1.3)
	wolves[1].walk_to(ARENA + Vector3(3.4, 0.0, -2.6), 1.3)
	after(1.9, func() -> void:
		wolves[0].face(hero.global_position, true)
		wolves[0].act(&"ability.40029")
		wolves[0].walk_to(ARENA + Vector3(-0.9, 0.0, -0.6), 7.0))
	after(2.05, func() -> void: roll(hero, 2.2))
	after(2.9, func() -> void:
		hero.face(wolves[0].global_position, true)
		swing(hero, 40001, wolves[0]))
	after(3.6, func() -> void: swing(hero, 40002, wolves[0], &"react.stagger"))
	after(4.0, func() -> void: wolves[1].walk_to(hero.position + Vector3(1.4, 0.0, -1.0), 5.0))
	after(4.9, func() -> void:
		wolves[1].face(hero.global_position, true)
		hero.face(wolves[1].global_position, true)
		parried(wolves[1], 40027, hero))
	after(5.8, func() -> void: swing(hero, 40023, wolves[1], &"react.death", true))
	after(6.9, func() -> void:
		hero.face(wolves[0].global_position, true)
		swing(hero, 40003, wolves[0], &"react.death", true))


## The line: steel and fire at once, for a wide shot.
func melee() -> void:
	steel()
	fire(Vector3(-9.0, 0.0, 3.0))
