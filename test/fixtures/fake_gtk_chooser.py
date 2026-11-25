#!/usr/bin/env python3

# A stand-in for the GTK file chooser backend, for filechooser.py's tests:
# it owns the GTK portal backend's name and answers every request at once
# with a file named after the request's title.

from gi.repository import Gio, GLib

NODE = """
<node>
  <interface name="org.freedesktop.impl.portal.FileChooser">
    <method name="OpenFile">
      <arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>
      <arg type="s" direction="in"/><arg type="a{sv}" direction="in"/>
      <arg type="u" direction="out"/><arg type="a{sv}" direction="out"/>
    </method>
  </interface>
</node>
"""


def call(connection, sender, path, interface, method, parameters, invocation):
    title = parameters.unpack()[3]
    invocation.return_value(GLib.Variant("(ua{sv})", (0, {"uris": GLib.Variant("as", ["file:///from/gtk/" + title])})))


def acquired(connection, name):
    connection.register_object("/org/freedesktop/portal/desktop", Gio.DBusNodeInfo.new_for_xml(NODE).interfaces[0], call, None, None)


Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.impl.portal.desktop.gtk", Gio.BusNameOwnerFlags.NONE, acquired, None, None)
GLib.MainLoop().run()
