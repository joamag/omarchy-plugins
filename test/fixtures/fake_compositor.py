#!/usr/bin/env python3

# A compositor stand-in for the files widget's clipboard.py: it advertises a
# seat and a data-control manager, takes the clipboard the helper sets, asks
# for every format offered through a pipe the way a pasting app does, then
# hands the clipboard to someone else. On the way it offers the helper the
# new selection, as every client of the seat is, and notes the offers let
# go. What it saw goes to stdout as JSON.
#
# Usage: fake_compositor.py SOCKET MANAGER   (MANAGER "none" advertises none)

import array
import json
import os
import socket
import struct
import sys


def message(obj, opcode, payload=b""):
    return struct.pack("=IHH", obj, opcode, 8 + len(payload)) + payload


def uint(value):
    return struct.pack("=I", value)


def string(text):
    data = text.encode() + b"\0"
    return uint(len(data)) + data + b"\0" * (-len(data) % 4)


def read_string(body, at):
    length = struct.unpack_from("=I", body, at)[0]
    return body[at + 4:at + 4 + length - 1].decode(), at + 4 + length + (-length % 4)


def main(path, manager):
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    conn, _ = server.accept()
    advertised = [(1, "wl_seat", 9)] + ([(2, manager, 2)] if manager != "none" else [])
    kinds = {1: "display"}
    seen = {"manager": None, "version": None, "offers": [], "selection": None, "data": {}, "released": []}
    source = None
    device = None
    # The compositor's own object ids start here.
    offer = 0xFF000000
    buffer = b""
    while True:
        if len(buffer) < 8 or len(buffer) < struct.unpack_from("=IHH", buffer)[2]:
            data = conn.recv(65536)
            if not data:
                break
            buffer += data
            continue
        obj, opcode, size = struct.unpack_from("=IHH", buffer)
        body = buffer[8:size]
        buffer = buffer[size:]
        kind = kinds.get(obj)
        if kind == "display" and opcode == 1:
            registry = struct.unpack_from("=I", body)[0]
            kinds[registry] = "registry"
            for name, interface, version in advertised:
                conn.sendall(message(registry, 0, uint(name) + string(interface) + uint(version)))
        elif kind == "display" and opcode == 0:
            callback = struct.unpack_from("=I", body)[0]
            conn.sendall(message(callback, 0, uint(0)))
            if seen["selection"] is None:
                continue
            # The clipboard is set: every client of the seat gets it offered.
            kinds[offer] = "offer"
            conn.sendall(message(device, 0, uint(offer)) + message(device, 1, uint(offer)))
            # Then paste every format, and take it away.
            for mime in seen["offers"]:
                read, write = os.pipe()
                conn.sendmsg([message(source, 0, string(mime))], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [write]))])
                os.close(write)
                chunks = []
                while True:
                    chunk = os.read(read, 65536)
                    if not chunk:
                        break
                    chunks.append(chunk)
                os.close(read)
                seen["data"][mime] = b"".join(chunks).decode(errors="replace")
            conn.sendall(message(source, 1))
        elif kind == "registry" and opcode == 0:
            interface, at = read_string(body, 4)
            version, new = struct.unpack_from("=II", body, at)
            kinds[new] = "manager" if interface == manager else interface
            if interface == manager:
                seen["manager"] = interface
                seen["version"] = version
        elif kind == "manager" and opcode == 0:
            source = struct.unpack_from("=I", body)[0]
            kinds[source] = "source"
        elif kind == "manager" and opcode == 1:
            device = struct.unpack_from("=I", body)[0]
            kinds[device] = "device"
        elif kind == "source" and opcode == 0:
            seen["offers"].append(read_string(body, 0)[0])
        elif kind == "device" and opcode in (0, 2):
            seen["selection"] = "clipboard" if opcode == 0 else "primary"
        elif kind == "offer" and opcode == 1:
            seen["released"].append(obj)
    print(json.dumps(seen))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
