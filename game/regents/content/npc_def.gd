@tool
class_name NpcDef extends ContentDef
## A FRIENDLY NPC & LORE CHARACTER (WB9, `docs/regents_rule/WORLD_BUILDER_PREP.md` §8.2): a named person placed on a
## level's `npc` (or `guide`) points, dressed in any of the five outfits (including the NPC-only `Noble` and the
## `Knight` tabard torso, `GAME.md` W1), with their own dye palette, held prop, lore codex notes, and branching
## `.dialogue` script (`CinemaDialogue`). Edited and tested live in the World Builder (`world_builder.tscn`, F6).

const OUTFITS: PackedStringArray = ["Peasant", "Ranger", "Wizard", "Knight", "Noble"]
const BODIES: PackedStringArray = ["male", "female"]
const HAIR_MODELS: PackedStringArray = [
	"",
	"res://game/characters/quaternius/models/Hair_SimpleParted.gltf",
	"res://game/characters/quaternius/models/Hair_Long.gltf",
	"res://game/characters/quaternius/models/Hair_Buns.gltf",
	"res://game/characters/quaternius/models/Hair_Buzzed.gltf",
]
const BEARD_MODELS: PackedStringArray = [
	"",
	"res://game/characters/quaternius/models/Hair_Beard.gltf",
	"res://game/characters/quaternius/models/Hair_Moustache.gltf",
	"res://game/characters/quaternius/models/Hair_MuttonChops.gltf",
]

## The key a `LevelPoint` of kind `"npc"` puts in `tags[0]` (e.g. `"chronicler"`, `"blacksmith_hal"`).
@export var key: StringName = &""
## Their role or title shown under their name (e.g. `"Keeper of the Writ"`, `"Camp Drillmaster"`).
@export var title: String = ""

@export_group("Appearance & Wardrobe")
## Body frame (`"male"` or `"female"`).
@export_enum("male", "female") var body: String = "male"
## Outfit family (`Noble` and the `Knight` tabard are reserved for NPCs, `GAME.md` W1).
@export_enum("Peasant", "Ranger", "Wizard", "Knight", "Noble") var outfit: String = "Peasant"
## On a `Knight` NPC: wear the cloth tabard torso (`Body_Cloth`) instead of plate (`Body_Armor`).
@export var knight_tabard: bool = false
## Include the outfit's headwear, pauldrons, and neck accessory.
@export var wear_extras: bool = true
## Optional dye palette applied via `Wardrobe.dress` (null keeps the outfit's painted colors).
@export var palette: DyePalette = null
## Hair style index (0 = none, 1..4 = hair meshes).
@export_range(0, 4) var hair_style: int = 1
## Beard style index (0 = none, 1..3 = beard meshes).
@export_range(0, 3) var beard_style: int = 0
## Skin tone (0 = light, 1 = dark).
@export_range(0, 1) var skin_tone: int = 0
@export var skin_tint: Color = Color.WHITE
@export var hair_color: Color = Color(0.24, 0.16, 0.08)
## Optional held weapon or prop scene (`HeldItem`, e.g. `iron_sword.tscn`, `yew_staff.tscn`, `hammer.tscn`).
@export var held_scene: PackedScene = null
## Idle pose key in the animation set.
@export var idle_pose: StringName = &"locomotion.idle"

@export_group("World & Behavior")
## How far they wander around their `LevelPoint` at rest (`0` = stands at their post).
@export_range(0.0, 20.0, 0.5, "suffix:m") var wander_m: float = 0.0
## Interaction radius in meters (`E` to talk).
@export_range(1.0, 8.0, 0.25, "suffix:m") var interact_m: float = 2.8
## Whether this NPC's point also shows as a named Point of Interest on the `M` World Map (WB11).
@export var map_poi: bool = false

@export_group("Lore & Dialogue")
## World-building lore / codex background for this NPC and their settlement or faction.
@export_multiline var lore_entry: String = ""
## Branching dialogue script in `CinemaDialogue` format (`~ start`, speaker lines, `- Choice [if flag]`, `=> section`).
@export_multiline var dialogue_script: String = ""

static var _all: Array[NpcDef] = []
static var _by_key: Dictionary[StringName, NpcDef] = {}
## Unsaved in-memory drafts created in the World Builder NPC Studio before clicking `Save NPC (.tres)`.
static var _drafts: Dictionary[StringName, NpcDef] = {}


func content_type() -> StringName:
	return &"npc"


func why_no_workbench() -> String:
	return "dressed, placed and its dialogue tested in the world builder (game/regents/builder/world_builder.tscn)"


func summary() -> String:
	var role: String = " (%s)" % title if not title.is_empty() else ""
	return "%s%s: %s %s" % [display_name, role, body, outfit]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"title": title,
		"body": body,
		"outfit": outfit,
		"knight_tabard": knight_tabard,
		"wander_m": wander_m,
		"interact_m": interact_m,
		"map_poi": map_poi,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key: a level's `npc` points name their NPC by `key`")
	if not BODIES.has(body):
		out.append("body '%s' must be 'male' or 'female'" % body)
	if not OUTFITS.has(outfit):
		out.append("outfit '%s' is not one of %s" % [outfit, str(OUTFITS)])
	if not dialogue_script.strip_edges().is_empty():
		out.append_array(validate_dialogue(dialogue_script))
	return out


