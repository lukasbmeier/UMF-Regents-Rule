"""REGENT'S RULE'S LOAD BOTS (the load test's genre hook, DECISIONS #284; tools/load/bots.py loads it).

Besides walking from cell to cell, each bot plays as a player of this game does:
- it WIELDS its starter Copper axe (the starter kit: the axe and the pickaxe), as the bag's first weapon;
- a FIGHTER (every third bot) swings the axe's light attacks every second or two as it walks (standing for
  each swing's committed part, as a client slow-walks within the server's Swinging bound), each one
  judged by the world's referee (`use_ability_seen`, as `combat_component.gd` sends it);
- a GATHERER (every third bot, the next) walks to the nearest tree (the axe) or copper rock (the pickaxe), says it saw
  it (`saw_nodes`, as `discovery.gd` does), works it AFK for 6 to 12 s (`gather`, tapped E), then stops
  (`work_stop`) and goes on to another;
- the rest only walk. LOAD_BOT_PLAY=0: every bot only walks (measuring the feed alone).
Active rounds (held E: a minigame the server times) are not played: a bot does not decode its challenge
rows. The skilling playtest plays those (`skilling_playtest.sh`).

What a real client knows from its own rows a bot reads as the owner (`bot.sql`): its bag's row ids, and
where the nodes stand. Each worker process reads them once (the bags again until every bot has its own).
"""
import math
import os

AXE = 40001          # the Copper axe: a weapon of the axe kit and a tool tagged axe
PICKAXE = 40006      # the Copper pickaxe: a tool tagged pick
LIGHT = (40006, 40007)   # the axe kit's light attacks, in combo order (shared/content/regents/kit.json)
# How long each stands for its committed part: the wind-up and `regents.swing_hold_ms` (80), and a little.
COMMIT_S = {40006: 0.26 + 0.12, 40007: 0.30 + 0.12}
NODE_TOOL = {40001: AXE, 40004: PICKAXE}   # the Tree and the Copper rock: rank 1, a tier-1 tool
VIEW_DELAY_MS = 100  # how far behind a client at this machine's latency sees others (a real client's is close)
REACH_M = 1.5        # where a gatherer stops from a node's centre (regents.work_reach_m is 3)
FIND_RADIUS_M = 120.0

# Refusals that are play, not faults ("reducer: its text"): a node worked out, by this bot or another, just as
# it is asked for. Nothing else: any other refusal fails the run (the referee dropping out is the
# foundation's limit `referee_gone_refusals`).
EXPECTED_REFUSALS = [
    r"^gather: gather: the [a-z ]+ is worked out",
    # A skeleton's heavy flinched the bot's first swing: a client that saw it starts the combo again; a bot,
    # which reads no statuses, finds out by this refusal (any other combo refusal is a bug).
    r"^use_ability_seen: use_ability: the swing before was cut short",
    # A skeleton killed the fighter as it swung (first seen with six region referees on the expanse, whose
    # skeletons each think more often): a client sees itself fall and stops; a bot, which reads no health,
    # finds out by this refusal.
    r"^use_ability_seen: use_ability: you cannot while slain",
]

_bags = {}           # entity id -> {item id: bag row id}
_bag_reading = False
_bag_read_at = 0.0
_nodes = None        # [(node id, def id, x, z)] of the nodes a starter kit works
_nodes_reading = False


def _read_bags(bot, now):
    global _bag_reading, _bag_read_at
    if _bag_reading or now - _bag_read_at < 2.0:
        return
    _bag_reading, _bag_read_at = True, now

    def done(rows, why):
        global _bag_reading
        _bag_reading = False
        if rows is None:
            bot.log("load_bot: the bags could not be read: " + why)
            return
        for r in rows:
            if r["item_def_id"] in (AXE, PICKAXE):
                _bags.setdefault(r["owner_entity_id"], {})[r["item_def_id"]] = r["id"]
    bot.sql("SELECT * FROM inventory_item", done)


