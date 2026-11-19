class_name RegentsNameplates extends CanvasLayer
## CRISP SCREEN-SPACE OVERHEAD TEXT (Luke, 2026-11-19): replaces fuzzy world-space `Label3D`
## nameplates, status tags, chat bubbles and ground-item labels with native 2D `Label`s projected
## onto a CanvasLayer below the HUD (`layer = 2`).
##
## Clutter & overlap control (Luke, 2026-11-19): sleeker 14/12 px native text, shorter default
## fade (16-24 m, extending to 36 m for your Tab target or whoever you look near), priority-ordered
## vertical anti-overlap stacking (capped at 2 rows; overflow in dense city crowds fades cleanly
## instead of piling to the sky), and a Game Settings choice (`All` / `Focus & close` / `Minimal`).
##
## Presentation only (hard rule 11): reads `NameplateComponent`, `ChatBubble` and `GroundItems`
## without altering any foundation file or gameplay state, keeping template merges clean.
## Every cached node reference is validated with `is_instance_valid()` BEFORE any typed cast.

## Settings key (Game tab: "Overhead names").
const SETTING: StringName = &"regents_overhead_names"

enum Mode { ALL, FOCUS_AND_CLOSE, MINIMAL }

const MODE_NAMES: Array[String] = ["All", "Focus & close", "Minimal"]

## How often (ms) each visible label re-checks world occlusion, staggered across entities.
const LOS_INTERVAL_MS: int = 100
## How often (ms) to scan for a newly spawned `GroundItems` node when none is cached yet.
const GROUND_SCAN_MS: int = 500
## Off-screen padding (px) before culling a projected label.
const SCREEN_MARGIN_PX: float = 200.0
## Ray hit within this distance of the anchor point counts as unoccluded (low ceiling / graze).
const LOS_GRAZE_M: float = 0.45
## Hysteresis half-width (m) around `far_distance_m` so font size never flickers on the threshold.
const SIZE_HYSTERESIS_M: float = 1.0
## Max width (px) for wrapped overhead chat bubbles.
const BUBBLE_MAX_WIDTH_PX: float = 260.0
## Padding (px) between stacked overhead labels when resolving screen-space overlap.
const OVERLAP_PAD_X: float = 6.0
const OVERLAP_PAD_Y: float = 2.0
## Priority tiers for overlap sorting (higher stays anchored and never hides in crowds).
const PRIO_NORMAL: int = 0
const PRIO_LOOK: int = 1
const PRIO_ACTIVE: int = 2
const PRIO_TARGET: int = 3

@export_group("Typography")
@export_range(10, 24, 1, "suffix:px") var name_font_size: int = 14
@export_range(10, 20, 1, "suffix:px") var far_font_size: int = 12
@export_range(9, 18, 1, "suffix:px") var tag_font_size: int = 11
@export_range(10, 20, 1, "suffix:px") var bubble_font_size: int = 13
@export_range(10, 18, 1, "suffix:px") var ground_font_size: int = 12
@export_range(0, 8, 1, "suffix:px") var outline_size: int = 3

@export_group("Range & Clutter")
@export var mode: Mode = Mode.ALL
## Distance (m) past which normal names step down from `name_font_size` to `far_font_size`.
@export_range(4.0, 30.0, 0.5, "suffix:m") var far_distance_m: float = 12.0
## Default max range (m) for non-focused entities in `All` mode (fades smoothly near this edge).
@export_range(8.0, 40.0, 1.0, "suffix:m") var normal_max_distance_m: float = 24.0
## Extended max range (m) for your Tab target or whoever you aim near.
@export_range(12.0, 50.0, 1.0, "suffix:m") var focus_max_distance_m: float = 36.0
## Always-show close range (m) used by `Focus & close` mode.
@export_range(4.0, 24.0, 0.5, "suffix:m") var close_distance_m: float = 10.0
## Screen-center radius (px) that counts as "looking near" an entity.
@export_range(40.0, 300.0, 5.0, "suffix:px") var focus_radius_px: float = 130.0
## Share of max distance where fade begins (0.67 -> fades smoothly across the outer third).
@export_range(0.1, 0.95, 0.05) var fade_start_ratio: float = 0.67
## Max distance (m) for ground item labels.
@export_range(6.0, 40.0, 1.0, "suffix:m") var ground_max_distance_m: float = 20.0
## Maximum vertical lifts when resolving overlap; lower-priority overflow hides cleanly in dense crowds.
@export_range(0, 5, 1) var max_stack_rows: int = 2
## Hide overhead labels when solid world geometry (layer 1) blocks line of sight from the camera.
@export var check_occlusion: bool = true

