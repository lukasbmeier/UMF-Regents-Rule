class_name SkillingRules extends RefCounted
## WHAT A PLAYED ROUND PAYS, as the client reads it (the server's `genre::regents::active_yield_milli` and
## `active_rare_mult` decide; these are for the readout, the recipe bench and the HUD's words). Luke's M11
## (2026-11-05): a good round beats AFK and a poor one still falls short, the break-even near half a score. Pay runs
## straight from `regents.active_yield_floor` (a score of 0) to `regents.active_yield_mult` (a full score), each a share
## of what AFK makes in the round's time; the rare edge from 1 (a score of 0) to `regents.active_rare_mult`.


## A round's pay at `score_pm`, as a share of AFK's in the same time.
static func active_factor(mult: float, floor_share: float, score_pm: int) -> float:
	var f: float = clampf(floor_share, 0.0, maxf(0.0, mult))
	return f + (mult - f) * clampi(score_pm, 0, 1000) / 1000.0


## The score at which a round pays what AFK does (1000 and over: never).
static func break_even_pm(mult: float, floor_share: float) -> int:
	var f: float = clampf(floor_share, 0.0, maxf(0.0, mult))
	if f >= 1.0:
		return 0
	if mult <= f:
		return 1001
	return ceili((1.0 - f) / (mult - f) * 1000.0 - 0.000001)


## How much likelier a round at `score_pm` is to bring a rare find than AFK.
static func rare_factor(rare_mult: float, score_pm: int) -> float:
	return 1.0 + (maxf(1.0, rare_mult) - 1.0) * clampi(score_pm, 0, 1000) / 1000.0
