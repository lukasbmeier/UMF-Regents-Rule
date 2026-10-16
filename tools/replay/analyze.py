"""How each bot behaved in a recorded round (DECISIONS #235's recordings; the `brain` events, #244).

    python tools/replay/analyze.py [recording.jsonl]     (default: the newest on this machine)

For every entity a brain drove: how far it walked and how much of that got it anywhere (the straightness
of its 5 s stretches: 1 is a straight line), how often it turned right round (reversals a minute), the
share of the round it spent in each step of its brain, how often it changed step, and FLIP-FLOPS (a step,
another, and back to the first within `FLIP_S`): a brain that cannot make up its mind. Players beside
them, for comparison.
"""
import collections
import glob
import json
import math
import os
import re
import sys

FLIP_S = 3.0
REVERSE_RAD = 2.6
MOVE_M = 0.05


def newest():
    name = "game"
    for line in open("project.godot", encoding="utf-8"):
        m = re.match(r'config/name="(.*)"', line.strip())
        if m:
            name = m.group(1)
            break
    base = os.environ.get("APPDATA") or os.path.expanduser("~/.local/share")
    files = glob.glob(os.path.join(base, "Godot", "app_userdata", name, "recordings", "*.jsonl"))
    return max(files, key=os.path.getmtime) if files else None


def load(path):
    lines = []
    for raw in open(path, encoding="utf-8"):
        try:
            lines.append(json.loads(raw))
        except ValueError:
            pass   # a round still being written
    return lines


def motion(track):
    walked = 0.0
    rev = 0
    last = None
    for i in range(1, len(track)):
        dx, dz = track[i][1] - track[i - 1][1], track[i][2] - track[i - 1][2]
        d = math.hypot(dx, dz)
        walked += d
        if d > MOVE_M:
            a = math.atan2(dx, dz)
            if last is not None and abs((a - last + math.pi) % (2 * math.pi) - math.pi) > REVERSE_RAD:
                rev += 1
            last = a
    eff = []
    for i in range(0, len(track) - 50, 50):
        seg = track[i:i + 50]
        w = sum(math.hypot(seg[j][1] - seg[j - 1][1], seg[j][2] - seg[j - 1][2]) for j in range(1, len(seg)))
        if w > 2.0:
            eff.append(math.hypot(seg[-1][1] - seg[0][1], seg[-1][2] - seg[0][2]) / w)
    return walked, rev, (sum(eff) / len(eff)) if eff else None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else newest()
    if not path:
        sys.exit("no recording found")
    lines = load(path)
    head = lines[0]
    names = head.get("names", {})
    kinds = head.get("kinds", {})
    frames = [l for l in lines if "e" in l]
    if not frames:
        sys.exit("no frames in %s" % path)
    dur = frames[-1]["t"] - frames[0]["t"]
    tracks = collections.defaultdict(list)
    kind_of = {}
    for f in frames:
        for e in f["e"]:
            tracks[e[0]].append((f["t"], e[2], e[4]))
            kind_of[e[0]] = e[1]
    brain = collections.defaultdict(list)
    for l in lines:
        if l.get("ev") == "brain":
            brain[l["id"]].append((l["t"], l["state"]))
    print("%s: %.0f s, %d frames" % (os.path.basename(path), dur, len(frames)))
    for eid in sorted(tracks, key=lambda i: (i not in brain, i)):
        tr = tracks[eid]
        walked, rev, straight = motion(tr)
        if walked < 1.0 and eid not in brain:
            continue
        who = names.get(str(eid)) or ("bot" if eid in brain else "")
        span = tr[-1][0] - tr[0][0]
        print("\n%d %s (%s): walked %.0f m, %.1f reversals/min, straightness %s" % (
            eid, who, kinds.get(str(kind_of[eid]), kind_of[eid]), walked, rev / max(span, 1) * 60, "%.2f" % straight if straight is not None else "-"))
        steps = brain.get(eid, [])
        if not steps:
            continue
        time_in = collections.Counter()
        for i, (t, s) in enumerate(steps):
            end = steps[i + 1][0] if i + 1 < len(steps) else frames[-1]["t"]
            time_in[s] += end - t
        changes = collections.Counter()
        flips = collections.Counter()
        for i in range(1, len(steps)):
            if steps[i][1] != steps[i - 1][1]:
                changes[(steps[i - 1][1], steps[i][1])] += 1
            if i >= 2 and steps[i][1] == steps[i - 2][1] and steps[i][1] != steps[i - 1][1] and steps[i][0] - steps[i - 2][0] < FLIP_S:
                flips[tuple(sorted((steps[i][1], steps[i - 1][1])))] += 1
        total = sum(time_in.values()) or 1
        print("    steps: " + ", ".join("%s %d%%" % (s, 100 * v / total) for s, v in time_in.most_common()))
        print("    changes: %d (%.1f/min); most: %s" % (sum(changes.values()), sum(changes.values()) / max(span, 1) * 60,
              ", ".join("%s>%s x%d" % (a, b, n) for (a, b), n in changes.most_common(4))))
        if flips:
            print("    FLIP-FLOPS (back within %.0f s): %s" % (FLIP_S, ", ".join("%s/%s x%d" % (a, b, n) for (a, b), n in flips.most_common(4))))


if __name__ == "__main__":
    main()
