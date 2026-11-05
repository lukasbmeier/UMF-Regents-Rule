# Before the minigame overhaul: where they stand, what is coming, and the decisions that are yours (2026-11-04)

Luke, 2026-11-04: "Let's start the minigame rework. First summarize where we are currently, and forecast ones we
will need in the future (herbalism, crafting for each complex weapon/armor/tool?, other skills). I think tiers
(copper, iron tier 1, steel+ tier 2, etc) will need increasingly hard but similar minigames to show skill while
rewarding. Also the quality of 2d minigames is a little low compared to the 3d assets, can we improve or should I
look for assets ... (maybe have gemini create javascript versions with good graphics/2d assets and convert them to
godot?)"

This is item (2) of `GAME.md`'s "The order of work, armor parked": **Fine and Masterwork take real skill, and a
skill's minigame grows as the skill levels up.** Like `ARMOR_PREP.md`, every decision (§7) carries a proposed
answer; nothing is built until Luke answers, then the answers go to `GAME.md` and §8 becomes the order of work.

Already settled (Luke's, `GAME.md` #17 and after): minigames are **immersive to their skill** (not a charge bar or a
QTE); every skill is **dual-mode** (tap E = AFK, hold E = the minigame; a good round pays AFK x 1.25 x score and 1.3x
rares, so AFK is never a non-option); **tier bands get harder minigames** (2026-10-18: woodcutting 1-3 branch dodge,
4-5 a harder one, 6 another); the server replays every round from its inputs; Escape leaves a round (gathering keeps
what it got, making uses nothing); grades: Common < 400 <= Fine < 800 <= Masterwork (`regents.grade_*_q`).

## 1. Where they stand

### 1.1 The four that are built
| Skill | Station / node | The minigame | Controls | Round | What its score decides |
|---|---|---|---|---|---|
| Woodcutting | Tree, Oak, Yew | **Branch dodge**: chop a 2D trunk from the left or right; a branch at your head on the side you chop from hits and staggers you | A / D | 10 s | how many logs (yield) |
| Mining | Copper, iron, coal rock | **Follow the seam**: strike the glowing next notch of a faint crack; open it end to end and the rock splits | click | 10 s | how much ore (yield) |
| Smelting | Furnace | **Bellows, then pour**: mash to keep the heat in a drifting, narrowing band under the burn line; then hold to tilt the crucible to the mold's line | Space / click, hold | 11-12 s | how many bars (batches) |
| Smithing | Anvil | **Shape to the outline**: strike the columns of a hot bar where it stands above the part's silhouette; a strike spreads into its neighbors; reheat with RMB | click, RMB | 15 s | **the part's QUALITY**, so its grade |

Each is a params resource (content, edited in the Inspector), a pure GDScript model, its Rust twin the server replays
(`server/src/genre/regents/{chop,crack,smelt,shape}.rs`), golden vectors from a third (Python) copy, a UI (a
`SkillMinigame`), and lines in `SkillMinigames`. All four play alone in `game/regents/skilling/skilling_lab.tscn` (F6).

### 1.2 What a round pays today
- **Gathering** (woodcutting, mining): items = AFK rate x 1.25 x score. Rares x 1.3. Score never touches quality (raw
  materials have none, `MATERIALS.md` §1).
- **Smelting**: batches = the same formula. Bars stack and have no quality, so **smelting skill never reaches Fine or
  Masterwork.**
- **Smithing**: quality = the score (thousandths), one part a round; AFK makes 350 (Common). **The only minigame that
  sets a grade.**
- **The workbench** (grips, hilts, rivets at the anvil, assembly, the yew bow and staff, arrows): **no minigame.**
  Assembly takes the head's quality; **grips, bows and staves have no quality at all**, so a wood-core weapon (the bow,
  the staff) can never be Fine or Masterwork from crafting.
- **Rank** only gates (which nodes and recipes you may use); it never changes how a round plays. A better TOOL swings
  faster in branch dodge and the seam (`SkillMinigames.with_speed`).

### 1.3 The tier ladder today
| Skill | Tier 1 | Tier 2 | Tier 3 | Feels |
|---|---|---|---|---|
| Woodcutting | Tree: 40 % branches, 20 chops | Oak: 50 %, 24, longer stagger | Yew: 62 %, 28 | harder numbers, same game |
| Mining | Copper: 7 notches, 6 shown ahead | Iron: 8, tighter, 2 ahead | Coal: 9, wilder, quicker | harder numbers, same game |
| Smelting | Copper / iron bar | | Steel bar: hotter, faster drift, narrower band | slightly harder |
| Smithing | copper head | iron head | steel head | **identical**: only the pattern's outline differs |

So today's ladder is "the same game, numbers tightened", and smithing, the one that decides the grade, does not
climb at all. A practiced player makes Masterwork steel as easily as Masterwork copper.

