class_name ConnectSettings extends RefCounted
## Where a player's server address and display name live between sessions.
##
## Not in `NetConfig`. That is one `.tres` per ENVIRONMENT, checked into the repo and shared by
## everyone who runs the build; a host address typed by a player and their chosen name are the
## opposite of that — per install, per person, and not something a commit should carry. They go
## in `user://`, which is per machine and per user, and the shipped `.tres` stays the default
## that a fresh install falls back to.
##
## ONE FILE PER IDENTITY. The settings are a profile of "who am I on this machine", which is the
## same question the identity token answers, so they are keyed the same way: the default install
## uses `connect.cfg`, editor instance 2 uses `connect_dev2.cfg` next to its own token, and a
## `--token=<tag>` run uses `connect_<tag>.cfg`. Two editor instances therefore remember two
## names, and a test run can never overwrite what the player typed.
##
## Only the connect screen WRITES here. Command-line flags (`--host=`, `--name=`) override a
## single run and are not remembered: a script that launches the game with `--name=Test` must not
## rename the player the next time they start it by hand.
##
## A TEST SUITE KEEPS OFF THE PLAYER'S PROFILE (DECISIONS #179): a process started by one (UMF_DB
## set, #154) uses a profile named after that database too, `connect_dev1.umf-test.cfg`, so it
## remembers within its own runs and never reads what the player chose. The e2e client runs as
## editor slot 1, Luke's own slot: it announced the look he had picked, was rebuilt mid-test,
## and two suites failed on a body that had been freed under them.

const DEFAULT_PATH: String = "user://connect.cfg"
const SECTION: String = "connect"
## SpacetimeDB's own default. A bare address ("192.168.1.20") gets it; an address that names its
## scheme or port is taken as written.
const DEFAULT_PORT: int = 3000

static var _path: String = DEFAULT_PATH


## Select whose settings are read and written. `tag` is the identity tag: "" for the default
## identity, "dev2" for editor slot 2, whatever followed `--token=` otherwise.
static func use_profile(tag: String) -> void:
	var file: String = "connect" if tag.is_empty() else "connect_%s" % tag.validate_filename()
	var db: String = OS.get_environment("UMF_DB")
	if not db.is_empty():
		file += "." + db.validate_filename()
	_path = "user://%s.cfg" % file


## The file the current profile lives in. For tests and for the connect screen's help text.
static func path() -> String:
	return _path


## The saved host, or `fallback` when nothing has been saved.
static func host(fallback: String) -> String:
	return String(_read(&"host", fallback))


## The saved display name, or "" when the player has never set one.
static func player_name() -> String:
	return String(_read(&"name", ""))


## The look this player chose in the character picker (`Appearance` text), "" for none
## (DECISIONS #166). Sent on every connect, like the name.
static func appearance() -> String:
	return String(_read(&"appearance", ""))


static func save_appearance(text: String) -> void:
	_write({&"appearance": text})


## True when the player ticked "connect automatically": skip the connect screen next launch.
static func auto_connect() -> bool:
	return bool(_read(&"auto_connect", false))


## Remember all three. Called by the connect screen when the player presses Connect, so the
## next launch starts where this one did.
static func save(p_host: String, p_name: String, p_auto_connect: bool) -> void:
	_write({&"host": p_host, &"name": p_name, &"auto_connect": p_auto_connect})


## Remember only the auto-connect choice. Ticking the box is a decision in itself; it should not
## need a successful connect to stick.
static func save_auto_connect(v: bool) -> void:
	_write({&"auto_connect": v})


## What the player typed, as a URL the SDK can use — or "" if it cannot be one.
##
##   192.168.1.20            -> http://192.168.1.20:3000     bare: SpacetimeDB's default port
##   192.168.1.20:4000       -> http://192.168.1.20:4000
##   myhost.example          -> http://myhost.example:3000
##   https://db.example.com  -> https://db.example.com       named a scheme: taken as written
##   ws://host:3000          -> http://host:3000             the SDK wants the http form
##   [::1]:3000              -> http://[::1]:3000
##
## Pure, so the rules are unit-tested rather than discovered by a friend who typed an address.
static func normalize_host(text: String) -> String:
	var s: String = text.strip_edges()
	if s.is_empty():
		return ""
	var scheme: String = ""
	var sep: int = s.find("://")
	if sep >= 0:
		scheme = s.substr(0, sep).to_lower()
		s = s.substr(sep + 3)
		match scheme:
			"http", "https":
				pass
			"ws":
				scheme = "http"
			"wss":
				scheme = "https"
			_:
				return ""
	# A path after the host is never part of a SpacetimeDB address; a trailing slash is common
	# when pasting one from a browser.
	var slash: int = s.find("/")
	if slash >= 0:
		if not s.substr(slash).strip_edges().trim_suffix("/").is_empty():
			return ""
		s = s.substr(0, slash)
	if s.is_empty() or s.contains(" ") or s.contains("@"):
		return ""

	var host_part: String = s
	var port_part: String = ""
	if s.begins_with("["):
		# IPv6 literal: the port, if any, follows the closing bracket.
		var close: int = s.find("]")
		if close < 0:
			return ""
		host_part = s.substr(0, close + 1)
		var rest: String = s.substr(close + 1)
		if not rest.is_empty():
			if not rest.begins_with(":"):
				return ""
			port_part = rest.substr(1)
	else:
		var colon: int = s.rfind(":")
		if colon >= 0:
			host_part = s.substr(0, colon)
			port_part = s.substr(colon + 1)
			if host_part.contains(":"):
				return ""   # an unbracketed IPv6 address cannot carry a port unambiguously
	if host_part.is_empty() or host_part == "[]":
		return ""
	if not port_part.is_empty():
		if not port_part.is_valid_int() or int(port_part) < 1 or int(port_part) > 65535:
			return ""

	if scheme.is_empty():
		# Bare address: this is somebody's SpacetimeDB, which listens on 3000 unless told not to.
		scheme = "http"
		if port_part.is_empty():
			port_part = str(DEFAULT_PORT)
	return "%s://%s%s" % [scheme, host_part, "" if port_part.is_empty() else ":" + port_part]


static func _write(values: Dictionary[StringName, Variant]) -> void:
	var cfg := ConfigFile.new()
	# Load first: writing one value must not drop the others.
	cfg.load(_path)
	for key: StringName in values:
		cfg.set_value(SECTION, String(key), values[key])
	var err: int = cfg.save(_path)
	if err != OK:
		# Not fatal — the game still runs, it just forgets. Say so rather than failing silently,
		# because "it forgot my server again" is otherwise impossible to diagnose.
		push_warning("ConnectSettings: could not save %s (%s)" % [_path, error_string(err)])


static func _read(key: StringName, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return fallback
	return cfg.get_value(SECTION, String(key), fallback)
