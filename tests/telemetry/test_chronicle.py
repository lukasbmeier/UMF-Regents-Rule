"""The chronicle's own rules (DECISIONS #276), without a server: how a subscription's messages are kept.
Run by tests/telemetry_test.sh (python -m unittest tests/telemetry/test_chronicle.py)."""
import json
import pathlib
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "tools" / "telemetry"))
import chronicle  # noqa: E402
import dashboard  # noqa: E402

TABLES = {
    "player": {"columns": ["identity", "entity_id", "name", "online"], "pk": ["identity"], "scheduled": False},
    "authority": {"columns": ["identity", "role", "world_id", "last_seen"], "pk": ["identity"], "scheduled": False},
    "skill_xp": {"columns": ["id", "entity_id", "skill_id", "xp"], "pk": ["id"], "scheduled": False},
    "where_sample": {"columns": ["entity_id", "world_id", "level", "pos", "yaw", "at"], "pk": ["entity_id"], "scheduled": False},
    "movement_state": {"columns": ["entity_id", "pos"], "pk": ["entity_id"], "scheduled": False},
    "tick_schedule": {"columns": ["scheduled_id", "scheduled_at"], "pk": ["scheduled_id"], "scheduled": True},
}
CONFIG = {"skip": {"movement_state"}, "quiet": {"authority": {"last_seen"}}, "panels": [], "keep_days": 0}
TS = "__timestamp_micros_since_unix_epoch__"
ME = {"__identity__": "0xaa"}
CLI = {"__identity__": "0xcc"}


def new():
    conn = sqlite3.connect(":memory:")
    c = chronicle.Chronicle(conn, TABLES, CONFIG, "test")
    c.begin_run(100.0)
    return conn, c


def lines(conn, op=None):
    q = "SELECT tbl, op, key, row, old FROM change" + (" WHERE op = ?" if op else "") + " ORDER BY id"
    return [(t, o, k, json.loads(r), json.loads(old) if old else None) for t, o, k, r, old in conn.execute(q, (op,) if op else ())]


