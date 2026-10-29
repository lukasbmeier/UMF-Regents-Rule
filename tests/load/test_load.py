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

    def lines(self, missing=None, refused=False, quiet=None, played=False):
        out = []
        for s in range(1, 11):
            per = []
            for i in range(4):
                if i == missing:
                    continue
                rows = 0 if i == quiet else 100
                per.append([i, 2048, 4096, rows, 20, 3, 5.0, 1])
            out.append({"t": 1000.0 + s, "states": {"walking": 4}, "per_bot": per, "rtt": {"submit_input": [5.0] * 20},
                        "ack": [40.0] * 20, "swaps": 1, "swap_ms": [30.0], "errors": {"x: no": 1} if refused and s == 3 else {},
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


if __name__ == "__main__":
    unittest.main()
