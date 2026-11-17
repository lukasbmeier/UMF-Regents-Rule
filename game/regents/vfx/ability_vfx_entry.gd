class_name AbilityVfxEntry extends Resource
## WHAT ONE ABILITY SHOWS (PROGRESS 82), beyond what the game draws already (a swing's cut: `SwingTrail`; a missile:
## its body's look; an area's ring: `SpellLooks`). One row of `ability_vfx.tres` (`AbilityVfxSet`); `AbilityVfx` on
## every player and foe plays it. Presentation only: never what happens, only how it looks.

## The ability (a spell's, or a foe's).
@export var ability: AbilityDef
@export_group("While it is cast")
## Shown in the hand(s) for its cast time (another player's: while their `casting` row says so; a foe's: its
## wind-up, the tell): a charge (`fire_charge.tscn`, `frost_charge.tscn`). Null: none.
@export var charge: PackedScene
## Both hands (a channel): the charge sits between them. Else in `hand_bone`.
@export var two_hands: bool = false
@export var hand_bone: StringName = &"hand_l"
## How far in front of the hand(s) it sits, toward where the caster faces (never inside the wrist).
@export_range(0.0, 1.0, 0.01, "suffix:m") var ahead_m: float = 0.16
@export_group("As it leaves the hand")
## A flash in the hand as a spell with NO cast time is let go, facing the way it was aimed (the Bolt's:
## `bolt_cast.tscn`), in `hand_bone`, `ahead_m` in front of it. This client's own as it casts; another player's from
## the server's word that it was cast (`spell_landed`), while fresh. Null: none. (A spell with a cast time shows its
## charge instead.)
@export var on_cast: PackedScene
@export_group("As it lands")
## Played at the caster's feet facing the way it was aimed, as it lands (a cone: `gale.tscn`). This client's own
## cast only: other clients are not told of a cast with no cast time.
@export var on_land: PackedScene
## Played when the caster is seen to jump (`blink.tscn`): from where they were to where they are, the body faded.
## Every client sees it (the jump is in the movement every client gets).
@export var on_jump: PackedScene
@export_group("Its ring")
## An AREA spell's circle on the ground (`SpellLooks`), a `VfxGroundRing` of its element (`frost_ring.tscn`,
## `meteor_ring.tscn`). Null: a player's in frost, a foe's in fire (`cinder_ring.tscn`).
@export var ring: PackedScene