@export_group("Colors")
@export var name_color: Color = Color(0.98, 0.97, 0.94, 0.98)
@export var target_name_color: Color = Color(1.0, 0.92, 0.68, 1.0)
@export var outline_color: Color = Color(0.04, 0.04, 0.06, 0.94)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.65)
@export var bubble_bg_color: Color = Color(0.06, 0.07, 0.09, 0.76)

## Whether this overlay reads and follows the `Settings` choice (false for isolated tests).
var follows_setting: bool = true
## The local player's CombatComponent (for Tab-target priority), assigned by RegentsHud.
var combat: CombatComponent = null
## Optional explicit target override (for tests without a bound CombatComponent).
var target_id_override: int = -1

var _root: Control = null
## entity_id -> {entity, plate, holder, box, bubble_wrap, bubble, name, tag, font_size, targeted, occluded, next_los_ms, bubble3d}
var _entries: Dictionary[int, Dictionary] = {}
## sack instance_id -> {sack, label3d, label, occluded, next_los_ms}
var _ground: Dictionary[int, Dictionary] = {}
var _ground_items: GroundItems = null
var _next_ground_scan_ms: int = 0
var _bubble_style: StyleBoxFlat = null


## Register the Game Settings choice ("Overhead names") once.
static func define_setting() -> void:
	if not Settings.entry(SETTING).is_empty():
		return
	Settings.define(SETTING, Settings.GAME, "Overhead names", Settings.Kind.CHOICE, Mode.ALL, {
		"choices": PackedStringArray(MODE_NAMES),
		"tooltip": "How names over characters and loot are shown. All: nearby names with anti-overlap; Focus & close: your target, whoever you look at, and close neighbors; Minimal: target and direct look-at only.",
	})


func _ready() -> void:
	name = "OverheadNames"
	layer = 2
	if follows_setting:
		define_setting()
		if not Settings.changed.is_connected(_on_setting):
			Settings.changed.connect(_on_setting)
		mode = clampi(int(Settings.get_value(SETTING)), 0, MODE_NAMES.size() - 1) as Mode
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bubble_style = StyleBoxFlat.new()
	_bubble_style.bg_color = bubble_bg_color
	_bubble_style.set_corner_radius_all(6)
	_bubble_style.content_margin_left = 8
	_bubble_style.content_margin_right = 8
	_bubble_style.content_margin_top = 3
	_bubble_style.content_margin_bottom = 3


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)
	for entry: Dictionary in _entries.values():
		var holder: Node3D = _live_node3d(entry.get("holder"))
		if holder != null:
			holder.visible = true
		var b3d: Label3D = _live_label3d(entry.get("bubble3d"))
		if b3d != null:
			b3d.visible = true
	for g: Dictionary in _ground.values():
		var l3d: Label3D = _live_label3d(g.get("label3d"))
		if l3d != null:
			l3d.visible = true
	_entries.clear()
	_ground.clear()
	_ground_items = null


func _on_setting(key: StringName, value: Variant) -> void:
	if key == SETTING:
		mode = clampi(int(value), 0, MODE_NAMES.size() - 1) as Mode


func _process(_delta: float) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	refresh(vp.get_camera_3d(), vp.get_visible_rect().size)


