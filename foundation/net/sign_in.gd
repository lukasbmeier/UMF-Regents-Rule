class_name SignIn extends Node
## SIGNING IN FROM A DESKTOP GAME (template 1.0, DECISIONS #278, `docs/TEMPLATE_1_0.md` §6.2). The game's
## sign-in service (`shared/game.json` `sign_in`: SpacetimeAuth unless it says otherwise) is an OpenID
## Connect issuer. `start()` opens the player's browser on its page (Discord, Google, an email link: what
## the service offers), with PKCE (no secret in the game), and listens on 127.0.0.1 for the answer; the
## code is swapped for an ID TOKEN, which the game connects with (`SpaceTimeSync.sign_in_token`), and a
## REFRESH token, kept in the user folder beside the identity's token file, so the next launch signs in
## silently (`resume()`). `forget()` signs out. The module decides what a sign-in is worth (an account,
## `module/accounts.rs`); nothing here is trusted by the server beyond the token itself.
##
## Not proved by the suites against SpacetimeAuth itself (they use `tests/lib/oidc_issuer.py`): its
## client must list the redirect `http://127.0.0.1:<redirect_port>/callback` (§2 of the plan).

signal signed_in(id_token: String)
signal failed(reason: String)

const SCOPES: String = "openid profile email offline_access"
const DEFAULT_ISSUER: String = "https://auth.spacetimedb.com/oidc"
const DEFAULT_PORT: int = 53682
## How long the browser may take before the sign-in gives up, s.
const WAIT_SEC: float = 300.0

## The service, this game's client id there, and the port its answer comes back to.
var issuer: String = DEFAULT_ISSUER
var client_id: String = ""
var redirect_port: int = DEFAULT_PORT
## Where the refresh token is kept (one per identity slot).
var store_path: String = "user://sign_in.cfg"
## How a URL is opened: the player's browser. A test drives the page itself.
var open_url: Callable = func(url: String) -> void: OS.shell_open(url)

var _tcp: TCPServer = null
var _peer: StreamPeerTCP = null
var _verifier: String = ""
var _state: String = ""
var _token_endpoint: String = ""
var _waited: float = 0.0
var _buffer: String = ""


func _init() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://shared/game.json"))
	var s: Variant = (doc as Dictionary).get("sign_in", {}) if doc is Dictionary else {}
	if s is Dictionary:
		var d: Dictionary = s as Dictionary
		issuer = str(d.get("issuer", DEFAULT_ISSUER)).strip_edges().trim_suffix("/")
		client_id = str(d.get("client_id", ""))
		redirect_port = int(d.get("redirect_port", DEFAULT_PORT))
	if SpaceTimeSync.config != null and not SpaceTimeSync.config.token_path.is_empty():
		store_path = SpaceTimeSync.config.token_path.get_basename() + ".sign_in.cfg"


## Whether this game can sign in at all (it names a client id at its service).
func configured() -> bool:
	return not client_id.is_empty() and not issuer.is_empty()


## Whether a sign-in is kept from before (a refresh token for this service).
func remembered() -> bool:
	var cf := ConfigFile.new()
	return cf.load(store_path) == OK and str(cf.get_value("sign_in", "issuer", "")) == issuer \
		and not str(cf.get_value("sign_in", "refresh_token", "")).is_empty()


## Sign out: the kept refresh token goes (the service's own session in the browser is the browser's).
func forget() -> void:
	if FileAccess.file_exists(store_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store_path))


## Sign in with the browser. `hint`: who is expected (the service may prefill it). Emits `signed_in`
## or `failed`.
func start(hint: String = "") -> void:
	stop()
	var conf: Dictionary = await _discover()
	if conf.is_empty():
		return
	_token_endpoint = str(conf.get("token_endpoint", ""))
	_verifier = _random(32)
	_state = _random(16)
	_tcp = TCPServer.new()
	var err: Error = _tcp.listen(redirect_port, "127.0.0.1")
	if err != OK:
		_tcp = null
		failed.emit("cannot listen for the answer on 127.0.0.1:%d (%s)" % [redirect_port, error_string(err)])
		return
	var q: Dictionary = {
		"response_type": "code", "client_id": client_id, "redirect_uri": redirect_uri(),
		"scope": SCOPES, "state": _state, "code_challenge": challenge_of(_verifier),
		"code_challenge_method": "S256", "prompt": "consent",
	}
	if not hint.is_empty():
		q["login_hint"] = hint
	_waited = 0.0
	set_process(true)
	open_url.call(str(conf.get("authorization_endpoint", "")) + "?" + _query(q))


## Sign in silently with the kept refresh token. Emits `signed_in`, or `failed` (sign in again).
func resume() -> void:
	var cf := ConfigFile.new()
	if cf.load(store_path) != OK:
		failed.emit("not signed in on this machine")
		return
	var conf: Dictionary = await _discover()
	if conf.is_empty():
		return
	_token_endpoint = str(conf.get("token_endpoint", ""))
	await _swap({"grant_type": "refresh_token", "refresh_token": str(cf.get_value("sign_in", "refresh_token", "")),
		"client_id": client_id})


