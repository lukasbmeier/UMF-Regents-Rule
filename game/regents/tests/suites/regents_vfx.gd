extends "res://tests/suite_base.gd"
## THE VFX LAB'S EFFECTS (`-- --only=regents_vfx`; the VFX lab, 2026-11-14), with no server and no renderer:
##   - every effect scene builds, plays on its own clock, says it finished and frees itself (and, kept for the lab,
##     hides instead); a stopped one hides
##   - the missile flies to its target in distance / speed and says so there, not before; its trail outlives it
##   - Blink fades its caster out, moves it at its moment (or, told not to, leaves it), and puts the fade back
##   - the frost ring's shards wait for the landing; the blast asks for a shake, and none when its shake is 0
##   - AT SCALE: a ring's pieces are ONE MultiMesh (a handful of draws, not one a piece); another player's effect is
##     the lighter version (half the particles, no light, no shake) and ours whole; the game's camera listens to
##     `shook`, as hard as asked near this client's character, less far off, never for a lighter one
##   - nothing under `game/regents/vfx/` is an image file (Luke's "No AI disclosure": procedural first)
##   - the lab opens, plays each showcase, and gives back the engine's speed when it closes
## How they LOOK is the lab's shots (windowed): `"$GODOT" --path . res://game/regents/vfx/vfx_lab.tscn -- <out dir>`.

const FX: String = "res://game/regents/vfx/effects/"
const STEP_S: float = 1.0 / 30.0


func run() -> void:
	_run_every_effect()
	_run_missile()
	_run_blink()
	_run_frost_and_shake()
	_run_at_scale()
	_run_no_images()
	_run_coverage()
	await _run_ability_vfx()
	await _run_spell_rings()
	await _run_lab()


## A fresh effect from `effects/<scene>.tscn`, in the tree, its clock stepped by hand (`_step`).
func _effect(scene: String, at: Vector3 = Vector3.ZERO, target: Vector3 = Vector3.ZERO) -> VfxEffect:
	var packed: PackedScene = load(FX + scene + ".tscn") as PackedScene
	if packed == null:
		return null
	var fx: VfxEffect = packed.instantiate() as VfxEffect
	fx.position = at
	fx.target = target
	add_child(fx)
	fx.set_process(false)
	return fx


## Step `fx` by `seconds` of its own clock; true when it finished meanwhile.
func _step(fx: VfxEffect, seconds: float) -> bool:
	var done: Array[bool] = [false]
	var on_done: Callable = func() -> void: done[0] = true
	fx.finished.connect(on_done)
	var t: float = 0.0
	while t < seconds - 0.0001 and not done[0]:
		fx._process(STEP_S)
		t += STEP_S
	if fx.finished.is_connected(on_done):
		fx.finished.disconnect(on_done)
	return done[0]


