"""THE REFEREE SWEEP'S TABLE (tests/referee_sweep.sh, template 1.5): one load test report per way of cutting the
world (build/load/<label>/report.json), side by side, and the fewest referees that held with room to spare.

  python tools/load/sweep_report.py sweep_1x1 sweep_2x2 sweep_3x3     ->  build/load/sweep.md
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "build", "load")
# A referee "with room" is at most this share of its frame limit (a referee at 45 of 50 ms holds today and
# breaks with the next camp).
ROOM = 0.5


def row_of(label):
    path = os.path.join(OUT, label, "report.json")
    with open(path, encoding="utf-8") as f:
        r = json.load(f)
    s = r["steps"][-1]
    limits = {name: (v, limit, holds) for name, v, limit, holds in s["limits"]}
    frame_limit = limits.get("referee_frame_p95_ms", (None, 50.0, None))[1] or 50.0
    refs = s.get("referees") or {}
    worst = max([v["frame_p95_ms"] for v in refs.values()], default=(s.get("referee") or {}).get("frame_p95_ms"))
    use = s.get("usage") or {}
    ref_use = [u for k, u in use.items() if not k.startswith("bots") and k != "server"]
    referee_breaks = [n for n, (v, lim, holds) in limits.items() if n.startswith("referee") and holds is False]
    server_breaks = [n for n, (v, lim, holds) in limits.items() if not n.startswith("referee") and holds is False]
    return {
        "label": label, "referees": r.get("referees_n", 1), "bots": s["bots_n"],
        "holds": s["holds"], "valid": s["valid"] and all(ok for _, ok in s["checks"]),
        "worst_frame": worst, "frame_limit": frame_limit,
        "room": worst is not None and worst <= ROOM * frame_limit,
        "stalls": sum(v.get("net_stalls", 0) for v in refs.values()) if refs else (s.get("referee") or {}).get("net_stalls"),
        "cores": sum(u["cores"] for u in ref_use) if ref_use else None,
        "memory_mb": sum(u["memory_mb"] or 0.0 for u in ref_use) if ref_use else None,
        "each_mb": max((u["memory_mb"] or 0.0 for u in ref_use), default=None),
        "busy": None if s["server"].get("module_busy") is None else s["server"]["module_busy"] * 100.0,
        "referee_breaks": referee_breaks, "server_breaks": server_breaks,
        "machine": s.get("machine") or {},
    }


def fmt(v, d=1):
    return "-" if v is None else ("%." + str(d) + "f") % v if isinstance(v, float) else str(v)


def main(labels):
    rows = []
    for label in labels:
        try:
            rows.append(row_of(label))
        except (OSError, ValueError, KeyError, IndexError) as e:
            print("sweep_report: %s has no usable report (%s)" % (label, e))
    if not rows:
        sys.exit("sweep_report: no reports")
    m = rows[0]["machine"]
    md = ["# How many referees: %d bots" % rows[0]["bots"], "",
          "This machine: %s CPUs, %s GB; the server, the bots and the referees all ran on it." % (
              m.get("cpus", "?"), fmt(m.get("memory_gb"), 0)), "",
          "| referees | worst referee frame p95 (ms) | net stalls | the referees' cores | their memory (MB, each at most) | module busy % | referees hold | the step |",
          "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        ref_ok = "yes, with room" if not r["referee_breaks"] and r["room"] else "yes" if not r["referee_breaks"] else "NO: " + ", ".join(r["referee_breaks"])
        step = "harness failed" if not r["valid"] else "holds" if r["holds"] else "breaks: " + ", ".join(r["server_breaks"] + r["referee_breaks"])
        md.append("| %d | %s | %s | %s | %s (%s) | %s | %s | %s |" % (
            r["referees"], fmt(r["worst_frame"]), fmt(r["stalls"]), fmt(r["cores"], 2), fmt(r["memory_mb"], 0),
            fmt(r["each_mb"], 0), fmt(r["busy"], 0), ref_ok, step))
    fit = [r for r in rows if r["valid"] and not r["referee_breaks"]]
    roomy = [r for r in fit if r["room"]]
    md.append("")
    if roomy:
        best = min(roomy, key=lambda r: r["referees"])
        md.append("**%d referees hold %d bots with room** (the worst at %s of its %s ms); they took %s cores and %s MB here." % (
            best["referees"], best["bots"], fmt(best["worst_frame"]), fmt(best["frame_limit"], 0), fmt(best["cores"], 1),
            fmt(best["memory_mb"], 0)))
    elif fit:
        best = min(fit, key=lambda r: r["referees"])
        md.append("**%d referees hold %d bots, without room** (the worst at %s of %s ms): try more." % (
            best["referees"], best["bots"], fmt(best["worst_frame"]), fmt(best["frame_limit"], 0)))
    else:
        md.append("**No cut tried held %d bots**: try more referees." % rows[0]["bots"])
    if any(r["server_breaks"] for r in rows):
        md.append("Where the step broke on the server's limits, more referees do not help: that is the server (one module thread).")
    text = "\n".join(md) + "\n"
    with open(os.path.join(OUT, "sweep.md"), "w", encoding="utf-8") as f:
        f.write(text)
    print(text)


if __name__ == "__main__":
    main(sys.argv[1:])
