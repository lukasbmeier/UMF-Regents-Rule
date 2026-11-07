"""MAKE THE MINIGAMES' SOUNDS (MINIGAMES_PREP.md §3.1: sound is part of reading a round), synthesized: no recording,
no download, ours (CC0). Each skill's go in game/regents/art/sound/<skill>/ (22050 Hz, mono, 16-bit); Godot imports
them on its next start (or `godot --headless --path . --import`). Change a number here and run it again to change a
sound; a recorded CC0 sound may replace one under the same name (its source noted in that folder's ATTRIBUTION.md).

    python game/regents/tools/make_skill_sounds.py

Smithing: the heavy strike's clang (the minigame pitches it down as the bar cools), the tap, a cold strike's thud,
the reheat's whoosh. Woodcutting: the axe biting, a branch striking the woodcutter, the cut piece landing. Mining:
the pick on stone, the rock splitting, a strike off the seam. Smelting: the bellows' breath, the pour's hiss."""

import math
import os
import random
import struct
import wave

RATE = 22050
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art", "sound")


def write(skill, name, samples):
    out = os.path.join(ART, skill)
    os.makedirs(out, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.89)) * 32767)) for s in samples)
    with wave.open(os.path.join(out, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print("wrote", skill, name, "%.2f s" % (len(samples) / RATE))


def ring(seconds, partials, noise_ms, noise_amp, seed):
    """Struck metal (or stone): inharmonic partials (freq, amp, decay per second), and a short burst of noise for the hit."""
    rnd = random.Random(seed)
    n = int(seconds * RATE)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        s = sum(a * math.exp(-d * t) * math.sin(2 * math.pi * f * t + ph) for f, a, d, ph in partials)
        if t < noise_ms / 1000.0:
            lp += 0.5 * (rnd.uniform(-1, 1) - lp)
            s += noise_amp * lp * (1.0 - t / (noise_ms / 1000.0))
        attack = min(1.0, t / 0.0015)
        out.append(s * attack)
    return out


def thud(seconds, seed, tone=140.0, decay=28.0, grit=3.0, smooth=0.08):
    """A dull blow: a low tone and filtered noise, short, no ring (cold iron, wood, a log landing, stone)."""
    rnd = random.Random(seed)
    out = []
    lp = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        lp += smooth * (rnd.uniform(-1, 1) - lp)
        out.append((0.8 * math.sin(2 * math.pi * tone * t) + grit * lp) * math.exp(-decay * t) * min(1.0, t / 0.002))
    return out


def whoosh(seconds, seed, k_lo=0.02, k_hi=0.10, crackle_rate=0.002):
    """Air: filtered noise that swells and dies (the forge, the bellows), with a little crackle."""
    rnd = random.Random(seed)
    n = int(seconds * RATE)
    out = []
    lp = lp2 = 0.0
    for i in range(n):
        t = i / n
        k = k_lo + k_hi * math.sin(math.pi * t)
        lp += k * (rnd.uniform(-1, 1) - lp)
        lp2 += k * (lp - lp2)
        env = math.sin(math.pi * min(1.0, t * 1.4)) ** 2 if t < 0.72 else math.sin(math.pi * 0.72 * 1.4) ** 2 * (1.0 - (t - 0.72) / 0.28)
        crackle = (rnd.uniform(-1, 1) * 0.6) if rnd.random() < crackle_rate else 0.0
        out.append(lp2 * 4.0 * env + crackle * env)
    return out


def rustle(seconds, seed):
    """Leaves: bright noise in quick bursts, dying away."""
    rnd = random.Random(seed)
    out = []
    hp_prev = lp = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        x = rnd.uniform(-1, 1)
        lp += 0.35 * (x - lp)
        hp = x - lp
        burst = 0.5 + 0.5 * math.sin(2 * math.pi * 23 * t + 3 * math.sin(2 * math.pi * 7 * t))
        out.append(hp * burst * math.exp(-6.0 * t) * min(1.0, t / 0.01))
        hp_prev = hp
    return out


def hiss(seconds, seed):
    """Molten metal: a bright hiss that rises fast and fades slowly, a few spits in it."""
    rnd = random.Random(seed)
    out = []
    lp = 0.0
    for i in range(int(seconds * RATE)):
        t = i / RATE
        x = rnd.uniform(-1, 1)
        lp += 0.6 * (x - lp)
        spit = rnd.uniform(-1, 1) * 2.0 if rnd.random() < 0.0015 else 0.0
        out.append((x - lp + spit) * min(1.0, t / 0.05) * math.exp(-2.2 * t))
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def main():
    # Smithing (2026-11-05, PROGRESS 41: unchanged from make_smithing_sounds.py).
    write("smithing", "clang", ring(1.1, [(587, 1.0, 5.0, 0.0), (1453, 0.55, 7.0, 1.1), (2389, 0.35, 9.0, 2.3),
                                          (3517, 0.22, 13.0, 0.4), (4710, 0.12, 18.0, 1.7), (294, 0.25, 9.0, 0.9)], 18, 0.9, 1))
    write("smithing", "tap", ring(0.45, [(1174, 0.8, 11.0, 0.3), (2907, 0.45, 16.0, 1.9), (4632, 0.25, 22.0, 0.8)], 6, 0.35, 2))
    write("smithing", "cold", thud(0.22, 3))
    write("smithing", "reheat", whoosh(1.3, 4))
    # Woodcutting: the axe biting (a woody knock), a branch in the face (leaves and a knock), the piece landing.
    write("woodcutting", "chop", mix(thud(0.28, 11, tone=210.0, decay=22.0, grit=4.0, smooth=0.25),
                                    ring(0.12, [(620, 0.25, 40.0, 0.0), (1310, 0.15, 55.0, 1.0)], 4, 0.3, 12)))
    write("woodcutting", "branch", mix(rustle(0.45, 13), thud(0.2, 14, tone=170.0, decay=30.0, grit=1.5)))
    write("woodcutting", "fall", thud(0.4, 15, tone=95.0, decay=12.0, grit=3.5, smooth=0.06))
    # Mining: the pick on stone (a short, gritty clink), the rock splitting (a crack and a rumble), off the seam.
    write("mining", "strike", ring(0.3, [(1780, 0.7, 26.0, 0.0), (3150, 0.4, 34.0, 1.3), (5020, 0.2, 45.0, 0.6)], 25, 1.2, 21))
    write("mining", "split", mix(thud(0.9, 22, tone=70.0, decay=5.0, grit=5.0, smooth=0.05),
                                 [s * 0.6 for s in rustle(0.35, 23)]))
    write("mining", "miss", thud(0.2, 24, tone=230.0, decay=35.0, grit=2.0, smooth=0.3))
    # Smelting: a pump of the bellows, the pour.
    write("smelting", "bellows", whoosh(0.45, 31, k_lo=0.03, k_hi=0.12, crackle_rate=0.0))
    write("smelting", "pour", hiss(1.0, 32))


main()
