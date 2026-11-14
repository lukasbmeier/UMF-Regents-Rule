@tool
class_name RegentsBarStyle extends Resource
## HOW THE ABILITY BAR LOOKS (Luke's B11, 2026-11-13: "I like round or square, maybe we do a small build of both"):
## one look a file, edited in the Inspector. `bar_round.tres` (Albion's round slots) and `bar_square.tres` (boxes,
## as OSRS and most MMOs) are the two built; the player picks one in Settings (Game: "Ability bar"), and
## `res://game/regents/ui/bar_lab.tscn` (F6, no server) shows both side by side. A third look is a third file, named
## in `RegentsAbilityBar.LOOKS`.

enum Shape { ROUND, SQUARE }

@export var shape: Shape = Shape.ROUND
@export_group("Sizes")
## An ability slot (Q E R F), its side or its diameter.
@export_range(32, 120, 1, "suffix:px") var slot_size: int = 60
## The roll's and the potion's slots, set apart.
@export_range(24, 100, 1, "suffix:px") var small_size: int = 42
## Between two slots.
@export_range(0, 40, 1, "suffix:px") var gap: int = 8
## Between the weapon's three and the chest's, and before the small ones.
@export_range(0, 80, 1, "suffix:px") var group_gap: int = 18
## A square slot's corners (a round one ignores it).
@export_range(0, 30, 1, "suffix:px") var corner_radius: int = 6
## A slot's edge.
@export_range(0.0, 8.0, 0.5, "suffix:px") var border_width: float = 2.0
## The ring round the weapon's three, filling toward the next unlock.
@export_range(1.0, 8.0, 0.5, "suffix:px") var ring_width: float = 3.0
## How far out of the slots the ring runs.
@export_range(0, 20, 1, "suffix:px") var ring_margin: int = 6
## The health bar above the slots.
@export_range(6, 40, 1, "suffix:px") var health_height: int = 18
@export_range(10, 40, 1) var key_font_size: int = 15
@export_range(10, 40, 1) var glyph_font_size: int = 26
@export_range(10, 40, 1) var count_font_size: int = 20
@export_group("Colors")
@export var slot_bg: Color = Color(0.07, 0.08, 0.1, 0.88)
@export var slot_border: Color = Color(0.55, 0.5, 0.4, 0.9)
## A slot's edge while in stance (Q E R F are abilities): the bar's clearest sign.
@export var stance_border: Color = Color(0.98, 0.8, 0.38, 1.0)
## The bar's glow while in a fight (hit or hurt lately).
@export var combat_glow: Color = Color(0.9, 0.18, 0.12, 0.75)
## Laid over a slot cooling down.
@export var cooldown_shade: Color = Color(0.0, 0.0, 0.0, 0.66)
## A slot whose cost the pool cannot pay.
@export var no_cost_tint: Color = Color(0.35, 0.45, 1.0, 0.45)
## A locked slot's whole look.
@export var locked_tint: Color = Color(0.45, 0.45, 0.48, 0.55)
## The flash as a slot fires.
@export var fire_flash: Color = Color(1.0, 0.95, 0.7, 0.85)
@export var ring_back: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var ring_fill: Color = Color(0.98, 0.8, 0.38, 0.95)
@export var key_color: Color = Color(1.0, 0.95, 0.82, 1.0)
@export var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var health_color: Color = Color(0.78, 0.16, 0.14)
@export var mana_color: Color = Color(0.22, 0.42, 0.92)
@export var roll_color: Color = Color(0.92, 0.7, 0.22)
@export_group("Out of stance")
## The whole bar's alpha out of stance (B11: it fades; E is then the world's key).
@export_range(0.1, 1.0, 0.05) var idle_alpha: float = 0.5


func round_slots() -> bool:
	return shape == Shape.ROUND
