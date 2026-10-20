@tool
class_name SpellDef extends ContentDef
## A SPELL (owner, 2026-10-20: the Staff, `docs/regents_rule/LOOT_AND_STYLES.md` §4-5): how one of a
## casting kit's abilities RESOLVES. A spell is an ability with a cost (the kit's pool: the Staff's mana)
## and a way it lands; its damage, cooldown and range are its `ability`'s. Four kinds, so a new spell of
## a kind is content, not code:
##
##   BOLT    a missile the world's referee flies (`body`): at your Tab target the server aims it and
##           rolls the hit (the bow's hit chance); with none it flies where you look. What it hits takes
##           its damage, those within `splash_m` `splash_pct` of it, and it may burn (`burn_dps`).
##   AREA    a circle `radius_m` wide where you aim (within its range), landing `delay_ms` later on every
##           foe in it: its damage, and `status` (Slowed) for `status_ms`.
##   BLINK   you, its range along where you look, at once (onto ground you can stand on).
##   CONE    everything within its range and `angle_deg` of where you look: its damage and a push.
##
## CASTING (owner, 2026-10-20): `cast_ms` 0 is instant; a longer cast shows a bar and lands at its end.
## Under 0.8 s you may walk while casting (`cast_while_moving`); a longer one roots you, and moving or
## rolling lets it go. No global cooldown: each spell its own (its ability's `cooldown_ms`).

enum Kind {
	BOLT,
	AREA,
	BLINK,
	CONE,
}

## The ability it is (its damage, cooldown, range, clip `ability.<id>`): one of a kit's.
@export var ability: AbilityDef
@export var kind: Kind = Kind.BOLT
## What it costs of the kit's pool (mana), paid when it lands.
@export_range(0.0, 1000.0, 1.0) var cost: float = 0.0
## How long it takes to cast (0: at once).
@export_range(0, 5000, 10, "suffix:ms") var cast_ms: int = 0
## Whether you may walk while casting it (the owner: casts under 0.8 s may, longer ones root).
@export var cast_while_moving: bool = true
@export_group("Bolt")
## The missile (a body the referee flies).
@export var body: BodyDef
@export_range(1.0, 100.0, 0.5, "suffix:m/s") var speed_mps: float = 30.0
## Those this near what it hits take `splash_pct` of its damage too (0: none).
@export_range(0.0, 20.0, 0.1, "suffix:m") var splash_m: float = 0.0
@export_range(0, 100, 1, "suffix:%") var splash_pct: int = 0
## What it hits burns: this much a second, this long (0: no burn).
@export_range(0.0, 100.0, 0.5, "suffix:/s") var burn_dps: float = 0.0
@export_range(0, 30000, 100, "suffix:ms") var burn_ms: int = 0
@export_group("Area")
@export_range(0.5, 30.0, 0.1, "suffix:m") var radius_m: float = 4.0
@export_range(0, 10000, 50, "suffix:ms") var delay_ms: int = 1000
@export_group("Cone")
@export_range(5.0, 180.0, 1.0, "suffix:°") var angle_deg: float = 45.0
## How hard what it hits is pushed away, m/s.
@export_range(0.0, 40.0, 0.5, "suffix:m/s") var push_mps: float = 0.0
@export_group("On what it hits")
## A status for what it hits (Slowed), this long. Empty: none.
@export var status: StatusDef
@export_range(0, 30000, 100, "suffix:ms") var status_ms: int = 3000

static var _by_ability: Dictionary[int, SpellDef] = {}


func content_type() -> StringName:
	return &"spell"


func why_no_workbench() -> String:
	return "a spell is its ability's numbers and how it lands: cast it with the Staff in the game (the combat playtest casts each)"


func summary() -> String:
	var kinds: PackedStringArray = ["bolt", "area", "blink", "cone"]
	return "%s: %s, %d mana, %s" % [ability.display_name if ability != null else "?", kinds[kind], roundi(cost),
		"instant" if cast_ms == 0 else "%.1f s cast%s" % [float(cast_ms) / 1000.0, "" if cast_while_moving else ", rooted"]]


func to_bake() -> Dictionary:
	return {"id": id, "name": display_name, "ability": ContentDef.ref(ability), "kind": int(kind), "cost": cost,
		"cast_ms": cast_ms, "cast_while_moving": cast_while_moving, "body": ContentDef.ref(body), "speed_mps": speed_mps,
		"splash_m": splash_m, "splash_pct": splash_pct, "burn_dps": burn_dps, "burn_ms": burn_ms, "radius_m": radius_m,
		"delay_ms": delay_ms, "angle_deg": angle_deg, "push_mps": push_mps,
		"status": status.status if status != null else 0, "status_ms": status_ms}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if ability == null:
		out.append("it is no ability's: set `ability`")
	if kind == Kind.BOLT and body == null:
		out.append("a bolt needs its missile: set `body`")
	if splash_pct > 0 and splash_m <= 0.0:
		out.append("it splashes nobody: set `splash_m`")
	if (burn_dps > 0.0) != (burn_ms > 0):
		out.append("a burn needs both how much and how long")
	return out


## The spell that ability `ability_id` is, or null (a swing, a shot).
static func by_ability(ability_id: int) -> SpellDef:
	if _by_ability.is_empty() or Engine.is_editor_hint():
		for d: ContentDef in RegentsContent.items(&"spell"):
			var s: SpellDef = d as SpellDef
			if s != null and s.ability != null:
				_by_ability[s.ability.id] = s
	return _by_ability.get(ability_id, null)
