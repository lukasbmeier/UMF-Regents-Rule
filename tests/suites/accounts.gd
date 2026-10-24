extends "res://tests/suite_base.gd"
## The `accounts` suite (template 1.0, DECISIONS #278): the client's half of signing in, without a
## server. The sign-in end to end (a real client, the suites' issuer, the server's accounts) is
## tests/accounts_test.sh.


func run() -> void:
	_run_accounts_tests()
	await get_tree().process_frame


func _run_accounts_tests() -> void:
	print("== SignIn and the Account page ==")
	# PKCE as RFC 7636 appendix B works it: a service that disagrees refuses every sign-in.
	_check(SignIn.challenge_of("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
		"the PKCE challenge is RFC 7636's own example")
	var codes: Dictionary[String, bool] = {}
	var bad: Array[String] = []
	for i: int in range(200):
		var c: String = SignIn.new_link_code()
		codes[c] = true
		if c.length() != 8:
			bad.append(c)
		for ch: String in c:
			if not "ABCDEFGHJKMNPQRSTUVWXYZ23456789".contains(ch):
				bad.append(c)
	_check(bad.is_empty(), "a link code is 8 of the module's letters (no 0, O, 1, I, L) %s" % str(bad.slice(0, 3)))
	_check(codes.size() >= 199, "and never the same twice in 200 (%d)" % codes.size())

	var si := SignIn.new()
	_check(si.issuer == "https://auth.spacetimedb.com/oidc", "the template signs in with SpacetimeAuth unless the game says otherwise (%s)" % si.issuer)
	_check(not si.configured(), "and offers no sign-in until the game names its client id there (shared/game.json sign_in)")
	_check(si.redirect_uri() == "http://127.0.0.1:53682/callback", "the answer comes back to 127.0.0.1 (%s)" % si.redirect_uri())
	si.store_path = "user://accounts_suite.sign_in.cfg"
	si.forget()
	_check(not si.remembered(), "nothing kept: not signed in on this machine")
	var cf := ConfigFile.new()
	cf.set_value("sign_in", "issuer", si.issuer)
	cf.set_value("sign_in", "refresh_token", "rt")
	cf.save(si.store_path)
	_check(si.remembered(), "a kept refresh token for this service: signed in")
	si.issuer = "https://another.example"
	_check(not si.remembered(), "another service's is not this one's")
	si.forget()
	si.free()

	var page := AccountPage.new()
	add_child(page)
	page.open()
	_check(not page.is_signed_in() and page._sign.visible == false and page._code_in.get_parent().visible,
		"a guest sees how to join an account, and no sign-in when the game has none")
	page.can_sign_in = true
	page.refresh()
	_check(page._sign.visible and page._sign.text == "Sign in" and not page._new.visible and not page._show_code.visible,
		"with one: Sign in; no characters to make nor codes to show until signed in")
	page.close()
	page.free()
