"""THE CHRONICLE (DECISIONS #276): everything that happens in the game's database, kept on the host's disk.

    python tools/telemetry/chronicle.py [--db NAME] [--file PATH] [--parent-alive FILE] [--for SECONDS]

Luke 2026-10-21: "ideally live telemetry exists for looking back ... full historical data in positions,
skills, and all other data points". SpacetimeDB holds every table in memory, so the history cannot live
in the database: this keeps it. Subscribed as the database's OWNER (the `spacetime` CLI's login: it sees
the private tables too), it writes every insert, update and delete of every table to a SQLite file
(build/telemetry/<database>.sqlite) as it happens, and each online player's place every
`foundation.telemetry_where_s` seconds (the module's `where_sample`). Kept forever, or `keep_days`.

What it skips is data: shared/telemetry.json (and a genre's shared/<genre>/telemetry.json): `skip`, the
tables never subscribed to (every step, every tick), and `quiet`, columns whose change alone is no line (a
heartbeat). Scheduled tables are always skipped. The file's tables:

    change(id, at, run, tx, tbl, op, key, row, old)   one line a row changed: op is have (the row as it was
                                                        when the chronicle connected), insert, update or
                                                        delete; row the row (JSON), old an update's
                                                        changed columns as they were
    position(at, entity_id, world_id, level, x, y, z, yaw)   where each online player was (server time)
    player_name(entity_id, name, identity, tool)       each player's latest name; tool 1 is the CLI's own
                                                        nameless admin (DECISIONS #272), left out of panels
    run(id, started, ended, db, tables, note)          each time it connected: a gap between runs is a gap

`at` is when the host heard it (Unix seconds); a position's is the server's own. One chronicle a file: a
second start finds the first's lock fresh and leaves. It reconnects when the server goes (a republish, a
restart), noting a new run. Read it with tools/telemetry/dashboard.py (tools\\telemetry.cmd), or any
SQLite tool.

Started by tools/host.sh while hosting, by an editor run (`ChronicleLauncher`, with --parent-alive), and
by the telemetry page when nothing records. Standard library only.
"""
import argparse
import json
import os
import pathlib
import signal
import sqlite3
import subprocess
import sys
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCHEMA = """
CREATE TABLE IF NOT EXISTS run(id INTEGER PRIMARY KEY, started REAL NOT NULL, ended REAL, db TEXT, tables INTEGER, note TEXT);
CREATE TABLE IF NOT EXISTS change(id INTEGER PRIMARY KEY, at REAL NOT NULL, run INTEGER, tx INTEGER, tbl TEXT NOT NULL,
    op TEXT NOT NULL, key TEXT, row TEXT, old TEXT);
CREATE INDEX IF NOT EXISTS change_tbl_at ON change(tbl, at);
CREATE INDEX IF NOT EXISTS change_at ON change(at);
CREATE TABLE IF NOT EXISTS position(at REAL NOT NULL, entity_id INTEGER NOT NULL, world_id INTEGER, level INTEGER,
    x REAL, y REAL, z REAL, yaw REAL);
CREATE INDEX IF NOT EXISTS position_at ON position(at);
CREATE INDEX IF NOT EXISTS position_entity_at ON position(entity_id, at);
CREATE TABLE IF NOT EXISTS player_name(entity_id INTEGER PRIMARY KEY, name TEXT, identity TEXT, tool INTEGER NOT NULL DEFAULT 0);
"""
ROLE_ADMIN = 0
LOCK_FRESH_S = 10.0
COMMIT_EVERY_S = 1.0


def say(text):
    sys.stdout.write("chronicle: %s\n" % text)
    sys.stdout.flush()


def database_name():
    if os.environ.get("UMF_DB"):
        return os.environ["UMF_DB"]
    return json.loads((ROOT / "shared/game.json").read_text(encoding="utf-8")).get("database", "umf")


