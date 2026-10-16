"""What the players said, and how the game ran for them (DECISIONS #244): read from the host's database.

    python tools/feedback.py [--db NAME] [--hours N] [--limit N]

FEEDBACK, newest first: when, who, what about, where in the game, what they wrote, how their game was
running at the moment they marked, and the referee's recording of that round with the second it happened
at (so the moment can be watched again: tools/replay). Then PERFORMANCE over the last hours, per player
and per referee: frames, the worst frame times, spikes (slow frames and network stalls), ping.

Run on the machine that hosts (it asks the local server, as the database's owner). tools/feedback.sh is
this for Git Bash, tools\\feedback.cmd for a double-click.
"""
import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

CATEGORY = ["Bug", "Lag", "Idea", "Other"]
ROLE = ["game", "referee"]


def sql(db, query):
    out = subprocess.run(["spacetime", "sql", db, "--format", "json", query], capture_output=True, text=True, encoding="utf-8")
    text = out.stdout[out.stdout.find("["):] if "[" in out.stdout else ""
    if not text:
        sys.exit("could not read %s (%s)" % (db, (out.stderr or out.stdout).strip()[-300:]))
    result = json.loads(text)[0]
    names = [e["name"].get("some", "") for e in result["schema"]["elements"]]
    rows = []
    for r in result["rows"]:
        row = {}
        for n, v in zip(names, r):
            # A Timestamp comes as [microseconds].
            row[n] = v[0] if isinstance(v, list) and len(v) == 1 and isinstance(v[0], int) else v
        rows.append(row)
    return rows


def when(us):
    return datetime.datetime.fromtimestamp(us / 1e6).strftime("%Y-%m-%d %H:%M:%S")


def ago(us, now_us):
    s = (now_us - us) / 1e6
    return "%d s ago" % s if s < 120 else "%d min ago" % (s / 60) if s < 7200 else "%.1f h ago" % (s / 3600)


def recordings_dir():
    name = "game"
    for line in open("project.godot", encoding="utf-8"):
        m = re.match(r'config/name="(.*)"', line.strip())
        if m:
            name = m.group(1)
            break
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "Godot", "app_userdata", name, "recordings")


def recording_of(session, rnd, at_us):
    """The referee's recording of round `rnd` of `session` that was going at `at_us`, and the second."""
    best = None
    for path in glob.glob(os.path.join(recordings_dir(), "*_s%d_r%d.jsonl" % (session, rnd))):
        try:
            head = json.loads(open(path, encoding="utf-8").readline())
        except (ValueError, OSError):
            continue
        t = at_us / 1e6 - float(head.get("started", 0))
        if t >= 0 and (best is None or t < best[1]):
            best = (os.path.basename(path), t)
    return best


def perf_line(p):
    if not isinstance(p, dict) or not p:
        return "no report"
    stalls = sum(1 for s in p.get("spike_list", []) if len(s) > 2 and s[2] == "net")
    fps = p["frames"] / p["window_s"] if p.get("window_s") else 0
    return "%d fps, frames %s ms (95th) / %s ms (worst), %d spikes (%d network stalls), ping %s ms" % (
        fps, p.get("p95"), p.get("max"), p.get("spikes", 0), stalls, p.get("rtt_ms"))


