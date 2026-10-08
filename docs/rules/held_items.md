# Held items and editor previews
Items in the hand (grips per animation and body, the hold, the wrist, put away, the off hand) and the @tool previews they are fitted in. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## HELD ITEMS (DECISIONS #153, #156)
- An item in a hand is a `HeldItem` (root at its grip point) with an `ItemGrip`: `GripEntry`s per
  ANIMATION and BODY, and nothing else: there are no modes. An animation uses its own grip, else
  the one its clip falls back to, else the idle's. Whatever plays an animation, the item follows
  it. Never place a held item by hand in code, and never tell one how to be held: give the
  animation a grip. A genre that needs one animation held two ways plays two animations.
- The game BLENDS the grips by `AnimationDriverComponent.semantic_weights()`. The locomotion
  points are read back by `AnimationTreeBuilder.LINE_POINTS/PLANE_POINTS`, the order
  `_build_ground` adds them: change one, change the other (the animation-scene suite checks).
- STEADY is per grip: its turn is in the BODY's frame, its position in the hand's. `set_steady`
  restates a grip without moving the item.
- `held_item_preview.gd` is a tool script and holds only engine types (#152). It may call
  `ItemGrip`, `GripEntry` and `BodyClearance` (tool scripts) and read the definition's data; it
  may not call a method of `AnimationSet`, `EntityDefinition`, `HeldItem` or the item's script.
- An item marks the points to keep off the body with a `clearance_radius` meta (metres); one
  that also has `clearance_to` (a NodePath) is a LINE to that node (the rod's `Shaft` to `Tip`).
  The preview measured only the reel once and called a run green while the blank went through
  the head (#156).
- The preview sets EXACTLY the chosen (animation, body): a drag or Steady makes it where the item
  already sits (`ItemGrip.ensure`), Clear This Grip removes it. The idle's shared grip is never
  removed: everything ends up borrowing it.
- THE HOLD (#158): grips place an item's `Hold` node, not its root (`GripFit.hold_of`); compare
  a drawn item through `HeldItem.hold_offset()`, and the hand through `HeldItem.hand_now()`: the
  wrist modifier's turn shows only during the skeleton's update and is undone after it, so a
  skeleton read after the frame is the clip's hand, not the drawn one.
- THE WRIST (#158): steady grips turn the hand (`HoldWrist`, `GripFit.wrist_turn`, up to
  `wrist_turn_deg`). The preview turns it the same way (`_turn_wrist`); a fit samples the clip's
  own hand and turns it per try. `GripFit.hole(..., false)` (no circle) is the per-frame call.
- PUT AWAY (#158, #159): IN HAND IS GAME STATE, `EquipComponent`, on its own clock (never an
  animation's). A genre calls `needed()` while using the item and checks `is_equipped()` before a
  verb that needs it in hand, WAITING (the cast) rather than playing it early. The item follows it
  (`HeldItem.follow`): draw/put-away on the UPPER-BODY one-shot, the swap when the state flips.
  Only ANOTHER player's verb, already playing when it arrives, may put the item in hand at once
  (`set_equipped_now(true)`), never with a draw under it: the draw would cover the arms of
  whatever pose follows. Our own state comes from our rig, theirs from their rows.
- THE EQUIP ROW (#160): the OWNER's EquipComponent reports every change (`set_equip_state`) and
  every other client's copy follows the `equip_state` row (`needed()`/`in_use()` are ignored
  there). `deciding()` is true for ours and for an entity nobody reports for (an NPC): only those
  run the idle and speed clocks. Our own verb's animation still playing keeps the item out with
  `in_use()` (never `needed()`: it must not draw).
- FIT, THEN LOOK (#157). `GripFit.hole` finds the fist's hole from the finger bones; `fit` puts the
  grip point there and points the item along the fist when the animation USES it, steady toward
  `ItemGrip.carry_point` when it only CARRIES it (`GripFit.CARRY_FOR`), then searches turns until
  it clears by 2 cm. A miss is reported with the hand's OWN air: when the animation puts the hand
  in the body, no grip clears it, so do not loosen the check. Look at the pictures (Save Pictures,
  or `godot --path . -s res://tools/held/fit_grip.gd -- --preview=<scene> [--fit] [--save]`, which
  needs a window) before calling a fit good. An item's convention: root at the grip point, +Y out
  past the thumb, +Z toward the wrist.
- PACKED SHORT (#161): `ItemGrip.stow_length` squeezes an item along its own +Y about its Hold
  while it is away (`ItemGrip.packing`, eased by `HeldItem.packed()`). Compare a slung item's
  hold through `.orthonormalized()` (`_near` does): its basis carries the squeeze.
- THE SHUT HAND (#160): while an item is in the hand, `HoldWrist` first closes the fingers toward
  `ItemGrip.fist_animation`'s first frame as far as the clip opened them (`GripFit.close_fist`),
  then turns the wrist. The preview does the same before every measurement (`_close_hand`), so a
  fit measures the hand the game draws. Finger poses are put back after the skeleton's update:
  read them in `skeleton_updated`, or `HeldItem.fist_closed()`.
- A grip can be kept for one BODY (`GripEntry.body`, #155): at each lookup step the holder's body
  wins over the shared grip, never across steps. The body comes from the look
  (`ModularCharacter.body`, set by make_looks.py) as the skeleton's `body` meta; the foundation
  reads the meta and never names a look class.

## EDITOR PREVIEWS (DECISIONS #147, #152)
- In the EDITOR only `@tool` scripts run; every other script is a placeholder with its exported
  data and none of its methods. A tool preview may READ a non-tool resource's exports
  (`AnimationSet.clips`, `EntityDefinition.visual_variants`) but never call its methods: the
  call fails, and the preview stands empty. `ModularCharacter` is a tool script so looks
  assemble in the editor. A runtime test cannot see any of this; check the source (the grip
  suite does), or look in the running editor.
- A `@tool` resource saves only non-default values: keep its defaults neutral so the file
  records every value that matters (`GripEntry`).
- The editor reloads a tool script under an OPEN scene when its file changes, and keeps the
  instance's variables. Keep them to engine types (nodes, numbers, arrays of those); objects of
  a class declared in the script are the known hazard across a reload, and the editor crashed
  while one was being rewritten (#152). Rewriting a tool script while its scene is open in the
  owner's editor can take that editor down: check the script in an editor of your own first.
- A preview shows what the GAME will: the bodies the game dresses people in, and the whole clip
  the game plays, not one frame of it. The grip preview showed a man in one frame, clear of the
  leg, while the game drew the same grip 5 cm inside a woman's (#152).
