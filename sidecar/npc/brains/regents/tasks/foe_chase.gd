@tool
extends RegentsFoeTask
## Its target out of sight (to where it last saw them, for FoeDef.lose_sight_ms) or too far to fight: it runs at them, round what is in the way (RegentsFoeBrain.chase).


func _generate_name() -> String:
	return "Out of sight or far: chases"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.chase(me(), world()))