def watch(db, every_s=5.0):
    """A POINT IN TIME ALERT (Luke): each new piece of feedback printed, with a bell, as it arrives."""
    import time
    seen = max([r["id"] for r in sql(db, "SELECT id FROM feedback")] or [0])
    while True:
        time.sleep(every_s)
        try:
            new = [r for r in sql(db, "SELECT id, name, entity_id, category, text, phase, round FROM feedback WHERE id > %d" % seen)]
        except SystemExit:
            continue
        for r in sorted(new, key=lambda r: r["id"]):
            seen = max(seen, r["id"])
            print("\a*** FEEDBACK #%d from %s [%s], round %d: %s   (tools\\feedback.cmd for it all)" % (
                r["id"], r["name"] or "entity %d" % r["entity_id"], CATEGORY[r["category"]] if r["category"] < len(CATEGORY) else "?",
                r["round"], r["text"]), flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=os.environ.get("UMF_DB") or json.load(open("shared/game.json", encoding="utf-8")).get("database", "umf"))
    ap.add_argument("--hours", type=float, default=24.0)
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--watch", action="store_true", help="print each new piece of feedback as it arrives (tools/host.sh)")
    a = ap.parse_args()
    if a.watch:
        watch(a.db)
        return
    now_us = int(datetime.datetime.now().timestamp() * 1e6)
    since = now_us - int(a.hours * 3600e6)

    fb = [r for r in sql(a.db, "SELECT * FROM feedback") if r["at"] >= since]
    fb.sort(key=lambda r: r["at"], reverse=True)
    print("FEEDBACK on %s, the last %g h: %d" % (a.db, a.hours, len(fb)))
    for r in fb[: a.limit]:
        pos = r["pos"] if isinstance(r["pos"], list) else [0, 0, 0]
        print("\n#%d  %s (%s)  %s  [%s]  phase %d, round %d, at (%.1f, %.1f, %.1f)" % (
            r["id"], when(r["noticed_at"]), ago(r["noticed_at"], now_us), r["name"] or "entity %d" % r["entity_id"],
            CATEGORY[r["category"]] if r["category"] < len(CATEGORY) else "?", r["phase"], r["round"], pos[0], pos[1], pos[2]))
        print('    "%s"' % r["text"])
        try:
            ctx = json.loads(r["context"] or "{}")
        except ValueError:
            ctx = {}
        perf = ctx.get("perf", {})
        print("    their game then: " + perf_line(perf.get("now", {})))
        rec = recording_of(r["session_id"], r["round"], r["noticed_at"])
        print("    recording: %s at %.1f s" % rec if rec else "    recording: none on this machine (the referee's)")
        print("    on: %s" % r["platform"])

    perf = [r for r in sql(a.db, "SELECT * FROM perf_report") if r["at"] >= since]
    print("\nPERFORMANCE, the last %g h: %d reports" % (a.hours, len(perf)))
    who = {}
    for r in perf:
        who.setdefault((r["entity_id"], r["role"], r["platform"]), []).append(r)
    names = {r["entity_id"]: r["name"] for r in sql(a.db, "SELECT entity_id, name FROM player")}
    for (eid, role, platform), rs in sorted(who.items(), key=lambda kv: -len(kv[1])):
        frames = sum(r["frames"] for r in rs)
        secs = sum(r["window_s"] for r in rs)
        stalls = 0
        worst = []
        for r in rs:
            try:
                for s in json.loads(r["detail"] or "{}").get("spikes", []):
                    stalls += 1 if len(s) > 2 and s[2] == "net" else 0
                    worst.append((s[1], s[0], s[2] if len(s) > 2 else "?"))
            except ValueError:
                pass
        worst.sort(reverse=True)
        rtts = [r["rtt_ms"] for r in rs if r["rtt_ms"] > 0]
        print("\n%s (%s) on %s" % (names.get(eid, "entity %d" % eid) if eid else "the referee", ROLE[role] if role < 2 else "?", platform))
        print("    %d reports, %.0f min: %.0f fps; frames 99th worst %.1f ms, worst %.1f ms; %d spikes (%d network stalls); ping %.0f ms avg, %.0f worst; %d corrections" % (
            len(rs), secs / 60, frames / secs if secs else 0, max(r["frame_ms_p_99"] for r in rs), max(r["frame_ms_max"] for r in rs),
            sum(r["spikes"] for r in rs), stalls, sum(rtts) / len(rtts) if rtts else 0, max(r["rtt_ms_max"] for r in rs), sum(r["corrections"] for r in rs)))
        for ms, t, cause in worst[:3]:
            print("    a %s spike of %.0f ms at %s" % ("network" if cause == "net" else "frame", ms, when(int(t * 1e6))))


if __name__ == "__main__":
    main()