## Project every active overhead label against `cam` into a viewport of `view_size`. Exposed for tests.
func refresh(cam: Camera3D, view_size: Vector2 = Vector2.ZERO) -> void:
	_sync_entities()
	_sync_ground_items()
	if cam == null or not is_instance_valid(cam):
		_hide_all()
		return
	if view_size.x <= 0.0 or view_size.y <= 0.0:
		var vp: Viewport = get_viewport()
		view_size = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	var now_ms: int = Time.get_ticks_msec()
	var world3d: World3D = cam.get_world_3d()
	var space: PhysicsDirectSpaceState3D = world3d.direct_space_state if check_occlusion and world3d != null else null
	var cam_pos: Vector3 = cam.global_position
	_update_entities(cam, cam_pos, view_size, space, now_ms)
	_update_ground(cam, cam_pos, view_size, space, now_ms)


## The 2D nameplate container for `entity_id`, or null (for tests).
func plate_for(entity_id: int) -> VBoxContainer:
	var entry: Dictionary = _entries.get(entity_id, {})
	var raw: Variant = entry.get("box")
	return raw as VBoxContainer if is_instance_valid(raw) else null


## The 2D ground-item label for `sack`, or null (for tests).
func ground_label_for(sack: Node3D) -> Label:
	if not is_instance_valid(sack):
		return null
	var g: Dictionary = _ground.get(sack.get_instance_id(), {})
	var raw: Variant = g.get("label")
	return raw as Label if is_instance_valid(raw) else null


## Distance fade multiplier in [0, 1]: full opacity out to `max_dist * fade_ratio`, then smooth linear fade.
static func distance_alpha(dist: float, max_dist: float, fade_ratio: float = 0.67) -> float:
	if max_dist <= 0.0 or dist >= max_dist:
		return 0.0
	var start: float = max_dist * clampf(fade_ratio, 0.0, 0.99)
	if dist <= start:
		return 1.0
	return clampf((max_dist - dist) / maxf(max_dist - start, 0.001), 0.0, 1.0)


## Pick an integer font size for `dist` with hysteresis so walking across `split_m` never flickers.
static func choose_font_size(dist: float, current_size: int, near_size: int, far_size: int, split_m: float) -> int:
	if current_size == far_size:
		return near_size if dist < split_m - SIZE_HYSTERESIS_M else far_size
	return far_size if dist > split_m + SIZE_HYSTERESIS_M else near_size


## Closer entities sort on top of farther ones; targeted/focused entities sort above background labels.
static func depth_z_index(dist: float, priority: int = 0) -> int:
	return clampi(1000 - int(dist * 10.0), 0, 1000) + priority * 250


## Pixel-snapped top-left position for a box of `box_size` bottom-centered on `screen`.
static func anchor_position(screen: Vector2, box_size: Vector2) -> Vector2:
	return Vector2(roundf(screen.x - box_size.x * 0.5), roundf(screen.y - box_size.y))


