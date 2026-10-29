"""LOAD TEST BOTS (DECISIONS #284): many light clients in one process, each a real connection to the
database, playing as a GUEST: it asks for what a real client of this game asks for (the interest dump,
`interest_dump.gd`), walks from cell to cell at the run speed sending its inputs as a real client does
(60 frames a second, 3 to a `submit_input` call), and re-centres its ring of cells where a real client
would (`cells.py`, the twin of `Cells`). It decodes almost nothing: a bot counts the rows and bytes it
is sent, times its reducer calls and ring swaps, and reads only its own rows.

A WORKER of `load_test.py`, which starts one per 50 bots and reads what each writes, a line a second:

  python tools/load/bots.py --db umf-template-test --interest build/load/interest.json \
      --first 0 --count 50 --stats build/load/w0.jsonl --stop build/load/stop

WHAT A BOT DOES BESIDES WALKING is its game's: `game/<genre>/load_bot.py` for each genre in
`shared/game.json`, with `setup(bot)` (once, when it is walking) and `tick(bot, now)` (10 times a second).
A hook calls reducers by name with Python values (`bot.call("cast", 3, {"x": 1.0, ...})`, encoded from
the module's own schema), steers (`bot.walk_to(x, z)`, `bot.wander()`), and reads `bot.pos`,
`bot.entity_id`, `bot.world_id`, `bot.rng`. `docs/HANDBOOK.md`, "The load test".
"""
import argparse
import asyncio
import importlib.util
import json
import math
import os
import random
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wire  # noqa: E402
from cells import Cells  # noqa: E402

MOVE_IDLE = 0
MOVE_RUN = 7          # the module's MOVE_RUN (server/src/module/constants.rs)
HOOK_HZ = 10


class Totals:
    """What a process saw in the current second; written out and reset each second."""

    def __init__(self):
        self.rtt = {}          # reducer -> [ms]
        self.ack = []          # ms from a batch sent to the server's movement row saying it was processed
        self.swap_ms = []      # ms from a new ring subscribed to it applied
        self.swaps = 0
        self.errors = {}       # "reducer: text" -> count
        self.sub_errors = []
        self.tables = {}       # table -> rows
        self.lag = []          # ms the event loop woke up late
        self.tick_behind = 0   # 60 Hz ticks skipped because the process was behind

    def err(self, key):
        self.errors[key] = self.errors.get(key, 0) + 1


