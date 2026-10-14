extends "res://tests/suite_base.gd"
## The `noise` suite (DECISIONS #233): what a player hears of the world, and their ping.
##   - which content a noise is: the one for its maker, else anyone's; the foundation's ping
##   - who hears one (its reach; its maker's kind only) and who is shown where it was
##   - what a marker says (the content's label, the genre's word for a ping, the thing's name, "Here")
##   - where on screen a marker goes, and the edge it points from when it is behind or off to one side
##   - what a ping points at (an entity, a wall or prop of one, a place), and what is heard is said
## The server's side (the `ping` reducer, its range and rate, the row gone after a while):
## tests/integration_test.sh.


func run() -> void:
	_run_content()
	_run_who()
	_run_words()
	await _run_screen()
	_run_heard()


func _def(kind: int, makers: Array[EntityDefinition], marker: int, reach: float, others: bool = true) -> NoiseDef:
	var d := NoiseDef.new()
	d.kind = kind
	d.made_by = makers
	d.marker_for = marker
	d.heard_within_m = reach
	d.others_hear = others
	return d


func _char(kind: int, name: String) -> EntityDefinition:
	var e := EntityDefinition.new()
	e.kind = kind
	e.display_name = name
	return e


func _run_content() -> void:
	print("== noise: which content a noise is ==")
	NoiseDef.clear_cache()
	var ping: NoiseDef = NoiseDef.find(1, 0)
	_check(ping != null and ping.resource_path == "res://foundation/content/noise/ping.tres" and ping.sound != null and ping.validate().is_empty(),
		"the foundation's ping (kind 1), with its sound, valid")
	_check(NoiseDef.find(1, 37) == ping, "anyone's ping is it, whatever they are")
	_check(NoiseDef.find(4321, 0) == null, "a kind nobody made content for: not heard")
	var hen: EntityDefinition = _char(100, "Hen")
	var bawk: NoiseDef = _def(1, [hen], NoiseDef.MARKER_MAKERS, 60.0)
	_check(bawk.made_by_kind(100) and not bawk.made_by_kind(101) and ping.made_by_kind(101), "a noise names its makers (a hen's bawk); one naming none is anyone's")
	var none := NoiseDef.new()
	_check(not none.validate().is_empty(), "a noise with no sound is refused")


func _run_who() -> void:
	print("== noise: who hears it, and who is shown where ==")
	var near: NoiseDef = _def(1, [], NoiseDef.MARKER_MAKERS, 60.0)
	_check(near.heard(100, 101, 59.0) and not near.heard(100, 101, 61.0), "heard within its reach (60 m), not beyond")
	var loud: NoiseDef = _def(100, [], NoiseDef.MARKER_OTHERS, 0.0)
	_check(loud.heard(0, 101, 900.0), "reach 0: heard everywhere in its world (a crack, farm-wide)")
	var own: NoiseDef = _def(1, [], NoiseDef.MARKER_MAKERS, 0.0, false)
	_check(own.heard(101, 101, 5.0) and not own.heard(101, 100, 5.0), "its maker's kind only (the wolf's mark): the hens do not hear it")
	_check(near.marked_for(100, 100, false) and not near.marked_for(100, 101, false), "a ping's marker: for its maker's kind (the hens), not the wolf")
	_check(loud.marked_for(0, 101, false) and loud.marked_for(100, 101, false) and not loud.marked_for(101, 101, false),
		"everyone else's: the world's own noise is marked for all; a hen's crack for the wolf, not the hens")
	_check(not _def(1, [], NoiseDef.MARKER_NOBODY, 0.0).marked_for(1, 1, true) and _def(1, [], NoiseDef.MARKER_EVERYONE, 0.0).marked_for(1, 2, false),
		"nobody, and everyone")


func _run_words() -> void:
	print("== noise: what a marker says ==")
	var said: NoiseDef = _def(100, [], NoiseDef.MARKER_OTHERS, 0.0)
	said.label = "Egg cracked!"
	_check(NoiseFeedback.marker_text(said, 0, null) == "Egg cracked!", "its content's label")
	var ping: NoiseDef = _def(1, [], NoiseDef.MARKER_MAKERS, 60.0)
	var was: Callable = NoiseFeedback.callout
	NoiseFeedback.callout = Callable()
	_check(NoiseFeedback.marker_text(ping, 0, null) == "Here", "a ping at a place, with no word of the genre's: \"Here\"")
	NoiseFeedback.callout = func(target_id: int, _maker: SpaceTimeEntity) -> String: return "Wolf!" if target_id == 77 else ""
	_check(NoiseFeedback.marker_text(ping, 77, null) == "Wolf!" and NoiseFeedback.marker_text(ping, 0, null) == "Here",
		"the genre's word for what it points at, and its own when the genre has none")
	NoiseFeedback.callout = was
	var wall := StaticBody3D.new()
	wall.set_meta(&"entity_id", 4242)
	var child := CollisionShape3D.new()
	wall.add_child(child)
	_check(NoiseFeedback.target_of(wall) == 4242 and NoiseFeedback.target_of(child) == 4242 and NoiseFeedback.target_of(Node3D.new()) == 0 and NoiseFeedback.target_of(null) == 0,
		"a ping at a wall or prop of an entity is about that entity; at anything else, a place")
	wall.free()


func _run_screen() -> void:
	print("== noise: where a marker goes on screen ==")
	# A screen of a known size: the camera in its own viewport, 1280 x 720.
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	add_child(view)
	var root := Node3D.new()
	view.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3.ZERO
	cam.look_at(Vector3(0, 0, -10))
	await get_tree().process_frame
	var size: Vector2 = Vector2(view.size)
	var ahead: Dictionary = NoiseFeedback.screen_place(cam, Vector3(0, 0, -10), size)
	_check(String(ahead["arrow"]).is_empty() and (ahead["point"] as Vector2).distance_to(size * 0.5) < 2.0, "ahead: on screen where it is, no arrow")
	var left: Dictionary = NoiseFeedback.screen_place(cam, Vector3(-200, 0, -10), size)
	_check(String(left["arrow"]) == "◀" and (left["point"] as Vector2).x < 40.0, "far to the left: at the left edge, pointing left (%s)" % str(left["point"]))
	var behind: Dictionary = NoiseFeedback.screen_place(cam, Vector3(3, 0, 10), size)
	_check(not String(behind["arrow"]).is_empty(), "behind: pointed to from an edge (%s %s)" % [behind["arrow"], str(behind["point"])])
	view.queue_free()


func _run_heard() -> void:
	print("== noise: heard and said ==")
	var nf := NoiseFeedback.new()
	add_child(nf)
	var heard: Array = []
	var on_heard := func(kind: int, pos: Vector3, src: int, tgt: int) -> void: heard.append([kind, pos, src, tgt])
	SignalBus.noise_heard.connect(on_heard)
	NoiseDef.clear_cache()
	var r: Dictionary = nf.hear(1, Vector3(1, 0, 2), 0, 0)
	_check(bool(r["heard"]) and heard.size() == 1 and int(heard[0][0]) == 1, "a ping arrives: played, and said on SignalBus.noise_heard")
	var none: Dictionary = nf.hear(4321, Vector3.ZERO, 0, 0)
	_check(not bool(none["heard"]) and not bool(none["marked"]) and heard.size() == 1, "a kind with no content: nothing")
	SignalBus.noise_heard.disconnect(on_heard)
	nf.queue_free()