func validate_with(others: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	for o: ContentDef in others:
		var other: NpcDef = o as NpcDef
		if other != null and other != self and other.key == key and key != &"":
			out.append("another NPC (%s, %d) already uses key '%s'" % [other.display_name, other.id, key])
	return out


## Checks a `CinemaDialogue` script for structural errors: must have a `~ start` section and every `=> target` jump
## must exist or be `END`.
static func validate_dialogue(source: String) -> Array[String]:
	var errs: Array[String] = []
	var sections: Dictionary = CinemaDialogue.parse(source)
	if sections.is_empty():
		errs.append("dialogue_script has no `~ section` headers (needs at least `~ start`)")
		return errs
	if not sections.has("start"):
		errs.append("dialogue_script has no `~ start` section")
	for sec_name: Variant in sections.keys():
		var steps: Array = sections[sec_name] as Array
		_check_jumps(steps, sections, String(sec_name), errs)
	return errs


static func _check_jumps(steps: Array, sections: Dictionary, sec_name: String, errs: Array[String]) -> void:
	for s_v: Variant in steps:
		var step: Dictionary = s_v as Dictionary
		var kind: String = String(step.get("kind", ""))
		if kind == "jump":
			var target: String = String(step.get("target", ""))
			if target != "END" and not sections.has(target):
				errs.append("dialogue section '%s' jumps to '=> %s', which does not exist" % [sec_name, target])
		elif kind == "choices":
			for item_v: Variant in (step.get("items", []) as Array):
				var item: Dictionary = item_v as Dictionary
				_check_jumps(item.get("body", []) as Array, sections, sec_name, errs)


## Builds the outfit piece map (`slot -> path`) for this NPC's body and outfit, honoring `knight_tabard` and `wear_extras`.
func outfit_pieces() -> Dictionary[StringName, String]:
	var b: StringName = StringName(body)
	var chosen: Dictionary[StringName, String] = Wardrobe.full_set(outfit, b, wear_extras)
	if outfit == "Knight" and knight_tabard:
		var prefix: String = "Female" if b == &"female" else "Male"
		var cloth_path: String = "res://game/regents/art/outfits/knight/models/%s_Knight_Body_Cloth.gltf" % prefix
		if ResourceLoader.exists(cloth_path):
			chosen[&"torso"] = cloth_path
	return chosen


## Builds and dresses a 3D preview `ModularCharacter` node for this NPC (with optional held prop attached).
func build_figure() -> ModularCharacter:
	var hairs: Array[String] = []
	if hair_style > 0 and hair_style < HAIR_MODELS.size() and not HAIR_MODELS[hair_style].is_empty():
		hairs.append(HAIR_MODELS[hair_style])
	if beard_style > 0 and beard_style < BEARD_MODELS.size() and not BEARD_MODELS[beard_style].is_empty():
		hairs.append(BEARD_MODELS[beard_style])
	var look: Dictionary = {
		"body": StringName(body),
		"pieces": outfit_pieces(),
		"skin": skin_tone,
		"skin_tint": skin_tint,
		"hair": hairs,
		"hair_color": hair_color,
	}
	var fig: ModularCharacter = Wardrobe.figure(look)
	fig.name = "NpcFigure_%s" % String(key)
	fig.assembled.connect(func() -> void:
		if palette != null:
			Wardrobe.dress(fig, palette)
		if held_scene != null and fig.skeleton() != null:
			HeldItem.attach(fig.skeleton(), held_scene))
	return fig


## Register an unsaved or live-edited `NpcDef` in memory so the World Builder palette, ghost preview, and
## placed `LevelPoint`s immediately see it before saving to `.tres`.
static func register_draft(npc: NpcDef) -> void:
	if npc == null or npc.key == &"":
		return
	_drafts[npc.key] = npc
	_all.clear()
	_by_key.clear()


static func unregister_draft(npc_key: StringName) -> void:
	if _drafts.erase(npc_key):
		_all.clear()
		_by_key.clear()


static func clear_drafts() -> void:
	_drafts.clear()
	_all.clear()
	_by_key.clear()


static func by_key(npc_key: StringName) -> NpcDef:
	if Engine.is_editor_hint() or _by_key.is_empty():
		var map: Dictionary[StringName, NpcDef] = {}
		for n: NpcDef in all():
			map[n.key] = n
		if Engine.is_editor_hint():
			return map.get(npc_key, null)
		_by_key = map
	return _by_key.get(npc_key, null)


static func all() -> Array[NpcDef]:
	if Engine.is_editor_hint() or _all.is_empty():
		var by_k: Dictionary[StringName, NpcDef] = {}
		var out: Array[NpcDef] = []
		for d: ContentDef in RegentsContent.items(&"npc"):
			var n: NpcDef = d as NpcDef
			if n != null:
				by_k[n.key] = n
				out.append(n)
		for dk: StringName in _drafts:
			var draft: NpcDef = _drafts[dk]
			if draft != null and not by_k.has(dk):
				out.append(draft)
		if Engine.is_editor_hint():
			return out
		_all = out
	return _all


static func clear_cache() -> void:
	_all.clear()
	_by_key.clear()
