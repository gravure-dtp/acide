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


import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GObject, GdkPixbuf
import cairo
import numpy as np


__all__ = ['GtkMatrixView']


class GtkMatrixView(Gtk.DrawingArea, Gtk.Scrollable):
    """A scrollable Gtk widget for making graphical representation\
        of 2D matrix (in sense of raster object).

        Extends Gtk.DrawingArea and implements Gtk.Scrollable.
        """

    __gtype_name__ = 'GtkMatrixView'

    def __init__(self, data=None, *args, **kwargs):
        super().__init__(*args, **kwargs)


        self._margins =(100, 100)
        self.data = data
        self.zoom = 20

        self.show_numbers = False
        self.thresh_view = False
        self.thresh_level = 0
        self._pixbuf = None
        self.connect('draw', self._on_draw_cb)

    #
    # zoom property
    #
    def get_zoom(self):
        return self._zoom

    def set_zoom(self, value):
        if value is None:
            return
        self._zoom = value
        self._update_canvas()
        self.queue_draw()

    zoom = property(fget=get_zoom, fset=set_zoom)

    #
    # thresh_view property
    #
    def get_thresh_view(self):
        return self._thresh_view

    def set_thresh_view(self, value):
        self._thresh_view = bool(value)
        self.queue_draw()

    thresh_view = property(fget=get_thresh_view, fset=set_thresh_view)

    #
    # thresh_level property
    #
    def get_thresh_level(self):
        return self._thresh_level

    def set_thresh_level(self, value):
        self._thresh_level = value
        self.queue_draw()

    thresh_level = property(fget=get_thresh_level, fset=set_thresh_level)

    #
    # show_numbers property
    #
    def get_show_numbers(self):
        return self._show_numbers

    def set_show_numbers(self, value):
        self._show_numbers = bool(value)
        self.queue_draw()

    show_numbers = property(fget=get_show_numbers, fset=set_show_numbers)

    #
    # data property
    #
    def get_data(self):
        return self._data

    def set_data(self, value):
        if value is None:
            self._data = None
            return

        # Testing for buffer protocols
        try : memoryview(value)
        except :
            raise AttributeError("Data should implement the buffer protocol")
        else :
            if value.ndim < 2 :
                raise ValueError("Data should at least be 2 dimensional")
            self._data = value
            self._rangelevels = np.unique(value)
            self._levels = self._rangelevels.size
            self._update_canvas()
            self.queue_draw()

    data = property(fget=get_data, fset=set_data)


    def _update_canvas(self):
        if self.data is None:
            self._canvas_size = (100, 100)
        else :
            self._canvas_size = (self.data.shape[1] * self.zoom + self._margins[0] * 2, \
                                self.data.shape[0] * self.zoom + self._margins[1] * 2)
            self._update_adjustement()


    def _update_adjustement(self):
        if not self.hadjustment :
            return
        self._update_hadjustement()
        self._update_vadjustement()

    def _update_hadjustement(self):
        self.hadjustment.configure(self.hadjustment.get_value(), 0, self._canvas_size[0], 1, \
                                   self.get_allocated_width()//100, \
                                   self.get_allocated_width())

    def _update_vadjustement(self):
        self.vadjustment.configure(self.vadjustment.get_value(), 0, self._canvas_size[1], 1, \
                                   self.get_allocated_height()//100, \
                                   self.get_allocated_height())


    #
    # canvas_size property
    #
    def get_canvas_size(self):
        return self._canvas_size

    canvas_size = property(fget=get_canvas_size)


    #
    # h & v scroll_policy property
    #
    hscroll_policy = GObject.property(type=Gtk.ScrollablePolicy,
                                      default=Gtk.ScrollablePolicy.MINIMUM,
                                      flags=GObject.PARAM_READWRITE)
    vscroll_policy = GObject.property(type=Gtk.ScrollablePolicy,
                                      default=Gtk.ScrollablePolicy.MINIMUM,
                                      flags=GObject.PARAM_READWRITE)

    #
    # hadjustment property
    #
    def set_hadjustment(self, adj):
        setattr(GtkMatrixView.hadjustment, '_property_helper_hadjustment', adj)
        self._update_hadjustement()
        self.hadjustment.connect('value-changed', self._on_hscroll)


    def get_hadjustment(self):
        return getattr(GtkMatrixView.hadjustment, '_property_helper_hadjustment')

    hadjustment = GObject.property(type=Gtk.Adjustment,
                                   default=None,
                                   setter=set_hadjustment,
                                   getter=get_hadjustment,
                                   flags=GObject.PARAM_READWRITE)

    def _on_hscroll(self, adjustment):
        pass
        #print("H scroll", adjustment.get_value())

    #
    # vadjustment property
    #
    def set_vadjustment(self, adj):
        setattr(GtkMatrixView.vadjustment, '_property_helper_vadjustment', adj)
        self._update_vadjustement()
        self.vadjustment.connect('value-changed', self._on_vscroll)

    def get_vadjustment(self):
        return getattr(GtkMatrixView.vadjustment, '_property_helper_vadjustment')

    vadjustment = GObject.property(type=Gtk.Adjustment,
                                   default=None,
                                   setter=set_vadjustment,
                                   getter=get_vadjustment,
                                   flags=GObject.PARAM_READWRITE)

    def _on_vscroll(self, adjustment):
        pass
        #sprint("V scroll", adjustment.get_value())


    #
    # drawing methods
    #
    def _on_draw_cb(self, widget, ctx):
        w = self.get_allocated_width()
        h = self.get_allocated_height()

        origin = ( self.hadjustment.get_value(), \
                   self.vadjustment.get_value())
        self._draw_background(ctx, w, h)
        self._draw_matrix(ctx, w, h, origin)

        return True


    def _draw_background(self, ctx, w, h):
        ctx.rectangle(0, 0, w, h)
        ctx.set_source_rgb(.9, .9, .9)
        ctx.fill()


    def _draw_matrix(self, ctx, w, h, origin=(0, 0)):
        ox, oy = origin
        cw, ch = self._canvas_size
        mw, mh = self._margins
        dh, dw = self.data.shape
        dox = doy = 0 # origin of visible part in data
        dx = mw - ox
        dy = mh - oy
        scale = self.zoom

        # clip data
        dw = (w // scale) + 2
        dox = - int(dx // scale) - 1
        dox = dox if dox>0 else 0
        dx = dx + dox * scale
        dh = (h // scale) + 2
        doy = - int(dy // scale) - 1
        doy = doy if doy>0 else 0
        dy = dy + doy * scale

        # memory view creation for the cliped area
        view = self.data[doy:doy+dh, dox:dox+dw]
        dw = min(dw, view.shape[1])
        dh = min(dh, view.shape[0])


        # Vector drawinng
        if self.zoom >= 10:
            ctx.set_antialias(cairo.ANTIALIAS_NONE)
            for ih in range(dh):
                for iw in range(dw):
                    # Threshold FIlter
                    if self.thresh_view:
                        color =  1 if (view[ih][iw] >= self.thresh_level) else 0
                    else :
                        color = view[ih][iw] / np.iinfo(view.dtype).max
                    ctx.rectangle(dx + iw * scale, dy + ih * scale, scale, scale)
                    ctx.set_source_rgb(color, color, color)
                    ctx.fill()
                    # Data number visualization
                    if self.show_numbers and self.zoom>=20:
                        ctx.set_font_size(6 * self.zoom / 20)
                        color = .9 - color
                        ctx.set_source_rgb(color , color , color)
                        ctx.move_to(dx + iw * scale + scale // 4, \
                                    dy + ih * scale + scale // 2)
                        ctx.show_text(str(view[ih][iw]))
                        ctx.stroke()
        # PixBuf Drawinng
        else:
            #TODO: Add threshold filter
            cs = GdkPixbuf.Colorspace.RGB
            data = view.repeat(3)
            data = (data / np.iinfo(view.dtype).max * 255).astype(np.uint8)
            self._pixbuf = GdkPixbuf.Pixbuf.new_from_data(data, cs, \
                           False, 8, dw, dh, dw*3, None, None)
            ctx.set_antialias(cairo.ANTIALIAS_NONE)
            ctx.scale(self.zoom, self.zoom)
            Gdk.cairo_set_source_pixbuf(ctx, self._pixbuf, 0, 0)
            ctx.paint()

        # Bounding Box
        dh *= scale
        dw *= scale
        ctx.set_source_rgb(0.6, 0.6, 0.6)

        ctx.move_to(0, dy)
        ctx.line_to(w, dy)
        ctx.move_to(0, dy + dh)
        ctx.line_to(w, dy + dh)

        ctx.move_to(dx, 0)
        ctx.line_to(dx, h)
        ctx.move_to(dx + dw, 0)
        ctx.line_to(dx + dw, h)

        ctx.stroke()

