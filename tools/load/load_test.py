"""THE LOAD TEST (DECISIONS #284): steps of bots on a TEST database, each measured, until a limit breaks.

For each step (50, then 100, then 300 bots: `shared/load.json`), it adds bots (`bots.py`, one process per
50), lets them settle, then measures for `measure_s`:
  - per client: rows and bytes a second (wire bytes, gzip; and as decoded), distinct neighbours seen;
  - reducers: each bot's round trip per reducer (p50/p95/p99), and from the SERVER's own metrics
    (`/v1/metrics`, this database only) each reducer's wall time and its wait in the queue, p95;
  - input to server: from a batch of inputs sent to the movement row saying it was processed;
  - ring interest: cell swaps a bot a minute, and how long a new ring took to apply;
  - the referee: its own reports (`perf_report`, role 1): frame time p95/p99/worst, spikes, net stalls;
  - the bots themselves: their event loop's lateness, so a slow bot process is not mistaken for a slow server.
The checks that the HARNESS worked must all pass (every bot connected, walking, sent rows, crossing cells,
nothing refused); the LIMITS say whether the game held at that step. Results: build/load/<label>.json, .md.

  python tools/load/load_test.py --db umf-template-test --interest build/load/interest.json [--steps 50,100,300]

Run it through tests/load_test.sh, which publishes the test database, starts a referee and dumps the interest.
"""
import argparse
import datetime
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ROLE_REFEREE = 1
# The referee's report window during the test (tests/load_test.sh sets foundation.telemetry_window_s).
REF_WINDOW_S = 10.0


# =============================================================================
# NUMBERS
# =============================================================================

