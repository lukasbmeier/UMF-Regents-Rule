@tool
class_name SimPlayer extends Resource
## A SIMULATED PLAYER OF SET SKILL, for the difficulty readout (`MinigameReadout`, `MINIGAMES_PREP.md` §6): how
## quickly they act on what a round shows them, how steady their timing and aim are, how often they make the
## wrong call, and how fast they can press. The four `presets()` (flawless, skilled, average, careless) are what
## the readout reports; a designer may make another (New Resource, SimPlayer) to see a round through other hands.
## A readout is a GUIDE for tuning, not the final word: Luke's own play is (Luke, 2026-11-05: M4).

@export var display_name: String = "Player"
## How long after a round shows something new (the trunk drops, the next notch glows) before they act on it.
@export_range(0, 1500, 10, "suffix:ms") var react_ms: int = 250
## The spread of their timing either side of when they mean to act (one standard deviation).
@export_range(0, 500, 5, "suffix:ms") var jitter_ms: int = 60
## The spread of where they strike, or of how they read a gauge (one standard deviation, thousandths of it).
@export_range(0, 300, 1, "suffix:‰") var aim_pm: int = 30
## How often a choice is the wrong one: the wrong side, the column beside the one meant, a notch skipped.
@export_range(0, 100, 1, "suffix:%") var slip_pct: int = 5
## The fastest they press again and again (the bellows), presses a second.
@export_range(1, 30) var mash_hz: int = 8
## Whether they think a strike ahead (the anvil: the strike that brings the bar closest to the outline,
## spread and all) or hit wherever the bar bulges most.
@export var plans: bool = false
## THE ANVIL'S TEMPLATE (2026-11-05): how many strikes after a look at the pattern they still have it exactly in mind
## (after that each column is remembered a little off), and whether they lay it on again to check before they finish
## (once the picture has blurred and only the finishing taps are left), or never look again after the first.
@export_range(0, 1000) var memory_strikes: int = 1000
@export var looks_again: bool = false


static func make(name: String, react: int, jitter: int, aim: int, slip: int, mash: int, plan: bool, memory: int = 1000,
		looks: bool = false) -> SimPlayer:
	var s: SimPlayer = SimPlayer.new()
	s.display_name = name
	s.react_ms = react
	s.jitter_ms = jitter
	s.aim_pm = aim
	s.slip_pct = slip
	s.mash_hz = mash
	s.plans = plan
	s.memory_strikes = memory
	s.looks_again = looks
	return s


## The four the readout reports, best first. A FLAWLESS player is the ceiling (no human plays it); SKILLED is
## a good player paying attention; AVERAGE someone who knows the game; CARELESS someone half watching.
## ASSUMPTION: these numbers are a first guess at human hands (react ~200-380 ms, timing spread 45-120 ms),
## to be set against Luke's own play of the same rounds. Memory (the anvil's pattern) is a guess too: a flawless
## smith never forgets it; a careless one forgets it in a few strikes and never looks again.
static func presets() -> Array[SimPlayer]:
	return [
		make("Flawless", 0, 0, 0, 0, 14, true),
		make("Skilled", 200, 45, 20, 3, 10, true, 20, true),
		make("Average", 280, 75, 35, 8, 7, false, 10, true),
		make("Careless", 380, 120, 55, 18, 5, false, 6, false),
	]