## Resolve 2D screen-space overlaps in place on `items` (each: `{id, priority, dist, pos, size, keep}`).
## Sorts higher priority first (then nearer 0.5 m distance bucket, then stable id), nudging colliding
## labels cleanly upward up to `max_lifts` rows. Writes `pos`, `lifts`, and `visible` on every item:
## overflow past `max_lifts` hides low-priority crowd labels while `keep == true` always stays visible.
static func resolve_overlaps(items: Array[Dictionary], max_lifts: int = 2) -> void:
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a["priority"])
		var pb: int = int(b["priority"])
		if pa != pb:
			return pa > pb
		var ba: int = int(float(a["dist"]) * 2.0)
		var bb: int = int(float(b["dist"]) * 2.0)
		if ba != bb:
			return ba < bb
		return int(a["id"]) < int(b["id"]))
	var placed: Array[Rect2] = []
	for item: Dictionary in items:
		var pos: Vector2 = item["pos"] as Vector2
		var sz: Vector2 = item["size"] as Vector2
		var lifts: int = 0
		var fits: bool = false
		while true:
			var rect: Rect2 = Rect2(pos.x - OVERLAP_PAD_X * 0.5, pos.y - OVERLAP_PAD_Y * 0.5,
				sz.x + OVERLAP_PAD_X, sz.y + OVERLAP_PAD_Y)
			var blocker_y: float = INF
			for other: Rect2 in placed:
				if rect.intersects(other):
					blocker_y = minf(blocker_y, other.position.y)
			if blocker_y == INF:
				fits = true
				break
			if lifts >= max_lifts:
				break
			pos.y = roundf(blocker_y - sz.y - OVERLAP_PAD_Y * 0.5)
			lifts += 1
		var must_keep: bool = bool(item.get("keep", false))
		item["pos"] = pos
		item["lifts"] = lifts
		item["visible"] = fits or must_keep
		if fits or must_keep:
			placed.append(Rect2(pos.x - OVERLAP_PAD_X * 0.5, pos.y - OVERLAP_PAD_Y * 0.5,
				sz.x + OVERLAP_PAD_X, sz.y + OVERLAP_PAD_Y))


# --- Entity nameplates, status tags & chat bubbles -------------------------------------------

func _current_target_id() -> int:
	if target_id_override >= 0:
		return target_id_override
	if combat != null and is_instance_valid(combat):
		return combat.target_id
	return -1


func _sync_entities() -> void:
	var seen: Dictionary[int, bool] = {}
	for eid: int in EntityRegistry.all_entity_ids():
		if EntityRegistry.is_local(eid):
			continue
		var raw_ent: Variant = EntityRegistry.get_entity(eid)
		if not is_instance_valid(raw_ent):
			continue
		var ent: SpaceTimeEntity = raw_ent as SpaceTimeEntity
		if ent == null or ent.is_local_authority:
			continue
		seen[eid] = true
		if _entries.has(eid):
			var existing: Dictionary = _entries[eid]
			var prev: Variant = existing.get("entity")
			if is_instance_valid(prev) and prev == ent:
				continue
			_free_entity_entry(eid)
		var plate: NameplateComponent = ent.find_component(NameplateComponent) as NameplateComponent
		var holder: Node3D = ent.get_node_or_null(^"Nameplate") as Node3D
		if plate == null or holder == null:
			continue
		holder.visible = false
		_entries[eid] = _make_entity_entry(eid, ent, plate, holder)
	for eid: int in _entries.keys():
		if not seen.has(eid):
			_free_entity_entry(eid)


func _make_entity_entry(eid: int, ent: SpaceTimeEntity, plate: NameplateComponent, holder: Node3D) -> Dictionary:
	var box := VBoxContainer.new()
	box.name = "Plate_%d" % eid
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override(&"separation", 1)
	box.visible = false
	var bubble_wrap := PanelContainer.new()
	bubble_wrap.name = "BubbleWrap"
	bubble_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bubble_wrap.add_theme_stylebox_override(&"panel", _bubble_style)
	bubble_wrap.visible = false
	var bubble := Label.new()
	bubble.name = "Bubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.custom_minimum_size = Vector2(0.0, 0.0)
	_style_label(bubble, bubble_font_size, maxi(outline_size - 1, 2), Color(1.0, 1.0, 1.0, 0.98))
	bubble_wrap.add_child(bubble)
	box.add_child(bubble_wrap)
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(name_lbl, name_font_size, outline_size, name_color)
	box.add_child(name_lbl)
	var tag_lbl := Label.new()
	tag_lbl.name = "Tag"
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_lbl.visible = false
	_style_label(tag_lbl, tag_font_size, maxi(outline_size - 1, 2), Color.WHITE)
	box.add_child(tag_lbl)
	_root.add_child(box)
	return {
		"entity": ent,
		"plate": plate,
		"holder": holder,
		"box": box,
		"bubble_wrap": bubble_wrap,
		"bubble": bubble,
		"name": name_lbl,
		"tag": tag_lbl,
		"font_size": name_font_size,
		"targeted": false,
		"occluded": false,
		"next_los_ms": 0,
		"bubble3d": null,
	}


