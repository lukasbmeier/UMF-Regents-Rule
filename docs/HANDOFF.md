# Handoff — UMF Template, 2026-10-21

## Where it stands
The session workflow (this session) is committed and shipped to every game; before it, `4883be6`
(Traits, DECISIONS #275). The CHANGELOG's last section is 0.51.2; chat (#273), the held jump (#274) and
traits (#275) were shipped after it without a numbered release.

## This session
- Adopted the per-sit-down session workflow: `CLAUDE.md` (imports `AGENTS.md`), `.claude/rules/umf-*.md`
  (the session protocol, unscoped; the module, the sidecar and GDScript, by path), this file.
- `.gitattributes`: a game keeps its own `CLAUDE.md` and `docs/HANDOFF.md` on a pull.
- `AGENTS.md`: the Godot MCP notes moved to `.claude/rules/umf-gdscript.md`.
- `docs/TEMPLATE_WORKFLOW.md`: who owns which instruction file.

## Next, in order
1. Regent's Rule's foundation asks (`GAME.md` there): M8, M16, M18-M26 and the template 1.0 `chunk`
   reshape (every game's database wiped once; decided 2026-10-18). Read `docs/FOUNDATION_SYSTEMS.md`
   for which is next.
2. Give the releases since 0.51.2 a CHANGELOG section when the next one ships.

## Waiting on Luke
- Nothing from this session.

## Watch out
- Each game wrote its own `CLAUDE.md` and `docs/HANDOFF.md` the same day. Shipping this keeps the
  game's copy, both on this first pull (both added) and on later template edits: checked in a scratch
  repo with the same `merge=ours` driver and `.git/info/attributes` step `ship_template.sh` uses.