def pct(values, q):
    """The q-th fraction (0..1) of `values`, nearest rank (as Telemetry.summary does); None if empty."""
    if not values:
        return None
    s = sorted(values)
    i = max(0, min(len(s) - 1, int(-(-q * len(s) // 1)) - 1))
    return s[i]


def summary(values):
    return {"n": len(values), "p50": pct(values, 0.5), "p95": pct(values, 0.95), "p99": pct(values, 0.99),
            "max": max(values) if values else None, "mean": sum(values) / len(values) if values else None}


def parse_metrics(text):
    """Prometheus text -> {(name, frozenset(labels)): value}."""
    out = {}
    for line in text.splitlines():
        if not line or line[0] == "#":
            continue
        try:
            head, value = line.rsplit(" ", 1)
            if "{" in head:
                name, rest = head.split("{", 1)
                labels = []
                for part in rest.rstrip("}").split('",'):
                    if "=" in part:
                        k, v = part.split("=", 1)
                        labels.append((k.strip(), v.strip().strip('"')))
                key = (name, frozenset(labels))
            else:
                key = (head, frozenset())
            out[key] = float(value)
        except ValueError:
            continue
    return out


def histogram(before, after, name, match):
    """The histogram `name`'s counts between two scrapes, for series whose labels include `match`:
    [(upper bound in s, cumulative count)]."""
    buckets = {}
    for (n, labels), v in after.items():
        if n != name + "_bucket":
            continue
        d = dict(labels)
        if any(d.get(k) != val for k, val in match.items()):
            continue
        le = d.get("le")
        prev = before.get((n, labels), 0.0)
        bound = float("inf") if le == "+Inf" else float(le)
        buckets[bound] = buckets.get(bound, 0.0) + (v - prev)
    return sorted(buckets.items())


def hist_quantile(buckets, q):
    """Prometheus's histogram_quantile: linear inside the bucket the rank falls in. None with no counts."""
    if not buckets or buckets[-1][1] <= 0:
        return None
    total = buckets[-1][1]
    rank = q * total
    lo_bound, lo_count = 0.0, 0.0
    for bound, count in buckets:
        if count >= rank:
            if bound == float("inf"):
                return lo_bound
            if count == lo_count:
                return bound
            return lo_bound + (bound - lo_bound) * (rank - lo_count) / (count - lo_count)
        lo_bound, lo_count = bound, count
    return lo_bound


def gauge(m, name, match):
    vals = [v for (n, labels), v in m.items() if n == name and all(dict(labels).get(k) == val for k, val in match.items())]
    return sum(vals) if vals else 0.0


# =============================================================================
# THE SERVER AND THE DATABASE
# =============================================================================

def scrape(host):
    with urllib.request.urlopen(host + "/v1/metrics", timeout=10) as r:
        return parse_metrics(r.read().decode("utf-8", "replace"))


def database_identity(host, db):
    with urllib.request.urlopen("%s/v1/database/%s" % (host, db), timeout=10) as r:
        doc = json.load(r)
    ident = doc["database_identity"]
    ident = ident.get("__identity__", "") if isinstance(ident, dict) else ident
    return ident[2:].lower() if ident.startswith("0x") else ident.lower()


def sql(db, query):
    """The owner's CLI (it sees private tables): `wire.owner_sql`."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import wire  # noqa: E402
    return wire.owner_sql(db, query)


def referee_windows(db, t0, t1):
    """The referee's perf reports that ended inside [t0, t1] (unix seconds)."""
    try:
        rows = sql(db, "SELECT * FROM perf_report WHERE role = %d" % ROLE_REFEREE)
    except RuntimeError as e:
        return None, str(e)
    out = []
    for r in rows:
        at = r.get("at", 0) / 1e6
        if t0 <= at <= t1:
            out.append(r)
    return out, ""


def referee_summary(rows):
    if not rows:
        return None
    stalls = 0
    worst_stall = 0.0
    for r in rows:
        try:
            for s in json.loads(r.get("detail") or "{}").get("spikes", []):
                if len(s) >= 3 and s[2] == "net":
                    stalls += 1
                    worst_stall = max(worst_stall, float(s[1]))
        except (ValueError, TypeError):
            pass
    return {
        "windows": len(rows),
        "frame_p95_ms": max(r["frame_ms_p_95"] for r in rows),
        "frame_p99_ms": max(r["frame_ms_p_99"] for r in rows),
        "frame_max_ms": max(r["frame_ms_max"] for r in rows),
        "fps": min(r["fps"] for r in rows),
        "spikes": sum(r["spikes"] for r in rows),
        "net_stalls": stalls,
        "worst_stall_ms": worst_stall,
        "rtt_ms": max(r["rtt_ms"] for r in rows),
        "rtt_max_ms": max(r["rtt_ms_max"] for r in rows),
        "entities": max(r["entities"] for r in rows),
        "memory_mb": max(r["memory_mb"] for r in rows),
    }


# =============================================================================
# THE BOTS
# =============================================================================

class Workers:
    def __init__(self, a, out_dir):
        self.a = a
        self.dir = out_dir
        self.procs = []
        self.stats = []
        self.stop = os.path.join(out_dir, "stop")
        if os.path.exists(self.stop):
            os.remove(self.stop)
        self.count = 0

    def add(self, n):
        while n > 0:
            k = min(n, self.a.per_proc)
            i = len(self.procs)
            stats = os.path.join(self.dir, "w%d.jsonl" % i)
            if os.path.exists(stats):
                os.remove(stats)
            cmd = [sys.executable, os.path.join(HERE, "bots.py"), "--host", self.a.host, "--db", self.a.db,
                   "--interest", self.a.interest, "--first", str(self.count), "--count", str(k), "--stats", stats,
                   "--stop", self.stop, "--seed", str(self.a.seed), "--area-cells", str(self.a.area_cells),
                   "--connect-rate", str(self.a.connect_rate)]
            if self.a.no_spread:
                cmd.append("--no-spread")
            log = open(os.path.join(self.dir, "w%d.log" % i), "w", encoding="utf-8")
            self.procs.append((subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT), log))
            self.stats.append(stats)
            self.count += k
            n -= k

    def lines(self, since=0.0):
        out = []
        for path in self.stats:
            if not os.path.exists(path):
                continue
            with open(path, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            d = json.loads(line)
                        except ValueError:
                            continue
                        if d["t"] >= since:
                            out.append(d)
        return out

    def latest_states(self):
        latest = {}
        for path in self.stats:
            if not os.path.exists(path):
                continue
            last = None
            with open(path, encoding="utf-8") as f:
                for line in f:
                    if line.strip():
                        last = line
            if last:
                try:
                    latest[path] = json.loads(last)["states"]
                except ValueError:
                    pass
        total = {}
        for s in latest.values():
            for k, v in s.items():
                total[k] = total.get(k, 0) + v
        return total

    def dead_workers(self):
        return [i for i, (p, _) in enumerate(self.procs) if p.poll() is not None]

    def stop_all(self):
        with open(self.stop, "w") as f:
            f.write("stop")
        for p, log in self.procs:
            try:
                p.wait(timeout=15)
            except subprocess.TimeoutExpired:
                p.kill()
            log.close()


# A judged ability refused because the world's referee is gone (module/referee.rs): the GAME breaking under
# the load, a limit (`referee_gone_refusals`), never the harness's fault.
REFEREE_GONE = "nobody is judging world"


def window(lines, t0, t1, n_bots):
    """Everything the bots saw in [t0, t1], summed up."""
    secs = max(1e-6, t1 - t0)
    per = {}
    rtt = {}
    ack, swap_ms, lag = [], [], []
    swaps = 0
    errors, expected, tables = {}, {}, {}
    sub_errors, deaths = [], []
    tick_behind = 0
    for d in lines:
        if not (t0 < d["t"] <= t1):
            continue
        for idx, w, raw, rows, msgs, seen, moved, walking in d["per_bot"]:
            p = per.setdefault(idx, [0, 0, 0, 0, 0, 0.0, 0, 0])
            p[0] += w
            p[1] += raw
            p[2] += rows
            p[3] += msgs
            p[4] += seen
            p[5] += moved
            p[6] += walking
            p[7] += 1
        for k, v in d["rtt"].items():
            rtt.setdefault(k, []).extend(v)
        ack.extend(d["ack"])
        swap_ms.extend(d["swap_ms"])
        swaps += d["swaps"]
        lag.extend(d["lag"])
        tick_behind += d.get("tick_behind", 0)
        for k, v in d["errors"].items():
            errors[k] = errors.get(k, 0) + v
        for k, v in d.get("expected", {}).items():
            expected[k] = expected.get(k, 0) + v
        for k, v in d["tables"].items():
            tables[k] = tables.get(k, 0) + v
        sub_errors.extend(d["sub_errors"])
        deaths.extend(d["deaths"])
    walking_all = [i for i, p in per.items() if p[6] == p[7] and p[7] > 0]
    kb = [per[i][0] / secs / 1024.0 for i in walking_all]
    kb_raw = [per[i][1] / secs / 1024.0 for i in walking_all]
    rows = [per[i][2] / secs for i in walking_all]
    msgs = [per[i][3] / secs for i in walking_all]
    seen = [per[i][4] / per[i][7] for i in walking_all]   # others moving round it, a second on average
    moved = [per[i][5] for i in walking_all]
    minutes = secs / 60.0
    return {
        "seconds": secs,
        "bots_walking_throughout": len(walking_all),
        "bots_expected": n_bots,
        "client_kb_per_s": summary(kb),
        "client_kb_per_s_decoded": summary(kb_raw),
        "client_rows_per_s": summary(rows),
        "client_msgs_per_s": summary(msgs),
        "neighbours_seen": summary(seen),
        "bots_sent_no_rows": sum(1 for r in rows if r <= 0),
        "bots_not_moved": sum(1 for m in moved if m <= 0.5),
        "metres_moved_mean": sum(moved) / len(moved) if moved else 0.0,
        "rtt_ms": {k: summary(v) for k, v in sorted(rtt.items())},
        "calls_per_s": {k: len(v) / secs for k, v in sorted(rtt.items())},
        "input_ack_ms": summary(ack),
        "ring_swaps": swaps,
        "ring_swaps_per_bot_min": swaps / max(1, len(walking_all)) / minutes,
        "ring_swap_ms": summary(swap_ms),
        "rows_per_s_by_table": {k: v / secs for k, v in sorted(tables.items(), key=lambda kv: -kv[1])},
        "refused": {k: v for k, v in errors.items() if REFEREE_GONE not in k},
        "refused_referee_gone": sum(v for k, v in errors.items() if REFEREE_GONE in k),
        "refused_in_play": expected,
        "subscription_errors": sub_errors[:10],
        "disconnected": deaths[:10],
        "disconnected_count": len(deaths),
        "bot_loop_lag_ms": summary(lag),
        "bot_ticks_behind": tick_behind,
    }


def server_window(before, after, dbid, gauges):
    out = {"reducers": {}}
    names = set()
    for (n, labels) in after:
        if n == "spacetime_txn_elapsed_time_sec_bucket":
            d = dict(labels)
            if d.get("db") == dbid and d.get("reducer"):
                names.add(d["reducer"])
    for r in sorted(names):
        el = histogram(before, after, "spacetime_txn_elapsed_time_sec", {"db": dbid, "reducer": r})
        cpu = histogram(before, after, "spacetime_txn_cpu_time_sec", {"db": dbid, "reducer": r})
        wait = histogram(before, after, "spacetime_reducer_wait_time_sec", {"db": dbid, "reducer": r})
        calls = el[-1][1] if el else 0
        if calls <= 0:
            continue
        ms = lambda b, q: None if hist_quantile(b, q) is None else hist_quantile(b, q) * 1000.0  # noqa: E731
        out["reducers"][r] = {"calls": calls, "wall_p50_ms": ms(el, 0.5), "wall_p95_ms": ms(el, 0.95),
                              "wall_p99_ms": ms(el, 0.99), "cpu_p95_ms": ms(cpu, 0.95),
                              "wait_p95_ms": ms(wait, 0.95), "wait_p99_ms": ms(wait, 0.99)}
    out["outgoing_queue_disconnects"] = gauge(after, "spacetime_client_outgoing_queue_disconnects_total", {"db": dbid}) - \
        gauge(before, "spacetime_client_outgoing_queue_disconnects_total", {"db": dbid})
    out["max_send_queue"] = max([g[0] for g in gauges], default=0.0)
    out["max_outgoing_queue"] = max([g[1] for g in gauges], default=0.0)
    out["max_instance_queue"] = max([g[2] for g in gauges], default=0.0)
    return out


def sample_gauges(host, dbid):
    m = scrape(host)
    return (gauge(m, "spacetime_subscription_send_queue_length", {"database_identity": dbid}),
            gauge(m, "spacetime_total_outgoing_queue_length", {"db": dbid}),
            gauge(m, "spacetime_worker_instance_operation_queue_length", {"database_identity": dbid}))


# =============================================================================
# JUDGING A STEP
# =============================================================================

def harness_checks(w, ring):
    """Did the harness do what it says? Every one must hold, or the numbers mean nothing."""
    c = []
    c.append(("every bot connected, placed and walking the whole window (%d of %d)"
              % (w["bots_walking_throughout"], w["bots_expected"]),
              w["bots_walking_throughout"] == w["bots_expected"]))
    c.append(("no bot was disconnected (%d)" % w["disconnected_count"], w["disconnected_count"] == 0))
    c.append(("every bot was sent rows (%d were not)" % w["bots_sent_no_rows"], w["bots_sent_no_rows"] == 0))
    c.append(("every bot moved, as the server saw it (%d did not; %.0f m on average)"
              % (w["bots_not_moved"], w["metres_moved_mean"]), w["bots_not_moved"] == 0))
    fewest = w.get("_min_neighbours_seen")
    c.append(("every bot saw others (the fewest any bot saw: %s)" % fewest, (fewest or 0) > 0))
    c.append(("nothing was refused (%s)" % (", ".join("%s x%d" % kv for kv in list(w["refused"].items())[:3]) or "none"),
              not w["refused"]))
    played = w.get("refused_in_play", {})
    if played:
        # A refusal the game's hook names as play (a node worked out as a bot reached it): shown, never judged.
        c.append(("refused in play, as the game's hook expects (%s)" % ", ".join(
            "%s x%d" % kv for kv in sorted(played.items(), key=lambda kv: -kv[1])[:3]), True))
    c.append(("no subscription was refused", not w["subscription_errors"]))
    if ring:
        c.append(("the bots crossed cells and their rings followed (%d swaps)" % w["ring_swaps"], w["ring_swaps"] > 0))
    return c


def limits_checks(w, srv, ref, limits, lag_limit):
    """Did the game hold at this step? [(name, measured, limit, holds)]; a null limit is reported only."""
    measured = {
        "tick_movement_p95_ms": srv["reducers"].get("tick_movement", {}).get("wall_p95_ms"),
        "reducer_wait_p95_ms": max([r["wait_p95_ms"] or 0.0 for r in srv["reducers"].values()], default=None),
        "submit_input_rtt_p95_ms": w["rtt_ms"].get("submit_input", {}).get("p95"),
        "input_ack_p95_ms": w["input_ack_ms"]["p95"],
        "ring_swap_p95_ms": w["ring_swap_ms"]["p95"],
        "referee_frame_p95_ms": ref["frame_p95_ms"] if ref else None,
        "referee_net_stalls": ref["net_stalls"] if ref else None,
        "referee_gone_refusals": w.get("refused_referee_gone", 0),
        "client_kb_per_s_p95": w["client_kb_per_s"]["p95"],
        "client_rows_per_s_p95": w["client_rows_per_s"]["p95"],
    }
    out = []
    for name, limit in limits.items():
        v = measured.get(name)
        holds = None if limit is None or v is None else v <= limit
        out.append((name, v, limit, holds))
    lag = w["bot_loop_lag_ms"]["p95"]
    valid = lag is not None and lag <= lag_limit
    return out, valid


# The cell grid's half width (foundation/net/cells.gd `HALF`): a region at the area's edge runs to the grid's.
GRID_HALF = 512


def regions(split, area_cells):
    """REGION REFEREES (DECISIONS #288): `split` [columns, rows] cuts the bots' square (`area_cells` a side,
    round the origin) into that many regions, as `--region=x0,z0,x1,z1` cell squares; those at its edges run
    to the grid's, so the whole world has a referee. [1, 1]: none (one referee for the whole world)."""
    cols, rows = max(1, int(split[0])), max(1, int(split[1]))
    if cols == 1 and rows == 1:
        return []
    lo = -(area_cells // 2)

    def cuts(n):
        inner = [lo + (area_cells * k) // n for k in range(1, n)]
        return [-GRID_HALF] + inner + [GRID_HALF]

    xs, zs = cuts(cols), cuts(rows)
    return ["%d,%d,%d,%d" % (xs[i], zs[j], xs[i + 1] - 1, zs[j + 1] - 1) for i in range(cols) for j in range(rows)]


def load_config():
    with open(os.path.join(ROOT, "shared", "load.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    with open(os.path.join(ROOT, "shared", "game.json"), encoding="utf-8") as f:
        genres = json.load(f).get("genres", [])
    for g in genres:
        path = os.path.join(ROOT, "shared", g, "load.json")
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                over = json.load(f)
            for k, v in over.items():
                if k == "limits":
                    cfg["limits"].update(v)
                elif not k.startswith("_"):
                    cfg[k] = v
    return cfg


def fmt(v, digits=1):
    if v is None:
        return "-"
    if isinstance(v, float):
        return ("%." + str(digits) + "f") % v
    return str(v)


def step_markdown(s):
    w, srv, ref = s["bots"], s["server"], s["referee"]
    lines = ["### %d bots: %s" % (s["bots_n"], "HOLDS" if s["holds"] else "BREAKS" if s["holds"] is False else "?"), ""]
    lines.append("| per client | mean | p95 | max |")
    lines.append("|---|---|---|---|")
    for key, label in (("client_kb_per_s", "KB/s on the wire (gzip)"), ("client_kb_per_s_decoded", "KB/s decoded"),
                       ("client_rows_per_s", "rows/s"), ("client_msgs_per_s", "messages/s"),
                       ("neighbours_seen", "others moving round it")):
        d = w[key]
        lines.append("| %s | %s | %s | %s |" % (label, fmt(d["mean"]), fmt(d["p95"]), fmt(d["max"])))
    lines += ["", "| timing (ms) | p50 | p95 | p99 | max |", "|---|---|---|---|---|"]
    for k, d in w["rtt_ms"].items():
        lines.append("| %s round trip (%d calls, %.0f/s) | %s | %s | %s | %s |" % (
            k, d["n"], w["calls_per_s"][k], fmt(d["p50"]), fmt(d["p95"]), fmt(d["p99"]), fmt(d["max"])))
    d = w["input_ack_ms"]
    lines.append("| input sent to processed | %s | %s | %s | %s |" % (fmt(d["p50"]), fmt(d["p95"]), fmt(d["p99"]), fmt(d["max"])))
    d = w["ring_swap_ms"]
    lines.append("| ring swap applied (%.1f a bot a minute) | %s | %s | %s | %s |" % (
        w["ring_swaps_per_bot_min"], fmt(d["p50"]), fmt(d["p95"]), fmt(d["p99"]), fmt(d["max"])))
    lines += ["", "| server, per reducer (ms) | calls | wall p50 | wall p95 | wall p99 | cpu p95 | queue wait p95 |",
              "|---|---|---|---|---|---|---|"]
    for k, r in srv["reducers"].items():
        lines.append("| %s | %d | %s | %s | %s | %s | %s |" % (k, r["calls"], fmt(r["wall_p50_ms"], 2), fmt(r["wall_p95_ms"], 2),
                                                             fmt(r["wall_p99_ms"], 2), fmt(r["cpu_p95_ms"], 2), fmt(r["wait_p95_ms"], 2)))
    lines.append("")
    lines.append("Server queues, worst sampled: subscription send %s, outgoing %s, module instance %s; outgoing-queue disconnects %s." % (
        fmt(srv["max_send_queue"], 0), fmt(srv["max_outgoing_queue"], 0), fmt(srv["max_instance_queue"], 0),
        fmt(srv["outgoing_queue_disconnects"], 0)))
    if ref:
        lines.append("Referee (%d reports): frame p95 %s ms, p99 %s, worst %s; %s fps at worst; %d spikes, %d net stalls (worst %s ms); ping %s ms (worst %s); %d entities." % (
            ref["windows"], fmt(ref["frame_p95_ms"]), fmt(ref["frame_p99_ms"]), fmt(ref["frame_max_ms"]), fmt(ref["fps"], 0),
            ref["spikes"], ref["net_stalls"], fmt(ref["worst_stall_ms"], 0), fmt(ref["rtt_ms"]), fmt(ref["rtt_max_ms"]), ref["entities"]))
    else:
        lines.append("Referee: no reports in the window (%s)." % (s.get("referee_note") or "none running?"))
    top = list(w["rows_per_s_by_table"].items())[:6]
    lines.append("Rows a second, all bots, by table: " + ", ".join("%s %.0f" % kv for kv in top) + ".")
    lines.append("Bots' own event loop: late by p95 %s ms, worst %s; ticks skipped %d (%s)." % (
        fmt(w["bot_loop_lag_ms"]["p95"]), fmt(w["bot_loop_lag_ms"]["max"]), w["bot_ticks_behind"],
        "the bots kept up" if s["valid"] else "THE BOTS FELL BEHIND: these numbers are the bots', not the server's"))
    lines += ["", "| harness check | |", "|---|---|"]
    for text, ok in s["checks"]:
        lines.append("| %s | %s |" % (text, "ok" if ok else "FAILED"))
    lines += ["", "| limit | measured | limit | |", "|---|---|---|---|"]
    for name, v, limit, holds in s["limits"]:
        lines.append("| %s | %s | %s | %s |" % (name, fmt(v), fmt(limit), "holds" if holds else "BREAKS" if holds is False else "reported"))
    return "\n".join(lines)


def main():
    cfg = load_config()
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--host", default="http://127.0.0.1:3000")
    p.add_argument("--db", required=True)
    p.add_argument("--interest", required=True)
    p.add_argument("--steps", default=",".join(str(s) for s in cfg["steps"]))
    p.add_argument("--settle", type=float, default=cfg["settle_s"])
    p.add_argument("--measure", type=float, default=cfg["measure_s"])
    p.add_argument("--area-cells", type=int, default=cfg["area_cells"])
    p.add_argument("--per-proc", type=int, default=50)
    p.add_argument("--connect-rate", type=float, default=10.0)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--no-spread", action="store_true")
    p.add_argument("--label", default="load")
    p.add_argument("--out", default=os.path.join(ROOT, "build", "load"))
    p.add_argument("--limit", action="append", default=[], help="name=value: override a limit (the suite's negative test)")
    p.add_argument("--no-referee", action="store_true", help="do not expect a referee's reports")
    a = p.parse_args()
    if not a.db.endswith("-test"):
        sys.exit("load_test: '%s' is not a test database (<database>-test): the load test never joins a play database" % a.db)
    limits = dict(cfg["limits"])
    for item in a.limit:
        k, v = item.split("=", 1)
        limits[k] = None if v == "null" else float(v)
    steps = [int(s) for s in a.steps.split(",") if s.strip()]
    out_dir = os.path.join(a.out, a.label)
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)
    with open(a.interest, encoding="utf-8") as f:
        ring = json.load(f)["interest"] == "ring"
    dbid = database_identity(a.host, a.db)
    print("load_test: %s (%s interest), steps %s, %ds settle, %ds measured, %d x %d cells" % (
        a.db, "ring" if ring else "world", steps, a.settle, a.measure, a.area_cells, a.area_cells), flush=True)
    workers = Workers(a, out_dir)
    results = []
    try:
        for n in steps:
            workers.add(n - workers.count)
            print("== %d bots: connecting ==" % n, flush=True)
            deadline = time.time() + 30 + n / a.connect_rate * 2
            states = {}
            while time.time() < deadline:
                time.sleep(1.0)
                states = workers.latest_states()
                if states.get("walking", 0) >= n or workers.dead_workers():
                    break
            print("   %s" % states, flush=True)
            if workers.dead_workers():
                print("load_test: a bot process stopped (see %s)" % out_dir, flush=True)
            time.sleep(a.settle)
            if not a.no_referee:
                time.sleep(max(0.0, REF_WINDOW_S - a.settle))   # the referee's first report of the step starts inside it
            before = scrape(a.host)
            t0 = time.time()
            gauges = []
            while time.time() < t0 + a.measure:
                time.sleep(1.0)
                try:
                    gauges.append(sample_gauges(a.host, dbid))
                except OSError:
                    pass
            t1 = time.time()
            after = scrape(a.host)
            time.sleep(1.5)   # the bots' last second in [t0, t1] reaches their files
            lines = workers.lines(t0 - 2)
            w = window(lines, t0, t1, n)
            w["_min_neighbours_seen"] = min_seen(lines, t0, t1)
            srv = server_window(before, after, dbid, gauges)
            # A report at `at` covers the referee's last window (10 s, set by the suite): only those inside [t0, t1].
            ref_rows, ref_note = (None, "not asked") if a.no_referee else referee_windows(a.db, t0 + REF_WINDOW_S, t1 + 1)
            ref = referee_summary(ref_rows) if ref_rows else None
            checks = harness_checks(w, ring)
            lim, valid = limits_checks(w, srv, ref, limits, cfg["bots_kept_up_lag_p95_ms"])
            ok_harness = all(ok for _, ok in checks)
            breaks = [x for x in lim if x[3] is False]
            step = {"bots_n": n, "t0": t0, "t1": t1, "bots": w, "server": srv, "referee": ref, "referee_note": ref_note,
                    "checks": checks, "limits": lim, "valid": valid,
                    "holds": (not breaks) if ok_harness and valid else None}
            results.append(step)
            print(step_markdown(step), flush=True)
            if not ok_harness or not valid:
                print("load_test: the harness did not work at %d bots: stopping here" % n, flush=True)
                break
    finally:
        workers.stop_all()
    report = {"label": a.label, "db": a.db, "when": datetime.datetime.now().isoformat(timespec="seconds"),
              "interest": "ring" if ring else "world", "area_cells": a.area_cells, "limits": limits,
              "machine": "%s, %d logical CPUs" % (platform.platform(), os.cpu_count() or 0), "steps": results}
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, default=str)
    md = ["# Load test: %s, %s" % (a.label, report["when"]), "",
          "%s on %s, %s interest, bots across %d x %d cells; %s (the server, the bots and the referee share it)."
          % (a.db, a.host, report["interest"], a.area_cells, a.area_cells, report["machine"]), ""]
    md += [step_markdown(s) + "\n" for s in results]
    first_break = next((s["bots_n"] for s in results if s["holds"] is False), None)
    harness_ok = all(all(ok for _, ok in s["checks"]) and s["valid"] for s in results) and len(results) == len(steps)
    verdict = ("the harness FAILED (see its checks)" if not harness_ok else
               "holds at every step" if first_break is None else "BREAKS at %d bots" % first_break)
    md.append("**Verdict: %s.**" % verdict)
    with open(os.path.join(out_dir, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print("\nload_test: %s (%s)" % (verdict, os.path.join(out_dir, "report.md")), flush=True)
    print("RESULT %s" % ("HARNESS_FAILED" if not harness_ok else "HOLDS" if first_break is None else "BREAKS_AT %d" % first_break), flush=True)
    sys.exit(0 if harness_ok and first_break is None else 2 if harness_ok else 1)


def min_seen(lines, t0, t1):
    """The fewest others any one bot saw in a second, at its best second of the window."""
    best = {}
    for d in lines:
        if t0 < d["t"] <= t1:
            for row in d["per_bot"]:
                best[row[0]] = max(best.get(row[0], 0), row[5])
    return min(best.values()) if best else None


if __name__ == "__main__":
    main()
