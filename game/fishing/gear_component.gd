class_name GearComponent extends SpaceTimeComponent
## GENRE CODE. What this angler fishes with, and the one way to buy more of it.
##
## Three tracks, and each changes a DIFFERENT thing (DECISIONS #118): the ROD how much lake you can
## reach, the REEL how forgiving the hook-set is, the LINE how heavy a catch it holds before it is
## a deadlift. Names, prices and numbers are `shared/fishing/fishing.json` (`FishingData`), the
## same file the module charges from. The server owns all of it; this component reports what the
## row says and forwards the intent.
##
## NO ROW MEANS TIER 0. A new angler has never bought anything, so `gear` is a table an entity
## legitimately has no row in — which is why it is `optional` as well as required. Without that
## every fisher would sit out its whole bind timeout before coming up (DECISIONS #69).

## The tiers changed: (rod, reel, line).
signal gear_changed(rod: int, reel: int, line: int)
## A purchase the server refused, with its reason. The shop is phase-gated server-side, so a HUD
## that offers a buy at the wrong moment has to be able to say what happened rather than looking
## like it dropped the click (DECISIONS #91).
signal purchase_refused(reason: String)
## A purchase landed. The row follows a moment later; this fires the instant the server says yes.
signal purchase_succeeded(kind: int)

const TABLE: StringName = &"gear"

## Must match `GEAR_ROD`/`GEAR_REEL`/`GEAR_LINE` in `server/src/game/fishing.rs`.
enum Kind { ROD = 0, REEL = 1, LINE = 2 }
const _TRACKS: Array[String] = ["rod", "reel", "line"]

var _tiers: Array[int] = [0, 0, 0]


func required_tables() -> Array[StringName]:
	return [TABLE]


func optional_tables() -> Array[StringName]:
	return [TABLE]


func tier(kind: Kind) -> int:
	return _tiers[int(kind)]


func rod_tier() -> int:
	return _tiers[0]


func reel_tier() -> int:
	return _tiers[1]


func line_tier() -> int:
	return _tiers[2]


## The highest tier a track goes to.
static func max_tier() -> int:
	return FishingData.max_tier()


## What the next tier of `kind` costs, or -1 when it is already maxed. Shown before the player
## clicks; the server charges it and is the only one that may.
func next_cost(kind: Kind) -> int:
	var t: int = tier(kind)
	if t >= max_tier():
		return -1
	return int(FishingData.gear(_TRACKS[int(kind)], t + 1).get("cost", -1))


## The track's name: "Rod", "Reel", "Line".
static func name_of(kind: Kind) -> String:
	return _TRACKS[int(kind)].capitalize()


## What this angler is holding on a track: "Ash Rod".
func item_name(kind: Kind) -> String:
	return str(FishingData.gear(_TRACKS[int(kind)], tier(kind)).get("name", name_of(kind)))


## What the next tier on a track is called, or "" when maxed.
func next_name(kind: Kind) -> String:
	if tier(kind) >= max_tier():
		return ""
	return str(FishingData.gear(_TRACKS[int(kind)], tier(kind) + 1).get("name", ""))


## Ask to buy the next tier. The server checks the phase, the price and the cap; every refusal
## comes back through `purchase_refused` rather than being swallowed.
func request_buy(kind: Kind) -> ReducerRequest:
	var req: ReducerRequest = SpaceTimeSync.call_reducer(&"buy_upgrade", [int(kind)], ["u8"])
	req.settled.connect(func(r: ReducerRequest) -> void:
		if r.is_ok():
			purchase_succeeded.emit(int(kind))
		else:
			purchase_refused.emit(r.error_message.trim_prefix("buy_upgrade: ")
				if not r.error_message.is_empty() else "the shop turned it down"))
	return req


func _on_row_updated(table: StringName, _old: RefCounted, new: RefCounted) -> void:
	if table != TABLE:
		return
	if new == null:
		_tiers = [0, 0, 0]
	else:
		_tiers = [int(new.get(&"rod_tier")), int(new.get(&"reel_tier")), int(new.get(&"line_tier"))]
	gear_changed.emit(_tiers[0], _tiers[1], _tiers[2])
