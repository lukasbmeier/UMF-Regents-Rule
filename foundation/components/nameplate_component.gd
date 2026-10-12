class_name NameplateComponent extends SpaceTimeComponent
## Who that is. Draws the player's name above their head, for everyone except themselves.
##
## The entity drops its `Nameplate` node for the local player (`SpaceTimeEntity`), so this
## component simply finds nothing to fill and costs nothing there — you do not need a label
## telling you who you are, and one drawn at your own camera would fill the screen.
##
## `player` is keyed by IDENTITY, not by entity, but it carries `entity_id`, which is what the
## registry routes on. An entity with no player row is an NPC or a prop: it keeps whatever the
## definition calls it, so a rival angler is labelled without the server having to invent a
## player row for it.
##
## Presentation only (hard rule 11): it reads a row and draws text. Nothing here can produce a
## gameplay event, and an entity whose name never arrives is a character with a blank label
## rather than a broken one.

const TABLE: StringName = &"player"

## Metres above the entity's origin — which is at its FEET (ENTITY CONVENTIONS), so this is
## roughly head height plus a little clearance.
@export var height: float = 2.05
@export var font_size: int = 48
## World-space size of the text. Small enough not to be a billboard across the pond.
@export var text_scale: float = 0.0045
## Past this, the label is not worth drawing or reading.
@export var max_distance_m: float = 40.0

var _label: Label3D = null
## A second line under the name: the entity's status (`set_tag`), in its colour.
var _tag: Label3D = null
var _tag_text: String = ""
var _tag_color: Color = Color.WHITE
var _holder: Node3D = null
## THE NAME ARRIVES BEFORE THE LABEL DOES. `bind()` replays the rows that were already in the
## cache and only then calls `_on_bound()`, so a component that kept its state inside a node it
## builds in `_on_bound` silently drops everything that was true before it existed — which for a
## nameplate is every player who was already in the world when you joined. Row state lives here;
## `_on_bound` builds the node and renders whatever is already known.
var _given_name: String = ""
## `player.online`. False for an entity with no player row, which is never a person.
var _online: bool = false
## Whether a `player` row has arrived for it: a person, whatever kind of character it plays.
var _is_player: bool = false


func required_tables() -> Array[StringName]:
	return [TABLE]


## An entity may legitimately have no player row — every NPC and every prop. Without this they
## would each sit out the full bind timeout before appearing (DECISIONS #69).
func optional_tables() -> Array[StringName]:
	return [TABLE]


func _on_bound() -> void:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent == null:
		return
	_holder = ent.get_node_or_null(^"Nameplate") as Node3D
	if _holder == null:
		return   # the local player: the entity dropped it, and that is the intended case
	_label = Label3D.new()
	_label.name = "Label"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.fixed_size = false
	_label.font_size = font_size
	_label.outline_size = font_size / 6
	_label.modulate = Color(1.0, 1.0, 1.0, 0.92)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_label.pixel_size = text_scale
	_label.position = Vector3(0.0, height, 0.0)
	_label.visibility_range_end = max_distance_m
	_holder.add_child(_label)
	_refresh()
	if not _tag_text.is_empty():
		set_tag(_tag_text, _tag_color)


## What to show before a name arrives, or for something that will never have one. A definition's
## `display_name` is how the rival angler is labelled without a player row; a player (kind 0) is
## "Player <id>" until its name arrives, not its character's name ("Humanoid").
func _fallback_name() -> String:
	var ent: SpaceTimeEntity = entity as SpaceTimeEntity
	if ent != null and ent.definition != null and not _is_player and not ent.definition.playable \
			and ent.definition.kind != 0 and not ent.definition.display_name.is_empty():
		return ent.definition.display_name
	return "Player %d" % entity_id


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	_given_name = "" if new == null else String(new.get(&"name")).strip_edges()
	_online = new != null and bool(new.get(&"online"))
	_is_player = new != null
	_refresh()


func _refresh() -> void:
	if _label == null:
		return   # the local player, whose Nameplate node the entity dropped
	var shown: String = _given_name if not _given_name.is_empty() else _fallback_name()
	if shown == _label.text:
		return
	_label.text = shown
	# Printed because a nameplate is otherwise only verifiable by looking at a screen, and the
	# thing worth verifying is that ANOTHER client's name arrived — which needs two processes.
	print("[Nameplate] nameplate: %d = %s" % [entity_id, shown])


## Show `text` under the name, in `color` (its status: "Downed"); "" for none.
func set_tag(text: String, color: Color) -> void:
	_tag_text = text
	_tag_color = color
	if _holder == null:
		return   # the local player has no nameplate; its HUD says its status
	if _tag == null and not text.is_empty():
		_tag = Label3D.new()
		_tag.name = "Tag"
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.font_size = int(font_size * 0.75)
		_tag.outline_size = font_size / 8
		_tag.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		_tag.pixel_size = text_scale
		_tag.position = Vector3(0.0, height - 0.22, 0.0)
		_tag.visibility_range_end = max_distance_m
		_holder.add_child(_tag)
	if _tag != null:
		_tag.text = text
		_tag.modulate = Color(color, 0.95)
		_tag.visible = not text.is_empty()


## The tag being shown ("" for none). For tests.
func shown_tag() -> String:
	return _tag_text


## What the nameplate is showing. For tests and the debug overlay.
func shown_name() -> String:
	return _label.text if _label != null else ""


## Whether the person behind this entity is connected right now. A player who leaves keeps their
## entity (and their round's score), so a scoreboard needs this to tell them from someone here.
func is_online() -> bool:
	return _online


## Whether this entity is a player's (it has a `player` row), online or not, whatever character it
## plays: not the kind, which a game may give its players (DECISIONS #217).
func is_player() -> bool:
	return _is_player


## What to call this entity anywhere else — a scoreboard, a kill feed. The same answer the label
## gives, but also for the LOCAL player, whose label the entity drops: the component still
## receives its `player` row, it just has nowhere to draw it.
func display_name() -> String:
	return _given_name if not _given_name.is_empty() else _fallback_name()
