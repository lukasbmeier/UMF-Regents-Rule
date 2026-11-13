@tool
class_name RegentsFoeTask extends BrainTask
## A STEP OF A FOE'S BEHAVIOR TREE (LimboAI; Luke's F2, 2026-11-12, `FOES_PREP.md` section 3.1; the template's
## `BrainTask`, DECISIONS #245): what each task in `trees/*.tres` is made of. A task asks its foe's brain to do one of
## its steps with this think's `me` and `world`: SUCCESS when it was that step's to do (and it has done it for this
## think), FAILURE when not (the tree goes on to the next).
##
## SERVER-ONLY (hard rule 7b): the world's referee runs the trees.


## The foe's brain (held weakly: its tree is its own, and must not keep it alive).
func brain() -> RegentsFoeBrain:
	return super() as RegentsFoeBrain
