@tool
class_name KitDef extends ContentDef
## A WEAPON KIT (owner, 2026-10-19: the weapon is the kit): what a weapon of this kind fights with. A
## weapon names its kit (`ItemDef.weapon_kit`); wielding it gives its STRING (tap the left mouse button:
## each tap the next in `light`, inside `regents.combo_window_ms` of the last), whose LAST step is the
## FINISHER (COMBAT_OVERHAUL.md §3, 2026-10-31: the heavy merged into it: armor, it flinches a light it
## hits, it staggers), and its SKILLS on Q, E, R and F, each unlocked at its mastery rank in `skill`
## (`skill_ranks`: 1, 3, 6, 9). The guard (the right button: a tap parries, held it blocks) and the dodge
## roll (Ctrl) are everyone's.
## The server refuses an ability the wielded weapon's kit does not give, or a rank does not unlock
## (`game/regents.rs`, `may_use_ability`), and scales its damage by the weapon and the mastery.

## Its key, as a weapon names it: "sword", "axe", "bow".
@export var key: StringName = &""
## The mastery it trains (XP for every hit) and whose rank unlocks its skills.
@export var skill: SkillDef
## The string, in order (the first after a pause, or a riposte); its last is the finisher.
@export var light: Array[AbilityDef] = []
## Q, E, R, F, in that order.
@export var skills: Array[AbilityDef] = []
## The mastery rank each skill unlocks at, one per skill.
@export var skill_ranks: PackedInt32Array = PackedInt32Array([1, 3, 6, 9])
## UNBLOCKABLE (COMBAT_OVERHAUL.md §2, 2026-10-31): of this kit's abilities, those no block or parry stops
## (roll, or step out of the sweep). Each glints red on its user as its wind-up starts. A foe's finisher.
@export var unblockable: Array[AbilityDef] = []
## A DRAWN KIT (a bow, owner 2026-10-20): the left button held DRAWS (the walk slowed) and let go LOOSES its
## ammo (`ItemDef.ammo_for` = this kit's key), its damage, speed and range growing with the draw to full at
## `draw_full_ms`; the right button lets the draw go. `light` is the shot (its damage, its clip). Off: a
## melee kit (tap, hold, combo).
@export var draws: bool = false
@export_range(100, 5000, 10, "suffix:ms") var draw_full_ms: int = 800
## A CASTING KIT (the Staff, owner 2026-10-20): its abilities are SPELLS (`SpellDef`: the left button its
## first light, Q-F its skills), paid from this pool (mana; DECISIONS #270), which wielding it gives you.
## Empty: a kit paced by cooldowns alone (melee, the bow).
@export var resource: ResourceDef
@export_group("Timing")
## THE SWING'S TIMING IS ITS ANIMATION'S (owner, 2026-10-19: "the attack synced to the animation"): a
## swing locks its fighter for its clip's length in this set (`ability.<id>`, at its speed), never less
## than its wind-up and `MIN_RECOVERY_MS`; the server holds the same lock (baked). Change a clip's speed
## in the set and the swing's lock follows.
@export var timing_set: AnimationSet = preload("res://game/regents/anim/adventurer.tres")
## THE FOLLOW-THROUGH (COMBAT_OVERHAUL.md §3: Luke's #8, the sword's second swing cut off): after each step
## lands (its wind-up), this long before the next step may start, so the arc finishes. One per step of
## `light`, in order; a step with none takes `DEFAULT_FOLLOW_MS`. Never past the step's lock.
@export var follow_ms: PackedInt32Array = PackedInt32Array()
@export_group("Roles")
## THE ROLE MAP (COMBAT_OVERHAUL.md §5, Luke 2026-11-01): per role (the handle's shape, `RoleDef`), the
## string's last hit and what it does. The plain role's last hit is `light`'s last. Empty: a kit with no
## roles yet (every weapon of it the plain role).
@export var roles: Array[KitRole] = []

## The shortest recovery a swing has after it lands, whatever its clip.
const MIN_RECOVERY_MS: int = 100
## A step's follow-through when `follow_ms` gives it none.
const DEFAULT_FOLLOW_MS: int = 200

static var _all: Array[KitDef] = []


func content_type() -> StringName:
	return &"kit"


func why_no_workbench() -> String:
	return "a list of abilities: each is tried on the training dummy in the frontier camp (a combat bench comes with the fight's tuning)"


func summary() -> String:
	return "%s: a string of %d, %d skills" % [key, light.size(), skills.size()]


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


## How long after step `step` lands the next step may start (its follow-through).
func follow_for(step: int) -> int:
	return follow_ms[step] if step >= 0 and step < follow_ms.size() else DEFAULT_FOLLOW_MS


## Whether `a` is this kit's FINISHER: its string's last step (armor, flinches a light, staggers), any role's.
func is_finisher(a: AbilityDef) -> bool:
	if a == null or light.is_empty():
		return false
	if light[light.size() - 1] == a:
		return true
	for kr: KitRole in roles:
		if kr != null and kr.finisher == a:
			return true
	return false