func _run_at_scale() -> void:
	# A ring's pieces: one MultiMesh, every one of them in it; the ring's own draws a handful, however many pieces.
	for scene: String in ["frost_ring", "cinder_ring"]:
		var ring: VfxGroundRing = _effect(scene) as VfxGroundRing
		if ring == null:
			_check(false, "%s builds" % scene)
			continue
		var meshes: int = ring.find_children("*", "MeshInstance3D", true, false).size()
		var multis: Array[Node] = ring.find_children("*", "MultiMeshInstance3D", true, false)
		_check(multis.size() == 1 and (multis[0] as MultiMeshInstance3D).multimesh.instance_count == ring.pieces,
			"%s: its %d pieces are one MultiMesh" % [scene, ring.pieces])
		_check(meshes <= 3 and ring.pieces >= 20, "%s: a handful of meshes beside it (%d), not one a piece" % [scene, meshes])
		_step(ring, ring.warn_s + 0.4)
		_check((multis[0] as MultiMeshInstance3D).multimesh.visible_instance_count == ring.risen_count(),
			"%s: the risen pieces are the ones drawn" % scene)
		ring.queue_free()
	# Ours whole, another player's lighter: half the particles, its lights out; the same parts otherwise.
	for scene: String in ["fire_blast", "frost_ring", "gale", "blink", "fire_charge"]:
		var whole: VfxEffect = _effect(scene)
		var packed: PackedScene = load(FX + scene + ".tscn") as PackedScene
		var light: VfxEffect = packed.instantiate() as VfxEffect
		light.lighter = true
		add_child(light)
		light.set_process(false)
		var pw: int = _particles(whole)
		var pl: int = _particles(light)
		_check(pw > 0 and pl <= ceili(pw * VfxEffect.LIGHTER_PARTICLES) + _systems(whole) and pl < pw,
			"%s: another player's has about half the particles (%d of %d)" % [scene, pl, pw])
		_check(_lights_on(light) == 0 and (_lights_on(whole) > 0 or scene == "gale"),
			"%s: another player's has no light of its own (ours %d)" % [scene, _lights_on(whole)])
		_check(_systems(whole) == _systems(light), "%s: the same parts, only fewer" % scene)
		whole.queue_free()
		light.queue_free()
	# Made lighter after it entered the world (a missile's look, built before its owner was known): the same.
	var late: VfxEffect = _effect("fire_blast")
	var before: int = _particles(late)
	late.make_lighter()
	late.make_lighter()   # (once only)
	_check(_particles(late) < before and _particles(late) >= before / 4, "made lighter late: thinned once (%d of %d)" % [_particles(late), before])
	late.queue_free()
	# Whose is lighter: nobody's (the lab, the showcase) is whole.
	var bare := Node3D.new()
	_check(not AbilityVfx.lighter_for(null) and not AbilityVfx.lighter_for(bare), "an effect with no player is whole")
	bare.free()
	# The camera listening.
	var cam := Camera3D.new()
	add_child(cam)
	var me := Node3D.new()
	add_child(me)
	var shaker: VfxCameraShake = VfxCameraShake.install(cam, me)
	_check(VfxCameraShake.current == shaker and VfxCameraShake.install(cam, me) == shaker, "one listener on the camera")
	var near: VfxEffect = _effect("fire_blast", Vector3(2, 0, 0))
	var far: VfxEffect = _effect("fire_blast", Vector3(60, 0, 0))
	var mid: VfxEffect = _effect("fire_blast", Vector3(13, 0, 0))
	_check(near.shook.is_connected(shaker.heard), "an effect made while it listens is heard")
	_check(is_equal_approx(shaker.heard(0.4, 0.3, near), 0.4), "near: as hard as it asks")
	var k_mid: float = shaker.heard(0.4, 0.3, mid)
	_check(k_mid > 0.0 and k_mid < 0.4, "farther: less (%.2f)" % k_mid)
	_check(is_zero_approx(shaker.heard(0.4, 0.3, far)), "far off: none")
	near.lighter = true
	_check(is_zero_approx(shaker.heard(0.4, 0.3, near)), "another player's: none")
	near.lighter = false
	near.shook.emit(0.4, 0.3)
	shaker._process(0.05)
	_check(not is_zero_approx(cam.h_offset) or not is_zero_approx(cam.v_offset), "the picture moves while it shakes")
	shaker._process(1.0)
	shaker._process(0.01)
	_check(is_zero_approx(cam.h_offset) and is_zero_approx(cam.v_offset), "and is put back after")
	for n: Node in [near, far, mid, me]:
		n.queue_free()
	cam.queue_free()
	await get_tree().process_frame
	_check(VfxCameraShake.current == null, "the listener goes with its camera")
	var lone: VfxEffect = _effect("fire_blast")
	_check(lone.shook.get_connections().is_empty(), "no camera listening (the lab): nothing connected")
	lone.queue_free()


func _particles(fx: Node) -> int:
	var n: int = 0
	for p: Node in fx.find_children("*", "GPUParticles3D", true, false):
		n += (p as GPUParticles3D).amount
	return n


func _systems(fx: Node) -> int:
	return fx.find_children("*", "GPUParticles3D", true, false).size()


func _lights_on(fx: Node) -> int:
	var n: int = 0
	for l: Node in fx.find_children("*", "Light3D", true, false):
		n += 1 if (l as Light3D).visible else 0
	return n


func _run_every_effect() -> void:
	var names: PackedStringArray = []
	for f: String in DirAccess.get_files_at(FX):
		if f.ends_with(".tscn"):
			names.append(f.get_basename())
	_check(names.size() >= 10, "the lab's effects are there (%d scenes)" % names.size())
	for n: String in names:
		var fx: VfxEffect = _effect(n, Vector3.ZERO, Vector3(0, 1, -6))
		_check(fx != null, "%s: its root is a VfxEffect" % n)
		if fx == null:
			continue
		_check(fx.playing and fx.visible, "%s: it plays as it enters the tree" % n)
		_check(fx._clocked.size() >= 2, "%s: its parts run on its clock (%d)" % [n, fx._clocked.size()])
		var finished: bool = _step(fx, fx.duration_s + 0.5)
		_check(finished and fx.is_queued_for_deletion(), "%s: it finishes and frees itself" % n)
		# Kept (the lab's way): it hides instead, and plays again from the start.
		var kept: VfxEffect = _effect(n, Vector3.ZERO, Vector3(0, 1, -6))
		kept.free_when_done = false
		_step(kept, kept.duration_s + 0.5)
		_check(not kept.is_queued_for_deletion() and not kept.visible and not kept.playing, "%s, kept: it hides when done" % n)
		kept.play()
		_check(kept.playing and kept.visible and kept.age == 0.0, "%s, kept: it plays again from the start" % n)
		kept.stop()
		_check(not kept.playing and not kept.visible, "%s: a stopped effect hides" % n)
		kept.queue_free()


