"""THE LOAD TEST'S WIRE (DECISIONS #284): what a bot needs to talk to SpacetimeDB without Godot.

Python's standard library only (like the chronicle, #276), so the harness runs wherever the project's
tools do. Three things:
  - a WebSocket client on asyncio streams (RFC 6455: the handshake, masked frames out, fragments, ping);
  - BSATN, SpacetimeDB's binary format, driven by the MODULE'S OWN SCHEMA (`/v1/database/<db>/schema`),
    so a reducer is called by name with Python values and nothing here knows a game's types;
  - the v3 messages (`v3.bsatn.spacetimedb`, the protocol the vendored SDK speaks): what a client sends,
    and what a server sends, read far enough to count rows and bytes and to find a bot's own rows.
The message layouts are the vendored SDK's (`addons/SpacetimeDB/core/bsatn_deserializer.gd`,
`core_types/client_message/*.gd`), the tiebreaker for this file.
"""
import asyncio
import base64
import gzip
import json
import os
import struct
import urllib.request

PROTOCOL = "v3.bsatn.spacetimedb"

# Client messages (the SDK's spacetimedb_client_message.gd).
SUBSCRIBE, UNSUBSCRIBE, ONEOFF_QUERY, CALL_REDUCER = 0, 1, 2, 3
# Server messages (spacetimedb_server_message.gd).
INITIAL_CONNECTION, SUBSCRIBE_APPLIED, UNSUBSCRIBE_APPLIED, SUBSCRIPTION_ERROR = 0, 1, 2, 3
TRANSACTION_UPDATE, ONE_OFF_QUERY_RESPONSE, REDUCER_RESULT, PROCEDURE_RESULT = 4, 5, 6, 7
# A server frame's first byte: how the rest is compressed.
COMPRESS_NONE, COMPRESS_BROTLI, COMPRESS_GZIP = 0, 1, 2


# =============================================================================
# BSATN: little-endian, length-prefixed (u32) strings, arrays and bytes
# =============================================================================

class Reader:
    __slots__ = ("buf", "pos")

    def __init__(self, buf, pos=0):
        self.buf = buf
        self.pos = pos

    def take(self, n):
        if self.pos + n > len(self.buf):
            raise ValueError("BSATN: wanted %d bytes at %d, have %d" % (n, self.pos, len(self.buf)))
        b = self.buf[self.pos:self.pos + n]
        self.pos += n
        return b

    def u8(self):
        return self.take(1)[0]

    def u16(self):
        return struct.unpack_from("<H", self.take(2))[0]

    def u32(self):
        return struct.unpack_from("<I", self.take(4))[0]

    def u64(self):
        return struct.unpack_from("<Q", self.take(8))[0]

    def i64(self):
        return struct.unpack_from("<q", self.take(8))[0]

    def string(self):
        return bytes(self.take(self.u32())).decode("utf-8", "replace")

    def blob(self):
        return self.take(self.u32())


def w_u32(v):
    return struct.pack("<I", v)


def w_string(s):
    b = s.encode("utf-8")
    return w_u32(len(b)) + b


def w_blob(b):
    return w_u32(len(b)) + bytes(b)


# =============================================================================
# THE MODULE'S SCHEMA: types by name, reducers' parameters, tables' row types
# =============================================================================

_PRIMS = {
    "Bool": "<?", "U8": "<B", "I8": "<b", "U16": "<H", "I16": "<h", "U32": "<I", "I32": "<i",
    "U64": "<Q", "I64": "<q", "F32": "<f", "F64": "<d",
}
_WIDE = {"U128": 16, "I128": 16, "U256": 32, "I256": 32}


