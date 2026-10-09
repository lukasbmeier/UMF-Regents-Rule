"""TAKE A GENRE OUT OF THIS GAME: delete every file its manifest names, and the lines it has in the
game's own files. What is left is the foundation plus the game's other genres, and it must build and
pass its suites as it is: that is the template's whole promise.

    python tools/template/strip_genre.py fishing [--dry-run]

What it touches:
  - every path in tools/template/genres/<genre>.paths (git rm; untracked files are deleted too)
  - shared/game.json: the genre leaves `genres`
  - server/build/genres.rs: every line tagged `// genre:<genre>`
  - shared/rules.json: each `@rate_limit <reducer>` the manifest names
  - project.godot: a main scene inside the removed paths becomes game/greybox_game.tscn
Then publish with --codegen (the bindings regenerate without the genre's tables) and run the suites.
"""
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MAIN = "res://game/greybox_game.tscn"


def run(*a: str) -> str:
    return subprocess.run(a, cwd=ROOT, check=True, capture_output=True, text=True).stdout


def manifest(genre: str) -> tuple[list[str], list[str]]:
    path = ROOT / "tools/template/genres" / f"{genre}.paths"
    if not path.exists():
        sys.exit(f"no manifest for '{genre}': {path.relative_to(ROOT)}")
    paths, limits = [], []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("@rate_limit "):
            limits.append(line.split(None, 1)[1].strip())
        else:
            paths.append(line)
    return paths, limits


def owned(paths: list[str], f: str) -> bool:
    return any(f.startswith(p) if p.endswith("/") else fnmatch.fnmatch(f, p) for p in paths)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    genre = args[0]
    paths, limits = manifest(genre)

    files = [f for f in run("git", "ls-files", "-co", "--exclude-standard").splitlines() if owned(paths, f)]
    print(f"{genre}: {len(files)} files")
    if dry:
        for f in files:
            print("  ", f)
    else:
        tracked = set(run("git", "ls-files").splitlines())
        gone = [f for f in files if f in tracked]
        for k in range(0, len(gone), 200):   # -f: a file with changes not yet committed goes too
            run("git", "rm", "-q", "-f", "--", *gone[k:k + 200])
        for f in files:
            if f not in tracked:
                (ROOT / f).unlink(missing_ok=True)
        # and the folders that leaves empty (deepest first)
        dirs = sorted({str(Path(f).parent) for f in files}, key=lambda d: -d.count("/"))
        for d in dirs:
            q = ROOT / d
            while q != ROOT and q.is_dir() and not any(q.iterdir()):
                q.rmdir()
                q = q.parent

    game_json = ROOT / "shared/game.json"
    g = json.loads(game_json.read_text(encoding="utf-8"))
    if genre in g.get("genres", []):
        g["genres"] = [x for x in g["genres"] if x != genre]
        print(f"shared/game.json: genres {g['genres']}")
        if not dry:
            game_json.write_bytes((json.dumps(g, indent=2) + "\n").encode())

    reg = ROOT / "server/build/genres.rs"
    lines = reg.read_text(encoding="utf-8").split("\n")
    kept = [l for l in lines if not l.rstrip().endswith(f"// genre:{genre}")]
    print(f"server/build/genres.rs: {len(lines) - len(kept)} lines")
    if not dry:
        reg.write_bytes("\n".join(kept).encode())

    rules = ROOT / "shared/rules.json"
    text = rules.read_text(encoding="utf-8")
    out = []
    for l in text.split("\n"):
        if any(l.strip().startswith(f'"{v}":') for v in limits):
            continue
        out.append(l)
    text2 = "\n".join(out)
    json.loads(text2)   # still valid
    print(f"shared/rules.json: rate limits {limits} removed")
    if not dry:
        rules.write_bytes(text2.encode())

    # Its baked content (DECISIONS #199). The manifest is rewritten by the next bake, which
    # tools/publish.sh runs first.
    if (ROOT / "shared/content" / genre).is_dir():
        print(f"shared/content/{genre}/: its baked content (the next publish re-bakes the manifest)")
        if not dry:
            run("git", "rm", "-r", "-q", "-f", "--ignore-unmatch", "--", f"shared/content/{genre}")
            import shutil
            shutil.rmtree(ROOT / "shared/content" / genre, ignore_errors=True)

    proj = ROOT / "project.godot"
    p = proj.read_text(encoding="utf-8")
    for l in p.split("\n"):
        if l.startswith("run/main_scene="):
            scene = l.split("=", 1)[1].strip('"').replace("res://", "")
            if owned(paths, scene):
                print(f"project.godot: main scene {scene} -> {DEFAULT_MAIN}")
                if not dry:
                    proj.write_bytes(p.replace(l, f'run/main_scene="{DEFAULT_MAIN}"').encode())
    print("now: tools/publish.sh --codegen, then the suites" if not dry else "(dry run: nothing changed)")


if __name__ == "__main__":
    main()
