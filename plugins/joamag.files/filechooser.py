#!/usr/bin/env python3

# Answer org.freedesktop.impl.portal.FileChooser, the backend
# xdg-desktop-portal asks when an app wants a file to open, a place to save
# or a folder (Chrome, Firefox, Flatpak apps), by showing the request in the
# Files widget: it goes to the widget over its IPC, and the widget answers
# through files.sh chosen, which runs this script with answer. Without the
# widget (not in the bar, or the shell is down) the request goes on to the
# GTK dialog, so an app always gets one. A shell started again asks through
# files.sh resend for the requests it lost.
#
# Usage: filechooser.py
#        filechooser.py answer ID RESPONSE FILTER [PATH...]
#        filechooser.py resend
#
# D-Bus starts it on demand once files.sh chooser on has put its service
# and portal files in place, and it runs until the session ends or
# files.sh chooser off stops it.

import itertools
import json
import os
import pathlib
import sys

from gi.repository import Gio, GLib

NAME = "org.freedesktop.impl.portal.desktop.joamag.files"
OBJECT = "/org/freedesktop/portal/desktop"
CHOOSER = "org.freedesktop.impl.portal.FileChooser"
REQUEST = "org.freedesktop.impl.portal.Request"
ANSWERS = "org.joamag.Files.Chooser"
GTK = "org.freedesktop.impl.portal.desktop.gtk"

# How a request ends: picked, cancelled, or closed some other way.
SUCCESS, CANCELLED, OTHER = 0, 1, 2

METHOD = """
    <method name="{}">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="a{{sv}}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{{sv}}" name="results" direction="out"/>
    </method>"""

INTERFACE = """
<node>
  <interface name="org.freedesktop.impl.portal.FileChooser">{}
  </interface>
  <interface name="org.joamag.Files.Chooser">
    <method name="Answer">
      <arg type="s" name="id" direction="in"/>
      <arg type="u" name="response" direction="in"/>
      <arg type="i" name="filter" direction="in"/>
      <arg type="as" name="paths" direction="in"/>
    </method>
    <method name="Resend"/>
  </interface>
  <interface name="org.freedesktop.impl.portal.Request">
    <method name="Close"/>
  </interface>
</node>
""".format("".join(METHOD.format(name) for name in ("OpenFile", "SaveFile", "SaveFiles")))


def path_option(options, key):
    """A path the portal sends as bytes ending in a NUL."""
    value = options.lookup_value(key, GLib.VariantType("ay"))
    return value.get_bytestring().decode("utf-8", "surrogateescape") if value else ""


def paths_option(options, key):
    value = options.lookup_value(key, GLib.VariantType("aay"))
    return [p.decode("utf-8", "surrogateescape") if isinstance(p, bytes) else p for p in value.get_bytestring_array()] if value else []


def filter_key(raw):
    """What tells one filter from another, the way the widget's model does
    (Model.sameFilter): its label, its globs and its MIME types, each in
    their order."""
    label, patterns = raw
    return label, [p for kind, p in patterns if kind != 1 and p], [p.lower() for kind, p in patterns if kind == 1 and p]


def filters_of(options):
    """The request's filters, its current one first when the list leaves it
    out, the way the widget's model numbers them."""
    filters = list(options.get("filters") or [])
    current = options.get("current_filter")
    if current and filter_key(current) not in [filter_key(f) for f in filters]:
        filters.insert(0, current)
    return filters


def mime_lines(name):
    """The lines of shared-mime-info's file NAME, in every data folder."""
    home = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    for folder in [home] + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        try:
            with open(os.path.join(folder, "mime", name), encoding="utf-8") as lines:
                yield from (line.rstrip("\n") for line in lines if not line.startswith("#"))
        except OSError:
            pass


def mime_globs(mimes):
    """The names ("*.docx") of the files of MIMES, and of the types that are
    kinds of them (text/x-python of text/plain), the way GTK matches a MIME
    type, as shared-mime-info lists them."""
    aliases = dict(line.split(" ", 1) for line in mime_lines("aliases") if " " in line)
    wanted = {aliases.get(mime, mime) for mime in mimes}
    parents = {}
    for line in mime_lines("subclasses"):
        child, _, parent = line.partition(" ")
        parents.setdefault(child, set()).add(parent)

    def kind(mime, seen):
        return mime in wanted or any(kind(parent, seen | {mime}) for parent in parents.get(mime, ()) if parent not in seen)

    globs = []
    for line in mime_lines("globs2"):
        fields = line.split(":")
        if len(fields) >= 3 and fields[2] != "__NOGLOBS__" and fields[2] not in globs and kind(fields[1], set()):
            globs.append(fields[2])
    return globs


