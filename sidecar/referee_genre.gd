class_name RefereeGenre extends RefCounted
## WHAT A GENRE TELLS ITS REFEREE (template 1.7.2, DECISIONS #304). A referee runs without entity scenes
## (`--referee` builds only the bots it drives, DECISIONS #230), so whatever a genre's client builds from a
## scene (a rock's hulls, a tree's trunk) the referee cannot see. A genre answers here, from the rows and
## the content the referee holds, in `res://sidecar/genres/<genre id>.gd` (extending this; list it in the
## genre's manifest, `tools/template/genres/<id>.paths`). The sidecar makes one for every genre
## `shared/game.json` lists that has one, and hands it to its referee. Fill in what you need.
##
## WALLS, PER ENTITY. An entity's character can put up one box for every entity of its kind
## (`EntityDefinition.blocker_size`, DECISIONS #229). A genre whose entities of one kind differ (a rock
## three metres wide and a tree with a 0.9 m trunk, both gathering nodes) sizes each one here instead:
##   sizes_kind(kind)   true for the kinds whose walls this genre gives (asked once a kind)
##   walls(eid, kind)   the boxes that entity puts in the way, in its own terms (from its feet, turned
##                      with it); empty: none (yet: its row has not come)
##   wall_tables()      the tables `walls` reads: when a row of one changes, `walls` is asked again for
##                      that row's `entity_id`. The referee is sent them without being listed elsewhere.
## The character's `blocks_in` still switches the wall (a worked-out rock's rubble does not block; a kind
## with no definition in the referee blocks in every status), its status row asks again too, and a wall
## counts in the walk maps its foes path by (`NpcNav`).
##
## REFEREE ONLY: a client builds its genre's own collision from the entity's scene, and never sees this
## (no second box there). Keep the two from the same numbers (a NodeDef's model and scale) so a foe stops
## where a player does.
##
## SERVER-ONLY (hard rule 7b).

## Where a genre's file is: `res://sidecar/genres/<id>.gd`.
const DIR: String = "res://sidecar/genres/"


## Whether this genre gives the walls of entities of `kind` (then `walls` is asked for each of them, and
## the kind's `blocker_size` is not used by the referee).
func sizes_kind(_kind: int) -> bool:
	return false


## The boxes entity `entity_id` (of `kind`) puts in the way, each in its own terms (an `AABB` from its feet,
## turned with its heading). Empty: none. Read its rows with `SpaceTimeSync.get_row(table, entity_id)`.
func walls(_entity_id: int, _kind: int) -> Array[AABB]:
	return []


## The tables `walls` reads (each row's `entity_id` is the entity whose walls it changes).
func wall_tables() -> Array[StringName]:
	return []


## A box `size` round a point `centre` above the feet (a convenience: `AABB(centre - size / 2, size)`).
static func box(size: Vector3, centre: Vector3 = Vector3.ZERO) -> AABB:
	return AABB(centre - size * 0.5, size)


## The genre's file for `genre_id`, made (null: it has none). `path` overrides where it is (tests).
static func load_for(genre_id: String, path: String = "") -> RefereeGenre:
	var at: String = path if not path.is_empty() else DIR + genre_id + ".gd"
	if at.contains("..") or not ResourceLoader.exists(at):
		return null
	var script: GDScript = load(at) as GDScript
	var made: Variant = script.new() if script != null else null
	if made is RefereeGenre:
		return made as RefereeGenre
	push_error("RefereeGenre: %s does not extend RefereeGenre" % at)
	return null
