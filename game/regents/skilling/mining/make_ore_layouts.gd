extends Node
## MAKES A STARTING ORE LAYOUT FOR EACH ROCK MODEL (owner, 2026-10-21; `RegentsOreSpots`): the rock and
## five nuggets snapped onto its surface, saved as `ore/<model>_ore.tscn`. Then open one in the editor and
## move, turn or size the nuggets (Ore1, Ore2, ...: add or delete some too) and save: every rock of that
## model shows its ore so. The nuggets show grey here; in the game they take their ore's colour.
## A layout that is already there is left alone (yours); --force writes it again.
##
##   godot --headless --path . res://game/regents/skilling/mining/make_ore_layouts.tscn [-- --force]
## (a scene, not a -s script: the content needs the autoloads)

const NUGGET: String = "res://game/regents/art/nature/Pebble_Round_1.gltf"


func _ready() -> void:
	var force: bool = OS.get_cmdline_user_args().has("--force")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RegentsOreSpots.LAYOUT_DIR))
	var nugget: PackedScene = load(NUGGET) as PackedScene
	var models: Array[PackedScene] = []
	for d: ContentDef in ContentLibrary.items(&"node"):
		var nd: NodeDef = d as NodeDef
		if nd == null or nd.ore_color.a <= 0.0:
			continue
		for m: PackedScene in nd.models:
			if m != null and not models.has(m):
				models.append(m)
	var made: int = 0
	for m: PackedScene in models:
		var path: String = RegentsOreSpots.layout_path(m)
		if ResourceLoader.exists(path) and not force:
			print("ore layout: %s is there already (yours): left alone" % path)
			continue
		var root := Node3D.new()
		root.name = m.resource_path.get_file().get_basename() + "_ore"
		var rock: Node3D = m.instantiate() as Node3D
		rock.name = "Rock"
		root.add_child(rock)
		rock.owner = root
		var i: int = 0
		for spot: Transform3D in RegentsOreSpots.on_surface(rock, 5, 0):
			i += 1
			var n: Node3D = nugget.instantiate() as Node3D
			n.name = "Ore%d" % i
			n.transform = spot
			root.add_child(n)
			n.owner = root
		var packed := PackedScene.new()
		packed.pack(root)
		var err: Error = ResourceSaver.save(packed, path)
		print("ore layout: %s, %d nuggets (%s)" % [path, i, error_string(err)])
		root.free()
		made += 1
	print("ore layouts made: %d" % made)
	AppExit.quit(get_tree(), 0)
