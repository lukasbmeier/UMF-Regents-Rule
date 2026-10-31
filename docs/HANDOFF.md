# Handoff — UMF Template, 2026-10-31 (1.6.4-1.6.5: the referees' last stall, and two that drove nothing)

## Where it stands
**1.6.5**, committed and pushed (1.6.4 `023a8c6`, 1.6.5 `5e3e94b`), merged into all four games and pushed. Client and
sidecar only: restart a game and its referees; nothing to republish. Suites here: unit 2288/0, sidecar 13/0, regions
25/0 (once 24/1: see Watch out), the load test's own 33/0. Each game's unit suite green after the 1.6.4 merge
(Fishing 3066, Fowl Play 2570, DiscGolf 2360, Regent's 2748); Regent's referee/content/telemetry at 1.6.5 206/0.

## This session (Regent's Rule's referees, `../Regents Rule/docs/regents_rule/REFEREE_SCALING.md`, last section)
- 1.6.4 (#298): `ContentLibrary.items(type)` reads only the type's folders (`files_in(folder_for(...))`); it loaded
  every content file each call (1.7 s in Regent's). A skeleton's first swing asked for every kit: the ~0.9 s
  "net stall" of every referee of three or more. `RefereeLauncher.wants_referee` reads the body folders the same way.
- 1.6.4: `Telemetry` times a frame by the clock (`frame_ms`, `note_frame`): Godot caps `delta` near 133 ms, so a
  frozen main thread never read as a slow frame. Worst frames read higher from now on.
- 1.6.5 (#299): `RegionKeeper` asks `drive_npcs` for at most `MAX_BATCH` (256, the module's cap; a unit check reads
  regions.rs). A region with more drove NONE before: "two referees hold" on the expanse was two idle referees.
- 1.6.5: the load test fails its harness when an NPC has no driver (`npcs_driven`, from `npc_driver`); claim codes
  always 19 characters; regions_test's admin check allows a hand-off between the two live referees.
- Found with a stamped ring of where rows go (socket, SDK parse thread, drain, message, row, component), printed
  when rows stop: the method is in #298.

## Next, in order
1. Regent's Rule: why the strip with the town runs 2x the others' frames (three strips: 102 ms p95).
2. A region referee loads the whole level (~375 MB on the expanse); its part would do.
3. The 2-3 s start-up stalls as a referee's skeletons bind (before players; not counted).

## Waiting on Luke
- The per-player bandwidth budget; the server's levers at 300 (#289). Fowl Play: the eagle and its playtest.

## Watch out
- Regent's Rule has a combat session at work (uncommitted, ~48 files): its sweeps ran from a worktree on
  `regents-rule-sweep-test`. That game's HANDOFF is that session's: merge with care (a dirty HANDOFF stops a merge).
- A worktree in the scratchpad needs a short name: cargo's build-script paths pass Windows' 260 limit (LNK1104).
- regions_test's bot wanders the edge; a check that reads a driver twice must allow a hand-off between them.
- Never put a `.gd` copy inside a project (even `build/`): two of a class and every spawn fails.
- Heredocs through the Bash tool mangle backslashes (`\r`, `\t`, a Windows path): write patch scripts with the
  file tool, or edit with Edit.