func _free_entity_entry(eid: int) -> void:
	var entry: Dictionary = _entries.get(eid, {})
	if entry.is_empty():
		return
	var holder: Node3D = _live_node3d(entry.get("holder"))
	if holder != null:
		holder.visible = true
	var b3d: Label3D = _live_label3d(entry.get("bubble3d"))
	if b3d != null:
		b3d.visible = true
	var raw_box: Variant = entry.get("box")
	if is_instance_valid(raw_box):
		(raw_box as VBoxContainer).queue_free()
	_entries.erase(eid)


func _update_entities(cam: Camera3D, cam_pos: Vector3, view_size: Vector2,
		space: PhysicsDirectSpaceState3D, now_ms: int) -> void:
	var target_id: int = _current_target_id()
	var center: Vector2 = view_size * 0.5
	var candidates: Array[Dictionary] = []
	for eid: int in _entries:
		var entry: Dictionary = _entries[eid]
		var raw_box: Variant = entry.get("box")
		if not is_instance_valid(raw_box):
			continue
		var box: VBoxContainer = raw_box as VBoxContainer
		var raw_ent: Variant = entry.get("entity")
		var raw_plate: Variant = entry.get("plate")
		var raw_holder: Variant = entry.get("holder")
		if not is_instance_valid(raw_ent) or not is_instance_valid(raw_plate) or not is_instance_valid(raw_holder):
			box.visible = false
			continue
		var ent: SpaceTimeEntity = raw_ent as SpaceTimeEntity
		var plate: NameplateComponent = raw_plate as NameplateComponent
		var holder: Node3D = raw_holder as Node3D
		if holder.visible:
			holder.visible = false
		if not ent.is_visible_in_tree():
			box.visible = false
			continue
		var shown: String = plate.shown_name()
		if shown.is_empty():
			box.visible = false
			continue
		var anchor: Vector3 = ent.get_global_transform_interpolated().origin + Vector3(0.0, plate.height, 0.0)
		if _behind_camera(cam, cam_pos, anchor):
			box.visible = false
			continue
		var dist: float = cam_pos.distance_to(anchor)
		var hard_max: float = maxf(plate.max_distance_m, 0.1)
		if dist >= hard_max or dist < 0.15:
			box.visible = false
			continue
		var screen: Vector2 = cam.unproject_position(anchor)
		if not _on_screen(screen, view_size):
			box.visible = false
			continue
		var is_target: bool = eid == target_id
		var tag_text: String = plate.shown_tag()
		var has_bubble: bool = _has_live_bubble(ent)
		var has_active: bool = has_bubble or not tag_text.is_empty()
		var look_r: float = focus_radius_px * (0.7 if mode == Mode.MINIMAL else 1.0)
		var is_focused: bool = screen.distance_to(center) <= look_r
		var eff_max: float = _effective_max_distance(hard_max, is_target, has_active, is_focused)
		if eff_max <= 0.0 or dist >= eff_max:
			box.visible = false
			continue
		if space != null and now_ms >= int(entry["next_los_ms"]):
			entry["next_los_ms"] = now_ms + LOS_INTERVAL_MS + (absi(eid) * 17) % (LOS_INTERVAL_MS / 2)
			entry["occluded"] = _is_occluded(space, cam_pos, anchor)
		if bool(entry["occluded"]):
			box.visible = false
			continue
		var priority: int = PRIO_TARGET if is_target else (PRIO_ACTIVE if has_active else (PRIO_LOOK if is_focused else PRIO_NORMAL))
		var dirty: bool = false
		var name_lbl: Label = entry["name"] as Label
		if name_lbl.text != shown:
			name_lbl.text = shown
			dirty = true
		if bool(entry["targeted"]) != is_target:
			entry["targeted"] = is_target
			name_lbl.add_theme_color_override(&"font_color", target_name_color if is_target else name_color)
		var want_size: int = name_font_size if priority >= PRIO_LOOK \
			else choose_font_size(dist, int(entry["font_size"]), name_font_size, far_font_size, far_distance_m)
		if want_size != int(entry["font_size"]):
			entry["font_size"] = want_size
			name_lbl.add_theme_font_size_override(&"font_size", want_size)
			dirty = true
		var tag_lbl: Label = entry["tag"] as Label
		var want_tag: bool = not tag_text.is_empty()
		if tag_lbl.visible != want_tag:
			tag_lbl.visible = want_tag
			dirty = true
		if want_tag:
			if tag_lbl.text != tag_text:
				tag_lbl.text = tag_text
				dirty = true
			var tag3d: Label3D = holder.get_node_or_null(^"Tag") as Label3D
			var tag_col: Color = Color(tag3d.modulate.r, tag3d.modulate.g, tag3d.modulate.b, 0.98) if tag3d != null else Color.WHITE
			tag_lbl.add_theme_color_override(&"font_color", tag_col)
		if _sync_chat_bubble(ent, entry):
			dirty = true
		if dirty:
			box.reset_size()
		var sz: Vector2 = box.get_combined_minimum_size()
		box.size = sz
		var alpha: float = distance_alpha(dist, eff_max, fade_start_ratio)
		if priority == PRIO_NORMAL and dist > far_distance_m:
			alpha *= 0.85
		candidates.append({
			"id": eid,
			"box": box,
			"priority": priority,
			"dist": dist,
			"pos": anchor_position(screen, sz),
			"size": sz,
			"alpha": alpha,
			"keep": priority >= PRIO_ACTIVE,
		})
	resolve_overlaps(candidates, max_stack_rows)
	for c: Dictionary in candidates:
		var box: VBoxContainer = c["box"] as VBoxContainer
		var shown_now: bool = bool(c["visible"])
		box.visible = shown_now
		if not shown_now:
			continue
		var lifts: int = int(c["lifts"])
		var lift_dim: float = 1.0 if lifts == 0 or int(c["priority"]) >= PRIO_ACTIVE else (0.88 if lifts == 1 else 0.76)
		box.position = c["pos"] as Vector2
		box.z_index = depth_z_index(float(c["dist"]), int(c["priority"]))
		box.modulate.a = float(c["alpha"]) * lift_dim


