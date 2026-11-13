@tool
extends RegentsFoeTask
## Its turn and its target beyond FoeDef.reach_m: in to its reach, mid-string too once the last swing's lock is over (RegentsFoeBrain.close_in).


func _generate_name() -> String:
	return "Its turn, out of reach: closes in"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.close_in(me(), world()))
