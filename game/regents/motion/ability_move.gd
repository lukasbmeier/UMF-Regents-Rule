class_name AbilityMove extends Resource
## ONE ABILITY SHOWN AS A MOVE (PROGRESS 110, Luke 2026-11-18: "map everything to placeholder abilities and I'll try them
## in action"): when `ability` begins on any fighter, on every client, `move` plays on it (`MotionPlayer`), and on
## whatever its hit lands `victim` plays, facing it. A row of `AbilityMoves` (`ability_moves.tres`).
##
## Presentation only (hard rule 11): the server's swing, lunge, push and pull are what happen; this shows them. The body
## is never carried here (the lunge's dash and the server's push move it), so a move's travel is only shown in the lab.

@export var ability: AbilityDef = null
## Its user's move.
@export var move: MotionMove = null
## Where the move begins (s into it): a long run-up left out where the ability's wind-up is short.
@export_range(0.0, 5.0, 0.01, "suffix:s") var from_s: float = 0.0
## How fast it plays (1: as made).
@export_range(0.25, 3.0, 0.05) var speed: float = 1.0
## What a fighter its hit lands on plays (null: its own flinch).
@export var victim: MotionMove = null
## Shown as a WALTZ: `move` once on each of up to `waltz_count` foes in reach, from a new side each, the figure (never
## the body) darting there and back. A sketch of a kind the server does not have yet (`ABILITY_LIMITS.md` §2).
@export var waltz: bool = false
@export_range(1, 6) var waltz_count: int = 3