class Kept(unittest.TestCase):
    def test_what_is_subscribed(self):
        self.assertEqual(chronicle.watched(TABLES, CONFIG), ["authority", "player", "skill_xp", "where_sample"],
                         "the skipped and the scheduled are not subscribed to")

    def test_the_first_message_is_what_there_was(self):
        conn, c = new()
        c.apply({"skill_xp": {"deletes": [], "inserts": [{"id": 1, "entity_id": 7, "skill_id": 40001, "xp": 10}]}}, 101.0, initial=True)
        c.apply({"skill_xp": {"deletes": [], "inserts": [{"id": 2, "entity_id": 7, "skill_id": 40002, "xp": 5}]}}, 102.0)
        got = [(t, o, k) for t, o, k, _, _ in lines(conn)]
        self.assertEqual(got, [("skill_xp", "have", "1"), ("skill_xp", "insert", "2")])

    def test_a_delete_and_insert_of_one_key_is_an_update_with_what_changed(self):
        conn, c = new()
        old = {"id": 1, "entity_id": 7, "skill_id": 40001, "xp": 10}
        c.apply({"skill_xp": {"deletes": [old], "inserts": [dict(old, xp=35)]}}, 103.0)
        (t, o, k, row, was), = lines(conn)
        self.assertEqual((t, o, k, row["xp"], was), ("skill_xp", "update", "1", 35, {"xp": 10}))

    def test_a_delete_alone_is_a_delete(self):
        conn, c = new()
        c.apply({"skill_xp": {"deletes": [{"id": 4, "entity_id": 7, "skill_id": 1, "xp": 1}], "inserts": []}}, 104.0)
        self.assertEqual([(o, k) for _, o, k, _, _ in lines(conn)], [("delete", "4")])

    def test_a_heartbeat_alone_is_no_line_but_a_real_change_is(self):
        conn, c = new()
        a = {"identity": ME, "role": 0, "world_id": 0, "last_seen": {TS: 1}}
        c.apply({"authority": {"deletes": [a], "inserts": [dict(a, last_seen={TS: 2})]}}, 105.0)
        self.assertEqual(lines(conn), [], "only last_seen moved: quiet")
        c.apply({"authority": {"deletes": [a], "inserts": [dict(a, role=1, last_seen={TS: 3})]}}, 106.0)
        (_, o, _, _, was), = lines(conn)
        self.assertEqual((o, was), ("update", {"role": 0, "last_seen": 1}))

    def test_values_are_made_plain(self):
        self.assertEqual(chronicle.plain({"at": {TS: 5}, "who": {"__identity__": "0x1"}, "l": [{TS: 6}]}),
                         {"at": 5, "who": "0x1", "l": [6]})

    def test_places_go_to_position_not_change(self):
        conn, c = new()
        w = {"entity_id": 7, "world_id": 0, "level": 20, "pos": {"x": 1.5, "y": 0.0, "z": -3.0}, "yaw": 0.5, "at": {TS: 200_000_000}}
        c.apply({"where_sample": {"deletes": [], "inserts": [w]}}, 107.0)
        c.apply({"where_sample": {"deletes": [w], "inserts": [dict(w, pos={"x": 4.0, "y": 0.0, "z": 2.0}, at={TS: 205_000_000})]}}, 108.0)
        c.apply({"where_sample": {"deletes": [w], "inserts": []}}, 109.0)
        self.assertEqual(lines(conn), [])
        self.assertEqual(conn.execute("SELECT at, entity_id, level, x, z FROM position ORDER BY at").fetchall(),
                         [(200.0, 7, 20, 1.5, -3.0), (205.0, 7, 20, 4.0, 2.0)], "each note at the server's time; a leaving no note")

    def test_a_nameless_admin_is_a_tool_and_a_named_one_a_player(self):
        conn, c = new()
        c.apply({"authority": {"deletes": [], "inserts": [{"identity": CLI, "role": 0, "world_id": 0, "last_seen": {TS: 1}}]},
                 "player": {"deletes": [], "inserts": [{"identity": CLI, "entity_id": 1, "name": "", "online": True},
                                                        {"identity": ME, "entity_id": 7, "name": "", "online": True}]}}, 110.0, initial=True)
        self.assertEqual(conn.execute("SELECT entity_id, tool FROM player_name ORDER BY 1").fetchall(), [(1, 1), (7, 0)],
                         "the CLI (an admin, no name) is a tool; a nameless player who is no admin is not")
        p = {"identity": CLI, "entity_id": 1, "name": "", "online": True}
        c.apply({"player": {"deletes": [p], "inserts": [dict(p, name="Luke")]}}, 111.0)
        self.assertEqual(conn.execute("SELECT name, tool FROM player_name WHERE entity_id = 1").fetchone(), ("Luke", 0),
                         "an admin who says a name plays")

    def test_kept_forever_unless_told(self):
        conn, c = new()
        c.apply({"skill_xp": {"deletes": [], "inserts": [{"id": 1, "entity_id": 7, "skill_id": 1, "xp": 1}]}}, 10.0)
        c.prune(10.0 + 400 * 86400)
        self.assertEqual(len(lines(conn)), 1, "keep_days 0: nothing goes")
        c.config = dict(CONFIG, keep_days=30)
        c.prune(10.0 + 31 * 86400)
        self.assertEqual(len(lines(conn)), 0, "older than keep_days: gone")

    def test_the_config_adds_each_genres_own(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            (root / "shared" / "g").mkdir(parents=True)
            (root / "shared/game.json").write_text(json.dumps({"genres": ["g"]}), encoding="utf-8")
            (root / "shared/telemetry.json").write_text(json.dumps({"skip": ["a"], "quiet": {"t": ["x"]}, "panels": [{"id": "f"}]}), encoding="utf-8")
            (root / "shared/g/telemetry.json").write_text(json.dumps({"skip": ["b"], "quiet": {"t": ["y"]}, "panels": [{"id": "p"}]}), encoding="utf-8")
            cfg = chronicle.load_config(root)
        self.assertEqual(cfg["skip"], {"a", "b"})
        self.assertEqual(cfg["quiet"], {"t": {"x", "y"}})
        self.assertEqual([(p["id"], p["owner"]) for p in cfg["panels"]], [("f", "foundation"), ("p", "g")])

    def test_content_has_its_names(self):
        conn, c = new()
        rows = dict(((t, i), n) for t, i, n in conn.execute("SELECT type, id, name FROM content_name"))
        self.assertTrue(any(t == "status" for t, _ in rows), "the foundation's statuses are named")
        self.assertTrue(all(isinstance(i, int) for _, i in rows))

    def test_the_lock_keeps_a_second_chronicle_out(self):
        with tempfile.TemporaryDirectory() as d:
            lock = chronicle.Lock(pathlib.Path(d) / "x.sqlite")
            self.assertFalse(lock.held_by_another())
            lock.touch()
            self.assertTrue(lock.held_by_another(), "touched just now: held")
            lock.release()
            self.assertFalse(lock.held_by_another(), "released: free")


class Panels(unittest.TestCase):
    """Every panel shipped runs on a chronicle's file (a typo in a panel's SQL fails here, not on the page)."""

    def test_every_panel_runs(self):
        conn, c = new()
        c.apply({"player": {"deletes": [], "inserts": [{"identity": ME, "entity_id": 7, "name": "Ann", "online": True}]}}, 120.0, initial=True)
        cfg = chronicle.load_config()
        self.assertTrue(cfg["panels"], "the foundation ships panels")
        for p in cfg["panels"]:
            with self.subTest(panel=p["id"]):
                out = dashboard.run_panel(conn, p, {"since": 0.0, "now": 200.0, "bucket": 60, "player": 0, "cell": 4.0})
                self.assertIsInstance(out["rows"], list)
                self.assertIn(p.get("kind"), ("line", "bar", "table", "heatmap"))

    def test_ranges(self):
        conn, c = new()
        self.assertEqual(dashboard.window(conn, "hour", 10_000.0), (6400.0, 60))
        self.assertEqual(dashboard.window(conn, "week", 1e6)[1], 3600)
        since, bucket = dashboard.window(conn, "all", 1e6)
        self.assertEqual(since, 0.0)
        self.assertGreaterEqual(bucket, 60)


if __name__ == "__main__":
    unittest.main()