## Stop listening for an answer (the player closed the sign-in, or it timed out).
func stop() -> void:
	set_process(false)
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _tcp != null:
		_tcp.stop()
		_tcp = null
	_buffer = ""


func redirect_uri() -> String:
	return "http://127.0.0.1:%d/callback" % redirect_port


## PKCE (RFC 7636): the challenge sent with the request is the SHA-256 of the verifier kept here.
static func challenge_of(verifier: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(verifier.to_utf8_buffer())
	return _b64u(h.finish())


## A link code (`module/accounts.rs` `LINK_ALPHABET`), from this machine's own random source: the
## module's is seeded from the clock and cannot make a secret.
static func new_link_code() -> String:
	const ALPHABET: String = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	var out: String = ""
	for b: int in bytes:
		out += ALPHABET[b % ALPHABET.length()]
	return out


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	_waited += delta
	if _waited > WAIT_SEC:
		stop()
		failed.emit("the sign-in took too long; try again")
		return
	if _tcp == null:
		return
	if _peer == null and _tcp.is_connection_available():
		_peer = _tcp.take_connection()
		_buffer = ""
	if _peer == null:
		return
	_peer.poll()
	var n: int = _peer.get_available_bytes()
	if n > 0:
		_buffer += _peer.get_utf8_string(n)
	if not _buffer.contains("\r\n"):
		return
	var line: String = _buffer.get_slice("\r\n", 0)
	var target: String = line.get_slice(" ", 1)
	var q: Dictionary = _parse_query(target.get_slice("?", 1) if target.contains("?") else "")
	var good: bool = target.begins_with("/callback") and str(q.get("state", "")) == _state and q.has("code")
	var page: String = "<html><body style='font-family:sans-serif'><h2>%s</h2><p>You can close this tab and go back to the game.</p></body></html>" \
		% ("Signed in." if good else "The sign-in did not work.")
	_peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
		% [page.to_utf8_buffer().size(), page]).to_utf8_buffer())
	var code: String = str(q.get("code", ""))
	var error: String = str(q.get("error_description", q.get("error", "")))
	stop()
	if not good:
		failed.emit("the sign-in was not completed%s" % ((": " + error) if not error.is_empty() else ""))
		return
	await _swap({"grant_type": "authorization_code", "code": code, "redirect_uri": redirect_uri(),
		"client_id": client_id, "code_verifier": _verifier})


func _discover() -> Dictionary:
	var res: Array = await _http(issuer + "/.well-known/openid-configuration", HTTPClient.METHOD_GET, "")
	var doc: Variant = JSON.parse_string(str(res[1])) if int(res[0]) == 200 else null
	if not doc is Dictionary or not (doc as Dictionary).has("authorization_endpoint"):
		failed.emit("the sign-in service at %s did not answer (%d)" % [issuer, int(res[0])])
		return {}
	return doc as Dictionary


func _swap(form: Dictionary) -> void:
	var res: Array = await _http(_token_endpoint, HTTPClient.METHOD_POST, _query(form))
	var doc: Variant = JSON.parse_string(str(res[1])) if not str(res[1]).is_empty() else null
	if int(res[0]) != 200 or not doc is Dictionary or str((doc as Dictionary).get("id_token", "")).is_empty():
		var why: String = str((doc as Dictionary).get("error_description", (doc as Dictionary).get("error", ""))) if doc is Dictionary else ""
		if form.get("grant_type") == "refresh_token":
			forget()   # a refresh token the service no longer takes: sign in again
		failed.emit("the sign-in service refused it (%d%s)" % [int(res[0]), (": " + why) if not why.is_empty() else ""])
		return
	var d: Dictionary = doc as Dictionary
	var refresh: String = str(d.get("refresh_token", ""))
	if not refresh.is_empty():
		var cf := ConfigFile.new()
		cf.set_value("sign_in", "issuer", issuer)
		cf.set_value("sign_in", "refresh_token", refresh)
		cf.save(store_path)
	signed_in.emit(str(d["id_token"]))


## [status, body] of one request.
func _http(url: String, method: HTTPClient.Method, body: String) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var headers: PackedStringArray = ["Accept: application/json"]
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/x-www-form-urlencoded")
	var err: Error = req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		return [0, ""]
	var r: Array = await req.request_completed
	req.queue_free()
	return [int(r[1]), (r[3] as PackedByteArray).get_string_from_utf8()]


static func _random(n: int) -> String:
	return _b64u(Crypto.new().generate_random_bytes(n))


static func _b64u(b: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(b).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")


static func _query(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: Variant in d:
		parts.append("%s=%s" % [str(k).uri_encode(), str(d[k]).uri_encode()])
	return "&".join(parts)


static func _parse_query(q: String) -> Dictionary:
	var out: Dictionary = {}
	for part: String in q.split("&", false):
		var kv: PackedStringArray = part.split("=", true, 1)
		out[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else ""
	return out
