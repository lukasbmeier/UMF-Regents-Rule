"""What a Mac export (the zip Godot writes) is, read from Windows.

    python tools/mac_bundle.py build/mac/umf.zip [extract_pck_to]
    python tools/mac_bundle.py --bundle-id shared/game.json

Prints `key: value` lines: the app's folder, its Info.plist bundle identifier, name and executable,
whether that executable is universal (both Intel and Apple Silicon: a fat Mach-O holding both), whether
the app is signed (a _CodeSignature), and the frameworks it carries (GDExtensions' libraries). With a
second argument, writes the app's .pck there, for tools/pck_list.py. Used by tests/export_test.sh.

`--bundle-id` prints the bundle identifier a game's app is exported with: `com.umf.` and its
title, lower case, apostrophes dropped, anything else but letters and digits a hyphen
(tools/mac_export.sh).
"""
import json
import plistlib
import re
import struct
import sys
import zipfile

CPU_X86_64 = 0x01000007
CPU_ARM64 = 0x0100000C


def bundle_id(title):
    # An apostrophe joins its word rather than splitting it: "Regent's Rule" is regents-rule.
    slug = re.sub(r"['’]", "", title.strip().lower())
    slug = re.sub(r"[^a-z0-9]+", "-", slug).strip("-")
    return "com.umf." + (slug or "game")


def fat_arches(data):
    # A universal binary starts 0xCAFEBABE (big-endian), then its count and one entry per arch.
    if len(data) < 8 or struct.unpack(">I", data[:4])[0] != 0xCAFEBABE:
        return []
    n = struct.unpack(">I", data[4:8])[0]
    return [struct.unpack(">I", data[8 + 20 * i:12 + 20 * i])[0] for i in range(n)]


def main():
    if sys.argv[1] == "--bundle-id":
        print(bundle_id(json.load(open(sys.argv[2], encoding="utf-8")).get("title", "game")))
        return
    z = zipfile.ZipFile(sys.argv[1])
    names = z.namelist()
    app = sorted({n.split("/")[0] for n in names if n.split("/")[0].endswith(".app")})
    if not app:
        sys.exit("no .app in the zip")
    app = app[0]
    plist = plistlib.loads(z.read(app + "/Contents/Info.plist"))
    exe = app + "/Contents/MacOS/" + plist.get("CFBundleExecutable", "")
    arches = fat_arches(z.read(exe)[:4096]) if exe in names else []
    frameworks = sorted({n.split("/")[3] for n in names if n.startswith(app + "/Contents/Frameworks/") and len(n.split("/")) > 4})
    pcks = [n for n in names if n.startswith(app + "/Contents/Resources/") and n.endswith(".pck")]
    print("app: " + app)
    print("bundle_id: " + plist.get("CFBundleIdentifier", ""))
    print("name: " + plist.get("CFBundleName", ""))
    print("executable: " + ("yes" if exe in names else "no"))
    print("universal: " + ("yes" if CPU_X86_64 in arches and CPU_ARM64 in arches else "no"))
    print("signed: " + ("yes" if app + "/Contents/_CodeSignature/CodeResources" in names else "no"))
    print("frameworks: " + " ".join(frameworks))
    print("pck: " + (pcks[0] if pcks else ""))
    if len(sys.argv) > 2 and pcks:
        open(sys.argv[2], "wb").write(z.read(pcks[0]))


if __name__ == "__main__":
    main()
