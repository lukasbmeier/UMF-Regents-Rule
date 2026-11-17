extends Node
## THE BAG'S DOLL, SHOT (W3; windowed, no server): "$GODOT" --path . res://game/regents/tests/bag_doll_shot.tscn -- <out dir>
## A bag with an iron cuirass worn (quality 50%), a fine helm, a steel cuirass, linen trousers and an axe: `doll.png` with
## the steel cuirass picked (its words and Wear); `doll_tooltip.png` with the mouse over the doll's chest (its tooltip).

func _ready() -> void:
	var dir: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://doll_shot"
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().size = Vector2i(1280, 720)
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.4, 0.3)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(bg)
	var inv := SpaceTimeInventoryComponent.new()
	add_child(inv)
	var ids: Array[Array] = [["iron_cuirass", 500], ["steel_armet", 800], ["steel_cuirass", 300], ["linen_trousers", -1], ["copper_axe", -1]]
	for i: int in ids.size():
		var it: ItemDef = load("res://game/regents/content/item/%s.tres" % String(ids[i][0])) as ItemDef
		var data: String = JSON.stringify({"q": int(ids[i][1])}) if int(ids[i][1]) >= 0 else ""
		inv._stacks[i + 1] = SpaceTimeInventoryComponent.Stack.new(i + 1, it.id if it != null else 40001, 1, 0, data)
	var armor := ArmorLookComponent.new()
	add_child(armor)
	armor.rows[&"chest"] = 1
	var cc := CombatComponent.new()
	add_child(cc)
	var bag := RegentsBagWindow.new()
	bag.inventory = inv
	bag.combat = cc
	bag.armor = armor
	layer.add_child(bag)
	bag.picked_row = 3
	bag.open()
	for i: int in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("doll.png"))
	print("saved ", dir.path_join("doll.png"))
	var chest: Control = bag.find_child("Doll_chest", true, false) as Control
	get_viewport().warp_mouse(chest.get_global_rect().get_center())
	var move := InputEventMouseMotion.new()
	move.position = chest.get_global_rect().get_center()
	move.global_position = move.position
	get_viewport().push_input(move)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("doll_tooltip.png"))
	print("saved ", dir.path_join("doll_tooltip.png"), " tooltip: ", chest.tooltip_text.replace("\n", " | "))
	AppExit.quit(get_tree(), 0)
