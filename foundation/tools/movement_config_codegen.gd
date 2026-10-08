@tool
extends EditorScript
## OPTIONAL. The client reads shared/movement_config.json directly (MovementConfig.shared()),
## and the Rust side bakes the same file in via build.rs, so neither needs this. Run it (File >
## Run) only to get a .tres snapshot a scene can assign to a specific entity's movement
## component — which is deliberately a SECOND source of truth, so prefer not to.

const SOURCE: String = "res://shared/movement_config.json"
const TARGET: String = "res://foundation/sim/movement_config.tres"

func _run() -> void:
	var cfg: MovementConfig = MovementConfig.from_json_file(SOURCE)
	cfg.resource_path = TARGET
	var err: Error = ResourceSaver.save(cfg, TARGET)
	if err != OK:
		push_error("movement_config_codegen: save failed (%s)" % error_string(err))
	else:
		print("movement_config_codegen: wrote ", TARGET)
