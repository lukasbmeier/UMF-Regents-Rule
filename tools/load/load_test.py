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
import bisect
import datetime
import json
import math
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import level as levels  # noqa: E402
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


def hist_sum(before, after, name, match):
    """The histogram `name`'s summed values (`_sum`) between two scrapes, for series whose labels include `match`.
    Exact, where a quantile is only as good as the buckets (SpacetimeDB's jump 1, 5, 10, 50 ms: a p95 of "46 ms"
    is anywhere from 10 to 50)."""
    total = 0.0
    for (n, labels), v in after.items():
        if n != name + "_sum":
            continue
        d = dict(labels)
        if any(d.get(k) != val for k, val in match.items()):
            continue
        total += v - before.get((n, labels), 0.0)
    return total


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


def referee_who(row):
    """Which referee sent a report: its name and region (Telemetry.who), else the end of its identity."""
    try:
        who = json.loads(row.get("detail") or "{}").get("who", "")
    except (ValueError, TypeError, AttributeError):
        who = ""
    if who:
        return who
    ident = row.get("identity")
    while isinstance(ident, (list, tuple)) and ident:
        ident = ident[0]
    return "referee %s" % (str(ident)[-8:] if ident is not None else "?")


def referees_summary(rows):
    """Each referee's own summary, by who sent it: {who: summary}."""
    by = {}
    for r in rows or []:
        by.setdefault(referee_who(r), []).append(r)
    return {k: referee_summary(v) for k, v in sorted(by.items())}


def referee_summary(rows):
    if not rows:
        return None
    stalls = 0
    worst_stall = 0.0
    stall_list = []   # [server seconds, ms] of each: when it was, to set beside what the referee was doing
    for r in rows:
        try:
            for s in json.loads(r.get("detail") or "{}").get("spikes", []):
                if len(s) >= 3 and s[2] == "net":
                    stalls += 1
                    worst_stall = max(worst_stall, float(s[1]))
                    stall_list.append([float(s[0]), float(s[1])])
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
        "stalls": sorted(stall_list),
        "rtt_ms": max(r["rtt_ms"] for r in rows),
        "rtt_max_ms": max(r["rtt_ms_max"] for r in rows),
        "entities": max(r["entities"] for r in rows),
        "memory_mb": max(r["memory_mb"] for r in rows),
    }


# =============================================================================
# WHAT EACH PROCESS COSTS THIS MACHINE
# =============================================================================

def proc_usage(pid):
    """(CPU seconds used so far, resident MB now) of process `pid`, or None if it cannot be read."""
    try:
        if os.name == "nt":
            import ctypes
            from ctypes import wintypes
            k32 = ctypes.WinDLL("kernel32", use_last_error=True)
            k32.OpenProcess.restype = wintypes.HANDLE
            k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            h = k32.OpenProcess(0x1000, False, int(pid))   # PROCESS_QUERY_LIMITED_INFORMATION
            if not h:
                return None
            try:
                ft = [wintypes.FILETIME() for _ in range(4)]
                k32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
                if not k32.GetProcessTimes(h, *[ctypes.byref(f) for f in ft]):
                    return None

                def secs(f):
                    return ((f.dwHighDateTime << 32) | f.dwLowDateTime) / 1e7

                class Counters(ctypes.Structure):
                    _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [
                        (n, ctypes.c_size_t) for n in ("PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
                                                     "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                                                     "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")]
                c = Counters()
                c.cb = ctypes.sizeof(Counters)
                k32.K32GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
                if not k32.K32GetProcessMemoryInfo(h, ctypes.byref(c), c.cb):
                    return None
                return (secs(ft[2]) + secs(ft[3]), c.WorkingSetSize / 1048576.0)
            finally:
                k32.CloseHandle(h)
        out = subprocess.run(["ps", "-o", "rss=,time=", "-p", str(int(pid))], capture_output=True, text=True)
        fields = out.stdout.split()
        if len(fields) < 2:
            return None
        days, _, clock = fields[1].rpartition("-")
        parts = [float(x) for x in clock.split(":")]
        while len(parts) < 3:
            parts.insert(0, 0.0)
        cpu = (float(days) if days else 0.0) * 86400.0 + parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]
        return (cpu, float(fields[0]) / 1024.0)
    except (OSError, ValueError, AttributeError):
        return None


def machine():
    """This machine: logical CPUs and its memory in GB (None if unknown)."""
    gb = None
    try:
        if os.name == "nt":
            import ctypes

            class Status(ctypes.Structure):
                _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong)] + [
                    (n, ctypes.c_ulonglong) for n in ("ullTotalPhys", "ullAvailPhys", "ullTotalPageFile",
                                                     "ullAvailPageFile", "ullTotalVirtual", "ullAvailVirtual",
                                                     "ullAvailExtendedVirtual")]
            st = Status()
            st.dwLength = ctypes.sizeof(Status)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(st)):
                gb = st.ullTotalPhys / 1073741824.0
        elif hasattr(os, "sysconf"):
            gb = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 1073741824.0
    except (OSError, ValueError, AttributeError):
        pass
    return {"cpus": os.cpu_count() or 0, "memory_gb": gb}


