@tool
extends RegentsFoeTask
## Near its target with no turn free (regents.attack_tokens): it circles a little beyond its reach, facing them (RegentsFoeBrain.wait_turn).


func _generate_name() -> String:
	return "No turn: circles, facing them"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.wait_turn(me(), world()))