def _read_nodes(bot):
    global _nodes_reading
    if _nodes_reading or _nodes is not None:
        return
    _nodes_reading = True
    found = {}

    def got_moves(rows, why):
        global _nodes, _nodes_reading
        _nodes_reading = False
        if rows is None:
            bot.log("load_bot: the nodes' places could not be read: " + why)
            return
        out = []
        for m in rows:
            n = found.get(m["entity_id"])
            if n is not None:
                out.append((m["entity_id"], n, float(m["pos"][0]), float(m["pos"][2])))
        _nodes = out
        bot.log("load_bot: %d nodes a starter kit works" % len(out))

    def got_nodes(rows, why):
        global _nodes_reading
        if rows is None:
            _nodes_reading = False
            bot.log("load_bot: the nodes could not be read: " + why)
            return
        for r in rows:
            if r["world_id"] == bot.world_id and r["def_id"] in NODE_TOOL:
                found[r["entity_id"]] = r["def_id"]
        bot.sql("SELECT * FROM movement_state WHERE world_id = %d" % bot.world_id, got_moves)
    bot.sql("SELECT * FROM gather_node", got_nodes)


def setup(bot):
    if os.environ.get("LOAD_BOT_PLAY", "1") == "0":
        return      # LOAD_BOT_PLAY=0: the bots only walk (the feed alone, for the referee's measurement)
    bot.rr = {
        "role": ("fighter", "gatherer", "walker")[bot.index % 3],
        "resume_at": 0.0, "resume_to": None,
        "wielded": False, "wield_asked": False, "next_swing": 0.0, "combo": 0, "pid": 0,
        "node": None, "work_until": 0.0, "working": False, "next_find": 0.0, "avoid": set(),
    }


def tick(bot, now):
    s = getattr(bot, "rr", None)
    if s is None or bot.pos is None:
        return
    # A bot the server has not seen move for 20 s says once what it is doing (a stuck bot fails the harness).
    sp = bot.server_pos
    if sp is not None:
        last = s.get("last_pos")
        if last is None or math.hypot(sp["x"] - last[0], sp["z"] - last[1]) > 1.0:
            s["last_pos"], s["last_moved"], s["told"] = (sp["x"], sp["z"]), now, False
        elif now - s["last_moved"] > 20.0 and not s.get("told"):
            s["told"] = True
            bot.log("load_bot: %s %d has not moved for 20 s: node %s, stand %s, working %s, paused %s, target %s, pos (%.1f, %.1f), server (%.1f, %.1f), bag %s" % (
                s["role"], bot.index, s["node"] and s["node"][0], s.get("stand"), s["working"], bot.paused, bot.target,
                bot.pos["x"], bot.pos["z"], sp["x"], sp["z"], bot.entity_id in _bags))
    bag = _bags.get(bot.entity_id)
    if bag is None or AXE not in bag:
        _read_bags(bot, now)
        return
    if not s["wield_asked"]:
        s["wield_asked"] = True
        bot.call("wield", bag[AXE])
        return
    if s["resume_at"] and now >= s["resume_at"]:
        # The swing's committed part is over: on again, as a client's slow-walk lets go.
        s["resume_at"] = 0.0
        if s["resume_to"] is not None:
            bot.walk_to(*s["resume_to"])
        else:
            bot.wander()
    if s["role"] == "fighter" and s["wielded"] and now >= s["next_swing"]:
        # A combo as a player swings it: each light in order, the next once the last's lock is over (578 and
        # 667 ms) and well inside the kit's 900 ms window; then a pause, after which it starts again.
        ability = LIGHT[s["combo"]]
        s["combo"] = (s["combo"] + 1) % len(LIGHT)
        s["next_swing"] = now + (0.75 if s["combo"] else bot.rng.uniform(1.5, 3.0))
        s["pid"] += 1
        tx, tz = bot.target if bot.target is not None else (bot.pos["x"], bot.pos["z"] - 1.0)
        dx, dz = tx - bot.pos["x"], tz - bot.pos["z"]
        d = math.hypot(dx, dz) or 1.0
        bot.call("use_ability_seen", ability, 0, {"x": dx / d, "y": 0.0, "z": dz / d}, s["pid"], VIEW_DELAY_MS)
        # Committed: a real client walks at a quarter of a run (the server's Swinging bound); the bot stands.
        s["resume_to"] = bot.target
        s["resume_at"] = now + COMMIT_S[ability]
        bot.stop()
    elif s["role"] == "gatherer":
        _gather(bot, s, now)


