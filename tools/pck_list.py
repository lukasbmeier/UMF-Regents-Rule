"""List the files inside a Godot 4 .pck (format v2 and v3).

    python tools/pck_list.py build/client/umf.pck

Used by tests/export_test.sh to check what an export actually contains - which is the only
way to know that `sidecar/` stayed out of the client (hard rule 7b), and that the few
non-resource files the game reads at runtime went in.
"""
import struct
import sys

MAGIC = 0x43504447  # "GDPC"
PACK_DIR_ENCRYPTED = 1
PACK_REL_FILEBASE = 2


def list_pck(path):
    with open(path, "rb") as f:
        data = f.read()
    start = 0
    if struct.unpack_from("<I", data, 0)[0] != MAGIC:
        # Embedded in an executable: a footer of (pack size: u64, magic: u32) at the very end.
        size, magic = struct.unpack_from("<QI", data, len(data) - 12)
        if magic != MAGIC:
            raise SystemExit("%s: not a Godot pack" % path)
        start = len(data) - 12 - size
    off = start
    magic, version, vmaj, vmin, vpat, flags = struct.unpack_from("<IIIIII", data, off)
    off += 24
    if flags & PACK_DIR_ENCRYPTED:
        raise SystemExit("%s: directory is encrypted" % path)
    file_base = struct.unpack_from("<Q", data, off)[0]
    off += 8
    if version >= 3:
        dir_offset = struct.unpack_from("<Q", data, off)[0]
        off += 8
        off = start + dir_offset
    else:
        off += 16 * 4  # reserved
    count = struct.unpack_from("<I", data, off)[0]
    off += 4
    names = []
    for _ in range(count):
        length = struct.unpack_from("<I", data, off)[0]
        off += 4
        raw = data[off:off + length]
        off += length
        name = raw.rstrip(b"\0").decode("utf-8")
        off += 8 + 8 + 16  # offset, size, md5
        if version >= 2:
            off += 4  # flags
        if name.startswith("res://"):
            name = name[len("res://"):]
        names.append(name)
    return (vmaj, vmin, vpat, version), names


if __name__ == "__main__":
    (vmaj, vmin, vpat, version), names = list_pck(sys.argv[1])
    # Bytes, not print(): on Windows text-mode stdout turns every newline into CRLF, and a shell
    # that anchors on `$` then matches nothing — which reads as "the file is missing".
    sys.stdout.buffer.write("".join(n + "\n" for n in sorted(names)).encode("utf-8"))
    sys.stdout.buffer.flush()
    print("# godot %d.%d.%d, pack format %d, %d files" % (vmaj, vmin, vpat, version, len(names)),
          file=sys.stderr)
