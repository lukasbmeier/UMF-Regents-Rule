# B2b: THE FAINT CIRCLE IN THE BOLT'S SHOTS WAS A LEFTOVER HIT FLASH (LAB ONLY)
Built:
- Found: the faint circle about 1 m in front of the hand on the Bolt's first frame was not the new hand flash.
  It was still there with the flash switched off. It was a Bolt HIT flash (`bolt_hit.tscn`: a pale ring with
  streaks) left over from the lab's warm-up pass:
  - The warm-up plays every showcase for 12 frames.
  - Moving from Bolt to Meteor freed the flying Bolt, and `ShotLook._ended` played its hit flash where the bolt was.
  - It plays under the scene root, which the lab's reset never clears, so it was still showing (0.5 s) when the real
    Bolt shot began.
  It is ours from B2 (the Bolt showcase is new there). The before shot did not show it, by timing. It is only in the
  lab: in the game a missile's body that goes did end there.
- `game/regents/combat/shot_look.gd`: `cancel_end()`. A look that is being cleared away, not ending, plays no end
  effect.
- `game/regents/vfx/vfx_lab.gd`: `_reset` calls `cancel_end()` on every `ShotLook` on the stage before freeing it.
- `game/regents/tests/suites/regents_vfx.gd`: in the lab check, a Bolt in flight (over 0.1 s old) cut off by the next
  showcase leaves no new hit flash in the world. B2's no-owner shot check now cancels its end too, so it leaves no
  flash for later checks.
How to play it: `vfx_lab.tscn`, Bolt: the first frames show only the flash in the hand and the missile.
Tested:
- `regents_vfx`: 248 passed, 0 failed (after `git merge main`: already up to date).
- Negative: with the lab's `cancel_end()` call taken out, "a Bolt cut off by the next showcase leaves no hit flash in
  the world (1)" fails.
- Shots looked at: the Bolt with the hand flash switched off (the circle still there, which ruled the flash out), and
  the Bolt after the fix (no circle; the hit flash on the foe at the end is unchanged).
Needs on merge: none.
Placeholders made: none.
For Luke: none.
For the rules/handbook: none.
Left for later: none.