func _run_missile() -> void:
	var fx: VfxFireMissile = _effect("fire_missile", Vector3(0, 1, 0), Vector3(0, 1, -10)) as VfxFireMissile
	var at: Array[Vector3] = []
	fx.arrived.connect(func(p: Vector3) -> void: at.append(p))
	var flight: float = 10.0 / fx.speed_mps
	_check(is_equal_approx(fx.duration_s, flight + fx.linger_s), "the missile: it lasts its flight (distance / speed) and its linger")
	_step(fx, flight - 0.1)
	_check(at.is_empty(), "the missile has not arrived a tenth of a second short of its flight")
	_check(fx._body.global_position.z < -7.0 and fx._body.global_position.z > -10.0, "the missile is on its way, short of the target")
	_step(fx, 0.2)
	_check(at.size() == 1 and at[0].is_equal_approx(Vector3(0, 1, -10)), "the missile arrives at its target, once")
	_check(not fx._body.visible and fx.playing, "arrived: the ball is gone, its trail still hangs on")
	fx.queue_free()


func _run_blink() -> void:
	for moves: bool in [true, false]:
		var who := Node3D.new()
		add_child(who)
		var body := MeshInstance3D.new()
		body.mesh = BoxMesh.new()
		who.add_child(body)
		var packed: PackedScene = load(FX + "blink.tscn") as PackedScene
		var fx: VfxBlink = packed.instantiate() as VfxBlink
		fx.caster = who
		fx.target = Vector3(5, 0, -5)
		fx.moves_caster = moves
		add_child(fx)
		fx.set_process(false)
		_step(fx, fx.gone_at_s * 0.5)
		_check(body.transparency > 0.3 and body.transparency < 1.0, "Blink: the body fades as it goes (%.2f)" % body.transparency)
		_step(fx, fx.gone_at_s * 0.5 + 0.03)
		if moves:
			_check(who.global_position.is_equal_approx(Vector3(5, 0, -5)), "Blink: the body is moved at its moment")
		else:
			_check(who.global_position.is_equal_approx(Vector3.ZERO), "Blink told not to move it: the body stays")
		_check(body.transparency > 0.9, "Blink: gone between the two ends")
		_step(fx, fx.duration_s)
		_check(is_zero_approx(body.transparency), "Blink: the fade is put back when it ends")
		fx.queue_free()
		who.queue_free()


func _run_frost_and_shake() -> void:
	# The frost ring and the imp's cinder ring are one family (Luke: "more similar and cohesive"): the same circle,
	# warning and wave, ice or fire.
	for scene: String in ["frost_ring", "cinder_ring"]:
		var ring: VfxGroundRing = _effect(scene) as VfxGroundRing
		_check(ring != null, "%s is a ground ring" % scene)
		if ring == null:
			continue
		_check((ring.element == VfxGroundRing.Element.FIRE) == (scene == "cinder_ring"), "%s: its element" % scene)
		_step(ring, ring.warn_s * 0.5)
		var up_early: int = ring.risen_count()
		_check(up_early == 0, "%s: nothing rises before it lands (%d up)" % [scene, up_early])
		_step(ring, ring.warn_s * 0.5 + 0.4)
		var up_late: int = ring.risen_count(0.5)
		_check(up_late == ring._shards.size(), "%s: everything up after it lands (%d of %d)" % [scene, up_late, ring._shards.size()])
		ring.queue_free()
	_run_blade_cut()
	for strength: float in [0.45, 0.0]:
		var packed: PackedScene = load(FX + "fire_blast.tscn") as PackedScene
		var blast: VfxFireBlast = packed.instantiate() as VfxFireBlast
		blast.shake = strength
		var asked: Array[float] = []
		blast.shook.connect(func(s: float, _secs: float) -> void: asked.append(s))
		add_child(blast)
		blast.set_process(false)
		if strength > 0.0:
			_check(asked.size() == 1 and is_equal_approx(asked[0], strength), "the blast asks the camera to shake, as hard as it says")
		else:
			_check(asked.is_empty(), "a blast with no shake asks for none")
		blast.queue_free()


