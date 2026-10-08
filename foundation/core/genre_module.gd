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
@export var scenes: Array[PackedScene] = []
