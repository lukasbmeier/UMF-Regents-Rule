extends SceneTree
## Prints this project's `user://` as an OS path, for shell harnesses that need to reset a saved
## file before a run. `godot --headless --path . -s res://tools/print_user_dir.gd`


func _init() -> void:
	print("USER_DIR=", ProjectSettings.globalize_path("user://"))
	quit()
