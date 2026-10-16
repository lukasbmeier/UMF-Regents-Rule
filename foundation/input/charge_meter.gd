class_name ChargeMeter extends RefCounted
## A HOLD-TO-CHARGE METER (DECISIONS #249): hold, and it fills from 0 to 1 in `charge_s`; let go, and
## the throw has that much power. Past `over_from` the throw is OVERCHARGED (a genre decides what that
## costs: a disc thrown nose-up, a cast that tangles). Held on at the top it stays full (HOLD), or comes
## back down and up again (BOUNCE, for a meter you must time). Pure: a throw, a cast, a kick, a jump pad.
##
## Presentation and input only: what it gives is the player's claim, bounded by the server like any.

enum Over { HOLD, BOUNCE }

## Seconds from empty to full.
var charge_s: float = 1.2
## Past this the throw is overcharged.
var over_from: float = 0.95
var over_mode: Over = Over.HOLD

## Where it is now, 0..1.
var value: float = 0.0
## Whether it is being held.
var held: bool = false
## How long it has been held.
var held_s: float = 0.0

var _dir: float = 1.0


func _init(p_charge_s: float = 1.2, p_over_from: float = 0.95, p_mode: Over = Over.HOLD) -> void:
	charge_s = maxf(p_charge_s, 0.01)
	over_from = p_over_from
	over_mode = p_mode


## Start holding: empty, filling.
func begin() -> void:
	held = true
	value = 0.0
	held_s = 0.0
	_dir = 1.0


## `dt` more seconds held. Its value after.
func step(dt: float) -> float:
	if not held or dt <= 0.0:
		return value
	held_s += dt
	var v: float = value + _dir * dt / charge_s
	if v >= 1.0:
		if over_mode == Over.BOUNCE:
			v = 1.0 - (v - 1.0)
			_dir = -1.0
		else:
			v = 1.0
	elif v <= 0.0 and over_mode == Over.BOUNCE:
		v = -v
		_dir = 1.0
	value = clampf(v, 0.0, 1.0)
	return value


## Whether letting go now would be overcharged.
func is_over() -> bool:
	return value >= over_from


## Let go: {power (0..1), over, held_s}. It stops filling.
func release() -> Dictionary:
	var out: Dictionary = {"power": value, "over": is_over(), "held_s": held_s}
	held = false
	return out


## Let go of it without throwing (hit while charging, a key to put it down).
func cancel() -> void:
	held = false
	value = 0.0
	held_s = 0.0
