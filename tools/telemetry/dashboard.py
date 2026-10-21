"""THE TELEMETRY PAGE (DECISIONS #276): the chronicle's file, as charts in your browser, live.

    python tools/telemetry/dashboard.py [--db NAME] [--file PATH] [--port 8765] [--no-open] [--no-record]
    tools\\telemetry.cmd                      (Windows: double-click it on the machine that hosts)

Opens http://127.0.0.1:8765: players online, where they were (a heatmap per level), who played, frame rate
and ping, chat and feedback, what the chronicle kept, and each genre's own panels; for the last hour, day,
week or all of it, everyone or one player; it refreshes itself while the game runs. The panels are data:
shared/telemetry.json and shared/<genre>/telemetry.json (SQL over the chronicle's tables; see
tools/telemetry/chronicle.py). A panel whose SQL fails shows its error in its own card.

When nothing is recording the database (no host, no editor run), this records it too while the page's
window is open (--no-record: only read). Only this machine can open the page (127.0.0.1). Standard
library only.
"""
import argparse
import http.server
import json
import pathlib
import sqlite3
import sys
import threading
import time
import urllib.parse
import webbrowser

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import chronicle  # noqa: E402

PAGE = pathlib.Path(__file__).resolve().parent / "page.html"
RANGES = {"hour": (3600, 60), "day": (86400, 900), "week": (7 * 86400, 3600), "all": (None, None)}
DEFAULT_CELL_M = 4.0


def window(conn, rng, now):
    """(since, bucket) for a range name: the last hour by the minute, the day by the quarter hour, the week
    by the hour; all of it in about two hundred steps."""
    span, bucket = RANGES.get(rng, RANGES["day"])
    if span is not None:
        return now - span, bucket
    first = conn.execute("SELECT MIN(at) FROM change").fetchone()[0] or now
    whole = max(now - first, 3600.0)
    return 0.0, max(60, int(whole / 200 / 60) * 60)


def run_panel(conn, panel, params):
    cur = conn.execute(panel["sql"], params)
    cols = [d[0] for d in cur.description or []]
    return {"columns": cols, "rows": cur.fetchmany(5000)}


class Site:
    def __init__(self, file, config, recording):
        self.file = pathlib.Path(file)
        self.config = config
        self.recording = recording

    def connect(self):
        if not self.file.exists():
            return None
        conn = sqlite3.connect("file:%s?mode=ro" % self.file.as_posix(), uri=True, timeout=5)
        return conn

    def status(self):
        conn = self.connect()
        out = {"file": str(self.file), "recording": self.recording(), "exists": conn is not None}
        if conn is not None:
            with conn:
                try:
                    out["last_change"] = conn.execute("SELECT MAX(at) FROM change").fetchone()[0]
                    out["last_place"] = conn.execute("SELECT MAX(at) FROM position").fetchone()[0]
                    out["runs"] = conn.execute("SELECT COUNT(*) FROM run").fetchone()[0]
                    out["size_mb"] = round(self.file.stat().st_size / 1e6, 1)
                except sqlite3.Error as e:
                    out["error"] = str(e)
        return out

    def players(self):
        conn = self.connect()
        if conn is None:
            return []
        with conn:
            try:
                return [{"id": r[0], "name": r[1] or "(no name) %d" % r[0]}
                        for r in conn.execute("SELECT entity_id, name FROM player_name WHERE tool = 0 ORDER BY name")]
            except sqlite3.Error:
                return []

    def panel(self, pid, rng, player, cell):
        panel = next((p for p in self.config["panels"] if p.get("id") == pid), None)
        if panel is None:
            return {"error": "no panel '%s'" % pid}
        conn = self.connect()
        if conn is None:
            return {"columns": [], "rows": [], "note": "nothing recorded yet"}
        with conn:
            now = time.time()
            since, bucket = window(conn, rng, now)
            params = {"since": since, "now": now, "bucket": bucket, "player": player, "cell": cell}
            try:
                out = run_panel(conn, panel, params)
            except sqlite3.Error as e:
                return {"error": "%s: %s" % (pid, e)}
        out.update(since=since, now=now, bucket=bucket)
        return out


def handler_for(site):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, code, body, kind):
            data = body.encode("utf-8") if isinstance(body, str) else body
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def json(self, obj):
            self.send(200, json.dumps(obj), "application/json; charset=utf-8")

        def do_GET(self):
            url = urllib.parse.urlparse(self.path)
            q = {k: v[-1] for k, v in urllib.parse.parse_qs(url.query).items()}
            if url.path in ("/", "/index.html"):
                self.send(200, PAGE.read_text(encoding="utf-8"), "text/html; charset=utf-8")
            elif url.path == "/api/status":
                self.json(site.status())
            elif url.path == "/api/panels":
                self.json([{k: p.get(k, "") for k in ("id", "title", "kind", "unit", "owner", "step")} for p in site.config["panels"]])
            elif url.path == "/api/players":
                self.json(site.players())
            elif url.path == "/api/panel":
                try:
                    player = int(q.get("player", "0") or 0)
                    cell = float(q.get("cell", DEFAULT_CELL_M) or DEFAULT_CELL_M)
                except ValueError:
                    player, cell = 0, DEFAULT_CELL_M
                self.json(site.panel(q.get("id", ""), q.get("range", "day"), player, max(0.5, cell)))
            else:
                self.send(404, "not here", "text/plain")

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default="")
    ap.add_argument("--file", default="")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--no-open", action="store_true", help="do not open the browser")
    ap.add_argument("--no-record", action="store_true", help="only read: never start a chronicle")
    a = ap.parse_args()
    db = a.db or chronicle.database_name()
    file = pathlib.Path(a.file) if a.file else chronicle.default_file(db)
    stop = threading.Event()
    mine = {"thread": None}
    if not a.no_record and not chronicle.Lock(file).held_by_another():
        t = threading.Thread(target=chronicle.record, args=(db, file), kwargs={"stop": stop}, daemon=True)
        t.start()
        mine["thread"] = t
        print("telemetry: nothing was recording %s, so this window records it while it is open" % db)

    def recording():
        if mine["thread"] is not None and mine["thread"].is_alive():
            return "this window"
        return "yes" if chronicle.Lock(file).held_by_another() else ""

    site = Site(file, chronicle.load_config(), recording)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), handler_for(site))
    url = "http://127.0.0.1:%d/" % a.port
    print("telemetry: %s on %s (%s). Close this window (or Ctrl+C) to stop." % (db, url, file))
    if not a.no_open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()
        if mine["thread"] is not None:
            mine["thread"].join(timeout=8)
    return 0


if __name__ == "__main__":
    sys.exit(main())
