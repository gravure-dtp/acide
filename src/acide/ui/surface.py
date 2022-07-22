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
from typing import Any, Union, Optional, Tuple

import gi
gi.require_version('Gtk', '4.0')
gi.require_version("Gdk", "4.0")
gi.require_version('Gsk', '4.0')
gi.require_version('Graphene', '1.0')

from gi.repository import Gdk, GdkPixbuf, Gio, GObject, Graphene, Gsk, Gtk, Pango
import cairo

from acide.measure import Measurable, GObjectMeasurableMeta, Unit
from acide.graphic import Graphic


class GraphicViewport(
    Gtk.Widget, Gtk.Scrollable, Measurable, metaclass=GObjectMeasurableMeta
):
    """A scrollable widget that render a Graphic Object."""

    __gtype_name__ = "GraphicViewport"
    _hscroll_policy = Gtk.ScrollablePolicy.NATURAL
    _vscroll_policy = Gtk.ScrollablePolicy.NATURAL
    __gproperties__ = {
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
        "rulers-unit": (
            object,
            "unit of measure for rulers",
            "surface.Unit enumeration",
            GObject.ParamFlags.READWRITE,
        ),
        "graphic": (
			object,
    		"the Graphic to show",
    		"a python object implementing acide.graphic.Graphic interface",
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
        if prop.name == "workspace-margins":
            return self.workspace_margins
        elif prop.name == "show-rulers":
            return self.show_rulers
        elif prop.name == "rulers-unit":
            return self.rulers_unit
        elif prop.name == "graphic":
            return self.graphic
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
        if prop.name == "workspace-margins":
            if not isinstance(value, Gtk.Border):
                raise TypeError(
                    f"workspace-margins should be a Gtk.Border not {value.__class}"
                )
            # TODO: minimum margin to rulers size
            self.workspace_margins = value
            self.update_workspace_size()
            self.queue_draw()
        elif prop.name == "show-rulers":
            self.show_rulers = bool(value)
            self.queue_draw()
        elif prop.name == "rulers-unit":
            if not isinstance(value, Unit):
                raise TypeError(
                    f"rulers-unit should be a Unit enum member not {value.__class}"
                )
            self.rulers_unit = value
            self.queue_draw()
        elif prop.name == "graphic":
            if isinstance(value, Graphic):
                if self.graphic is not None:
                    self.graphic.on_removed()
                self.graphic = value
                self.graphic.on_added(self)
                self.update_metrics()
                self.update_workspace_size()
                self.graphic.connect("ready", self._on_graphic_ready_cb)
                self.graphic.connect("scaled", self._on_graphic_scaled_cb)
            elif value is None:
                if self.graphic is not None:
                    self.graphic.on_removed()
                self.graphic = None
                self.queue_draw()
            else:
                raise TypeError(
                    "graphic should implement the acide.graphic.Graphic interface"
                )
        elif prop.name == "hscroll-policy":
            self._hscroll_policy = value
        elif prop.name == "vscroll-policy":
            self._vscroll_policy = value
        elif prop.name == "hadjustment":
            self.hadjustment = value
            self._update_hadjustement()
            self.hadjustment.connect("value-changed", self._on_view_changed)
        elif prop.name == "vadjustment":
            self.vadjustment = value
            self._update_vadjustement()
            self.vadjustment.connect("value-changed", self._on_view_changed)
        else:
            raise AttributeError(f'unknown property {prop.name}')

    __slots__ = (
        "pixel_scale",
        "device_margins",
        "workspace_size",
        "graphic_clip",
        "rulers_size",
        "viewport2lpx_transform",
        "lpx2viewport_transform",
        "lpx2graphic_transform",
        "device_matrix",
        "render",
    )

    def __init__(self):
        super().__init__()
        Measurable.__init__(self)  # Mandatory

        self.pixel_scale: int = 1
        self.workspace_size: Graphene.Size = Graphene.Size()  # in logical pixel
        self.rulers_size: Gtk.Border = Gtk.Border()  # in logical pixel
        self.rulers_size.left = self.rulers_size.top = 20
        self.device_matrix: cairo.Matrix = cairo.Matrix()
        self.graphic_clip: Graphene.Rect = Graphene.Rect()
        self.render = None

        # Inherited Gtk.Widget properties
        self.set_vexpand(True)
        self.set_hexpand(True)

        # Inherited Measurable properties
        self.unit = Unit.MILLIMETER
        self.dpi = 72.0  # in physical pixel

        # GObject Properties default values
        self.hadjustment = Gtk.Adjustment()
        self.vadjustment = Gtk.Adjustment()
        self.workspace_margins = Gtk.Border()  # in self.unit
        self.workspace_margins.top = 20.0
        self.workspace_margins.bottom = 20.0
        self.workspace_margins.left = 20.0
        self.workspace_margins.right = 20.0
        self.device_margins = Gtk.Border()  # in logical pixel
        self.rulers_unit = Unit.MILLIMETER
        self.show_rulers = True
        self.graphic = None

        #
        self.update_metrics()
        self.update_workspace_size()

        # Signals
        self.connect("realize", self.update_monitor_infos)

    def _on_graphic_ready_cb(self, graphic, state):
        if state:
            self._on_view_changed(None)

    def _on_graphic_scaled_cb(self, graphic, scale):
        self._update_graphic_transform(graphic, scale)
        self.update_workspace_size()
        self._on_view_changed(None)

    def update_monitor_infos(self, caller: GObject.GObject=None) -> None:
        """Update infos for monitor displaying self.

        This function can only be called after the widget has been added
        to a widget hierarchy with a GtkWindow at the top. In general, we should
        only create display specific resources when a widget has been realized.
        """
        #TODO: should be call if top window go on another monitor
        display = self.get_display()
        surface = self.get_native().get_surface()
        monitor = display.get_monitor_at_surface(surface)
        geometry = monitor.get_geometry()
        #
        self.pixel_scale = monitor.get_scale_factor()
        # Measurable properties
        self.dpi = (geometry.width * self.pixel_scale) / \
                   (monitor.get_width_mm() / 25.4)
        self.size = (monitor.get_width_mm(), monitor.get_height_mm())
        self.unit = Unit.MILLIMETER
        # signals
        monitor.connect("notify::scale-factor", self.update_monitor_infos)
        # Proprties that should consequently be updates
        if self.props.graphic is not None:
            self.graphic.on_updated()
        # Transformation Matrix
        self.update_metrics()
        self.update_workspace_size()

    def update_metrics(self):
        """Update internal matrix.

        Update all internel matrix and transformation coefficients used
        for rendering. This is usually called when properties like :attr:`dpi` or
        :attr:`size` for this viewport changed or when a :class:`Graphic` is added.
        It is safe to called update_metrics() at any time when needed.
        """
        self.viewport2lpx_transform = self.get_transform(Unit.PIXEL) / self.pixel_scale
        self.lpx2viewport_transform = 1.0 / self.viewport2lpx_transform
        self.device_matrix.xx = self.device_matrix.yy = 1 / self.pixel_scale
        if self.props.graphic is not None:
            self._update_graphic_transform(self.props.graphic)
        else:
            self.graphic2lpx_transform = self.lpx2graphic_transform = 1.0

    def _update_graphic_transform(self, graphic, scale=1):
        self.graphic2lpx_transform = (
                (graphic.get_transform(Unit.PIXEL) * (self.dpi / graphic.dpi)) \
                / self.pixel_scale * scale
            )
        self.lpx2graphic_transform = 1.0 / self.graphic2lpx_transform

    def update_workspace_size(self) -> None:
        """Update workspace size.

        Compute workspace_size attrbute accordingly to displayed :class:`Graphic`
        and workspace margins settings measured in logical pixel unit.
        """
        w = h = 0
        if self.props.graphic is not None:
            w = self.props.graphic.size[0] * self.graphic2lpx_transform
            h = self.props.graphic.size[1] * self.graphic2lpx_transform
            trs = self.viewport2lpx_transform * self.props.graphic.scale
            self.device_margins.top = self.props.workspace_margins.top * trs
            self.device_margins.bottom = self.props.workspace_margins.top * trs
            self.device_margins.left = self.props.workspace_margins.top * trs
            self.device_margins.right = self.props.workspace_margins.top * trs
        self.workspace_size.init(
            w + self.device_margins.right + \
                self.device_margins.left,
            h + self.device_margins.top + \
                self.device_margins.bottom,
        ) # in logical pixel
        # TODO: clip x,y could not be zero?
        self.graphic_clip.init(
            0,
            0,
            w,
            h,
        ) # in logical pixel
        self._update_adjustements()

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
            return (self.workspace_size.width, self.workspace_size.width, -1, -1)
        else:
            return (self.workspace_size.height, self.workspace_size.height, -1, -1)

    def _update_adjustements(self) -> None:
        """Update horizontal and vertical adustements."""
        if not self.props.hadjustment:
            return
        self._update_hadjustement()
        self._update_vadjustement()

    def _update_hadjustement(self) -> None:
        """Sets all properties of the hadjustment at once."""
        self.props.hadjustment.configure(
            self.props.hadjustment.get_value(),  # value
            - self.device_margins.left,  # lower
            self.workspace_size.width - self.device_margins.left,  # upper
            1,  # step increment
            self.get_allocated_width() // 100,  # page increment
            self.get_allocated_width(),  # page size
        )

    def _update_vadjustement(self) -> None:
        """Sets all properties of the vadjustment at once."""
        self.props.vadjustment.configure(
            self.props.vadjustment.get_value(),  # value
            - self.device_margins.top,  # lower
            self.workspace_size.height - self.device_margins.top,  # upper
            1,  # step increment
            self.get_allocated_height() // 100,  # page increment
            self.get_allocated_height(),  # page size
        )

    def do_snapshot(self, snap: Gtk.Snapshot) -> None:
        xo = self.props.hadjustment.get_value()
        yo = self.props.vadjustment.get_value()

        # TODO: get this from css or preferences
        bg_color = self.get_rgba(.4, .4, .4)
        fg_color = self.get_rgba(.2, .2, .2)
        gr_color = self.get_rgba(1, 1, .8)

        fgbox = self.get_rect(
            0, 0, self.get_allocated_width(), self.get_allocated_height()
        )
        snap.append_color(bg_color, fgbox)

        if self.render is not None:
            clip = self.get_rect(
                (self.graphic_clip.get_x() - xo) + \
                    (self.render.x * self.graphic2lpx_transform),
                (self.graphic_clip.get_y() - yo) + \
                    (self.render.y * self.graphic2lpx_transform),
                self.render.w / self.pixel_scale,
                self.render.h / self.pixel_scale,
            )
            if self.render.texture is not None:
                snap.append_texture(self.render.texture, clip)
            else:
                snap.append_color(gr_color, clip)

            if self.props.show_rulers:
                self.draw_rulers(snap, fgbox, xo, yo, self.props.graphic.scale)

    def draw_rulers(
        self, snap: Gtk.Snapshot, clip: Graphene.Rect, xo: float, yo: float, scale
    ) -> None:
        #TODO: marker on ruler for current mouse pointer position
        # rulers background in lpx
        snap.append_color(
            self.get_rgba(0, 0, 0),
            self.get_rect(0, 0, clip.get_width(), self.rulers_size.top),
        )
        snap.append_color(
            self.get_rgba(0, 0, 0),
            self.get_rect(0, 0, self.rulers_size.left, clip.get_height()),
        )

        #TODO: drawing could be pre-cached for speed-up
        # draw with physical pixel coordinates
        ctx = snap.append_cairo(clip)
        ctx.set_matrix(self.device_matrix)
        w = clip.get_width() * self.pixel_scale
        h = clip.get_height() * self.pixel_scale
        rw = self.rulers_size.top * self.pixel_scale
        rh = self.rulers_size.left * self.pixel_scale
        ctx.set_antialias(cairo.ANTIALIAS_NONE)

        # rulers ticks
        #TODO: render measurement unit following unit-measure property
        tick = self.dpi / 25.4 * scale # mm ticks gap in physical px
        tick_len = 8  # ticks lenght in physical px
        ctx.set_source_rgb(1, 1, 1)

        # ticks font
        ctx.select_font_face("sans")
        ctx.set_font_size(10.0 * self.pixel_scale)

        # Horizontal ruler
        xt = tick - ((xo * self.pixel_scale) % tick)
        index = int(xo / scale * self.lpx2viewport_transform)

        while xt < w:
            if xt < rw:
                xt += tick
                index += 1
                continue
            if (index % 10 == 0):
                # set longer tick & draw unit value
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

        # vertical ruler
        #TODO: vertical text position (use of pango to draw text)
        yt = tick - ((yo * self.pixel_scale) % tick)
        index = int(yo / scale * self.lpx2viewport_transform)
        while yt < h:
            if yt < rw:
                yt += tick
                index += 1
                continue
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
        self._update_adjustements()

    def _on_view_changed(self, adjustment: Gtk.Adjustment) -> None:
        if self.props.graphic is not None:
            self.props.graphic.on_panned(
                (self.props.hadjustment.get_value() + self.graphic_clip.get_x()) * \
                 self.lpx2graphic_transform,
                (self.props.vadjustment.get_value() + self.graphic_clip.get_y()) * \
                 self.lpx2graphic_transform,
            )
            # self.render = self.props.graphic.get_render()
            self.props.graphic.get_render_async(
                cancellable=None, callback=self._on_get_render_cb, user_data=None
            )
        self.queue_draw()

    def _on_get_render_cb(
        self, src: Graphic, result: Gio.Task, user_data: Any
    ) -> None:
        self.render = self.props.graphic.get_render_finish(result, None)
        self.queue_draw()

    def __str__(self) -> str:
        return (
            f"screen: {self.size[0]}{self.unit.abbr} x {self.size[1]}{self.unit.abbr}\n"
            f"Scale factor: {self.pixel_scale}\n"
            f"dpi: {self.dpi}\n"
            f"workspace margins: top={self.workspace_margins.top}px, "
            f"bottom={self.workspace_margins.bottom}px, "
            f"left={self.workspace_margins.left}px, "
            f"right={self.workspace_margins.right}px"
        )

# END
