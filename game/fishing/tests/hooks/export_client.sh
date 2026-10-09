# FISHING'S PART OF tests/export_test.sh ($CPCK is the client's pack, count/check its helpers), sourced there by run_genre_hooks (it sees the suite's helpers).

check "$([ "$(count $CPCK '^game/fishing/sfx/[a-z_]+\.wav\.import$')" -ge 12 ] && echo true || echo false)" \
  "and the game's sounds"
# THE LAKESIDE. Its bake is how the client knows water from land (the aim ring), read as plain
# files: the JSON is a resource and travels on its own, the depth grid is not and needs the
# include filter. A client without it draws every cast as dry land.
check "$([ "$(count $CPCK '^game/world/lakeside\.tscn')" -ge 1 ] && echo true || echo false)" \
  "the lakeside level is in the client"
check "$([ "$(count $CPCK '^shared/world/lakeside\.json$')" = "1" ] && [ "$(count $CPCK '^shared/world/lakeside_depth\.bin$')" = "1" ] && echo true || echo false)" \
  "with its bake: the JSON and the depth grid"
check "$([ "$(count $CPCK '^shared/fishing/fishing\.json$')" = "1" ] && echo true || echo false)" \
  "and the fishing content the HUD names catches and gear from"
check "$([ "$(count $CPCK '^game/characters/looks/[a-z_]+\.tscn')" -ge 9 ] && echo true || echo false)" \
  "and every character look"
# A friend's build must know which version it is (DECISIONS #164) and what the game is made of (#173).
check "$([ "$(count $CPCK '^spacetime_bindings/schema_fingerprint\.json$')" = "1" ] && echo true || echo false)" \
  "the bindings' schema fingerprint is in the client (the version check)"
check "$([ "$(count $CPCK '^shared/game\.json$')" = "1" ] && [ "$(count $CPCK '^game/fishing/genre\.tres')" -ge 1 ] && echo true || echo false)" \
  "and the game's genres: shared/game.json and fishing's genre.tres"
check "$([ "$(count $CPCK '^shared/world/meadow\.json$')" = "1" ] && [ "$(count $CPCK '^shared/world/meadow_depth\.bin$')" = "1" ] && echo true || echo false)" \
  "and the meadow's bake, the level built in the editor"
# The Nature kit's leaves are drawn by a shader that INCLUDES another file (#141). A shader that
# cannot find its include compiles to nothing, and a headless run never compiles one — so the
# only place a missing include shows is here, in the pack.
check "$([ "$(count $CPCK '^game/world/kits/nature_foliage(_opaque)?\.gdshader$')" = "2" ] && [ "$(count $CPCK '^game/world/kits/nature_foliage\.gdshaderinc$')" = "1" ] && echo true || echo false)" \
  "and the foliage shaders, with the file they include"
