"""THE EDITOR'S IDENTITIES ON THIS MACHINE (DECISIONS #272): the identity each editor instance plays as
(`user://spacetime_token_dev<N>.txt`, Boot's dev identity slots), one `0x<hex>` per line. tools/publish.sh
makes each an admin of the database it publishes, so pressing Play starts the world's referee
(RefereeLauncher only does for the admin: Luke's editor was not one, and a referee left over from
hosting ran yesterday's code instead).

Reads only the token's public `hex_identity` claim; never prints a token.

    python tools/editor_admins.py            (from the project folder)
"""
import base64
import glob
import json
import os
import re
import sys


def project_name() -> str:
    text = open("project.godot", encoding="utf-8").read()
    m = re.search(r'^config/name="(.*)"', text, re.M)
    return m.group(1) if m else ""


def user_dir(name: str) -> str:
    if sys.platform.startswith("win"):
        return os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", name)
    if sys.platform == "darwin":
        return os.path.expanduser(os.path.join("~/Library/Application Support/Godot/app_userdata", name))
    return os.path.expanduser(os.path.join("~/.local/share/godot/app_userdata", name))


def identity_of(token: str) -> str:
    payload = token.strip().split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload)).get("hex_identity", "")


def main() -> int:
    name = project_name()
    if not name:
        return 0
    for path in sorted(glob.glob(os.path.join(user_dir(name), "spacetime_token_dev*.txt"))):
        try:
            ident = identity_of(open(path, encoding="utf-8").read())
        except (OSError, ValueError, IndexError):
            continue
        if re.fullmatch(r"[0-9a-f]{64}", ident or ""):
            print("0x" + ident)
    return 0


if __name__ == "__main__":
    sys.exit(main())
