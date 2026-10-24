extends Node
## A REAL CLIENT SIGNS IN (template 1.0, DECISIONS #278): driven by tests/accounts_test.sh with Boot's
## sign-in flags. Boot signs in (the browser's part played in-process, against the suites' issuer, or
## silently with the refresh token kept from the run before), connects with the ID token, and this waits
## for its player and prints it for the shell to look up: `SIGNED_IN entity=<id> name=<name>`.

const TIMEOUT_SEC: float = 60.0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var deadline: int = Time.get_ticks_msec() + int(TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline and EntityRegistry.local_entity_id < 0:
		await get_tree().process_frame
	if EntityRegistry.local_entity_id < 0:
		printerr("  FAIL: no player within %.0f s (signed in: %s)" % [TIMEOUT_SEC, not SpaceTimeSync.sign_in_token.is_empty()])
		AppExit.quit(get_tree(), 1)
		return
	var signed: bool = not SpaceTimeSync.sign_in_token.is_empty()
	print("SIGNED_IN entity=%d signed=%s" % [EntityRegistry.local_entity_id, signed])
	# Leave cleanly, so the server sees the connection go (the next run is a sign-in coming back).
	await get_tree().create_timer(0.5).timeout
	AppExit.quit(get_tree(), 0)
