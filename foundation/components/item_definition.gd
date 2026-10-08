class_name ItemDefinition extends Resource
## Client-side presentation for one `item_def` row. The server's row is the source of truth for
## `kind` and `max_stack`; this is how a game attaches a name, an icon and a description to it.
##
## Genres ship these as `.tres` files and register them with an `ItemCatalog`-style lookup, the
## same shape as `EntityDefinition` for entities.

## Must match the server's `item_def.item_def_id`.
@export var item_def_id: int = 0
## Mirrors the server row; kept here so UI can lay out stacks without a round trip.
@export var max_stack: int = 1
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
