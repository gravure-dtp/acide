# window.py
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
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')

from gi.repository import Adw, Gtk, Gio

from acide.doc import Document, Page
from acide.ui.surface import GraphicViewport

@Gtk.Template(resource_path='/io/github/gravures/acide/gtk/AcideWindow.ui')
class AcideWindow(Gtk.ApplicationWindow):
    __gtype_name__ = 'AcideWindow'

    scrolled_window = Gtk.Template.Child()
    header_bar = Gtk.Template.Child()
    menu_button = Gtk.Template.Child()
    zoom_out_button = Gtk.Template.Child()
    zoom_in_button = Gtk.Template.Child()
    zoom_init_button = Gtk.Template.Child()
    zoom_fit_button = Gtk.Template.Child()

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.application = kwargs.get("application")
        self.connect("realize", self.on_realise_cb)

        self.document: Document = None
        self.viewport: GraphicViewport = GraphicViewport()
        self.scrolled_window.set_child(self.viewport)
        self.viewport.queue_draw()

    def get_scale(self):
        display = self.get_display()
        surface = self.get_native().get_surface()
        monitor = display.get_monitor_at_surface(surface)
        return monitor.get_scale_factor()

    def on_realise_cb(self, _):
        self._setup_buttons(
            (
                self.zoom_out_button, "zoom-out-symbolic",
                "zoom_out", self.on_zoom_out
            ),
            (
                self.zoom_in_button, "zoom-in-symbolic",
                "zoom_in", self.on_zoom_in
            ),
            (
                self.zoom_init_button, "zoom-original-symbolic",
                "zoom_init", self.on_zoom_init
            ),
            (
                self.zoom_fit_button, "zoom-fit-best-symbolic",
                "zoom_fit", self.on_zoom_fit
            ),
            scale=self.get_scale(),
        )

    def _setup_buttons(self, *args, scale=1):
        icon_theme = self.application.get_icon_theme()
        for (button, name, _action, callback)  in args:
            icon = icon_theme.lookup_icon(
                name, None, 48, scale, Gtk.TextDirection.NONE, 0
            )
            img = Gtk.Image.new_from_paintable(icon)
            button.set_child(img)
            button.set_sensitive(True)
            action = Gio.SimpleAction.new(_action, None)
            action.connect("activate", callback)
            self.add_action(action)

    def on_zoom_in(self, widget, *args):
        if self.document:
            self.viewport.props.graphic.scale_increase()

    def on_zoom_out(self, widget, *args):
        if self.document:
            self.viewport.props.graphic.scale_decrease()

    def on_zoom_fit(self, widget, *args):
        if self.document:
            self.viewport.props.graphic.scale_fit()

    def on_zoom_init(self, widget, *args):
        if self.document:
            self.viewport.props.graphic.scale_init()

    def set_document(self, doc: Document) -> None:
        self.document = doc
        graphic = self.document.get_graphic()
        self.viewport.props.graphic = graphic


class AboutDialog(Gtk.AboutDialog):

    def __init__(self, parent):
        Gtk.AboutDialog.__init__(self)
        self.props.program_name = 'acide'
        self.props.version = "0.1.0"
        self.props.authors = ['Gilles Coissac']
        self.props.copyright = '2022 Gilles Coissac'
        self.props.logo_icon_name = 'io.github.gravures.acide'
        self.props.modal = True
        self.set_transient_for(parent)