class Usage:
    """CPU (cores busy on average) and memory (resident MB, the most seen) of some processes over a window."""

    def __init__(self, procs):
        self.procs = {k: v for k, v in procs.items() if v}     # name -> pid
        self.first, self.last, self.peak = {}, {}, {}

    def sample(self):
        now = time.time()
        for name, pid in self.procs.items():
            u = proc_usage(pid)
            if u is None:
                continue
            self.first.setdefault(name, (now, u[0]))
            self.last[name] = (now, u[0])
            self.peak[name] = max(self.peak.get(name, 0.0), u[1])

    def result(self):
        out = {}
        for name in self.procs:
            if name in self.first and self.last[name][0] > self.first[name][0]:
                (t0, c0), (t1, c1) = self.first[name], self.last[name]
                out[name] = {"cores": (c1 - c0) / (t1 - t0), "memory_mb": self.peak.get(name)}
        return out


def referees_from_logs(paths):
    """The referees a suite started, from their logs: name, process id, region (as each one printed them)."""
    out = []
    for path in paths:
        name, pid, region = os.path.splitext(os.path.basename(path))[0], None, ""
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith("[Sidecar] process "):
                        words = line.split()
                        pid = int(words[2])
                        name = words[3] if len(words) > 3 else name
                    elif line.startswith("[Sidecar] a region referee: "):
                        region = line.split(": ", 1)[1].strip()
        except (OSError, ValueError):
            pass
        out.append({"log": path, "name": name, "pid": pid, "region": region})
    return out


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
            cmd += ["--level-id", str(self.a.level_id), "--spread", json.dumps(self.a.spread)]
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

    def pids(self):
        return {"bots %d" % i: p.pid for i, (p, _) in enumerate(self.procs)}

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


