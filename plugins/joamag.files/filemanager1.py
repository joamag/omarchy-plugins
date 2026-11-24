#!/usr/bin/env python3

# Answer org.freedesktop.FileManager1, the D-Bus service browsers and other
# apps call to show a folder or a file in the file manager ("Show in
# folder", "Open containing folder"), by handing it to the Files widget
# through files.sh: ShowFolders opens the folder, ShowItems and
# ShowItemProperties open the folder holding the item, with it picked.
#
# Usage: filemanager1.py
#
# files.sh default on starts it, and D-Bus starts it on demand once the
# service file is in place. While another file manager holds the name
# (Nautilus does while a window of it is open) it waits in line and takes
# over when that one lets go; it never takes the name away. It runs until
# files.sh default off stops it, or the session ends.

import os
import signal
import subprocess
import sys

from gi.repository import Gio, GLib

NAME = "org.freedesktop.FileManager1"
OBJECT = "/org/freedesktop/FileManager1"
HERE = os.path.dirname(os.path.abspath(__file__))

INTERFACE = """
<node>
  <interface name="org.freedesktop.FileManager1">
    <method name="ShowFolders">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItems">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItemProperties">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
  </interface>
</node>
"""

COMMANDS = {"ShowFolders": "open", "ShowItems": "reveal", "ShowItemProperties": "reveal"}


def call(connection, sender, path, interface, method, parameters, invocation):
    uris = parameters.unpack()[0]
    # The caller does not wait on the widget; the widget shows the first one.
    invocation.return_value(None)
    if uris:
        subprocess.Popen([os.path.join(HERE, "files.sh"), COMMANDS[method], uris[0]],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    # Children are reaped as they end, never waited on.
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)
    interface = Gio.DBusNodeInfo.new_for_xml(INTERFACE).interfaces[0]
    loop = GLib.MainLoop()

    def connected(connection, name):
        connection.register_object(OBJECT, interface, call, None, None)

    def lost(connection, name):
        # Called while waiting in line too; only a closed bus ends it.
        if connection is None or connection.is_closed():
            loop.quit()

    Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.NONE, connected, None, lost)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