def load_config(root=ROOT):
    """The foundation's shared/telemetry.json with each genre's own added: skip, quiet, panels, keep_days.
    Each panel says whose it is (`owner`)."""
    game = json.loads((root / "shared/game.json").read_text(encoding="utf-8"))
    out = {"skip": set(), "quiet": {}, "panels": [], "keep_days": 0}
    sources = [("foundation", root / "shared/telemetry.json")]
    sources += [(g, root / "shared" / g / "telemetry.json") for g in game.get("genres", [])]
    for owner, path in sources:
        if not path.exists():
            continue
        doc = json.loads(path.read_text(encoding="utf-8"))
        out["skip"].update(doc.get("skip", []))
        for tbl, cols in doc.get("quiet", {}).items():
            out["quiet"].setdefault(tbl, set()).update(cols)
        for p in doc.get("panels", []):
            out["panels"].append(dict(p, owner=owner))
        if owner == "foundation":
            out["keep_days"] = float(doc.get("keep_days", 0))
    return out


def plain(v):
    """A value as the CLI writes it, made plain: a Timestamp's microseconds, an Identity's hex, a duration's
    microseconds; everything inside lists and objects likewise."""
    if isinstance(v, dict):
        if len(v) == 1:
            (k, inner), = v.items()
            if k in ("__timestamp_micros_since_unix_epoch__", "__time_duration_micros__"):
                return inner
            if k in ("__identity__", "__connection_id__"):
                return str(inner)
        return {k: plain(x) for k, x in v.items()}
    if isinstance(v, list):
        return [plain(x) for x in v]
    return v


def parse_schema(described):
    """`spacetime describe --json`: {table: {"pk": [column names], "columns": [...], "scheduled": bool}}."""
    sec = {}
    for s in described["sections"]:
        sec.update(s)
    types = sec["Typespace"]["types"]
    scheduled = {s["table_name"] for s in sec.get("Schedules", [])}
    tables = {}
    for t in sec["Tables"]:
        cols = [e["name"].get("some", "") for e in types[t["product_type_ref"]]["Product"]["elements"]]
        tables[t["source_name"]] = {
            "columns": cols,
            "pk": [cols[i] for i in t.get("primary_key", [])],
            "scheduled": t["source_name"] in scheduled,
        }
    return tables


def watched(tables, config):
    """The tables subscribed to: all but the skipped and the scheduled."""
    return sorted(n for n, t in tables.items() if not t["scheduled"] and n not in config["skip"])


