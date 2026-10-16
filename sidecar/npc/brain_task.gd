@tool
class_name BrainTask extends BTAction
## A STEP OF A BOT'S BEHAVIOUR TREE (LimboAI, DECISIONS #245): what a genre's tasks extend. A task asks
## its brain (the blackboard's `brain`, set by `NpcBrain.run_tree`) to do one of its steps with this
## think's `me` and `world`, with the numbers set on the task in the Inspector: SUCCESS when it was that
## step's to do (and it has done it for now), FAILURE when not (the tree goes on to the next).
##
## A genre's own base task narrows `brain()` to its brain's class (`ChickenTask`: `brain() as ChickenBot`).
##
## SERVER-ONLY (hard rule 7b): the world's referee runs the trees.


## The brain (held weakly: its tree is its own, and must not keep it alive).
func brain() -> NpcBrain:
	var w: WeakRef = blackboard.get_var(&"brain", null, false) as WeakRef
	return w.get_ref() as NpcBrain if w != null else null


func me() -> MovementState:
	return blackboard.get_var(&"me", null, false) as MovementState


func world() -> NpcWorldView:
	return blackboard.get_var(&"world", null, false) as NpcWorldView


static func done(ok: bool) -> Status:
	return SUCCESS if ok else FAILURE
