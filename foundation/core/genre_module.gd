class_name GenreModule extends Resource
## ONE GENRE, AS THE CLIENT BOOTS IT (DECISIONS #173): everything the game needs from it, in one
## file at `res://game/<id>/genre.tres`. A game is the list of genres in `shared/game.json` (the
## server compiles in the same list); Boot loads each genre's file and takes from it:
##
##   entity_definitions  the kinds of entity it spawns (its player, its NPCs, its props)
##   tables              its tables, added to the game's subscription; `world_tables` are those
##                       whose rows each belong to one world (asked for `WHERE world_id = N`)
##   scenes              what it puts in the game: its HUD, its world's presentation (the sky,
##                       the music), added under the game scene when it boots
##
## Take a genre out of `shared/game.json` and none of this is loaded; nothing in the foundation
## names it. Edit it in the Inspector.

## The genre's name: its folder under `game/` and its file under `server/src/game/`.
@export var id: StringName = &""
@export var display_name: String = ""
@export var entity_definitions: Array[EntityDefinition] = []
@export var tables: Array[StringName] = []
@export var world_tables: Array[StringName] = []
## Of `world_tables`, those whose rows carry the cell of a placed thing (`chunk`, template 1.0): a ring client
## and a REGION REFEREE (DECISIONS #288) ask for them by cell, not the whole world (template 1.5: before, a
## referee's config never heard of the game's, and its region was sent every one of these rows). The same
## list the game's NetConfig `cell_tables` has (either may name them; both are used).
@export var cell_tables: Array[StringName] = []
## The tables a REFEREE reads for this genre (DECISIONS #286): what its brains and its sidecar parts ask
## `SpaceTimeSync` for themselves, the foundation's or its own. A referee subscribes only what it reads
## (the tables its entity scenes' components declare come by themselves), so a table left off is never
## there: reading one is an error in the referee, naming it. `*` (the default): every one of the genre's
## `tables`, as before. Empty: none.
@export var referee_tables: Array[StringName] = [&"*"]
@export var scenes: Array[PackedScene] = []
## Where this genre's content ids start (ContentLibrary, DECISIONS #200): a new ability, item or
## species made for it gets the next free id at or above this, so two genres' content in one game
## never collides. Pick a block no other genre uses (fishing 0 by history; the next 10000, ...).
@export var content_id_base: int = 0
