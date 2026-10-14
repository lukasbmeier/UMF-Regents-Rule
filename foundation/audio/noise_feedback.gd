class_name NoiseFeedback extends Control
## WHAT THE PLAYER HEARS OF THE WORLD, AND THEIR PING (DECISIONS #233). Each `noise` row as it arrives
## is played where it was made (its `NoiseDef`: its sound, how far it carries, who hears it), and, for
## those its content says, a marker shown there for a few seconds: on screen where it is, or at the
## edge of the screen pointing to it when it is behind or off to one side. Every one heard is said on
## `SignalBus.noise_heard` (a genre's music or HUD reacts to it).
##
## THE PING KEY (`ping`): a ping where the player looks (the middle of the screen), about whatever is
## there (an entity: its id; the ground: a place). The server makes it a noise of kind 1 for everyone.
## What a marker says for a ping is the genre's word for what was pointed at (`callout`).
##
## Presentation only (hard rule 11): it plays, draws and asks; the server decides there was a noise.
## The foundation's HUD adds one.

const TABLE: StringName = &"noise"
const ACTION_PING: StringName = &"ping"
## How far a ping looks for something to point at (the server allows `PING_RANGE_M`, 80).
const PING_REACH_M: float = 78.0
## What a ping's look meets: the level, its props and walls (1, 3) and bodies (2).
const PING_MASK: int = 1 | 2 | 4

## A GENRE'S WORD FOR WHAT A PING POINTS AT: (target_id, maker: SpaceTimeEntity or null) -> String.
## "" keeps the foundation's ("Here", or the thing's name). Fowl Play's: "Wolf!", "Help!", "Nest".
static var callout: Callable = Callable()

## [{pos: Vector3, text: String, color: Color, until_msec: int, label: Label}]
var _markers: Array[Dictionary] = []
## Noise rows already played (a row event can come twice: an insert and an update).
var _seen: Dictionary[int, bool] = {}


func _ready() -> void:
	name = "NoiseFeedback"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not EntityRegistry.global_row_event.is_connected(_on_row):
		EntityRegistry.global_row_event.connect(_on_row)


func _exit_tree() -> void:
	if EntityRegistry.global_row_event.is_connected(_on_row):
		EntityRegistry.global_row_event.disconnect(_on_row)


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION_PING) and event.is_action_pressed(ACTION_PING) and not event.is_echo():
		send_ping()


## PING where the player looks: what is in the middle of the screen within reach. False when there is
## nothing to point at (the sky) or nobody to ping as.
func send_ping() -> bool:
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if me == null or cam == null:
		return false
	var aim: Dictionary = aim_from(cam, me)
	if aim.is_empty():
		return false
	SpaceTimeSync.call_reducer(&"ping", [aim["pos"] as Vector3, int(aim["target"])], ["vector3[f32,f32,f32]", "u64"])
	return true


## Where a ping from `cam` (the middle of its view) lands and what it is about: {pos, target (0: a
## place)}, or {} when it meets nothing within reach. `me`'s own body is looked through.
static func aim_from(cam: Camera3D, me: SpaceTimeEntity) -> Dictionary:
	var from: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * PING_REACH_M, PING_MASK)
	q.collide_with_areas = false
	if me != null and me.body != null:
		q.exclude = [me.body.get_rid()]
	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	return {"pos": hit["position"] as Vector3, "target": target_of(hit.get("collider"))}


## The entity a collider is (or is a wall or prop of), or 0.
static func target_of(collider: Variant) -> int:
	if not (collider is Node):
		return 0
	var n: Node = collider
	while n != null:
		if n is SpaceTimeEntity:
			return (n as SpaceTimeEntity).entity_id
		if n.has_meta(&"entity_id"):
			return int(n.get_meta(&"entity_id"))
		n = n.get_parent()
	return 0


## What a marker for a noise says: its content's label, or for a ping the genre's word for what it was
## about ("Here", or the thing's name, without one).
static func marker_text(def: NoiseDef, target_id: int, maker: SpaceTimeEntity) -> String:
	if not def.label.is_empty():
		return def.label
	if callout.is_valid():
		var said: String = String(callout.call(target_id, maker))
		if not said.is_empty():
			return said
	var t: SpaceTimeEntity = EntityRegistry.get_entity(target_id) as SpaceTimeEntity if target_id != 0 else null
	if t != null and t.definition != null and not t.definition.display_name.is_empty():
		return t.definition.display_name
	return "Here"


