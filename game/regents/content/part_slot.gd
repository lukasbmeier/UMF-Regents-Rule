@tool
class_name PartSlot extends Resource
## ONE SLOT OF A PATTERN (`PatternDef.parts`; `docs/regents_rule/MATERIALS.md` §3): one thing its recipe
## takes. A pattern lists as many as it needs (an axe: head, handle, binding; a bar: its ore), so an oil or
## a weapon of five parts is a pattern with more slots, never code.

enum Takes {
	## The material's raw form (its `MaterialDef.raw`: iron ore for an iron bar, oak logs for an oak handle).
	RAW,
	## THIS material's cell of `pattern` (an iron axe takes an IRON axe head).
	SAME_MATERIAL,
	## Any material's cell of `pattern`, the player's pick at the station (an iron axe takes any handle).
	## The recipe lists `default_material`'s; one slot of a pattern at most, for now.
	ANY_MATERIAL,
	## One fixed item (copper rivets), whatever the material.
	ITEM,
}

## What it is called ("head", "handle", "binding", "ore").
@export var name: String = ""
@export var takes: Takes = Takes.RAW
## The pattern whose cell goes here (`SAME_MATERIAL`, `ANY_MATERIAL`).
@export var pattern: PatternDef
## The material the recipe lists for an `ANY_MATERIAL` slot (plain wood: the plain handle).
@export var default_material: MaterialDef
## The item that goes here (`ITEM`).
@export var item: ItemDef
## How many the recipe takes (the recipe's own number is kept once made: tune it there, on the recipe bench).
@export_range(1, 1000) var qty: int = 1
## THE CORE: the slot whose material is the made item's, and so its tier (`MATERIALS.md` §1). One a pattern.
@export var core: bool = false


func to_bake() -> Dictionary:
	return {"name": name, "takes": int(takes), "pattern": ContentDef.ref(pattern), "default_material": ContentDef.ref(default_material),
		"item": ContentDef.ref(item), "qty": qty, "core": core}


## What is wrong with it, one sentence each (its pattern's `validate` names it).
func validate() -> Array[String]:
	var out: Array[String] = []
	if name.strip_edges().is_empty():
		out.append("a slot has no name")
	match takes:
		Takes.SAME_MATERIAL, Takes.ANY_MATERIAL:
			if pattern == null:
				out.append("its %s slot takes a pattern's cell but names no `pattern`" % name)
			if takes == Takes.ANY_MATERIAL and default_material == null:
				out.append("its %s slot is the player's pick but names no `default_material` (the one the recipe lists)" % name)
			if takes == Takes.ANY_MATERIAL and core:
				out.append("its %s slot is the core and the player's pick: the core's material is the item's own" % name)
		Takes.ITEM:
			if item == null:
				out.append("its %s slot takes an item but names none" % name)
			if core:
				out.append("its %s slot is the core but takes a fixed item: the core's material is the item's own" % name)
	return out