## The role map's entry for `role` (null for a role it has none for: then the plain one's last hit).
func role_entry(role: RoleDef) -> KitRole:
	for kr: KitRole in roles:
		if kr != null and role != null and kr.role == role:
			return kr
	return null


## THE STRING'S LAST HIT for a weapon of `role`: the role map's, else `light`'s last.
func finisher_for(role: RoleDef) -> AbilityDef:
	var kr: KitRole = role_entry(role)
	if kr != null and kr.finisher != null:
		return kr.finisher
	return light[light.size() - 1] if not light.is_empty() else null


## Step `step` of the string for a weapon of `role` (its last step is the role's last hit).
func light_at(step: int, role: RoleDef) -> AbilityDef:
	if step < 0 or step >= light.size():
		return null
	return finisher_for(role) if step == light.size() - 1 else light[step]


## The string for a weapon of `role`, in order.
func string_for(role: RoleDef) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	for i: int in light.size():
		out.append(light_at(i, role))
	return out


## Whether this kit has roles (a role map).
func has_roles() -> bool:
	return not roles.is_empty()


## Whether it casts (the Staff): its abilities are spells, paid from `resource`.
func casts() -> bool:
	return resource != null


## Every ability of the kit: the string, every role's last hit, the skills.
func abilities() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	out.assign(light)
	for kr: KitRole in roles:
		if kr != null and kr.finisher != null and not out.has(kr.finisher):
			out.append(kr.finisher)
	out.append_array(skills)
	return out


## The key slot `slot` (0 Q, 1 E, 2 R, 3 F) unlocks at (99: never).
func rank_for(slot: int) -> int:
	return skill_ranks[slot] if slot >= 0 and slot < skill_ranks.size() else 99


func to_bake() -> Dictionary:
	var lights: Array = []
	var follows: Array = []
	for i: int in light.size():
		lights.append(ContentDef.ref(light[i]))
		follows.append(follow_for(i))
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
		"follow_ms": follows,
		"skills": sk,
		"draw_full_ms": draw_full_ms if draws else 0,
		"resource": ContentDef.ref(resource) if resource != null else 0,
		"locks": locks,
		"unblockable": unblockable.map(func(a: AbilityDef) -> int: return ContentDef.ref(a)),
		"roles": roles.map(func(kr: KitRole) -> Dictionary: return kr.to_bake() if kr != null else {}),
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
	if resource != null:
		for a: AbilityDef in light + skills:
			if a != null and SpellDef.by_ability(a.id) == null:
				out.append("%s is a casting kit's but no spell's (a SpellDef with it as its ability)" % a.display_name)
	if follow_ms.size() > light.size():
		out.append("`follow_ms` has %d entries for a string of %d" % [follow_ms.size(), light.size()])
	for f: int in follow_ms:
		if f < 0:
			out.append("a follow-through below 0 ms")
	if skill_ranks.size() < skills.size():
		out.append("`skill_ranks` needs a rank per skill (%d skills, %d ranks)" % [skills.size(), skill_ranks.size()])
	for a: AbilityDef in unblockable:
		if a == null or not abilities().has(a):
			out.append("`unblockable` lists %s, which is not this kit's" % (a.display_name if a != null else "an empty slot"))
	out.append_array(_validate_roles())
	return out


## The role map's rules: each entry a role and a last hit; a role once; the plain role there, its last hit
## `light`'s last; no other role's last hit a step or a skill; its words never a role's name.
func _validate_roles() -> Array[String]:
	var out: Array[String] = []
	if roles.is_empty():
		return out
	var seen: Array[RoleDef] = []
	var has_plain: bool = false
	for kr: KitRole in roles:
		if kr == null or kr.role == null or kr.finisher == null:
			out.append("a role map entry needs its role and its last hit")
			continue
		if seen.has(kr.role):
			out.append("the role map has %s twice" % kr.role.display_name)
		seen.append(kr.role)
		if kr.role.plain:
			has_plain = true
			if light.is_empty() or kr.finisher != light[light.size() - 1]:
				out.append("the plain role's last hit must be the string's last (%s)" % (light[light.size() - 1].display_name if not light.is_empty() else "none"))
		elif light.has(kr.finisher) or skills.has(kr.finisher):
			out.append("%s's last hit, %s, is a step or a skill already" % [kr.role.display_name, kr.finisher.display_name])
		if kr.does.strip_edges().is_empty():
			out.append("%s's entry says nothing of what the handle does: set `does`" % kr.role.display_name)
		for w: String in ["tank", "damage", "support", "finisher"]:
			if kr.does.to_lower().contains(w):
				out.append("%s's `does` names a role (\"%s\"): show what it does, never its name" % [kr.role.display_name, w])
	if not has_plain:
		out.append("the role map has no plain role (a weapon whose handle names none)")
	return out


## Whether ability `ability_id` is one no block or parry stops (any kit's `unblockable`).
static func is_unblockable(ability_id: int) -> bool:
	for k: KitDef in all():
		for a: AbilityDef in k.unblockable:
			if a != null and a.id == ability_id:
				return true
	return false


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
