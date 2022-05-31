# -*- coding: utf-8 -*-
#
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

from gi.repository import Gdk, GdkPixbuf, GObject, Graphene, Gsk, Gtk, Pango

import cairo


class PdfSurface(Gtk.Widget):
    """A scrollable widget to render pdf."""

   #  __gtype_name__ = "PdfSurface"
   #  __gproperties__ = {
   #      "zoom": (
			# float,
   #  		"zoom level",
   #  		"a float value",
   #  		1.0,
   #  		400.0,
   #  		20.0,
   #          GObject.ParamFlags.READWRITE,
   #      ),
   #      "threshold-view": (
   #          bool,
   #          "is in threshold view mode",
   #          "a boolean value",
   #          False,
   #          GObject.ParamFlags.READWRITE,
   #      ),
   #      "threshold-value": (
			# float,
   #  		"threshold value",
   #  		"a float value",
   #  		0,
   #  		1.0,
   #  		0.5,
   #          GObject.ParamFlags.READWRITE,
   #      ),
   #      "show-numbers": (
   #          bool,
   #          "show numbers",
   #          "a boolean value",
   #          False,
   #          GObject.ParamFlags.READWRITE,
   #      ),
   #      "data": (
			# object,
   #  		"data to show",
   #  		"a python object implementing buffer protocol",
   #          GObject.ParamFlags.READWRITE,
   #      ),
   #      "canvas-size": (
			# object,
   #  		"the current canvas size",
   #  		"a python tuple",
   #          GObject.ParamFlags.READABLE,
   #      ),
   #  }

    def __init__(self, data=None):
        super().__init__()
        #self.set_vexpand(True)
        #self.set_hexpand(True)
        self.scale = 1
        self.data = data

    # def do_get_property(self, prop):
    #     if prop.name == 'zoom':
    #         return self.zoom
    #     elif prop.name == 'threshold-view':
    #         return self.threshold_view
    #     elif prop.name == 'threshold-value':
    #         return self.threshold_value
    #     elif prop.name == 'show-numbers':
    #         return self.show_numbers
    #     elif prop.name == 'data':
    #         return self.data
    #     elif prop.name == 'canvas-size':
    #         return self.canvas_size
        # elif prop.name == 'hadjustment':
        #     return getattr(
        #         MatrixView.hadjustment,
        #         '_property_helper_hadjustment'
        #     )
        # elif prop.name == 'vadjustment':
        #     return getattr(
        #         MatrixView.vadjustment,
        #         '_property_helper_vadjustment'
        #     )
    #     else:
    #         raise AttributeError(f'unknown property {prop.name}')

    # def do_set_property(self, prop, value):
    #     if prop.name == 'zoom':
    #         self.zoom = value
    #         self._update_canvas()
    #         self.queue_draw()
    #     elif prop.name == 'threshold-view':
    #         self.threshold_view = bool(value)
    #         self.queue_draw()
    #     elif prop.name == 'threshold-value':
    #         self.threshold_value = value
    #         self.queue_draw()
    #     elif prop.name == 'show-numbers':
    #         self.show_numbers = bool(value)
    #         self.queue_draw()
    #     elif prop.name == 'data':
    #         self.data = self._validate_data(value)
    #         self.queue_draw()
        # elif prop.name == 'hadjustment':
        #     setattr(
        #         MatrixView.hadjustment,
        #         '_property_helper_hadjustment',
        #         value
        #     )
        #     self._update_hadjustement()
        #     self.hadjustment.connect('value-changed', self._on_hscroll)
        # elif prop.name == 'vadjustment':
        #     setattr(
        #         MatrixView.vadjustment,
        #         '_property_helper_vadjustment',
        #         value
        #     )
        #     self._update_vadjustement()
        #     self.vadjustment.connect('value-changed', self._on_vscroll)
    #     else:
    #         raise AttributeError(f'unknown property {prop.name}')

    def _validate_data(self, data):
        return data

    def get_rgba(self, r, g, b, a=1.0):
        color = Gdk.RGBA()
        color.red = r
        color.green = g
        color.blue = b
        color.alpha = a
        return color

    def get_rect(self, x, y, w, h):
        rect = Graphene.Rect()
        rect.__init__(x, y, w, h)
        return rect

    def draw_text(self, text, color, x, y, snap):
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

    def do_snapshot(self, snap):
        w = self.get_allocated_width()
        h = self.get_allocated_height()
        print(f"snapshot {w}x{h}")

        texture = self.data
        fg_color = self.get_rgba(.3, .7, 0)
        bg_color = self.get_rgba(.2, .2, .10)

        bbox = self.get_rect(
            0, 0, texture.get_intrinsic_width(), texture.get_intrinsic_height()
        )
        rect = self.get_rect(100, 80, 50, 50)

        # DRAWING
        snap.append_color(bg_color, bbox)

        # grid
        size = 16
        for y in range(0, h + 20, 100):
            y += 40
            for x in range(0, w + 20, 100):
                x += 40
                r = self.get_rect(x + size / 2 - 1, y, 2, size)
                snap.append_color(bg_color, r)
                r = self.get_rect(x, y + size / 2 - 1, size, 2)
                snap.append_color(fg_color, r)

        # text
        self.draw_text("Mon texte ici", fg_color, 200, 100, snap)
        self.draw_text("un autre texte ici", bg_color, 400, 150, snap)

        # shape
        snap.append_color(fg_color, rect)

        # texture.snapshot(
        #     snap, texture.get_intrinsic_width(), texture.get_intrinsic_height()
        # )
        # snap.append_texture(texture, bbox)



    # def do_get_request_mode(self):
    #     return Gtk.SizeRequestMode.CONSTANT_SIZE

    # def do_size_allocate(self, width, height, baselne):
    #     pass

    # def do_measure(self, orientation, for_size):
    #     if orientation == Gtk.Orientation.HORIZONTAL:
    #         width = self.data.get_intrinsic_width() * self.scale
    #         return (width, width, -1, -1)
    #     else:
    #         height = self.data.get_intrinsic_height() * self.scale
    #         return (height, height, -1, -1)