def patterns_of(patterns):
    """A filter's patterns as lists, with the names of the files of each
    MIME type in it, which the widget tells files apart by; image/* and the
    like it knows by itself."""
    mimes = [mime for kind, mime in patterns if kind == 1 and not mime.endswith("/*")]
    return [list(p) for p in patterns] + ([[0, glob] for glob in mime_globs(mimes)] if mimes else [])


def describe(ident, method, app_id, title, options, raw):
    """The request as the widget reads it (Model.chooserRequest), from its
    options unpacked and, for the paths, as bytes (RAW)."""
    current = options.get("current_filter")
    return {
        "id": ident,
        "method": method,
        "app": app_id,
        "title": title,
        "acceptLabel": options.get("accept_label", ""),
        "currentName": options.get("current_name", ""),
        "currentFolder": path_option(raw, "current_folder"),
        "currentFile": path_option(raw, "current_file"),
        "multiple": bool(options.get("multiple", False)),
        "directory": bool(options.get("directory", False)),
        "filters": [[label, patterns_of(patterns)] for label, patterns in options.get("filters") or []],
        "currentFilter": [current[0], patterns_of(current[1])] if current else None,
        "files": paths_option(raw, "files"),
    }


class Chooser:
    """The requests on their way, by the id the widget knows them by."""

    def __init__(self, connection, nodes):
        self.connection = connection
        self.request = nodes.lookup_interface(REQUEST)
        self.pending = {}
        # Closed while on their way to the widget, which hears of it after.
        self.closed = set()
        self.ids = itertools.count(1)

    def call(self, connection, sender, path, interface, method, parameters, invocation):
        if interface == ANSWERS:
            if method == "Resend":
                self.resend()
            else:
                try:
                    self.answer(*parameters.unpack())
                except ValueError as error:
                    invocation.return_dbus_error("org.freedesktop.DBus.Error.InvalidArgs", str(error))
                    return
            invocation.return_value(None)
            return
        handle, app_id, _parent, title, options = parameters.unpack()
        ident = str(next(self.ids))
        # The portal closes the request here when the app gives up on it.
        registration = connection.register_object(handle, self.request, lambda *args: self.close(ident, args[-1]), None, None)
        self.pending[ident] = {"invocation": invocation, "method": method, "parameters": parameters, "handle": handle,
                               "registration": registration, "filters": filters_of(options), "forwarded": False,
                               "asking": False}
        # The widget has no controls for an app's choices (the encoding to
        # read a file in), which the GTK dialog shows.
        if options.get("choices"):
            self.forward(ident)
            return
        self.pending[ident]["request"] = json.dumps(describe(ident, method, app_id, title, options, parameters.get_child_value(4)))
        self.ask(ident)

    def ask(self, ident):
        """Hands the request to the widget, or to the GTK dialog when it
        cannot be asked."""
        entry = self.pending[ident]
        try:
            process = Gio.Subprocess.new(["omarchy-shell", "joamag.files", "choose", ident, entry["request"]],
                                         Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error:
            self.forward(ident)
            return
        entry["asking"] = True
        process.communicate_utf8_async(None, None, self.asked, ident)

    def resend(self):
        """The requests the widget took go to it again: a shell that started
        again lost them, and the apps still wait. One on its way already goes
        again once the widget has taken it; one with the GTK dialog stays
        there."""
        for ident, entry in list(self.pending.items()):
            if entry["forwarded"]:
                continue
            if entry["asking"]:
                entry["resend"] = True
            else:
                self.ask(ident)

    def asked(self, process, result, ident):
        """The widget took the request, or it goes to the GTK dialog."""
        try:
            _, out, _ = process.communicate_utf8_finish(result)
        except GLib.Error:
            out = ""
        if ident in self.closed:
            self.closed.discard(ident)
            self.drop(ident)
            return
        entry = self.pending.get(ident)
        if not entry:
            return
        entry["asking"] = False
        if not entry["forwarded"] and (not process.get_successful() or (out or "").strip() != "ok"):
            self.forward(ident)
        elif entry.pop("resend", False):
            # Asked for again while on its way: the shell that took it may
            # be the one that went.
            self.ask(ident)

    def forward(self, ident):
        entry = self.pending[ident]
        entry["forwarded"] = True

        def done(connection, result):
            self.pending.pop(ident, None)
            self.release(entry)
            try:
                entry["invocation"].return_value(connection.call_finish(result))
            except GLib.Error as error:
                entry["invocation"].return_gerror(error)

        self.connection.call(GTK, OBJECT, CHOOSER, entry["method"], entry["parameters"], GLib.VariantType("(ua{sv})"),
                             Gio.DBusCallFlags.NONE, GLib.MAXINT32, None, done)

    def close(self, ident, invocation):
        invocation.return_value(None)
        entry = self.pending.get(ident)
        if not entry:
            return
        if entry["forwarded"]:
            # The GTK dialog answers the call itself once it is closed.
            self.connection.call(GTK, entry["handle"], REQUEST, "Close", None, None, Gio.DBusCallFlags.NONE, -1, None, None)
            return
        self.pending.pop(ident)
        self.release(entry)
        entry["invocation"].return_value(GLib.Variant("(ua{sv})", (OTHER, {})))
        # One still on its way would show after the widget heard it was
        # closed, so the widget hears of it once it has it.
        if entry["asking"]:
            self.closed.add(ident)
        else:
            self.drop(ident)

    def drop(self, ident):
        """The widget lets go of a request the app gave up on."""
        try:
            Gio.Subprocess.new(["omarchy-shell", "joamag.files", "chooserClose", ident],
                               Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error:
            pass

    def answer(self, ident, response, chosen, paths):
        """The widget's answer: the paths picked and the filter on screen. A
        path that is not absolute raises ValueError and leaves the request
        waiting for a right answer."""
        entry = self.pending.get(ident)
        if not entry or entry["forwarded"]:
            return
        results = {}
        if response == SUCCESS:
            results["uris"] = GLib.Variant("as", [pathlib.Path(p).as_uri() for p in paths])
            if 0 <= chosen < len(entry["filters"]):
                results["current_filter"] = GLib.Variant("(sa(us))", entry["filters"][chosen])
        self.pending.pop(ident)
        self.release(entry)
        entry["invocation"].return_value(GLib.Variant("(ua{sv})", (response, results)))

    def release(self, entry):
        if entry["registration"]:
            self.connection.unregister_object(entry["registration"])
            entry["registration"] = 0


def send_answer(args):
    """The widget's answer, handed to the running service."""
    try:
        ident, response, chosen, paths = args[0], int(args[1]), int(args[2]), args[3:]
    except (IndexError, ValueError):
        print("error\tanswer needs an id, a response and a filter")
        return 1
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync(NAME, OBJECT, ANSWERS, "Answer", GLib.Variant("(suias)", (ident, response, chosen, paths)),
                      None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None)
    except GLib.Error as error:
        print("error\t" + error.message)
        return 1
    return 0


def send_resend():
    """The running service's requests, shown in the widget again; without a
    service running there are none."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        bus.call_sync(NAME, OBJECT, ANSWERS, "Resend", None, None, Gio.DBusCallFlags.NO_AUTO_START, 5000, None)
    except GLib.Error as error:
        if error.matches(Gio.dbus_error_quark(), Gio.DBusError.NAME_HAS_NO_OWNER) or error.matches(Gio.dbus_error_quark(), Gio.DBusError.SERVICE_UNKNOWN):
            return 0
        print("error\t" + error.message)
        return 1
    return 0


def main(argv):
    if argv[:1] == ["answer"]:
        return send_answer(argv[1:])
    if argv[:1] == ["resend"]:
        return send_resend()
    nodes = Gio.DBusNodeInfo.new_for_xml(INTERFACE)
    loop = GLib.MainLoop()

    def connected(connection, name):
        service = Chooser(connection, nodes)
        for interface in (CHOOSER, ANSWERS):
            connection.register_object(OBJECT, nodes.lookup_interface(interface), service.call, None, None)

    def lost(connection, name):
        # Another one already answers, or the bus closed.
        loop.quit()

    Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, connected, None, lost)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