## Max visible distance for an entity given the active `mode` and its focus/target state.
func _effective_max_distance(hard_max: float, is_target: bool, has_active: bool, is_focused: bool) -> float:
	if is_target:
		return minf(hard_max, focus_max_distance_m)
	match mode:
		Mode.ALL:
			if is_focused or has_active:
				return minf(hard_max, focus_max_distance_m)
			return minf(hard_max, normal_max_distance_m)
		Mode.FOCUS_AND_CLOSE:
			if is_focused:
				return minf(hard_max, minf(focus_max_distance_m, 30.0))
			if has_active:
				return minf(hard_max, normal_max_distance_m)
			return minf(hard_max, close_distance_m)
		Mode.MINIMAL:
			if is_focused:
				return minf(hard_max, 22.0)
			if has_active:
				return minf(hard_max, 20.0)
			return 0.0
	return minf(hard_max, normal_max_distance_m)


static func _has_live_bubble(ent: SpaceTimeEntity) -> bool:
	var b3d: Label3D = ent.get_node_or_null(^"ChatBubble") as Label3D
	return b3d != null and is_instance_valid(b3d) and not b3d.is_queued_for_deletion() and not b3d.text.is_empty()


func _sync_chat_bubble(ent: SpaceTimeEntity, entry: Dictionary) -> bool:
	var dirty: bool = false
	var wrap: PanelContainer = entry["bubble_wrap"] as PanelContainer
	var lbl: Label = entry["bubble"] as Label
	var b3d: Label3D = ent.get_node_or_null(^"ChatBubble") as Label3D
	if b3d != null and is_instance_valid(b3d) and not b3d.is_queued_for_deletion() and not b3d.text.is_empty():
		b3d.visible = false
		entry["bubble3d"] = b3d
		if lbl.text != b3d.text:
			lbl.text = b3d.text
			# Only constrain width when the message is long enough to wrap, so short lines stay snug.
			lbl.custom_minimum_size.x = BUBBLE_MAX_WIDTH_PX if b3d.text.length() > 36 else 0.0
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if b3d.text.length() > 36 else TextServer.AUTOWRAP_OFF
			dirty = true
		wrap.modulate.a = b3d.modulate.a
		if not wrap.visible:
			wrap.visible = true
			dirty = true
	else:
		entry["bubble3d"] = null
		if wrap.visible:
			wrap.visible = false
			dirty = true
	return dirty