# class MatrixView(Gtk.DrawingArea, Gtk.Scrollable):
#     """A scrollable widget to render raster object.

#     Extends Gtk.DrawingArea and implements Gtk.Scrollable.
#     The GtkDrawingArea is used for creating custom user interface.
#     It’s essentially a blank widget we can draw on it.

#     The application may want to connect to this events:
#     	* Mouse and button press signals to respond to input
#     	  from the user. (Use gtk_widget_add_events()
#     	  to enable events you wish to receive.)

#     	* The GtkWidget::realize signal to take any necessary
#     	  actions when the widget is instantiated on a particular display.
#     	  (Create GDK resources in response to this signal.)

#     	* The GtkWidget::size-allocate signal to take any necessary
#     	  actions when the widget changes size.

#     	* The GtkWidget::draw signal to handle artredrawing
#     	  the contents of the widget.

#     If you want to have a theme-provided background,
#     you need to call gtk_render_background() in draw method().
#     """

#     __gtype_name__ = "MatrixView"

#     __gproperties__ = {
#         "zoom": (
# 			float,
#     		"zoom level",
#     		"a float value",
#     		1.0,
#     		400.0,
#     		20.0,
#             GObject.ParamFlags.READWRITE,
#         ),
#         "threshold-view": (
#             bool,
#             "is in threshold view mode",
#             "a boolean value",
#             False,
#             GObject.ParamFlags.READWRITE,
#         ),
#         "threshold-value": (
# 			float,
#     		"threshold value",
#     		"a float value",
#     		0,
#     		1.0,
#     		0.5,
#             GObject.ParamFlags.READWRITE,
#         ),
#         "show-numbers": (
#             bool,
#             "show numbers",
#             "a boolean value",
#             False,
#             GObject.ParamFlags.READWRITE,
#         ),
#         "data": (
# 			object,
#     		"data to show",
#     		"a python object implementing buffer protocol",
#             GObject.ParamFlags.READWRITE,
#         ),
#         "canvas-size": (
# 			object,
#     		"the current canvas size",
#     		"a python tuple",
#             GObject.ParamFlags.READABLE,
#         ),
#         "hscroll-policy": (
#             Gtk.ScrollablePolicy,
#             "hscroll_policy",
#             "hscroll policy",
#             Gtk.ScrollablePolicy.MINIMUM,
#             GObject.ParamFlags.READWRITE,
#         ),
#         "vscroll-policy": (
#             Gtk.ScrollablePolicy,
#             "vscroll_policy",
#             "vscroll policy",
#             Gtk.ScrollablePolicy.MINIMUM,
#             GObject.ParamFlags.READWRITE,
#         ),
#         "hadjustment": (
#             Gtk.Adjustment,
#             "hadjustment",
#             "horizontal adjustment",
#             GObject.ParamFlags.READWRITE,
#         ),
#         "vadjustment": (
#             Gtk.Adjustment,
#             "vadjustment",
#             "vertical adjustment",
#             GObject.ParamFlags.READWRITE,
#         )
#     }

