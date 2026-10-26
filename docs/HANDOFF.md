# Handoff — UMF Template, 2026-10-26

## Where it stands
**1.1.1 COMMITTED AND PUSHED, NOT SHIPPED**: four foundation fixes made from a Regent's Rule session (Luke's
playtest of the continent, 2026-10-24). Regent's Rule has pulled it; **Fishing, Fowl Play and DiscGolf have
not** (`ship_template.sh` not run: the usage ran short). No schema change; the content bake is in it (a new
hot rule), so a game takes it with a pull, a publish (data kept) and its suites.
Suites here: the unit sweep 2205/0 after the last change (referee, remote_animation, presence, cells each
with its new checks; each new check failed with its fix taken out). Not run here: e2e, export, the server
suites (no server code changed; `cargo check` wasm green).

## This session (CHANGELOG 1.1.1)
- **DECISIONS #283, two sides**: hot flag `foundation.referee_two_sides` (off). On, a judged sweep passes
  through its user's own side, the players or everyone else (`ActionReferee.is_player`), to the first of
  the other. Regent's Rule turns it on (two skeletons blocked each other's swings). Fowl Play keeps it off.
  The referee suite sets it either way, since a game's override is its default.
- `AnimationDriverComponent`: a character is posed the moment it is built (`_tree.advance(0.0)`); since
  #282 a new one stood in its rest pose (a T-pose) until the driver's first advance.
- `Cells.recentre`: a jump past the cells next to the centre re-centres at once. Regent's Rule's spawn is
  ON a cell edge; back from far away a player kept a ring 600 m off and was sent nothing round them.
- `PresenceComponent`: a nameless player not yet known as an admin is asked after again every 0.5 s;
  `is_tool` is renamed `is_tool_row` (called from outside the class, `PresenceComponent.is_tool` was
  Godot's own `Script.is_tool()`).

## Next, in order
1. **Ship 1.1.1** to Fishing, Fowl Play and DiscGolf: `ship_template.sh "1.1.1: ..."` (each game's work
   committed first), then in each a publish and its suites. Fowl Play's referee suites matter most (the
   two-sides rule must stay off there).
2. The load test harness (Regent's Rule's HANDOFF: Tuesday after 5 pm), a milestone of its own here.

## Waiting on Luke
- Nothing new for the template.

## Watch out
- A game's hot-rule override is its build's default: a foundation test that assumes a rule's foundation
  default must set the rule itself (the referee suite does now).
- `SomeClass.is_tool(...)` from outside a script calls `Script.is_tool()`: avoid static names that
  shadow `Script`/`Resource` methods.