class Schema:
    """The module's schema (`GET /v1/database/<db>/schema?version=9`), compiled into encoders and decoders."""

    def __init__(self, doc):
        self.types = doc["typespace"]["types"]
        self.reducers = {r["name"]: r["params"] for r in doc["reducers"]}
        self.tables = {t["name"]: t["product_type_ref"] for t in doc["tables"]}
        self._enc = {}
        self._dec = {}

    @staticmethod
    def fetch(host, db):
        with urllib.request.urlopen("%s/v1/database/%s/schema?version=9" % (host, db), timeout=10) as r:
            return Schema(json.load(r))

    def resolve(self, t):
        while "Ref" in t:
            t = self.types[t["Ref"]]
        return t

    # --- encoding Python values: a product is a dict by field name (or a list in order), an Option is
    # None or the value, any other sum is {"variant": value}, an array a list, Identity-like products a
    # bytes/hex value of their one field.
    def encoder(self, t):
        key = json.dumps(t, sort_keys=True)
        enc = self._enc.get(key)
        if enc is None:
            enc = self._compile_enc(self.resolve(t))
            self._enc[key] = enc
        return enc

    def _compile_enc(self, t):
        (kind, body), = t.items()
        if kind in _PRIMS:
            s = struct.Struct(_PRIMS[kind])
            return lambda v: s.pack(v)
        if kind in _WIDE:
            n = _WIDE[kind]
            return lambda v: (bytes.fromhex(v[2:] if v.startswith("0x") else v)[::-1] if isinstance(v, str)
                              else int(v).to_bytes(n, "little", signed=kind[0] == "I"))
        if kind == "String":
            return w_string
        if kind == "Array":
            if self.resolve(body) == {"U8": []}:
                return lambda v: w_blob(v)
            inner = self.encoder(body)
            return lambda v: w_u32(len(v)) + b"".join(inner(x) for x in v)
        if kind == "Product":
            names = [(e["name"] or {}).get("some", str(i)) for i, e in enumerate(body["elements"])]
            encs = [self.encoder(e["algebraic_type"]) for e in body["elements"]]
            if len(names) == 1 and names[0].startswith("__"):   # Identity, ConnectionId, Timestamp...
                one = encs[0]
                return lambda v: one(v[names[0]] if isinstance(v, dict) else v)
            pairs = list(zip(names, encs))

            def enc_product(v):
                if isinstance(v, dict):
                    return b"".join(e(v[n]) for n, e in pairs)
                return b"".join(e(x) for (_, e), x in zip(pairs, v))
            return enc_product
        if kind == "Sum":
            variants = [((x["name"] or {}).get("some", str(i)), x["algebraic_type"]) for i, x in enumerate(body["variants"])]
            names = [n for n, _ in variants]
            if names == ["some", "none"]:
                some = self.encoder(variants[0][1])
                return lambda v: b"\x01" if v is None else b"\x00" + some(v)
            encs = {n: (i, self.encoder(at)) for i, (n, at) in enumerate(variants)}

            def enc_sum(v):
                (name, val), = v.items()
                i, e = encs[name]
                return bytes([i]) + e(val)
            return enc_sum
        raise ValueError("BSATN: cannot encode a %s" % kind)

    def reducer_args(self, name, args):
        """A reducer's arguments, in order, as the bytes `CallReducer` carries."""
        params = self.reducers.get(name)
        if params is None:
            raise KeyError("the module has no reducer '%s'" % name)
        els = params["elements"]
        if len(args) != len(els):
            raise ValueError("%s takes %d arguments, given %d" % (name, len(els), len(args)))
        return b"".join(self.encoder(e["algebraic_type"])(a) for e, a in zip(els, args))

    # --- decoding a row into a dict (only where a bot needs to read one: its own)
    def decoder(self, t):
        key = json.dumps(t, sort_keys=True)
        dec = self._dec.get(key)
        if dec is None:
            dec = self._compile_dec(self.resolve(t))
            self._dec[key] = dec
        return dec

    def _compile_dec(self, t):
        (kind, body), = t.items()
        if kind in _PRIMS:
            s = struct.Struct(_PRIMS[kind])
            return lambda r: s.unpack_from(r.take(s.size))[0]
        if kind in _WIDE:
            n = _WIDE[kind]
            return lambda r: int.from_bytes(r.take(n), "little", signed=kind[0] == "I")
        if kind == "String":
            return lambda r: r.string()
        if kind == "Array":
            inner = self.decoder(body)
            return lambda r: [inner(r) for _ in range(r.u32())]
        if kind == "Product":
            names = [(e["name"] or {}).get("some", str(i)) for i, e in enumerate(body["elements"])]
            decs = [self.decoder(e["algebraic_type"]) for e in body["elements"]]
            pairs = list(zip(names, decs))
            if len(names) == 1 and names[0].startswith("__"):
                one = decs[0]
                return lambda r: one(r)
            return lambda r: {n: d(r) for n, d in pairs}
        if kind == "Sum":
            variants = [((x["name"] or {}).get("some", str(i)), self.decoder(x["algebraic_type"]))
                        for i, x in enumerate(body["variants"])]
            if [n for n, _ in variants] == ["some", "none"]:
                some = variants[0][1]
                return lambda r: some(r) if r.u8() == 0 else None
            return lambda r: (lambda i: {variants[i][0]: variants[i][1](r)})(r.u8())
        raise ValueError("BSATN: cannot decode a %s" % kind)

    def row_decoder(self, table):
        return self.decoder({"Ref": self.tables[table]})

    def column_offset(self, table, column):
        """Where `column` starts in every row of `table`, when every column before it has a fixed size
        (else None). Lets a bot find its own row among thousands by reading 8 bytes, not decoding all."""
        t = self.resolve({"Ref": self.tables[table]})
        off = 0
        for e in t["Product"]["elements"]:
            if (e["name"] or {}).get("some") == column:
                return off
            size = self._fixed_size(self.resolve(e["algebraic_type"]))
            if size is None:
                return None
            off += size
        return None

    def _fixed_size(self, t):
        (kind, body), = t.items()
        if kind in _PRIMS:
            return struct.calcsize(_PRIMS[kind])
        if kind in _WIDE:
            return _WIDE[kind]
        if kind == "Product":
            total = 0
            for e in body["elements"]:
                s = self._fixed_size(self.resolve(e["algebraic_type"]))
                if s is None:
                    return None
                total += s
            return total
        return None


