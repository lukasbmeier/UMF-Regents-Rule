@abstract
class_name ContentDef extends Resource
## ONE PIECE OF CONTENT, edited in the Inspector (docs/CONTENT_TOOLING_SPEC.md §1, DECISIONS #199):
## an ability, an item, a fish. Godot's Inspector is the content editor; the JSON the server
## compiles in (`shared/content/<owner>/<type>.json`) is a build artifact, written by the bake
## (`tools/bake_content.gd`) and never edited by hand. `server/build.rs` refuses to build while a
## `.tres` has been changed or added without baking.
##
## A content type is a subclass: `@export`s with `@export_range` on every number (the real design
## bounds), an enum for every category, a typed reference for every link to other content (never a
## bare id). Its instances live under `foundation/content/<type>/` or `game/<genre>/content/<type>/`.
## The `##` comment above each export is what the Inspector shows: it is the documentation.

## Unique within its type. A genre takes its numbers from the space it claims (DECISIONS #173).
@export var id: int = 0
## What a player sees it called.
@export var display_name: String = ""
## For the people making the game. Never baked, never shipped to the server.
@export_multiline var designer_notes: String = ""


## The type's name: the baked file is `<type>.json`. `&"ability"`, `&"item"`, `&"fish"`.
@abstract func content_type() -> StringName


## What the server compiles in, exactly: plain JSON values, no designer notes.
@abstract func to_bake() -> Dictionary


## What is wrong with it that the types cannot say, one human sentence each; empty when it is
## fine. The bake refuses content with any.
func validate() -> Array[String]:
	var out: Array[String] = []
	if id < 0:
		out.append("its id is negative")
	if display_name.strip_edges().is_empty():
		out.append("it has no display name")
	return out
