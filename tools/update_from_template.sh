#!/usr/bin/env bash
# TAKE THE FOUNDATION'S LATEST (docs/TEMPLATE_WORKFLOW.md, DECISIONS #196). In a game made from the
# template: pulls `template main`, regenerates this game's bindings against its own database
# (tools/publish.sh --codegen: keeps the data) and runs the unit suite. Commit, push.
#
#   tools\update_from_template.cmd      (Windows: double-click it)
#   GODOT=<path> ./tools/update_from_template.sh
#
# A conflict outside the game's own files means foundation work was done in the game: move it to
# the template. Close the editor first (codegen rewrites scripts it has open).
set -euo pipefail
cd "$(dirname "$0")/.."
if ! git remote get-url template >/dev/null 2>&1; then
  echo "This repo has no 'template' remote: it is the template, or was not made from it." >&2
  echo "  git remote add template https://github.com/lukasbmeier/UMF-Foundation.git" >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Commit or stash your changes first: a pull into a dirty tree mixes them in." >&2
  exit 1
fi
git config merge.ours.driver true   # .gitattributes: the game's own bindings, GAME.md, game.json
echo "== pull the template =="
before="$(git rev-parse HEAD)"
git fetch -q template
# The template's .gitattributes rules apply to THIS merge too: git reads the attributes already
# checked out, so a rule arriving in the pull (GAME.md merge=ours) would otherwise miss it.
git show template/main:.gitattributes > .git/info/attributes
git merge --no-edit template/main
if [ "$(git rev-parse HEAD)" = "$before" ]; then
  echo "Already up to date."
  exit 0
fi
git log --oneline "$before..HEAD" | sed 's/^/   /'
echo "== this game's server and bindings =="
GODOT="${GODOT:-godot}" ./tools/publish.sh --codegen
echo "== the unit suite =="
GODOT="${GODOT:-godot}" ./tests/run_tests.sh
echo
echo "Done. Commit the regenerated bindings if they changed, then push."