#     def __init__(self, data=None, *args, **kwargs):
#         super().__init__(*args, **kwargs)
#         self.data = data
#         self._margins = (100, 100)  #TODO: make it a property
#         self._pixbuf = None
#         self.connect('draw', self._on_draw_cb)

#     def do_get_property(self, prop):
#         if prop.name == 'zoom':
#             return self.zoom
#         elif prop.name == 'threshold-view':
#             return self.threshold_view
#         elif prop.name == 'threshold-value':
#             return self.threshold_value
#         elif prop.name == 'show-numbers':
#             return self.show_numbers
#         elif prop.name == 'data':
#             return self.data
#         elif prop.name == 'canvas-size':
#             return self.canvas_size
#         elif prop.name == 'hadjustment':
#             return getattr(
#                 MatrixView.hadjustment,
#                 '_property_helper_hadjustment'
#             )
#         elif prop.name == 'vadjustment':
#             return getattr(
#                 MatrixView.vadjustment,
#                 '_property_helper_vadjustment'
#             )
#         else:
#             raise AttributeError(f'unknown property {prop.name}')

#     def do_set_property(self, prop, value):
#         if prop.name == 'zoom':
#             self.zoom = value
#             self._update_canvas()
#             self.queue_draw()
#         elif prop.name == 'threshold-view':
#             self.threshold_view = bool(value)
#             self.queue_draw()
#         elif prop.name == 'threshold-value':
#             self.threshold_value = value
#             self.queue_draw()
#         elif prop.name == 'show-numbers':
#             self.show_numbers = bool(value)
#             self.queue_draw()
#         elif prop.name == 'data':
#             self.data = self._validate_data(value)
#             self._rangelevels = np.unique(value)
#             self._levels = self._rangelevels.size
#             self._update_canvas()
#             self.queue_draw()
#         elif prop.name == 'hadjustment':
#             setattr(
#                 MatrixView.hadjustment,
#                 '_property_helper_hadjustment',
#                 value
#             )
#             self._update_hadjustement()
#             self.hadjustment.connect('value-changed', self._on_hscroll)
#         elif prop.name == 'vadjustment':
#             setattr(
#                 MatrixView.vadjustment,
#                 '_property_helper_vadjustment',
#                 value
#             )
#             self._update_vadjustement()
#             self.vadjustment.connect('value-changed', self._on_vscroll)
#         else:
#             raise AttributeError(f'unknown property {prop.name}')

#     def _validate_data(self, data):
#         if not data is None:
#             try:
                # Testing for buffer protocols
#                 memoryview(data)
#             except:
#                 raise AttributeError("Data should implement the buffer protocol")
#             else:
#                 if data.ndim < 2:
#                     raise ValueError("Data should at least be 2 dimensional")
#         return data

#     def _update_canvas(self):
#         if self.data is None:
#             self._canvas_size = (100, 100)
#         else:
#             self._canvas_size = (
#                 self.data.shape[1] * self.zoom + self._margins[0] * 2,
#                 self.data.shape[0] * self.zoom + self._margins[1] * 2,
#             )
#             self._update_adjustement()

#     def _update_adjustement(self):
#         if not self.hadjustment:
#             return
#         self._update_hadjustement()
#         self._update_vadjustement()

#     def _update_hadjustement(self):
#         self.hadjustment.configure(
#             self.hadjustment.get_value(), 0, self._canvas_size[0], 1,
#             self.get_allocated_width() // 100,
#             self.get_allocated_width(),
#         )

