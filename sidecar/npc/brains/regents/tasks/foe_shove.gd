@tool
extends RegentsFoeTask
## Its target in its reach and a melee turn free: its string, a shove. No turn: the tasks below (RegentsFoeBrain.shove).


func _generate_name() -> String:
	return "Caught, in reach: shoves"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.shove())
