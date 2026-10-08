@tool
extends EditorPlugin
## KEEPS EDITOR TOOLING OUT OF THE BUILDS (REVIEW 0.23.1 B4). Both export presets exclude
## `addons/godot_ai/*` (the MCP bridge: it can compile and run code it is sent, and no player needs
## it), but that addon registers an AUTOLOAD, and an exported game whose autoload's script is not
## in the pack fails to start it and logs an error. This plugin takes those autoloads out of the
## project settings for the length of an export and puts them back after it; `tests/export_test.sh`
## proves the builds carry neither the files nor the error.
##
## Add an autoload to `EDITOR_ONLY_AUTOLOADS` when an editor addon brings another one.

const EDITOR_ONLY_AUTOLOADS: PackedStringArray = ["_mcp_game_helper"]

var _export: UmfExport = null


func _enter_tree() -> void:
	_export = UmfExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class UmfExport extends EditorExportPlugin:
	## What was taken out, to put back: setting name -> value, and its place in the boot order
	## (autoloads start in the order project.godot lists them).
	var _held: Dictionary[String, Variant] = {}
	var _order: Dictionary[String, int] = {}

	func _get_name() -> String:
		return "UmfExport"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		_held.clear()
		_order.clear()
		for name: String in EDITOR_ONLY_AUTOLOADS:
			var key: String = "autoload/" + name
			if ProjectSettings.has_setting(key):
				_held[key] = ProjectSettings.get_setting(key)
				_order[key] = ProjectSettings.get_order(key)
				ProjectSettings.set_setting(key, null)

	func _export_end() -> void:
		for key: String in _held:
			ProjectSettings.set_setting(key, _held[key])
			ProjectSettings.set_order(key, _order[key])
		_held.clear()
		_order.clear()
