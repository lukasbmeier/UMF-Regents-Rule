"""TIMED CALLS for the integration suite's referee checks (Regent's Rule, 2026-11-04).

A `spacetime call` takes 0.5 to 3 s to start on Windows, so a check that needs things a set time apart
(an overhead, then Cleave inside its hold; a roll inside its wind-up; a missile's hit reported inside its
3 s life) raced the CLI and failed on a busy machine. This sends them over ONE kept-alive HTTP connection,
each a set time after the last was SENT, with the CLI's own token (the same player the CLI is).

    python timed_calls.py <database> <token> < steps

Each line of the steps, `<ms after the last>` then one of:
  - `<reducer> <args as a JSON array>`: prints `<reducer> ok <ms>` or `<reducer> error <ms> <the server's words>`
  - `sql <NAME> <query>`: the largest value of the first column (a timestamp as its microseconds), or `-` for no
    rows; prints `sql <NAME> <value> <ms>`
  - `sqlwait <NAME> <query>`: the same, asked again every 50 ms until a row comes (4 s at most)
A later step's text may hold `{NAME}`: the value a sql step found.
UMF_HTTP: the server (default http://127.0.0.1:3000).
"""
import http.client
import json
import os
import sys
import time
import urllib.parse

WAIT_S = 4.0


def value_of(v: object) -> str:
    if isinstance(v, dict) and len(v) == 1:
        v = next(iter(v.values()))   # a timestamp, an identity: its one field
    elif isinstance(v, list) and len(v) == 1:
        v = v[0]                     # (the server sends a timestamp as a one-field list)
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def main() -> int:
    db, token = sys.argv[1], sys.argv[2]
    url = urllib.parse.urlparse(os.environ.get("UMF_HTTP", "http://127.0.0.1:3000"))
    steps = []
    for line in sys.stdin:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        delay, rest = line.split(" ", 1)
        steps.append((int(delay), rest))
    conn = http.client.HTTPConnection(url.hostname, url.port or 80, timeout=10)
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    found: dict[str, str] = {}

    def post(path: str, body: str) -> tuple[int, str]:
        conn.request("POST", "/v1/database/%s/%s" % (db, path), body=body.encode("utf-8"), headers=headers)
        resp = conn.getresponse()
        return resp.status, resp.read().decode("utf-8", "replace").strip()

    def query(sql: str) -> str:
        status, body = post("sql", sql)
        if not 200 <= status < 300:
            return "error:" + body.replace("\n", " ")
        rows = [r for table in json.loads(body) for r in table.get("rows", [])]
        if not rows:
            return "-"
        vals = [value_of(r[0]) for r in rows]
        try:
            return max(vals, key=lambda s: float(s))
        except ValueError:
            return vals[0]

    start = time.perf_counter()
    last = start
    for delay, rest in steps:
        for name, val in found.items():
            rest = rest.replace("{%s}" % name, val)
        time.sleep(max(0.0, last + delay / 1000.0 - time.perf_counter()))
        last = time.perf_counter()
        at = int((last - start) * 1000)
        verb, tail = rest.split(" ", 1)
        if verb in ("sql", "sqlwait"):
            name, sql = tail.split(" ", 1)
            val = query(sql)
            while verb == "sqlwait" and val == "-" and time.perf_counter() - last < WAIT_S:
                time.sleep(0.05)
                val = query(sql)
            found[name] = val
            print("sql %s %s %d" % (name, val, at))
        else:
            try:
                json.loads(tail)
            except ValueError:   # (a sql step that found nothing, put into a call)
                print("%s error %d not sent: its arguments are not JSON: %s" % (verb, at, tail))
                sys.stdout.flush()
                continue
            status, body = post("call/" + verb, tail)
            if 200 <= status < 300:
                print("%s ok %d" % (verb, at))
            else:
                print("%s error %d %s" % (verb, at, body.replace("\n", " ") or status))
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