## The cut follows the weapon: it draws only within its window, along where the blade is (a sword swept round),
## with the look of its own on the ribbon; with no weapon it draws nothing.
func _run_blade_cut() -> void:
	var item: ItemDef = load("res://game/regents/content/item/steel_sword.tres") as ItemDef
	for armed: bool in [true, false]:
		var sword: HeldItem = item.held_scene.instantiate() as HeldItem
		add_child(sword)
		var packed: PackedScene = load(FX + "blade_cut.tscn") as PackedScene
		var cut: VfxBladeCut = packed.instantiate() as VfxBladeCut
		cut.weapon = sword if armed else null
		cut.cut_from_s = 0.1
		cut.hit_at_s = 0.3
		add_child(cut)
		cut.set_process(false)
		cut._sheet.set_process(false)
		_check(cut._sheet.material_override == cut._sheet.look and cut._sheet.look is ShaderMaterial, "the cut's ribbon wears the crescent's look")
		_step(cut, 0.05)
		_check(cut._sheet.sample_count() == 0, "the cut draws nothing before its window (armed: %s)" % armed)
		var t: float = 0.0
		while t < 0.3:
			sword.rotation.x += 0.25   # swept round (across its length)
			cut._process(STEP_S)
			t += STEP_S
		if armed:
			_check(cut._sheet.sample_count() >= 5, "the cut draws the blade's path through its window (%d edges)" % cut._sheet.sample_count())
			_check(cut._struck and cut._hit_at.global_position.distance_to(cut.blade_now()[1] as Vector3) < 1.5, "the hit lands at the blade's tip")
		else:
			_check(cut._sheet.sample_count() == 0, "a cut with no weapon draws nothing")
		cut.queue_free()
		sword.queue_free()


## IN THE GAME (PROGRESS 82, Luke: "lets use the vfx in all the current abilites"): every spell the game has is
## drawn by the lab's looks: a missile by its body's look (a riding `VfxFireMissile`, or the arrow's own), an area by
## `SpellLooks`' rings, Blink and Gale by `ability_vfx.tres`, and every spell with a cast time (and a foe's with a
## tell) shows a charge; every swing wears the crescent.
func _run_coverage() -> void:
	var table: AbilityVfxSet = AbilityVfxSet.current()
	_check(table != null and table.parry is PackedScene, "the game's table of ability effects loads, with the parry's")
	if table == null:
		return
	var spells: Array[ContentDef] = ContentLibrary.items(&"spell")
	_check(spells.size() >= 8, "every spell is looked at (%d)" % spells.size())
	for d: ContentDef in spells:
		var spell: SpellDef = d as SpellDef
		var e: AbilityVfxEntry = table.entry(spell.ability.id)
		var drawn: bool = false
		match spell.kind:
			SpellDef.Kind.BOLT:
				var look: Node = spell.body.visual_scene.instantiate() if spell.body != null and spell.body.visual_scene != null else null
				var rider: bool = false
				for c: Node in look.get_children() if look != null else []:
					rider = rider or (c is VfxFireMissile and (c as VfxFireMissile).rides)
				drawn = rider or (look is ShotLook and spell.body.resource_path.get_file() == "arrow.tres")
				if look != null:
					look.free()
			SpellDef.Kind.AREA:
				drawn = SpellLooks.FROST_RING != null and SpellLooks.CINDER_RING != null
			SpellDef.Kind.BLINK:
				drawn = e != null and e.on_jump != null
			_:
				drawn = e != null and e.on_land != null
		_check(drawn, "%s is drawn by the lab's looks" % spell.display_name)
		# A player's spell with a cast time, and the imp's two (its ember, its ring: their wind-ups are its tells).
		if spell.cast_ms > 0 or spell.ability.id in [40032, 40033]:
			_check(e != null and e.charge != null, "%s shows a charge while it is cast" % spell.display_name)
	var trail := SwingTrail.new()
	_check(trail.crescent and VfxBladeCut.look(trail.crescent_player_color) is ShaderMaterial, "every swing wears the crescent")
	trail.free()


