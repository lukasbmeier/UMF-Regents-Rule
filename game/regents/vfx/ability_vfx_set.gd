class_name AbilityVfxSet extends Resource
## EVERY ABILITY'S EFFECTS (PROGRESS 82: Luke, 2026-11-14, "lets use the vfx in all the current abilites"): the
## table `AbilityVfx` reads, `res://game/regents/vfx/ability_vfx.tres`. Open it in the Inspector to change which
## effect an ability shows; the effects themselves are the scenes in `vfx/effects/`.
##
## What is not in it, because the game draws it already, now in the lab's looks:
##   - every melee swing (a player's and a foe's): the cut along the blade (`SwingTrail`, `VfxBladeCut.look()`);
##   - a missile in flight and where it ends: its body's look (`content/body/*.tres` -> `fireball_look.tscn`,
##     `bolt_look.tscn`: the riding `fire_missile.tscn` and the end effect);
##   - an area spell's circle and landing: `SpellLooks` (`frost_ring.tscn`, `cinder_ring.tscn`).

const PATH: String = "res://game/regents/vfx/ability_vfx.tres"

@export var entries: Array[AbilityVfxEntry] = []
## Played where a parry turns a blow (this client's own parry): at the blocking hand.
@export var parry: PackedScene

static var _loaded: AbilityVfxSet = null


## The game's table (loaded once).
static func current() -> AbilityVfxSet:
	if _loaded == null:
		_loaded = load(PATH) as AbilityVfxSet
	return _loaded


## The row for ability `id`, or null.
func entry(id: int) -> AbilityVfxEntry:
	for e: AbilityVfxEntry in entries:
		if e != null and e.ability != null and e.ability.id == id:
			return e
	return null
