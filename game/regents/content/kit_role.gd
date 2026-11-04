@tool
class_name KitRole extends Resource
## ONE ROLE OF A KIT (`KitDef.roles`; COMBAT_OVERHAUL.md §5): what a weapon of this kit does when its handle
## gives `role`. The role changes ONLY the string's last hit (Luke, 2026-10-31), so this is that hit and what
## it does besides its damage. It cannot be shared across kits: its lock is the kit's clip, and the referee
## judges each kit's moves its own way. (The pick pools join it with mastery picks, step 5.)

## The role (`RoleDef`).
@export var role: RoleDef
## The string's last hit with this role: armour, it flinches a light in its wind-up, it staggers.
@export var finisher: AbilityDef
## Its stagger, in percent of `regents.stagger_ms` (the sword's pommel bash: 150, so 1.2 s), before the Heavy
## trait's.
@export_range(0, 500, 5, "suffix:%") var stagger_pct: int = 100
## Landing, it heals players within `heal_radius_m` of its user this much, once a swing (the sword's rallying
## cut: 8). Its user too: in full alone, `regents.rally_self_share_pct` of it with players near (Luke,
## 2026-11-01). 0: no heal.
@export_range(0.0, 500.0, 0.5) var heal: float = 0.0
@export_range(0.0, 30.0, 0.5, "suffix:m") var heal_radius_m: float = 6.0
## WHAT THE HANDLE DOES, in the player's words, for the craft window's handle row and the weapon's tooltip
## ("ends the string with a pommel bash that holds the foe"). Never a role's name (show, don't name).
@export var does: String = ""


func to_bake() -> Dictionary:
	return {"role": ContentDef.ref(role), "finisher": ContentDef.ref(finisher), "stagger_pct": stagger_pct, "heal": heal,
		"heal_radius_m": heal_radius_m}