# =============================================================================
# CLIENT MESSAGES
# =============================================================================

def msg_subscribe(request_id, query_set_id, queries):
    return bytes([SUBSCRIBE]) + w_u32(request_id) + w_u32(query_set_id) + w_u32(len(queries)) + \
        b"".join(w_string(q) for q in queries)


def msg_unsubscribe(request_id, query_set_id, send_dropped=False):
    return bytes([UNSUBSCRIBE]) + w_u32(request_id) + w_u32(query_set_id) + bytes([1 if send_dropped else 0])


def msg_call_reducer(request_id, name, args):
    return bytes([CALL_REDUCER]) + w_u32(request_id) + b"\x00" + w_string(name) + w_blob(args)


# =============================================================================
# SERVER MESSAGES: parsed into small tuples; rows stay bytes
# =============================================================================

def read_row_list(r):
    """A BsatnRowList: its rows as memoryview slices (cheap; nothing is decoded)."""
    hint = r.u8()
    if hint == 0:      # FixedSize(u16)
        size = r.u16()
        data = r.blob()
        if size == 0:
            return []
        return [data[i:i + size] for i in range(0, len(data), size)]
    if hint == 1:      # RowOffsets(Vec<u64>)
        n = r.u32()
        offs = struct.unpack_from("<%dQ" % n, r.take(8 * n)) if n else ()
        data = r.blob()
        ends = list(offs[1:]) + [len(data)]
        return [data[s:e] for s, e in zip(offs, ends)]
    raise ValueError("BSATN: unknown row size hint %d" % hint)