def server_window(before, after, dbid, gauges, seconds=0.0):
    """Each reducer's times in the window, and how busy the module was: a database runs one reducer at a time,
    so `busy_ms_per_s` (the reducer and its subscription queries, summed, a second of the window) over 1000 is
    the share of that one thread it took; all of them together, `module_busy`, near 1 is the ceiling."""
    out = {"reducers": {}}
    names = set()
    for (n, labels) in after:
        if n == "spacetime_txn_elapsed_time_sec_bucket":
            d = dict(labels)
            if d.get("db") == dbid and d.get("reducer"):
                names.add(d["reducer"])
    for r in sorted(names):
        # A call is two transactions in these two histograms: the reducer's (`Reducer`) and the subscription
        # update after it (`Update`). Summed, they counted every call twice and mixed the two times.
        el = histogram(before, after, "spacetime_txn_elapsed_time_sec", {"db": dbid, "reducer": r, "txn_type": "Reducer"})
        cpu = histogram(before, after, "spacetime_txn_cpu_time_sec", {"db": dbid, "reducer": r, "txn_type": "Reducer"})
        wait = histogram(before, after, "spacetime_reducer_wait_time_sec", {"db": dbid, "reducer": r})
        calls = el[-1][1] if el else 0
        if calls <= 0:
            continue
        ms = lambda b, q: None if hist_quantile(b, q) is None else hist_quantile(b, q) * 1000.0  # noqa: E731
        match = {"db": dbid, "reducer": r}
        wall_s = hist_sum(before, after, "spacetime_txn_elapsed_time_sec", dict(match, txn_type="Reducer"))
        update_s = hist_sum(before, after, "spacetime_txn_elapsed_time_sec", dict(match, txn_type="Update"))
        plus_s = hist_sum(before, after, "spacetime_reducer_plus_query_duration_sec", match)
        wait_s = hist_sum(before, after, "spacetime_reducer_wait_time_sec", match)
        out["reducers"][r] = {"calls": calls, "wall_p50_ms": ms(el, 0.5), "wall_p95_ms": ms(el, 0.95),
                              "wall_p99_ms": ms(el, 0.99), "cpu_p95_ms": ms(cpu, 0.95),
                              "wait_p95_ms": ms(wait, 0.95), "wait_p99_ms": ms(wait, 0.99),
                              "wall_mean_ms": wall_s * 1000.0 / calls,
                              "update_mean_ms": update_s * 1000.0 / calls,
                              "plus_query_mean_ms": plus_s * 1000.0 / calls,
                              "wait_mean_ms": wait_s * 1000.0 / calls,
                              "busy_ms_per_s": plus_s * 1000.0 / seconds if seconds > 0 else None}
    busy = [r["busy_ms_per_s"] for r in out["reducers"].values() if r["busy_ms_per_s"] is not None]
    out["module_busy"] = sum(busy) / 1000.0 if busy else None
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

def harness_checks(w, ring, over_level=False):
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
    if over_level:
        # Spread over a world, a bot alone in the wilds rightly sees nobody: some must see others (the town).
        saw = w.get("_bots_saw_others", 0)
        c.append(("bots near others saw them (%d of %d saw someone; one alone in the wilds sees nobody)"
                  % (saw, w["bots_expected"]), saw > 0))
    else:
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
        "tick_movement_mean_ms": srv["reducers"].get("tick_movement", {}).get("wall_mean_ms"),
        "module_busy_pct": None if srv.get("module_busy") is None else srv["module_busy"] * 100.0,
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


def _increasing(cuts, lo, hi):
    """`cuts` made strictly increasing inside (lo, hi): no two regions share a column of cells."""
    out, prev = [], lo
    for c in cuts:
        prev = min(max(int(c), prev + 1), hi - 1)
        out.append(prev)
    return out