class Bot:
    def __init__(self, swarm, index):
        self.swarm = swarm
        self.index = index
        self.name = "Bot %d" % index
        self.rng = random.Random(swarm.seed * 100003 + index)
        self.state = "new"          # new, connecting, joined, spreading, walking, dead
        self.why = ""
        self.ws = None
        self.identity = b""
        self.entity_id = -1
        self.world_id = 0
        self.pos = None             # where this bot says it is: {x, y, z}
        self.server_pos = None      # where the server last said
        self.epoch = 0
        self.seq = 0
        self.frames = []
        self.target = None
        self.paused = False
        self.spread_to = None
        self.spread_since = 0.0
        self._req = 0
        self._qset = 0
        self.pending = {}           # request id -> (reducer, sent at)
        self.sent_seq = {}          # last seq of a batch -> sent at
        self.sets = {}              # query set id -> {"kind", "at", "applied"}
        self.world_set = None
        self.own_set = None
        self.own_incoming = None
        self.ring_set = None
        self.ring_incoming = None
        self.centre = -1
        # This second's counts (the swarm reads and zeroes them).
        self.wire = 0
        self.raw = 0
        self.rows = 0
        self.msgs = 0
        self.seen = set()
        self.moved = 0.0            # metres the server moved us, this second
        self.hook_at = 0.0

    # ---- the API a genre's hook uses -------------------------------------------------------------
    def call(self, reducer, *args):
        """Call `reducer` with Python values (encoded from the module's schema). Its round trip is timed."""
        self._req += 1
        self.pending[self._req] = (reducer, time.perf_counter())
        self.ws.send(wire.msg_call_reducer(self._req, reducer, self.swarm.schema.reducer_args(reducer, args)))
        return self._req

    def walk_to(self, x, z):
        self.target = (float(x), float(z))
        self.paused = False

    def wander(self):
        self.target = None
        self.paused = False

    def stop(self):
        self.paused = True

    def log(self, text):
        print("[%s] %s" % (self.name, text), flush=True)

    # ---- connecting -----------------------------------------------------------------------------
    async def run(self):
        sw = self.swarm
        self.state = "connecting"
        try:
            _, token = await asyncio.get_running_loop().run_in_executor(None, wire.new_identity, sw.host)
            u = urllib.parse.urlparse(sw.host)
            path = "/v1/database/%s/subscribe?connection_id=%s&compression=Gzip&confirmed=false" % (
                sw.db, os.urandom(16).hex())
            self.ws = await wire.WebSocket.connect(u.hostname, u.port or 80, path, {"Authorization": "Bearer " + token})
            while True:
                frame = await self.ws.recv()
                self.on_frame(frame)
                if self.ws.writer.transport.get_write_buffer_size() > 1 << 20:
                    await self.ws.writer.drain()
        except asyncio.CancelledError:
            pass
        except Exception as e:  # noqa: BLE001 - a bot that fails says why and is counted, never lost quietly
            self.die("%s: %s" % (type(e).__name__, e))

    def die(self, why):
        if self.state != "dead":
            self.state = "dead"
            self.why = why
            self.swarm.deaths.append((self.index, why))

    def subscribe(self, kind, queries):
        self._req += 1
        self._qset += 1
        self.sets[self._qset] = {"kind": kind, "at": time.perf_counter(), "applied": False}
        self.ws.send(wire.msg_subscribe(self._req, self._qset, queries))
        return self._qset

    def unsubscribe(self, qset):
        if qset is None:
            return
        self._req += 1
        self.sets.pop(qset, None)
        self.ws.send(wire.msg_unsubscribe(self._req, qset))

    # ---- what the server sends ------------------------------------------------------------------
    def on_frame(self, frame):
        sw = self.swarm
        self.wire += len(frame)
        payload = wire.decompress(frame)
        self.raw += len(payload)
        for m in wire.parse_server_messages(payload):
            self.msgs += 1
            kind = m[0]
            if kind == wire.INITIAL_CONNECTION:
                self.identity = m[1]
                self.state = "joined"
                self.world_set = self.subscribe("world", sw.queries("world_queries", world=0))
                self.call("set_player_name", self.name)
            elif kind == wire.SUBSCRIBE_APPLIED:
                self.on_applied(m[2])
                self.on_rows([(m[2], t, rows, []) for t, rows in m[3]])
            elif kind == wire.UNSUBSCRIBE_APPLIED:
                self.on_rows([(m[2], t, [], rows) for t, rows in m[3]])
            elif kind == wire.SUBSCRIPTION_ERROR:
                sw.totals.sub_errors.append(m[3])
                self.die("subscription refused: " + m[3])
            elif kind == wire.TRANSACTION_UPDATE:
                self.on_rows(m[1])
            elif kind == wire.REDUCER_RESULT:
                sent = self.pending.pop(m[1], None)
                if sent is not None:
                    sw.totals.rtt.setdefault(sent[0], []).append((time.perf_counter() - sent[1]) * 1000.0)
                    if m[2] != "ok":
                        text = wire.reducer_error_text(m[3]) if m[2] == "err" else m[3]
                        sw.totals.err("%s: %s" % (sent[0], text[:120]))
                if m[2] == "ok":
                    self.on_rows(m[3])

    def on_applied(self, qset):
        s = self.sets.get(qset)
        if s is None:
            return
        s["applied"] = True
        if s["kind"] == "ring" and qset == self.ring_incoming:
            old, self.ring_set, self.ring_incoming = self.ring_set, qset, None
            if old is not None:
                self.swarm.totals.swaps += 1
                self.swarm.totals.swap_ms.append((time.perf_counter() - s["at"]) * 1000.0)
                self.unsubscribe(old)   # only now: the shared cells' rows are held by the new one too
        elif s["kind"] == "own" and qset == self.own_incoming:
            old, self.own_set, self.own_incoming = self.own_set, qset, None
            self.unsubscribe(old)

    def on_rows(self, updates):
        sw = self.swarm
        for _, table, ins, dels in updates:
            n = len(ins) + len(dels)
            self.rows += n
            sw.totals.tables[table] = sw.totals.tables.get(table, 0) + n
            if table == "player" and self.entity_id < 0:
                for row in ins:
                    if bytes(row[sw.player_identity_at:sw.player_identity_at + 32]) == self.identity:
                        self.on_entity(sw.player_row(wire.Reader(row))["entity_id"])
            elif table == "movement_state":
                at = sw.movement_entity_at
                for row in ins:
                    eid = int.from_bytes(row[at:at + 8], "little")
                    if eid == self.entity_id:
                        self.on_own_movement(sw.movement_row(wire.Reader(row)))
                    else:
                        self.seen.add(eid)

    def on_entity(self, eid):
        self.entity_id = eid
        if self.swarm.ring:
            self.own_incoming = self.subscribe("own", self.swarm.queries("own_queries", entity=eid))

    def on_own_movement(self, row):
        sw = self.swarm
        now = time.perf_counter()
        p = row["pos"]
        if self.server_pos is not None:
            self.moved += math.hypot(p["x"] - self.server_pos["x"], p["z"] - self.server_pos["z"])
        self.server_pos = dict(p)
        self.world_id = row["world_id"]
        done = [s for s in self.sent_seq if s <= row["last_processed_seq"]]
        for s in done:
            sw.totals.ack.append((now - self.sent_seq.pop(s)) * 1000.0)
        if self.pos is None or row["correction_epoch"] != self.epoch:
            # The server overrode us (a teleport, a clamp) or this is where we start: take its place.
            self.pos = dict(p)
            self.epoch = row["correction_epoch"]
        if sw.ring:
            nxt = sw.cells.recentre(self.centre, p["x"], p["z"])
            if nxt != self.centre:
                self.centre = nxt
                self.apply_ring()
        if self.state == "joined":
            if sw.spread:
                self.state = "spreading"
                self.spread_to = sw.random_point(self.rng)
                self.spread_since = now
                self.call("teleport", {"x": self.spread_to[0], "y": p["y"], "z": self.spread_to[1]})
            else:
                self.start_walking()
        elif self.state == "spreading":
            close = math.hypot(p["x"] - self.spread_to[0], p["z"] - self.spread_to[1]) < 1.0
            if close or now - self.spread_since > 10.0:
                self.start_walking()

    def apply_ring(self):
        if self.ring_incoming is not None:
            self.unsubscribe(self.ring_incoming)   # superseded: we moved on again
            self.ring_incoming = None
        queries = []
        for c in self.swarm.cells.ring(self.centre):
            queries.extend(self.swarm.queries("cell_queries", world=self.world_id, cell=c))
        self.ring_incoming = self.subscribe("ring", queries)

    def start_walking(self):
        self.state = "walking"
        for h in self.swarm.hooks:
            if hasattr(h, "setup"):
                h.setup(self)

    # ---- 60 times a second ----------------------------------------------------------------------
    def tick(self, tick_no, now):
        sw = self.swarm
        if self.state not in ("walking", "spreading") or self.pos is None:
            return
        moving = False
        yaw = 0.0
        if self.state == "walking" and not self.paused:
            if self.target is None:
                self.target = sw.random_point(self.rng)
            dx, dz = self.target[0] - self.pos["x"], self.target[1] - self.pos["z"]
            d = math.hypot(dx, dz)
            step = sw.speed / sw.hz
            if d <= step:
                self.pos["x"], self.pos["z"] = self.target
                self.target = None
            else:
                self.pos["x"] += dx / d * step
                self.pos["z"] += dz / d * step
                # ASSUMPTION: Godot's forward is -Z, so facing (dx, dz) is atan2(-dx, -dz) (only animation reads it).
                yaw = math.atan2(-dx, -dz)
                moving = True
        self.seq += 1
        self.frames.append({
            "seq": self.seq, "client_tick": tick_no, "move_x": 0.0, "move_y": -1.0 if moving else 0.0,
            "look_yaw": yaw, "look_pitch": 0.0, "jump": False, "sprint": False,
            "client_pos": {"x": self.pos["x"], "y": self.pos["y"], "z": self.pos["z"]},
            "epoch": self.epoch, "move_state": MOVE_RUN if moving else MOVE_IDLE,
            "dash": False, "slow": False, "face": False})
        if len(self.frames) >= sw.batch:
            self.call("submit_input", self.frames)
            self.sent_seq[self.seq] = time.perf_counter()
            self.frames = []
        if self.state == "walking" and sw.hooks and now >= self.hook_at:
            self.hook_at = now + 1.0 / HOOK_HZ
            for h in sw.hooks:
                if hasattr(h, "tick"):
                    h.tick(self, now)