def _query_rows(r):
    """QueryRows: [(table, rows)]."""
    return [(r.string(), read_row_list(r)) for _ in range(r.u32())]


def _transaction_update(r):
    """TransactionUpdate: [(query_set_id, table, inserts, deletes)]."""
    out = []
    for _ in range(r.u32()):
        qs = r.u32()
        for _ in range(r.u32()):
            table = r.string()
            ins, dels = [], []
            for _ in range(r.u32()):
                tag = r.u8()
                if tag == 0:
                    ins.extend(read_row_list(r))
                    dels.extend(read_row_list(r))
                elif tag == 1:
                    ins.extend(read_row_list(r))
                else:
                    raise ValueError("BSATN: unknown TableUpdateRows tag %d" % tag)
            out.append((qs, table, ins, dels))
    return out


def parse_server_messages(payload):
    """Every message in one (decompressed) frame: v3 packs one or more whole messages in a frame.
    Each is (kind, ...) with kind one of the server message tags."""
    buf = memoryview(payload)
    r = Reader(buf)
    out = []
    while r.pos < len(buf):
        tag = r.u8()
        if tag == INITIAL_CONNECTION:
            identity = bytes(r.take(32))
            conn = bytes(r.take(16))
            out.append((tag, identity, conn, r.string()))
        elif tag == SUBSCRIBE_APPLIED:
            req, qs = r.u32(), r.u32()
            out.append((tag, req, qs, _query_rows(r)))
        elif tag == UNSUBSCRIBE_APPLIED:
            req, qs = r.u32(), r.u32()
            some = r.u8()
            out.append((tag, req, qs, _query_rows(r) if some == 0 else []))
        elif tag == SUBSCRIPTION_ERROR:
            req = r.u32() if r.u8() == 0 else None
            qs = r.u32()
            out.append((tag, req, qs, r.string()))
        elif tag == TRANSACTION_UPDATE:
            out.append((tag, _transaction_update(r)))
        elif tag == REDUCER_RESULT:
            req = r.u32()
            r.i64()   # timestamp
            outcome = r.u8()
            if outcome == 0:
                r.blob()   # the return value
                out.append((tag, req, "ok", _transaction_update(r)))
            elif outcome == 1:
                out.append((tag, req, "ok", []))
            elif outcome == 2:
                out.append((tag, req, "err", bytes(r.blob())))
            elif outcome == 3:
                out.append((tag, req, "internal", r.string()))
            else:
                raise ValueError("BSATN: unknown reducer outcome %d" % outcome)
        elif tag == ONE_OFF_QUERY_RESPONSE:
            req = r.u32()
            if r.u8() == 0:
                out.append((tag, req, _query_rows(r)))
            else:
                out.append((tag, req, r.string()))
        else:
            raise ValueError("server message type %d is not one a bot reads" % tag)
    return out


def reducer_error_text(blob):
    """An Err(String) from a reducer arrives as the BSATN of the string."""
    try:
        return Reader(memoryview(blob)).string()
    except ValueError:
        return bytes(blob).decode("utf-8", "replace")


def decompress(frame):
    """A server frame's payload with its compression byte read: (wire bytes, the payload)."""
    tag = frame[0]
    body = frame[1:]
    if tag == COMPRESS_NONE:
        return body
    if tag == COMPRESS_GZIP:
        return gzip.decompress(body)
    raise ValueError("a %s frame: ask the server for Gzip or None (Brotli is not in Python's standard library)"
                     % ("Brotli" if tag == COMPRESS_BROTLI else "tag %d" % tag))


# =============================================================================
# THE WEBSOCKET (RFC 6455), client side
# =============================================================================

class Closed(Exception):
    pass


