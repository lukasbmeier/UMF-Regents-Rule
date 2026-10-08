# addons/

Vendor the SpacetimeDB GDScript SDK here (plaught-armor, Godot 4.6+, SpacetimeDB 2.2+).

1. AssetLib → "SpacetimeDB Godot SDK" → Install, or extract a GitHub release zip at the project root.
   Commit `addons/SpacetimeDB/` — never depend on a live download.
2. Project → Project Settings → Plugins → enable **SpacetimeDB**. Restart the editor.
3. Publish the Rust module, then in the SpacetimeDB bottom dock: set the server URL, Check URI,
   add module `umf` with alias **`Umf`** (must match `NetConfig.module_alias`), Generate schema.
   Output: `res://spacetime_bindings/`. Commit it.
4. The editor registers the `SpacetimeDB` autoload (`spacetime_bindings/schema/spacetime_autoload.gd`).
   Open Project Settings → Autoload and **drag it to the top** so it precedes `SpaceTimeSync`. Commit
   `project.godot` and `addons/SpacetimeDB/plugin_config.tres`.

Headless regeneration (CI):
```
godot --headless --path client --import
godot --headless --path client --script res://addons/SpacetimeDB/cli.gd
```

Nothing outside `foundation/net/spacetime_sync.gd` may reference the SDK, the `SpacetimeDB` autoload,
or `spacetime_bindings/`. `tests/run_tests.sh` greps for violations.
