"""The load test's own parts (DECISIONS #284), without a server: the cells twin, BSATN from a schema, the
v3 messages, the WebSocket frames, and the arithmetic of a step. Run by tests/load_test.sh
(python -m unittest tests/load/test_load.py)."""
import json
import math
import os
import pathlib
import struct
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "load"))
import cells  # noqa: E402
import load_test  # noqa: E402
import wire  # noqa: E402


class TheCells(unittest.TestCase):
    """The twin of Cells / cell.rs, held to the same cases (shared/golden/cells.json)."""

    def setUp(self):
        self.golden = json.loads((ROOT / "shared" / "golden" / "cells.json").read_text(encoding="utf-8"))
        self.c = cells.Cells(self.golden["cell_m"], 1, 4.0)

    def test_every_golden_case(self):
        for case in self.golden["cases"]:
            self.assertEqual(self.c.chunk_of(case["x"], case["z"]), case["chunk"], case)

    def test_the_cases_catch_truncation(self):
        # Truncating instead of flooring (the classic slip) must fail at least one case, or they prove nothing.
        wrong = cells.Cells(self.golden["cell_m"])
        wrong.axis = lambda v: max(-cells.HALF, min(cells.HALF - 1, int(v / wrong.cell_m)))
        self.assertTrue(any(wrong.chunk_of(k["x"], k["z"]) != k["chunk"] for k in self.golden["cases"]))

    def test_a_ring_is_nine_cells_and_less_at_the_edge(self):
        centre = self.c.chunk_of(10, 10)
        ring = self.c.ring(centre)
        self.assertEqual(len(set(ring)), 9)
        self.assertIn(centre, ring)
        self.assertEqual(len(self.c.ring(cells.Cells.at(-cells.HALF, -cells.HALF))), 4)

    def test_recentre_waits_for_the_margin_and_jumps_at_once(self):
        c0 = self.c.chunk_of(10, 10)
        self.assertEqual(self.c.recentre(-1, 10, 10), c0)
        self.assertEqual(self.c.recentre(c0, 66, 10), c0, "2 m into the next cell: not yet")
        self.assertEqual(self.c.recentre(c0, 70, 10), self.c.chunk_of(70, 10), "6 m in: moved")
        self.assertEqual(self.c.recentre(c0, 300, 10), self.c.chunk_of(300, 10), "a jump: at once")
        # Along an edge it did not cross: still a move once deep enough on the axis it did cross.
        self.assertEqual(self.c.recentre(c0, 70, 63.5), self.c.chunk_of(70, 63.5))


SCHEMA = {
    "typespace": {"types": [
        {"Product": {"elements": [{"name": {"some": "x"}, "algebraic_type": {"F32": []}},
                                  {"name": {"some": "y"}, "algebraic_type": {"F32": []}},
                                  {"name": {"some": "z"}, "algebraic_type": {"F32": []}}]}},
        {"Product": {"elements": [{"name": {"some": "entity_id"}, "algebraic_type": {"U64": []}},
                                  {"name": {"some": "world_id"}, "algebraic_type": {"U32": []}},
                                  {"name": {"some": "pos"}, "algebraic_type": {"Ref": 0}},
                                  {"name": {"some": "grounded"}, "algebraic_type": {"Bool": []}},
                                  {"name": {"some": "name"}, "algebraic_type": {"String": []}},
                                  {"name": {"some": "tags"}, "algebraic_type": {"Array": {"U8": []}}},
                                  {"name": {"some": "hits"}, "algebraic_type": {"Array": {"U32": []}}},
                                  {"name": {"some": "target"}, "algebraic_type": {"Sum": {"variants": [
                                      {"name": {"some": "some"}, "algebraic_type": {"U64": []}},
                                      {"name": {"some": "none"}, "algebraic_type": {"Product": {"elements": []}}}]}}},
                                  {"name": {"some": "who"}, "algebraic_type": {"Product": {"elements": [
                                      {"name": {"some": "__identity__"}, "algebraic_type": {"U256": []}}]}}}]}},
        {"Product": {"elements": [{"name": {"some": "identity"}, "algebraic_type": {"Product": {"elements": [
                                      {"name": {"some": "__identity__"}, "algebraic_type": {"U256": []}}]}}},
                                  {"name": {"some": "entity_id"}, "algebraic_type": {"U64": []}},
                                  {"name": {"some": "name"}, "algebraic_type": {"String": []}}]}},
    ]},
    "tables": [{"name": "thing", "product_type_ref": 1}, {"name": "player", "product_type_ref": 2}],
    "reducers": [{"name": "do_it", "params": {"elements": [
        {"name": {"some": "things"}, "algebraic_type": {"Array": {"Ref": 1}}},
        {"name": {"some": "n"}, "algebraic_type": {"U32": []}}]}}],
}


