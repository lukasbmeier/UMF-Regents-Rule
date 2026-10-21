@AGENTS.md

# CLAUDE.md — the UMF template (this repo's own; a game keeps its own copy on a pull)

This repo is the FOUNDATION: no genre, playable as the greybox game. Every game is a fork that
takes it with `git pull template main`. Foundation work for any game is done here, with its tests.

## Session protocol
`.claude/rules/umf-session.md` (loaded every session): on start read `docs/HANDOFF.md`, `GAME.md`,
the progress file below and `tail -n 20 docs/DECISIONS.md`; on finish update progress, add decisions,
rewrite `docs/HANDOFF.md`.

## The files
| File | What it is | When |
|---|---|---|
| `docs/HANDOFF.md` | where the last session stopped; overwritten every session | first, every session |
| `GAME.md` | what this repo is, its database (`umf-template`, suites `umf-template-test`) | every session |
| `docs/FOUNDATION_SYSTEMS.md` | THE PROGRESS FILE: the milestones, built and next, and which game asked for each | every session: the current milestone |
| `docs/DECISIONS.md` | the decision log; numbered rows, index by system at the top | the last ~20, plus your system's rows; never whole |
| `docs/HANDBOOK.md` | the human guide; updated in the same change as what it describes | when a change alters how something works |
| `docs/CHANGELOG.md` | one section per release | when shipping |
| `docs/TEMPLATE_WORKFLOW.md` | how games take the template; who owns which file | when touching the boundary |
| `docs/rules/*.md` | the long rules per system (AGENTS.md's index) | before touching that system |
| `.claude/rules/umf-*.md` | Claude's rules per layer; load themselves by path | automatic |

## Owning the instruction files (`docs/TEMPLATE_WORKFLOW.md`, Claude Code)
- THE TEMPLATE OWNS `AGENTS.md` and `.claude/rules/umf-*.md`: they reach every game on a pull. Keep
  them free of any game's name (rule 16).
- EACH REPO OWNS `CLAUDE.md`, `docs/HANDOFF.md` and `.claude/rules/<game>-*.md` (a game's rules files
  are in its genre manifest). `.gitattributes` keeps the game's `CLAUDE.md` and `HANDOFF.md` on a pull.
- `.claude/settings.local.json` (not committed) points auto memory at the one shared directory for
  all of `UMF ALL`, so what Luke corrects in one repo holds in all of them.

## Working with Luke
- Luke is on Windows, plays from the editor (two instances), and did not write this code: give him
  `tools\publish.cmd` / `tools\run.cmd tests\<suite>.sh`, and explain changes in plain terms.
- Run the suites a change touches plus its negative, not every layer; a template ship that changed
  server code runs the integration suite once. Never loosen a test to pass.
- Close-the-editor first when codegen or a `@tool` script rewrite is coming: ask once, up front.
- Open design items are Luke's: ask, never default them.
- Once green, ship with `bash "../ship_template.sh" "<version>: <what>"` (never `--fresh`), then
  republish each game that uses the change with `--codegen` and run its suites. Every game must be
  committed first: the script refuses a dirty game.
