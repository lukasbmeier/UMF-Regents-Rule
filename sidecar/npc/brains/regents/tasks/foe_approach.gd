@tool
extends RegentsFoeTask
## Its target out of sight or past FoeDef.shot_range_m: in, round what is in the way, until they are in sight and a little inside its range (RegentsFoeBrain.approach).


func _generate_name() -> String:
	return "Out of sight or range: walks in"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.approach(me(), world()))
