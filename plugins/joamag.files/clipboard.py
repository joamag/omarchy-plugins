#!/usr/bin/env python3

# Own the Wayland clipboard with several formats at once, the way a file
# manager does, so files copied in the widget paste everywhere: Nautilus
# reads x-special/gnome-copied-files (which also says copy or cut), browsers
# and most apps read text/uri-list, text fields and terminals read plain
# text, and a picture can be pasted as the picture itself. wl-copy offers a
# single format, hence this.
#
# It speaks the data-control protocol (ext-data-control-v1, or the wlr one
# it grew from), which sets the clipboard without a focused window, straight
# over the compositor's socket with nothing but the standard library.
#
# Usage: clipboard.py [--primary] [--foreground] TYPE=FILE...
#
# Every TYPE is offered with the bytes of FILE, read up front. Once the
# compositor has the clipboard it forks into the background (unless
# --foreground) and serves pastes until another app takes the clipboard.
# --primary sets the middle-click selection instead. Exits 2 when there is
# no Wayland session or no data-control protocol, so the caller can fall
# back to wl-copy.

import array
import os
import socket
import struct
import sys

MANAGERS = ("ext_data_control_manager_v1", "zwlr_data_control_manager_v1")

# Object ids this client picks; the compositor's own start at 0xff000000.
DISPLAY, REGISTRY, SYNC, SEAT, MANAGER, SOURCE, DEVICE, READY = range(1, 9)


def message(obj, opcode, payload=b""):
    return struct.pack("=IHH", obj, opcode, 8 + len(payload)) + payload


def uint(value):
    return struct.pack("=I", value)


def string(text):
    data = text.encode() + b"\0"
    return uint(len(data)) + data + b"\0" * (-len(data) % 4)


def read_string(body, at):
    length = struct.unpack_from("=I", body, at)[0]
    text = body[at + 4:at + 4 + length - 1].decode(errors="replace")
    return text, at + 4 + length + (-length % 4)


class Connection:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buffer = b""
        self.fds = []

    def send(self, data):
        self.sock.sendall(data)

    # The next whole message, with the file descriptors that came along.
    def receive(self):
        while True:
            if len(self.buffer) >= 8:
                obj, opcode, size = struct.unpack_from("=IHH", self.buffer)
                if len(self.buffer) >= size:
                    body = self.buffer[8:size]
                    self.buffer = self.buffer[size:]
                    return obj, opcode, body
            data, ancillary, _, _ = self.sock.recvmsg(65536, socket.CMSG_SPACE(28 * 4))
            if not data:
                raise ConnectionError("the compositor closed the connection")
            for level, kind, payload in ancillary:
                if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    fds = array.array("i")
                    fds.frombytes(payload[:len(payload) - len(payload) % fds.itemsize])
                    self.fds.extend(fds)
            self.buffer += data


def socket_path():
    display = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    if display.startswith("/"):
        return display
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    return os.path.join(runtime, display) if runtime else None


def fail(text, code):
    print("clipboard.py: " + text, file=sys.stderr)
    sys.exit(code)


def write_all(fd, data):
    try:
        os.set_blocking(fd, True)
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
    except OSError:
        pass
    finally:
        os.close(fd)


def detach():
    if os.fork() > 0:
        os._exit(0)
    os.setsid()
    null = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(null, fd)


def main(argv):
    primary = "--primary" in argv
    foreground = "--foreground" in argv
    offers = []
    for arg in argv:
        if arg.startswith("--"):
            continue
        # The last = splits: a type can carry one (text/plain;charset=utf-8).
        mime, sep, path = arg.rpartition("=")
        if not sep or not mime:
            fail("expected TYPE=FILE, got " + arg, 1)
        with open(path, "rb") as source:
            offers.append((mime, source.read()))
    if not offers:
        fail("nothing to offer", 1)

    path = socket_path()
    if not path:
        fail("no Wayland session", 2)
    try:
        conn = Connection(path)
    except OSError as error:
        fail("cannot reach the compositor: " + str(error), 2)

    # The globals this needs: a seat and a data-control manager.
    conn.send(message(DISPLAY, 1, uint(REGISTRY)) + message(DISPLAY, 0, uint(SYNC)))
    seat = None
    managers = {}
    while True:
        obj, opcode, body = conn.receive()
        if obj == REGISTRY and opcode == 0:
            name = struct.unpack_from("=I", body)[0]
            interface, at = read_string(body, 4)
            version = struct.unpack_from("=I", body, at)[0]
            if interface == "wl_seat" and seat is None:
                seat = name
            elif interface in MANAGERS:
                managers[interface] = (name, version)
        elif obj == DISPLAY and opcode == 0:
            fail("the compositor refused the request", 1)
        elif obj == SYNC and opcode == 0:
            break
    kind = next((m for m in MANAGERS if m in managers), None)
    if seat is None or kind is None:
        fail("the compositor offers no data-control protocol", 2)
    name, version = managers[kind]
    # The primary selection needs version 2 of the wlr protocol.
    if primary and kind.startswith("zwlr") and version < 2:
        fail("the compositor has no primary selection over data-control", 2)

    requests = message(REGISTRY, 0, uint(seat) + string("wl_seat") + uint(1) + uint(SEAT))
    # Only the requests of version 1 of ext and version 2 of wlr are used, so
    # a newer compositor is asked for no more than that.
    supported = 2 if kind.startswith("zwlr") else 1
    requests += message(REGISTRY, 0, uint(name) + string(kind) + uint(min(version, supported)) + uint(MANAGER))
    requests += message(MANAGER, 0, uint(SOURCE))
    for mime, _ in offers:
        requests += message(SOURCE, 0, string(mime))
    requests += message(MANAGER, 1, uint(DEVICE) + uint(SEAT))
    requests += message(DEVICE, 2 if primary else 0, uint(SOURCE))
    requests += message(DISPLAY, 0, uint(READY))
    conn.send(requests)

    data = dict(offers)
    detached = foreground
    while True:
        obj, opcode, body = conn.receive()
        if obj == DISPLAY and opcode == 0:
            fail("the compositor refused the clipboard", 1)
        elif obj == READY and opcode == 0 and not detached:
            # The clipboard is ours; the caller can go on while this serves it.
            detach()
            detached = True
        elif obj == SOURCE and opcode == 0:
            mime, _ = read_string(body, 0)
            write_all(conn.fds.pop(0), data.get(mime, b""))
        elif obj == SOURCE and opcode == 1:
            # Another app took the clipboard.
            return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