## A FIGHTER STAND-IN: an adventurer's model under `Visual/Model` (its hands), a combat component, an `AbilityVfx`
## bound by hand (no server).
func _fighter(kit: StringName) -> Array:
	var who := Node3D.new()
	add_child(who)
	var vis := Node3D.new()
	vis.name = "Visual"
	who.add_child(vis)
	var man := Mannequin.new()
	man.name = "Model"
	man.definition = load("res://game/regents/content/character/adventurer.tres") as EntityDefinition
	vis.add_child(man)
	var combat := CombatComponent.new()
	combat.is_local_authority = true
	combat.kit = KitDef.by_key(kit)
	var fx := AbilityVfx.new()
	who.add_child(fx)
	# Bound by hand, after it entered the tree (hard rule 8).
	fx.entity = who
	fx.vfx_set = AbilityVfxSet.current()
	fx._combat = combat
	fx._bound = true
	fx.set_process(false)
	return [who, combat, fx, man]


func _run_ability_vfx() -> void:
	var parts: Array = _fighter(&"staff")
	var who: Node3D = parts[0]
	var combat: CombatComponent = parts[1]
	var fx: AbilityVfx = parts[2]
	var man: Mannequin = parts[3]
	await get_tree().process_frame
	await get_tree().process_frame
	# The spells (by their own ids; the game keys their effects on their abilities' ids).
	var fireball: SpellDef = ContentLibrary.find(&"spell", 40002) as SpellDef
	var frost: SpellDef = ContentLibrary.find(&"spell", 40003) as SpellDef
	var blink_id: int = (ContentLibrary.find(&"spell", 40004) as SpellDef).ability.id
	var gale_id: int = (ContentLibrary.find(&"spell", 40005) as SpellDef).ability.id
	# A cast's charge: in front of the casting hand, never in the wrist; gone with the cast.
	fx._process(0.016)
	_check(fx.charge_id == -1 and not is_instance_valid(fx.charge), "NEGATIVE: no cast, no charge")
	combat.cast_spell = fireball
	combat.cast_until_ms = Time.get_ticks_msec() + 600
	fx._process(0.016)
	var hand: Vector3 = man.bone_position(&"hand_l")
	var at: Vector3 = (fx.charge as Node3D).global_position if is_instance_valid(fx.charge) else Vector3.INF
	_check(fx.charge is VfxFireCharge and fx.played.has("fire_charge:%d" % fireball.ability.id), "casting Fireball: its charge shows")
	_check(at != Vector3.INF and absf(at.distance_to(hand) - 0.16) < 0.03 and (at - hand).dot(fx._forward()) > 0.1,
		"in front of the casting hand, toward where you face (%.2f m from it)" % at.distance_to(hand))
	var was: Variant = fx.charge
	combat.cast_spell = null
	combat.cast_until_ms = -1
	fx._process(0.016)
	_check(fx.charge_id == -1 and (not is_instance_valid(was) or (was as Node).is_queued_for_deletion()), "the cast over: the charge goes")
	# Frost Ring: two-handed, between the hands.
	combat.cast_spell = frost
	combat.cast_until_ms = Time.get_ticks_msec() + 1000
	fx._process(0.016)
	var mid: Vector3 = (man.bone_position(&"hand_l") + man.bone_position(&"hand_r")) * 0.5
	at = (fx.charge as Node3D).global_position if is_instance_valid(fx.charge) else Vector3.INF
	_check(fx.played.has("frost_charge:%d" % frost.ability.id) and at != Vector3.INF and absf(at.distance_to(mid) - 0.2) < 0.03, "casting Frost Ring: its charge between both hands, in front")
	combat.cast_spell = null
	combat.cast_until_ms = -1
	fx._process(0.016)
	# Gale lands at once, at the feet, the way it was aimed; a spell with a cast time lands nothing here.
	var before: int = fx.played.size()
	fx.cast_landing(fireball.ability.id, Vector3.FORWARD)
	_check(fx.played.size() == before, "NEGATIVE: Fireball (a cast time) plays nothing as it is sent")
	fx.cast_landing(gale_id, Vector3(1, 0, 0))
	var gale: Node3D = null
	for n: Node in get_children():
		gale = n as Node3D if n is VfxGale else gale
	_check(fx.played.has("gale:%d" % gale_id) and gale != null and gale.global_position.is_equal_approx(who.global_position)
		and (-gale.global_basis.z).is_equal_approx(Vector3(1, 0, 0)), "Gale: the gust at the feet, the way it was aimed")
	# Blink: a jump of 3-12 m in a frame, a staff in hand; not a step, not a respawn, not with a sword.
	fx._process(0.016)
	who.position += Vector3(1.0, 0, 0)
	fx._process(0.016)
	_check(not fx.played.has("blink:%d" % blink_id), "NEGATIVE: a step is no blink")
	who.position += Vector3(0, 0, -8.0)
	fx._process(0.016)
	_check(not fx.played.has("blink:%d" % blink_id), "NEGATIVE: our own character moved 8 m by something else (no Blink cast): no blink")
	fx.cast_landing(blink_id, Vector3.FORWARD)   # we cast Blink; the server's move arrives
	who.position += Vector3(0, 0, -8.0)
	fx._process(0.016)
	var blink: VfxBlink = null
	for n: Node in get_children():
		blink = n as VfxBlink if n is VfxBlink else blink
	_check(fx.played.has("blink:%d" % blink_id) and blink != null and not blink.moves_caster and blink.target.is_equal_approx(who.global_position),
		"a jump of 8 m with a staff: Blink's columns, from where it was to where it is, the body not moved by it")
	var count: int = fx.played.size()
	fx.cast_landing(blink_id, Vector3.FORWARD)
	who.position += Vector3(30, 0, 0)
	fx._process(0.016)
	combat.kit = KitDef.by_key(&"sword")
	fx.cast_landing(blink_id, Vector3.FORWARD)
	who.position += Vector3(8, 0, 0)
	fx._process(0.016)
	_check(fx.played.size() == count, "NEGATIVE: a 30 m jump (a respawn) and a jump with a sword are no blink")
	# Another player's character: no cast is seen here, the jump alone shows it.
	combat.kit = KitDef.by_key(&"staff")
	combat.is_local_authority = false
	fx._process(0.016)
	who.position += Vector3(0, 0, 8)
	fx._process(0.016)
	_check(fx.played.size() == count + 1 and fx.played[-1] == "blink:%d" % blink_id, "another player's 8 m jump with a staff: their blink shows here")
	combat.is_local_authority = true
	# ANOTHER PLAYER'S GALE (Luke, 2026-11-15): the server's `spell_landed` row, shown where they stood, the way they aimed,
	# while it is fresh. Not ours (shown as we cast it), not a stale row handed over as we came near, not a cast-time spell.
	var now_us: int = ClockSync.server_usec()
	var from: Vector3 = Vector3(3, 0, -2)
	_check(fx.required_tables().has(&"spell_landed") and fx.optional_tables().has(&"spell_landed"),
		"AbilityVfx is sent each fighter's `spell_landed` row (optional: none until they cast)")
	fx.is_local_authority = true
	count = fx.played.size()
	_check(not fx.landed_elsewhere(gale_id, from, Vector3(0, 0, 1), now_us) and fx.played.size() == count,
		"NEGATIVE: our own Gale's row plays nothing more (it showed as we cast it)")
	fx.is_local_authority = false
	_check(not fx.landed_elsewhere(gale_id, from, Vector3(0, 0, 1), now_us - (AbilityVfx.FRESH_MS + 500) * 1000) and fx.played.size() == count,
		"NEGATIVE: a row %.1f s old (handed over as we came near) is history: nothing" % ((AbilityVfx.FRESH_MS + 500) / 1000.0))
	_check(not fx.landed_elsewhere(fireball.ability.id, from, Vector3(0, 0, 1), now_us) and fx.played.size() == count,
		"NEGATIVE: their Fireball's landing plays nothing here (its cast showed by its `casting` row, its missile flies)")
	for n: Node in get_children():
		if n is VfxGale:
			n.free()
	var fake: Dictionary = {"ability": gale_id, "from": from, "aim": Vector3(0, 0, 1), "at": now_us}
	var landed_row: LandedRow = _row(fake)
	fx._on_row_updated(&"spell_landed", null, landed_row)
	gale = null
	for n: Node in get_children():
		gale = n as Node3D if n is VfxGale else gale
	_check(fx.played.size() == count + 1 and fx.played[-1] == "gale:%d" % gale_id and gale != null and gale.global_position.is_equal_approx(from)
		and (-gale.global_basis.z).is_equal_approx(Vector3(0, 0, 1)), "another player's Gale, by its row: the gust where they stood, the way they aimed")
	fx._on_row_updated(&"spell_landed", landed_row, _row(fake))
	_check(fx.played.size() == count + 1, "NEGATIVE: the same landing again (its row rewritten, the same stamp): shown once")
	fake["at"] = now_us + 2000
	fx._on_row_updated(&"spell_landed", landed_row, _row(fake))
	_check(fx.played.size() == count + 2, "their next Gale (a new stamp): shown again")
	# THEIR ARMS (Luke, 2026-11-15: "yes, add the pose"): the same row plays their spell's release on their character
	# here, as their own client played it (`ability.<id>`, the arms' clip), by the same freshness.
	var arms := CombatComponent.new()
	var drv := PoseDriver.new()
	arms._driver = drv
	_check(arms.required_tables().has(&"spell_landed") and arms.optional_tables().has(&"spell_landed"),
		"CombatComponent is sent each player's `spell_landed` row (optional)")
	arms.is_local_authority = true
	_check(not arms.landed_elsewhere(gale_id, now_us) and drv.played.is_empty(), "NEGATIVE: our own landing: no second pose (ours played as it landed)")
	arms.is_local_authority = false
	_check(not arms.landed_elsewhere(gale_id, now_us - (AbilityVfx.FRESH_MS + 500) * 1000) and drv.played.is_empty(),
		"NEGATIVE: a row that is history: their arms stay still")
	var arm_row: LandedRow = _row(fake)
	arms._on_row_updated(&"spell_landed", null, arm_row)
	_check(drv.played == [StringName("ability.%d" % gale_id)] and arms.remote_landed_ability == gale_id,
		"another player's Gale, by its row: their arms play its release (%s)" % str(drv.played))
	arms._on_row_updated(&"spell_landed", arm_row, _row(fake))
	_check(drv.played.size() == 1, "NEGATIVE: the same landing again (same stamp): played once")
	var frost_row: Dictionary = {"ability": frost.ability.id, "from": from, "aim": Vector3(0, 0, 1), "at": now_us + 4000}
	arms._on_row_updated(&"spell_landed", arm_row, _row(frost_row))
	_check(drv.played.size() == 2 and drv.played[-1] == StringName("ability.%d" % frost.ability.id),
		"their Frost Ring landing: its release too (the end of a cast, as their own client plays it)")
	arms.free()
	drv.free()
	# A foe's tell: a charge in its hand for the wind-up, gone after.
	combat.kit = null
	var ember: AbilityDef = ContentLibrary.find(&"ability", 40032) as AbilityDef
	fx.began(40032)
	fx._process(0.016)
	at = (fx.charge as Node3D).global_position if is_instance_valid(fx.charge) else Vector3.INF
	_check(fx.played.has("fire_charge:40032") and at != Vector3.INF and absf(at.distance_to(man.bone_position(&"hand_r")) - 0.14) < 0.03,
		"a foe's ember: its tell's charge in its right hand")
	fx._tell_until_ms = Time.get_ticks_msec() - 1
	fx._process(0.016)
	_check(fx.charge_id == -1 and ember.wind_up_ms > 0, "its wind-up over: the charge goes")
	# A parry: the flash at the hand.
	fx.parried(-1)
	_check(fx.played.has("parry_flash:-1"), "a parry: its flash")
	for n: Node in get_children():
		if n is VfxEffect:
			n.queue_free()
	who.queue_free()
	combat.free()
	await get_tree().process_frame