# --- Ground item labels ----------------------------------------------------------------------

func _sync_ground_items() -> void:
	if _ground_items == null or not is_instance_valid(_ground_items):
		var now_ms: int = Time.get_ticks_msec()
		if now_ms < _next_ground_scan_ms:
			return
		_next_ground_scan_ms = now_ms + GROUND_SCAN_MS
		var root_win: Node = get_tree().root if get_tree() != null else null
		_ground_items = root_win.find_child("GroundItems", true, false) as GroundItems if root_win != null else null
		if _ground_items == null:
			return
	var seen: Dictionary[int, bool] = {}
	for child: Node in _ground_items.get_children():
		var sack: Node3D = child as Node3D
		if sack == null or sack.is_queued_for_deletion():
			continue
		var l3d: Label3D = sack.get_node_or_null(^"Name") as Label3D
		if l3d == null:
			continue
		var key: int = sack.get_instance_id()
		seen[key] = true
		if not _ground.has(key):
			l3d.visible = false
			var lbl := Label.new()
			lbl.name = "Ground_%d" % key
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.visible = false
			var col: Color = Color(l3d.modulate.r, l3d.modulate.g, l3d.modulate.b, 0.98)
			_style_label(lbl, ground_font_size, maxi(outline_size - 1, 2), col)
			lbl.text = l3d.text
			_root.add_child(lbl)
			_ground[key] = {
				"sack": sack,
				"label3d": l3d,
				"label": lbl,
				"occluded": false,
				"next_los_ms": 0,
			}
	for key: int in _ground.keys():
		if not seen.has(key):
			var g: Dictionary = _ground[key]
			var l3d: Label3D = _live_label3d(g.get("label3d"))
			if l3d != null:
				l3d.visible = true
			var raw_lbl: Variant = g.get("label")
			if is_instance_valid(raw_lbl):
				(raw_lbl as Label).queue_free()
			_ground.erase(key)


