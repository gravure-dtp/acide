#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# surface.py
#
# Copyright (C) 2011 Gilles Coissacr.
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
#
# NOTE:
#
# Containers that scroll a lot (GtkViewport, GtkTextView, GtkTreeView, etc)
# allocate an offscreen image during scrolling and render their children to it
# (which is possible since drawing is fully hierarchical).
# The offscreen image is a bit larger than the visible area, so most
# of the time when scrolling it just needs to draw the offscreen
# in a different position. This matches contemporary graphics hardware
# much better, as well as allowing efficient transparent backgrounds.
# In order for this to work such containers need to detect when child
# widgets are redrawn so that it can update the offscreen.
# This can be done with the new gdk_window_set_invalidate_handler() function.
"""surface module.

To allow using of GTK on screens with very high DPI value GTK3 and GTK4
use logical pixels, as opposed to physical ones. This is, the user can configure
the desktop environment to scale the pixel size, generally by factor 1 for ordinary
displays and by 2 for high DPI displays.
So on a HiDPI display the logical and physical measurements may differ in scale,
typically by a factor of 2. In most places we're dealing with logical units methods,
but take care that some methods like Texture.get_width() returns physical units.
"""
from enum import IntEnum, unique, auto
from typing import Any, Union, Optional, Tuple

from gi.repository import Gdk, GdkPixbuf, GObject, Graphene, Gsk, Gtk, Pango
import cairo


@unique
class UNIT(IntEnum):
    MILLIMETER = auto()
    INCH = auto()
    PS_POINT = auto()