class Swarm:
    def __init__(self, a):
        self.host = a.host.rstrip("/")
        self.db = a.db
        self.seed = a.seed
        self.spread = not a.no_spread
        with open(a.interest, encoding="utf-8") as f:
            self.interest = json.load(f)
        self.ring = self.interest["interest"] == "ring"
        self.cells = Cells.from_doc(self.interest["cells"])
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
        with open(os.path.join(root, "shared", "movement_config.json"), encoding="utf-8") as f:
            mc = json.load(f)
        self.hz = int(mc.get("client_tick_hz", 60))
        self.batch = int(mc.get("input_batch_size", 3))
        self.speed = float(a.speed if a.speed > 0 else mc.get("run_speed", 5.0))
        half = a.area_cells * self.cells.cell_m / 2.0
        self.area = (-half, half)
        self.schema = wire.Schema.fetch(self.host, self.db)
        self.player_identity_at = self.schema.column_offset("player", "identity")
        self.movement_entity_at = self.schema.column_offset("movement_state", "entity_id")
        if self.player_identity_at is None or self.movement_entity_at is None:
            raise SystemExit("bots: player.identity or movement_state.entity_id is not at a fixed place in its row")
        self.player_row = self.schema.row_decoder("player")
        self.movement_row = self.schema.row_decoder("movement_state")
        self.hooks = load_hooks(root) if not a.no_hooks else []
        self.bots = [Bot(self, i) for i in range(a.first, a.first + a.count)]
        self.connect_rate = a.connect_rate
        self.totals = Totals()
        self.deaths = []
        self.stats_path = a.stats
        self.stop_path = a.stop

    def queries(self, key, **marks):
        out = []
        for q in self.interest[key]:
            for k, v in marks.items():
                q = q.replace("{%s}" % k, str(v))
            out.append(q)
        return out

    def random_point(self, rng):
        return (rng.uniform(*self.area), rng.uniform(*self.area))

    async def main(self):
        loop = asyncio.get_running_loop()
        tasks = []
        out = open(self.stats_path, "a", encoding="utf-8")
        ticker = asyncio.ensure_future(self.ticker())
        lag = asyncio.ensure_future(self.lag_monitor())
        next_write = time.time() + 1.0
        started = 0
        t0 = loop.time()
        try:
            while not os.path.exists(self.stop_path):
                # Connect a few a second (a real crowd does not arrive in one instant).
                due = min(len(self.bots), int((loop.time() - t0) * self.connect_rate) + 1)
                while started < due:
                    tasks.append(asyncio.ensure_future(self.bots[started].run()))
                    started += 1
                await asyncio.sleep(0.05)
                if time.time() >= next_write:
                    self.write(out)
                    next_write += 1.0
        finally:
            self.write(out)
            out.close()
            ticker.cancel()
            lag.cancel()
            for b in self.bots:
                if b.ws is not None:
                    b.ws.close()
            for t in tasks:
                t.cancel()

    async def ticker(self):
        loop = asyncio.get_running_loop()
        dt = 1.0 / self.hz
        nxt = loop.time()
        tick_no = 0
        while True:
            now = loop.time()
            if now - nxt > 4 * dt:      # far behind: skip ahead rather than burst (bots move slower)
                self.totals.tick_behind += int((now - nxt) / dt)
                nxt = now
            tick_no += 1
            for b in self.bots:
                if b.state in ("walking", "spreading"):
                    try:
                        b.tick(tick_no, now)
                    except Exception as e:  # noqa: BLE001 - one bot's fault must not stop every bot's ticks
                        b.die("tick: %s: %s" % (type(e).__name__, e))
            nxt += dt
            await asyncio.sleep(max(0.0, nxt - loop.time()))

    async def lag_monitor(self):
        """How far behind the event loop is: the wait for a callback queued now to run (by the fine clock).
        Not a sleep's lateness: on Windows asyncio's own clock ticks every 15.6 ms, so that measures the clock."""
        loop = asyncio.get_running_loop()
        while True:
            await asyncio.sleep(0.02)
            t = time.perf_counter()
            fut = loop.create_future()
            loop.call_soon(fut.set_result, None)
            await fut
            self.totals.lag.append((time.perf_counter() - t) * 1000.0)

    def write(self, out):
        t = self.totals
        states = {}
        per_bot = []
        for b in self.bots:
            states[b.state] = states.get(b.state, 0) + 1
            if b.state != "new":
                per_bot.append([b.index, b.wire, b.raw, b.rows, b.msgs, len(b.seen), round(b.moved, 2),
                                1 if b.state == "walking" else 0])
            b.wire = b.raw = b.rows = b.msgs = 0
            b.moved = 0.0
            b.seen = set()
        line = {"t": time.time(), "states": states, "per_bot": per_bot,
                "rtt": {k: [round(x, 2) for x in v] for k, v in t.rtt.items()},
                "ack": [round(x, 2) for x in t.ack], "swaps": t.swaps, "swap_ms": [round(x, 2) for x in t.swap_ms],
                "errors": t.errors, "sub_errors": t.sub_errors, "tables": t.tables,
                "lag": [round(x, 2) for x in t.lag], "tick_behind": t.tick_behind,
                "deaths": self.deaths}
        out.write(json.dumps(line) + "\n")
        out.flush()
        self.totals = Totals()
        self.deaths = []