func _on_row(ev: RowEvent) -> void:
	if ev.table != TABLE or ev.kind != RowEvent.Kind.INSERTED:
		return
	var row: RefCounted = ev.current()
	if row == null:
		return
	var id: int = int(row.get(&"id"))
	if _seen.has(id):
		return
	_seen[id] = true
	if _seen.size() > 256:
		_seen.erase(_seen.keys()[0])
	hear(int(row.get(&"kind")), row.get(&"pos") as Vector3, int(row.get(&"source_id")), int(row.get(&"target_id")))


## A NOISE ARRIVED: played and marked as its content says, for this player. What was done:
## {heard, marked} (for tests).
func hear(kind: int, pos: Vector3, source_id: int, target_id: int) -> Dictionary:
	var maker: SpaceTimeEntity = EntityRegistry.get_entity(source_id) as SpaceTimeEntity if source_id != 0 else null
	var maker_kind: int = maker.definition.kind if maker != null and maker.definition != null else 0
	var def: NoiseDef = NoiseDef.find(kind, maker_kind)
	var out: Dictionary = {"heard": false, "marked": false}
	if def == null:
		return out
	var me: SpaceTimeEntity = EntityRegistry.get_entity(EntityRegistry.local_entity_id) as SpaceTimeEntity
	var my_kind: int = me.definition.kind if me != null and me.definition != null else -1
	var listener: Vector3 = me.global_position if me != null and me.is_inside_tree() else pos
	if def.heard(maker_kind, my_kind, listener.distance_to(pos)):
		out["heard"] = true
		_play(def, pos)
		SignalBus.noise_heard.emit(kind, pos, source_id, target_id)
	if def.marked_for(maker_kind, my_kind, source_id != 0 and source_id == EntityRegistry.local_entity_id):
		out["marked"] = true
		_mark(pos, marker_text(def, target_id, maker), def.color, def.marker_s)
	return out


func _play(def: NoiseDef, pos: Vector3) -> void:
	if def.sound == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = def.sound
	p.volume_db = def.volume_db
	# Farm-wide: heard from anywhere, quieter with distance but never gone; otherwise to its reach.
	p.max_distance = def.heard_within_m if def.heard_within_m > 0.0 else 0.0
	p.unit_size = 12.0 if def.heard_within_m <= 0.0 else maxf(3.0, def.heard_within_m * 0.15)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if AudioServer.get_bus_index(Settings.BUS_EFFECTS) >= 0:
		p.bus = Settings.BUS_EFFECTS
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(p)
	holder.global_position = pos
	p.finished.connect(holder.queue_free)
	p.play()


func _mark(pos: Vector3, text: String, color: Color, seconds: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 18)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_markers.append({"pos": pos, "text": text, "until_msec": Time.get_ticks_msec() + int(seconds * 1000.0), "label": l})


## The markers up now: [{pos, text}] (for tests).
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in _markers:
		out.append({"pos": m["pos"], "text": m["text"]})
	return out


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var size: Vector2 = get_viewport_rect().size
	for m: Dictionary in _markers.duplicate():
		var l: Label = m["label"]
		if now >= int(m["until_msec"]) or cam == null:
			_markers.erase(m)
			l.queue_free()
			continue
		var at: Dictionary = screen_place(cam, m["pos"] as Vector3, size)
		l.text = ("%s %s" % [at["arrow"], m["text"]]) if not String(at["arrow"]).is_empty() else String(m["text"])
		l.position = (at["point"] as Vector2) - l.size * 0.5
		l.modulate.a = clampf(float(int(m["until_msec"]) - now) / 400.0, 0.0, 1.0)


## Where on a screen of `size` a marker for `world` goes, seen from `cam`: {point, arrow} (arrow: "" on
## screen; a pointer at the edge it is clamped to when it is behind or off to one side).
static func screen_place(cam: Camera3D, world: Vector3, size: Vector2) -> Dictionary:
	var margin: float = 36.0
	var behind: bool = cam.is_position_behind(world)
	var p: Vector2 = cam.unproject_position(world)
	if behind:
		p = size - p   # mirrored: what is behind is pointed to from the opposite side
	var inside: bool = not behind and p.x >= margin and p.x <= size.x - margin and p.y >= margin and p.y <= size.y - margin
	if inside:
		return {"point": p, "arrow": ""}
	var c: Vector2 = size * 0.5
	var d: Vector2 = p - c
	if behind and d.length() < 1.0:
		d = Vector2(0, 1)
	var half: Vector2 = c - Vector2(margin, margin)
	var k: float = minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	var edge: Vector2 = c + d * k
	var arrow: String = "◀" if absf(d.x) * half.y >= absf(d.y) * half.x and d.x < 0.0 else \
		"▶" if absf(d.x) * half.y >= absf(d.y) * half.x else ("▲" if d.y < 0.0 else "▼")
	return {"point": edge, "arrow": arrow}
