@tool
class_name BeatParams extends Resource
## ONE SMELT'S ROUND AS A RHYTHM TRACK (`BeatModel`; Luke, 2026-11-07: "smelting needs to be changed to a rhythm game",
## then "Full rhythm track"). The bellows breathe on a beat: after a count-in, notes come down a track to the bellows
## and the player presses on each (Space or the mouse), holding the long ones to their end. A press near a note
## heats the melt (nearer pays more); a press on no note is wasted breath and costs; mashing never pays. Then the
## POUR, as before: hold to tilt the crucible, let go at the mold's line; past the brim it spills.
## The track is drawn from the round's seed, so no two rounds are the same, and the server replays it. Whole numbers
## only (the server replays it in Rust: `genre::regents::beat`).

@export var display_name: String = "Smelt"

@export_group("The beat")
## One beat (the tempo: 600 ms is 100 beats a minute). Even, and at least four times `good_ms`, so two notes'
## windows never meet (the bake refuses it otherwise).
@export_range(200, 2000, 2, "suffix:ms") var beat_ms: int = 600
## Beats of count-in before the first note (the beat is heard and the track scrolls, nothing to press).
@export_range(0, 16) var lead_beats: int = 4
## How many beats the track lasts. Every fourth beat (a bar's first) always has a note.
@export_range(1, 128) var beats: int = 16

@export_group("The track (drawn from the seed)")
## How often a beat other than a bar's first is a rest (no note), in thousandths.
@export_range(0, 1000, 1, "suffix:‰") var rest_pm: int = 150
## How often a note falls half a beat after a beat (an off-beat), in thousandths.
@export_range(0, 1000, 1, "suffix:‰") var offbeat_pm: int = 120
## How often a beat's note is a LONG DRAW of the bellows (press on it, hold to its end), and how many beats it
## lasts (0: never). A draw always ends inside the track; nothing else is played while it is drawn.
@export_range(0, 1000, 1, "suffix:‰") var hold_pm: int = 100
@export_range(0, 8) var hold_beats: int = 2

@export_group("Judging a press")
## A press this near a note (either side) is full value; this near is `good_pm` of it; farther is no note at all.
@export_range(1, 500, 1, "suffix:ms") var perfect_ms: int = 70
@export_range(1, 500, 1, "suffix:ms") var good_ms: int = 150
## What a press in the outer window is worth (a full one is 1000).
@export_range(0, 1000, 1, "suffix:‰") var good_pm: int = 600
## What a press on no note costs (taken off the track's total, a full note being 1000): what stops mashing.
@export_range(0, 1000, 1, "suffix:‰") var stray_pm: int = 250

@export_group("The pour")
## How long the pour lasts after the track (0: no pour, the track is the whole score), and how long after the
## track before the crucible will tilt (a press on the last note never spills into a pour).
@export_range(0, 30000, 50, "suffix:ms") var pour_ms: int = 4000
@export_range(0, 3000, 50, "suffix:ms") var pour_ready_ms: int = 600
## How fast the mold fills while pouring (thousandths per 50 ms).
@export_range(1, 500) var pour_rate: int = 28
## The mold's line falls somewhere between these (thousandths of the mold).
@export_range(0, 1000) var target_lo: int = 620
@export_range(0, 1000) var target_hi: int = 820
## How far off the line scores nothing for the pour.
@export_range(1, 1000) var pour_tolerance: int = 220
## The track's share of the score (percent); the pour has the rest.
@export_range(0, 100) var track_weight_pct: int = 70

@export_group("Slag (band 2, a test)")
## SLAG (`MINIGAMES_PREP.md` §3, band 2's new thing for smelting; a TEST for Luke's play, 2026-11-07): how likely a
## press note is slag, skimmed off with the SECOND button (F or the right mouse button) instead of pumped. The main
## button never plays a slag note; a skim on no slag is wasted breath. 0: no slag (a skim is then ignored).
@export_range(0, 1000, 1, "suffix:‰") var slag_pm: int = 0