class TheCodec(unittest.TestCase):
    def setUp(self):
        self.s = wire.Schema(SCHEMA)
        self.thing = {"entity_id": 7, "world_id": 2, "pos": {"x": 1.5, "y": -2.0, "z": 0.25}, "grounded": True,
                      "name": "Bot 7", "tags": b"\x01\x02", "hits": [3, 4], "target": None, "who": "0x" + "ab" * 32}

    def test_bytes_as_bsatn_lays_them_out(self):
        got = self.s.encoder({"Ref": 1})(self.thing)
        want = (struct.pack("<QI", 7, 2) + struct.pack("<fff", 1.5, -2.0, 0.25) + b"\x01" +
                struct.pack("<I", 5) + b"Bot 7" + struct.pack("<I", 2) + b"\x01\x02" +
                struct.pack("<III", 2, 3, 4) + b"\x01" + bytes.fromhex("ab" * 32))
        self.assertEqual(got, want)

    def test_round_trip(self):
        b = self.s.encoder({"Ref": 1})(dict(self.thing, target=99))
        back = self.s.row_decoder("thing")(wire.Reader(memoryview(b)))
        self.assertEqual(back["entity_id"], 7)
        self.assertEqual(back["pos"], {"x": 1.5, "y": -2.0, "z": 0.25})
        self.assertEqual(back["name"], "Bot 7")
        self.assertEqual(back["hits"], [3, 4])
        self.assertEqual(back["target"], 99)
        self.assertEqual(back["who"], int("ab" * 32, 16))

    def test_a_reducer_by_name(self):
        args = self.s.reducer_args("do_it", [[self.thing], 5])
        self.assertTrue(args.startswith(struct.pack("<I", 1)))
        self.assertTrue(args.endswith(struct.pack("<I", 5)))
        with self.assertRaises(ValueError):
            self.s.reducer_args("do_it", [[self.thing]])
        with self.assertRaises(KeyError):
            self.s.reducer_args("not_there", [])
        with self.assertRaises(KeyError):
            self.s.reducer_args("do_it", [[{"entity_id": 1}], 5])   # a missing field is loud, never zero

    def test_where_a_column_starts(self):
        self.assertEqual(self.s.column_offset("thing", "entity_id"), 0)
        self.assertEqual(self.s.column_offset("thing", "pos"), 12)
        self.assertEqual(self.s.column_offset("player", "entity_id"), 32)
        self.assertIsNone(self.s.column_offset("thing", "hits"), "after a string nothing is at a fixed place")


def row_list_fixed(rows):
    size = len(rows[0]) if rows else 0
    data = b"".join(rows)
    return b"\x00" + struct.pack("<H", size) + struct.pack("<I", len(data)) + data


def row_list_offsets(rows):
    offs, at = [], 0
    for r in rows:
        offs.append(at)
        at += len(r)
    data = b"".join(rows)
    return b"\x01" + struct.pack("<I", len(offs)) + b"".join(struct.pack("<Q", o) for o in offs) + \
        struct.pack("<I", len(data)) + data