class Chronicle:
    """What a subscription's messages are written as (the part with no process, so a test feeds it)."""

    def __init__(self, conn, tables, config, db=""):
        self.conn = conn
        self.tables = tables
        self.config = config
        self.db = db
        conn.executescript(SCHEMA)
        self.tx = (conn.execute("SELECT MAX(tx) FROM change").fetchone()[0] or 0)
        self.run = None
        self.admins = set()
        self.players = {}
        self.lines = 0
        self.places = 0

    def begin_run(self, at, note=""):
        cur = self.conn.execute("INSERT INTO run(started, db, tables, note) VALUES (?, ?, ?, ?)",
                                (at, self.db, len(watched(self.tables, self.config)), note))
        self.run = cur.lastrowid
        self.conn.commit()

    def end_run(self, at):
        if self.run is not None:
            self.conn.execute("UPDATE run SET ended = ? WHERE id = ?", (at, self.run))
            self.conn.commit()

    def key_of(self, tbl, row):
        pk = self.tables.get(tbl, {}).get("pk") or []
        if not pk:
            return json.dumps(row, sort_keys=True)
        vals = [row.get(c) for c in pk]
        return str(vals[0]) if len(vals) == 1 else json.dumps(vals)

    def apply(self, message, at, initial=False):
        """One message from the subscription: one transaction (or, `initial`, every row as it is now).
        A delete and an insert of the same key are one update."""
        self.tx += 1
        for tbl, change in message.items():
            dels = {}
            for r in change.get("deletes", []):
                r = plain(r)
                dels[self.key_of(tbl, r)] = r
            ins = []
            for r in change.get("inserts", []):
                r = plain(r)
                ins.append((self.key_of(tbl, r), r))
            for key, new in ins:
                old = dels.pop(key, None)
                if tbl == "where_sample":
                    self._place(new)
                    continue
                if old is None:
                    self._line(at, tbl, "have" if initial else "insert", key, new, None)
                else:
                    changed = {c: old.get(c) for c in set(old) | set(new) if old.get(c) != new.get(c)}
                    if not changed or set(changed) <= self.config["quiet"].get(tbl, set()):
                        self._watch(tbl, new)
                        continue
                    self._line(at, tbl, "update", key, new, changed)
            for key, old in dels.items():
                if tbl == "where_sample":
                    continue
                self._line(at, tbl, "delete", key, old, None)
                self._forget(tbl, old)

    def _line(self, at, tbl, op, key, row, old):
        self.conn.execute("INSERT INTO change(at, run, tx, tbl, op, key, row, old) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                          (at, self.run, self.tx, tbl, op, key, json.dumps(row, separators=(",", ":")),
                           None if old is None else json.dumps(old, separators=(",", ":"))))
        self.lines += 1
        self._watch(tbl, row)

    def _place(self, r):
        pos = r.get("pos") or {}
        self.conn.execute("INSERT INTO position(at, entity_id, world_id, level, x, y, z, yaw) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                          (r.get("at", 0) / 1e6, r.get("entity_id"), r.get("world_id"), r.get("level"),
                           pos.get("x"), pos.get("y"), pos.get("z"), r.get("yaw")))
        self.places += 1

    def _watch(self, tbl, row):
        """Keep up who is a player (and who is a tool: a nameless admin) from the rows that say so."""
        if tbl == "authority":
            if row.get("role") == ROLE_ADMIN:
                self.admins.add(row.get("identity"))
            else:
                self.admins.discard(row.get("identity"))
            self._names()
        elif tbl == "player":
            self.players[row.get("entity_id")] = row
            self._name(row)

    def _forget(self, tbl, row):
        if tbl == "authority":
            self.admins.discard(row.get("identity"))
            self._names()

    def _names(self):
        for row in self.players.values():
            self._name(row)

    def _name(self, row):
        name = row.get("name") or ""
        tool = 1 if not name.strip() and row.get("identity") in self.admins else 0
        self.conn.execute("INSERT INTO player_name(entity_id, name, identity, tool) VALUES (?, ?, ?, ?) "
                          "ON CONFLICT(entity_id) DO UPDATE SET name = excluded.name, identity = excluded.identity, tool = excluded.tool",
                          (row.get("entity_id"), name, row.get("identity"), tool))

    def prune(self, now):
        days = self.config.get("keep_days", 0)
        if days and days > 0:
            cutoff = now - days * 86400.0
            self.conn.execute("DELETE FROM change WHERE at < ?", (cutoff,))
            self.conn.execute("DELETE FROM position WHERE at < ?", (cutoff,))
            self.conn.commit()


def spacetime():
    return os.environ.get("SPACETIME", "spacetime")


def describe(db, server):
    cmd = [spacetime(), "describe", db, "--json", "-y"] + (["-s", server] if server else [])
    out = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    text = out.stdout[out.stdout.find("{"):] if "{" in out.stdout else ""
    if out.returncode != 0 or not text:
        raise RuntimeError((out.stderr or out.stdout).strip()[-300:] or "describe failed")
    return parse_schema(json.loads(text))


def kill_tree(proc):
    if proc.poll() is not None:
        return
    if os.name == "nt":
        # `spacetime` is a launcher: the subscription is its child, which terminate() would leave running.
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
    else:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except OSError:
            proc.terminate()


class Lock:
    """One chronicle a file: `<file>.lock` holds its pid and is touched every second while it runs."""

    def __init__(self, path):
        self.path = pathlib.Path(str(path) + ".lock")

    def held_by_another(self):
        try:
            return time.time() - self.path.stat().st_mtime < LOCK_FRESH_S
        except OSError:
            return False

    def touch(self):
        self.path.write_text(str(os.getpid()), encoding="utf-8")

    def release(self):
        try:
            if self.path.read_text(encoding="utf-8").strip() == str(os.getpid()):
                self.path.unlink()
        except OSError:
            pass