def load_hooks(root):
    """Each genre's `game/<genre>/load_bot.py`, in `shared/game.json` order (none in the template)."""
    with open(os.path.join(root, "shared", "game.json"), encoding="utf-8") as f:
        genres = json.load(f).get("genres", [])
    hooks = []
    for g in genres:
        path = os.path.join(root, "game", g, "load_bot.py")
        if os.path.exists(path):
            spec = importlib.util.spec_from_file_location("load_bot_" + g, path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            hooks.append(mod)
            print("bots: %s's hook (%s)" % (g, path), flush=True)
    return hooks


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--host", default="http://127.0.0.1:3000")
    p.add_argument("--db", required=True)
    p.add_argument("--interest", required=True, help="the interest dump (interest_dump.gd)")
    p.add_argument("--first", type=int, default=0)
    p.add_argument("--count", type=int, default=50)
    p.add_argument("--stats", required=True)
    p.add_argument("--stop", required=True, help="the bots leave once this file exists")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--area-cells", type=int, default=8, help="the square the bots walk in, in cells a side")
    p.add_argument("--speed", type=float, default=0.0, help="m/s; 0 = the game's run_speed")
    p.add_argument("--connect-rate", type=float, default=10.0, help="bots connected a second")
    p.add_argument("--no-spread", action="store_true", help="start everyone at the spawn instead of across the area")
    p.add_argument("--no-hooks", action="store_true")
    a = p.parse_args()
    if not a.db.endswith("-test"):
        raise SystemExit("bots: '%s' is not a test database (<database>-test): bots never join a play database" % a.db)
    asyncio.run(Swarm(a).main())


if __name__ == "__main__":
    main()
