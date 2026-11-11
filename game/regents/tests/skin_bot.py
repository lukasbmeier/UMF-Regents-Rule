"""THE CUT LINE PLAYED FROM A SHELL (the integration hook's, for skinning): the round the server dealt, played by the
independent Python copy of the model (`make_skill_goldens.py`'s Skin, the goldens' third copy, held to the server's twin
by the golden rounds). It starts in a moment: a Godot bot (`skill_bot_cli.gd`) took over two minutes to start on a
loaded machine (2026-11-10), past the round's time and grace, so the server had let the round go before it was sent.

    python game/regents/tests/skin_bot.py <node id> <seed> <speed %> <ease %> [off]

Reads the node's round from the bake (`shared/content/regents/node.json`), makes it as the server deals it (a faster
knife cuts faster, rank widens the line: `Minigame::score_eased`), traces every line at the cut's pace (`off` across the
line: 70 tears every look). Prints `RESULT [values...]` (the inputs, as the challenge takes them) and `PLAYED <result>`.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_skill_goldens as g  # noqa: E402


def main():
    node_id, seed, speed, ease = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    off = int(sys.argv[5]) if len(sys.argv) > 5 else 0
    with open(os.path.join(HERE, "..", "..", "..", "shared", "content", "regents", "node.json"), encoding="utf-8") as f:
        doc = json.load(f)
    items = doc["items"] if isinstance(doc, dict) and "items" in doc else doc
    node = next(n for n in items if int(n["id"]) == node_id)
    p = {k: v for k, v in node["minigame"].items() if k != "kind"}
    e = max(0, min(50, ease))
    p["cut_speed"] = max(1, p["cut_speed"] * 100 // max(1, speed))
    p["near"] = p["near"] * (100 + e) // 100
    inputs = g.skin_bot(seed, p, off=off)
    print("RESULT [%s]" % ",".join(str(v) for row in inputs for v in row))
    print("PLAYED %s" % json.dumps(g.skin_play(seed, p, inputs)))


main()