def alive(path, stale_s=6.0):
    """Whether the game that keeps `path` touched is still there (an editor run's `ChronicleLauncher`)."""
    try:
        return time.time() - os.path.getmtime(path) <= stale_s
    except OSError:
        return False


def record(db, file, server="", parent_alive="", for_s=0.0, stop=None):
    """Record `db` into `file` until stopped (Ctrl+C, `stop` set, the parent gone, or `for_s` seconds)."""
    stop = stop or threading.Event()
    file = pathlib.Path(file)
    file.parent.mkdir(parents=True, exist_ok=True)
    gdignore = file.parent / ".gdignore"
    if not gdignore.exists():
        gdignore.write_text("", encoding="utf-8")
    lock = Lock(file)
    if lock.held_by_another():
        say("%s is already being recorded (%s)" % (db, lock.path))
        return 0
    lock.touch()
    config = load_config()
    conn = sqlite3.connect(str(file), check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    started = time.time()
    chron = None
    proc = None

    def keeper():
        while not stop.is_set():
            lock.touch()
            if parent_alive and not alive(parent_alive):
                say("the game that started it has gone: stopping")
                stop.set()
            if for_s and time.time() - started >= for_s:
                stop.set()
            if stop.is_set() and proc is not None:
                kill_tree(proc)
            time.sleep(1.0)

    threading.Thread(target=keeper, daemon=True).start()
    last_prune = 0.0
    try:
        while not stop.is_set():
            try:
                tables = describe(db, server)
            except (RuntimeError, OSError, ValueError) as e:
                say("cannot read %s yet (%s): trying again in 5 s" % (db, e))
                stop.wait(5.0)
                continue
            if chron is None:
                chron = Chronicle(conn, tables, config, db)
            else:
                chron.tables = tables
            names = watched(tables, config)
            queries = ["SELECT * FROM %s" % n for n in names]
            cmd = [spacetime(), "subscribe", db] + queries + ["--print-initial-update", "-y"] + (["-s", server] if server else [])
            kw = {"start_new_session": True} if os.name != "nt" else {}
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8", **kw)
            chron.begin_run(time.time(), "%d tables, %d skipped" % (len(names), len(tables) - len(names)))
            say("recording %s into %s (%d tables; skipped: %s)" % (db, file, len(names),
                ", ".join(sorted(n for n in tables if n not in names and not tables[n]["scheduled"])) or "none"))
            first = True
            last_commit = time.time()
            for line in proc.stdout:
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                now = time.time()
                chron.apply(msg, now, initial=first)
                first = False
                if now - last_commit >= COMMIT_EVERY_S:
                    conn.commit()
                    last_commit = now
                if now - last_prune > 3600:
                    chron.prune(now)
                    last_prune = now
                if stop.is_set():
                    break
            conn.commit()
            kill_tree(proc)
            err = (proc.stderr.read() or "").strip() if proc.stderr else ""
            chron.end_run(time.time())
            if stop.is_set():
                break
            say("the subscription ended (%s): connecting again in 5 s" % (err.splitlines()[-1] if err else "the server went"))
            stop.wait(5.0)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        if proc is not None:
            kill_tree(proc)
        if chron is not None:
            conn.commit()
            chron.end_run(time.time())
            say("stopped: %d lines, %d places this time" % (chron.lines, chron.places))
        conn.close()
        lock.release()
    return 0


def default_file(db):
    return ROOT / "build" / "telemetry" / ("%s.sqlite" % db)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db", default="", help="the database (default: UMF_DB, else shared/game.json's)")
    ap.add_argument("--file", default="", help="the SQLite file (default: build/telemetry/<db>.sqlite)")
    ap.add_argument("--server", default="", help="the spacetime server nickname or URL (default: the CLI's)")
    ap.add_argument("--parent-alive", default="", help="stop once this file is no longer touched (an editor run)")
    ap.add_argument("--for", dest="for_s", type=float, default=0.0, help="stop after this many seconds (tests)")
    a = ap.parse_args()
    db = a.db or database_name()
    return record(db, a.file or default_file(db), a.server, a.parent_alive, a.for_s)


if __name__ == "__main__":
    sys.exit(main())