## A stand-in animation driver: what it was asked to play on the arms.
class PoseDriver extends AnimationDriverComponent:
	var played: Array[StringName] = []

	func play_upper(semantic: StringName) -> bool:
		played.append(semantic)
		return true


## A stand-in `spell_landed` row (the fields `AbilityVfx` reads).
class LandedRow extends RefCounted:
	var ability: int
	var from: Vector3
	var aim: Vector3
	var at: int


func _row(fields: Dictionary) -> LandedRow:
	var r := LandedRow.new()
	r.ability = int(fields["ability"])
	r.from = fields["from"] as Vector3
	r.aim = fields["aim"] as Vector3
	r.at = int(fields["at"])
	return r


## The game's rings (`SpellLooks`): the lab's, of the caster's element, landing when the server says; a row gone
## mid-landing lets it play out.
func _run_spell_rings() -> void:
	var looks := SpellLooks.new()
	add_child(looks)
	looks.show_area(7, Vector3(2, 0, 2), 4.0, ClockSync.server_usec() + 1_000_000, false)
	var ring: VfxGroundRing = looks.ring_of(7)
	_check(ring != null and ring.element == VfxGroundRing.Element.FROST and ring.playing and is_equal_approx(ring.radius_m, 4.0),
		"a player's area: the frost ring, its radius")
	ring.set_process(false)
	_step(ring, ring.warn_s + 0.2)
	looks.forget_area(7)
	_check(is_instance_valid(ring) and not ring.is_queued_for_deletion() and ring.free_when_done, "its row gone as it lands: it plays its landing out")
	_step(ring, ring.duration_s)
	_check(ring.is_queued_for_deletion(), "then frees itself")
	looks.show_area(8, Vector3.ZERO, 3.0, ClockSync.server_usec() - 10, true, true)
	var late: VfxGroundRing = looks.ring_of(8)
	_check(late != null and late.element == VfxGroundRing.Element.FIRE and late.warn_s <= SpellLooks.MIN_WARN_S + 0.001,
		"a foe's ring seen already landed: fire, and it lands at once")
	looks.queue_free()
	await get_tree().process_frame


