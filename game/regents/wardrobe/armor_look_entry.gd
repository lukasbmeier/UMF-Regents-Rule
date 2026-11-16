@tool
class_name ArmorLookEntry extends Resource
## WHAT ONE ARMOR PATTERN LOOKS LIKE WORN (W2; Luke's W1 and W3, `GAME.md`): the outfit pieces it puts on, slot by slot,
## for each body. A row of `armor_looks.tres` (`ArmorLooks`), edited in the Inspector. The pieces are file names in
## `Wardrobe.PIECE_DIRS` without `.gltf` ("Male_Knight_Body_Armor"); "" in a slot wears nothing there.
## Slots are the character's: torso, arms, legs, feet, head, shoulders, neck (and hairstyle, beard, brows).
## A row with a `material` is that pattern in that material only (steel's spiked pauldrons) and wins over the
## pattern's own row.

## The pattern it is (`PatternDef.key`: armet, cuirass, legplates, hood, jerkin, leather_trousers, robe, cloth_trousers).
@export var pattern: StringName = &""
## Only in this material (`MaterialDef.key`: steel); empty for every material.
@export var material: StringName = &""
## slot -> piece file, on a man's body.
@export var male: Dictionary[StringName, String] = {}
## slot -> piece file, on a woman's body.
@export var female: Dictionary[StringName, String] = {}


## The pieces for `body` (&"male" / &"female").
func pieces_for(body: StringName) -> Dictionary[StringName, String]:
	return female if body == &"female" else male