def _gather(bot, s, now):
    if _nodes is None:
        _read_nodes(bot)
        return
    if s["working"]:
        if now >= s["work_until"]:
            s["working"] = False
            s["avoid"].add(s["node"][0])
            s["node"] = None
            bot.call("work_stop")
            bot.wander()
        return
    if s["node"] is None:
        if now < s["next_find"]:
            return
        s["next_find"] = now + 5.0
        best, best_d = None, FIND_RADIUS_M
        level = getattr(bot.swarm, "level", None)
        here = (bot.pos["x"], bot.pos["z"])
        for n in _nodes:
            if n[0] in s["avoid"]:
                continue
            d = math.hypot(n[2] - bot.pos["x"], n[3] - bot.pos["z"])
            # Not across a bay: the server refuses a step into deep water, and a bot walking straight at a node
            # over the sea stood at the shore for good (the expanse, PROGRESS step 25).
            if d < best_d and (level is None or level.segment_dry(here, (n[2], n[3]))):
                best, best_d = n, d
        if best is None:
            s["avoid"].clear()      # walked round them all: any may have grown back
            bot.wander()            # none near (a bot living in the mountains): walk on and look again
            return
        s["node"] = best
        # Stand REACH_M short of its centre, on the side the bot comes from.
        dx, dz = bot.pos["x"] - best[2], bot.pos["z"] - best[3]
        d = math.hypot(dx, dz) or 1.0
        s["stand"] = (best[2] + dx / d * REACH_M, best[3] + dz / d * REACH_M)
        bot.walk_to(*s["stand"])
        return
    if math.hypot(bot.pos["x"] - s["stand"][0], bot.pos["z"] - s["stand"][1]) < 0.3:
        bot.stop()
        # As a player stops and then taps E: only once the server has us standing there too (on a busy
        # world it lags the bot's own place by a step or two, and from 3 m out the node is "too far").
        sp = bot.server_pos
        s.setdefault("arrived", now)
        if (sp is None or math.hypot(sp["x"] - s["stand"][0], sp["z"] - s["stand"][1]) > 0.5) and now - s["arrived"] < 2.0:
            return
        s.pop("arrived", None)
        bot.call("saw_nodes", [s["node"][0]])
        bot.call("gather", s["node"][0], False)
        s["working"] = True
        # 6 to 12 s, then on: the shortest window a run measures (15 s) always sees a gatherer walk.
        s["work_until"] = now + bot.rng.uniform(6.0, 12.0)
    elif bot.target is None or bot.paused:
        # The walk was interrupted (a correction), or it had stopped there and the server's correction then
        # put it a step away (paused for good, the expanse found): on to the node again.
        s.pop("arrived", None)
        bot.walk_to(*s["stand"])


def on_result(bot, request_id, reducer, ok, text):
    s = getattr(bot, "rr", None)
    if s is None:
        return
    if reducer == "use_ability_seen" and not ok:
        s["combo"] = 0      # the swing never happened: the combo starts again, as a client's does
    elif reducer == "wield":
        s["wielded"] = ok
        if not ok:
            bot.log("load_bot: wield refused: " + text)
    elif reducer == "gather" and not ok and s["node"] is not None:
        # Worked out (or refused): on to another node at once.
        s["working"] = False
        s["avoid"].add(s["node"][0])
        s["node"] = None
        bot.wander()
