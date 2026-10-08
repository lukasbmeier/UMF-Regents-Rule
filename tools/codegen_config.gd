extends SceneTree
## Writes addons/SpacetimeDB/plugin_config.tres so headless codegen (cli.gd) has
## the module/alias/URI it normally gets from the editor dock.
##   godot --headless --path . -s tools/codegen_config.gd

const CFG_SCRIPT: String = "res://addons/SpacetimeDB/core_types/plugin_config.gd"
const MOD_SCRIPT: String = "res://addons/SpacetimeDB/core_types/module_config.gd"
const SAVE_PATH: String = "res://addons/SpacetimeDB/plugin_config.tres"

const MODULE_NAME: String = "umf"
const MODULE_ALIAS: String = "Umf"
const SERVER_URI: String = "http://127.0.0.1:3000"


func _initialize() -> void:
	var cfg_script: GDScript = load(CFG_SCRIPT) as GDScript
	var mod_script: GDScript = load(MOD_SCRIPT) as GDScript
	if cfg_script == null or mod_script == null:
		printerr("addon scripts did not load")
		quit(1)
		return

	var cfg: Resource = cfg_script.new()
	cfg.autoload_name = "SpacetimeDB"
	cfg.uri = SERVER_URI

	var mod: Resource = mod_script.new()
	mod.name = MODULE_NAME
	mod.alias = MODULE_ALIAS
	cfg.module_configs[MODULE_NAME] = mod

	var err: Error = ResourceSaver.save(cfg, SAVE_PATH)
	if err != OK:
		printerr("save failed: %s" % [error_string(err)])
		quit(1)
		return
	print("wrote %s (module=%s alias=%s uri=%s)" % [SAVE_PATH, MODULE_NAME, MODULE_ALIAS, SERVER_URI])
	quit(0)
