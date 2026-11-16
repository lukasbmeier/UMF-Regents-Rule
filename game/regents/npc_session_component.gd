extends SessionComponent
## AN NPC'S SESSION: the foundation's `SessionComponent` with its `session_member` row OPTIONAL (armor run E2,
## 2026-11-15). The foes (`combat/foe.tscn`) and the guide (`npc.tscn`) are built on the foundation's
## `player.tscn`, whose Session component needs a member row before the entity binds. An NPC here is never a
## session's member (the server's `add_member` is for players joining a world's session), so each NPC that came
## into a client's ring stood frozen at its first rows until the 2 s bind timeout ran out, and printed "binding
## after 2.0s without rows for session_member". With the row optional it binds as soon as its own rows are in,
## and reads as in no session (`is_in_session()` false), as before.
##
## Set as the script of the inherited `Components/Session` node in those scenes; a player's (`adventurer.tscn`)
## keeps the foundation's, since a player in a world with a session is its member.
## OPEN QUESTION: the general fix is the foundation's (`SessionComponent.optional_tables` naming the member
## table, for every game's NPCs); proposed to the template in `docs/regents_rule/inbox/E2.md`. Once it lands
## this script and the scenes' override can go.


func optional_tables() -> Array[StringName]:
	return [MEMBER_TABLE, LOBBY_TABLE]
