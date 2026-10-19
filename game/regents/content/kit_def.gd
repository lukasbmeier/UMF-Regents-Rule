@tool
class_name KitDef extends ContentDef
## A WEAPON KIT (owner, 2026-10-19: the weapon is the kit): what a weapon of this kind fights with. A
## weapon names its kit (`ItemDef.weapon_kit`); wielding it gives its LIGHT combo (tap the left mouse
## button: each tap the next in `light`, inside `combo_window_ms` of the last), its HEAVY (hold the left
## button), and its SKILLS on Q, E, R and F, each unlocked at its mastery rank in `skill`
## (`skill_ranks`: 1, 3, 6, 9). Block (hold the right button) and the dodge roll (Ctrl) are everyone's.
## The server refuses an ability the wielded weapon's kit does not give, or a rank does not unlock
## (`game/regents.rs`, `may_use_ability`), and scales its damage by the weapon and the mastery.

## Its key, as a weapon names it: "sword", "axe", "bow".
@export var key: StringName = &""
## The mastery it trains (XP for every hit) and whose rank unlocks its skills.
@export var skill: SkillDef
## The light combo, in order (the first after a pause).
@export var light: Array[AbilityDef] = []
## Held left button: the heavy.
@export var heavy: AbilityDef
## Q, E, R, F, in that order.
@export var skills: Array[AbilityDef] = []
## The mastery rank each skill unlocks at, one per skill.
@export var skill_ranks: PackedInt32Array = PackedInt32Array([1, 3, 6, 9])
## A tap this soon after the last light hit is the next in the combo; later, the combo starts over.
@export_range(200, 3000, 10, "suffix:ms") var combo_window_ms: int = 900
## How long the left button must be held for the heavy rather than a light.
@export_range(150, 1500, 10, "suffix:ms") var heavy_hold_ms: int = 350

static var _all: Array[KitDef] = []


func content_type() -> StringName:
	return &"kit"


func why_no_workbench() -> String:
	return "a list of abilities: each is tried on the training dummy in the frontier camp (a combat bench comes with the fight's tuning)"


func summary() -> String:
	return "%s: %d light, %s heavy, %d skills" % [key, light.size(), "a" if heavy != null else "no", skills.size()]


## The key slot `slot` (0 Q, 1 E, 2 R, 3 F) unlocks at (99: never).
func rank_for(slot: int) -> int:
	return skill_ranks[slot] if slot >= 0 and slot < skill_ranks.size() else 99


func to_bake() -> Dictionary:
	var lights: Array = []
	for a: AbilityDef in light:
		lights.append(ContentDef.ref(a))
	var sk: Array = []
	for i: int in skills.size():
		sk.append([ContentDef.ref(skills[i]), rank_for(i)])
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"skill": ContentDef.ref(skill),
		"light": lights,
		"heavy": ContentDef.ref(heavy) if heavy != null else 0,
		"skills": sk,
		"combo_window_ms": combo_window_ms,
	}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (sword, axe, bow): weapons name it")
	if skill == null:
		out.append("it trains no mastery: set `skill`")
	if light.is_empty() or light.has(null):
		out.append("it has no light combo (or an empty slot): set `light`")
	if skills.has(null):
		out.append("its skills have an empty slot")
	if skills.size() > 4:
		out.append("four skills at most (Q, E, R, F)")
	if skill_ranks.size() < skills.size():
		out.append("`skill_ranks` needs a rank per skill (%d skills, %d ranks)" % [skills.size(), skill_ranks.size()])
	return out


## The kit a weapon of key `kit_key` fights with, or null.
static func by_key(kit_key: StringName) -> KitDef:
	for k: KitDef in all():
		if k.key == kit_key:
			return k
	return null


static func all() -> Array[KitDef]:
	if Engine.is_editor_hint() or _all.is_empty():
		var out: Array[KitDef] = []
		for d: ContentDef in ContentLibrary.items(&"kit"):
			var k: KitDef = d as KitDef
			if k != null:
				out.append(k)
		out.sort_custom(func(a: KitDef, b: KitDef) -> bool: return a.id < b.id)
		if Engine.is_editor_hint():
			return out
		_all = out
	return _all
