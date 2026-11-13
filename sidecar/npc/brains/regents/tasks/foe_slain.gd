@tool
extends RegentsFoeTask
## Slain, it lies still and gives up its turn (RegentsFoeBrain.be_slain).


func _generate_name() -> String:
	return "Slain: lies still"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.be_slain(world()))
