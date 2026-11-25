#!/usr/bin/env python3

# A stand-in for the GTK file chooser backend, for filechooser.py's tests:
# it owns the GTK portal backend's name, logs each request's method and
# title to the file it is given, and answers at once with a file named
# after them, but for one titled Wait, which it holds until the portal
# closes it.

import sys

from gi.repository import Gio, GLib

METHOD = """
    <method name="{}">
      <arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="a{{sv}}" direction="in"/>
      <arg type="u" direction="out"/><arg type="a{{sv}}" direction="out"/>
    </method>"""

NODE = """
<node>
  <interface name="org.freedesktop.impl.portal.FileChooser">{}
  </interface>
  <interface name="org.freedesktop.impl.portal.Request">
    <method name="Close"/>
  </interface>
</node>
""".format("".join(METHOD.format(name) for name in ("OpenFile", "SaveFile", "SaveFiles")))

nodes = Gio.DBusNodeInfo.new_for_xml(NODE)


def call(connection, sender, path, interface, method, parameters, invocation):
    handle, _app, _parent, title, _options = parameters.unpack()
    if title != "Wait":
        invocation.return_value(GLib.Variant("(ua{sv})", (0, {"uris": GLib.Variant("as", ["file:///from/gtk/" + method + "/" + title])})))
    else:
        def close(connection, sender, path, interface, method, parameters, closing):
            closing.return_value(None)
            connection.unregister_object(registration)
            invocation.return_value(GLib.Variant("(ua{sv})", (2, {})))

        registration = connection.register_object(handle, nodes.lookup_interface("org.freedesktop.impl.portal.Request"), close, None, None)
    with open(sys.argv[1], "a") as log:
        log.write(method + " " + title + "\n")


def acquired(connection, name):
    connection.register_object("/org/freedesktop/portal/desktop", nodes.lookup_interface("org.freedesktop.impl.portal.FileChooser"), call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.impl.portal.desktop.gtk", Gio.BusNameOwnerFlags.NONE, acquired, None, None)
GLib.MainLoop().run()