class GraphicSurface(Gtk.Widget, Gtk.Scrollable):
    """A scrollable widget that render a Graphic Object."""

    __gtype_name__ = "GraphicSurface"
    _hscroll_policy = Gtk.ScrollablePolicy.NATURAL
    _vscroll_policy = Gtk.ScrollablePolicy.NATURAL
    __gproperties__ = {
        "zoom-level": (
			float,
    		"zoom level",
    		"a float value as percent",
    		10.0,
    		3200.0,
    		100.0,
            GObject.ParamFlags.READWRITE,
        ),
        "workspace-margins": (
			object,
    		"size of margins around a page",
    		(
                "a tuple of floats expressing (top, right, bottom, left)"
                "in postscript points unit (1pt = 1/72 inch)"
            ),
            GObject.ParamFlags.READWRITE,
        ),
        "show-rulers": (
            bool,
            "rulers are visible",
            "a boolean value",
            True,
            GObject.ParamFlags.READWRITE,
        ),
        "unit-measure": (
            object,
            "unit of measurement",
            "surface.UNIT enumeration",
            GObject.ParamFlags.READWRITE,
        ),
        "show-cropbox": (
            bool,
            "whetever to show cropbox",
            "a boolean value",
            False,
            GObject.ParamFlags.READWRITE,
        ),
        "data": (
			object,
    		"data to show",
    		"a python object implementing buffer protocol",
            GObject.ParamFlags.READWRITE,
        ),
        "hadjustment": (
            Gtk.Adjustment,
            "hadjustment",
            "horizontal adjustment",
            GObject.ParamFlags.READWRITE,
        ),
        "vadjustment": (
            Gtk.Adjustment,
            "vadjustment",
            "vertical adjustment",
            GObject.ParamFlags.READWRITE,
        ),
        "hscroll-policy": (
            Gtk.ScrollablePolicy,
            "hscroll-policy",
            ("Defines the policy to be used in a scrollable widget when updating"
             "the scrolled window adjustments in a given orientation."),
            Gtk.ScrollablePolicy.NATURAL,
            GObject.ParamFlags.READWRITE,
        ),
        "vscroll-policy": (
            Gtk.ScrollablePolicy,
            "vscroll-policy",
            ("Defines the policy to be used in a scrollable widget when updating"
             "the scrolled window adjustments in a given orientation."),
            Gtk.ScrollablePolicy.NATURAL,
            GObject.ParamFlags.READWRITE,
        )
    }

    def do_get_property(self, prop):
        if prop.name == "zoom-level":
            return self.zoom_level
        elif prop.name == "workspace-margins":
            return self.workspace_margins
        elif prop.name == "show-rulers":
            return self.show_rulers
        elif prop.name == "unit-measure":
            return self.unit_measure
        elif prop.name == "show-cropbox":
            return self.show_cropbox
        elif prop.name == "data":
            return self.data
        elif prop.name == "hscroll-policy":
            return self._hscroll_policy
        elif prop.name == "vscroll-policy":
            return self._vscroll_policy
        elif prop.name == "hadjustment":
            return self.hadjustment
        elif prop.name == "vadjustment":
            return self.vadjustment
        else:
            raise AttributeError(f'unknown property {prop.name}')

    def do_set_property(self, prop, value):
        if prop.name == "zoom-level":
            self.zoom_level = value
            self.queue_draw()
        elif prop.name == "workspace-margins":
            if not isinstance(value, Gtk.Border):
                raise TypeError(
                    f"workspace-margins should be a Gtk.Border not {value.__class}"
                )
            self.workspace_margins = value
            self.queue_draw()
        elif prop.name == "show-rulers":
            self.show_rulers = bool(value)
            self.queue_draw()
        elif prop.name == "unit-measure":
            if not isinstance(value, UNIT):
                raise TypeError(
                    f"unit-measure should be a UNIT enum member not {value.__class}"
                )
            self.unit_measure = value
            self.queue_draw()
        elif prop.name == "show-cropbox":
            self.show_cropbox = bool(value)
            self.queue_draw()
        elif prop.name == "data":
            self.data = self._validate_data(value)
            self.queue_draw()
        elif prop.name == "hscroll-policy":
            self._hscroll_policy = value
        elif prop.name == "vscroll-policy":
            self._vscroll_policy = value
        elif prop.name == "hadjustment":
            self.hadjustment = value
            self._update_hadjustement()
            self.hadjustment.connect("value-changed", self._on_hscroll)
        elif prop.name == "vadjustment":
            self.vadjustment = value
            self._update_vadjustement()
            self.vadjustment.connect("value-changed", self._on_vscroll)
        else:
            raise AttributeError(f'unknown property {prop.name}')

    __slots__ = (
        "unit_scale",
        "monitor_dpi",
        "monitor_res",
        "workspace_size",
        "rulers_size",
        "ps2ppx_transform",
        "ps2lpx_transform",
        "ps2mm_transform",
        "device_matrix",
    )

    def __init__(self):
        super().__init__()
        self.unit_scale: int = 1
        self.monitor_dpi: float = 72.0  # in physical pixel
        self.monitor_res: Graphene.Size = Graphene.Size()  # in physical pixel
        self.workspace_size: Graphene.Size = Graphene.Size()  # in PostScript point
        self.workspace_size.init(612.0, 792.0)  # US Letter
        self.rulers_size: Gtk.Border = Gtk.Border()  # in logical pixel
        self.rulers_size.left = self.rulers_size.top = 20
        self.ps2ppx_transform: float = 1.0
        self.ps2lpx_transform: float = 1.0
        self.ps2mm_transform: float = 25.4 / 72.0
        self.device_matrix: cairo.Matrix = cairo.Matrix()
        self.connect("realize", self.update_monitor_infos)# in physical pixel

        # GObject Properties default values
        self.workspace_margins = Gtk.Border()  # in PostScript point
        self.workspace_margins.top = 100.0
        self.workspace_margins.bottom = 100.0
        self.workspace_margins.left = 100.0
        self.workspace_margins.right = 100.0
        self.show_rulers = True
        self.unit_measure = UNIT.MILLIMETER

        # Inherited properties
        self.set_vexpand(True)
        self.set_hexpand(True)

    def update_monitor_infos(self, caller: GObject) -> None:
        """Update infos for monitor displaying self.

        This function can only be called after the widget has been added
        to a widget hierarchy with a GtkWindow at the top. In general, we should
        only create display specific resources when a widget has been realized.
        """
        #TODO: should be call if top window go on another monitor
        display = self.get_display()
        surface = self.get_native().get_surface()
        monitor = display.get_monitor_at_surface(surface)
        self.unit_scale = monitor.get_scale_factor()
        geometry = monitor.get_geometry()
        self.monitor_res.width = geometry.width * self.unit_scale
        self.monitor_res.height = geometry.height * self.unit_scale
        self.monitor_dpi = self.monitor_res.width / (monitor.get_width_mm() / 25.4)
        # Transformation Matrix
        self.ps2ppx_transform = 1.0 / 72.0 * self.monitor_dpi
        self.ps2lpx_transform = self.ps2ppx_transform / self.unit_scale
        self.device_matrix.xx = self.device_matrix.yy = 1 / self.unit_scale
        # signals
        monitor.connect("notify::scale-factor", self.update_monitor_infos)
        print(self)

    def __str__(self) -> str:
        return (
            f"screen: {self.monitor_res.width} x {self.monitor_res.height}\n"
            f"Scale factor: {self.unit_scale}\n"
            f"dpi: {self.monitor_dpi}\n"
            f"workspace margins: top={self.workspace_margins.top}, "
            f"bottom={self.workspace_margins.bottom}, "
            f"left={self.workspace_margins.left}, "
            f"right={self.workspace_margins.right}"
        )

    @staticmethod
    def get_rgba(r, g, b, a=1.0):
        color = Gdk.RGBA()
        color.red = r
        color.green = g
        color.blue = b
        color.alpha = a
        return color

    @staticmethod
    def get_rect(x, y, w, h):
        rect = Graphene.Rect()
        rect.init(x, y, w, h)
        return rect

    def draw_text(self, snap, text, x, y, color):
        font = Pango.FontDescription.new()
        font.set_family("Sans")
        font.set_size(12 * Pango.SCALE)
        context = self.get_pango_context()
        layout = Pango.Layout(context)
        layout.set_font_description(font)
        point = Graphene.Point()
        point.x = x
        point.y = y
        snap.save()
        snap.translate(point)
        layout.set_text(text)
        snap.append_layout(layout, color)
        snap.restore()

    def draw_grid(self, snap, clip, r, g, b):
        ctx = snap.append_cairo(clip)
        ctx.set_matrix(cairo.Matrix(0.5, 0, 0, 0.5, 0, 0))
        ctx.set_source_rgb(r, g, b)
        ctx.set_line_width(0.5)
        w *= 2
        h *= 2
        for sx in range(0, w, 50):
            ctx.move_to(sx, 0)
            ctx.line_to(sx, h)
        for sy in range(0, h, 50):
            ctx.move_to(0, sy)
            ctx.line_to(w, sy)
        ctx.stroke()

    def draw_rulers(self, snap: Gtk.Snapshot, clip: Graphene.Rect, xo: float, yo: float) -> None:
        # rulers background
        snap.append_color(
            self.get_rgba(0, 0, 0),
            self.get_rect(0, 0, clip.get_width(), self.rulers_size.top),
        )
        snap.append_color(
            self.get_rgba(0, 0, 0),
            self.get_rect(0, 0, self.rulers_size.left, clip.get_height()),
        )

        # draw with physical pixel coordinate
        ctx = snap.append_cairo(clip)
        ctx.set_matrix(self.device_matrix)
        w = clip.get_width() * self.unit_scale
        h = clip.get_height() * self.unit_scale
        rw = self.rulers_size.top * self.unit_scale
        rh = self.rulers_size.left * self.unit_scale
        ctx.set_antialias(cairo.ANTIALIAS_NONE)

        # rulers ticks
        tick = self.monitor_dpi / 25.4  # mm ticks
        tick_len = 8
        ctx.set_source_rgb(1, 1, 1)

        # ticks font
        ctx.select_font_face("sans")
        ctx.set_font_size(20.0)

        # Horinzontal ruler
        xt = xo - xo.__floor__() + rw
        index = int(-xo / self.ps2lpx_transform * self.ps2mm_transform)
        while xt < w:
            if (index % 10 == 0):
                lw = 2.0
                ctx.move_to(xt + 2, rw - tick_len * lw - 4)
                ctx.show_text(str(index))
            else:
                lw = 1.0
            ctx.set_line_width(lw)
            ctx.move_to(xt, rw)
            ctx.line_to(xt, rw - tick_len * lw)
            xt += tick
            index += 1

        # vertcal ruler
        yt = yo - yo.__floor__() + rh
        index = int(-yo / self.ps2lpx_transform  * self.ps2mm_transform)
        while yt < h:
            if (index % 10 == 0):
                lw = 2.0
                gw = 0  # ctx.glyph_extents(list(str(index))).width
                ctx.move_to(rh - tick_len * lw - 4, yt - gw)
                ctx.save()
                ctx.rotate(-1.5708)
                ctx.show_text(str(index))
                ctx.restore()
            else:
                lw = 1.0
            ctx.set_line_width(lw)
            ctx.move_to(rh, yt)
            ctx.line_to(rh - tick_len * lw, yt)
            yt += tick
            index += 1

        ctx.stroke()


    def do_snapshot(self, snap: Gtk.Snapshot) -> None:
        w = self.get_allocated_width()
        h = self.get_allocated_height()
        xo = self.props.hadjustment.get_value()
        yo = self.props.vadjustment.get_value()

        bg_color = self.get_rgba(.4, .4, .4)
        fg_color = self.get_rgba(.2, .2, .2)
        gr_color = self.get_rgba(1, 1, 1)

        fgbox = self.get_rect(0, 0, w, h)
        graphic = self.get_rect(
            (self.props.workspace_margins.left * self.ps2lpx_transform) - xo,
            (self.props.workspace_margins.top * self.ps2lpx_transform) - yo,
            self.workspace_size.width * self.ps2lpx_transform,
            self.workspace_size.height * self.ps2lpx_transform,
        )
        snap.append_color(bg_color, fgbox)
        snap.append_color(gr_color, graphic)

        if self.props.show_rulers:
            self.draw_rulers(
                snap,
                fgbox,
                graphic.get_x() - self.rulers_size.left,
                graphic.get_y() - self.rulers_size.top,
            )

    def do_get_request_mode(self) -> Gtk.SizeRequestMode:
        """Gets whether the widget prefers a height-for-width layout
        or a width-for-height layout.

        Single-child widgets generally propagate the preference of their child,
        more complex widgets need to request something either in context of their
        children or in context of their allocation capabilities.
        """
        return Gtk.SizeRequestMode.CONSTANT_SIZE

    def do_get_border(self) -> Optional[Gtk.Border]:
        """Returns the size of a non-scrolling border around
        the outside of the scrollable."""
        if self.props.show_rulers:
            return self.rulers_size
        return None

    def do_size_allocate(self, width: int, height: int, baseline: int) -> None:
        """This function is used to assign a size, position and (optionally)
        baseline to child widgets.

        When the parent allocates space to the scrollable child widget,
        the widget must ensure the adjustments property values are correct
        and up to date.
        """
        self._update_adjustement()

    def get_workspace_width(self) -> int:
        """Return workspace width measured in logical pixel unit."""
        return (
            self.workspace_size.width + self.props.workspace_margins.right + \
            self.props.workspace_margins.left
        ) * self.ps2lpx_transform

    def get_workspace_height(self) -> int:
        """Return workspace height measured in logical pixel unit."""
        return (
            self.workspace_size.height + self.props.workspace_margins.top + \
            self.props.workspace_margins.bottom
        ) * self.ps2lpx_transform

    def do_measure(
        self, orientation: Gtk.Orientation, for_size: int
    ) -> Tuple[int, int, int, int]:
        """Measures widget for the orientation and for the given for_size.

        As an example, if orientation is GTK_ORIENTATION_HORIZONTAL and for_size
        is 300, this functions will compute the minimum and natural width of widget
        if it is allocated at a height of 300 pixels.
        Return measurements are in logical pixel unit within a tuple
        (int minimum, int natural, int minimum_baseline, int natural_baseline).
        """
        if orientation == Gtk.Orientation.HORIZONTAL:
            width = self.get_workspace_width()
            return (width, width, -1, -1)
        else:
            height = self.get_workspace_height()
            return (height, height, -1, -1)

    def _update_adjustement(self) -> None:
        """Update horizontal and vertical adustements."""
        if not self.props.hadjustment:
            return
        self._update_hadjustement()
        self._update_vadjustement()

    def _update_hadjustement(self) -> None:
        """Sets all properties of the hadjustment at once."""
        self.hadjustment.configure(
            self.props.hadjustment.get_value(),  # value
            0,  # lower
            self.get_workspace_width(),  # upper
            1,  # step increment
            self.get_allocated_width() // 100,  # page increment
            self.get_allocated_width(),  # page size
        )

    def _update_vadjustement(self) -> None:
        """Sets all properties of the vadjustment at once."""
        self.vadjustment.configure(
            self.props.vadjustment.get_value(),  # value
            0,  # lower
            self.get_workspace_height(),  # upper
            1,  # step increment
            self.get_allocated_height() // 100,  # page increment
            self.get_allocated_height(),  # page size
        )

    def _on_hscroll(self, adjustment: Gtk.Adjustment) -> None:
        self.queue_draw()

    def _on_vscroll(self, adjustment: Gtk.Adjustment) -> None:
        self.queue_draw()

# END
