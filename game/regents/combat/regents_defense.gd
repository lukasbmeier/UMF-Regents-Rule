class_name RegentsDefense extends RefCounted
## ARMOR'S NUMBERS, AS THE SERVER COUNTS THEM (W3): the client's twin of `rules::piece_defense` and `rules::defense_mult`
## (`server/src/genre/regents/mod.rs`) and of `defense_of` (`server/src/game/regents.rs`). Change both together; the
## `regents_bar` suite checks this twin on the case the integration suite pins (a skeleton's 4 through an iron cuirass
## and a steel armet: 3.18). For the bag's words only: the server decides every hit.

## A worn piece's Defense: its item's, its quality (thousandths) adding up to a fifth more, as quality adds to damage.
static func piece(defense: int, quality_pm: int) -> float:
	return float(defense) * (1.0 + float(clampi(quality_pm, 0, 1000)) / 5000.0)


## What a hit keeps through Defense `defense`: K / (K + Defense), K the hot rule `regents.defense_k`. None, or K not above
## 0: all of it.
static func keeps(defense: float, k: float) -> float:
	return 1.0 if defense <= 0.0 or k <= 0.0 else k / (k + defense)


## K, live (`regents.defense_k`).
static func k_now() -> float:
	return HotRules.number(&"regents.defense_k")


## The share of every hit taken away by Defense `defense`, in whole percent (19 for 19 %).
static func less_pct(defense: float, k: float) -> int:
	return roundi((1.0 - keeps(defense, k)) * 100.0)


## The Defense of the bag row `row` as worn in `slot` (0 when it is not that slot's armor, or not in the bag).
static func of_row(inventory: SpaceTimeInventoryComponent, row: int, slot: StringName) -> float:
	if inventory == null or row == 0:
		return 0.0
	for st: SpaceTimeInventoryComponent.Stack in inventory.items():
		if st.id == row and st.qty > 0:
			var it: ItemDef = ItemDef.by_id(st.item_def_id)
			if it == null or it.armor_slot != slot:
				return 0.0
			return piece(it.defense, maxi(RegentsGrade.quality_of(st.instance_data), 0))
	return 0.0