class TheMessages(unittest.TestCase):
    def test_client_messages(self):
        m = wire.msg_subscribe(3, 9, ["SELECT * FROM a", "b"])
        self.assertEqual(m, b"\x00" + struct.pack("<III", 3, 9, 2) + struct.pack("<I", 15) + b"SELECT * FROM a" +
                         struct.pack("<I", 1) + b"b")
        self.assertEqual(wire.msg_unsubscribe(4, 9), b"\x01" + struct.pack("<II", 4, 9) + b"\x00")
        self.assertEqual(wire.msg_call_reducer(5, "go", b"\x07"),
                         b"\x03" + struct.pack("<I", 5) + b"\x00" + struct.pack("<I", 2) + b"go" + struct.pack("<I", 1) + b"\x07")

    def test_several_messages_in_one_frame(self):
        ident = bytes(range(32))
        initial = b"\x00" + ident + bytes(16) + struct.pack("<I", 3) + b"tok"
        applied = b"\x01" + struct.pack("<II", 1, 2) + struct.pack("<I", 1) + struct.pack("<I", 5) + b"thing" + \
            row_list_fixed([b"aaaa", b"bbbb", b"cccc"])
        tx = b"\x04" + struct.pack("<I", 1) + struct.pack("<II", 2, 1) + struct.pack("<I", 5) + b"thing" + \
            struct.pack("<I", 1) + b"\x00" + row_list_offsets([b"x", b"yyy"]) + row_list_fixed([b"zz"])
        err = b"\x06" + struct.pack("<I", 8) + struct.pack("<q", 123) + b"\x02" + \
            struct.pack("<I", 8) + struct.pack("<I", 4) + b"nope"
        ok = b"\x06" + struct.pack("<I", 9) + struct.pack("<q", 124) + b"\x01"
        msgs = wire.parse_server_messages(initial + applied + tx + err + ok)
        self.assertEqual([m[0] for m in msgs], [0, 1, 4, 6, 6])
        self.assertEqual(msgs[0][1], ident)
        self.assertEqual(msgs[0][3], "tok")
        self.assertEqual([bytes(r) for r in msgs[1][3][0][1]], [b"aaaa", b"bbbb", b"cccc"])
        qs, table, ins, dels = msgs[2][1][0]
        self.assertEqual((qs, table), (2, "thing"))
        self.assertEqual([bytes(r) for r in ins], [b"x", b"yyy"])
        self.assertEqual([bytes(r) for r in dels], [b"zz"])
        self.assertEqual(msgs[3][1:3], (8, "err"))
        self.assertEqual(wire.reducer_error_text(msgs[3][3]), "nope")
        self.assertEqual(msgs[4][1:3], (9, "ok"))

    def test_a_short_frame_is_an_error_not_a_guess(self):
        with self.assertRaises(ValueError):
            wire.parse_server_messages(b"\x01" + struct.pack("<II", 1, 2) + struct.pack("<I", 1))

    def test_compression(self):
        import gzip
        self.assertEqual(wire.decompress(b"\x00abc"), b"abc")
        self.assertEqual(wire.decompress(b"\x02" + gzip.compress(b"hello")), b"hello")
        with self.assertRaises(ValueError):
            wire.decompress(b"\x01xx")


def read_frame(b):
    """A server's reading of a client frame: (fin, opcode, payload)."""
    fin, op = b[0] & 0x80, b[0] & 0x0F
    masked, n = b[1] & 0x80, b[1] & 0x7F
    at = 2
    if n == 126:
        n = struct.unpack(">H", b[2:4])[0]
        at = 4
    elif n == 127:
        n = struct.unpack(">Q", b[2:10])[0]
        at = 10
    assert masked, "a client frame must be masked"
    mask = b[at:at + 4]
    return fin, op, wire.ws_unmask(mask, b[at + 4:at + 4 + n])


class TheWebSocket(unittest.TestCase):
    def test_frames_of_every_length(self):
        for n in (0, 1, 125, 126, 65535, 65536, 70000):
            payload = os.urandom(n)
            fin, op, back = read_frame(wire.ws_frame(2, payload))
            self.assertTrue(fin)
            self.assertEqual(op, 2)
            self.assertEqual(back, payload, n)

    def test_the_mask_is_applied(self):
        payload = b"\x00" * 64
        frame = wire.ws_frame(2, payload)
        self.assertNotEqual(frame[-64:], payload, "sent unmasked (a server must refuse that)")