def ws_frame(opcode, payload):
    """One masked client frame (a client MUST mask)."""
    n = len(payload)
    head = bytes([0x80 | opcode])
    if n < 126:
        head += bytes([0x80 | n])
    elif n < 65536:
        head += bytes([0x80 | 126]) + struct.pack(">H", n)
    else:
        head += bytes([0x80 | 127]) + struct.pack(">Q", n)
    mask = os.urandom(4)
    if n:
        reps = (mask * (n // 4 + 1))[:n]
        masked = (int.from_bytes(payload, "little") ^ int.from_bytes(reps, "little")).to_bytes(n, "little")
    else:
        masked = b""
    return head + mask + masked


def ws_unmask(mask, payload):
    n = len(payload)
    if not n:
        return b""
    reps = (mask * (n // 4 + 1))[:n]
    return (int.from_bytes(payload, "little") ^ int.from_bytes(reps, "little")).to_bytes(n, "little")


class WebSocket:
    def __init__(self, reader, writer):
        self.reader = reader
        self.writer = writer
        self.protocol = ""

    @staticmethod
    async def connect(host, port, path, headers):
        reader, writer = await asyncio.open_connection(host, port, limit=64 * 1024 * 1024)
        key = base64.b64encode(os.urandom(16)).decode()
        lines = ["GET %s HTTP/1.1" % path, "Host: %s:%d" % (host, port), "Upgrade: websocket",
                 "Connection: Upgrade", "Sec-WebSocket-Key: " + key, "Sec-WebSocket-Version: 13",
                 "Sec-WebSocket-Protocol: " + PROTOCOL] + ["%s: %s" % kv for kv in headers.items()]
        writer.write(("\r\n".join(lines) + "\r\n\r\n").encode())
        await writer.drain()
        head = await reader.readuntil(b"\r\n\r\n")
        status = head.split(b"\r\n", 1)[0].decode(errors="replace")
        if " 101 " not in status + " ":
            body = b""
            try:
                body = await asyncio.wait_for(reader.read(2000), 2)
            except (asyncio.TimeoutError, OSError):
                pass
            writer.close()
            raise Closed("handshake refused: %s %s" % (status, body[:300].decode(errors="replace")))
        ws = WebSocket(reader, writer)
        for line in head.decode(errors="replace").split("\r\n")[1:]:
            if line.lower().startswith("sec-websocket-protocol:"):
                ws.protocol = line.split(":", 1)[1].strip()
        return ws

    def send(self, payload):
        """Queue one binary message (the caller drains when it wants backpressure)."""
        self.writer.write(ws_frame(2, payload))

    async def recv(self):
        """The next whole binary message, answering pings on the way. Raises Closed."""
        parts = []
        while True:
            h = await self.reader.readexactly(2)
            fin, opcode = h[0] & 0x80, h[0] & 0x0F
            n = h[1] & 0x7F
            if n == 126:
                n = struct.unpack(">H", await self.reader.readexactly(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", await self.reader.readexactly(8))[0]
            mask = await self.reader.readexactly(4) if h[1] & 0x80 else None
            data = await self.reader.readexactly(n) if n else b""
            if mask:
                data = ws_unmask(mask, data)
            if opcode == 9:          # ping
                self.writer.write(ws_frame(10, data))
                continue
            if opcode == 10:         # pong
                continue
            if opcode == 8:          # close
                code = struct.unpack(">H", data[:2])[0] if len(data) >= 2 else 1005
                raise Closed("closed by the server: %d %s" % (code, data[2:].decode(errors="replace")))
            parts.append(data)
            if fin:
                return b"".join(parts)

    def close(self):
        try:
            self.writer.write(ws_frame(8, struct.pack(">H", 1000)))
            self.writer.close()
        except (OSError, RuntimeError):
            pass


def new_identity(host):
    """A fresh guest identity and its token (what the SDK fetches for a client with no saved token)."""
    req = urllib.request.Request(host + "/v1/identity", data=b"", method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        doc = json.load(r)
    return doc["identity"], doc["token"]
