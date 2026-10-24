"""A LOCAL SIGN-IN SERVICE FOR THE SUITES (template 1.0, DECISIONS #278). SpacetimeAuth is an OpenID
Connect issuer on the internet; the suites prove sign-in, accounts and link codes without it, against
this: an issuer on 127.0.0.1 that the TEST database is told to trust (`trust_issuer`), never a database
anyone plays in. Python's standard library only (the RSA is done by hand, as the chronicle needs nothing
installed either).

    python tests/lib/oidc_issuer.py serve --port 8765 --dir build/test_issuer
        the issuer: its discovery document and keys (what SpacetimeDB fetches to check a token), an
        /authorize that says yes at once (to the user named by login_hint) and a /token that swaps the
        code (PKCE checked) or a refresh token for an ID token: the desktop sign-in, end to end.
    python tests/lib/oidc_issuer.py mint --dir build/test_issuer --sub alice [--aud umf-test] [--exp 3600]
        prints an ID token signed with the same key, for a shell suite's curl calls. --exp -120: one
        that ran out two minutes ago.

The key is made on first `serve` (2048-bit, a few seconds) and kept in --dir/key.json, so `mint`
signs with what the running issuer publishes.
"""

import argparse
import base64
import hashlib
import json
import os
import secrets
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KID = "umf-test"
SMALL_PRIMES = [p for p in range(3, 2000, 2) if all(p % q for q in range(3, int(p ** 0.5) + 1, 2))]


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _int_bytes(n: int) -> bytes:
    return n.to_bytes((n.bit_length() + 7) // 8, "big")


def _probable_prime(n: int) -> bool:
    for p in SMALL_PRIMES:
        if n % p == 0:
            return n == p
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(40):
        a = secrets.randbelow(n - 3) + 2
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def _prime(bits: int) -> int:
    while True:
        c = secrets.randbits(bits) | (1 << (bits - 1)) | (1 << (bits - 2)) | 1
        if _probable_prime(c):
            return c


def make_key(bits: int = 2048) -> dict:
    e = 65537
    while True:
        p, q = _prime(bits // 2), _prime(bits // 2)
        phi = (p - 1) * (q - 1)
        if p != q and phi % e:
            break
    return {"n": p * q, "e": e, "d": pow(e, -1, phi)}


def load_key(folder: str) -> dict:
    path = os.path.join(folder, "key.json")
    if os.path.exists(path):
        k = json.load(open(path, encoding="utf-8"))
        return {"n": int(k["n"]), "e": int(k["e"]), "d": int(k["d"])}
    os.makedirs(folder, exist_ok=True)
    k = make_key()
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"n": str(k["n"]), "e": str(k["e"]), "d": str(k["d"])}, f)
    return k


# DigestInfo for SHA-256 (RFC 8017 9.2): what PKCS #1 v1.5 signs.
SHA256_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


def sign_jwt(key: dict, claims: dict) -> str:
    header = {"alg": "RS256", "typ": "JWT", "kid": KID}
    signing = _b64u(json.dumps(header, separators=(",", ":")).encode()) + "." + \
        _b64u(json.dumps(claims, separators=(",", ":")).encode())
    t = SHA256_PREFIX + hashlib.sha256(signing.encode()).digest()
    k = (key["n"].bit_length() + 7) // 8
    em = b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t
    sig = pow(int.from_bytes(em, "big"), key["d"], key["n"]).to_bytes(k, "big")
    return signing + "." + _b64u(sig)


def id_token(key: dict, issuer: str, sub: str, aud: str, exp_s: int) -> str:
    now = int(time.time())
    return sign_jwt(key, {"iss": issuer, "sub": sub, "aud": aud, "iat": now, "exp": now + exp_s,
                          "preferred_username": sub, "login_method": "test"})


