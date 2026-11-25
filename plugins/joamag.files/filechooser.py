#!/usr/bin/env python3

# Answer org.freedesktop.impl.portal.FileChooser, the backend
# xdg-desktop-portal asks when an app wants a file to open, a place to save
# or a folder (Chrome, Firefox, Flatpak apps), by showing the request in the
# Files widget: it goes to the widget over its IPC, and the widget answers
# through files.sh chosen, which runs this script with answer. Without the
# widget (not in the bar, or the shell is down) the request goes on to the
# GTK dialog, so an app always gets one.
#
# Usage: filechooser.py
#        filechooser.py answer ID RESPONSE FILTER [PATH...]
#
# D-Bus starts it on demand once files.sh chooser on has put its service
# and portal files in place, and it runs until the session ends or
# files.sh chooser off stops it.

import itertools
import json
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


def filters_of(options):
    """The request's filters, its current one first when the list leaves it
    out, the way the widget's model numbers them."""
    filters = list(options.get("filters") or [])
    current = options.get("current_filter")
    if current and current[0] not in [label for label, _ in filters]:
        filters.insert(0, current)
    return filters


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
        "filters": [[label, [list(p) for p in patterns]] for label, patterns in options.get("filters") or []],
        "currentFilter": [current[0], [list(p) for p in current[1]]] if current else None,
        "files": paths_option(raw, "files"),
    }


class Chooser:
    """The requests on their way, by the id the widget knows them by."""

    def __init__(self, connection, nodes):
        self.connection = connection
        self.request = nodes.lookup_interface(REQUEST)
        self.pending = {}
        self.ids = itertools.count(1)

    def call(self, connection, sender, path, interface, method, parameters, invocation):
        if interface == ANSWERS:
            self.answer(*parameters.unpack())
            invocation.return_value(None)
            return
        handle, app_id, _parent, title, options = parameters.unpack()
        ident = str(next(self.ids))
        # The portal closes the request here when the app gives up on it.
        registration = connection.register_object(handle, self.request, lambda *args: self.close(ident, args[-1]), None, None)
        self.pending[ident] = {"invocation": invocation, "method": method, "parameters": parameters, "handle": handle,
                               "registration": registration, "filters": filters_of(options), "forwarded": False}
        request = json.dumps(describe(ident, method, app_id, title, options, parameters.get_child_value(4)))
        try:
            process = Gio.Subprocess.new(["omarchy-shell", "joamag.files", "choose", ident, request],
                                         Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error:
            self.forward(ident)
            return
        process.communicate_utf8_async(None, None, self.asked, ident)

    def asked(self, process, result, ident):
        """The widget took the request, or it goes to the GTK dialog."""
        try:
            _, out, _ = process.communicate_utf8_finish(result)
        except GLib.Error:
            out = ""
        entry = self.pending.get(ident)
        if entry and not entry["forwarded"] and (not process.get_successful() or (out or "").strip() != "ok"):
            self.forward(ident)

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
        Gio.Subprocess.new(["omarchy-shell", "joamag.files", "chooserClose", ident],
                           Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE)
        entry["invocation"].return_value(GLib.Variant("(ua{sv})", (OTHER, {})))

    def answer(self, ident, response, chosen, paths):
        """The widget's answer: the paths picked and the filter on screen."""
        entry = self.pending.get(ident)
        if not entry or entry["forwarded"]:
            return
        self.pending.pop(ident)
        self.release(entry)
        results = {}
        if response == SUCCESS:
            results["uris"] = GLib.Variant("as", [pathlib.Path(p).as_uri() for p in paths])
            if 0 <= chosen < len(entry["filters"]):
                results["current_filter"] = GLib.Variant("(sa(us))", entry["filters"][chosen])
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


def main(argv):
    if argv[:1] == ["answer"]:
        return send_answer(argv[1:])
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
