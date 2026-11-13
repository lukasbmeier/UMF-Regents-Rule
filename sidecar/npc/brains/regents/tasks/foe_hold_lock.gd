@tool
extends RegentsFoeTask
## Mid-draw or mid-shove it stands where it is, facing its target, until that move is over: its opening (RegentsFoeBrain.hold_lock).


func _generate_name() -> String:
	return "Mid-draw or mid-shove: stands"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.hold_lock())
