# The wardrobe: clothes, armor and the dye (2026-11-14, before armor comes back)

Luke, 2026-11-14: "before [armor] we need to figure out clothes and shaders on them ... do we have armor models? all
colors on every model should have a shader material that allows for any color combo ... a lab that is basically a
more advanced character selector ... a full inventory of what clothes/armor potential we have based on our prep, what
we need and how we can reuse metal for all tiers/metals with shaders and recoloring."

Built (PROGRESS 81): the Knight outfit brought in, a dye that colors ANY piece ANY way, and the WARDROBE LAB
(`game/regents/wardrobe/wardrobe_lab.tscn`, F6, no server). Nothing is in the game yet: the lab is presentation only.
Luke's calls of 2026-11-14 (who wears what) are in §5; W1-W8 and the tier colors are settled (§7, `GAME.md`).

## 1. Short answers

- **Armor models: yes.** The Quaternius *Modular Character Outfits - Fantasy* pack (Luke's, CC0) has a full KNIGHT:
  plate body, plate arms, plate legs, plate feet, two closed helms (armet, horned), round and spiked pauldrons, a
  scarf, and a cloth tabard torso that goes over the same arms and legs. Male and female. The foundation's import left
  it out ("armour nobody fishes in"); it is now the genre's, in `game/regents/art/outfits/knight/`.
  The Noble adds metal accessories (gorget, two pauldrons, crown), the Ranger a leather-and-metal pauldron.
- **Any color on every piece: yes, built.** One shader (`outfit_dye.gdshader`) for all five outfits. Each outfit's
  painted atlas is split into SIX DYE SLOTS: metal, main cloth, accent cloth, trim, leather and under (the dark
  undercloth). Each slot takes any color, and the metal also takes a FINISH (color, metallic, roughness, wear). The
  painting's light and dark (folds, dents, stitching, grime) stay. It is faithful: the lab's Colorways view puts each
  outfit's painted colorways (the pack's textures) beside the same colorway made by the dye from one texture, and
  they are hard to tell apart.
- **One mesh for every metal tier: yes, built.** The Knight's plate in copper, iron, steel and four studies for later
  tiers (blued, gilded, blackened, pale alloy) is ONE set of meshes and ONE texture. A tier is a `MetalFinish` `.tres`.
  Copper gets green verdigris in its hollows, iron gets rust, and steel gets almost none. The lab's Metal tiers view
  shows all seven side by side.

## 2. What we have

### 2.1 The pieces (all in the lab; both bodies have every one)

| outfit | reads as | torso | arms | legs | feet | head | shoulders | neck |
|---|---|---|---|---|---|---|---|---|
| **Knight** (genre) | METAL plate | plate armor; cloth tabard | plate + leather | plate | plate | armet; horned helm | round; spiked | scarf (cloth) |
| **Noble** | cloth, metal trim | doublet | sleeves | trousers | boots | crown (metal) | pauldron; lion pauldron (metal) | gorget (metal) |
| **Ranger** | LEATHER | jerkin | bracers | trousers | boots | hood (cloth) | pauldron (leather + metal) | - |
| **Wizard** | CLOTH robe | robe | sleeves | trousers | shoes | - | - | - |
| **Peasant** | plain cloth | shirt | sleeves | trousers | boots | - | - | - |

