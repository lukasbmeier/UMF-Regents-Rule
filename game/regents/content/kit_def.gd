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
@export_group("Timing")
## THE SWING'S TIMING IS ITS ANIMATION'S (owner, 2026-10-19: "the attack synced to the animation"): a
## swing locks its fighter for its clip's length in this set (`ability.<id>`, at its speed), never less
## than its wind-up and `MIN_RECOVERY_MS`; the server holds the same lock (baked). Change a clip's speed
## in the set and the swing's lock follows.
@export var timing_set: AnimationSet = preload("res://game/regents/anim/adventurer.tres")
## After a light swing lands (its wind-up), this long before the next step of the combo may start: the
## recovery a combo cancels into the next swing.
@export_range(0, 1000, 10, "suffix:ms") var chain_ms: int = 60

## The shortest recovery a swing has after it lands, whatever its clip.
const MIN_RECOVERY_MS: int = 100

static var _all: Array[KitDef] = []


func content_type() -> StringName:
	return &"kit"


func why_no_workbench() -> String:
	return "a list of abilities: each is tried on the training dummy in the frontier camp (a combat bench comes with the fight's tuning)"


func summary() -> String:
	return "%s: %d light, %s heavy, %d skills" % [key, light.size(), "a" if heavy != null else "no", skills.size()]


## How long ability `a` locks its fighter: its clip's length in `timing_set`, at least its wind-up and the
## least recovery.
func lock_ms(a: AbilityDef) -> int:
	if a == null:
		return 0
	var sem: StringName = StringName("ability.%d" % a.id)
	var clip_ms: int = 0
	if timing_set != null and timing_set.has_exact(sem):
		var ref: AnimationClipRef = timing_set.clip(sem)
		var speed: float = ref.speed_scale if ref.speed_scale > 0.0 else 1.0
		clip_ms = roundi(AnimationTreeBuilder.clip_length(timing_set, sem) / speed * 1000.0)
	return maxi(clip_ms, a.wind_up_ms + MIN_RECOVERY_MS)


## Every ability of the kit: the combo, the heavy, the skills.
func abilities() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	out.assign(light)
	if heavy != null:
		out.append(heavy)
	out.append_array(skills)
	return out


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
	var locks: Array = []
	for a: AbilityDef in abilities():
		locks.append([ContentDef.ref(a), lock_ms(a)])
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"skill": ContentDef.ref(skill),
		"light": lights,
		"heavy": ContentDef.ref(heavy) if heavy != null else 0,
		"skills": sk,
		"combo_window_ms": combo_window_ms,
		"chain_ms": chain_ms,
		"locks": locks,
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
	for a: AbilityDef in abilities():
		if a != null and timing_set != null and not timing_set.has_exact(StringName("ability.%d" % a.id)):
			out.append("%s has no clip in its timing set (ability.%d): it would play Interact and lock only its wind-up" % [a.display_name, a.id])
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
		for d: ContentDef in RegentsContent.items(&"kit"):
			var k: KitDef = d as KitDef
			if k != null:
				out.append(k)
		out.sort_custom(func(a: KitDef, b: KitDef) -> bool: return a.id < b.id)
		if Engine.is_editor_hint():
			return out
		_all = out
	return _all