### 1.4 What a minigame costs
A new model is about one step of work: params, the GDScript model, the Rust twin, the Python golden maker and its
golden file, a UI, the registry, unit tests, an integration round. A new MECHANIC in an existing model is less:
add-only params whose default switches it off (so today's rounds replay unchanged), the three models and new
goldens. A reshaped model whose old rounds would score differently gets a new challenge kind (rule 17: an old
client then can't play the new round, but old rounds still score as they did).

### 1.5 Why they look worse than the world
Every minigame is a 960 x 620 panel in the middle of the screen, drawn with `draw_rect`, `draw_circle` and
`draw_line` in flat colors: no textures, no lighting, no particles, **no sound**, the default font. The woodcutter is
a red rectangle with a circle for a head. Beside Quaternius's lit 3D world it reads as a placeholder, because it is
one. The good news: **the models are pure and the UIs only draw them**, so the whole look can be redone without
touching a rule, a Rust twin or a golden.

### 1.6 Found while looking
- The copper and steel axe heads' rounds are titled "Iron axe head", both sword blades' "Iron sword blade" (the
  params' `display_name`, copied when they were made). A one-line fix each, in the first build step.

## 2. What is coming: every skill that will want a minigame
Most new skills fit one of **five families** the built ones already are. A family is one model with params; a new
skill in a family is mostly content and a UI skin, not a new model.

| Family | Built as | Its idea |
|---|---|---|
| **Dodge** (timed sides) | branch dodge | act on a rhythm, read what is coming, punish the wrong side |
| **Trace** (a path) | follow the seam | strike or follow points along a seeded path |
| **Heat** (hold in a band) | bellows, then pour | keep a drifting value in a band, then finish to a line |
| **Shape** (match a profile) | shape to the outline | work columns toward a silhouette |
| **Tension** (pull without snapping) | not built (§7.2 of the design) | hold to pull while a strain rises; too far snaps |

| Skill (product) | When | Proposed minigame (Luke's to decide) | Family | Score decides |
|---|---|---|---|---|
| **Herbalism** (herbs, fiber) | next, with hunting | **pull the root**: ease it out, strain rises while held; snap and it is lost | Tension (new model) | yield |
| **Hunting** (hides, sinew, meat) | next | the hunt is the fight; **skinning** the kill: follow the cut line along the hide; a cut off the line tears it | Trace (a skin of the seam) | yield (whole hides vs torn) |
| **Woodworking** (grips, hilts, bow staves, staff shafts) | with or right after the overhaul (§7, M5) | **carve to the line**: shave a turning blank down to the profile; wood can't be put back, over-cutting ruins it | Shape, subtractive | **quality** (gives bows and staves a grade) |
| **Tanning** (hide to leather) | with hunting | scrape and stretch: a scraping rhythm across the hide, or soak timing | Dodge or Heat | batches |
| **Spinning / weaving** (fiber to thread to cloth) | with herbalism | the shuttle: pass it on the beat, a pattern of colors | Dodge | batches (thread), quality (cloth) |
| **Leatherworking / tailoring** (cloth and leather armor) | with armor | **stitch the seam**: follow the pattern's seam with the needle, on a rhythm | Trace | **quality** |
| **Armorsmithing** (plates) | with armor | **shape to the outline** again: a plate is a pattern with its own silhouette | Shape (no new model) | **quality** |
| **Alchemy** (potions, the trinket?) | with potions | heat the mix in its band and add each herb when it shows its color | Heat (+ timed adds) | batches or potency |
| **Fishing** | later | game 1's cast and reel | its own | yield |
| Assembly (the workbench) | | **no minigame**: a choice screen (parts, grip shape, traits); quality from the core | | |

### 2.1 Complex weapons, armor and tools: one minigame per craft, not per item
Luke asked whether each complex weapon, armor piece or tool needs its own. **Proposed: no.** The minigame belongs to
the SKILL (smithing, woodworking, stitching); the PATTERN feeds it data (its outline, its seam, how many steps). A
complex item is more PARTS, so more rounds, each in its own skill: a steel greatsword is a blade (smithing, a long
outline), a crossguard (smithing, a short one), a grip (woodworking) and a binding, then assembly. A new weapon is
a pattern with an outline drawn in the Inspector, never code. This is already how the axe, pickaxe and sword heads
work (one shape model, three outlines).

## 3. Tiers: harder, but similar
Luke: "increasingly hard but similar minigames". Proposed: each skill keeps ONE game for life, and it climbs in
three ways at once.

1. **Within a band, the numbers tighten** (what happens now): copper, iron, steel each a little harder.
2. **Each new band adds ONE new thing to master**, layered on the same game, never a different game. What you
   learned on copper still works on mithril; there is just more to it. (This is the reading of the 2026-10-18 "each
   band its own harder minigame" that fits "similar": §7 M1 asks.)
3. **Your rank eases the round you are on** (a small hot-rule edge per rank above the node's or recipe's
   requirement, capped), so leveling up feels good, then the next tier is hard again. A sawtooth: copper is hard at
   rank 1 and easy at rank 4; iron at rank 3 is hard again.

The bands, as Luke's message reads: **band 1 = copper and iron, band 2 = steel and up** (today's tiers: copper 1,
iron 2, steel 3, coal 3, yew 3). The 2026-10-18 call put bands at tiers 1-3 / 4-5 / 6; §7 M2 asks which holds.

What the band's new thing could be (proposals, one each, to play before deciding):

| Skill | Band 1 (today's game) | Band 2: the new thing | Band 3 |
|---|---|---|---|
| Woodcutting | branches on your side | **knots**: a knotted piece takes two chops from the same side in a beat | **deadwood falls**: a piece dropping from above must be stepped away from |
| Mining | the seam, outline shown | **brittle notches**: strike on the rock's ring (a beat); too soon and the seam cracks wrong | **a fault**: two seams cross; follow the wrong branch and the split closes |
| Smelting | the band, then the pour | **slag**: skim it (a key) when it rises, or the bar comes out short | a two-metal melt: two bands to hold at once (alloys) |
| Smithing | shape to the outline | **heat colors**: metal only moves in its working color; struck too cold it cracks (a mark you can't hammer out) | **the quench**: release at the right color at the end; a good quench lifts the score, a bad one cracks the part |
| Woodworking | carve to the profile | **grain**: cutting against the grain tears deeper | figured wood: a pattern to keep in the face |
| Herbalism | pull the root | **roots that branch**: two strains to watch | a wilting plant: a timer on the whole pull |

Smithing goes first (§8) because it is the one that sets the grade, and it is the only skill whose tiers are the
same game today.

## 4. Showing skill, and paying for it
- **The grade is the reward for making.** Today quality = the score, so a 400 round is Fine and an 800 Masterwork.
  Proposed: keep that straight mapping (simple to read, easy to tune) and set the DIFFICULTY so the shares come out
  right, measured (§6) rather than guessed. Proposed targets, Luke's to change: on a band you have just reached, a
  good player makes Fine about half the time and Masterwork about 1 in 10; three ranks later, Masterwork about 1 in
  3. A careless round is Common; AFK is always Common.
- **Higher tiers pay more for the same skill**: a Masterwork steel blade is worth more than a Masterwork copper one
  (tier sets Power), so the harder band's Masterwork is the prize, and copper Masterwork staying easy for a veteran
  is fine.
- **Gathering pays in amount and rares**: today a perfect round is 1.25x AFK and 1.3x rares. Proposed: leave the
  multipliers, and make "rares" mean the catalysts (`MATERIALS.md` §6) so a skilled gatherer feeds trait ranks.
- **Smelting**: bars stay without quality (they stack). Its skill pays in bars per ore. (Open: §7 M6.)
- **Bots**: a scripted client can play any of these perfectly (the accepted risk, design §13 #19). The more
  Masterwork is worth, the more that matters; a later step, not this one.

## 5. The look
### 5.1 Three ways to make them look like the game
| | What it is | Cost | Good | Bad |
|---|---|---|---|---|
| **A. Re-skin in 2D** | real painted art (textures, a UI theme, a font), particles (chips, sparks, dust), sound, motion (shake, flashes, squash) | low | quick; each UI is one file | 2D art next to a 3D world still reads as a different game unless the art is very good |
| **B. In the world** | the camera comes in close on the real tree, rock or anvil; the seam is a decal on the rock's mesh, the bar a mesh that deforms; others see you working | high | the most immersive; others watch you smith | the camera, other players and the HUD all get involved; hardest to read clearly |
| **C. A 3D stage in the panel** | the panel shows a small 3D scene (a `SubViewport`) built from the game's own Quaternius models and lit like the world, with 2D readouts (heat, the outline) in a proper theme on top, plus particles and sound | medium | matches the 3D assets exactly, costs nothing in art, reversible, the world camera untouched; can become B later | a 3D stage per minigame to build |

**Proposed: C, prototyped on smithing first** (the anvil, the hot bar as a mesh glowing by its heat, the hammer,
sparks, a clang), shown to Luke before the others. A 2D readout stays where 2D is clearer (the target outline).

### 5.2 Assets, and the Gemini idea
- **Our own 3D assets first**: Quaternius's packs (CC0) already have the anvil, rocks, trees and tools; a 3D stage
  uses them as they are, so the style matches by construction.
- **CC0 for the rest**: Kenney's particle pack, UI packs, fonts and audio (impact, RPG, foley), freesound's CC0
  filter. Paid royalty-free packs (itch.io, Craftpix) are possible if Luke wants painted 2D; the design's asset rule
  says CC0 unless noted (`RULE_DESIGN.md` §14), so a paid pack is his call, and every import gets its
  `ATTRIBUTION.md` line.
- **Gemini making JavaScript versions to convert: proposed only as a MOCKUP tool**, not a source of code. What it
  is good for: a quick, playable look at an idea (a carve-to-the-line, a heat-color anvil) to react to before any
  work here. Why not convert its code: every minigame here must be an integer, seeded, deterministic model with a
  Rust twin the server replays and golden vectors pinning both; a JS canvas game is none of those and would be
  rewritten rule by rule anyway. Its graphics would be either canvas shapes (today's problem again) or generated
  images. **AI-generated art** in a shipped game must be disclosed on Steam's store page, and its style would have to
  match Quaternius's; a sound reason to prefer the game's own 3D assets. If Luke does mock ideas in Gemini, a
  short screen recording or the HTML file is enough to work from.

## 6. Measuring it: the difficulty readout
"Masterwork takes real skill" needs a number, not a feeling. Proposed tool (first build step): **simulated players
of set skill** (a perfect one, a good one with ~60 ms timing spread and occasional misreads, an average one, a
careless one) each play a few hundred seeds of a round through its model, and the readout shows the score spread and
the Common / Fine / Masterwork shares per tier and per rank. It runs headless in the unit suite (a pin: "a good
player makes Masterwork steel less than 15 % of the time") and in the skilling lab beside each round, so a designer
tuning params sees the shares move. Luke's own play stays the final word; the readout keeps a later tweak from
silently making Masterwork routine again.

## 7. Decisions for Luke
Each with the proposed answer. The bold part is what needs his yes or no.

- **M1. The ladder's shape.** **Proposed: one game per skill for life; a band adds one new thing on top; numbers
  tighten within a band** (§3). The alternative is a different game per band, as 2026-10-18 could be read.
- **M2. The bands.** **Proposed: as Luke wrote today: band 1 = tiers 1-2 (copper, iron; tree, oak), band 2 = tier 3
  and up (steel, coal, yew)**, band 3 from the next metal. Or keep 2026-10-18's 1-3 / 4-5 / 6.
- **M3. Rank eases the round.** **Proposed: yes, small**: each rank above the requirement widens the windows a few
  percent, capped at three ranks (hot rules). Or rank stays a gate only and skill alone shows.
- **M4. What a score is worth.** **Proposed: quality = score, as now; the difficulty is tuned to target shares**
  (§4: fresh band Fine ~50 %, Masterwork ~10 %; three ranks on, Masterwork ~33 %). Luke's numbers win.
- **M5. Woodworking gets a minigame.** **Proposed: yes, carve to the line**, so grips, bows and staves get a quality
  and a grade (today they can't). Assembly stays a choice screen with no minigame.
- **M6. Smelting's reward.** **Proposed: bars stay without quality; the score pays in bars per ore.** Or a good smelt
  makes a better bar that starts the smith's round closer to the outline (more to track, more reason to smelt well).
- **M7. The look.** **Proposed: C, a 3D stage in the panel, on smithing first** (§5.1), sound and particles
  included. Or A (2D re-skin) or B (in the world).
- **M8. Art sources.** **Proposed: the game's own Quaternius models plus CC0 (Kenney, freesound); Gemini for mockups
  only.** His calls: paid packs yes or no; AI-generated art yes or no.
- **M9. Each band's new thing** (§3's table). **Proposed: start with smithing's heat colors (band 2) and the quench
  (band 3)**; the others are proposals to prototype in the lab and play before deciding.
- **M10. The new skills' minigames** (§2's table): herbalism's pull-the-root and skinning's cut line are the next
  two needed (herbalism and hunting come right after this). **Proposed: as in the table**; decided with those steps.

## 8. The order of work (once answered)
1. **The readout and the fixes**: the simulated players and the share readout (§6), pinned in the unit suite and
   shown in the lab; the copied round titles (§1.6).
2. **The look, on smithing**: the 3D stage (or M7's choice), sparks, sound, a proper font and theme. Luke plays it.
3. **Smithing's ladder**: heat colors (band 2), the quench (band 3), rank easing (M3), tuned to M4's targets with the
   readout. Luke plays copper, iron and steel heads.
4. **The other three**: mining, woodcutting and smelting get the look and their band's new thing, one at a time,
   each played by Luke.
5. **Woodworking's carve to the line** (M5): grips, hilts, bows and staves get a quality.
6. Then herbalism and hunting (`GAME.md`'s item 3), whose minigames (pull the root, skinning) are built to this bar
   from the start.
