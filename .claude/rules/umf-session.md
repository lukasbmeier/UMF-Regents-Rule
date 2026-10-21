# Session protocol (the foundation's: the same in the template and every game)

One sit-down with Luke is one session. A new session is a reset, not a cost, because three files
carry the state: `docs/HANDOFF.md` (where the last one stopped), the progress file `CLAUDE.md`
names, and `docs/DECISIONS.md` (why things are the way they are).

## On start, before any work
1. `docs/HANDOFF.md`: read it first, all of it.
2. `GAME.md`: what this repo is, its database, Luke's decisions for it.
3. The progress file `CLAUDE.md` names: the section for the current step, not the whole file.
4. The last ~20 decisions: `tail -n 20 docs/DECISIONS.md` (one row per line). The index by system at
   its top says which older rows the system you are touching needs. Never read the whole log, and
   never `@`-import it (an import loads at launch, and the log is past #275).
5. `git status` and `git log --oneline -5`. Uncommitted changes HANDOFF does not mention may be
   another session's or Luke's: leave them alone and ask.

## On finish, before the closing summary
1. **Progress**: update the progress file's current step: what was built, how to play it, how it was
   tested, what was left for later.
2. **Decisions**:
   - A FOUNDATION decision is a new numbered row at the end of the TEMPLATE's `docs/DECISIONS.md`,
     plus its line in the index by system.
   - A GAME never appends to its own `docs/DECISIONS.md`: that file is the template's and arrives
     with every pull, so a game's row would collide with the template's numbering. Luke's calls go
     in `GAME.md` (its owner decisions); the rest in the progress file's step.
3. **HANDOFF**: OVERWRITE `docs/HANDOFF.md` (rewrite it, never append; under ~60 lines) in the shape
   below. Write it even when the session ends mid-step: that is when it matters most.
4. The handbook and changelog as `AGENTS.md` already requires (the handbook in the same change).

## docs/HANDOFF.md, the shape
```markdown
# Handoff — <repo>, <YYYY-MM-DD>

## Where it stands
<version or step; last commit; committed or not; published to the play database or not; suites
green or red, naming the red ones>

## This session
<what was done, 3-8 bullets, each naming its files or DECISIONS row>

## Next, in order
1. <the next concrete step, with the file or doc section it starts from>

## Waiting on Luke
<questions only Luke can answer; open design items are his: never defaulted>

## Watch out
<traps found this session: a flaky suite, a stale editor, a file another session is editing>
```

## Across repos
- Foundation work goes in `../UMF Template`, never in a game. A small foundation fix found in a game
  session may be made there in the same session; a milestone gets its own template session. Either
  way both repos' HANDOFFs say what moved where.
- A template release reaches the games through `ship_template.sh` (in `UMF ALL`), then each game
  republishes with `--codegen` and runs the suites it uses.