class TheArithmetic(unittest.TestCase):
    def test_nearest_rank(self):
        v = list(range(1, 101))
        self.assertEqual(load_test.pct(v, 0.95), 95)
        self.assertEqual(load_test.pct(v, 0.5), 50)
        self.assertEqual(load_test.pct([7], 0.99), 7)
        self.assertIsNone(load_test.pct([], 0.5))

    def test_histogram_quantile_as_prometheus(self):
        text = "\n".join([
            '# HELP x', 'h_bucket{db="d",reducer="r",le="0.01"} 50', 'h_bucket{db="d",reducer="r",le="0.1"} 90',
            'h_bucket{db="d",reducer="r",le="+Inf"} 100', 'h_bucket{db="e",reducer="r",le="0.01"} 1000',
            'h_bucket{db="e",reducer="r",le="+Inf"} 1000'])
        after = load_test.parse_metrics(text)
        before = load_test.parse_metrics('h_bucket{db="d",reducer="r",le="0.01"} 10\nh_bucket{db="d",reducer="r",le="0.1"} 10\n'
                                         'h_bucket{db="d",reducer="r",le="+Inf"} 10')
        b = load_test.histogram(before, after, "h", {"db": "d", "reducer": "r"})
        self.assertEqual(b, [(0.01, 40.0), (0.1, 80.0), (math.inf, 90.0)])
        self.assertAlmostEqual(load_test.hist_quantile(b, 0.5), 0.01 + 0.09 * (45 - 40) / 40)
        self.assertEqual(load_test.hist_quantile(b, 0.95), 0.1, "past the last bound: the last bound")
        self.assertIsNone(load_test.hist_quantile([], 0.5))

    def test_means_and_busy_from_the_sums(self):
        """The bucketed p95 cannot tell 15 ms from 49 (buckets 10 and 50): the sums can, and they say how much of
        the module's one thread each reducer took."""
        def scrape(n, wall, plus, wait):
            # Each call is a Reducer and an Update transaction, alike in count (as the server's metrics are).
            rows = []
            for kind, secs in (("Reducer", wall), ("Update", wall / 10.0)):
                rows += ['spacetime_txn_elapsed_time_sec_bucket{db="d",reducer="tick",txn_type="%s",le="0.05"} %d' % (kind, n),
                         'spacetime_txn_elapsed_time_sec_bucket{db="d",reducer="tick",txn_type="%s",le="+Inf"} %d' % (kind, n),
                         'spacetime_txn_elapsed_time_sec_sum{db="d",reducer="tick",txn_type="%s"} %f' % (kind, secs)]
            return load_test.parse_metrics("\n".join(rows + [
                'spacetime_reducer_plus_query_duration_sec_sum{db="d",reducer="tick"} %f' % plus,
                'spacetime_reducer_wait_time_sec_sum{db="d",reducer="tick"} %f' % wait,
                'spacetime_reducer_plus_query_duration_sec_sum{db="e",reducer="tick"} 99']))
        before, after = scrape(100, 1.0, 1.5, 0.0), scrape(300, 3.0, 5.5, 0.4)
        srv = load_test.server_window(before, after, "d", [], 10.0)
        r = srv["reducers"]["tick"]
        self.assertEqual(r["calls"], 200, "a call counted once, not as its two transactions")
        self.assertAlmostEqual(r["wall_mean_ms"], 10.0, msg="the reducer's own time")
        self.assertAlmostEqual(r["update_mean_ms"], 1.0, msg="its subscription update, apart")
        self.assertAlmostEqual(r["plus_query_mean_ms"], 20.0)
        self.assertAlmostEqual(r["wait_mean_ms"], 2.0)
        self.assertAlmostEqual(r["busy_ms_per_s"], 400.0, msg="4 s of 10, another database's not counted")
        self.assertAlmostEqual(srv["module_busy"], 0.4)
        self.assertIsNone(load_test.server_window(before, after, "d", [])["module_busy"], "no window: no share")

    def lines(self, missing=None, refused=False, quiet=None, played=False, gone=False):
        out = []
        for s in range(1, 11):
            per = []
            for i in range(4):
                if i == missing:
                    continue
                rows = 0 if i == quiet else 100
                per.append([i, 2048, 4096, rows, 20, 3, 5.0, 1])
            out.append({"t": 1000.0 + s, "states": {"walking": 4}, "per_bot": per, "rtt": {"submit_input": [5.0] * 20},
                        "ack": [40.0] * 20, "swaps": 1, "swap_ms": [30.0], "errors": ({"x: no": 1} if refused and s == 3 else {}) | (
                            {"use_ability: use_ability: nobody is judging world 0 (no referee)": 3} if gone and s == 5 else {}),
                        "expected": {"gather: worked out": 2} if played and s in (3, 4) else {},
                        "sub_errors": [], "tables": {"movement_state": 400}, "lag": [1.0] * 50, "tick_behind": 0, "deaths": []})
        return out

    def test_a_step_summed_up(self):
        w = load_test.window(self.lines(), 1000.0, 1010.0, 4)
        self.assertEqual(w["bots_walking_throughout"], 4)
        self.assertAlmostEqual(w["client_kb_per_s"]["mean"], 2.0)
        self.assertAlmostEqual(w["client_rows_per_s"]["p95"], 100.0)
        self.assertAlmostEqual(w["ring_swaps_per_bot_min"], 10 / 4 / (10 / 60.0))
        self.assertAlmostEqual(w["calls_per_s"]["submit_input"], 20.0)
        w["_min_neighbours_seen"] = 3
        self.assertTrue(all(ok for _, ok in load_test.harness_checks(w, True)))

    def test_the_harness_checks_catch_what_they_say(self):
        for kw, word in ((dict(missing=2), "walking"), (dict(refused=True), "refused"), (dict(quiet=1), "sent rows")):
            w = load_test.window(self.lines(**kw), 1000.0, 1010.0, 4)
            w["_min_neighbours_seen"] = 3
            failed = [t for t, ok in load_test.harness_checks(w, True) if not ok]
            self.assertTrue(any(word in t for t in failed), (kw, failed))

    def test_a_refusal_the_game_expects_is_counted_never_judged(self):
        w = load_test.window(self.lines(played=True), 1000.0, 1010.0, 4)
        w["_min_neighbours_seen"] = 3
        self.assertEqual(w["refused_in_play"], {"gather: worked out": 4})
        self.assertEqual(w["refused"], {})
        checks = load_test.harness_checks(w, True)
        self.assertTrue(all(ok for _, ok in checks), checks)
        self.assertTrue(any("refused in play" in t and "x4" in t for t, _ in checks))
        w = load_test.window(self.lines(played=True, refused=True), 1000.0, 1010.0, 4)
        w["_min_neighbours_seen"] = 3
        self.assertTrue(any("nothing was refused" in t for t, ok in load_test.harness_checks(w, True) if not ok),
                        "an unexpected refusal still fails beside an expected one")

    def test_a_referee_gone_breaks_the_step_not_the_harness(self):
        w = load_test.window(self.lines(gone=True), 1000.0, 1010.0, 4)
        w["_min_neighbours_seen"] = 3
        self.assertEqual(w["refused"], {})
        self.assertEqual(w["refused_referee_gone"], 3)
        self.assertTrue(all(ok for _, ok in load_test.harness_checks(w, True)))
        lim, _ = load_test.limits_checks(w, {"reducers": {}}, None, {"referee_gone_refusals": 0}, 20)
        self.assertEqual(lim, [("referee_gone_refusals", 3, 0, False)])

    def test_limits(self):
        w = load_test.window(self.lines(), 1000.0, 1010.0, 4)
        srv = {"reducers": {"tick_movement": {"wall_p95_ms": 60.0, "wait_p95_ms": 1.0}}}
        lim, valid = load_test.limits_checks(w, srv, None, {"tick_movement_p95_ms": 50, "input_ack_p95_ms": 250,
                                                             "client_kb_per_s_p95": None}, 20)
        got = {name: holds for name, _, _, holds in lim}
        self.assertEqual(got, {"tick_movement_p95_ms": False, "input_ack_p95_ms": True, "client_kb_per_s_p95": None})
        self.assertTrue(valid)
        lim, valid = load_test.limits_checks(w, srv, None, {}, 0.5)
        self.assertFalse(valid, "bots whose loop is late by more than the limit make the step invalid")


    def test_regions_cover_the_world_split_in_the_bots_square(self):
        self.assertEqual(load_test.regions([1, 1], 8), [], "one referee: no regions")
        four = load_test.regions([2, 2], 8)
        self.assertEqual(four, ["-512,-512,-1,-1", "-512,0,-1,511", "0,-512,511,-1", "0,0,511,511"])
        three = load_test.regions(["3", "1"], 8)
        xs = [tuple(int(v) for v in r.split(",")) for r in three]
        self.assertEqual(xs[0][0], -512, "the first runs to the grid's west edge")
        self.assertEqual(xs[-1][2], 511, "the last to its east")
        for a, b in zip(xs, xs[1:]):
            self.assertEqual(a[2] + 1, b[0], "neighbours meet, with no gap and no overlap")

    def test_regions_where_the_bots_live_share_them_out(self):
        # Most bots in a town of a few cells at (1000, 1000), the rest strung out west: an even cut of the square would give one
        # referee nearly all of them; cut where they live, each column and each row holds its share.
        pts = [(1000.0 + 25.0 * (i % 10), 1000.0 + 25.0 * (i // 10)) for i in range(60)] + [(-3000.0 + 50 * i, 200.0 * (i % 7)) for i in range(40)]
        cuts = [tuple(int(v) for v in r.split(",")) for r in load_test.regions_by_homes([2, 2], pts, 64.0)]
        self.assertEqual(len(cuts), 4)
        self.assertEqual(load_test.regions_by_homes([1, 1], pts, 64.0), [])

        def inside(r, p):
            cx, cz = math.floor(p[0] / 64.0), math.floor(p[1] / 64.0)
            return r[0] <= cx <= r[2] and r[1] <= cz <= r[3]
        for p in pts:
            self.assertEqual(sum(1 for r in cuts if inside(r, p)), 1, "every bot is in exactly one region: %s" % (p,))
        counts = [sum(1 for p in pts if inside(r, p)) for r in cuts]
        self.assertLessEqual(max(counts), 40, "no region holds most of them (%s)" % counts)
        self.assertEqual(min(c[0] for c in cuts), -512)
        self.assertEqual(max(c[2] for c in cuts), 511)
        # Everyone in one cell still makes valid, strictly ordered regions (no two share a column).
        same = load_test.regions_by_homes([3, 1], [(5.0, 5.0)] * 30, 64.0)
        xs = [tuple(int(v) for v in r.split(",")) for r in same]
        for a, b in zip(xs, xs[1:]):
            self.assertEqual(a[2] + 1, b[0])
            self.assertLessEqual(b[0], b[2])

    def test_a_spread_world_needs_only_some_bots_to_see_others(self):
        w = load_test.window(self.lines(), 1000.0, 1010.0, 4)
        w["_min_neighbours_seen"] = 0
        w["_bots_saw_others"] = 2
        self.assertTrue(any("every bot saw others" in t for t, ok in load_test.harness_checks(w, True) if not ok),
                        "in a square, a bot seeing nobody is the harness failing")
        self.assertTrue(all(ok for _, ok in load_test.harness_checks(w, True, over_level=True)),
                        "over a world, a bot alone in the wilds is play")
        w["_bots_saw_others"] = 0
        self.assertFalse(all(ok for _, ok in load_test.harness_checks(w, True, over_level=True)), "but nobody seeing anyone is not")


class TheLevel(unittest.TestCase):
    """`level.py`: land, the ground's height, and where each bot lives, from a level's bake."""

    def setUp(self):
        import tempfile
        self.dir = tempfile.mkdtemp()
        # A 9 x 9 grid at 10 m from (0, 0): the sea in its east third, the ground rising 1 m every 10 m east and
        # 0.5 m every 10 m south, no ground at all in one corner sample.
        depth = bytearray(9 * 9)
        for j in range(9):
            for i in range(6, 9):
                depth[j * 9 + i] = 20
        ground = []
        for j in range(9):
            for i in range(9):
                ground.append(65535 if (i, j) == (0, 8) else int(round((i * 1.0 + j * 0.5 + 10.0) * 10)))
        with open(os.path.join(self.dir, "t_depth.bin"), "wb") as f:
            f.write(bytes(depth))
        with open(os.path.join(self.dir, "t_ground.bin"), "wb") as f:
            f.write(struct.pack("<%dH" % len(ground), *ground))
        self.doc = {"level": "t", "id": 7, "spawn": [20.0, 0.0, 20.0], "water_y": 0.0,
                    "points": [{"kind": "wolf", "x": 1.0, "z": 2.0}, {"kind": "tree", "x": 3.0, "z": 4.0},
                               {"kind": "bear", "x": 5.0, "z": 6.0}],
                    "depth_grid": {"file": "t_depth.bin", "origin_x": 0.0, "origin_z": 0.0, "spacing": 10.0, "width": 9, "height": 9},
                    "ground_grid": {"file": "t_ground.bin", "origin_x": 0.0, "origin_z": 0.0, "spacing": 10.0, "width": 9,
                                    "height": 9, "base_y": -10.0}}
        import level
        self.L = level
        self.lvl = level.Level(self.doc, self.dir)

    def test_land_and_sea(self):
        self.assertTrue(self.lvl.dry(20.0, 20.0))
        self.assertFalse(self.lvl.dry(70.0, 20.0), "the sea is not land")
        self.assertFalse(self.lvl.dry(-5.0, 20.0), "nor is off the level")
        self.assertFalse(self.lvl.dry(1.0, 79.0), "nor where no ray hit the ground")
        self.assertTrue(self.lvl.segment_dry((10.0, 10.0), (50.0, 40.0)))
        self.assertFalse(self.lvl.segment_dry((10.0, 10.0), (80.0, 10.0)), "a walk into the sea is not dry")

    def test_the_ground_between_samples(self):
        self.assertAlmostEqual(self.lvl.ground(20.0, 20.0), -10.0 + 2.0 + 1.0 + 10.0)
        self.assertAlmostEqual(self.lvl.ground(25.0, 20.0), -10.0 + 2.5 + 1.0 + 10.0, places=4)
        self.assertAlmostEqual(self.lvl.ground(20.0, 25.0), -10.0 + 2.0 + 1.25 + 10.0, places=4)
        self.assertIsNone(self.lvl.ground(-1.0, 0.0))
        flat = self.L.Level(dict(self.doc, ground_grid=None), self.dir)
        self.assertFalse(flat.has_ground())
        self.assertIsNone(flat.ground(20.0, 20.0), "a level baked without its ground has none")

    def test_the_npcs_a_referee_runs(self):
        self.assertEqual(sorted(self.L.npc_points(self.lvl, ["wolf", "bear"])), [(1.0, 2.0), (5.0, 6.0)])
        self.assertEqual(self.L.npc_points(self.lvl, []), [], "no npc_kinds: the cut is by players alone")

    def test_homes_are_the_same_everywhere_and_on_land(self):
        spread = self.L.spread_of({"spread": {"over": "level", "crowd_share": 0.5, "crowd_cells": 0.3, "roam_cells": 1}})
        a = self.L.homes(40, 3, spread, self.lvl, 8, 64.0)
        b = self.L.homes(40, 3, spread, self.lvl, 8, 64.0)
        self.assertEqual(a, b, "the harness and every bot process compute the same homes")
        self.assertNotEqual(a, self.L.homes(40, 4, spread, self.lvl, 8, 64.0), "another seed, other homes")
        self.assertTrue(all(self.lvl.dry(*p) for p in a), "every home on land")
        near = sum(1 for p in a if abs(p[0] - 20.0) <= 9.6 and abs(p[1] - 20.0) <= 9.6)
        self.assertGreaterEqual(near, 12, "about half live round the spawn (%d of 40)" % near)
        self.assertEqual(self.L.home_of(5, 3, spread, self.lvl, 8, 64.0), a[5], "one bot's home on its own is the same")
        square = self.L.spread_of({})
        self.assertEqual(square["over"], "square")
        self.assertTrue(all(abs(x) <= 256.0 and abs(z) <= 256.0 for x, z in self.L.homes(20, 3, square, self.lvl, 8, 64.0)))


class TheMachine(unittest.TestCase):
    """What a process costs: this one, measured."""

    def test_this_process(self):
        u = load_test.proc_usage(os.getpid())
        self.assertIsNotNone(u)
        self.assertGreaterEqual(u[0], 0.0)
        self.assertGreater(u[1], 1.0, "a Python process holds more than a megabyte")
        self.assertIsNone(load_test.proc_usage(2 ** 30), "a process that is not there")
        use = load_test.Usage({"me": os.getpid(), "nobody": None})
        use.sample()
        t = __import__("time").time()
        while __import__("time").time() < t + 0.3:
            sum(i * i for i in range(10000))
        use.sample()
        got = use.result()
        self.assertEqual(list(got), ["me"])
        self.assertGreater(got["me"]["cores"], 0.2, "busy for the window: most of a core")
        m = load_test.machine()
        self.assertGreater(m["cpus"], 0)

    def test_each_referee_by_who_sent_it(self):
        row = {"frame_ms_p_95": 5.0, "frame_ms_p_99": 6.0, "frame_ms_max": 9.0, "fps": 60.0, "spikes": 0, "rtt_ms": 1.0,
               "rtt_ms_max": 2.0, "entities": 10, "memory_mb": 300.0}
        rows = [dict(row, detail=json.dumps({"who": "load_r0 cells 0,0 to 3,3"})),
                dict(row, frame_ms_p_95=9.0, detail=json.dumps({"who": "load_r0 cells 0,0 to 3,3"})),
                dict(row, detail=json.dumps({"who": "load_r1 cells 4,0 to 9,3"})),
                dict(row, detail="{}", identity=["0x00ab12cd34"])]
        per = load_test.referees_summary(rows)
        self.assertEqual(sorted(per), ["load_r0 cells 0,0 to 3,3", "load_r1 cells 4,0 to 9,3", "referee ab12cd34"])
        self.assertEqual(per["load_r0 cells 0,0 to 3,3"]["frame_p95_ms"], 9.0, "a referee's worst window")
        self.assertEqual(per["load_r0 cells 0,0 to 3,3"]["windows"], 2)

    def test_referees_from_their_logs(self):
        import tempfile
        d = tempfile.mkdtemp()
        path = os.path.join(d, "referee_2.log")
        with open(path, "w", encoding="utf-8") as f:
            f.write("Godot Engine\n[Sidecar] process 4242 load_r2\n[Sidecar] a region referee: cells 0,0 to 3,3\n")
        bare = os.path.join(d, "referee.log")
        with open(bare, "w", encoding="utf-8") as f:
            f.write("[Sidecar] process 77\n")
        got = load_test.referees_from_logs([path, bare, os.path.join(d, "missing.log")])
        self.assertEqual(got[0], {"log": path, "name": "load_r2", "pid": 4242, "region": "cells 0,0 to 3,3"})
        self.assertEqual((got[1]["name"], got[1]["pid"]), ("referee", 77), "one with no name is its log's")
        self.assertIsNone(got[2]["pid"])


class TheSweep(unittest.TestCase):
    """tests/referee_sweep.sh's table: the fewest referees that held with room, from the reports."""

    def report(self, d, label, n_refs, frames, holds=True, busy=0.5):
        refs = {"load_r%d cells" % i: {"frame_p95_ms": f, "net_stalls": 0} for i, f in enumerate(frames)}
        lim = [["referee_frame_p95_ms", max(frames), 50, max(frames) <= 50], ["module_busy_pct", busy * 100, 80, busy <= 0.8]]
        step = {"bots_n": 300, "holds": holds and max(frames) <= 50 and busy <= 0.8, "valid": True, "checks": [["ok", True]],
                "limits": lim, "referees": refs, "server": {"module_busy": busy},
                "usage": {"load_r%d" % i: {"cores": 0.5, "memory_mb": 600.0} for i in range(n_refs)},
                "machine": {"cpus": 18, "memory_gb": 31.4}}
        os.makedirs(os.path.join(d, label), exist_ok=True)
        with open(os.path.join(d, label, "report.json"), "w", encoding="utf-8") as f:
            json.dump({"referees_n": n_refs, "steps": [step]}, f)

    def test_the_fewest_with_room(self):
        import tempfile
        import sweep_report
        d = tempfile.mkdtemp()
        sweep_report.OUT = d
        self.report(d, "a", 1, [140.0])
        self.report(d, "b", 4, [40.0, 30.0, 20.0, 10.0])
        self.report(d, "c", 6, [20.0, 18.0, 12.0, 9.0, 8.0, 5.0])
        self.report(d, "e", 9, [9.0] * 9)
        sweep_report.main(["a", "b", "c", "e"], quiet=True)
        text = pathlib.Path(d, "sweep.md").read_text(encoding="utf-8")
        self.assertIn("**6 referees hold 300 bots with room**", text, "4 hold but at 40 of 50: not with room")
        self.assertIn("| 1 | 140.0 |", text)
        self.assertIn("they took 3.0 cores and 3600 MB here", text)
        sweep_report.main(["a"], quiet=True)
        self.assertIn("**No cut tried held 300 bots**", pathlib.Path(d, "sweep.md").read_text(encoding="utf-8"))
        self.report(d, "s", 9, [9.0] * 9, busy=0.95)
        sweep_report.main(["s"], quiet=True)
        text = pathlib.Path(d, "sweep.md").read_text(encoding="utf-8")
        self.assertIn("more referees do not help", text, "a step broken on the server's limit says so")


if __name__ == "__main__":
    unittest.main()