Worn with any of them: two heads (male, female), six skin tones, the hairstyles, beards and brows, ten hair colors
(`CharacterLooks`, the foundation's). A closed helm hides hair and beard, and a hood hides the hair
(`Wardrobe.HIDES_HAIR`). Pieces are FOUND by file name (`<Male|Female>_<Outfit>_<Part>.gltf` in
`Wardrobe.PIECE_DIRS`): a new outfit is its files in a folder, its zones in `zones.json` and a bake. Then the lab
lists it.

Not usable as they are (checked in Luke's downloads): the *All in One* bundle's older characters (Knight Character
2018, Ultimate Modular Men / Women 2022, RPG Characters 2020) are low-poly, flat-colored, on other skeletons and in
another style: none mixes with these outfits without remodeling. The Bestiary is monsters.

### 2.2 What each piece is made of

Written by the lab's shots (`-- <dir>` writes `wardrobe_inventory.md`; the lab's Pieces list shows it per piece):
each piece's vertices by the dye slot under them. These are vertices, not area: a buckle has many and a cloth panel
few, so read it as a guide.

| body | outfit | slot | piece | metal | leather | main | accent | trim | under |
|---|---|---|---|---|---|---|---|---|---|
| female | Knight | shoulders | Acc_Pauldrons_Round | 100 % |  |  |  |  |  |
| female | Knight | shoulders | Acc_Pauldrons_Spike | 100 % |  |  |  |  |  |
| female | Knight | neck | Acc_Scarf |  |  |  | 100 % |  |  |
| female | Knight | arms | Arms | 34 % | 55 % |  |  |  | 11 % |
| female | Knight | torso | Body_Armor | 73 % | 26 % |  |  |  | 1 % |
| female | Knight | torso | Body_Cloth | 7 % | 43 % | 20 % | 21 % | 9 % |  |
| female | Knight | feet | Feet | 100 % |  |  |  |  |  |
| female | Knight | head | Head_Armet | 100 % |  |  |  |  |  |
| female | Knight | head | Head_Horns | 100 % |  |  |  |  |  |
| female | Knight | legs | Legs | 84 % | 16 % |  |  |  |  |
| female | Noble | neck | Acc_Gorget | 100 % |  |  |  |  |  |
| female | Noble | shoulders | Acc_Pauldron | 100 % |  |  |  |  |  |
| female | Noble | shoulders | Acc_Pauldron_Lion | 100 % |  |  |  |  |  |
| female | Noble | arms | Arms | 6 % |  | 15 % | 80 % |  |  |
| female | Noble | torso | Body | 24 % | 12 % | 45 % | 16 % |  | 2 % |
| female | Noble | feet | Feet |  | 8 % |  | 76 % |  | 16 % |
| female | Noble | head | Head_Crown | 100 % |  |  |  |  |  |
| female | Noble | legs | Legs |  |  |  | 100 % |  |  |
| female | Peasant | arms | Arms | 29 % | 59 % |  |  | 12 % |  |
| female | Peasant | torso | Body |  | 23 % | 1 % |  | 4 % | 72 % |
| female | Peasant | feet | Feet |  | 100 % |  |  |  |  |
| female | Peasant | legs | Legs |  |  |  | 100 % |  |  |
| female | Ranger | shoulders | Acc_Pauldrons | 100 % |  |  |  |  |  |
| female | Ranger | arms | Arms | 34 % | 53 % |  | 1 % |  | 13 % |
| female | Ranger | torso | Body | 31 % | 48 % | 21 % |  |  |  |
| female | Ranger | feet | Feet | 48 % | 51 % |  |  |  |  |
| female | Ranger | head | Head_Hood |  |  | 98 % | 2 % |  |  |
| female | Ranger | legs | Legs |  |  |  |  |  | 100 % |
| female | Wizard | arms | Arms |  | 34 % |  |  |  | 66 % |
| female | Wizard | torso | Body | 58 % | 2 % | 34 % |  |  | 5 % |
| female | Wizard | feet | Feet |  | 49 % |  |  |  | 51 % |
| female | Wizard | legs | Legs | 6 % |  |  | 89 % | 5 % |  |
| male | Knight | shoulders | Acc_Pauldron_Round | 100 % |  |  |  |  |  |
| male | Knight | shoulders | Acc_Pauldron_Spike | 100 % |  |  |  |  |  |
| male | Knight | neck | Acc_Scarf |  |  |  | 100 % |  |  |
| male | Knight | arms | Arms | 44 % | 47 % |  |  |  | 9 % |
| male | Knight | torso | Body_Armor | 48 % | 33 % |  |  |  | 19 % |
| male | Knight | torso | Body_Cloth | 7 % | 44 % | 19 % | 21 % | 9 % |  |
| male | Knight | feet | Feet_Armor | 100 % |  |  |  |  |  |
| male | Knight | head | Head_Armet | 100 % |  |  |  |  |  |
| male | Knight | head | Head_Horns | 100 % |  |  |  |  |  |
| male | Knight | legs | Legs_Armor | 72 % | 28 % |  |  |  |  |
| male | Noble | neck | Acc_Gorget | 100 % |  |  |  |  |  |
| male | Noble | shoulders | Acc_Pauldron | 100 % |  |  |  |  |  |
| male | Noble | shoulders | Acc_Pauldron_Lion | 100 % |  |  |  |  |  |
| male | Noble | arms | Arms | 6 % | 75 % |  | 9 % |  | 10 % |
| male | Noble | torso | Body | 53 % | 30 % | 16 % |  |  | 1 % |
| male | Noble | feet | Feet | 65 % |  |  |  |  | 35 % |
| male | Noble | head | Head_Crown | 100 % |  |  |  |  |  |
| male | Noble | legs | Legs |  |  |  | 76 % |  | 24 % |
| male | Peasant | arms | Arms |  | 100 % |  |  |  |  |
| male | Peasant | torso | Body | 9 % | 72 % | 18 % |  | 1 % |  |
| male | Peasant | feet | Feet |  | 100 % |  |  |  |  |
| male | Peasant | legs | Legs |  | 1 % |  | 99 % |  |  |
| male | Ranger | shoulders | Acc_Pauldron | 100 % |  |  |  |  |  |
| male | Ranger | arms | Arms |  | 58 % |  | 1 % |  | 42 % |
| male | Ranger | torso | Body | 31 % | 47 % | 22 % |  |  |  |
| male | Ranger | feet | Feet_Boots | 48 % | 51 % |  |  |  |  |
| male | Ranger | head | Head_Hood |  |  | 98 % | 2 % |  |  |
| male | Ranger | legs | Legs |  |  |  |  |  | 100 % |
| male | Wizard | arms | Arms |  | 28 % |  |  |  | 72 % |
| male | Wizard | torso | Body | 57 % | 16 % | 18 % |  |  | 9 % |
| male | Wizard | feet | Feet |  | 52 % |  |  |  | 48 % |
| male | Wizard | legs | Legs | 6 % |  |  | 89 % | 5 % |  |

What it says: the Wizard and Noble torsos carry a lot of METAL TRIM (buckles, clasps, gold edging), so a finish shows
on them too: a cloth chest of copper fittings is copper-trimmed. The Peasant's and the Ranger's legs have none.

## 3. How the dye works

1. **The zones, baked once** (`python game/regents/tools/wardrobe_assets.py zones`). Each outfit ships in three
   colorways; texels that CHANGE TOGETHER between them belong to one part, the way the artist split it. `zones.json`
   (designer-editable) gives each outfit's parts as reference colors, one per colorway, and names their slot. Every
   texel goes to its nearest reference, and metal (the ORM texture's blue channel) always goes to metal. Out comes
   `zones/T_<Outfit>_Zones.png` (R: the slot; B: the slot's mean brightness) and, for each colorway, a palette with
   the slots' mean colors (`palettes/<outfit>_<n>.tres`, the lab's check).
2. **The shader** reads the outfit's own albedo, ORM and normal textures (no new textures per color), and the zones
   (nearest filtering, no mipmaps, lossless). A dyed texel = the slot's color x (its painted brightness / the slot's
   mean brightness). Metal also takes the finish's metallic and roughness, plus WEAR in the hollows. A color's alpha
   is how much: 0 keeps the painting.
3. **`DyePalette`** (a `.tres`: the five cloth colors, a `MetalFinish`, a trim glow) is one look for a whole figure.
   A Noble torso and Knight legs worn together take the same main color and the same metal.
4. **`Wardrobe.dress(model, palette)`** gives every outfit surface of an assembled `ModularCharacter` one dye
   material per outfit (kept and re-tinted, so a color picker can drag live); skin and hair keep theirs.

Gray area under "No AI disclosure": none. The masks are the CC0 pack's own pixels sorted and averaged by a script; no
generative model touched any of it (`AI_ASSET_AUDIT.md` §5's reading of code-made work).

## 4. Reusing metal across every tier

One plate set, many tiers, in layers, cheapest first:
1. **The finish (built):** color, metallic, roughness, wear. Copper warm and verdigrised, iron dark and rusted, steel
   bright and clean. A later tier is a new `.tres` (the four studies are only looks; their names are Luke's when
   tiers 4-6 are named, `MATERIALS.md`).
2. **The trim (built):** the trim slot can glow (`trim_glow`), for a top tier's mark or runes. Cloth colors are free
   too: a tier can carry a heraldic color.
3. **The silhouette, by part (pieces exist):** the same slot has options to swap per tier: round pauldrons on copper
   and iron, spiked on steel; the armet early, the horned helm later; the tabard over plate for a "knight" look. Only
   two variants per slot exist, so this runs out after two steps.
4. **Grade or quality, if wanted (not built):** less wear and a cleaner polish for Fine and Masterwork, so a
   Masterwork copper piece looks cared for.

## 5. Who wears what, and the tiers

Settled: five equipment slots (weapon, head, chest, legs, trinket); "the chestpiece draws torso and arms, the leggings
legs and feet"; helms always shown; recolored by material; THE CHEST CARRIES ITS FAMILY'S ABILITY (cloth casting and
moving, leather quick utility, metal guarding: B8), with full-set bonuses wanted later.

**Luke, 2026-11-14 (`GAME.md`, "The wardrobe: who wears what"):** every player STARTS IN THE PEASANT CLOTHES in colors
they pick (with hair and the rest); LEATHER is the RANGER, CLOTH the WIZARD, METAL the KNIGHT; the NOBLE is not for
players (it stays for higher NPCs). Leather starts BROWN and changes with its animal; cloth stays NEUTRAL; green bases
are out.

| family | head | chest (torso + arms) | legs (legs + feet) |
|---|---|---|---|
| METAL (Knight) | armet | plate torso + plate arms + round pauldrons + scarf | plate legs + plate feet |
| LEATHER (Ranger) | the hood, dyed as leather | jerkin + bracers + its pauldron | trousers + boots |
| CLOTH (Wizard) | none yet: hair shows (W5) | robe + sleeves | trousers + shoes |
| nothing worn | hair | the Peasant shirt and sleeves, in the player's colors | the Peasant trousers and boots, in the player's colors |

(The pieces in each cell are W1, settled.)

**The tiers (accepted by Luke, 2026-11-14)** (the lab's Tiers view; each a `DyePalette` in `wardrobe/palettes/`; the
buckles and clasps take the matching metal, so a tier reads the same across families):

| tier | METAL (Knight) | LEATHER (Ranger) | CLOTH (Wizard) | fittings |
|---|---|---|---|---|
| 1 | copper: warm, verdigris in the hollows | SOFT (deer hide): tan buckskin, undyed | FLAX (linen): oatmeal and cream, twine trim | copper |
| 2 | iron: dark, rust in the hollows | SUPPLE (wolf pelt): cool gray-brown | HEMP: stone gray-taupe, pale thread | iron |
| 3 | steel: bright and clean | HARDENED (stag hide): deep oxblood, burnished | NETTLE: deep slate, silver-gray thread | steel |
| 4-6 | the four studies (blued, gilded, blackened, pale) | a new animal each (its hide's own color) | finer fibers, then the first true dyes | the tier's metal |

The names are the settled ones (H7: fibers Flax, Hemp, Nettle; leathers Soft, Supple, Hardened). The starting
clothes: `starter_*.tres` are four examples of what a player might pick (oat and brown, blue and gray, madder red, moss
and cream); the picker itself is W8.

What we NEED (the gaps):
- **A cloth hat.** Cloth has no headwear. A hat is the easiest piece there is: a rigid mesh on the head bone, as the
  hairstyles are ("Rigged to Head Bone"), so it needs no skinning. Made by hand, CC0, or commissioned
  (`AI_ASSET_AUDIT.md` §6). Until then the cloth head slot shows hair.
- **A leather helm, if the hood is not enough.** The Ranger's hood, dyed in the leather's colors, reads as a leather
  hood (the Tiers view). A coif or cap later if wanted.
- **More than one silhouette per family.** One body per family, so tiers differ by color, finish and fittings (built),
  not by shape; the Knight's spiked pauldrons and horned helm are the only spare shapes (W3).
- **Mail.** `ARMOR_PREP.md` §6 (point 3) floats a MAIL lining as a second trait-bearing part. No mail model; a
  procedural ring pattern on the under slot (in the shader, code-made) could show it without one.
- **Shields and gloves on their own.** None (gloves are part of the arms). Not asked for.
- **The undressed body.** Only heads are imported (the readme: a full body under clothes clips), so an empty slot
  shows the Peasant pieces (W4).

## 6. Into the game (the agent's plan; nothing built)

1. **A public hook in the foundation's `ModularCharacter`** (template work, `../UMF Template`): `wear(pieces)` to
   swap pieces without the appearance text, and a signal when it is put together again, so a genre can dress it.
   Today a swap goes only through `CharacterLooks.apply`, whose slots do not list the Knight.
2. **A genre look component** (like `CombatLook`): reads the `worn` row (`ARMOR_PREP.md` §3), maps each worn item to
   its pieces and palette (an item's material picks the `MetalFinish`; its cloth colors from W2), and calls
   `Wardrobe.dress` after each reassembly. Presentation only (hard rule 11).
3. **The character picker**: today it offers each outfit's colorways by index. With the dye it could offer any color
   (a key per slot on the `appearance` text, `main=#rrggbb`: old clients ignore keys they do not know, so this is
   add-only, rule 17).
4. **Cost at 300 players** (not measured yet): one dye material per outfit per player (at most three), one pass,
   three texture reads more than the imported material. Players in the same palette could share materials (a key by
   palette). To measure with the load test when it goes in.

## 7. W1-W8: ANSWERED (Luke, 2026-11-14: "Yes, all stand")

All eight as proposed, and the tier colors of §5; recorded in `GAME.md` ("W1-W8 ANSWERED").

- **W1 Which pieces each family draws:** the §5 table. Pauldrons and the scarf are PART OF THE CHEST (the scarf carries
  the player's color on plate). The Knight's tabard torso is NOT a player chest: it goes with the Noble to NPCs (guards,
  a lord's men), or later a surcoat cosmetic if wanted.
- **W2 Who picks the colors:** a mix. The STARTING CLOTHES: the player, freely. ARMOR: its tier's palette (the
  material decides: leather by animal, cloth by fiber, metal by bar), so anyone can read a tier at a glance. LATER,
  DYES from herbalism recolor an armor piece's cloth and leather slots (main, accent, under), NEVER its metal: the
  metal always shows the tier. Dyes are not part of the armor step.
- **W3 Tiers beyond color:** the finish and fittings (built), plus ONE shape step: steel wears the SPIKED pauldrons.
  The horned helm is kept for a later tier or a rare drop. Trim glow only from tier 4.
- **W4 Under an empty slot:** the player's own starting Peasant pieces, in their own colors. A plate chest over
  Peasant trousers works because every piece is on the same skeleton.
- **W5 The gaps:** leather's head is the dyed hood (no new model); cloth's head shows hair until a hat exists. The hat
  is one small rigid mesh: Luke's choice of source (by hand, CC0, a commission).
- **W6 Grade and quality on the look:** not now. Maybe later: Masterwork with less wear.
- **W7 The four tier studies:** kept as candidates, chosen when tiers 4-6 are named.
- **W8 Colors in the character picker:** WITH THE ARMOR WORK, for the starting clothes: a color per slot (main,
  accent, under, trim, leather) on the `appearance` text (`main=#rrggbb`: add-only, rule 17), a free picker with a row
  of suggested swatches (the four starters' colors and their kin) so most players land on something that fits the
  world.

## 8. Using the lab

`res://game/regents/wardrobe/wardrobe_lab.tscn`, F6 in the editor (no server). One figure on a turntable; the panel:
- **View**: One, Tiers (of Metal, Leather, Cloth or Starter: "Tiers of"), Outfits, Colorways (keys 1-4); Zones (Z: main red, accent blue, trim orange, leather
  brown, under green, metal gray); Turn (T); Day / Dusk / Night. Right-drag turns round, the wheel zooms.
- **Body**: male or female, skin, hair, beard, brows, hair color.
- **Whole outfit**: dress the figure in one outfit's set.
- **Pieces**: every slot, every piece our body has, with what it is made of under it.
- **Colors**: a palette (the colorways, or one saved), the metal (a finish, then its color, metallic, roughness and
  wear), each cloth slot (check "dye", pick a color), trim glow; Random colors; Clear dye; Save palette (writes
  `palettes/custom_<time>.tres` from the editor).
Shots: `"$GODOT" --path . res://game/regents/wardrobe/wardrobe_lab.tscn -- <dir>` (windowed).
Fixing a zone: edit `zones.json`, run `python game/regents/tools/wardrobe_assets.py zones --preview=<png>`, look at the
lab with Z.