#     def _update_vadjustement(self):
#         self.vadjustment.configure(
#             self.vadjustment.get_value(), 0, self._canvas_size[1], 1,
#             self.get_allocated_height() // 100,
#             self.get_allocated_height(),
#         )

#     def _on_hscroll(self, adjustment):
#         print("H scroll", adjustment.get_value())

#     def _on_vscroll(self, adjustment):
#         print("V scroll", adjustment.get_value())

#     def _on_draw_cb(self, widget, ctx):
#         w = self.get_allocated_width()
#         h = self.get_allocated_height()
#         origin = (
#             self.hadjustment.get_value(),
#             self.vadjustment.get_value(),
#         )
#         self._draw_background(ctx, w, h)
#         self._draw_matrix(ctx, w, h, origin)
#         return True

#     def _draw_background(self, ctx, w, h):
#         ctx.rectangle(0, 0, w, h)
#         ctx.set_source_rgb(.9, .9, .9)
#         ctx.fill()

#     def _draw_matrix(self, ctx, w, h, origin=(0, 0)):
#         ox, oy = origin
#         cw, ch = self._canvas_size
#         mw, mh = self._margins
#         dh, dw = self.data.shape
#         dox = doy = 0  # origin of visible part in data
#         dx = mw - ox
#         dy = mh - oy
#         scale = self.zoom

        # clip data
#         dw = (w // scale) + 2
#         dox = - int(dx // scale) - 1
#         dox = dox if dox > 0 else 0
#         dx = dx + dox * scale
#         dh = (h // scale) + 2
#         doy = - int(dy // scale) - 1
#         doy = doy if doy > 0 else 0
#         dy = dy + doy * scale

        # memory view creation for the cliped area
#         view = self.data[doy:doy+dh, dox:dox+dw]
#         dw = min(dw, view.shape[1])
#         dh = min(dh, view.shape[0])

        # Vector drawinng
#         if self.zoom >= 10:
#             ctx.set_antialias(cairo.ANTIALIAS_NONE)
#             for ih in range(dh):
#                 for iw in range(dw):
                    # Threshold FIlter
#                     if self.threshold_view:
#                         color =  1 if (view[ih][iw] >= self.thresh_level) else 0
#                     else :
#                         color = view[ih][iw] / np.iinfo(view.dtype).max
#                     ctx.rectangle(
#                         dx + iw * scale,
#                         dy + ih * scale,
#                         scale,
#                         scale
#                     )
#                     ctx.set_source_rgb(color, color, color)
#                     ctx.fill()
                    # Data number visualization
#                     if self.show_numbers and self.zoom>=20:
#                         ctx.set_font_size(6 * self.zoom / 20)
#                         color = .9 - color
#                         ctx.set_source_rgb(color , color , color)
#                         ctx.move_to(
#                             dx + iw * scale + scale // 4,
#                             dy + ih * scale + scale // 2
#                         )
#                         ctx.show_text(str(view[ih][iw]))
#                         ctx.stroke()

        # PixBuf Drawinng
#         else:
            #TODO: Add threshold filter
#             cs = GdkPixbuf.Colorspace.RGB
#             data = view.repeat(3)
#             data = (data / np.iinfo(view.dtype).max * 255).astype(np.uint8)
#             self._pixbuf = GdkPixbuf.Pixbuf.new_from_data(
#                 data,
#                 cs,
#                 False,
#                 8,
#                 dw,
#                 dh,
#                 dw * 3,
#                 None,
#                 None
#             )
#             ctx.set_antialias(cairo.ANTIALIAS_NONE)
#             ctx.scale(self.zoom, self.zoom)
#             Gdk.cairo_set_source_pixbuf(ctx, self._pixbuf, 0, 0)
#             ctx.paint()

        # Bounding Box
#         dh *= scale
#         dw *= scale
#         ctx.set_source_rgb(0.6, 0.6, 0.6)

#         ctx.move_to(0, dy)
#         ctx.line_to(w, dy)
#         ctx.move_to(0, dy + dh)
#         ctx.line_to(w, dy + dh)

#         ctx.move_to(dx, 0)
#         ctx.line_to(dx, h)
#         ctx.move_to(dx + dw, 0)
#         ctx.line_to(dx + dw, h)

#         ctx.stroke()

# END