def regions_by_homes(split, points, cell_m):
    """REGION REFEREES WHERE THE BOTS ARE (template 1.5): `split` [columns, rows], the columns cut so each holds
    as many of `points` (where the bots live, `level.homes`) as the next, then each column's rows the same way;
    the outer regions run to the grid's edge. A world mostly sea, or a town where many start, still gives each
    referee its share of the players. [1, 1]: none (one referee for the whole world)."""
    cols, rows = max(1, int(split[0])), max(1, int(split[1]))
    if (cols == 1 and rows == 1) or not points:
        return []

    def cell(v):
        return int(math.floor(v / cell_m))

    def quantiles(vals, n):
        # A cut is between two columns of cells: the one leaving nearest the k-th share of `vals` (sorted) before it.
        out = []
        for k in range(1, n):
            target = len(vals) * k / n
            best = min(sorted(set(vals)) + [vals[-1] + 1],
                       key=lambda c: abs(bisect.bisect_left(vals, c) - target))
            out.append(best)
        return out

    xs = sorted(cell(p[0]) for p in points)
    xc = [-GRID_HALF] + _increasing(quantiles(xs, cols), -GRID_HALF, GRID_HALF) + [GRID_HALF]
    out = []
    for i in range(cols):
        zs = sorted(cell(p[1]) for p in points if xc[i] <= cell(p[0]) < xc[i + 1])
        inner = quantiles(zs, rows) if zs else [-GRID_HALF + (2 * GRID_HALF * k) // rows for k in range(1, rows)]
        zc = [-GRID_HALF] + _increasing(inner, -GRID_HALF, GRID_HALF) + [GRID_HALF]
        out += ["%d,%d,%d,%d" % (xc[i], zc[j], xc[i + 1] - 1, zc[j + 1] - 1) for j in range(rows)]
    return out


def cell_m():
    with open(os.path.join(ROOT, "shared", "rules.json"), encoding="utf-8") as f:
        return float(json.load(f).get("cells", {}).get("cell_m", 64))


def region_args(cfg, split, n_bots, seed=1):
    """The `--region=` of each referee for `split` [columns, rows] (tests/load_test.sh asks): round the bots'
    square, or, spread over the level, where its `n_bots` bots live."""
    spread = levels.spread_of(cfg)
    if spread["over"] == "level":
        level = levels.Level.by_id(ROOT, int(cfg.get("level", 0)))
        if level is not None:
            pts = levels.homes(n_bots, seed, spread, level, int(cfg["area_cells"]), cell_m())
            # A referee's work is its players AND the NPCs it runs (template 1.5.2): a cut by players alone
            # gave one referee of four half of a world's 660 skeletons. `npc_kinds`: the level points it runs.
            pts = pts + [p for p in levels.npc_points(level, cfg.get("npc_kinds", []))
                         for _ in range(max(0, int(round(float(cfg.get("npc_weight", 1.0))))))]
            return regions_by_homes(split, pts, cell_m())
    return regions(split, int(cfg["area_cells"]))


def load_config():
    with open(os.path.join(ROOT, "shared", "load.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    with open(os.path.join(ROOT, "shared", "game.json"), encoding="utf-8") as f:
        genres = json.load(f).get("genres", [])
    # A game's own load config over the foundation's, key by key; and LOAD=<name> (template 1.5) its other one,
    # shared/<genre>/load_<name>.json, over that (a bigger world, another crowd).
    variant = os.environ.get("LOAD", "").strip()
    names = ["load.json"] + (["load_%s.json" % variant] if variant else [])
    found_variant = not variant
    for g in genres:
        for name in names:
            path = os.path.join(ROOT, "shared", g, name)
            if not os.path.exists(path):
                continue
            found_variant = found_variant or name != "load.json"
            with open(path, encoding="utf-8") as f:
                over = json.load(f)
            for k, v in over.items():
                if k == "limits":
                    cfg["limits"].update(v)
                elif not k.startswith("_"):
                    cfg[k] = v
    if not found_variant:
        raise SystemExit("load_test: LOAD=%s, but no genre has shared/<genre>/load_%s.json" % (variant, variant))
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
    lines += ["", "| server, per reducer (ms) | calls | wall p50 | wall p95 | wall p99 | cpu p95 | queue wait p95 | wall mean | its update mean | wait mean | busy ms/s |",
              "|---|---|---|---|---|---|---|---|---|---|---|"]
    by_busy = sorted(srv["reducers"].items(), key=lambda kv: -(kv[1].get("busy_ms_per_s") or 0.0))
    for k, r in by_busy:
        lines.append("| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            k, r["calls"], fmt(r["wall_p50_ms"], 2), fmt(r["wall_p95_ms"], 2), fmt(r["wall_p99_ms"], 2),
            fmt(r["cpu_p95_ms"], 2), fmt(r["wait_p95_ms"], 2), fmt(r.get("wall_mean_ms"), 2),
            fmt(r.get("update_mean_ms"), 2), fmt(r.get("wait_mean_ms"), 2), fmt(r.get("busy_ms_per_s"), 0)))
    lines.append("")
    if srv.get("module_busy") is not None:
        lines.append("The module was busy %.0f %% of the window (its one thread: reducers and their subscription updates; "
                     "the p95s above are only as good as the server's buckets, 1, 5, 10, 50 ms; the means and busy are exact; "
                     "a reducer's update is the subscription work after it)." % (
                         srv["module_busy"] * 100.0))
    lines.append("Server queues, worst sampled: subscription send %s, outgoing %s, module instance %s; outgoing-queue disconnects %s." % (
        fmt(srv["max_send_queue"], 0), fmt(srv["max_outgoing_queue"], 0), fmt(srv["max_instance_queue"], 0),
        fmt(srv["outgoing_queue_disconnects"], 0)))
    if ref:
        lines.append("Referee (%d reports): frame p95 %s ms, p99 %s, worst %s; %s fps at worst; %d spikes, %d net stalls (worst %s ms); ping %s ms (worst %s); %d entities." % (
            ref["windows"], fmt(ref["frame_p95_ms"]), fmt(ref["frame_p99_ms"]), fmt(ref["frame_max_ms"]), fmt(ref["fps"], 0),
            ref["spikes"], ref["net_stalls"], fmt(ref["worst_stall_ms"], 0), fmt(ref["rtt_ms"]), fmt(ref["rtt_max_ms"]), ref["entities"]))
    else:
        lines.append("Referee: no reports in the window (%s)." % (s.get("referee_note") or "none running?"))
    refs = s.get("referees") or {}
    use = s.get("usage") or {}
    if len(refs) > 1 or use:
        lines += ["", "| each referee | frame p95 | p99 | worst | net stalls | entities | its own memory MB | cores busy | resident MB |",
                  "|---|---|---|---|---|---|---|---|---|"]
        for who, r in refs.items():
            # A named referee's report starts with its name (Telemetry.who), its usage is under it; one with no
            # name reports as "referee <identity>", its usage is under its log's name, "referee".
            u = use.get(who.split(" ")[0]) or {}
            lines.append("| %s | %s | %s | %s | %d | %d | %s | %s | %s |" % (
                who, fmt(r["frame_p95_ms"]), fmt(r["frame_p99_ms"]), fmt(r["frame_max_ms"]), r["net_stalls"],
                r["entities"], fmt(r["memory_mb"], 0), fmt(u.get("cores"), 2), fmt(u.get("memory_mb"), 0)))
        m = s.get("machine") or {}
        ref_use = [u for k, u in use.items() if not k.startswith("bots") and k != "server"]
        bots_use = [u for k, u in use.items() if k.startswith("bots")]
        srv_use = use.get("server")
        lines.append("")
        lines.append("This machine: %d CPUs, %s GB. The referees together: %s cores, %s MB; the bots: %s cores; the server: %s cores, %s MB." % (
            m.get("cpus", 0), fmt(m.get("memory_gb"), 0), fmt(sum(u["cores"] for u in ref_use), 2) if ref_use else "-",
            fmt(sum(u["memory_mb"] or 0.0 for u in ref_use), 0) if ref_use else "-",
            fmt(sum(u["cores"] for u in bots_use), 2) if bots_use else "-",
            fmt(srv_use["cores"], 2) if srv_use else "-", fmt(srv_use["memory_mb"], 0) if srv_use else "-"))
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
    p.add_argument("--level-id", type=int, default=int(cfg.get("level", 0)), help="the level world 0 plays (its bake)")
    p.add_argument("--referee-log", action="append", default=[], help="a referee's log (its process and region): what it costs")
    p.add_argument("--watch", type=float, default=-1.0,
                   help="after the steps, keep the bots playing this many seconds (0: until stopped) for a person to join")
    a = p.parse_args()
    a.spread = levels.spread_of(cfg)
    over_level = a.spread["over"] == "level"
    if over_level and levels.Level.by_id(ROOT, a.level_id) is None:
        sys.exit("load_test: the bots are spread over level %d, which has no bake in shared/world" % a.level_id)
    refs = referees_from_logs(a.referee_log)
    server_pid = find_server_pid()
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
    print("load_test: %s (%s interest), steps %s, %ds settle, %ds measured, %s" % (
        a.db, "ring" if ring else "world", steps, a.settle, a.measure, where_bots(a)), flush=True)
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
            procs = dict(workers.pids())
            procs.update({r["name"]: r["pid"] for r in refs})
            if server_pid:
                procs["server"] = server_pid
            usage = Usage(procs)
            usage.sample()
            before = scrape(a.host)
            t0 = time.time()
            gauges = []
            while time.time() < t0 + a.measure:
                time.sleep(1.0)
                usage.sample()
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
            w["_bots_saw_others"] = saw_others(lines, t0, t1)
            srv = server_window(before, after, dbid, gauges, t1 - t0)
            # A report at `at` covers the referee's last window (10 s, set by the suite): only those inside [t0, t1].
            ref_rows, ref_note = (None, "not asked") if a.no_referee else referee_windows(a.db, t0 + REF_WINDOW_S, t1 + 1)
            ref = referee_summary(ref_rows) if ref_rows else None
            checks = harness_checks(w, ring, over_level)
            lim, valid = limits_checks(w, srv, ref, limits, cfg["bots_kept_up_lag_p95_ms"])
            ok_harness = all(ok for _, ok in checks)
            breaks = [x for x in lim if x[3] is False]
            step = {"bots_n": n, "t0": t0, "t1": t1, "bots": w, "server": srv, "referee": ref, "referee_note": ref_note,
                    "referees": referees_summary(ref_rows) if ref_rows else {}, "usage": usage.result(),
                    "machine": machine(), "regions": {r["name"]: r["region"] for r in refs},
                    "checks": checks, "limits": lim, "valid": valid,
                    "holds": (not breaks) if ok_harness and valid else None}
            results.append(step)
            print(step_markdown(step), flush=True)
            if not ok_harness or not valid:
                print("load_test: the harness did not work at %d bots: stopping here" % n, flush=True)
                break
        if a.watch >= 0:
            watch(a, workers, refs, server_pid, dbid, out_dir)
    except KeyboardInterrupt:
        print("load_test: stopped (Ctrl+C)", flush=True)
    finally:
        workers.stop_all()
    report = {"label": a.label, "db": a.db, "when": datetime.datetime.now().isoformat(timespec="seconds"),
              "interest": "ring" if ring else "world", "area_cells": a.area_cells, "limits": limits,
              "level": a.level_id, "spread": a.spread, "referees_n": max(1, len(refs)),
              "machine": "%s, %d logical CPUs" % (platform.platform(), os.cpu_count() or 0), "steps": results}
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, default=str)
    md = ["# Load test: %s, %s" % (a.label, report["when"]), "",
          "%s on %s, %s interest, %s; %d referee(s); %s (the server, the bots and the referees share it)."
          % (a.db, a.host, report["interest"], where_bots(a), report["referees_n"], report["machine"]), ""]
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


def where_bots(a):
    if a.spread["over"] == "level":
        return "bots spread over level %d (%d %% within %d cells of the spawn, each roaming %d cells)" % (
            a.level_id, round(float(a.spread["crowd_share"]) * 100), int(a.spread["crowd_cells"]), int(a.spread["roam_cells"]))
    return "bots across %d x %d cells" % (a.area_cells, a.area_cells)


def find_server_pid():
    """The local SpacetimeDB's process (`spacetimedb-standalone`), for what it costs; None if not found."""
    try:
        if os.name == "nt":
            out = subprocess.run(["tasklist", "/FO", "CSV", "/NH", "/FI", "IMAGENAME eq spacetimedb-standalone.exe"],
                                 capture_output=True, text=True).stdout
            for line in out.splitlines():
                cols = [c.strip('"') for c in line.split('","')]
                if len(cols) > 1 and cols[0].lower().startswith("spacetimedb-standalone"):
                    return int(cols[1])
            return None
        out = subprocess.run(["pgrep", "-f", "spacetimedb-standalone"], capture_output=True, text=True).stdout.split()
        return int(out[0]) if out else None
    except (OSError, ValueError):
        return None


WATCH_EVERY_S = 10.0


def watch(a, workers, refs, server_pid, dbid, out_dir):
    """THE BOTS KEEP PLAYING FOR A PERSON TO JOIN (template 1.5): a line every 10 s (bots playing, the module's
    busy share, each referee's frames, what each costs) until `a.watch` seconds pass (0: until Ctrl+C or the
    file `<out>/stop_watch` exists). Nothing is judged; the lines go to `<out>/watch.jsonl` too."""
    stop = os.path.join(out_dir, "stop_watch")
    if os.path.exists(stop):
        os.remove(stop)
    print("WATCHING: the bots play on %s until %s. Stop: Ctrl+C, or create %s" % (
        a.db, "%d s pass" % a.watch if a.watch > 0 else "stopped", stop), flush=True)
    procs = dict(workers.pids())
    procs.update({r["name"]: r["pid"] for r in refs})
    if server_pid:
        procs["server"] = server_pid
    end = time.time() + a.watch if a.watch > 0 else float("inf")
    log = open(os.path.join(out_dir, "watch.jsonl"), "a", encoding="utf-8")
    try:
        while time.time() < end and not os.path.exists(stop):
            usage = Usage(procs)
            usage.sample()
            before = scrape(a.host)
            t0 = time.time()
            while time.time() < t0 + WATCH_EVERY_S and not os.path.exists(stop):
                time.sleep(1.0)
            usage.sample()
            t1 = time.time()
            srv = server_window(before, scrape(a.host), dbid, [], t1 - t0)
            rows, _ = referee_windows(a.db, t0 - REF_WINDOW_S, t1 + 1)
            per = referees_summary(rows) if rows else {}
            use = usage.result()
            states = workers.latest_states()
            refs_text = ", ".join("%s %s ms" % (who.split(" ")[0], fmt(r["frame_p95_ms"])) for who, r in per.items()) or "no reports"
            ref_use = [u for k, u in use.items() if not k.startswith("bots") and k != "server"]
            print("[watch %s] %d bots playing; module %s %% busy; referees' frame p95: %s; referees %s cores, %s MB; server %s cores" % (
                time.strftime("%H:%M:%S"), states.get("walking", 0),
                fmt(None if srv.get("module_busy") is None else srv["module_busy"] * 100.0, 0), refs_text,
                fmt(sum(u["cores"] for u in ref_use), 1) if ref_use else "-",
                fmt(sum(u["memory_mb"] or 0.0 for u in ref_use), 0) if ref_use else "-",
                fmt((use.get("server") or {}).get("cores"), 1)), flush=True)
            log.write(json.dumps({"t": t1, "states": states, "module_busy": srv.get("module_busy"),
                                  "referees": per, "usage": use}, default=str) + "\n")
            log.flush()
    finally:
        log.close()


def saw_others(lines, t0, t1):
    """How many bots saw someone else at some second of the window."""
    best = {}
    for d in lines:
        if t0 < d["t"] <= t1:
            for row in d["per_bot"]:
                best[row[0]] = max(best.get(row[0], 0), row[5])
    return sum(1 for v in best.values() if v > 0)


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