func _run_no_images() -> void:
	var found: PackedStringArray = []
	var dirs: Array[String] = ["res://game/regents/vfx/"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub: String in DirAccess.get_directories_at(d):
			dirs.append(d + sub + "/")
		for f: String in DirAccess.get_files_at(d):
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr", "svg", "ktx", "dds"]:
				found.append(d + f)
	_check(found.is_empty(), "the VFX are made in code: no image files under game/regents/vfx/ %s" % [found])


## TODAY BESIDE NEW (Luke, 2026-11-14): both comparisons show the second pair and the tags, draw today's plain trail
## (the game's own `SwingTrail` values, no look of its own) on the left and the new cut on the right, both along a
## blade that moves; another showcase hides the second pair again.
func _run_comparison(lab: Node3D, showcases: Array) -> void:
	for name_s: String in ["Axe: old | new", "Sword: old | new"]:
		var i: int = -1
		for k: int in showcases.size():
			if String(showcases[k][0]) == name_s:
				i = k
		_check(i >= 0, "the lab has the comparison '%s'" % name_s)
		if i < 0:
			continue
		lab.call(&"_select", i)
		var twin: Node3D = lab.get(&"_twin_root") as Node3D
		var tags: Array = lab.get(&"_tags") as Array
		_check(twin.visible and tags.size() == 2 and (tags[0] as Label3D).visible and (tags[1] as Label3D).visible
			and (tags[0] as Label3D).text == "Old" and (tags[1] as Label3D).text == "New", "%s: the second pair and its tags show" % name_s)
		var today: int = 0
		var new_cut: int = 0
		var plain_look: bool = false
		var until: int = Time.get_ticks_msec() + 4000
		while (today < 3 or new_cut < 3) and Time.get_ticks_msec() < until:
			await get_tree().process_frame
			for p: Variant in lab.get(&"_plain") as Array:
				var tr: Variant = (p as Array)[0]
				if is_instance_valid(tr):
					today = maxi(today, (tr as RibbonTrail).sample_count())
					plain_look = (tr as RibbonTrail).look == null
			for n: Node in (lab.get(&"_stage") as Node3D).get_children():
				if n is VfxBladeCut:
					new_cut = maxi(new_cut, (n as VfxBladeCut)._sheet.sample_count())
		_check(today >= 3 and plain_look, "%s: the old plain trail draws along the blade (%d edges)" % [name_s, today])
		_check(new_cut >= 3, "%s: the new cut draws along the blade (%d edges)" % [name_s, new_cut])
	lab.call(&"_select", 0)
	_check(not (lab.get(&"_twin_root") as Node3D).visible, "another showcase hides the second pair")


func _run_lab() -> void:
	var packed: PackedScene = load("res://game/regents/vfx/vfx_lab.tscn") as PackedScene
	_check(packed != null, "the VFX lab's scene loads")
	if packed == null:
		return
	var lab: Node3D = packed.instantiate() as Node3D
	add_child(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	var showcases: Array = lab.get(&"showcases") as Array
	_check(showcases.size() == 10, "the lab: ten showcases (%d)" % showcases.size())
	var stage: Node3D = lab.get(&"_stage") as Node3D
	for i: int in showcases.size():
		lab.call(&"_select", i)
		# A showcase may wind up first (a foe's swing, the imp's cast): give it up to 3 s.
		var until: int = Time.get_ticks_msec() + 3000
		while stage.get_child_count() == 0 and Time.get_ticks_msec() < until:
			await get_tree().process_frame
		_check(stage.get_child_count() > 0, "the lab plays %s: its effects are on the stage" % showcases[i][0])
	await _run_comparison(lab, showcases)
	lab.call(&"_set_speed", 2)
	_check(is_equal_approx(Engine.time_scale, 0.25), "the lab's quarter speed slows the engine")
	lab.queue_free()
	await get_tree().process_frame
	_check(is_equal_approx(Engine.time_scale, 1.0), "closing the lab gives the engine its speed back")