def serve(port: int, folder: str) -> None:
    key = load_key(folder)
    issuer = f"http://127.0.0.1:{port}"
    codes: dict = {}      # code -> {sub, aud, challenge, redirect}
    refresh: dict = {}    # refresh token -> {sub, aud}
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            sys.stderr.write("[issuer] " + fmt % args + "\n")

        def _json(self, code: int, body: dict) -> None:
            raw = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            u = urllib.parse.urlparse(self.path)
            q = dict(urllib.parse.parse_qsl(u.query))
            if u.path == "/.well-known/openid-configuration":
                return self._json(200, {
                    "issuer": issuer, "jwks_uri": issuer + "/jwks",
                    "authorization_endpoint": issuer + "/authorize", "token_endpoint": issuer + "/token",
                    "response_types_supported": ["code"], "subject_types_supported": ["public"],
                    "id_token_signing_alg_values_supported": ["RS256"],
                    "code_challenge_methods_supported": ["S256"],
                    "grant_types_supported": ["authorization_code", "refresh_token"],
                })
            if u.path == "/jwks":
                return self._json(200, {"keys": [{"kty": "RSA", "kid": KID, "use": "sig", "alg": "RS256",
                                                  "n": _b64u(_int_bytes(key["n"])), "e": _b64u(_int_bytes(key["e"]))}]})
            if u.path == "/authorize":
                if q.get("code_challenge_method") != "S256" or not q.get("code_challenge") or not q.get("redirect_uri"):
                    return self._json(400, {"error": "invalid_request", "error_description": "PKCE S256 and a redirect_uri, please"})
                code = secrets.token_urlsafe(16)
                with lock:
                    codes[code] = {"sub": q.get("login_hint") or "tester", "aud": q.get("client_id", ""),
                                   "challenge": q["code_challenge"], "redirect": q["redirect_uri"]}
                back = q["redirect_uri"] + ("&" if "?" in q["redirect_uri"] else "?") + \
                    urllib.parse.urlencode({"code": code, "state": q.get("state", "")})
                self.send_response(302)
                self.send_header("Location", back)
                self.end_headers()
                return
            self._json(404, {"error": "not_found"})

        def do_POST(self):
            if urllib.parse.urlparse(self.path).path != "/token":
                return self._json(404, {"error": "not_found"})
            n = int(self.headers.get("Content-Length", "0"))
            form = dict(urllib.parse.parse_qsl(self.rfile.read(n).decode()))
            with lock:
                if form.get("grant_type") == "authorization_code":
                    c = codes.pop(form.get("code", ""), None)
                    if c is None:
                        return self._json(400, {"error": "invalid_grant"})
                    verifier = form.get("code_verifier", "")
                    if _b64u(hashlib.sha256(verifier.encode()).digest()) != c["challenge"]:
                        return self._json(400, {"error": "invalid_grant", "error_description": "PKCE verifier"})
                    if form.get("redirect_uri") != c["redirect"]:
                        return self._json(400, {"error": "invalid_grant", "error_description": "redirect_uri"})
                    who = {"sub": c["sub"], "aud": c["aud"]}
                elif form.get("grant_type") == "refresh_token":
                    who = refresh.get(form.get("refresh_token", ""))
                    if who is None:
                        return self._json(400, {"error": "invalid_grant"})
                else:
                    return self._json(400, {"error": "unsupported_grant_type"})
                rt = secrets.token_urlsafe(24)
                refresh[rt] = who
            return self._json(200, {"id_token": id_token(key, issuer, who["sub"], who["aud"], 3600),
                                    "refresh_token": rt, "token_type": "Bearer", "expires_in": 3600})

    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    sys.stderr.write(f"[issuer] {issuer} ready\n")
    sys.stderr.flush()
    srv.serve_forever()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["serve", "mint"])
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--dir", default="build/test_issuer")
    ap.add_argument("--sub", default="tester")
    ap.add_argument("--aud", default="")
    ap.add_argument("--exp", type=int, default=3600)
    ap.add_argument("--issuer", default="")
    a = ap.parse_args()
    if a.mode == "serve":
        serve(a.port, a.dir)
    else:
        key = load_key(a.dir)
        print(id_token(key, a.issuer or f"http://127.0.0.1:{a.port}", a.sub, a.aud, a.exp))


if __name__ == "__main__":
    main()
