# -*- coding: utf-8 -*-
#
# main.py
#
# Copyright 2022 Gilles Coissac
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import sys
import gi

gi.require_version('Gtk', '3.0')
gi.require_version('Adw', '1')

from gi.repository import Gtk, Gio
from acide.ui.window import AcideWindow, AboutDialog


class AcideApplication(Gtk.Application):
    """The main application singleton class."""

    def __init__(self):
        super().__init__(application_id='org.gnome.acide',
                         flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_startup(self):
        """This function is called when the application is first started.
        All initialization should be done here, to prevent doing
        duplicate work in case another window is opened.
        """
        Gtk.Application.do_startup(self)
        actions = [
            ("quit", self.on_quit_action, ['<primary>q']),
            ("about", self.on_about_action, None),
            ('preferences', self.on_preferences_action, None),
        ]
        for action in actions:
            self.create_action(*action)

    def create_action(self, name, callback, shortcuts=None):
        """Add an application action.

        Args:
            name: the name of the action
            callback: the function to be called when the action is
              activated
            shortcuts: an optional list of accelerators
        """
        action = Gio.SimpleAction.new(name, None)
        action.connect("activate", callback)
        self.add_action(action)
        if shortcuts:
            self.set_accels_for_action(f"app.{name}", shortcuts)

    def do_activate(self):
        """Called when the application is activated.

        We raise the application's main window, creating it if
        necessary.
        """
        win = self.props.active_window
        if not win:
            win = AcideWindow(application=self)
        win.present()

    def on_quit_action(self, action, param):
        # self.config.win_height, self.config.win_width = self.window.get_size()
        # self.config.win_x, self.config.win_y = self.window.get_position()
        # self.config.save()
        windows = self.get_windows()
        for window in windows:
            window.destroy()
        self.quit()

    def on_about_action(self, widget, _):
        """Callback for the app.about action."""
        about = AboutDialog(self.props.active_window)
        about.present()

    def on_preferences_action(self, widget, _):
        """Callback for the app.preferences action."""
        print('app.preferences action activated')




def main(version):
    """The application's entry point."""
    app = AcideApplication()
    return app.run(sys.argv)
