@tool
extends RegentsFoeTask
## It stands, faces its target and draws its shot (the first skill of its kit that a bolt SpellDef flies) when rested, with a turn for a shot free (regents.ranged_tokens); FoeDef.shot_rest_ms between two. Never at what it cannot see (RegentsFoeBrain.shoot).


func _generate_name() -> String:
	return "In range, in sight: draws and shoots"


func _tick(_delta: float) -> Status:
	var b: RegentsFoeBrain = brain()
	return done(b != null and b.shoot())