func _update_ground(cam: Camera3D, cam_pos: Vector3, view_size: Vector2,
		space: PhysicsDirectSpaceState3D, now_ms: int) -> void:
	var center: Vector2 = view_size * 0.5
	var candidates: Array[Dictionary] = []
	for key: int in _ground:
		var g: Dictionary = _ground[key]
		var raw_lbl: Variant = g.get("label")
		if not is_instance_valid(raw_lbl):
			continue
		var lbl: Label = raw_lbl as Label
		var sack: Node3D = _live_node3d(g.get("sack"))
		var l3d: Label3D = _live_label3d(g.get("label3d"))
		if sack == null or l3d == null or not sack.is_visible_in_tree():
			lbl.visible = false
			continue
		if l3d.visible:
			l3d.visible = false
		var anchor: Vector3 = sack.global_position + Vector3(0.0, l3d.position.y, 0.0)
		if _behind_camera(cam, cam_pos, anchor):
			lbl.visible = false
			continue
		var dist: float = cam_pos.distance_to(anchor)
		var screen: Vector2 = cam.unproject_position(anchor)
		if not _on_screen(screen, view_size):
			lbl.visible = false
			continue
		var is_focused: bool = screen.distance_to(center) <= focus_radius_px
		var eff_max: float = ground_max_distance_m if mode != Mode.MINIMAL else (14.0 if is_focused else close_distance_m)
		if dist >= eff_max or dist < 0.15:
			lbl.visible = false
			continue
		if space != null and now_ms >= int(g["next_los_ms"]):
			g["next_los_ms"] = now_ms + LOS_INTERVAL_MS + (absi(key) * 13) % (LOS_INTERVAL_MS / 2)
			g["occluded"] = _is_occluded(space, cam_pos, anchor)
		if bool(g["occluded"]):
			lbl.visible = false
			continue
		if lbl.text != l3d.text:
			lbl.text = l3d.text
			lbl.reset_size()
		var sz: Vector2 = lbl.get_combined_minimum_size()
		lbl.size = sz
		candidates.append({
			"id": key,
			"label": lbl,
			"priority": PRIO_LOOK if is_focused else PRIO_NORMAL,
			"dist": dist,
			"pos": anchor_position(screen, sz),
			"size": sz,
			"alpha": distance_alpha(dist, eff_max, fade_start_ratio),
			"keep": false,
		})
	resolve_overlaps(candidates, max_stack_rows)
	for c: Dictionary in candidates:
		var lbl: Label = c["label"] as Label
		var shown_now: bool = bool(c["visible"])
		lbl.visible = shown_now
		if not shown_now:
			continue
		lbl.position = c["pos"] as Vector2
		lbl.z_index = depth_z_index(float(c["dist"]), int(c["priority"]))
		lbl.modulate.a = float(c["alpha"])


# --- Helpers ---------------------------------------------------------------------------------

func _hide_all() -> void:
	for entry: Dictionary in _entries.values():
		var raw_box: Variant = entry.get("box")
		if is_instance_valid(raw_box):
			(raw_box as VBoxContainer).visible = false
	for g: Dictionary in _ground.values():
		var raw_lbl: Variant = g.get("label")
		if is_instance_valid(raw_lbl):
			(raw_lbl as Label).visible = false


static func _live_node3d(raw: Variant) -> Node3D:
	return raw as Node3D if is_instance_valid(raw) else null


static func _live_label3d(raw: Variant) -> Label3D:
	return raw as Label3D if is_instance_valid(raw) else null


## True when `world` is behind or on the camera plane (avoids `unproject_position` `p.d == 0` engine error).
static func _behind_camera(cam: Camera3D, cam_pos: Vector3, world: Vector3) -> bool:
	return (-cam.global_transform.basis.z).dot(world - cam_pos) <= 0.15


func _style_label(lbl: Label, size_px: int, outline_px: int, color: Color) -> void:
	lbl.add_theme_font_size_override(&"font_size", size_px)
	lbl.add_theme_color_override(&"font_color", color)
	lbl.add_theme_color_override(&"font_outline_color", outline_color)
	lbl.add_theme_constant_override(&"outline_size", outline_px)
	lbl.add_theme_color_override(&"font_shadow_color", shadow_color)
	lbl.add_theme_constant_override(&"shadow_offset_x", 0)
	lbl.add_theme_constant_override(&"shadow_offset_y", 1)
	lbl.add_theme_constant_override(&"shadow_outline_size", 2)


static func _on_screen(p: Vector2, size: Vector2) -> bool:
	return p.x >= -SCREEN_MARGIN_PX and p.x <= size.x + SCREEN_MARGIN_PX \
		and p.y >= -SCREEN_MARGIN_PX and p.y <= size.y + SCREEN_MARGIN_PX


static func _is_occluded(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, SpaceTimeEntity.WORLD_MASK)
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return false
	return (hit["position"] as Vector3).distance_to(to) > LOS_GRAZE_M
