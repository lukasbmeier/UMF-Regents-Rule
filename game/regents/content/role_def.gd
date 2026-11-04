@tool
class_name RoleDef extends ContentDef
## A ROLE (COMBAT_OVERHAUL.md §5, Luke 2026-11-01): what a weapon is FOR, set by the SHAPE of its handle (a
## sword's plain grip, crossguard hilt or banner hilt; `PatternDef.role`), never by a slot or a menu. Its
## MATERIAL still gives the trait. What every weapon of a role SHARES is here: its held guard and its threat;
## what it does with each weapon (the string's last hit) is that kit's (`KitDef.roles`).
##
## SHOW, DON'T NAME (Luke, 2026-11-01): a role's name is for code and docs. The player sees its BADGE and
## what the handle does (`guard_words`, the kit's `KitRole.does`); never "Tank", "Damage" or "Support".

enum Badge {
	## A blade's point (a diamond).
	POINT,
	## A shield (a square standing on a rounded foot).
	SHIELD,
	## A banner's cross.
	CROSS,
}

## Its key, for code ("damage", "tank", "support").
@export var key: StringName = &""
## THE PLAIN ROLE: a weapon whose handle names no role is this one (the plain handle, an old item). One role.
@export var plain: bool = false
@export_group("What it carries")
## THE FULL GUARD: a held block takes `regents.block_damage_pct` of a hit in front; else the light one,
## `regents.weak_block_pct`.
@export var full_block: bool = false
## THREAT (stored for step 6, threat targeting; nothing targets by it yet): its damage, and its healing,
## count this much toward a foe's choice. Healing never counts for more than damage (Luke, 2026-11-01).
@export_range(0, 1000, 5, "suffix:%") var threat_pct: int = 100
## A hot rule (`regents.<name>`) that sets `threat_pct` live instead; empty: `threat_pct` as it is.
@export var threat_rule: StringName = &""
## A hot flag (`regents.<name>`): on, its threat counts against bosses only, and others count it as the
## plain role's. Empty: every foe (Luke, 2026-11-01: "maybe bosses only; test it").
@export var threat_scope_rule: StringName = &""
## A hot rule (`regents.<name>`): its weight when a dropped weapon rolls its handle's shape (Luke: 50 % plain,
## 25 / 25). Empty: never rolled.
@export var drop_rule: StringName = &""
@export_group("How it shows")
## Its badge (craft window, bag, tooltip): a shape and a colour, never a word.
@export var badge: Badge = Badge.POINT
@export var badge_color: Color = Color(0.9, 0.75, 0.4)
## What its held guard does, in the player's words ("stops most of a blow in front").
@export var guard_words: String = ""

static var _all: Array[RoleDef] = []


func content_type() -> StringName:
	return &"role"


func why_no_workbench() -> String:
	return "a few numbers and a badge: tried at the camp's dummies and skeletons with a weapon of its handle, and live on the Rules page"


func summary() -> String:
	return "%s: %s guard, threat %s" % [key, "full" if full_block else "light", threat_rule if threat_rule != &"" else "%d%%" % threat_pct]


func to_bake() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"key": String(key),
		"plain": plain,
		"full_block": full_block,
		"threat_pct": threat_pct,
		"threat_rule": _rule_key(threat_rule),
		"threat_scope_rule": _rule_key(threat_scope_rule),
		"drop_rule": _rule_key(drop_rule),
	}


## "regents.<name>" for a rule's name ("" for none).
static func _rule_key(n: StringName) -> String:
	return "" if n == &"" else (String(n) if String(n).contains(".") else "regents.%s" % n)


## Its threat now, in percent (`threat_rule` when it names one).
func threat_now() -> float:
	return HotRules.number(StringName(_rule_key(threat_rule))) if threat_rule != &"" else float(threat_pct)


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (\"damage\", \"tank\", \"support\")")
	if guard_words.strip_edges().is_empty():
		out.append("it says nothing of its guard: set `guard_words` (the player's words, no role name)")
	for n: StringName in [threat_rule, threat_scope_rule, drop_rule]:
		if n != &"" and not _rule_declared(_rule_key(n)):
			out.append("it names the rule %s, which no rule set declares" % _rule_key(n))
	for w: String in ["tank", "damage", "support", "finisher"]:
		if guard_words.to_lower().contains(w):
			out.append("its `guard_words` name a role (\"%s\"): show what it does, never its name" % w)
	return out


func validate_with(all_of_type: Array[ContentDef]) -> Array[String]:
	var out: Array[String] = []
	var plains: int = 0
	for d: ContentDef in all_of_type:
		var r: RoleDef = d as RoleDef
		if r == null:
			continue
		plains += 1 if r.plain else 0
		if r.id != id and r.key == key:
			out.append("its key \"%s\" is %s's too" % [key, r.display_name])
	if plain and plains != 1:
		out.append("%d roles are the plain one: one is" % plains)
	return out


## Whether a rule set declares `rule_key` ("regents.x").
static func _rule_declared(rule_key: String) -> bool:
	return RuleSetDef.effective().has(rule_key)


## The role with content id `role_id`, or null.
static func by_id(role_id: int) -> RoleDef:
	for r: RoleDef in all():
		if r.id == role_id:
			return r
	return null


## THE PLAIN ROLE: a weapon's whose handle names none.
static func plain_role() -> RoleDef:
	for r: RoleDef in all():
		if r.plain:
			return r
	return null


static func all() -> Array[RoleDef]:
	if Engine.is_editor_hint() or _all.is_empty():
		var out: Array[RoleDef] = []
		for d: ContentDef in RegentsContent.items(&"role"):
			var r: RoleDef = d as RoleDef
			if r != null:
				out.append(r)
		out.sort_custom(func(a: RoleDef, b: RoleDef) -> bool: return a.id < b.id)
		if Engine.is_editor_hint():
			return out
		_all = out
	return _all
