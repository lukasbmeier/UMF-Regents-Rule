@tool
class_name ResourceDef extends ContentDef
## A RESOURCE (DECISIONS #270): a pool an entity spends to act (mana, stamina, focus) that fills again by
## itself, slower in a fight than out of one. An entity has a pool only when the game gives it one (a
## genre's `module::ensure_resource`: Regent's Rule's staff gives mana); the server spends it
## (`spend_resource`) and refuses what it cannot pay.
##
## Nothing ticks: a pool's row keeps what it held after its last spend and when; what it holds now is
## worked out from that by `level` (the server's `resource::level`, its twin), on the server and on every
## client alike, so the bar fills smoothly without a row a second.

## Its name in code and on the HUD ("mana").
@export var key: StringName = &""
## The most it holds.
@export_range(1.0, 100000.0, 1.0) var max_amount: float = 100.0
## What it fills by out of a fight, a second.
@export_range(0.0, 10000.0, 0.1, "suffix:/s") var regen_out_per_s: float = 10.0
## What it fills by in a fight, a second.
@export_range(0.0, 10000.0, 0.1, "suffix:/s") var regen_in_per_s: float = 4.0
## "In a fight": this long after the last spend.
@export_range(0.0, 600.0, 0.1, "suffix:s") var combat_s: float = 5.0
## Its bar's colour.
@export var color: Color = Color(0.35, 0.55, 1.0)


func content_type() -> StringName:
	return &"resource"


func why_no_workbench() -> String:
	return "a pool and two rates: its summary says how long it takes to fill, in a fight and out of one"


func summary() -> String:
	var fill: Callable = func(rate: float) -> String: return "never" if rate <= 0.0 else "%d s" % roundi(max_amount / rate)
	return "%s: %d, empty to full in %s out of a fight, %s in one" % [key, roundi(max_amount), fill.call(regen_out_per_s), fill.call(regen_in_per_s)]


func to_bake() -> Dictionary:
	return {"id": id, "name": display_name, "key": String(key), "max": max_amount, "regen_out": regen_out_per_s,
		"regen_in": regen_in_per_s, "combat_s": combat_s}


func validate() -> Array[String]:
	var out: Array[String] = super()
	if key == &"":
		out.append("it has no key (\"mana\")")
	return out


## WHAT A POOL HOLDS `since_s` seconds after it last held `stored`: the first `combat_s` of them at the
## in-a-fight rate, the rest at the other, never past `max_amount`. Twin: `server/src/resource.rs`.
static func level(stored: float, max_amount_: float, since_s: float, regen_in: float, regen_out: float, combat: float) -> float:
	var t: float = maxf(since_s, 0.0)
	var fighting: float = minf(t, combat)
	return minf(max_amount_, stored + regen_in * fighting + regen_out * maxf(t - combat, 0.0))


## This pool's level after `since_s` from `stored`.
func level_after(stored: float, since_s: float) -> float:
	return level(stored, max_amount, since_s, regen_in_per_s, regen_out_per_s, combat_s)


static var _by_id: Dictionary[int, ResourceDef] = {}


## The resource with content id `resource_id`, or null.
static func by_id(resource_id: int) -> ResourceDef:
	if _by_id.is_empty() or Engine.is_editor_hint():
		for f: Dictionary in ContentLibrary.files():
			if not String(f["path"]).begins_with(ContentLibrary.folder_for(&"resource", String(f["owner"])) + "/"):
				continue
			var d: ResourceDef = load(String(f["path"])) as ResourceDef
			if d != null:
				_by_id[d.id] = d
	return _by_id.get(resource_id, null)
