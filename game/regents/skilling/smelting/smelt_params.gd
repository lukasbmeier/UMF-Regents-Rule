@tool
class_name SmeltParams extends Resource
## ONE SMELT'S ROUND (bellows, then pour: `SmeltModel`). First the HEAT: the furnace cools every tick;
## each pump of the bellows heats it; keep it inside a band that drifts and narrows (and never past the
## burn line): mash faster to heat it, ease off to cool it. Then the POUR: hold to tilt the crucible, let
## go to stop; tilt again to top it up; end at the mould's line; past the brim it spills. Whole numbers
## only (the server replays it in Rust); heat and fill are thousandths.

@export var display_name: String = "Smelt"
## The heating part's length, then the pouring part's.
@export_range(1000, 60000, 50, "suffix:ms") var heat_ms: int = 7000
@export_range(500, 30000, 50, "suffix:ms") var pour_ms: int = 4000
## After the heat, this long before the crucible can tilt: mashing the bellows never spills into a pour.
@export_range(0, 3000, 50, "suffix:ms") var pour_ready_ms: int = 600
## The shortest time between two pumps of the bellows: keep it under how fast a hand can mash (a pump
## sooner is lost), so it only stops a macro.
@export_range(0, 2000, 10, "suffix:ms") var pump_ms: int = 40
## Heat one pump adds, and heat lost every 50 ms tick: the furnace holds steady at
## cool_per_tick * 20 / pump_heat pumps a second.
@export_range(1, 500) var pump_heat: int = 45
@export_range(0, 200) var cool_per_tick: int = 10
## The furnace's heat when the round begins.
@export_range(0, 1000) var start_heat: int = 350
## The band's middle, how far it swings either way, and how long one swing takes (ticks of 50 ms).
@export_range(0, 1000) var band_center: int = 600
@export_range(0, 500) var band_amp: int = 140
@export_range(4, 2000) var band_period_ticks: int = 80
## The band's half-width at the start of the heat and at its end.
@export_range(5, 500) var band_half_start: int = 120
@export_range(5, 500) var band_half_end: int = 60
## Heat above this burns the ore (a tick there counts against the heat).
@export_range(0, 1000) var burn_line: int = 900
## How fast the mould fills while pouring (thousandths per tick).
@export_range(1, 500) var pour_rate: int = 28
## The mould's line falls somewhere between these (thousandths of the mould).
@export_range(0, 1000) var target_lo: int = 620
@export_range(0, 1000) var target_hi: int = 820
## How far off the line scores nothing for the pour.
@export_range(1, 1000) var pour_tolerance: int = 220
## The heat's share of the score (percent); the pour has the rest.
@export_range(0, 100) var heat_weight_pct: int = 60
