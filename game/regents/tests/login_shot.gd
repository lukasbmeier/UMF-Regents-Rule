extends Node
## THE LOGIN SCREEN, SHOT (2026-11-15; windowed, no server): Regent's Rule's front door over the live valley, as its
## title card (the name and one Play button: Luke, 2026-11-15, the composers' film shows no form), or with `form` the
## form open. Saves `<out>/login.png` after it settles, then quits; with `seconds` it runs that long first (for the
## movie writer: the drifting picture).
##   godot --path . --resolution 1920x1080 res://game/regents/tests/login_shot.tscn -- <out dir> [seconds] [form]

const LOGIN: PackedScene = preload("res://game/regents/ui/login/regents_login.tscn")


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://"
	var seconds: float = float(args[1]) if args.size() > 1 else 2.5
	var screen: RegentsLogin = LOGIN.instantiate() as RegentsLogin
	screen.title_card = not (args.size() > 2 and args[2] == "form")
	add_child(screen)
	screen.open("", "", false)
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var file: String = out_dir.path_join("login.png")
	get_viewport().get_texture().get_image().save_png(file)
	print("[shot] %s" % file)
	AppExit.quit(get_tree(), 0)
